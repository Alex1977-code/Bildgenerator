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
