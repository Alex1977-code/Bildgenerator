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

    test('Ein gemessener Wert schlägt die Schätzung', () {
      // Genau der Fall, an dem die Schätzung dieser App danebenlag:
      // Für SD 3.5 standen 10 GB in der Tabelle, mit dem T5-Encoder
      // sind es rund 16. Wer einmal gemessen hat, soll nicht weiter
      // die Tabelle sehen.
      final text = vramSummary(
        cardGb: 11,
        models: const {'sd35': 10.0},
        measured: const {'sd35': 15.8},
      );
      expect(text, contains('ausgelagert'));
      expect(text, contains('(gemessen)'));
      // Und ohne Messung gälte die Schätzung: 10 + 1,5 > 11 → knapp
      // ausgelagert, aber eben aus anderem Grund.
      expect(vramSummary(cardGb: 12, models: const {'sd35': 10.0}),
          contains('ganz auf der GPU'));
    });

    test('Der gemessene Wert braucht keinen Aufschlag mehr', () {
      // Er ist bereits der Spitzenwert eines echten Laufs – noch
      // einmal 1,5 GB draufzuschlagen würde doppelt zählen.
      final text = vramSummary(
        cardGb: 8,
        models: const {'sdxl': 8.0},
        measured: const {'sdxl': 7.4},
      );
      expect(text, contains('ganz auf der GPU'));
    });

    test('Gemessene und geschätzte Modelle nebeneinander', () {
      final text = vramSummary(
        cardGb: 11,
        models: const {'klein': 4.0, 'gross': 10.0},
        measured: const {'gross': 15.0},
      );
      expect(text, contains('ganz auf der GPU: klein'));
      expect(text, contains('gross (gemessen)'));
    });

    test('Ohne Angaben bleibt die Meldung leer', () {
      expect(vramSummary(cardGb: 0, models: const {'sdxl': 8}), isEmpty);
      expect(vramSummary(cardGb: 10, models: const {}), isEmpty);
    });
  });
}
