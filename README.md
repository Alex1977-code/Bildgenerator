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
  In der Auswahl stehen die Pixelmaße dabei — bei Stability als
  Schätzung („ca."), bei Gemini und beim eigenen Bild-Server exakt,
  weil App und Server dieselbe Rechnung anstellen. „Automatisch"
  (OpenAI) trägt keine Zahl, weil dort das Modell entscheidet; das
  steht jetzt auch dran.
- **Blickrichtung wählbar**: Vorderansicht, Dreiviertel, Profil,
  Rückansicht, isometrische Spielgrafik, Draufsicht, Augenhöhe,
  Untersicht — oder „keine Vorgabe". Die Wahl geht in **jede**
  Prompt-Vorlage ein, formuliert so, wie das gewählte Modell liest:
  als Satz für GPT-Image und Gemini, als Stichworte plus Negativ-Block
  für Stable Diffusion, und bei den Modellen ohne Guidance doppelt im
  positiven Teil, weil dort kein Negativ-Block wirkt. Unter der
  Auswahl steht, was daraus wird.
- **Qualität wählbar**: Auto / Niedrig / Mittel / Hoch.
- **Transparenter Hintergrund** (für Logos & Icons, PNG/WebP) – mit
  Schachbrett-Vorschau.
- **Wartegrafik je Modell**: Solange gerechnet wird, zeichnet ein
  Motiv, das zum arbeitenden Modell gehört — Nano Banana eine Banane,
  Stable Diffusion das Hugging-Face-Gesicht, GPT-Image eine Rosette,
  die eigene GPU einen Chip, die Schnellmodelle einen Blitz. Der
  Zeichner entsteht Punkt für Punkt, und auf seiner Leinwand
  verdichtet sich eine zweite Punktwolke zu einem Bild.
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
  - **FBX-Export** (binär, Fassung 7.4): Der Viewer schreibt das
    Modell als FBX – das Format, das Roblox Studio für gerigte Figuren
    erwartet. Enthalten sind Geometrie, Normalen, Texturkoordinaten,
    das Skelett als LimbNode-Kette, die Hautgewichte und die
    Bindepose; die Textur liegt als eigene PNG daneben, weil FBX
    Bilder nicht einbettet, sondern auf Nachbardateien verweist – und
    Roblox das Bild ohnehin getrennt hochlädt. Damit entfällt der
    bisherige Umweg über Blender
  - **STL-, 3MF- und OBJ-Export**: Der Viewer exportiert Modelle als
    binäres STL (nur Form) oder als 3MF **mit Farben** (Material-
    Palette je Dreieck) – jeweils aufs Druckbett gedreht, zentriert
    und auf die gewünschte Größe in mm skaliert, mit eingebauter
    **Wasserdichtheits-Prüfung** im Export-Dialog; dazu OBJ mit
    Vertexfarben für Blender/MeshLab. Druck: Datei in einen Slicer
    laden (PrusaSlicer, Cura, Bambu Studio …) oder beim
    Farbdruck-Dienst hochladen
  - **Viewer als Drop-Ziel**: eigene GLB-, **FBX**-, STL- und
    OBJ-Dateien lassen sich per Drag & Drop in den 3D-Tab oder direkt
    in den Viewer ziehen und werden dort angezeigt (FBX/STL/OBJ werden
    intern nach GLB gewandelt). Aus einer FBX kommt die **Geometrie**
    – Skelett, Materialien und Animationen bleiben außen vor; das
    Skelett baut die App ohnehin selbst
  - **Für Roblox herrichten**, direkt am abgelegten Modell: „Roblox-
    konform riggen und anpassen" baut bei Bedarf ein Skelett ein,
    bringt die Knochen auf die R15-Namen (mit `Root` und
    `HumanoidRootNode` darüber), schließt Löcher, vereinheitlicht die
    Wicklung, verkleinert Texturen auf 1024 und skaliert auf 5 Studs.
    „Nur anpassen" lässt das Skelett weg – für Accessoires und Props.
    Vorher gab es das nur am frisch erzeugten Ergebnis im 3D-Tab; ein
    abgelegtes Modell kam dort nie an
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

## Der Bild-Tab, aufgeräumt

Ein Umbau nach Entwurf, nicht nach Gefühl: Aus einer Design-Runde
(drei Richtungen für den Bild-Tab plus Handy) wurde **1a
„Aufgeräumt"** gebaut – die Evolution der bestehenden Material-Oberfläche.
Rail bleibt, Indigo bleibt; es ändert sich die Anordnung, nicht das
Fundament. Vier Regeln stehen dahinter:

1. **Zahl statt Absatz.** Jede Erklärung wird zu Wert, Etikett oder
   Tooltip. Prosa gibt es nur noch auf Abruf.
2. **Eine Entscheidung pro Fläche.** Modell, Format, Anzahl,
   Qualitätsstufe – vier Karten, nicht eine Spalte.
3. **Warten zeigt, wer rechnet** – nie einen erfundenen Fortschritt.
4. **Kosten sind Teil des Knopfs.** „2 Bilder · ≈ 0,08 $" steht am
   Knopf, nicht in einem Feld weiter oben.

### Was sich geändert hat

**Kopfzeile.** Logo, **Projektwähler**, **Guthaben**, Hell/Dunkel,
Hilfe. Der Projektwähler bestimmt, in welchen Galerie-Ordner das
nächste Bild oder Modell fällt – vorher landete alles unsortiert. Das
Guthaben zeigt den gewählten Bild- und 3D-Anbieter: Stability, Meshy
und Tripo melden Credits über ihre API; OpenAI und Gemini haben keine
Guthaben-API, dort steht, ob ein Schlüssel hinterlegt ist; die eigene
GPU kostet 0 $. Ein Klick holt die Zahlen neu, und nach jedem Lauf,
der ein Restguthaben mitliefert, ist es sofort aktuell.

**Linke Spalte.** Oben der Umschalter *Massenprompt | Einzelbild* mit
dem Zähler „2 Blöcke · 2 Bilder" und dem Menü „Vorlage laden"
(Beispiel, CSV einlesen, Prüfbericht, Umschreiben, Vorlage für die
Prompt-KI, Stil-Vorlagen). Der Massenprompt zeigt sich als **Tabelle**
– eine Zeile je Block mit Nummer, Name und Prompt –, solange nicht
getippt wird; ein Klick öffnet den Editor. Warnungen aus der Prüfung
sind **Zeilen mit „Details"**, nicht mehr eine Wand. Die
Referenzbilder sind eine Zeile aus Kacheln mit „+". Dann die vier
Karten; ein Klick auf eine Karte öffnet die Auswahl. Alles Seltene
(Negativ-Prompt, Blickrichtung, Seed, Style-Preset, Dateiformat,
GPU-Stufen, Kostenvergleich, API-Schlüssel) liegt zusammengeklappt
unter **Profi-Optionen**.

**Der Knopf** steht fest unter der Spalte: „2 Bilder · ≈ 0,08 $", darunter
„276 Stück für 10 € · Schätzwert, echter Abzug nach dem Lauf".

**Rechts die Ergebnisse.** Kopfzeile mit „2 / 3 fertig", Schnitt je
Bild, Restzeit, „Alle herunterladen" (ein Dialog für alle). Jede Karte
trägt den Namen, darunter „11 s · 0,04 $", Vergrößern, Speichern und
**„→ 3D"** – das reicht das Bild als Vorderansicht in den 3D-Tab, ohne
Umweg über die Platte. Während gerechnet wird, zeigt eine Karte die
Wartegrafik des Modells („Nano Banana zeichnet …") und sagt „keine
Vorschau möglich", wo das so ist; was noch ansteht, steht als
gestrichelte Karte „in Warteschlange" daneben.

**Handy.** Keine Kopfzeile, der Tab trägt seinen Titel selbst; Prompt
oben, darunter „Referenz" und „Vorlage", unten das Feld mit Modell
(„wechseln ▸"), Seitenverhältnis-Chips, Stufe, Kosten und dem Knopf
„1 Bild generieren". Seltenes unter „Mehr Optionen". In der Leiste
heißt es „Mehr" statt „Einstellungen".

### Die Warteschlange

Ein Lauf ist ein **Zustand der App**, kein Dialog. Jeder Block des
Massenprompts und jeder 3D-Lauf ist ein Auftrag in einer Schlange,
die neben den Tabs steht: als „1 Lauf" unten in der Leiste (Desktop)
und als Chip in der Titelzeile (Handy); ein Klick öffnet die Seite
„Lauf" mit dem, was rechnet, wartet und fertig ist.

Sie überlebt den Neustart – mit einer ehrlichen Einschränkung: **Die
App rechnet nicht, wenn sie geschlossen ist.** Der Entwurf versprach
„läuft weiter, auch wenn du die App schließt"; das kann eine
Flutter-App ohne Hintergrunddienst nicht halten, und die Oberfläche
behauptet es deshalb auch nicht. Stattdessen: Was beim Schließen
offen war, ist beim nächsten Start als **unterbrochen** markiert, der
Massenprompt-Text ist noch da, und der Bild-Tab bietet an, die
fehlenden Bilder **nachzuholen** – nur diese, die fertigen bleiben in
der Galerie.

### CSV einlesen

Prompts entstehen selten in der App; wer vierzig Assets plant, hat sie
in einer Tabelle. „Vorlage laden → CSV einlesen" (oder eine CSV ins
Feld ziehen) macht daraus Blöcke: Trennzeichen (`;` `,` Tab `|`) und
Kopfzeile werden erkannt, Spalten heißen `name`, `prompt`, `negativ`,
`referenz` in beliebiger Reihenfolge; ohne Kopfzeile gilt Name,
Prompt, Negativ, Referenz. Anführungszeichen nach RFC 4180. Was keinen
Prompt hat, wird übersprungen und gezählt.

### Was bewusst nicht gebaut wurde

Aus derselben Design-Runde gab es **1b „Studio"** (dunkel, Icon-Dock,
⌘K-Palette) und **1c „Fließband"** (der Massenprompt als Tabelle mit
Pipeline-Reitern). Beide sind komplette Alternativen, nicht
Ergänzungen; gebaut wurde 1a, weil es das Fundament behält und keine
bestehende Funktion weichen muss. Der 3D-Tab ist noch die alte
Anordnung – dieselbe Sprache dort ist eine eigene Runde.

## Prüfung gegen die Zielliste

Eine Durchsicht des Codes gegen die Frage „Was soll die App können,
und tut sie es?" – mit dem, was dabei geändert wurde, und dem, was
offen bleibt. Ehrlich getrennt.

**2D-Generator für Text und Bilder, einzeln und als Massenprompt.**
Vorhanden. Die Prompt-Vorlage hängt am gewählten Modell
(`prompt_briefing.dart`: Stichwortkette für Stability und die eigene
GPU, gegliedertes Briefing für GPT-Image und Gemini; Höchstlänge,
Negativ-Umgang und Modellregeln je Modell). Der Massenprompt wird
gegen dasselbe Profil geprüft und lässt sich mit „Umschreiben" darauf
bringen. **Neu:** Felder, die das Modell nicht braucht, sind
**ausgegraut statt versteckt** – Seed (nur Stability und eigene GPU),
Style-Preset (nur Stability Core), Negativ-Prompt (bei SDXL Turbo und
FLUX schnell ohne Wirkung) – jeweils mit dem Satz, warum.

**3D-Generator für Text und Bild, mit Voreinstellungen.** Vorhanden:
acht Vorlagen (Fahrzeug, Figur, Schnelltest, Eigene GPU, Höchste
Detailtreue, 3D-Druck und zwei für Roblox), dazu eigene Vorlagen.
Die Optionen richten sich nach dem Anbieter (Tripo: Face-Limit,
Textur, Rigging, PBR, Smart Low-Poly, Quad; Meshy: Ultra Mode,
Polygone; Rodin: Quad; Stability: Stufen; Lokal: Raster und
Tiefenkarten). **Umbenannt:** Die Roblox-Ziele heißen jetzt **„Figur
im Erlebnis"**, **„UGC-Accessoire"** und **„Marktplatz-Avatar"**, die
Vorlagen **„Roblox: Figur im Erlebnis"** und **„Roblox:
Marktplatz-Avatar"** – zwei Wege, zwei Regelwerke, ein Namensmuster.
Offen: Im 3D-Tab sind nicht zutreffende Optionen weiterhin
ausgeblendet statt ausgegraut; das ist die eigene Runde „3D-Tab in
derselben Sprache".

**Roblox-Prompts.** Durchgesehen: Figur, Accessoire und
Marktplatz-Körper haben je einen festen Schwanz, eine NEGATIV-Zeile
und einen erprobten Beispielblock; die Marktplatz-Fassung trägt die
gemessenen Grenzen (Tiefe, Beine, Hals, A-Pose) und verlangt Augen
und Mund als Volumen. Die Längen passen zu Tripos 1.024/255 Zeichen.
Keine Änderung nötig.

**„Direkt tauglich für den Marktplatz".** Hier steht die eine
Einschränkung, die kein Prompt und keine Reparatur aufhebt: Der
Marktplatz verlangt für den Kopf eines Ganzkörper-Bundles einen
dynamischen Kopf mit FACS-Posen, und dafür müssen **Augenhöhlen mit
Lidern und eine Mundhöhle mit Lippen im Kopfnetz** liegen. Tripo
liefert eine geschlossene Hülle; fünf Läufe haben gezeigt, dass
angesetzte Augen und Zähne nicht reichen. Was die App leistet:
Torso, Arme und Beine bestehen `ValidateUGCBodyPartAsync`; Maße,
Hals, Beine, Pose, Dreiecke, Textur, Ausrichtung sind geprüft und
reparierbar; das Konzept-Gate warnt vor Motiven ohne Gesicht. Was
sie nicht leisten kann, sagt sie vorher.

**Nachbearbeitung.** Vorhanden: Skelett nachträglich einbauen
(Typ wird erkannt), Rig-Editor, Dreiecksbudget, Preflight mit
Reparatur, Textur-Pipeline (Verkleinern, ein UV-Satz, ein Material,
Hautton), Textur-Beschreibung bei Tripo, Testanimationen als Clips
einbetten, Export als GLB/FBX/OBJ/STL/3MF mit Presets und
Roblox-Paket. **Neu: „Skelett entfernen"** im Vorschaufenster – das
Gegenstück zum Einbauen. Knochen, Gewichte und Animationen fallen
weg, das Netz bleibt exakt stehen (Bind-Pose); für Auto Setup Pflicht,
für einen Prop schlicht kleiner.

**Galerie.** Vorhanden: Projekte mit Ordnern, Suche, Auswahl mit
Bereichsmarkierung, Einsortieren, Sammel-Download, Nachweis-PDF.
**Neu:** Filter **Alle / Bilder / 3D** mit Zahlen, „Alle" trägt die
Gesamtzahl, jede Kachel nennt die Art („02.09. · GLB"), und aus der
Bildansicht führt **„→ 3D"** direkt als Vorderansicht in den 3D-Tab.

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

### Die Vorgabe für die 3D-Ansichten

Die Ansichten, aus denen die 3D-Pipeline rechnet, bekommen ihre
Kamera-Vorgabe ebenfalls in der Schreibweise des Modells. Für
GPT-Image und Gemini bleibt es der ausformulierte Auftrag mit
Verneinungen („NOT elevated, NOT from above"). Für Stable Diffusion
gibt es jetzt eine eigene Stichwortkette: Dort wären die Verneinungen
ein Eigentor — das Modell liest daraus „elevated", „from above" und
holt genau das ins Bild. Dazu geht erstmals ein Negativ-Prompt mit
(`from above, perspective distortion, ground plane, shadow, second
subject, cropped …`); Stability und der eigene Server haben ein Feld
dafür, es blieb bisher leer. Die Kette bleibt unter 40 Wörtern — dem
Budget des sparsamsten Modells; die ausformulierte Fassung hatte rund
90.

### Blickrichtung „Spielgrafik: isometrisch, 35° von oben"

Diese Blickrichtung ist für Bilder gedacht, die später als Asset auf
einen Karten-Knoten gesetzt werden. Sie bringt als einzige einen ganzen
Regelblock mit — er kommt in die Vorlage und wird beim Massenprompt
mitgeprüft. (Vorher war das ein eigener Schalter „Spielgrafik-Regeln";
der kannte genau eine Kamera und war für alles andere nutzlos. Jetzt
ist die Spielgrafik eine Blickrichtung unter anderen.)

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

**„Beispiel einfügen"** setzt bei der Blickrichtung „Spielgrafik"
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

## Jeder Bild-Prompt gegen sein Ziel gehalten

Eine Durchsicht aller Texte, die die App an ein **Bildmodell** gibt –
und aller Vorlagen, aus denen solche Texte entstehen. Die Frage war
jedes Mal dieselbe: Welches Modell bekommt diesen Prompt, und tut
darin jedes Wort etwas für das Ziel? Ein Bild, aus dem hinterher ein
3D-Modell gerechnet wird, braucht andere Wörter als ein hübsches Bild.

Der Ausgangspunkt ist die Landkarte: Derselbe Satz kann an drei ganz
verschiedene Empfänger gehen, und was beim einen wirkt, ist beim
anderen verlorener Platz.

| Empfänger | Wer das ist | Was dort wirkt | Was dort nichts tut |
| --- | --- | --- | --- |
| Bildmodell, Briefing | GPT-Image, Gemini | ganze Sätze, Verneinungen, Maße | Netz-Begriffe (`single mesh`) |
| Bildmodell, Stichworte | Stability, eigene GPU | dichte Kette, Reihenfolge = Gewichtung | Verneinungen, Sätze, Netz-Begriffe |
| Text→3D | Tripo, Meshy, Rodin | Form, Proportion, Netz-Begriffe | Kamera, Licht, Hintergrund |

Geprüft wurde mit Tests, nicht nach Gefühl: `test/image_prompt_audit_test.dart`
hält jeden Befund fest, `test/prompt_template_audit_test.dart` prüft
weiterhin jede Vorlage gegen jedes eingebaute Modell und jede
Blickrichtung.

### Der Gegenstands-Prompt hatte drei Empfänger und eine Fassung

**Befund.** Der Prompt für einen Gegenstand („Passende Gegenstände zu
einer Figur") geht auf drei Wegen los: als kopierter Block in den
Massenprompt des Bild-Tabs, über die Ansichten-Pipeline an ein
Bildmodell, oder direkt an Tripo/Meshy. Er sah auf allen drei Wegen
gleich aus und schleppte dabei jeweils Wörter mit, die dort nichts
bewirken können.

**Beleg.** Der Schwanz endete auf `even neutral lighting, plain flat
background`. Geht derselbe Text über die Ansichten, hängt
`viewFrontKeywords` seinerseits `single subject, centered … even
diffuse studio lighting` an – und bei jedem Anbieter außer OpenAI
zusätzlich `uniform magenta background, chroma key magenta`. Genau
diesen Magenta-Screen entfernt die App hinterher per Chroma-Key
(`removeGeneratedBackground`); bleibt weniger als 30 % des Bildrands
magenta, fällt sie auf den generischen Flutlauf zurück.
`plain flat background` arbeitet also gegen den einen Schritt, von dem
das Freistellen abhängt. Umgekehrt sagt die App in ihrer eigenen
Vorlage „Natives Text→3D": *keine Kamera-, Licht- oder
Qualitätswörter – Text-zu-3D-Modelle ignorieren sie oder werden
schlechter.* Und `closed watertight shell, single mesh` sagt einem
Bildmodell nichts – das steht seit Längerem so im Code, als
Begründung für `robloxAccessoryImageTail`; im allgemeinen Schwanz
standen die Wörter trotzdem weiter.

**Geändert.** Der Schwanz ist in drei Teile zerlegt
(`itemShapeTail`, `itemMeshTail`, `itemStagingTail`), und
`itemPromptParts` bekommt mit `ItemPromptTarget`, wer den Text liest.

| Empfänger | Formworte | Netz-Angaben | Inszenierung | Länge (Schwert, mit Stilvorlage) |
| --- | --- | --- | --- | --- |
| `image` (kopierter Block) | ja | nein | ja | 70 Wörter |
| `views` (Ansichten) | ja | nein | nein | 63 Wörter |
| `text3d` (Tripo/Meshy) | ja | ja | nein | 68 Wörter |

Der zusammengesetzte Ansichts-Prompt ist damit von 105 auf 93 Wörter
gefallen, `centered` und die Lichtangabe stehen je einmal statt
zweimal, und `plain flat background` steht dem Magenta-Screen nicht
mehr entgegen.

### Ein Verweis auf ein Referenzbild, das nie mitging

**Befund.** Mit eingeschalteter Stilvorlage begann der
Gegenstands-Prompt mit *„in exactly the same art style … as the
reference image"*. Ob wirklich eines mitgeht, wurde nicht geprüft.

**Beleg.** `generateViewsFromText` verwirft Referenzbilder, sobald der
Bild-Anbieter keine auswertet (`provider.supportsReferences` – das
sind nur OpenAI und Gemini). Und bei reinem Text→3D gibt es überhaupt
keinen Bildschritt. In beiden Fällen verwies der Prompt auf ein Bild,
das nie ankam – und die Figur, an deren Stil sich der Gegenstand
halten soll, stand dann nirgends mehr, weil die Beschreibung nur
*statt* des Verweises eingesetzt wird.

**Geändert.** Der Verweis steht nur noch, wenn alle drei Bedingungen
erfüllt sind: gerenderte Stilvorlage, referenzbildfähiges Bild-Modell,
Lauf über die Ansichten-Pipeline. Sonst wandert wieder die gekürzte
Figurbeschreibung in den Text.

### „no character in the image" holte den Charakter ins Bild

**Befund.** Derselbe Satz endete auf `no character in the image`. Der
Zusatz war ausdrücklich für die Modelle gedacht, die keinen
Negativ-Prompt auswerten (SDXL Turbo, FLUX schnell) – also für
Diffusions-Modelle.

**Beleg.** Es ist die Regel, vor der dieselbe App an vier Stellen
warnt: In einer Stichwortkette wirkt „no text" wie „text". Hier hieß
das Substantiv `character`, und genau das sollte nicht ins Bild. Bei
den Modellen, für die der Zusatz gedacht war, wirkte er also gegen
sich selbst.

**Geändert.** Positiv formuliert: *„but the image shows the object on
its own"*. Ausgeschlossen wird über die NEGATIV-Zeile, die ohnehin mit
`character, person, hand, arm` beginnt.

### Der Schalter „Roblox-Regeln anhängen" tat innerhalb der App nichts

**Befund.** Im Gegenstands-Dialog schaltet er die Roblox-Bausteine zu.
Beim **Kopieren** wirkte er; beim **Erzeugen** in der App nicht.

**Beleg.** `itemPromptParts` wertet `roblox` nur zusammen mit
`accessoryTail`/`accessoryNegative` aus, und der Lauf innerhalb der App
gab beide nicht mit. `roblox: true` änderte dort kein Zeichen.

**Geändert.** Der Lauf gibt sie jetzt mit – für die Ansichten die
Formworte (`robloxAccessoryImageTail`), für Text→3D den vollen
Schwanz (`robloxAccessoryTail`), dazu die NEGATIV-Begriffe.

### „plain fully transparent background" an ein Modell ohne Alphakanal

**Befund.** Die Ansichten kannten zwei Hintergründe: echtes Alpha oder
Magenta-Screen. Die eigene GPU wurde dem Alpha-Fall zugeschlagen und
bekam *„plain fully transparent background"* bestellt.

**Beleg.** Ein Diffusions-Modell hat keinen Alphakanal. Auf der
eigenen GPU schneidet **der Server** frei: `_cutout` in
`server/local_image_server.py` ruft rembg auf, ausgelöst durch
`transparent: true`. Die vier Wörter konnten dort also nichts
bewirken, während das, was das Freistellen wirklich braucht – eine
gleichmäßige, schattenfreie Fläche – nicht bestellt wurde.

**Geändert.** Aus dem Schalter ist `ViewBackground` mit drei Fällen
geworden:

| Anbieter | Bestellt wird | Freigestellt wird |
| --- | --- | --- |
| OpenAI | `plain fully transparent background` | vom Modell selbst (`background: transparent`) |
| Stability, Gemini | Magenta-Screen `#FF00FF` | Chroma-Key in der App |
| Eigene GPU | eine gleichmäßige, unbeleuchtete graue Fläche | rembg auf dem Server |

Alle drei Ketten bleiben unter 40 Wörtern, dem Budget des sparsamsten
Modells (SDXL Turbo): 31, 34 und 35 Wörter.

### Die Spielgrafik-Regeln nannten eine zweite Wortzahl

**Befund.** In einer einzigen kopierten Vorlage standen zwei
Höchstlängen: die des Modells („Höchstlänge des PROMPT-Blocks: etwa 40
Wörter") und die feste Zeile der Spielgrafik-Regeln („Zusammen unter
60 Wörter").

**Beleg.** Die feste Stil-Kette hat 34 Wörter. Bei SDXL Turbo
(40 Wörter) blieben dem Motiv damit 6, bei SD 1.5 (50) sechzehn – für
Gebäudeart *und* erkennendes Merkmal zu wenig. Der erprobte Block
selbst ist 53 Wörter lang und passt bei beiden gar nicht.

**Geändert.** Die Vorlage rechnet das Budget jetzt aus dem gewählten
Modell aus und schreibt es hin. Reicht es nicht, steht das dort auch:

| Modell | Budget | Feste Kette | Fürs Motiv | Text in der Vorlage |
| --- | --- | --- | --- | --- |
| SDXL Turbo | 40 | 34 | 6 | ACHTUNG … besser SDXL Base oder SD 3.5 |
| SD 1.5 | 50 | 34 | 16 | ACHTUNG … besser SDXL Base oder SD 3.5 |
| SDXL Base | 60 | 34 | 26 | „dem Motiv bleiben rund 26" |
| Stability Core | 60 | 34 | 26 | „dem Motiv bleiben rund 26" |
| FLUX.1 schnell | 120 | 34 | 86 | „dem Motiv bleiben rund 86" |

### Eine NEGATIV-Zeile für Modelle, die keine lesen

**Befund.** Dieselben Spielgrafik-Regeln verlangten „immer genau diese
Zeile NEGATIV:" – auch von SDXL Turbo und FLUX schnell, die ohne
Guidance laufen.

**Beleg.** Die Prüfung des Massenprompts sagt es seit Längerem selbst:
*„… wertet den NEGATIV-Block nicht aus (Guidance ≤ 1). Bodenfleck,
Bodenplatte und ein zweites Gebäude lassen sich damit nicht
ausschließen."* Der ganze Bodenausschluss der Spielgrafik hängt an
dieser Zeile. Der Server bestätigt es: `MODELS` in
`server/local_image_server.py` führt für beide Guidance `0.0`, und
`/health` meldet je Modell `negativePrompt: guidance > 0 and family
!= "flux"`.

**Geändert.** Bei diesen Modellen verlangt die Vorlage keine
NEGATIV-Zeile mehr, sagt stattdessen, dass der Boden **nirgends**
stehen darf – es gibt keinen Block, in den er ausweichen könnte –, und
empfiehlt dasselbe wie die Prüfung: SDXL Base oder SD 3.5.

### Die Roblox-Regeln an einer Bild-Vorlage

**Befund.** Im 3D-Tab hängt die App bei eingeschaltetem Roblox-Ziel
ihren Regelblock an die kopierte Vorlage – auch an die Bild-Vorlagen
„Figur für Bild→3D" und „Objekt/Fahrzeug". Der Block ist für Text→3D
geschrieben. Drei seiner Angaben stimmten dort nicht.

| Angabe im Block | Warum sie an einer Bild-Vorlage falsch ist |
| --- | --- |
| „KEINE T-Pose in den Prompt schreiben" | Die Vorlage „Figur für Bild→3D" verlangt zwei Zeilen weiter oben genau eine T- oder A-Pose. Den Posen-Zusatz hängt die App nur an einen Text→3D-Prompt an; einem Bild lässt sich die Pose nachträglich nicht mehr geben. |
| „Der PROMPT darf höchstens 1.024 Zeichen haben" | Das ist Tripos Grenze. Ein Bild-Prompt geht an GPT-Image, Gemini oder Stable Diffusion; dort greift sie nicht. |
| `closed watertight shell, single mesh` im festen Schwanz | Sagt einem Bildmodell nichts – dieselbe Begründung wie oben. |

**Geändert.** `robloxPromptRules` kennt jetzt einen Bild-Fall
(`image: true`, gesetzt vom 3D-Tab im Bild-Modus): Die Pose gehört
dann ausdrücklich **in** den Prompt – an beiden Stellen, an denen der
Block sie erwähnt –, Tripos Zeichengrenze entfällt mit
einem Verweis darauf, was stattdessen zählt, und beim festen Schwanz
steht, welche zwei Begriffe im Bild nichts bewirken. Der Bauplan, die
Dreiecksgrenzen und die NEGATIV-Zeile bleiben unverändert – die gelten
für beide Wege.

### Kleinigkeiten, die dabei auffielen

- **„Pixar-Stil" als Stilbeispiel** stand in der Vorlage „Figur für
  Bild→3D". Wer die Roblox-Regeln dazuschaltet, bekommt im selben
  kopierten Text „keine Marken- oder Figurenbezüge: Alles Hochgeladene
  geht durch die Roblox-Moderation". Jetzt steht dort „stilisierter
  3D-Zeichentrick".
- **Die fehlende Kamera-Angabe.** Die Ansichten, die die App selbst
  erzeugt, bestellen `orthographic view without perspective
  distortion` und führen `perspective distortion` im Negativ-Block.
  Für eine von Hand geschriebene Bildvorlage galt das nicht – dabei
  geht dieselbe Rekonstruktion darüber. Die Vorlage verlangt jetzt
  „wie durch ein langes Objektiv gesehen".
- **„die App wählt die Pose"** stand in der Vorlage
  „Motiv-Beschreibung". Das stimmt nur, solange Rigging oder der
  Posen-Schalter an ist; sonst bleibt `pose` null und das Bild bekommt
  gar keine. Die Vorlage sagt jetzt beides.
- **„15 Wörter Motiv"** stand als Kommentar am Massenprompt-Beispiel;
  die Vorgabe ist seit Längerem 20, das Beispiel hat 19. Die Zahlen im
  Vorlagentext werden jetzt aus dem Beispiel gerechnet statt
  festgeschrieben.

### Was in Ordnung war

- **`_turnPrompt` und `_depthPrompt`** (gedrehte Ansichten,
  Tiefenkarte) entstehen nur bei referenzbildfähigen Anbietern, also
  bei GPT-Image und Gemini. Sie dürfen deshalb Sätze und Verneinungen
  enthalten, und sie tun es.
- **`viewNegativePrompt`** geht nur dorthin, wo es ein Negativ-Feld
  gibt (Stability, eigene GPU mit Guidance) – geprüft über
  `negativeHandling == separateField`.
- **Die Vorlage „Objekt/Fahrzeug"** verlangt die Dreiviertelansicht
  und deckt sich mit dem, was `_frontPrompt` im
  Dreiviertel-Fall bestellt (rund 40° seitlich, leicht erhöht).
- **Der Massenprompt** setzt eine Zeile `NEGATIV:` je nach Modell als
  eigenes Feld ab, webt sie als Satz in den Prompt oder meldet, dass
  sie wirkungslos bleibt. Das war schon richtig.

### Was offen bleibt

- **Meshys Zeichengrenze ist ungeprüft.** Für Tripo stehen 1.024 und
  255 Zeichen im Code, und `clipToLimit` kürzt an einer Kommastelle,
  bevor die API mit 400 antwortet. `MeshyService` schickt `prompt`,
  `negative_prompt` und `texture_prompt` ungekürzt. Aus dieser
  Umgebung ließ sich Meshys Dokumentation nicht abrufen (der
  Netz-Proxy blockt `docs.meshy.ai`), und eine Zahl ohne Beleg
  einzutragen wäre schlimmer als keine. Der Punkt bleibt offen – zu
  tun ist: die Grenze in der Doku nachsehen und wie bei Tripo als
  Konstante mit `clipToLimit` eintragen.
- **Die harten Zeichengrenzen der Bild-APIs** (OpenAI, Gemini,
  Stability) konnten aus demselben Grund nicht gegen die
  Dokumentation belegt werden. Was die App stattdessen kennt und
  einhält, ist die Grenze, die praktisch zählt: Ein CLIP-Block fasst
  75 Tokens, also rund 60 Wörter – daraus stammen die Wortbudgets je
  Modell. Der eigene Server belegt das Verfahren: Er zerlegt lange
  Prompts in bis zu fünf Blöcke (`_MAX_BLOCKS = 5`, `_CLIP_CHUNK =
  75`) und meldet, wenn darüber hinaus etwas wegfiel.
- **Der Gegenstands-Prompt bleibt für die sparsamen Modelle zu lang.**
  Zusammengesetzt mit der Ansichts-Kette sind es 93 Wörter (vorher
  105); SDXL Turbo gewichtet 40, SDXL Base und Stability Core 60. Das
  liegt am Kern des Gegenstands plus Größensatz plus Stilverweis –
  jedes davon trägt Information, die das Ergebnis braucht. Gekürzt
  wurde deshalb nur, was nichts trägt. Der Lauf für Gegenstände geht
  außerdem nicht durch die Massenprompt-Prüfung und warnt darum auch
  nicht.

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
- Bei der Blickrichtung „Spielgrafik": Bodenplatten, ein möglicher
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
Die Ordnerleiste steht auch über der noch leeren Galerie — wer die
Ablage vorbereiten will, bevor das erste Bild da ist, kommt sonst nicht
an den Knopf.
Nach dem Anlegen bleibt die Ansicht stehen, wo sie war. Die erste
Fassung wechselte gleich hinein — in der Hand ist das falsch herum:
Nach Enter stand man in einem leeren Ordner, ohne die Kacheln, die man
gerade einsortieren wollte. Der neue Ordner steht in der Leiste, und
der Hinweis bietet „Öffnen" an.

**Kacheln markieren.** Der Knopf **„Auswählen"** über der Liste
schaltet den Auswahlmodus ein: Jede Kachel trägt dann ein Kästchen,
ein Tipp markiert sie. (Langes Drücken geht weiterhin, aber darauf
muss man erst kommen.) Oben stehen dann **„Alle"**,
**„Einsortieren …"** und **„Fertig"**. Zusammen mit der Suche lassen
sich so z. B. alle `burg-` auf einmal einsortieren.

**Einen ganzen Block markieren.** Die erste Kachel antippen, die letzte
mit **Umschalt** anklicken — alles dazwischen ist markiert. Auf dem
Handy gibt es keine Umschalttaste; dort zieht **langes Drücken** im
Auswahlmodus denselben Bereich. Nach einem Massenlauf mit vierzig
Kacheln ist das der Unterschied zwischen zwei Klicks und vierzig. Der
Anker ist immer die zuletzt angetippte Kachel; ist sie inzwischen aus
der Ansicht verschwunden, markiert der Umschalt-Klick nur sich selbst,
statt einen Bereich zu raten.

Unter „Einsortieren …" steht jedes vorhandene Projekt — auch ein eben
angelegter, noch leerer Ordner —, ein neues, ein Unterordner im gerade
geöffneten Ordner, oder „Ohne Projekt", um wieder herauszusortieren.

**„Ohne Projekt"** in der Ordnerleiste ist ein Filter: Ein Klick zeigt
nur noch die Einträge, die in keinem Projekt liegen — genau die, die
noch aufzuräumen sind. Ein zweiter Klick zeigt wieder alles.

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

### Hintergrund und Licht in der Anprobe

Die Anprobe stand auf einer gleichmäßig grauen Fläche, bei einem
Licht, das nie wanderte. Damit ließ sich schlecht beurteilen, was die
Anprobe beurteilen soll: ob ein Teil **an** der Figur sitzt oder **in**
ihr steckt.

Jetzt liegt hinter dem Modell ein senkrechter Verlauf statt einer
Fläche, und darunter ein weicher Bodenschatten — er folgt der
Kameraneigung, wird beim Blick von oben rund und bei waagerechter
Kamera flach. Damit hat das Bild ein Oben und ein Unten, und das
Modell steht, statt zu schweben.

Dazu fünf Lichtaufstellungen, umschaltbar über der Reglerreihe:

| Aufstellung | Wofür |
| --- | --- |
| Studio (von vorn oben) | Der ruhige Standard — genau das Licht von bisher |
| Von oben | Aufsicht und Silhouette: Hüte, Helme, alles auf dem Kopf |
| Von der Seite | Streiflicht: Wölbungen und Kanten treten hervor |
| Gegenlicht | Der Umriss steht scharf — ragt das Teil über die Figur hinaus? |
| Ohne Schatten | Gleichmäßig ausgeleuchtet, die reinen Farben |

Figur und Gegenstand bekommen dasselbe Licht — sonst wirkte der
Gegenstand wie hineinmontiert. Der Viewer bekommt Verlauf und
Bodenschatten ebenfalls; die Lichtauswahl steht (vorerst) nur in der
Anprobe, weil dort das Wandern des Lichts die eigentliche Auskunft ist.

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

### Preflight: zwei Stufen, mit Begründung und Reparaturknopf

Im Viewer (Klemmbrett-Symbol) prüft der **Preflight** ein Modell gegen
die Vorgaben des gewählten Asset-Typs. Neu ist die Trennung in zwei
Stufen:

- **Fehler** blockieren den Export — so nimmt Roblox das Modell nicht an.
- **Warnungen** blockieren nicht, kosten aber Qualität oder Nacharbeit.
- **Hinweise** sind Dinge, die sich aus der Datei nicht sehen lassen.
  Sie stehen trotzdem im Bericht, sonst wirkte die Liste vollständiger,
  als sie ist.

Sortiert wird nach dem, was in der Praxis zur Ablehnung führt: **oben
die Attachments und das Dreiecksbudget**, darunter Wasserdichtheit,
Wicklung, Volumen, Hüllquader-Füllung, Texturen, UVs, Materialien,
Transformationen, Maßstab, Cages, und ganz unten das, was die Datei
nicht hergibt.

Jeder Punkt sagt **warum** — eine Prüfliste, die nur „Fehler" meldet,
verschiebt die Arbeit nur. Wo die App reparieren kann, steht der Knopf
daneben: Dreiecke reduzieren, Hülle schließen, Textur verkleinern, für
Roblox anpassen. „Bericht kopieren" gibt alles als Text.

Drei Dinge kann die App **nicht** aus der Datei lesen, und sagt das
auch:

- **N-Gons** — glTF speichert ausschließlich Dreiecke. Die Zahl im
  Bericht ist die nach der Triangulierung, also genau das, was Roblox
  zählt.
- **Material „Plastic", Transparency 0, VertexColor 1,1,1** — das sind
  Eigenschaften des Teils in Studio, nicht der Datei. Das mitgelieferte
  Lua-Skript setzt sie beim Anlegen.
- **Cages** — Roblox verlangt ausdrücklich, dass sie aus den offiziellen
  Vorlagen übernommen und nicht selbst gebaut werden. Solange die
  Vorlage nicht vorliegt, meldet der Preflight ihr Fehlen, erzeugt aber
  keine.

### Dreiecksbudget: Regler mit Ampel

Im Viewer sitzt in der Werkzeugleiste ein Regler fürs Dreiecksbudget
(Tacho-Symbol). Er gilt für **jede GLB**, egal von welchem Anbieter sie
kommt, und wirkt nach dem Herunterladen.

- **Asset-Typ wählen** — starres Accessoire (4.000), Prop (20.000),
  Charakterkörper (10.742). Die Zahlen kommen aus `roblox_specs.json`.
- **Zähler und Ampel folgen dem Regler sofort.** Grün: unter 90 % des
  Budgets. Gelb: 90–100 % — passt, aber Löcher schließen, Cage und Naht
  bringen noch Dreiecke dazu. Rot: über dem Budget, so nimmt Roblox das
  Modell nicht an.
- **„Aufs Budget setzen"** stellt auf 85 % des Budgets.
- Gerechnet wird erst beim **Übernehmen**. Die Reduktion sucht ihr
  Raster binär und braucht bei einem großen Netz spürbar Zeit; bei
  jedem Reglerschritt neu zu rechnen machte den Regler unbenutzbar.

Der Regler ist **nicht linear** über die Dreieckszahl gelegt, sondern
logarithmisch: Der interessante Bereich liegt zwischen ein paar hundert
und ein paar tausend Dreiecken. Linear läge das alles im linken
Zehntel.

**Das Face-Limit für Tripo bleibt.** Es wirkt *vorher* — der Anbieter
baut gleich ein schlankeres Netz, und das sieht meist besser aus als
jede spätere Reduktion. Es greift nur eben bei Tripo; der Regler
ergänzt es für alle anderen.

**Ein Skelett übersteht das Reduzieren nicht** und die App sagt das
auch: Beim Zusammenlegen von Punkten lässt sich nicht mitteln, welchem
Knochen der neue Punkt gehört. Reihenfolge also: erst reduzieren, dann
riggen. Texturen überstehen es dagegen — die UV-Koordinaten werden wie
Position und Farbe gemittelt.

### Modul 3: Zerlegung in die 15 R15-Meshes

Roblox nimmt einen Figurenkörper nicht als ein Netz an. Er will 15
benannte Meshes (`Head_Geo`, `UpperTorso_Geo`, …), alle an dasselbe
R15-Skelett gehäutet. Die KI liefert dagegen **ein** Netz — und das ist
richtig so, denn nur daran lassen sich Skin-Gewichte sinnvoll erzeugen.

Die App macht aus dem einen die fünfzehn. Maßstab ist das Gewicht:
Jedes Dreieck kommt zu dem Teil, dessen Knochen an seinen drei Ecken am
schwersten wiegt. Kein Punkt wird verschoben, kein Dreieck geteilt — die
Naht liegt genau dort, wo die Häutung sie ohnehin hat. Über die drei
Ecken zu summieren statt je Ecke zu entscheiden verhindert einzelne
Dreiecke, die mitten in einer Fläche ins Nachbarteil springen.

**Zwischenknochen sind unschädlich.** Tripo liefert 43 Knochen, von
denen 16 R15-Namen tragen; `tripo::Spine_1` und Geschwister werden auf
ihren nächsten R15-Vorfahren zurückgeführt. An einer echten Figur waren
das 27 Knochen — und kein einziges Dreieck blieb ohne Zuordnung.

Nachgeprüft durch Import in Blender: 15 Objekte, jedes mit
Armature-Modifier am selben Skelett, UVs erhalten, Gesamtmaße
unverändert.

**Das Budget rechnet Roblox je Gruppe, nicht je Mesh** — Kopf 4.000,
Torso 1.750 (Ober + Unter), je Arm 1.248 (Ober + Unter + Hand), je Bein
1.248. Genau daran scheitert eine Figur, an der keine Mesh-Grenze
reißt:

| Gruppe | Kapuzzee | Budget |
| --- | --- | --- |
| DynamicHead | 1.816 | 4.000 |
| Torso | 1.330 | 1.750 |
| LeftArm | **1.956** | 1.248 |
| RightArm | **1.968** | 1.248 |
| LeftLeg | 1.240 | 1.248 |
| RightLeg | 1.237 | 1.248 |

Die Arme reißen es, weil Tripo Finger ausmodelliert: 1.292 und 1.382
Dreiecke allein für die Hände. Deshalb prüft die App zusätzlich den
**Handanteil** (höchstens 1.000 für beide zusammen). Die Abhilfe steht
im Prompt, nicht im Netz — `rounded mitten stumps without separate
fingers` nimmt der Hand zwei Drittel ihrer Dreiecke. Nachträglich zu
dezimieren zerstört gerade an der Hand die Form.

### Marktplatz: die Regeln, die nirgends stehen

Eine Figur kann im eigenen Erlebnis tadellos laufen und trotzdem vom
Marktplatz abgelehnt werden. Diese Grenzen stehen **nicht in Roblox'
Dokumentation**; sie sind am Validator gemessen (Stand 31.08.2026), teils
aus dessen Quelltext (`UGCValidation/flags/`). Alle Werte bei 5 Studs
Figurenhöhe:

| Regel | Grenze |
| --- | --- |
| Tiefe (kleinere waagerechte Achse) | höchstens **2,00** |
| Bein-Breite je Seite | höchstens **1,50** |
| Bein-Tiefe je Seite | höchstens **2,00** |
| Rumpfbreite | mindestens **2,54** |
| Armspanne | mindestens **6,22** |

Dazu drei Prüfungen, die **ohne Skelett** auf der Gesamtfigur laufen:

- **Tiefe.** Reißt sie, ist die Figur für den Marktplatz verloren, egal
  was danach kommt — flach drücken geht nicht, ohne sie zu verformen.
- **Hals.** Die schmalste Stelle zwischen Kopf und Schulter muss
  höchstens **50 %** der Kopfbreite messen. Die Zahl kommt aus einem
  gescheiterten Lauf: Eine Figur mit 59 % wurde von Auto Setup
  segmentiert, als gehörte die Kapuze bis zu den Schultern zum Kopf —
  heraus kam ein „Head" von 3,75 Studs Breite.
- **Bein-Breite.** Höchstens 1,50 je Seite, gemessen an der breitesten
  Insel unterhalb der Hüfte. Zu breit heißt fast immer: Es ist gar nicht
  das Bein, sondern ein Saum, der mitgemessen wird.
- **Getrennte Beine.** In den unteren 45 % der Höhe muss der Querschnitt
  in mindestens 80 % der Höhenbänder in zwei Inseln zerfallen. Was beide
  Beine verbindet, ist fast immer ein Saum — er bläht den Hüllkörper des
  Beins auf, während das Bein darin dünn bleibt, und reißt Deckung und
  die Regel `LegsSeparated` zugleich.

Gemessen wird an **Dreiecken, nicht an Punkten**. Der erste Anlauf
zählte nur Vertices, und an einer grob unterteilten Stelle zerfiel ein
einzelnes Bein in sieben „Inseln": Ein Dreieck, das ein Höhenband
überspannt, hat dort gar keinen Punkt.

Die **Armspanne wird als größere waagerechte Achse bestimmt**, nicht als
x angenommen. Ein Lauf kam mit der Armspanne auf z herein; wer x
voraussetzt, misst dann die Tiefe als Breite und lässt eine abgelehnte
Figur durchgehen.

An der Figur „Kapuzzee" gemessen: Tiefe 2,45 (Grenze 2,00), Armspanne
6,22, kein Hals, Beine zu 45 % getrennt — genau die Punkte, an denen der
Marktplatz sie abgewiesen hat.

**Diese Fehler entstehen beim Prompt, nicht beim Export.** Die Prüfung
ist deshalb vor allem eine Frühwarnung: Sie sagt, dass der nächste Lauf
einen anderen Prompt braucht. Jeder Befund nennt den Textbaustein dazu.

### Die Prompt-Vorlage „Marktplatz-Avatar"

Die Formfehler entstehen beim Prompt, nicht beim Export — deshalb gibt es
für den Marktplatz-Weg eine eigene Vorlage mit eigenem festem Schwanz.
Sieben Bausteine, jeder aus einem gemessenen Grund:

| Baustein | Warum |
| --- | --- |
| `body depth less than two fifths of body height, flat chest and back` | Die abgelehnte Figur hatte 49 %, die Grenze liegt bei 40 % |
| `garment hem ending at the hip bone, thighs uncovered` | „hip-length" las Tripo als Mitte Oberschenkel — der Saum landete im Bein-Hüllkörper |
| `two separate leg tubes from the hips down` | `LegsSeparated` und die Deckungsprüfung zugleich |
| `slim straight legs each narrower than one third of body height` | Grenze 1,50 von 5,00 |
| `mitten hands without fingers` | Ausmodellierte Finger kosteten je Hand über 1.280 Dreiecke — mehr als der ganze Arm haben darf |
| `narrow visible neck clearly separating head from shoulders` | Ohne Einschnürung wurde die Kapuze bis zu den Schultern zum „Kopf" von 3,75 Studs |
| `face fully visible, eye sockets with eyelids and a mouth with lips shaped into the head` | Der Marktplatz verlangt einen dynamischen Kopf mit FACS-Posen, und Auto Setup baut sie nur aus Lidern und Lippen **im Kopfnetz**. Hier stand „two hemisphere eyes and a mouth modelled as separate volumes" — Lauf 5 hat entschieden, dass genau das nicht reicht |

**`chunky` fliegt raus.** Genau dieses Wort hat die Tiefe bestellt, die
jetzt abgelehnt wird. In der Vorlage für die Figur im eigenen Erlebnis
bleibt es — dort gilt die Grenze nicht.

**A-Pose statt T-Pose.** Im ersten echten Lauf durch Auto Setup wurden
die waagerechten Arme der T-Pose dem Kopf und dem Rumpf zugeschlagen —
heraus kam ein „UpperTorso" von 4,38 Studs Breite. Arme in 45° hängen
frei und sind als Arme erkennbar.

Ins Negativ, ganz vorn das, was das Gesicht verdeckt, dann die
Formfehler: `hood, helmet, mask, visor, deep body, round belly, long
hem, thigh-length, skirt, cape, fingers, T-pose, arms out sideways,
thick legs, …`

Die Vorlage setzt außerdem die Schalter, die bisher von Hand gesetzt
wurden: Rigging aus, T-Pose aus, Smart Low-Poly an, PBR aus, Textur
1024, **face_limit 7.000** und Skalierung auf 5 Studs. Die 7.000 statt
10.000, weil Auto Setup selbst nicht reduziert: Bei 9.627 Dreiecken bekam
jede Gliedmaße 2.304 — bei einem Gruppenbudget von 1.248.

### Die Vorlagen gegen ihr Ziel gehalten

Sind die Vorlageprompts wirklich alle gut? Nein, nicht alle waren es.
Die Bild-Vorlagen je Modell und die Spielgrafik-Vorlage stimmten. Die
Marktplatz-Vorlage trug an drei Stellen noch den Wissensstand von vor
Lauf 5, dazu kamen vier nachgemessene Mängel. Alles in einer Runde
behoben:

- **Das Marktplatz-Beispiel war die Kapuzenfigur.** „hooded creature …
  eyes and a small mouth inside the hood opening" — wörtlich das
  Konzept, das fünfmal gescheitert ist. Das Konzept-Gate hielt es nicht
  auf, weil „eyes" und „mouth" dastanden. Jetzt zeigt das Beispiel die
  Figur **unter** der Kapuze: sichtbares Gesicht, Lider, Lippen. Die
  Kapuze kommt als Accessoire dazu. Ein Test hält das Beispiel gegen
  das Gate und gegen die Wörter Kapuze, Helm, Maske, Visier, Schatten.
- **Der Schwanz bestellte „eyes and a mouth as separate volumes".**
  Jetzt: `face fully visible, eye sockets with eyelids and a mouth with
  lips shaped into the head`. Der Regeltext sagt dazu, warum, und nennt
  den Ausweg über die Gegenstandsarten Kapuze, Helm, Maske.
- **Das Negativ schloss nichts aus, was das Gesicht verdeckt.** Jetzt
  stehen `hood, helmet, mask, visor` ganz vorn — der einzige Fehler,
  den weder Prompt noch Reparatur nachträglich beheben. „painted flat
  eyes" ist dafür gewichen; das bestellt der Schwanz positiv.
- **Das Motiv-Budget steht jetzt im Regeltext.** „Höchstens 1.024"
  allein ließ die Prompt-KI ein langes Motiv schreiben, und Tripo
  kürzte hinten — also die Regeln weg. Jetzt rechnet der Text vor, was
  der Schwanz belegt und was fürs Motiv bleibt, je Ziel:

  | Ziel | Schwanz | Posen-Zusatz | bleibt fürs Motiv |
  | --- | --- | --- | --- |
  | Marktplatz-Körper | 737 | in der Pose enthalten | 285 |
  | Figur im Erlebnis | 267 | 121 | 634 |
  | Accessoire | 228 | — | 794 |

- **Zwei Gegenstands-Negative lagen über Tripos 255.** Kapuze 288,
  Reitvogel 261 — Tripo kürzte stillschweigend hinten. „set of objects"
  ist aus dem allgemeinen Negativ gestrichen (deckt „second object"
  ab), die Kapuze kürzer, und Listen werden jetzt **ohne Doppelte**
  gemischt. Ein Test prüft jede der 30 Arten auf beiden Wegen.
- **Die Posen-Erkennung hatte falsche Treffer.** „striking a pose" und
  „posed" galten als Pose — dann hängte die App keine an, und die
  Figur kam dynamisch zurück. Jetzt mit Wortgrenzen, und „a pose" nur
  noch als „A-pose", „a_pose" oder „A pose" mit großem A.
- **Figur-Negativ „arms down" gegen A-Pose.** Wer auf dem Figur-Weg
  die A-Pose wählte, hatte „angled 45 degrees down" im Prompt und „arms
  down" im Negativ. Jetzt `arms along the body` — gemeint war nie die
  Richtung, sondern das Anliegen.
- **Kopierte Gegenstände mit Roblox an** bekamen den 3D-Schwanz
  („watertight shell, single mesh") **statt** der Bild-Inszenierung
  („shown alone, centered, plain background") und verloren `hand, arm`
  aus dem Negativ — den häufigsten Fehlschlag. Jetzt kommt ein
  Bild-Schwanz mit den Formworten **dazu**, und die Negative werden
  gemischt statt getauscht. Der Block geht an ein Bildmodell, dort gilt
  die 255er-Grenze nicht.
- **Zwei veraltete Texte.** „Natives Text→3D" behauptete, die App hänge
  die T-Pose bei Rigging an — der Posen-Schalter steht standardmäßig
  auf Aus, und die Vorlage sagt das jetzt. „Figur für Bild→3D" nannte
  die A-Pose „Arme seitlich ausgestreckt"; das ist die T-Pose.

### Gegen die Dokumentation geprüft: Skalen, Mindestmaße, Deckung

Eine Prüfung gegen die aktuelle Roblox-Dokumentation und die
Validator-Regeln hat drei Stellen gekippt, an denen die App aus
Messwerten statt aus der Doku gearbeitet hat. Die Tabellen stehen unter
„Character body specifications" (nachgesehen 3. September 2026, aus dem
öffentlichen Doku-Spiegel; sie liegen jetzt auch in
`assets/roblox_specs.json` unter `bodyScales`, mit Quelle und Datum).

**Die Grenzen sind absolut in Studs, nicht relativ zur Höhe.**

| Skala | Kopf max (B×H×T) | Rumpf max | Bein max | Körper max | Tiefe |
| --- | --- | --- | --- | --- | --- |
| Classic (Rig Scale R15) | 1,5 × 1,8 × 2 | 4 × 3,8 × 2 | 1,5 × 3,5 × 2 | 8 × 9,1 × 2 | 2,00 |
| Normal (Rig Scale Rthro) | 3 × 2 × 2 | 4,6 × 3,5 × 2,25 | 1,5 × 4 × 2 | 8,6 × 9,5 × 2,25 | 2,25 |
| Slender (Rthro Slender) | 2 × 2 × 2 | 3 × 3,5 × 2 | 1,5 × 4 × 2 | 6 × 9,5 × 2 | 2,00 |

Minimum für alle Skalen: Kopf 0,5³, Arm 0,25 × 1,5 × 0,25, Rumpf
0,85 × 1,7 × 0,7, Bein 0,25 × 1,4 × 0,5, Körper 1,35 × 3,6 × 0,7.

Was das geändert hat:

- **Tiefe.** „2,00 sind 40 % von 5,00" war Zufall der Größe; die
  Grenze ist 2,00 (Classic, Slender) oder 2,25 (Normal), bei jeder
  Höhe. Prüfung und Reparatur rechnen jetzt mit der Skala, und der
  feste Schwanz leitet sein Wort aus Höhe und Skala ab – immer das
  größte Wort, das noch unter der Grenze bleibt („less than two
  fifths" bei 5 Studs für alle drei Skalen, „less than one third" bei
  6 Studs Classic). Eine Zwischenfassung sagte bei 5 Studs Normal
  „less than half" – das sind 2,5, über den 2,25; siehe den Nachtrag
  unten.
- **Der große Kopf sprengt die Höhenrechnung.** Rumpf 1,7 und Bein
  1,4 sind absolut; bei 5 Studs bleiben unter einem 2-Studs-Kopf nur
  3,0. Die Prüfung misst jetzt Kopf-, Rumpf- und Beinhöhe am Netz (der
  Schritt ist das höchste Band, das noch in zwei Beine zerfällt) und
  meldet beide Auswege: Kopf auf ein Viertel der Höhe, oder mehr
  Studs. Der Schwanz bestellt „head about one quarter of body height",
  das Beispiel keinen „oversized" Kopf mehr.
- **Die Skala ist wählbar** (Körper-Skala neben der Höhe, Vorgabe
  Normal): Nur dort darf der Kopf bis 3 Studs breit sein, Classic
  deckelt bei 1,5. Die Prüfung sagt, welche Skala zum gemessenen Kopf
  passt, und die Paket-Anleitung nennt den Rig Scale für Studio.
- **„thick legs" im Negativ war verkehrt herum.** Jedes Teil muss 50 %
  seines Hüllkörpers füllen, von vorn, von der Seite, von hinten, der
  Kopf eingeschlossen — seit dem 17. August 2026 wird darauf schärfer
  geprüft, ausdrücklich gegen zu kleine Gliedmaßen. Die früheren
  Schwellen (Rumpf 50/46, Beine 30, Kopf 30, Arme gar nicht) waren
  kein Ziel, sondern ein Grenzfall. Jetzt 50 überall, „slim legs" und
  „thick legs" sind raus, „sturdy arms and legs filling their
  outlines" und „spindly limbs" im Negativ sind drin.
- **Modesty-Layer.** „thighs uncovered" ließ nackte Haut, wo die
  Marktplatz-Policy Bedeckung verlangt: von der Hüfte bis unter
  Schritt und Gesäß, undurchsichtig, in einer anderen Farbe als die
  Haut. Der Schwanz bestellt eng anliegende Shorts, die der Beinform
  folgen — kein hängender Saum, also kein Konflikt mit den getrennten
  Beinen. Das Konzept-Gate warnt bei „naked", „nackt".
- **Keine Anbauten.** Erlaubt sind genau ein Kopf, ein Rumpf, zwei
  Arme, zwei Beine; Schwanz, Flügel, Hörner, abstehende Ohren und
  Haarsträhnen werden Accessoires („must be uploaded separately"). Das
  Negativ nennt sie, das Konzept-Gate warnt, das Beispiel sagt
  „humanoid" statt „creature".
- **Outer Cages.** Der eigentliche Mechanismus hinter dem
  Saum-Problem: Der Validator verlangt, dass das Render-Mesh im Outer
  Cage des Teils liegt, den Auto Setup um das Teil legt. Ein Saum
  ragt heraus. Das steht jetzt in den Befunden, wo vorher nur
  „Deckung" stand.
- **Dynamischer Kopf.** Mindestens 17 FACS-Posen, und der Validator
  prüft, ob sich Lider und Lippen für Blinzeln, Mundöffnen, fröhlich
  und traurig wirklich bewegen. Augenbrauen und Wimpern gehören als
  Accessoires ans Bundle. Beides steht im Regeltext; ob Höhle plus
  Grat dafür reicht, entscheidet weiterhin der Lauf.
- **Messwerte als Reserve, Doku als Grenze.** Rumpfbreite 2,54 und
  Armspanne 6,22 stammen aus einem echten Validator-Lauf, die Doku
  nennt 0,85 und keine Spanne; zwischen beiden gibt es offene
  Bugreports. Die Prüfung sagt jetzt bei diesen Werten, woher sie
  kommen.
- **Der Posen-Schalter steht beim Marktplatz aus.** Die A-Pose steht
  im festen Schwanz; die App hätte ohnehin keine zweite angehängt
  (sie erkennt die Pose im Text), aber der Schalter zeigte „A-Pose"
  an und erklärte nichts. Jetzt steht er auf „Keiner" mit dem Satz,
  warum – und seit dem Nachtrag unten ist er dort auch gesperrt.

### Nachtrag zur Doku-Prüfung: Tiefe und Posen-Schalter

Zwei Fehler steckten noch in der überarbeiteten Fassung.

- **Die Tiefenangabe war zu großzügig.** Der Schwanz bestellte „body
  depth less than half of body height" – bei 5 Studs sind das 2,5,
  über dem Maximum von 2,25 (Normal) und weit über 2,00 (Classic,
  Slender). Die Rechnung hatte das nächstgrößere Wort genommen, wenn
  es „nah genug" lag. Jetzt nimmt sie das größte Wort, das noch unter
  der Grenze bleibt: bei 5 Studs für alle drei Skalen wieder `body
  depth less than two fifths of body height` (2,0), bei 6 Studs
  Classic „one third", bei 8 „a quarter", darüber „a fifth". Ein Test
  rechnet für jede Skala von 3,6 bis 9,5 Studs nach, dass Wort mal
  Höhe nie über der Grenze liegt. Der Schwanz ist damit 737 Zeichen
  lang, dem Motiv bleiben 285.
- **Der Posen-Schalter widersprach sich.** Die Vorlage „Natives
  Text→3D" sagte „für eine riggbare Figur muss er an sein", der feste
  Marktplatz-Schwanz enthält die A-Pose aber schon. Mit eingeschaltetem
  Schalter wäre der Text über Tripos 1.024 gelandet, und Tripo kürzt
  hinten – wo die Regeln stehen. Jetzt ist der Schalter beim
  Marktplatz-Ziel **gesperrt** auf „Keiner" (mit dem Satz, warum), der
  fertige Prompt bekommt dort keinen Zusatz, was auch immer gespeichert
  war, und die Ansichten nehmen die A-Pose aus dem Schwanz.
- **Die Vorlage rechnet statt zu behaupten.** „Höchstens etwa 850
  Zeichen, rund 120 für den Posen-Zusatz" war eine Zahl von gestern.
  Die beiden Zeilen zu Pose und Länge werden beim Kopieren zum Ziel
  eingesetzt: beim Marktplatz „Schalter bleibt auf Keiner" und das
  Motiv-Budget, das auch der Hinweis unter dem Feld zeigt (285); mit
  Roblox-Figur der Verweis auf die Roblox-Regeln, die es unten
  vorrechnen; ohne Roblox die Grenze minus gewähltem Posen-Zusatz
  (T-Pose 119, A-Pose 108 Zeichen). Zwei Widget-Tests halten den
  gesperrten Schalter und den kopierten Text fest.

### Die erste Figur mit dem Marktplatz-Schwanz

Das Beispielmotiv der Vorlage, unverändert an Tripo (P1-20260311,
face_limit 5.500, Smart Low-Poly, ohne Rigging): 5.321 Dreiecke, ein
Netz, A-Pose, Gesicht sichtbar, Ohren, Pullover, Shorts – die Form,
die der Schwanz bestellt. Die Prüfung der App auf der rohen Datei sah
0,93 Studs ohne Gesichtsteile; das ist der Zustand vor dem Herrichten.
Nach „Für Roblox vorbereiten" (5 Studs, Zehen nach +Z, Gesicht ins
Kopfnetz, Gesichtsteile) ergibt die Messung:

| Maß | gemessen | Grenze | Urteil |
| --- | --- | --- | --- |
| Tiefe | 2,15 (43 %) | 2,25 Normal / 2,00 Classic, Slender | nur Normal |
| Kopf breit | 1,84 | 3,0 Normal | ok |
| Kopf hoch | 1,40 (28 %) | etwa ein Viertel | knapp |
| Hals | 55 % der Kopfbreite | höchstens 50 % | Reparatur schnürt auf 45 % |
| Schritt | 0,90 Studs | Bein mindestens 1,4 | **Stummelbeine** |
| Beine getrennt | 50 % der Bänder | 90 % | **Block bis zum Knie** |
| Augen | 0,38 Studs **vor** dem Gesicht | Höhle 0,06 tief | **Kugeln statt Höhlen** |
| Armspanne | 5,36 | 6,22 (Reserve aus dem Validator) | Warnung |
| Hände | Finger | Fäustlinge | Warnung im Bericht |

Drei Dinge hat der Prompt bestellt und Tripo anders gebaut, und keines
davon behebt eine Reparatur:

- **„small stocky … sturdy legs" wurden Stummelbeine.** Der Schritt
  liegt bei 0,9 Studs, verlangt sind 1,4; die Shorts sind ein Block bis
  zum Knie. Der Schwanz sagte nur „two separate leg tubes", nichts über
  die Länge. Jetzt: `two separate legs one third of body height with a
  gap between the thighs`, im Beispiel „compact humanoid" statt „small
  stocky" und „sturdy legs a third of body height", im Negativ „short
  legs".
- **„large round eyes with thick eyelids" wurden Kugeln aus dem
  Kopf.** Die Augen stehen 0,38 Studs vor der Gesichtsfläche. In einen
  Buckel lässt sich keine Höhle schneiden: Das Gesicht-ins-Kopfnetz
  macht ihn nur flacher (auf 0,25) und hat sein Budget vorher
  verbraucht. Jetzt: `eyes sunk into sockets with eyelids` im Schwanz,
  „eyes sunk into the head" im Beispiel, „bulging eyes" im Negativ; der
  Einbau sagt es, wenn er Kugeln vorfindet.
- **Das Beispielmotiv war zu lang.** 329 Zeichen bei 285 Budget – mit
  dem Schwanz 1.068, und Tripo schneidet hinten ab: „few flat separated
  color areas, uniform material" wären weg gewesen, beim Beispiel, das
  die Vorlage selbst vormacht. Jetzt 266 Zeichen, und ein Test hält das
  Beispiel unter dem Budget. Um Platz zu behalten, ist der Schwanz an
  zwei Stellen kürzer („narrow visible neck between head and
  shoulders", Shorts ohne „following the leg shape"), „logo" und „arms
  out sideways" sind aus dem Negativ.

**Die Reparatur hat diese Figur beschädigt – und merkt es jetzt.** Der
Beinschnitt nahm den Streifen zwischen Hüfte (2,25) und Schritt (0,9)
heraus, die Klemme zog den Bauch auf 0,75 Studs an die Beinmitten:
danach zeigten 2.800 statt 1.400 Dreiecke im Rumpf nach innen, die
längste Kante war 1,4 statt 0,6, und die Beine waren zu 41 statt 50 %
getrennt – der Bericht meldete „freigeschnitten" und „geklemmt". Zwei
Wächter stehen jetzt davor:

- **Umstülp-Wächter.** Hals, Klemme, Beinbreite und Armsenkung messen
  an einer Kopie, wie viele Dreiecke ihre Normale umkehren; mehr als
  ein halbes Prozent (mindestens 20), und der Schritt wird
  zurückgenommen, mit dem Satz, was stattdessen in den Prompt gehört.
- **Der Beinschnitt auf Probe.** Nach Schnitt und Klemme wird geheilt
  und nachgemessen, wie am Ende auch. Wird die Trennung nicht besser
  oder der Schritt tiefer, kommt die Geometrie von vor dem Schnitt
  zurück. Bei dieser Figur: „Der Schnitt brachte die Trennung von 50
  auf 41 % und den Schritt von 0,90 auf 0,80 Studs – zurückgenommen.
  Bei einem Schritt von 0,90 Studs ist das kein Saum vor zwei Beinen,
  sondern ein Rumpf, der bis kurz über den Boden reicht." Die
  Testfigur mit echtem Saum wird weiter geschnitten; dort bestätigt
  die Probe den Schnitt.

**Zwei Fehler der App, die diese Figur erst sichtbar gemacht hat:**

- **Das automatische Herrichten lief nie.** Die Vorlage verspricht,
  dass nach dem Lauf hergerichtet und vermessen wird – die Prüfung im
  Bild zeigte aber die rohe Datei (0,93 Studs, keine Gesichtsteile).
  Ursache: Das Herrichten wurde direkt nach dem Ergebnis angestoßen,
  der Lauf holte danach aber noch das Guthaben, und solange
  `_running` stand, ließ das Herrichten sich selbst nicht zu – still.
  Jetzt wird die Figur vorgemerkt und hergerichtet, sobald der Lauf
  zu Ende ist. Es muss nichts mehr geklickt werden: Bei der Vorlage
  „Roblox: Marktplatz-Avatar" kommt die Figur hergerichtet in die
  Liste, mit dem Vermerk „Marktplatz: hergerichtet …", und bei
  Fehlern öffnet sich die Reparatur.
- **Die Wicklungs-Vereinheitlichung stülpte die Hülle um.** „Für
  Roblox anpassen" und das Herrichten drehen zuerst alle Dreiecke in
  eine Richtung. Der Algorithmus reichte die Richtung über jede
  geteilte Kante weiter – auch über Kanten, an denen drei oder mehr
  Dreiecke liegen (Saumring, Bund, Augapfel im Gesicht). Dort
  durchläuft die Innenwand die Kante zwangsläufig wie eines der
  beiden Hüllendreiecke, wurde „korrigiert", und über sie dann die
  Hülle dahinter: 1.737 von 5.321 Dreiecken gedreht, die Hülle in
  Flecken nach innen (Blender zählte 22 solcher Kanten). Jetzt läuft
  die Richtung nur über Mantelkanten mit genau zwei Dreiecken, und
  die Prüfung zählt „gegenläufige" Kanten auch nur dort – die 42, die
  sie an dieser Figur meldete, waren Innenwände. Ein Test mit einem
  Würfel und einer Wand quer hindurch schlägt am alten Code fehl.

Was bleibt: Diese Figur braucht einen neuen Lauf mit dem geänderten
Prompt. Die Tiefe (43 %) geht nur in der Skala Normal durch; wer
Classic will, braucht „flat chest and back" stärker im Motiv als den
Bauch.

### Die zweite Figur: drei Messfehler der App

Derselbe Weg noch einmal, mit dem geänderten Prompt. Diesmal lief das
Herrichten von selbst, und die Reparatur behob Hals, Beinschnitt, Saum,
Löcher, Dreieckszahl und die Pose (Tripo lieferte trotz „A-pose" im
Schwanz und „T-pose" im Negativ eine T-Pose). Der Bericht danach hat
drei Dinge falsch dargestellt:

- **Ein grüner Haken auf einem offenen Befund.** Die Zeile „Armspanne
  4,12 von mindestens 6,22 Studs: – → offen" trug den grünen Haken,
  also „Die App hat es behoben". Das Symbol kam aus der *Herkunft* des
  Schritts (App oder Prompt), nicht aus dem Ergebnis; eine Nachmessung
  mit Herkunft „Export" bekam ihn deshalb ebenfalls. Dasselbe traf
  „Tiefe: 3,20 → 3,20", wenn die Tiefe zu groß zum Stauchen war. Jetzt
  hat jeder Schritt ein Feld `fixed`, das aus dem Ergebnis kommt: grüner
  Haken nur, wenn die Regel wirklich erfüllt ist, Stift für „offen, das
  muss der Prompt richten", Ausrufezeichen für „offen, aber am Export
  oder an der Messung".
- **Die Armlänge maß den Arm gegen sich selbst.** Geschätzt wurde
  `(Spanne − Schulterbreite) / 2 × √2`. Die Schulterbreite war die
  Breite des ganzen Bandes an der Schulter — und dort hängt der Arm am
  Rumpf, steckt also in derselben Insel. Für diese Figur: Spanne 4,12,
  „Schulter" 2,90, Ergebnis 0,87 — Warnung „Arm zu kurz", obwohl der Arm
  1,7 Studs lang ist. Jetzt wird der Rumpf **im selben Band** gemessen,
  in dem auch die Spanne entsteht (dem breitesten): dort steht die Hand
  in der A-Pose frei neben dem Körper, der Rumpf misst 1,74, und der Arm
  kommt auf 1,69 — über dem Mindestmaß von 1,5. Ist die Mitte dieses
  Bandes frei, sagt die Schätzung nichts und wird gar nicht erst
  gemeldet.
- **Eine T-Pose-Schwelle an einer A-Pose-Figur.** Die 6,22 Studs
  Armspanne stammen aus einem Validator-Lauf **in T-Pose**. Der
  Marktplatz-Schwanz bestellt aber eine A-Pose, und dort ist dieselbe
  Armlänge um cos 45° schmaler — die App maß also gegen eine Schwelle,
  die sie durch ihren eigenen Prompt unerreichbar gemacht hatte. Jetzt
  wird die Schwelle über den gemessenen Rumpf umgerechnet (hier 4,91
  statt 6,22), und die Zeile nennt beide Zahlen. Aus demselben Grund
  rechnet die Armlänge das √2 nur noch in der A-Pose heraus; in T-Pose
  fiel die Schätzung vorher 41 % zu hoch aus.

**Was am Prompt lag: die Hüfte, nicht die Beine.** Die Figur hatte
Beine von 1,00 Studs statt 1,4 — obwohl im Schwanz „two separate legs
one third of body height" stand. Der Grund: Die Beine sind, was unter
der Hüfte übrig bleibt, und über die Hüfte sagte der Satz nichts. Tripo
baute den Rumpf bis 2,70 von 5,00 hinunter; darunter blieb 1,00. Jetzt
steht eine Linie im Schwanz, die sich messen lässt: `hips at mid body
height, two separate legs with a clear gap between the thighs`. Im
Beispiel und in den Befunden ebenso — eine Länge zu bestellen half
nicht, eine Höhe schon.

### Das Gesicht: warum es Matsch wurde

Bis hierher waren Ganzkörper-Bilder und Bandmessungen geprüft, das
Gesicht nicht. Es war der schlimmste Teil. Der Kopf der zweiten Figur
hatte im Augenbereich ausgerissene Krater und im Profil ein Feld
vorstehender Zacken, während der Hinterkopf glatt blieb. Isoliert man
die Stufen einzeln und rendert den Kopf nach jeder, wird die Ursache
sichtbar: **Tripo liefert ein saubereres Gesicht, als die App daraus
macht.**

| Stufe | Zustand des Kopfs |
| --- | --- |
| Tripo, roh | Augäpfel in Lidern, Brauen, Nase, Mund mit Lippen — sauber |
| nach „Gesicht ins Kopfnetz" (1×) | Keile in die Augäpfel gefräst |
| nach 2× | Brauen zerrissen, Mundwulst |
| nach 3× | unkenntlich |

**Der Wächter hat nie gegriffen.** Vor dem Eingriff fragt der Code
„sind schon Höhlen da?" und misst dazu `Rand minus Mitte` am
Augenzentrum. Ein modellierter Augapfel steht **vor** der Fläche, das
ergibt eine **negative** Tiefe — und die galt als „nichts da". Gemessen:

| Kopf | Auge | Mund | Schwelle | „hasFace" alt |
| --- | --- | --- | --- | --- |
| leerer Testkasten | 0,000 | 0,000 | 0,047 | false (richtig) |
| Tripo, roh | −0,376 | −0,088 | 0,051 | false (**falsch**) |
| nach 1× Sculpt | −0,256 | 0,045 | 0,051 | false |
| nach 2× Sculpt | −0,135 | 0,181 | 0,051 | false |

Weil das Ergebnis nie eine Höhle war, griff der Wächter auch beim
zweiten Aufruf nicht — und es gibt zwei: das automatische Herrichten
nach dem Lauf und die Reparatur danach. Jeder Durchgang fügte rund
1.800 Dreiecke hinzu und grub erneut; der Mund wurde von 0,045 über
0,181 auf 0,313 Studs tief, ohne Grenze.

Der Betrag trennt beides sauber (0,000 gegen 0,376). Deshalb prüft der
Einbau jetzt auf **Relief** statt auf Vertiefung: `hasFaceRelief` fragt,
ob im Gesicht überhaupt Geometrie ist, in welche Richtung auch immer.
Ist Relief da, bleibt der Kopf unberührt, und der Bericht sagt, was er
gefunden hat und dass Hineingraben daraus Matsch macht.
`hasFace` bleibt daneben stehen für die Frage, die Auto Setup stellt:
sind **echte Höhlen** da? Ein Test mit einem Kastenkopf, dem
Augäpfel und ein Nasenrücken aufsitzen, hält beides fest — und dass
dreimaliges Anwenden folgenlos bleibt.

**Ein zweiter Verdacht war keiner.** Die eingebauten Augenkugeln
stehen 0,062 Studs vor der Kopffläche — nachgemessen mit
Punkt-in-Dreieck-Test. Das sah nach einem zweiten Augapfel auf dem
ersten aus, ist aber genau der Sollwert: Ein Auge wird um 0,4 × Radius
versenkt und schaut um 0,6 × Radius heraus (0,6 × 0,103 = 0,062), damit
es sichtbar ist. Zwei Tests halten das seit dem Modul fest. Der
Eindruck kam aus Tripos eigenen Augäpfeln darunter, nicht aus einem
Platzierungsfehler — der Kurzschluss stand einen Zwischenstand lang
hier und ist zurückgenommen.

Was am Einbau **doch** krumm war: die Regel, an welcher Fläche das Auge
sitzt. Gefragt wurde „liegt das Augenzentrum mindestens einen halben
Radius hinter der **Gesichtsmitte**?" — bei „ja" die eigene Fläche, bei
„nein" die Mitte. Auf einem gewölbten Gesicht ist diese Schwelle
willkürlich: Liegt die Fläche am Auge nur knapp hinter der Mitte,
bekommt das Auge trotzdem die Tiefe der Mitte und schaut weiter heraus
als die gewollten 0,6 × Radius. Der Kommentar nannte den Grund selbst
mehrdeutig — „Höhle oder zurückweichendes Gesicht". Jetzt gilt immer
die Fläche an der eigenen Stelle; die Mitte bleibt nur der Notnagel,
wenn der Strahl nichts trifft. Und der **Ring um das Auge** entscheidet,
was der Bericht dazu sagt: Höhle, wenn die Mitte dahinter liegt,
„modellierter Augapfel" mit dem Hinweis auf den Prompt, wenn davor.

**Was das für den Prompt heißt.** Die App kann aus einem vorstehenden
Augapfel keine Höhle machen; die muss aus dem Prompt kommen. Genau
dafür steht seit dem letzten Durchgang `eyes sunk into sockets with
eyelids` im Schwanz und „bulging eyes" im Negativ. Die Prüfung
unterscheidet jetzt beide Fälle: bei glattem Gesicht „die App baut die
Höhlen", bei Kugeln „das gehört in den Prompt".

### Nur noch, was Roblox verlangt

Der Schwanz war über Monate gewachsen: aus jedem Fehlschlag kam ein
Satz dazu, und niemand hat je gefragt, ob Roblox das überhaupt
verlangt. Diese Runde hat jede Angabe gegen den öffentlichen
Doku-Spiegel `Roblox/creator-docs` gehalten (nachgesehen 3. September
2026). Die entscheidende Datei war neu dabei:
`avatar-setup/auto-setup-requirements.md`, „Mesh requirements" — was
Auto Setup von einem eingegebenen Körpernetz erwartet. Sie steht jetzt
als Block `autoSetup` in `assets/roblox_specs.json`, mit Quelle,
Zitat und Datum.

| Angabe im Schwanz | Beleg |
| --- | --- |
| `upright A-pose, arms angled down` | Auto Setup 6: „should form an upright A-pose or T-Pose" |
| `clear of the torso` | Auto Setup 6: „no limbs obscure or overlap each other from the front view" |
| `symmetrical` | Auto Setup 8 |
| `humanoid with one head, one torso, two arms with hands, two legs with feet` | Auto Setup 5; Policy: „Each body can only include the following parts" |
| `distinct narrow neck not merged with the shoulders` | Auto Setup 11, wörtlich |
| `head about one quarter`, `hips at mid body height` | Body scale: Rumpf ≥ 1,7 und Bein ≥ 1,4 Studs bei 5 Studs — in Anteile übersetzt, weil ein Text-zu-3D-Modell keine Studs kennt |
| `body depth less than two fifths of body height` | Body scale: Tiefe ≤ 2,00 (Classic, Slender) / 2,25 (Normal) |
| `thick enough to fill their outlines` | Visibility: „must take up at least 50% of body part's bounding box" |
| `two separate legs with a gap between the thighs` | Auto Setup 6 |
| `opaque clothing covering upper and lower torso` | Policy „Modesty layers"; Visibility „Body parts must be fully opaque" |
| `face uncovered` | Auto Setup 10: „Do not include any accessories … hair, eyebrows, beards, and eyelashes" |
| `two eye sockets each holding a half-sphere eye` | Auto Setup 2: „2 connected eyebags containing half-sphere eyes" |
| `an open mouth cavity` | Auto Setup 2: „a connected mouthbag that houses the upper teeth, lower teeth, and tongue" |
| `watertight … apart from the eye and mouth openings` | Auto Setup 9: „watertight in all regions with the exception of the eyes and mouth" |
| `one single body mesh` | Auto Setup 1 |

**Was gestrichen wurde, weil es nirgends steht:**

- **„never horizontal".** Auto Setup 6 erlaubt die T-Pose ausdrücklich.
  Der Schwanz wählt weiter die A-Pose — eine der beiden erlaubten —,
  aber die Regeln verbieten die andere nicht mehr, und „T-pose" ist
  aus dem Negativ raus.
- **„mitten hands without fingers".** Finger sind nirgends verboten.
  Die Grenze ist das Dreiecksbudget (1.248 je Arm), und das stellt die
  App am Anbieter ein — nicht der Prompt. „fingers" ist aus dem
  Negativ raus.
- **„eyelids" und „lips".** Die Policy sagt beides ausdrücklich:
  „does not need to have an eyeball or eyelid" und „does not need to
  have lips, teeth or tongue". Verlangt sind die **Höhlen** — Augensack
  und Mundsack —, damit Auto Setup die fünf Kopfteile hineinsetzen
  kann. Genau das steht jetzt da.
- **„in a contrasting colour".** Die Policy verlangt eine Schicht
  Kleidung über Ober- und Unterkörper, keine bestimmte Farbe.
- **„few flat separated color areas", „uniform material".** Stil. Das
  Material setzt der Export (`Plastic`), die Textur wird ohnehin auf
  eine Karte gebacken.
- **„flat chest and back"** (dieselbe Regel wie die Tiefe, doppelt) und
  **„solid closed volumes with visible wall thickness"** (dieselbe
  Regel wie wasserdicht).

Dazu ins Negativ, weil Auto Setup 10 sie namentlich nennt: `hair`,
`beard`, `eyebrows`, `eyelashes` — Augenbrauen und Wimpern gehören als
eigene `Accessory`-Objekte ans Bundle, nicht ins Körpernetz.

Der Schwanz ist damit von 745 auf **629 Zeichen** geschrumpft, dem
Motiv bleiben **393 statt 277**. Ein Test führt die Zuordnung als
Tabelle mit und prüft beides: dass jede belegte Angabe drinsteht und
dass keine der gestrichenen zurückkommt.

### Die dritte Figur: die Wölbung als Augapfel gelesen

Eine Figur ohne Gesicht, nackt, Arme am Körper — und die Prüfung sagte
„keine Fehler, 2 Warnungen. Bereit für Export/Roblox-Paket." Vier
Fehler steckten dahinter, drei davon in der App.

**Die Relief-Messung las die Wölbung als Merkmal.** Der Kopf war eine
glatte Kugel ohne Augen und Mund. Gemessen wurde das Relief als
„Ring um das Augenzentrum minus Mitte" — und auf einer Kugel liegt
dieser Ring schon durch die **Wölbung** hinter der Mitte:

| Kopf | Ring-Tiefe | Schwelle | Urteil |
| --- | --- | --- | --- |
| glatter Kugelkopf | −0,12 | 0,04 | „Augapfel modelliert" — **falsch** |
| Kastenkopf (flach) | 0,00 | 0,04 | nichts da — richtig |

Der Wächter, den die letzte Runde eingebaut hat, ließ damit
ausgerechnet den Kopf in Ruhe, für den der Einbau gebaut ist. Er
wirkte richtig, weil die Testvorlage ein **flacher** Kasten ist: Dort
gibt es keine Wölbung. Jetzt wird eine Quadrik
`z = a + bx + cy + dx² + ey²` kleinste-Quadrate in die Gesichtsfläche
gelegt (Augen und Mund von der Anpassung ausgenommen) und der Rest
gemessen. Eine Kugel trifft die Quadrik fast genau: Aus −0,12 wird
−0,007, der Einbau läuft wieder, und danach steht dort eine echte
Höhle (−0,080). Dieselbe Ursache hatte die Prüfung: Sie meldete die
frisch gebauten Höhlen weiter als fehlend; auch `hasEyeSockets` und
`hasMouthCavity` rechnen jetzt gegen die angepasste Fläche. Eine neue
Testvorlage ist eine Figur mit **rundem** Kopf.

**`withoutFaceMeshes` und der Einbau passten nicht zusammen.** Das
Entfernen leert die Primitive und lässt den Namen stehen; der Einbau
zählte nur Namen und warf „Die Gesichtsteile stehen schon in der
Datei". Die Reparatur beginnt genau mit diesem Entfernen — aus dem
Fehler wurde eine weggefangene Notiz, und die Höhlen fehlten. Jetzt
zählen nur Teile mit Geometrie.

**Zwei Warnungen für dieselbe Sache, beide entschuldigend.** Die Figur
stand in I-Pose (Arme am Körper). Dafür meldete die App „Arm etwa 0,55
lang von mindestens 1,5" und „Armspanne 1,77 von mindestens 4,69" —
und beide Texte schoben hinterher, in I-Pose sage die Zahl nichts,
ohne die I-Pose je zu erkennen. Jetzt ein Befund: **wie weit die Arme
abstehen**, Spanne minus Rumpf im selben Band, gegen die 2 × 1,5 ×
cos 45° = 2,12 Studs, die ein Arm von Mindestlänge dafür braucht. Bei
0,78 heißt das im Klartext: I-Pose, und Auto Setup nennt sie
ausdrücklich schlechter („Character bodies with I-pose may yield lower
quality results"). Dass die Armlänge damit **ungeprüft** bleibt, steht
dabei.

**„Bereit" bei zwei Warnungen.** Der Vermerk in der Liste nannte die
Warnungen nur als Zahl und schloss mit „Bereit für
Export/Roblox-Paket". Jetzt nennt er sie beim Namen und sagt „erst in
die Prüfung sehen, dann exportieren". Und die Prüfung endet mit dem,
was sie **nicht** kann: ob die Figur einem Menschen ähnelt und damit
einen Modesty-Layer braucht (die Policy knüpft ihn an „smooth and flat
skin-like surface texture in the groin and chest area" — eine Frage
ans Aussehen, nicht an die Form), ob sie den Community Standards
entspricht, und ob Auto Setup aus den Kopfteilen die 17 FACS-Posen
baut.

**Was am Prompt lag:** nichts, was der Schwanz nicht schon bestellt —
er verlangt A-Pose, Gesicht und Kleidung. Tripo hat alle drei
ignoriert. Dagegen hilft kein weiterer Satz im Prompt, sondern ein
neuer Lauf.

### Ein Blender-Skript für die Nachbearbeitung

`tools/roblox_nachbearbeitung.py` macht außerhalb der App, was die App
beim Herrichten tut, und misst dazu die Punkte, die sie bisher nicht
gemessen hat. Die Anleitung steht in `tools/README_nachbearbeitung.md`.

```
blender -b -P tools/roblox_nachbearbeitung.py -- ein.glb aus.glb
```

Der Bericht ist in vier Blöcke geteilt — GEMESSEN, GEÄNDERT, DAS MUSS
DER PROMPT RICHTEN, NICHT GEPRÜFT —, und jede Zeile trägt den Punkt der
Doku, auf den sie sich stützt.

**Nachgemessen an echten Figuren, nicht behauptet:**

| Prüfung | Ergebnis |
| --- | --- |
| Kugelkopf ohne Gesicht (`neu.glb`) | Höhlen gebaut, Relief −0,094 / −0,109; fünf Kopfteile als eigene, wasserdichte Netze |
| Löcher schließen | 210 → **2** Randkanten, unabhängig in Blender nachgemessen |
| Figur mit fertigem Gesicht | Kopfnetz unangetastet (5.321 Dreiecke unverändert), nur die fünf Teile kommen dazu |
| zweiter Lauf auf dem eigenen Ergebnis | gräbt nicht nach: „Augen und Mund liegen bereits hinter der Gesichtsfläche" |
| Pose | I-Pose an `neu.glb` erkannt (Armneigung 0,26; abgespreizt ab 0,30), A-Pose an der Tripo-Figur (1,53) |

**Was es nicht kann,** und was es deshalb nur meldet: Pose, Hals,
Accessoires, Symmetrie und Dreiecksbudget lassen sich nicht
nachträglich herstellen. Die Zerlegung in Kopf, Rumpf, Arme und Beine
ist aus der Silhouette geschätzt, nicht aus einem Rig — der Bericht
sagt das an jeder Zahl dazu. Und das Ergebnis von `neu.glb` liegt mit
11.532 Dreiecken über den erlaubten 10.742: Wer die Höhlen bauen will,
muss vorher auf 9.242 dezimieren, und das Skript rechnet es vor.

Zwei begründete Abweichungen von den Zahlen der App stehen im Skript:
Das Kopfband beginnt am **gemessenen Hals** statt fest am obersten
Fünftel (dort lagen bei A-Pose-Figuren die Schultern mit drin), und die
Augen sind ganze Kugeln statt Halbkugeln — eine Halbkugel hätte einen
offenen Rand, und Doku 9 verlangt wasserdichte Netze.

### Die vierte Figur: der Kopf war gar nicht der Kopf

Ein Frankenstein aus dem lokalen Generator — Flachschädel, Jacke,
Hose. Zwei Berichte, die sich widersprachen: Die Reparatur meldete
„Hals: 100 % → 45 % behoben", die Prüfung „Kein erkennbarer Hals" als
Fehler. Und am Kopf saßen zwei Knöpfe, die aussahen wie Halsbolzen.

**Die Knöpfe waren die Augen, die die App neben den Kopf gesetzt
hatte.** Das Breitenprofil zeigt, warum:

| Höhe | Breite | was dort ist |
| --- | --- | --- |
| 4,90–5,00 | 0,62 | Kopf |
| 4,30–4,40 | 0,66 | Kopf |
| 4,20–4,30 | 0,80 | Kopfunterkante |
| 4,10–4,20 | 1,39 | Schulter |
| 4,00–4,10 | 1,80 | Schulter |

Die Kopfmessung nahm „das oberste Fünftel ist der Kopf". Bei 5 Studs
Höhe ist das alles über 4,00 — und da liegen die Schultern mit drin.
Gemessene Kopfbreite: **1,85 statt 0,62**. Alles Weitere folgt daraus:
Die Augen sitzen bei 0,18 × B = ± 0,33, der Kopf reicht aber nur bis
± 0,31. Sie standen daneben.

Die Regel hielt nur, solange der Kopf ungefähr ein Fünftel hoch ist.
Jetzt wird die Unterkante **gemessen**: Das breiteste Band in den
obersten 12 % ist die Kopfbreite; von dort abwärts endet der Kopf beim
ersten Band, das deutlich schmaler ist (ein Hals) oder deutlich breiter
(die Schultern, wenn es keinen Hals gibt). Zwei Fallen dabei, beide an
echten Vorlagen aufgelaufen:

- **Nicht gegen das vorige Band vergleichen.** Auf einem runden Kopf
  wächst die Breite vom Scheitel an; die Regel löste sofort aus und
  machte den Kopf 0,25 Studs hoch.
- **Über Dreiecke messen, nicht über Punkte.** Ein Kasten hat zwischen
  Unter- und Oberkante keine Punkte — der Hals einer Kastenfigur war
  unsichtbar, und der Kopf reichte in den Rumpf.

Ergebnis an vier Vorlagen: Kastenfigur 1,56 (Kopf ist 1,56), Kugelkopf
0,84 (Durchmesser 0,84), Frankenstein 0,75 statt 1,85, kleiner Kopf
0,80 statt 2,50. Die Augen sitzen danach im Kopf.

**Die Relief-Schwelle war zu eng.** Sie lag bei 3 % der Kopfbreite —
derselben Zahl, ab der eine Vertiefung als Höhle gilt. Damit blockierte
ein Brauenwulst von 3,2 % das Höhlenbauen auf einem sonst flachen
Gesicht. Die beiden Fragen sind verschieden: „ist diese Vertiefung tief
genug für Auto Setup" und „ist hier überhaupt schon ein Gesicht". Für
die zweite ist der Maßstab, was der Einbau selbst gräbt — 6 % der
Kopfbreite. Die Schwelle steht jetzt bei 5 %, gemessen an vier Köpfen:
glatte Kugel 0,6 %, flaches Gesicht mit Brauenwulst 3,2 %, frisch
gebaute Höhlen 7,8 %, modellierte Augäpfel 22 %.

**Der Widerspruch der zwei Berichte** war keiner: Die Reparatur zeigt,
was sie tun *würde*, die Prüfung misst die Datei, wie sie *ist*. Die
Zahlen gingen trotzdem auseinander, weil beide den Kopf verschieden
suchten — mit der gemessenen Unterkante messen sie dasselbe.

### Dieselbe Falle stand an drei Stellen, behoben war eine

Die fünfte Figur brachte zwei Fehler zurück: „Beine 1.30 hoch von
mindestens 1.4 Studs" und „Kein erkennbarer Hals". Der Prompt enthielt
beide Regeln wörtlich. Das Problem lag nicht mehr am Text.

**„Das oberste Fünftel ist der Kopf" stand an drei Stellen im Code.**
Behoben war es nach der vierten Figur nur beim Einbau der
Gesichtsteile. Die Marktplatz-Messung
(`measureMarketplaceFigure`) und die Zonen der Reparatur
(`_messeZonen`) rieten weiter — und die Reparatur maß ihre Bänder
zusätzlich über **Punkte** statt über Dreiecke, die zweite Falle aus
derselben Runde.

Was daraus folgt, ist eine Kette:

1. Die Schultern ragen ins oberste Fünftel, also wird die
   Schulterbreite (1,80) als Kopfbreite gemessen statt 0,62.
2. Das so bestimmte „Kopfband" liegt damit **unter** dem echten Hals.
   Die Suche nach der schmalsten Stelle sucht ab dort abwärts — der
   Hals liegt darüber und kann gar nicht gefunden werden.
3. Gemeldet wird „Hals 1,80 von 1,80, also 100 %" — kein erkennbarer
   Hals, für eine Figur, die einen hat.
4. Die Reparatur schnürt daraufhin am Kopf selbst ein. Sie schrumpft
   ihn mit, das Verhältnis bleibt, und der Fehler steht nach der
   Reparatur genauso da wie davor.

Die Regel liegt jetzt einmal da (`headBottomBand`) und wird von allen
drei Stellen benutzt: das breiteste Band in den obersten 12 % ist die
Kopfbreite, von dort abwärts endet der Kopf beim ersten Band, das
deutlich schmaler ist (ein Hals) oder deutlich breiter (die Schultern).
Ein Test hält den Fall fest: Kopf 0,62 über Schultern von 1,80, dazu
ein Hals von 0,26. Mit der alten Regel misst die App 1,80 Kopfbreite
und findet keinen Hals; mit der neuen 0,62 und einen Hals bei 42 %.

### Der Maßstab: die Mindestmaße sind absolut, die Höhe ist frei

„Beine 1,30 von mindestens 1,4" war bisher ein Fehler ohne Ausweg. Die
Reparatur kann Beine nicht verlängern, und ein Prompt trifft die Zahl
nicht zuverlässig — „a third of body height" gab 1,0.

Der Ausweg steht in der Doku selbst. Die Mindestmaße sind **absolut**
(Rumpf 1,7, Bein 1,4, Arm 1,5 Studs), die Gesamthöhe dagegen ist
**frei**: Die Tabelle „Character body specifications" erlaubt für jede
Skala 3,6 bis 9,5 Studs. Und der Importer nimmt eine glTF-Einheit als
einen Stud — also entscheidet allein die ausgegebene Größe, welche
Studs-Maße der Validator misst. Die App hatte 5,00 fest verdrahtet und
nie nachgerechnet, ob ein anderer Wert die Fehler löst.

Dieselbe Figur als 5,41 Studs statt als 5,00 hat Beine von 1,41. Kein
Verhältnis ändert sich dabei — Hals, Beintrennung, Pose, Symmetrie und
Dreieckszahl bleiben, wie sie sind.

Die Reparatur rechnet das jetzt aus (`fitMarketplaceScale`) und
vergrößert, wenn es aufgeht:

- **Der nötige Faktor** ist der größte über alle Mindestmaße —
  Gesamthöhe, Beinhöhe, Rumpfhöhe, Kopfhöhe, Kopfbreite und, wenn die
  Arme frei genug abstehen, die Armlänge. Hängen sie am Körper, bleibt
  die Armlänge außen vor: Dann ist sie geschätzt, nicht gemessen, und
  die Prüfung meldet sie selbst nur als Warnung.
- **Der erlaubte Faktor** ist der kleinste über alle Höchstgrenzen —
  Gesamthöhe, Tiefe, Kopfbreite, Kopfhöhe, Beinbreite, Rumpfbreite,
  Gesamtbreite, alle aus der Skala.
- **Passt der nötige unter den erlaubten**, wird vergrößert, und die
  Höhe im 3D-Tab wandert mit. Sonst steht im Bericht, welches Maß den
  Faktor fordert und welches ihn deckelt — dann stimmen die
  Verhältnisse nicht, und das richtet nur der Prompt.

Zwei Dinge, die beim Bauen aufgefallen sind:

- **Der Schritt gehört hinter das Tiefen-Stauchen.** Eine Figur mit
  2,20 Tiefe lässt bis 2,25 nur den Faktor 1,023 — zu wenig für die
  Beine. Gestaucht auf 1,95 sind es 1,154, und dann geht es.
- **Genau treffen reicht nicht.** 1,4 / 1,3 × 1,3 ist in Fließkomma
  1,3999999999999997, und die Prüfung vergleicht mit „kleiner als".
  Der Faktor bekommt deshalb ein halbes Prozent Aufschlag — weit
  innerhalb eines Messbands von 2 %.

Nebenbei aufgefallen: Die Testvorlage „eine Figur ohne Mängel" hatte
selbst einen — 1,50 Rumpfhöhe gegen die geforderten 1,70. Gemeldet
wurde das immer, nur eben als Zeile in der Nachmessung, die niemand
für einen Mangel der Vorlage hielt. Der Maßstab-Schritt fing an, ihn
zu beheben, und damit fiel er auf.

### Aus dem Text eine Marktplatz-Figur

Bis hierher lieferte der Text eine Tripo-Figur in A-Pose, und
marktplatzfähig wurde sie erst durch drei Klicks danach. Der feste
Marktplatz-Schwanz stand nur in der kopierbaren Vorlage — wer ihn nicht
über die Prompt-KI zurück ins Feld holte, schickte ein nacktes Motiv,
und die Figur kannte keine der Formregeln. Jetzt ist der Weg
geschlossen:

- **Der Schwanz hängt von selbst dran.** Beim Ziel Marktplatz-Avatar
  geht an Tripo das Motiv plus der feste Schwanz (mit A-Pose, also
  ohne zweiten Posen-Zusatz) und die feste NEGATIV-Zeile — eigene
  Negativ-Begriffe vorn, dann die festen, ohne Doppelte, in Tripos
  Grenze. Steht der Schwanz schon im Text (Vorlage zurückkopiert),
  bleibt es bei einem. Der Hinweis unter dem Feld zählt den fertigen
  Text und nennt, was dem Motiv bleibt: 285 Zeichen (die App rechnet
  den Wert aus dem Schwanz; zuerst waren es 335, dann wuchs der
  Schwanz mit der Doku-Prüfung).
- **Nach dem Lauf wird von selbst hergerichtet.** Löcher schließen,
  Textur auf 2048, 5 Studs, Zehen nach +Z, Gesicht ins Kopfnetz,
  Gesichtsteile, Messung. Das Ergebnis in der Liste ist danach die
  **vorbereitete** Datei, und die Karte sagt, was die Messung ergab.
- **Ohne Fehler geht es ohne Rückfrage weiter** zum Export. Mit
  Fehlern öffnet sich die Reparatur — sie fragt vor dem Übernehmen,
  weil sie die Figur verformt. Das ist die eine Entscheidung, die
  bleibt.

Damit die Reparatur eine schon hergerichtete Figur verträgt: Sie
nimmt die fünf Gesichtsteile vorher heraus und setzt sie am Ende neu
(sonst verschmölzen die alten Augäpfel mit dem Kopf, und fünf neue
kämen dazu), und der Gesichts-Eingriff lässt ein fertiges Gesicht in
Ruhe (sonst gräbe er die Höhlen doppelt tief). Ein Test hält beides
fest.

Was der Weg **nicht** entscheidet: ob Roblox' Auto Setup die Figur
annimmt. Das passiert in Studio, und das ist Lauf 6.

### Das Gesicht nachträglich ins Kopfnetz bauen

Fünf Läufe haben entschieden, was Auto Setup für den dynamischen Kopf
braucht: **Höhlen im Kopfnetz**, nicht Teile davor. Augen und Zähne als
eigene Netze ergaben „Cannot detect mouth open / left eye close
expression" — die FACS-Posen bewegen Lider und Lippen, und ohne
Vertiefung dahinter sieht man beim Schließen und Öffnen keinen
Unterschied. Ob Tripo aus „eye sockets with eyelids" Geometrie macht,
ist nicht verlässlich. Also baut die App sie selbst: nach dem Lauf,
vor den Gesichtsteilen. Schalter „Gesicht ins Kopfnetz bauen" beim
Ziel Marktplatz-Avatar, an in „Für Roblox vorbereiten" und im
Reparatur-Modus.

**Zwei Eingriffe, beide rein geometrisch.**

1. **Verfeinern, wo es nötig ist.** Ein Kopf mit 1.500 Dreiecken hat
   um das Auge herum vielleicht acht; daraus wird keine Höhle mit Rand.
   Die Dreiecke im Gesichtsbereich werden geteilt — **konform**: Jede
   geteilte Kante teilt auch das Nachbardreieck, sonst entstehen
   T-Stöße, und die reißen die Hülle. Ein Dreieck mit einer markierten
   Kante wird zu zwei, mit zwei zu drei, mit drei zu vier. Geteilt wird
   nur, was noch zu grob ist, die gröbsten zuerst, bis die Kanten
   0,035 × Kopfbreite kurz sind oder das Budget von 1.500 Dreiecken
   erreicht ist.
2. **Verschieben.** Punkte um das Augenzentrum wandern nach hinten
   (die Höhle, 0,06 × B tief bei 0,10 × B Radius), der Rand darum
   leicht nach vorn (der Lidgrat, 0,015 × B). Dasselbe elliptisch für
   den Mund: Mitte bei 34 % von H, damit beide Zahnreihen darin Platz
   haben, 0,08 × B tief. Verschoben wird **nur entlang Z**: Die
   Verschiebung hängt allein von x und y ab, deshalb bewegen sich
   doppelte Punkte an UV-Nähten gleich, und die Hülle bleibt
   geschlossen.

Danach setzen die Gesichtsteile die Augen **in** die Höhle: Der
Strahl auf das Augenzentrum trifft den Höhlenboden, und liegt der
tiefer als die Kopfmitte, sitzt der Augapfel dort — hinter dem
Lidgrat, wie ein Auge hinter Lidern. Der Mittelstrahl bleibt die
Grundlage für alles andere.

**Das Budget gehört zum face_limit.** Wer mit 7.000 erzeugt und das
Gesicht einbaut, landet bei 8.500. Deshalb zieht die Marktplatz-Vorgabe
die 1.500 vorher ab (Tripo bekommt 5.500), und die Reparatur dezimiert
auf 6.800 minus 1.500. Der Eingriff füllt auf.

**Der Fund aus Blender.** Der Kastentest war sauber, zwei echte
Tripo-Netze nicht: nach dem Eingriff 90 bzw. 162 Randkanten. Die
Verfeinerung hatte Kanten über die **rohen** Indizes markiert. An einer
UV-Naht hat das Nachbardreieck andere Indizes an derselben Stelle, sah
seine Kante als unmarkiert und blieb ungeteilt — ein T-Stoß je
Nahtkante. Der Kasten teilt seine acht Eckpunkte über alle Flächen
und hat keine Nähte, darum konnte er das nicht zeigen. Jetzt wird
über **verschweißte** Punkte markiert, die Mittelpunkte entstehen
trotzdem je roher Kante mit eigenen UVs. Ein Nahtkasten (jede Fläche
mit eigenen vier Punkten) hält das im Test fest, und Blender bestätigt
es an beiden Netzen: nach dem Verschweißen null Randkanten, vorher wie
nachher.

| Netz | Dreiecke | Augenhöhlen vorher → nachher | Zeit |
| --- | --- | --- | --- |
| Kapuzzee (Tripo, 9.554) | +1.672 | −0,01 / 0,05 → 0,11 / 0,16 Studs | 0,3 s |

**Die Prüfung misst es nach.** Beim Ziel Marktplatz-Avatar sagt sie
jetzt „Gesicht im Kopfnetz: Augenhöhlen und Mundhöhle da" oder was
fehlt — gemessen am Export-Puffer, per Strahl von vorn: Rand minus
Mitte muss mindestens 3 % der Kopfbreite tief sein. Der Rand ist ein
Ring auf dem Grat, und es zählt der **niedrigste** Treffer: Mit dem
höchsten sähe jedes Gesicht unter einer Kapuze nach Höhle aus, weil
die äußeren Strahlen den Kapuzenrand treffen. Gemessen wird am Kopf
**ohne** die Gesichtsteile, sonst träfe der Strahl den Augapfel statt
den Boden.

**Was es nicht ist.** Ein Lidgrat ist kein Überhang; ein echtes
Oberlid hängt über den Augapfel, und das entsteht nicht durch
Verschieben vorhandener Punkte. Ob Auto Setup aus Höhle plus Grat
FACS-Posen baut, entscheidet Lauf 6. Hier steht die beste Näherung,
die ohne neue Topologie geht.

### Gesichtsteile: fünf Netze, ohne die es keinen Marktplatz gibt

Der Marktplatz ordnet dem Kopf eines Ganzkörper-Bundles den Typ
`DynamicHead` zu und verlangt „FACS controls for at least 17 poses".
Auto Setup erzeugt diese Posen — aber nur, wenn es etwas zu bewegen
findet. Im ersten echten Lauf entstand ein leeres `FaceControls`, weil
die Figur nur aufgemalte Augen hatte.

Die App ergänzt deshalb fünf eigene Netze: **LeftEye, RightEye,
UpperTeeth, LowerTeeth, Tongue**. Sie teilen **keine Punkte mit dem
Kopf** — daran trennt Auto Setup sie vom Rest.

**Feste Maße gibt es nicht**, weder bei Roblox noch in der Übergabe —
die Figuren fallen unterschiedlich groß aus. Alle Zahlen sind deshalb
Anteile der gemessenen **Kopfbreite B** und der **Kopfhöhe H aus der
Bandmessung**:

| Teil | Form | Maß | Position |
|---|---|---|---|
| Auge, je Seite | Kugel | Radius 0,06 × B | P ± 0,18 × B auf X, bei 55 % von H, um 0,4 × Radius versenkt |
| Oberzähne | flacher Quader | 0,25 × B breit, 0,03 × H hoch, 0,04 × B tief | bei 36 % von H, direkt hinter der Gesichtsfläche |
| Unterzähne | wie Oberzähne | wie Oberzähne | bei 32 % von H (siehe unten) |
| Zunge | Ellipsoid | 0,15 × B breit, 0,02 × H hoch, 0,10 × B tief | zwischen den Zahnreihen, 0,05 × B dahinter |

Für eine Figur mit B = 1,57 heißt das: Augenradius 0,09, Augenabstand
0,57, Zahnreihe 0,39 Studs breit — die drei Zahlen aus der Übergabe,
und der Test rechnet sie nach.

**Gesichtspunkt P** ist der Treffer eines Strahls von vorn auf die
Kopfmitte bei 55 % von H, nicht die vorderste Kante des Kopfbands. Bei
einer Kapuze liegt die Kante am Kapuzenrand, das Gesicht aber tiefer;
ein Auge an der Kante schwebte davor.

Drei Entscheidungen dabei, jede aus einem Fehlschlag:

- **Die Höhe kommt aus dem Kopfband, nicht aus dem Mittelwert der
  Punkte darin.** Ein grob unterteilter Kopf hat oft nur die obere
  Kante im Band; der Mittelwert lag dann auf dem Scheitel, und die
  Augen saßen über der Figur.
- **33 % und der Abstand von 0,01 × H widersprechen sich.** Bei 36 %
  und 33 % mit je 0,03 × H Höhe stoßen die Zahnreihen genau aneinander.
  Der Abstand gewinnt, die Unterzähne rutschen auf 32 %, und der
  Bericht sagt es an: Zwei Netze, die sich berühren, sind die Sorte
  Geometrie, an der der Validator hängen bleibt.
- **„Versenkt" heißt: Mittelpunkt 0,4 × Radius hinter der Fläche.** Das
  Auge schaut also um 0,6 × Radius heraus. Ob das Tiefe kostet, sagt
  aber nur der **Hüllkörper**, nicht der Radius: Der Bericht misst
  vorher und nachher. Bei einer Kapuze liegt die Gesichtsfläche hinter
  dem Kapuzenrand — dann kosten die Augen nichts, und der Bericht sagt
  „unverändert" statt einer erfundenen Zahl. Der Marktplatz misst
  höchstens 2,00 Studs Tiefe.

Die Augen sind volle Kugeln, keine Halbkugeln: Eine Halbkugel hätte
einen offenen Rand, und „wasserdicht ohne offene Löcher" gilt für jedes
Netz in der Datei. Die hintere Hälfte steckt im Kopf.

**Zwei Fehler, die erst Blender zeigte** — und beide gehen auf
dieselbe Ursache zurück: Die App prüfte etwas anderes, als sie schrieb.

- Ein doppelter Punkt je Pol und eine wiederholte Nahtspalte ergaben
  **46 offene Kanten je Auge**. Die Prüfung verschweißt vor dem Zählen
  nach Position und meldete null. Blender und Roblox verschweißen
  nicht. Jetzt steht jeder Punkt genau einmal.
- Die Kugeln waren **nach innen gewickelt** (negatives Volumen, während
  Quader und Figur positiv waren). Die Wicklungsprüfung achtet auf
  Einheitlichkeit — und einheitlich falsch herum ist einheitlich.

Die Lehre daraus steht jetzt in der Prüfung selbst, für jedes Modell,
nicht nur für die Gesichtsteile:

- **Beide Zahlen für die Randkanten.** Die verschweißte sagt, ob es
  Löcher gibt; die rohe sagt, was in der Datei steht. Die Differenz
  sind doppelte Punkte: an einer Textur-Naht richtig, an einem Teil
  ohne UVs ein Modellierfehler.
- **Das Volumen mit Vorzeichen je zusammenhängendem Teil.** Die Summe
  allein genügt nicht — ein Körper mit +10,4 überdeckt eine Kugel mit
  −0,003, und genau das ist passiert. Positiv heißt außen, und das gilt
  für jedes Teil einzeln, für den Körper wie für die Augen.

Geprüft ist beides von Tests, die roh über die Indizes gehen; gegen den
alten Stand schlagen sie fehl. Die 46 Randkanten aus Blender kommen
darin auf die Kante genau heraus.

Dreiecke: 80 je Auge, 12 je Zahnreihe, 36 für die Zunge — **220
zusammen**, alle zum Kopfbudget von 4.000 gerechnet. Der Bericht sagt,
was für den Kopf selbst übrig bleibt.

### Konzept-Gate: die Frage vor dem ersten Credit

Fünf Läufe, drei Kapuzenfiguren, und keine konnte als
Ganzkörper-Avatar bestehen. Nicht am Prompt und nicht am Export —
Roblox' Auto Setup braucht **Augenhöhlen mit Lidern und eine Mundhöhle
mit Lippen im Kopfnetz**. Tripo liefert eine geschlossene Hülle ohne
beides. Lauf 5 hat es entschieden: Augen und Zähne als eigene Netze
reichen nicht, egal wo sie sitzen.

Beim Ziel „Marktplatz-Avatar" liest die App das Motiv deshalb, **bevor**
sie erzeugt. Findet sie ein Wort, das das Gesicht ausschließt — „face in
shadow", „faceless", Helm, Maske, Visier —, fragt sie nach, statt
Credits zu verbrauchen. Nennt das Motiv gar kein Gesicht, gibt es eine
Warnung.

**Eine Rückfrage, keine Sperre.** Das Gate liest Wörter, keine Bilder;
es kann nicht wissen, ob eine Figur ein Gesicht hat. Wer weiß, was er
tut, klickt auf „Trotzdem erzeugen".

**Die Falle, die zuerst zuschlägt:** „hoodie" enthält „hood". Eine
Kapuzenjacke mit sichtbarem Gesicht ist völlig in Ordnung —
ausgeschlossen ist der leere Kopf, nicht das Kleidungsstück. Ein Test
hält genau das fest.

**Und der Ausweg steht im Befund.** Was das Gesicht verdeckt, ist fast
immer abtrennbar: Die Kapuze wird ein **starres Hut-Accessoire** — ein
Netz, höchstens 4.000 Dreiecke, kein Cage, kein Rig, kein Gesicht —,
und darunter steht eine Figur mit sichtbarem Gesicht. Beides besteht
für sich. Aus einer unmöglichen Aufgabe werden zwei lösbare.

Dafür gibt es die Gegenstandsart **„Kapuze"**: offene Vorderseite, hohl
innen, mit dem Negativ-Zusatz gegen den Kopf darin — sonst kommt eine
halbe Figur statt eines Accessoires zurück.

### Reparatur-Modus: die Figur anpassen statt neu erzeugen

Bisher endete jede Prüfung mit einer Liste und einem neuen Lauf. Ein
Lauf kostet Credits und würfelt die Figur neu — wer nur 0,45 Studs zu
tief ist, will keine andere Figur, sondern dieselbe etwas flacher.

**„Export/Roblox → Marktplatz-Reparatur …"** misst, behebt und misst
nach. Sechs Eingriffe, alle direkt auf den Punkten:

| Regel | Was die App tut | Grenze, ab der sie es lässt |
|---|---|---|
| Tiefe | staucht auf 1,95 Studs | über 2,60 wäre die Figur ein Brett |
| Hals | schnürt das Halsband glockenförmig ein (cos² über ±6 % der Höhe) | — |
| Beine getrennt | löscht den Saum: Dreiecke, deren **drei** Punkte unter der Hüfte und im Mittelstreifen liegen | — |
| Beinform | Zylinder-Klemme mit 0,75 Studs Radius um jede Beinachse | — |
| Beinbreite | schmälert auf 1,45 | über 1,80 bliebe vom Bein nichts übrig |
| Pose | dreht die Arme um 45° ums Schultergelenk, weicher Anlauf über 4 % der Höhe | — |

Danach laufen Lochschluss und Wicklungskorrektur (der Schnitt
hinterlässt Löcher), die Dezimierung auf 6.800 Dreiecke — etwas unter
der Grenze, damit die Gesichtsteile noch hineinpassen — und zuletzt die
Gesichtsteile.

**Jede Zeile sagt, wer dran ist.** Grüner Haken: Die App hat es
behoben. Stift: Das muss der Prompt richten, weil die Korrektur die
Figur so verformen würde, dass sie nicht mehr wie das Konzept aussieht.
Die zweite Spalte der Tabelle oben ist genau diese Schwelle.

**Übernommen wird nur auf Wunsch.** Eine Reparatur formt die Figur um;
wer sie nicht wiedererkennt, klickt „Verwerfen" und behält das
Original. Auf „Übernehmen" arbeitet auch die Prüfung ab da auf dem
reparierten Stand — dieselbe Lehre wie beim Herrichten: Jede Prüfung
läuft auf dem Export-Puffer, nicht auf einer Arbeitskopie.

**Vorher wird immer hergerichtet.** Die Messungen brauchen eine Figur
von 5,00 Studs mit den Zehen auf +Z; in Bändern von 2 % der Höhe misst
man sonst etwas anderes, als man glaubt.

### Die Front war spiegelverkehrt

Der schwerste Fund aus dem Pflichtenheft, und er kostet Läufe: **Studios
glTF-Import spiegelt die Z-Achse.** Was in der GLB auf −Z liegt, kommt
in Studio auf +Z heraus. Roblox verlangt die Front auf −Z — also müssen
die Zehen **in der Datei nach +Z** zeigen.

Die App hat auf −Z gedreht, der Dokumentation folgend statt der Messung.
Zwei Auto-Setup-Läufe standen deshalb rückwärts. Jetzt dreht sie auf
+Z, und der Doc-Kommentar sagt, warum das verkehrt aussieht und wie man
es in Studio nachprüft (EditableMesh: mittleres Z der untersten 8 %
minus mittleres Z bei 15–25 % muss negativ sein).

**Die Gesichtsteile mussten mit.** Die Figur schaut dorthin, wo ihre
Zehen hinzeigen — wer eine Seite dreht und die andere vergisst, setzt
die Augen an den Hinterkopf. Nachgemessen in Blender an der ganzen
Kette: gedreht um 180°, Zehen bei glTF-z +0,28, Gesicht bei +0,53,
dieselbe Seite.

Dabei ist noch etwas sichtbar geworden: Ist die Blickrichtung **nicht
bestimmbar** (Signal unter der Schwelle), dreht die App nicht — und dann
kann das Gesicht auf der Rückseite landen. Der Bericht sagt es an; im
Viewer nachsehen und notfalls mit den 90°-Knöpfen nachhelfen.

### Zwei Prüfungen aus dem Lauf-Protokoll

- **Taille.** Auto Setup setzt die Kopf-Rumpf-Grenze an die schmalste
  Stelle. „hoodie ending at the hip bone" hat einen Bund erzeugt, der
  schmaler war als der Hals (0,68 gegen 0,81) — heraus kam ein „Head"
  von 3,16 Studs Breite. Die Prüfung meldet jede Stelle unter der
  Schulter, die schmaler ist als der Hals, mit dem Textbaustein dagegen.
- **T-Pose am Ergebnis, nicht am Prompt.** Zweimal stand der A-Pose-Text
  im Prompt und die Figur kam trotzdem waagerecht zurück. Gemessen wird
  jetzt am Netz — und zwar an der **Höhe der breitesten Stelle**, nicht
  an der Breite: In der T-Pose ist die Figur an der Schulter am
  breitesten (rund 77 % der Höhe), in der A-Pose an den Händen, und die
  hängen bei 45° auf etwa 40 %. Die Regel greift ab 68 %, zusammen mit
  einer Armspanne ≥ 0,95 × Höhe; die zweite Bedingung schützt davor,
  einen Sonnenhut für eine Schulter zu halten.

  **Warum nicht über die Breite.** Der erste Anlauf maß „Armspanne
  ≥ 0,95 × Höhe **und** ein Band über 3,5 Studs oben" — und das war in
  sich widersprüchlich, was erst eine Testfigur ans Licht gebracht hat.
  Der Marktplatz **verlangt** mindestens 6,22 Studs Armspanne bei 5,00
  Studs Höhe, also 1,24 × Höhe. Jede zulässige Figur liegt damit über
  der 0,95er-Schwelle, auch eine tadellose A-Pose: Die Breite kann die
  Posen gar nicht trennen. Die alte Regel hätte für **jede** Figur, die
  die Armspannen-Regel erfüllt, eine T-Pose gemeldet. Aufgefallen ist
  es an der Test-Vorlage „gute Figur", die selbst waagerechte Arme
  hatte — der Prüfer hatte recht, die Vorlage war falsch. Sie steht
  jetzt in A-Pose, aus fünf Stufen von der Schulter (3,85) zur Hand
  (1,95), 1,90 nach außen auf 1,90 nach unten: genau 45°, Spanne 6,40,
  breiteste Stelle auf 47 % der Höhe.

Dazu eine Grenze nachgezogen: **Beine getrennt in ≥ 90 %** der Bänder
statt 80 %.

### Export: ein Ordner, ein Name, wählbare Textur

Vier kleine Dinge, die zusammen den Unterschied zwischen „Datei
gespeichert" und „Paket fertig" ausmachen:

- **Ein Dialog statt sieben.** Das Roblox-Paket öffnete je Datei ein
  „Speichern unter" — mit FBX und Textur sind das sieben Fenster für
  einen Vorgang, obwohl die Dateien ohnehin zusammen in einen Ordner
  gehören. Jetzt wird einmal nach dem Ordner gefragt, wie beim
  Sammel-Download in der Galerie.
- **Name = Datei = Node.** Das Paket hieß `roblox_figur_1788…`, und
  das Netz in der Datei hieß gar nichts — Studio nennt ein namenloses
  Netz „Mesh". Der Name kommt jetzt aus der Bezeichnung des
  Ergebnisses und steht an allen drei Stellen. Die fünf Gesichtsteile
  bleiben ausgenommen: Auto Setup erkennt sie an ihren Namen.
- **Textur-Größe wählbar:** wie sie ist / 2048 / 1024. Vorher wurde
  fest auf 1024 verkleinert. Der Marktplatz nimmt **2048** — dort ist
  Verkleinern freiwillig und kostet Schärfe, die man im Gesicht sieht.
  Die Vorgabe folgt dem Ziel: Marktplatz 2048, Importer-Weg 1024.

### Die Prüfung sieht die Gesichtsteile

„Für das Gesichtsrig müssen es sechs Meshes sein — das sehe ich erst in
der gespeicherten Datei." Muss man nicht mehr: Beim Ziel
„Marktplatz-Avatar" nennt die Prüfung die fünf Netze beim Namen und
sagt, welche fehlen.

Dazu eine Wortkorrektur mit Anlass. Der Wicklungsbefund zählt
**zusammenhängende Dreiecksinseln** und schrieb dafür „Teile" — was
prompt für die Gesichtsteile gehalten wurde („alle 3 Teile" = Körper
plus zwei Augen?). Es heißt jetzt „zusammenhängende Stücke", mit dem
Satz dazu, dass ein Körper mit freistehenden Armen allein schon
mehrere mitbringt.

### Die Marktplatz-Vorlage: Pose nach vorn

Im ersten Lauf kam die Figur trotz A-Pose-Vorlage in T-Pose zurück
(Armspanne 5,06 bei 5,00 Höhe). Der Text war drin — die App hängt
korrekt nichts an, wenn der Prompt schon eine Pose nennt, und die
Vorlage nannte sie. Tripo hat ihn übergangen.

Drei Änderungen an der Vorlage:

- **Die Pose steht jetzt vorn.** Text→3D-Modelle wichten frühe
  Begriffe stärker; sie stand an vierter Stelle.
- **Klarer formuliert:** `arms straight and angled 45 degrees down in
  an A-pose, never horizontal` statt `arms in a relaxed A-pose about 45
  degrees from the body`. „Relaxed" lässt hängende Arme zu.
- **Ein Widerspruch raus:** Die Vorlage verlangte im selben Satz
  „eyes and a mouth modelled as separate volumes" und „single mesh".
  Jetzt heißt es „one single body mesh".

### Der Posen-Zusatz steht für sich

Bisher waren es zwei Bedienelemente: ein Schalter „Pose-Zusatz", den
eingeschaltetes Rigging erzwang und dann ausgraute, und daneben die
Wahl zwischen T und A. Wer eine geriggte Figur **ohne** Zusatz wollte,
kam nicht hin; wo der Schalter aus war, war die Wahl unsichtbar.

Jetzt ist es **ein** Schalter mit drei Werten: **Keiner / T-Pose /
A-Pose**. Er hängt an nichts anderem. Rigging *setzt* die T-Pose vor —
ein Skelett trifft ohne gespreizte Arme schlechter —, aber es erzwingt
sie nicht mehr; wer sie abwählt, bekommt einen Hinweis statt einer
gesperrten Schaltfläche.

Eine Ausnahme, und sie steht als Begründung im Schalter: Beim **eigenen
Auto-Rigging** (Lokal, Stability, fal.ai, Server, Rodin, Replicate)
erzeugt die App die Ansichten selbst und nimmt die Pose zum Figurtyp.
Ein Zusatz daneben würde ihr widersprechen, also ist die Wahl dort
gesperrt — mit dem Satz, warum.

Dabei ist noch ein stiller Fehler aufgefallen: Ohne Rigging bekamen die
erzeugten Ansichten **immer** die T-Pose, auch wenn die A-Pose
eingestellt war. Die Wahl lief ins Leere. Jetzt geht der gewählte
Baustein durch.

Drei weitere Angaben, die bisher fest im Code standen:

- **Höhe in Studs** als Feld, Standard 5,00. Der Validator misst alle
  Grenzen bei einer Höhe — Tiefe, Beinbreite und Armspanne verschieben
  sich mit. Mit Tripos `auto_size` hat der Wert nichts zu tun.
- **Gesichtsteile ergänzen** an/aus, mit Bericht: Jedes der fünf Netze
  steht danach einzeln da, mit Dreieckszahl und Sitz, dazu die
  gemessene Kopfbreite und -höhe. Eine Summenzeile sagt nur, dass
  irgendetwas passiert ist.
- Zwei Texte korrigiert: Der `auto_size`-Hinweis behauptete, Roblox
  rechne glTF-Einheiten als Meter, und kam auf 3,5 Studs. Gemessen ist
  **eine Einheit gleich einem Stud**. Und „T-Pose wird angehängt" stand
  beim Rigging-Schalter — es gehört zum Posen-Zusatz.

### Die FBX liegt im Paket, statt daneben beschrieben zu sein

Roblox importiert Rigs über `.fbx`, nicht über `.glb`. Im Roblox-Paket
lag dafür bisher nur ein Blender-Skript, das die Umwandlung erledigt —
obwohl die App FBX inzwischen selbst schreibt (7.4 binär, mit Skelett
und Gewichten). Jetzt liegt das Ergebnis im Paket und nicht die
Anleitung dorthin; das Skript bleibt als Rückfallweg dabei.

Zwei Punkte dazu:

- **Nur auf dem Rig-Weg.** Auf dem Marktplatz-Weg nimmt Auto Setup das
  rohe Netz; eine zweite Fassung derselben Figur wäre dort nur eine
  Quelle für Verwechslungen.
- **Die Textur liegt daneben**, als PNG. Sie steckt nicht in der FBX
  und wird in Studio getrennt aufs Mesh gelegt — die Anleitung sagt es
  an, und ohne Textur im Modell bleibt der Punkt einfach weg.

Nachgemessen in Blender, Paket-GLB gegen Paket-FBX: 1 Netz, 72
Dreiecke, 18 Knochen mit identischen R15-Namen, höchstens 2 Einflüsse
je Vertex, Höhe 5,0000 in beiden, größte Abweichung 0,00000021.

### Das Skelett fällt für Auto Setup weg

Auf dem Marktplatz-Weg stand bisher eine Absage: „Die Datei trägt ein
Skelett … bei Tripo also ohne Rigging erzeugen." Richtig gemeint, in der
Sache falsch — für jede vorhandene geriggte Figur lief der Weg damit ins
Leere, obwohl Auto Setup das Skelett ohnehin verwirft und die Datei sich
in zwei Handgriffen brauchbar machen lässt.

Sie fallen jetzt weg: Skin, Gewichte (`JOINTS_*`/`WEIGHTS_*`), die
Knochenknoten und die Animationen, deren Spuren auf die Knochen zeigten.

**Warum sich dabei nichts bewegt.** Bei einem Netz in Bindepose sind die
Punkte in der Datei genau die Punkte, die man sieht: Die
Skinning-Matrix ist Gelenk-Weltmatrix × inverse Bindematrix, und in der
Bindepose ist das die Einheitsmatrix. Zwei Dinge müssen dafür stimmen,
und um beide kümmert sich der Schnitt:

- Die glTF-Regel „bei einem geskinnten Netz wird die Transformation des
  Knotens **und seiner Eltern** ignoriert" gilt danach nicht mehr. Eine
  geerbte Transformation würde die Figur auf einmal verschieben. Das
  Netz hängt deshalb anschließend ohne Transformation direkt in der
  Szene — und nirgends zusätzlich als Kind.
- Ein Knochen, an dem Geometrie hängt (ein Gegenstand in der Hand),
  bleibt samt seiner Transformation stehen. Ihn zu entfernen würde das
  Netz verschieben.

Nachgemessen in Blender, mit ausgewertetem Armature-Modifier gegen das
entriggte Netz: 48 zu 48 Punkte, größte Abweichung 0,00000024 Studs —
Float-Rundung. Übrig bleiben ungenutzte Accessoren (die Bindematrizen);
sie stören keinen Importer, die Datei wird davon nicht kleiner.

Was der Schnitt nicht messen kann: Stand die Figur in der Datei in einer
anderen Haltung als in den Bindematrizen, sieht man sie danach in der
Bindepose. Der Bericht sagt es an, nachsehen muss man im Viewer.

### Was vorbereitet wurde, wird auch geprüft

„Für Roblox vorbereiten" schrieb die reparierte Figur bisher nur ins
gespeicherte Paket. In der Ergebnisliste blieb das rohe Modell stehen —
und die Roblox-Prüfung liest die Liste. Sie meldete deshalb offene
Kanten und uneinheitliche Wicklung, die im Paket längst behoben waren,
und schrieb daneben „das macht die App selbst". Beides stimmte, und
zusammen sah es wie ein Widerspruch aus.

Das Ergebnis übernimmt jetzt die vorbereitete Datei, sobald das Paket
gespeichert wird. „Abbrechen" ändert nichts. Damit zeigen Prüfung,
GLB-Export und Herkunftsprotokoll dieselben Bytes.

### Auto Setup: der kurze Weg, und warum er nötig ist

Für den Marktplatz reicht ein R15-Rig aus dieser App nicht. Der
Validator ordnet dem Kopf eines Ganzkörper-Bundles den Typ
`DynamicHead` zu und verlangt „FACS controls for at least 17 poses" —
ein Kopf ohne Gesichtsanimation besteht nicht, und den kann diese App
nicht erzeugen.

Roblox' **Auto Setup** kann es. Es nimmt ein **ungeriggtes** Netz und
baut Zerlegung in 15 Teile, R15-Rig, Skinning, Cages, Attachments und
den Gesichtsrig. Das Roblox-Paket enthält deshalb ein zusätzliches
Luau-Skript, das die Schnittstelle direkt aufruft:

```
AvatarCreationService:AutoSetupAvatarAsync(player, {Body = model}, fortschritt)
AvatarCreationService:LoadGeneratedAvatarAsync(generationId)
AvatarCreationService:ValidateUGCFullBodyAsync(player, humanoidDescription)
```

Drei Fallen, an denen der erste echte Lauf hängengeblieben ist und die
das Skript umgeht:

- `AutoSetupAvatarAsync` verlangt einen **echten Player** — es läuft nur
  im Playtest, nicht in der Befehlsleiste im Bearbeitungsmodus.
- Der Aufruf **yieldet minutenlang**. Ohne `task.spawn` steht Studio
  still und man hält es für abgestürzt.
- Das Ergebnis darf **nicht unverankert** in einen laufenden Playtest.
  Beim ersten Lauf hat die Physik es zerlegt, und die Prüfung meldete
  einen Arm 4.184 Studs weit weg.

`ValidateUGCFullBodyAsync` liefert Roblox' Urteil ohne Dialog und ohne
Gebühr — der Weg, ein Modell zu prüfen, bevor man dafür bezahlt.

### Face-Limit als freies Zahlenfeld

Die App bot nur feste Stufen an — 20.000, 10.000, 4.000. Der
Marktplatz-Weg braucht **7.000**, und den gab es dort nicht. Das war ein
Fehler der App, nicht von Tripo: Die API nimmt jede ganze Zahl, mit
Smart Low-Poly empfiehlt Tripo 1.000 bis 20.000.

Jetzt steht dort ein Eingabefeld mit Chips für die gängigen Werte
daneben. Das Feld hängt am Wert, nicht umgekehrt: Eine Vorlage setzt den
Wert, das Feld zieht nach — sonst zeigte es eine Zahl, die nicht gilt.

### Zwei Posen, zwei Empfänger

Der Posen-Zusatz ist umschaltbar. **T-Pose** für den Roblox-Importer,
**A-Pose** für Auto Setup: Dort wurden die waagerechten Arme der T-Pose
vom Segmentierer dem Kopf und dem Rumpf zugeschlagen — heraus kam ein
„UpperTorso" von 4,38 Studs Breite. Arme in 45° hängen frei und sind als
Arme erkennbar.

Nennt der Prompt schon eine Pose — gleich welche —, hängt die App nichts
an. Geprüft wird auf beide: Stünde „A-pose" im Text und die App hängte
die T-Pose an, widersprächen sich die Angaben.

Der A-Pose-Baustein muss **drei** Angaben enthalten: A-Pose, 45 Grad
nach unten, **Arme gestreckt**. Das letzte fehlte anfangs — „hanging"
allein lässt angewinkelte Arme zu, und die sind für den Segmentierer so
unbrauchbar wie waagerechte. Ein Test prüft alle drei.

### Deterministischer Export für den Marktplatz

Für den Marktplatz-Weg gibt es kein Skelett, also kann
`prepareRigForRoblox` dort nicht greifen — es liest die Gelenke. Höhe,
Front und Nullpunkt kommen deshalb aus der **Geometrie**:

- **5,00 Studs.** Tripos `auto_size` liefert sie nicht; gemessen kamen
  1,00 Einheiten zurück.
- **Front nach −Z** (Auto Setups Vorgabe; der Importer-Weg dreht auf
  +Z). Die Armspanne ist die größere waagerechte Achse — ein Lauf kam
  mit ihr auf z herein.
- **Nullpunkt mittig unter der Figur.**
- **Vertexfarben raus.** Roblox erwartet `VertexColor 1,1,1`; eine
  COLOR_0-Spur färbt zusätzlich ein, und die Farbe steckt dann doppelt
  drin.

Gedreht wird nur bei einem **eindeutigen** Signal. Bei einer vorn wie
hinten gleichen Figur weiß niemand, wo vorn ist — dort würde ein
zweiter Durchlauf sonst erneut drehen, und das Ergebnis hinge davon ab,
wie oft man den Knopf gedrückt hat. Kann die App es nicht bestimmen,
sagt sie das, statt zu raten.

Vor dem Export laufen die vier Proportionsprüfungen, und **jede Meldung
sagt, ob sie beim Prompt oder beim Export entsteht** — der Unterschied
entscheidet, was zu tun ist: Ein Formfehler lässt sich nicht wegrechnen,
da braucht der nächste Lauf einen anderen Prompt.

### Löcher schließen, ohne neue Fehler zu erzeugen

Die Reparatur schloss Löcher bisher mit einem **Fächer**: alles vom
ersten Randpunkt aus. Für ein rundes Loch geht das; für eine
langgezogene oder eingebuchtete Schleife entstehen dabei extrem schmale
und teils nullflächige Dreiecke — und genau die lehnt der
Marktplatz-Validator ab (`TriangleAreaValid`, `VerticesNotCoincident`).

Jetzt läuft **Ear Clipping** in der Ebene der Schleife (Normale nach
Newell, damit auch eine leicht gewellte Schleife trägt). Anschließend
fliegen alle Dreiecke mit einer Fläche unter 10⁻⁷ der Modellfläche raus
— auch die, die schon in der Datei standen. Der Bericht nennt die Zahl.

### Vier Aussagen der Roblox-Prüfung, die falsch waren

Der Prüf-Dialog kannte bisher nur die Importer-Regeln. Vier seiner
Aussagen stimmten für den Marktplatz-Weg nicht:

| Was dort stand | Was stimmt |
| --- | --- |
| „Textur zu groß: 2048 — höchstens 1024", blockiert | Der Importer nimmt bis 4096, der Marktplatz bis 2048. Erst darüber wird blockiert; 1024–2048 ist ein Hinweis |
| „Ohne Skelett — eine animierbare Figur braucht ein Skelett" | Für den Marktplatz-Weg ist **kein** Skelett richtig: Auto Setup baut sein eigenes und verwirft ein mitgebrachtes |
| „57 gegenläufige Kanten — in Blender beheben" | Die App dreht die Wicklung selbst um („Für Roblox anpassen") |
| „In der App lassen sich die Dreiecke nicht senken" | Seit dem Dreiecksbudget-Regler doch — und die UVs bleiben erhalten |

Dazu ein Widerspruch: Die Prüfung sagte „eine Einheit ist ein Stud", die
Einstellungen versprachen „auto_size → 5 Studs". Gemessen kam mit
`auto_size` eine Figur von 1,00 Einheiten zurück. `auto_size` sorgt für
eine Größenordnung, nicht für das Maß — auf 5,0 bringt die Figur erst
„Für Roblox anpassen".

Neu ist ein **drittes Ziel „Marktplatz-Avatar"** neben „Figur oder Prop"
und „UGC-Accessoire". Es rechnet das Budget je Körpergruppe, erwartet
kein Skelett und fordert einen erkennbaren Hals.

### Textur-Pipeline und Export-Presets

Im Viewer (Symbol mit dem Pfeil aus dem Kasten) sitzt beides in einem
Blatt, weil es zum selben Schritt gehört: erst die Textur in Ordnung
bringen, dann in dem Format ausgeben, das zum Modell passt.

**Die Textur-Pipeline** repariert vier Punkte, die der Preflight bisher
nur genannt hat — jeder einzeln abschaltbar:

| Schritt | Was passiert |
| --- | --- |
| Texturgröße | Alle eingebetteten Bilder auf 1.024 px, Seitenverhältnis bleibt |
| UV-Sätze | `TEXCOORD_1` und höher fliegen raus — Studio liest ohnehin nur den ersten |
| UV-Raum | UVs um **ganze Zahlen** in 0–1 geschoben |
| Material | Teilnetze mit demselben Material werden zusammengelegt |

Zwei Stellen, an denen die Pipeline **bewusst nichts tut**, statt etwas
kaputtzumachen:

- **UVs über einer Kachelgrenze.** Nur ganze Verschiebungen sind
  bildgleich: Unter der Wiederholung (`REPEAT`, der glTF-Standard)
  trifft u = 1,3 dasselbe Pixel wie u = 0,3. Reicht eine Insel dagegen
  von 0,9 bis 1,5, bringt sie keine ganze Zahl nach innen — und eine
  gebrochene würde die Textur verrutschen lassen. Dann steht im
  Bericht, dass das UV-Layout im 3D-Programm neu gelegt werden muss.
- **Verschiedene Materialien in einem Mesh.** Die ließen sich nur über
  einen Textur-Atlas vereinen, und der gehört ins 3D-Programm. Der
  Bericht sagt das, statt es heimlich zu versuchen.

**Hautton-fähig machen** ist eine eigene Option, kein Pipeline-Schritt.
Roblox multipliziert die Textur mit der Farbe des Teils, und die
Hautfarbe kommt aus dem Avatar-Editor genau über diese Farbe. Steckt
der Hautton schon in der Textur, wird er ein zweites Mal eingefärbt —
der Regler im Editor tut dann scheinbar nichts Richtiges. Die Option
reduziert die Basisfarbtextur deshalb auf Helligkeit (Rec. 709) und
hellt sie über eine Gammakurve auf einen Mittelwert von 78 % auf; der
Basisfarbfaktor geht auf Weiß. Schatten und Falten bleiben, **die
Farben der Vorlage gehen verloren** — für eine Figur, deren Farbigkeit
aus Kleidung besteht, ist das der falsche Knopf.

**Drei Export-Presets**, jedes mit dem Grund dabei:

| Preset | Wofür |
| --- | --- |
| **FBX für Roblox Studio** | Gerigte Figuren und Accessoires. Skelett, Gewichte und Bindepose gehen mit; die Textur liegt als PNG daneben |
| **GLB mit eingebetteten Texturen** | Eine Datei mit allem drin — für die eigene Ablage, Blender und jedes glTF-Werkzeug |
| **OBJ für statische Props** | Kisten, Möbel, Deko. Kennt weder Knochen noch Animation — genau deshalb für Unbewegtes das schlankeste Format |

Vor jedem Export läuft dieselbe Vorbereitung:

- **Transformationen einfrieren.** Eine gleichmäßige Skalierung über
  der Szene wird in die Punkte gerechnet und vom Wurzelknoten genommen.
  Bei einem Skelett wandern **Gelenke und inverse Bindematrizen mit** —
  sonst reißt die Haut. Steht dort eine Drehung oder eine ungleiche
  Skalierung, wird nichts angefasst und der Bericht sagt warum.
- **Nullpunkt.** Mittig unter das Modell (Figuren, so setzt Roblox sie
  ab), in die Mitte (drehende Teile) oder unverändert.
- **Achsen.** +Y oben ist glTF-Gesetz und wird nur nachgeprüft. Die
  Blickrichtung wird aus der Geometrie gemessen; schaut das Modell nach
  −Z, steht das im Bericht — gedreht wird nichts, weil bei einem
  Skelett Gelenke und Netz gemeinsam gedreht werden müssten (dafür gibt
  es die 90°-Knöpfe im Viewer).
- **Maßstab.** Der Importer setzt einen Meter gleich einem Stud; der
  Bericht nennt die Höhe in Studs (ein Standard-Charakter misst 5).

**Der Dateiname kommt automatisch**: `stamm_JJJJMMTT-HHMM.endung`.
Umlaute werden ausgeschrieben (`Größe` → `Groesse`, nicht `Gre`), alles
andere wird zu `_`, und nach 40 Zeichen ist Schluss — der Titel eines
Laufs ist oft der ganze Prompt, und der ist als Dateiname unbrauchbar.
Der Zeitstempel steht **hinten**, damit die alphabetische Sortierung im
Ordner auch die zeitliche ist.

Im Preflight tragen die drei Befunde „UV-Sätze", „UV-Raum" und
„Material" jetzt den Knopf **Textur-Pipeline** — und ihre Begründung
sagt gleich mit, wo die Pipeline aufhört.

### Galerie: zwei Ärgernisse abgestellt

**Der Auswahlmodus blieb an.** Wer die Galerie im Auswahlmodus verließ
und später zurückkam, fand Häkchen auf den Kacheln, die er vor einer
Stunde gesetzt hatte — und klickte sie versehentlich an. Ursache: Die
Tabs liegen in einem `IndexedStack` und bleiben deshalb am Leben. Das
ist gewollt (sonst wären Suchbegriff und geöffneter Ordner nach jedem
Wechsel weg), gilt aber nicht für die Auswahl. Sie fällt jetzt beim
Verlassen weg; Suchbegriff und Ordner bleiben.

**„Alle herunterladen" öffnete einen Dialog je Bild.** Bei vierzig
Bildern waren das vierzig „Speichern unter"-Fenster; niemand klickt die
durch. Jetzt wird **einmal nach dem Ordner** gefragt und alles dort
abgelegt.

Je Plattform so nah an „einmal fragen", wie es geht:

| | Verhalten |
| --- | --- |
| Desktop | Ein Ordner-Dialog, danach alle Dateien hinein. Gleichnamige bekommen `-2`, `-3` … statt überschrieben zu werden |
| Handy | Ein einziger Teilen-Vorgang mit allen Dateien |
| Web | Der Browser fragt einmal, ob die Seite mehrere Dateien speichern darf — einen Ordner-Dialog gibt es dort nicht |

Gelesen wird weiterhin nacheinander, mit Fortschrittsanzeige: Vierzig
Modelle gleichzeitig in den Speicher zu holen ist eine schlechte Idee.
Der Knopf heißt während dieser Phase deshalb „Sammelt …" — der
Speichern-Dialog kommt danach.

### Modul 8: Größenmaßstab in der Vorschau

Ob eine Figur 3 oder 7 Studs hoch ist, sieht man ihr im Viewer nicht an
— dort füllt jedes Modell das Fenster. Und die Größe ist keine
Kleinigkeit: Eine Figur mit 1,20 Einheiten kam in Roblox kniehoch an,
und niemand hat es vor dem Import gemerkt.

Der Knopf mit dem Lineal blendet ein Mannequin als **Drahtgitter hinter
dem Modell** ein — kein Körper, der die Sicht wegnähme, für die er da
ist. Drei Bauarten stehen zur Wahl:

| Typ | Höhe | Wofür |
| --- | --- | --- |
| Classic | 5,00 Studs | Der Bezug, auf den die App skaliert und an dem der Marktplatz-Validator alle Grenzen misst |
| Rthro Normal | 5,75 Studs | Die menschlichere Bauart; die Accessoire-Grenzen sind darauf bezogen |
| Rthro Slender | 6,50 Studs | Die höchste — wer für sie baut, hat bei den anderen Luft |

Daneben steht der Vergleich im Klartext: „1,20 Studs — 76 % kleiner als
das Classic-Mannequin. So klein kommt die Figur kniehoch an."

**Woher die Maße kommen, und woher nicht.** Das Gitter ist aus den
Proportionen eines R15-Körpers gebaut, **nicht** aus Roblox'
Vorlagendateien. Als Maßstab genügt das und hat den Vorteil, ohne
Dateien zu funktionieren, die die App nicht mitliefern darf. Als **Cage**
taugt es nicht — wer die echten Hüllkörper braucht, braucht die
offiziellen Dateien. Das steht auch in der Oberfläche.

### Modul 9: Pack-Modus mit Stil-Sperre

Ein Spiel braucht selten ein Modell, sondern einen Satz: Fass, Kiste,
Sack, Laterne. Einzeln erzeugt sehen die vier aus wie von vier
verschiedenen Leuten — eines glänzend, eines matt, eines mit
Kantenrundung, eines ohne. Nicht weil der Prompt schlecht war, sondern
weil er jedes Mal ein bisschen anders lautete.

Der Knopf **„Satz …"** neben „3D-Modell generieren" nimmt eine Liste
entgegen:

```
Fass: a wooden barrel with three iron bands
Kiste: a wooden crate with iron corners

STIL: low-poly game asset, matte painted wood and iron, soft even lighting
NEGATIV: text, logo, floating parts
```

Der Stilblock wird **einmal geschrieben und für jeden Gegenstand
wörtlich wiederverwendet** — nicht sinngemäß, nicht umformuliert.
Text→3D-Modelle reagieren auf jede Umstellung; schon eine andere
Reihenfolge derselben Wörter ergibt ein anderes Ergebnis. Dazu derselbe
**Seed** für den ganzen Satz, wo der Anbieter einen nimmt.

Das Motiv steht **vorn**, der Stil hinten: Text→3D-Modelle wichten frühe
Begriffe stärker.

Die Prüfung meldet, was die Sperre aufhebt:

- **Stilwörter im Motiv** (`glossy`, `matte`, `lighting`, `4k` …). Steht
  „glossy" bei einem von vier Gegenständen, sieht genau dieser anders
  aus — und dafür ist der Modus da. Das blockiert nicht, wird aber
  benannt.
- **Doppelte Namen**, weil die zweite Datei die erste überschriebe.
- **Kein Stilblock** — dann ist es nur eine Liste.
- **Kein Seed**: Der Anbieter würfelt für jeden Gegenstand neu. Der Text
  ist gesperrt, das Ergebnis wird trotzdem ungleichmäßiger.

Der Seed lässt sich auch **absichtlich entsperren**: Vier Fässer mit
demselben Seed würden sich zu ähnlich.

**Was der Modus nicht kann:** aus vier Läufen einen machen. Jeder
Gegenstand kostet, was er kostet — die Sperre spart keine Kosten,
sondern Nacharbeit.

### Modul 10: Eine Kosteneinheit über alle Anbieter

Die Anbieter rechnen in verschiedenen Währungen im wörtlichen Sinn:
Stability nimmt Credits mit festem Dollarwert, fal und Replicate rechnen
je Lauf oder nach GPU-Sekunden, Meshy und Tripo verkaufen Abo-Credits,
deren Wert vom gebuchten Paket abhängt. „0,10 bis 0,40 $" ist deshalb
ehrlich, aber zum Vergleichen unbrauchbar: Zwei Anbieter mit
überlappenden Spannen lassen sich so nicht ordnen.

Die Kostenanzeige nennt jetzt zusätzlich einen **Vergleichswert**: den
Preis eines fertigen Assets in Cent (AE) und die Zahl, die man beim
Vergleichen wirklich sucht — **wie viele Assets für zehn Euro**.

Drei Regeln machen ihn vergleichbar:

1. **Ein Asset ist ein Asset**, nicht ein Aufruf und nicht ein Credit.
   Ein Lauf mit vier Ansichten plus Modell kostet vier Bildpreise plus
   einen Modellpreis — zusammen eine Einheit.
2. **Gerechnet wird der obere Rand der Spanne.** Wer plant, plant nicht
   mit dem besten Fall, und bei Abo-Credits ist der untere Rand ein
   Paket, das man vielleicht gar nicht hat.
3. **Eigene Hardware ist nicht kostenlos**, sie kostet nur nichts
   *zusätzlich*. Sie steht bei 0 AE, und daneben steht, dass Strom und
   Anschaffung nicht drin sind.

Dazu sagt jede Zahl, **wie belastbar sie ist**: fester Listenpreis,
Abo-Credits (eine Obergrenze — mit größerem Paket wird es billiger, nie
teurer) oder Rechenzeit (schwankt mit der Motivgröße).

### Modul 11: Herkunftsprotokoll neben jedem Asset

Den **Erstellungsnachweis als PDF** gibt es schon — der ist für
Menschen, mit Unterschriftszeile und Prüfsumme. Das Herkunftsprotokoll
ist das Gegenstück für Maschinen: dieselben Angaben als JSON neben der
Werkdatei (`modell.glb` → `modell.herkunft.json`), damit ein Skript, ein
Asset-Verwalter oder der nächste Lauf sie lesen kann.

Nach zwanzig Läufen weiß niemand mehr, welches Modell aus welchem Prompt
kam. Genau diese Angaben entscheiden aber, ob sich ein Ergebnis
wiederholen lässt — und ob man belegen kann, womit es entstanden ist.

Was drinsteht, und warum jedes Feld:

- **Anbieter und Modellfassung**, getrennt geführt. „Tripo" allein
  reicht nicht: P1 und v2.5 liefern grundverschiedene Netze.
- **Prompt und Zusatz getrennt** — der getippte Text und das, was die
  App angehängt hat (Pose, fester Schwanz). Wer nur den ersten
  speichert, kann den Lauf nicht wiederholen.
- **Seed**, und zwar auch als `null`, wenn keiner geliefert wurde: Das
  ist eine Aussage, ein fehlendes Feld wäre eine andere.
- **Zeitpunkt als ISO 8601** mit Zeitzone. „31.08.2026, 22:26" ist für
  Menschen lesbar und für Maschinen mehrdeutig.
- **Nachbearbeitung** in der Reihenfolge, in der sie passiert ist.
- **Lizenz** des Anbieters für erzeugte Inhalte — mit **Stand**. Sie
  ändert sich, und dann gilt fürs alte Asset weiterhin die alte. Für
  einen unbekannten Anbieter sagt das Protokoll, dass es nichts weiß,
  statt etwas zu behaupten.
- **SHA-256 der Werkdatei**, die Protokoll und Datei eindeutig
  verknüpft.

Ältere Protokolle bleiben lesbar: Fehlende Felder sind kein Fehler.

### Die Roblox-Vorgaben stehen in einer Datei, nicht im Code

`assets/roblox_specs.json` hält die Budgets, Texturgrenzen, Rig-Namen
und Posen. Der Grund ist einfach: Roblox ändert seine Grenzen, und eine
Zahl im Code altert still — auffallen tut das erst beim abgelehnten
Upload.

Jeder Block nennt **seine Quelle** (Pfad im offenen Repository
`Roblox/creator-docs`), das **wörtliche Zitat** und das **Datum**, an
dem zuletzt nachgesehen wurde. Sind die Daten älter als `maxAgeDays`
(Vorgabe 90), sagt die App das in den Einstellungen unter
„Roblox-Vorgaben".

Startwerte:

| Asset-Typ | Dreiecke | Textur (Ziel / max / Nicht-Albedo) | Sonstiges |
| --- | --- | --- | --- |
| Starres Accessoire (UGC) | 4.000 | 1024 / 2048 / 256 | ein Mesh, ein Attachment |
| Generisches Mesh (Prop) | 20.000 | 1024 / 2048 / 1024 | — |
| Charakterkörper (R15) | 10.742 | 1024 / 2048 / 1024 | 15 Meshes auf `_Geo`, Einzelbudgets Kopf 4.000, Rumpf 1.750, je Arm/Bein 1.248 |

Dazu: höchstens 4 Bone-Einflüsse je Vertex, Vierecke wo möglich,
Hüllquader mindestens zu 50 % gefüllt, Rig `Root > HumanoidRootNode >
LowerTorso > …`, Posen I/A/T, Figurhöhe 5 Studs.

**Eigene Werte**: Datei bearbeiten und in den Einstellungen laden. Die
App prüft sie beim Übernehmen — passen die Einzelbudgets nicht zur
Summe, liegt die Textur-Zielgröße über der harten Grenze oder fehlt ein
Prüfdatum, steht das als Befund da. Was nicht lesbar ist, wird durch
die eingebauten Werte ersetzt; die App läuft weiter und sagt, warum.

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
Die App exportiert **alle drei**: GLB, OBJ und – seit dem FBX-Schreiber
– FBX. Für eine gerigte Figur ist damit kein Zwischenschritt über
Blender mehr nötig.

Was im FBX steht: Geometrie, Normalen, Texturkoordinaten, das Skelett
als LimbNode-Kette, die Hautgewichte als Cluster und die Bindepose.
Was **nicht** darin steht: Material und Textur. FBX bettet Bilder
nicht ein, sondern verweist auf Nachbardateien – ein solcher Verweis
zeigt beim Empfänger ins Leere. Deshalb speichert die App die Textur
als eigene PNG neben der FBX; in Studio wird sie getrennt hochgeladen
und dem Mesh zugewiesen. Ein FBX ohne Material importiert sauber, es
kommt nur grau herein.

Zwei Stolpersteine, die der Schreiber bereits umgeht und die beim
eigenen Nachbau Zeit kosten:

- **Objektkennungen müssen 64-Bit sein.** Als int32 geschrieben bricht
  Blenders Importer mit einer Zusicherung ab, weil er die Typenfolge
  jedes Objekts prüft (int64, Zeichenkette, Zeichenkette).
- **Ein Punkt darf je Cluster nur einmal vorkommen.** Nennt eine GLB
  denselben Knochen für einen Punkt zweimal (0,55 + 0,45 auf „Hips"),
  ist das in glTF harmlos – dort wird summiert. In FBX steht je Cluster
  eine Punktnummer mit einem Gewicht, und der Importer überschreibt den
  ersten Eintrag mit dem zweiten; der Punkt verlöre fast die Hälfte
  seines Gewichts. Die App addiert solche Doppelnennungen vorher.

Nachgeprüft wurde das nicht nur im Test, sondern durch einen echten
Import in Blender: 285 Punkte, 504 Dreiecke, Maße unverändert, 17
Knochen in der richtigen Hierarchie, Gewichtssumme je Punkt genau 1,0
und höchstens vier Knochen je Punkt – die Roblox-Grenze.

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
