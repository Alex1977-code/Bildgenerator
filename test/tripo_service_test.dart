import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/tripo_service.dart';

void main() {
  group('Tripo-API-Fassung', () {
    test('V3 ist der Standard, V2 nur auf ausdrückliche Wahl', () {
      expect(TripoApiVersion.fromName(null), TripoApiVersion.v3);
      expect(TripoApiVersion.fromName(''), TripoApiVersion.v3);
      expect(TripoApiVersion.fromName('v3'), TripoApiVersion.v3);
      expect(TripoApiVersion.fromName('irgendwas'), TripoApiVersion.v3);
      expect(TripoApiVersion.fromName('v2'), TripoApiVersion.v2);
    });

    test('Die Abschalttermine stehen fest', () {
      // 1. November 2026, 00:00 UTC+8 = 31. Oktober 2026, 16:00 UTC.
      expect(tripoV2Shutdown, DateTime.utc(2026, 10, 31, 16));
      expect(tripoV2FeatureFreeze, DateTime.utc(2026, 9, 30, 16));
      expect(tripoV2FeatureFreeze.isBefore(tripoV2Shutdown), isTrue);
    });
  });

  group('Längengrenzen der Textfelder', () {
    // Tripo lehnt die ganze Anfrage mit 400 ab, sobald ein Feld zu
    // lang ist: „negative_prompt exceeds maximum length 255
    // characters".
    test('Die Grenzen stehen fest', () {
      expect(TripoService.maxPromptChars, 1024);
      expect(TripoService.maxNegativePromptChars, 255);
    });

    test('Kurze Texte bleiben unverändert', () {
      expect(TripoService.clipToLimit('low poly, blobby', 255),
          'low poly, blobby');
      expect(TripoService.clipToLimit('  Rand  ', 255), 'Rand');
    });

    test('Eine Stichwortliste wird am letzten Komma gekürzt', () {
      // 30 Einträge à 8 Zeichen = 240, mit dem 31. über die Grenze.
      final list = List.generate(40, (i) => 'begriff$i').join(', ');
      final clipped = TripoService.clipToLimit(list, 255);
      expect(clipped.length, lessThanOrEqualTo(255));
      // Kein abgeschnittenes Wort am Ende, und kein Komma.
      expect(clipped.endsWith(','), isFalse);
      expect(list.startsWith(clipped), isTrue);
      // Der letzte Eintrag ist vollständig.
      final last = clipped.split(', ').last;
      expect(list.split(', '), contains(last));
    });

    test('Ein Text ohne Kommas wird am Leerzeichen getrennt', () {
      final words = List.filled(80, 'wort').join(' ');
      final clipped = TripoService.clipToLimit(words, 255);
      expect(clipped.length, lessThanOrEqualTo(255));
      expect(clipped.endsWith('wort'), isTrue);
    });

    test('Ein einziges überlanges Wort wird hart geschnitten', () {
      final clipped = TripoService.clipToLimit('a' * 400, 255);
      expect(clipped.length, 255);
    });

    test('Der gemeldete Fall bleibt unter der Grenze', () {
      // Genau die Liste aus dem 400er-Fehler.
      const real = 'human, person, character, weapon, minion animal, '
          'holes, open mesh, frayed edges, spread fingers, arms down, '
          'dynamic pose, cluttered details, text, watermark, low '
          'quality, blurry, extra limbs, deformed, floating parts, '
          'base, pedestal, multiple objects, background scenery, '
          'sharp thin spikes, transparent surfaces';
      expect(real.length, greaterThan(255));
      expect(
          TripoService.clipToLimit(
                  real, TripoService.maxNegativePromptChars)
              .length,
          lessThanOrEqualTo(255));
    });
  });

  group('Ergebnis-URLs aus der Task-Antwort', () {
    test('V3 nennt model_url, V2 nannte pbr_model', () {
      expect(
          TripoService.findGlbUrl({
            'output': {'model_url': 'https://x/modell.glb'}
          }),
          'https://x/modell.glb');
      expect(
          TripoService.findGlbUrl({
            'output': {'pbr_model': 'https://x/alt.glb'}
          }),
          'https://x/alt.glb');
    });

    test('model_urls als Liste wird gelesen', () {
      expect(
          TripoService.findGlbUrl({
            'output': {
              'model_urls': ['https://x/eins.glb', 'https://x/zwei.glb']
            }
          }),
          'https://x/eins.glb');
    });

    test('PBR-Variante geht vor, model_url vor pbr_model', () {
      expect(
          TripoService.findGlbUrl({
            'output': {
              'model_url': 'https://x/neu.glb',
              'pbr_model': 'https://x/alt.glb',
            }
          }),
          'https://x/neu.glb');
    });

    test('Notfalls wird die Antwort nach einer GLB-URL durchsucht', () {
      expect(
          TripoService.findGlbUrl({
            'result': {
              'irgendwo': {'tief': 'https://x/versteckt.glb'}
            }
          }),
          'https://x/versteckt.glb');
      expect(TripoService.findGlbUrl({'output': {}}), isNull);
    });

    test('Vorschaubild: beide Feldnamen', () {
      expect(
          TripoService.findThumbnailUrl({
            'output': {'rendered_image_url': 'https://x/neu.png'}
          }),
          'https://x/neu.png');
      expect(
          TripoService.findThumbnailUrl({
            'output': {'rendered_image': 'https://x/alt.png'}
          }),
          'https://x/alt.png');
      expect(TripoService.findThumbnailUrl({'output': {}}), isNull);
    });
  });
}
