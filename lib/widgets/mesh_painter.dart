import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/glb_preview.dart';
import '../services/studio_light.dart';

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
    this.mannequin,
    this.mannequinBottom = 0,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
    this.backgroundBottom,
    this.light = const StudioLight(
        id: 'studio',
        label: 'Studio',
        hint: '',
        x: -0.26,
        y: 0.44,
        z: 0.86),
    this.groundShadow = false,
    this.viewCenter,
    this.viewExtent,
    this.opacity = 1.0,
  });

  final PreviewMesh mesh;
  final Float32List positions;
  final Float32List normals;
  final Float32List? skeleton; // x,y,z je Gelenk (Weltkoordinaten)
  final List<int>? skeletonParents;

  /// Der Größenmaßstab: Strecken zu je sechs Zahlen (x1,y1,z1,x2,y2,z2)
  /// in Studs, Füße bei y = 0.
  ///
  /// Ein Drahtgitter, kein Körper – es soll **hinter** dem Modell
  /// stehen und die Sicht nicht wegnehmen, für die es da ist. Deshalb
  /// wird es vor dem Netz gezeichnet und nicht darüber.
  final Float32List? mannequin;

  /// Auf welcher Höhe die Füße des Modells stehen. Das Mannequin wird
  /// dorthin geschoben, sonst schwebt eines von beiden.
  final double mannequinBottom;
  final double rotX;
  final double rotY;
  final double zoom;

  /// Hintergrundfarbe – null zeichnet keinen, damit sich zwei Netze
  /// übereinanderlegen lassen.
  final Color? background;

  /// Die zweite Farbe des Hintergrunds. Gesetzt entsteht ein
  /// senkrechter Verlauf statt einer gleichmäßigen Fläche: Damit hat
  /// das Bild ein Oben und ein Unten, und das Modell steht in einem
  /// Raum statt vor einer Wand.
  final Color? backgroundBottom;

  /// Woher das Licht kommt. Vorher stand die Richtung fest im Code –
  /// bei der Anprobe ist gerade das Wandern des Lichts die Auskunft:
  /// Streiflicht zeigt, ob ein Teil in der Figur steckt.
  final StudioLight light;

  /// Weiche Ellipse unter dem Modell. Keine Physik, eine Lesehilfe –
  /// ohne sie schwebt alles im Nichts.
  final bool groundShadow;

  /// Mittelpunkt und Ausdehnung, nach denen die Ansicht ausgerichtet
  /// wird. Ohne Angabe die des eigenen Netzes; gesetzt, wenn zwei
  /// Modelle **im selben Maßstab** nebeneinanderstehen sollen – sonst
  /// würde jedes für sich formatfüllend gezeichnet und ein Schwert
  /// sähe so groß aus wie die Figur.
  final List<double>? viewCenter;
  final double? viewExtent;

  /// Deckkraft des ganzen Netzes. Unter 1 wird über eine Ebene
  /// gezeichnet – so lässt sich die Figur durchscheinend zeigen und
  /// der Gegenstand darin erkennen.
  final double opacity;

  static final Float64List _identityMatrix = Float64List.fromList(
      [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = background;
    if (bg != null) {
      final unten = backgroundBottom;
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        unten == null
            ? (Paint()..color = bg)
            : (Paint()
              ..shader = ui.Gradient.linear(
                Offset(0, 0),
                Offset(0, size.height),
                [bg, unten],
              )),
      );
    }
    // Maßstab schon hier, weil der Bodenschatten ihn braucht – und
    // der gehört unter das Modell, aber nicht in die Ebene, mit der
    // die Figur durchscheinend gemacht wird.
    final viewScale = 0.42 *
        math.min(size.width, size.height) /
        (viewExtent ?? mesh.extent) *
        zoom;
    if (groundShadow) {
      final schatten = groundShadowFor(
        width: size.width,
        height: size.height,
        extent: viewExtent ?? mesh.extent,
        scale: viewScale,
        tiltX: rotX,
        zoom: zoom,
      );
      if (!schatten.isEmpty) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(schatten.centerX, schatten.centerY),
            width: schatten.radiusX * 2,
            height: schatten.radiusY * 2,
          ),
          Paint()
            ..color = const Color(0x33000000)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
        );
      }
    }

    final faded = opacity < 0.999;
    if (faded) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
      );
    }

    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final scale = viewScale;
    final cx = size.width / 2, cy = size.height / 2;
    final view = viewCenter ?? mesh.center;
    final centerX = view[0], centerY = view[1], centerZ = view[2];

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

    // Der Größenmaßstab, **vor** dem Netz: Er soll dahinter stehen und
    // die Sicht nicht wegnehmen, für die er da ist.
    final masstab = mannequin;
    if (masstab != null && masstab.length >= 6) {
      final linie = Paint()
        ..color = const Color(0x66607D8B)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i + 5 < masstab.length; i += 6) {
        final (ax, ay, _) = project(masstab[i],
            masstab[i + 1] + mannequinBottom, masstab[i + 2]);
        final (bx, by, _) = project(masstab[i + 3],
            masstab[i + 4] + mannequinBottom, masstab[i + 5]);
        canvas.drawLine(Offset(ax, ay), Offset(bx, by), linie);
      }
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
    // Halbvektor aus Lichtrichtung und Blick (0,0,1).
    final (lx, ly, lz) = light.direction;
    var hx = lx, hy = ly, hz = lz + 1.0;
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
      // Doppelseitig (Betrag): Ein Netz mit uneinheitlicher Wicklung
      // soll nicht halb schwarz sein.
      var dot = (lx * x1 + ly * y2 + lz * z2).abs();
      if (dot > 1) dot = 1;
      final ambient = light.ambient;
      shade[i] = (ambient + (1 - ambient) * dot) * (1 - 0.45 * metallic);
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

    if (faded) canvas.restore();
  }

  @override
  bool shouldRepaint(MeshPainter oldDelegate) =>
      oldDelegate.opacity != opacity ||
      oldDelegate.viewExtent != viewExtent ||
      oldDelegate.mesh != mesh ||
      oldDelegate.positions != positions ||
      oldDelegate.normals != normals ||
      oldDelegate.skeleton != skeleton ||
      oldDelegate.mannequin != mannequin ||
      oldDelegate.mannequinBottom != mannequinBottom ||
      oldDelegate.rotX != rotX ||
      oldDelegate.rotY != rotY ||
      oldDelegate.zoom != zoom ||
      oldDelegate.background != background ||
      oldDelegate.backgroundBottom != backgroundBottom ||
      oldDelegate.light.id != light.id ||
      oldDelegate.groundShadow != groundShadow;
}
