import 'package:flutter_test/flutter_test.dart';
import 'package:bildgenerator/services/selection_range.dart';

void main() {
  const ids = ['a', 'b', 'c', 'd', 'e'];

  group('Bereichsauswahl', () {
    test('Vorwärts nimmt beide Enden mit', () {
      expect(selectionRange(ids, 'b', 'd'), ['b', 'c', 'd']);
    });

    test('Rückwärts ergibt denselben Bereich', () {
      expect(selectionRange(ids, 'd', 'b'), ['b', 'c', 'd']);
    });

    test('Anker gleich Ziel ist eine Kachel', () {
      expect(selectionRange(ids, 'c', 'c'), ['c']);
    });

    test('Ohne Anker bleibt es beim Ziel', () {
      expect(selectionRange(ids, null, 'c'), ['c']);
    });

    test('Ein verschwundener Anker wird nicht geraten', () {
      // Die Ankerkachel wurde inzwischen einsortiert und ist aus der
      // Ansicht verschwunden. Dann von der ersten Kachel an zu
      // markieren wäre eine Überraschung.
      expect(selectionRange(ids, 'weg', 'c'), ['c']);
    });

    test('Ein unbekanntes Ziel markiert nichts', () {
      expect(selectionRange(ids, 'a', 'weg'), isEmpty);
    });

    test('Der ganze Bereich ist möglich', () {
      expect(selectionRange(ids, 'a', 'e'), ids);
    });
  });
}
