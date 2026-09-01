import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/roblox_check.dart';
import 'package:bildgenerator/services/roblox_preflight.dart';
import 'package:bildgenerator/services/roblox_specs_config.dart';

/// Ein makelloses Modell als Ausgangspunkt – jeder Test verschlechtert
/// genau eine Sache.
RobloxFacts _gut({
  int triangles = 1000,
  int meshCount = 1,
  int maxPrimitivesPerMesh = 1,
  int uvSets = 1,
  double uvMin = 0.0,
  double uvMax = 1.0,
  int openEdges = 0,
  int reversedEdges = 0,
  double signedVolume = 0.6,
  double volumeRatio = 0.6,
  List<double> size = const [1.0, 1.0, 1.0],
  List<RobloxTexture> textures = const [],
}) =>
    RobloxFacts(
      triangles: triangles,
      meshCount: meshCount,
      primitiveCount: 1,
      materialCount: 1,
      uvSets: uvSets,
      uvMin: uvMin,
      uvMax: uvMax,
      openEdges: openEdges,
      textures: textures,
      meshTriangles: [triangles],
      maxPrimitivesPerMesh: maxPrimitivesPerMesh,
      size: size,
      reversedEdges: reversedEdges,
      signedVolume: signedVolume,
      volumeRatio: volumeRatio,
    );

const _keineNamen = GlbNodeNames(
  attachments: [],
  cages: [],
  meshNodes: ['Mesh'],
  transformedMeshNodes: [],
);

void main() {
  final specs = fallbackSpecs();
  final zubehoer = specs['rigidAccessory']!;
  final prop = specs['genericMesh']!;

  PreflightReport bericht(RobloxFacts facts,
          {GlbNodeNames names = _keineNamen, AssetSpec? spec}) =>
      buildPreflightReport(
          facts: facts,
          names: names,
          spec: spec ?? zubehoer,
          specs: specs);

  PreflightIssue? finde(PreflightReport r, String id) {
    for (final issue in r.issues) {
      if (issue.id == id) return issue;
    }
    return null;
  }

  group('Zwei Stufen', () {
    test('Ein sauberes Modell blockiert nicht', () {
      final r = bericht(_gut(), spec: prop);
      expect(r.blocked, isFalse);
      expect(r.errors, isEmpty);
      expect(r.summary, 'Alles in Ordnung.');
    });

    test('Ein gerissenes Budget blockiert', () {
      final r = bericht(_gut(triangles: 9000));
      expect(r.blocked, isTrue);
      expect(finde(r, 'budget')!.severity, PreflightSeverity.fehler);
      expect(finde(r, 'budget')!.title, contains('9000 von 4000'));
      expect(finde(r, 'budget')!.reason, contains('5000 Dreiecke zu viel'));
      expect(r.summary, contains('blockiert'));
    });

    test('Ein knappes Budget warnt nur', () {
      final r = bericht(_gut(triangles: 3900));
      expect(r.blocked, isFalse);
      expect(finde(r, 'budget')!.severity, PreflightSeverity.warnung);
      expect(r.summary, contains('Export ist frei'));
    });

    test('Warnungen allein blockieren nie', () {
      final r = bericht(_gut(triangles: 3900, size: const [4, 0.2, 4]));
      expect(r.warnings, isNotEmpty);
      expect(r.blocked, isFalse);
    });
  });

  group('Reihenfolge', () {
    test('Attachments und Budget stehen ganz oben', () {
      final r = bericht(_gut(triangles: 9000, openEdges: 12));
      expect(r.issues.first.id, startsWith('attachment'));
      expect(r.issues[1].id, 'budget');
      // Die Feinheiten kommen danach.
      final ngonIndex = r.issues.indexWhere((i) => i.id == 'ngons');
      expect(ngonIndex, greaterThan(3));
    });

    test('Der Bericht führt jeden Fehler mit Begründung', () {
      final r = bericht(_gut(triangles: 9000, openEdges: 5));
      for (final issue in r.errors) {
        expect(issue.reason, isNotEmpty, reason: issue.id);
        expect(issue.reason.length, greaterThan(40), reason: issue.id);
      }
    });
  });

  group('Die einzelnen Prüfungen', () {
    test('Offene Kanten sind ein Fehler mit Auto-Fix', () {
      final issue = finde(bericht(_gut(openEdges: 7)), 'wasserdicht')!;
      expect(issue.severity, PreflightSeverity.fehler);
      expect(issue.fix, PreflightFix.huelleSchliessen);
      expect(issue.title, contains('7 offene'));
    });

    test('Gegenläufige Wicklung und umgestülpte Normalen', () {
      expect(finde(bericht(_gut(reversedEdges: 3)), 'wicklung')!.severity,
          PreflightSeverity.fehler);
      expect(finde(bericht(_gut(signedVolume: -0.5)), 'normalen')!.fix,
          PreflightFix.huelleSchliessen);
    });

    test('Ein Blatt ohne Dicke ist ein Fehler', () {
      final issue = finde(bericht(_gut(volumeRatio: 0.0)), 'volumen')!;
      expect(issue.severity, PreflightSeverity.fehler);
      expect(issue.reason, contains('Solidify'));
    });

    test('Ein zu leerer Hüllquader warnt', () {
      // Volumen 0,05 in einem Quader von 4×0,5×4 = 8 → 0,6 %.
      final r = bericht(_gut(signedVolume: 0.05, size: const [4, 0.5, 4]));
      final issue = finde(r, 'huellquader')!;
      expect(issue.severity, PreflightSeverity.warnung);
      expect(issue.title, contains('%'));
      // Roblox beurteilt es an der Ansicht – das steht dabei.
      expect(issue.reason, contains('Ansicht'));
    });

    test('Texturen: über der Zielgröße warnt, über der harten Grenze '
        'blockiert', () {
      final knapp = finde(
          bericht(_gut(textures: const [RobloxTexture(2048, 2048, 'png')])),
          'textur')!;
      expect(knapp.severity, PreflightSeverity.warnung);
      expect(knapp.fix, PreflightFix.texturVerkleinern);

      final zuviel = finde(
          bericht(_gut(textures: const [RobloxTexture(4096, 4096, 'png')])),
          'textur')!;
      expect(zuviel.severity, PreflightSeverity.fehler);
    });

    test('UVs außerhalb von 0–1 und mehrere UV-Sätze', () {
      final raum = finde(bericht(_gut(uvMax: 3.0)), 'uv_raum')!;
      expect(raum.severity, PreflightSeverity.fehler);
      expect(raum.reason, contains('3.00'));
      final saetze = finde(bericht(_gut(uvSets: 2)), 'uv_saetze')!;
      expect(saetze.severity, PreflightSeverity.fehler);
      // Keine kaputte Zeichenkette: die Zahl muss ausgerechnet sein.
      expect(saetze.title, '2 UV-Sätze');
    });

    test('Mehrere Materialien in einem Mesh blockieren', () {
      expect(
          finde(bericht(_gut(maxPrimitivesPerMesh: 3)), 'material')!.severity,
          PreflightSeverity.fehler);
    });

    test('UV- und Material-Befunde bieten die Textur-Pipeline an', () {
      // Der Preflight nannte diese drei Punkte lange nur. Seit der
      // Textur-Pipeline gibt es dafür einen Knopf – und die Oberfläche
      // baut ihn allein aus dieser Angabe.
      for (final (fakten, id) in [
        (_gut(uvSets: 2), 'uv_saetze'),
        (_gut(uvMax: 3.0), 'uv_raum'),
        (_gut(maxPrimitivesPerMesh: 3), 'material'),
      ]) {
        expect(finde(bericht(fakten), id)!.fix, PreflightFix.texturPipeline,
            reason: '$id ohne Reparatur');
      }
    });

    test('die Begründung sagt, wo die Pipeline aufhört', () {
      // Ein Knopf, der schweigend nichts tut, ist schlimmer als
      // keiner: Beide Fälle stehen deshalb im Text.
      expect(finde(bericht(_gut(uvMax: 3.0)), 'uv_raum')!.reason,
          contains('Kachelgrenze'));
      expect(finde(bericht(_gut(maxPrimitivesPerMesh: 3)), 'material')!.reason,
          contains('Textur-Atlas'));
    });

    test('Ein Accessoire muss ein einziges Mesh sein, ein Prop nicht',
        () {
      expect(finde(bericht(_gut(meshCount: 3)), 'ein_mesh')!.severity,
          PreflightSeverity.fehler);
      expect(finde(bericht(_gut(meshCount: 3), spec: prop), 'ein_mesh'),
          isNull);
    });

    test('Ein Mesh über 20.000 Dreiecken blockiert immer', () {
      final r = bericht(_gut(triangles: 25000), spec: prop);
      expect(finde(r, 'mesh_budget')!.severity, PreflightSeverity.fehler);
    });
  });

  group('Attachments', () {
    test('Ohne Attachment nur eine Warnung – das Lua-Skript legt es an',
        () {
      final issue = finde(bericht(_gut()), 'attachments')!;
      expect(issue.severity, PreflightSeverity.warnung);
      expect(issue.reason, contains('Lua-Skript'));
    });

    test('Falsch benannt ist ein Fehler', () {
      final r = bericht(_gut(),
          names: const GlbNodeNames(
              attachments: ['HatAttachment'],
              cages: [],
              meshNodes: ['Mesh'],
              transformedMeshNodes: []));
      final issue = finde(r, 'attachments_namen')!;
      expect(issue.severity, PreflightSeverity.fehler);
      expect(issue.reason, contains('_Att'));
    });

    test('Zu viele Attachments sind ein Fehler', () {
      final r = bericht(_gut(),
          names: const GlbNodeNames(
              attachments: ['Hat_Att', 'Hair_Att'],
              cages: [],
              meshNodes: ['Mesh'],
              transformedMeshNodes: []));
      expect(finde(r, 'attachments_zahl')!.severity,
          PreflightSeverity.fehler);
    });

    test('Genau eines richtig benannt ist in Ordnung', () {
      final r = bericht(_gut(),
          names: const GlbNodeNames(
              attachments: ['Hat_Att'],
              cages: [],
              meshNodes: ['Mesh'],
              transformedMeshNodes: []));
      expect(finde(r, 'attachments')!.severity, PreflightSeverity.ok);
    });

    test('Ein Prop braucht keine Attachments', () {
      expect(finde(bericht(_gut(), spec: prop), 'attachments'), isNull);
    });
  });

  group('Was die Datei nicht hergibt', () {
    test('N-Gons und Studio-Eigenschaften stehen als Hinweis drin', () {
      final r = bericht(_gut());
      expect(finde(r, 'ngons')!.severity, PreflightSeverity.hinweis);
      final studio = finde(r, 'studio_eigenschaften')!;
      expect(studio.severity, PreflightSeverity.hinweis);
      expect(studio.reason, contains('Plastic'));
      expect(studio.reason, contains('VertexColor'));
      expect(studio.reason, contains('Lua-Skript'));
    });

    test('Fehlende Cages sind ein Hinweis, kein Fehler', () {
      final issue = finde(bericht(_gut()), 'cages')!;
      expect(issue.severity, PreflightSeverity.hinweis);
      expect(issue.reason, contains('Vorlagen'));
    });

    test('Vorhandene Cages werden erkannt', () {
      final r = bericht(_gut(),
          names: const GlbNodeNames(
              attachments: [],
              cages: ['Head_Geo_OuterCage'],
              meshNodes: ['Mesh'],
              transformedMeshNodes: []));
      expect(finde(r, 'cages')!.severity, PreflightSeverity.ok);
    });
  });

  group('Transformationen', () {
    test('Ein Mesh-Knoten mit Drehung warnt und bietet die Reparatur',
        () {
      final r = bericht(_gut(),
          names: const GlbNodeNames(
              attachments: [],
              cages: [],
              meshNodes: ['Hut'],
              transformedMeshNodes: ['Hut']));
      final issue = finde(r, 'transform')!;
      expect(issue.severity, PreflightSeverity.warnung);
      expect(issue.fix, PreflightFix.rigHerrichten);
    });

    test('Eine Einheitsmatrix zählt nicht als Transformation', () {
      final json = {
        'nodes': [
          {
            'name': 'A',
            'mesh': 0,
            'matrix': [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
          },
          {'name': 'B', 'mesh': 0, 'scale': [1, 1, 1]},
          {'name': 'C', 'mesh': 0, 'rotation': [0, 0, 0, 1]},
          {'name': 'D', 'mesh': 0, 'scale': [2, 1, 1]},
          {'name': 'Hat_Att'},
          {'name': 'Head_Geo_OuterCage'},
        ],
      };
      final names = readGlbNodeNames(_fakeGlb(json));
      expect(names.transformedMeshNodes, ['D']);
      expect(names.meshNodes, ['A', 'B', 'C', 'D']);
      expect(names.attachments, ['Hat_Att']);
      expect(names.cages, ['Head_Geo_OuterCage']);
    });

    test('Eine kaputte Datei liefert leere Listen statt eines Absturzes',
        () {
      final names = readGlbNodeNames(Uint8List.fromList([1, 2, 3]));
      expect(names.meshNodes, isEmpty);
      expect(names.attachments, isEmpty);
    });
  });

  group('Ausgabe', () {
    test('Der Text nennt jede Stufe', () {
      final text = preflightAsText(
          bericht(_gut(triangles: 9000, openEdges: 3)), zubehoer);
      expect(text, contains('FEHLER'));
      expect(text, contains('HINWEIS'));
      expect(text, contains('Starres Accessoire'));
    });

    test('Das JSON lässt sich wieder lesen', () {
      final json = jsonDecode(
          preflightAsJson(bericht(_gut(triangles: 9000)), zubehoer));
      expect(json['blocked'], isTrue);
      expect(json['budget'], 4000);
      expect(json['triangles'], 9000);
      final issues = json['issues'] as List;
      expect(issues.first['id'], startsWith('attachment'));
      expect(
          issues.any((i) => i['fix'] == 'reduzieren'), isTrue);
    });
  });
}

/// Eine GLB-Hülle um ein beliebiges JSON – genug, damit splitGlb sie
/// liest.
Uint8List _fakeGlb(Map<String, dynamic> json) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final pad = (4 - jsonBytes.length % 4) % 4;
  final chunk = Uint8List(jsonBytes.length + pad)
    ..setAll(0, jsonBytes)
    ..fillRange(jsonBytes.length, jsonBytes.length + pad, 0x20);
  final out = BytesBuilder();
  final header = ByteData(12);
  header.setUint32(0, 0x46546C67, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, 12 + 8 + chunk.length, Endian.little);
  out.add(header.buffer.asUint8List());
  final chunkHeader = ByteData(8);
  chunkHeader.setUint32(0, chunk.length, Endian.little);
  chunkHeader.setUint32(4, 0x4E4F534A, Endian.little);
  out.add(chunkHeader.buffer.asUint8List());
  out.add(chunk);
  return out.toBytes();
}
