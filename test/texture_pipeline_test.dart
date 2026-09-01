import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bildgenerator/services/glb_preview.dart'
    show splitGlb, joinGlb;
import 'package:bildgenerator/services/texture_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ein einfarbiges PNG der gewünschten Kantenlänge.
Future<Uint8List> _png(int size, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = color);
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Ein Dreieck mit frei wählbaren UVs, wahlweise mit zweitem UV-Satz.
Uint8List _glbWithUvs(List<double> uvs, {bool secondSet = false}) {
  final positions = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final uvData = Float32List.fromList(uvs);
  final indices = Uint16List.fromList([0, 1, 2]);
  int pad4(int n) => (n + 3) & ~3;

  final blocks = <Uint8List>[
    positions.buffer.asUint8List(),
    uvData.buffer.asUint8List(),
    if (secondSet) uvData.buffer.asUint8List(),
    indices.buffer.asUint8List(),
  ];
  final views = <Map<String, dynamic>>[];
  var offset = 0;
  final bin = Uint8List(
      blocks.fold<int>(0, (sum, b) => sum + pad4(b.length)));
  for (final block in blocks) {
    bin.setRange(offset, offset + block.length, block);
    views.add({'buffer': 0, 'byteOffset': offset, 'byteLength': block.length});
    offset += pad4(block.length);
  }

  final attribute = <String, dynamic>{'POSITION': 0, 'TEXCOORD_0': 1};
  if (secondSet) attribute['TEXCOORD_1'] = 2;

  final json = <String, dynamic>{
    'asset': {'version': '2.0'},
    'buffers': [
      {'byteLength': bin.length}
    ],
    'bufferViews': views,
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [0.0, 0.0, 0.0],
        'max': [1.0, 1.0, 0.0],
      },
      {
        'bufferView': 1,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC2',
      },
      if (secondSet)
        {
          'bufferView': 2,
          'componentType': 5126,
          'count': 3,
          'type': 'VEC2',
        },
      {
        'bufferView': secondSet ? 3 : 2,
        'componentType': 5123,
        'count': 3,
        'type': 'SCALAR',
      },
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': attribute,
            'indices': secondSet ? 3 : 2,
            'mode': 4,
          }
        ]
      }
    ],
    'nodes': [
      {'mesh': 0}
    ],
    'scenes': [
      {'nodes': [0]}
    ],
    'scene': 0,
  };
  return joinGlb(json, bin);
}

/// Liest die UVs des ersten Teilnetzes zurück.
List<double> _readUvs(Uint8List glb) {
  final parts = splitGlb(glb);
  final prim = ((parts.json['meshes'] as List)[0] as Map)['primitives'][0]
      as Map;
  final index = (prim['attributes'] as Map)['TEXCOORD_0'] as int;
  final accessor = (parts.json['accessors'] as List)[index] as Map;
  final view = (parts.json['bufferViews'] as List)
      [accessor['bufferView'] as int] as Map;
  final start = (view['byteOffset'] as int? ?? 0);
  final data = ByteData.sublistView(parts.bin);
  final count = accessor['count'] as int;
  return [
    for (var i = 0; i < count * 2; i++)
      data.getFloat32(start + i * 4, Endian.little),
  ];
}

/// Zwei Teilnetze mit demselben Material in einem Mesh – so, wie es
/// manche Exporteure abliefern.
Uint8List _glbTwoPrimitives() {
  final a = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);
  final b = Float32List.fromList([2, 0, 0, 3, 0, 0, 2, 1, 0]);
  final indices = Uint16List.fromList([0, 1, 2]);
  int pad4(int n) => (n + 3) & ~3;
  final blocks = [
    a.buffer.asUint8List(),
    b.buffer.asUint8List(),
    indices.buffer.asUint8List(),
  ];
  final views = <Map<String, dynamic>>[];
  var offset = 0;
  final bin =
      Uint8List(blocks.fold<int>(0, (s, x) => s + pad4(x.length)));
  for (final block in blocks) {
    bin.setRange(offset, offset + block.length, block);
    views.add({'buffer': 0, 'byteOffset': offset, 'byteLength': block.length});
    offset += pad4(block.length);
  }
  final json = <String, dynamic>{
    'asset': {'version': '2.0'},
    'buffers': [
      {'byteLength': bin.length}
    ],
    'bufferViews': views,
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [0.0, 0.0, 0.0],
        'max': [1.0, 1.0, 0.0],
      },
      {
        'bufferView': 1,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [2.0, 0.0, 0.0],
        'max': [3.0, 1.0, 0.0],
      },
      {
        'bufferView': 2,
        'componentType': 5123,
        'count': 3,
        'type': 'SCALAR',
      },
    ],
    'materials': [
      {'name': 'einziges'}
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0},
            'indices': 2,
            'material': 0,
            'mode': 4,
          },
          {
            'attributes': {'POSITION': 1},
            'indices': 2,
            'material': 0,
            'mode': 4,
          },
        ]
      }
    ],
    'nodes': [
      {'mesh': 0}
    ],
    'scenes': [
      {'nodes': [0]}
    ],
    'scene': 0,
  };
  return joinGlb(json, bin);
}

void main() {
  group('UV-Sätze', () {
    test('der zweite Satz fliegt raus', () async {
      final glb = _glbWithUvs(
          [0.1, 0.1, 0.9, 0.1, 0.1, 0.9], secondSet: true);
      final result = await runTexturePipeline(glb,
          shrinkTextures: false, uvIntoUnitSquare: false,
          mergePrimitives: false);
      final prim =
          ((splitGlb(result.glb).json['meshes'] as List)[0] as Map)
              ['primitives'][0] as Map;
      expect((prim['attributes'] as Map).containsKey('TEXCOORD_1'), isFalse);
      expect((prim['attributes'] as Map).containsKey('TEXCOORD_0'), isTrue);
      expect(result.report.steps.first.changed, isTrue);
    });

    test('ein einziger Satz bleibt in Ruhe', () async {
      final glb = _glbWithUvs([0.1, 0.1, 0.9, 0.1, 0.1, 0.9]);
      final result = await runTexturePipeline(glb,
          shrinkTextures: false, uvIntoUnitSquare: false,
          mergePrimitives: false);
      expect(result.report.changed, isFalse);
      expect(result.glb.length, glb.length);
    });
  });

  group('UV-Raum', () {
    test('eine ganze Kachel weiter wird zurückgeschoben', () async {
      // u liegt bei 1,3 bis 1,8 – unter der Wiederholung trifft das
      // dieselben Pixel wie 0,3 bis 0,8.
      final glb = _glbWithUvs([1.3, 0.2, 1.8, 0.2, 1.3, 0.7]);
      final result = await runTexturePipeline(glb,
          shrinkTextures: false, singleUvSet: false,
          mergePrimitives: false);
      final uvs = _readUvs(result.glb);
      expect(uvs[0], closeTo(0.3, 1e-5));
      expect(uvs[2], closeTo(0.8, 1e-5));
      expect(uvs[4], closeTo(0.3, 1e-5));
      // v war schon drin und bleibt unverändert.
      expect(uvs[1], closeTo(0.2, 1e-5));
      expect(result.report.text, contains('bildgleich'));
    });

    test('negative UVs kommen ebenfalls zurück', () async {
      final glb = _glbWithUvs([-1.8, 0.2, -1.3, 0.2, -1.8, 0.7]);
      final result = await runTexturePipeline(glb,
          shrinkTextures: false, singleUvSet: false,
          mergePrimitives: false);
      final uvs = _readUvs(result.glb);
      for (var i = 0; i < uvs.length; i += 2) {
        expect(uvs[i], inInclusiveRange(-0.001, 1.001));
      }
      expect(uvs[0], closeTo(0.2, 1e-5));
    });

    test('über eine Kachelgrenze hinweg wird nichts verbogen', () async {
      // 0,9 bis 1,5: Keine ganze Verschiebung bringt das in 0–1, und
      // eine gebrochene würde die Textur verrutschen lassen.
      final glb = _glbWithUvs([0.9, 0.2, 1.5, 0.2, 0.9, 0.7]);
      final vorher = _readUvs(glb);
      final result = await runTexturePipeline(glb,
          shrinkTextures: false, singleUvSet: false,
          mergePrimitives: false);
      expect(_readUvs(result.glb), vorher);
      expect(result.report.text, contains('Kachelgrenze'));
      expect(result.report.text, contains('3D-Programm'));
    });

    test('was schon in 0–1 liegt, wird nicht angefasst', () async {
      final glb = _glbWithUvs([0.1, 0.1, 0.9, 0.1, 0.1, 0.9]);
      final result = await runTexturePipeline(glb,
          shrinkTextures: false, singleUvSet: false,
          mergePrimitives: false);
      expect(result.report.changed, isFalse);
      expect(result.report.text, contains('lagen schon in 0–1'));
    });

    test('min und max des Accessors werden nachgezogen', () async {
      final glb = _glbWithUvs([1.3, 0.2, 1.8, 0.2, 1.3, 0.7]);
      final parts = splitGlb(glb);
      ((parts.json['accessors'] as List)[1] as Map)
        ..['min'] = [1.3, 0.2]
        ..['max'] = [1.8, 0.7];
      final mitGrenzen = joinGlb(parts.json, parts.bin);

      final result = await runTexturePipeline(mitGrenzen,
          shrinkTextures: false, singleUvSet: false,
          mergePrimitives: false);
      final accessor =
          (splitGlb(result.glb).json['accessors'] as List)[1] as Map;
      expect((accessor['min'] as List)[0], closeTo(0.3, 1e-5));
      expect((accessor['max'] as List)[0], closeTo(0.8, 1e-5));
    });
  });

  group('Material je Mesh', () {
    test('Teilnetze mit gleichem Material werden zusammengelegt',
        () async {
      final result = await runTexturePipeline(_glbTwoPrimitives(),
          shrinkTextures: false, singleUvSet: false,
          uvIntoUnitSquare: false);
      final json = splitGlb(result.glb).json;
      final primitives =
          ((json['meshes'] as List)[0] as Map)['primitives'] as List;
      expect(primitives.length, 1);
      final prim = primitives.first as Map;
      // Sechs Punkte und zwei Dreiecke – nichts ist verlorengegangen.
      final positionAccessor = (json['accessors'] as List)
          [(prim['attributes'] as Map)['POSITION'] as int] as Map;
      expect(positionAccessor['count'], 6);
      final indexAccessor =
          (json['accessors'] as List)[prim['indices'] as int] as Map;
      expect(indexAccessor['count'], 6);
      expect(prim['material'], 0);
      expect(result.report.text, contains('zusammengelegt'));
    });

    test('die verschobenen Indizes zeigen auf das zweite Dreieck',
        () async {
      final result = await runTexturePipeline(_glbTwoPrimitives(),
          shrinkTextures: false, singleUvSet: false,
          uvIntoUnitSquare: false);
      final parts = splitGlb(result.glb);
      final prim = ((parts.json['meshes'] as List)[0] as Map)
          ['primitives'][0] as Map;
      final accessor = (parts.json['accessors'] as List)
          [prim['indices'] as int] as Map;
      final view = (parts.json['bufferViews'] as List)
          [accessor['bufferView'] as int] as Map;
      final data = ByteData.sublistView(parts.bin);
      final start = view['byteOffset'] as int;
      final indizes = [
        for (var i = 0; i < 6; i++)
          data.getUint16(start + i * 2, Endian.little),
      ];
      expect(indizes, [0, 1, 2, 3, 4, 5]);
    });

    test('verschiedene Materialien bleiben stehen, mit Begründung',
        () async {
      final parts = splitGlb(_glbTwoPrimitives());
      (parts.json['materials'] as List).add({'name': 'zweites'});
      (((parts.json['meshes'] as List)[0] as Map)['primitives'][1]
          as Map)['material'] = 1;
      final glb = joinGlb(parts.json, parts.bin);

      final result = await runTexturePipeline(glb,
          shrinkTextures: false, singleUvSet: false,
          uvIntoUnitSquare: false);
      final primitives =
          ((splitGlb(result.glb).json['meshes'] as List)[0] as Map)
              ['primitives'] as List;
      expect(primitives.length, 2);
      expect(result.report.text, contains('Textur-Atlas'));
    });
  });

  group('Hautton', () {
    /// Eine GLB mit genau einer eingebetteten Textur.
    Uint8List glbWithTexture(Uint8List png) {
      int pad4(int n) => (n + 3) & ~3;
      final bin = Uint8List(pad4(png.length))..setRange(0, png.length, png);
      final json = <String, dynamic>{
        'asset': {'version': '2.0'},
        'buffers': [
          {'byteLength': bin.length}
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': png.length}
        ],
        'images': [
          {'bufferView': 0, 'mimeType': 'image/png'}
        ],
        'textures': [
          {'source': 0}
        ],
        'materials': [
          {
            'pbrMetallicRoughness': {
              'baseColorTexture': {'index': 0},
              'baseColorFactor': [0.6, 0.4, 0.3, 1.0],
            }
          }
        ],
        'meshes': [],
        'nodes': [],
        'scenes': [
          {'nodes': <int>[]}
        ],
        'scene': 0,
      };
      return joinGlb(json, bin);
    }

    test('die Textur wird neutral und der Farbfaktor weiß', () async {
      final glb = glbWithTexture(await _png(32, const ui.Color(0xFF7A4B2A)));
      final result = await makeSkinToneReady(glb);
      expect(result.changed, isTrue);

      final parts = splitGlb(result.glb);
      final pbr = ((parts.json['materials'] as List)[0]
          as Map)['pbrMetallicRoughness'] as Map;
      expect(pbr['baseColorFactor'], [1.0, 1.0, 1.0, 1.0]);

      // Das neue Bild muss grau sein: R = G = B.
      final view = (parts.json['bufferViews'] as List)[0] as Map;
      final bytes = Uint8List.sublistView(parts.bin,
          view['byteOffset'] as int,
          (view['byteOffset'] as int) + (view['byteLength'] as int));
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final data = await frame.image
          .toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      final pixel = data!.buffer.asUint8List();
      expect(pixel[0], pixel[1]);
      expect(pixel[1], pixel[2]);
      // Und deutlich aufgehellt, damit der Hautton darauf wirken kann.
      expect(pixel[0], greaterThan(150));
    });

    test('ohne Textur wird nichts behauptet', () async {
      final glb = _glbWithUvs([0.1, 0.1, 0.9, 0.1, 0.1, 0.9]);
      final result = await makeSkinToneReady(glb);
      expect(result.changed, isFalse);
      expect(result.detail, contains('keine eingebettete Textur'));
      expect(result.glb, glb);
    });
  });

  test('der Bericht nennt jeden Schritt', () async {
    final result = await runTexturePipeline(
        _glbWithUvs([0.1, 0.1, 0.9, 0.1, 0.1, 0.9]));
    expect(result.report.steps.length, 4);
    expect(result.report.text, contains('Textur-Pipeline'));
    expect(result.report.text, contains('Dateigröße'));
    expect(jsonEncode(result.report.steps.map((s) => s.title).toList()),
        contains('UV-Raum'));
  });
}
