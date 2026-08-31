import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/project_tree.dart';

void main() {
  group('Pfade aufräumen', () {
    test('Leerzeichen, doppelte Striche und leere Ebenen fallen weg', () {
      expect(normalizeProject('  Burgenspiel / Gebäude //Türme '),
          'Burgenspiel/Gebäude/Türme');
      expect(normalizeProject('///'), '');
      expect(normalizeProject(''), '');
    });

    test('Eltern und Name', () {
      expect(parentProject('a/b/c'), 'a/b');
      expect(parentProject('a'), '');
      expect(projectName('a/b/c'), 'c');
      expect(projectName(''), '');
    });

    test('Der Krümelpfad nennt jede Ebene', () {
      expect(projectTrail('a/b/c'), ['a', 'a/b', 'a/b/c']);
      expect(projectTrail(''), isEmpty);
    });
  });

  group('Liegt darin', () {
    test('Der Ordner selbst zählt mit, der leere Ordner ist alles', () {
      expect(projectIsInside('a/b', 'a'), isTrue);
      expect(projectIsInside('a', 'a'), isTrue);
      expect(projectIsInside('a', 'a/b'), isFalse);
      expect(projectIsInside('a/b', ''), isTrue);
    });

    test('Verglichen wird ebenenweise, nicht als Textanfang', () {
      // „Burg" darf „Burgenspiel" nicht einschließen – bei einem
      // Textvergleich waere genau das passiert.
      expect(projectIsInside('Burgenspiel/Turm', 'Burg'), isFalse);
      expect(projectIsInside('Burg/Turm', 'Burg'), isTrue);
    });
  });

  group('Baum bauen', () {
    test('Zwischenebenen entstehen von selbst', () {
      final tree = buildProjectTree([
        'Spiel/Gebäude/Türme',
        'Spiel/Gebäude/Türme',
        'Spiel/Figuren',
      ]);
      expect(tree.length, 1);
      final spiel = tree.first;
      expect(spiel.name, 'Spiel');
      // „Spiel" selbst hat keinen eigenen Eintrag, nur seine Kinder.
      expect(spiel.directCount, 0);
      expect(spiel.totalCount, 3);
      expect(spiel.children.map((c) => c.name), ['Figuren', 'Gebäude']);
      final gebaeude =
          spiel.children.firstWhere((c) => c.name == 'Gebäude');
      expect(gebaeude.totalCount, 2);
      expect(gebaeude.children.single.name, 'Türme');
      expect(gebaeude.children.single.directCount, 2);
    });

    test('Ein leerer Ordner ist da, zählt aber nichts', () {
      // Ohne das wäre ein frisch angelegtes Projekt unsichtbar, bis
      // das erste Bild darin landet – man legt einen Ordner an und
      // nichts passiert.
      final tree = buildProjectTree(['Spiel/Figuren'],
          empty: ['Spiel/Gebäude/Türme']);
      final spiel = tree.single;
      expect(spiel.totalCount, 1);
      expect(spiel.children.map((c) => c.name), ['Figuren', 'Gebäude']);
      final tuerme =
          spiel.children.last.children.single;
      expect(tuerme.name, 'Türme');
      expect(tuerme.directCount, 0);
      expect(tuerme.totalCount, 0);
    });

    test('Ein leerer Ordner neben einem gefüllten mit gleichem Namen '
        'verschmilzt', () {
      final tree =
          buildProjectTree(['Burg'], empty: ['Burg']);
      expect(tree.single.directCount, 1);
    });

    test('Nicht einsortierte Einträge tauchen im Baum nicht auf', () {
      expect(buildProjectTree(['', '  ', '///']), isEmpty);
    });

    test('Alphabetisch, ohne Rücksicht auf Groß- und Kleinschreibung', () {
      final tree = buildProjectTree(['zeta', 'Alpha', 'beta']);
      expect(tree.map((n) => n.name), ['Alpha', 'beta', 'zeta']);
    });
  });

  group('Umbenennen und verschieben', () {
    test('Unterordner wandern mit', () {
      expect(reparentProject('a/b/c', 'a/b', 'x/y'), 'x/y/c');
      expect(reparentProject('a/b', 'a/b', 'neu'), 'neu');
    });

    test('Was nicht darin liegt, bleibt unberührt', () {
      expect(reparentProject('anderes/b', 'a', 'x'), 'anderes/b');
    });

    test('Auf die oberste Ebene ziehen', () {
      expect(reparentProject('a/b/c', 'a/b', ''), 'c');
    });
  });

  group('Doppelte Namen', () {
    test('Ein belegter Name bekommt eine Nummer', () {
      final da = {'Spiel', 'Spiel (2)'};
      expect(uniqueProject('Spiel', da), 'Spiel (3)');
      expect(uniqueProject('Neu', da), 'Neu');
    });
  });
}
