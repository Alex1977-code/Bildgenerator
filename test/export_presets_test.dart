import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/export_presets.dart';
import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eine Figur, die deutlich neben dem Nullpunkt steht: von y = 1 bis
/// y = 3, in x von 2 bis 3.
LocalMesh _figur({double dx = 2.5, double dy = 2.0}) {
  final m = LocalMesh();
  final ids = <List<int>>[];
  const rings = 10, sectors = 12;
  for (var i = 0; i <= rings; i++) {
    final phi = (i / rings) * math.pi;
    final row = <int>[];
    for (var j = 0; j <= sectors; j++) {
      final th = (j / sectors) * 2 * math.pi;
      row.add(m.addVertex(
        dx + 0.5 * math.sin(phi) * math.cos(th),
        dy + 1.0 * math.cos(phi) * -1,
        0.35 * math.sin(phi) * math.sin(th),
        j / sectors,
        i / rings,
      ));
    }
    ids.add(row);
  }
  for (var i = 0; i < rings; i++) {
    for (var j = 0; j < sectors; j++) {
      m.addQuad(ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]);
    }
  }
  return m;
}

({double minX, double maxX, double minY, double maxY}) _bounds(
    Float32List p) {
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (var i = 0; i + 2 < p.length; i += 3) {
    minX = math.min(minX, p[i]);
    maxX = math.max(maxX, p[i]);
    minY = math.min(minY, p[i + 1]);
    maxY = math.max(maxY, p[i + 1]);
  }
  return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

void main() {
  group('Presets', () {
    test('jedes Preset sagt, wofür es da ist', () {
      expect(exportPresets.length, 3);
      for (final preset in exportPresets) {
        expect(preset.purpose.length, greaterThan(40),
            reason: '${preset.id} erklärt sich nicht');
        expect(preset.extension, isNotEmpty);
        expect(preset.mimeType, contains('/'));
      }
      // Kennungen sind eindeutig – die Oberfläche wählt darüber aus.
      expect(exportPresets.map((p) => p.id).toSet().length, 3);
    });

    test('OBJ verspricht kein Skelett', () {
      expect(presetObjStatic.carriesRig, isFalse);
      expect(presetGlbTextured.carriesRig, isTrue);
      expect(presetFbxRigged.carriesRig, isTrue);
    });

    test('nur GLB trägt die Textur in der Datei', () {
      expect(presetGlbTextured.textureInFile, isTrue);
      expect(presetFbxRigged.textureInFile, isFalse);
      expect(presetFbxRigged.textureSidecar, isTrue);
    });

    test('Vorschlag hängt am Skelett und am Ziel', () {
      expect(recommendedPreset(hasRig: true, forRoblox: true).format,
          ExportFormat.fbx);
      expect(recommendedPreset(hasRig: true, forRoblox: false).format,
          ExportFormat.glb);
      expect(recommendedPreset(hasRig: false, forRoblox: true).format,
          ExportFormat.obj);
    });

    test('unbekannte Kennung fällt auf GLB zurück', () {
      expect(exportPresetById('gibtsnicht').id, presetGlbTextured.id);
      expect(exportPresetById(null).id, presetGlbTextured.id);
      expect(exportPresetById('obj_prop').id, presetObjStatic.id);
    });
  });

  group('Namensgebung', () {
    test('Umlaute werden ausgeschrieben, nicht verschluckt', () {
      expect(exportBaseName('Kapuzenpullover für Größe M'),
          'Kapuzenpullover_fuer_Groesse_M');
    });

    test('ein ganzer Prompt wird zu einem brauchbaren Namen', () {
      // Genau der Fall, an dem die App schon einmal hängengeblieben
      // ist: Der Titel eines Laufs ist der komplette Prompt.
      final name = exportBaseName(
          'A stylized low-poly sword, game-ready, 4000 triangles, '
          'watertight, front view, no background');
      expect(name.length, lessThanOrEqualTo(40));
      expect(name, isNot(contains(',')));
      expect(name, isNot(endsWith('_')));
      expect(name, startsWith('A_stylized_low_poly_sword'));
    });

    test('leerer Titel bekommt den Ersatznamen', () {
      expect(exportBaseName('   '), 'modell');
      expect(exportBaseName('!!!'), 'modell');
      expect(exportBaseName('', fallback: 'figur'), 'figur');
    });

    test('der Zeitstempel steht hinten, damit die Sortierung stimmt', () {
      final name = exportFileName(
          presetFbxRigged, 'Ritter', now: DateTime(2026, 3, 7, 9, 5));
      expect(name, 'Ritter_20260307-0905.fbx');
      // Alphabetisch sortiert ist damit auch zeitlich sortiert.
      final spaeter = exportFileName(
          presetFbxRigged, 'Ritter', now: DateTime(2026, 3, 7, 14, 30));
      expect(name.compareTo(spaeter), lessThan(0));
    });

    test('Zusatz landet vor dem Zeitstempel', () {
      expect(
          exportFileName(presetFbxRigged, 'Ritter',
              now: DateTime(2026, 3, 7, 9, 5), suffix: 'textur'),
          'Ritter_textur_20260307-0905.fbx');
    });
  });

  group('Vorbereitung ohne Skelett', () {
    test('Nullpunkt landet mittig unter dem Modell', () async {
      final glb = buildGlb(_figur());
      final vorher = await parseGlbForPreview(glb);
      final b0 = _bounds(vorher.positions);
      vorher.dispose();
      expect(b0.minY, greaterThan(0.5), reason: 'Testfigur steht zu tief');

      final result = prepareForExport(glb);
      final nachher = await parseGlbForPreview(result.glb);
      final b1 = _bounds(nachher.positions);
      nachher.dispose();

      expect(b1.minY, closeTo(0, 1e-4));
      expect((b1.minX + b1.maxX) / 2, closeTo(0, 1e-4));
      // Die Größe bleibt, nur die Lage ändert sich.
      expect(b1.maxY - b1.minY, closeTo(b0.maxY - b0.minY, 1e-4));
      expect(result.report.changed, isTrue);
    });

    test('Mitte-Modus legt den Nullpunkt in die Mitte', () async {
      final result =
          prepareForExport(buildGlb(_figur()), pivot: PivotMode.mitte);
      final mesh = await parseGlbForPreview(result.glb);
      final b = _bounds(mesh.positions);
      mesh.dispose();
      expect((b.minY + b.maxY) / 2, closeTo(0, 1e-4));
    });

    test('„unverändert" fasst nichts an', () {
      final glb = buildGlb(_figur());
      final result =
          prepareForExport(glb, pivot: PivotMode.unveraendert);
      expect(result.glb.length, glb.length);
      expect(result.report.changed, isFalse);
    });

    test('ein zweiter Durchlauf ändert nichts mehr', () async {
      final einmal = prepareForExport(buildGlb(_figur()));
      final zweimal = prepareForExport(einmal.glb);
      expect(zweimal.report.changed, isFalse);
    });

    test('der Bericht nennt Höhe in Studs und die Achsen', () {
      final report = prepareForExport(buildGlb(_figur())).report;
      expect(report.text, contains('+Y oben'));
      expect(report.text, contains('Stud'));
      expect(report.steps.map((s) => s.title), contains('Blickrichtung'));
    });
  });

  group('Vorbereitung mit Skelett', () {
    test('die gehäutete Figur wandert genau so weit wie gewollt',
        () async {
      // Der eigentliche Beweis: Punkte, Gelenke und Bindematrizen
      // müssen gemeinsam wandern. Wandert nur eine Seite, reißt die
      // Haut – und das sieht man erst an den gehäuteten Punkten.
      final glb = injectAutoRig(buildGlb(_figur()), rigType: 'biped');
      final vorher = await parseGlbForPreview(glb);
      final p0 = computeSkinnedPositions(vorher);
      final b0 = _bounds(p0);
      vorher.dispose();

      final result = prepareForExport(glb);
      final nachher = await parseGlbForPreview(result.glb);
      final p1 = computeSkinnedPositions(nachher);
      nachher.dispose();

      expect(p1.length, p0.length);
      final dx = -(b0.minX + b0.maxX) / 2;
      final dy = -b0.minY;
      for (var i = 0; i + 2 < p0.length; i += 3) {
        expect(p1[i], closeTo(p0[i] + dx, 1e-3), reason: 'Punkt $i x');
        expect(p1[i + 1], closeTo(p0[i + 1] + dy, 1e-3),
            reason: 'Punkt $i y');
        expect(p1[i + 2], closeTo(p0[i + 2], 1e-3), reason: 'Punkt $i z');
      }
    });

    test('Skalierung am Wurzelknoten wird eingerechnet', () async {
      // So sieht eine GLB aus, nachdem „für Roblox herrichten" den
      // Maßstab über einen Wurzelknoten gesetzt hat.
      final glb = injectAutoRig(buildGlb(_figur()), rigType: 'biped');
      final parts = splitGlb(glb);
      final nodes = parts.json['nodes'] as List;
      final scene = (parts.json['scenes'] as List)[0] as Map;
      final alteWurzeln = (scene['nodes'] as List).toList();
      nodes.add({
        'name': 'roblox_scale',
        'scale': [2.0, 2.0, 2.0],
        'children': alteWurzeln,
      });
      scene['nodes'] = [nodes.length - 1];
      final skaliert = joinGlb(parts.json, parts.bin);

      final vorher = await parseGlbForPreview(skaliert);
      final p0 = computeSkinnedPositions(vorher);
      final h0 = _bounds(p0);
      vorher.dispose();

      final result = prepareForExport(skaliert);
      expect(result.report.text, contains('2.000'));

      final nachher = await parseGlbForPreview(result.glb);
      final p1 = computeSkinnedPositions(nachher);
      final h1 = _bounds(p1);
      nachher.dispose();

      // Die Skalierung steckt jetzt in den Punkten: Höhe unverändert,
      // aber am Wurzelknoten steht nichts mehr.
      expect(h1.maxY - h1.minY, closeTo(h0.maxY - h0.minY, 1e-3));
      expect(h1.minY, closeTo(0, 1e-3));
      final neu = splitGlb(result.glb);
      final wurzel = (neu.json['nodes'] as List)
          [((neu.json['scenes'] as List)[0] as Map)['nodes'][0] as int] as Map;
      expect(wurzel.containsKey('scale'), isFalse);
    });

    test('eine Drehung am Wurzelknoten wird nicht angefasst', () {
      final glb = injectAutoRig(buildGlb(_figur()), rigType: 'biped');
      final parts = splitGlb(glb);
      final nodes = parts.json['nodes'] as List;
      final scene = (parts.json['scenes'] as List)[0] as Map;
      nodes.add({
        'name': 'gedreht',
        'rotation': [0.0, 0.7071, 0.0, 0.7071],
        'children': (scene['nodes'] as List).toList(),
      });
      scene['nodes'] = [nodes.length - 1];

      final result = prepareForExport(joinGlb(parts.json, parts.bin));
      final schritt = result.report.steps
          .firstWhere((s) => s.title == 'Transformationen');
      expect(schritt.changed, isFalse);
      expect(schritt.detail, contains('Drehung'));
    });
  });
}
