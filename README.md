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
  - **3D-Bereich mit 8 Anbietern** (Lokal, Stability 3D, Meshy AI,
    Tripo3D, fal.ai, Rodin, Replicate, eigener Server): 3D-Figuren
    und -Objekte aus Text oder Bild, optional mit Textur und
    Auto-Rigging (T-Pose wird automatisch berücksichtigt, Tripo prüft
    die Riggbarkeit vorab), Export als GLB für
    Blender/Unity/Unreal/Godot. Stability 3D (Stable Fast 3D /
    Stable Point Aware 3D) nutzt trainierte generative Modelle, die aus
    einem einzigen Bild auch Rückseite, Vertiefungen und Hohlräume
    rekonstruieren – mit demselben Stability-Schlüssel wie die
    Bilderzeugung; einstellbar sind Textur-Auflösung, Polygonform
    (Original/Quads/Dreiecke), Ziel-Polygonzahl und Detailgrad – jede
    Option mit Infotext
  - **Einrichtungs-Assistent für den eigenen Server** (Windows, Linux,
    macOS): Einstellungen → Eigener 3D-Server → „Einrichtungs-Assistent".
    Prüft Python 3.11, Git und die NVIDIA-GPU (mit Download-Links, wenn
    etwas fehlt), zeigt vorab jeden Schritt samt Downloadgröße, führt
    die komplette Installation mit Live-Protokoll aus und startet den
    Server anschließend – die Adresse trägt sich selbst ein
  - **Vier lokale Modelle zur Auswahl** – der Assistent gleicht den
    VRAM-Bedarf mit der erkannten Grafikkarte ab: **TripoSR**
    (~4–6 GB, Sekunden), **SF3D** (~6 GB, echte UV-Textur – dasselbe
    Modell wie Stabilitys kostenpflichtige „Fast 3D"-API),
    **SPAR3D** (~7–10,5 GB, beste Rückseiten-Rekonstruktion) und
    **TRELLIS** (~12–16 GB, Spitzenqualität mit **Multiview**).
    Der Server meldet unter `/health`, was er kann – die App blendet
    genau die passenden Bedienelemente ein: bei Multiview die Kacheln
    für links/rechts/hinten, sonst Textur-Auflösung, Polygonform,
    Polygonzahl, Detailgrad oder Textur-Backen
  - **Eigener 3D-Server** als Provider „Server“: Bild→3D komplett auf
    dem eigenen PC mit NVIDIA-GPU – kostenlos, ohne Cloud, alle Daten
    bleiben lokal. Mitgelieferter Python-Server
    (`server/local3d_server.py`, FastAPI) mit den MIT-lizenzierten
    Open-Source-Modellen **TripoSR** (Sekunden, ~4–6 GB VRAM) oder
    **TRELLIS** (beste Qualität, ~12–16 GB VRAM); Einrichtung in
    `server/README.md`. Adresse in den Einstellungen eintragen
    („Speichern & testen“ zeigt Backend und GPU an) – Rigging und
    Veredelung übernimmt wie gewohnt die App
  - **Vorlagen für bewährte Einstellungen** ganz oben im 3D-Tab: ein
    Klick setzt Anbieter, Modell und alle Qualitäts-Optionen auf eine
    erprobte Kombination – „Fahrzeug (Game-Asset)“ und „Figur
    (Game-Asset)“ (Rodin Gen-2.5 High, Quad-Netz, passendes Rig),
    „Schnelltest“ (fal.ai TRELLIS für wenige Cent), „Eigene GPU“
    (eigener Server), „Höchste Detailtreue“ (Meshy 7 Ultra) und
    „3D-Druck“ (lokaler Generator, 128er-Raster, ohne Skelett);
    danach bleibt jede Option einzeln änderbar. Dazu **5 frei
    belegbare Plätze für eigene Vorlagen**: eine beliebige Kombination
    aus Anbieter, Modell, Qualitäts-Optionen, Rigging, Veredelung und
    Negativ-/Textur-Prompt unter eigenem Namen sichern, per Klick
    zurückholen und wieder löschen – bleibt auch nach einem Neustart
    erhalten
  - **Rodin (Hyper3D, Beta)** als 3D-Provider: Spitzenklasse für
    Game-Assets – Rodin Gen-2.5 liefert produktionsreife Meshes mit
    sauberer **Quad-Topologie**, PBR-Texturen und wählbarer
    Polygonzahl; Text→3D nativ (Figuren auf Wunsch direkt in
    T/A-Pose) und Bild→3D mit bis zu 4 Ansichten; Bezahlung nach
    Verbrauch (hyper3d.ai)
  - **Replicate (Beta)** als 3D-Provider: Pay-per-Use-Plattform mit
    tausenden gehosteten Modellen – eingebauter Katalog (TRELLIS,
    Hunyuan3D 2.0) plus freiem Feld für jede Replicate-Kennung
    (`owner/name` oder `owner/name:version`); Bilder gehen über die
    Replicate-Files-API (kein Data-URI-Limit), die Provider-Auswahl im
    3D-Tab ist jetzt eine umbrechende Chip-Leiste (8 Provider)
  - **fal.ai-Marktplatz (Beta)** als 3D-Provider: Bild→3D mit
    wählbarem Marktplatz-Modell – TRELLIS (Microsoft, ab wenigen
    Cent), TRELLIS.2, TripoSR (am schnellsten), Hunyuan3D 2.0 und
    Hunyuan3D 3.1 Pro (Tencent, Spitzenklasse) – plus freiem Feld für
    eigene fal.ai-Modell-IDs; Bezahlung pro Lauf (Pay per Use), ideal
    für Game-Assets wie Fahrzeuge und Gebäude. Rigging, Symmetrisieren
    und Textur-Schärfen übernimmt die eigene lokale
    Veredelungs-Pipeline
  - **Eigener lokaler 3D-Generator** (Standard, ohne API, kostenlos):
    baut direkt in der App ein farbiges 360°-Modell (Visual Hull aus
    bis zu 4 Ansichten mit geglätteter Surface-Nets-Oberfläche);
    eigener glTF-2.0-Writer in Dart. Die Ansichtsfarben werden weich
    nach Blickrichtung gemischt, bilinear abgetastet (keine harten
    Farbnähte) und standardmäßig als **hochauflösender Textur-Atlas**
    (2048 px, je Dreieck ein eigener Pixelblock) statt als
    Vertex-Farben gespeichert – die Farbschärfe hängt damit nicht mehr
    an der Netzdichte; einstellbar sind Detailgrad (bis 160er-Raster),
    Glättung, Ziel-Polygonzahl (Dezimierung per Vertex-Clustering)
    und die PBR-Oberfläche (matt bis metallisch) – jede Option mit
    Infotext.
    Optional **KI-Tiefenschätzung**: Per Bild-KI geschätzte
    Tiefenkarten formen Mulden und Vertiefungen in Vorder- und
    Rückseite – über die Silhouetten-Grenze des Visual Hull hinaus
  - **Eigenes Auto-Rigging** für Lokal und Stability: ein
    Standard-Skelett wird komplett lokal berechnet (Heuristik aus der
    Bounding Box, Abstands-Skinning) und direkt ins GLB eingebaut –
    für Animationstests in Blender/Unity/Godot. Wählbare Figurtypen:
    Mensch/Roboter/Fantasy (T-Pose, 17 Gelenke), Vierbeiner (19),
    Insekt/Mehrbeiner (22), Vogel mit gespreizten Flügeln (13),
    Schlange (8), Fisch (6) und **Fahrzeug mit automatischer
    Rad-Erkennung** (Achsen werden aus der bodennahen Geometrie
    erkannt – vom Einrad über Fahrrad/Motorrad mit Einzelrädern bis
    Auto, Bus und LKW mit bis zu 5 Achsen/10 Rädern); die passende
    Rig-Pose fließt automatisch in die KI-erzeugten Ansichten ein.
    Die **Blickrichtung wird automatisch erkannt** (Stability-Modelle
    schauen Richtung −z, lokale Richtung +z; zusätzlich geometrische
    Schätzung über Fußspitzen und Kopfposition): Skelett,
    Testanimationen (z. B. Verbeugen nach vorn) und die Startansicht
    im Viewer richten sich nach dem Gesicht der Figur
  - **Modell drehen im Viewer**: 90°-Schritte um X, Y oder Z direkt in
    der Werkzeugleiste – dreht die **echte Geometrie**, wirkt also auch
    im Export für Druck und Engine. Hilft vor allem bei importierten
    Dateien aus Blender oder CAD, die meist z-up statt y-up stehen und
    dadurch auf der Seite liegen; bei geriggten Modellen wird die
    ungeriggte Fassung gedreht und das Skelett neu eingebaut
  - **Rig-Anpassungen bleiben erhalten**: Beim erneuten Öffnen des
    Editors werden die zuletzt verschobenen Gelenke aus dem geriggten
    Modell zurückgelesen (statt das Standard-Skelett neu zu rechnen) –
    Bewegungen prüfen und weiter feinjustieren ist damit ein
    durchgängiger Ablauf. „Zurücksetzen" stellt weiterhin die
    Automatik her
  - **Wirkungsbereich sichtbar**: Ein ausgewähltes Gelenk zeigt seinen
    Wirkungs-Radius als blaue Kugel – so ist zu sehen, wie viel
    Geometrie es mitnimmt; der Regler „Einflussbereich" skaliert genau
    diese Kugel und ist jetzt dauerhaft eingeblendet (ohne Auswahl
    deaktiviert mit Hinweis). Damit lassen sich etwa Daumen und Finger
    von Fäustlingen gezielt an die Hand binden
  - **Gelenk-Anleitung im Rig-Editor**: Ein angetipptes Gelenk erklärt
    sich selbst – wo der Punkt sitzen soll (z. B. „Handwurzel, wo die
    Hand am Unterarm ansetzt; bei Fäustlingen den Punkt in die
    Handmitte legen und den Einflussbereich vergrößern") und was er
    steuert
  - **Animationen direkt in der App**: Die 3D-Vorschau spielt
    Animations-Clips aus der GLB-Datei ab (CPU-Skinning im eigenen
    Renderer) und bringt eingebaute Testanimationen je Figurtyp mit
    (Gehen, Winken, Vierbeiner-Gang, Flügelschlag, Krabbeln,
    Schlängeln, Schwimmen, Fahren mit drehenden Rädern, Wackeltest);
    das Skelett lässt sich per
    Knopf grafisch über dem Modell einblenden. Die Testanimationen
    können optional als echte, loopbare glTF-Clips mit ins exportierte
    GLB gebacken werden („GLB + Testanimationen exportieren“). Die
    Vorschau zeigt auch die PBR-Oberfläche des Materials: Glanzlichter
    je nach Metall- und Rauheitswert (matt bis metallisch)
  - **STL-, 3MF- und OBJ-Export**: Der Viewer exportiert Modelle als
    binäres STL (nur Form) oder als 3MF **mit Farben** (Material-
    Palette je Dreieck) – jeweils aufs Druckbett gedreht, zentriert
    und auf die gewünschte Größe in mm skaliert, mit eingebauter
    **Wasserdichtheits-Prüfung** im Export-Dialog; dazu OBJ mit
    Vertexfarben für Blender/MeshLab. Druck: Datei in einen Slicer
    laden (PrusaSlicer, Cura, Bambu Studio …) oder beim
    Farbdruck-Dienst hochladen
  - **Viewer als Drop-Ziel**: eigene GLB-, STL- und OBJ-Dateien lassen
    sich per Drag & Drop in den 3D-Tab oder direkt in den Viewer
    ziehen und werden dort angezeigt (STL/OBJ werden intern nach GLB
    gewandelt)
  - **Rig-Editor**: Bei selbst geriggten Modellen (Lokal/Stability)
    lassen sich die Gelenke im Viewer manuell verschieben („Rig
    anpassen“) – mit Symmetrie-Modus (links/rechts gespiegelt),
    unsichtbarem Raster-Fang (Standard an), Mehrfachauswahl per
    Antippen (gemeinsames Verschieben) und festen Ansichten
    Vorn/Hinten/Seiten; Knochen und Skin-Gewichte werden beim
    Übernehmen neu berechnet. Im Viewer werden Animationen über eine
    seitliche Icon-Leiste gewählt, und „Animationen ans Modell hängen“
    bettet die Testanimationen dauerhaft in die GLB ein.
    Die automatische Vermessung erkennt Schulterhöhe an seitlich
    abstehenden Armen und auch feine Beinspalte (Belegungsraster)
  - **Galerie mit 3D-Modellen**: Generierte Modelle erscheinen neben
    den Bildern in der Galerie (3D-Abzeichen, Vorschaubild, ein Tipp
    öffnet den Viewer); nach der Generierung zeigt der 3D-Tab den
    Token-Verbrauch der Bild-KI-Schritte und das Restguthaben des
    Providers an
  - **Lokale Veredelungs-Pipeline** (Stability): Nachbearbeitung nach
    Profi-Vorbild, komplett in der App ohne Zusatzkosten – Fahrzeuge
    aus Dreiviertelansichten werden automatisch **gerade ausgerichtet**
    (Hauptachsen-Analyse; danach greift die Rad-Erkennung), und auf
    Wunsch wird die vom Foto abgewandte, verwaschene Modellhälfte
    durch die **gespiegelte bessere Hälfte ersetzt** (Symmetrisierung
    für Fahrzeuge und symmetrische Motive)
  - **Modellwahl mit Kosten-/Qualitätsanzeige**: Das KI-Modell wird
    direkt im Generator- und im 3D-Tab gewählt; eine grafische Anzeige
    daneben zeigt die Qualitätsstufe (5er-Skala) und die geschätzten
    Gesamtkosten pro Lauf (alle Bild-KI-Schritte plus 3D-Dienst,
    aufgeschlüsselt; Schätzwerte laut Preisliste)
  - **Erstellungsnachweis (PDF)**: Zu jedem generierten Bild (Knopf
    unter dem Ergebnis) und 3D-Modell (Knopf am Ergebnis und im
    Export-Menü des Viewers) sowie **zu jedem Galerie-Eintrag**
    (Nachweis-Knopf auf der Kachel, mit dem gespeicherten
    Original-Erstellungszeitpunkt) lässt
    sich ein druckbares PDF erzeugen, das Zeitpunkt, Ersteller,
    KI-Dienst/Modell, Eingabe und die **SHA-256-Prüfsumme** der Datei
    dokumentiert – mit Unterschriftszeile zum Ausdrucken. Die
    Prüfsumme verknüpft Nachweis und Datei eindeutig; zusammen
    aufbewahrt dient das als Beleg der Eigenerstellung (keine
    notarielle Beglaubigung)
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
- **fal.ai** (3D-Bereich, Pay per Use, Startguthaben):
  <https://fal.ai/dashboard/keys>
- **Rodin / Hyper3D** (3D-Bereich, Bezahlung nach Verbrauch):
  <https://hyper3d.ai/api>
- **Replicate** (3D-Bereich, Bezahlung pro Lauf):
  <https://replicate.com/account/api-tokens>

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
