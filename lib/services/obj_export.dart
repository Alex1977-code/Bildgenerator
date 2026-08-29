import 'dart:convert';
import 'dart:typed_data';

import 'glb_preview.dart';

/// Wandelt ein GLB-Modell in Wavefront OBJ um.
///
/// Die Vertex-Farben (bzw. die abgetastete Textur) werden als
/// erweiterte OBJ-Vertexfarben mitgeschrieben („v x y z r g b“) –
/// Blender, MeshLab und viele weitere Programme lesen das direkt.
/// Ausrichtung und Maße bleiben wie im GLB (y = oben).
Future<Uint8List> glbToObj(Uint8List glbBytes) async {
  final mesh = await parseGlbForPreview(glbBytes);
  final positions = mesh.positions;
  final indices = mesh.indices;
  if (indices.isEmpty) {
    throw Exception('Das Modell enthält keine Dreiecke.');
  }

  String num6(double v) {
    final s = v.toStringAsFixed(6);
    return s
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  final buffer = StringBuffer()
    ..writeln('# 3DGenerator OBJ-Export')
    ..writeln('# Vertexfarben als Erweiterung: v x y z r g b')
    ..writeln('o Modell');
  final vertexCount = positions.length ~/ 3;
  for (var v = 0; v < vertexCount; v++) {
    final color = mesh.colors[v];
    final r = ((color >> 16) & 0xFF) / 255.0;
    final g = ((color >> 8) & 0xFF) / 255.0;
    final b = (color & 0xFF) / 255.0;
    buffer.writeln('v ${num6(positions[v * 3])} '
        '${num6(positions[v * 3 + 1])} ${num6(positions[v * 3 + 2])} '
        '${num6(r)} ${num6(g)} ${num6(b)}');
  }
  for (var t = 0; t < indices.length; t += 3) {
    buffer.writeln('f ${indices[t] + 1} ${indices[t + 1] + 1} '
        '${indices[t + 2] + 1}');
  }
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}
