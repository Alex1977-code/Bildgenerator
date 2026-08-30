#!/usr/bin/env python3
"""Eigener 3D-Server fuer den 3DGenerator.

Stellt MIT-lizenzierte Open-Source-Modelle (TripoSR, TRELLIS) ueber
eine kleine HTTP-API bereit, die die App als Provider "Server" nutzt:
die App schickt die Vorderansicht als Base64-Bild, der Server
antwortet direkt mit der fertigen GLB-Datei.

Start (aus dem Ordner des geklonten Modell-Repos, siehe README.md):

    python local3d_server.py --backend triposr --port 8765
    python local3d_server.py --backend trellis --port 8765

Endpunkte:
    GET  /health    -> {"status": "ok", "backend": ..., "device": ...}
    POST /generate  -> GLB-Bytes (model/gltf-binary)
                       Body: {"image": "<Base64>", "mime_type": "image/png"}
"""

import argparse
import base64
import io
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


def _decode_image(req: GenerateRequest):
    from PIL import Image

    data = req.image
    if data.startswith("data:"):
        data = data.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(data)))


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


def _run_triposr(img):
    import torch

    model = _load_triposr()
    image = _prepare_foreground(img)
    with torch.no_grad():
        scene_codes = model([image], device=_device)
    # True = Vertex-Farben direkt aus dem Modell (kein Textur-Baking).
    meshes = model.extract_mesh(scene_codes, True, resolution=256)
    buf = io.BytesIO()
    meshes[0].export(buf, file_type="glb")
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


def _run_trellis(img):
    from trellis.utils import postprocessing_utils

    pipeline = _load_trellis()
    outputs = pipeline.run(img.convert("RGBA"))
    glb = postprocessing_utils.to_glb(
        outputs["gaussian"][0],
        outputs["mesh"][0],
        simplify=0.95,
        texture_size=1024,
    )
    buf = io.BytesIO()
    glb.export(buf, file_type="glb")
    return buf.getvalue()


# --------------------------------------------------------------------- API


def _missing_modules():
    """Pakete, die zum Generieren gebraucht werden, aber fehlen."""
    import importlib.util

    needed = ["PIL", "torch", "numpy"]
    if BACKEND == "trellis":
        needed += ["trellis"]
    else:
        needed += ["tsr", "torchmcubes", "transformers", "trimesh"]
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
        "backend": BACKEND,
        "device": device
        + (f" - ES FEHLEN: {', '.join(missing)}" if missing else ""),
        "missing": missing,
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
        img = _decode_image(req)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(400, f"Bild konnte nicht gelesen werden: {e}")
    t0 = time.time()
    try:
        glb = _run_trellis(img) if BACKEND == "trellis" else _run_triposr(img)
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
        "--backend", choices=["triposr", "trellis"], default="triposr"
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
