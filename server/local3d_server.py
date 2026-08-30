#!/usr/bin/env python3
"""Eigener 3D-Server fuer den 3DGenerator.

Stellt MIT-lizenzierte Open-Source-Modelle (TripoSR, TRELLIS) ueber
eine kleine HTTP-API bereit, die die App als Provider "Server" nutzt:
die App schickt die Vorderansicht als Base64-Bild, der Server
antwortet direkt mit der fertigen GLB-Datei.

Start (aus dem Ordner des geklonten Modell-Repos, siehe README.md):

    python local3d_server.py --backend triposr --port 8765
    python local3d_server.py --backend sf3d --port 8765
    python local3d_server.py --backend spar3d --port 8765
    python local3d_server.py --backend trellis --port 8765

Endpunkte:
    GET  /health    -> {"status": "ok", "backend": ..., "device": ...}
    POST /generate  -> GLB-Bytes (model/gltf-binary)
                       Body: {"image": "<Base64>", "mime_type": "image/png"}
"""

import argparse
import base64
import io
import os
import time

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel

app = FastAPI(title="3DGenerator - Eigener 3D-Server")

# CORS erlauben, damit auch die Web-Version der App (Browser) den
# lokalen Server ansprechen darf.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

BACKEND = "triposr"
_model = None
_device = None


class GenerateRequest(BaseModel):
    image: str  # Base64 (mit oder ohne "data:...;base64,"-Praefix)
    mime_type: str = "image/png"

    # Weitere Ansichten desselben Objekts (nur bei Backends mit
    # "multiview", sonst ignoriert).
    images: list[str] | None = None

    # Optionale Qualitaets-Einstellungen; None = Vorgabe des Backends.
    texture_resolution: int | None = None
    remesh: str | None = None
    target_count: int | None = None
    resolution: int | None = None
    bake_texture: bool | None = None
    foreground_ratio: float | None = None


def _decode_one(data: str):
    from PIL import Image

    if data.startswith("data:"):
        data = data.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(data)))


def _decode_image(req: GenerateRequest):
    return _decode_one(req.image)


def _decode_images(req: GenerateRequest):
    """Vorderansicht plus optionale weitere Ansichten."""
    images = [_decode_one(req.image)]
    for extra in req.images or []:
        images.append(_decode_one(extra))
    return images


# Was das jeweilige Backend kann - die App blendet danach ihre
# Bedienelemente ein.
CAPABILITIES = {
    "triposr": ["resolution", "bake_texture", "foreground_ratio"],
    "sf3d": ["texture_resolution", "remesh", "target_count",
             "foreground_ratio"],
    "spar3d": ["texture_resolution", "remesh", "foreground_ratio"],
    "trellis": ["multiview", "texture_resolution", "target_count"],
}


def _torch_device():
    import torch

    return "cuda" if torch.cuda.is_available() else "cpu"


# ---------------------------------------------------------------- TripoSR


def _load_triposr():
    global _model, _device
    if _model is None:
        from tsr.system import TSR

        _device = _torch_device()
        print(f"[triposr] Lade Modell (stabilityai/TripoSR) auf {_device} ...")
        _model = TSR.from_pretrained(
            "stabilityai/TripoSR",
            config_name="config.yaml",
            weight_name="model.ckpt",
        )
        _model.renderer.set_chunk_size(8192)
        _model.to(_device)
    return _model


def _prepare_foreground(img):
    """Hintergrund entfernen und zuschneiden wie im TripoSR-Beispiel.

    Bilder aus der App kommen bereits freigestellt (Alpha-Kanal) -
    dann wird der Alpha-Kanal direkt genutzt und rembg uebersprungen.
    """
    import numpy as np
    from PIL import Image
    from tsr.utils import remove_background, resize_foreground

    has_alpha = img.mode == "RGBA" and img.getextrema()[3][0] < 255
    if has_alpha:
        image = img
    else:
        import rembg

        image = remove_background(img.convert("RGB"), rembg.new_session())
    image = resize_foreground(image, 0.85)
    arr = np.array(image).astype(np.float32) / 255.0
    arr = arr[:, :, :3] * arr[:, :, 3:4] + (1 - arr[:, :, 3:4]) * 0.5
    return Image.fromarray((arr * 255.0).astype(np.uint8))


def _shim_active():
    """True, wenn statt torchmcubes der CPU-Ersatz geladen ist."""
    try:
        import torchmcubes

        return bool(getattr(torchmcubes, "SHIM", False))
    except Exception:  # noqa: BLE001
        return False


def _fix_shim_axes(mesh):
    """Dreht das Netz gerade, wenn der CPU-Ersatz benutzt wurde.

    scikit-image gibt die Ecken in anderer Achsen-Reihenfolge zurueck
    als torchmcubes; die Figur stuende sonst entlang z statt y (an
    einem erzeugten Modell nachgemessen: blauer Hut bei z-max, Stiefel
    bei z-min, Gesicht bei x-max, Spiegelachse y).

    Die Zuordnung laesst sich mit TRIPOSR_AXES ueberschreiben, z. B.
    "yzx" (Vorgabe) oder "y z -x", falls das Modell spiegelverkehrt
    herauskommt.
    """
    import numpy as np

    order = os.environ.get("TRIPOSR_AXES", "yzx").replace(" ", "").lower()
    index = {"x": 0, "y": 1, "z": 2}
    vertices = np.asarray(mesh.vertices, dtype=np.float64)
    columns = []
    rest = order
    while rest:
        sign = 1.0
        if rest[0] in "+-":
            sign = -1.0 if rest[0] == "-" else 1.0
            rest = rest[1:]
        columns.append(sign * vertices[:, index[rest[0]]])
        rest = rest[1:]
    if len(columns) != 3:
        print(f"[triposr] TRIPOSR_AXES='{order}' ist ungueltig - "
              "es wird nicht gedreht.")
        return mesh
    mesh.vertices = np.stack(columns, axis=1)
    return mesh


def _apply_baked_texture(mesh, baked):
    """Haengt die gebackene UV-Textur ans Netz (trimesh-Material)."""
    import numpy as np
    import trimesh
    from PIL import Image

    mesh.visual = trimesh.visual.TextureVisuals(
        uv=baked["uvs"],
        material=trimesh.visual.material.PBRMaterial(
            baseColorTexture=Image.fromarray(
                np.array(baked["colors"], dtype=np.uint8)
            ).transpose(Image.FLIP_TOP_BOTTOM),
            metallicFactor=0.0,
            roughnessFactor=1.0,
        ),
    )


def _run_triposr(img, req=None):
    import torch

    model = _load_triposr()
    image = _prepare_foreground(img)
    with torch.no_grad():
        scene_codes = model([image], device=_device)
    # Aufloesung des Schnitz-Rasters: hoeher = feinere Geometrie,
    # mehr Speicher und Rechenzeit (256 ist die Vorgabe von TripoSR).
    resolution = (req.resolution if req and req.resolution else None) or int(
        os.environ.get("TRIPOSR_RESOLUTION", "256"))
    # Textur-Baking (xatlas + moderngl) statt Vertex-Farben: Die
    # Farbschaerfe haengt dann nicht mehr an der Netzdichte - der
    # groesste Qualitaetsgewinn bei TripoSR. Braucht die Pakete xatlas
    # und moderngl.
    bake = (req.bake_texture if req and req.bake_texture is not None
            else os.environ.get("TRIPOSR_BAKE_TEXTURE", "0")
            not in ("0", ""))
    meshes = model.extract_mesh(scene_codes, not bake, resolution=resolution)
    mesh = meshes[0]
    if _shim_active():
        mesh = _fix_shim_axes(mesh)
    if bake:
        try:
            from tsr.bake_texture import bake_texture as _bake

            size = (req.texture_resolution
                    if req and req.texture_resolution else None) or int(
                        os.environ.get("TRIPOSR_TEXTURE_SIZE", "2048"))
            baked = _bake(mesh, model, scene_codes[0], size)
            _apply_baked_texture(mesh, baked)
        except ImportError as e:
            print(f"[triposr] Textur-Baking uebersprungen ({e}) - "
                  "'pip install xatlas moderngl' nachholen.")
        except Exception as e:  # noqa: BLE001
            print(f"[triposr] Textur-Baking fehlgeschlagen: {e}")
    buf = io.BytesIO()
    mesh.export(buf, file_type="glb")
    return buf.getvalue()


# ------------------------------------------------- SF3D / SPAR3D (Stability)


def _load_stability(repo, weight):
    """Laedt SF3D bzw. SPAR3D. Beide Modelle sind auf Hugging Face
    zugriffsbeschraenkt: Lizenz auf der Modellseite bestaetigen und
    'huggingface-cli login' ausfuehren (oder HF_TOKEN setzen)."""
    global _model, _device
    if _model is None:
        if BACKEND == "spar3d":
            from spar3d.system import SPAR3D as Model
        else:
            from sf3d.system import SF3D as Model

        _device = _torch_device()
        print(f"[{BACKEND}] Lade Modell ({repo}) auf {_device} ...")
        try:
            _model = Model.from_pretrained(
                repo, config_name="config.yaml", weight_name=weight
            )
        except Exception as e:  # noqa: BLE001
            raise HTTPException(
                500,
                f"Modell '{repo}' konnte nicht geladen werden: {e}\n"
                "Meist fehlt die Freigabe: Auf huggingface.co die "
                f"Modellseite '{repo}' oeffnen, die Lizenz bestaetigen "
                "und in der aktiven Umgebung 'huggingface-cli login' "
                "ausfuehren.",
            )
        _model.to(_device)
        _model.eval()
    return _model


def _run_stability(img, req=None):
    """Bild -> Mesh mit UV-Textur (deutlich schaerfer als Vertex-Farben)."""
    import torch
    from PIL import Image

    if BACKEND == "spar3d":
        model = _load_stability("stabilityai/spar3d", "model.safetensors")
    else:
        model = _load_stability(
            "stabilityai/stable-fast-3d", "model.safetensors")

    # Beide Modelle erwarten ein freigestelltes RGBA-Bild.
    image = img.convert("RGBA") if img.mode != "RGBA" else img
    if image.getextrema()[3][0] >= 255:
        try:
            import rembg
            from sf3d.utils import remove_background

            image = remove_background(image, rembg.new_session())
        except Exception:  # noqa: BLE001
            raise HTTPException(
                400,
                "Das Bild hat keinen Transparenz-Kanal und der "
                "Hintergrund konnte nicht entfernt werden. Bitte ein "
                "freigestelltes PNG verwenden.",
            )
    ratio = (req.foreground_ratio if req and req.foreground_ratio
             else None) or float(
                 os.environ.get("SF3D_FOREGROUND_RATIO", "0.85"))
    try:
        from sf3d.utils import resize_foreground

        image = resize_foreground(image, ratio)
    except Exception:  # noqa: BLE001
        pass

    texture = (req.texture_resolution
               if req and req.texture_resolution else None) or int(
                   os.environ.get("SF3D_TEXTURE_RESOLUTION", "1024"))
    remesh = (req.remesh if req and req.remesh else None) or os.environ.get(
        "SF3D_REMESH", "none")
    target = (req.target_count if req and req.target_count else None) or int(
        os.environ.get("SF3D_TARGET_COUNT", "0"))
    with torch.no_grad():
        mesh, _ = model.run_image(
            image,
            bake_resolution=texture,
            remesh=remesh,
            vertex_count=target if target > 0 else -1,
        )
    if isinstance(mesh, list):
        mesh = mesh[0]
    buf = io.BytesIO()
    mesh.export(buf, file_type="glb")
    return buf.getvalue()


# ---------------------------------------------------------------- TRELLIS


def _load_trellis():
    global _model
    if _model is None:
        from trellis.pipelines import TrellisImageTo3DPipeline

        print("[trellis] Lade Modell (microsoft/TRELLIS-image-large) ...")
        _model = TrellisImageTo3DPipeline.from_pretrained(
            "microsoft/TRELLIS-image-large"
        )
        _model.cuda()
    return _model


def _run_trellis(images, req=None):
    from trellis.utils import postprocessing_utils

    pipeline = _load_trellis()
    views = [i.convert("RGBA") for i in images]
    if len(views) > 1 and hasattr(pipeline, "run_multi_image"):
        # Mehrere Ansichten desselben Objekts - deutlich genauere
        # Rueckseite als aus einem Einzelbild.
        print(f"[trellis] {len(views)} Ansichten werden genutzt.")
        outputs = pipeline.run_multi_image(views)
    else:
        outputs = pipeline.run(views[0])
    texture = (req.texture_resolution
               if req and req.texture_resolution else None) or 1024
    glb = postprocessing_utils.to_glb(
        outputs["gaussian"][0],
        outputs["mesh"][0],
        simplify=0.95,
        texture_size=texture,
    )
    buf = io.BytesIO()
    glb.export(buf, file_type="glb")
    return buf.getvalue()


# --------------------------------------------------------------------- API


def _missing_modules():
    """Pakete, die zum Generieren gebraucht werden, aber fehlen."""
    import importlib.util

    needed = ["PIL", "torch", "numpy", "trimesh"]
    if BACKEND == "trellis":
        needed += ["trellis"]
    elif BACKEND == "sf3d":
        needed += ["sf3d"]
    elif BACKEND == "spar3d":
        needed += ["spar3d"]
    else:
        needed += ["tsr", "torchmcubes", "transformers"]
    return [m for m in needed if importlib.util.find_spec(m) is None]


@app.get("/health")
def health():
    try:
        import torch

        if torch.cuda.is_available():
            device = f"cuda ({torch.cuda.get_device_name(0)})"
        else:
            device = "cpu (langsam - CUDA-Torch installieren!)"
    except Exception as e:  # noqa: BLE001 - Diagnose-Endpunkt
        device = f"unbekannt (torch fehlt? {e})"
    missing = _missing_modules()
    return {
        "status": "ok" if not missing else "unvollstaendig",
        "kind": "3d",
        "backend": BACKEND,
        "device": device
        + (f" - ES FEHLEN: {', '.join(missing)}" if missing else ""),
        "missing": missing,
        "capabilities": CAPABILITIES.get(BACKEND, []),
    }


@app.post("/generate")
def generate(req: GenerateRequest):
    missing = _missing_modules()
    if missing:
        raise HTTPException(
            500,
            "Die Installation ist unvollstaendig - es fehlen: "
            f"{', '.join(missing)}. Im Ordner des Modell-Repos in der "
            "aktiven Umgebung 'pip install -r requirements.txt' "
            "ausfuehren und auf Fehlermeldungen achten (siehe "
            "server/README.md).",
        )
    try:
        images = _decode_images(req)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(400, f"Bild konnte nicht gelesen werden: {e}")
    t0 = time.time()
    try:
        if BACKEND == "trellis":
            glb = _run_trellis(images, req)
        elif BACKEND in ("sf3d", "spar3d"):
            glb = _run_stability(images[0], req)
        else:
            glb = _run_triposr(images[0], req)
    except ImportError as e:
        raise HTTPException(
            500,
            f"Backend '{BACKEND}' ist nicht installiert: {e}. "
            "Bitte die Installation laut server/README.md abschliessen "
            "und den Server aus dem Ordner des Modell-Repos starten.",
        )
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(500, f"Generierung fehlgeschlagen: {e}")
    print(
        f"[{BACKEND}] GLB in {time.time() - t0:.1f} s erzeugt "
        f"({len(glb)} Bytes)"
    )
    return Response(content=glb, media_type="model/gltf-binary")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--backend",
        choices=["triposr", "sf3d", "spar3d", "trellis"],
        default="triposr"
    )
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    BACKEND = args.backend

    import uvicorn

    fehlend = _missing_modules()
    if fehlend:
        print("\n!!! ACHTUNG: Die Installation ist unvollstaendig. "
              f"Es fehlen: {', '.join(fehlend)}")
        print("!!! Bitte in der aktiven Umgebung im Ordner des "
              "Modell-Repos ausfuehren:")
        print("!!!   pip install -r requirements.txt")
        print("!!! Der Server startet trotzdem, das Generieren wird "
              "aber fehlschlagen.\n")
    print(f"Backend: {BACKEND} - in der App als Server-Adresse eintragen: "
          f"http://127.0.0.1:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port)
