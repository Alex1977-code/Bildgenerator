# Auftrag für eine Sitzung mit Zugriff auf die Roblox-Dokumentation

Diese Datei ist der Arbeitsauftrag. Sie richtet sich an eine Sitzung,
die `create.roblox.com` und `github.com/Roblox/creator-docs` erreichen
kann — die Entwicklungsumgebung, in der der Marktplatz-Weg gebaut
wurde, kann das nicht (Egress-Sperre auf `create.roblox.com`).

**Der Kern der Sache:** Der Marktplatz-Weg der App steht auf 27
Vorgaben (`marketplaceRules`) und rund zwei Dutzend Zahlen. Ein Teil
davon ist belegt, ein Teil ist **an einem gescheiterten
Validator-Lauf gemessen**, und ein Teil ist geraten und als solcher
gekennzeichnet. Was gemessen wurde, galt am 31.08.2026 —
Roblox ändert die Prüfung (die verschärften Mindestmaße kamen am
17.08.2026). Diese Sitzung soll jede einzelne Zahl gegen die
Dokumentation halten und den Unterschied ins Repository schreiben.

Es geht **nicht** darum, den Weg neu zu bauen. Er läuft, ist an sechs
echten Figuren gemessen und dokumentiert. Es geht darum, die Belege
nachzutragen und das zu korrigieren, was der Doku widerspricht.

## Randbedingungen (gelten ohne Ausnahme)

- Entwickelt und gepusht wird **nur** auf
  `claude/image-generator-text-descriptions-hxsqas`. Niemals ein
  anderer Branch ohne ausdrückliche Erlaubnis.
- **Keine Pull Requests**, außer der Nutzer bittet darum.
- **Keine Modellnamen** (Claude, Opus, Anthropic, GPT …) in Commits,
  Code, Kommentaren oder irgendeiner gepushten Datei.
- Commit-Trailer wie bisher (`Co-Authored-By:` und `Claude-Session:`).
- **Nach jedem Modul das README ergänzen. Keine bestehende Funktion
  entfernen, ohne zu fragen.**
- Vor jedem Commit: `flutter analyze` sauber, die volle Test-Suite
  grün, `flutter build web --release` durch. `dart format` **nicht**
  benutzen — es formatiert ganze Dateien um.
- Nach jedem Push rund 12 Minuten später die Workflows **„Build"** und
  **„Web-Version veröffentlichen (GitHub Pages)"** prüfen und
  Fehlschläge selbst beheben. Ein Maven-Central-429 im Android-Job ist
  der bekannte Infrastruktur-Fehler: einmal neu starten.
- Antworten an den Nutzer auf Deutsch, kurz, mit Testlinks (Web
  <https://alex1977-code.github.io/Bildgenerator/> mit Strg+F5;
  Windows/Android
  <https://github.com/Alex1977-code/Bildgenerator/releases/latest>).
- **Die Stelle im Werkzeug immer genau benennen.** Es gibt mehrere
  Marktplatz-Stellen; „Marktplatz-Reparatur" allein genügt nicht,
  sondern „3D-Bereich → Export/Roblox → Marktplatz-Reparatur …".

## Wie ein Befund festgehalten wird

Jede geprüfte Zahl bekommt am Fundort im Code einen Beleg in dieser
Form — Dateipfad im `creator-docs`-Repo (relativ zu `content/en-us/`)
plus **wörtliches Zitat**, wie es `roblox_spec.dart` schon vormacht:

```dart
/// „Individual meshes can not exceed 20,000 triangles."
/// art/modeling/specifications.md, Abschnitt „Geometry", geprüft
/// 2026-09-07.
const int specMaxMeshTriangles = 20000;
```

Zwei Ablagen, und die Trennung ist wichtig:

- `lib/services/roblox_spec.dart` — **was dokumentiert ist.**
- `lib/services/roblox_marketplace.dart` — **was gemessen ist**, samt
  Datum. Findet sich für eine gemessene Zahl ein Doku-Beleg, wandert
  sie nach `roblox_spec.dart` und wird dort zitiert; die alte Stelle
  verweist darauf.

Weicht die Doku von der Messung ab: **beides hinschreiben**, mit
Datum, und begründen, welchem gefolgt wird. Ein Validator-Lauf sticht
eine Doku, die ihn nicht erklärt — aber nur, wenn beide Zahlen
dastehen.

## Die zwölf offenen Punkte, nach Dringlichkeit

### 1. Nimmt Studios 3D-Importer glTF an? (blockierend)

Die Anleitung im Paket sagt seit `ee4ee20` auf dem Marktplatz-Weg:
„Avatar → 3D-Importer → figur.glb. Studio liest glTF; eine FBX
braucht dieser Weg nicht." Belegt ist das **nicht**. Stimmt es nicht,
ist der erste Schritt des Pakets falsch und muss über das
beiliegende Blender-Skript zur FBX führen.

Zu prüfen: `art/modeling/3d-importer.md` (unterstützte Formate).
Fundort: `lib/services/roblox_export.dart`, `robloxReadme`,
Zweig `marketplace ? …`.

### 2. Die Front-Achse — hängt an Punkt 1 (blockierend)

`prepareForAutoSetup` dreht die Zehen **in der Datei nach +Z**, obwohl
Roblox die Front auf −Z verlangt. Begründung im Code: Studios
glTF-Import spiegelt die Z-Achse (gemessen am 02.09.2026, zwei
Auto-Setup-Läufe standen vorher rückwärts). Diese Umkehrung gilt für
den **glTF**-Weg. Führt Punkt 1 zur FBX, kippt das Vorzeichen, und
jede Figur steht rückwärts.

Zu prüfen: ob die Doku die Spiegelung beim glTF-Import erwähnt, und
was für FBX gilt. Fundort:
`lib/services/roblox_marketplace.dart`, `prepareForAutoSetup`,
Schritt 1, sowie `marketplaceFrontThreshold`.

Nachprüfen lässt es sich nur in Studio: EditableMesh laden, mittleres
Z der untersten 8 % (Zehen) minus mittleres Z bei 15–25 %
(Schienbein) muss **negativ** sein.

### 3. Brauchen die fünf Gesichtsteile UVs und ein Material?

`addFaceParts` erzeugt `LeftEye`, `RightEye`, `UpperTeeth`,
`LowerTeeth`, `Tongue` mit `POSITION` und `NORMAL` — **ohne
`TEXCOORD_0` und ohne Material**. Gemessen an der erzeugten Datei:

```
LeftEye    p0 NORMAL,POSITION   pos=42 idx=240 mat=None
```

Ob Auto Setup daraus einen dynamischen Kopf baut, ist unbekannt. Es
ist der wahrscheinlichste stille Fehlschlag im ganzen Weg.

Zu prüfen: `avatar/character-bodies/specifications.md` (Abschnitt zum
dynamischen Kopf), `art/characters/facial-animation/*`. Fundort:
`lib/services/roblox_face_parts.dart`.

### 4. Sind das die Namen, an denen Auto Setup die Teile erkennt?

`faceMeshNames = [LeftEye, RightEye, UpperTeeth, LowerTeeth, Tongue]`,
und die Annahme „sie dürfen keine Punkte mit dem Kopf teilen — daran
erkennt Auto Setup sie". Beides stammt aus einer Übergabe, nicht aus
der Doku. Fundort: `lib/services/roblox_face_parts.dart`.

### 5. Gilt das Dreiecksbudget als Summe oder je Teil?

`specBodyTotalTriangles = 10742` ist die Summe aus
`specBodyPartTriangles` (DynamicHead 4.000, Torso 1.750, je Arm und
Bein 1.248). Die App dezimiert seit `ee4ee20` das **ganze Netz** auf
diese Summe, verteilt aber nichts. Ein Kopf mit 6.000 Dreiecken reißt
`DynamicHead`, auch wenn die Summe passt.

Zu prüfen: ob der Validator je Teil prüft (dann braucht die
Dezimierung eine Gewichtung nach Körperregion) oder nur die Summe.
Fundort: `lib/services/roblox_spec.dart` und die Regel `dreiecke` in
`lib/services/roblox_marketplace.dart`.

### 6. Welche Texturgrenze gilt für einen Marktplatz-Körper?

Zwei Zahlen stehen nebeneinander:
`specMaxTexture = 1024` („Roblox supports up to 1024×1024 pixel spaces
for texture maps", Abschnitt „UV mapping") und
`specMarketplaceTexture = 2048` („Textures for Marketplace assets
can't exceed 2048x2048 resolution"). Der Export nimmt 2048.

Zu prüfen: welche für einen hochgeladenen Körper bindend ist, und ob
1024 eine Empfehlung oder eine Grenze ist. Fundort:
`lib/services/roblox_spec.dart`, benutzt in
`lib/screens/three_d_screen.dart` (`_exportTextureSize`).

### 7. `HumanoidRootNode` oder `HumanoidRootPart`?

Die Doku ist laut Kommentar in `roblox_spec.dart` selbst uneinheitlich:
`avatar/character-bodies/specifications.md` und
`art/characters/validation-tool.md` nennen `HumanoidRootNode`,
`art/characters/export-avatar-animations-from-maya.md` an derselben
Stelle `HumanoidRootPart`. Die App exportiert Körper, nimmt also
ersteres, erkennt beim Einlesen beides.

Zu prüfen: ob sich das inzwischen aufgelöst hat. Fundort:
`specRootNode`.

### 8. Die gemessenen Marktplatz-Grenzen gegen die Doku halten

Diese Werte stammen aus dem Validator-Lauf vom 31.08.2026 und teils
aus `UGCValidation/flags/`, **nicht** aus der Doku. Jeder braucht
entweder einen Beleg oder den ausdrücklichen Vermerk „steht nirgends":

| Konstante | Wert | Was sie behauptet |
| --- | --- | --- |
| `marketplaceMaxDepth` | 2,00 | größte Rumpftiefe (Classic/Slender) |
| `marketplaceMaxLegWidth` | 1,50 | größte Breite eines Beins |
| `marketplaceMaxLegDepth` | 2,00 | größte Tiefe eines Beins |
| `marketplaceMinTorsoWidth` | 2,54 | kleinste Rumpfbreite |
| `marketplaceMinArmSpan` | 6,22 | kleinste Armspanne |
| `marketplaceNeckRatio` | 0,50 | Hals halb so breit wie der Kopf |
| `marketplaceLegSeparation` | 0,90 | Anteil der Bänder mit zwei Inseln |
| `marketplaceCoverage` | 50 % | Füllung des Hüllkörpers je Teil |

Dazu die Mindestmaße, die die Datei als „Doku, Tabelle Minimum"
führt, aber ohne wörtliches Zitat: `specMinTorsoHeight` 1,7,
`specMinTorsoWidth` 0,85, `specMinLegHeight` 1,4, `specMinLegWidth`
0,25, `specMinArmLength` 1,5, `specMinHeadSize` 0,5,
`specMinBodyHeight` 3,6. Und die drei Körper-Skalen in
`RobloxBodyScale` (Kopfbreite, Tiefe, Gesamthöhe je Skala).

Alles in `lib/services/roblox_marketplace.dart`, Zeilen 100–215.

### 9. Die 13 Auto-Setup-Regeln nachschlagen

`marketplaceRules` führt 27 Vorgaben, davon 13 mit der Quelle
„Auto Setup 1" bis „Auto Setup 13". Das ist eine Nummerierung aus einer Übergabe, kein
Doku-Anker. Jede Regel braucht Datei und Abschnitt. Besonders:

- „Ein einziges Körpernetz" (Auto Setup 1)
- „Augen, Zähne und Zunge teilen keine Punkte mit dem Kopf" (3)
- „FACS controls for at least 17 poses" — die **17** prüfen
- „Arme abgespreizt, sichtbare Lücke zum Rumpf" (6) — daraus leitet
  die App `2 × 1,5 × cos 45° = 2,12 Studs` ab; steht die Herleitung so
  in der Doku oder ist sie eine Auslegung?

### 10. Die Lua-Skripte gegen die Engine-Referenz

`lib/services/roblox_export.dart`, `autoSetupLua`. Zu prüfen sind
Namen und Argumentformen:

- `AvatarCreationService:AutoSetupAvatarAsync(player, {Body = model,
  Accessories = {}}, callback)`
- `AvatarCreationService:LoadGeneratedAvatarAsync(generationId)`
- `AvatarCreationService:ValidateUGCFullBodyAsync(player, description)`
- `Players:CreateHumanoidModelFromDescription(description,
  Enum.HumanoidRigType.R15)`

Dazu: Braucht Auto Setup ein verifiziertes Konto, eine Gebühr oder
eine freigeschaltete Beta? Die Anleitung behauptet „ohne Gebuehr und
ohne Dialog" — das ist zu belegen. Und: Baut Auto Setup Cages und
Attachments wirklich selbst, wie die Anleitung sagt?

### 11. Ist der Marktplatz-Schwanz im Prompt noch vollständig?

`robloxMarketplaceTail` in `lib/services/roblox_prompt.dart` bestellt
die Vorgaben im Bild-Prompt. Zwei Tests halten fest, dass **jeder**
Satz der Regeltabelle darin vorkommt und **nichts** darin steht, was zu
keiner Regel gehört (`test/roblox_marketplace_test.dart`, Gruppe „Jede
Vorgabe hat einen Zuständigen"). Kommt beim Nachschlagen eine Regel
hinzu, muss der Satz dazu — sonst schlägt der Test fehl, und das ist
Absicht.

### 12. Die Marktplatz-Policy

`source: 'Policy „Avatar body guidelines"'` und
`'Policy „Modesty layers"'` — die Fundstellen fehlen. Zu prüfen:
`marketplace/marketplace-policy.md`. Interessant ist besonders, ob es
Regeln gibt, die die App gar nicht kennt.

## Reihenfolge

1. Punkte 1 und 2 zuerst. Sie entscheiden, ob der erste Schritt des
   ausgelieferten Pakets richtig ist. Alles andere ist Feinschliff
   daneben.
2. Dann 3 und 4 — der dynamische Kopf ist die Bedingung dafür, dass
   ein Ganzkörper-Bundle überhaupt durchkommt.
3. Dann 5 bis 8, die Zahlen.
4. Dann 9 bis 12, die Belege.

## Womit gearbeitet wird

Sechs echte Figuren liegen dem Nutzer vor und sind schon durch den Weg
gelaufen; ihre Messwerte stehen im README unter „Der Export-Weg selbst,
grundlegend nachgemessen". Ein neuer Lauf ist dafür nicht nötig — der
Weg lässt sich ohne Oberfläche in einem Test durchspielen:

```dart
final fixed = fixGlbForRoblox(glb, closeHoles: true, fixWinding: true);
final small = await shrinkGlbTextures(fixed.glb, maxSize: specMarketplaceTexture);
final ohne = removeFaceParts(small.glb);
final vor = prepareForAutoSetup(ohne, targetStuds: marketplaceFigureStuds);
var out = vor.glb;
final ziel = specBodyTotalTriangles - faceSculptTriangleBudget - facePartsTriangleBudget;
if (await glbTriangleCount(out) > ziel) out = await decimateGlb(out, ziel);
out = (await sculptFaceIntoHead(out)).glb;
out = addFaceParts(out).glb;
out = applyExportName(out, 'pruef');
```

Das ist genau die Kette aus `_prepareMarketplace` in
`lib/screens/three_d_screen.dart`. Temporäre Testdateien vor dem
Commit wieder löschen; `print` in Tests braucht
`// ignore: avoid_print`.

## Was am Ende dastehen soll

- Jede Zahl aus den Punkten 5 bis 8 trägt entweder ein wörtliches
  Doku-Zitat mit Pfad und Prüfdatum, oder den Vermerk, dass sie
  gemessen ist und nirgends steht.
- Die Punkte 1 bis 4 sind beantwortet, und der Code folgt der Antwort.
- Das README hat einen Abschnitt „Gegen die Dokumentation geprüft" mit
  dem Datum und dem, was sich dabei geändert hat.
- Diese Datei ist auf den neuen Stand gebracht: erledigte Punkte
  gestrichen, neue offene Fragen eingetragen.

## Vorgeschichte in zwei Sätzen

Der Marktplatz-Weg wurde in einer Umgebung ohne Roblox-Zugang gebaut,
gegen einen Validator-Befund vom 31.08.2026 und gegen Messungen an
echten Figuren. Alles, was dabei geraten werden musste, steht im Code
als solches gekennzeichnet — diese Datei zählt es auf, damit es jemand
mit Zugang zu Ende bringen kann.
