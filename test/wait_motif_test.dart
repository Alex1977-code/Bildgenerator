import 'package:flutter_test/flutter_test.dart';
import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/wait_motif.dart';

void main() {
  group('Punkte auf den Strichen', () {
    test('Ein gerader Strich bekommt gleichmäßig verteilte Punkte', () {
      const strich = MotifStroke([Offset(0, 0), Offset(1, 0)]);
      final punkte = samplePoints([strich], 4);
      expect(punkte.length, 4);
      // Mittig im jeweiligen Viertel: 0.125, 0.375, 0.625, 0.875.
      expect(punkte[0].dx, closeTo(0.125, 1e-6));
      expect(punkte[3].dx, closeTo(0.875, 1e-6));
      for (final p in punkte) {
        expect(p.dy, closeTo(0, 1e-9));
      }
    });

    test('Der längere Strich bekommt mehr Punkte', () {
      const kurz = MotifStroke([Offset(0, 0), Offset(0.2, 0)]);
      const lang = MotifStroke([Offset(0, 1), Offset(1, 1)]);
      final punkte = samplePoints([kurz, lang], 60);
      final obenauf = punkte.where((p) => p.dy == 0).length;
      expect(obenauf, lessThan(punkte.length - obenauf));
    });

    test('Gewicht verdichtet einen Strich', () {
      const a = MotifStroke([Offset(0, 0), Offset(1, 0)]);
      const b = MotifStroke([Offset(0, 1), Offset(1, 1)], weight: 3);
      final punkte = samplePoints([a, b], 80);
      final unten = punkte.where((p) => p.dy == 1).length;
      expect(unten, greaterThan(punkte.length ~/ 2));
    });

    test('Ein geschlossener Strich läuft zum Anfang zurück', () {
      const quadrat = MotifStroke([
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ], closed: true);
      final punkte = samplePoints([quadrat], 40);
      // Ohne Schließen fehlte die linke Kante.
      expect(punkte.where((p) => p.dx < 0.05 && p.dy > 0.1).length,
          greaterThan(3));
    });

    test('Ohne Striche oder ohne Punkte kommt nichts heraus', () {
      expect(samplePoints(const [], 10), isEmpty);
      expect(
          samplePoints(
              const [MotifStroke([Offset(0, 0), Offset(1, 0)])], 0),
          isEmpty);
    });

    test('Dieselbe Eingabe liefert dieselben Punkte', () {
      final a = samplePoints(waitMotifs['banane']!.artist, 100);
      final b = samplePoints(waitMotifs['banane']!.artist, 100);
      expect(a, b);
    });
  });

  group('Jedes Motiv taugt zum Zeichnen', () {
    test('Alle Punkte liegen im Bereich -1 bis 1', () {
      for (final motif in waitMotifs.values) {
        for (final striche in [motif.artist, motif.canvas]) {
          for (final p in samplePoints(striche, 200)) {
            expect(p.dx.abs(), lessThanOrEqualTo(1.0),
                reason: '${motif.id}: x außerhalb');
            expect(p.dy.abs(), lessThanOrEqualTo(1.0),
                reason: '${motif.id}: y außerhalb');
          }
        }
      }
    });

    test('Kein Motiv ist leer, und jedes hat eine Leinwand', () {
      for (final motif in waitMotifs.values) {
        expect(samplePoints(motif.artist, 200).length, greaterThan(40),
            reason: '${motif.id}: zu wenige Punkte im Zeichner');
        expect(samplePoints(motif.canvas, 200).length, greaterThan(20),
            reason: '${motif.id}: zu wenige Punkte im Bild');
        expect(motif.name, isNotEmpty);
        expect(motif.note, isNotEmpty);
      }
    });

    test('Die Kennung stimmt mit dem Schlüssel überein', () {
      waitMotifs.forEach((key, motif) => expect(motif.id, key));
    });
  });

  group('Zuordnung zum Modell', () {
    test('Jeder Anbieter hat sein Motiv', () {
      expect(waitMotifFor(GenProvider.gemini, 'gemini-2.5-flash-image').id,
          'banane');
      expect(
          waitMotifFor(GenProvider.gemini, 'gemini-3-pro-image-preview').id,
          'banane');
      expect(waitMotifFor(GenProvider.stability, 'core').id, 'hugging');
      expect(waitMotifFor(GenProvider.openai, 'gpt-image-2').id, 'rosette');
      expect(waitMotifFor(GenProvider.selfhost, 'sdxl').id, 'chip');
    });

    test('Die Modelle ohne Guidance bekommen den Blitz', () {
      expect(waitMotifFor(GenProvider.selfhost, 'sdxl-turbo').id, 'blitz');
      expect(waitMotifFor(GenProvider.selfhost, 'flux-schnell').id, 'blitz');
    });

    test('Jedes eingebaute Bild-Modell bekommt ein Motiv', () {
      for (final provider in GenProvider.values) {
        for (final option in staticModelOptions(provider)) {
          final motif = waitMotifFor(provider, option.$1);
          expect(waitMotifs.values, contains(motif),
              reason: '${provider.name}/${option.$1}');
        }
      }
    });

    test('Der eigene Rechner bekommt im 3D-Bereich den Chip', () {
      expect(waitMotifForThreeD('local').id, 'chip');
      expect(waitMotifForThreeD('meshy').id, 'wuerfel');
    });
  });
}
