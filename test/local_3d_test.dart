import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/animation_bake.dart';
import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/preview_animations.dart';
import 'package:bildgenerator/services/mesh_check.dart';
import 'package:bildgenerator/services/model_import.dart';
import 'package:bildgenerator/services/model_refine.dart';
import 'package:bildgenerator/services/obj_export.dart';
import 'package:bildgenerator/services/roblox_check.dart';
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

  test('Wasserdichtheits-Prüfung: Hull geschlossen, offenes Netz nicht',
      () {
    final hull = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final closed = checkMeshWatertight(
      Float32List.fromList(hull.positions),
      Uint32List.fromList(hull.indices),
    );
    expect(closed.watertight, isTrue);
    expect(closed.openEdges, 0);
    expect(closed.triangles, hull.indices.length ~/ 3);

    // Ein einzelnes Dreieck hat drei offene Kanten.
    final open = checkMeshWatertight(
      Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
      Uint32List.fromList([0, 1, 2]),
    );
    expect(open.watertight, isFalse);
    expect(open.openEdges, 3);
  });

  test('Orientierung: Volumen, Wicklung und Nullstärke', () {
    final hull = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final positions = Float32List.fromList(hull.positions);
    final indices = Uint32List.fromList(hull.indices);
    final report = checkMeshOrientation(positions, indices);
    // Ein geschlossener Körper: einheitliche Wicklung, Volumen nach
    // außen, spürbares Volumen im Verhältnis zur Ausdehnung.
    expect(report.windingConsistent, isTrue);
    expect(report.normalsInverted, isFalse);
    expect(report.volumeRatio, greaterThan(0.001));
    expect(report.degenerateTriangles, 0);

    // Dieselbe Form mit umgedrehter Wicklung: Normalen nach innen.
    final flipped = Uint32List.fromList([
      for (var t = 0; t + 2 < indices.length; t += 3) ...[
        indices[t],
        indices[t + 2],
        indices[t + 1],
      ],
    ]);
    expect(checkMeshOrientation(positions, flipped).normalsInverted, isTrue);

    // Zwei Dreiecke als Platte: kein Volumen, dünnste Seite null.
    final sheet = checkMeshOrientation(
      Float32List.fromList([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0]),
      Uint32List.fromList([0, 1, 2, 0, 2, 3]),
    );
    expect(sheet.volumeRatio, lessThan(0.0001));
    expect(sheet.smallestSide, 0);
  });

  test('OBJ-Export: Vertices mit Farben und 1-basierte Flächen',
      () async {
    final mesh = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final glb = buildGlb(mesh);
    final obj = String.fromCharCodes(await glbToObj(glb));

    final vertexLines = [
      for (final line in obj.split('\n'))
        if (line.startsWith('v ')) line,
    ];
    final faceLines = [
      for (final line in obj.split('\n'))
        if (line.startsWith('f ')) line,
    ];
    expect(vertexLines, hasLength(mesh.positions.length ~/ 3));
    expect(faceLines, hasLength(mesh.indices.length ~/ 3));
    // Vertexzeile: Position + Farbe = 6 Zahlen.
    expect(vertexLines.first.split(RegExp(r'\s+')), hasLength(7));
    // OBJ-Indizes sind 1-basiert.
    for (final part in faceLines.first.split(' ').skip(1)) {
      expect(int.parse(part), greaterThan(0));
    }
  });

  test('Modell-Import: STL und OBJ kommen als GLB zurück', () async {
    final mesh = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final glb = buildGlb(mesh);

    // GLB wird unverändert durchgereicht.
    expect(importModelToGlb(glb, 'modell.glb'), same(glb));

    // STL → GLB: gleiche Dreieckszahl, Vorschau funktioniert.
    final stl = await glbToStl(glb, targetSizeMm: 50);
    final fromStl = await parseGlbForPreview(
        importModelToGlb(stl, 'modell.stl'));
    expect(fromStl.triangleCount, mesh.indices.length ~/ 3);

    // OBJ → GLB: Vertices, Flächen und Farben bleiben erhalten.
    final obj = await glbToObj(glb);
    final fromObj = await parseGlbForPreview(
        importModelToGlb(obj, 'modell.obj'));
    expect(fromObj.vertexCount, mesh.positions.length ~/ 3);
    expect(fromObj.triangleCount, mesh.indices.length ~/ 3);
    expect(fromObj.colors.toSet().length, greaterThan(1));

    // Unbekanntes Format wird abgelehnt.
    expect(
        () => importModelToGlb(
            Uint8List.fromList([1, 2, 3, 4, 5]), 'datei.xyz'),
        throwsException);
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

  test('Dezimierung reduziert die Dreieckszahl und erhält Farben', () {
    final mesh = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 24,
    );
    final before = mesh.indices.length ~/ 3;
    expect(before, greaterThan(400));
    final target = before ~/ 4;
    final small = decimateLocalMesh(mesh, target);
    final after = small.indices.length ~/ 3;
    expect(after, greaterThan(0));
    expect(after, lessThanOrEqualTo(target));
    // Farben bleiben je Vertex erhalten.
    expect(small.colors.length, small.positions.length);
  });

  test('Bilineare Farbabtastung mischt Pixel und meldet Transparenz', () {
    // 2×1: links rot, rechts grün.
    final img = RgbaImage(
        Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]), 2, 1);
    final mid = img.colorBilinear(0.5, 0)!;
    expect(mid.$1, closeTo(0.5, 0.02));
    expect(mid.$2, closeTo(0.5, 0.02));
    final clear = RgbaImage(Uint8List(8), 2, 1);
    expect(clear.colorBilinear(0.5, 0), isNull);
  });

  test('Textur-Atlas: hochauflösende Textur statt Vertex-Farben',
      () async {
    final front = _solidImage();
    final sampler = HullColorSampler(front: front, left: front, back: front);
    final mesh = buildVisualHullMesh(
      front: front,
      left: front,
      back: front,
      resolution: 12,
      sampler: sampler,
    );
    final (baked, rgba, size) =
        bakeHullTextureAtlas(mesh, sampler, atlasSize: 256);
    // Dreieckszahl unverändert; je Ecke ein eigener Vertex mit UV.
    expect(baked.indices.length, mesh.indices.length);
    expect(baked.positions.length ~/ 3, mesh.indices.length);
    expect(baked.uvs.length, (baked.positions.length ~/ 3) * 2);
    for (final uv in baked.uvs) {
      expect(uv, inInclusiveRange(0.0, 1.0));
    }
    expect(rgba.length, size * size * 4);
    // Erster Block ist deckend mit der Ansichtsfarbe gefüllt.
    expect(rgba[3], 255);
    expect(rgba[0].toDouble(), closeTo(120, 30));

    // GLB mit eingebetteter Textur, durch den Viewer lesbar.
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
    final glb = buildGlb(baked, pngTexture: png);
    final json = _readGlbJson(glb);
    final attrs = ((((json['meshes'] as List).first as Map)['primitives']
        as List)
        .first as Map)['attributes'] as Map;
    expect(attrs, contains('TEXCOORD_0'));
    expect(json['images'], isNotNull);

    final preview = await parseGlbForPreview(glb);
    expect(preview.texture, isNotNull);
    expect(preview.uvs, isNotNull);
    // Verschweißte Normalen: positionsgleiche (aufgetrennte) Vertices
    // erhalten identische glatte Normalen.
    final weld = preview.weldMap!;
    var duplicates = 0;
    for (var v = 0; v < weld.length; v++) {
      if (weld[v] != v) {
        duplicates++;
        expect(preview.normals[v * 3], preview.normals[weld[v] * 3]);
        expect(
            preview.normals[v * 3 + 1], preview.normals[weld[v] * 3 + 1]);
      }
    }
    expect(duplicates, greaterThan(0));
    preview.dispose();
  });

  test('Viewer ignoriert Textur-Alpha bei OPAQUE-Material (kein Ghosting)',
      () async {
    // 2×2-Textur mit transparenten/halbtransparenten Pixeln.
    final rgba = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 0, //
      0, 0, 255, 128, 255, 255, 0, 255,
    ]);
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(buffer,
        width: 2, height: 2, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final png =
        (await frame.image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
    frame.image.dispose();

    final mesh = LocalMesh();
    mesh.addVertex(0, 0, 0, 0, 0);
    mesh.addVertex(1, 0, 0, 1, 0);
    mesh.addVertex(0, 1, 0, 0, 1);
    mesh.addTriangle(0, 1, 2);
    // Kein alphaMask → Material ist OPAQUE, Alpha wird entfernt.
    final glb = buildGlb(mesh, pngTexture: png);
    final preview = await parseGlbForPreview(glb);
    final texture = preview.texture!;
    final pixels =
        (await texture.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    for (var i = 3; i < pixels.length; i += 4) {
      expect(pixels[i], 255);
    }
    preview.dispose();

    // UV-Wrap: Werte in [0,1] bleiben unverändert (v. a. u = 1,0),
    // außerhalb wird wiederholt.
    expect(wrapUv(1.0), 1.0);
    expect(wrapUv(0.0), 0.0);
    expect(wrapUv(1.25), closeTo(0.25, 1e-9));
    expect(wrapUv(-0.25), closeTo(0.75, 1e-9));
  });

  test('GLB-Material übernimmt Oberflächen-Werte (PBR)', () async {
    final mesh = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 10,
    );
    final glb = buildGlb(mesh, metallic: 0.9, roughness: 0.35);
    final json = _readGlbJson(glb);
    final pbr = ((json['materials'] as List).first
        as Map)['pbrMetallicRoughness'] as Map;
    expect(pbr['metallicFactor'], closeTo(0.9, 1e-6));
    expect(pbr['roughnessFactor'], closeTo(0.35, 1e-6));

    // Der Viewer-Parser liest die Werte zurück (für die
    // Glanzlicht-Anzeige in der Vorschau).
    final preview = await parseGlbForPreview(glb);
    expect(preview.metallic, closeTo(0.9, 1e-6));
    expect(preview.roughness, closeTo(0.35, 1e-6));
    preview.dispose();
  });

  test('Auto-Rigging vermisst Chibi-Proportionen (Hals unter dem Kopf)',
      () {
    // Synthetische Chibi-Figur: kurze getrennte Beine unten, schmaler
    // Rumpf, riesiger Kopf ab halber Höhe.
    final mesh = LocalMesh();
    void addBox(double x0, double x1, double y0, double y1, double z0,
        double z1) {
      final a = mesh.addVertex(x0, y0, z0, 0, 0);
      final b = mesh.addVertex(x1, y0, z0, 0, 0);
      final c = mesh.addVertex(x1, y1, z0, 0, 0);
      final d = mesh.addVertex(x0, y1, z0, 0, 0);
      final e = mesh.addVertex(x0, y0, z1, 0, 0);
      final f = mesh.addVertex(x1, y0, z1, 0, 0);
      final g = mesh.addVertex(x1, y1, z1, 0, 0);
      final h = mesh.addVertex(x0, y1, z1, 0, 0);
      mesh.addQuad(a, b, c, d);
      mesh.addQuad(e, f, g, h);
      mesh.addQuad(a, b, f, e);
      mesh.addQuad(d, c, g, h);
      mesh.addQuad(a, d, h, e);
      mesh.addQuad(b, c, g, f);
    }

    // Umriss-Vertices auf vielen Höhenstufen, damit das Höhenprofil
    // dicht besetzt ist (wie bei echten, fein aufgelösten Netzen).
    void densify(double x0, double x1, double y0, double y1, double z0,
        double z1, {required bool centerFilled}) {
      for (var step = 0; step <= 12; step++) {
        final y = y0 + (y1 - y0) * step / 12;
        mesh.addVertex(x0, y, z0, 0, 0);
        mesh.addVertex(x1, y, z0, 0, 0);
        mesh.addVertex(x1, y, z1, 0, 0);
        mesh.addVertex(x0, y, z1, 0, 0);
        if (centerFilled) mesh.addVertex(0, y, z1, 0, 0);
      }
    }

    addBox(-0.22, -0.08, 0.0, 0.2, -0.1, 0.1); // Bein links
    addBox(0.08, 0.22, 0.0, 0.2, -0.1, 0.1); // Bein rechts
    addBox(-0.2, 0.2, 0.2, 0.5, -0.12, 0.12); // Rumpf
    addBox(-0.5, 0.5, 0.5, 1.0, -0.35, 0.35); // Riesenkopf
    densify(-0.22, -0.08, 0.0, 0.2, -0.1, 0.1, centerFilled: false);
    densify(0.08, 0.22, 0.0, 0.2, -0.1, 0.1, centerFilled: false);
    densify(-0.2, 0.2, 0.2, 0.5, -0.12, 0.12, centerFilled: true);
    densify(-0.5, 0.5, 0.5, 1.0, -0.35, 0.35, centerFilled: true);

    final rigged = injectAutoRig(buildGlb(mesh));
    final json = _readGlbJson(rigged);
    final nodes = json['nodes'] as List;
    double absoluteY(String name) {
      var index = -1;
      for (var i = 0; i < nodes.length; i++) {
        if ((nodes[i] as Map)['name'] == name) index = i;
      }
      expect(index, greaterThanOrEqualTo(0), reason: '$name fehlt');
      // Übersetzungen entlang der Elternkette aufsummieren.
      var y = 0.0;
      final childOf = <int, int>{};
      for (var i = 0; i < nodes.length; i++) {
        for (final child in (nodes[i] as Map)['children'] as List? ?? []) {
          childOf[child as int] = i;
        }
      }
      var current = index;
      while (current >= 0) {
        final t = (nodes[current] as Map)['translation'] as List?;
        if (t != null) y += (t[1] as num).toDouble();
        current = childOf[current] ?? -1;
      }
      return y;
    }

    // Hals sitzt unter dem Riesenkopf (~0.5), nicht bei Standard 0.84;
    // die Hüfte nahe dem Beinansatz (~0.2), nicht bei 0.52.
    expect(absoluteY('Neck'), lessThan(0.62));
    expect(absoluteY('Neck'), greaterThan(0.35));
    expect(absoluteY('Hips'), lessThan(0.35));
    expect(absoluteY('Shoulder_L'), lessThan(0.6));
  });

  test('Auto-Rigging: Schultern folgen erkannten Armen (nicht der Frisur)',
      () {
    // Figur, bei der die Halsschätzung über Breiten-Minima versagt:
    // riesige Frisur umschließt den Kopf, die Stiefel stehen so eng,
    // dass das grobe Mittelband keinen Beinspalt sieht. Die
    // Inseln-Erkennung findet Beinspalt und Arm-Band trotzdem.
    final mesh = LocalMesh();
    void denseBox(double x0, double x1, double y0, double y1, double z0,
        double z1) {
      const nx = 9, ny = 13;
      for (var iy = 0; iy <= ny; iy++) {
        final y = y0 + (y1 - y0) * iy / ny;
        for (var ix = 0; ix <= nx; ix++) {
          final x = x0 + (x1 - x0) * ix / nx;
          mesh.addVertex(x, y, z0, 0, 0);
          mesh.addVertex(x, y, z1, 0, 0);
        }
      }
      final a = mesh.addVertex(x0, y0, z0, 0, 0);
      final b = mesh.addVertex(x1, y0, z0, 0, 0);
      final c = mesh.addVertex(x1, y1, z1, 0, 0);
      final d = mesh.addVertex(x0, y1, z1, 0, 0);
      mesh.addQuad(a, b, c, d);
    }

    denseBox(-0.16, -0.02, 0.0, 0.12, -0.08, 0.08); // Stiefel links
    denseBox(0.02, 0.16, 0.0, 0.12, -0.08, 0.08); // Stiefel rechts
    denseBox(-0.22, 0.22, 0.12, 0.52, -0.12, 0.12); // Rumpf
    denseBox(-0.4, -0.3, 0.28, 0.42, -0.06, 0.06); // Fäustling links
    denseBox(0.3, 0.4, 0.28, 0.42, -0.06, 0.06); // Fäustling rechts
    denseBox(-0.4, 0.4, 0.52, 1.0, -0.3, 0.3); // Riesiger Haarkopf

    final rigged = injectAutoRig(buildGlb(mesh));
    final json = _readGlbJson(rigged);
    final nodes = json['nodes'] as List;
    double absoluteY(String name) {
      var index = -1;
      for (var i = 0; i < nodes.length; i++) {
        if ((nodes[i] as Map)['name'] == name) index = i;
      }
      expect(index, greaterThanOrEqualTo(0), reason: '$name fehlt');
      final childOf = <int, int>{};
      for (var i = 0; i < nodes.length; i++) {
        for (final child in (nodes[i] as Map)['children'] as List? ?? []) {
          childOf[child as int] = i;
        }
      }
      var y = 0.0;
      var current = index;
      while (current >= 0) {
        final t = (nodes[current] as Map)['translation'] as List?;
        if (t != null) y += (t[1] as num).toDouble();
        current = childOf[current] ?? -1;
      }
      return y;
    }

    // Schultern auf Armhöhe (~0,45) statt auf Nasenhöhe (0,80).
    expect(absoluteY('Shoulder_L'), inInclusiveRange(0.38, 0.58));
    expect(absoluteY('Neck'), lessThan(0.65));
    // Beinspalt trotz eng stehender Stiefel erkannt.
    expect(absoluteY('Hips'), lessThan(0.35));
  });

  test(
      'Blickrichtung: -z-Figur wird erkannt, Rig gespiegelt und '
      'Verbeugung geht zum Gesicht', () async {
    // Figur wie aus Stability-Bild→3D: Gesicht Richtung sign*z –
    // Schuhe ragen nach vorn über den Rumpf hinaus, der Kopf sitzt
    // vor der Brustmitte.
    LocalMesh figure(double sign) {
      final mesh = LocalMesh();
      void denseBox(double x0, double x1, double y0, double y1, double z0,
          double z1) {
        const nx = 9, ny = 13;
        for (var iy = 0; iy <= ny; iy++) {
          final y = y0 + (y1 - y0) * iy / ny;
          for (var ix = 0; ix <= nx; ix++) {
            final x = x0 + (x1 - x0) * ix / nx;
            mesh.addVertex(x, y, sign * z0, 0, 0);
            mesh.addVertex(x, y, sign * z1, 0, 0);
          }
        }
        final a = mesh.addVertex(x0, y0, sign * z0, 0, 0);
        final b = mesh.addVertex(x1, y0, sign * z0, 0, 0);
        final c = mesh.addVertex(x1, y1, sign * z1, 0, 0);
        final d = mesh.addVertex(x0, y1, sign * z1, 0, 0);
        mesh.addQuad(a, b, c, d);
      }

      denseBox(-0.18, -0.04, 0.0, 0.12, 0.22, -0.06); // Schuh links
      denseBox(0.04, 0.18, 0.0, 0.12, 0.22, -0.06); // Schuh rechts
      denseBox(-0.22, 0.22, 0.12, 0.55, 0.10, -0.10); // Rumpf
      denseBox(-0.42, -0.3, 0.3, 0.44, 0.06, -0.06); // Hand links
      denseBox(0.3, 0.42, 0.3, 0.44, 0.06, -0.06); // Hand rechts
      denseBox(-0.24, 0.24, 0.55, 1.0, 0.2, -0.04); // Kopf (Gesicht vorn)
      return mesh;
    }

    // Geometrische Schätzung: -1 bei Gesicht nach -z, +1 gespiegelt.
    Float32List positionsOf(LocalMesh mesh) =>
        Float32List.fromList(mesh.positions);

    expect(estimateFrontSign([positionsOf(figure(-1))]), -1);
    expect(estimateFrontSign([positionsOf(figure(1))]), 1);

    for (final (sign, expected) in [(-1.0, -1), (1.0, 1)]) {
      final rigged = injectAutoRig(buildGlb(figure(sign)));
      final json = _readGlbJson(rigged);
      final skin = (json['skins'] as List).first as Map;
      // Blickrichtung in den Skin-Extras hinterlegt.
      expect((skin['extras'] as Map)['front_z'], expected,
          reason: 'front_z für sign=$sign');

      // Beim Abspielen: Verbeugung biegt die Wirbelsäule zum Gesicht
      // (Rotation um +x biegt nach +z, um -x nach -z).
      final preview = await parseGlbForPreview(rigged);
      expect(preview.rig, isNotNull);
      expect(preview.rig!.frontSign, expected);
      final clips = proceduralClipsFor(preview.rig!);
      final verbeugen = clips.firstWhere((c) => c.name == 'Verbeugen');
      final names = preview.rig!.jointNames;
      final spineNode =
          preview.rig!.joints[names.indexOf('Spine')];
      final pose = verbeugen.poseAt(verbeugen.period / 2);
      final qx = pose[spineNode]![0];
      expect(qx * expected, greaterThan(0),
          reason: 'Verbeugung muss zum Gesicht ($expected z) gehen');
      preview.dispose();
    }
  });

  test('Drehen in 90°-Schritten dreht die Geometrie mit', () async {
    // Schmaler, liegender Quader: lang in z, flach in y – wie ein
    // Modell, das z-up exportiert wurde.
    final mesh = LocalMesh();
    void add(double x, double y, double z) =>
        mesh.addVertex(x, y, z, 0, 0);
    for (final x in [-0.2, 0.2]) {
      for (final y in [-0.1, 0.1]) {
        for (final z in [-0.9, 0.9]) {
          add(x, y, z);
        }
      }
    }
    for (var i = 0; i + 2 < 8; i++) {
      mesh.addTriangle(i, i + 1, i + 2);
    }
    final glb = buildGlb(mesh);

    Future<(double, double, double)> extent(Uint8List data) async {
      final positions = (await parseGlbForPreview(data)).positions;
      var lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
      for (var i = 0; i + 2 < positions.length; i += 3) {
        for (var k = 0; k < 3; k++) {
          if (positions[i + k] < lo[k]) lo[k] = positions[i + k];
          if (positions[i + k] > hi[k]) hi[k] = positions[i + k];
        }
      }
      return (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]);
    }

    final before = await extent(glb);
    expect(before.$3, greaterThan(before.$2),
        reason: 'liegt zunächst in z');

    // Drehung um x tauscht Höhe und Tiefe: das Modell steht.
    final upright = rotateGlbQuarterTurns(glb, 'x');
    final after = await extent(upright);
    expect(after.$2, closeTo(before.$3, 1e-4), reason: 'Höhe war Tiefe');
    expect(after.$3, closeTo(before.$2, 1e-4), reason: 'Tiefe war Höhe');
    expect(after.$1, closeTo(before.$1, 1e-4), reason: 'Breite bleibt');

    // Viermal drehen führt zurück zum Ausgangszustand.
    var round = glb;
    for (var i = 0; i < 4; i++) {
      round = rotateGlbQuarterTurns(round, 'x');
    }
    final back = await extent(round);
    expect(back.$1, closeTo(before.$1, 1e-4));
    expect(back.$2, closeTo(before.$2, 1e-4));
    expect(back.$3, closeTo(before.$3, 1e-4));

    // 0 Vierteldrehungen lassen die Datei unverändert.
    expect(rotateGlbQuarterTurns(glb, 'y', quarterTurns: 0), same(glb));

    // Geriggte Modelle werden abgelehnt (Skelett würde zerreißen).
    final rigged = injectAutoRig(glb, rigType: 'biped');
    expect(() => rotateGlbQuarterTurns(rigged, 'x'), throwsException);
  });

  test('Gelenke melden ihren Wirkungs-Radius für die Kugel-Anzeige',
      () {
    final glb = buildGlb(buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    ));
    final joints = computeAutoRigJoints(glb, rigType: 'biped');
    expect(joints, isNotEmpty);
    for (final j in joints) {
      expect(j.radius, greaterThan(0),
          reason: 'jedes Gelenk braucht einen Radius für die Anzeige');
    }
    // Kopf und Rumpf greifen weiter als die schmalen Arme.
    double radiusOf(String name) =>
        joints.firstWhere((j) => j.name == name).radius;
    expect(radiusOf('Head'), greaterThan(radiusOf('Elbow_L')));
  });

  test('Gelenk-Anleitung erklärt jedes Gelenk verständlich', () {
    expect(jointGuide('Hips'), contains('Becken'));
    expect(jointGuide('Hand_L'), contains('linke Seite'));
    expect(jointGuide('Hand_R'), contains('rechte Seite'));
    // Fäustlinge/Handschuhe: Hinweis auf den Einflussbereich.
    expect(jointGuide('Hand_L'), contains('Einflussbereich'));
    // Nummerierte Namen fallen auf die Grundform zurück.
    expect(jointGuide('Wheel2_L'), contains('Radmitte'));
    expect(jointGuide('Spine_3'), contains('Wirbelsäule'));
    // Endsegmente und Unbekanntes bekommen trotzdem einen Text.
    expect(jointGuide('Hand_L_Tip'), isNotEmpty);
    expect(jointGuide('Sonderling'), contains('Sonderling'));
  });

  test(
      'Veredelung: kanonische Ausrichtung dreht schräge Fahrzeuge '
      'gerade und macht sie riggbar', () {
    // Standard-Testauto (Länge entlang z), um 25° um die y-Achse
    // gedreht – wie eine Stability-Rekonstruktion aus einer
    // Dreiviertelansicht.
    const angle = 25 * math.pi / 180;
    LocalMesh rotatedCar() {
      final mesh = LocalMesh();
      void add(double x, double y, double z) {
        mesh.addVertex(x * math.cos(angle) + z * math.sin(angle), y,
            -x * math.sin(angle) + z * math.cos(angle), 0, 0);
      }

      void box(List<double> b) {
        for (final z in [b[4], b[5]]) {
          for (final x in [b[0], b[1]]) {
            for (final y in [b[2], b[3]]) {
              add(x, y, z);
            }
          }
        }
      }

      box([-0.5, 0.5, 0.3, 1.0, -1.0, 1.0]); // Karosserie
      for (final (z0, z1) in [(0.5, 0.9), (-0.9, -0.5)]) {
        box([-0.45, -0.25, 0.0, 0.35, z0, z1]);
        box([0.25, 0.45, 0.0, 0.35, z0, z1]);
        for (var step = 0; step <= 60; step++) {
          final z = z0 + (z1 - z0) * step / 60;
          add(-0.35, 0.02, z);
          add(0.35, 0.02, z);
        }
      }
      final a = mesh.addVertex(0, 0, 0, 0, 0);
      final b2 = mesh.addVertex(0.1, 0, 0, 0, 0);
      final c = mesh.addVertex(0, 0.1, 0, 0, 0);
      mesh.addTriangle(a, b2, c);
      return mesh;
    }

    final glb = buildGlb(rotatedCar());
    final (aligned, degrees) = canonicalizeYawGlb(glb);
    // Der angewendete Winkel entspricht der Verdrehung (±3°).
    expect(degrees.abs(), inInclusiveRange(22, 28));
    // Nach der Ausrichtung greift die Rad-Erkennung wieder.
    final rigged = injectAutoRig(aligned, rigType: 'vehicle');
    final json = _readGlbJson(rigged);
    final nodes = json['nodes'] as List;
    final skin = (json['skins'] as List).first as Map;
    final names = [
      for (final j in skin['joints'] as List)
        (nodes[j as int] as Map)['name'] as String,
    ];
    expect(
        names,
        unorderedEquals(
            ['Body', 'Wheel1_L', 'Wheel1_R', 'Wheel2_L', 'Wheel2_R']));
    // Bereits ausgerichtete Modelle bleiben unverändert.
    final (_, zeroDegrees) = canonicalizeYawGlb(aligned);
    expect(zeroDegrees, 0);
  });

  test(
      'Veredelung: Symmetrisieren ersetzt die schwächere Hälfte durch '
      'das Spiegelbild', () async {
    // Texturiertes Testnetz: dichte linke Hälfte, rechts nur ein
    // grober „Klumpen“-Fortsatz (wie die abgewandte Seite einer
    // Einzelbild-Rekonstruktion).
    final mesh = LocalMesh();
    void quad(double x0, double x1, double y0, double y1, double z) {
      final a = mesh.addVertex(x0, y0, z, 0.1, 0.1);
      final b = mesh.addVertex(x1, y0, z, 0.9, 0.1);
      final c = mesh.addVertex(x1, y1, z, 0.9, 0.9);
      final d = mesh.addVertex(x0, y1, z, 0.1, 0.9);
      mesh.addQuad(a, b, c, d);
    }

    // Dichte linke Seite (viele kleine Quads) über die Mitte hinweg.
    for (var i = 0; i < 8; i++) {
      quad(-0.5 + i * 0.05, -0.45 + i * 0.05, 0.0, 0.5, 0.1 * (i % 2));
    }
    quad(-0.5, 0.5, 0.0, 0.5, 0.3); // über die Mittelebene
    // Grobe rechte Markierung, die verschwinden muss.
    quad(0.38, 0.42, 0.6, 0.9, 0.0);

    final rgba = Uint8List.fromList(
        List.generate(16, (i) => i % 4 == 3 ? 255 : 180));
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(buffer,
        width: 2, height: 2, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final png =
        (await frame.image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
    frame.image.dispose();
    final glb = buildGlb(mesh, pngTexture: png);
    final symmetrized = await mirrorSymmetrizeGlb(glb);

    final preview = await parseGlbForPreview(symmetrized);
    expect(preview.texture, isNotNull, reason: 'Textur bleibt erhalten');
    final positions = preview.positions;
    // Perfekt symmetrisch: jede x-Koordinate existiert gespiegelt.
    var leftCount = 0, rightCount = 0;
    var hasRightMarker = false;
    for (var i = 0; i < positions.length; i += 3) {
      if (positions[i] < -1e-6) leftCount++;
      if (positions[i] > 1e-6) rightCount++;
      if (positions[i] > 0.3 && positions[i + 1] > 0.55) {
        hasRightMarker = true;
      }
    }
    expect(leftCount, rightCount, reason: 'beide Hälften gleich dicht');
    expect(hasRightMarker, isFalse,
        reason: 'die grobe rechte Hälfte wurde ersetzt');
    preview.dispose();
  });

  test(
      'Veredelung: Textur-Reprojektion schärft die sichtbare Seite und '
      'lässt Verdecktes unberührt', () async {
    // Drei Quads: der Kamera (-z) zugewandt vorn, dahinter ein
    // verdecktes Quad, dazu ein abgewandtes Quad – jedes mit eigener
    // Textur-Region.
    final mesh = LocalMesh();
    void quad(double z, double u0, double v0, {bool facingCamera = true}) {
      final a = mesh.addVertex(-0.5, -0.5, z, u0, v0 + 0.35);
      final b = mesh.addVertex(0.5, -0.5, z, u0 + 0.35, v0 + 0.35);
      final c = mesh.addVertex(0.5, 0.5, z, u0 + 0.35, v0);
      final d = mesh.addVertex(-0.5, 0.5, z, u0, v0);
      if (facingCamera) {
        mesh.addTriangle(a, c, b);
        mesh.addTriangle(a, d, c);
      } else {
        mesh.addTriangle(a, b, c);
        mesh.addTriangle(a, c, d);
      }
    }

    quad(-0.4, 0.05, 0.05); // vorn, sichtbar
    quad(0.1, 0.55, 0.05); // gleiche Fläche, verdeckt
    quad(0.5, 0.05, 0.55, facingCamera: false); // abgewandt

    // Einheitlich graue 64er-Textur.
    final gray = Uint8List.fromList(List.generate(
        64 * 64 * 4, (i) => i % 4 == 3 ? 255 : 128));
    Future<Uint8List> encode(Uint8List rgba, int size) async {
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

    final glb = buildGlb(mesh, pngTexture: await encode(gray, 64));

    // Quellbild 200×200: deckender Kernbereich mit grau-nahem
    // Verlauf und markantem Blauanteil (b=140).
    const s = 200;
    final source = Uint8List(s * s * 4);
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        final o = (y * s + x) * 4;
        source[o] = 100 + (x * 40 ~/ s);
        source[o + 1] = 128;
        source[o + 2] = 140;
        source[o + 3] =
            (x >= 20 && x < 180 && y >= 20 && y < 180) ? 255 : 0;
      }
    }

    final refined = await reprojectSourceImageTexture(
        glb, await encode(source, s));
    expect(refined, isNotNull, reason: 'Kalibrierung muss gelingen');
    final preview = await parseGlbForPreview(refined!);
    final tex =
        (await preview.texture!.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    final tw = preview.texture!.width;
    int channel(double u, double v, int c) =>
        tex[(((v * (tw - 1)).round()) * tw + (u * (tw - 1)).round()) * 4 +
            c];
    // Sichtbares Quad: Bildfarbe übernommen (markantes b=140).
    expect(channel(0.225, 0.225, 2), inInclusiveRange(132, 148),
        reason: 'sichtbare Seite geschärft');
    expect(channel(0.225, 0.225, 0), inInclusiveRange(95, 145));
    // Verdecktes Quad: unverändert grau.
    expect(channel(0.725, 0.225, 2), inInclusiveRange(120, 136),
        reason: 'verdeckte Fläche bleibt unberührt');
    // Abgewandtes Quad: unverändert grau.
    expect(channel(0.225, 0.725, 2), inInclusiveRange(120, 136),
        reason: 'abgewandte Fläche bleibt unberührt');
    preview.dispose();

    // Unpassendes Bild (kräftiges Blau, weit weg von der Textur):
    // Kalibrierung schlägt fehl, nichts wird verändert.
    final wrong = Uint8List(s * s * 4);
    for (var i = 0; i < wrong.length; i += 4) {
      wrong[i + 2] = 255;
      wrong[i + 3] = 255;
    }
    expect(await reprojectSourceImageTexture(glb, await encode(wrong, s)),
        isNull);
  });

  test('Fahrzeug-Rig lehnt flache „Platten“-Modelle verständlich ab', () {
    // Wie eine Bild→3D-Rekonstruktion aus reiner Frontalansicht: hoch
    // und breit, aber fast ohne Tiefe – kein fahrbereites Fahrzeug.
    final mesh = LocalMesh();
    for (var iy = 0; iy <= 20; iy++) {
      for (var ix = 0; ix <= 12; ix++) {
        final x = -0.3 + 0.6 * ix / 12;
        final y = iy / 20;
        mesh.addVertex(x, y, -0.13, 0, 0);
        mesh.addVertex(x, y, 0.13, 0, 0);
      }
    }
    final a = mesh.addVertex(-0.3, 0, -0.13, 0, 0);
    final b = mesh.addVertex(0.3, 0, -0.13, 0, 0);
    final c = mesh.addVertex(0.3, 1, 0.13, 0, 0);
    final d = mesh.addVertex(-0.3, 1, 0.13, 0, 0);
    mesh.addQuad(a, b, c, d);
    expect(
        () => injectAutoRig(buildGlb(mesh), rigType: 'vehicle'),
        throwsA(predicate((e) =>
            e.toString().contains('Frontalansicht') &&
            e.toString().contains('Dreiviertelansicht'))));
  });

  test('Rig-Editor: angepasste Gelenke lassen sich aus dem GLB '
      'zurücklesen', () async {
    // Kern des Fehlers "geändertes Rig ist beim erneuten Öffnen weg":
    // Der Editor muss die verschobenen Gelenke aus dem geriggten
    // Modell wiederfinden, statt die Automatik neu zu rechnen.
    final glb = buildGlb(buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    ));
    final auto = computeAutoRigJoints(glb);
    final head = auto.firstWhere((j) => j.name == 'Head');
    final target = (head.x + 0.12, head.y + 0.07, head.z - 0.03);
    final rigged = injectAutoRig(glb, jointPositions: {'Head': target});

    // Wie im Viewer: lokale Translationen der Skelett-Kette aufaddieren.
    final rig = (await parseGlbForPreview(rigged)).rig!;
    final world = <int, List<double>>{};
    for (final index in rig.nodeOrder) {
      final node = rig.nodes[index];
      final parent = node.parent >= 0 ? world[node.parent] : null;
      world[index] = [
        (parent?[0] ?? 0) + node.translation[0],
        (parent?[1] ?? 0) + node.translation[1],
        (parent?[2] ?? 0) + node.translation[2],
      ];
    }
    List<double>? readBack;
    for (final nodeIndex in rig.joints) {
      if (rig.nodes[nodeIndex].name == 'Head') readBack = world[nodeIndex];
    }
    expect(readBack, isNotNull, reason: 'Head im Skelett gefunden');
    expect(readBack![0], closeTo(target.$1, 1e-4));
    expect(readBack[1], closeTo(target.$2, 1e-4));
    expect(readBack[2], closeTo(target.$3, 1e-4));
    // Und die zurückgelesene Position ist wirklich die verschobene.
    expect(readBack[0], isNot(closeTo(head.x, 1e-3)));
  });

  test('Rig-Editor: Gelenk-Overrides verschieben Skelett-Knoten', () {
    final mesh = buildVisualHullMesh(
      front: _solidImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 12,
    );
    final glb = buildGlb(mesh);
    final joints = computeAutoRigJoints(glb);
    expect(joints, hasLength(rigJointCounts['biped']!));
    final head = joints.firstWhere((j) => j.name == 'Head');

    final moved = injectAutoRig(glb, jointPositions: {
      'Head': (head.x + 0.1, head.y + 0.05, head.z),
    });
    final json = _readGlbJson(moved);
    final nodes = json['nodes'] as List;
    (double, double) absoluteXY(String name) {
      var index = -1;
      for (var i = 0; i < nodes.length; i++) {
        if ((nodes[i] as Map)['name'] == name) index = i;
      }
      expect(index, greaterThanOrEqualTo(0), reason: '$name fehlt');
      final childOf = <int, int>{};
      for (var i = 0; i < nodes.length; i++) {
        for (final child in (nodes[i] as Map)['children'] as List? ?? []) {
          childOf[child as int] = i;
        }
      }
      var x = 0.0, y = 0.0;
      var current = index;
      while (current >= 0) {
        final t = (nodes[current] as Map)['translation'] as List?;
        if (t != null) {
          x += (t[0] as num).toDouble();
          y += (t[1] as num).toDouble();
        }
        current = childOf[current] ?? -1;
      }
      return (x, y);
    }

    final (hx, hy) = absoluteXY('Head');
    expect(hx, closeTo(head.x + 0.1, 1e-5));
    expect(hy, closeTo(head.y + 0.05, 1e-5));
    // Nicht überschriebene Gelenke bleiben an ihrer Position.
    final hips = joints.firstWhere((j) => j.name == 'Hips');
    final (px, py) = absoluteXY('Hips');
    expect(px, closeTo(hips.x, 1e-5));
    expect(py, closeTo(hips.y, 1e-5));

    // Einfluss-Skalierung eines Gelenks verändert die Skin-Gewichte.
    final normal = injectAutoRig(glb);
    final narrow = injectAutoRig(glb, jointInfluence: {'Head': 0.4});
    expect(narrow.length, normal.length);
    expect(narrow, isNot(equals(normal)));
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
      if (rigType == 'vehicle') {
        // Radzahl ist adaptiv – mindestens Karosserie + 1 Rad.
        expect((skin['joints'] as List).length, greaterThanOrEqualTo(2),
            reason: 'Gelenkzahl für $rigType');
      } else {
        expect(skin['joints'] as List, hasLength(rigJointCounts[rigType]!),
            reason: 'Gelenkzahl für $rigType');
      }
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

  test('Fahrzeug-Rig erkennt Achsen und Radzahl automatisch', () async {
    // Fahrzeug-Testnetz: Quader ([x0,x1,y0,y1,z0,z1]) für Karosserie
    // und Räder; die Radunterseiten werden dicht abgetastet, damit die
    // Achsen-Erkennung ein gefülltes Histogramm sieht (wie bei echten,
    // fein aufgelösten Netzen).
    LocalMesh vehicleMesh(
        List<List<double>> boxes, List<List<double>> wheelFloors) {
      final mesh = LocalMesh();
      for (final b in boxes) {
        final v0 = mesh.addVertex(b[0], b[2], b[4], 0, 0);
        final v1 = mesh.addVertex(b[1], b[2], b[4], 0, 0);
        final v2 = mesh.addVertex(b[1], b[3], b[4], 0, 0);
        final v3 = mesh.addVertex(b[0], b[3], b[4], 0, 0);
        final v4 = mesh.addVertex(b[0], b[2], b[5], 0, 0);
        final v5 = mesh.addVertex(b[1], b[2], b[5], 0, 0);
        final v6 = mesh.addVertex(b[1], b[3], b[5], 0, 0);
        final v7 = mesh.addVertex(b[0], b[3], b[5], 0, 0);
        mesh.addQuad(v0, v1, v2, v3);
        mesh.addQuad(v4, v5, v6, v7);
        mesh.addQuad(v0, v1, v5, v4);
        mesh.addQuad(v3, v2, v6, v7);
        mesh.addQuad(v0, v3, v7, v4);
        mesh.addQuad(v1, v2, v6, v5);
      }
      for (final f in wheelFloors) {
        for (var step = 0; step <= 60; step++) {
          final z = f[2] + (f[3] - f[2]) * step / 60;
          mesh.addVertex(f[0], 0.02, z, 0, 0);
          mesh.addVertex(f[1], 0.02, z, 0, 0);
          mesh.addVertex((f[0] + f[1]) / 2, 0.02, z, 0, 0);
        }
      }
      return mesh;
    }

    Uint8List rig(LocalMesh mesh) =>
        injectAutoRig(buildGlb(mesh), rigType: 'vehicle');
    List<String> jointNames(Uint8List rigged) {
      final json = _readGlbJson(rigged);
      final nodes = json['nodes'] as List;
      final skin = (json['skins'] as List).first as Map;
      return [
        for (final j in skin['joints'] as List)
          (nodes[j as int] as Map)['name'] as String,
      ];
    }

    // Auto: 2 Achsen mit Radpaaren → Karosserie + 4 Räder.
    final car = vehicleMesh([
      [-0.5, 0.5, 0.3, 1.0, -1.0, 1.0],
      [-0.45, -0.25, 0.0, 0.35, 0.5, 0.9],
      [0.25, 0.45, 0.0, 0.35, 0.5, 0.9],
      [-0.45, -0.25, 0.0, 0.35, -0.9, -0.5],
      [0.25, 0.45, 0.0, 0.35, -0.9, -0.5],
    ], [
      [-0.45, -0.25, 0.5, 0.9],
      [0.25, 0.45, 0.5, 0.9],
      [-0.45, -0.25, -0.9, -0.5],
      [0.25, 0.45, -0.9, -0.5],
    ]);
    expect(
        jointNames(rig(car)),
        unorderedEquals(
            ['Body', 'Wheel1_L', 'Wheel1_R', 'Wheel2_L', 'Wheel2_R']));

    // LKW/Bus: 3 Achsen → Karosserie + 6 Räder.
    final truck = vehicleMesh([
      [-0.5, 0.5, 0.3, 1.0, -1.0, 1.0],
      for (final (z0, z1) in [(0.5, 0.85), (-0.15, 0.2), (-0.85, -0.5)])
        ...[
          [-0.45, -0.25, 0.0, 0.35, z0, z1],
          [0.25, 0.45, 0.0, 0.35, z0, z1],
        ],
    ], [
      for (final (z0, z1) in [(0.5, 0.85), (-0.15, 0.2), (-0.85, -0.5)])
        ...[
          [-0.45, -0.25, z0, z1],
          [0.25, 0.45, z0, z1],
        ],
    ]);
    final truckJoints = jointNames(rig(truck));
    expect(truckJoints, hasLength(7));
    expect(truckJoints,
        containsAll(['Wheel1_L', 'Wheel2_R', 'Wheel3_L', 'Wheel3_R']));

    // Fahrrad/Motorrad: 2 Einzelräder in der Spur → 3 Gelenke.
    final bike = vehicleMesh([
      [-0.02, 0.02, 0.35, 1.0, -0.6, 0.6], // Rahmen
      [-0.08, 0.08, 0.8, 0.9, -0.05, 0.05], // Lenker (volle Breite)
      [-0.03, 0.03, 0.0, 0.6, 0.3, 0.95],
      [-0.03, 0.03, 0.0, 0.6, -0.95, -0.3],
    ], [
      [-0.03, 0.03, 0.3, 0.95],
      [-0.03, 0.03, -0.95, -0.3],
    ]);
    final bikeRigged = rig(bike);
    expect(jointNames(bikeRigged),
        unorderedEquals(['Body', 'Wheel1', 'Wheel2']));

    // Einrad: 1 zentrales Rad → 2 Gelenke.
    final unicycle = vehicleMesh([
      [-0.06, 0.06, 0.6, 1.0, -0.1, 0.1], // Sattel/Stange
      [-0.03, 0.03, 0.0, 0.7, -0.35, 0.35],
    ], [
      [-0.03, 0.03, -0.35, 0.35],
    ]);
    expect(jointNames(rig(unicycle)),
        unorderedEquals(['Body', 'Wheel1']));

    // Die Fahren-Testanimation dreht alle erkannten Räder.
    final preview = await parseGlbForPreview(bikeRigged);
    final clips = proceduralClipsFor(preview.rig!);
    expect(clips.map((c) => c.name), contains('Fahren'));
    final fahren = clips.firstWhere((c) => c.name == 'Fahren');
    // 2 Räder + Karosserie-Wippen.
    expect(fahren.poseAt(0.3), hasLength(3));
    preview.dispose();
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
    expect(preview.normals, hasLength(preview.positions.length));
    // Vertex-Farb-Mesh ohne Textur → kein Textur-Mapping-Pfad.
    expect(preview.texture, isNull);
    expect(preview.extent, greaterThan(0));
    // Vertex-Farben kommen aus COLOR_0, nicht aus dem Grau-Fallback.
    expect(preview.colors.toSet().length, greaterThan(1));
    preview.dispose();
  });

  test('Roblox-Prüfung liest die Zahlen aus einer echten GLB', () async {
    final mesh = buildVisualHullMesh(
      front: _testImage(),
      left: _solidImage(),
      back: _solidImage(),
      resolution: 10,
    );
    final glb = buildGlb(mesh);

    final facts = await readRobloxFacts(glb);
    expect(facts.triangles, mesh.indices.length ~/ 3);
    expect(facts.meshCount, 1);
    expect(facts.primitiveCount, 1);
    expect(facts.materialCount, lessThanOrEqualTo(1));
    // Das Vertex-Farb-Netz trägt kein Skelett und keine Textur.
    expect(facts.hasRig, isFalse);
    expect(facts.textures, isEmpty);

    final findings = checkRobloxFacts(facts, RobloxTarget.character);
    // Ohne UVs kann Roblox keine Textur auflegen – das ist der
    // erwartete Blocker für dieses schlichte Netz.
    expect(
        findings
            .where((f) => f.level == RobloxLevel.blocker)
            .map((f) => f.title)
            .join(' '),
        contains('UV'));
  });

  test('Jeder Figurtyp sagt, was der Prompt zeigen muss', () {
    // Ohne diese Regeln beschreibt die Prompt-KI Figuren, die sich
    // hinterher nicht riggen lassen – anliegende Arme, ein Umhang
    // über den Beinen, ein eingerollter Schwanz.
    for (final (value, _) in rigTypeOptions) {
      final rule = rigTypePromptRules[value];
      expect(rule, isNotNull, reason: value);
      expect(rule!.length, greaterThan(40), reason: value);
    }
    // Kein Eintrag ohne zugehörigen Typ.
    for (final key in rigTypePromptRules.keys) {
      expect(rigTypeOptions.map((o) => o.$1), contains(key));
    }
    // Die Regeln nennen das Wesentliche.
    expect(rigTypePromptRules['biped'], contains('Arme'));
    expect(rigTypePromptRules['quadruped'], contains('Vier Beine'));
    expect(rigTypePromptRules['insect'], contains('Sechs Beine'));
    expect(rigTypePromptRules['snake'], contains('ohne Gliedmaßen'));
    expect(rigTypePromptRules['vehicle'], contains('Räder'));
  });

  group('Blickrichtung aus der Geometrie', () {
    /// Baut eine stehende Figur als Punktwolke: Fuesse mit Zehen nach
    /// +z, ein Bauch, der nach vorn steht, und eine Kapuze, die nach
    /// hinten ueberhaengt. Genau diese Kombination hat die alte
    /// Messung umgedreht – sie verglich den Fuss mit dem Rumpf und den
    /// Kopf mit der Brust, und beide Bezugspunkte waren verschoben.
    Float32List figur({required double front}) {
      final points = <double>[];
      void add(double x, double y, double z) {
        points.addAll([x, y * 1.0, z * front]);
      }

      for (var i = 0; i < 400; i++) {
        final t = i / 400;
        // Fuesse 0-8 %: von der Ferse (-0.1) bis zur Zehe (+0.35).
        add(-0.3 + 0.6 * (i % 2), 0.02 + 0.05 * t, -0.1 + 0.45 * t);
        // Schienbein 12-28 %: schlank, mittig.
        add(-0.3 + 0.6 * (i % 2), 0.14 + 0.14 * t, -0.05 + 0.1 * t);
        // Bauch 45-70 %: dick und weit nach vorn.
        add(-0.5 + 1.0 * t, 0.45 + 0.25 * t, 0.55);
        // Kapuze 75-100 %: haengt nach hinten ueber.
        add(-0.3 + 0.6 * t, 0.75 + 0.25 * t, -0.5);
      }
      return Float32List.fromList(points);
    }

    test('Bauch und Kapuze drehen die Richtung nicht mehr um', () {
      // Zehen nach +z -> Gesicht nach +z, obwohl Bauch (+0.55) und
      // Kapuze (-0.5) in entgegengesetzte Richtungen ziehen.
      expect(estimateFrontSign([figur(front: 1)]), 1);
      // Dieselbe Figur gespiegelt: Zehen nach -z.
      expect(estimateFrontSign([figur(front: -1)]), -1);
    });
  });

}
