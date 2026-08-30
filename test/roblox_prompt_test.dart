import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/pose_prompt.dart';
import 'package:bildgenerator/services/roblox_prompt.dart';
import 'package:bildgenerator/services/tripo_service.dart';

void main() {
  final figur = robloxPromptRules(accessory: false);
  final accessoire = robloxPromptRules(accessory: true);

  group('Die Vorlage gibt den Bauplan mit', () {
    test('Der feste Schwanz steht wörtlich drin', () {
      // Ohne ihn muss die Prompt-KI raten – genau daran sind die
      // ersten Läufe gescheitert.
      expect(figur, contains(robloxFigureTail));
      expect(accessoire, contains(robloxAccessoryTail));
    });

    test('Die vier tragenden Angaben stehen im Schwanz', () {
      for (final term in [
        'single connected body',
        'visible wall thickness',
        'closed watertight shell',
        'single mesh',
      ]) {
        expect(robloxFigureTail, contains(term), reason: term);
      }
      for (final term in [
        'single solid object',
        'visible wall thickness',
        'closed watertight shell',
        'single mesh',
      ]) {
        expect(robloxAccessoryTail, contains(term), reason: term);
      }
    });

    test('Die NEGATIV-Zeile steht wörtlich drin und passt in die '
        'Grenze', () {
      expect(figur, contains(robloxFigureNegative));
      expect(accessoire, contains(robloxAccessoryNegative));
      expect(robloxFigureNegative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
      expect(robloxAccessoryNegative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
    });

    test('Ein vollständiges Beispiel ist dabei', () {
      expect(figur, contains(robloxFigureExample));
      expect(accessoire, contains(robloxAccessoryExample));
      // Das Beispiel selbst hält die Längengrenze ein – mit dem
      // T-Pose-Zusatz, den die App anhängt.
      final prompt = robloxFigureExample
          .split('\n')
          .firstWhere((l) => l.startsWith('PROMPT: '))
          .substring('PROMPT: '.length);
      expect(prompt.length + tPoseSuffix.length + 2,
          lessThanOrEqualTo(TripoService.maxPromptChars));
    });

    test('Die Reihenfolge des Motivs wird vorgegeben', () {
      expect(figur, contains('AUFBAU des PROMPT'));
      expect(figur, contains('Proportionen'));
      expect(figur, contains('erkennende Merkmal'));
      expect(accessoire, contains('Grundform'));
    });
  });

  group('Die Vorlage nennt die Fallen', () {
    test('Keine T-Pose im Text, aber der Zusatz wird beziffert', () {
      expect(figur, contains('KEINE T-Pose'));
      expect(figur, contains('${tPoseSuffix.length + 2} Zeichen'));
      // Beim Accessoire gibt es keine Pose.
      expect(accessoire, contains('KEINE Pose'));
      expect(accessoire, isNot(contains('T-Pose')));
    });

    test('Verneinungen und dünne Kleinteile stehen als Falle drin', () {
      for (final text in [figur, accessoire]) {
        expect(text, contains('KEINE Verneinungen'));
        expect(text, contains('dünnen Kleinteile'));
        expect(text, contains('Moderation'));
      }
    });

    test('Verdeckende Kleidung nur bei der Figur', () {
      expect(figur, contains('Umhänge'));
      expect(figur, contains('kein Skelett andocken'));
      expect(accessoire, isNot(contains('Umhänge')));
    });
  });

  group('Die Vorlage nennt die Grenzen', () {
    test('Dreiecke, Textur und Zeichen', () {
      expect(figur, contains('10.000 Dreiecke'));
      expect(accessoire, contains('4.000 Dreiecke'));
      for (final text in [figur, accessoire]) {
        expect(text, contains('1024er-Textur'));
        expect(text, contains('1.024 Zeichen'));
        expect(text, contains('255'));
      }
    });

    test('Die Studs stehen nur bei der Figur', () {
      expect(figur, contains('5 Studs'));
      expect(accessoire, isNot(contains('Studs')));
    });
  });
}
