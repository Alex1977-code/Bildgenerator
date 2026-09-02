import 'dart:math' as math;

import 'package:bildgenerator/services/mannequin.dart';
import 'package:bildgenerator/services/roblox_check.dart'
    show robloxCharacterStuds;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Die drei Körpertypen', () {
    test('Classic misst genau die 5 Studs, auf die die App skaliert', () {
      // Das ist der Bezug, an dem der Marktplatz-Validator alle
      // Grenzen misst – die Zahl muss zur App passen.
      expect(mannequinById('classic').studs, robloxCharacterStuds);
    });

    test('Slender ist der höchste, Classic der kleinste', () {
      final hoehen = {
        for (final m in mannequins) m.id: m.studs,
      };
      expect(hoehen['slender'], greaterThan(hoehen['normal']!));
      expect(hoehen['normal'], greaterThan(hoehen['classic']!));
    });

    test('jeder Typ erklärt sich', () {
      for (final m in mannequins) {
        expect(m.note.length, greaterThan(40), reason: m.id);
        expect(m.shoulderStuds, greaterThan(0));
        expect(m.depthStuds, greaterThan(0));
      }
      expect(mannequins.map((m) => m.id).toSet().length, mannequins.length);
    });

    test('unbekannt heißt Classic – der Bezug der Roblox-Grenzen', () {
      expect(mannequinById('gibtsnicht').id, 'classic');
      expect(mannequinById(null).id, 'classic');
    });

    test('die Meterangabe dient nur dem Einordnen', () {
      // Ein Stud sind 0,28 m – der Importer rechnet aber nicht damit.
      expect(mannequinById('classic').meters, closeTo(1.4, 0.001));
    });
  });

  group('Der Umriss', () {
    test('steht auf dem Boden und reicht bis zur vollen Höhe', () {
      for (final m in mannequins) {
        final linien = mannequinOutline(m);
        var lo = double.infinity, hi = double.negativeInfinity;
        for (final l in linien) {
          for (final y in [l[1], l[4]]) {
            lo = math.min(lo, y);
            hi = math.max(hi, y);
          }
        }
        expect(lo, closeTo(0, 1e-9), reason: '${m.id} steht nicht auf 0');
        expect(hi, closeTo(m.studs, 1e-9),
            reason: '${m.id} erreicht seine Höhe nicht');
      }
    });

    test('bleibt in der Schulterbreite', () {
      for (final m in mannequins) {
        for (final l in mannequinOutline(m)) {
          for (final x in [l[0], l[3]]) {
            // Die Arme dürfen etwas hinausragen, mehr als ein Drittel
            // darüber wäre aber keine hängende Haltung mehr.
            expect(x.abs(), lessThanOrEqualTo(m.shoulderStuds * 0.7),
                reason: m.id);
          }
        }
      }
    });

    test('ist ein Drahtgitter, kein Körper', () {
      // Ein gefüllter Körper nähme die Sicht weg, für die er da ist.
      final linien = mannequinOutline(mannequins.first);
      expect(linien.length, greaterThan(20));
      for (final l in linien) {
        expect(l.length, 6, reason: 'kein Streckenpaar');
      }
    });

    test('als flaches Feld passt die Länge', () {
      final m = mannequins.first;
      expect(mannequinSegments(m).length,
          mannequinOutline(m).length * 6);
    });
  });

  group('Der Vergleich', () {
    test('gleiche Größe heißt „passt"', () {
      final v = MannequinComparison(
        mannequin: mannequinById('classic'),
        modelStuds: 5.0,
        modelShoulder: 2.0,
        modelDepth: 1.0,
      );
      expect(v.heightRatio, 1.0);
      expect(v.heightText, contains('Passt'));
    });

    test('eine kniehohe Figur wird als solche benannt', () {
      // Genau der gemeldete Fall: 1,20 Einheiten kamen kniehoch an.
      final v = MannequinComparison(
        mannequin: mannequinById('classic'),
        modelStuds: 1.2,
        modelShoulder: 0.5,
        modelDepth: 0.3,
      );
      expect(v.heightText, contains('kleiner'));
      expect(v.heightText, contains('kniehoch'));
    });

    test('eine zu große Figur ebenso', () {
      final v = MannequinComparison(
        mannequin: mannequinById('classic'),
        modelStuds: 9.0,
        modelShoulder: 3.0,
        modelDepth: 1.5,
      );
      expect(v.heightText, contains('größer'));
      expect(v.heightText, contains('überragt'));
    });

    test('kleine Abweichungen gelten als passend', () {
      final v = MannequinComparison(
        mannequin: mannequinById('classic'),
        modelStuds: 5.1,
        modelShoulder: 2.0,
        modelDepth: 1.0,
      );
      expect(v.heightText, contains('Passt'));
    });
  });
}
