import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/mesh_budget.dart';
import 'package:bildgenerator/services/roblox_specs_config.dart';

/// Ein Gitternetz mit vorhersagbarer Dreieckszahl: n×n Felder ergeben
/// 2·n² Dreiecke.
LocalMesh _gitter(int n) {
  final mesh = LocalMesh();
  final ids = <List<int>>[];
  for (var i = 0; i <= n; i++) {
    final row = <int>[];
    for (var j = 0; j <= n; j++) {
      row.add(mesh.addVertex(i / n, j / n, (i * j % 3) / 10, i / n, j / n,
          r: 0.5, g: 0.4, b: 0.3));
    }
    ids.add(row);
  }
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      mesh.addQuad(ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]);
    }
  }
  return mesh;
}

void main() {
  final specs = fallbackSpecs();
  final zubehoer = specs['rigidAccessory']!; // 4.000
  final prop = specs['genericMesh']!; // 20.000

  group('Ampel', () {
    test('Grün, solange reichlich Luft ist', () {
      final v = budgetVerdict(1000, zubehoer);
      expect(v.light, BudgetLight.gruen);
      expect(v.blocks, isFalse);
      expect(v.text, contains('25 %'));
      expect(v.text, contains('4000'));
    });

    test('Gelb ab 90 Prozent – da wird es eng', () {
      expect(budgetVerdict(3599, zubehoer).light, BudgetLight.gruen);
      expect(budgetVerdict(3600, zubehoer).light, BudgetLight.gelb);
      expect(budgetVerdict(4000, zubehoer).light, BudgetLight.gelb);
      expect(budgetVerdict(3800, zubehoer).text, contains('Knapp'));
    });

    test('Rot erst über dem Budget – und sagt, um wie viel', () {
      final v = budgetVerdict(4500, zubehoer);
      expect(v.light, BudgetLight.rot);
      expect(v.blocks, isTrue);
      expect(v.text, contains('500 Dreiecke über dem Budget'));
    });

    test('Dasselbe Netz kann für den einen Typ rot und für den '
        'anderen grün sein', () {
      expect(budgetVerdict(9000, zubehoer).light, BudgetLight.rot);
      expect(budgetVerdict(9000, prop).light, BudgetLight.gruen);
    });

    test('Der Füllstand stimmt', () {
      expect(budgetVerdict(2000, zubehoer).fill, 0.5);
      expect(budgetVerdict(0, zubehoer).fill, 0);
    });

    test('Ohne Budget wird nichts behauptet', () {
      const ohne = AssetSpec(
          id: 'x',
          label: 'Ohne',
          triangles: 0,
          texture: TextureBudget(target: 1024, hardCap: 2048, nonAlbedo: 256));
      final v = budgetVerdict(5000, ohne);
      expect(v.light, BudgetLight.gruen);
      expect(v.text, contains('kein Budget'));
    });
  });

  group('Reglerkennlinie', () {
    test('Rechts steht das unveränderte Netz, links das Minimum', () {
      expect(targetForSlider(1.0, 50000), 50000);
      expect(targetForSlider(0.0, 50000), 200);
    });

    test('Sie ist logarithmisch – die Mitte liegt nicht bei der '
        'halben Dreieckszahl', () {
      final mitte = targetForSlider(0.5, 20000);
      expect(mitte, lessThan(10000),
          reason: 'linear wären es 10.000');
      expect(mitte, greaterThan(1500));
    });

    test('Sie steigt überall an', () {
      var vorher = 0;
      for (var i = 0; i <= 20; i++) {
        final wert = targetForSlider(i / 20, 30000);
        expect(wert, greaterThanOrEqualTo(vorher), reason: 'bei ${i / 20}');
        vorher = wert;
      }
    });

    test('Hin und zurück trifft sich wieder', () {
      for (final ziel in [400, 1000, 4000, 12000]) {
        final regler = sliderForTarget(ziel, 40000);
        expect(targetForSlider(regler, 40000), closeTo(ziel, ziel * 0.02));
      }
    });

    test('Ein Netz unter dem Minimum lässt sich nicht weiter '
        'reduzieren', () {
      expect(targetForSlider(0.0, 120), 120);
      expect(sliderForTarget(50, 120), 1.0);
    });
  });

  group('Reduzieren einer GLB', () {
    test('Die Dreieckszahl sinkt auf das Ziel', () async {
      final glb = buildGlb(_gitter(40)); // 3.200 Dreiecke
      expect(await glbTriangleCount(glb), 3200);
      final klein = await decimateGlb(glb, 800);
      final zahl = await glbTriangleCount(klein);
      expect(zahl, lessThanOrEqualTo(800));
      expect(zahl, greaterThan(50), reason: 'nicht auf nichts reduzieren');
    });

    test('Ein Ziel über der Dreieckszahl lässt die Datei unberührt',
        () async {
      final glb = buildGlb(_gitter(10));
      expect(identical(await decimateGlb(glb, 100000), glb), isTrue);
      expect(identical(await decimateGlb(glb, 0), glb), isTrue);
    });

    test('Die Textur überlebt das Reduzieren', () async {
      // 1x1-PNG als Textur.
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0,
        0x1F, 0x15, 0xC4, 0x89, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99,
        0, 1, 0, 0, 5, 0, 1, 13, 0x0A, 0x2D, 0xB4, 0, 0, 0, 0, 73, 69, 78,
        68, 0xAE, 0x42, 0x60, 0x82,
      ]);
      final glb = buildGlb(_gitter(30), pngTexture: png);
      expect(firstGlbTexturePng(glb), isNotNull);
      final klein = await decimateGlb(glb, 400);
      expect(firstGlbTexturePng(klein), isNotNull,
          reason: 'Die erste Fassung lieferte ein graues Netz zurück');
      final preview = await parseGlbForPreview(klein);
      addTearDown(preview.dispose);
      expect(preview.uvs, isNotNull);
      // Die UVs müssen im 0-1-Raum bleiben, sonst kachelt die Textur.
      for (final uv in preview.uvs!) {
        expect(uv, inInclusiveRange(-0.001, 1.001));
      }
    });

    test('Ohne Textur bleibt es bei den Vertexfarben', () async {
      final glb = buildGlb(_gitter(30));
      final klein = await decimateGlb(glb, 400);
      expect(firstGlbTexturePng(klein), isNull);
      final preview = await parseGlbForPreview(klein);
      addTearDown(preview.dispose);
      expect(preview.colors, isNotEmpty);
    });

    test('Aus einer kaputten Datei kommt keine Textur, aber auch '
        'kein Absturz', () {
      expect(firstGlbTexturePng(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}
