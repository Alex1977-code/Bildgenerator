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
import threading
import traceback

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
#
# Zur Familie gehoert, wie der Text verarbeitet wird:
#   sd/sdxl  CLIP, hart begrenzt auf 77 Tokens (~60 Woerter). Laengere
#            Prompts schneidet diffusers stillschweigend ab - deshalb
#            zerlegt dieser Server sie selbst in Bloecke und haengt die
#            Text-Vektoren aneinander (_embed_long, siehe unten).
#   sd3      CLIP + T5, bis 256 Tokens.
#   flux     T5, bis 512 Tokens.
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

# FastAPI fuehrt gewoehnliche (nicht-async) Endpunkte in einem
# Threadpool aus. Pipeline und Scheduler sind aber ein einziges,
# gemeinsam genutztes Objekt mit internem Schrittzaehler - laufen zwei
# Anfragen gleichzeitig hinein, zaehlt der Scheduler ueber das Ende
# hinaus ("index 31 is out of bounds for dimension 0 with size 31" bei
# 30 Schritten). Deshalb darf immer nur eine Anfrage rechnen.
_pipe_lock = threading.Lock()

# Eigene Sperre fuers Laden, damit nicht zwei Anfragen dasselbe Modell
# gleichzeitig in den Speicher holen.
_load_lock = threading.Lock()


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
    # Zwei gleichzeitige Anfragen duerfen nicht beide laden - das
    # kostet doppelt Speicher und kann die GPU sprengen.
    with _load_lock:
        if _pipe is not None and _pipe_name == name:
            return _pipe
        return _load_locked(name)


def _load_locked(name: str):
    global _pipe, _pipe_name, _device
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


# Wie viele Tokens die Textmodelle am Stueck verstehen. Bei CLIP sind
# es 77 einschliesslich Start- und Endmarke, also 75 echte Tokens.
_CLIP_CHUNK = 75


def _chunk_ids(tokenizer, text: str) -> list[list[int]]:
    """Zerlegt einen Text in CLIP-Bloecke zu je 75 Tokens.

    Jeder Block bekommt Start- und Endmarke und wird auf volle Laenge
    aufgefuellt, damit alle Bloecke dieselbe Form haben.
    """
    ids = tokenizer(text, truncation=False,
                    add_special_tokens=False).input_ids
    blocks = [ids[i:i + _CLIP_CHUNK]
              for i in range(0, len(ids), _CLIP_CHUNK)] or [[]]
    bos = tokenizer.bos_token_id
    eos = tokenizer.eos_token_id
    pad = tokenizer.pad_token_id
    if pad is None:
        pad = eos
    out = []
    for block in blocks:
        full = [bos] + block + [eos]
        full += [pad] * (_CLIP_CHUNK + 2 - len(full))
        out.append(full)
    return out


def _embed_clip(pipe, text: str, device, blocks: int):
    """Text-Vektoren fuer Stable Diffusion 1.5 (ein CLIP-Encoder)."""
    import torch

    chunks = _chunk_ids(pipe.tokenizer, text)
    while len(chunks) < blocks:
        chunks.append(_chunk_ids(pipe.tokenizer, "")[0])
    parts = []
    for chunk in chunks[:blocks]:
        ids = torch.tensor([chunk], device=device)
        parts.append(pipe.text_encoder(ids)[0])
    return torch.cat(parts, dim=1)


def _embed_sdxl(pipe, text: str, device, blocks: int):
    """Text-Vektoren fuer SDXL (zwei CLIP-Encoder plus Pooling)."""
    import torch

    tokenizers = [pipe.tokenizer, pipe.tokenizer_2]
    encoders = [pipe.text_encoder, pipe.text_encoder_2]
    chunk_sets = [_chunk_ids(tok, text) for tok in tokenizers]
    for tok, chunks in zip(tokenizers, chunk_sets):
        while len(chunks) < blocks:
            chunks.append(_chunk_ids(tok, "")[0])

    pooled = None
    parts = []
    for index in range(blocks):
        halves = []
        for position, (encoder, chunks) in enumerate(
                zip(encoders, chunk_sets)):
            ids = torch.tensor([chunks[index]], device=device)
            out = encoder(ids, output_hidden_states=True)
            # SDXL nutzt die vorletzte Schicht beider Encoder; der
            # Pooling-Vektor kommt aus dem zweiten und nur aus dem
            # ersten Block (er beschreibt den Gesamteindruck).
            if position == 1 and pooled is None:
                pooled = out[0]
            halves.append(out.hidden_states[-2])
        parts.append(torch.cat(halves, dim=-1))
    return torch.cat(parts, dim=1), pooled


# Obergrenze fuer die Zahl der Bloecke. Mehr als das braucht kein
# sinnvoller Prompt, und ein versehentlich riesiger Text soll den
# Speicher nicht sprengen.
_MAX_BLOCKS = 5


def _block_count(pipe, family: str, texts: list[str]) -> int:
    """Wie viele 75-Token-Bloecke der laengste Text braucht.

    SDXL hat zwei Tokenizer, die denselben Text unterschiedlich lang
    zerlegen. Es zaehlt der laengere - sonst bekommt der zweite Encoder
    stillschweigend nur den Anfang des Prompts zu sehen.
    """
    tokenizers = [pipe.tokenizer]
    if family == "sdxl" and getattr(pipe, "tokenizer_2", None) is not None:
        tokenizers.append(pipe.tokenizer_2)
    longest = 1
    for tokenizer in tokenizers:
        for text in texts:
            ids = tokenizer(text, truncation=False,
                            add_special_tokens=False).input_ids
            longest = max(longest, -(-len(ids) // _CLIP_CHUNK) or 1)
    return longest


def _long_prompt_kwargs(pipe, family: str, prompt: str, negative: str):
    """Baut die Text-Vektoren fuer lange Prompts.

    Liefert (kwargs, Anmerkung). kwargs ist None, wenn der Prompt
    ohnehin in 77 Tokens passt oder die Familie (SD 3.5, FLUX) von Haus
    aus lange Texte versteht - dann bekommt die Pipeline wie bisher
    einfach den Text. Die Anmerkung ist leer, solange nichts wegfiel.
    """
    if family not in ("sd", "sdxl"):
        return None, ""
    needed = _block_count(pipe, family, [prompt, negative])
    if needed <= 1:
        return None, ""
    blocks = min(needed, _MAX_BLOCKS)
    note = ""
    if needed > _MAX_BLOCKS:
        note = (
            f"Der Prompt braucht {needed} Textbloecke, verarbeitet "
            f"werden hoechstens {_MAX_BLOCKS} (rund "
            f"{_MAX_BLOCKS * _CLIP_CHUNK} Tokens) - der Rest fiel weg. "
            "Kuerzer formulieren bringt hier mehr."
        )
        print(note, flush=True)
    device = pipe._execution_device
    if family == "sdxl":
        embeds, pooled = _embed_sdxl(pipe, prompt, device, blocks)
        negative_embeds, negative_pooled = _embed_sdxl(
            pipe, negative, device, blocks)
        return {
            "prompt_embeds": embeds,
            "pooled_prompt_embeds": pooled,
            "negative_prompt_embeds": negative_embeds,
            "negative_pooled_prompt_embeds": negative_pooled,
        }, note
    return {
        "prompt_embeds": _embed_clip(pipe, prompt, device, blocks),
        "negative_prompt_embeds": _embed_clip(pipe, negative, device,
                                              blocks),
    }, note


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
        # Was die App ueber die Modelle wissen will: Schritte, Guidance
        # (0 = kein Negativ-Prompt moeglich) und ob lange Prompts
        # ungekuerzt ankommen.
        "modelInfo": {
            key: {
                "family": family,
                "steps": steps,
                "guidance": guidance,
                "size": base,
                "vram": vram,
                "negativePrompt": guidance > 0 and family != "flux",
                "longPrompt": True,
            }
            for key, (_, family, steps, guidance, base, vram)
            in MODELS.items()
        },
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
        width=width,
        height=height,
        num_inference_steps=int(steps),
        guidance_scale=float(guidance),
        num_images_per_prompt=count,
        generator=generator,
    )
    # FLUX und SDXL-Turbo kennen keinen Negativ-Prompt.
    family = MODELS[name][1]
    use_negative = (
        bool(req.negative_prompt) and family != "flux" and guidance > 0
    )

    # Lange Prompts: SD 1.5 und SDXL verstehen am Stueck nur 77 Tokens.
    # Statt den Rest wegzuwerfen, zerlegen wir den Text in Bloecke und
    # reichen die fertigen Text-Vektoren durch.
    long_kwargs = None
    long_note = ""
    if len(req.prompt) > 200:
        try:
            long_kwargs, long_note = _long_prompt_kwargs(
                pipe, family, req.prompt,
                req.negative_prompt if use_negative else "")
        except Exception as exc:  # pragma: no cover - modellabhaengig
            print(
                "Langer Prompt konnte nicht zerlegt werden, es gilt das "
                f"77-Token-Limit: {exc}",
                flush=True,
            )
            traceback.print_exc()
            long_kwargs = None
            long_note = (
                f"Der lange Prompt liess sich nicht zerlegen "
                f"({type(exc).__name__}: {exc}); es gilt das "
                "77-Token-Limit."
            )

    if long_kwargs:
        kwargs.update(long_kwargs)
        if not use_negative:
            kwargs.pop("negative_prompt_embeds", None)
            kwargs.pop("negative_pooled_prompt_embeds", None)
    else:
        kwargs["prompt"] = req.prompt
        if use_negative:
            kwargs["negative_prompt"] = req.negative_prompt
        # SD 3.5 und FLUX verstehen laengere Texte, muessen aber
        # ausdruecklich danach gefragt werden.
        if family == "sd3":
            kwargs["max_sequence_length"] = 256
        elif family == "flux":
            kwargs["max_sequence_length"] = 512

    # Nur eine Anfrage zur Zeit an die Pipeline: Scheduler und Modell
    # sind gemeinsam genutzter Zustand (siehe _pipe_lock).
    note = long_note
    with _pipe_lock:
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
            # Der ganze Stapel gehoert ins Server-Log: Die einzeilige
            # Meldung ("index 31 is out of bounds ...") sagt nicht, aus
            # welcher Ecke sie kommt.
            print("Generierung fehlgeschlagen:", flush=True)
            traceback.print_exc()
            if not long_kwargs:
                raise HTTPException(
                    status_code=500,
                    detail=f"Generierung fehlgeschlagen "
                    f"({type(exc).__name__}): {exc}",
                )
            # Zweiter Versuch ohne die selbst gebauten Text-Vektoren.
            # Der Prompt wird dann bei 77 Tokens abgeschnitten - ein
            # etwas schwaecheres Bild ist immer noch besser als ein
            # Loch mitten im Massenlauf.
            print(
                "Zweiter Versuch ohne zerlegten Prompt (der Text wird "
                "dabei bei 77 Tokens abgeschnitten).",
                flush=True,
            )
            for key in (
                "prompt_embeds",
                "pooled_prompt_embeds",
                "negative_prompt_embeds",
                "negative_pooled_prompt_embeds",
            ):
                kwargs.pop(key, None)
            kwargs["prompt"] = req.prompt
            if use_negative:
                kwargs["negative_prompt"] = req.negative_prompt
            try:
                result = pipe(**kwargs)
            except Exception as second:
                print("Auch der zweite Versuch schlug fehl:", flush=True)
                traceback.print_exc()
                raise HTTPException(
                    status_code=500,
                    detail=f"Generierung fehlgeschlagen "
                    f"({type(exc).__name__}): {exc} - auch der Versuch "
                    f"mit gekuerztem Prompt schlug fehl "
                    f"({type(second).__name__}): {second}",
                )
            note = (
                "Der zerlegte lange Prompt liess sich nicht verwenden "
                f"({type(exc).__name__}: {exc}); das Bild entstand mit "
                "dem bei 77 Tokens gekuerzten Text."
            )

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
        # Leer, wenn alles glatt lief; sonst steht hier, was der Server
        # hinter den Kulissen anders machen musste.
        "note": note,
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
