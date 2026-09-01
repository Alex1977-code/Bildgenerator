import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/roblox_check.dart';
import 'package:bildgenerator/services/roblox_rig.dart';

/// Ein Modell, das alle Regeln einhält – Grundlage der Einzelfälle.
RobloxFacts _good({
  int triangles = 8000,
  int materialCount = 1,
  int primitiveCount = 1,
  int meshCount = 1,
  int uvSets = 1,
  double uvMin = 0.0,
  double uvMax = 1.0,
  int openEdges = 0,
  List<RobloxTexture> textures = const [
    RobloxTexture(1024, 1024, 'image/png')
  ],
  int jointSets = 1,
  int boneCount = 12,
  int maxInfluences = 4,
  int scaledBones = 0,
  int rotatedBones = 0,
  bool rootAtOrigin = true,
  bool rootWeighted = false,
  List<int>? meshTriangles,
  int maxPrimitivesPerMesh = 1,
  List<double> size = const [1.4, 5.0, 1.1],
  int reversedEdges = 0,
  double signedVolume = 0.05,
  double volumeRatio = 0.02,
  int degenerateTriangles = 0,
  List<String>? boneNames,
}) =>
    RobloxFacts(
      // Ein regelkonformes Modell trägt die R15-Namen.
      boneNames: boneNames ?? robloxR15Bones,
      meshTriangles: meshTriangles ?? [triangles],
      maxPrimitivesPerMesh: maxPrimitivesPerMesh,
      size: size,
      reversedEdges: reversedEdges,
      signedVolume: signedVolume,
      volumeRatio: volumeRatio,
      degenerateTriangles: degenerateTriangles,
      triangles: triangles,
      meshCount: meshCount,
      primitiveCount: primitiveCount,
      materialCount: materialCount,
      uvSets: uvSets,
      uvMin: uvMin,
      uvMax: uvMax,
      openEdges: openEdges,
      textures: textures,
      jointSets: jointSets,
      boneCount: boneCount,
      maxInfluences: maxInfluences,
      scaledBones: scaledBones,
      rotatedBones: rotatedBones,
      rootAtOrigin: rootAtOrigin,
      rootWeighted: rootWeighted,
      rootName: 'root',
    );

List<RobloxFinding> _blockers(List<RobloxFinding> findings) =>
    findings.where((f) => f.level == RobloxLevel.blocker).toList();

String _text(List<RobloxFinding> findings) =>
    findings.map((f) => '${f.title} ${f.detail}').join(' | ');

void main() {
  group('Roblox-Regeln beurteilen', () {
    test('Ein regelkonformes Modell hat keine Blocker', () {
      final findings =
          checkRobloxFacts(_good(), RobloxTarget.character);
      expect(_blockers(findings), isEmpty, reason: _text(findings));
      expect(findings.where((f) => f.level == RobloxLevel.warning), isEmpty);
    });

    test('Über 20.000 Dreiecke lehnt der Importer ab', () {
      final findings = checkRobloxFacts(
          _good(triangles: 240000), RobloxTarget.character);
      final blocker = _blockers(findings).first;
      expect(blocker.title, contains('240.000'));
      expect(blocker.detail, contains('20.000'));
      expect(blocker.detail, contains('Decimate'));
    });

    test('Zwischen Ziel und Grenze gibt es nur eine Warnung', () {
      final findings =
          checkRobloxFacts(_good(triangles: 15000), RobloxTarget.character);
      expect(_blockers(findings), isEmpty);
      expect(
          findings
              .where((f) => f.level == RobloxLevel.warning)
              .single
              .title,
          contains('15.000'));
    });

    test('Für Accessoires gilt die 4.000er-Grenze', () {
      final findings =
          checkRobloxFacts(_good(triangles: 8000), RobloxTarget.accessory);
      expect(_blockers(findings).first.detail, contains('4.000'));
      // Dasselbe Modell wäre als Figur in Ordnung.
      expect(
          _blockers(checkRobloxFacts(
              _good(triangles: 8000), RobloxTarget.character)),
          isEmpty);
    });

    test('Mehrere Materialien in EINEM Mesh sind ein Blocker', () {
      final findings = checkRobloxFacts(
          _good(materialCount: 3, primitiveCount: 3,
              maxPrimitivesPerMesh: 3),
          RobloxTarget.character);
      expect(_text(_blockers(findings)), contains('Atlas'));
    });

    test('Ein Material je Mesh ist auch bei mehreren Meshes in Ordnung',
        () {
      // Drei Meshes mit je einem eigenen Material – der Importer legt
      // daraus drei MeshParts an, jede mit genau einem Material.
      final findings = checkRobloxFacts(
          _good(
              triangles: 18000,
              meshTriangles: [6000, 6000, 6000],
              meshCount: 3,
              materialCount: 3,
              primitiveCount: 3,
              maxPrimitivesPerMesh: 1),
          RobloxTarget.character);
      expect(_blockers(findings), isEmpty, reason: _text(findings));
    });

    test('Die Dreiecksgrenze gilt je Mesh, nicht für die Summe', () {
      // 5 × 6.000 = 30.000 gesamt, aber jedes Mesh bleibt unter 20.000.
      final ok = checkRobloxFacts(
          _good(
              triangles: 30000,
              meshTriangles: [6000, 6000, 6000, 6000, 6000],
              meshCount: 5),
          RobloxTarget.character);
      expect(_blockers(ok), isEmpty, reason: _text(ok));
      expect(_text(ok), contains('Größtes Mesh: 6.000'));
      expect(_text(ok), contains('30.000'));

      // Umgekehrt: ein einzelnes zu großes Teil faellt auf, obwohl die
      // Summe klein wirkt.
      final bad = checkRobloxFacts(
          _good(
              triangles: 21500,
              meshTriangles: [21000, 500],
              meshCount: 2),
          RobloxTarget.character);
      expect(_text(_blockers(bad)), contains('21.000'));
    });

    test('Offene Kanten sind eine Warnung, kein Blocker', () {
      final findings =
          checkRobloxFacts(_good(openEdges: 42), RobloxTarget.character);
      expect(_blockers(findings), isEmpty);
      expect(_text(findings), contains('Offene Kanten: 42'));
    });

    test('Fehlende UVs und mehrere UV-Sätze blockieren', () {
      expect(
          _text(_blockers(
              checkRobloxFacts(_good(uvSets: 0), RobloxTarget.character))),
          contains('UV'));
      expect(
          _text(_blockers(
              checkRobloxFacts(_good(uvSets: 2), RobloxTarget.character))),
          contains('UV-Sätze: 2'));
    });

    test('UVs außerhalb 0–1 sind eine Warnung', () {
      final findings = checkRobloxFacts(
          _good(uvMin: -0.4, uvMax: 2.5), RobloxTarget.character);
      expect(_blockers(findings), isEmpty);
      expect(_text(findings), contains('außerhalb 0–1'));
    });

    test('Texturen über 1024 px blockieren', () {
      final findings = checkRobloxFacts(
          _good(textures: const [RobloxTexture(2048, 2048, 'image/png')]),
          RobloxTarget.character);
      expect(_text(_blockers(findings)), contains('2048'));
    });

    test('Rig-Regeln: Einflüsse, Transformationen, Wurzelknochen', () {
      expect(
          _text(_blockers(checkRobloxFacts(
              _good(maxInfluences: 6), RobloxTarget.character))),
          contains('6 Bones je Vertex'));
      expect(
          _text(_blockers(checkRobloxFacts(
              _good(jointSets: 2), RobloxTarget.character))),
          contains('Bones je Vertex'));
      expect(
          _text(_blockers(checkRobloxFacts(
              _good(scaledBones: 2, rotatedBones: 1),
              RobloxTarget.character))),
          contains('Scale 1,1,1'));
      expect(
          _text(_blockers(checkRobloxFacts(
              _good(rootAtOrigin: false), RobloxTarget.character))),
          contains('Ursprung'));
      expect(
          _text(_blockers(checkRobloxFacts(
              _good(rootWeighted: true), RobloxTarget.character))),
          contains('Gewichte'));
    });

    test('Ohne Skelett gibt es keine Rig-Blocker, nur den Hinweis', () {
      final findings = checkRobloxFacts(
          _good(boneCount: 0, maxInfluences: 0, jointSets: 0),
          RobloxTarget.character);
      expect(_blockers(findings), isEmpty);
      expect(_text(findings), contains('No Rig'));
    });

    test('R15-Benennung: fehlende Gelenke werden aufgezählt', () {
      // Ein Rig mit Mixamo-Namen kennt keines der 15 Gelenke.
      final mixamo = checkRobloxFacts(
          _good(boneNames: const [
            'mixamorig:Hips',
            'mixamorig:Spine',
            'mixamorig:LeftArm'
          ]),
          RobloxTarget.character);
      final text = _text(mixamo);
      expect(text, contains('nicht nach R15 benannt'));
      expect(text, contains('Für Roblox vorbereiten'));

      // Teilweise benannt: die Fehlenden stehen namentlich da.
      final partial = checkRobloxFacts(
          _good(boneNames: const [
            'HumanoidRootNode',
            'LowerTorso',
            'UpperTorso',
            'Head',
            'LeftUpperArm',
            'LeftLowerArm',
            'LeftHand',
            'RightUpperArm',
            'RightLowerArm',
            'RightHand',
          ]),
          RobloxTarget.character);
      expect(_text(partial), contains('LeftUpperLeg'));
      expect(_text(partial), contains('10 von 16'));

      // Vollständig benannt: grüner Haken, keine Warnung.
      final full = checkRobloxFacts(_good(), RobloxTarget.character);
      expect(
          full
              .firstWhere((f) => f.title == 'Knochen nach R15 benannt')
              .level,
          RobloxLevel.ok);
    });

    test('Die T-Pose- und Formathinweise stehen immer in der Liste', () {
      final findings = checkRobloxFacts(_good(), RobloxTarget.character);
      final text = _text(findings);
      expect(text, contains('T-Pose'));
      expect(text, contains('R15'));
      expect(text, contains('.fbx'));
    });

    test('Backfaces: uneinheitliche Wicklung und innen liegende Normalen',
        () {
      final mixed =
          checkRobloxFacts(_good(reversedEdges: 12), RobloxTarget.character);
      expect(_text(mixed), contains('Recalculate Outside'));
      final inverted = checkRobloxFacts(
          _good(signedVolume: -0.05), RobloxTarget.character);
      expect(_text(inverted), contains('nach innen'));
      // Ein sauberes Modell bekommt den grünen Haken.
      expect(
          checkRobloxFacts(_good(), RobloxTarget.character)
              .where((f) => f.title == 'Normalen nach außen')
              .single
              .level,
          RobloxLevel.ok);
    });

    test('Nullstärke: eine Platte wird erkannt', () {
      final sheet = checkRobloxFacts(
          _good(size: const [3.5, 5.0, 0.007], volumeRatio: 0.00001),
          RobloxTarget.character);
      expect(_text(sheet), contains('Solidify'));
      expect(_text(sheet), contains('ohne Dicke'));
      // Ein Körper mit Volumen nicht.
      expect(_text(checkRobloxFacts(_good(), RobloxTarget.character)),
          contains('Hat Volumen'));
    });

    test('Degenerierte Dreiecke werden gemeldet', () {
      expect(
          _text(checkRobloxFacts(
              _good(degenerateTriangles: 7), RobloxTarget.character)),
          contains('Degenerate Dissolve'));
    });

    test('Größe: eine Einheit ist ein Stud', () {
      // Gemessen an einem echten Import: Der Importer rechnet die
      // Datei in Meter um und setzt einen Meter gleich einem Stud.
      // Die Höhe in Einheiten ist damit die Höhe in Studs.
      final findings = checkRobloxFacts(
          _good(size: const [1.4, 5.0, 1.1]), RobloxTarget.character);
      final scale =
          findings.firstWhere((f) => f.title.startsWith('Größe:'));
      expect(scale.title, contains('5.00 Studs'));
      expect(scale.level, RobloxLevel.ok);

      // Genau der Fall, der beim ersten Import danebenging: 1,2
      // Einheiten kamen kniehoch an.
      final klein = checkRobloxFacts(
          _good(size: const [1.5, 1.2, 0.6]), RobloxTarget.character);
      final zuKlein =
          klein.firstWhere((f) => f.title.startsWith('Größe:'));
      expect(zuKlein.level, RobloxLevel.warning);
      expect(zuKlein.detail, contains('Für Roblox vorbereiten'));

      // Ein Hut misst rund einen Stud – als Accessoire in Ordnung.
      final hut = checkRobloxFacts(
          _good(size: const [1.0, 1.0, 1.0]), RobloxTarget.accessory);
      expect(hut.firstWhere((f) => f.title.startsWith('Größe:')).level,
          RobloxLevel.ok);
    });

    test('Quad- und FBX-Grenzen der Prüfung stehen in der Liste', () {
      final text = _text(checkRobloxFacts(_good(), RobloxTarget.character));
      expect(text, contains('Quad-Topologie ist hier nicht messbar'));
      expect(text, contains('gilt für die GLB'));
      expect(text, contains('Apply → All Transforms'));
    });

    test('Quad-Budget: Roblox zählt Dreiecke, der Anbieter Polygone', () {
      // 10.000 Dreiecke = 5.000 Vierecke; ohne Quads bleibt es gleich.
      expect(robloxPolygonBudget(10000, quad: true), 5000);
      expect(robloxPolygonBudget(10000, quad: false), 10000);
      expect(robloxPolygonBudget(4000, quad: true), 2000);
    });

    test('Accessoire: Skelett ist eine Warnung, kein Skelett richtig',
        () {
      final rigged =
          checkRobloxFacts(_good(triangles: 3000), RobloxTarget.accessory);
      final text = _text(rigged);
      expect(_blockers(rigged), isEmpty);
      expect(text, contains('Skelett in einem Accessoire'));
      expect(text, contains('Cage'));

      final rigid = checkRobloxFacts(
          _good(triangles: 3000, boneCount: 0, maxInfluences: 0,
              jointSets: 0),
          RobloxTarget.accessory);
      expect(
          rigid
              .where((f) => f.title == 'Ohne Skelett')
              .single
              .level,
          RobloxLevel.ok);
      // Ohne Skelett steht der T-Pose-Hinweis nicht in der Liste.
      expect(_text(rigid), isNot(contains('T-Pose')));
    });

    test('Accessoires bekommen den Hinweis auf Handle und Attachment',
        () {
      final text = _text(checkRobloxFacts(
          _good(triangles: 3000, boneCount: 0, maxInfluences: 0,
              jointSets: 0),
          RobloxTarget.accessory));
      expect(text, contains('Attachment'));
      expect(text, contains('Marketplace'));
      // Für eine Figur ist der Hinweis nicht dabei.
      expect(_text(checkRobloxFacts(_good(), RobloxTarget.character)),
          isNot(contains('Attachment')));
    });

    test('Die Kurzfassung nennt alle harten Grenzen', () {
      final text = robloxRulesSummary(RobloxTarget.character);
      expect(text, contains('20.000'));
      expect(text, contains('1024'));
      expect(text, contains('4 Bones je Vertex'));
      expect(robloxRulesSummary(RobloxTarget.accessory), contains('4.000'));
    });
  });

  group('Bildmaße aus den Rohbytes', () {
    test('PNG-Kopf wird gelesen', () {
      final bytes = Uint8List(32);
      bytes.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      ByteData.sublistView(bytes)
        ..setUint32(16, 1024)
        ..setUint32(20, 512);
      final size = imageDimensions(bytes);
      expect(size?.width, 1024);
      expect(size?.height, 512);
      expect(size?.mimeType, 'image/png');
    });

    test('JPEG-SOF0 wird gefunden', () {
      // SOI, APP0-Segment (Länge 4), dann SOF0 mit 800×600.
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, //
        0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, //
        0xFF, 0xC0, 0x00, 0x11, 0x08, //
        0x02, 0x58, // Höhe 600
        0x03, 0x20, // Breite 800
        0x03, 0x01, 0x11, 0x00,
      ]);
      final size = imageDimensions(bytes);
      expect(size?.width, 800);
      expect(size?.height, 600);
      expect(size?.mimeType, 'image/jpeg');
    });

    test('Unbekannte Bytes liefern null', () {
      expect(imageDimensions(Uint8List.fromList(utf8.encode('kein Bild'))),
          isNull);
    });
  });
}
