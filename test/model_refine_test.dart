import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/model_refine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ein Prisma mit 16 Seitenflächen, jede mit eigener Atlas-Kachel.
///
/// Fläche 0 steht frontal zur Kamera (Blickrichtung −Z), jede weitere
/// ist um 22,5° gedreht: Fläche 1 steht bei 22,5°, Fläche 2 bei 45°,
/// Fläche 3 bei 67,5°, Fläche 4 parallel zum Blick. Damit lässt sich
/// ablesen, **bis zu welchem Winkel** die Textur-Stufe das
/// Ausgangsbild aufprojiziert – jede Fläche schreibt in ihre eigene
/// Kachel, also verrät die Kachelfarbe, wer etwas abbekommen hat.
Uint8List _prisma(Uint8List textur) {
  const n = 16;
  final m = LocalMesh();
  for (var i = 0; i < n; i++) {
    final a = (i - 0.5) * 2 * math.pi / n;
    final b = (i + 0.5) * 2 * math.pi / n;
    // Kachel i im 4×4-Raster, mit Rand gegen das Ausbluten.
    final kx = (i % 4) * 0.25, ky = (i ~/ 4) * 0.25;
    const rand = 0.03;
    final u0 = kx + rand, u1 = kx + 0.25 - rand;
    final v0 = ky + rand, v1 = ky + 0.25 - rand;
    double px(double t) => math.sin(t);
    double pz(double t) => -math.cos(t);
    final p0 = m.addVertex(px(a), -1, pz(a), u0, v1);
    final p1 = m.addVertex(px(b), -1, pz(b), u1, v1);
    final p2 = m.addVertex(px(b), 1, pz(b), u1, v0);
    final p3 = m.addVertex(px(a), 1, pz(a), u0, v0);
    m.addQuad(p3, p2, p1, p0);
  }
  return buildGlb(m, pngTexture: textur);
}

Future<Uint8List> _einfarbig(int w, int h, ui.Color farbe) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = farbe);
  final bild = await recorder.endRecording().toImage(w, h);
  final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();
  return daten!.buffer.asUint8List();
}

/// Der Blau-Anteil in der Mitte der Kachel [i].
Future<int> _blauInKachel(Uint8List glb, int i) async {
  final mesh = await parseGlbForPreview(glb);
  try {
    final tex = mesh.texture!;
    final daten =
        (await tex.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    final x = (((i % 4) * 0.25 + 0.125) * tex.width).round();
    final y = (((i ~/ 4) * 0.25 + 0.125) * tex.height).round();
    return daten[(y * tex.width + x) * 4 + 2];
  } finally {
    mesh.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Textur aus Originalbild schärfen', () {
    // Vorlage und Ausgangsbild unterscheiden sich nur im Blau-Kanal:
    // Die Kalibrierung findet die Abbildung trotzdem (der Fehler je
    // Stichprobe bleibt weit unter der Schwelle), und hinterher sagt
    // der Blau-Wert einer Kachel, ob ihre Fläche das Bild bekommen
    // hat - 60 heißt unberührt, 120 heißt voll übernommen.
    const grund = ui.Color.fromARGB(255, 200, 60, 60);
    const quelle = ui.Color.fromARGB(255, 200, 60, 120);

    test('nur was frontal steht, bekommt das Bild', () async {
      final glb = _prisma(await _einfarbig(128, 128, grund));
      final neu = await reprojectSourceImageTexture(
          glb, await _einfarbig(256, 256, quelle));
      expect(neu, isNotNull,
          reason: 'Die Kalibrierung muss dieses Paar zusammenbringen.');

      // Fläche 0 steht frontal: voll übernommen.
      expect(await _blauInKachel(neu!, 0), greaterThan(110));

      // Fläche 3 steht bei 67,5° - Kosinus 0,38. Hier lag die alte
      // Grenze von 0,25 darunter, und die Fläche bekam einen
      // Bildstreifen über ihre ganze Breite gezogen. Genau das war das
      // verschmierte Gesicht auf der Flanke.
      expect(await _blauInKachel(neu, 3), lessThan(65),
          reason: 'Eine Fläche bei 67,5° darf das Bild nicht mehr '
              'bekommen.');

      // Fläche 4 steht parallel zum Blick: nie.
      expect(await _blauInKachel(neu, 4), lessThan(65));
    });

    test('dazwischen wird eingeblendet, nicht geschaltet', () async {
      // Fläche 2 steht bei 45°, Kosinus 0,707: zwischen 0,55 und 0,90,
      // also anteilig. Ohne diese Rampe entstünde an der Grenze eine
      // sichtbare Kante.
      final glb = _prisma(await _einfarbig(128, 128, grund));
      final neu = await reprojectSourceImageTexture(
          glb, await _einfarbig(256, 256, quelle));
      final teil = await _blauInKachel(neu!, 2);
      expect(teil, greaterThan(65));
      expect(teil, lessThan(110));
    });
  });
}
