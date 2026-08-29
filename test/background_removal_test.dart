import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/view_generator.dart';

Future<Uint8List> _encodePng(Uint8List rgba, int size) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(buffer,
      width: size, height: size, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final png =
      (await frame.image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
  frame.image.dispose();
  return png;
}

Future<Uint8List> _decodeRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final rgba =
      (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
  frame.image.dispose();
  return rgba;
}

void main() {
  test('Greenscreen-Freistellung: Hintergrund weg, Motiv bleibt', () async {
    const size = 32;
    final rgba = Uint8List(size * size * 4);
    void put(int x, int y, int r, int g, int b) {
      final o = (y * size + x) * 4;
      rgba[o] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = 255;
    }

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        put(x, y, 0, 177, 64); // Greenscreen #00B140
      }
    }
    // Graues Motiv in der Mitte …
    for (var y = 10; y < 22; y++) {
      for (var x = 10; x < 22; x++) {
        put(x, y, 120, 120, 120);
      }
    }
    // … mit einer grünen Fläche IM Motiv (nicht randverbunden).
    put(16, 16, 0, 177, 64);

    final out = await removeGeneratedBackground(
        await _encodePng(rgba, size),
        expectGreenScreen: true);
    final result = await _decodeRgba(out);
    int alpha(int x, int y) => result[(y * size + x) * 4 + 3];
    expect(alpha(0, 0), 0, reason: 'Greenscreen entfernt');
    expect(alpha(31, 31), 0);
    expect(alpha(15, 15), 255, reason: 'Motiv bleibt deckend');
    expect(alpha(16, 16), 255,
        reason: 'grüne Fläche im Motiv bleibt erhalten');
    // Entgrünung am Motivrand: kein Grünstich mehr.
    final edge = (10 * size + 10) * 4;
    expect(result[edge + 1],
        lessThanOrEqualTo(result[edge] > result[edge + 2]
            ? result[edge]
            : result[edge + 2]));
  });

  test('Magenta-Screen: Hintergrund samt Schatten weg, Motiv bleibt',
      () async {
    const size = 32;
    final rgba = Uint8List(size * size * 4);
    void put(int x, int y, int r, int g, int b) {
      final o = (y * size + x) * 4;
      rgba[o] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = 255;
    }

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        put(x, y, 240, 20, 240); // Magenta-Screen
      }
    }
    // Abgedunkelter „Schatten“ auf dem Screen (dunkles Magenta).
    for (var x = 4; x < 28; x++) {
      put(x, 26, 90, 20, 95);
    }
    // GRÜNES Motiv in der Mitte – der Grund für den Magenta-Wechsel.
    for (var y = 10; y < 22; y++) {
      for (var x = 10; x < 22; x++) {
        put(x, y, 40, 160, 60);
      }
    }

    final out = await removeGeneratedBackground(
        await _encodePng(rgba, size),
        expectGreenScreen: true);
    final result = await _decodeRgba(out);
    int alpha(int x, int y) => result[(y * size + x) * 4 + 3];
    expect(alpha(0, 0), 0, reason: 'Magenta-Screen entfernt');
    expect(alpha(10, 26), 0, reason: 'Schatten auf dem Screen entfernt');
    expect(alpha(15, 15), 255, reason: 'grünes Motiv bleibt deckend');
    final o = ((15 * size) + 15) * 4;
    expect(result[o + 1], greaterThan(120),
        reason: 'Grün des Motivs bleibt unangetastet');
  });

  test('Greenscreen-Freistellung: Rückfall auf Flutlauf ohne Grün',
      () async {
    const size = 16;
    final rgba = Uint8List(size * size * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 250;
      rgba[i + 1] = 250;
      rgba[i + 2] = 250;
      rgba[i + 3] = 255;
    }
    for (var y = 5; y < 11; y++) {
      for (var x = 5; x < 11; x++) {
        final o = (y * size + x) * 4;
        rgba[o] = 200;
        rgba[o + 1] = 30;
        rgba[o + 2] = 30;
      }
    }
    final out = await removeGeneratedBackground(
        await _encodePng(rgba, size),
        expectGreenScreen: true);
    final result = await _decodeRgba(out);
    expect(result[3], 0, reason: 'weißer Hintergrund per Flutlauf weg');
    expect(result[((7 * size) + 7) * 4 + 3], 255, reason: 'Motiv bleibt');
  });
}
