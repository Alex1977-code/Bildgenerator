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
/// **Die Figur bleibt trotzdem gesichtslos**, wenn sie das soll: Die
/// Augen sitzen im Kapuzenschatten, der Mund ist ein geschlossener
/// Schlitz. Sichtbar ist davon fast nichts; der Segmentierer braucht
/// die Volumen trotzdem.
///
/// **Wo die Maße herkommen.** Roblox nennt in seiner Anforderung die
/// Teile, nicht ihre Größe – die hängt am Kopf. Die Zahlen hier sind
/// deshalb **Anteile der gemessenen Kopfbreite**, keine absoluten
/// Studs: So passen sie an jede Figur, und an einer 5-Studs-Figur mit
/// 1,5 Studs Kopfbreite ergeben sie ein Auge von 0,18 Studs
/// Durchmesser – die Größenordnung eines Roblox-Standardkopfs.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart' show splitGlb, joinGlb, readGltfFloats;
import 'gltf_edit.dart';

/// Ein erzeugtes Gesichtsteil.
class FacePart {
  const FacePart(this.name, this.triangles, this.center);
  final String name;
  final int triangles;

  /// Mittelpunkt in Modellkoordinaten – für den Bericht.
  final List<double> center;
}

class FacePartsReport {
  const FacePartsReport({
    required this.parts,
    required this.headWidth,
    required this.notes,
  });

  final List<FacePart> parts;
  final double headWidth;
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
/// (Front nach −Z, Füße auf y = 0) – die Teile richten sich nach dem
/// gemessenen Kopf, und ein schiefer Maßstab verschöbe sie mit.
///
/// [headTopFraction] sagt, welcher obere Anteil der Höhe als Kopf
/// gilt. 0,2 heißt: das oberste Fünftel. Bei einer Kapuzenfigur ist
/// das großzügig – der Kopf steckt darin –, und genau deshalb wird die
/// **Breite** dort gemessen und nicht geraten.
FacePartsResult addFaceParts(
  Uint8List glb, {
  double headTopFraction = 0.2,
  double eyeDiameterFraction = 0.12,
  double mouthWidthFraction = 0.34,
  int ringSteps = 12,
}) {
  final parts = splitGlb(glb);
  final json = parts.json;
  final notes = <String>[];

  // 1. Den Kopf vermessen.
  final positionen = <int>{};
  for (final mesh in (json['meshes'] as List?) ?? const []) {
    for (final prim in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final index = ((prim as Map)['attributes'] as Map?)?['POSITION'] as num?;
      if (index != null) positionen.add(index.toInt());
    }
  }
  if (positionen.isEmpty) {
    throw Exception('Keine Geometrie gefunden – ohne Kopf lassen sich '
        'die Gesichtsteile nicht platzieren.');
  }
  final alle = [
    for (final index in positionen) readGltfFloats(json, parts.bin, index),
  ];
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (final p in alle) {
    for (var i = 1; i < p.length; i += 3) {
      minY = math.min(minY, p[i]);
      maxY = math.max(maxY, p[i]);
    }
  }
  final hoehe = maxY - minY;
  if (hoehe <= 0) throw Exception('Das Modell hat keine Höhe.');
  final kopfAb = maxY - hoehe * headTopFraction;

  var kopfMinX = double.infinity, kopfMaxX = double.negativeInfinity;
  var kopfMinZ = double.infinity, kopfMaxZ = double.negativeInfinity;
  var kopfPunkte = 0;
  for (final p in alle) {
    for (var i = 0; i + 2 < p.length; i += 3) {
      if (p[i + 1] < kopfAb) continue;
      kopfPunkte++;
      kopfMinX = math.min(kopfMinX, p[i]);
      kopfMaxX = math.max(kopfMaxX, p[i]);
      kopfMinZ = math.min(kopfMinZ, p[i + 2]);
      kopfMaxZ = math.max(kopfMaxZ, p[i + 2]);
    }
  }
  if (kopfPunkte == 0) {
    throw Exception('Im oberen Fünftel liegt keine Geometrie – dort '
        'müsste der Kopf sein.');
  }
  final kopfBreite = kopfMaxX - kopfMinX;
  final kopfMitteX = (kopfMinX + kopfMaxX) / 2;
  // Die Höhe kommt aus dem **Band**, nicht aus dem Mittelwert der
  // Punkte darin. Ein grob unterteilter Kopf hat oft nur die obere
  // Kante im Band – der Mittelwert läge dann auf dem Scheitel, und
  // die Augen säßen über der Figur. Genau das ist passiert.
  final kopfMitteY = kopfAb + (maxY - kopfAb) * 0.55;
  // Front ist −z: Auto Setup erwartet die Figur so herum.
  final front = kopfMinZ;

  // 2. Die Teile setzen. Die Augen sitzen leicht über der Kopfmitte
  // und ein Stück innerhalb der Front – im Kapuzenschatten, aber als
  // Volumen vorhanden.
  final bandHoehe = maxY - kopfAb;
  final augeR = kopfBreite * eyeDiameterFraction / 2;
  final augeY = kopfMitteY + bandHoehe * 0.12;
  final augeZ = front + augeR * 1.2;
  final augeX = kopfBreite * 0.19;

  // Der Mund liegt darunter, als flacher geschlossener Schlitz: Ober-
  // und Unterzähne berühren sich fast, die Zunge liegt dahinter.
  final mundBreite = kopfBreite * mouthWidthFraction;
  final mundY = kopfMitteY - bandHoehe * 0.25;
  final mundZ = front + kopfBreite * 0.05;
  final zahnHoehe = kopfBreite * 0.045;
  final zahnTiefe = kopfBreite * 0.09;

  final anhang = GltfAppender(json, parts.bin);
  final neueMeshes = <Map<String, dynamic>>[];
  final berichte = <FacePart>[];

  void kugel(String name, double cx, double cy, double cz, double r) {
    final (pos, idx) = _kugel(cx, cy, cz, r, ringSteps);
    berichte.add(FacePart(name, idx.length ~/ 3, [cx, cy, cz]));
    neueMeshes.add(_mesh(anhang, name, pos, idx));
  }

  void quader(String name, double cx, double cy, double cz, double bx,
      double by, double bz) {
    final (pos, idx) = _quader(cx, cy, cz, bx, by, bz);
    berichte.add(FacePart(name, idx.length ~/ 3, [cx, cy, cz]));
    neueMeshes.add(_mesh(anhang, name, pos, idx));
  }

  kugel('LeftEye', kopfMitteX - augeX, augeY, augeZ, augeR);
  kugel('RightEye', kopfMitteX + augeX, augeY, augeZ, augeR);
  quader('UpperTeeth', kopfMitteX, mundY + zahnHoehe / 2, mundZ,
      mundBreite, zahnHoehe, zahnTiefe);
  quader('LowerTeeth', kopfMitteX, mundY - zahnHoehe / 2, mundZ,
      mundBreite, zahnHoehe, zahnTiefe);
  quader('Tongue', kopfMitteX, mundY, mundZ + zahnTiefe * 0.7,
      mundBreite * 0.7, zahnHoehe * 0.8, zahnTiefe * 1.2);

  // 3. Eintragen. Eigene Meshes, eigene Knoten, keine gemeinsamen
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

  notes.add('Kopfbreite gemessen: ${kopfBreite.toStringAsFixed(2)} – '
      'alle Maße sind Anteile davon, damit sie an jede Figur passen.');
  notes.add('Die Teile teilen keine Punkte mit dem Kopf. Genau daran '
      'trennt Auto Setup sie vom Rest.');
  notes.add('Sichtbar ist davon fast nichts: Die Augen sitzen im '
      'Schatten der Kapuze, der Mund ist ein geschlossener Schlitz. '
      'Die Figur bleibt gesichtslos – aber der Segmentierer findet, '
      'was er für die FACS-Posen braucht.');

  return FacePartsResult(
    joinGlb(json, anhang.finish()),
    FacePartsReport(
        parts: berichte, headWidth: kopfBreite, notes: notes),
  );
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

/// Eine geschlossene Kugel aus Längen- und Breitenkreisen.
///
/// Roblox nennt für die Augen Halbkugeln. Geschrieben wird trotzdem
/// eine volle Kugel: Eine Halbkugel hätte einen offenen Rand, und
/// „wasserdicht ohne offene Löcher" gilt für jedes Netz in der Datei.
/// Die hintere Hälfte steckt im Kopf und ist nie zu sehen.
(Float32List, List<int>) _kugel(
    double cx, double cy, double cz, double r, int steps) {
  final ringe = math.max(4, steps ~/ 2);
  final punkte = <double>[];
  final indizes = <int>[];
  for (var i = 0; i <= ringe; i++) {
    final phi = math.pi * i / ringe;
    for (var j = 0; j <= steps; j++) {
      final theta = 2 * math.pi * j / steps;
      punkte.addAll([
        cx + r * math.sin(phi) * math.cos(theta),
        cy + r * math.cos(phi),
        cz + r * math.sin(phi) * math.sin(theta),
      ]);
    }
  }
  int at(int i, int j) => i * (steps + 1) + j;
  for (var i = 0; i < ringe; i++) {
    for (var j = 0; j < steps; j++) {
      // An den Polen fallen alle Punkte eines Rings zusammen. Dort
      // darf nur **ein** Dreieck je Spalte entstehen – das zweite
      // hätte zwei gleiche Ecken und damit keine Fläche, und genau
      // die lehnt Roblox' Validator ab (TriangleAreaValid).
      if (i > 0) {
        indizes.addAll([at(i, j), at(i + 1, j + 1), at(i, j + 1)]);
      }
      if (i < ringe - 1) {
        indizes.addAll([at(i, j), at(i + 1, j), at(i + 1, j + 1)]);
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
