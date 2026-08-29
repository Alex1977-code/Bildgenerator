import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart';

/// Wandelt ein GLB-Modell in binäres STL für den 3D-Druck um.
///
/// STL enthält nur die Geometrie (keine Farben/Texturen). Das Modell
/// wird von glTF-Ausrichtung (y = oben) in Druck-Ausrichtung
/// (z = oben) gedreht, auf der Druckplatte zentriert, mit der
/// Unterseite auf z = 0 gesetzt und so skaliert, dass die längste
/// Ausdehnung [targetSizeMm] Millimeter misst.
Future<Uint8List> glbToStl(
  Uint8List glbBytes, {
  double targetSizeMm = 100,
}) async {
  final mesh = await parseGlbForPreview(glbBytes);
  final positions = mesh.positions;
  final indices = mesh.indices;
  final triangleCount = indices.length ~/ 3;
  if (triangleCount == 0) {
    throw Exception('Das Modell enthält keine Dreiecke.');
  }

  // Achsen tauschen (y-oben → z-oben) und Grenzen bestimmen.
  final vertexCount = positions.length ~/ 3;
  final transformed = Float64List(vertexCount * 3);
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (var v = 0; v < vertexCount; v++) {
    final x = positions[v * 3].toDouble();
    final y = -positions[v * 3 + 2].toDouble(); // Tiefe → Druck-y
    final z = positions[v * 3 + 1].toDouble(); // Höhe → Druck-z
    transformed[v * 3] = x;
    transformed[v * 3 + 1] = y;
    transformed[v * 3 + 2] = z;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;
  }
  var extent = maxX - minX;
  if (maxY - minY > extent) extent = maxY - minY;
  if (maxZ - minZ > extent) extent = maxZ - minZ;
  if (extent <= 0) {
    throw Exception('Das Modell hat keine Ausdehnung.');
  }
  final scale = targetSizeMm / extent;
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  for (var v = 0; v < vertexCount; v++) {
    transformed[v * 3] = (transformed[v * 3] - cx) * scale;
    transformed[v * 3 + 1] = (transformed[v * 3 + 1] - cy) * scale;
    transformed[v * 3 + 2] = (transformed[v * 3 + 2] - minZ) * scale;
  }

  // Binäres STL: 80-Byte-Header, Dreieckszahl, je Dreieck Normale +
  // 3 Eckpunkte (float32) + 2 Attribut-Bytes.
  final out = ByteData(84 + triangleCount * 50);
  const header = '3DGenerator binary STL (mm)';
  for (var i = 0; i < header.length && i < 80; i++) {
    out.setUint8(i, header.codeUnitAt(i));
  }
  out.setUint32(80, triangleCount, Endian.little);
  var o = 84;
  void f32(double value) {
    out.setFloat32(o, value, Endian.little);
    o += 4;
  }

  for (var t = 0; t < triangleCount; t++) {
    final a = indices[t * 3] * 3;
    final b = indices[t * 3 + 1] * 3;
    final c = indices[t * 3 + 2] * 3;
    final ux = transformed[b] - transformed[a];
    final uy = transformed[b + 1] - transformed[a + 1];
    final uz = transformed[b + 2] - transformed[a + 2];
    final vx = transformed[c] - transformed[a];
    final vy = transformed[c + 1] - transformed[a + 1];
    final vz = transformed[c + 2] - transformed[a + 2];
    var nx = uy * vz - uz * vy;
    var ny = uz * vx - ux * vz;
    var nz = ux * vy - uy * vx;
    final length = nx * nx + ny * ny + nz * nz;
    if (length > 1e-20) {
      final inv = 1 / math.sqrt(length);
      nx *= inv;
      ny *= inv;
      nz *= inv;
    } else {
      nx = 0;
      ny = 0;
      nz = 0;
    }
    f32(nx);
    f32(ny);
    f32(nz);
    for (final i in [a, b, c]) {
      f32(transformed[i]);
      f32(transformed[i + 1]);
      f32(transformed[i + 2]);
    }
    out.setUint16(o, 0, Endian.little);
    o += 2;
  }
  return out.buffer.asUint8List();
}
