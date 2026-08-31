import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/prompt_drop.dart';

void main() {
  group('Welche Dateien gelten', () {
    test('Text und Markdown, sonst nichts', () {
      expect(isPromptTextFile('prompts.txt'), isTrue);
      expect(isPromptTextFile('Beschreibung.MD'), isTrue);
      expect(isPromptTextFile('a.markdown'), isTrue);
      expect(isPromptTextFile('bild.png'), isFalse);
      expect(isPromptTextFile('modell.glb'), isFalse);
      expect(isPromptTextFile('ohne-endung'), isFalse);
    });
  });

  group('Inhalt aufräumen', () {
    test('Eine BOM fliegt raus', () {
      // Sonst steht ein unsichtbares Zeichen vor dem ersten Wort und
      // wandert in den Prompt.
      expect(cleanPromptText('﻿ein Ritter'), 'ein Ritter');
    });

    test('Windows-Zeilenenden werden vereinheitlicht', () {
      // Der Massenprompt trennt Blöcke an Leerzeilen – ein „\r" macht
      // aus einer Leerzeile eine Zeile mit Inhalt.
      expect(cleanPromptText('a\r\n\r\nb'), 'a\n\nb');
      expect(cleanPromptText('a\rb'), 'a\nb');
    });

    test('Ein umschließender Codeblock fällt weg', () {
      // Prompt-KIs geben ihre Ergebnisse gern so aus.
      expect(cleanPromptText('```\nein Ritter\n```'), 'ein Ritter');
      expect(cleanPromptText('```text\nein Ritter\n```'), 'ein Ritter');
    });

    test('Backticks mitten im Text bleiben', () {
      const text = 'NAME: a\n```\nnicht alles\n```\nNAME: b';
      expect(cleanPromptText(text), text);
    });

    test('Rand wird getrimmt, Inneres nicht angetastet', () {
      expect(cleanPromptText('  \n a\n\n b \n  '), 'a\n\n b');
    });
  });

  group('Anhängen statt ersetzen', () {
    test('Vorhandenes bleibt erhalten', () {
      // Wer schon getippt hat, soll es durch eine abgelegte Datei
      // nicht verlieren.
      expect(appendPromptText('ein Ritter', 'ein Turm'),
          'ein Ritter\n\nein Turm');
    });

    test('In ein leeres Feld kommt nur der neue Text', () {
      expect(appendPromptText('', 'ein Turm'), 'ein Turm');
      expect(appendPromptText('   ', 'ein Turm'), 'ein Turm');
    });

    test('Eine leere Datei ändert nichts', () {
      expect(appendPromptText('ein Ritter', '   \n\n '), 'ein Ritter');
      expect(appendPromptText('ein Ritter', '```\n\n```'), 'ein Ritter');
    });

    test('Die Trennung ist eine Leerzeile – die Blockgrenze', () {
      final text = appendPromptText('NAME: a\nPROMPT: x', 'NAME: b\nPROMPT: y');
      expect(text.split('\n\n').length, 2);
    });
  });

  group('Meldung nach dem Ablegen', () {
    test('Nennt Übernommenes und Übergangenes', () {
      final text = promptDropSummary(['a.txt'], ['b.png']);
      expect(text, contains('1 Datei übernommen'));
      expect(text, contains('a.txt'));
      expect(text, contains('übergangen: b.png'));
    });

    test('Nur Übernommenes, wenn nichts abgelehnt wurde', () {
      final text = promptDropSummary(['a.txt', 'b.md'], []);
      expect(text, contains('2 Dateien'));
      expect(text, isNot(contains('übergangen')));
    });
  });
}
