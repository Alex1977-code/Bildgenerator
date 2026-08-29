import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Liest ein GLB (binäres glTF 2.0) für die eingebaute 3D-Vorschau ein:
/// Positionen, Indizes und Farben je Vertex (aus COLOR_0 oder – angenähert –
/// aus der Basisfarb-Textur). Node-Transformationen und Materialdetails
/// werden für die Vorschau ignoriert.
class PreviewMesh {
  PreviewMesh({
    required this.positions,
    required this.indices,
    required this.colors,
    required this.center,
    required this.extent,
    this.rig,
  });

  final Float32List positions; // x,y,z je Vertex
  final Uint32List indices;
  final Int32List colors; // ARGB je Vertex
  final List<double> center;
  final double extent;

  /// Skelett samt Skin-Gewichten und Animationen (falls vorhanden).
  final PreviewRig? rig;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// Knoten der Szenen-Hierarchie (nur Translation/Rotation/Skalierung).
class RigNode {
  RigNode({
    required this.parent,
    required this.translation,
    required this.rotation,
    required this.scale,
    required this.name,
  });

  final int parent; // -1 = Wurzel
  final Float32List translation; // x,y,z
  final Float32List rotation; // Quaternion x,y,z,w
  final Float32List scale; // x,y,z
  final String name;
}

/// Ein Animations-Kanal: steuert Translation/Rotation/Skalierung eines
/// Knotens über der Zeit (lineare Interpolation).
class PreviewChannel {
  PreviewChannel({
    required this.node,
    required this.path,
    required this.times,
    required this.values,
    required this.components,
  });

  final int node;
  final String path; // 'translation' | 'rotation' | 'scale'
  final Float32List times;
  final Float32List values; // times.length * components
  final int components; // 3 bzw. 4 (Rotation)
}

class PreviewAnimation {
  PreviewAnimation({
    required this.name,
    required this.channels,
    required this.duration,
  });

  final String name;
  final List<PreviewChannel> channels;
  final double duration;
}

/// Skelett-Daten fürs CPU-Skinning der Vorschau.
class PreviewRig {
  PreviewRig({
    required this.nodes,
    required this.nodeOrder,
    required this.joints,
    required this.jointParents,
    required this.inverseBindMatrices,
    required this.vertexJoints,
    required this.vertexWeights,
    required this.animations,
  });

  final List<RigNode> nodes;
  final List<int> nodeOrder; // Eltern vor Kindern
  final List<int> joints; // Skin-Joint → Knotenindex
  final List<int> jointParents; // Skin-Joint → Skin-Joint-Elternteil (-1)
  final Float32List inverseBindMatrices; // joints*16, column-major
  final Uint16List vertexJoints; // vertexCount*4 (Skin-Joint-Slots)
  final Float32List vertexWeights; // vertexCount*4
  final List<PreviewAnimation> animations;

  List<String> get jointNames => [for (final j in joints) nodes[j].name];
}

class _Gltf {
  _Gltf(this.json, this.bin);
  final Map<String, dynamic> json;
  final Uint8List bin;

  Map<String, dynamic> accessor(int index) =>
      (json['accessors'] as List)[index] as Map<String, dynamic>;

  ({int offset, int? stride, Uint8List bytes}) view(int accessorIndex) {
    final acc = accessor(accessorIndex);
    final bv = (json['bufferViews'] as List)[acc['bufferView'] as int]
        as Map<String, dynamic>;
    final offset =
        ((bv['byteOffset'] as num?)?.toInt() ?? 0) +
            ((acc['byteOffset'] as num?)?.toInt() ?? 0);
    return (
      offset: offset,
      stride: (bv['byteStride'] as num?)?.toInt(),
      bytes: bin,
    );
  }

  Uint8List viewBytes(int bufferViewIndex) {
    final bv = (json['bufferViews'] as List)[bufferViewIndex]
        as Map<String, dynamic>;
    final offset = (bv['byteOffset'] as num?)?.toInt() ?? 0;
    final length = (bv['byteLength'] as num).toInt();
    return Uint8List.sublistView(bin, offset, offset + length);
  }
}

int _componentCount(String type) => switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      'MAT2' => 4,
      'MAT3' => 9,
      'MAT4' => 16,
      _ => 3,
    };

/// Liest einen Attribut-Accessor als Gleitkommawerte (mit Stride,
/// normalisiert Byte-/Short-Komponenten auf 0–1).
Float32List _readFloats(_Gltf gltf, int accessorIndex) {
  final acc = gltf.accessor(accessorIndex);
  final count = (acc['count'] as num).toInt();
  final components = _componentCount(acc['type'] as String);
  final componentType = (acc['componentType'] as num).toInt();
  final v = gltf.view(accessorIndex);
  final data = ByteData.sublistView(v.bytes);

  final componentSize = switch (componentType) {
    5126 => 4, // float
    5123 || 5122 => 2, // ushort / short
    5121 || 5120 => 1, // ubyte / byte
    _ => 4,
  };
  final stride = v.stride ?? components * componentSize;
  final out = Float32List(count * components);
  for (var i = 0; i < count; i++) {
    final base = v.offset + i * stride;
    for (var c = 0; c < components; c++) {
      final at = base + c * componentSize;
      out[i * components + c] = switch (componentType) {
        5126 => data.getFloat32(at, Endian.little),
        5123 => data.getUint16(at, Endian.little) / 65535.0,
        5121 => data.getUint8(at) / 255.0,
        5122 => (data.getInt16(at, Endian.little) / 32767.0).clamp(-1, 1),
        5120 => (data.getInt8(at) / 127.0).clamp(-1, 1),
        _ => 0,
      };
    }
  }
  return out;
}

/// Liest einen Accessor als rohe Ganzzahlen (z. B. JOINTS_0).
Uint16List _readUints(_Gltf gltf, int accessorIndex) {
  final acc = gltf.accessor(accessorIndex);
  final count = (acc['count'] as num).toInt();
  final components = _componentCount(acc['type'] as String);
  final componentType = (acc['componentType'] as num).toInt();
  final v = gltf.view(accessorIndex);
  final data = ByteData.sublistView(v.bytes);
  final size = switch (componentType) { 5125 => 4, 5123 => 2, _ => 1 };
  final stride = v.stride ?? components * size;
  final out = Uint16List(count * components);
  for (var i = 0; i < count; i++) {
    final base = v.offset + i * stride;
    for (var c = 0; c < components; c++) {
      final at = base + c * size;
      out[i * components + c] = switch (componentType) {
        5125 => data.getUint32(at, Endian.little),
        5123 => data.getUint16(at, Endian.little),
        _ => data.getUint8(at),
      };
    }
  }
  return out;
}

Uint32List _readIndices(_Gltf gltf, int accessorIndex) {
  final acc = gltf.accessor(accessorIndex);
  final count = (acc['count'] as num).toInt();
  final componentType = (acc['componentType'] as num).toInt();
  final v = gltf.view(accessorIndex);
  final data = ByteData.sublistView(v.bytes);
  final size = switch (componentType) { 5125 => 4, 5123 => 2, _ => 1 };
  final stride = v.stride ?? size;
  final out = Uint32List(count);
  for (var i = 0; i < count; i++) {
    final at = v.offset + i * stride;
    out[i] = switch (componentType) {
      5125 => data.getUint32(at, Endian.little),
      5123 => data.getUint16(at, Endian.little),
      _ => data.getUint8(at),
    };
  }
  return out;
}

int _packColor(double r, double g, double b) =>
    0xFF000000 |
    ((r * 255).round().clamp(0, 255) << 16) |
    ((g * 255).round().clamp(0, 255) << 8) |
    (b * 255).round().clamp(0, 255);

const int _defaultColor = 0xFFB9BCC4;

/// Dekodiert die Basisfarb-Textur eines Primitivs (falls vorhanden).
Future<({Uint8List rgba, int width, int height})?> _decodeTexture(
    _Gltf gltf, Map<String, dynamic> primitive) async {
  try {
    final materialIndex = primitive['material'] as int?;
    if (materialIndex == null) return null;
    final material = (gltf.json['materials'] as List?)?[materialIndex]
        as Map<String, dynamic>?;
    final textureInfo = ((material?['pbrMetallicRoughness']
        as Map<String, dynamic>?)?['baseColorTexture'])
        as Map<String, dynamic>?;
    if (textureInfo == null) return null;
    final texture = (gltf.json['textures'] as List)[textureInfo['index'] as int]
        as Map<String, dynamic>;
    final image = (gltf.json['images'] as List)[texture['source'] as int]
        as Map<String, dynamic>;
    final bufferView = image['bufferView'] as int?;
    if (bufferView == null) return null;
    final codec = await ui.instantiateImageCodec(
      gltf.viewBytes(bufferView),
      targetWidth: 256,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    final decoded = frame.image;
    try {
      final raw =
          await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) return null;
      return (
        rgba: raw.buffer.asUint8List(),
        width: decoded.width,
        height: decoded.height,
      );
    } finally {
      decoded.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Parst ein GLB und liefert das Vorschau-Mesh (oder wirft bei Fehlern).
Future<PreviewMesh> parseGlbForPreview(Uint8List glb) async {
  final data = ByteData.sublistView(glb);
  if (glb.length < 20 || data.getUint32(0, Endian.little) != 0x46546C67) {
    throw Exception('Keine GLB-Datei.');
  }
  final jsonLength = data.getUint32(12, Endian.little);
  if (data.getUint32(16, Endian.little) != 0x4E4F534A) {
    throw Exception('GLB ohne JSON-Chunk.');
  }
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  var bin = Uint8List(0);
  final binHeader = 20 + jsonLength;
  if (glb.length >= binHeader + 8) {
    final binLength = data.getUint32(binHeader, Endian.little);
    bin = Uint8List.sublistView(
        glb, binHeader + 8, binHeader + 8 + binLength);
  }
  final gltf = _Gltf(json, bin);

  final allPositions = <double>[];
  final allColors = <int>[];
  final allIndices = <int>[];
  final allJoints = <int>[];
  final allWeights = <double>[];
  var hasSkinData = false;

  final meshes = json['meshes'] as List? ?? [];
  for (final mesh in meshes) {
    final primitives =
        (mesh as Map<String, dynamic>)['primitives'] as List? ?? [];
    for (final primitiveRaw in primitives) {
      final primitive = primitiveRaw as Map<String, dynamic>;
      if ((primitive['mode'] as num?)?.toInt() case final mode?
          when mode != 4) {
        continue; // nur Dreiecke
      }
      final attributes = primitive['attributes'] as Map<String, dynamic>;
      final positionAccessor = attributes['POSITION'] as int?;
      if (positionAccessor == null) continue;
      final positions = _readFloats(gltf, positionAccessor);
      final vertexCount = positions.length ~/ 3;
      final base = allPositions.length ~/ 3;

      // Farben: COLOR_0, sonst Textur-Abtastung, sonst Grau.
      var colors = List<int>.filled(vertexCount, _defaultColor);
      final colorAccessor = attributes['COLOR_0'] as int?;
      if (colorAccessor != null) {
        final acc = gltf.accessor(colorAccessor);
        final components = _componentCount(acc['type'] as String);
        final values = _readFloats(gltf, colorAccessor);
        for (var i = 0; i < vertexCount; i++) {
          colors[i] = _packColor(values[i * components],
              values[i * components + 1], values[i * components + 2]);
        }
      } else if (attributes['TEXCOORD_0'] case final uvAccessor?) {
        final texture = await _decodeTexture(gltf, primitive);
        if (texture != null) {
          final uvs = _readFloats(gltf, uvAccessor as int);
          for (var i = 0; i < vertexCount; i++) {
            var u = uvs[i * 2] % 1.0;
            var v = uvs[i * 2 + 1] % 1.0;
            if (u < 0) u += 1;
            if (v < 0) v += 1;
            final x =
                (u * (texture.width - 1)).round().clamp(0, texture.width - 1);
            final y = (v * (texture.height - 1))
                .round()
                .clamp(0, texture.height - 1);
            final o = (y * texture.width + x) * 4;
            colors[i] = _packColor(texture.rgba[o] / 255.0,
                texture.rgba[o + 1] / 255.0, texture.rgba[o + 2] / 255.0);
          }
        }
      }

      allPositions.addAll(positions);
      allColors.addAll(colors);

      // Skin-Daten (für Animationen und Skelett-Anzeige).
      final jointsAccessor = attributes['JOINTS_0'] as int?;
      final weightsAccessor = attributes['WEIGHTS_0'] as int?;
      if (jointsAccessor != null && weightsAccessor != null) {
        hasSkinData = true;
        allJoints.addAll(_readUints(gltf, jointsAccessor));
        allWeights.addAll(_readFloats(gltf, weightsAccessor));
      } else {
        allJoints.addAll(List.filled(vertexCount * 4, 0));
        allWeights.addAll(List.filled(vertexCount * 4, 0.0));
      }

      final indicesAccessor = primitive['indices'] as int?;
      if (indicesAccessor != null) {
        for (final index in _readIndices(gltf, indicesAccessor)) {
          allIndices.add(base + index);
        }
      } else {
        for (var i = 0; i < vertexCount; i++) {
          allIndices.add(base + i);
        }
      }
    }
  }

  if (allIndices.isEmpty) {
    throw Exception('Das Modell enthält keine darstellbaren Dreiecke.');
  }

  final positions = Float32List.fromList(allPositions);
  final minPos = [double.infinity, double.infinity, double.infinity];
  final maxPos = [
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity
  ];
  for (var i = 0; i < positions.length; i += 3) {
    for (var k = 0; k < 3; k++) {
      final value = positions[i + k];
      if (value < minPos[k]) minPos[k] = value;
      if (value > maxPos[k]) maxPos[k] = value;
    }
  }
  final center = [
    (minPos[0] + maxPos[0]) / 2,
    (minPos[1] + maxPos[1]) / 2,
    (minPos[2] + maxPos[2]) / 2,
  ];
  var extent = 0.0;
  for (var k = 0; k < 3; k++) {
    extent = math.max(extent, maxPos[k] - minPos[k]);
  }

  // Skelett/Skin einlesen – Fehler hier machen nur die Animation
  // unmöglich, die statische Vorschau bleibt erhalten.
  PreviewRig? rig;
  if (hasSkinData) {
    try {
      rig = _parseRig(gltf, allJoints, allWeights);
    } catch (_) {
      rig = null;
    }
  }

  return PreviewMesh(
    positions: positions,
    indices: Uint32List.fromList(allIndices),
    colors: Int32List.fromList(allColors),
    center: center,
    extent: extent <= 0 ? 1 : extent,
    rig: rig,
  );
}

PreviewRig? _parseRig(
    _Gltf gltf, List<int> allJoints, List<double> allWeights) {
  final json = gltf.json;
  final skins = json['skins'] as List? ?? [];
  if (skins.isEmpty) return null;
  final skin = skins.first as Map<String, dynamic>;
  final joints = [for (final j in skin['joints'] as List) (j as num).toInt()];
  if (joints.isEmpty) return null;

  // Knoten samt Eltern-Beziehung.
  final rawNodes = json['nodes'] as List? ?? [];
  final parents = List<int>.filled(rawNodes.length, -1);
  for (var i = 0; i < rawNodes.length; i++) {
    for (final child in (rawNodes[i] as Map)['children'] as List? ?? []) {
      parents[(child as num).toInt()] = i;
    }
  }
  final nodes = <RigNode>[];
  for (var i = 0; i < rawNodes.length; i++) {
    final raw = rawNodes[i] as Map;
    List<double> vec(String key, List<double> fallback) {
      final value = raw[key] as List?;
      return value == null
          ? fallback
          : [for (final x in value) (x as num).toDouble()];
    }

    var translation = vec('translation', const [0, 0, 0]);
    if (raw['matrix'] case final List matrix?) {
      // Näherung: nur die Translation aus der Matrix übernehmen.
      translation = [
        (matrix[12] as num).toDouble(),
        (matrix[13] as num).toDouble(),
        (matrix[14] as num).toDouble(),
      ];
    }
    nodes.add(RigNode(
      parent: parents[i],
      translation: Float32List.fromList(translation),
      rotation: Float32List.fromList(vec('rotation', const [0, 0, 0, 1])),
      scale: Float32List.fromList(vec('scale', const [1, 1, 1])),
      name: (raw['name'] as String?) ?? 'Knoten $i',
    ));
  }

  // Reihenfolge: Eltern vor Kindern.
  final nodeOrder = <int>[];
  final queue = <int>[
    for (var i = 0; i < nodes.length; i++)
      if (nodes[i].parent < 0) i,
  ];
  final childLists = List<List<int>>.generate(nodes.length, (_) => []);
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].parent >= 0) childLists[nodes[i].parent].add(i);
  }
  while (queue.isNotEmpty) {
    final node = queue.removeAt(0);
    nodeOrder.add(node);
    queue.addAll(childLists[node]);
  }

  // Eltern-Gelenk je Skin-Joint (nächster Vorfahre, der auch Joint ist).
  final nodeToJoint = <int, int>{
    for (var j = 0; j < joints.length; j++) joints[j]: j,
  };
  final jointParents = <int>[];
  for (final jointNode in joints) {
    var ancestor = nodes[jointNode].parent;
    while (ancestor >= 0 && !nodeToJoint.containsKey(ancestor)) {
      ancestor = nodes[ancestor].parent;
    }
    jointParents.add(ancestor >= 0 ? nodeToJoint[ancestor]! : -1);
  }

  final ibmAccessor = skin['inverseBindMatrices'] as int?;
  Float32List ibm;
  if (ibmAccessor != null) {
    ibm = _readFloats(gltf, ibmAccessor);
  } else {
    ibm = Float32List(joints.length * 16);
    for (var j = 0; j < joints.length; j++) {
      ibm[j * 16] = 1;
      ibm[j * 16 + 5] = 1;
      ibm[j * 16 + 10] = 1;
      ibm[j * 16 + 15] = 1;
    }
  }

  // Animationen (lineare Interpolation; CUBICSPLINE wird auf die
  // Stützwerte reduziert).
  final animations = <PreviewAnimation>[];
  final animationsJson = json['animations'] as List? ?? [];
  for (var a = 0; a < animationsJson.length; a++) {
    final anim = animationsJson[a] as Map<String, dynamic>;
    final samplers = anim['samplers'] as List;
    final channels = <PreviewChannel>[];
    var duration = 0.0;
    for (final channelRaw in anim['channels'] as List) {
      final channel = channelRaw as Map<String, dynamic>;
      final target = channel['target'] as Map<String, dynamic>;
      final path = target['path'] as String?;
      final node = (target['node'] as num?)?.toInt();
      if (node == null ||
          (path != 'translation' && path != 'rotation' && path != 'scale')) {
        continue;
      }
      final sampler =
          samplers[(channel['sampler'] as num).toInt()] as Map<String, dynamic>;
      final times = _readFloats(gltf, (sampler['input'] as num).toInt());
      var values = _readFloats(gltf, (sampler['output'] as num).toInt());
      final components = path == 'rotation' ? 4 : 3;
      if (sampler['interpolation'] == 'CUBICSPLINE' &&
          values.length == times.length * components * 3) {
        final reduced = Float32List(times.length * components);
        for (var k = 0; k < times.length; k++) {
          for (var c = 0; c < components; c++) {
            reduced[k * components + c] =
                values[(k * 3 + 1) * components + c];
          }
        }
        values = reduced;
      }
      if (values.length < times.length * components || times.isEmpty) {
        continue;
      }
      channels.add(PreviewChannel(
        node: node,
        path: path!,
        times: times,
        values: values,
        components: components,
      ));
      if (times.last > duration) duration = times.last;
    }
    if (channels.isNotEmpty) {
      animations.add(PreviewAnimation(
        name: (anim['name'] as String?) ?? 'Animation ${a + 1}',
        channels: channels,
        duration: duration <= 0 ? 1 : duration,
      ));
    }
  }

  return PreviewRig(
    nodes: nodes,
    nodeOrder: nodeOrder,
    joints: joints,
    jointParents: jointParents,
    inverseBindMatrices: ibm,
    vertexJoints: Uint16List.fromList(allJoints),
    vertexWeights: Float32List.fromList(allWeights),
    animations: animations,
  );
}

// ---------- Pose-Berechnung (CPU-Skinning) ----------

void _mulMat4(Float32List out, int o, Float32List a, int ao, Float32List b,
    int bo) {
  for (var col = 0; col < 4; col++) {
    for (var row = 0; row < 4; row++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[ao + k * 4 + row] * b[bo + col * 4 + k];
      }
      out[o + col * 4 + row] = sum;
    }
  }
}

void _trsToMatrix(Float32List out, int o, double tx, double ty, double tz,
    double qx, double qy, double qz, double qw, double sx, double sy,
    double sz) {
  final x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
  final xx = qx * x2, yy = qy * y2, zz = qz * z2;
  final xy = qx * y2, xz = qx * z2, yz = qy * z2;
  final wx = qw * x2, wy = qw * y2, wz = qw * z2;
  out[o] = (1 - (yy + zz)) * sx;
  out[o + 1] = (xy + wz) * sx;
  out[o + 2] = (xz - wy) * sx;
  out[o + 3] = 0;
  out[o + 4] = (xy - wz) * sy;
  out[o + 5] = (1 - (xx + zz)) * sy;
  out[o + 6] = (yz + wx) * sy;
  out[o + 7] = 0;
  out[o + 8] = (xz + wy) * sz;
  out[o + 9] = (yz - wx) * sz;
  out[o + 10] = (1 - (xx + yy)) * sz;
  out[o + 11] = 0;
  out[o + 12] = tx;
  out[o + 13] = ty;
  out[o + 14] = tz;
  out[o + 15] = 1;
}

/// q = a ⊗ b (beide als x,y,z,w).
void _quatMul(Float32List out, int o, double ax, double ay, double az,
    double aw, double bx, double by, double bz, double bw) {
  out[o] = aw * bx + ax * bw + ay * bz - az * by;
  out[o + 1] = aw * by - ax * bz + ay * bw + az * bx;
  out[o + 2] = aw * bz + ax * by - ay * bx + az * bw;
  out[o + 3] = aw * bw - ax * bx - ay * by - az * bz;
}

/// Weltmatrizen aller Knoten für eine (optionale) Animationspose plus
/// zusätzliche lokale Rotations-Overrides (Knotenindex → Quaternion).
Float32List _globalMatrices(
  PreviewRig rig, {
  PreviewAnimation? animation,
  double time = 0,
  Map<int, Float32List>? rotationOverrides,
}) {
  final n = rig.nodes.length;
  final t = Float32List(n * 3);
  final r = Float32List(n * 4);
  final s = Float32List(n * 3);
  for (var i = 0; i < n; i++) {
    final node = rig.nodes[i];
    t.setRange(i * 3, i * 3 + 3, node.translation);
    r.setRange(i * 4, i * 4 + 4, node.rotation);
    s.setRange(i * 3, i * 3 + 3, node.scale);
  }

  if (animation != null) {
    for (final channel in animation.channels) {
      final times = channel.times;
      final looped = animation.duration <= 0
          ? 0.0
          : time % animation.duration;
      var k = 0;
      while (k < times.length - 1 && times[k + 1] < looped) {
        k++;
      }
      final k1 = (k + 1).clamp(0, times.length - 1);
      final span = times[k1] - times[k];
      final f = span <= 0 ? 0.0 : ((looped - times[k]) / span).clamp(0.0, 1.0);
      final c = channel.components;
      final base0 = k * c, base1 = k1 * c;
      if (channel.path == 'rotation') {
        var x = channel.values[base0];
        var y = channel.values[base0 + 1];
        var z = channel.values[base0 + 2];
        var w = channel.values[base0 + 3];
        var x1 = channel.values[base1];
        var y1 = channel.values[base1 + 1];
        var z1 = channel.values[base1 + 2];
        var w1 = channel.values[base1 + 3];
        // NLERP mit Vorzeichen-Korrektur.
        if (x * x1 + y * y1 + z * z1 + w * w1 < 0) {
          x1 = -x1;
          y1 = -y1;
          z1 = -z1;
          w1 = -w1;
        }
        x += (x1 - x) * f;
        y += (y1 - y) * f;
        z += (z1 - z) * f;
        w += (w1 - w) * f;
        final len = math.sqrt(x * x + y * y + z * z + w * w);
        final inv = len < 1e-12 ? 0 : 1 / len;
        r[channel.node * 4] = x * inv;
        r[channel.node * 4 + 1] = y * inv;
        r[channel.node * 4 + 2] = z * inv;
        r[channel.node * 4 + 3] = w * inv;
      } else {
        final out = channel.path == 'translation' ? t : s;
        for (var comp = 0; comp < 3; comp++) {
          final v0 = channel.values[base0 + comp];
          final v1 = channel.values[base1 + comp];
          out[channel.node * 3 + comp] = v0 + (v1 - v0) * f;
        }
      }
    }
  }

  if (rotationOverrides != null) {
    for (final entry in rotationOverrides.entries) {
      final i = entry.key;
      if (i < 0 || i >= n) continue;
      final q = entry.value;
      _quatMul(r, i * 4, r[i * 4], r[i * 4 + 1], r[i * 4 + 2], r[i * 4 + 3],
          q[0], q[1], q[2], q[3]);
    }
  }

  final globals = Float32List(n * 16);
  final local = Float32List(16);
  for (final i in rig.nodeOrder) {
    _trsToMatrix(local, 0, t[i * 3], t[i * 3 + 1], t[i * 3 + 2], r[i * 4],
        r[i * 4 + 1], r[i * 4 + 2], r[i * 4 + 3], s[i * 3], s[i * 3 + 1],
        s[i * 3 + 2]);
    final parent = rig.nodes[i].parent;
    if (parent < 0) {
      globals.setRange(i * 16, i * 16 + 16, local);
    } else {
      _mulMat4(globals, i * 16, globals, parent * 16, local, 0);
    }
  }
  return globals;
}

/// CPU-Skinning: neue Vertex-Positionen für eine Pose. Vertices ohne
/// Gewichte behalten ihre Ruheposition.
Float32List computeSkinnedPositions(
  PreviewMesh mesh, {
  PreviewAnimation? animation,
  double time = 0,
  Map<int, Float32List>? rotationOverrides,
}) {
  final rig = mesh.rig;
  if (rig == null) return mesh.positions;
  final globals = _globalMatrices(rig,
      animation: animation, time: time, rotationOverrides: rotationOverrides);
  final jointCount = rig.joints.length;
  final jm = Float32List(jointCount * 16);
  for (var j = 0; j < jointCount; j++) {
    _mulMat4(jm, j * 16, globals, rig.joints[j] * 16,
        rig.inverseBindMatrices, j * 16);
  }

  final rest = mesh.positions;
  final out = Float32List(rest.length);
  final vertexCount = rest.length ~/ 3;
  for (var v = 0; v < vertexCount; v++) {
    final px = rest[v * 3], py = rest[v * 3 + 1], pz = rest[v * 3 + 2];
    var x = 0.0, y = 0.0, z = 0.0, weightSum = 0.0;
    for (var k = 0; k < 4; k++) {
      final w = rig.vertexWeights[v * 4 + k];
      if (w <= 0) continue;
      weightSum += w;
      final o = rig.vertexJoints[v * 4 + k] * 16;
      x += w * (jm[o] * px + jm[o + 4] * py + jm[o + 8] * pz + jm[o + 12]);
      y += w *
          (jm[o + 1] * px + jm[o + 5] * py + jm[o + 9] * pz + jm[o + 13]);
      z += w *
          (jm[o + 2] * px + jm[o + 6] * py + jm[o + 10] * pz + jm[o + 14]);
    }
    if (weightSum < 1e-6) {
      out[v * 3] = px;
      out[v * 3 + 1] = py;
      out[v * 3 + 2] = pz;
    } else {
      out[v * 3] = x / weightSum;
      out[v * 3 + 1] = y / weightSum;
      out[v * 3 + 2] = z / weightSum;
    }
  }
  return out;
}

/// Weltpositionen der Gelenke (x,y,z je Skin-Joint) für die
/// Skelett-Anzeige – mit derselben Pose wie [computeSkinnedPositions].
Float32List computeJointPositions(
  PreviewMesh mesh, {
  PreviewAnimation? animation,
  double time = 0,
  Map<int, Float32List>? rotationOverrides,
}) {
  final rig = mesh.rig!;
  final globals = _globalMatrices(rig,
      animation: animation, time: time, rotationOverrides: rotationOverrides);
  final out = Float32List(rig.joints.length * 3);
  for (var j = 0; j < rig.joints.length; j++) {
    final o = rig.joints[j] * 16;
    out[j * 3] = globals[o + 12];
    out[j * 3 + 1] = globals[o + 13];
    out[j * 3 + 2] = globals[o + 14];
  }
  return out;
}
