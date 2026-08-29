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
  });

  final Float32List positions; // x,y,z je Vertex
  final Uint32List indices;
  final Int32List colors; // ARGB je Vertex
  final List<double> center;
  final double extent;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
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
    5123 => 2, // ushort
    5121 => 1, // ubyte
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
        _ => 0,
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

  return PreviewMesh(
    positions: positions,
    indices: Uint32List.fromList(allIndices),
    colors: Int32List.fromList(allColors),
    center: center,
    extent: extent <= 0 ? 1 : extent,
  );
}
