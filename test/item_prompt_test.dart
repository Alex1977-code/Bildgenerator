import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/item_prompt.dart';
import 'package:bildgenerator/services/roblox_prompt.dart'
    show robloxAccessoryTail, robloxAccessoryNegative;
import 'package:bildgenerator/services/run_stats.dart'
    show rideableItemKinds;

void main() {
  group('Der Katalog', () {
    test('Jede Art ist vollständig und eindeutig', () {
      final ids = <String>{};
      for (final kind in itemKinds) {
        expect(ids.add(kind.id), isTrue, reason: 'doppelt: ${kind.id}');
        expect(kind.label, isNotEmpty);
        expect(kind.core.length, greaterThan(20), reason: kind.id);
        expect(kind.share, greaterThan(0), reason: kind.id);
        expect(kind.carry, isNotEmpty, reason: kind.id);
        expect(kind.words, isNotEmpty, reason: kind.id);
      }
      expect(itemKinds.length, greaterThan(15));
    });

    test('Nur echte Werte der Roblox-Aufzählung AccessoryType', () {
      // Aus der offiziellen Referenz; ein erfundener Wert wäre in
      // Studio schlicht nicht auswählbar.
      const erlaubt = {
        'Hat', 'Hair', 'Face', 'Neck', 'Shoulder', 'Front', 'Back',
        'Waist',
      };
      for (final kind in itemKinds) {
        final type = kind.robloxAccessoryType;
        if (type != null) {
          expect(erlaubt, contains(type), reason: kind.id);
        }
      }
    });

    test('Suchen und Gruppieren', () {
      expect(itemKindById('schwert')!.label, 'Schwert');
      expect(itemKindById('gibtsnicht'), isNull);
      expect(itemGroups, contains('Waffe'));
      expect(itemGroups.length, greaterThan(2));
    });
  });

  group('Vorschläge aus der Figurbeschreibung', () {
    List<String> ids(String prompt) =>
        [for (final k in suggestedItems(prompt)) k.id];

    test('Ein Ritter bekommt Schwert, Schild und Helm', () {
      final v = ids('a stout knight in plate armour, T-pose');
      expect(v, contains('schwert'));
      expect(v, contains('schild'));
      expect(v, contains('helm'));
    });

    test('Ein Zauberer bekommt Stab, Hut und Buch – kein Schild', () {
      final v = ids('ein alter Zauberer mit langem Bart, Magier');
      expect(v, contains('stab'));
      expect(v, contains('hut'));
      expect(v, isNot(contains('schild')));
    });

    test('Deutsch und Englisch werden beide erkannt', () {
      expect(ids('ein Bogenschütze im Wald'), contains('bogen'));
      expect(ids('a hunter with a bow'), contains('bogen'));
    });

    test('Ohne Anhaltspunkt kommt eine Grundausstattung statt einer '
        'leeren Liste', () {
      final v = ids('ein blaues Wesen mit drei Augen');
      expect(v, isNotEmpty);
      expect(v, contains('schwert'));
    });

    test('Die Reihenfolge ist stabil', () {
      const prompt = 'a knight with a sword';
      expect(ids(prompt), ids(prompt));
    });

    test('Die Zahl der Vorschläge lässt sich begrenzen', () {
      expect(suggestedItems('a knight in armour', limit: 3).length, 3);
    });
  });

  group('Größe im Verhältnis zur Figur', () {
    test('Eine Waffe misst sich an der Figur, ein Helm am Kopf', () {
      // Roblox-Figur: 5 Studs hoch.
      final schwert = itemKindById('schwert')!;
      expect(itemSize(schwert, 5), closeTo(2.75, 1e-9));
      // Der Helm bezieht sich auf den Kopf (0,25 der Höhe), nicht auf
      // die Figur – sonst käme ein Helm von über sechs Studs heraus.
      final helm = itemKindById('helm')!;
      expect(itemSize(helm, 5), closeTo(5 * 0.25 * 1.25, 1e-9));
      expect(itemSize(helm, 5), lessThan(2));
    });

    test('Ein Handgegenstand bleibt klein', () {
      final trank = itemKindById('trank')!;
      expect(itemSize(trank, 5), lessThan(1));
    });

    test('Der Maßstab-Satz nennt Zahl und Bezug', () {
      final note = itemScaleNote(itemKindById('schwert')!, 5);
      expect(note, contains('2,75'));
      expect(note, contains('Studs'));
      expect(note, contains('Figurenhöhe'));
      expect(itemScaleNote(itemKindById('helm')!, 5),
          contains('Kopfhöhe'));
    });

    test('Der englische Satz nennt ein Verhältnis, keine Studs', () {
      // Ein Bildmodell kennt keine Studs, aber Verhältnisse.
      final schwert = itemScaleClause(itemKindById('schwert')!);
      expect(schwert, contains("character's full height"));
      expect(schwert, isNot(contains('stud')));
      expect(itemScaleClause(itemKindById('speer')!),
          contains('1.2 times'));
      expect(itemScaleClause(itemKindById('trank')!),
          contains("character's hand"));
    });
  });

  group('Der Prompt', () {
    const figur = 'PROMPT: a stout knight in plate armour, broad '
        'shoulders, matte steel with warm brass trim, single connected '
        'body, watertight shell, single mesh\nNEGATIV: low poly';

    test('Ohne Referenzbild wandert der Figurenstil in den Text', () {
      final p = itemPrompt(
          kind: itemKindById('schwert')!, figurePrompt: figur);
      expect(p, startsWith('PROMPT: '));
      expect(p, contains('one-handed sword'));
      expect(p, contains('matte steel'));
      expect(p, contains('NEGATIV: '));
    });

    test('Mit Referenzbild verweist er aufs Bild', () {
      final p = itemPrompt(
          kind: itemKindById('schwert')!,
          figurePrompt: figur,
          withReference: true);
      expect(p, contains('reference image'));
      // Und sagt ausdrücklich, dass die Figur nicht mitzumalen ist –
      // Modelle ohne Negativ-Prompt (Turbo, FLUX) hören sonst nichts
      // davon.
      expect(p, contains('no character in the image'));
    });

    test('„character" steht ganz vorn im Negativ-Prompt', () {
      // Der häufigste Fehlschlag: Das Schwert kommt samt Hand.
      expect(itemNegative, startsWith('character'));
      expect(itemNegative, contains('hand'));
    });

    test('Im Roblox-Modus gelten die Roblox-Bausteine', () {
      final p = itemPrompt(
        kind: itemKindById('helm')!,
        figurePrompt: figur,
        roblox: true,
        accessoryTail: robloxAccessoryTail,
        accessoryNegative: robloxAccessoryNegative,
      );
      expect(p, contains(robloxAccessoryTail));
      expect(p, contains(robloxAccessoryNegative));
    });

    test('Die Figurbeschreibung wird gekürzt, nicht angehängt', () {
      final lang = 'PROMPT: ${'ein sehr langer Satz über die Figur, ' * 20}';
      final hint = figureStyleHint(lang);
      expect(hint.length, lessThanOrEqualTo(180));
      expect(hint, isNot(contains('PROMPT:')));
      // Sauber an einer Kommagrenze abgeschnitten.
      expect(hint, isNot(endsWith(',')));
    });

    test('Ein kurzer Prompt bleibt unangetastet', () {
      expect(figureStyleHint('ein Ritter'), 'ein Ritter');
    });
  });

  group('Mehrere Gegenstände auf einmal', () {
    test('Ein Block je Gegenstand, mit Namen für die Galerie', () {
      final block = itemBatchPrompt(
        kinds: [itemKindById('schwert')!, itemKindById('schild')!],
        figurePrompt: 'a knight',
        figureName: 'Burg Ritter 01',
      );
      expect(block, contains('NAME: burg-ritter-01-schwert'));
      expect(block, contains('NAME: burg-ritter-01-schild'));
      expect('\n$block'.split('\nNAME: ').length - 1, 2);
    });

    test('Ohne Figurnamen bleibt ein brauchbarer Ersatz', () {
      final block = itemBatchPrompt(
        kinds: [itemKindById('trank')!],
        figurePrompt: 'a mage',
        figureName: '  ',
      );
      expect(block, contains('NAME: item-trank'));
    });
  });

  group('Fortbewegung', () {
    test('Reittiere und Fahrzeuge brauchen ein Skelett', () {
      // Ohne Skelett kann der Strauß nicht laufen und die Räder
      // drehen sich nicht.
      expect(itemKindById('reitvogel')!.rigType, 'bird');
      expect(itemKindById('reitpferd')!.rigType, 'quadruped');
      expect(itemKindById('auto')!.rigType, 'vehicle');
      expect(itemKindById('reitvogel')!.needsRig, isTrue);
      expect(itemKindById('schwert')!.needsRig, isFalse);
    });

    test('Sie sind weder Accessoire noch Werkzeug', () {
      final vogel = itemKindById('reitvogel')!;
      expect(vogel.rideable, isTrue);
      expect(vogel.handHeld, isFalse);
      expect(vogel.robloxAccessoryType, isNull);
      expect(robloxAttachNote(vogel), contains('Seat'));
      expect(robloxAttachNote(itemKindById('auto')!),
          contains('VehicleSeat'));
    });

    test('„rider" steht im Negativ-Prompt', () {
      // Sonst kommt das Pferd mit Reiter, und der steckt danach im
      // Netz.
      final (_, negativ) = itemPromptParts(
          kind: itemKindById('reitpferd')!, figurePrompt: 'a knight');
      expect(negativ, startsWith('rider'));
    });

    test('Der Größensatz spricht vom Aufsitzen, nicht von Vielfachen',
        () {
      // „1,5-mal so hoch wie die Figur" sagt nichts Brauchbares –
      // entscheidend ist die Sitzhöhe.
      final satz = itemScaleSentence(itemKindById('reitvogel')!);
      expect(satz, contains('ride'));
      expect(satz, contains('hip height'));
    });

    test('Die Liste in der Statistik deckt sich mit dem Katalog', () {
      // Zwei Listen, die auseinanderlaufen könnten: hier die Arten,
      // dort die Motivklasse „fortbewegung".
      final ausKatalog = {
        for (final kind in itemKinds)
          if (kind.rideable) kind.id,
      };
      expect(rideableItemKinds, ausKatalog);
    });
  });

  group('Anbau in Roblox', () {
    test('Getragenes nennt seinen AccessoryType', () {
      expect(robloxAttachNote(itemKindById('helm')!), contains('Hat'));
      expect(robloxAttachNote(itemKindById('rucksack')!),
          contains('Back'));
    });

    test('Handgehaltenes wird ein Tool mit Handle', () {
      final note = robloxAttachNote(itemKindById('schwert')!);
      expect(note, contains('Tool'));
      expect(note, contains('Handle'));
      expect(itemKindById('schwert')!.handHeld, isTrue);
      expect(itemKindById('helm')!.handHeld, isFalse);
    });
  });
}
