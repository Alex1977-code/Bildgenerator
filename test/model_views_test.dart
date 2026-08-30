import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/model_views.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Ein Würfel als Prüfmodell – klein, aber mit echter Geometrie.
  Uint8List cubeGlb() {
    final mesh = LocalMesh();
    const s = 0.5;
    final corners = [
      [-s, -s, -s], [s, -s, -s], [s, s, -s], [-s, s, -s],
      [-s, -s, s], [s, -s, s], [s, s, s], [-s, s, s],
    ];
    for (final c in corners) {
      mesh.addVertex(c[0], c[1], c[2], 0, 0, r: 0.8, g: 0.4, b: 0.2);
    }
    const faces = [
      [0, 1, 2], [0, 2, 3], [5, 4, 7], [5, 7, 6],
      [4, 0, 3], [4, 3, 7], [1, 5, 6], [1, 6, 2],
      [3, 2, 6], [3, 6, 7], [4, 5, 1], [4, 1, 0],
    ];
    for (final f in faces) {
      mesh.addTriangle(f[0], f[1], f[2]);
    }
    return buildGlb(mesh);
  }

  test('Aus einem Modell werden vier Ansichten', () async {
    final views = await renderGlbViews(cubeGlb(), size: 128);
    expect(views.keys.toSet(), {'front', 'left', 'back', 'right'});
    for (final entry in views.entries) {
      // Jede Ansicht ist ein lesbares PNG der gewünschten Größe.
      final codec = await ui.instantiateImageCodec(entry.value);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 128, reason: entry.key);
      expect(frame.image.height, 128, reason: entry.key);
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('Die Ansicht zeigt wirklich das Modell, nicht nur Hintergrund',
      () async {
    final views = await renderGlbViews(cubeGlb(), size: 64);
    final codec = await ui.instantiateImageCodec(views['front']!);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    final pixels = data!.buffer.asUint8List();
    // Ein leeres Bild hätte überall dieselbe Farbe.
    final colors = <int>{};
    for (var i = 0; i < pixels.length; i += 4) {
      colors.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
    }
    expect(colors.length, greaterThan(2));
  });

  test('Eine einzelne Ansicht lässt sich anfordern', () async {
    final views =
        await renderGlbViews(cubeGlb(), size: 64, views: const ['front']);
    expect(views.keys.toList(), ['front']);
  });

  test('Die Winkel decken den vollen Umlauf ab', () {
    expect(modelViewAngles.length, 4);
    expect(modelViewAngles['front'], 0);
    // Links, hinten, rechts liegen auf 90, 180 und 270 Grad.
    expect(modelViewAngles['back']! / modelViewAngles['left']!, 2);
    expect(modelViewAngles['right']! / modelViewAngles['left']!, 3);
  });
}
