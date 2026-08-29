import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'glb_preview.dart';

/// Wandelt ein GLB-Modell in 3MF für den Farb-3D-Druck um.
///
/// 3MF ist ein ZIP-Container mit XML-Modell. Die Vertex-Farben (bzw.
/// die abgetastete Textur) werden als Material-Palette gespeichert und
/// jedem Dreieck zugewiesen – das verstehen PrusaSlicer, Bambu Studio,
/// der Windows-3D-Viewer und Druckdienste. Ausrichtung und Skalierung
/// wie beim STL-Export: z = oben, zentriert, Unterseite auf 0, längste
/// Seite = [targetSizeMm] Millimeter (3MF-Einheit ist mm).
Future<Uint8List> glbTo3mf(
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

  // Achsen tauschen (y-oben → z-oben), zentrieren, skalieren.
  final vertexCount = positions.length ~/ 3;
  final transformed = Float64List(vertexCount * 3);
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (var v = 0; v < vertexCount; v++) {
    final x = positions[v * 3].toDouble();
    final y = -positions[v * 3 + 2].toDouble();
    final z = positions[v * 3 + 1].toDouble();
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

  // Farbe je Dreieck (Mittel der Eckfarben), adaptiv auf höchstens
  // 256 Palettenfarben quantisiert.
  final triangleColor = Int32List(triangleCount);
  for (var t = 0; t < triangleCount; t++) {
    var r = 0, g = 0, b = 0;
    for (var k = 0; k < 3; k++) {
      final color = mesh.colors[indices[t * 3 + k]];
      r += (color >> 16) & 0xFF;
      g += (color >> 8) & 0xFF;
      b += color & 0xFF;
    }
    triangleColor[t] = ((r ~/ 3) << 16) | ((g ~/ 3) << 8) | (b ~/ 3);
  }
  Int32List quantized = triangleColor;
  var palette = <int>[];
  for (final bits in [8, 5, 4, 3, 2]) {
    final shift = 8 - bits;
    final mapped = Int32List(triangleCount);
    final seen = <int>{};
    for (var t = 0; t < triangleCount; t++) {
      final c = triangleColor[t];
      // Auf die Bucket-Mitte runden, damit die Farben nicht abdunkeln.
      int q(int channel) {
        final bucket = channel >> shift;
        final center = (bucket << shift) + ((1 << shift) >> 1);
        return shift == 0 ? channel : center.clamp(0, 255);
      }

      mapped[t] = (q((c >> 16) & 0xFF) << 16) |
          (q((c >> 8) & 0xFF) << 8) |
          q(c & 0xFF);
      seen.add(mapped[t]);
    }
    if (seen.length <= 256) {
      quantized = mapped;
      palette = seen.toList()..sort();
      break;
    }
  }
  final paletteIndex = <int, int>{
    for (var i = 0; i < palette.length; i++) palette[i]: i,
  };

  // 3D/3dmodel.model
  String hex(int c) =>
      '#${c.toRadixString(16).padLeft(6, '0').toUpperCase()}FF';
  String num3(double v) {
    final s = v.toStringAsFixed(4);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  final xml = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<model unit="millimeter" xml:lang="und" '
        'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">')
    ..writeln(' <metadata name="Application">3DGenerator</metadata>')
    ..writeln(' <resources>')
    ..writeln('  <basematerials id="1">');
  for (var i = 0; i < palette.length; i++) {
    xml.writeln('   <base name="Farbe ${i + 1}" '
        'displaycolor="${hex(palette[i])}"/>');
  }
  xml
    ..writeln('  </basematerials>')
    ..writeln('  <object id="2" type="model" pid="1" pindex="0">')
    ..writeln('   <mesh>')
    ..writeln('    <vertices>');
  for (var v = 0; v < vertexCount; v++) {
    xml.writeln('     <vertex x="${num3(transformed[v * 3])}" '
        'y="${num3(transformed[v * 3 + 1])}" '
        'z="${num3(transformed[v * 3 + 2])}"/>');
  }
  xml
    ..writeln('    </vertices>')
    ..writeln('    <triangles>');
  for (var t = 0; t < triangleCount; t++) {
    final p = paletteIndex[quantized[t]] ?? 0;
    xml.writeln('     <triangle v1="${indices[t * 3]}" '
        'v2="${indices[t * 3 + 1]}" v3="${indices[t * 3 + 2]}" p1="$p"/>');
  }
  xml
    ..writeln('    </triangles>')
    ..writeln('   </mesh>')
    ..writeln('  </object>')
    ..writeln(' </resources>')
    ..writeln(' <build>')
    ..writeln('  <item objectid="2"/>')
    ..writeln(' </build>')
    ..writeln('</model>');

  const contentTypes = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\n'
      ' <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\n'
      ' <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>\n'
      '</Types>\n';
  const rels = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n'
      ' <Relationship Target="/3D/3dmodel.model" Id="rel-1" '
      'Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>\n'
      '</Relationships>\n';

  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rels);
  add('3D/3dmodel.model', xml.toString());
  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}
