import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/batch_prompt.dart';
import 'package:bildgenerator/services/prompt_briefing.dart';
import 'package:bildgenerator/services/view_direction.dart';
import 'package:bildgenerator/services/view_generator.dart';

/// Die Durchsicht aller Vorlagen, die die App an eine Prompt-KI
/// weitergibt. Geprüft wird für **jedes eingebaute Modell** und
/// **jede Blickrichtung**, ob sechs Dinge darin stehen. Jedes davon
/// hat schon einmal gefehlt, und jedes kostet einen ganzen Lauf.
void main() {
  final modelle = <(GenProvider, String)>[
    for (final provider in GenProvider.values)
      for (final option in staticModelOptions(provider))
        (provider, option.$1),
  ];

  group('Einzelbild-Vorlage', () {
    test('Jede Vorlage nennt das Modell, für das sie gilt', () {
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model);
        expect(profile.briefing, contains(profile.modelLabel),
            reason: '$provider/$model');
        expect(profile.modelLabel, contains(provider.label));
      }
    });

    test('Jede Vorlage fragt nach dem Stil', () {
      for (final (provider, model) in modelle) {
        expect(promptProfileFor(provider, model).briefing,
            contains('- Stil: [HIER STIL]'),
            reason: '$provider/$model');
      }
    });

    test('Jede Blickrichtung steht in jeder Vorlage', () {
      for (final (provider, model) in modelle) {
        for (final direction in viewDirections) {
          final briefing =
              promptProfileFor(provider, model, direction: direction)
                  .briefing;
          expect(briefing, contains('Blickrichtung'),
              reason: '$provider/$model/${direction.id}');
          if (direction.isEmpty) continue;
          expect(briefing, contains(direction.label),
              reason: '$provider/$model/${direction.id}');
          final profile = promptProfileFor(provider, model);
          final teile = viewDirectionParts(
              direction, profile.style, profile.negativeHandling);
          expect(briefing, contains(teile.prompt),
              reason: 'Der positive Teil fehlt: '
                  '$provider/$model/${direction.id}');
        }
      }
    });

    test('Der Umgang mit dem Negativ-Prompt steht drin', () {
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model);
        switch (profile.negativeHandling) {
          case NegativeHandling.separateField:
            expect(profile.briefing, contains('NEGATIV'),
                reason: '$provider/$model');
            expect(profile.negativeExample, isNotEmpty);
          case NegativeHandling.inPrompt:
            expect(profile.briefing, contains('Do not include in the image'),
                reason: '$provider/$model');
          case NegativeHandling.ignored:
            expect(profile.briefing, contains('nicht aus'),
                reason: '$provider/$model');
            expect(profile.negativeExample, isEmpty);
        }
      }
    });

    test('Stichwort-Modelle bekommen eine Höchstlänge genannt', () {
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model);
        if (profile.style != PromptStyle.keywords) continue;
        expect(profile.maxWords, greaterThan(0), reason: '$provider/$model');
        expect(profile.briefing, contains('${profile.maxWords} Wörter'),
            reason: '$provider/$model');
      }
    });

    test('Referenzbilder werden erwähnt – auch wenn sie nichts nützen',
        () {
      for (final (provider, model) in modelle) {
        final ohne = promptProfileFor(provider, model);
        // Ohne geladene Vorlagen darf keine Zahl behauptet werden.
        // (Ein allgemeiner Rat zu Referenzbildern in den Modellregeln
        // ist etwas anderes und bleibt erlaubt.)
        expect(ohne.briefing, isNot(contains('0 Referenzbild')),
            reason: '$provider/$model');
        expect(ohne.briefing, isNot(contains('Es liegen')),
            reason: '$provider/$model');
        final mit =
            promptProfileFor(provider, model, referenceCount: 2);
        expect(mit.briefing, contains('2 Referenzbild'),
            reason: '$provider/$model');
        if (!provider.supportsReferences) {
          expect(mit.briefing, contains('nicht aus'),
              reason: 'Muss sagen, dass sie nichts nützen: '
                  '$provider/$model');
        }
      }
    });
  });

  group('Massenprompt-Vorlage', () {
    test('Sie nennt Modell, Stil, Blickrichtung und Negativ-Umgang', () {
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model);
        for (final direction in [freeDirection, viewDirections[1]]) {
          final text = batchPromptBriefing(profile, direction: direction);
          expect(text, contains(profile.modelLabel),
              reason: '$provider/$model');
          expect(text, contains('Gemeinsamer Stil aller Bilder'),
              reason: '$provider/$model');
          expect(text, contains('Blickrichtung'),
              reason: '$provider/$model/${direction.id}');
          if (profile.negativeHandling == NegativeHandling.ignored) {
            expect(text, contains('nicht aus'), reason: '$provider/$model');
          } else {
            expect(text, contains('NEGATIV: '), reason: '$provider/$model');
          }
        }
      }
    });

    test('Sie nennt die Referenzbilder beim Namen', () {
      final profile =
          promptProfileFor(GenProvider.openai, 'gpt-image-2');
      final text = batchPromptBriefing(profile,
          references: ['burg.png', 'held.png']);
      expect(text, contains('burg.png, held.png'));
      expect(batchPromptBriefing(profile), contains('keine'));
    });

    test('Das Beispiel passt zur Schreibweise des Modells', () {
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model);
        final beispiel = batchPromptExample(profile);
        expect(beispiel, contains('NAME: '), reason: '$provider/$model');
        expect(beispiel, contains('PROMPT: '), reason: '$provider/$model');
        if (profile.negativeHandling == NegativeHandling.ignored) {
          expect(beispiel, isNot(contains('NEGATIV: ')),
              reason: 'Ohne Wirkung, also auch nicht im Beispiel: '
                  '$provider/$model');
        }
      }
    });
  });

  group('Die Blickrichtung selbst', () {
    test('Jede Richtung außer „keine Vorgabe" ist vollständig', () {
      for (final d in viewDirections) {
        expect(d.label, isNotEmpty);
        expect(d.hint, isNotEmpty);
        if (d.isEmpty) continue;
        expect(d.sentence, isNotEmpty, reason: d.id);
        expect(d.keywords, isNotEmpty, reason: d.id);
        expect(d.negativeTerms, isNotEmpty, reason: d.id);
        // Der Satz für sprachverstehende Modelle nennt die Kamera.
        expect(d.sentence.toLowerCase(), contains('camera'), reason: d.id);
      }
    });

    test('Kennungen sind eindeutig', () {
      final ids = viewDirections.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('Ohne Negativ-Feld steht die Richtung doppelt im Prompt', () {
      final turbo =
          promptProfileFor(GenProvider.selfhost, 'sdxl-turbo');
      expect(turbo.negativeHandling, NegativeHandling.ignored);
      final teile = viewDirectionParts(viewDirectionById('front'),
          turbo.style, turbo.negativeHandling);
      expect(teile.negative, isEmpty);
      expect(teile.prompt.split(',').length,
          greaterThan(viewDirectionById('front').keywords.split(',').length));
    });

    test('Eine unbekannte Kennung fällt auf „keine Vorgabe" zurück', () {
      expect(viewDirectionById('gibtesnicht').id, 'frei');
      expect(viewDirectionById('').id, 'frei');
    });
  });

  group('Die Vorgabe für die 3D-Ansichten', () {
    // Sie ging bisher wortgleich an jedes Modell – auch an die
    // Diffusions-Modelle. Dort ist sie doppelt falsch: voller
    // Verneinungen, die dort als Wunsch ankommen, und mit rund 90
    // Wörtern weit über jedem Budget.
    test('Für Stichwort-Modelle ist es eine Kette ohne Verneinungen', () {
      final kette = viewFrontKeywords('a small stone tower', null,
          background: ViewBackground.magenta);
      for (final wort in ['NOT', 'no ', 'without']) {
        expect(kette, isNot(contains(wort)), reason: 'Verneinung: $wort');
      }
      expect(kette, contains('front view'));
      expect(kette, contains('a small stone tower'));
      expect(kette, contains('magenta'));
    });

    test('Die Kette bleibt im Budget des sparsamsten Modells', () {
      final kette = viewFrontKeywords('a small stone tower', null,
          background: ViewBackground.alpha);
      final woerter = kette.split(RegExp(r'\s+')).length;
      final knappstes =
          promptProfileFor(GenProvider.selfhost, 'sdxl-turbo').maxWords;
      expect(woerter, lessThanOrEqualTo(knappstes),
          reason: 'Die Kette ist $woerter Wörter lang, SDXL Turbo '
              'verträgt $knappstes');
    });

    test('Dreiviertel und Frontal schließen sich gegenseitig aus', () {
      final vorn = viewFrontKeywords('x', null, background: ViewBackground.alpha);
      final schraeg = viewFrontKeywords('x', null,
          threeQuarter: true, background: ViewBackground.alpha);
      expect(vorn, contains('front view'));
      expect(vorn, isNot(contains('three quarter')));
      expect(schraeg, contains('three quarter view'));
      expect(viewNegativePrompt(threeQuarter: false),
          contains('three quarter view'));
      expect(viewNegativePrompt(threeQuarter: true),
          contains('flat frontal view'));
    });

    test('Der Negativ-Block nennt die Fehler, die eine Ansicht '
        'unbrauchbar machen', () {
      final negativ = viewNegativePrompt(threeQuarter: false);
      for (final begriff in [
        'from above',
        'perspective distortion',
        'ground plane',
        'shadow',
        'second subject',
        'cropped',
      ]) {
        expect(negativ, contains(begriff), reason: begriff);
      }
    });

    test('Die Pose steht mit in der Kette', () {
      final kette = viewFrontKeywords('a hero', 'T-pose, arms straight out',
          background: ViewBackground.alpha);
      expect(kette, contains('T-pose'));
    });
  });
}
