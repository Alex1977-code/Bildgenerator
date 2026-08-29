# Eigener 3D-Server (TripoSR / TRELLIS)

Mit diesem kleinen Server läuft die Bild→3D-Generierung **komplett auf
deinem eigenen PC** – kostenlos, ohne Cloud, alle Bilder bleiben lokal.
Die App nutzt ihn als Provider **„Server“** im 3D-Tab: Sie schickt die
Vorderansicht an den Server, der antwortet mit der fertigen GLB-Datei.
Rigging und die lokale Veredelung (Symmetrisieren, Textur schärfen)
übernimmt danach wie gewohnt die App.

Beide Modelle sind **MIT-lizenziert** und damit auch in der EU ohne
Einschränkungen nutzbar (anders als z. B. Hunyuan3D 2.1 zum
Selbst-Hosten, dessen Community-Lizenz die EU ausschließt).

| Backend | Qualität | Tempo | VRAM | Installation |
|---|---|---|---|---|
| **TripoSR** (empfohlen zum Start) | solide | Sekunden | ~4–6 GB | einfach |
| **TRELLIS** | deutlich besser (Textur!) | 1–3 Min. | ~12–16 GB | aufwendig |

## Voraussetzungen

- NVIDIA-GPU mit aktuellem Treiber
- Python 3.10 oder 3.11 und Git
- Windows: am einfachsten unter **WSL2 (Ubuntu)**; nativ unter Windows
  werden zusätzlich die „Visual Studio Build Tools“ (C++) benötigt,
  weil TripoSR das Paket `torchmcubes` beim Installieren kompiliert.

## Installation – TripoSR (empfohlen)

```bash
# 1) Repo klonen und Umgebung anlegen
git clone https://github.com/VAST-AI-Research/TripoSR.git
cd TripoSR
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

# 2) PyTorch MIT CUDA installieren (Version passend zur GPU, siehe
#    pytorch.org – Beispiel für CUDA 12.x):
pip install torch --index-url https://download.pytorch.org/whl/cu121

# 3) TripoSR-Abhängigkeiten + Server-Abhängigkeiten
pip install -r requirements.txt
pip install rembg onnxruntime
pip install -r /pfad/zum/Bildgenerator/server/requirements.txt

# 4) Server-Skript in den TripoSR-Ordner kopieren und starten
cp /pfad/zum/Bildgenerator/server/local3d_server.py .
python local3d_server.py --backend triposr --port 8765
```

Beim ersten Lauf lädt der Server die Modellgewichte automatisch von
Hugging Face herunter (~1,5 GB).

## Installation – TRELLIS (beste Qualität)

TRELLIS hat eine aufwendigere Installation (flash-attn, spconv,
nvdiffrast … – Linux/WSL2 dringend empfohlen). Der offiziellen
Anleitung folgen: <https://github.com/microsoft/TRELLIS>
(`. ./setup.sh --new-env --basic --xformers --flash-attn --diffoctreerast
--spconv --mipgaussian --kaolin --nvdiffrast`).

Danach in derselben Umgebung:

```bash
pip install -r /pfad/zum/Bildgenerator/server/requirements.txt
cp /pfad/zum/Bildgenerator/server/local3d_server.py .
python local3d_server.py --backend trellis --port 8765
```

(TRELLIS.2 und Hi3DGen sind ebenfalls MIT-lizenziert – sie lassen sich
nach demselben Muster anbinden, sobald gewünscht.)

## In der App verbinden

1. App öffnen → **Einstellungen** → Karte **„Eigener 3D-Server“** →
   Adresse eintragen: `http://127.0.0.1:8765` → **Speichern & testen**
   (zeigt Backend und GPU an).
2. 3D-Tab → Provider **„Server“** wählen → wie gewohnt aus Text oder
   Bild generieren.

**Anderer PC im Netzwerk** (z. B. App auf dem Handy, Server auf dem
Gaming-PC): Als Adresse `http://<IP-des-PCs>:8765` eintragen und den
Port 8765 in der Windows-Firewall freigeben.

**Web-Version der App**: Der Browser erlaubt Zugriffe auf
`http://127.0.0.1` bzw. `http://localhost` auch aus der per HTTPS
geladenen Web-App. Für Adressen mit LAN-IP blockieren Browser dagegen
„Mixed Content“ – dann die Windows- oder Android-App verwenden.

## Fehlersuche

- **„Backend ist nicht installiert“** → Server aus dem Ordner des
  geklonten Modell-Repos starten (dort liegt das `tsr`- bzw.
  `trellis`-Paket) und Installation abschließen.
- **`/health` meldet `cpu`** → PyTorch ohne CUDA installiert; Schritt 2
  oben mit dem CUDA-Index wiederholen.
- **Out of Memory** → andere GPU-Programme schließen; bei TRELLIS
  `texture_size` im Skript auf 512 senken.
