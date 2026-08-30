"""CPU-Ersatz für torchmcubes – für Rechner ohne CUDA-Toolkit.

TripoSR verlangt das Paket ``torchmcubes``. Das kompiliert beim
Installieren CUDA-Kernel und braucht dafür ``nvcc`` aus dem
CUDA-Toolkit; fehlt es, bricht ``pip install -r requirements.txt`` mit
„CMake configuration failed" ab.

Diese Datei ersetzt das Paket durch eine CPU-Variante auf Basis von
scikit-image (über ``rembg`` ohnehin installiert). Nur das Marching
Cubes selbst wandert damit auf die CPU – bei Auflösung 256 kostet das
etwa eine Sekunde, das eigentliche Modell rechnet weiter auf der GPU.

Verwendung: die Datei als ``torchmcubes.py`` in den TripoSR-Ordner
legen (neben ``run.py``). Python findet sie dort anstelle des Pakets,
``pip install`` ist nicht nötig.

Achsen-Reihenfolge: torchmcubes und scikit-image geben die Ecken in
unterschiedlicher Reihenfolge zurück – das Modell läge sonst auf der
Seite. Der Server erkennt diesen Ersatz am Merkmal ``SHIM`` und dreht
das fertige Netz gerade (siehe ``_fix_shim_axes`` in
``local3d_server.py``); an dieser Datei ist dafür nichts einzustellen.
"""

import os

import numpy as np
import torch
from skimage import measure

# Erkennungsmerkmal: Der Server sieht daran, dass nicht das echte
# torchmcubes läuft, und dreht die Achsen entsprechend gerade.
SHIM = True

_FLIP = os.environ.get("TORCHMCUBES_SHIM_FLIP", "1") != "0"


def marching_cubes(vol, thresh=0.0):
    """Wie ``torchmcubes.marching_cubes``: (Ecken, Dreiecke) als Tensoren."""
    volume = vol.detach().cpu().numpy().astype(np.float32)
    level = float(thresh)
    # Liegt der Schwellwert außerhalb der Daten, gibt es keine Fläche –
    # scikit-image würde hier eine Ausnahme werfen.
    if not (float(volume.min()) < level < float(volume.max())):
        return (
            torch.zeros((0, 3), dtype=torch.float32),
            torch.zeros((0, 3), dtype=torch.long),
        )
    verts, faces, _normals, _values = measure.marching_cubes(
        volume, level=level
    )
    if _FLIP:
        verts = verts[:, ::-1]
    return (
        torch.from_numpy(np.ascontiguousarray(verts)).float(),
        torch.from_numpy(np.ascontiguousarray(faces)).long(),
    )


def grid_interp(vol, points):
    """Im CPU-Ersatz nicht enthalten – von TripoSR nicht benutzt."""
    raise NotImplementedError(
        'grid_interp fehlt im CPU-Ersatz für torchmcubes.'
    )
