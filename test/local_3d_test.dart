import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';

RgbaImage _testImage() {
  // 8×8: linke Hälfte deckend hell, rechte Hälfte transparent.
  const w = 8, h = 8;
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      if (x < w ~/ 2) {
        bytes[o] = 200;
        bytes[o + 1] = 180;
        bytes[o + 2] = 160;
        bytes[o + 3] = 255;
      }
    }
  }
  return RgbaImage(bytes, w, h);
}

RgbaImage _solidImage() {
  const w = 8, h = 8;
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = 120;
    bytes[i + 1] = 90;
    bytes[i + 2] = 60;
    bytes[i + 3] = 255;
  }
  return RgbaImage(bytes, w, h);
}

Map<String, dynamic> _readGlbJson(Uint8List glb) {
  final data = ByteData.sublistView(glb);
  expect(data.getUint32(0, Endian.little), 0x46546C67,
      reason: 'GLB-Magic fehlt');
  expect(data.getUint32(4, Endian.little), 2, reason: 'glTF-Version');
  expect(data.getUint32(8, Endian.little), glb.length,
      reason: 'Gesamtlänge stimmt nicht');
  final jsonLength = data.getUint32(12, Endian.little);
  expect(data.getUint32(16, Endian.little), 0x4E4F534A,
      reason: 'JSON-Chunk-Typ');
  final jsonString = utf8.decode(glb.sublist(20, 20 + jsonLength));
  final binOffset = 20 + jsonLength;
  final binLength = data.getUint32(binOffset, Endian.little);
  expect(data.getUint32(binOffset + 4, Endian.little), 0x004E4942,
      reason: 'BIN-Chunk-Typ');
  expect(binOffset + 8 + binLength, glb.length);
  return jsonDecode(jsonString) as Map<String, dynamic>;
}

void main() {
  final fakePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  test('Relief-Mesh erzeugt gültiges GLB', () {
    final mesh = buildReliefMesh(_testImage(),
        resolution: 16, depth: 0.2, invert: false);
    expect(mesh.indices.length % 3, 0);
    expect(mesh.positions.length ~/ 3, mesh.uvs.length ~/ 2);

    final glb = buildGlb(mesh, pngTexture: fakePng);
    final json = _readGlbJson(glb);
    final accessors = json['accessors'] as List;
    expect(accessors, hasLength(4));
    expect((accessors[0] as Map)['count'], mesh.positions.length ~/ 3);
    expect((accessors[3] as Map)['count'], mesh.indices.length);
    expect((json['images'] as List), hasLength(1));
  });

  test('Standee-Mesh nutzt nur die deckende Silhouette', () {
    final mesh = buildStandeeMesh(_testImage(), resolution: 16, depth: 0.1);
    expect(mesh.indices, isNotEmpty);
    // Alle Vertices liegen in der linken (deckenden) Bildhälfte.
    for (var i = 0; i < mesh.positions.length; i += 3) {
      expect(mesh.positions[i], lessThanOrEqualTo(0.01));
    }
    final glb = buildGlb(mesh, pngTexture: fakePng, alphaMask: true);
    final json = _readGlbJson(glb);
    expect(((json['materials'] as List).first as Map)['alphaMode'], 'MASK');
  });

  test('Visual Hull erzeugt farbiges 360°-Mesh ohne Textur', () {
    // Rückansicht ist spiegelverkehrt zur Vorderansicht – für das
    // links-halbe Testobjekt also rechts-halb; hier: volle Silhouetten
    // für Seiten/Rücken, Beschnitt kommt aus der Vorderansicht.
    final mesh = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    expect(mesh.indices, isNotEmpty);
    expect(mesh.colors.length, (mesh.positions.length ~/ 3) * 3);

    final glb = buildGlb(mesh);
    final json = _readGlbJson(glb);
    final primitive = (((json['meshes'] as List).first as Map)['primitives']
        as List)[0] as Map;
    expect((primitive['attributes'] as Map).containsKey('COLOR_0'), isTrue);
    expect(json.containsKey('images'), isFalse);
    // Material nutzt baseColorFactor statt Textur.
    final material = (json['materials'] as List).first as Map;
    expect(
        (material['pbrMetallicRoughness'] as Map)
            .containsKey('baseColorTexture'),
        isFalse);
  });

  test('GLB-Vorschau-Parser liest eigenes GLB zurück (Round-Trip)',
      () async {
    final mesh = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 10,
    );
    final glb = buildGlb(mesh);

    final preview = await parseGlbForPreview(glb);
    expect(preview.vertexCount, mesh.positions.length ~/ 3);
    expect(preview.indices.length, mesh.indices.length);
    expect(preview.colors.length, preview.vertexCount);
    expect(preview.extent, greaterThan(0));
    // Vertex-Farben kommen aus COLOR_0, nicht aus dem Grau-Fallback.
    expect(preview.colors.toSet().length, greaterThan(1));
  });
}
