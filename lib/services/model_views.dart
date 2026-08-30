import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/mesh_painter.dart';
import 'glb_preview.dart';

/// Die vier Ansichten, die die Multiview-Pipeline erwartet, mit dem
/// jeweiligen Drehwinkel um die Hochachse.
///
/// Vorn ist 0; danach im Uhrzeigersinn, damit „links" auch die linke
/// Seite der Figur zeigt und nicht deren Spiegelbild.
const Map<String, double> modelViewAngles = {
  'front': 0,
  'left': 1.5707963267948966, // 90°
  'back': 3.141592653589793, // 180°
  'right': 4.71238898038469, // 270°
};

/// Rendert Ansichten eines vorhandenen Modells als PNG.
///
/// Damit lässt sich ein fertiges 3D-Modell als **Vorlage** benutzen:
/// Die Bilder gehen in dieselbe Multiview-Pipeline wie eigene Fotos,
/// und heraus kommt ein neues Modell, das die Grenzen des Ziels
/// einhält – etwa Roblox' 20.000 Dreiecke. Ein vorhandenes Netz
/// direkt zu reduzieren, ohne UV-Nähte und Textur zu zerstören, kann
/// die App nicht; ein neues aus Ansichten bauen zu lassen schon.
///
/// Gezeichnet wird mit demselben [MeshPainter] wie im Viewer – was
/// man dort sieht, geht auch in die Pipeline. Der Hintergrund ist
/// bewusst schlicht: Die 3D-Dienste rechnen ihn weg.
Future<Map<String, Uint8List>> renderGlbViews(
  Uint8List glb, {
  int size = 1024,
  List<String> views = const ['front', 'left', 'back', 'right'],
  Color background = const Color(0xFFF2F2F2),
  double tilt = 0,
}) async {
  final mesh = await parseGlbForPreview(glb);
  try {
    final out = <String, Uint8List>{};
    for (final view in views) {
      final angle = modelViewAngles[view];
      if (angle == null) continue;
      final png = await _renderOne(
        mesh: mesh,
        rotY: angle,
        rotX: tilt,
        size: size,
        background: background,
      );
      if (png != null) out[view] = png;
    }
    return out;
  } finally {
    mesh.dispose();
  }
}

Future<Uint8List?> _renderOne({
  required PreviewMesh mesh,
  required double rotY,
  required double rotX,
  required int size,
  required Color background,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  MeshPainter(
    mesh: mesh,
    positions: mesh.positions,
    normals: mesh.normals,
    skeleton: null,
    skeletonParents: null,
    rotX: rotX,
    rotY: rotY,
    // Etwas Luft am Rand: Die Dienste schneiden selbst zu, ein
    // angeschnittenes Modell lässt sich aber nicht mehr ergänzen.
    zoom: 0.92,
    background: background,
  ).paint(canvas, Size(size.toDouble(), size.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size, size);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
