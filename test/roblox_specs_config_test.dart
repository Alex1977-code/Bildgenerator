import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/roblox_spec.dart';
import 'package:bildgenerator/services/roblox_specs_config.dart';

void main() {
  final datei = File('assets/roblox_specs.json').readAsStringSync();

  group('Die mitgelieferte Datei', () {
    test('Ist gültiges JSON und wird ohne Befund gelesen', () {
      final specs = parseRobloxSpecs(datei);
      expect(specs.problems, isEmpty,
          reason: 'Befunde: ${specs.problems}');
      expect(specs.fromFile, isTrue);
      expect(specs.version, greaterThan(0));
      expect(specs.maxAgeDays, 90);
    });

    test('Enthält die drei Asset-Typen mit den Startwerten', () {
      final specs = parseRobloxSpecs(datei);
      final zubehoer = specs['rigidAccessory']!;
      expect(zubehoer.triangles, 4000);
      expect(zubehoer.singleMesh, isTrue);
      expect(zubehoer.attachments, 1);
      expect(zubehoer.texture.target, 1024);
      expect(zubehoer.texture.hardCap, 2048);
      expect(zubehoer.texture.nonAlbedo, 256);

      expect(specs['genericMesh']!.triangles, 20000);

      final koerper = specs['characterBody']!;
      expect(koerper.triangles, 10742);
      expect(koerper.parts['DynamicHead'], 4000);
      expect(koerper.parts['Torso'], 1750);
      expect(koerper.parts['LeftArm'], 1248);
      expect(koerper.parts['RightLeg'], 1248);
      expect(koerper.meshNames.length, 15);
      expect(koerper.partSum, koerper.triangles);
    });

    test('Jeder Typ nennt Quelle und Prüfdatum', () {
      final specs = parseRobloxSpecs(datei);
      for (final spec in specs.assetTypes.values) {
        expect(spec.source, isNotEmpty, reason: spec.id);
        expect(spec.checked, isNotNull, reason: spec.id);
      }
    });

    test('Rig und Geometrie stimmen mit den Konstanten überein', () {
      final specs = parseRobloxSpecs(datei);
      expect(specs.rootBone, specRootBone);
      expect(specs.rootNode, specRootNode);
      expect(specs.maxInfluences, specMaxInfluences);
      expect(specs.allowedPoses, specAllowedPoses);
      expect(specs.hierarchy.keys.toSet(), specR15Hierarchy.keys.toSet());
      for (final entry in specR15Hierarchy.entries) {
        expect(specs.hierarchy[entry.key], entry.value, reason: entry.key);
      }
      expect(specs.minBoundingBoxFill, 0.5);
    });

    test('Die Datei sagt dasselbe wie der Rückfall', () {
      final ausDatei = parseRobloxSpecs(datei);
      final eingebaut = fallbackSpecs();
      for (final id in eingebaut.assetTypes.keys) {
        expect(ausDatei[id]!.triangles, eingebaut[id]!.triangles,
            reason: id);
        expect(ausDatei[id]!.texture.target, eingebaut[id]!.texture.target,
            reason: id);
        expect(ausDatei[id]!.texture.hardCap,
            eingebaut[id]!.texture.hardCap,
            reason: id);
      }
    });
  });

  group('Alter der Angaben', () {
    RobloxSpecs mitDatum(String datum) => parseRobloxSpecs(jsonEncode({
          'maxAgeDays': 90,
          'assetTypes': {
            'rigidAccessory': {
              'triangles': 4000,
              'quelle': 'x',
              'checked': datum,
              'texture': {'target': 1024, 'hardCap': 2048, 'nonAlbedo': 256},
            },
          },
        }));

    test('Frisch geprüft heißt keine Warnung', () {
      final specs = mitDatum('2026-09-01');
      expect(specs.isStale(now: DateTime(2026, 9, 20)), isFalse);
      expect(specs.staleWarning(now: DateTime(2026, 9, 20)), isEmpty);
      expect(specs.ageInDays(now: DateTime(2026, 9, 20)), 19);
    });

    test('Über 90 Tage warnt die App mit der Zahl', () {
      final specs = mitDatum('2026-01-01');
      expect(specs.isStale(now: DateTime(2026, 9, 1)), isTrue);
      final text = specs.staleWarning(now: DateTime(2026, 9, 1));
      expect(text, contains('243 Tage'));
      expect(text, contains('90'));
    });

    test('Genau an der Grenze wird noch nicht gewarnt', () {
      final specs = mitDatum('2026-06-03');
      expect(specs.ageInDays(now: DateTime(2026, 9, 1)), 90);
      expect(specs.isStale(now: DateTime(2026, 9, 1)), isFalse);
    });

    test('Ohne Datum gilt es als veraltet', () {
      final specs = parseRobloxSpecs(jsonEncode({
        'assetTypes': {
          'rigidAccessory': {'triangles': 4000},
        },
      }));
      expect(specs.isStale(), isTrue);
      expect(specs.staleWarning(), contains('kein Prüfdatum'));
      expect(specs.problems, contains(contains('kein Prüfdatum')));
    });

    test('Das älteste Datum entscheidet', () {
      final specs = parseRobloxSpecs(jsonEncode({
        'assetTypes': {
          'a': {'triangles': 10, 'checked': '2026-08-01'},
          'b': {'triangles': 10, 'checked': '2026-01-01'},
        },
      }));
      expect(specs.oldestChecked, DateTime(2026, 1, 1));
    });
  });

  group('Kaputte Dateien', () {
    test('Unlesbares JSON führt auf die eingebauten Werte', () {
      final specs = parseRobloxSpecs('{kaputt');
      expect(specs.fromFile, isFalse);
      expect(specs['rigidAccessory']!.triangles, specAccessoryTriangles);
      expect(specs.problems.first, contains('ließ sich nicht lesen'));
    });

    test('Kein Objekt, keine Typen – beides wird gemeldet', () {
      expect(parseRobloxSpecs('[1,2,3]').problems.first,
          contains('kein Objekt'));
      expect(parseRobloxSpecs('{}').problems.first,
          contains('keine Asset-Typen'));
    });

    test('Einzelbudgets, die nicht zur Summe passen, fallen auf', () {
      final specs = parseRobloxSpecs(jsonEncode({
        'assetTypes': {
          'characterBody': {
            'triangles': 10742,
            'checked': '2026-09-01',
            'parts': {'DynamicHead': 4000, 'Torso': 1750},
          },
        },
      }));
      expect(specs.problems, contains(contains('ergeben 5750')));
    });

    test('Eine Zielgröße über der harten Grenze fällt auf', () {
      final specs = parseRobloxSpecs(jsonEncode({
        'assetTypes': {
          'genericMesh': {
            'triangles': 20000,
            'checked': '2026-09-01',
            'texture': {'target': 4096, 'hardCap': 2048, 'nonAlbedo': 1024},
          },
        },
      }));
      expect(specs.problems, contains(contains('über der harten Grenze')));
    });

    test('Ein fehlender Typ kommt aus dem Rückfall, mit Hinweis', () {
      final specs = parseRobloxSpecs(jsonEncode({
        'assetTypes': {
          'rigidAccessory': {'triangles': 4000, 'checked': '2026-09-01'},
        },
      }));
      expect(specs['characterBody']!.triangles, specBodyTotalTriangles);
      expect(specs.problems, contains(contains('„characterBody" fehlt')));
    });

    test('Ein Budget von 0 fällt auf', () {
      final specs = parseRobloxSpecs(jsonEncode({
        'assetTypes': {
          'genericMesh': {'triangles': 0, 'checked': '2026-09-01'},
        },
      }));
      expect(specs.problems, contains(contains('ist 0')));
    });
  });

  group('Laden', () {
    test('Eine eigene Fassung gewinnt', () async {
      final eigene = jsonEncode({
        'assetTypes': {
          'rigidAccessory': {'triangles': 1234, 'checked': '2026-09-01'},
        },
      });
      final specs = await loadRobloxSpecs(
          (key) async => datei, override: eigene);
      expect(specs['rigidAccessory']!.triangles, 1234);
    });

    test('Ohne eigene Fassung kommt die mitgelieferte', () async {
      final specs = await loadRobloxSpecs((key) async {
        expect(key, 'assets/roblox_specs.json');
        return datei;
      });
      expect(specs['rigidAccessory']!.triangles, 4000);
      expect(specs.fromFile, isTrue);
    });

    test('Fehlt die Datei, läuft die App weiter', () async {
      final specs =
          await loadRobloxSpecs((key) async => throw Exception('weg'));
      expect(specs.fromFile, isFalse);
      expect(specs['genericMesh']!.triangles, specMaxMeshTriangles);
      expect(specs.problems.first, contains('nicht öffnen'));
    });
  });
}
