/// Die fünf Gesichtsteile, ohne die Roblox' Auto Setup keinen
/// dynamischen Kopf baut.
///
/// **Warum das sein muss.** Der Marktplatz ordnet dem Kopf eines
/// Ganzkörper-Bundles den Typ `DynamicHead` zu, und die Regel
/// `DynamicHeadFacsPresent` verlangt „FACS controls for at least 17
/// poses". Auto Setup erzeugt diese Posen – aber nur, wenn es etwas
/// zu bewegen findet. Im ersten echten Lauf entstand ein leeres
/// `FaceControls`, weil die Figur nur aufgemalte Augen hatte.
///
/// Roblox verlangt dafür fünf eigene Netze: zwei Augen, Oberzähne,
/// Unterzähne und eine Zunge. Sie dürfen **keine Punkte mit dem Kopf
/// teilen** – Auto Setup trennt sie an genau dieser Eigenschaft vom
/// Rest.
///
/// **Wo die Maße herkommen.** Feste Maße gibt es nicht, weder bei
/// Roblox noch in der Übergabe – die Figuren fallen unterschiedlich
/// groß aus. Alle Zahlen sind deshalb Anteile der **gemessenen
/// Kopfbreite B** und der **Kopfhöhe H aus der Bandmessung**, nach
/// den Werten aus der Übergabe:
///
/// | Teil | Form | Maß | Position |
/// |---|---|---|---|
/// | Auge, je Seite | Kugel | Radius 0,06 × B | P ± 0,18 × B auf X, bei 55 % von H, um 0,4 × Radius versenkt |
/// | Oberzähne | flacher Quader | 0,25 × B breit, 0,03 × H hoch, 0,04 × B tief | bei 36 % von H, direkt hinter der Gesichtsfläche |
/// | Unterzähne | wie Oberzähne | wie Oberzähne | bei 33 % von H, 0,01 × H unter den Oberzähnen |
/// | Zunge | Ellipsoid | 0,15 × B breit, 0,02 × H hoch, 0,10 × B tief | zwischen den Zahnreihen, 0,05 × B dahinter |
///
/// **Gesichtspunkt P** ist der Treffer eines Strahls von vorn auf die
/// Kopfmitte bei 55 % von H – nicht die vorderste Kante des ganzen
/// Kopfbands. Bei einer Kapuze liegt die Kante am Kapuzenrand, das
/// Gesicht aber tiefer; ein Auge an der Kante schwebte davor.
///
/// **Vorn ist +Z.** Die Figur schaut dorthin, wohin ihre Zehen zeigen,
/// und die stehen nach der Vorbereitung auf +Z – Studios glTF-Import
/// spiegelt die Z-Achse (siehe `prepareForAutoSetup`). Als der Export
/// noch auf −Z drehte, gehörte das Gesicht dorthin; wer eine Seite
/// ändert und die andere vergisst, setzt die Augen an den
/// Hinterkopf.
///
/// **„Versenkt" heißt hier:** Der Mittelpunkt sitzt 0,4 × Radius
/// hinter der Gesichtsfläche, das Auge schaut also um 0,6 × Radius
/// heraus. Läge der Mittelpunkt auf P, wäre es die halbe Kugel.
///
/// Ob das Tiefe kostet, sagt nur der **Hüllkörper**, nicht der
/// Radius: Die Augen zählen zur 2,00-Studs-Grenze allein dann, wenn
/// sie den Hüllkörper nach vorn vergrößern. Bei einer Kapuze liegt die
/// Gesichtsfläche hinter dem Kapuzenrand, dann kosten sie nichts. Der
/// Bericht misst deshalb vorher und nachher, statt den Radius zu
/// addieren.
///
/// **33 % und 0,01 × H widersprechen sich.** Bei 36 % und 33 % mit je
/// 0,03 × H Höhe stoßen die Zahnreihen genau aneinander; für den
/// Abstand von 0,01 × H müssen die Unterzähne auf 32 % rutschen. Der
/// Abstand gewinnt: Zwei Netze, die sich berühren, sind die Sorte
/// Geometrie, an der der Validator hängen bleibt. Der Bericht sagt es
/// an.
///
/// **Dreiecke.** Die Übergabe nennt 64 bis 96 je Auge und 12 bis 40
/// je Mundteil. Erreicht wird das über die Zahl der Längenkreise: 10
/// Schritte ergeben 80 Dreiecke je Auge, 6 Schritte 36 für die Zunge,
/// die Zahnreihen sind Quader mit je 12. Alles zusammen zählt zum
/// Kopfbudget von 4.000.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart' show splitGlb, joinGlb, readGltfFloats;
import 'gltf_edit.dart';
import 'roblox_spec.dart' show specBodyPartTriangles;

/// Ein erzeugtes Gesichtsteil.
class FacePart {
  const FacePart(this.name, this.triangles, this.center);
  final String name;
  final int triangles;

  /// Mittelpunkt in Modellkoordinaten – für den Bericht.
  final List<double> center;
}

/// Die Anteile, aus denen die Teile gebaut werden.
///
/// [eyeRadius] und alles mit `× B` im Namen sind Anteile der
/// gemessenen Kopfbreite, alles mit `× H` Anteile der Kopfhöhe aus
/// der Bandmessung. [eyeSink] ist der einzige Wert, der sich auf
/// etwas anderes bezieht: auf den Augenradius.
class FaceProportions {
  const FaceProportions({
    this.eyeRadius = 0.06,
    this.eyeSeparation = 0.18,
    this.eyeHeight = 0.55,
    this.eyeSink = 0.4,
    this.upperTeethHeight = 0.36,
    this.lowerTeethHeight = 0.33,
    this.teethWidth = 0.25,
    this.teethHeight = 0.03,
    this.teethDepth = 0.04,
    this.teethGap = 0.01,
    this.tongueWidth = 0.15,
    this.tongueHeight = 0.02,
    this.tongueDepth = 0.10,
    this.tongueSetback = 0.05,
  });

  /// Augenradius, × B.
  final double eyeRadius;

  /// Abstand jedes Auges von der Mitte, × B.
  final double eyeSeparation;

  /// Höhe der Augen im Kopfband, × H.
  final double eyeHeight;

  /// Wie tief der Mittelpunkt hinter der Gesichtsfläche liegt,
  /// × Augenradius.
  final double eyeSink;

  /// Höhe der Oberzähne im Kopfband, × H.
  final double upperTeethHeight;

  /// Höhe der Unterzähne im Kopfband, × H – nachrangig gegenüber
  /// [teethGap].
  final double lowerTeethHeight;

  /// Breite beider Zahnreihen, × B.
  final double teethWidth;

  /// Höhe beider Zahnreihen, × H.
  final double teethHeight;

  /// Tiefe beider Zahnreihen, × B.
  final double teethDepth;

  /// Freier Abstand zwischen den Zahnreihen, × H.
  final double teethGap;

  /// Breite der Zunge, × B.
  final double tongueWidth;

  /// Höhe der Zunge, × H.
  final double tongueHeight;

  /// Tiefe der Zunge, × B.
  final double tongueDepth;

  /// Abstand der Zunge hinter den Zahnreihen, × B.
  final double tongueSetback;
}

class FacePartsReport {
  const FacePartsReport({
    required this.parts,
    required this.headWidth,
    required this.headHeight,
    required this.notes,
  });

  final List<FacePart> parts;

  /// Die gemessene Kopfbreite B.
  final double headWidth;

  /// Die Kopfhöhe H aus der Bandmessung.
  final double headHeight;

  final List<String> notes;

  int get triangles => parts.fold(0, (a, p) => a + p.triangles);

  String get text => [
        'Gesichtsteile für Auto Setup',
        for (final p in parts)
          '  ${p.name}: ${p.triangles} Dreiecke bei '
              '${p.center.map((v) => v.toStringAsFixed(2)).join(' / ')}',
        'Zusammen ${parts.length} Netze, $triangles Dreiecke.',
        ...notes,
      ].join('\n');
}

class FacePartsResult {
  const FacePartsResult(this.glb, this.report);
  final Uint8List glb;
  final FacePartsReport report;
}

/// Die Namen, unter denen die Teile in der Datei stehen.
const List<String> faceMeshNames = [
  'LeftEye',
  'RightEye',
  'UpperTeeth',
  'LowerTeeth',
  'Tongue',
];

/// Hängt die fünf Gesichtsteile an eine Figur.
///
/// Erwartet eine Figur, die schon auf ihre Endgröße gebracht ist
/// (Zehen nach +Z, Füße auf y = 0) – die Teile richten sich nach dem
/// gemessenen Kopf, und ein schiefer Maßstab verschöbe sie mit.
///
/// [headTopFraction] sagt, welcher obere Anteil der Höhe als Kopf
/// gilt. 0,2 heißt: das oberste Fünftel. Bei einer Kapuzenfigur ist
/// das großzügig – der Kopf steckt darin –, und genau deshalb wird
/// dort **gemessen** und nicht geraten.
FacePartsResult addFaceParts(
  Uint8List glb, {
  double headTopFraction = 0.2,
  FaceProportions proportions = const FaceProportions(),
  int eyeSteps = 10,
  int tongueSteps = 6,
}) {
  final parts = splitGlb(glb);
  final json = parts.json;
  final notes = <String>[];

  // 1. Den Kopf vermessen. Gelesen werden Punkte **und** Dreiecke:
  // Die Punkte geben das Band und die Breite, die Dreiecke braucht
  // der Strahl auf die Gesichtsfläche.
  final flaechen = <double>[];
  final alle = <Float32List>[];
  for (final mesh in (json['meshes'] as List?) ?? const []) {
    for (final prim in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final map = prim as Map;
      final mode = (map['mode'] as num?)?.toInt() ?? 4;
      final index = (map['attributes'] as Map?)?['POSITION'] as num?;
      if (index == null) continue;
      final pos = readGltfFloats(json, parts.bin, index.toInt());
      alle.add(pos);
      if (mode != 4) continue;
      final indexAccessor = (map['indices'] as num?)?.toInt();
      final idx = indexAccessor == null
          ? [for (var i = 0; i < pos.length ~/ 3; i++) i]
          : readGltfInts(json, parts.bin, indexAccessor);
      for (var t = 0; t + 2 < idx.length; t += 3) {
        for (var k = 0; k < 3; k++) {
          final v = idx[t + k] * 3;
          if (v + 2 >= pos.length) continue;
          flaechen.addAll([pos[v], pos[v + 1], pos[v + 2]]);
        }
      }
    }
  }
  if (alle.isEmpty) {
    throw Exception('Keine Geometrie gefunden – ohne Kopf lassen sich '
        'die Gesichtsteile nicht platzieren.');
  }
  final huelleVorMin = [
    double.infinity,
    double.infinity,
    double.infinity
  ];
  final huelleVorMax = [
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity
  ];
  for (final p in alle) {
    for (var i = 0; i + 2 < p.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        huelleVorMin[k] = math.min(huelleVorMin[k], p[i + k]);
        huelleVorMax[k] = math.max(huelleVorMax[k], p[i + k]);
      }
    }
  }
  final minY = huelleVorMin[1], maxY = huelleVorMax[1];
  final gesamtHoehe = maxY - minY;
  if (gesamtHoehe <= 0) throw Exception('Das Modell hat keine Höhe.');
  final kopfAb = maxY - gesamtHoehe * headTopFraction;

  var kopfMinX = double.infinity, kopfMaxX = double.negativeInfinity;
  var kopfMaxZ = double.negativeInfinity;
  var kopfPunkte = 0;
  for (final p in alle) {
    for (var i = 0; i + 2 < p.length; i += 3) {
      if (p[i + 1] < kopfAb) continue;
      kopfPunkte++;
      kopfMinX = math.min(kopfMinX, p[i]);
      kopfMaxX = math.max(kopfMaxX, p[i]);
      kopfMaxZ = math.max(kopfMaxZ, p[i + 2]);
    }
  }
  if (kopfPunkte == 0) {
    throw Exception('Im oberen Fünftel liegt keine Geometrie – dort '
        'müsste der Kopf sein.');
  }
  // B und H, so wie die Übergabe sie nennt.
  final b = kopfMaxX - kopfMinX;
  final h = maxY - kopfAb;
  final mitteX = (kopfMinX + kopfMaxX) / 2;

  // 2. Der Gesichtspunkt P: ein Strahl von vorn (+z) auf die
  // Kopfmitte, auf Augenhöhe. Trifft er nichts – etwa weil die
  // Kopfmitte hohl ist –, bleibt die vorderste Kante des Bands als
  // Notnagel, und das steht dann auch im Bericht.
  final augeY = kopfAb + h * proportions.eyeHeight;
  final mundY = kopfAb + h * proportions.upperTeethHeight;
  final augeTreffer = faceFrontHitZ(flaechen, mitteX, augeY, kopfAb);
  final mundTreffer = faceFrontHitZ(flaechen, mitteX, mundY, kopfAb);
  if (augeTreffer == null || mundTreffer == null) {
    notes.add('Der Strahl auf die Kopfmitte traf keine Fläche; als '
        'Gesichtsfläche gilt deshalb die vorderste Kante des '
        'Kopfbands. Bei einer Kapuze sitzen die Teile dann zu weit '
        'vorn – bitte im Viewer nachsehen.');
  }
  final augeFront = augeTreffer ?? kopfMaxZ;
  // Ober- und Unterzähne teilen sich **einen** Strahl. Zwei Strahlen
  // auf einem schrägen Gesicht ergäben zwei verschiedene Tiefen, und
  // die Zahnreihen stünden versetzt.
  final mundFront = mundTreffer ?? kopfMaxZ;

  // 3. Die Maße. Front ist +z, „nach hinten" heißt also −z.
  final augeR = b * proportions.eyeRadius;
  final augeX = b * proportions.eyeSeparation;

  // Je Auge noch ein Strahl auf sein eigenes Zentrum: Hat der Kopf
  // dort eine **Höhle** (etwa aus `sculptFaceIntoHead`), sitzt der
  // Augapfel in ihrem Boden – hinter dem Lidgrat, wie ein Auge hinter
  // Lidern. Ohne Höhle bleibt es beim Mittelstrahl: Auf einem
  // gewölbten Gesicht liegt das Augenzentrum weiter hinten als die
  // Mitte, und ein Auge auf dieser Tiefe versänke halb im Kopf.
  /// Die vorderste Fläche auf einem Ring um ein Augenzentrum – das
  /// Maß, an dem sich eine Höhle von einer Wölbung unterscheidet.
  ///
  /// Vorher wurde die Mitte des Gesichts als Bezug genommen
  /// („liegt das Augenzentrum hinter der Kopfmitte?"). Das war
  /// mehrdeutig, und der Kommentar sagte es selbst: „Höhle oder
  /// zurückweichendes Gesicht". An der ersten echten Figur war es das
  /// zweite – Nasenrücken und Brauen stehen vor –, und das Auge wurde
  /// auf die Tiefe der Höhle gesetzt, die es nicht gab: 0,06 Studs aus
  /// dem Kopf heraus, ein zweites Auge auf dem, den Tripo gebaut
  /// hatte. Der Ring um das Auge fragt das Richtige.
  double? ringVorn(double x) {
    const ecken = 8;
    final r = augeR * 1.3;
    var kleinste = double.infinity;
    var treffer = 0;
    for (var i = 0; i < ecken; i++) {
      final w = i * 2 * math.pi / ecken;
      final z = faceFrontHitZ(
          flaechen, x + r * math.cos(w), augeY + r * math.sin(w), kopfAb);
      if (z == null) continue;
      treffer++;
      kleinste = math.min(kleinste, z);
    }
    return treffer >= 5 ? kleinste : null;
  }

  /// Ab wann eine Vertiefung als Höhle gilt: 3 % der Kopfbreite – wie
  /// in `FaceCavities.minDepthOfHeadWidth`, hier gespiegelt, damit
  /// dieser Dienst nicht vom Einbau abhängt (der von ihm abhängt).
  const hoehleAnteil = 0.03;

  /// Wie tief ein Auge sitzt: an der Fläche **an seiner eigenen
  /// Stelle**, um [FaceProportions.eyeSink] × Radius versenkt. Es
  /// schaut also um den Rest des Radius heraus – so ist ein Auge
  /// sichtbar, und so verlangt es der dynamische Kopf.
  ///
  /// Vorher standen hier zwei Zweige: die Gesichtsmitte als Regel und
  /// der eigene Strahl nur dann, wenn er „deutlich dahinter" lag
  /// (halber Radius). Der Kommentar nannte den Grund selbst mehrdeutig
  /// – „Höhle oder zurückweichendes Gesicht" –, und auf einem
  /// gewölbten Gesicht war die Schwelle willkürlich: Lag die Fläche am
  /// Auge nur knapp hinter der Mitte, wurde das Auge trotzdem auf die
  /// Tiefe der Mitte gesetzt und schaute weiter heraus als gewollt.
  /// Der eigene Strahl ist in beiden Fällen die richtige Antwort; die
  /// Mitte bleibt nur der Notnagel, wenn er nichts trifft.
  double augeTiefe(double x, String seite) {
    final treffer = faceFrontHitZ(flaechen, x, augeY, kopfAb);
    if (treffer == null) {
      notes.add('$seite: Der Strahl auf das Augenzentrum traf keine '
          'Fläche – gesetzt wird nach der Gesichtsmitte. Im Viewer '
          'nachsehen.');
      return augeFront - augeR * proportions.eyeSink;
    }
    // Nur für den Bericht: Höhle oder Wölbung? Der Ring um das Auge
    // sagt es, die Gesichtsmitte konnte es nicht.
    final ring = ringVorn(x);
    if (ring != null) {
      final tiefe = ring - treffer;
      if (tiefe >= b * hoehleAnteil) {
        notes.add('$seite: Am Augenzentrum liegt eine Höhle, '
            '${tiefe.toStringAsFixed(2)} Studs tief gegen ihren Rand – '
            'das Auge sitzt in ihrem Boden, hinter dem Lidgrat.');
      } else if (tiefe <= -b * hoehleAnteil) {
        notes.add('$seite: Am Augenzentrum steht die Fläche '
            '${(-tiefe).toStringAsFixed(2)} Studs **vor** ihrem Rand – '
            'dort ist ein modellierter Augapfel, keine Höhle. Die '
            'Kugel sitzt darauf; für die FACS-Posen fehlt die '
            'Vertiefung. Ins Motiv: „eyes sunk into the head", ins '
            'Negativ „bulging eyes".');
      }
    }
    return treffer - augeR * proportions.eyeSink;
  }

  final augeZLinks = augeTiefe(mitteX - augeX, 'LeftEye');
  final augeZRechts = augeTiefe(mitteX + augeX, 'RightEye');

  final zahnBreite = b * proportions.teethWidth;
  final zahnHoehe = h * proportions.teethHeight;
  final zahnTiefe = b * proportions.teethDepth;
  final zahnZ = mundFront - zahnTiefe / 2;
  final oberY = mundY;
  // Der Abstand hat Vorrang vor den 33 %: siehe oben.
  final wunschUnterY = kopfAb + h * proportions.lowerTeethHeight;
  final maxUnterY = oberY - zahnHoehe - h * proportions.teethGap;
  final unterY = math.min(wunschUnterY, maxUnterY);
  if (wunschUnterY - unterY > h * 1e-6) {
    notes.add('Die Unterzähne sitzen bei '
        '${(((unterY - kopfAb) / h) * 100).toStringAsFixed(0)} % statt '
        '${(proportions.lowerTeethHeight * 100).toStringAsFixed(0)} % '
        'von H: Bei den genannten Höhen stießen die Zahnreihen '
        'aneinander, und der geforderte Abstand von '
        '${(proportions.teethGap * 100).toStringAsFixed(0)} % × H '
        'geht vor.');
  }

  final zungeZ = zahnZ -
      zahnTiefe / 2 -
      b * proportions.tongueSetback -
      b * proportions.tongueDepth / 2;
  final zungeY = (oberY - zahnHoehe / 2 + unterY + zahnHoehe / 2) / 2;

  final anhang = GltfAppender(json, parts.bin);
  final neueMeshes = <Map<String, dynamic>>[];
  final berichte = <FacePart>[];

  // Der Hüllkörper wächst mit den Teilen – gemessen, nicht gerechnet.
  final huelleNachMin = [...huelleVorMin];
  final huelleNachMax = [...huelleVorMax];
  void merken(Float32List pos) {
    for (var i = 0; i + 2 < pos.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        huelleNachMin[k] = math.min(huelleNachMin[k], pos[i + k]);
        huelleNachMax[k] = math.max(huelleNachMax[k], pos[i + k]);
      }
    }
  }

  void kugel(String name, double cx, double cy, double cz, double rx,
      double ry, double rz, int steps) {
    final (pos, idx) = _ellipsoid(cx, cy, cz, rx, ry, rz, steps);
    berichte.add(FacePart(name, idx.length ~/ 3, [cx, cy, cz]));
    neueMeshes.add(_mesh(anhang, name, pos, idx));
    merken(pos);
  }

  void quader(String name, double cx, double cy, double cz, double bx,
      double by, double bz) {
    final (pos, idx) = _quader(cx, cy, cz, bx, by, bz);
    berichte.add(FacePart(name, idx.length ~/ 3, [cx, cy, cz]));
    neueMeshes.add(_mesh(anhang, name, pos, idx));
    merken(pos);
  }

  kugel('LeftEye', mitteX - augeX, augeY, augeZLinks, augeR, augeR, augeR,
      eyeSteps);
  kugel('RightEye', mitteX + augeX, augeY, augeZRechts, augeR, augeR,
      augeR, eyeSteps);
  quader('UpperTeeth', mitteX, oberY, zahnZ, zahnBreite, zahnHoehe,
      zahnTiefe);
  quader('LowerTeeth', mitteX, unterY, zahnZ, zahnBreite, zahnHoehe,
      zahnTiefe);
  kugel(
      'Tongue',
      mitteX,
      zungeY,
      zungeZ,
      b * proportions.tongueWidth / 2,
      h * proportions.tongueHeight / 2,
      b * proportions.tongueDepth / 2,
      tongueSteps);

  // 4. Eintragen. Eigene Meshes, eigene Knoten, keine gemeinsamen
  // Punkte mit dem Kopf – daran erkennt Auto Setup sie.
  final meshes = (json['meshes'] as List?) ?? (json['meshes'] = []);
  final nodes = (json['nodes'] as List?) ?? (json['nodes'] = []);
  final neueNodes = <int>[];
  for (final mesh in neueMeshes) {
    meshes.add(mesh);
    nodes.add(<String, dynamic>{
      'name': mesh['name'],
      'mesh': meshes.length - 1,
    });
    neueNodes.add(nodes.length - 1);
  }
  final scenes = (json['scenes'] as List);
  final sceneIndex = (json['scene'] as num?)?.toInt() ?? 0;
  final scene = scenes[sceneIndex] as Map<String, dynamic>;
  scene['nodes'] = [
    for (final v in ((scene['nodes'] as List?) ?? const []).cast<num>())
      v.toInt(),
    ...neueNodes,
  ];

  notes.add('Gemessen: Kopfbreite B = ${b.toStringAsFixed(2)}, '
      'Kopfhöhe H = ${h.toStringAsFixed(2)} Studs. Alle Maße sind '
      'Anteile davon – feste Studs gäbe es nur für eine feste '
      'Figurengröße.');
  notes.add('Augenradius ${augeR.toStringAsFixed(2)}, Augenabstand '
      '${(augeX * 2).toStringAsFixed(2)}, Zahnreihe '
      '${zahnBreite.toStringAsFixed(2)} Studs breit.');
  final tiefeVor = huelleVorMax[2] - huelleVorMin[2];
  final tiefeNach = huelleNachMax[2] - huelleNachMin[2];
  final zuwachs = tiefeNach - tiefeVor;
  notes.add(zuwachs > 0.005
      ? 'Tiefe des Hüllkörpers: ${tiefeVor.toStringAsFixed(2)} → '
          '${tiefeNach.toStringAsFixed(2)} Studs. Die Augen ragen '
          'vorn heraus und kosten ${zuwachs.toStringAsFixed(2)} Studs. '
          'Der Marktplatz misst höchstens 2,00.'
      : 'Tiefe des Hüllkörpers unverändert bei '
          '${tiefeNach.toStringAsFixed(2)} Studs: Die Augen liegen '
          'hinter der vordersten Kante und kosten nichts. Der '
          'Marktplatz misst höchstens 2,00.');
  final budget = specBodyPartTriangles['DynamicHead'] ?? 4000;
  final summe = berichte.fold(0, (a, p) => a + p.triangles);
  notes.add('$summe Dreiecke, die zum Kopfbudget von $budget zählen – '
      'für den Kopf selbst bleiben ${budget - summe}.');
  notes.add('Die Teile teilen keine Punkte mit dem Kopf. Genau daran '
      'trennt Auto Setup sie vom Rest.');
  notes.add('Ob Auto Setup ohne echte Augen- und Mundhöhlen FACS-Posen '
      'baut, ist der offene Prüfpunkt: erst mit versenkten Kugeln '
      'testen, Höhlen erst danach bauen.');

  return FacePartsResult(
    joinGlb(json, anhang.finish()),
    FacePartsReport(
        parts: berichte, headWidth: b, headHeight: h, notes: notes),
  );
}

/// Der vorderste Treffer eines Strahls von +z auf (x, y).
///
/// Gerechnet wird in der Aufsicht: Enthält das Dreieck in der
/// XY-Ebene den Punkt, liefert die baryzentrische Mischung sein z.
/// Der **größte** Wert gewinnt – das ist die Fläche, die man von vorn
/// sieht, denn vorn ist +z. Dreiecke unterhalb von [abY] bleiben außen
/// vor, damit eine erhobene Hand nicht als Gesicht durchgeht.
double? faceFrontHitZ(List<double> tris, double x, double y, double abY) {
  var best = double.negativeInfinity;
  for (var t = 0; t + 8 < tris.length; t += 9) {
    final ay = tris[t + 1], by = tris[t + 4], cy = tris[t + 7];
    if (ay < abY && by < abY && cy < abY) continue;
    final ax = tris[t], bx = tris[t + 3], cx = tris[t + 6];
    final nenner = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy);
    if (nenner.abs() < 1e-12) continue;
    final l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / nenner;
    final l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / nenner;
    final l3 = 1 - l1 - l2;
    if (l1 < -1e-9 || l2 < -1e-9 || l3 < -1e-9) continue;
    final z = l1 * tris[t + 2] + l2 * tris[t + 5] + l3 * tris[t + 8];
    if (z > best) best = z;
  }
  return best.isFinite ? best : null;
}

/// Legt Accessoren an und gibt den fertigen Mesh-Eintrag zurück.
Map<String, dynamic> _mesh(GltfAppender anhang, String name,
    Float32List positions, List<int> indices) {
  final min = [double.infinity, double.infinity, double.infinity];
  final max = [
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity
  ];
  for (var i = 0; i + 2 < positions.length; i += 3) {
    for (var k = 0; k < 3; k++) {
      min[k] = math.min(min[k], positions[i + k]);
      max[k] = math.max(max[k], positions[i + k]);
    }
  }
  return <String, dynamic>{
    'name': name,
    'primitives': [
      <String, dynamic>{
        'attributes': {
          'POSITION':
              anhang.addFloats(positions, 'VEC3', min: min, max: max),
          'NORMAL': anhang.addFloats(
              _normalen(positions, indices), 'VEC3'),
        },
        'indices': anhang.addIndices(indices, positions.length ~/ 3),
        'mode': 4,
      }
    ],
  };
}

/// Ein geschlossenes Ellipsoid aus Längen- und Breitenkreisen.
///
/// Roblox nennt für die Augen Halbkugeln. Geschrieben wird trotzdem
/// eine volle Kugel: Eine Halbkugel hätte einen offenen Rand, und
/// „wasserdicht ohne offene Löcher" gilt für jedes Netz in der Datei.
/// Die hintere Hälfte steckt im Kopf und ist nie zu sehen.
///
/// [steps] steuert die Dreieckszahl: Bei `steps` Längenschritten und
/// `steps ~/ 2` Ringen entstehen `2 × steps × (Ringe − 1)` Dreiecke –
/// 80 bei 10 Schritten, 36 bei 6.
///
/// **Jeder Punkt steht genau einmal.** Der naheliegende Aufbau legt
/// für jeden Pol einen ganzen Ring gleicher Punkte an und wiederholt
/// die erste Längsspalte am Ende. Das Ergebnis sieht richtig aus und
/// ist trotzdem kaputt: Jede Kante an einem Pol und jede Kante an der
/// Naht gehört dann nur **einem** Dreieck. Blender zählte an einem
/// solchen Auge 46 offene Kanten. Die App selbst merkte es nicht, weil
/// sie vor dem Prüfen nach Position verschweißt – eine UV-Naht ist
/// kein Loch, ein doppelter Pol schon. Roblox verschweißt nicht.
///
/// Deshalb: ein Punkt je Pol, `steps` Punkte je Zwischenring, und die
/// letzte Spalte greift per Modulo auf die erste zurück.
///
/// **Die Wicklung zeigt nach außen.** Auch das war einmal falsch
/// herum: Blender maß an den Augen ein negatives Volumen, während
/// Quader und Figur positiv waren. Die Prüfung der App sah nichts,
/// weil sie nur auf **einheitliche** Wicklung achtet – und einheitlich
/// falsch herum ist einheitlich.
(Float32List, List<int>) _ellipsoid(double cx, double cy, double cz,
    double rx, double ry, double rz, int steps) {
  final ringe = math.max(4, steps ~/ 2);
  final punkte = <double>[cx, cy + ry, cz];
  for (var i = 1; i < ringe; i++) {
    final phi = math.pi * i / ringe;
    for (var j = 0; j < steps; j++) {
      final theta = 2 * math.pi * j / steps;
      punkte.addAll([
        cx + rx * math.sin(phi) * math.cos(theta),
        cy + ry * math.cos(phi),
        cz + rz * math.sin(phi) * math.sin(theta),
      ]);
    }
  }
  final sued = punkte.length ~/ 3;
  punkte.addAll([cx, cy - ry, cz]);

  int at(int i, int j) {
    if (i <= 0) return 0;
    if (i >= ringe) return sued;
    return 1 + (i - 1) * steps + j % steps;
  }

  final indizes = <int>[];
  for (var i = 0; i < ringe; i++) {
    for (var j = 0; j < steps; j++) {
      // An den Polen läuft das Viereck auf ein Dreieck zusammen. Dort
      // darf nur **eines** entstehen – das zweite hätte zwei gleiche
      // Ecken und damit keine Fläche, und genau die lehnt Roblox'
      // Validator ab (TriangleAreaValid).
      if (i > 0) {
        indizes.addAll([at(i, j), at(i, j + 1), at(i + 1, j + 1)]);
      }
      if (i < ringe - 1) {
        indizes.addAll([at(i, j), at(i + 1, j + 1), at(i + 1, j)]);
      }
    }
  }
  return (Float32List.fromList(punkte), indizes);
}

/// Ein geschlossener Quader.
(Float32List, List<int>) _quader(double cx, double cy, double cz,
    double bx, double by, double bz) {
  final hx = bx / 2, hy = by / 2, hz = bz / 2;
  final p = <double>[];
  for (final (sx, sy, sz) in [
    (-1, -1, -1),
    (1, -1, -1),
    (1, 1, -1),
    (-1, 1, -1),
    (-1, -1, 1),
    (1, -1, 1),
    (1, 1, 1),
    (-1, 1, 1),
  ]) {
    p.addAll([cx + sx * hx, cy + sy * hy, cz + sz * hz]);
  }
  const flaechen = [
    [0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
    [0, 1, 5], [0, 5, 4], [2, 3, 7], [2, 7, 6],
    [1, 2, 6], [1, 6, 5], [0, 4, 7], [0, 7, 3],
  ];
  return (
    Float32List.fromList(p),
    [for (final f in flaechen) ...f],
  );
}

/// Glatte Normalen aus den Flächennormalen.
Float32List _normalen(Float32List positions, List<int> indices) {
  final out = Float32List(positions.length);
  for (var t = 0; t + 2 < indices.length; t += 3) {
    final a = indices[t] * 3, b = indices[t + 1] * 3, c = indices[t + 2] * 3;
    final ux = positions[b] - positions[a];
    final uy = positions[b + 1] - positions[a + 1];
    final uz = positions[b + 2] - positions[a + 2];
    final vx = positions[c] - positions[a];
    final vy = positions[c + 1] - positions[a + 1];
    final vz = positions[c + 2] - positions[a + 2];
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    for (final o in [a, b, c]) {
      out[o] += nx;
      out[o + 1] += ny;
      out[o + 2] += nz;
    }
  }
  for (var i = 0; i + 2 < out.length; i += 3) {
    final l = math.sqrt(out[i] * out[i] +
        out[i + 1] * out[i + 1] +
        out[i + 2] * out[i + 2]);
    if (l > 1e-9) {
      out[i] /= l;
      out[i + 1] /= l;
      out[i + 2] /= l;
    } else {
      out[i + 1] = 1;
    }
  }
  return out;
}
