import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/batch_prompt.dart';
import 'package:bildgenerator/services/prompt_briefing.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';

void main() {
  group('Massenprompt lesen', () {
    test('Blöcke, Namen, Referenzen und Negativ-Prompt', () {
      final plan = parseBatchPrompt(
        'NAME: burg-01\n'
        'PROMPT: A castle at night\n'
        'NEGATIV: people, text\n'
        '---\n'
        'NAME: burg-02\n'
        'REF: burg.png, skizze.jpg\n'
        'PROMPT: The same castle at noon,\n'
        'birds in the sky\n',
        availableReferences: ['burg.png', 'Skizze.JPG'],
      );
      expect(plan.isValid, isTrue, reason: plan.issues.join('; '));
      expect(plan.items.length, 2);
      expect(plan.items.first.name, 'burg-01');
      expect(plan.items.first.negativePrompt, 'people, text');
      expect(plan.items.first.references, isEmpty);
      // Mehrzeiliger Prompt bleibt zusammen.
      expect(plan.items[1].prompt,
          'The same castle at noon,\nbirds in the sky');
      // Referenzen werden auf die echten Dateinamen abgebildet.
      expect(plan.items[1].references, ['burg.png', 'Skizze.JPG']);
      expect(plan.withReferences, 1);
    });

    test('Doppelte Namen blockieren den Lauf', () {
      final plan = parseBatchPrompt(
        'NAME: gleich\nPROMPT: eins\n---\nNAME: gleich\nPROMPT: zwei\n',
      );
      expect(plan.isValid, isFalse);
      expect(plan.issues.single.message, contains('eindeutig'));
      expect(plan.issues.single.line, 4);
    });

    test('Fehlendes Referenzbild blockiert den Lauf', () {
      final plan = parseBatchPrompt(
        'NAME: a\nREF: fehlt.png\nPROMPT: irgendwas\n',
        availableReferences: ['da.png'],
      );
      expect(plan.isValid, isFalse);
      expect(plan.issues.single.message, contains('fehlt.png'));
    });

    test('Fehlender Name ist nur ein Hinweis und wird ergänzt', () {
      final plan = parseBatchPrompt('PROMPT: ohne Namen\n');
      expect(plan.isValid, isTrue);
      expect(plan.items.single.name, 'bild-01');
      expect(plan.warnings, isNotEmpty);
    });

    test('Block ohne Beschreibung wird bemängelt', () {
      final plan = parseBatchPrompt('NAME: leer\n---\nNAME: b\nPROMPT: ok\n');
      expect(plan.isValid, isFalse);
      expect(plan.issues.single.message, contains('keine Bildbeschreibung'));
    });

    test('Leerer Text ergibt eine verständliche Meldung', () {
      final plan = parseBatchPrompt('   \n\n');
      expect(plan.isValid, isFalse);
      expect(plan.items, isEmpty);
      expect(plan.issues.single.message, contains('kein Bild erkannt'));
    });

    test('Text ohne Schlüsselwörter gilt als ein Bild', () {
      final plan = parseBatchPrompt('Ein Hund im Schnee\n---\nEine Katze');
      expect(plan.isValid, isTrue);
      expect(plan.items.length, 2);
      expect(plan.items.first.prompt, 'Ein Hund im Schnee');
    });

    test('Ohne Referenz-Unterstützung gibt es nur einen Hinweis', () {
      final plan = parseBatchPrompt(
        'NAME: a\nREF: da.png\nPROMPT: x\n',
        availableReferences: ['da.png'],
        supportsReferences: false,
      );
      expect(plan.isValid, isTrue);
      expect(plan.warnings.single.message, contains('ignoriert'));
    });

    test('Namen werden zu sicheren Dateinamen', () {
      expect(sanitizeBatchName('Burg bei Nacht'), 'Burg-bei-Nacht');
      expect(sanitizeBatchName('grün/über*'), 'gruen-ueber');
      expect(sanitizeBatchName('   '), 'bild');
      expect(sanitizeBatchName('a' * 90).length, 60);
    });

    test('Das Beispiel im Programm ist für jedes Modell gültig', () {
      for (final profile in [
        promptProfileFor(GenProvider.openai, 'gpt-image-1'),
        promptProfileFor(GenProvider.selfhost, 'sdxl'),
        promptProfileFor(GenProvider.selfhost, 'sdxl-turbo'),
      ]) {
        final plan = parseBatchPrompt(batchPromptExample(profile));
        expect(plan.isValid, isTrue, reason: plan.issues.join('; '));
        expect(plan.items.length, 2);
      }
    });
  });

  group('Massenprompt gegen das gewählte Modell prüfen', () {
    const long = 'NAME: lang\nPROMPT: '
        'a b c d e f g h i j k l m n o p q r s t u v w x y z '
        'a b c d e f g h i j k l m n o p q r s t u v w x y z\n'
        'NEGATIV: text\n';

    test('Zu lange Beschreibung ist ein Hinweis, kein Fehler', () {
      final plan = parseBatchPrompt(long,
          profile: promptProfileFor(GenProvider.selfhost, 'sdxl-turbo'));
      expect(plan.isValid, isTrue);
      expect(plan.warnings.map((w) => w.message).join(' '),
          contains('40 Wörter'));
    });

    test('SDXL Turbo verwirft den Negativ-Prompt – die Prüfung sagt es',
        () {
      final plan = parseBatchPrompt(
        'NAME: a\nPROMPT: castle\nNEGATIV: people, text\n',
        profile: promptProfileFor(GenProvider.selfhost, 'sdxl-turbo'),
      );
      final text = plan.warnings.map((w) => w.message).join(' ');
      expect(text, contains('wirkungslos'));
    });

    test('Gemini bekommt den Negativ-Prompt in den Prompt geschrieben', () {
      final plan = parseBatchPrompt(
        'NAME: a\nPROMPT: A castle at night\nNEGATIV: people\n',
        profile:
            promptProfileFor(GenProvider.gemini, 'gemini-2.5-flash-image'),
      );
      expect(plan.warnings.map((w) => w.message).join(' '),
          contains('Do not include in the image'));
    });

    test('Stable Diffusion: Verneinungen und Überschriften werden gerügt',
        () {
      final plan = parseBatchPrompt(
        'NAME: a\nPROMPT: a castle, no people, no text\n'
        'NEGATIV: blurry\n'
        '---\n'
        'NAME: b\nMOTIV: eine Burg\nPROMPT: STIL: comic, warm\n'
        'NEGATIV: blurry\n',
        profile: promptProfileFor(GenProvider.selfhost, 'sdxl'),
      );
      final text = plan.warnings.map((w) => w.message).join(' ');
      expect(text, contains('Verneinungen'));
      expect(text, contains('Briefing mit Überschriften'));
    });

    test('Fehlt der Negativ-Prompt ganz, gibt es bei SDXL einen Hinweis',
        () {
      final plan = parseBatchPrompt(
        'NAME: a\nPROMPT: a castle at night\n',
        profile: promptProfileFor(GenProvider.selfhost, 'sdxl'),
      );
      expect(plan.warnings.map((w) => w.message).join(' '),
          contains('NEGATIV'));
    });

    test('Spielgrafik: Bodenplatte, zweites Gebäude und Kamerawinkel', () {
      final plan = parseBatchPrompt(
        'NAME: haus\n'
        'PROMPT: A thatched cottage and a tower on a paved terrace with '
        'a low wall\n'
        'NEGATIV: text\n',
        profile: promptProfileFor(GenProvider.openai, 'gpt-image-1'),
        gameAssets: true,
      );
      final text = plan.warnings.map((w) => w.message).join(' ');
      expect(text, contains('Bodenplatte'));
      expect(text, contains('zweites Gebäude'));
      expect(text, contains('35°'));
      expect(plan.isValid, isTrue);
    });

    test('Die empfohlenen Sätze selbst lösen keine Asset-Hinweise aus',
        () {
      // Der zweite Satz nennt „no terrace, no paving, no low wall …",
      // um sie auszuschließen – die Prüfung darf ihn nicht als
      // Bodenplatte lesen.
      final plan = parseBatchPrompt(
        'NAME: haus\nPROMPT: ${gameAssetSentences.join(' ')}\n'
        'NEGATIV: $gameAssetNegativeTerms\n',
        profile: promptProfileFor(GenProvider.openai, 'gpt-image-1'),
        gameAssets: true,
      );
      final text = plan.warnings.map((w) => w.message).join(' ');
      expect(text, isNot(contains('Spielgrafik')), reason: text);
    });

    test('Der erprobte Block löst keine Asset-Hinweise aus', () {
      final plan = parseBatchPrompt(
        gameAssetExample,
        profile: promptProfileFor(GenProvider.selfhost, 'sdxl'),
        gameAssets: true,
      );
      final text = plan.warnings.map((w) => w.message).join(' ');
      expect(plan.isValid, isTrue);
      expect(text, isNot(contains('Spielgrafik')), reason: text);
      // Und er bleibt unter der Wortgrenze von SDXL.
      expect(text, isNot(contains('Wörter')), reason: text);
    });

    test('Die drei Stolpersteine des Bäckerei-Blocks werden gemeldet', () {
      final plan = parseBatchPrompt(
        'NAME: bakery\n'
        'PROMPT: single isolated building, stylized diorama game asset, '
        'medieval bakery, camera elevation 35 degrees looking down onto '
        'the roof, coarse masonry of large softly rounded boulders, at '
        'most 15 stone courses over the wall height\n'
        'NEGATIV: $gameAssetNegativeTerms\n',
        profile: promptProfileFor(GenProvider.selfhost, 'sdxl'),
        gameAssets: true,
      );
      final text = plan.warnings.map((w) => w.message).join(' ');
      // Mengenangabe: das Modell zählt nicht.
      expect(text, contains('Mengenangaben'));
      // Gradzahl: kein Winkelbegriff für ein Diffusions-Modell.
      expect(text, contains('Gradzahl'));
      // „boulders" hat die Häuser zu Findlings-Kuppeln gemacht.
      expect(text, contains('boulders'));
      // Und der Stil steht vor dem Motiv.
      expect(text, contains('ersten 15 Wörtern'));
    });

    test('Bei sprachverstehenden Modellen bleibt die Gradzahl richtig',
        () {
      final plan = parseBatchPrompt(
        'NAME: haus\nPROMPT: ${gameAssetSentences.join(' ')}\n'
        'NEGATIV: $gameAssetNegativeTerms\n',
        profile: promptProfileFor(GenProvider.openai, 'gpt-image-1'),
        gameAssets: true,
      );
      final text = plan.warnings.map((w) => w.message).join(' ');
      // GPT-Image versteht „35 degrees" – kein Hinweis dazu.
      expect(text, isNot(contains('Gradzahl')));
      expect(text, isNot(contains('Mengenangaben')));
      expect(text, isNot(contains('Spielgrafik')), reason: text);
    });
  });

  group('Vorlage für die Prompt-KI', () {
    test('Die Vorlage nennt Modell, Länge und Negativ-Regel', () {
      final profile = promptProfileFor(GenProvider.selfhost, 'sdxl');
      final text = batchPromptBriefing(profile,
          references: ['burg.png']);
      expect(text, contains('SDXL'));
      expect(text, contains('60 Wörter'));
      expect(text, contains('Stichwortkette'));
      expect(text, contains('burg.png'));
    });

    test('Bei FLUX steht in der Vorlage, dass NEGATIV nichts bringt', () {
      final text = batchPromptBriefing(
          promptProfileFor(GenProvider.selfhost, 'flux-schnell'));
      expect(text, contains('wertet sie nicht aus'));
    });

    test('Bei Gemini verlangt die Vorlage ganze Sätze', () {
      final text = batchPromptBriefing(
          promptProfileFor(GenProvider.gemini, 'gemini-2.5-flash-image'));
      expect(text, contains('ganzen Sätzen'));
      expect(text, contains('Do not include in the image'));
    });

    test('Spielgrafik-Regeln stehen wörtlich in der Vorlage', () {
      final text = batchPromptBriefing(
          promptProfileFor(GenProvider.openai, 'gpt-image-1'),
          gameAssets: true);
      for (final sentence in gameAssetSentences) {
        expect(text, contains(sentence));
      }
      expect(text, contains('ROWH 32 auf TILE 52'));
    });

    test('Für Stable Diffusion werden die Regeln zu Stichworten', () {
      final text = batchPromptBriefing(
          promptProfileFor(GenProvider.selfhost, 'sdxl'),
          gameAssets: true);
      expect(text, contains(gameAssetKeywords));
      expect(text, contains(gameAssetNegativeTerms));
      expect(text, isNot(contains(gameAssetSentences.first)));
      // Das Beispiel in der Vorlage ist der erprobte Block.
      expect(text, contains('bld-02-bakery'));
    });

    test('„Beispiel einfügen" liefert bei Spielgrafik den Block', () {
      final profile = promptProfileFor(GenProvider.selfhost, 'sdxl');
      expect(batchPromptExample(profile, gameAssets: true),
          gameAssetExample);
      // Ohne den Schalter bleibt es beim allgemeinen Beispiel.
      expect(batchPromptExample(profile), isNot(gameAssetExample));
    });
  });

  group('Verlauf mit Namen', () {
    test('Bilder aus dem Massenprompt landen unter ihrem Namen', () async {
      final history = HistoryService(store: MemoryHistoryStore());
      final request = GenerationRequest(
        provider: GenProvider.openai,
        prompt: 'A castle',
      );
      final image = GeneratedImage(
          bytes: Uint8List.fromList([1, 2, 3]), format: 'png');

      await history.addResults(request, [image], name: 'burg-01');
      final entry = history.entries.single;
      expect(entry.name, 'burg-01');
      expect(entry.fileName, 'burg-01.png');
      expect(entry.title, 'burg-01');
    });

    test('Derselbe Name zweimal überschreibt nichts', () async {
      final history = HistoryService(store: MemoryHistoryStore());
      final request = GenerationRequest(
        provider: GenProvider.openai,
        prompt: 'A castle',
      );
      final image = GeneratedImage(
          bytes: Uint8List.fromList([1, 2, 3]), format: 'png');

      await history.addResults(request, [image], name: 'burg-01');
      await history.addResults(request, [image], name: 'burg-01');
      final names = history.entries.map((e) => e.name).toList();
      expect(names, containsAll(['burg-01', 'burg-01-2']));
    });

    test('Mehrere Bilder eines Blocks werden durchnummeriert', () async {
      final history = HistoryService(store: MemoryHistoryStore());
      final request = GenerationRequest(
        provider: GenProvider.openai,
        prompt: 'A castle',
        count: 2,
      );
      final image = GeneratedImage(
          bytes: Uint8List.fromList([1, 2, 3]), format: 'png');

      await history.addResults(request, [image, image], name: 'burg');
      final names = history.entries.map((e) => e.name).toList();
      expect(names, containsAll(['burg-1', 'burg-2']));
    });

    test('Ohne Namen bleibt alles wie bisher', () async {
      final history = HistoryService(store: MemoryHistoryStore());
      final request = GenerationRequest(
        provider: GenProvider.openai,
        prompt: 'A castle',
      );
      await history.addResults(
          request,
          [GeneratedImage(bytes: Uint8List.fromList([1]), format: 'png')]);
      final entry = history.entries.single;
      expect(entry.name, isEmpty);
      expect(entry.title, 'A castle');
      expect(entry.fileName, '${entry.id}.png');
    });

    test('Name übersteht das Speichern und Laden des Verlaufs', () {
      final entry = HistoryEntry(
        id: 'x',
        prompt: 'A castle',
        providerLabel: 'OpenAI',
        createdAt: DateTime(2026, 8, 30),
        params: const {},
        format: 'png',
        fileName: 'burg-01.png',
        name: 'burg-01',
      );
      final back = HistoryEntry.fromJson(entry.toJson());
      expect(back.name, 'burg-01');
      expect(back.fileName, 'burg-01.png');
    });
  });
}
