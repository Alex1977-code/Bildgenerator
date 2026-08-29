import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/models.dart';

/// Positionen für das Wasserzeichen.
const List<Option> watermarkPositionOptions = [
  ('br', 'Unten rechts'),
  ('bl', 'Unten links'),
  ('tr', 'Oben rechts'),
  ('tl', 'Oben links'),
  ('center', 'Mitte'),
];

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Legt das Logo als Wasserzeichen über das Bild und liefert PNG-Bytes.
///
/// [sizePercent] ist die Logobreite in Prozent der Bildbreite,
/// [opacityPercent] die Deckkraft (10–100).
Future<Uint8List> applyWatermark(
  Uint8List imageBytes,
  Uint8List logoBytes, {
  required String position,
  required int sizePercent,
  required int opacityPercent,
}) async {
  final base = await _decode(imageBytes);
  final logo = await _decode(logoBytes);
  try {
    final width = base.width.toDouble();
    final height = base.height.toDouble();

    final targetWidth = width * sizePercent / 100;
    final targetHeight = logo.height * (targetWidth / logo.width);
    final margin = width * 0.02;

    final (dx, dy) = switch (position) {
      'tl' => (margin, margin),
      'tr' => (width - targetWidth - margin, margin),
      'bl' => (margin, height - targetHeight - margin),
      'center' => ((width - targetWidth) / 2, (height - targetHeight) / 2),
      _ => (width - targetWidth - margin, height - targetHeight - margin),
    };

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(base, ui.Offset.zero, ui.Paint());

    final opacity = (opacityPercent.clamp(1, 100)) / 100;
    canvas.saveLayer(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF).withValues(alpha: opacity),
    );
    canvas.drawImageRect(
      logo,
      ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      ui.Rect.fromLTWH(dx, dy, targetWidth, targetHeight),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final composed = await picture.toImage(base.width, base.height);
    try {
      final data =
          await composed.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw Exception('Wasserzeichen konnte nicht gerendert werden.');
      }
      return data.buffer.asUint8List();
    } finally {
      composed.dispose();
    }
  } finally {
    base.dispose();
    logo.dispose();
  }
}
