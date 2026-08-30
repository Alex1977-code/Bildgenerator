#!/usr/bin/env python3
"""Eigener Bild-Server fuer den 3DGenerator: Text -> Bild auf der eigenen GPU.

Stellt Stable Diffusion (ueber die Bibliothek "diffusers") als kleine
HTTP-API bereit, die die App als Bild-Anbieter "Eigene GPU" nutzt.
Damit laeuft die komplette Kette lokal: Text -> Ansichten -> 3D-Modell,
ohne Cloud, ohne Kosten, alle Daten bleiben auf dem Rechner.

Start (im Ordner der Installation, siehe README.md):

    python local_image_server.py --model sdxl-turbo --port 8766

Endpunkte:
    GET  /health    -> {"status": "ok", "model": ..., "device": ...,
                        "models": [...], "missing": [...]}
    POST /generate  -> {"images": ["<Base64-PNG>", ...], "seed": 123}
                       Body: {"prompt": "...", "count": 1, ...}

Die Modellgewichte laedt Hugging Face beim ersten Lauf automatisch in
den Cache (~/.cache/huggingface). Fuer Modelle mit Lizenzabfrage
(SD 3.5, FLUX) einmalig die Lizenz auf der Modellseite bestaetigen und
"huggingface-cli login" ausfuehren.
"""

import argparse
import base64
import io
import os
import random

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="3DGenerator - Eigener Bild-Server")

# CORS erlauben, damit auch die Web-Version der App (Browser) den
# lokalen Server ansprechen darf.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# Auswaehlbare Modelle: Kennung -> (Hugging-Face-Repo, Familie,
# Vorgabe-Schritte, Vorgabe-Guidance, Kantenlaenge, VRAM in GB).
# Die App zeigt dieselben Kennungen in ihrer Modell-Liste.
MODELS = {
    "sd15": ("stable-diffusion-v1-5/stable-diffusion-v1-5", "sd",
             25, 7.5, 512, 4),
    "sdxl-turbo": ("stabilityai/sdxl-turbo", "sdxl", 4, 0.0, 512, 7),
    "sdxl": ("stabilityai/stable-diffusion-xl-base-1.0", "sdxl",
             30, 7.0, 1024, 8),
    "sd35-medium": ("stabilityai/stable-diffusion-3.5-medium", "sd3",
                    28, 4.5, 1024, 10),
    "flux-schnell": ("black-forest-labs/FLUX.1-schnell", "flux",
                     4, 0.0, 1024, 16),
}

MODEL = "sdxl-turbo"
_pipe = None
_pipe_name = None
_device = None
_remover = None


class GenerateRequest(BaseModel):
    prompt: str
    negative_prompt: str = ""

    # Modell-Kennung aus MODELS; leer = das beim Start gewaehlte.
    model: str = ""

    # Seitenverhaeltnis wie in der App ("1:1", "16:9", "3:2" ...).
    aspect: str = "1:1"

    # Feinsteuerung; None = Vorgabe des Modells.
    steps: int | None = None
    guidance: float | None = None
    seed: int | None = None
    count: int = 1

    # Hintergrund freistellen (rembg) - so entstehen die transparenten
    # Ansichten, die der 3D-Teil der App braucht.
    transparent: bool = False


def _aspect_size(aspect: str, base: int) -> tuple[int, int]:
    """Rechnet ein Seitenverhaeltnis in Pixelmasse um.

    Die Kantenlaengen werden auf Vielfache von 64 gerundet - Stable
    Diffusion arbeitet sonst nicht sauber - und die Flaeche bleibt
    ungefaehr so gross wie beim quadratischen Bild.
    """
    ratios = {
        "1:1": (1, 1),
        "16:9": (16, 9),
        "9:16": (9, 16),
        "4:3": (4, 3),
        "3:4": (3, 4),
        "3:2": (3, 2),
        "2:3": (2, 3),
        "21:9": (21, 9),
        "5:4": (5, 4),
        "4:5": (4, 5),
    }
    w, h = ratios.get(aspect, (1, 1))
    scale = (base * base / (w * h)) ** 0.5
    width = max(256, int(round(w * scale / 64)) * 64)
    height = max(256, int(round(h * scale / 64)) * 64)
    return width, height


def _missing_modules() -> list[str]:
    import importlib.util as util

    needed = ["torch", "diffusers", "transformers", "PIL", "safetensors"]
    return [name for name in needed if util.find_spec(name) is None]


def _load(name: str):
    """Laedt das gewuenschte Modell (einmalig) und liefert die Pipeline."""
    global _pipe, _pipe_name, _device
    if _pipe is not None and _pipe_name == name:
        return _pipe
    if name not in MODELS:
        raise HTTPException(
            status_code=400,
            detail=f"Unbekanntes Modell '{name}'. Moeglich: "
            + ", ".join(sorted(MODELS)),
        )
    missing = _missing_modules()
    if missing:
        raise HTTPException(
            status_code=500,
            detail="Es fehlen Pakete: " + ", ".join(missing)
            + ". Bitte die Installation abschliessen "
            "(pip install -r requirements-image.txt).",
        )

    import torch

    repo, family, _, _, _, vram = MODELS[name]
    _device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if _device == "cuda" else torch.float32

    if family == "sdxl":
        from diffusers import StableDiffusionXLPipeline as Pipe
    elif family == "sd3":
        from diffusers import StableDiffusion3Pipeline as Pipe
    elif family == "flux":
        from diffusers import FluxPipeline as Pipe
    else:
        from diffusers import StableDiffusionPipeline as Pipe

    print(f"Modell wird geladen: {repo} ({_device}) ...", flush=True)
    pipe = Pipe.from_pretrained(repo, torch_dtype=dtype)

    if _device == "cuda":
        free_gb = torch.cuda.get_device_properties(0).total_memory / 2**30
        # Passt das Modell nicht bequem in den Speicher, wandern die
        # Teile zwischen GPU und Hauptspeicher - langsamer, laeuft aber.
        if free_gb + 0.5 < vram:
            print(
                f"Nur {free_gb:.1f} GB VRAM fuer ein Modell mit ~{vram} GB "
                "Bedarf - Teile werden ausgelagert (langsamer).",
                flush=True,
            )
            pipe.enable_model_cpu_offload()
        else:
            pipe = pipe.to(_device)
        pipe.enable_attention_slicing()
        if hasattr(pipe, "enable_vae_slicing"):
            pipe.enable_vae_slicing()
    else:
        pipe = pipe.to(_device)

    # Der Sicherheitsfilter wirft bei harmlosen Motiven regelmaessig
    # schwarze Bilder aus; er laeuft lokal und ohne Netz, deshalb hier aus.
    if hasattr(pipe, "safety_checker"):
        pipe.safety_checker = None

    _pipe = pipe
    _pipe_name = name
    return _pipe


def _cutout(image):
    """Hintergrund entfernen - fuer die Ansichten des 3D-Teils."""
    global _remover
    try:
        from rembg import new_session, remove
    except Exception as exc:  # pragma: no cover - haengt an der Umgebung
        raise HTTPException(
            status_code=500,
            detail="Fuer transparente Bilder wird rembg gebraucht: "
            f"pip install rembg onnxruntime ({exc})",
        )
    if _remover is None:
        _remover = new_session("u2net")
    return remove(image, session=_remover)


@app.get("/health")
def health():
    missing = _missing_modules()
    device = "unbekannt"
    gpu = ""
    if "torch" not in missing:
        import torch

        device = "cuda" if torch.cuda.is_available() else "cpu"
        if device == "cuda":
            gpu = torch.cuda.get_device_name(0)
    return {
        "status": "ok" if not missing else "unvollstaendig",
        "kind": "image",
        "model": MODEL,
        "models": sorted(MODELS),
        "device": device,
        "gpu": gpu,
        "missing": missing,
        "loaded": _pipe_name or "",
    }


@app.post("/generate")
def generate(req: GenerateRequest):
    name = req.model.strip() or MODEL
    pipe = _load(name)
    _, _, def_steps, def_guidance, base, _ = MODELS[name]
    width, height = _aspect_size(req.aspect, base)
    steps = req.steps if req.steps and req.steps > 0 else def_steps
    guidance = req.guidance if req.guidance is not None else def_guidance
    count = max(1, min(4, req.count))
    seed = req.seed if req.seed and req.seed > 0 else random.randint(1, 2**31 - 1)

    import torch

    generator = torch.Generator(
        device="cpu" if _device != "cuda" else "cuda"
    ).manual_seed(seed)

    kwargs = dict(
        prompt=req.prompt,
        width=width,
        height=height,
        num_inference_steps=int(steps),
        guidance_scale=float(guidance),
        num_images_per_prompt=count,
        generator=generator,
    )
    # FLUX und SDXL-Turbo kennen keinen Negativ-Prompt.
    family = MODELS[name][1]
    if req.negative_prompt and family not in ("flux",) and guidance > 0:
        kwargs["negative_prompt"] = req.negative_prompt

    try:
        result = pipe(**kwargs)
    except torch.cuda.OutOfMemoryError:
        raise HTTPException(
            status_code=500,
            detail="Der GPU-Speicher reicht nicht. Kleineres Modell "
            "waehlen (sd15 oder sdxl-turbo), weniger Bilder auf einmal "
            "oder ein kleineres Seitenverhaeltnis.",
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Generierung fehlgeschlagen: {exc}")

    images = []
    for image in result.images:
        if req.transparent:
            image = _cutout(image)
        buffer = io.BytesIO()
        image.convert("RGBA" if req.transparent else "RGB").save(
            buffer, format="PNG"
        )
        images.append(base64.b64encode(buffer.getvalue()).decode("ascii"))

    return {
        "images": images,
        "seed": seed,
        "model": name,
        "width": width,
        "height": height,
        "steps": int(steps),
    }


def main():
    global MODEL
    parser = argparse.ArgumentParser(
        description="Text->Bild auf der eigenen GPU fuer den 3DGenerator"
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("IMAGE_MODEL", "sdxl-turbo"),
        choices=sorted(MODELS),
        help="Modell, das beim Start vorgewaehlt ist",
    )
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument(
        "--preload",
        action="store_true",
        help="Modell sofort laden statt beim ersten Bild",
    )
    args = parser.parse_args()

    MODEL = args.model
    missing = _missing_modules()
    if missing:
        print("Es fehlen noch Pakete: " + ", ".join(missing))
        print("  pip install -r requirements-image.txt")
    else:
        print(f"Modell: {MODEL}")
    if args.preload and not missing:
        _load(MODEL)
    print(
        f"In der App als Bild-Server eintragen: http://127.0.0.1:{args.port}"
    )

    import uvicorn

    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
