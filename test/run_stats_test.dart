import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/run_stats.dart';

RunRecord _run(
  String motif,
  String provider,
  Map<String, String> settings, {
  double? mesh,
  int? rating,
  int day = 1,
}) =>
    RunRecord(
      at: DateTime(2026, 1, day),
      motif: motif,
      provider: provider,
      settings: settings,
      meshScore: mesh,
      rating: rating,
    );

void main() {
  group('Bewertung eines Laufs', () {
    test('Ohne Note zählt die Messung, ohne Messung die Note', () {
      expect(_run('objekt', 'a', const {}, mesh: 0.8).score, 0.8);
      // Note 5 von 5 = 1,0; Note 1 = 0,0.
      expect(_run('objekt', 'a', const {}, rating: 5).score, 1.0);
      expect(_run('objekt', 'a', const {}, rating: 1).score, 0.0);
      expect(_run('objekt', 'a', const {}).score, isNull);
    });

    test('Die Note wiegt schwerer als die Messung', () {
      // Ein technisch tadelloses Modell, das das Motiv verfehlt, darf
      // nicht als gelungen durchgehen.
      final schoenGemessen = _run('objekt', 'a', const {},
          mesh: 1.0, rating: 1).score!;
      expect(schoenGemessen, lessThan(0.4));
      // Und umgekehrt: ein Modell mit Löchern, das trotzdem trägt.
      final schlechtGemessen =
          _run('objekt', 'a', const {}, mesh: 0.0, rating: 5).score!;
      expect(schlechtGemessen, greaterThan(0.6));
    });
  });

  group('Messbare Beschaffenheit', () {
    test('Ein sauberes Netz im Zielbereich bekommt volle Punktzahl', () {
      expect(
          meshQualityScore(
            triangles: 9000,
            targetTriangles: 9000,
            watertight: true,
            reversedEdges: 0,
            degenerateTriangles: 0,
            materials: 1,
            hasTexture: true,
            volumeRatio: 0.3,
          ),
          1.0);
    });

    test('Löcher, Backfaces und eine flache Platte ziehen ab', () {
      final wert = meshQualityScore(
        triangles: 9000,
        targetTriangles: 9000,
        watertight: false,
        reversedEdges: 12,
        degenerateTriangles: 4,
        materials: 3,
        hasTexture: false,
        volumeRatio: 0.001,
      );
      expect(wert, lessThan(0.2));
    });

    test('Zu wenige Dreiecke zählen wie zu viele', () {
      double mit(int dreiecke) => meshQualityScore(
            triangles: dreiecke,
            targetTriangles: 10000,
            watertight: true,
            reversedEdges: 0,
            degenerateTriangles: 0,
            materials: 1,
            hasTexture: true,
            volumeRatio: 0.3,
          );
      expect(mit(10000), 1.0);
      // Doppelt so viele und halb so viele liegen gleich weit daneben.
      expect(mit(20000), closeTo(mit(5000), 1e-9));
      expect(mit(20000), lessThan(1.0));
    });
  });

  group('Empfehlungen aus den eigenen Läufen', () {
    test('Unter vier bewerteten Läufen wird nichts empfohlen', () {
      final stats = RunStats([
        _run('gebaeude', 'tripo', const {'textur': '1024'}, rating: 5),
        _run('gebaeude', 'server', const {'textur': '2048'}, rating: 2),
        _run('gebaeude', 'tripo', const {'textur': '1024'}, rating: 5),
      ]);
      expect(stats.adviceFor('gebaeude'), isEmpty);
      expect(stats.ratedCount('gebaeude'), 3);
    });

    test('Der Anbieter mit den besseren Noten kommt nach oben', () {
      final stats = RunStats([
        for (var i = 0; i < 5; i++)
          _run('gebaeude', 'tripo', const {'textur': '1024'},
              rating: 5, day: i + 1),
        for (var i = 0; i < 5; i++)
          _run('gebaeude', 'server', const {'textur': '2048'},
              rating: 2, day: i + 6),
      ]);
      final advice = stats.adviceFor('gebaeude');
      expect(advice, isNotEmpty);
      final anbieter = advice.firstWhere((a) => a.setting == 'anbieter');
      expect(anbieter.value, 'tripo');
      expect(anbieter.runs, 5);
      expect(anbieter.solid, isTrue);
      expect(anbieter.average, greaterThan(anbieter.baseline));
    });

    test('Ein einzelner Glückstreffer wird nicht empfohlen', () {
      // Acht gleichmäßig gute Läufe mit dem einen Anbieter, ein
      // einziger Bestnoten-Lauf mit dem anderen. Ein Mittelwert allein
      // würde den Einzelfall nach oben spülen.
      final stats = RunStats([
        for (var i = 0; i < 8; i++)
          _run('figur', 'tripo', const {'pose': 't-pose'},
              rating: 4, day: i + 1),
        _run('figur', 'meshy', const {'pose': 'a-pose'},
            rating: 5, day: 20),
      ]);
      final advice = stats.adviceFor('figur');
      expect(advice.where((a) => a.value == 'meshy'), isEmpty);
      // Und weil die acht Läufe den Durchschnitt selbst bestimmen,
      // hebt sich auch tripo nicht davon ab: keine Empfehlung ist
      // hier die richtige Antwort.
      expect(advice, isEmpty);
    });

    test('Zwei Läufe reichen, wenn der Abstand deutlich ist', () {
      final stats = RunStats([
        for (var i = 0; i < 4; i++)
          _run('figur', 'server', const {}, rating: 2, day: i + 1),
        for (var i = 0; i < 2; i++)
          _run('figur', 'tripo', const {}, rating: 5, day: i + 5),
      ]);
      final anbieter =
          stats.adviceFor('figur').firstWhere((a) => a.setting == 'anbieter');
      expect(anbieter.value, 'tripo');
      expect(anbieter.runs, 2);
      // Zwei Läufe sind ein Hinweis, keine Aussage.
      expect(anbieter.solid, isFalse);
    });

    test('Gebäude und Figuren werden getrennt gerechnet', () {
      final stats = RunStats([
        for (var i = 0; i < 5; i++)
          _run('gebaeude', 'tripo', const {}, rating: 5, day: i + 1),
        for (var i = 0; i < 5; i++)
          _run('figur', 'meshy', const {}, rating: 5, day: i + 6),
        for (var i = 0; i < 5; i++)
          _run('figur', 'tripo', const {}, rating: 1, day: i + 11),
      ]);
      expect(
          stats
              .adviceFor('figur')
              .firstWhere((a) => a.setting == 'anbieter')
              .value,
          'meshy');
      // Bei Gebäuden gibt es nur einen Anbieter – nichts zu vergleichen.
      expect(stats.adviceFor('gebaeude'), isEmpty);
    });

    test('Ein Gleichstand ergibt keine Empfehlung', () {
      final stats = RunStats([
        for (var i = 0; i < 4; i++)
          _run('objekt', 'a', const {'textur': '1024'},
              rating: 3, day: i + 1),
        for (var i = 0; i < 4; i++)
          _run('objekt', 'b', const {'textur': '2048'},
              rating: 3, day: i + 5),
      ]);
      expect(stats.adviceFor('objekt'), isEmpty);
    });

    test('Der Text nennt die Zahl der Läufe und warnt bei wenigen', () {
      final stats = RunStats([
        for (var i = 0; i < 4; i++)
          _run('gebaeude', 'tripo', const {}, rating: 5, day: i + 1),
        for (var i = 0; i < 2; i++)
          _run('gebaeude', 'server', const {}, rating: 1, day: i + 5),
      ]);
      final text = stats.adviceText('gebaeude').join(' | ');
      expect(text, contains('Anbieter'));
      expect(text, contains('tripo'));
      expect(text, contains('Läufe'));
      expect(text, contains('eher ein Hinweis'));
    });
  });

  group('Ablegen und Zurücklesen', () {
    test('Ein Rundlauf über den gespeicherten Text', () {
      final stats = RunStats([]);
      stats.add(_run('figur', 'tripo', const {'textur': '1024'}, mesh: 0.9));
      stats.rateLatest(4);
      final wieder = RunStats.decode(stats.encode());
      expect(wieder.runs.length, 1);
      expect(wieder.runs.first.provider, 'tripo');
      expect(wieder.runs.first.settings['textur'], '1024');
      expect(wieder.runs.first.rating, 4);
      expect(wieder.runs.first.meshScore, closeTo(0.9, 1e-9));
    });

    test('Kaputter Text ergibt eine leere Liste statt eines Absturzes', () {
      expect(RunStats.decode('kein json').runs, isEmpty);
      expect(RunStats.decode('').runs, isEmpty);
      expect(RunStats.decode('{"a":1}').runs, isEmpty);
    });

    test('Alte Läufe fallen hinten heraus', () {
      final stats = RunStats([]);
      for (var i = 0; i < RunStats.keep + 20; i++) {
        stats.add(_run('objekt', 'a$i', const {}, rating: 3));
      }
      expect(stats.runs.length, RunStats.keep);
      // Der jüngste ist noch da, der älteste nicht mehr.
      expect(stats.runs.last.provider, 'a${RunStats.keep + 19}');
      expect(stats.runs.first.provider, 'a20');
    });
  });

  group('Motivklasse aus dem Prompt', () {
    test('Gebäude, Fahrzeug, Figur, sonst Objekt', () {
      expect(motifOf('medieval bakery with a domed oven'), 'gebaeude');
      expect(motifOf('ein Karren mit zwei Rädern'), 'fahrzeug');
      expect(motifOf('a knight in plate armour'), 'figur');
      expect(motifOf('ein Fass'), 'objekt');
    });

    test('Ein gewählter Figurtyp gewinnt gegen den Wortvergleich', () {
      expect(motifOf('ein Haus', figureType: 'biped'), 'figur');
    });
  });

  test('Zahlenwerte werden auf Stufen gerundet', () {
    expect(bucket(1100, const [512, 1024, 2048]), '1024');
    expect(bucket(1900, const [512, 1024, 2048]), '2048');
    expect(bucket(9800, const [4000, 10000, 20000]), '10000');
  });
}
