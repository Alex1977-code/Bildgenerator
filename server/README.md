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
- **Python 3.11** und Git. Wichtig: **nicht Python 3.12 oder neuer** –
  TripoSR pinnt `transformers==4.35.0` (Anfang 2024), und das dazu
  passende `tokenizers 0.14.1` hat für 3.12 kein fertiges Paket. pip
  versucht dann, es mit Rust aus dem Quellcode zu bauen, was
  regelmäßig scheitert.
- Windows: TripoSR läuft nativ (siehe unten); für TRELLIS ist
  **WSL2 (Ubuntu)** dringend zu empfehlen.

## Installation – TripoSR (empfohlen)

### Windows (PowerShell)

Wichtig: PowerShell **ohne** „Als Administrator ausführen" starten –
sonst landest du in `C:\WINDOWS\System32` und darfst dort nichts
anlegen. Ein eigener Ordner ist Pflicht, kein Systemordner.

Vorab einmalig installieren:

- **Python 3.11** von python.org (beim Setup „Add python.exe to PATH"
  ankreuzen). Nicht 3.12+ (siehe Voraussetzungen oben) und nicht die
  Version aus dem Microsoft Store. Eine vorhandene 3.12 kann parallel
  installiert bleiben – die Umgebung wird unten gezielt mit
  `py -3.11` angelegt.
- **Git** von git-scm.com
- **Visual Studio Build Tools** mit der Arbeitslast „Desktopentwicklung
  mit C++" – TripoSR kompiliert beim Installieren das Paket
  `torchmcubes`, ohne die Build Tools bricht das ab.

Dann:

```powershell
# 1) Eigener Arbeitsordner (NICHT System32)
mkdir C:\KI
cd C:\KI

# 2) Repo holen und Umgebung anlegen
git clone https://github.com/VAST-AI-Research/TripoSR.git
cd TripoSR
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
```

Meldet PowerShell „Die Datei kann nicht geladen werden, da die
Ausführung von Skripts auf diesem System deaktiviert ist", einmalig:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

Vor der Eingabezeile steht danach `(.venv)`. Weiter:

```powershell
# 3) PyTorch MIT CUDA (Beispiel CUDA 12.1 – aktuelle Zeile auf
#    pytorch.org/get-started/locally nachsehen)
pip install torch --index-url https://download.pytorch.org/whl/cu121

# 4) Version prüfen (muss 3.11.x zeigen), dann Abhängigkeiten
python --version
pip install -r requirements.txt
pip install fastapi uvicorn pydantic

# 5) Server-Skript herunterladen und starten
curl.exe -L -o local3d_server.py https://raw.githubusercontent.com/Alex1977-code/Bildgenerator/claude/image-generator-text-descriptions-hxsqas/server/local3d_server.py
python local3d_server.py --backend triposr --port 8765
```

Beim ersten Lauf lädt der Server die Modellgewichte automatisch von
Hugging Face herunter (~1,5 GB). Läuft er, meldet die Konsole die
Adresse `http://127.0.0.1:8765` – genau die kommt in die App.

Zum späteren Starten reichen drei Zeilen:

```powershell
cd C:\KI\TripoSR
.\.venv\Scripts\Activate.ps1
python local3d_server.py --backend triposr --port 8765
```

### Linux / macOS / WSL2

```bash
mkdir -p ~/ki && cd ~/ki
git clone https://github.com/VAST-AI-Research/TripoSR.git
cd TripoSR
python3.11 -m venv .venv
source .venv/bin/activate

# PyTorch MIT CUDA (Version passend zur GPU, siehe pytorch.org)
pip install torch --index-url https://download.pytorch.org/whl/cu121

pip install -r requirements.txt
pip install fastapi uvicorn pydantic

curl -L -o local3d_server.py https://raw.githubusercontent.com/Alex1977-code/Bildgenerator/claude/image-generator-text-descriptions-hxsqas/server/local3d_server.py
python local3d_server.py --backend triposr --port 8765
```

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
- **`Permission denied` / `Zugriff verweigert` beim Klonen** → du bist
  in `C:\WINDOWS\System32`. PowerShell ohne Administrator-Rechte neu
  starten und in einen eigenen Ordner wechseln (`cd C:\KI`).
- **`source .venv/bin/activate` wird nicht erkannt** → das ist
  Linux-Syntax. Unter Windows: `.\.venv\Scripts\Activate.ps1`.
- **Fehler beim Bauen von `torchmcubes`** → die Visual Studio Build
  Tools mit „Desktopentwicklung mit C++" fehlen; nach der Installation
  eine neue PowerShell öffnen und `pip install -r requirements.txt`
  wiederholen.
- **`tokenizers` bricht mit „Rust not found" / `metadata-generation-failed`
  ab** → die Umgebung läuft auf Python 3.12 oder neuer. Umgebung
  löschen (`Remove-Item -Recurse -Force .venv`) und mit
  `py -3.11 -m venv .venv` neu anlegen.
- **`Microsoft Visual C++ 14.0 or greater is required`** → siehe
  `torchmcubes` unten; Build Tools installieren und den Schritt
  wiederholen.
- **`python` öffnet den Microsoft Store** → Python von python.org
  installieren (mit „Add python.exe to PATH") oder unter
  „Einstellungen → Apps → App-Ausführungsaliase" die Python-Aliase
  abschalten.
