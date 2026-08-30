import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/model_format.dart';

Uint8List bytesOf(String text, {int pad = 64}) {
  final list = <int>[...text.codeUnits];
  while (list.length < pad) {
    list.add(0);
  }
  return Uint8List.fromList(list);
}

void main() {
  group('Dateiart aus dem Inhalt', () {
    test('GLB am glTF-Kopf', () {
      final glb = Uint8List.fromList([
        0x67, 0x6C, 0x54, 0x46, // 'glTF'
        0x02, 0, 0, 0,
        0x40, 0, 0, 0,
      ]);
      expect(detectModelFormat(glb), ModelFormat.glb);
      expect(modelExtension(ModelFormat.glb), '.glb');
      expect(modelIsUsableInApp(ModelFormat.glb), isTrue);
      expect(modelFormatLimitation(ModelFormat.glb), isEmpty);
    });

    test('Binäres FBX am Kaydara-Kopf', () {
      // Genau der Kopf der Datei, die als „modell.glb" ankam und sich
      // weder anzeigen noch prüfen noch riggen ließ.
      final fbx = bytesOf('Kaydara FBX Binary  ');
      expect(detectModelFormat(fbx), ModelFormat.fbxBinary);
      expect(modelExtension(ModelFormat.fbxBinary), '.fbx');
      expect(modelFormatLabel(ModelFormat.fbxBinary), 'FBX');
      // Und die App sagt, was damit nicht geht.
      expect(modelIsUsableInApp(ModelFormat.fbxBinary), isFalse);
      expect(modelFormatLimitation(ModelFormat.fbxBinary),
          contains('FBX'));
      expect(modelFormatLimitation(ModelFormat.fbxBinary),
          contains('Blender'));
    });

    test('glTF als JSON', () {
      final gltf = bytesOf('{"asset":{"version":"2.0"},"meshes":[]}');
      expect(detectModelFormat(gltf), ModelFormat.gltfJson);
    });

    test('OBJ an den ersten Datenzeilen', () {
      final obj = bytesOf('# exportiert\nv 0.0 1.0 2.0\nf 1 2 3\n');
      expect(detectModelFormat(obj), ModelFormat.obj);
    });

    test('ZIP, PLY und STL', () {
      expect(
          detectModelFormat(Uint8List.fromList(
              [0x50, 0x4B, 0x03, 0x04, ...List.filled(20, 0)])),
          ModelFormat.zip);
      expect(detectModelFormat(bytesOf('ply\nformat ascii 1.0\n')),
          ModelFormat.ply);
      expect(detectModelFormat(bytesOf('solid modell\n facet normal')),
          ModelFormat.stl);
    });

    test('Zu kurz oder unbekannt bleibt unbekannt', () {
      expect(detectModelFormat(Uint8List.fromList([1, 2, 3])),
          ModelFormat.unknown);
      expect(detectModelFormat(bytesOf('\x01\x02irgendwas anderes')),
          ModelFormat.unknown);
      expect(modelExtension(ModelFormat.unknown), '.bin');
    });

    test('Jede Art hat Endung, MIME-Typ und Namen', () {
      for (final format in ModelFormat.values) {
        expect(modelExtension(format), startsWith('.'), reason: '$format');
        expect(modelMimeType(format), contains('/'), reason: '$format');
        expect(modelFormatLabel(format), isNotEmpty, reason: '$format');
      }
    });
  });
}
