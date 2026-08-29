import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/view_generator.dart';

/// Baut ein PNG aus rohen RGBA-Daten (über die Engine-Codecs).
Future<Uint8List> _encodePng(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  return png!.buffer.asUint8List();
}

Future<Uint8List> _decodeRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final raw = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  return raw!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensureTransparentBackground stellt weißen Hintergrund frei',
      () async {
    // 16×16 weiß mit rotem 6×6-Quadrat in der Mitte.
    const w = 16, h = 16;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        final inSquare = x >= 5 && x < 11 && y >= 5 && y < 11;
        rgba[o] = inSquare ? 200 : 255;
        rgba[o + 1] = inSquare ? 30 : 255;
        rgba[o + 2] = inSquare ? 30 : 255;
        rgba[o + 3] = 255;
      }
    }
    final png = await _encodePng(rgba, w, h);

    final result = await ensureTransparentBackground(png);
    final out = await _decodeRgba(result);

    // Ecken (Hintergrund) sind transparent, Motivmitte bleibt deckend.
    expect(out[3], 0, reason: 'Ecke oben links transparent');
    expect(out[((h - 1) * w + (w - 1)) * 4 + 3], 0,
        reason: 'Ecke unten rechts transparent');
    expect(out[(8 * w + 8) * 4 + 3], 255, reason: 'Motiv bleibt deckend');
  });

  test('ensureTransparentBackground lässt Alpha-Bilder unverändert',
      () async {
    const w = 8, h = 8;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        rgba[o] = 10;
        rgba[o + 1] = 200;
        rgba[o + 2] = 10;
        rgba[o + 3] = x < w ~/ 2 ? 255 : 0; // hat bereits Transparenz
      }
    }
    final png = await _encodePng(rgba, w, h);

    final result = await ensureTransparentBackground(png);
    expect(result, same(png), reason: 'Bild mit Alpha bleibt unangetastet');
  });
}
