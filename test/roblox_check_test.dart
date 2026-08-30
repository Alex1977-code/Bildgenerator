import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/roblox_check.dart';

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
}) =>
    RobloxFacts(
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

    test('Mehrere Materialien sind ein Blocker mit Atlas-Hinweis', () {
      final findings = checkRobloxFacts(
          _good(materialCount: 3, primitiveCount: 3),
          RobloxTarget.character);
      expect(_text(_blockers(findings)), contains('Atlas'));
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

    test('Die T-Pose- und Formathinweise stehen immer in der Liste', () {
      final findings = checkRobloxFacts(_good(), RobloxTarget.character);
      final text = _text(findings);
      expect(text, contains('T-Pose'));
      expect(text, contains('R15'));
      expect(text, contains('.fbx'));
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
