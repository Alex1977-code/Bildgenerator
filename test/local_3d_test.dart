import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/animation_bake.dart';
import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/preview_animations.dart';
import 'package:bildgenerator/services/stl_export.dart';
import 'package:bildgenerator/services/threemf_export.dart';
import 'package:archive/archive.dart';

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

/// Vertikaler Verlauf: hell oben, dunkel unten (als Tiefenkarte: oben
/// nah, unten fern).
RgbaImage _verticalGradientImage() {
  const w = 8, h = 8;
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final value = (255 * (1 - y / (h - 1))).round();
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      bytes[o] = value;
      bytes[o + 1] = value;
      bytes[o + 2] = value;
      bytes[o + 3] = 255;
    }
  }
  return RgbaImage(bytes, w, h);
}

/// Horizontaler Verlauf: dunkel links, hell rechts.
RgbaImage _horizontalGradientImage() {
  const w = 8, h = 8;
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final value = (255 * x / (w - 1)).round();
      final o = (y * w + x) * 4;
      bytes[o] = value;
      bytes[o + 1] = value;
      bytes[o + 2] = value;
      bytes[o + 3] = 255;
    }
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

  test('KI-Tiefenkarte formt die Vorderseite des Visual Hull', () {
    double maxZWhere(LocalMesh mesh, bool Function(double y) rowFilter) {
      var maxZ = double.negativeInfinity;
      for (var i = 0; i < mesh.positions.length; i += 3) {
        if (rowFilter(mesh.positions[i + 1]) &&
            mesh.positions[i + 2] > maxZ) {
          maxZ = mesh.positions[i + 2];
        }
      }
      return maxZ;
    }

    final noDepth = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final withDepth = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      frontDepth: _verticalGradientImage(),
      resolution: 12,
    );
    // Ohne Tiefenkarte liegt die Front oben wie unten gleich weit vorn …
    expect(maxZWhere(noDepth, (y) => y < -0.15),
        closeTo(maxZWhere(noDepth, (y) => y > 0.15), 0.06));
    // … mit Tiefenkarte wird sie unten (dunkel = fern) nach innen gezogen.
    expect(maxZWhere(withDepth, (y) => y < -0.15),
        lessThan(maxZWhere(withDepth, (y) => y > 0.15) - 0.1));
  });

  test('Relief nutzt die Tiefenkarte als Höhenquelle', () {
    final flat = buildReliefMesh(_solidImage(),
        resolution: 16, depth: 0.3, invert: false);
    final shaped = buildReliefMesh(_solidImage(),
        resolution: 16,
        depth: 0.3,
        invert: false,
        heightSource: _horizontalGradientImage());
    double maxZWhere(LocalMesh mesh, bool Function(double x) filter) {
      var maxZ = double.negativeInfinity;
      for (var i = 0; i < mesh.positions.length; i += 3) {
        if (filter(mesh.positions[i]) && mesh.positions[i + 2] > maxZ) {
          maxZ = mesh.positions[i + 2];
        }
      }
      return maxZ;
    }

    // Einfarbiges Bild → flache Deckfläche; mit Tiefenkarte steigt die
    // Höhe von links (dunkel) nach rechts (hell) an.
    expect(maxZWhere(flat, (x) => x < -0.2),
        closeTo(maxZWhere(flat, (x) => x > 0.2), 1e-6));
    expect(maxZWhere(shaped, (x) => x > 0.2),
        greaterThan(maxZWhere(shaped, (x) => x < -0.2) + 0.1));
  });

  test('Auto-Rigging baut Skelett und Gewichte ins GLB ein', () async {
    final mesh = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final glb = buildGlb(mesh);
    expect(glbHasSkin(glb), isFalse);

    final rigged = injectAutoRig(glb);
    expect(glbHasSkin(rigged), isTrue);

    final json = _readGlbJson(rigged);
    final skin = (json['skins'] as List).first as Map;
    expect(skin['joints'] as List, hasLength(rigJointCounts['biped']!));
    expect(skin.containsKey('inverseBindMatrices'), isTrue);

    final primitive = (((json['meshes'] as List).first as Map)['primitives']
        as List)[0] as Map;
    final attrs = primitive['attributes'] as Map;
    final accessors = json['accessors'] as List;
    final vertexCount =
        ((accessors[attrs['POSITION'] as int]) as Map)['count'];
    expect(((accessors[attrs['JOINTS_0'] as int]) as Map)['count'],
        vertexCount);
    expect(((accessors[attrs['WEIGHTS_0'] as int]) as Map)['count'],
        vertexCount);

    // Gewichte des ersten Vertex summieren sich zu 1.
    final weightsAccessor = accessors[attrs['WEIGHTS_0'] as int] as Map;
    final weightsView = (json['bufferViews']
        as List)[weightsAccessor['bufferView'] as int] as Map;
    final data = ByteData.sublistView(rigged);
    final jsonLength = data.getUint32(12, Endian.little);
    final binStart = 20 + jsonLength + 8;
    final o = binStart + (weightsView['byteOffset'] as int);
    var sum = 0.0;
    for (var c = 0; c < 4; c++) {
      sum += data.getFloat32(o + c * 4, Endian.little);
    }
    expect(sum, closeTo(1.0, 1e-4));

    // Der Mesh-Knoten hängt am Skin, die Vorschau funktioniert weiter.
    final meshNode = (json['nodes'] as List)
        .firstWhere((n) => (n as Map).containsKey('mesh')) as Map;
    expect(meshNode['skin'], 0);
    final preview = await parseGlbForPreview(rigged);
    expect(preview.vertexCount, vertexCount);

    // Doppeltes Rigging wird abgelehnt.
    expect(() => injectAutoRig(rigged), throwsException);
  });

  test('Geriggtes GLB: Skinning, Gelenke und Testanimationen', () async {
    final mesh = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final rigged = injectAutoRig(buildGlb(mesh));

    final preview = await parseGlbForPreview(rigged);
    final rig = preview.rig;
    expect(rig, isNotNull);
    expect(rig!.joints, hasLength(rigJointCounts['biped']!));
    expect(rig.vertexWeights, hasLength(preview.vertexCount * 4));
    expect(rig.vertexJoints, hasLength(preview.vertexCount * 4));

    // Ruhepose: Skinning reproduziert exakt die Originalpositionen.
    final rest = computeSkinnedPositions(preview);
    for (var i = 0; i < preview.positions.length; i += 97) {
      expect(rest[i], closeTo(preview.positions[i], 1e-4));
    }

    // Eine Rotation an einem Gelenk verändert die Pose sichtbar.
    final shoulderNode = rig.joints[rig.jointNames.indexOf('Shoulder_L')];
    final posed = computeSkinnedPositions(preview, rotationOverrides: {
      shoulderNode: Float32List.fromList([0, 0, 0.7071, 0.7071]),
    });
    var moved = 0.0;
    for (var i = 0; i < posed.length; i++) {
      moved += (posed[i] - preview.positions[i]).abs();
    }
    expect(moved, greaterThan(0.1));

    // Gelenkpositionen für die Skelett-Anzeige.
    final jointPositions = computeJointPositions(preview);
    expect(jointPositions, hasLength(rig.joints.length * 3));

    // Eingebaute Testanimationen passend zum Zweibeiner-Skelett.
    final clips = proceduralClipsFor(rig);
    final names = [for (final clip in clips) clip.name];
    expect(names, contains('Gehen'));
    expect(names, contains('Wackeltest'));
    expect(clips.first.poseAt(0.5), isNotEmpty);
  });

  test('Testanimationen lassen sich als glTF-Clips ins GLB backen',
      () async {
    final mesh = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final rigged = injectAutoRig(buildGlb(mesh));
    final preview = await parseGlbForPreview(rigged);
    final clips = proceduralClipsFor(preview.rig!);

    final baked = bakeAnimationsIntoGlb(rigged, clips);
    final json = _readGlbJson(baked);
    final animations = json['animations'] as List;
    expect(animations, hasLength(clips.length));
    for (var i = 0; i < clips.length; i++) {
      final animation = animations[i] as Map;
      expect(animation['name'], '${clips[i].name} (Test)');
      expect(animation['channels'] as List, isNotEmpty);
      expect((animation['samplers'] as List).length,
          (animation['channels'] as List).length);
    }

    // Die eingebackenen Clips sind wieder abspielbar und bewegen das
    // Modell tatsächlich.
    final bakedPreview = await parseGlbForPreview(baked);
    final bakedClips = bakedPreview.rig!.animations;
    expect(bakedClips, hasLength(clips.length));
    final walk = bakedClips.first;
    expect(walk.duration, greaterThan(0));
    final posed = computeSkinnedPositions(bakedPreview,
        animation: walk, time: walk.duration / 4);
    var moved = 0.0;
    for (var i = 0; i < posed.length; i++) {
      moved += (posed[i] - bakedPreview.positions[i]).abs();
    }
    expect(moved, greaterThan(0.01));
  });

  test('STL-Export: gültiges binäres STL in Druckgröße', () async {
    final mesh = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final glb = buildGlb(mesh);
    final stl = await glbToStl(glb, targetSizeMm: 80);

    final data = ByteData.sublistView(stl);
    final triangleCount = data.getUint32(80, Endian.little);
    expect(triangleCount, mesh.indices.length ~/ 3);
    expect(stl.length, 84 + triangleCount * 50);

    // Grenzen aller Eckpunkte: längste Seite 80 mm, Unterseite auf z=0.
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    var minZ = double.infinity, maxZ = double.negativeInfinity;
    for (var t = 0; t < triangleCount; t++) {
      final base = 84 + t * 50 + 12; // Normale überspringen
      for (var v = 0; v < 3; v++) {
        final x = data.getFloat32(base + v * 12, Endian.little);
        final y = data.getFloat32(base + v * 12 + 4, Endian.little);
        final z = data.getFloat32(base + v * 12 + 8, Endian.little);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }
    }
    final largest = [maxX - minX, maxY - minY, maxZ - minZ]
        .reduce((a, b) => a > b ? a : b);
    expect(largest, closeTo(80, 0.5));
    expect(minZ, closeTo(0, 1e-3));
  });

  test('3MF-Export: gültiger Container mit Farbpalette', () async {
    final mesh = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final glb = buildGlb(mesh);
    final data = await glbTo3mf(glb, targetSizeMm: 50);

    final archive = ZipDecoder().decodeBytes(data);
    final names = [for (final file in archive.files) file.name];
    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('_rels/.rels'));
    expect(names, contains('3D/3dmodel.model'));

    final model = String.fromCharCodes(
        archive.findFile('3D/3dmodel.model')!.content as List<int>);
    expect(model, contains('<model unit="millimeter"'));
    expect(model, contains('<basematerials id="1">'));
    // Farbiges Hull-Modell → mehrere Palettenfarben.
    expect('displaycolor'.allMatches(model).length, greaterThan(1));
    expect('<vertex '.allMatches(model).length,
        mesh.positions.length ~/ 3);
    expect('<triangle '.allMatches(model).length,
        mesh.indices.length ~/ 3);
    expect(model, contains('<item objectid="2"/>'));
  });

  test('Auto-Rigging kennt alle Figurtypen', () {
    final mesh = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final glb = buildGlb(mesh);
    for (final (rigType, _) in rigTypeOptions) {
      final rigged = injectAutoRig(glb, rigType: rigType);
      final json = _readGlbJson(rigged);
      final skin = (json['skins'] as List).first as Map;
      expect(skin['joints'] as List, hasLength(rigJointCounts[rigType]!),
          reason: 'Gelenkzahl für $rigType');
      // Alle Gelenk-Knoten existieren und der Wurzelknoten hängt in
      // der Szene.
      final nodes = json['nodes'] as List;
      for (final jointIndex in skin['joints'] as List) {
        expect((nodes[jointIndex as int] as Map).containsKey('translation'),
            isTrue);
      }
      expect(((json['scenes'] as List).first as Map)['nodes'] as List,
          contains(skin['skeleton']));
    }
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
