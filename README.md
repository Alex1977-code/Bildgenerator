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
    Jede Installation steht **einmal** in der Liste, mit ihrem Port:
    Derselbe Ordner tauchte sonst doppelt auf (einmal gemerkt, einmal
    gefunden, mit verschiedenen Ports) und von den beiden gleich
    aussehenden Einträgen funktionierte nur einer. Eine von Hand
    geänderte Portnummer im Adressfeld gilt auch für den Start und
    wird gemerkt. Meldet sich der Server nach einer Minute nicht,
    zeigt die Karte den **Befehl zum Starten von Hand** zum Kopieren –
    die App startet den Prozess abgekoppelt und sieht seine Ausgabe
    nicht, im Terminal steht der wirkliche Grund.
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
  - **Dummy-Zeichnung neben dem Rig-Editor**: Seitlich steht eine
    gezeichnete Figur des gewählten Typs mit allen Gelenkpunkten und
    einem Ring je Punkt, der den empfohlenen Einflussbereich zeigt.
    Das angetippte Gelenk wird hervorgehoben – so ist im Bild zu
    sehen, wohin der Punkt gehört und wie weit er greifen soll
  - **Skelett nachträglich einbauen**: Modelle ohne Rig – Importe,
    Läufe ohne Auto-Rigging, Anbieter, die nur das Netz liefern –
    bekommen im Viewer über den Zauberstab ein Skelett; danach steht
    auch der Rig-Editor offen
  - **Rig-Typ wird an der Form erkannt**: Standflächen am Boden,
    Proportionen und Radform ergeben einen Vorschlag samt Begründung
    („4 radförmige Standflächen auf 2 Achsen"); die Auswahl bleibt
    frei
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

  Gerechnet wird das Zwischenbild über eine **4×3-Matrix auf den
  Latents**, nicht über den VAE. Der erste Anlauf nahm den VAE – und
  lieferte auf der GPU ein **komplett schwarzes Bild**: Die Pipeline
  läuft dort in `float16`, und der SDXL-VAE kippt darin in NaN. Für
  das Endbild hebt diffusers ihn eigens nach `float32` an
  (`force_upcast`), im Rückruf fehlte das. Die Matrix rechnet auf
  Latent-Auflösung (ein Achtel) – grob, aber ab dem ersten
  Zwischenschritt sind Form und Farben da, und sie kostet praktisch
  keine Rechenzeit.
- **OpenAI, Gemini, Stability und die 3D-Dienste** liefern keine
  Zwischenstände, sie antworten erst mit dem fertigen Ergebnis. Dort
  läuft ein **Drahtnetz, das sich Linie für Linie aufbaut** –
  ausdrücklich als Wartezeichen beschriftet, **kein** vorgetäuschter
  Fortschritt und kein Fantasie-Motiv. Die erste Fassung ließ Punkte
  kreisen; das war unangenehm anzusehen, weil sich ständig die ganze
  Fläche bewegte. Jetzt bleibt jede gezeichnete Linie stehen, nur die
  vorderste Kante wandert weiter.
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

**Grün heißt nicht „richtig".** Blockierende Funde sind rot, aber ein
Lauf, der startklar ist und trotzdem fünf Hinweise gegen sich hat,
bekommt jetzt eine **orange** Meldung: „N Bilder erkannt – der Lauf
ist möglich, aber M Punkt(e) sprechen gegen das Ergebnis". Vorher
stand über denselben fünf Hinweisen ein grüner Haken mit „ist in
Ordnung" – das war eine Falschmeldung.

**„Für dieses Modell umschreiben"** macht aus einem Briefing eine
Stichwortkette – bei Stable Diffusion und der eigenen GPU, wo ein
Briefing nicht funktioniert. Der Anlass war ein Massenprompt mit
351 Wörtern auf SDXL Base: ganze Sätze, Verneinungen, Gradzahlen,
Erklärungen zum Spiel. Herausgekommen ist ein Gebäude in
Frontalansicht auf einem Erdboden – also genau das, was der Text
ausschließen wollte. Die Prüfung hatte jeden Punkt genannt, aber
Hinweise lesen und 43 Blöcke von Hand umschreiben sind zwei
verschiedene Dinge. Der Knopf

- stellt das **Motiv voran**, ohne Artikel und Füllwörter, und
  behält dabei die Nebensätze als eigene Stichworte (aus „a smith's
  workshop **with an open forge and anvil**" wird „smith's workshop,
  open forge and anvil" – das Merkmal geht nicht verloren),
- wirft **Verneinungssätze** raus und schreibt ihre Begriffe in die
  `NEGATIV:`-Zeile, wo sie wirken,
- wirft **Erklärungen zum Spiel** raus („the image is downscaled
  about 13 times") – das Modell kann sie nicht befolgen, sieht aber
  die Substantive darin,
- wirft **Grad- und Mengenangaben** raus und setzt die erprobte
  Kamera-Kette dafür ein,
- kürzt auf die Wortgrenze des Modells.

Aus den 351 Wörtern werden so 54, und der umgeschriebene Text besteht
dieselbe Prüfung, die den ursprünglichen bemängelt hat – das hält
`test/prompt_rewrite_test.dart` fest. Vorher wird gezeigt, was
passiert; der alte Text wird ersetzt.

**Blockgrenzen:** Ein zweites `NAME:` beginnt einen neuen Block, auch
ohne `---` dazwischen. Vorher trennte nur die Trennlinie – zwei Blöcke
mit bloß einer Leerzeile dazwischen verschmolzen zu einem, der zweite
Name überschrieb den ersten, und beide Beschreibungen landeten in
einem einzigen Bild.

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

## Galerie: direkt herunterladen

Jede Kachel hat einen **Download-Knopf** — die Datei kommt sofort,
ohne den Umweg über die Detailansicht. Daneben liegt weiterhin der
Erstellungsnachweis als PDF.

Über der Liste steht **„Alle herunterladen"**, bei aktiver Suche
**„Gefundene herunterladen"** — gedacht für einen Massenlauf: 43
Gebäude auf einmal, oder nach `burg-` gefiltert nur die Burgen. Die
Dateien gehen einzeln nacheinander raus, nicht als Schwall; im Browser
fragt Chrome beim ersten Mal, ob die Seite mehrere Dateien speichern
darf. Das einmal erlauben.

**Der Dateiname ist der Name aus dem Massenprompt** — aus `bld-02-bakery`
wird `bld-02-bakery.png`. Ohne eigenen Namen bleibt es bei der
Kennung. Zeichen, die Windows in Dateinamen nicht erlaubt, werden
ersetzt.

## Bildqualität und Detailtreue steuern (eigene GPU)

Der Bild-Server nahm Schrittzahl und Prompt-Treue schon immer entgegen
– **die App hat sie nie mitgeschickt**. Es galt also stillschweigend
immer die Vorgabe des Modells. Jetzt steht im Bild-Tab unter „Eigene
GPU" ein eigener Abschnitt.

### Vier Stufen

| Stufe | Was sie tut |
| --- | --- |
| **Entwurf** | Weniger Schritte – schnell sehen, ob die Bildidee trägt |
| **Standard** | Die Vorgabe des Modells |
| **Fein** | Mehr Schritte **und ein Detail-Durchgang** |
| **Sehr fein** | Deutlich mehr Schritte, kräftigerer Durchgang auf 1,5-facher Größe |

Unter den Stufen steht immer, was daraus wird: „Daraus wird: 42
Schritte, Prompt-Treue 7,0, Detail-Durchgang auf 1,25× Größe." Ohne
diese Zeile wäre die Stufe eine Behauptung.

**Die Stufe rechnet relativ zum Modell, nicht in festen Zahlen.** SDXL
Turbo und FLUX schnell sind destillierte Modelle: vier Schritte, gar
keine Prompt-Treue-Regelung. Wer dort auf 40 Schritte und CFG 7 stellt,
bekommt kein besseres Bild, sondern ein zermatschtes. Deshalb bleibt
die Schrittzahl dort gedeckelt und der CFG-Regler ausgegraut – ein
Regler, der nichts tut, ist schlimmer als keiner.

### Der Detail-Durchgang – der eigentliche Hebel

Mehr Schritte bringen irgendwann nichts mehr, weil die **Auflösung**
das Limit ist: In 1024×1024 passt nur so viel Struktur. Der
Detail-Durchgang vergrößert das fertige Bild und schickt es mit
geringer Stärke noch einmal durch dasselbe Modell. Der zweite Lauf malt
in die gewonnene Fläche echte Struktur – Poren, Fugen, Holzmaserung –,
statt sie hochzurechnen.

Entscheidend ist die Stärke: Bei 0,3–0,45 bleibt das Motiv dasselbe und
wird nur schärfer. Ab etwa 0,6 fasst der zweite Durchgang die
Komposition an und erfindet Details dazu, die im ersten Bild nicht
standen. Die App bleibt deshalb unter 0,45.

Die Gewichte werden dafür **nicht ein zweites Mal geladen**
(`from_pipe` baut die Bild-zu-Bild-Pipeline aus denselben Bausteinen) –
sonst läge das Modell doppelt im Speicher, und auf einer 10-GB-Karte
wäre hier Schluss. Passt der Durchgang trotzdem nicht in den
Grafikspeicher, kommt das Bild aus dem ersten Durchgang mit einem
Hinweis statt eines Fehlers.

Der Detail-Durchgang gilt für SD 1.5 und SDXL. SD 3.5 und FLUX rechnen
nach einem anderen Verfahren (Flow Matching); dort sagt die App das
dazu, statt es still zu übergehen.

### Sampler

Der Sampler bestimmt, wie das Rauschen über die Schritte abgebaut wird
– bei gleicher Schrittzahl ein sichtbarer Unterschied in Schärfe und
Struktur. Zur Wahl stehen DPM++ 2M Karras (die übliche Standardwahl für
feine Details), DPM++ 2M, Euler, Euler a und DDIM. Auch das nur für SD
und SDXL: SD 3.5 und FLUX haben eigene Scheduler, ein DPM++
dazwischenzuschieben ergibt Rauschen statt Bild.

### Wo es sonst noch wirkt

Schritte, Prompt-Treue und Sampler gelten auch für die **Ansichten der
3D-Pipeline** – die sind die Detailquelle des 3D-Modells. Der
Detail-Durchgang bleibt dort aus: Er vergrößert das Bild über 1024
hinaus, und die 3D-Rekonstruktion rechnet mit quadratischen 1024ern.

Alle Werte landen im Verlauf und im Erstellungsnachweis („Schritte 42,
Prompt-Treue 7,0, Sampler dpmpp2m-karras, Detail-Durchgang 0,35 auf
1,25×"). Ohne das ließe sich ein gelungenes Bild später nicht
wiederholen – und die Lernstatistik wüsste nicht, woran es lag.

### Bei den Cloud-Anbietern

Dort gibt es diese Regler nicht, weil die APIs sie nicht annehmen.
Deren eigene Steuerung bleibt: die Qualitätsstufe bei OpenAI, die
Style-Presets und die Modellwahl bei Stability, die Bildgröße
(1K/2K/4K) bei Nano Banana Pro.

## Eigene GPU: Was passt in 10 GB (RTX 3080)?

**Diese App benutzt weder Automatic1111 noch ComfyUI oder Fooocus.**
Der Bild-Server (`server/local_image_server.py`) setzt direkt auf
🤗 *diffusers* auf – also auf derselben Bibliothek, auf der ComfyUI und
Fooocus intern ebenfalls rechnen, nur ohne deren Oberfläche und
Node-Graphen. Der Rat „nimm auf keinen Fall A1111" trifft hier deshalb
ins Leere: A1111 ist gar nicht im Spiel. Was an dem Rat stimmt, sind
die Techniken dahinter – und die sind jetzt eingebaut.

### Was mit einer 10-GB-Karte läuft

| Modell | Gewichte | Auf 10 GB |
| --- | --- | --- |
| SD 1.5 | ~4 GB | ganz auf der GPU |
| SDXL Turbo | ~7 GB | ganz auf der GPU |
| **SDXL Base (1024²)** | **~8 GB** | **ganz auf der GPU** |
| **SD 3.5 Medium (sparsam)** | **~7 GB** | **ganz auf der GPU** |
| SD 3.5 Medium | ~16 GB | ausgelagert, deutlich langsamer |
| FLUX.1 schnell | ~16 GB | ausgelagert, deutlich langsamer |

### SD 3.5 sparsam: ohne den T5-Text-Encoder

SD 3.5 lädt drei Text-Encoder, und **T5-XXL ist mit Abstand der
größte Brocken** – er allein macht aus einem 7-GB-Modell ein 16-GB-
Modell. In der Modellliste steht deshalb zusätzlich
**`sd35-medium-lean`**: dasselbe Bildmodell, ohne diesen Encoder.

Der Preis ist das Textverständnis, und zwar gezielt:

| | volles SD 3.5 | sparsam |
| --- | --- | --- |
| Kurze, dichte Motivketten | gut | **gut** |
| Lange, verschachtelte Sätze | gut | **schlecht** |
| Lesbarer Text im Bild | gut | **nur grob** |
| Wortgrenze im Prompt-Briefing | 120 | 60 |

Für Spielgrafik – kurze Motivbeschreibungen, kein Text im Bild – ist
das ein guter Tausch. Für ein Plakat mit Beschriftung nicht.

### Gemessen statt geschätzt

Die GB-Angaben oben sind Schätzungen, und Schätzungen liegen daneben:
Für SD 3.5 stand hier zuerst 10 GB, mit dem T5-Encoder sind es rund
16. Der Server misst deshalb selbst – nach dem Laden, was die Gewichte
belegen, und nach dem ersten Bild den Spitzenwert. Sobald ein Modell
einmal gelaufen ist, zeigt **„Verbindung prüfen"** diesen Wert mit dem
Zusatz *(gemessen)* statt der Tabelle. Ein gemessener Wert bekommt
auch keinen Sicherheitsaufschlag mehr – er ist bereits die Spitze.

SDXL bei 1024² – das Modell, mit dem die besten Ergebnisse entstanden
sind – läuft auf einer 3080 also vollständig im Grafikspeicher. Genau
dafür ist keine andere Oberfläche nötig.

### Drei Dinge, die dafür geändert wurden

- **Halbierte Gewichte laden.** Viele Repositories legen ihre Dateien
  zweimal ab: in voller Größe und als `fp16`-Variante. Ohne Angabe
  nimmt diffusers die großen – bei SDXL 13,9 GB Download statt 6,9 GB,
  und beim Laden liegt kurzzeitig das Doppelte im Hauptspeicher. Der
  Server fragt jetzt zuerst nach der `fp16`-Variante und fällt zurück,
  wo es sie nicht gibt.
- **Kein Scheibchen-Rechnen ohne Not.** `enable_attention_slicing()`
  lief bisher immer. Es spart Speicher, kostet aber Zeit – und moderne
  PyTorch-Versionen rechnen die Aufmerksamkeit ohnehin schon
  speichersparend (SDPA). Jetzt läuft es nur noch im Engpass.
- **Der Aufschlag fürs Rechnen.** Die alte Rechnung verglich den
  Grafikspeicher mit den Gewichten. Bei einer 10-GB-Karte und einem
  10-GB-Modell hieß das „passt" – und der erste Lauf endete mit *CUDA
  out of memory*. Aktivierungen, Latents und der VAE-Schritt brauchen
  bei 1024² grob 1,5 GB obendrauf; die zählen jetzt mit.

Dazu meldet `/health` den Grafikspeicher der Karte, und
**Einstellungen → Eigener Bild-Server → Verbindung prüfen** schreibt
das Ergebnis hin: „10,0 GB VRAM – ganz auf der GPU: sd15, sdxl-turbo,
sdxl; ausgelagert (langsamer): sd35-medium, flux-schnell".

### Und was mit FP8 wirklich ist

FP8 halbiert tatsächlich den Speicherbedarf der Gewichte. Aber:
**Die RTX 3080 ist eine Ampere-Karte und hat keine FP8-Recheneinheiten**
– die gibt es erst ab Ada (RTX 40) und Hopper. Auf einer 3080 wird FP8
nur als *Ablageformat* benutzt und zum Rechnen wieder hochgerechnet.
Das spart Speicher, macht aber **nicht schneller**, eher minimal
langsamer.

Für SDXL bringt FP8 auf 10 GB deshalb nichts: Das Modell passt bereits.
Interessant wäre es allein für SD 3.5 und FLUX – und selbst FLUX bliebe
in FP8 mit ~12 GB über der Grenze. Wenn die Karte da ist und SD 3.5
tatsächlich zu langsam läuft, baue ich die Quantisierung gern ein; ohne
die Karte zum Nachmessen wäre es geraten.

**Zur Geschwindigkeit:** Realistisch sind für SDXL bei 1024² und 30
Schritten grob 8–15 Sekunden pro Bild, nicht 5–8. Das ist eine
Schätzung aus dem Leistungsverhältnis der Karten, keine Messung – die
kommt, wenn die 3080 eingebaut ist. Die Live-Vorschau zeigt währenddessen
alle fünf Schritte, wie das Bild entsteht.

## Prompts per Drag & Drop

Prompts entstehen selten in der App: Sie kommen aus einer Prompt-KI,
einem Notizzettel, einer Markdown-Datei mit den Beschreibungen eines
ganzen Spiel-Sets. Deshalb nehmen **beide Prompt-Felder** – im Bild-
und im 3D-Tab – jetzt **.txt- und .md-Dateien per Drag & Drop**
entgegen (auch .markdown, .text, .prompt).

- Der Inhalt wird **angehängt**, nicht ersetzt: Wer schon getippt hat,
  verliert nichts. Getrennt wird mit einer Leerzeile – im Massenprompt
  ist das die Blockgrenze.
- Aufgeräumt wird beim Einlesen: eine **BOM** am Anfang fliegt raus
  (sonst steht ein unsichtbares Zeichen vor dem ersten Wort),
  **Windows-Zeilenenden** werden vereinheitlicht (ein `\r` macht aus
  einer Leerzeile eine Zeile mit Inhalt und zerlegt den Massenprompt
  falsch), und ein **umschließender Codeblock** aus Markdown fällt weg
  – Prompt-KIs geben ihre Ergebnisse gern in ``` aus.
- Gedeutet wird nichts: kein Erraten von Feldern, kein Umschreiben.
  Was in der Datei steht, steht danach im Feld.
- Im 3D-Tab teilt sich das Ablegen mit den Modelldateien dasselbe
  Ziel: Die Endung entscheidet, ob etwas in den Viewer oder in die
  Beschreibung geht. Eine abgelegte Beschreibung schaltet zugleich auf
  „Aus Text" – im Bild-Modus läge sie unbeachtet da.

## Galerie: Projekte und Ordner

Bilder und Modelle lassen sich in **Projekte** einsortieren, mit
beliebig tiefer Ordnerstruktur: „Burgenspiel", „Burgenspiel/Gebäude",
„Burgenspiel/Gebäude/Türme". Nach einem Massenlauf mit 43 Blöcken ist
das der Unterschied zwischen einer Wand aus Kacheln und einer Ablage,
in der man etwas wiederfindet.

**Ein Projekt anlegen.** In der Ordnerleiste steht **„Neues Projekt"**
(im Ordner: „Neuer Unterordner"). Das legt ihn an, auch wenn noch
nichts darin liegt, und wechselt gleich hinein — wer einen Ordner
anlegt, will ihn benutzen. Angelegte Ordner bleiben gespeichert.

**Kacheln markieren.** Der Knopf **„Auswählen"** über der Liste
schaltet den Auswahlmodus ein: Jede Kachel trägt dann ein Kästchen,
ein Tipp markiert sie. (Langes Drücken geht weiterhin, aber darauf
muss man erst kommen.) Oben stehen dann **„Alle"**,
**„Einsortieren …"** und **„Fertig"**. Zusammen mit der Suche lassen
sich so z. B. alle `burg-` auf einmal einsortieren.

Unter „Einsortieren …" steht jedes vorhandene Projekt, ein neues, ein
Unterordner im gerade geöffneten Ordner — oder „Ohne Projekt", um
wieder herauszusortieren.

**Die Ordnerleiste** ganz oben zeigt den Weg („Alle › Burgenspiel ›
Gebäude") und darunter die Unterordner der aktuellen Ebene mit ihrer
Anzahl. Ein Klick geht hinein, ein Klick auf eine Ebene im Weg zurück.
Ein Ordner zeigt **alles, was darin oder darunter liegt** — wer
„Burgenspiel" öffnet, sieht auch die Türme. Über das **⋯** neben dem
Weg (oder langes Drücken auf eine Ebene) lässt sich ein Ordner
**umbenennen** — Unterordner wandern mit — oder **auflösen**: Der
Inhalt rutscht eine Ebene höher. Auflösen löscht nichts; zum Löschen
gibt es weiterhin nur den Papierkorb an der einzelnen Kachel.

**Es sind keine echten Ordner auf der Platte.** Der Eintrag merkt sich
nur seinen Pfad, die Datei bleibt liegen, wo die App sie abgelegt hat.
Deshalb kann Umsortieren nichts verlieren und ist immer einen Klick
zurückzunehmen. Beim Herunterladen taucht der Ordner nicht auf —
Browser und Teilen-Menü nehmen ohnehin nur einen Dateinamen. Die
Einsortierung bleibt gespeichert (in der Web-Version nur für die
laufende Sitzung, wie der übrige Verlauf).

Verglichen wird ebenenweise, nicht als Textanfang: Ein Ordner „Burg"
schließt „Burgenspiel" **nicht** ein — beim Umbenennen von „Burg" bleibt
„Burgenspiel" unberührt.

## Passende Gegenstände zu einer Figur

Eine Figur allein ist noch kein Spielinhalt – es fehlen Schwert, Helm,
Rucksack, Laterne. Einzeln erzeugt passen die aber weder im Stil noch
in der Größe zusammen: Das Schwert wird so lang wie die Figur, der Helm
passt auf einen Kürbis. Und man merkt es erst, wenn beides zusammen im
Spiel steht.

Neben jedem fertigen Modell steht deshalb ein Knopf **„Passende
Gegenstände"**. Er öffnet eine Auswahl mit rund zwanzig Arten in vier
Gruppen (Waffe, Am Körper, Ausrüstung, Umgebung).

### Zwei Dinge, die den Unterschied machen

**Die Figur als Stilvorlage.** Auf Wunsch wird eine Ansicht der
fertigen Figur gerendert und als Referenzbild mitgeschickt. Farben und
Formensprache trifft das Bild-Modell damit deutlich genauer als über
eine Beschreibung. Der Prompt sagt dann ausdrücklich „only the object
itself, no character in the image" – doppelt zum Negativ-Prompt, weil
Modelle wie SDXL Turbo und FLUX den gar nicht auswerten und sonst
nichts davon hören. Ohne Referenz wandert stattdessen der Anfang der
Figurbeschreibung in den Text.

**Das Größenverhältnis im Prompt.** Ein Bildmodell kennt keinen
Maßstab: „Schwert" allein füllt das Bild. Erst „sized about half the
character's full height" bringt die Proportion ins Bild – und aus dem
Bild ins 3D-Modell. Jede Art trägt dafür ein Verhältnis **und einen
Bezug**:

| Bezug | Gilt für | Beispiel |
| --- | --- | --- |
| Figurenhöhe | Waffen, Rucksack, Truhe | Schwert 0,55 × → 2,75 Studs |
| Kopfhöhe | Helm, Hut, Krone, Maske, Amulett | Helm 1,25 × Kopf → 1,56 Studs |
| Handlänge | Trank, Laterne, Buch, Schlüssel | Trank 1,1 × Hand → 0,6 Studs |

Der Bezug ist der Punkt: Ein Helm als Anteil der *Figurenhöhe* käme bei
über sechs Studs heraus. In der Auswahl steht neben jedem Eintrag, was
dabei herauskommt („etwa 2,75 Studs – 0,55 × Figurenhöhe · in der
Hand").

### Vorauswahl aus der Figurbeschreibung

Vorgeschlagen (★) wird, was zur Beschreibung passt: Ein Ritter bekommt
Schwert, Schild und Helm, ein Zauberer Stab, Hut und Buch. Erkannt wird
über Stichwörter, deutsch wie englisch. Findet sich nichts – ein Tier,
ein Fantasiewesen ohne Rolle –, kommt eine Grundausstattung statt einer
leeren Liste.

### Der Lauf

Jeder Gegenstand entsteht in einem **eigenen Lauf**, nacheinander, mit
Fortschrittsanzeige und einem „Nach diesem beenden". Beim ersten
echten Fehler bricht die Reihe ab: Stimmt etwas grundsätzlich nicht
(Schlüssel, Guthaben, Server), wären die restlichen Läufe nur weitere
Fehlschläge – bei einem bezahlten Anbieter auch weitere Kosten.

Für den Lauf werden **Rigging und T-Pose abgeschaltet** und die
Ansichten geleert; sonst käme ein Schwert mit Armen zurück oder das
Schwert erbte die Ansichten des Helms. Danach steht alles wieder wie
vorher.

**„Prompts kopieren"** gibt es alternativ: Die Blöcke sind im Format
des Massenprompts (`NAME:` / `PROMPT:` / `NEGATIV:`) und lassen sich so
im Bild-Tab in einem Lauf zu Bildern machen.

### Fortbewegung: Reittiere und Fahrzeuge

In der Gruppe **Fortbewegung** stehen Dinge, die bestiegen werden:
Reitpferd, Reitvogel (Strauß), Reitechse, Karren, Fahrzeug, Boot,
Gleiter. Die sind keine Gegenstände, sondern Figuren für sich – und
werden entsprechend anders behandelt:

- **Sie bekommen ein Skelett.** Ein Strauß, auf dem man reiten soll,
  muss laufen können; ein Karren braucht drehende Räder. Für den Lauf
  schaltet die App das Auto-Rigging an und wählt den passenden Typ
  (Vogel, Vierbeiner, Fahrzeug). Boot und Gleiter bleiben starr – da
  bewegt sich nichts.
- **Der Größensatz spricht vom Aufsitzen.** „1,5-mal so hoch wie die
  Figur" sagt nichts Brauchbares; im Prompt steht deshalb, dass der
  Sattel auf Hüfthöhe der Figur sitzen soll und die Figur darauf passen
  muss.
- **„rider" steht im Negativ-Prompt.** Sonst kommt das Pferd mit
  Reiter, und der steckt danach im Netz.

### Wo die Gegenstände zu finden sind

An zwei Stellen, und die zweite ist die wichtigere:

- **Im 3D-Tab** am frischen Ergebnis, über das ⋮-Menü neben „Export".
- **In der Galerie** an jedem gespeicherten Modell: öffnen, dann der
  Würfel-Knopf in der Werkzeugleiste. Die App wechselt in den 3D-Tab
  und öffnet die Auswahl.

Der zweite Weg war zuerst nicht da, und das war ein Fehler: Die
Ergebnisliste des 3D-Tabs lebt nur im Arbeitsspeicher. Nach einem
Neustart stand die Figur zwar noch in der Galerie, aber Zubehör dazu
gab es nur, wenn man sie noch einmal erzeugte. Gesucht wird die
Funktion am fertigen Modell – dort steht sie jetzt.

### Anprobe: Figur und Gegenstand zusammen

Neben jedem erzeugten Gegenstand steht **„Anprobe"**. Dort stehen Figur
und Gegenstand im selben Maßstab nebeneinander – die Figur grau, der
Gegenstand farbig, mit einem Kreuz am Anbaupunkt.

**Der Anbaupunkt kommt aus dem Skelett der Figur**: das Schwert an
`Hand_R`, der Helm an `Head`, der Rucksack an `Chest`. Hat die Figur
kein Skelett, wird der Punkt aus der Bounding Box geschätzt (Kopf oben
mittig, Hand seitlich auf 55 % Höhe) – die Anzeige sagt, welcher der
beiden Fälle gilt. Ohne diesen Rückfall stünde jedes ungeriggte Modell
im Boden.

Regler für Größe, Höhe, Vor/Zurück, Seitlich und die drei Drehachsen.
Der erste Vorschlag setzt die Größe auf das, was die Maßtabelle für
diese Figur vorsieht – hat das Bildmodell die Proportion getroffen,
ändert sich fast nichts.

### Was „Übernehmen" genau tut

**Größe, Drehung und Versatz** werden in die Punkte des Gegenstands
gerechnet und als **neue Fassung gespeichert** – in der Ergebnisliste
und in der Galerie als „… (angepasst)". Das ursprüngliche Modell
bleibt daneben erhalten, nichts wird überschrieben.

**Der Versatz gehört dazu**, und das war zuerst falsch gebaut. Er war
ausgenommen, aus der Überlegung, das Accessoire schwebte sonst um die
Anbauhöhe daneben. Falsch herum gedacht: In Roblox fällt das
`Attachment` im `Handle` mit dem Punkt am Körper zusammen – der
Abstand des Netzes zu seinem eigenen Ursprung **ist** der Abstand zum
Körperpunkt. Ohne ihn wäre die Anprobe Zierde gewesen: Man schiebt
etwas hin, und in Studio liegt es woanders.

Die Figur in der Anprobe ist dabei eine **Näherung**: Ihr Kopfgelenk
liegt nicht auf den Millimeter dort, wo Roblox sein `HatAttachment`
hat. Für den Feinschliff gibt es in Studio das Accessory Fitting Tool.

Übernommen wird **ins Netz gebacken**, nicht als Matrix am
Wurzelknoten. Der Unterschied ist
keiner der Eleganz: Eine Knoten-Matrix sehen nur Programme, die
Knoten-Transformationen auswerten. Die Größenprüfung dieser App liest
die Positionen roh und hätte weiter die alte Größe gemeldet – man
stellt das Schwert auf 40 % und die Prüfung sagt unverändert „zu
groß". Gebacken sehen Vorschau, Prüfung und Import dasselbe. Nur bei
Modellen mit Skelett (Reittiere, Fahrzeuge) bleibt es beim
Wurzelknoten: Dort müssten die Bind-Matrizen mitgerechnet werden, und
für die gilt die Accessoire-Größentabelle ohnehin nicht.

Die **Verschiebung** gilt nur für die Anprobe: Wohin am Körper das Teil
gehört, entscheidet in Roblox das Attachment – stünde sie in der Datei,
schwebte das Accessoire beim Anziehen um die Anbauhöhe daneben.

Die angepasste Fassung landet auch in der Galerie („… (angepasst)").
Sonst lieferte der Download dort weiter das unangepasste Modell,
während der Export hier das neue liefert – zwei Dateien gleichen
Namens mit verschiedener Größe.

Gezeichnet wird mit demselben Renderer wie im Viewer – **mit Textur
und Licht**. Die erste Fassung zeigte flache Silhouetten; an einer
grauen Fläche ließ sich aber nicht erkennen, wo an der Figur man
gerade ist. Stattdessen gibt es den Regler **„Figur sichtbar"**: Die
Figur lässt sich durchscheinend stellen, dann ist der Gegenstand auch
zu sehen, wenn er dahinter oder darin liegt.

Nach einem Gegenstands-Lauf öffnet sich die Anprobe **von selbst** –
für jeden neu erzeugten Gegenstand nacheinander. Ein Gegenstand, den
man zur Figur erzeugt hat, will an die Figur gehalten werden; ihn nur
in der Liste abzulegen hieße, den entscheidenden Schritt zu
verstecken.

### Anbau in Roblox: fertig ausliefern

Neben der Anprobe steht **„Für Roblox ausliefern"**. Das legt drei
Dateien ab: das GLB, ein **Lua-Skript** und eine Anleitung.

Ein Mesh allein ist in Roblox kein Hut und kein Schwert. Der
3D-Importer legt eine `MeshPart` in den Arbeitsbereich, mehr nicht. Das
Skript baut daraus in einem Schritt die richtige Hülle:

| Art | Was entsteht |
| --- | --- |
| Getragen | `Accessory` mit `AccessoryType`, Teil `Handle`, darin ein `Attachment` mit dem passenden Namen |
| In der Hand | `Tool` mit einem Teil namens `Handle` |
| Zum Aufsitzen | `Model` mit `Seat` (Reittier) bzw. `VehicleSeat` (Fahrbares) |

**Am Namen hängt alles.** Das `Attachment` muss `HatAttachment`,
`BodyBackAttachment`, `WaistCenterAttachment` … heißen – je nach
`AccessoryType`. Ein anderer Name führt zu **keiner Fehlermeldung**:
Das Teil sitzt beim Anziehen einfach irgendwo, meist im Boden. Ebenso
beim `Tool`: Ohne ein Teil namens genau `Handle` nimmt die Figur nichts
in die Hand. Die Namen stammen aus der offiziellen Tabelle, ein Test
schreibt sie fest.

Der **Name des Gegenstands** selbst ist die Art – „Schwert", „Helm",
„Reitpferd". Das ist bewusst kurz: Er steht im Rucksack der Figur und
im Explorer von Studio. Die Bezeichnung eines Laufs ist in dieser App
sonst der Prompt, und der ist bei einem Gegenstand eine Aufzählung von
mehreren hundert Zeichen mit Anführungszeichen darin – als Name
unbrauchbar, und im Lua-Skript hätte das Anführungszeichen die
Zeichenkette mittendrin beendet. Ein selbst vergebener kurzer Name
bleibt stehen; alles, was nach einer Beschreibung aussieht (ein Komma
oder mehr als 40 Zeichen), weicht der Art. Der volle Prompt bleibt in
der Galerie neben dem Modell stehen.

### Größenprüfung vor dem Hochladen

Starre Accessoires haben je Art feste Höchstmaße in Studs. Die App
misst den Gegenstand und vergleicht:

| AccessoryType | Breite | Höhe | Tiefe |
| --- | --- | --- | --- |
| Hat | 1,87 | 2,50 | 1,87 |
| Hair | 1,87 | 3,12 | 2,18 |
| Face | 1,87 | 1,25 | 1,25 |
| Neck | 2,95 | 3,68 | 2,16 |
| Shoulder | 2,67 | 4,40 | 3,09 |
| Front | 2,95 | 3,68 | 3,24 |
| Back | 9,86 | 8,59 | 4,87 |
| Waist | 3,94 | 4,29 | 7,57 |

(Body Scale `Normal`, Mannequin rund 5,75–6,5 Studs hoch. Für `Slender`
und `Classic` sind die Grenzen kleiner – wer darunter bleibt, ist
überall auf der sicheren Seite.)

Passt etwas nicht, steht dabei, **auf wie viel Prozent** es
verkleinert werden muss – schon in der Anprobe, nicht erst beim
abgelehnten Upload. Für Werkzeuge gibt es keine Tabelle; da zählt, dass
es zur Figur passt.

## Skelett nachträglich einbauen und der Dummy im Rig-Editor

Bisher bekam ein Modell sein Skelett nur im selben Lauf, in dem es
entstand. Ein importiertes GLB, ein Lauf ohne Auto-Rigging oder ein
Anbieter, der nur das Netz liefert, blieb ohne – und damit ohne
Animation und ohne Rig-Editor.

**Der Zauberstab im Viewer** (nur bei Modellen ohne Skelett) baut eines
ein. Im Dialog steht oben, was die Form hergibt, darunter die freie
Auswahl aller Typen. Danach verhält sich das Modell wie ein frisch
geriggtes: Testanimationen laufen, das Skelett lässt sich einblenden,
der Rig-Editor ist offen. Das Netz bleibt unverändert – es kommen nur
Knochen und Gewichte hinzu.

### Wie der Typ erkannt wird

Vier Messwerte, alle direkt aus den Punkten ablesbar:

| Messwert | Wofür |
| --- | --- |
| **Standflächen** im untersten Sechstel | 2 Beine, 4 Beine/Räder, 6 = Insekt |
| **Rad oder Bein** | Ein Rad ist in Fahrtrichtung 3-mal länger als quer (man schneidet fast den ganzen Durchmesser an), ein Bein ist rund |
| **Aufrechtheit** (Höhe / Grundfläche) | Mensch über 1, Vierbeiner darunter, Schlange ganz unten |
| **Rumpf über den Beinen** (Tiefe / Höhe) | Der Mensch ist dort hoch und schmal, der Vogel trägt ihn waagerecht |

Der zweite und der vierte sind die eigentliche Arbeit: **Auto und
Vierbeiner haben beide vier Punkte am Boden**, und **Mensch und Vogel
haben beide zwei Beine nebeneinander und weit abstehende Arme bzw.
Flügel**. Ohne diese zwei Messwerte wären beide Paare nicht zu
trennen.

Der Vorschlag kommt **mit seiner Begründung** („4 radförmige
Standflächen auf 2 Achsen …") – nachprüfbar statt orakelhaft. Passt
nichts, sagt der Dialog das ehrlich: Bei einem Gebäude oder einem
Gegenstand ist „kein Typ" die richtige Antwort. Die Auswahlliste steht
immer daneben; erkannt **oder** gewählt führt zum selben Skelett.

Ein liegend importiertes Modell (z. B. z-up aus Blender) bekommt
bewusst keinen Zweibeiner vorgeschlagen: Der Rigger nimmt y = oben an,
und das Modell gehört erst mit den 90°-Knöpfen aufgerichtet.

### Der Dummy neben dem Editor

„Schulter" ist keine eindeutige Anweisung: Der Punkt gehört ein Stück
**innerhalb** der Silhouette, nicht auf den Ärmelrand; das Fußgelenk
an den Knöchel, nicht an die Fußspitze. Deshalb steht neben dem
Rig-Editor (ab ca. 780 px Fensterbreite, darunter über das
Fragezeichen in der Titelleiste) eine gezeichnete Figur des gewählten
Typs:

- alle Gelenkpunkte an ihrer Soll-Stelle,
- je Punkt ein **Ring für den empfohlenen Einflussbereich** – so weit,
  dass das eigene Körperteil hineinpasst, aber nicht das benachbarte,
- das im Editor angetippte Gelenk hervorgehoben, mit einem Satz dazu.

Gezeichnet wird jeweils die Ansicht, in der man am meisten sieht:
Zweibeiner und Vogel von vorn, Vierbeiner, Fisch, Schlange und
Fahrzeug von der Seite, das Insekt von oben (in der Seitenansicht
verdecken sich die drei Beinpaare).

**Die Maße sind dieselben Anteile, die der Auto-Rigger verwendet.** Der
Dummy zeigt also nicht irgendein Ideal, sondern genau das, was die
Automatik anstrebt – wer davon abweicht, sieht, wie weit. Ein Test
prüft, dass jedes Gelenk, das der echte Rigger für einen Typ baut, in
der Zeichnung auch einen Punkt hat; die Anleitung kann dem Skelett
also nicht davonlaufen.

## Aus den eigenen Läufen lernen

Die App merkt sich zu jedem 3D-Modell, mit welchen Einstellungen es
entstanden ist und wie gut es geworden ist, und leitet daraus
Empfehlungen ab — getrennt nach Motivklasse, weil sich die Anbieter bei
Gebäuden anders schlagen als bei Figuren.

**Getrennt gezählt wird nach Motivklasse**: Figuren, Gebäude,
Fahrzeuge, Objekte – und seit den Gegenständen zwei weitere:
**Gegenstände** (Schwert, Helm, Laterne) und **Fortbewegung**
(Reittiere, Fahrzeuge zum Aufsitzen). Ein Schwert ist weder Figur noch
Gebäude: klein, ohne Gliedmaßen, ganz anders gut oder schlecht. In
denselben Topf geworfen verwässert es die Empfehlungen für Figuren.
Bei den Gegenständen wird zusätzlich die **Art** mitgeschrieben – erst
damit lässt sich sehen, dass Schilde gut werden und Bögen misslingen;
über alle Gegenstände gemittelt bliebe das unsichtbar.

**Die Bewertung kommt aus zwei Quellen.** Aus der messbaren
Beschaffenheit des Netzes — wasserdicht, einheitliche Wicklung, keine
entarteten Dreiecke, ein Material, Textur vorhanden, nicht flach, und
die Dreieckszahl im angeforderten Bereich — und aus **deiner Note**
(die fünf Sterne unter einem fertigen Modell). Beides zusammen, weil
das eine ohne das andere in die Irre führt: Ein technisch tadelloses
Netz kann das Motiv verfehlen, ein schönes Modell kann Löcher haben.
Die Note wiegt deshalb schwerer als die Messung.

**Was das ist — und was nicht.** Kein neuronales Netz. Bei ein paar
Dutzend Läufen wäre eines das falsche Werkzeug: Es hätte mehr
Parameter als du Datenpunkte hast und würde vor allem den Zufall der
ersten Versuche auswendig lernen. Gerechnet wird ein geschrumpfter
Mittelwert je Einstellung (Bayes-Mittel): Ein Wert mit zwei Läufen
wird zum Gesamtmittel hingezogen, einer mit zwanzig steht für sich.
Ein Wert, der nur einmal vorkam, wird gar nicht erst vorgeschlagen —
ein einzelner guter Lauf ist Glück, kein Befund.

Deshalb steht bei jeder Empfehlung, **auf wie vielen Läufen sie
beruht**. Eine Empfehlung aus drei Läufen ist eine Vermutung und wird
auch so benannt; eine aus dreißig ist eine Aussage. Unter vier
bewerteten Läufen einer Motivklasse sagt die App gar nichts, sondern
zeigt, wie viele noch fehlen.

Alles bleibt auf diesem Rechner: Die Läufe liegen in den lokalen
Einstellungen, nichts wird hochgeladen, und kein fremdes Wissen fließt
ein — die Empfehlungen sind ausschließlich deine eigenen Ergebnisse.

## Roblox: Figuren, die der Importer annimmt

> Kurzfassung samt offener Punkte für eine neue Sitzung:
> [`docs/roblox-uebergabe.md`](docs/roblox-uebergabe.md).

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
bekommt bei Quad-Topologie die halbe Zahl. Halbiert wird nur dort, wo
wirklich Vierecke angefragt werden – Tripo und Rodin haben eigene
Topologie-Schalter. Die Roblox-Karte schreibt aus, was gerade
tatsächlich gesetzt ist, z. B. „Ziel: 10.000 Dreiecke (Budget 5.000
Polygone). Aktuell eingestellt: Meshy „target_polycount" = 5.000".

**Die Roblox-Vorlage schaltet Quad-Topologie aus**, und zwar
absichtlich: Der Importer trianguliert ohnehin und zählt Dreiecke –
für Roblox bringt ein Viereck-Netz nichts. Kosten bringt es dreifach:
Bei Meshy halbiert es das Polygonbudget, bei Tripo erzwingt es FBX
(beim Ziel **Accessoire**, wo kein Rigging läuft, hätte das den ganzen
Weg gesprengt – Prüfung, Ansicht und Export lesen GLB), und P1 liefert
von sich aus schon vierecksnahe Topologie. Wer das Modell danach in
Blender überarbeiten will, schaltet sie von Hand ein; beim
Accessoire-Ziel warnt die App dann ausdrücklich.

**Bei Tripo schließen sich Quad-Topologie und Rigging aus.** glTF
kennt keine Vierecke, nur Dreiecke – Tripo liefert Quad-Netze deshalb
**ausschließlich als FBX**. Alles, was diese App danach rechnet
(Ansicht, Roblox-Prüfung, R15-Umbenennung, STL/OBJ/3MF), liest GLB.
Deshalb hat das Skelett Vorrang: Ist Rigging an, geht `quad` nicht mit
an Tripo, und der Schalter sagt das auch. Ohne Rigging bleibt die Wahl
frei; das Ergebnis ist dann eine FBX-Datei, die in der Ergebnisliste
als solche steht und sich nur herunterladen lässt. Für Roblox ist das
kein Verlust: Der Importer trianguliert ohnehin und zählt Dreiecke.

**Die App prüft, was wirklich in der Datei steht, nicht den
Dateinamen.** Anlass war ein Lauf, der als `modell.glb` in der Galerie
lag und sich weder anzeigen noch prüfen noch riggen ließ – drin war
ein binäres FBX aus einem Quad-Lauf. Jetzt wird die Dateiart nach dem
Download am Inhalt erkannt (`glTF`-Kopf, `Kaydara FBX Binary`, OBJ,
PLY, STL, ZIP), sie steht in der Ergebniskarte, der Export bekommt die
richtige Endung, und die GLB-Funktionen sind grau statt kaputt. Dieselbe
Prüfung greift bei per Drag & Drop abgelegten Dateien.

#### Was für Roblox an Tripo geht

Ein Lauf mit `face_limit` = 10.000 lieferte 101.298 Dreiecke und drei
2048er Texturen. Die Grenze war also mitgeschickt – falsch war der
Rest des Auftrags. Die Prüfung Feld für Feld gegen Tripos
Parameterliste hat drei Lücken gefunden, alle drei sind geschlossen,
und die Roblox-Vorlage setzt sie:

| Feld | vorher | jetzt (Roblox) | warum |
| --- | --- | --- | --- |
| `model` | `v2.5-20250123` | **`P1`** | P1 ist Tripos Low-Poly-Modell: Flächenbudget 48–20.000, saubere Topologie, zum Riggen gedacht. Genau Roblox' Bereich. v2.5 ist das allgemeine Modell. |
| `pbr` | fest an `texture` gekoppelt, also **immer an** | **aus** | PBR liefert drei Bilder (Basecolor, Normal, Metallic-Roughness). Roblox nimmt je Mesh **ein** Material – die anderen beiden kosten nur Texturgrenze und Ladezeit. Der PBR-Schalter der App wirkte bisher nur auf Meshy. |
| `auto_size` | nicht gesendet | **an** | Ohne Maßstab kam die Figur mit 0,98 Einheiten. Der Importer rechnet glTF-Einheiten als Meter → 3,5 Studs statt der üblichen 5. |
| `face_limit` | 10.000 | 10.000 | Bei P1 im dokumentierten Bereich. |
| `smart_low_poly` | nicht gesendet | **an** | Baut ein spielefertiges Netz, statt das volle zu beschneiden. |
| `quad` | an (Vorlage) | **aus** | Erzwingt FBX; das Skelett kommt als GLB. |
| `orientation` (Bild→3D) | nicht gesendet | **`align_image`** | Sonst dreht Tripo das Modell nach eigenem Gutdünken. |
| Rigging `rig_type` | nicht gesendet | **aus dem Figurtyp** | Tripo musste raten. |
| Rigging `spec` | nicht gesendet | **`mixamo`** | Die R15-Umbenennung der App ist auf Mixamo-Namen ausgelegt (`mixamorig:Hips`, `LeftForeArm`). |

Nicht gesendet werden bewusst `generate_parts` (zerlegt das Modell in
mehrere Meshes) und `compress` (gepackte GLB). `test/tripo_service_test.dart`
hält das fest, damit die Prüfung nicht wieder zur Vermutung wird.

**Tripo legt Modellfassungen unter neuem Datum neu auf und schaltet
die alten ab.** Die Vorgabe `v2.5-20250123` wurde dabei ungültig; die
API antwortet mit „invalid model 'v2.5-20250123', allowed values:
v1.0-20240301, v2.5-20260210". Getroffen hat das ausgerechnet das
**Rigging**: Der Rigging-Endpunkt verlangt eine eigene Modellangabe,
und ohne sie greift bei Tripo genau die abgeschaltete Vorgabe – das
Modell selbst war mit P1 sauber erzeugt, das Skelett scheiterte
trotzdem. Zwei Änderungen:

- Die App schickt beim Rigging und bei der Rigging-Vorprüfung die
  Fassung **ausdrücklich** mit (`v2.5-20260210`), und die Vorgabe für
  die Generierung ist dieselbe.
- Nennt Tripo in einer Fehlermeldung die **gültigen Fassungen**, nimmt
  die App die passende und versucht es einmal erneut – die aus
  derselben Reihe (`v2.5` bleibt `v2.5`), sonst die letztgenannte.
  Damit kostet die nächste Datumsumstellung keinen Lauf mehr.

#### Die Roblox-Regeln stehen vollständig in der Vorlage

„Prompt-Vorlage kopieren (mit Roblox-Regeln)" hängte bisher nur eine
Liste an, was zu **vermeiden** ist. Damit muss die Prompt-KI den Rest
raten – und genau daran sind die ersten Läufe gescheitert. Jetzt
enthält der Block alles, was für einen brauchbaren Prompt nötig ist:

- **Den Bauplan** in Reihenfolge: Was es ist → Proportionen →
  Kleidung und erkennendes Merkmal (ausgeschrieben, mit Ort am
  Körper) → Farben → fester Schwanz.
- **Den festen Schwanz wörtlich.** Vier Angaben darin entscheiden
  über „besteht die Prüfung": `single connected body`, `visible wall
  thickness`, `closed watertight shell`, `single mesh`.
- **Die NEGATIV-Zeile wörtlich** – fertig, innerhalb der 255 Zeichen.
- **Die Fallen**, jede mit Grund: keine T-Pose im Text (die App hängt
  121 Zeichen selbst an), keine Verneinungen (Text→3D liest sie nicht
  als Ausschluss, sondern sieht das Substantiv), keine dünnen
  Kleinteile, bei Figuren keine Umhänge oder Röcke über Armen und
  Beinen – was verdeckt ist, verschmilzt mit dem Rumpf, und dort kann
  kein Skelett andocken.
- **Die Grenzen**: Dreiecke, ein Material, 1024er-Textur, 5 Studs
  Höhe, und die Zeichenbudgets samt T-Pose-Abzug.
- **Ein vollständiges Beispiel**, das selbst in die Grenzen passt.

Für **UGC-Accessoires** dieselbe Struktur mit den anderen Vorgaben:
kein Körper, keine Pose, 4.000 Dreiecke, eigener Schwanz und eigene
NEGATIV-Zeile. `test/roblox_prompt_test.dart` hält fest, dass jeder
dieser Punkte wirklich in der Vorlage steht.

#### Vorhandene Modelle als Vorlage

**„3D-Modell laden"** im Ergebnisbereich nimmt eine vorhandene GLB,
OBJ oder STL in dieselbe Liste wie ein frisch erzeugtes Modell. Damit
greifen alle Werkzeuge darauf: die Roblox-Prüfung, „In Ordnung
bringen", die R15-Umbenennung samt Blender- und Studio-Skript, die
Ausgabeformate.

**„Als Vorlage für ein neues Modell"** im Export-Menü rendert vier
Ansichten (vorn, links, hinten, rechts) aus dem geladenen Netz –
gezeichnet mit demselben Renderer wie der Viewer, was man dort sieht,
geht auch in die Pipeline – und legt sie in die Ansichten-Kacheln.
Von da an ist es ein gewöhnlicher Multiview-Lauf: Der gewählte Dienst
baut daraus ein **neues** Modell im eingestellten Budget. Das ist der
Weg für ein Modell, das mit 100.000 Dreiecken ankommt: Ein
vorhandenes Netz zu reduzieren, ohne UV-Nähte und Textur zu
zerstören, kann die App nicht – ein neues aus Ansichten bauen zu
lassen schon.

#### Figurtyp: Dropdown und Prompt-Vorlage

Der **Figurtyp** steht jetzt bei jedem Anbieter unter dem
Rigging-Schalter, nicht mehr nur beim lokalen Generator. Er tut zwei
Dinge auf einmal:

- Er geht als `rig_type` an den Anbieter, statt ihn raten zu lassen.
- Er hängt einen Absatz an die **kopierte Prompt-Vorlage**, damit die
  Beschreibung zum Skelett passt. Das ist keine Kosmetik: Ein Skelett
  kann nur an Gliedmaßen andocken, die im Netz als getrennte Volumen
  vorhanden sind. Arme, die am Körper anliegen, verschmelzen bei der
  Rekonstruktion mit dem Rumpf – danach ist nichts mehr zu trennen,
  weder für den Auto-Rigger dieser App noch für Tripos.

| App-Typ | Tripo | Was der Prompt zeigen muss |
| --- | --- | --- |
| Mensch / Roboter / Fantasy (2 Beine) | `biped` | Zwei Beine, zwei Arme, **nicht am Körper anliegend**; Hände und Füße als eigene Volumen. Ein Umhang über den Beinen macht die Figur unriggbar. |
| Vierbeiner | `quadruped` | Vier Beine einzeln getrennt, stehend – nicht sitzend oder liegend; Kopf abgesetzt, Schwanz frei. |
| Insekt / Mehrbeiner | `hexapod` | Sechs Beine paarweise abstehend, Körper in Kopf/Brust/Hinterleib. |
| Vogel | `avian` | Flügel **gespreizt** (angelegt verschmelzen sie), zwei Beine, Schwanzfedern als eigenes Volumen. |
| Schlange | `serpentine` | Langgestreckt, gleichmäßig dick, nicht eingerollt. |
| Fisch | `aquatic` | Flossen mit sichtbarer Dicke, seitlich symmetrisch. |
| Fahrzeug | – | Räder als eigene runde Volumen; riggt die App selbst mit automatischer Achsenerkennung. |

Bei der Roblox-Vorlage mit Ziel **Figur** warnt die App, wenn ein
anderer Typ als `biped` eingestellt ist: R15 ist ein zweibeiniges
Skelett, ein Vierbeiner lässt sich nicht darauf umbenennen. Als freies
Mesh geht er trotzdem, nur nicht als Avatar.

**Bleibt es trotzdem zu groß**, gibt es den Reparaturweg: **„Bei
Tripo3D nachrechnen"** in der Prüfung schickt das fertige Modell über
Tripos Umwandlungs-Auftrag zurück – `face_limit` (dokumentierte
Vorgabe 10.000) und `texture_size` in einem Lauf – und holt es passend
wieder. **UVs und Textur bleiben erhalten, weil derselbe Dienst
rechnet, der das Modell gebaut hat.** Das kostet zusätzliche Credits
(laut Preisliste 20 für einen Lauf mit Geometrie-Optionen), deshalb
fragt die App vorher. Gedacht ist der Knopf für Modelle, die vor
diesen Korrekturen entstanden sind – im Normalfall soll er nicht
gebraucht werden.

Damit hinterher nicht offenbleibt, wer die Grenze übergangen hat,
merkt sich jedes Ergebnis, **was angefordert war** („Tripo
`face_limit` = 10.000, Smart Low-Poly: an") – die Zeile steht in der
Roblox-Prüfung über der gemessenen Dreieckszahl und im
Galerie-Eintrag.

**Zu große Texturen behebt die App selbst.** Roblox nimmt höchstens
1024×1024; Tripo liefert PBR-Texturen als 2048er JPEG. In der
Roblox-Prüfung steht dafür der Knopf **„Texturen auf 1024
verkleinern"**: Er rechnet alle eingebetteten Bilder herunter, packt
den GLB-Puffer neu (die alten großen Bilddaten fallen weg) und prüft
gleich noch einmal. Neu kodiert wird als PNG – Flutter kann nichts
anderes schreiben –, deshalb kann die Datei trotz kleinerer Bilder
wachsen; die Karte nennt die gemessene Größe vorher und nachher. Am
Beispiel der 3,19-MB-Figur: drei Texturen 2048 → 1024, Geometrie
unverändert, Datei 3,83 MB, Textur-Blocker weg.

#### „In Ordnung bringen": vier Punkte, ein Knopf

Was die Prüfung findet, repariert sie auf Wunsch auch – in einem Zug,
danach wird neu geprüft:

- **Offene Kanten.** Kanten, die nur zu einem Dreieck gehören, bilden
  den Rand eines Lochs. Die Ränder werden zu Schleifen
  zusammengesetzt und als Fächer geschlossen – **ohne neue
  Vertices**, damit UVs, Farben und Gewichte unangetastet bleiben.
  Ein zusätzlicher Mittelpunkt bräuchte auch UV, Normale und
  Gewichte, und jede dieser Erfindungen wäre an der Naht sichtbar.
  Sehr große Schleifen (über 512 Kanten) bleiben offen: Das ist kein
  Loch mehr, sondern ein offenes Netz, und ein Deckel darüber wäre
  Unsinn.
- **Uneinheitliche Wicklung.** Benachbarte Dreiecke müssen ihre
  gemeinsame Kante gegenläufig durchlaufen. Ein Flutfüllen über die
  Nachbarschaft dreht die Ausreißer um – je zusammenhängendem Teil
  getrennt, ein Modell kann aus mehreren bestehen. Zeigt danach das
  ganze Netz nach innen (negatives Volumen), wird alles gedreht.
  Anschließend werden die **Normalen** neu gerechnet, sonst zeigen
  sie weiter in die alte Richtung.
- **Einheiten.** glTF rechnet in Metern, der Importer in Studs
  (1 Stud ≈ 0,28 m). Beim Ziel *Figur* wird auf **5 Studs** skaliert.
  Ohne Skelett geht der Maßstab in die Punkte (dann sieht ihn jedes
  Werkzeug, auch eines, das Knotenmatrizen ignoriert), mit Skelett
  über einen Knoten darüber – Gelenke und Bind-Matrizen einzeln
  umzurechnen wäre fehleranfällig. Die `min`/`max` der Accessoren
  werden mitgezogen; Importer glauben ihnen.
- **Textur.** Wie oben beschrieben auf 1024 herunter.

`test/roblox_fix_test.dart` prüft das an einem Würfel mit
herausgenommenen und verdrehten Flächen: Löcher zu, Wicklung
einheitlich, Volumen positiv, Höhe 1,4 m bei 5 Studs – und ein heiles
Netz bleibt unangetastet.

**Die Dreieckszahl senkt die App nicht selbst.** Ein Netz zu
reduzieren, ohne UV-Nähte und damit die Textur zu zerstören, braucht
ein Werkzeug, das UVs und Rig mitführt. Der eingebaute Dezimierer
arbeitet per Vertex-Clustering und wirft die UVs weg – auf einem
texturierten Modell wäre das Ergebnis eine zerrissene Textur. Deshalb
geht der Weg über den Anbieter (siehe „Bei Tripo3D nachrechnen") oder
über Blender (Modifier **Decimate**), statt über einen Knopf, der das
Modell verunstaltet.

**Kein Skelett, obwohl Rigging an war?** Dann steht der Grund am
Ergebnis und in der Prüfung („Rigging wurde angefordert, kam aber
nicht zustande: …"). Vorher gab es dafür nur eine Kurzmeldung während
des Laufs – wer sie verpasste, sah später ein Modell ohne Rig-Anzeige
und ohne Animationen und wusste nicht, ob die App nicht gefragt oder
der Dienst abgelehnt hatte. Die App nennt Tripo beim Rigging jetzt
auch den Figurtyp (`rig_type`), statt ihn raten zu lassen.

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
`Shoulder_L`. Tripos V3-Rig liefert dagegen `tripo::0_Left_Limb_2` und
`bone_6` — daraus liest kein Namensvergleich eine Rolle heraus.

**Das nimmt die App ab**: Export-Menü → **„Für Roblox vorbereiten …"**.
Zuerst über die Namen (Mixamo, eigener Rigger, geläufige
Schreibweisen), und wenn die nichts hergeben, über die **Form des
Skeletts**: Arme sind die beiden seitlich äußersten Äste ab der ersten
gemeinsamen Gabelung, Beine die tiefsten, Rumpf und Kopf ergeben sich
aus dem Weg dazwischen. Links und rechts kommen dabei aus der
Geometrie, nicht aus den Namen — die Blickrichtung liest sich am
Schritt vom Fuß zum Zeh ab. Das ist kein Übereifer: Tripo hat die
Seiten bei der Testfigur **vertauscht** benannt.

Knochen ohne R15-Gegenstück (Finger, ein zweiter Wirbel) behalten ihren
Namen — das ist richtig so.

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
(Scale 1,1,1, Rotation 0,0,0), Wurzelknochen und LowerTorso bei 0,0,0,
Wurzelknochen ohne Gewichtung, höchstens vier Bones je Vertex, Größe in
Studs — und die R15-Benennung. Alles davon ist aus der Datei messbar;
nur die T-Pose nicht, die bleibt ein Hinweis.

#### Drei Regeln, die man nicht aus Plausibilität ableiten kann

Beim ersten echten Import ging jede einzelne davon daneben, weil sie
sich anders verhält, als man erwartet. Alle drei sind jetzt in der App
umgesetzt und in der Prüfliste hinterlegt.

**1. Eine Datei-Einheit ist ein Stud, nicht ein Meter.** Der Importer
rechnet die Datei über die Scale-Unit-Einstellung in Meter um und setzt
dann einen Meter gleich einem Stud. Eine Figur von 1,20 glTF-Einheiten
kommt also 1,2 Studs hoch an und steht kniehoch neben einem
Standard-Charakter — die 4,3 Studs, die sich aus 0,28 m je Stud
ergäben, sieht man nie. „Für Roblox vorbereiten" skaliert eine Figur
deshalb auf 5 Einheiten.

**2. Der Nullpunkt liegt an der Hüfte, nicht am Boden.** Roblox'
Spezifikation für Charakterkörper verlangt beides zugleich: *„The
LowerTorso and Root bone or joint position must be set to 0, 0, 0."*
Die Füße stehen damit im Minus. Legt man den Wurzelknochen stattdessen
auf Fußhöhe, landet der `HumanoidRootPart` zwischen den Füßen; die
Figur schwebt im Spiel um die Hip Height nach oben und kippt beim
ersten Schritt um. Bei einer 5-Studs-Figur ergibt sich daraus eine Hip
Height von rund 2,0 — genau der Wert eines Standard-R15-Rigs; die App
rechnet sie aus und trägt sie ins Studio-Skript ein.

**3. „Bones ohne Einfluss behalten" muss im Importer an sein.** Der
Wurzelknochen darf keine Vertices bewegen (*„Do not apply influences to
the Root bone or joint"*) — genau dadurch ist er ein Knochen ohne
Einfluss, und der Importer wirft solche Knochen ohne diesen Haken weg.

Die übrigen Einstellungen im 3D-Importer: Rig-Typ **R15**, Scale Unit
**Zentimeter** (Blender schreibt die FBX in cm), „Drehpunkt auf
Szenenursprung setzen" an, „Verankert" aus.

**Eine stehende Figur im Workspace kippt um, wenn man sie anrempelt.**
Das ist kein Fehler an der Datei, sondern normale Roblox-Physik: Ein
freistehendes Humanoid-Modell hat niemanden, der es steuert. Soll sie
als Deko oder NPC stehen bleiben, in der Befehlsleiste
`workspace.<Name>.HumanoidRootPart.Anchored = true` setzen. Als
Startfigur stellt sich die Frage nicht — die steuert der Spieler.

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
│   ├── item_fit.dart          # Anprobe: Anbaupunkt, Maßstab, Transform
│   ├── model_relay.dart       # Modell aus der Galerie in den 3D-Tab
│   ├── item_prompt.dart       # Gegenstände zur Figur: Maßstab + Prompt
│   ├── roblox_accessory.dart  # Accessory/Tool/Seat + Größengrenzen
│   ├── project_tree.dart      # Projektpfade und Ordnerbaum der Galerie
│   ├── prompt_drop.dart       # Text-/MD-Dateien ins Prompt-Feld
│   ├── quality_preset.dart    # Schritte, Prompt-Treue, Detail-Durchgang
│   ├── rig_detect.dart        # Rig-Typ aus der Form des Netzes
│   ├── rig_dummy.dart         # Soll-Gelenke der Dummy-Zeichnung
│   ├── vram_fit.dart          # Passt ein Bild-Modell in den VRAM?
│   └── exporter.dart          # Speichern/Teilen/Download je Plattform
└── widgets/common.dart        # Schachbrett-Transparenzvorschau u. a.
```

Weitere Provider lassen sich über das `ImageGenerator`-Interface in
`lib/services/generators.dart` ergänzen.
