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

| Backend | Qualität | VRAM | Besonderheit | Lizenz |
|---|---|---|---|---|
| **TripoSR** | solide, Vertex-Farben | ~4–6 GB | Sekunden; optional Textur-Backen | MIT |
| **SF3D** (Empfehlung) | gut, echte UV-Textur | ~6 GB | dasselbe Modell wie Stabilitys „Fast 3D"-API | Community (frei < 1 Mio. US-$) |
| **SPAR3D** | sehr gut, UV-Textur | ~7–10,5 GB | beste Rückseiten-Rekonstruktion | Community |
| **TRELLIS** | am besten | ~12–16 GB | **Multiview**: wertet mehrere Ansichten gemeinsam aus; Windows nur über WSL2 | MIT |

SF3D und SPAR3D sind auf Hugging Face freigabepflichtig: einmalig die
Lizenz auf der Modellseite bestätigen und `huggingface-cli login`
ausführen.

Nicht dabei ist **Hunyuan3D**: Dessen Community-Lizenz schließt die EU,
Großbritannien und Südkorea vom Selbst-Hosten aus. Über fal.ai oder
Replicate ist es dagegen ganz normal nutzbar.

Der Server meldet unter `/health`, was das laufende Modell kann
(`multiview`, `texture_resolution`, `remesh`, `target_count`,
`resolution`, `bake_texture`) – die App blendet genau die passenden
Bedienelemente ein.

## Zwei Server: Bild und 3D

Der Ordner enthält zwei kleine Server, die unabhängig voneinander
laufen können:

| Server | Skript | Port | Aufgabe |
| --- | --- | --- | --- |
| Bild | `local_image_server.py` | 8766 | Text→Bild (Stable Diffusion) |
| 3D | `local3d_server.py` | 8765 | Bild→3D (TripoSR, SF3D, SPAR3D, TRELLIS) |

Beide zusammen ergeben die komplette Kette **Text→Bild→3D auf dem
eigenen Rechner**: kostenlos, ohne API-Schlüssel, und kein Bild
verlässt den PC. Beide richtet derselbe Assistent in der App ein
(Einstellungen → „Eigener Bild-Server" bzw. „Eigener 3D-Server").

### Bild-Server: Modelle und Speicherbedarf

| Kennung | Modell | VRAM | Bemerkung |
| --- | --- | --- | --- |
| `sd15` | Stable Diffusion 1.5 | ~4 GB | sparsam, schnell |
| `sdxl-turbo` | SDXL Turbo | ~7 GB | wenige Schritte, sehr schnell |
| `sdxl` | SDXL Base 1.0 | ~8 GB | beste Allround-Qualität |
| `sd35-medium` | SD 3.5 Medium | ~10 GB | auch Schrift im Bild |
| `flux-schnell` | FLUX.1 schnell | ~16 GB | Spitzenklasse |

Reicht der Grafikspeicher nicht, lagert der Server Teile automatisch
aus – langsamer, aber es läuft. Das Modell wird in der App gewählt
(Bild-Tab → KI-Modell → „Eigene GPU · …"); der Server lädt es beim
ersten Bild aus dem Hugging-Face-Cache. SD 3.5 und FLUX verlangen
einmalig eine Lizenz-Zustimmung auf huggingface.co und
`huggingface-cli login`.

Start von Hand:

```powershell
.\.venv\Scripts\python.exe local_image_server.py --model sdxl-turbo --port 8766
```

## Der bequeme Weg: Assistent in der App

Die Windows-, Linux- und macOS-App bringt die Einrichtung fertig mit:
**Einstellungen → Eigener 3D-Server → „Einrichtungs-Assistent"**. Er
prüft Python 3.11, Git und die GPU, zeigt vorab, was installiert wird,
erledigt alle Schritte mit Live-Protokoll und startet den Server; die
Adresse trägt sich selbst in die Einstellungen ein.
Er lässt auch das Modell wählen (TripoSR, SF3D, SPAR3D, TRELLIS) und
gleicht den VRAM-Bedarf mit der erkannten Karte ab. Die Anleitung unten
ist der Weg von Hand – nötig nur für TRELLIS unter Windows oder wenn
etwas schiefgeht.

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

### Wenn `torchmcubes` nicht baut (kein CUDA-Toolkit)

`pip install -r requirements.txt` bricht bei `torchmcubes` mit
„CMake configuration failed" ab, sobald `nvcc` fehlt – der
CUDA-Compiler steckt weder im Grafiktreiber noch in PyTorch, sondern
nur im separaten **CUDA-Toolkit** (~3 GB).

Statt es zu installieren, reicht der mitgelieferte CPU-Ersatz
(`server/shim/torchmcubes.py`, nutzt scikit-image). Marching Cubes
läuft dann auf der CPU – bei Auflösung 256 rund eine Sekunde –, das
Modell selbst weiter auf der GPU:

Wichtig: Scheitert `torchmcubes`, bricht pip den **gesamten** Vorgang
ab – es ist dann gar nichts installiert, auch numpy und Pillow nicht.
Deshalb hier eine eigene Paketliste ohne torchmcubes:

```powershell
# im TripoSR-Ordner, Umgebung aktiv
curl.exe -L -o torchmcubes.py https://raw.githubusercontent.com/Alex1977-code/Bildgenerator/claude/image-generator-text-descriptions-hxsqas/server/shim/torchmcubes.py
curl.exe -L -o requirements-triposr.txt https://raw.githubusercontent.com/Alex1977-code/Bildgenerator/claude/image-generator-text-descriptions-hxsqas/server/requirements-triposr.txt
pip install -r requirements-triposr.txt
```

Der Server erkennt den Ersatz selbst und dreht das Netz gerade –
scikit-image liefert die Achsen anders als torchmcubes, die Figur läge
sonst auf der Seite. Sollte ein Modell trotzdem falsch herum stehen,
lässt sich die Zuordnung überschreiben:

```powershell
$env:TRIPOSR_AXES = "yzx"   # Vorgabe; z. B. "y z -x" spiegelt zusätzlich
python local3d_server.py --backend triposr --port 8765
```

Wer lieber den offiziellen Weg geht: CUDA-Toolkit passend zur
PyTorch-Version installieren (bei `cu121` also 12.1, siehe
<https://developer.nvidia.com/cuda-toolkit-archive>), neue PowerShell
öffnen, `nvcc --version` prüfen und
`pip install -r requirements.txt` wiederholen.

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

1. App öffnen → **Einstellungen** → Karte **„Eigener 3D-Server“**.
   In der Auswahlliste steht oben **„Keiner“**, darunter jeder auf
   diesem PC eingerichtete Server. Einen auswählen →
   **„Server starten“**: Die App startet ihn im Hintergrund, trägt die
   Adresse ein und meldet, sobald er antwortet (beim ersten Start lädt
   er die Modellgewichte – das dauert).
2. Alternativ von Hand: Adresse `http://127.0.0.1:8765` eintragen →
   **Speichern & testen** (zeigt Backend und GPU an).
3. 3D-Tab → Provider **„Server“** wählen → wie gewohnt aus Text oder
   Bild generieren.

Die Liste zeigt sowohl die vom Assistenten angelegten Installationen
als auch solche, die neben dem Standardordner (z. B. `C:\KI\SF3D`)
von Hand eingerichtet wurden. „Aus der Liste nehmen“ entfernt nur den
Eintrag, nicht die Installation.

**Anderer PC im Netzwerk** (z. B. App auf dem Handy, Server auf dem
Gaming-PC): Als Adresse `http://<IP-des-PCs>:8765` eintragen und den
Port 8765 in der Windows-Firewall freigeben.

**Web-Version der App**: Der Browser erlaubt Zugriffe auf
`http://127.0.0.1` bzw. `http://localhost` auch aus der per HTTPS
geladenen Web-App. Für Adressen mit LAN-IP blockieren Browser dagegen
„Mixed Content“ – dann die Windows- oder Android-App verwenden.

## Fehlersuche

- **SF3D/SPAR3D: `Getting requirements to build wheel did not run
  successfully`** → Beide Projekte bauen eigene C++-Erweiterungen
  (`texture_baker`, `uv_unwrapper`), die PyTorch schon beim Bauen
  brauchen. pip kapselt den Bauvorgang aber ab, dort fehlt torch. Der
  Assistent installiert deshalb mit `--no-build-isolation`; von Hand:

  ```powershell
  pip install -U pip setuptools wheel
  pip install -r requirements.txt --no-build-isolation
  ```

  Zusätzlich nötig: die Visual Studio Build Tools mit
  „Desktopentwicklung mit C++".
- **SF3D/SPAR3D unter Windows: `Failed building wheel for
  uv_unwrapper` / `texture_baker`** → zwei Ursachen, beide behebt der
  Assistent inzwischen selbst:
  1. MSVC übersetzt ohne Angabe nach C++14, die PyTorch-Header
     verlangen aber C++17. Ergebnis sind unverständliche
     Vorlagen-Fehler wie „Fehler beim Spezialisieren der
     Funktionsvorlage `std::make_tuple`". Von Hand vor dem Bauen:

     ```powershell
     $env:CL = "/std:c++17"
     pip install -r requirements.txt --no-build-isolation
     ```

  2. `uv_unwrapper/uv_unwrapper/csrc/bvh.cpp` nutzt `std::make_tuple`
     und `std::exchange`, ohne `<tuple>` und `<utility>` einzubinden.
     GCC zieht sie nebenbei mit herein, MSVC nicht – die beiden
     `#include`-Zeilen oben in der Datei ergänzen
     (Stability-AI/stable-fast-3d, Issue 45).

  Bleibt es dabei, fehlt meist der Compiler selbst: Visual Studio
  Build Tools mit „Desktopentwicklung mit C++" nachinstallieren und
  erneut auf „Installieren" tippen – bereits geladene Teile werden
  übersprungen. Wer sich das sparen will, nimmt **TripoSR**: Das
  Modell kommt ohne eigene C++-Bauteile aus.
- **SF3D/SPAR3D unter Windows: `link.exe … returned non-zero exit
  status 1120`** → Das Übersetzen hat geklappt, erst das
  Zusammenbinden scheitert; 1120 heißt „nicht aufgelöste Symbole".
  Welche fehlen, steht im Protokoll in den Zeilen darüber
  (`LNK2019: unresolved external symbol …`). Der Assistent speichert
  das vollständige Protokoll als `einrichtung-protokoll.txt` im
  Zielordner und hat einen Knopf „Kopieren".
  Hintergrund: SF3D und SPAR3D werden vom Projekt selbst nur unter
  Linux gebaut – die `setup.py` beider C++-Teile kennt ausschließlich
  GCC/Clang-Schalter und keinen Windows-Zweig. Zuverlässig laufen
  unter Windows deshalb **TripoSR** (3D) und der **Bild-Server**
  (Text→Bild); beide brauchen keinen Compiler. SF3D in voller
  Qualität gibt es alternativ über WSL2 (Ubuntu) oder als
  Bezahl-API (Stability „Fast 3D", fal.ai).
- **`No module named 'PIL'`** (oder ein anderes Paket) beim Generieren
  → `pip install -r requirements.txt` ist nicht vollständig
  durchgelaufen. In der aktiven Umgebung wiederholen und dabei auf die
  letzten Zeilen achten – es muss `Successfully installed …` erscheinen.
  Der Server nennt fehlende Pakete beim Start und unter `/health`.
- **„Backend ist nicht installiert“** → Server aus dem Ordner des
  geklonten Modell-Repos starten (dort liegt das `tsr`- bzw.
  `trellis`-Paket) und Installation abschließen.
- **`/health` meldet `cpu`** → PyTorch ohne CUDA installiert; Schritt 2
  oben mit dem CUDA-Index wiederholen.
- **Figur steht auf der Seite oder liegt** → alte Fassung von
  `local3d_server.py`; die aktuelle dreht das Netz beim CPU-Ersatz
  selbst gerade. Beide Dateien neu laden (`local3d_server.py` und
  `torchmcubes.py`).
- **`'numpy.ndarray' object has no attribute 'ptp'`** → das von
  TripoSR gepinnte `trimesh==4.0.5` ist nicht mit NumPy 2 verträglich.
  `pip install -U trimesh` behebt es; die Liste
  `requirements-triposr.txt` verlangt deshalb `trimesh>=4.5`.
- **Out of Memory** → andere GPU-Programme schließen; bei TRELLIS
  `texture_size` im Skript auf 512 senken.
- **`Permission denied` / `Zugriff verweigert` beim Klonen** → du bist
  in `C:\WINDOWS\System32`. PowerShell ohne Administrator-Rechte neu
  starten und in einen eigenen Ordner wechseln (`cd C:\KI`).
- **`source .venv/bin/activate` wird nicht erkannt** → das ist
  Linux-Syntax. Unter Windows: `.\.venv\Scripts\Activate.ps1`.
- **Fehler beim Bauen von `torchmcubes`** → bei
  „Microsoft Visual C++ 14.0 or greater is required" fehlen die Visual
  Studio Build Tools; bei „CMake configuration failed" mit
  `CMakeDetermineCUDACompiler` fehlt das CUDA-Toolkit – dafür gibt es
  den CPU-Ersatz, siehe Abschnitt „Wenn `torchmcubes` nicht baut".
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
