import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/glb_preview.dart'
    show splitGlb, joinGlb, gltfBufferViewBytes;
import 'package:bildgenerator/services/glb_textures.dart';

/// Ein PNG der gewünschten Kantenlänge – gemalt, nicht mitgeliefert.
Future<Uint8List> makePng(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF3366CC));
  canvas.drawCircle(ui.Offset(size / 2, size / 2), size / 4,
      ui.Paint()..color = const ui.Color(0xFFEE8822));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Eine GLB mit einem Daten-bufferView (steht für Geometrie) und
/// einem Bild-bufferView.
Uint8List buildGlbWithImage(Uint8List png, Uint8List payload) {
  int pad4(int n) => (n + 3) & ~3;
  final bin = Uint8List(pad4(payload.length) + pad4(png.length))
    ..setRange(0, payload.length, payload)
    ..setRange(pad4(payload.length),
        pad4(payload.length) + png.length, png);
  final json = <String, dynamic>{
    'asset': {'version': '2.0'},
    'buffers': [
      {'byteLength': bin.length}
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': payload.length},
      {
        'buffer': 0,
        'byteOffset': pad4(payload.length),
        'byteLength': png.length,
      },
    ],
    'images': [
      {'bufferView': 1, 'mimeType': 'image/png'}
    ],
    'meshes': <dynamic>[],
    'nodes': <dynamic>[],
  };
  return joinGlb(json, bin);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('2048er Textur wird auf 1024 verkleinert', () async {
    final png = await makePng(2048);
    final payload = Uint8List.fromList(List.generate(37, (i) => i));
    final glb = buildGlbWithImage(png, payload);

    final result = await shrinkGlbTextures(glb, maxSize: 1024);
    expect(result.didSomething, isTrue);
    expect(result.changed.single.fromWidth, 2048);
    expect(result.changed.single.toWidth, 1024);
    expect(result.changed.single.toHeight, 1024);
    expect(result.untouched, 0);
    expect(result.external, 0);

    // Das Bild im Ergebnis ist wirklich 1024 groß …
    final parts = splitGlb(result.glb);
    final shrunk = gltfBufferViewBytes(parts.json, parts.bin, 1);
    final codec = await ui.instantiateImageCodec(shrunk);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1024);
    expect(frame.image.height, 1024);
    frame.image.dispose();
    codec.dispose();

    // … und die Nutzdaten daneben sind unangetastet, nur neu
    // einsortiert. Genau das geht schief, wenn man Puffer umbaut.
    final kept = gltfBufferViewBytes(parts.json, parts.bin, 0);
    expect(kept, payload);
    expect((parts.json['buffers'] as List).first['byteLength'],
        parts.bin.length);
  });

  test('Kleine Texturen bleiben unangetastet', () async {
    final png = await makePng(512);
    final glb = buildGlbWithImage(png, Uint8List.fromList([1, 2, 3, 4]));
    final result = await shrinkGlbTextures(glb, maxSize: 1024);
    expect(result.didSomething, isFalse);
    expect(result.untouched, 1);
    // Unverändert heißt: dieselbe Datei, nicht eine neu gepackte.
    expect(identical(result.glb, glb), isTrue);
  });

  test('Ohne Bilder passiert nichts', () async {
    final glb = joinGlb({
      'asset': {'version': '2.0'},
      'meshes': <dynamic>[],
    }, Uint8List(0));
    final result = await shrinkGlbTextures(glb);
    expect(result.didSomething, isFalse);
    expect(result.bytesBefore, result.bytesAfter);
  });

  test('Ein Bild per URI wird als extern gezählt', () async {
    final glb = joinGlb({
      'asset': {'version': '2.0'},
      'buffers': [
        {'byteLength': 4}
      ],
      'bufferViews': [
        {'buffer': 0, 'byteOffset': 0, 'byteLength': 4}
      ],
      'images': [
        {'uri': 'textur.png'}
      ],
    }, Uint8List.fromList([1, 2, 3, 4]));
    final result = await shrinkGlbTextures(glb);
    expect(result.external, 1);
    expect(result.didSomething, isFalse);
  });
}
