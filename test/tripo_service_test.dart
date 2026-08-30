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

  group('Was für Roblox an Tripo geht', () {
    // Diese Gruppe hält die Prüfung fest, die einmal von Hand gegen
    // Tripos Parameterliste gelaufen ist. Sie beantwortet die Frage
    // „schicken wir eigentlich alles Nötige?" nachprüfbar.
    final service = TripoService('schluessel');

    Map<String, dynamic> robloxFields() => service.qualityFields(
          texture: true,
          modelVersion: 'P1-20260311',
          faceLimit: 10000,
          smartLowPoly: true,
          pbr: false,
          autoSize: true,
        );

    test('Das Low-Poly-Modell P1 wird ausdrücklich genannt', () {
      // Die V3-API verlangt eine Modellangabe, und für Roblox ist es
      // nicht das allgemeine v2.5: P1 arbeitet im Bereich 48 bis
      // 20.000 Flächen – genau Roblox\' Grenze.
      expect(robloxFields()['model'], 'P1-20260311');
    });

    test('Ohne Angabe bleibt es beim bewährten Modell', () {
      expect(service.qualityFields(texture: true)['model'],
          TripoService.defaultModelVersion);
    });

    test('Flächengrenze, Low-Poly und Maßstab stehen im Auftrag', () {
      final fields = robloxFields();
      expect(fields['face_limit'], 10000);
      expect(fields['smart_low_poly'], true);
      // Ohne auto_size kam die Figur mit 0,98 Einheiten – im
      // Importer 3,5 Studs statt der üblichen 5.
      expect(fields['auto_size'], true);
    });

    test('Quad erzwingt FBX und bleibt deshalb bei Roblox draußen', () {
      final quad = service.qualityFields(texture: true, quad: true);
      expect(quad['quad'], true);
      expect(quad['out_format'], 'fbx');
      expect(robloxFields().containsKey('quad'), isFalse);
      expect(robloxFields().containsKey('out_format'), isFalse);
    });

    test('Detaillierte Texturen nur auf Wunsch', () {
      expect(robloxFields().containsKey('texture_quality'), isFalse);
      expect(
          service.qualityFields(
              texture: true, detailedTexture: true)['texture_quality'],
          'detailed');
      // Ohne Textur ergibt die Stufe keinen Sinn.
      expect(
          service
              .qualityFields(texture: false, detailedTexture: true)
              .containsKey('texture_quality'),
          isFalse);
    });

    test('Nichts Unerwünschtes im Auftrag', () {
      final fields = robloxFields();
      // „generate_parts" zerlegt das Modell in mehrere Meshes,
      // „compress" liefert eine gepackte GLB – beides bringt den
      // Roblox-Import durcheinander.
      expect(fields.containsKey('generate_parts'), isFalse);
      expect(fields.containsKey('compress'), isFalse);
      expect(fields.containsKey('style'), isFalse);
    });

    test('Die Figurtypen der App treffen Tripos Namen', () {
      expect(TripoService.rigTypes['biped'], 'biped');
      expect(TripoService.rigTypes['quadruped'], 'quadruped');
      expect(TripoService.rigTypes['insect'], 'hexapod');
      expect(TripoService.rigTypes['bird'], 'avian');
      expect(TripoService.rigTypes['snake'], 'serpentine');
      expect(TripoService.rigTypes['fish'], 'aquatic');
      // Ein Fahrzeug hat kein Skelett, das Tripo kennt.
      expect(TripoService.rigTypes['vehicle'], isNull);
    });
  });

  group('Abgeschaltete Modellfassungen', () {
    // Der gemeldete Fehler im Wortlaut.
    const real = '{"code":2000,"message":"invalid model '
        "'v2.5-20250123', allowed values: v1.0-20240301, "
        'v2.5-20260210 (Refer to the API documentation for parameter '
        'requirements)"}';

    test('Die Vorgabe ist nicht mehr die abgeschaltete Fassung', () {
      expect(TripoService.defaultModelVersion, isNot('v2.5-20250123'));
      expect(TripoService.defaultModelVersion, 'v2.5-20260210');
      // Rigging braucht eine eigene Angabe, sonst greift bei Tripo
      // die abgeschaltete Vorgabe.
      expect(TripoService.defaultRigModel, 'v2.5-20260210');
    });

    test('Aus der Meldung wird die Fassung derselben Reihe genommen', () {
      expect(TripoService.pickAllowedModel('v2.5-20250123', real),
          'v2.5-20260210');
    });

    test('Ohne passende Reihe die letztgenannte', () {
      expect(TripoService.pickAllowedModel('P1-20260311', real),
          'v2.5-20260210');
    });

    test('Steht die eigene Fassung schon in der Liste, kein Wechsel', () {
      expect(TripoService.pickAllowedModel('v2.5-20260210', real), isNull);
    });

    test('Andere Fehler liefern keinen Vorschlag', () {
      expect(
          TripoService.pickAllowedModel(
              'v2.5-20260210', '{"message":"prompt too long, max 1024"}'),
          isNull);
      expect(TripoService.pickAllowedModel('', ''), isNull);
    });
  });
}
