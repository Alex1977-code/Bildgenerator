# 3DGenerator

Eine App zum Erstellen von Bildern und 3D-Modellen aus
Textbeschreibungen – mit optionalen Referenzbildern, wählbarer
Bildgröße, Qualität und transparentem Hintergrund. Eine Codebasis
(Flutter) für **Windows, Android, iOS und Web**. (Repository-Name:
Bildgenerator – die App heißt 3DGenerator, Icon: 3D-Würfel.)

## Funktionen

- **Text → Bild**: Bildbeschreibung (Prompt) eingeben, Bild generieren.
- **Mehrere Referenzbilder** (bis zu 16): eigene Fotos/Bilder als Vorlage
  mitgeben – das Ergebnis orientiert sich daran (OpenAI und Gemini).
- **Bildgröße/Seitenverhältnis wählbar**: Quadrat, Quer-, Hochformat
  (OpenAI) bzw. 9 Seitenverhältnisse von 21:9 bis 9:21 (Stability AI).
- **Qualität wählbar**: Auto / Niedrig / Mittel / Hoch.
- **Transparenter Hintergrund** (für Logos & Icons, PNG/WebP) – mit
  Schachbrett-Vorschau.
- **Profi-Features**:
  - Drei Provider: **OpenAI GPT Image**, **Stability AI Stable Image**
    (Core/Ultra) und **Google Gemini** („Nano Banana“ / „Nano Banana Pro“
    mit bis zu 4K-Auflösung)
  - **Modell frei wählbar**: bekannte Modelle per Klick, zusätzlich freie
    Eingabe beliebiger Modell-IDs – neue Modelle der Anbieter (z. B. ein
    künftiges gpt-image-2) lassen sich sofort ohne App-Update nutzen
  - Ausgabeformat PNG / JPEG / WebP inkl. Kompressionsgrad
  - Batch-Generierung (1–4 Bilder pro Anfrage)
  - Negativ-Prompt, Seed (reproduzierbare Bilder) und 16 Style-Presets
    (Stability AI)
  - Stil-Vorlagen per Klick (fotorealistisch, Ölgemälde, Logo, 3D-Render …)
  - Generierte Bilder als neue Referenz übernehmen (iteratives Verfeinern)
  - **3D-Bereich (Meshy AI, Tripo3D oder Stability 3D)**: 3D-Figuren
    und -Objekte aus Text oder Bild, optional mit Textur und
    Auto-Rigging (T-Pose wird automatisch berücksichtigt, Tripo prüft
    die Riggbarkeit vorab), Export als GLB für
    Blender/Unity/Unreal/Godot. Stability 3D (Stable Fast 3D /
    Stable Point Aware 3D) nutzt trainierte generative Modelle, die aus
    einem einzigen Bild auch Rückseite, Vertiefungen und Hohlräume
    rekonstruieren – mit demselben Stability-Schlüssel wie die
    Bilderzeugung
  - **Eigener lokaler 3D-Generator** (Standard, ohne API, kostenlos):
    baut direkt in der App ein farbiges 360°-Modell (Visual Hull aus
    bis zu 4 Ansichten mit Farbprojektion und geglätteter
    Surface-Nets-Oberfläche); eigener glTF-2.0-Writer in Dart.
    Optional **KI-Tiefenschätzung**: Per Bild-KI geschätzte
    Tiefenkarten formen Mulden und Vertiefungen in Vorder- und
    Rückseite – über die Silhouetten-Grenze des Visual Hull hinaus
  - **Eigenes Auto-Rigging** für Lokal und Stability: ein
    Standard-Skelett wird komplett lokal berechnet (Heuristik aus der
    Bounding Box, Abstands-Skinning) und direkt ins GLB eingebaut –
    für Animationstests in Blender/Unity/Godot. Wählbare Figurtypen:
    Mensch/Roboter/Fantasy (T-Pose, 17 Gelenke), Vierbeiner (19),
    Insekt/Mehrbeiner (22), Vogel mit gespreizten Flügeln (13),
    Schlange (8) und Fisch (6); die passende Rig-Pose fließt
    automatisch in die KI-erzeugten Ansichten ein
  - **Animationen direkt in der App**: Die 3D-Vorschau spielt
    Animations-Clips aus der GLB-Datei ab (CPU-Skinning im eigenen
    Renderer) und bringt eingebaute Testanimationen je Figurtyp mit
    (Gehen, Winken, Vierbeiner-Gang, Flügelschlag, Krabbeln,
    Schlängeln, Schwimmen, Wackeltest); das Skelett lässt sich per
    Knopf grafisch über dem Modell einblenden. Die Testanimationen
    können optional als echte, loopbare glTF-Clips mit ins exportierte
    GLB gebacken werden („GLB + Testanimationen exportieren“)
  - **STL-, 3MF- und OBJ-Export**: Der Viewer exportiert Modelle als
    binäres STL (nur Form) oder als 3MF **mit Farben** (Material-
    Palette je Dreieck) – jeweils aufs Druckbett gedreht, zentriert
    und auf die gewünschte Größe in mm skaliert, mit eingebauter
    **Wasserdichtheits-Prüfung** im Export-Dialog; dazu OBJ mit
    Vertexfarben für Blender/MeshLab. Druck: Datei in einen Slicer
    laden (PrusaSlicer, Cura, Bambu Studio …) oder beim
    Farbdruck-Dienst hochladen
  - **Immer aktuelle Bild-Modelle**: gpt-image-2/1.5, SD 3.5 & Co.
    sind vorkonfiguriert, und der Aktualisieren-Knopf neben der
    Modell-Auswahl lädt die aktuell verfügbaren Modelle direkt vom
    Anbieter (OpenAI/Google) – neue Modelle sind so ohne App-Update
    wählbar
  - **Multi-View 3D**: Ansichten von vorn/links/rechts/hinten ergeben bei
    allen drei 3D-Wegen ein deutlich genaueres Rundum-Modell (Meshy
    Multi-Image-API, Tripo multiview_to_model, lokal per Voxel-Carving)
  - **Text → Ansichten → 3D**: Die Ansichten-Bilder können automatisch
    per Bild-KI (OpenAI oder Gemini) aus der Beschreibung erzeugt werden –
    zuerst die Vorderansicht, dann Links/Rechts/Hinten mit der
    Vorderansicht als Referenz und strengen Konsistenz-Prompts
    (orthographisch, gleiche Skalierung, transparenter Hintergrund,
    optional T-Pose). So funktioniert auch der lokale Generator rein per
    Text; bei Meshy/Tripo ist die Pipeline im Text-Modus zuschaltbar.
    Bereits erzeugte Ansichten werden wiederverwendet und lassen sich
    einzeln austauschen. Auch im Bild-Modus: Wer weniger als 4 Ansichten
    hochlädt, bekommt die fehlenden auf Wunsch automatisch aus der
    Vorderansicht ergänzt – mit denselben Konsistenz-Vorgaben.
  - **Qualitäts-Optionen (Profi)** für Meshy/Tripo: KI-Generation
    wählbar (Meshy 5/6/Neueste bzw. Tripo v2.5/v3.0), Polygonzahl,
    Quad-Topologie, Symmetrie-Modus, PBR-Material, Textur-Qualität
    „detailliert“ und eigener Textur-Prompt; dazu T-Pose-Schalter und
    eingebaute Tipps für bessere 3D-Modelle
  - Wasserzeichen mit eigenem Logo (Position, Größe, Deckkraft)
  - Galerie/Verlauf mit Prompt, Parametern und „Erneut verwenden“
  - Bilder speichern, teilen bzw. herunterladen
  - API-Schlüssel werden **verschlüsselt lokal** gespeichert (Keychain /
    Keystore / DPAPI), dunkles & helles Design

## Voraussetzung: API-Schlüssel

Die Bilder werden von einem KI-Provider erzeugt. Dafür wird ein eigener
API-Schlüssel benötigt (nutzungsbasierte Kosten beim Anbieter, grob
0,01–0,25 $ pro Bild je nach Qualität):

- **OpenAI** (empfohlen, alle Funktionen): <https://platform.openai.com/api-keys>
  – für `gpt-image-1` muss die Organisation einmalig verifiziert werden
  (platform.openai.com → Settings → Organization → Verify).
- **Google Gemini** („Nano Banana“, **kostenloses Kontingent** zum
  Ausprobieren): <https://aistudio.google.com/apikey>
- **Stability AI** (Alternative): <https://platform.stability.ai/account/keys>
- **Meshy AI** (3D-Bereich, API-Zugang ab Pro-Plan):
  <https://www.meshy.ai/api>
- **Tripo3D** (3D-Bereich, Bezahlung nach Verbrauch, Startguthaben):
  <https://platform.tripo3d.ai>

Den Schlüssel in der App unter **Einstellungen** eintragen – er bleibt
ausschließlich auf dem Gerät und wird nur an den gewählten Provider gesendet.

## Feste Download-Links (immer neueste Version)

- **Windows**: <https://github.com/Alex1977-code/Bildgenerator/releases/latest/download/bildgenerator-windows.zip>
  (entpacken → `bildgenerator.exe` starten)
- **Android-APK**: <https://github.com/Alex1977-code/Bildgenerator/releases/latest/download/bildgenerator-android.apk>
- **Web-App (live)**: <https://alex1977-code.github.io/Bildgenerator/>
- Übersicht: [Release „Aktuelle Version“](https://github.com/Alex1977-code/Bildgenerator/releases/latest)

Diese Links zeigen automatisch auf den jeweils neuesten erfolgreichen Build.

## So testest du die App

Bei jedem Push baut GitHub Actions automatisch alle Varianten
(Reiter **Actions** → neuester „Build“-Lauf → Abschnitt **Artifacts**):

### Android (empfohlen zum Testen)

1. Auf dem Handy im Browser: GitHub → Repository → **Actions** → neuester
   „Build“-Lauf → Artifact **`bildgenerator-android-apk`** herunterladen
   (Anmeldung bei GitHub erforderlich).
2. Die ZIP entpacken und `app-release.apk` antippen. Beim ersten Mal fragt
   Android nach der Erlaubnis, Apps „aus unbekannten Quellen“ zu
   installieren – bestätigen.
3. App öffnen → Einstellungen → API-Schlüssel eintragen → losgenerieren.

### Windows

1. Artifact **`bildgenerator-windows`** herunterladen und entpacken.
2. `bildgenerator.exe` starten (keine Installation nötig).

### iPhone / iPad

- **Sofort testbar als Web-App (PWA):**
  1. Einmalig: Repository → **Settings → Pages** → Source **„GitHub
     Actions“** auswählen.
  2. Workflow **„Web-Version veröffentlichen (GitHub Pages)“** unter
     Actions per „Run workflow“ starten (läuft bei Pushes auf `main`
     später automatisch).
  3. Die App ist dann unter
     `https://<benutzername>.github.io/<repository-name>/` erreichbar –
     in Safari öffnen → Teilen → **„Zum Home-Bildschirm“** → sie verhält
     sich wie eine installierte App.
- **Nativ (App Store / TestFlight):** iOS-Apps können nur auf einem Mac
  mit Xcode (oder einem CI-Dienst wie Codemagic) signiert werden und
  benötigen ein Apple-Developer-Konto. Das Projekt ist dafür vorbereitet:
  `flutter build ipa` auf einem Mac genügt.

> Hinweis zur Web-Version: Der Verlauf gilt dort nur für die aktuelle
> Sitzung, und einzelne Provider können Browser-Anfragen per CORS
> einschränken (OpenAI funktioniert im Browser). Die nativen Apps sind
> davon nicht betroffen und speichern den Verlauf dauerhaft.

## Entwicklung

```bash
flutter pub get
flutter run                # auf angeschlossenem Gerät/Emulator
flutter run -d chrome      # im Browser
flutter build apk          # Android-APK
flutter build windows      # Windows (auf einem Windows-PC)
flutter build ipa          # iOS (auf einem Mac)
flutter test               # Tests
```

Verwendete Flutter-Version: 3.47.2 (stable).

## Architektur

```
lib/
├── main.dart                  # App-Shell, Navigation, Theme
├── models/models.dart         # Anfrage/Ergebnis/Verlauf + Auswahloptionen
├── screens/                   # Generator, Galerie, Detailansicht, Einstellungen
├── services/
│   ├── generators.dart        # OpenAI- & Stability-Anbindung (austauschbar)
│   ├── settings_service.dart  # Einstellungen + sichere Schlüsselablage
│   ├── history_service.dart   # Verlauf (Dateisystem nativ, In-Memory im Web)
│   └── exporter.dart          # Speichern/Teilen/Download je Plattform
└── widgets/common.dart        # Schachbrett-Transparenzvorschau u. a.
```

Weitere Provider lassen sich über das `ImageGenerator`-Interface in
`lib/services/generators.dart` ergänzen.
