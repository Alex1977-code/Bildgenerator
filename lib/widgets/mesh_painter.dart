import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/glb_preview.dart';

/// Zeichnet ein Netz mit Textur, weicher Beleuchtung und optionalem
/// Skelett.
///
/// Lag vorher als privater Painter im Viewer. Herausgezogen, damit
/// dieselbe Darstellung auch **ohne Bildschirm** verwendet werden kann:
/// [renderGlbViews] rendert damit Ansichten eines geladenen Modells,
/// aus denen sich ein neues, regelkonformes Modell bauen lässt.
class MeshPainter extends CustomPainter {
  MeshPainter({
    required this.mesh,
    required this.positions,
    required this.normals,
    required this.skeleton,
    required this.skeletonParents,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
  });

  final PreviewMesh mesh;
  final Float32List positions;
  final Float32List normals;
  final Float32List? skeleton; // x,y,z je Gelenk (Weltkoordinaten)
  final List<int>? skeletonParents;
  final double rotX;
  final double rotY;
  final double zoom;
  final Color background;

  static final Float64List _identityMatrix = Float64List.fromList(
      [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final scale = 0.42 * math.min(size.width, size.height) /
        mesh.extent *
        zoom;
    final cx = size.width / 2, cy = size.height / 2;
    final centerX = mesh.center[0],
        centerY = mesh.center[1],
        centerZ = mesh.center[2];

    (double, double, double) project(double x0, double y0, double z0) {
      final x = x0 - centerX;
      final y = y0 - centerY;
      final z = z0 - centerZ;
      // Erst um Y, dann um X drehen.
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      final y2 = y * cosX - z1 * sinX;
      final z2 = y * sinX + z1 * cosX;
      return (cx + x1 * scale, cy - y2 * scale, z2);
    }

    final vertexCount = positions.length ~/ 3;
    final sx = Float32List(vertexCount);
    final sy = Float32List(vertexCount);
    final sz = Float32List(vertexCount);
    for (var i = 0; i < vertexCount; i++) {
      final (px, py, pz) = project(positions[i * 3], positions[i * 3 + 1],
          positions[i * 3 + 2]);
      sx[i] = px;
      sy[i] = py;
      sz[i] = pz;
    }

    // Maler-Algorithmus: entfernte Dreiecke zuerst.
    final indices = mesh.indices;
    final triangleCount = indices.length ~/ 3;
    final order = List<int>.generate(triangleCount, (i) => i);
    final depth = Float32List(triangleCount);
    for (var t = 0; t < triangleCount; t++) {
      depth[t] = sz[indices[t * 3]] +
          sz[indices[t * 3 + 1]] +
          sz[indices[t * 3 + 2]];
    }
    order.sort((a, b) => depth[a].compareTo(depth[b]));

    // Weiche per-Vertex-Beleuchtung aus den mitgedrehten Normalen
    // (Gouraud-Shading statt facettiertem Flat-Shading) – plus
    // PBR-Glanzlichter nach Metall/Rauheit des Materials: Metalle
    // streuen weniger diffus und bekommen einen additiven
    // Spekular-Pass (Blinn-Phong-Näherung).
    final metallic = mesh.metallic;
    final gloss = (1 - mesh.roughness).clamp(0.0, 1.0);
    final shininess = 4 + gloss * gloss * 96;
    final specStrength =
        (0.25 + 0.75 * metallic) * math.pow(gloss, 1.5).toDouble();
    // Halbvektor aus Lichtrichtung (-0.26, 0.44, 0.86) und Blick (0,0,1).
    var hx = -0.26, hy = 0.44, hz = 1.86;
    final hLen = math.sqrt(hx * hx + hy * hy + hz * hz);
    hx /= hLen;
    hy /= hLen;
    hz /= hLen;
    final shade = Float32List(vertexCount);
    final spec = specStrength > 0.01 ? Float32List(vertexCount) : null;
    for (var i = 0; i < vertexCount; i++) {
      final nx = normals[i * 3],
          ny = normals[i * 3 + 1],
          nz = normals[i * 3 + 2];
      final x1 = nx * cosY + nz * sinY;
      final z1 = -nx * sinY + nz * cosY;
      final y2 = ny * cosX - z1 * sinX;
      final z2 = ny * sinX + z1 * cosX;
      // Licht schräg von oben vorn; doppelseitig (Betrag).
      var dot = (-0.26 * x1 + 0.44 * y2 + 0.86 * z2).abs();
      if (dot > 1) dot = 1;
      shade[i] = (0.42 + 0.58 * dot) * (1 - 0.45 * metallic);
      if (spec != null) {
        var hDot = (hx * x1 + hy * y2 + hz * z2).abs();
        if (hDot > 1) hDot = 1;
        spec[i] = specStrength * math.pow(hDot, shininess).toDouble();
      }
    }

    final texture = mesh.texture;
    final uvs = mesh.uvs;
    final textured = texture != null && uvs != null;
    final outPositions = Float32List(triangleCount * 6);
    final outColors = Int32List(triangleCount * 3);
    final outTex = textured ? Float32List(triangleCount * 6) : null;
    final specColors = spec != null ? Int32List(triangleCount * 3) : null;
    var p = 0, c = 0, texOut = 0, scOut = 0;
    for (final t in order) {
      final ia = indices[t * 3],
          ib = indices[t * 3 + 1],
          ic = indices[t * 3 + 2];
      for (final vi in [ia, ib, ic]) {
        outPositions[p++] = sx[vi];
        outPositions[p++] = sy[vi];
        final s = shade[vi];
        if (specColors != null) {
          // Glanzlicht-Farbe: weiß für Nichtmetalle, bei Metallen zur
          // Grundfarbe hin getönt.
          final sv = spec![vi];
          final base = mesh.colors[vi];
          final br = 255 + (((base >> 16) & 0xFF) - 255) * metallic;
          final bg = 255 + (((base >> 8) & 0xFF) - 255) * metallic;
          final bb = 255 + ((base & 0xFF) - 255) * metallic;
          specColors[scOut++] = 0xFF000000 |
              ((sv * br).round().clamp(0, 255) << 16) |
              ((sv * bg).round().clamp(0, 255) << 8) |
              (sv * bb).round().clamp(0, 255);
        }
        if (textured) {
          // wrapUv erhält Werte in [0,1] – insbesondere darf u = 1,0
          // nicht auf 0,0 springen (Schmier-Streifen quer über die
          // Textur bei Dreiecken am Texturrand).
          outTex![texOut++] = wrapUv(uvs[vi * 2]) * texture.width;
          outTex[texOut++] = wrapUv(uvs[vi * 2 + 1]) * texture.height;
          final grey = (s * 255).round().clamp(0, 255);
          outColors[c++] =
              0xFF000000 | (grey << 16) | (grey << 8) | grey;
        } else {
          final color = mesh.colors[vi];
          final r = ((color >> 16) & 0xFF) * s;
          final g = ((color >> 8) & 0xFF) * s;
          final b = (color & 0xFF) * s;
          outColors[c++] = 0xFF000000 |
              (r.round().clamp(0, 255) << 16) |
              (g.round().clamp(0, 255) << 8) |
              b.round().clamp(0, 255);
        }
      }
    }

    if (textured) {
      // Echtes Textur-Mapping: Texturkoordinaten je Vertex, Helligkeit
      // über die Vertex-Farben (modulate) – volle Texturschärfe.
      final paint = Paint()
        ..shader = ui.ImageShader(texture, ui.TileMode.clamp,
            ui.TileMode.clamp, _identityMatrix);
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
            textureCoordinates: outTex, colors: outColors),
        BlendMode.modulate,
        paint,
      );
    } else {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
            colors: outColors),
        BlendMode.dst,
        Paint(),
      );
    }

    // Additiver Glanzlicht-Pass (PBR): hellt dort auf, wo die
    // Oberfläche das Licht zur Kamera spiegelt – sichtbar bei
    // glänzenden und metallischen Materialien.
    if (specColors != null) {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
            colors: specColors),
        BlendMode.dst,
        Paint()..blendMode = BlendMode.plus,
      );
    }

    // Skelett-Overlay: Knochenlinien und Gelenkpunkte über dem Modell.
    final joints = skeleton;
    final parents = skeletonParents;
    if (joints != null && parents != null) {
      final jointCount = joints.length ~/ 3;
      final jx = Float32List(jointCount);
      final jy = Float32List(jointCount);
      for (var j = 0; j < jointCount; j++) {
        final (px, py, _) = project(
            joints[j * 3], joints[j * 3 + 1], joints[j * 3 + 2]);
        jx[j] = px;
        jy[j] = py;
      }
      final bonePaint = Paint()
        ..color = const Color(0xFFFFB300)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (var j = 0; j < jointCount; j++) {
        final parent = parents[j];
        if (parent < 0) continue;
        canvas.drawLine(Offset(jx[parent], jy[parent]),
            Offset(jx[j], jy[j]), bonePaint);
      }
      final jointPaint = Paint()..color = const Color(0xFFE65100);
      final jointBorder = Paint()..color = const Color(0xFFFFFFFF);
      for (var j = 0; j < jointCount; j++) {
        canvas.drawCircle(Offset(jx[j], jy[j]), 4.5, jointBorder);
        canvas.drawCircle(Offset(jx[j], jy[j]), 3.2, jointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(MeshPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.positions != positions ||
      oldDelegate.normals != normals ||
      oldDelegate.skeleton != skeleton ||
      oldDelegate.rotX != rotX ||
      oldDelegate.rotY != rotY ||
      oldDelegate.zoom != zoom ||
      oldDelegate.background != background;
}
