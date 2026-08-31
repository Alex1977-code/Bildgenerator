import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/vram_fit.dart';

void main() {
  group('Ein Modell auf einer Karte', () {
    test('Mit Luft nach oben läuft es ganz auf der GPU', () {
      final v = vramVerdict(cardGb: 10, modelGb: 8);
      expect(v.fit, VramFit.ganz);
      expect(v.fast, isTrue);
      expect(v.text, contains('10,0 GB'));
    });

    test('Gleich groß heißt nicht passend', () {
      // Genau der Fall, an dem die alte Rechnung im Server hängen
      // blieb: 10-GB-Karte, 10-GB-Modell, „passt" – und der erste
      // Lauf endete mit „CUDA out of memory". Die Gewichte sind nicht
      // alles.
      final v = vramVerdict(cardGb: 10, modelGb: 10);
      expect(v.fit, VramFit.ausgelagert);
      expect(v.fast, isFalse);
      expect(v.text, contains('Rechnen'));
    });

    test('Deutlich zu groß wird als solches benannt', () {
      final v = vramVerdict(cardGb: 10, modelGb: 16);
      expect(v.fit, VramFit.knapp);
      expect(v.text, contains('Zu groß'));
    });

    test('Ohne Angaben wird nichts behauptet', () {
      expect(vramVerdict(cardGb: 0, modelGb: 8).fit, VramFit.unbekannt);
      expect(vramVerdict(cardGb: 10, modelGb: 0).fit, VramFit.unbekannt);
    });

    test('Der Aufschlag lässt sich vom Server vorgeben', () {
      expect(vramVerdict(cardGb: 10, modelGb: 9, reserveGb: 0.5).fit,
          VramFit.ganz);
      expect(vramVerdict(cardGb: 10, modelGb: 9, reserveGb: 3).fit,
          VramFit.ausgelagert);
    });
  });

  group('Zusammenfassung für die Verbindungsmeldung', () {
    test('Trennt, was ganz auf die Karte passt', () {
      // Eine 10-GB-Karte, wie sie in einer RTX 3080 steckt.
      final text = vramSummary(cardGb: 10, models: const {
        'sd15': 4,
        'sdxl-turbo': 7,
        'sdxl': 8,
        'sd35-medium': 10,
        'flux-schnell': 16,
      });
      expect(text, contains('10,0 GB VRAM'));
      expect(text, contains('ganz auf der GPU: sd15, sdxl-turbo, sdxl'));
      expect(text,
          contains('ausgelagert (langsamer): sd35-medium, flux-schnell'));
    });

    test('Passt alles, fehlt der zweite Teil', () {
      final text = vramSummary(cardGb: 24, models: const {'sdxl': 8});
      expect(text, contains('ganz auf der GPU: sdxl'));
      expect(text, isNot(contains('ausgelagert')));
    });

    test('Ohne Angaben bleibt die Meldung leer', () {
      expect(vramSummary(cardGb: 0, models: const {'sdxl': 8}), isEmpty);
      expect(vramSummary(cardGb: 10, models: const {}), isEmpty);
    });
  });
}
