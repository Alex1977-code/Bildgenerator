# Roblox: Stand und offene Punkte

Kurzfassung für eine neue Sitzung. Ausführlich steht alles im
[README](../README.md) unter „Roblox: Figuren, die der Importer
annimmt".

## Wo die Sache steht

Eine Tripo-Figur („Kapuzzee", 9.554 Dreiecke) ist durch die ganze
Kette gegangen und steht in Roblox Studio: richtige Größe, Textur da,
aufrecht, R15-Rig vollständig. Der Weg dahin ist in der App
automatisiert, Knopf **„Für Roblox vorbereiten …"** im Export-Menü des
3D-Bereichs.

Die Kette, in dieser Reihenfolge:

1. `fixGlbForRoblox` — Löcher schließen, Wicklung vereinheitlichen
2. `shrinkGlbTextures(maxSize: 1024)`
3. `prepareRigForRoblox(targetStuds: 5)` — R15-Namen, flache
   Bone-Transformationen, Nullpunkt, Maßstab, Blickrichtung,
   Wurzelknochen entgewichten
4. Blender-Skript → FBX, Studio-Skript → einsetzen

## Die vier Regeln, an denen es hing

Jede davon verhält sich anders, als man es aus Plausibilität ableiten
würde. Alle vier sind belegt — drei aus Roblox' eigener Spezifikation,
eine gemessen.

| Regel | Warum sie überrascht |
| --- | --- |
| **Eine Datei-Einheit = ein Stud** | Nicht 0,28 m je Stud. Eine 1,20-Einheiten-Figur kommt 1,2 Studs hoch an. Gemessen an einem echten Import. |
| **Nullpunkt an der Hüfte** | „The LowerTorso and Root bone or joint position must be set to 0, 0, 0." Die Füße stehen im Minus. Auf Fußhöhe schwebt die Figur und kippt um. |
| **Wurzelknochen ohne Gewichte** | „Do not apply influences to the Root bone or joint." Deshalb muss im Importer **„Bones ohne Einfluss behalten"** an sein, sonst fliegt er raus. |
| **Anbieter-Seiten stimmen nicht** | Tripo hat links und rechts vertauscht benannt. Die Seiten kommen deshalb aus der Geometrie (Blickrichtung über den Schritt vom Fuß zum Zeh). |

Quellen: `create.roblox.com/docs/avatar/character-bodies/specifications`
(im Repo nicht erreichbar, über die Rohfassung in
`Roblox/creator-docs` auf GitHub gelesen).

Import-Einstellungen, die sich bewährt haben: Rig-Typ **R15**, Scale
Unit **Zentimeter**, „Bones ohne Einfluss behalten" **an**, „Drehpunkt
auf Szenenursprung setzen" **an**, „Verankert" **aus**.

## Wo der Code steht

| Datei | Was drin ist |
| --- | --- |
| `lib/services/roblox_rig.dart` | R15-Namen (Namensvergleich **und** Struktur-Erkennung), `prepareRigForRoblox` mit allen Eingriffen, `robloxPrepareSummary` |
| `lib/services/roblox_check.dart` | Prüfliste, Grenzwerte, Befundtexte |
| `lib/services/roblox_fix.dart` | Löcher, Wicklung, Normalen, Maßstabsknoten |
| `lib/services/roblox_export.dart` | Blender-Skript, Studio-Skript, Kurzanleitung |
| `lib/screens/three_d_screen.dart` | `_prepareForRoblox` — verbindet die Kette und den Dialog |
| `test/roblox_rig_test.dart` | Synthetisches Tripo-Skelett; deckt Namen, Seiten, Transformationen, Nullpunkt, Bind-Matrizen und Gewichte ab |

## Offen

**Nicht dringend, aber ungelöst:**

- **Vier Kanten mit uneinheitlicher Wicklung und drei Dreiecke ohne
  Fläche** bleiben nach dem Schließen der Löcher übrig. Die Fächer, mit
  denen `_closeHoles` die Ränder schließt, erzeugen bei kollinearen
  Randpunkten entartete Dreiecke; deren Wicklung ist undefiniert. Kein
  Blocker — Roblox wirft solche Dreiecke beim Import weg —, aber die
  Prüfliste meldet es. Sauber wäre, den Rand vor dem Füllen zu
  vereinfachen.

- **Die Blickrichtung kann um 180° daneben liegen.** Dass die Figur
  gedreht werden muss, wenn die Armspanne auf der Tiefenachse liegt,
  ist eindeutig; ob sie am Ende nach +z oder −z schaut, hängt an der
  Zehen-Heuristik. Bei der Testfigur stimmte sie (gegen einen Render
  geprüft). Fällt einmal eine Figur rückwärts laufend auf: Vorzeichen
  in `detectR15ByStructure` kippen, nicht die Achse.

- **Eigene Animationen aus Blender** sind ungetestet. Katalog-R15
  läuft. Erfahrungsgemäß der wunde Punkt der ganzen Kette.

- **UGC-Accessoires** gehen denselben Weg, aber ohne Skalierung auf 5
  Studs und ohne Rig. Der Pfad ist da, aber nie an einem echten
  Accessoire durchgespielt worden.

**Bewusst nicht gemacht:**

- Kein eigener FBX-Schreiber. Ließe sich hier nicht gegen Roblox
  testen; deshalb das Blender-Skript.
- Kein Hochladen nach Roblox. Ein Platz verweist auf ein hochgeladenes
  MeshPart, und Hochladen samt Moderation passiert in Studio.

## Was jemand als Erstes tun sollte

Eine zweite Figur durch die Kette schicken — am besten eine mit
deutlich anderer Silhouette (schlank, vierbeinig, mit Schwanz). Die
Struktur-Erkennung ist an genau einem Rig entwickelt worden. Der
synthetische Test in `roblox_rig_test.dart` deckt die Logik ab, aber
nicht die Vielfalt echter Anbieter-Rigs.
