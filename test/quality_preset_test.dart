import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/quality_preset.dart';

void main() {
  group('Stufen für ein gewöhnliches Modell', () {
    // SDXL Base: 30 Schritte, Prompt-Treue 7.
    QualitySettings sdxl(QualityPreset preset) =>
        qualityFor(preset: preset, modelSteps: 30, modelGuidance: 7);

    test('Standard entspricht der Vorgabe des Modells', () {
      final s = sdxl(QualityPreset.standard);
      expect(s.steps, 30);
      expect(s.guidance, 7);
      expect(s.hasDetailPass, isFalse);
    });

    test('Die Schrittzahl steigt mit der Stufe', () {
      expect(sdxl(QualityPreset.entwurf).steps, lessThan(30));
      expect(sdxl(QualityPreset.fein).steps, greaterThan(30));
      expect(sdxl(QualityPreset.sehrFein).steps,
          greaterThan(sdxl(QualityPreset.fein).steps));
    });

    test('Ab „Fein" kommt der Detail-Durchgang dazu', () {
      expect(sdxl(QualityPreset.standard).hasDetailPass, isFalse);
      expect(sdxl(QualityPreset.fein).hasDetailPass, isTrue);
      expect(sdxl(QualityPreset.sehrFein).detailScale,
          greaterThan(sdxl(QualityPreset.fein).detailScale));
    });

    test('Der zweite Durchgang bleibt schwach genug, um zu schärfen '
        'statt neu zu erfinden', () {
      for (final preset in QualityPreset.values) {
        expect(sdxl(preset).detail, lessThan(0.5));
      }
    });
  });

  group('Destillierte Modelle', () {
    // SDXL Turbo und FLUX schnell: 4 Schritte, keine Prompt-Treue.
    QualitySettings turbo(QualityPreset preset) =>
        qualityFor(preset: preset, modelSteps: 4, modelGuidance: 0);

    test('Die Prompt-Treue bleibt aus', () {
      // Ein CFG-Wert würde das Bild hier zerstören, nicht verbessern.
      for (final preset in QualityPreset.values) {
        expect(turbo(preset).guidance, 0);
      }
    });

    test('Die Schrittzahl bleibt gedeckelt', () {
      for (final preset in QualityPreset.values) {
        expect(turbo(preset).steps,
            lessThanOrEqualTo(distilledStepCap));
      }
      // Und mindestens ein Schritt, auch beim Entwurf.
      expect(turbo(QualityPreset.entwurf).steps, greaterThanOrEqualTo(1));
    });
  });

  test('Kein Detail-Durchgang, wo das Modell keinen kann', () {
    final s = qualityFor(
        preset: QualityPreset.sehrFein,
        modelSteps: 28,
        modelGuidance: 4.5,
        supportsDetail: false);
    expect(s.hasDetailPass, isFalse);
    expect(s.steps, greaterThan(28));
  });

  test('Ohne Angaben des Modells wird von 30 Schritten ausgegangen', () {
    expect(
        qualityFor(
                preset: QualityPreset.standard,
                modelSteps: 0,
                modelGuidance: 7)
            .steps,
        30);
  });

  test('Nie über die Obergrenze', () {
    expect(
        qualityFor(
                preset: QualityPreset.sehrFein,
                modelSteps: 50,
                modelGuidance: 7)
            .steps,
        lessThanOrEqualTo(maxSteps));
  });

  group('Warnungen zu den Reglern', () {
    test('Zu hohe und zu niedrige Prompt-Treue', () {
      expect(qualityWarning(steps: 30, guidance: 14, modelGuidance: 7),
          contains('überzeichnet'));
      expect(qualityWarning(steps: 30, guidance: 1.5, modelGuidance: 7),
          contains('ignoriert'));
    });

    test('Zu viele Schritte bei einem destillierten Modell', () {
      expect(qualityWarning(steps: 30, guidance: 0, modelGuidance: 0),
          contains('wenige Schritte'));
      expect(
          qualityWarning(steps: 6, guidance: 0, modelGuidance: 0), isEmpty);
    });

    test('Vernünftige Werte melden nichts', () {
      expect(qualityWarning(steps: 30, guidance: 7, modelGuidance: 7),
          isEmpty);
    });
  });

  group('Modell-Vorgaben', () {
    test('Die bekannten Modelle des eigenen Servers stehen drin', () {
      expect(localModelDefault('sdxl'), (30, 7.0, true));
      expect(localModelDefault('sdxl-turbo').$2, 0.0);
      // SD 3.5 und FLUX rechnen anders – kein Detail-Durchgang.
      expect(localModelDefault('sd35-medium').$3, isFalse);
      expect(localModelDefault('flux-schnell').$3, isFalse);
    });

    test('Ein unbekanntes Modell bekommt vernünftige Vorgaben', () {
      final (steps, guidance, detail) = localModelDefault('was-neues');
      expect(steps, 30);
      expect(guidance, 7.0);
      expect(detail, isTrue);
    });
  });

  test('Die Tabelle stimmt mit dem Server überein', () {
    // Die Vorgaben stehen zweimal: hier für die Regler, bevor der
    // Server antwortet, und in server/local_image_server.py als
    // Wahrheit. Läuft das auseinander, stehen die Regler beim
    // nächsten Modellwechsel falsch – dieser Test merkt es.
    final quelle = File('server/local_image_server.py').readAsStringSync();
    final block = RegExp(r'^MODELS = \{(.*?)^\}', multiLine: true, dotAll: true)
        .firstMatch(quelle);
    expect(block, isNotNull, reason: 'MODELS im Server nicht gefunden');
    final eintrag = RegExp(
        r'"([\w.-]+)":\s*\("[^"]+",\s*"(\w+)",\s*'
        r'(\d+),\s*([\d.]+),');
    final gefunden = <String>{};
    for (final m in eintrag.allMatches(block!.group(1)!)) {
      final name = m.group(1)!;
      final family = m.group(2)!;
      final steps = int.parse(m.group(3)!);
      final guidance = double.parse(m.group(4)!);
      gefunden.add(name);
      expect(localModelDefaults, contains(name),
          reason: '$name fehlt in localModelDefaults');
      final (dartSteps, dartGuidance, dartDetail) =
          localModelDefaults[name]!;
      expect(dartSteps, steps, reason: '$name: Schritte');
      expect(dartGuidance, guidance, reason: '$name: Prompt-Treue');
      // Der Detail-Durchgang gilt nur für SD und SDXL – siehe
      // _detail_pass im Server.
      expect(dartDetail, family == 'sd' || family == 'sdxl',
          reason: '$name: Detail-Durchgang');
    }
    expect(gefunden.length, greaterThan(3));
    expect(localModelDefaults.keys.toSet(), gefunden);
  });

  group('Die Werte landen im Verlauf', () {
    GenerationRequest anfrage(QualitySettings q) => GenerationRequest(
          provider: GenProvider.selfhost,
          prompt: 'ein Fass',
          steps: q.steps,
          guidance: q.guidance,
          sampler: 'dpmpp2m-karras',
          detail: q.detail,
          detailScale: q.detailScale,
        );

    test('Schritte, Prompt-Treue, Sampler und Detail-Durchgang', () {
      // Ohne das ließe sich ein gelungenes Bild später nicht
      // wiederholen – und die Lernstatistik wüsste nicht, woran es lag.
      final params = anfrage(qualityFor(
              preset: QualityPreset.fein,
              modelSteps: 30,
              modelGuidance: 7))
          .describeParams();
      expect(params['Schritte'], '42');
      expect(params['Prompt-Treue'], '7.0');
      expect(params['Sampler'], 'dpmpp2m-karras');
      expect(params['Detail-Durchgang'], contains('1.25×'));
    });

    test('Was nicht gesetzt ist, steht auch nicht da', () {
      final params = GenerationRequest(
        provider: GenProvider.selfhost,
        prompt: 'ein Fass',
      ).describeParams();
      expect(params.containsKey('Schritte'), isFalse);
      expect(params.containsKey('Prompt-Treue'), isFalse);
      expect(params.containsKey('Detail-Durchgang'), isFalse);
    });

    test('Prompt-Treue 0 ist ein Wert, kein „unbestimmt"', () {
      // Destillierte Modelle rechnen mit 0. Wäre 0 die Marke für
      // „nicht gesetzt", käme dort die Vorgabe des Servers an.
      final params = anfrage(qualityFor(
              preset: QualityPreset.standard,
              modelSteps: 4,
              modelGuidance: 0))
          .describeParams();
      expect(params['Prompt-Treue'], '0.0');
    });
  });

  test('Jede Stufe hat Namen und Erklärung', () {
    for (final preset in QualityPreset.values) {
      final (name, hint) = qualityLabel(preset);
      expect(name, isNotEmpty);
      expect(hint.length, greaterThan(20));
    }
  });
}
