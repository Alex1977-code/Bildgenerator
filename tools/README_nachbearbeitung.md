# Nachbearbeitung für Roblox' Avatar Setup

`roblox_nachbearbeitung.py` nimmt eine GLB, wie sie eine Text‑zu‑3D‑KI
liefert, und bringt sie so weit, wie sich das aus der Geometrie allein
bringen lässt: Es baut die fünf Kopfteile und die Höhlen, in denen sie
sitzen, stellt die Figur auf 5 Studs, dreht falsch gewickelte Netze um –
und **misst** alles Übrige, statt es zu behaupten.

Was sich nur beim Erzeugen entscheidet – Pose, Hals, Accessoires,
Dreiecksbudget –, kann kein Skript nachträglich richten. Solche Befunde
stehen im Bericht unter „DAS MUSS DER PROMPT RICHTEN", jeweils mit dem
Punkt der Roblox‑Doku, auf den sie sich stützen.

## Aufruf

```
blender -b -P tools/roblox_nachbearbeitung.py -- eingabe.glb ausgabe.glb
```

Getestet mit Blender 4.0.2. Ohne zweiten Dateinamen schreibt das Skript
neben die Eingabe (`…_nachbearbeitet.glb`).

Im **Blender‑Text‑Editor**: Datei öffnen, oben `EINGABE` und `AUSGABE`
eintragen, „Skript ausführen".

### Schalter

| Schalter | Wirkung |
|---|---|
| `--nur-messen` | ändert nichts, druckt nur den Bericht |
| `--loecher-fuellen` | zieht Deckel in Randschleifen außerhalb von Augen und Mund ein (Doku 9) |
| `--teile-neu` | löscht vorhandene Kopfteile, baut die Höhlen und setzt die Teile danach neu |

`--teile-neu` ist der Schalter für den häufigsten Fall aus der App: Die
fünf Netze stehen schon in der Datei, das Kopfnetz hat aber keine
Höhlen. Ohne den Schalter rührt das Skript den Kopf nicht an – die
Verfeinerung würde die Teile mit ihm verschmelzen, und die Kugeln
stünden danach vor der Höhle statt darin.

## Was es herstellt

* **Fünf Kopfteile** (`LeftEye`, `RightEye`, `UpperTeeth`, `LowerTeeth`,
  `Tongue`) als eigene Netze ohne einen gemeinsamen Punkt mit dem Kopf –
  Doku 2 und 3. Vorhandene Teile bleiben, wo sie sind.
* **Augenhöhlen und Mundhöhle** im Kopfnetz: Der Gesichtsbereich wird
  verfeinert, dann werden die Punkte entlang der Tiefenachse verschoben.
  Doku 2 („connected eyebags", „connected mouthbag").
* **Höhe 5 Studs**, Füße auf 0, Nullpunkt mittig – Pivot 0,0,0 und
  „stand up in positive Y" aus der Körper‑Doku.
* **Eingefrorene Objekt‑Transformationen**, ebenfalls Körper‑Doku.
* **Wicklung umdrehen**, wenn ein geschlossenes Netz ein negatives
  Volumen hat: Dann zeigen alle Flächen nach innen, und Roblox sieht
  überall Rückseiten (Doku 9, zweiter Teil).
* **Löcher schließen** – nur mit `--loecher-fuellen`, nur außerhalb von
  Augen und Mund.

## Was es misst und meldet

| Punkt | Was gemessen wird |
|---|---|
| Doku 1 | Zahl der Körpernetze |
| Doku 2/3 | Tiefe der Höhlen, Relief des Gesichts, welche Kopfteile da sind |
| Doku 4 | Dreiecke gesamt und je Körperteil, geschätzt aus der Silhouette |
| Doku 6 | Pose (A/T/I) aus Armneigung und Silhouetten‑Inseln; Verdeckung von vorn |
| Doku 7 | Blickrichtung, gemessen an den Zehen |
| Doku 9 | Randkanten, nicht‑mannigfaltige Kanten, Vorzeichen des Volumens |
| Doku 10 | zusammenhängende Stücke; Netznamen, die nach Accessoire klingen |
| Doku 11 | schmalste Stelle zwischen Kopf und Schulter gegen Kopf‑ und Schulterbreite |
| Doku 12 | ob überhaupt eine Textur in der Datei liegt |

„Doku N" ist Punkt N der Liste **Mesh requirements** in
`avatar-setup/auto-setup-requirements.md`.

## Was es nicht kann

* **Doku 5** (humanoide Form), **Doku 8** (Symmetrie) und **Doku 13**
  (Community Standards, Marktplatz‑Regeln) prüft es nicht.
* Die **Pose** kann es nicht ändern. Eine I‑Pose meldet es; umformen
  müsste ein Rig, und Auto Setup will genau keines.
* Einen **Hals** kann es nicht schnitzen, ein **Accessoire** nicht von
  einer Frisur unterscheiden. Es misst und sagt, was zu sehen ist.
* Ein **Dreiecksbudget** kann es nicht einhalten; dezimiert wird vorher.
* Die Grenzen zwischen Kopf, Rumpf, Armen und Beinen sind aus der
  Silhouette **geschätzt**, nicht aus einem Rig. Auto Setup zerlegt
  selbst; die Zahlen sind ein Anhalt, keine Abrechnung.
* Ein **Lidgrat ist kein Überhang.** Ein echtes Oberlid hängt über den
  Augapfel; das geht durch Verschieben vorhandener Punkte nicht.

## Zwei Dinge, die man leicht falsch herum bekommt

**Vorn ist in der Datei +Z, nicht −Z.** Doku 7 verlangt die Front auf
−Z, und das stimmt für Studio. Studios glTF‑Import spiegelt aber die
Z‑Achse: Was in der GLB auf −Z liegt, kommt in Studio auf +Z heraus.
Zwei Auto‑Setup‑Läufe standen rückwärts, weil die Vorbereitung der Doku
gefolgt ist statt der Messung (siehe `prepareForAutoSetup` in
`lib/services/roblox_marketplace.dart`). Das Skript **misst** die
Blickrichtung an den Zehen und setzt das Gesicht auf die gemessene
Seite; gedreht wird nicht – das tut die App.

**In Blender ist oben +Z und vorn −Y.** Der glTF‑Importer dreht die
Achsen, der Exporter dreht sie zurück. Alle Rechnungen im Skript laufen
in Blender‑Koordinaten.

## Woher die Zahlen stammen

Die Gesichtsmaße sind Anteile der gemessenen **Kopfbreite B** und
**Kopfhöhe H** und stehen unverändert so in der App:

* `lib/services/roblox_face_parts.dart` – Augenradius 0,06 × B,
  Augenabstand 0,18 × B, Augenhöhe 0,55 × H, Zahnreihen bei 36 % und
  32 % von H (die 32 % statt 33 %, weil der Abstand von 1 % × H
  vorgeht), Zunge 0,15 × B breit.
* `lib/services/roblox_face_sculpt.dart` – Höhlenradius 0,10 × B,
  Höhlentiefe 0,06 × B, Mundmitte 0,34 × H, Mund‑Halbachsen 0,16 × B
  und 0,045 × H, Mundtiefe 0,08 × B, Budget 1.500 zusätzliche Dreiecke.

Zwei begründete Abweichungen, beide auch im Code kommentiert:

1. **Das Kopfband beginnt am gemessenen Hals**, nicht fest beim obersten
   Fünftel. Im obersten Fünftel einer A‑Pose‑Figur liegen auch Schultern
   und Oberarme; am Kastenmenschen wurde B = 1,19 gemessen statt der
   0,82, die der Kopf breit ist – daraus werden zu große, zu weit außen
   sitzende Augen. Findet das Skript keinen Hals, gilt wieder das
   oberste Fünftel. Beide Zahlen stehen im Bericht.
2. **Die Augen sind ganze Kugeln**, obwohl Doku 2 „half-sphere eyes"
   sagt. Eine Halbkugel hätte einen offenen Rand, und Doku 9 verlangt
   wasserdichte Netze. Die hintere Hälfte steckt in der Höhle.

## Wie es zum Rest des Projekts passt

`lib/services/roblox_export.dart` erzeugt bereits ein Blender‑Skript für
den Weg GLB → FBX und ein Luau‑Skript für Auto Setup in Studio. Dieses
Skript hier ist der Schritt **davor** und doppelt nichts davon: Es
bereitet das Netz auf, bevor Auto Setup es bekommt.

Die App selbst kann dasselbe in Dart (`addFaceParts`,
`sculptFaceIntoHead`, `prepareForAutoSetup`). Das Blender‑Skript ist der
Weg für alle, die eine fertige GLB von Hand nachsehen und nachbessern
wollen – und der Ort, an dem sich das Ergebnis im Viewer sofort
anschauen lässt.

## Was gemessen wurde, als das Skript geschrieben wurde

An einem Kastenmenschen (816 Dreiecke, glatter Kugelkopf) und an zwei
echten Figuren:

* **Kastenmensch, A‑Pose** – Höhlen gebaut (892 → 2.040 Dreiecke),
  fünf Teile angelegt (220 Dreiecke), Netz danach wasserdicht.
* **`neu.glb`** (echte Figur, 10.280 Dreiecke, glatter Kugelkopf, die
  fünf Teile schon in der Datei) – als I‑Pose gemeldet (Armneigung
  0,26, abgespreizt wäre ab 0,30). Mit `--teile-neu` Höhlen gebaut
  (10.280 → 11.312) und die Teile neu gesetzt; mit
  `--loecher-fuellen` 210 Randkanten auf 2 gebracht.
* **`s2_vorbereitet.glb`** (echte Figur mit fertigem Gesicht) – das
  Gesicht blieb unberührt: „Die Augen stehen als Kugeln vor der Fläche",
  gemeldet statt angegraben. Das Körpernetz kam mit 6.161 Punkten herein
  und ging mit 6.161 Punkten hinaus.

* **`auto.glb`** (Ergebnis der App‑Kette, 7.317 Dreiecke) – A‑Pose,
  Hals 0,38, Kopf 4.199 Dreiecke bei 4.000 erlaubten, 28
  nicht‑mannigfaltige Kanten: alles gemeldet, nichts angefasst.

Ein zweiter Lauf auf der eigenen Ausgabe ändert nichts mehr; beim ersten
Wiederholungslauf einer gerade veränderten Datei kann noch der Nullpunkt
um Bruchteile nachrücken, weil das Gesicht die Hüllkörper‑Mitte
verschiebt. Der dritte Lauf ist still.
