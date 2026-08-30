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
  - Batch-Generierung (1–4 Bilder pro Anfrage) – immer verschiedene
    Varianten desselben Prompts: OpenAI und Gemini würfeln je Bild neu,
    bei Stability und der eigenen GPU zählt der Seed pro Bild hoch
  - **Massenprompt**: ein Text mit den Beschreibungen vieler Bilder,
    die nacheinander erzeugt, unter ihrem Namen gespeichert und in der
    Galerie über die Suche wiedergefunden werden; Vorlage und Prüfung
    richten sich nach dem gewählten Bild-Modell, und jedes Bild bekommt
    seinen eigenen Negativ-Prompt (siehe unten)
  - Negativ-Prompt für **jedes** Modell – bei GPT-Image und Gemini
    hängt die App ihn als Satz an den Prompt, weil diese Modelle kein
    Negativ-Feld haben
  - Seed (reproduzierbare Bilder) und 16 Style-Presets (Stability AI)
  - Stil-Vorlagen per Klick (fotorealistisch, Ölgemälde, Logo, 3D-Render …)
  - **Prompt-Vorlage für das gewählte Modell**: ein fertiger Auftrag zum
    Kopieren, mit dem eine Prompt-KI genau in der Schreibweise
    schreibt, die dieses Modell versteht – gegliedertes Briefing bei
    GPT-Image/Gemini, gewichtete Stichwortkette samt Negativ-Prompt bei
    Stable Diffusion (siehe unten)
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
  - **Server-Auswahlliste mit Startknopf**: In den Einstellungen steht
    oben „Keiner“, darunter jeder auf diesem PC eingerichtete Server
    (samt Ordner). Ein Klick auf **„Server starten"** startet ihn im
    Hintergrund, trägt die Adresse ein und wartet, bis er antwortet –
    kein PowerShell-Fenster mehr nötig. Die Liste enthält sowohl die
    vom Assistenten angelegten als auch von Hand eingerichtete
    Installationen, die neben dem Standardordner gefunden werden.
    **„Läuft bereits"** steht auf dem Knopf nur, wenn der Server unter
    dieser Adresse tatsächlich antwortet – und zwar der richtige:
    Meldet sich dort der jeweils andere Server (beide auf demselben
    Port), sagt die Statuszeile das und der Startknopf bleibt
    bedienbar. Nach „Server-Dateien auffrischen" oder einer von Hand
    geänderten Adresse gilt der Zustand nicht mehr, der Knopf heißt
    wieder „Server starten"
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
    (eigener Server), „Höchste Detailtreue“ (Meshy 7 Ultra),
    „3D-Druck“ (lokaler Generator, 128er-Raster, ohne Skelett) und
    **„Roblox-Figur“** (alle Grenzen des Roblox-Importers auf einmal,
    siehe unten); danach bleibt jede Option einzeln änderbar. Dazu **5 frei
    belegbare Plätze für eigene Vorlagen**: eine beliebige Kombination
    aus Anbieter, Modell, Qualitäts-Optionen, Rigging, Veredelung und
    Negativ-/Textur-Prompt unter eigenem Namen sichern, per Klick
    zurückholen und wieder löschen – bleibt auch nach einem Neustart
    erhalten
  - **Roblox-Vorlage samt Plattform-Prüfung**: setzt Polygonziel,
    1024er-Textur, T-Pose und Skelett auf die Grenzen des
    Roblox-Importers, hängt die Roblox-Regeln an die Prompt-Vorlage an
    und prüft das fertige Modell gegen alle harten Vorgaben –
    Dreiecke (20.000/10.000/4.000), ein Material je Mesh, ein UV-Satz
    in 0–1, Texturgröße, offene Kanten und die Rig-Regeln (Scale 1,
    Rotation 0, Wurzel im Ursprung, höchstens 4 Bones je Vertex)
    (siehe unten)
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
  - **Direkt aus Text zum 3D-Modell** (ohne Bild-Zwischenschritt):
    **Meshy**, **Tripo3D** und **Rodin** bauen aus der Beschreibung
    unmittelbar ein Modell; bei fal.ai steht dafür **Rodin 2.5
    (text-to-3d)** in der Modell-Liste. Bei Meshy/Tripo/Rodin lässt
    sich der Weg über KI-Ansichten zuschalten, wenn er detailtreuer
    ist – die Kostenanzeige rechnet beide Wege ehrlich durch. Lokal
    entsteht Text→3D aus der Kette eigener Bild-Server → eigener
    3D-Server (siehe nächster Punkt)
  - **Text→Bild auf der eigenen GPU** (kostenlos, ohne Cloud): Der
    mitgelieferte Bild-Server (`server/local_image_server.py`) stellt
    Stable Diffusion über die eigene NVIDIA-Karte bereit – wählbar sind
    **SD 1.5** (~4 GB VRAM), **SDXL Turbo** (~7 GB), **SDXL** (~8 GB),
    **SD 3.5 Medium** (~10 GB) und **FLUX.1 schnell** (~16 GB). In der
    Modell-Liste des Bild-Tabs steht er als „Eigene GPU“; die
    Einrichtung übernimmt derselbe Assistent wie beim 3D-Server
    (Einstellungen → Eigener Bild-Server), ein Knopfdruck startet ihn.
    Zusammen mit einem lokalen 3D-Server läuft damit die **komplette
    Kette Text→Bild→3D auf dem eigenen Rechner** – ohne API-Schlüssel,
    ohne Kosten, ohne dass ein Bild den PC verlässt. Der Hintergrund
    wird serverseitig freigestellt (rembg), sodass die Ansichten mit
    echter Transparenz beim 3D-Teil ankommen
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
    direkt im Bild- und im 3D-Tab gewählt – **eine Liste über alle
    Anbieter hinweg** (OpenAI, Stability, Gemini). Die Auswahl setzt
    Anbieter und Modell in einem Schritt; ein Schlüssel-Symbol zeigt,
    wo noch kein API-Schlüssel hinterlegt ist. In den Einstellungen
    stehen deshalb nur noch die Schlüssel. Eine grafische Anzeige
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

## Zusehen, wie das Bild entsteht

Während eines Laufs zeigt die App eine Fortschrittsfläche statt eines
Kreisels – und der Unterschied zwischen „echt" und „Wartezeichen" wird
ausgesprochen statt kaschiert:

- **Eigene GPU**: eine **echte Live-Vorschau**. Der Server legt alle
  fünf Diffusionsschritte ein kleines Zwischenbild ab, die App holt es
  im Sekundentakt und zeigt das Motiv, wie es aus dem Rauschen
  auftaucht – mit Schrittzähler (`Schritt 15/30`). Möglich bei SD 1.5
  und SDXL; SD 3.5 und FLUX packen ihre Latents anders, dort steht das
  auch so da.
- **OpenAI, Gemini, Stability und die 3D-Dienste** liefern keine
  Zwischenstände, sie antworten erst mit dem fertigen Ergebnis. Dort
  läuft eine Aufbau-Grafik, die ausdrücklich als Wartezeichen
  beschriftet ist – **kein** vorgetäuschter Fortschritt und kein
  Fantasie-Motiv.
- Im **3D-Tab** kommt der Prozentwert dazu, den Meshy und Tripo
  melden, plus die verstrichene Zeit.

Im Massenlauf steht dieselbe Fläche unter dem Statusfenster und zeigt,
welches Bild gerade entsteht.

## Prompt-Vorlage für das gewählte Modell

Die Bild-Modelle lesen einen Prompt grundverschieden, und ein Prompt,
der bei einem hervorragend funktioniert, geht beim anderen daneben:

- **GPT-Image und Gemini** verstehen Sprache. Sie befolgen ein
  gegliedertes Briefing mit Abschnitten, ganzen Sätzen und
  ausdrücklichen Anweisungen – auch Verneinungen („kein Text im Bild").
- **Stable Diffusion** (Stability und eigene GPU) versteht keine
  Sprache, sondern gewichtet Stichworte. Gegliederte Briefings
  verwässern das Ergebnis, Verneinungen im Prompt bewirken oft das
  Gegenteil; sie gehören in den **Negativ-Prompt**. Dazu kommt die
  Textlänge: SD 1.5 und SDXL verarbeiten nur rund 75 Wörter, alles
  Weitere zählt weniger. FLUX und SD 3.5 vertragen deutlich mehr.

Deshalb steht im Tab **Bild** unter dem Prompt-Feld die Zeile
**„Prompt-Vorlage für <Anbieter · Modell>"** mit den Knöpfen
**Ansehen** und **Kopieren**. Kopiert wird ein fertiger Auftrag für
eine Prompt-KI (ChatGPT, Gemini, Claude …): Er nennt das Zielmodell,
die Schreibweise, die empfohlene Höchstlänge und – wo das Modell einen
auswertet – ein Beispiel für den Negativ-Prompt. Die Vorlage wechselt
automatisch mit, sobald oben ein anderes KI-Modell gewählt wird.

Ein Satz unter der Zeile fasst zusammen, worauf es bei diesem Modell
ankommt. Im Massenprompt-Modus gibt es dieselbe Vorlage – dort um das
Blockformat mit `NAME:`/`PROMPT:` ergänzt, sodass die Prompt-KI gleich
die ganze Liste in der richtigen Form ausgibt.

### Der Negativ-Prompt bei jedem Modell

Was mit dem Negativ-Prompt geschieht, hängt am Modell. Die App sagt es
unter dem Feld und in der Vorlage, und sie sorgt selbst dafür, dass er
ankommt:

- **Stability und eigene GPU** (außer die beiden unten) haben ein
  eigenes Negativ-Feld. Der Text geht unverändert dorthin.
- **GPT-Image und Gemini** kennen kein Negativ-Feld, verstehen aber
  Sprache. Die App hängt den Negativ-Prompt deshalb als Satz an die
  Beschreibung: `Do not include in the image: …`. Damit wirkt er.
- **SDXL Turbo und FLUX schnell** arbeiten ohne Guidance und werten
  einen Negativ-Prompt gar nicht aus. Hier muss das Unerwünschte
  positiv formuliert im Prompt stehen („empty grey background" statt
  „no props").

### Spielgrafik-Regeln (Gebäude-Assets)

Der Schalter **„Spielgrafik-Regeln (Gebäude-Assets)"** unter der
Vorlage ist für Bilder gedacht, die später als Asset auf einen
Karten-Knoten gesetzt werden. Er nimmt die Vorgaben in die Vorlage auf
und prüft sie beim Massenprompt mit:

- **Genau ein Gebäude je Bild** – sonst lässt sich das Asset nicht auf
  einen Knoten setzen.
- **Kein Boden unter dem Gebäude** – weder Platte noch Fleck: keine
  Terrasse, kein Pflaster, kein Mäuerchen, kein Sockel, aber auch kein
  Gras, keine Erde, kein Moos. Der Renderer malt den festgetretenen
  Erdsaum selbst um jedes Gebäude; ein mitgemalter Fleck läge darüber
  und hinterließe beim Freistellen eine harte Kante.
- **Kamera rund 35° von oben**, deutlich auf das Dach schauend, nicht
  auf die Fassade: Die Dachfläche füllt dann rund ein Drittel des
  Bildes. Die Bodenebene ist auf 0,62 verkürzt (ROWH 32 auf TILE 52);
  ein flach gesehenes Haus kippt neben dem Gelände und lässt sich
  nachträglich nicht reparieren.
- **Das erkennende Merkmal ausgeschrieben und weit vorn** – bei einer
  Bäckerei `large domed bread oven attached to the side wall`. Knapp
  genannt geht es unter: Aus `big domed stone oven` wurden zwei
  Schornsteine.
- **Grobes Mauerwerk**: große, weich geformte Steine, kein feines
  Mosaik. Das Bild wird im Spiel rund 13-fach verkleinert (eine
  Bäckerei ist nur etwa 78 Weltpixel hoch) – ein feines Mosaik
  zerfällt dabei zu Rauschen.

Bei GPT-Image und Gemini stehen die Sätze wörtlich in der Vorlage.
**Stable Diffusion bekommt etwas anderes**, und das aus Erfahrung: Die
erste Fassung übersetzte die Sätze eins zu eins in eine Stichwortkette
– 47 Wörter. Zusammen mit 12 Motivwörtern blieben dem Gebäude 20 % des
Prompts, und aus einer Bäckerei mit Kuppelofen wurden runde
Lehmkuppeln in Sandfarbe. Drei Formulierungen waren dabei aktiv
schädlich:

- **Mengenangaben** (`at most 15 stone courses over the wall height`).
  Das Modell zählt nicht; es sieht `stone courses` und macht mehr
  Stein.
- **Gradzahlen** (`camera elevation 35 degrees`). Kein Winkelbegriff.
- **`rounded boulders`**. Gemeint war grobes Mauerwerk, angekommen ist
  „Gebäude aus Findlingen".

Das zweite Bild traf Stil, Formensprache und Vereinzelung – und
scheiterte an zwei anderen Stellen, die beide in der Kette selbst
lagen:

- **Ein Kamera-Schlagwort reicht nicht.** `high angle isometric view`
  ergab fast die volle Fassade und vom Dach nur einen Streifen. Der
  Blickwinkel steht jetzt **dreifach** da: von hoch oben, auf das Dach
  herab, gekippte Draufsicht.
- **`centered on empty ground` holte den Bodenfleck zurück.** Das
  Modell malt, was dasteht, und `ground` stand da. Der Boden ist
  vollständig aus dem positiven Teil verschwunden; die Vereinzelung
  trägt jetzt `single isolated 3d building model`. Auch `diorama` ist
  gewandert – es bringt die Bodenplatte gleich mit und steht im
  Negativ-Block.

Die Kette lautet damit (34 Wörter, keine Zahl außer `3d`):

```
single isolated 3d building model, isometric view from high above,
looking down onto the roof, tilted top view, stylized game asset,
chunky rounded shapes, warm matte colors, soft golden hour light,
plain grey background
```

Davor gehören **rund 20 Wörter Motiv**: Gebäudeart, dann sofort das
erkennende Merkmal ausgeschrieben und mit Ort am Bau, danach Wände,
Dach, ein bis zwei Requisiten. Zusammen bleibt der Block unter
60 Wörtern – die Grenze, die für SDXL jetzt auch in der Prüfung steht
(vorher 100).

**„Beispiel einfügen"** setzt bei eingeschalteten Spielgrafik-Regeln
genau diesen erprobten Block ein:

```
NAME: bld-02-bakery
PROMPT: medieval bakery, large domed bread oven attached to the side wall,
timber framed plaster walls, thatched roof, stone chimney,
single isolated 3d building model, isometric view from high above,
looking down onto the roof, tilted top view, stylized game asset,
chunky rounded shapes, warm matte colors, soft golden hour light,
plain grey background
NEGATIV: grass patch, dirt patch, soil, moss, ground plate, base, disc, platter,
pedestal, platform, terrain, island, diorama, miniature scene, fence, garden,
village, many houses, second building, street, path, trees, bushes, terrace,
paving, low wall, steps, onion dome, blue-grey slate, glossy, harsh shadows,
front view, side view, eye level, low camera angle, text, watermark, people,
blurry, low quality
```

19 Wörter Motiv, 34 Wörter Stil, zusammen 53.

## Massenprompt: viele Bilder in einem Lauf

Im Tab **Bild** oben auf **Massenprompt** umschalten. Statt einer
einzelnen Beschreibung steht dort ein Text mit den Beschreibungen
mehrerer Bilder; die App erzeugt sie nacheinander und legt jedes unter
seinem Namen ab. So entstehen 40 Bilder in einem Rutsch, ohne dass man
dabeisitzen muss.

**Aufbau.** Jedes Bild ist ein Block, getrennt durch eine Zeile aus drei
Bindestrichen:

```
NAME: burg-01
PROMPT: A medieval castle on a cliff at night, full moon, cinematic lighting
NEGATIV: people, text, watermark
---
NAME: burg-02
REF: burg.png
PROMPT: The same castle at noon, clear blue sky, warm sunlight
```

- `NAME:` – kurzer, eindeutiger Name. Unter ihm wird das Bild
  gespeichert und in der Galerie gefunden. Leerzeichen und Umlaute
  werden ersetzt (`Burg Nacht` → `Burg-Nacht`); fehlt der Name, heißt
  das Bild `bild-01`, `bild-02` …
- `PROMPT:` – die Bildbeschreibung, darf über mehrere Zeilen gehen.
- `REF:` – optional, die Dateinamen der Referenzbilder für genau
  dieses Bild (mehrere durch Komma). Die Bilder müssen unter
  „Referenzbilder" geladen sein; Groß-/Kleinschreibung und Dateiendung
  sind egal.
- `NEGATIV:` – optional, was **dieses eine** Bild nicht enthalten
  soll. Ist die Zeile leer, gilt der Negativ-Prompt aus dem Formular.
  Wie er beim gewählten Modell ankommt, steht oben unter
  [„Der Negativ-Prompt bei jedem Modell"](#der-negativ-prompt-bei-jedem-modell)
  – bei GPT-Image und Gemini wird er an genau diesen Prompt gehängt,
  nicht an alle.

**Den Massenprompt von der KI schreiben lassen.** Der Knopf **„Vorlage
für Prompt-KI kopieren"** legt ein fertiges Briefing in die
Zwischenablage – inklusive der Namen der gerade geladenen
Referenzbilder. Die Vorlage ist immer auf das oben gewählte Bild-Modell
zugeschnitten: Sie nennt das Modell, verlangt für GPT-Image und Gemini
ganze Sätze und für Stable Diffusion eine Stichwortkette, gibt die
Höchstlänge in Wörtern vor und sagt, was mit `NEGATIV:` geschieht. Auch
das eingefügte Beispiel wechselt mit dem Modell. Wird oben ein anderes
Modell gewählt, ändert sich die Vorlage sofort mit – **„Vorlage
ansehen"** zeigt sie, ohne sie zu kopieren.

**Prüfen vor dem Start.** **„Prüfen"** liest den Text und meldet mit
grünem Haken, wie viele Bilder erkannt wurden und wie viele davon ein
Referenzbild nutzen. Blockierend sind doppelte Namen, fehlende
Beschreibungen und genannte, aber nicht geladene Referenzbilder –
jeweils mit Zeilennummer. Dazu kommen Hinweise, die den Lauf nicht
aufhalten, aber die Ergebnisse deutlich verbessern:

- Beschreibungen, die länger sind als für das gewählte Modell sinnvoll
  (mit der längsten Wortzahl und den betroffenen Namen).
- Verneinungen im `PROMPT:` und gegliederte Briefings mit
  Überschriften, wenn das Modell eine Stichwortkette braucht.
- `NEGATIV:`-Zeilen, die das Modell verwirft (SDXL Turbo, FLUX) – oder
  umgekehrt der Hinweis, dass kein einziger Block eine hat, obwohl das
  Modell sie auswertet.
- Bei eingeschalteten Spielgrafik-Regeln: Bodenplatten, ein möglicher
  zweiter Baukörper, jedes Bodenwort im `PROMPT:` (`empty ground`,
  `grass`, `soil` …) und eine fehlende Aufsicht – für
  Diffusions-Modelle wird dabei `isometric view from high above`
  verlangt, für GPT-Image und Gemini die Gradangabe.
- Eine Aufsicht, die nur als Schlagwort dasteht: Fehlt die
  Blickrichtung auf das Dach, wird das gemeldet – genau daran ist das
  zweite Bäckerei-Bild gescheitert.
- `NEGATIV:`-Zeilen, die eine der drei Gruppen nicht abdecken:
  Bodenfleck (`grass`, `dirt`, `soil`, `moss`), Bodenplatte (`plate`,
  `platform`, `pedestal` …) und flacher Blickwinkel (`front view`,
  `side view`, `eye level`).
- Modelle, die den Negativ-Prompt gar nicht auswerten (SDXL Turbo,
  FLUX): Bodenfleck und zweites Gebäude lassen sich dort nicht
  ausschließen – für Gebäude-Assets besser SDXL Base oder SD 3.5.
- Ebenfalls nur bei Diffusions-Modellen: Mengenangaben, Gradzahlen,
  das Wort `boulders` und `diorama` – sowie Stil-Angaben, die schon in
  den ersten 20 Wörtern stehen und damit das Motiv verdrängen.

Erst nach dem grünen Haken lässt sich der Lauf starten; jede Änderung
am Text macht die Prüfung wieder ungültig.

**Während des Laufs** zeigt das Statusfenster rechts, welches Bild
gerade entsteht, wie viele fertig sind, die vergangene Zeit, den
Schnitt je Bild und daraus die geschätzte Restzeit. **„Abbrechen"**
stoppt nach dem laufenden Bild – alles bereits Erstellte bleibt
erhalten. Fehlgeschlagene Bilder halten den Lauf nicht an, sie werden
unten mit Grund aufgeführt.

**Danach** liegen alle Bilder in der Galerie, mit ihrem Namen über der
Beschreibung. Das Suchfeld oben in der Galerie findet sie über Name
oder Beschreibung; heruntergeladen werden sie ebenfalls unter ihrem
Namen. Gibt es einen Namen schon aus einem früheren Lauf, hängt die App
`-2`, `-3` … an, statt das alte Bild zu überschreiben.

Pro Block entsteht genau ein Bild – die Einstellung „Anzahl Bilder"
gilt im Massenlauf nicht, sonst passten Name und Ergebnis nicht mehr
zusammen. Höchstens 200 Bilder pro Lauf. Kosten: Anzahl der Blöcke ×
Preis des gewählten Modells; auf der eigenen GPU 0 $.

## Roblox: Figuren, die der Importer annimmt

Im Tab **3D** gibt es unter „Vorlagen" den Knopf **„Roblox-Figur"**. Er
setzt Anbieter, Ziel-Polygonzahl, Textur-Größe, Skelett und T-Pose in
einem Rutsch auf die Grenzen des Roblox-Importers, blendet die
Plattformregeln ein und hängt sie an die Prompt-Vorlage an. Danach
lässt sich weiterhin jede Option einzeln ändern.

### Was Roblox annimmt

Als Datei nimmt Roblox `.fbx`, `.gltf`/`.glb` und `.obj`. **FBX** ist
der Standardfall, weil es Materialdaten, Rig und Bone-Transforms in
einer Datei trägt. **glTF** bündelt die Texturen und wird von Studio
direkt gelesen, hat dort aber eingeschränkte Rig-Unterstützung –
`.glb` ist dabei kein eigenes Format, sondern dieselbe Spezifikation,
nur binär geschrieben. **OBJ** passt nur für einfache statische Props.
Die App exportiert GLB und OBJ; für eine gerigte Figur führt der Weg
über Blender (GLB öffnen, als FBX ausgeben).

### Die Grenzen, an denen KI-Assets scheitern

| Regel | Grenze |
| --- | --- |
| Dreiecke **je Mesh** | höchstens **20.000**, Arbeitsziel unter **10.000** |
| UGC-Accessoires | höchstens **4.000** Dreiecke je Mesh |
| Material | genau **eines** je Mesh (sonst Texture-Atlas nötig) |
| UVs | **ein** Satz, vollständig im **0–1**-Raum |
| Texturen | PNG, JPG, TGA, BMP, höchstens **1024×1024** |
| Geometrie | wasserdicht, keine offenen Löcher, keine Backfaces, keine Nullstärke, möglichst Quads statt N-Gons |

Genau daran scheitern KI-Modelle zuverlässig: Meshes aus Meshy oder
Tripo starten oft bei mehreren hunderttausend Dreiecken. Deshalb
begrenzt die Vorlage die Polygonzahl **schon bei der Generierung** –
das macht deutlich weniger Ärger als nachträgliches Dezimieren:

- **Meshy**: `target_polycount` (in der App „Detailgrad (Polygone)")
  bzw. der Low-Poly-Modus.
- **Tripo**: `face_limit` – neu als Auswahl **„Face-Limit (Flächen)"**
  mit den Stufen 20.000 / 10.000 / 4.000.
- **Rodin**: `quality_override` (in der App „Polygonzahl").
- **Stability und lokaler Generator**: Ziel-Polygonzahl bzw.
  Ziel-Dreiecke.

Reicht das nicht, hilft nur noch Blender: Modifier **Decimate**.

**Quads sind keine Dreiecke.** Roblox zählt Dreiecke, die Anbieter
zählen Polygone. Bei eingeschalteter Quad-Topologie wird aus jedem
Viereck beim Export ein Paar Dreiecke – ein „10.000er"-Quad-Netz landet
also bei 20.000 Dreiecken, genau auf der harten Grenze. Die App rechnet
das um: Das Ziel ist immer in **Dreiecken** angegeben, und der Anbieter
bekommt bei Quad-Topologie die halbe Zahl. Die Roblox-Karte schreibt
aus, was gerade tatsächlich gesetzt ist, z. B. „Ziel: 10.000 Dreiecke
(Budget 5.000 Polygone). Aktuell eingestellt: Meshy „target_polycount"
= 5.000".

**Die Einheiten der Anbieter meinen nicht dasselbe.** `face_limit` bei
Tripo, `target_polycount` bei Meshy und `quality_override` bei Rodin
sind drei verschiedene Größen; Rodin arbeitet zusätzlich mit
Qualitätsstufen, eine Zahl darauf abzubilden bleibt eine Näherung. Die
Stability-Auswahl kennt nur feste Stufen – genommen wird die größte,
die unter dem Budget bleibt. Was beim gewählten Anbieter herauskommt,
steht deshalb im Klartext in der Karte.

**Die Grenze gilt je Mesh, nicht fürs Modell.** Ein Modell aus fünf
Teilen à 6.000 Dreiecken geht durch, ein einzelnes Teil mit 21.000
nicht. Die Prüfliste meldet deshalb das größte Mesh und nennt die
Summe nur als Leistungshinweis. Dasselbe gilt für die Materialregel:
Entscheidend ist, dass **je Mesh** genau eines vorliegt.

### Figur oder UGC-Accessoire

Die Vorlage deckt beide Fälle ab; umgeschaltet wird in der
Roblox-Karte. Der Unterschied ist größer als nur die Dreieckszahl,
deshalb stellt die App gleich mit um:

| | Figur / Prop | UGC-Accessoire |
| --- | --- | --- |
| Dreiecke | 20.000 hart, Ziel unter 10.000 | 4.000 |
| Skelett | Zweibeiner-Rig | keins – starres Netz |
| Pose | T-Pose | keine |
| Motivart | Figur (Vorderansicht) | Objekt (Dreiviertelansicht) |
| Prompt-Zusatz | genau eine Figur, T-Pose | nur das Teil allein, keine Figur |

Ein Hut, eine Frisur oder ein Rucksack ist kein kleiner Charakter: Es
ist ein einzelnes starres Netz, das in Studio über einen **Handle**
mit einem **Attachment** (z. B. `HatAttachment`) am Avatar befestigt
wird – dabei hilft das **Accessory Fitting Tool**. Ein Skelett gehört
da nicht hinein; die Prüfung meldet es deshalb als Warnung.

Die Ausnahme ist **Layered Clothing** – Kleidung, die sich mit dem
Körper verformt. Die braucht ein Rig *und* zusätzlich Innen- und
Außen-Cage-Meshes in derselben Datei. Die erzeugt diese App nicht;
dafür führt der Weg über Blender.

### Bei gerigten Figuren zusätzlich

- Jeder Bone braucht **Scale 1,1,1** und **Rotation 0,0,0**.
- Der **Wurzelknochen** sitzt bei **0,0,0** und beeinflusst keine
  Vertices.
- Kein Vertex darf von mehr als **vier Bones** beeinflusst werden.
- Das Modell muss in **T-Pose** stehen. Die Vorlage hängt dafür
  `standing in T-pose, arms stretched out` an den Prompt.
- Beim Import wählt man **R15**, **Custom** oder **No Rig**; Studio
  versucht, den Typ aus der Datei zu erkennen. Ein vollwertiger
  R15-Avatar braucht **15 einzeln benannte Körperteil-Meshes** – ein
  einteiliges Modell importiert man als „Custom".

### Prüfen vor dem Hochladen

Am fertigen Modell führt das Export-Menü den Punkt **„Für Roblox
prüfen …"**. Die App liest die GLB und legt eine Prüfliste vor:
Dreiecke, Materialzahl, offene Kanten, UV-Sätze und UV-Spanne,
Texturgrößen sowie – wenn ein Skelett vorhanden ist – Einflüsse je
Vertex, Bone-Transformationen und der Wurzelknochen. Jeder Punkt sagt,
was zu tun ist; erledigte Punkte stehen mit grünem Haken dabei, damit
man sieht, was schon stimmt. Umschalten zwischen **Figur/Prop**
(20.000 hart, 10.000 Ziel) und **UGC-Accessoire** (4.000) geht in der
Roblox-Karte; die Prüfliste passt sich mit an – bei Accessoires kommen
der Hinweis auf Handle und Attachment sowie die Warnung vor einem
überflüssigen Skelett dazu, T-Pose und Rig-Typ entfallen.

Dazu kommen drei Prüfungen, die über die reine Löcher-Suche
hinausgehen:

- **Skalierung.** Die häufigste Importpanne: glTF rechnet laut
  Spezifikation in Metern, der Importer steht per Vorgabe auf *Stud*.
  Die App liest die Bounding Box, rechnet mit 1 Stud ≈ 0,28 m um und
  sagt, was herauskommt – Vergleichsmaßstab ist ein Standard-Charakter
  mit rund 5 Studs. Bei einem 1,4 m hohen Modell heißt das: Scale Unit
  auf *Meter* stellen, sonst baut Studio etwas Kniehohes.
- **Backfaces und Normalen.** Offene Kanten allein decken das nicht ab.
  Die App misst die Kantenrichtungen: Gegenläufig gewickelte Nachbarn
  ergeben unsichtbare Flächen (→ *Recalculate Outside*), ein negatives
  Gesamtvolumen heißt, alle Normalen zeigen nach innen (→ *Flip*).
- **Nullstärke.** Aus Volumen und Bounding Box fällt auf, wenn das
  „Modell" eine Platte ohne Dicke ist – genau der Fehler, vor dem der
  Prompt-Block bei Umhängen, Schleiern und Netzen warnt (→ *Solidify*).
  Degenerierte Dreiecke werden mitgezählt.

Drei Dinge kann die App **nicht** messen und listet sie deshalb als
Hinweis:

- ob das Modell wirklich in **T-Pose** steht,
- welcher **Rig-Typ** beim Import zu wählen ist,
- ob **Quad-Topologie** geliefert wurde – glTF speichert ausschließlich
  Dreiecke, die Vierecke stehen schlicht nicht in der Datei. Die
  angezeigte Zahl ist die Dreieckszahl nach der Triangulierung, also
  genau das, was Roblox zählt.

**Die Prüfung gilt für die GLB.** Geht das Modell für ein Rig über
Blender nach FBX, ändern sich genau dort Dreieckszahl und
Bone-Transforms. Die Prüfliste sagt das am Ende und nennt, was in
Blender gegenzuprüfen ist: Statistik-Overlay für die Dreiecke, N-Panel
→ Item → Transform für Scale 1,1,1 und Rotation 0,0,0 der Bones,
notfalls Object → Apply → All Transforms.

### Was der Prompt beitragen kann

Die Roblox-Vorlage hängt an die kopierbare Prompt-Vorlage einen Block
mit genau den Punkten an, die ein Bild- oder 3D-Prompt beeinflusst:
genau eine Figur ohne Sockel, T-Pose, geschlossene massive Formen mit
sichtbarer Dicke (keine hauchdünnen Umhänge, Schleier, Netze oder
Zäune), keine losen Kleinteile, eine kompakte Silhouette – bei 10.000
Dreiecken gehen feine Rüschen ohnehin verloren – wenige klar
getrennte Farbflächen für die eine 1024er-Textur und keine Schrift
oder Markenbezüge.

### Von der geriggten Figur zur Spielfigur

Für eine **Figur** reicht die GLB nicht: Mesh- und Animationsimport
läuft bei Roblox über **`.fbx`**. GLB direkt geht für Props, nicht für
den Rig-Weg.

**Der Schritt, an dem alles hängt, sind die Knochennamen.** Man muss
die Figur *nicht* in 15 MeshParts zerschneiden — es reicht, die Knochen
nach der R15-Konvention zu benennen und auf ein einzelnes Mesh zu
skinnen. Der Wurzelknochen heißt dabei **`HumanoidRootPart`**, nicht
„HumanoidRootNode":

```
HumanoidRootPart
LowerTorso, UpperTorso, Head
LeftUpperArm,  LeftLowerArm,  LeftHand
RightUpperArm, RightLowerArm, RightHand
LeftUpperLeg,  LeftLowerLeg,  LeftFoot
RightUpperLeg, RightLowerLeg, RightFoot
```

Tripos Auto-Rig liefert mit `spec: "mixamo"` Namen wie
`mixamorig:Hips`, der eigene Auto-Rigger `Hips`, `Chest`,
`Shoulder_L`. **Das Umbenennen nimmt die App ab**: Export-Menü →
**„Für Roblox vorbereiten …"**. Sie erkennt Mixamo-Namen, die eigenen
und die geläufigen Schreibweisen, zieht einen `HumanoidRootPart` im
Ursprung über der Hüfte ein (ohne Gewichtung, wie verlangt) und sagt,
welche der 15 Gelenke danach noch fehlen. Knochen ohne R15-Gegenstück
(Finger, ein zweiter Wirbel) behalten ihren Namen — das ist richtig so.

Gespeichert werden vier Dateien:

| Datei | Wofür |
| --- | --- |
| `…​.glb` | Das Modell, Knochen bereits auf R15 benannt |
| `…​_blender_fbx.py` | Blender-Skript: macht daraus die FBX |
| `…​_studio.lua` | Luau für die Befehlsleiste in Roblox Studio |
| `…​_ANLEITUNG.txt` | Die Schritte, auch zum Teilen mit Freunden |

**FBX erzeugen.** `blender --background --python …_blender_fbx.py`.
Das Skript nimmt die drei Stellen ab, an denen es sonst schiefgeht:
Transformationen einfrieren (Scale 1,1,1, Rotation 0,0,0 an jedem
Knochen), höchstens vier Knochen je Vertex, keine leeren Endknochen.

**Zwei Importwege, zwei Ergebnisse.** In Studio unter Avatar →
3D-Importer:

- **Custom** → ein Modell auf einem einzelnen Mesh, das die aktuellen
  Katalog-R15-Animationen abspielt. Laufen, Springen, Emotes
  funktionieren, ohne eine einzige Animation selbst zu bauen.
- **R15 / Rthro / Rthro Slender** → ein Humanoid-Rig, der als
  StarterCharacter taugt.

**Die drei Korrekturen** für den zweiten Weg macht das Studio-Skript:

1. `HumanoidRootPart` und das importierte MeshPart verschweißen.
2. `Humanoid.AutomaticScalingEnabled` aus und die Hip Height von Hand
   eintragen — sonst steht die Figur nicht sauber auf dem Boden. Der
   Wert lässt sich im Dialog vorwählen.
3. `CanCollide` am MeshPart aus, die Kollision übernimmt der
   `HumanoidRootPart`. **Diese dritte wird gern vergessen** und ist die
   Ursache dafür, dass Figuren an Kanten hängenbleiben.

**Einsetzen.** Ist der Schalter „Als Startfigur einsetzen" an, sichert
das Skript eine vorhandene Startfigur zuerst nach
`ServerStorage.StarterCharacter_Sicherung_<Zeitstempel>`, benennt das
Modell in `StarterCharacter` um und hängt es nach `StarterPlayer`.
Alles unanchored, `PrimaryPart` zeigt auf `HumanoidRootPart`.
Zurücknehmen geht über die Sicherung. Danach Playtest starten — ab dann
spawnt man als die eigene Figur.

**Mit Freunden teilen.** Datei → Auf Roblox veröffentlichen. Danach im
Creator-Dashboard: das Erlebnis privat lassen und Freunde unter
„Zugriff" als Tester hinzufügen, oder es auf „Öffentlich" stellen und
den Link teilen. Gemeinsam bearbeiten geht über Team Create.

**Rig-Hygiene** prüft die App mit: eingefrorene Transformationen
(Scale 1,1,1, Rotation 0,0,0), Wurzelknochen bei 0,0,0 ohne Gewichtung,
höchstens vier Bones je Vertex — und neu die R15-Benennung. Alles davon
ist aus der Datei messbar; nur die T-Pose nicht, die bleibt ein
Hinweis.

**Was erfahrungsgemäß hakt** sind nicht der Import, sondern **eigene
Animationen aus Blender**: Die brechen auch bei korrektem Rig oft,
während der StarterCharacter einwandfrei läuft. Deshalb zuerst mit den
Katalog-Animationen testen — laufen die, stimmen Rig und Benennung.

**Was die App nicht kann, und warum:** Eine FBX schreiben (ein eigener
FBX-Schreiber ließe sich hier nicht gegen Roblox testen — dafür das
Blender-Skript) und die Figur selbst in einen Roblox-Platz setzen. Ein
Platz verweist auf ein **hochgeladenes** MeshPart (`rbxassetid://…`);
das Hochladen samt Moderation passiert in Studio. Deshalb das
Studio-Skript statt eines halben Versprechens.

**Roblox-Installation.** Der Dialog sucht Roblox Studio an den üblichen
Stellen (`%LOCALAPPDATA%\Roblox\Versions`, Programme, unter macOS
`/Applications`) und zeigt Pfad und Fassung an; ein Knopf öffnet den
Ordner. Wird nichts gefunden, ändert das nichts am Paket — Studio ist
kostenlos unter create.roblox.com.

### Lizenz und Moderation

Ein Roblox-Upload ist eine **Veröffentlichung auf fremder Plattform**.

Bei den **API-Anbietern** (OpenAI, Gemini, Stability, Meshy, Tripo,
fal.ai, Rodin, Replicate) gilt deshalb: nur mit **bezahlten Credits**
generieren, nicht mit Gratis-Kontingenten – deren Lizenzbedingungen
decken eine Veröffentlichung in der Regel nicht ab.

Beim **lokalen Generator und beim eigenen Server** greift diese Regel
nicht; dort entscheidet die Lizenz des verwendeten Modells. Die ist
nicht überall eindeutig: Bei TRELLIS etwa steht MIT im Repository,
während die Projektseite von Forschungszweck spricht. Vor einer
kommerziellen Veröffentlichung also die Lizenz des konkreten Modells
nachlesen.

Unabhängig davon: Wer eigene Meshes als Accessoires im **Marketplace
verkaufen** will, muss die zusätzlichen Kontovoraussetzungen von Roblox
erfüllen. Und alles Hochgeladene – Meshes wie Texturen – geht durch die
**Roblox-Moderation**.

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
  <https://platform.tripo3d.ai> – die App spricht die **V3-API**;
  siehe unten „Tripo3D: Umstellung auf die V3-API".
- **fal.ai** (3D-Bereich, Pay per Use, Startguthaben):
  <https://fal.ai/dashboard/keys>
- **Rodin / Hyper3D** (3D-Bereich, Bezahlung nach Verbrauch):
  <https://hyper3d.ai/api>
- **Replicate** (3D-Bereich, Bezahlung pro Lauf):
  <https://replicate.com/account/api-tokens>

Den Schlüssel in der App unter **Einstellungen** eintragen – er bleibt
ausschließlich auf dem Gerät und wird nur an den gewählten Provider gesendet.

## Tripo3D: Umstellung auf die V3-API

Tripo stellt die alte V2-Schnittstelle ab:

- **1. Oktober 2026** (30.09.2026, 16:00 UTC): keine Neuerungen und kein
  technischer Support mehr für V2.
- **1. November 2026** (31.10.2026, 16:00 UTC): die V2-Endpunkte nehmen
  **keine Anfragen mehr an**.

Die App spricht deshalb standardmäßig **V3**. Unter *Einstellungen →
Tripo3D-API-Fassung* lässt sich vorübergehend auf V2 zurückschalten,
falls ein V3-Aufruf unerwartet scheitert; nach dem Stichtag hilft das
nicht mehr, und die App sagt das in der Karte auch.

Was sich technisch geändert hat:

| | V2 | V3 |
| --- | --- | --- |
| Basis | `api.tripo3d.ai/v2/openapi` | `openapi.tripo3d.ai/v3` |
| Task anlegen | ein `POST /task` mit Feld `type` | eigener Endpunkt je Art (`/generation/text-to-model`, `/animations/rig` …), kein `type` |
| Modellwahl | `model_version`, optional | `model`, **Pflicht** |
| Upload | `POST /upload` | `POST /files` |
| Status | `GET /task/{id}` | `GET /tasks/{id}` |
| Guthaben | `GET /user/balance` | `GET /account/balance` |
| Ergebnis | `pbr_model` / `model` | `model_url` / `model_urls` |
| Vorschaubild | `rendered_image` | `rendered_image_url` |

Weil `model` unter V3 Pflicht ist, schickt die Auswahl **„Standard"**
jetzt ausdrücklich `v2.5-20250123` mit. Neu in der Liste ist
**P1-20260311** – die Fassung mit hand-gearbeiteter Low-Poly-Topologie,
die gut zum Face-Limit und damit zum Roblox-Weg passt.

Fehlgeschlagene Aufträge liest die App jetzt genauer aus: V3 liefert
`error_code` und `error_message`, und die beiden häufigen Fälle stehen
im Klartext da – **2008** ist eine Ablehnung durch die Inhaltsprüfung,
**2018** ein in der Warteschlange abgelaufener Auftrag.

**Längengrenzen.** Tripo lehnt die ganze Anfrage mit `400` ab, sobald
ein Textfeld zu lang ist: der Prompt fasst **1024**, der
Negativ-Prompt nur **255 Zeichen**. Die App kürzt deshalb selbst, und
zwar am letzten Komma vor der Grenze – aus einer Stichwortliste bleibt
so eine vollständige Liste übrig statt eines abgeschnittenen Worts.
Beim Negativ-Prompt zählt das Feld im 3D-Tab live mit und sagt vorher,
wie viele Zeichen wegfallen würden. Das Wichtigste gehört deshalb nach
vorn.

> **Hinweis zur Quelle.** Die offizielle Tripo-Dokumentation war aus der
> Entwicklungsumgebung nicht erreichbar (Netzwerksperre). Die
> Feldnamen stammen deshalb aus einem öffentlich gepflegten
> OpenAPI-Abbild der V3-API. Der erste echte Lauf mit einem Tripo-
> Schlüssel ist die eigentliche Probe; schlägt er fehl, steht in der
> Fehlermeldung der Weg zurück auf V2.

## Feste Download-Links (immer neueste Version)

- **Windows**: <https://github.com/Alex1977-code/Bildgenerator/releases/latest/download/bildgenerator-windows.zip>
  (entpacken → `bildgenerator.exe` starten)
- **Android-APK**: <https://github.com/Alex1977-code/Bildgenerator/releases/latest/download/bildgenerator-android.apk>
- **Web-App (live)**: <https://alex1977-code.github.io/Bildgenerator/>
- Übersicht: [Release „Aktuelle Version“](https://github.com/Alex1977-code/Bildgenerator/releases/latest)

Diese Links zeigen automatisch auf den jeweils neuesten erfolgreichen Build.

### Update direkt in der App

Einstellungen → **Version & Update** → „Nach Updates suchen“. Die App
vergleicht ihre eigene Build-Kennung mit der des neuesten Releases:

- **Windows/Linux/macOS**: „Herunterladen & starten“ lädt das ZIP,
  entpackt es in einen **eigenen Ordner neben** der laufenden Fassung
  (`3DGenerator-<Kennung>`), startet die neue Version und schließt die
  alte. Einstellungen, API-Schlüssel und Galerie liegen im
  Benutzerprofil und gelten damit sofort auch in der neuen Fassung.
  Absichtlich kein Überschreiben: Eine laufende `.exe` lässt sich unter
  Windows nicht ersetzen, und die alte Fassung bleibt als Rückfall
  erhalten.
- **Android**: Der Knopf öffnet den APK-Download; die Installation
  übernimmt das System.
- **Web**: Ein Neuladen mit `Strg`+`F5` genügt.

**Wenn die Prüfung mit „403" abbricht.** Für den Versionsvergleich
fragt die App die GitHub-API. Ohne Anmeldung erlaubt GitHub davon nur
60 Abfragen je Stunde und Internet-Anschluss; sind sie aufgebraucht,
antwortet der Dienst mit 403. Die App sagt dann, woran es liegt und
wann es wieder geht, und bietet zwei Auswege an: **„Neueste Fassung
trotzdem laden"** holt die Datei über den festen Download-Link (der
ohne API auskommt) – nur ob sie wirklich neuer ist, kann die App dabei
nicht sagen –, und **„Release-Seite öffnen"** führt zum Nachsehen von
Hand. Dasselbe hilft, wenn ein Firmennetz oder ein Virenscanner die
API blockiert.

**Was ein Update nicht anfasst.** Alles, was die App sich merkt, liegt
im Benutzerprofil und nicht im Programmordner: Einstellungen und die
Server-Liste unter `%APPDATA%`, die API-Schlüssel im
Windows-Anmeldeinformationsspeicher, die Galerie unter „Dokumente" →
`bildgenerator`. Die eigenen Server liegen ebenfalls unabhängig davon
(Vorgabe `C:\KI\…`) – ihre Pfade veralten durch ein App-Update also
nicht, und der 3D-Server läuft nach dem Update unverändert weiter.

Eine Sache kann mit der Zeit auseinanderlaufen: Das **Server-Skript**
(`local3d_server.py` bzw. `local_image_server.py`) wurde bei der
Einrichtung in den Server-Ordner kopiert und bleibt auf diesem Stand,
während die App weiterentwickelt wird. Dafür gibt es in den
Einstellungen beim jeweiligen Server den Knopf **„Server-Dateien
auffrischen"**: Er holt Skript und Paketliste neu, ohne die
Python-Umgebung oder die Modelle anzurühren (Sekunden statt Minuten).
Danach den Server einmal beenden und neu starten. Nötig ist das nur,
wenn der Server nach einem App-Update etwas nicht mehr kann, was die
App erwartet.

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
