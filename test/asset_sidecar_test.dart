import 'dart:convert';
import 'dart:typed_data';

import 'package:bildgenerator/services/asset_sidecar.dart';
import 'package:flutter_test/flutter_test.dart';

AssetSidecar _protokoll() => AssetSidecar(
      fileName: 'kapuzzee.glb',
      kind: '3D-Modell',
      provider: 'tripo',
      createdAt: DateTime.utc(2026, 8, 31, 22, 26),
      model: 'Tripo3D',
      modelVersion: 'P1-20260311',
      prompt: 'hooded creature character',
      promptSuffix: 'full body character in A-pose',
      negativePrompt: 'deep body, long hem',
      seed: 4711,
      settings: const {'face_limit': 7000, 'pbr': false},
      pipeline: const ['Löcher geschlossen', 'auf 5 Studs gebracht'],
      appVersion: '1.0.0',
      checksum: 'abc123',
    );

void main() {
  group('Das Protokoll', () {
    test('trennt, was der Mensch getippt hat, und was die App anhängte',
        () {
      final s = _protokoll();
      expect(s.prompt, 'hooded creature character');
      expect(s.promptSuffix, 'full body character in A-pose');
      expect(s.fullPrompt,
          'hooded creature character, full body character in A-pose');
      // Beides steht in der Datei – wer nur den getippten Text
      // speichert, kann den Lauf nicht wiederholen.
      final json = s.toJson();
      expect(json['prompt'], isNotNull);
      expect(json['promptZusatz'], isNotNull);
      expect(json['promptVollstaendig'], s.fullPrompt);
    });

    test('führt die Modellfassung getrennt vom Namen', () {
      // „Tripo" allein reicht nicht: P1 und v2.5 liefern
      // grundverschiedene Netze.
      final json = _protokoll().toJson();
      expect(json['modell'], 'Tripo3D');
      expect(json['modellFassung'], 'P1-20260311');
    });

    test('schreibt den Zeitpunkt als ISO 8601', () {
      final json = _protokoll().toJson();
      expect(json['erzeugtAm'], '2026-08-31T22:26:00.000Z');
    });

    test('nennt den Seed auch, wenn keiner da ist', () {
      // Null ist eine Aussage: „Der Anbieter hat keinen geliefert."
      // Ein fehlendes Feld wäre eine andere – „wissen wir nicht".
      final ohne = AssetSidecar(
        fileName: 'x.png',
        kind: 'Bild',
        provider: 'openai',
        createdAt: DateTime.utc(2026),
      );
      expect(ohne.toJson().containsKey('seed'), isTrue);
      expect(ohne.toJson()['seed'], isNull);
    });

    test('lässt sich wieder einlesen', () {
      final text = _protokoll().toJsonText();
      final zurueck = AssetSidecar.fromJson(
          jsonDecode(text) as Map<String, dynamic>);
      expect(zurueck.fileName, 'kapuzzee.glb');
      expect(zurueck.modelVersion, 'P1-20260311');
      expect(zurueck.seed, 4711);
      expect(zurueck.pipeline.length, 2);
      expect(zurueck.createdAt, DateTime.utc(2026, 8, 31, 22, 26));
    });

    test('ein älteres Protokoll bleibt lesbar', () {
      // Fehlende Felder sind kein Fehler.
      final alt = AssetSidecar.fromJson(const {
        'datei': 'alt.glb',
        'anbieter': 'meshy',
      });
      expect(alt.fileName, 'alt.glb');
      expect(alt.provider, 'meshy');
      expect(alt.seed, isNull);
      expect(alt.pipeline, isEmpty);
    });

    test('der Dateiname steht neben dem Asset, nicht in dessen Weg', () {
      expect(AssetSidecar.sidecarNameFor('modell.glb'),
          'modell.herkunft.json');
      expect(AssetSidecar.sidecarNameFor('bild.png'),
          'bild.herkunft.json');
      // Ohne Endung: nichts abschneiden.
      expect(AssetSidecar.sidecarNameFor('modell'),
          'modell.herkunft.json');
      // Punkte im Namen dürfen nicht stören.
      expect(AssetSidecar.sidecarNameFor('v1.2.modell.glb'),
          'v1.2.modell.herkunft.json');
    });

    test('trägt seine Formatfassung', () {
      expect(_protokoll().toJson()['protokollFassung'], sidecarVersion);
    });

    test('ist eingerückt – die Datei wird auch gelesen', () {
      expect(_protokoll().toJsonText(), contains('\n  "datei"'));
    });
  });

  group('Die Lizenzangabe', () {
    test('nennt für jeden bekannten Anbieter einen Stand', () {
      for (final entry in providerLicenses.entries) {
        expect(entry.value.checked, isNotEmpty,
            reason: '${entry.key} ohne Stand');
        expect(entry.value.summary.length, greaterThan(30),
            reason: '${entry.key} erklärt sich nicht');
      }
    });

    test('sagt bei einem unbekannten Anbieter, dass sie nichts weiß', () {
      final unbekannt = licenseFor('irgendwas');
      expect(unbekannt.commercial, isFalse);
      expect(unbekannt.summary, contains('keine Angabe'));
      expect(unbekannt.checked, isEmpty);
    });

    test('hängt an jedem Protokoll', () {
      final json = _protokoll().toJson();
      final lizenz = json['lizenz'] as Map<String, dynamic>;
      expect(lizenz['anbieter'], 'Tripo3D');
      expect(lizenz['stand'], isNotEmpty);
    });
  });

  test('die Prüfsumme verknüpft Protokoll und Datei', () {
    final a = assetChecksum(Uint8List.fromList([1, 2, 3]));
    final b = assetChecksum(Uint8List.fromList([1, 2, 4]));
    expect(a.length, 64);
    expect(a, isNot(b));
    // Gleiche Bytes, gleiche Summe – sonst taugt sie nicht.
    expect(a, assetChecksum(Uint8List.fromList([1, 2, 3])));
  });
}
