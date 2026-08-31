import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:bildgenerator/models/models.dart';

void main() {
  group('Pixelmaße des eigenen Bild-Servers', () {
    // Der Server rechnet in _aspect_size dieselbe Formel. Weicht die
    // App davon ab, steht im Dropdown eine Zahl, die nie herauskommt –
    // schlimmer als gar keine.
    (int, int) serverRechnung(String aspect, int base) {
      const ratios = {
        '1:1': (1, 1),
        '16:9': (16, 9),
        '9:16': (9, 16),
        '4:3': (4, 3),
        '3:4': (3, 4),
        '3:2': (3, 2),
        '2:3': (2, 3),
        '21:9': (21, 9),
        '9:21': (9, 21),
        '5:4': (5, 4),
        '4:5': (4, 5),
      };
      final (w, h) = ratios[aspect]!;
      final s = math.sqrt(base * base / (w * h));
      int kante(double v) {
        final k = (v / 64).round() * 64;
        return k < 256 ? 256 : k;
      }

      return (kante(w * s), kante(h * s));
    }

    test('Jedes angebotene Verhältnis kennt der Server', () {
      final quelle = File('server/local_image_server.py').readAsStringSync();
      final block = RegExp(r'ratios = \{(.*?)\}', dotAll: true)
          .firstMatch(quelle);
      expect(block, isNotNull, reason: 'ratios im Server nicht gefunden');
      final imServer = {
        for (final m
            in RegExp(r'"(\d+:\d+)":').allMatches(block!.group(1)!))
          m.group(1)!,
      };
      expect(imServer, selfHostAspects.keys.toSet(),
          reason: 'App und Server kennen verschiedene Verhältnisse');
      // Was die App zur Auswahl stellt, muss der Server auch können –
      // sonst kommt ein quadratisches Bild zurück, ohne Fehlermeldung.
      for (final option in stabilityAspectOptions) {
        expect(imServer, contains(option.$1),
            reason: '${option.$1} fehlt im Server');
      }
    });

    test('Die Grundauflösungen stimmen mit MODELS überein', () {
      final quelle = File('server/local_image_server.py').readAsStringSync();
      final block =
          RegExp(r'^MODELS = \{(.*?)^\}', multiLine: true, dotAll: true)
              .firstMatch(quelle);
      expect(block, isNotNull);
      final eintrag = RegExp(
          r'"([\w.-]+)":\s*\("[^"]+",\s*"\w+",\s*\d+,\s*[\d.]+,\s*(\d+),');
      final gefunden = <String>{};
      for (final m in eintrag.allMatches(block!.group(1)!)) {
        final name = m.group(1)!;
        gefunden.add(name);
        expect(selfHostBaseSizes, contains(name),
            reason: '$name fehlt in selfHostBaseSizes');
        expect(selfHostBaseSizes[name], int.parse(m.group(2)!),
            reason: '$name: Grundauflösung');
      }
      expect(gefunden.length, greaterThan(3));
      expect(selfHostBaseSizes.keys.toSet(), gefunden);
    });

    test('Die Rechnung entspricht der des Servers', () {
      for (final model in selfHostBaseSizes.keys) {
        for (final aspect in selfHostAspects.keys) {
          expect(selfHostPixels(aspect, model),
              serverRechnung(aspect, selfHostBaseSizes[model]!),
              reason: '$model $aspect');
        }
      }
    });

    test('Quadrat ergibt die Grundauflösung', () {
      expect(selfHostPixels('1:1', 'sdxl'), (1024, 1024));
      expect(selfHostPixels('1:1', 'sd15'), (512, 512));
    });

    test('Ein unbekanntes Modell rechnet mit 1024', () {
      expect(selfHostPixels('1:1', 'gibtesnicht'), (1024, 1024));
    });

    test('Die Kanten sind Vielfache von 64 und mindestens 256', () {
      for (final model in selfHostBaseSizes.keys) {
        for (final aspect in selfHostAspects.keys) {
          final (w, h) = selfHostPixels(aspect, model);
          expect(w % 64, 0, reason: '$model $aspect Breite');
          expect(h % 64, 0, reason: '$model $aspect Höhe');
          expect(w, greaterThanOrEqualTo(256));
          expect(h, greaterThanOrEqualTo(256));
        }
      }
    });
  });
}
