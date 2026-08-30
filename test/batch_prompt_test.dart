import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/batch_prompt.dart';
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

    test('Das Beispiel im Programm ist gültig', () {
      final plan = parseBatchPrompt(batchPromptExample);
      expect(plan.isValid, isTrue, reason: plan.issues.join('; '));
      expect(plan.items.length, 3);
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
