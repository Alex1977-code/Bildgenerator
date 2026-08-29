/// Eigenes Auto-Rigging: baut ein Standard-Skelett (Heuristik aus der
/// Bounding Box) direkt in eine GLB-Datei ein – komplett lokal, ohne
/// API. Die Skin-Gewichte entstehen über den Abstand jedes Vertex zu
/// den Knochensegmenten (die zwei nächsten Knochen werden gemischt).
///
/// Es gibt Skelett-Vorlagen für Zweibeiner (Mensch/Roboter/Fantasy in
/// T-Pose), Vierbeiner, Insekten/Mehrbeiner, Vögel (gespreizte Flügel),
/// Schlangen und Fische. Konvention: y = oben, Blick/Kopf nach +z –
/// genau das, was die App bei aktivem Rigging erzeugt.
/// Texturen, Materialien und alle übrigen Daten der GLB bleiben
/// unverändert; es kommen nur Skelett-Knoten, ein Skin und
/// JOINTS_0/WEIGHTS_0-Attribute hinzu.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Verfügbare Figurtypen: (Wert, deutsche Bezeichnung).
const rigTypeOptions = [
  ('biped', 'Mensch / Roboter / Fantasy (2 Beine)'),
  ('quadruped', 'Vierbeiner (Hund, Pferd, Katze …)'),
  ('insect', 'Insekt / Mehrbeiner'),
  ('bird', 'Vogel (gespreizte Flügel)'),
  ('snake', 'Schlange / ohne Beine'),
  ('fish', 'Fisch'),
];

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x, y, z;
}

class _Joint {
  const _Joint(this.name, this.parent, this.position);
  final String name;
  final int parent; // -1 = Wurzel
  final _Vec3 position;
}

class _Bone {
  const _Bone(this.joint, this.from, this.to);
  final int joint; // Index des steuernden Gelenks
  final _Vec3 from;
  final _Vec3 to;
}

int _pad4(int n) => (n + 3) & ~3;

double _distToSegmentSq(double px, double py, double pz, _Vec3 a, _Vec3 b) {
  final abx = b.x - a.x, aby = b.y - a.y, abz = b.z - a.z;
  final apx = px - a.x, apy = py - a.y, apz = pz - a.z;
  final abLenSq = abx * abx + aby * aby + abz * abz;
  var t = abLenSq < 1e-12
      ? 0.0
      : (apx * abx + apy * aby + apz * abz) / abLenSq;
  t = t.clamp(0.0, 1.0);
  final dx = px - (a.x + abx * t);
  final dy = py - (a.y + aby * t);
  final dz = pz - (a.z + abz * t);
  return dx * dx + dy * dy + dz * dz;
}

/// Sammelt Gelenke und Knochen: Jedes Gelenk (außer der Wurzel)
/// erzeugt automatisch einen Knochen vom Elternteil, der vom Elternteil
/// gesteuert wird; [tip] hängt an Blatt-Gelenke ein virtuelles
/// Endsegment für die Gewichtsverteilung an.
class _SkeletonBuilder {
  final joints = <_Joint>[];
  final bones = <_Bone>[];

  int joint(String name, int parent, _Vec3 position) {
    joints.add(_Joint(name, parent, position));
    if (parent >= 0) {
      bones.add(_Bone(parent, joints[parent].position, position));
    }
    return joints.length - 1;
  }

  void tip(int jointIndex, _Vec3 to) =>
      bones.add(_Bone(jointIndex, joints[jointIndex].position, to));
}

/// Baut das Skelett des gewünschten Figurtyps aus der Bounding Box.
/// Konvention: y = oben, Kopf/Blick nach +z.
(List<_Joint>, List<_Bone>) _skeletonFor(String rigType, double minX,
    double maxX, double minY, double maxY, double minZ, double maxZ) {
  final h = maxY - minY;
  final w = maxX - minX;
  final d = maxZ - minZ;
  final cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  _Vec3 p(double x, double yFraction, [double z = 0]) =>
      _Vec3(cx + x, minY + h * yFraction, cz + z);
  final b = _SkeletonBuilder();

  switch (rigType) {
    case 'quadruped':
      final hips = b.joint('Hips', -1, p(0, 0.6, -0.25 * d));
      final spine = b.joint('Spine', hips, p(0, 0.65, 0));
      final chest = b.joint('Chest', spine, p(0, 0.65, 0.2 * d));
      final neck = b.joint('Neck', chest, p(0, 0.75, 0.35 * d));
      final head = b.joint('Head', neck, p(0, 0.85, 0.45 * d));
      b.tip(head, p(0, 0.88, 0.52 * d));
      final tail1 = b.joint('Tail_1', hips, p(0, 0.6, -0.4 * d));
      final tail2 = b.joint('Tail_2', tail1, p(0, 0.55, -0.48 * d));
      b.tip(tail2, p(0, 0.5, -0.55 * d));
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        for (final (prefix, legRoot, legZ) in [
          ('Front', chest, 0.2 * d),
          ('Hind', hips, -0.25 * d),
        ]) {
          final upper = b.joint('${prefix}UpperLeg_$suffix', legRoot,
              p(sign * 0.22 * w, 0.5, legZ));
          final knee = b.joint('${prefix}LowerLeg_$suffix', upper,
              p(sign * 0.24 * w, 0.25, legZ));
          final foot = b.joint(
              '${prefix}Foot_$suffix', knee, p(sign * 0.25 * w, 0.04, legZ));
          b.tip(foot, p(sign * 0.25 * w, 0.02, legZ + 0.06 * d));
        }
      }
    case 'insect':
      final root = b.joint('Thorax', -1, p(0, 0.55, 0));
      final head = b.joint('Head', root, p(0, 0.6, 0.32 * d));
      b.tip(head, p(0, 0.6, 0.5 * d));
      final abdomen1 = b.joint('Abdomen_1', root, p(0, 0.52, -0.25 * d));
      final abdomen2 =
          b.joint('Abdomen_2', abdomen1, p(0, 0.48, -0.42 * d));
      b.tip(abdomen2, p(0, 0.45, -0.52 * d));
      var pair = 0;
      for (final legZ in [0.18 * d, 0.0, -0.18 * d]) {
        pair++;
        for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
          final hip = b.joint(
              'Leg${pair}Hip_$suffix', root, p(sign * 0.14 * w, 0.5, legZ));
          final mid = b.joint('Leg${pair}Mid_$suffix', hip,
              p(sign * 0.32 * w, 0.32, legZ));
          final foot = b.joint('Leg${pair}Foot_$suffix', mid,
              p(sign * 0.46 * w, 0.04, legZ));
          b.tip(foot, p(sign * 0.5 * w, 0.02, legZ));
        }
      }
    case 'bird':
      final root = b.joint('Body', -1, p(0, 0.5, 0));
      final chest = b.joint('Chest', root, p(0, 0.6, 0.12 * d));
      final neck = b.joint('Neck', chest, p(0, 0.72, 0.28 * d));
      final head = b.joint('Head', neck, p(0, 0.82, 0.4 * d));
      b.tip(head, p(0, 0.85, 0.5 * d));
      final tail = b.joint('Tail', root, p(0, 0.45, -0.4 * d));
      b.tip(tail, p(0, 0.42, -0.52 * d));
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        final wing = b.joint(
            'Wing_$suffix', chest, p(sign * 0.12 * w, 0.62, 0));
        final wingMid =
            b.joint('WingMid_$suffix', wing, p(sign * 0.3 * w, 0.62, 0));
        b.tip(wingMid, p(sign * 0.5 * w, 0.62, 0));
        final leg = b.joint('Leg_$suffix', root, p(sign * 0.07 * w, 0.32, 0));
        final foot =
            b.joint('Foot_$suffix', leg, p(sign * 0.07 * w, 0.04, 0));
        b.tip(foot, p(sign * 0.07 * w, 0.02, 0.06 * d));
      }
    case 'snake' || 'fish':
      // Gelenk-Kette entlang der längeren horizontalen Achse, Kopf am
      // +Ende (bei z: vorn).
      final segments = rigType == 'snake' ? 8 : 6;
      final alongZ = d >= w;
      var parent = -1;
      for (var i = 0; i < segments; i++) {
        final t = 0.45 - 0.9 * i / (segments - 1);
        parent = b.joint(
          i == 0 ? 'Head' : 'Spine_$i',
          parent,
          alongZ ? p(0, 0.5, t * d) : p(t * w, 0.5),
        );
      }
      b.tip(parent, alongZ ? p(0, 0.5, -0.55 * d) : p(-0.55 * w, 0.5));
      b.tip(0, alongZ ? p(0, 0.5, 0.55 * d) : p(0.55 * w, 0.5));
    default: // 'biped'
      final hips = b.joint('Hips', -1, p(0, 0.52));
      final spine = b.joint('Spine', hips, p(0, 0.62));
      final chest = b.joint('Chest', spine, p(0, 0.74));
      final neck = b.joint('Neck', chest, p(0, 0.84));
      final head = b.joint('Head', neck, p(0, 0.90));
      b.tip(head, p(0, 1.0));
      const armY = 0.80;
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        final shoulder =
            b.joint('Shoulder_$suffix', chest, p(sign * 0.10 * w, armY));
        final elbow =
            b.joint('Elbow_$suffix', shoulder, p(sign * 0.28 * w, armY));
        final hand =
            b.joint('Hand_$suffix', elbow, p(sign * 0.43 * w, armY));
        b.tip(hand, p(sign * 0.5 * w, armY));
      }
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        final upper =
            b.joint('UpperLeg_$suffix', hips, p(sign * 0.06 * w, 0.48));
        final knee =
            b.joint('Knee_$suffix', upper, p(sign * 0.06 * w, 0.26));
        final foot =
            b.joint('Foot_$suffix', knee, p(sign * 0.06 * w, 0.05));
        b.tip(foot, p(sign * 0.06 * w, 0.02, 0.2 * d));
      }
  }
  return (b.joints, b.bones);
}

/// Liest die Positionen eines POSITION-Accessors (float32 VEC3).
Float32List _readPositions(Map<String, dynamic> json, Uint8List bin,
    int accessorIndex) {
  final accessor =
      (json['accessors'] as List)[accessorIndex] as Map<String, dynamic>;
  if (accessor['componentType'] != 5126 ||
      accessor['type'] != 'VEC3' ||
      accessor.containsKey('sparse')) {
    throw Exception('Positionsformat wird nicht unterstützt.');
  }
  final viewIndex = accessor['bufferView'] as int?;
  if (viewIndex == null) {
    throw Exception('Positions-Accessor ohne Daten.');
  }
  final view =
      (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  final count = accessor['count'] as int;
  final stride = (view['byteStride'] as int?) ?? 12;
  final start = ((view['byteOffset'] as int?) ?? 0) +
      ((accessor['byteOffset'] as int?) ?? 0);
  final data = ByteData.sublistView(bin);
  final out = Float32List(count * 3);
  for (var i = 0; i < count; i++) {
    final o = start + i * stride;
    out[i * 3] = data.getFloat32(o, Endian.little);
    out[i * 3 + 1] = data.getFloat32(o + 4, Endian.little);
    out[i * 3 + 2] = data.getFloat32(o + 8, Endian.little);
  }
  return out;
}

/// Baut das Standard-Skelett des gewählten [rigType] in die GLB ein und
/// liefert die neue Datei. Wirft [Exception] mit verständlicher
/// Meldung, wenn das nicht geht.
Uint8List injectAutoRig(Uint8List glb, {String rigType = 'biped'}) {
  // GLB zerlegen.
  if (glb.length < 20) throw Exception('Ungültige GLB-Datei.');
  final header = ByteData.sublistView(glb);
  if (header.getUint32(0, Endian.little) != 0x46546C67 ||
      header.getUint32(4, Endian.little) != 2) {
    throw Exception('Ungültige GLB-Datei.');
  }
  final jsonLength = header.getUint32(12, Endian.little);
  if (header.getUint32(16, Endian.little) != 0x4E4F534A) {
    throw Exception('GLB ohne JSON-Chunk.');
  }
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  final binHeaderOffset = 20 + _pad4(jsonLength);
  var bin = Uint8List(0);
  if (binHeaderOffset + 8 <= glb.length &&
      header.getUint32(binHeaderOffset + 4, Endian.little) == 0x004E4942) {
    final binLength = header.getUint32(binHeaderOffset, Endian.little);
    bin = glb.sublist(binHeaderOffset + 8, binHeaderOffset + 8 + binLength);
  }

  if ((json['skins'] as List?)?.isNotEmpty ?? false) {
    throw Exception('Das Modell besitzt bereits ein Skelett.');
  }
  final meshes = (json['meshes'] as List?) ?? [];
  if (meshes.isEmpty) throw Exception('Die GLB enthält kein Mesh.');

  // Alle Primitive samt Positionen einlesen und Bounding Box bestimmen.
  final primitives = <(Map<String, dynamic>, Float32List)>[];
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (final mesh in meshes) {
    for (final primitive in (mesh as Map)['primitives'] as List) {
      final attributes =
          (primitive as Map)['attributes'] as Map<String, dynamic>;
      final positionIndex = attributes['POSITION'] as int?;
      if (positionIndex == null) continue;
      final positions = _readPositions(json, bin, positionIndex);
      primitives.add((primitive.cast<String, dynamic>(), positions));
      for (var i = 0; i < positions.length; i += 3) {
        final x = positions[i], y = positions[i + 1], z = positions[i + 2];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }
    }
  }
  if (primitives.isEmpty) {
    throw Exception('Keine Geometrie mit Positionsdaten gefunden.');
  }
  final height = maxY - minY, width = maxX - minX;
  if (height <= 0 || width <= 0) {
    throw Exception('Die Geometrie ist leer oder flach.');
  }
  if (rigType == 'biped' && height < 0.4 * width) {
    throw Exception(
        'Das Modell wirkt nicht wie eine aufrecht stehende Figur '
        '(zu breit/flach) – ggf. einen anderen Figurtyp wählen.');
  }

  final (joints, bones) =
      _skeletonFor(rigType, minX, maxX, minY, maxY, minZ, maxZ);

  // Neue Binärdaten: pro Primitive JOINTS_0 (ubyte VEC4) und WEIGHTS_0
  // (float VEC4), dazu die inversen Bind-Matrizen (MAT4 float).
  final bufferViews =
      ((json['bufferViews'] as List?) ?? []).cast<dynamic>().toList();
  final accessors =
      ((json['accessors'] as List?) ?? []).cast<dynamic>().toList();
  final appendParts = <Uint8List>[];
  var appendCursor = _pad4(bin.length);
  final appendOffsets = <int>[];
  int addPart(Uint8List part) {
    appendOffsets.add(appendCursor);
    appendParts.add(part);
    appendCursor = _pad4(appendCursor + part.length);
    return appendOffsets.length - 1;
  }

  for (final (primitive, positions) in primitives) {
    final vertexCount = positions.length ~/ 3;
    final jointData = Uint8List(vertexCount * 4);
    final weightData = Float32List(vertexCount * 4);
    for (var v = 0; v < vertexCount; v++) {
      final px = positions[v * 3],
          py = positions[v * 3 + 1],
          pz = positions[v * 3 + 2];
      // Die zwei nächsten Knochen bestimmen.
      var best = -1, second = -1;
      var bestD = double.infinity, secondD = double.infinity;
      for (var b = 0; b < bones.length; b++) {
        final d = _distToSegmentSq(px, py, pz, bones[b].from, bones[b].to);
        if (d < bestD) {
          second = best;
          secondD = bestD;
          best = b;
          bestD = d;
        } else if (d < secondD) {
          second = b;
          secondD = d;
        }
      }
      final eps = 1e-6 * height * height;
      final w0 = 1.0 / (bestD + eps);
      final w1 = second >= 0 ? 1.0 / (secondD + eps) : 0.0;
      final sum = w0 + w1;
      jointData[v * 4] = bones[best].joint;
      jointData[v * 4 + 1] = second >= 0 ? bones[second].joint : 0;
      weightData[v * 4] = w0 / sum;
      weightData[v * 4 + 1] = second >= 0 ? w1 / sum : 0.0;
    }

    final jointPart = addPart(jointData);
    final weightPart =
        addPart(weightData.buffer.asUint8List(0, weightData.lengthInBytes));
    bufferViews.add({
      'buffer': 0,
      'byteOffset': appendOffsets[jointPart],
      'byteLength': jointData.length,
      'target': 34962,
    });
    accessors.add({
      'bufferView': bufferViews.length - 1,
      'componentType': 5121,
      'count': vertexCount,
      'type': 'VEC4',
    });
    primitive['attributes']['JOINTS_0'] = accessors.length - 1;
    bufferViews.add({
      'buffer': 0,
      'byteOffset': appendOffsets[weightPart],
      'byteLength': weightData.lengthInBytes,
      'target': 34962,
    });
    accessors.add({
      'bufferView': bufferViews.length - 1,
      'componentType': 5126,
      'count': vertexCount,
      'type': 'VEC4',
    });
    primitive['attributes']['WEIGHTS_0'] = accessors.length - 1;
  }

  // Inverse Bind-Matrizen (reine Translationen).
  final ibm = Float32List(joints.length * 16);
  for (var j = 0; j < joints.length; j++) {
    final p = joints[j].position;
    final o = j * 16;
    ibm[o] = 1;
    ibm[o + 5] = 1;
    ibm[o + 10] = 1;
    ibm[o + 12] = -p.x;
    ibm[o + 13] = -p.y;
    ibm[o + 14] = -p.z;
    ibm[o + 15] = 1;
  }
  final ibmPart = addPart(ibm.buffer.asUint8List(0, ibm.lengthInBytes));
  bufferViews.add({
    'buffer': 0,
    'byteOffset': appendOffsets[ibmPart],
    'byteLength': ibm.lengthInBytes,
  });
  accessors.add({
    'bufferView': bufferViews.length - 1,
    'componentType': 5126,
    'count': joints.length,
    'type': 'MAT4',
  });
  final ibmAccessor = accessors.length - 1;

  // Skelett-Knoten anhängen (lokale Translationen relativ zum Elternteil).
  final nodes = ((json['nodes'] as List?) ?? []).cast<dynamic>().toList();
  final jointBase = nodes.length;
  for (var j = 0; j < joints.length; j++) {
    final joint = joints[j];
    final parentPos = joint.parent >= 0
        ? joints[joint.parent].position
        : const _Vec3(0, 0, 0);
    final children = [
      for (var c = 0; c < joints.length; c++)
        if (joints[c].parent == j) jointBase + c,
    ];
    nodes.add({
      'name': joint.name,
      'translation': [
        joint.position.x - parentPos.x,
        joint.position.y - parentPos.y,
        joint.position.z - parentPos.z,
      ],
      if (children.isNotEmpty) 'children': children,
    });
  }
  // Skin registrieren und den Mesh-Knoten zuweisen.
  json['skins'] = [
    {
      'joints': [for (var j = 0; j < joints.length; j++) jointBase + j],
      'inverseBindMatrices': ibmAccessor,
      'skeleton': jointBase,
    }
  ];
  for (final node in nodes) {
    if (node is Map && node.containsKey('mesh')) {
      node['skin'] = 0;
    }
  }
  json['nodes'] = nodes;
  json['bufferViews'] = bufferViews;
  json['accessors'] = accessors;
  for (final scene in (json['scenes'] as List?) ?? []) {
    ((scene as Map)['nodes'] as List?)?.add(jointBase);
  }

  // Binärpuffer zusammensetzen.
  final newBinLength = appendCursor;
  final newBin = Uint8List(newBinLength);
  newBin.setRange(0, bin.length, bin);
  for (var i = 0; i < appendParts.length; i++) {
    newBin.setRange(appendOffsets[i],
        appendOffsets[i] + appendParts[i].length, appendParts[i]);
  }
  (json['buffers'] as List)[0]['byteLength'] = newBinLength;

  // GLB neu schreiben.
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadded = Uint8List(_pad4(jsonBytes.length))
    ..fillRange(0, _pad4(jsonBytes.length), 0x20)
    ..setRange(0, jsonBytes.length, jsonBytes);
  final total = 12 + 8 + jsonPadded.length + 8 + newBinLength;
  final out = ByteData(total);
  var o = 0;
  void u32(int value) {
    out.setUint32(o, value, Endian.little);
    o += 4;
  }

  u32(0x46546C67);
  u32(2);
  u32(total);
  u32(jsonPadded.length);
  u32(0x4E4F534A);
  out.buffer.asUint8List().setRange(o, o + jsonPadded.length, jsonPadded);
  o += jsonPadded.length;
  u32(newBinLength);
  u32(0x004E4942);
  out.buffer.asUint8List().setRange(o, o + newBinLength, newBin);
  return out.buffer.asUint8List();
}

/// Für Tests und Anzeige: Gelenkzahl je Figurtyp.
const rigJointCounts = {
  'biped': 17,
  'quadruped': 19,
  'insect': 22,
  'bird': 13,
  'snake': 8,
  'fish': 6,
};

/// Kleiner Selbsttest-Helfer: prüft, ob eine GLB ein Skin trägt.
bool glbHasSkin(Uint8List glb) {
  final header = ByteData.sublistView(glb);
  final jsonLength = header.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  return (json['skins'] as List?)?.isNotEmpty ?? false;
}
