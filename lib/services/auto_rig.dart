/// Eigenes Auto-Rigging: baut ein Standard-Humanoid-Skelett (17 Gelenke,
/// T-Pose-Heuristik aus der Bounding Box) direkt in eine GLB-Datei ein –
/// komplett lokal, ohne API. Die Skin-Gewichte entstehen über den
/// Abstand jedes Vertex zu den Knochensegmenten (die zwei nächsten
/// Knochen werden gemischt).
///
/// Funktioniert für aufrecht stehende Figuren in T-Pose (y = oben,
/// Blick nach +z) – genau das, was die App bei aktivem Rigging erzeugt.
/// Texturen, Materialien und alle übrigen Daten der GLB bleiben
/// unverändert; es kommen nur Skelett-Knoten, ein Skin und
/// JOINTS_0/WEIGHTS_0-Attribute hinzu.
library;

import 'dart:convert';
import 'dart:typed_data';

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

/// Baut das Skelett aus der Bounding Box der Figur.
(List<_Joint>, List<_Bone>) _buildSkeleton(
    double minX, double maxX, double minY, double maxY,
    double minZ, double maxZ) {
  final h = maxY - minY;
  final w = maxX - minX;
  final d = maxZ - minZ;
  final cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  _Vec3 at(double xOffset, double yFraction, [double zOffset = 0]) =>
      _Vec3(cx + xOffset, minY + h * yFraction, cz + zOffset);

  final hips = at(0, 0.52);
  final spine = at(0, 0.62);
  final chest = at(0, 0.74);
  final neck = at(0, 0.84);
  final head = at(0, 0.90);
  final headTop = at(0, 1.0);
  final armY = 0.80;
  final shoulderL = at(-0.10 * w, armY), shoulderR = at(0.10 * w, armY);
  final elbowL = at(-0.28 * w, armY), elbowR = at(0.28 * w, armY);
  final handL = at(-0.43 * w, armY), handR = at(0.43 * w, armY);
  final handTipL = at(-0.5 * w, armY), handTipR = at(0.5 * w, armY);
  final legX = 0.06 * w;
  final upperLegL = at(-legX, 0.48), upperLegR = at(legX, 0.48);
  final kneeL = at(-legX, 0.26), kneeR = at(legX, 0.26);
  final footL = at(-legX, 0.05), footR = at(legX, 0.05);
  final toeL = at(-legX, 0.02, 0.2 * d), toeR = at(legX, 0.02, 0.2 * d);

  final joints = [
    _Joint('Hips', -1, hips), // 0
    _Joint('Spine', 0, spine), // 1
    _Joint('Chest', 1, chest), // 2
    _Joint('Neck', 2, neck), // 3
    _Joint('Head', 3, head), // 4
    _Joint('Shoulder_L', 2, shoulderL), // 5
    _Joint('Elbow_L', 5, elbowL), // 6
    _Joint('Hand_L', 6, handL), // 7
    _Joint('Shoulder_R', 2, shoulderR), // 8
    _Joint('Elbow_R', 8, elbowR), // 9
    _Joint('Hand_R', 9, handR), // 10
    _Joint('UpperLeg_L', 0, upperLegL), // 11
    _Joint('Knee_L', 11, kneeL), // 12
    _Joint('Foot_L', 12, footL), // 13
    _Joint('UpperLeg_R', 0, upperLegR), // 14
    _Joint('Knee_R', 14, kneeR), // 15
    _Joint('Foot_R', 15, footR), // 16
  ];
  final bones = [
    _Bone(0, hips, spine),
    _Bone(0, hips, upperLegL),
    _Bone(0, hips, upperLegR),
    _Bone(1, spine, chest),
    _Bone(2, chest, neck),
    _Bone(2, chest, shoulderL),
    _Bone(2, chest, shoulderR),
    _Bone(3, neck, head),
    _Bone(4, head, headTop),
    _Bone(5, shoulderL, elbowL),
    _Bone(6, elbowL, handL),
    _Bone(7, handL, handTipL),
    _Bone(8, shoulderR, elbowR),
    _Bone(9, elbowR, handR),
    _Bone(10, handR, handTipR),
    _Bone(11, upperLegL, kneeL),
    _Bone(12, kneeL, footL),
    _Bone(13, footL, toeL),
    _Bone(14, upperLegR, kneeR),
    _Bone(15, kneeR, footR),
    _Bone(16, footR, toeR),
  ];
  return (joints, bones);
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

/// Baut das Humanoid-Skelett in die GLB ein und liefert die neue Datei.
/// Wirft [Exception] mit verständlicher Meldung, wenn das nicht geht.
Uint8List injectHumanoidRig(Uint8List glb) {
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
  if (height < 0.5 * width) {
    throw Exception(
        'Das Modell wirkt nicht wie eine aufrecht stehende Figur '
        '(zu breit/flach für das Standard-Skelett).');
  }

  final (joints, bones) = _buildSkeleton(minX, maxX, minY, maxY, minZ, maxZ);

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

/// Für Tests: Anzahl der Gelenke des Standard-Skeletts.
const humanoidJointCount = 17;

/// Kleiner Selbsttest-Helfer: prüft, ob eine GLB ein Skin trägt.
bool glbHasSkin(Uint8List glb) {
  final header = ByteData.sublistView(glb);
  final jsonLength = header.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  return (json['skins'] as List?)?.isNotEmpty ?? false;
}
