import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/prompt_briefing.dart';
import 'package:bildgenerator/services/view_direction.dart';
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
      // Ein CLIP-Block fasst 75 Tokens, also rund 60 Wörter. Darüber
      // verwässert das Motiv – 97 Wörter mit 12 Motivwörtern kamen als
      // Lehmkuppel zurück statt als Bäckerei.
      expect(profile.maxWords, 60);
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
              direction: viewDirectionById('iso35'))
          .briefing;
      expect(briefing, contains(gameAssetSentences[2]));
      final keywords =
          promptProfileFor(GenProvider.selfhost, 'sdxl', direction: viewDirectionById('iso35'))
              .briefing;
      expect(keywords, contains(gameAssetKeywords));
      expect(keywords, contains(gameAssetNegativeTerms));
      expect(keywords, contains(gameAssetExample));
    });

    test('Der Stil-Schwanz bleibt kurz und ohne die drei Stolpersteine',
        () {
      int words(String t) =>
          t.replaceAll(',', ' ').split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty).length;
      // Die erste Fassung war 47 Wörter lang und hat das Motiv
      // ertränkt. Zusammen mit den Motivwörtern muss der Block unter
      // die 60-Wörter-Grenze von SDXL passen.
      expect(words(gameAssetKeywords), lessThanOrEqualTo(35));
      expect(words(gameAssetKeywords) + gameAssetLeadWords,
          lessThan(promptProfileFor(GenProvider.selfhost, 'sdxl').maxWords));

      // Mengenangaben, Gradzahlen und „boulders" sind raus. („3d" in
      // „3d building model" ist keine Mengenangabe – geprüft wird
      // deshalb auf eine Zahl als eigenes Wort.)
      expect(gameAssetKeywords, isNot(contains('boulder')));
      expect(gameAssetKeywords, isNot(matches(RegExp(r'\b\d+\s'))));
      expect(gameAssetKeywords, isNot(contains('degree')));

      // Der Blickwinkel braucht alle drei Angaben: Ein Schlagwort
      // allein („high angle isometric view") blieb zu flach.
      expect(gameAssetKeywords, contains('isometric view from high above'));
      expect(gameAssetKeywords, contains('looking down onto the roof'));
      expect(gameAssetKeywords, contains('tilted top view'));

      // Die Vereinzelung steht positiv im Prompt, nicht nur im
      // Negativ-Block.
      expect(gameAssetKeywords, contains('single isolated 3d building'));

      // Und kein Wort über den Boden: „centered on empty ground" hat
      // den Gras- und Erdfleck zurückgeholt. „background" zählt
      // nicht, deshalb die Wortgrenze.
      expect(gameAssetKeywords, isNot(matches(RegExp(r'\bground\b'))));
      expect(gameAssetKeywords, isNot(contains('diorama')));

      // Was im Negativ-Block stehen muss, steht dort auch.
      for (final term in [
        'grass patch',
        'dirt patch',
        'moss',
        'ground plate',
        'pedestal',
        'diorama',
        'front view',
        'side view',
        'eye level',
        'onion dome',
      ]) {
        expect(gameAssetNegativeTerms, contains(term), reason: term);
      }
    });

    test('Der erprobte Block passt in das SDXL-Budget', () {
      int words(String t) => t
          .replaceAll(',', ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      final prompt = gameAssetExample
          .split('\n')
          .firstWhere((l) => l.startsWith('PROMPT: '))
          .substring('PROMPT: '.length);
      expect(words(prompt),
          lessThan(promptProfileFor(GenProvider.selfhost, 'sdxl').maxWords));
      // Das erkennende Merkmal steht ausgeschrieben und weit vorn –
      // aus „big domed stone oven" wurden sonst zwei Schornsteine.
      expect(prompt, startsWith('medieval bakery, large domed bread oven '
          'attached to the side wall'));
    });

    test('Die Stichwort-Vorlage warnt vor den drei Stolpersteinen', () {
      final text =
          promptProfileFor(GenProvider.selfhost, 'sdxl', direction: viewDirectionById('iso35'))
              .briefing;
      expect(text, contains('Mengenangaben'));
      expect(text, contains('Gradzahlen'));
      expect(text, contains('boulders'));
      expect(text, contains('$gameAssetLeadWords Wörtern'));
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
