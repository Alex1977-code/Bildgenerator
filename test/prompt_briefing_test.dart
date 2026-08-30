import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/prompt_briefing.dart';
import 'package:bildgenerator/services/update_check.dart';

void main() {
  group('Prompt-Vorlage je Modell', () {
    test('GPT-Image bekommt ein gegliedertes Briefing', () {
      final profile =
          promptProfileFor(GenProvider.openai, 'gpt-image-1');
      expect(profile.style, PromptStyle.briefing);
      expect(profile.briefing, contains('MOTIV'));
      expect(profile.briefing, contains('Verneinungen sind erlaubt'));
      // Kein Negativ-Feld, aber Verneinungen wirken – deshalb lohnt
      // sich ein Negativ-Prompt trotzdem.
      expect(profile.negativeHandling, NegativeHandling.inPrompt);
      expect(profile.wantsNegativePrompt, isTrue);
    });

    test('Gemini nennt die Referenzbild-Stärke', () {
      final profile =
          promptProfileFor(GenProvider.gemini, 'gemini-2.5-flash-image');
      expect(profile.style, PromptStyle.briefing);
      expect(profile.briefing, contains('Referenzbilder'));
    });

    test('Stable Diffusion bekommt Stichwort-Regeln statt Briefing', () {
      final profile = promptProfileFor(GenProvider.selfhost, 'sdxl');
      expect(profile.style, PromptStyle.keywords);
      expect(profile.briefing, contains('KEINE Verneinungen'));
      expect(profile.briefing, contains('PROMPT:'));
      expect(profile.briefing, contains('NEGATIV:'));
      expect(profile.wantsNegativePrompt, isTrue);
      expect(profile.maxWords, 100);
    });

    test('SDXL Turbo warnt vor fehlendem Negativ-Prompt und ist kurz', () {
      final profile =
          promptProfileFor(GenProvider.selfhost, 'sdxl-turbo');
      expect(profile.negativeHandling, NegativeHandling.ignored);
      expect(profile.wantsNegativePrompt, isFalse);
      expect(profile.maxWords, 40);
      expect(profile.briefing, contains('nicht aus'));
      expect(profile.summary, contains('keinen Negativ-Prompt'));
    });

    test('FLUX kennt keinen Negativ-Prompt', () {
      final profile =
          promptProfileFor(GenProvider.selfhost, 'flux-schnell');
      expect(profile.negativeHandling, NegativeHandling.ignored);
      expect(profile.wantsNegativePrompt, isFalse);
      expect(profile.briefing, contains('positive Formulierungen'));
    });

    test('Negativ-Prompt landet dort, wo das Modell ihn versteht', () {
      // Stability hat ein eigenes Feld – der Prompt bleibt unberührt.
      final field = applyNegativePrompt(
          'a castle', 'people, text', NegativeHandling.separateField);
      expect(field.prompt, 'a castle');
      expect(field.negativePrompt, 'people, text');

      // GPT-Image und Gemini haben keines – der Satz wandert hinein.
      final inPrompt = applyNegativePrompt(
          'a castle', 'people, text.', NegativeHandling.inPrompt);
      expect(inPrompt.prompt,
          'a castle\n\nDo not include in the image: people, text.');
      expect(inPrompt.negativePrompt, 'people, text');

      // Ohne Angabe bleibt alles, wie es war.
      final empty = applyNegativePrompt(
          'a castle', '   ', NegativeHandling.inPrompt);
      expect(empty.prompt, 'a castle');
      expect(empty.negativePrompt, isEmpty);
    });

    test('Spielgrafik-Regeln kommen in die Vorlage', () {
      final briefing = promptProfileFor(GenProvider.openai, 'gpt-image-1',
              gameAssets: true)
          .briefing;
      expect(briefing, contains(gameAssetSentences[2]));
      final keywords =
          promptProfileFor(GenProvider.selfhost, 'sdxl', gameAssets: true)
              .briefing;
      expect(keywords, contains(gameAssetKeywords));
      expect(keywords, contains(gameAssetNegativeTerms));
    });

    test('Stability Core bleibt kurz, Ultra darf länger', () {
      expect(promptProfileFor(GenProvider.stability, 'core').maxWords, 60);
      expect(
          promptProfileFor(GenProvider.stability, 'ultra').maxWords, 120);
    });

    test('Referenzbilder werden im Auftrag erwähnt', () {
      final profile = promptProfileFor(
          GenProvider.gemini, 'gemini-2.5-flash-image',
          referenceCount: 3);
      expect(profile.briefing, contains('3 Referenzbild'));
    });

    test('Referenzbilder bei einem Modell ohne Unterstützung', () {
      final profile = promptProfileFor(GenProvider.stability, 'core',
          referenceCount: 2);
      expect(profile.briefing, contains('nicht aus'));
    });

    test('Jedes eingebaute Modell liefert eine brauchbare Vorlage', () {
      for (final provider in GenProvider.values) {
        for (final option in staticModelOptions(provider)) {
          final profile = promptProfileFor(provider, option.$1);
          expect(profile.briefing.length, greaterThan(300),
              reason: '${provider.name}/${option.$1}');
          expect(profile.modelLabel, contains(provider.label));
          expect(profile.summary, isNotEmpty);
        }
      }
    });
  });

  group('Update-Prüfung: Fehlermeldungen', () {
    test('403 mit aufgebrauchter Abfragegrenze erklärt die Ursache', () {
      final reset = DateTime.now()
              .add(const Duration(minutes: 25))
              .millisecondsSinceEpoch ~/
          1000;
      final text = describeApiFailure(403, {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '$reset',
      });
      expect(text, contains('60 Abfragen'));
      expect(text, contains('Minuten'));
      expect(text, contains('trotzdem'));
    });

    test('403 ohne Grenz-Kopfzeile nennt Netz und Virenscanner', () {
      final text = describeApiFailure(403, const {});
      expect(text, contains('403'));
      expect(text, contains('Firmen-Netz'));
    });

    test('404 heißt: noch keine Veröffentlichung', () {
      expect(describeApiFailure(404, const {}), contains('404'));
    });

    test('Andere Fehler behalten die knappe Meldung', () {
      expect(describeApiFailure(500, const {}), contains('(500)'));
    });

    test('Größe unbekannt statt 0.0 MB', () {
      const info = UpdateInfo(
        sha: '',
        published: null,
        downloadUrl: 'https://example.invalid/x.zip',
        assetName: 'x.zip',
        sizeBytes: 0,
      );
      expect(info.sizeLabel, 'Größe unbekannt');
    });
  });
}
