import 'package:bildgenerator/services/asset_pack.dart';
import 'package:flutter_test/flutter_test.dart';

const _stil = PackStyle(
  block: 'low-poly game asset, matte painted wood and iron, soft even '
      'lighting, three quarter view',
  negative: 'text, logo, floating parts',
  seed: 4711,
);

const _satz = [
  PackItem(name: 'Fass', subject: 'a wooden barrel with three iron bands'),
  PackItem(name: 'Kiste', subject: 'a wooden crate with iron corners'),
  PackItem(name: 'Sack', subject: 'a burlap sack tied with rope'),
];

void main() {
  group('Die Stil-Sperre', () {
    test('jeder Auftrag trägt denselben Block, wörtlich', () {
      final plan = buildPack(_satz, _stil);
      expect(plan.isValid, isTrue);
      expect(plan.jobs.length, 3);
      expect(plan.styleLocked, isTrue);
      for (final job in plan.jobs) {
        expect(job.prompt, endsWith(_stil.block));
        expect(job.negative, _stil.negative);
      }
    });

    test('das Motiv steht vorn, der Stil hinten', () {
      // Text→3D-Modelle wichten frühe Begriffe stärker – das Motiv
      // muss zuerst kommen.
      final plan = buildPack(_satz, _stil);
      expect(plan.jobs.first.prompt,
          startsWith('a wooden barrel with three iron bands'));
    });

    test('derselbe Seed für alle', () {
      final plan = buildPack(_satz, _stil);
      expect(plan.jobs.map((j) => j.seed).toSet(), {4711});
    });

    test('ohne Seed-Sperre bekommt keiner einen', () {
      final plan = buildPack(
          _satz, const PackStyle(block: 'x y z', seed: 1, lockSeed: false));
      expect(plan.jobs.every((j) => j.seed == null), isTrue);
      expect(plan.issues.map((i) => i.message).join(),
          contains('nicht gesperrt'));
    });

    test('ohne Seed sagt die App, was das kostet', () {
      final plan = buildPack(_satz, const PackStyle(block: 'x y z'));
      expect(plan.isValid, isTrue);
      expect(plan.issues.map((i) => i.message).join(),
          contains('würfelt'));
    });
  });

  group('Was den Satz kaputtmacht', () {
    test('Stilwörter im Motiv heben die Sperre auf', () {
      final plan = buildPack(const [
        PackItem(name: 'Fass', subject: 'a glossy wooden barrel'),
        PackItem(name: 'Kiste', subject: 'a wooden crate'),
      ], _stil);
      // Nicht blockierend – aber gemeldet, mit dem Grund.
      expect(plan.isValid, isTrue);
      final hinweis = plan.issues.firstWhere((i) => i.item == 'Fass');
      expect(hinweis.message, contains('glossy'));
      expect(hinweis.message, contains('Stilblock'));
    });

    test('doppelte Namen würden Dateien überschreiben', () {
      final plan = buildPack(const [
        PackItem(name: 'Fass', subject: 'a barrel'),
        PackItem(name: 'fass', subject: 'another barrel'),
      ], _stil);
      expect(plan.isValid, isFalse);
      expect(plan.blockers.first.message, contains('überschreiben'));
    });

    test('ohne Stilblock ist es nur eine Liste', () {
      final plan = buildPack(_satz, const PackStyle(block: '   '));
      expect(plan.isValid, isFalse);
      expect(plan.blockers.map((b) => b.message).join(),
          contains('Stilblock'));
    });

    test('ein leerer Satz blockiert', () {
      expect(buildPack(const [], _stil).isValid, isFalse);
    });

    test('zu viele Gegenstände sind vor allem eine Rechnung', () {
      final viele = [
        for (var i = 0; i < packMaxItems + 1; i++)
          PackItem(name: 'Teil $i', subject: 'a thing number $i'),
      ];
      final plan = buildPack(viele, _stil);
      expect(plan.isValid, isFalse);
      expect(plan.blockers.first.message, contains('Rechnung'));
    });

    test('ein Gegenstand ohne Motiv blockiert', () {
      final plan = buildPack(
          const [PackItem(name: 'Fass', subject: '  ')], _stil);
      expect(plan.isValid, isFalse);
    });
  });

  group('Der Satz aus Text', () {
    const text = '''
# Requisiten für eine Taverne
Fass: a wooden barrel with three iron bands
Kiste: a wooden crate with iron corners

STIL: low-poly game asset, matte painted wood
NEGATIV: text, logo
''';

    test('liest Gegenstände, Stil und Negativ getrennt', () {
      final (:items, :style) = parsePackText(text, seed: 99);
      expect(items.length, 2);
      expect(items.first.name, 'Fass');
      expect(items.first.subject, 'a wooden barrel with three iron bands');
      expect(style.block, 'low-poly game asset, matte painted wood');
      expect(style.negative, 'text, logo');
      expect(style.seed, 99);
    });

    test('Kommentarzeilen bleiben draußen', () {
      final (:items, style: _) = parsePackText(text);
      expect(items.map((i) => i.name), isNot(contains('# Requisiten')));
    });

    test('eine Zeile ohne Doppelpunkt geht nicht verloren', () {
      // Besser ein abgeleiteter Name als eine weggeworfene Zeile.
      final (:items, style: _) =
          parsePackText('a rusty iron lantern\nSTIL: matte');
      expect(items.length, 1);
      expect(items.first.subject, 'a rusty iron lantern');
      expect(items.first.name, 'a rusty iron');
      expect(items.first.note, contains('abgeleitet'));
    });

    test('mehrzeiliger Stil wird zusammengefügt', () {
      final (items: _, :style) = parsePackText('''
Fass: a barrel
STIL: low-poly game asset,
matte painted wood,
soft lighting
''');
      expect(style.block,
          'low-poly game asset, matte painted wood, soft lighting');
    });

    test('der Dateiname ist unbedenklich', () {
      final (:items, style: _) =
          parsePackText('Großes Fass / Nr. 1: a barrel');
      expect(items.first.fileName, isNot(contains('/')));
      expect(items.first.fileName, isNot(contains('ß')));
    });
  });

  test('das Briefing sagt, was ins Motiv gehört und was nicht', () {
    final text = packBriefing();
    expect(text, contains('STIL:'));
    expect(text, contains('NEGATIV:'));
    expect(text, contains('WÖRTLICH'));
    expect(text, contains('KEINE Stilwörter im Motiv'));
  });
}
