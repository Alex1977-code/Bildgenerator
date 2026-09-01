import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:bildgenerator/services/studio_light.dart';

void main() {
  group('Lichtaufstellungen', () {
    test('Jede ist vollständig und benannt', () {
      for (final light in studioLights) {
        expect(light.id, isNotEmpty);
        expect(light.label, isNotEmpty);
        expect(light.hint, isNotEmpty, reason: light.id);
        expect(light.ambient, inInclusiveRange(0.0, 1.0), reason: light.id);
      }
      final ids = studioLights.map((l) => l.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('Die Richtung hat Länge 1', () {
      for (final light in studioLights) {
        final (x, y, z) = light.direction;
        expect(math.sqrt(x * x + y * y + z * z), closeTo(1.0, 1e-9),
            reason: light.id);
      }
    });

    test('Die erste ist die bisherige – wer nichts umstellt, sieht '
        'dasselbe wie vorher', () {
      final studio = studioLights.first;
      expect(studio.id, 'studio');
      final (x, y, z) = studio.direction;
      final len = math.sqrt(0.26 * 0.26 + 0.44 * 0.44 + 0.86 * 0.86);
      expect(x, closeTo(-0.26 / len, 1e-9));
      expect(y, closeTo(0.44 / len, 1e-9));
      expect(z, closeTo(0.86 / len, 1e-9));
      expect(studio.ambient, 0.42);
    });

    test('Die Richtungen zeigen wirklich woanders hin', () {
      expect(studioLightById('oben').direction.$2,
          greaterThan(studioLightById('studio').direction.$2));
      expect(studioLightById('seite').direction.$1,
          greaterThan(0.8));
      // Gegenlicht kommt von hinten: z negativ.
      expect(studioLightById('gegen').direction.$3, lessThan(0));
      // „Ohne Schatten" steht fast auf Grundhelligkeit.
      expect(studioLightById('flach').ambient, greaterThan(0.9));
    });

    test('Eine unbekannte Kennung fällt auf Studio zurück', () {
      expect(studioLightById('gibtesnicht').id, 'studio');
      expect(studioLightById('').id, 'studio');
    });

    test('Eine Richtung ohne Länge kippt nicht um', () {
      const kaputt = StudioLight(
          id: 'x', label: 'x', hint: 'x', x: 0, y: 0, z: 0);
      expect(kaputt.direction, (0.0, 0.0, 1.0));
    });
  });

  group('Bodenschatten', () {
    test('Er liegt mittig unter dem Modell', () {
      final s = groundShadowFor(
          width: 400, height: 300, extent: 1.0, scale: 100, tiltX: 0.3);
      expect(s.centerX, 200);
      expect(s.centerY, greaterThan(150), reason: 'unterhalb der Mitte');
      expect(s.isEmpty, isFalse);
    });

    test('Von oben wird er rund, von der Seite flach', () {
      final flach = groundShadowFor(
          width: 400, height: 300, extent: 1, scale: 100, tiltX: 0.0);
      final steil = groundShadowFor(
          width: 400, height: 300, extent: 1, scale: 100, tiltX: 1.4);
      expect(flach.radiusY, lessThan(steil.radiusY));
      expect(flach.radiusX, steil.radiusX);
    });

    test('Ohne Ausdehnung oder Maßstab gibt es keinen', () {
      expect(
          groundShadowFor(
                  width: 400, height: 300, extent: 0, scale: 100, tiltX: 0)
              .isEmpty,
          isTrue);
      expect(
          groundShadowFor(
                  width: 400, height: 300, extent: 1, scale: 0, tiltX: 0)
              .isEmpty,
          isTrue);
    });

    test('Ein größeres Modell wirft einen größeren Schatten', () {
      final klein = groundShadowFor(
          width: 400, height: 300, extent: 0.5, scale: 100, tiltX: 0.3);
      final gross = groundShadowFor(
          width: 400, height: 300, extent: 2.0, scale: 100, tiltX: 0.3);
      expect(gross.radiusX, greaterThan(klein.radiusX));
    });
  });
}
