import 'dart:convert';
import 'dart:typed_data';

import 'preview_animations.dart';

/// Backt die eingebauten Testanimationen als echte glTF-Animations-Clips
/// in eine GLB-Datei: Die Gelenk-Rotationen werden über einen kompletten
/// Bewegungszyklus abgetastet und als Keyframes gespeichert – das
/// Ergebnis läuft als Loop in Blender, Unity, Godot und jedem
/// glTF-Viewer. Alle vorhandenen Inhalte (Geometrie, Texturen, Skin,
/// bestehende Clips) bleiben unverändert.
int _pad4(int n) => (n + 3) & ~3;

/// q = a ⊗ b (beide x,y,z,w).
List<double> _quatMul(List<double> a, Float32List b) => [
      a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
      a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
      a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
      a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    ];

Uint8List bakeAnimationsIntoGlb(
  Uint8List glb,
  List<ProceduralClip> clips, {
  int fps = 24,
}) {
  if (clips.isEmpty) return glb;

  // GLB zerlegen.
  final header = ByteData.sublistView(glb);
  if (glb.length < 20 ||
      header.getUint32(0, Endian.little) != 0x46546C67) {
    throw Exception('Ungültige GLB-Datei.');
  }
  final jsonLength = header.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  final binHeaderOffset = 20 + _pad4(jsonLength);
  var bin = Uint8List(0);
  if (binHeaderOffset + 8 <= glb.length &&
      header.getUint32(binHeaderOffset + 4, Endian.little) == 0x004E4942) {
    final binLength = header.getUint32(binHeaderOffset, Endian.little);
    bin = glb.sublist(binHeaderOffset + 8, binHeaderOffset + 8 + binLength);
  }

  final rawNodes = json['nodes'] as List? ?? [];
  List<double> restRotation(int node) {
    final rotation = (rawNodes[node] as Map)['rotation'] as List?;
    return rotation == null
        ? [0.0, 0.0, 0.0, 1.0]
        : [for (final x in rotation) (x as num).toDouble()];
  }

  final bufferViews =
      ((json['bufferViews'] as List?) ?? []).cast<dynamic>().toList();
  final accessors =
      ((json['accessors'] as List?) ?? []).cast<dynamic>().toList();
  final animations =
      ((json['animations'] as List?) ?? []).cast<dynamic>().toList();

  final appendParts = <Uint8List>[];
  final appendOffsets = <int>[];
  var appendCursor = _pad4(bin.length);
  int addBufferView(Uint8List part) {
    appendOffsets.add(appendCursor);
    appendParts.add(part);
    bufferViews.add({
      'buffer': 0,
      'byteOffset': appendCursor,
      'byteLength': part.length,
    });
    appendCursor = _pad4(appendCursor + part.length);
    return bufferViews.length - 1;
  }

  for (final clip in clips) {
    final period = clip.period;
    final steps = (period * fps).round().clamp(4, 240);
    final times = Float32List(steps + 1);
    for (var k = 0; k <= steps; k++) {
      times[k] = k * period / steps;
    }
    final timesView =
        addBufferView(times.buffer.asUint8List(0, times.lengthInBytes));
    accessors.add({
      'bufferView': timesView,
      'componentType': 5126,
      'count': times.length,
      'type': 'SCALAR',
      'min': [0.0],
      'max': [period],
    });
    final timesAccessor = accessors.length - 1;

    // Betroffene Knoten – die Pose-Funktion liefert bei jedem Aufruf
    // dieselbe Knotenmenge.
    final nodes = clip.poseAt(0).keys.toList()..sort();
    final samplers = <Map<String, dynamic>>[];
    final channels = <Map<String, dynamic>>[];
    final perNode = {
      for (final node in nodes) node: Float32List((steps + 1) * 4),
    };
    for (var k = 0; k <= steps; k++) {
      final pose = clip.poseAt(times[k]);
      for (final node in nodes) {
        final override = pose[node];
        final rest = restRotation(node);
        final local = override == null ? rest : _quatMul(rest, override);
        final out = perNode[node]!;
        for (var c = 0; c < 4; c++) {
          out[k * 4 + c] = local[c];
        }
      }
    }
    for (final node in nodes) {
      final values = perNode[node]!;
      final view =
          addBufferView(values.buffer.asUint8List(0, values.lengthInBytes));
      accessors.add({
        'bufferView': view,
        'componentType': 5126,
        'count': steps + 1,
        'type': 'VEC4',
      });
      samplers.add({
        'input': timesAccessor,
        'output': accessors.length - 1,
        'interpolation': 'LINEAR',
      });
      channels.add({
        'sampler': samplers.length - 1,
        'target': {'node': node, 'path': 'rotation'},
      });
    }
    animations.add({
      'name': '${clip.name} (Test)',
      'samplers': samplers,
      'channels': channels,
    });
  }

  json['bufferViews'] = bufferViews;
  json['accessors'] = accessors;
  json['animations'] = animations;

  final newBinLength = appendCursor;
  final newBin = Uint8List(newBinLength);
  newBin.setRange(0, bin.length, bin);
  for (var i = 0; i < appendParts.length; i++) {
    newBin.setRange(appendOffsets[i],
        appendOffsets[i] + appendParts[i].length, appendParts[i]);
  }
  (json['buffers'] as List)[0]['byteLength'] = newBinLength;

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
