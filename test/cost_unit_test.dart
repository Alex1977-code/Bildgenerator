import 'package:bildgenerator/services/cost_estimator.dart';
import 'package:bildgenerator/services/cost_unit.dart';
import 'package:flutter_test/flutter_test.dart';

CostQualityEstimate _schaetzung(double min, double max) =>
    CostQualityEstimate(
      items: [CostItem('3D-Modell', min, max)],
      quality: 4,
      qualityLabel: 'x',
    );

void main() {
  group('Die Asset-Einheit', () {
    test('rechnet den oberen Rand der Spanne', () {
      // Wer plant, plant nicht mit dem besten Fall – und bei
      // Abo-Credits ist der untere Rand ein Paket, das man vielleicht
      // gar nicht hat.
      final ae = unitCostOf(_schaetzung(0.10, 0.40),
          provider: 'tripo', label: 'Tripo', basis: CostBasis.credits);
      expect(ae.cents, closeTo(40, 0.001));
    });

    test('beantwortet die Frage, die man wirklich hat', () {
      final ae = unitCostOf(_schaetzung(0.10, 0.40),
          provider: 'tripo', label: 'Tripo', basis: CostBasis.credits);
      // 10 € sind 10,80 $ – bei 40 Cent je Asset sind das 27 Stück.
      expect(ae.assetsPerTenEuro, 27);
      expect(ae.perTenEuroLabel, contains('27'));
      expect(ae.perTenEuroLabel, contains('10 €'));
    });

    test('macht zwei Anbieter mit überlappenden Spannen vergleichbar', () {
      // Genau das Problem: 0,10–0,40 und 0,15–0,50 lassen sich als
      // Spannen nicht ordnen, als Zahl schon.
      final a = unitCostOf(_schaetzung(0.10, 0.40),
          provider: 'tripo', label: 'Tripo', basis: CostBasis.credits);
      final b = unitCostOf(_schaetzung(0.15, 0.50),
          provider: 'meshy', label: 'Meshy', basis: CostBasis.credits);
      expect(a.cents, lessThan(b.cents));
      expect(a.assetsPerTenEuro, greaterThan(b.assetsPerTenEuro));
    });

    test('eigene Hardware steht bei null, ohne „unendlich" zu behaupten',
        () {
      final ae = unitCostOf(_schaetzung(0, 0),
          provider: 'local',
          label: 'Lokal',
          basis: CostBasis.ownHardware);
      expect(ae.cents, 0);
      expect(ae.centsLabel, '0 AE');
      expect(ae.perTenEuroLabel, 'unbegrenzt');
      // Und der Vorbehalt sagt, was fehlt.
      expect(ae.basis.caveat, contains('Strom'));
    });

    test('die Beschriftung rundet lesbar', () {
      expect(
          unitCostOf(_schaetzung(0, 0.04),
                  provider: 'stability',
                  label: 'x',
                  basis: CostBasis.perCall)
              .centsLabel,
          '4,0 AE');
      expect(
          unitCostOf(_schaetzung(0, 0.40),
                  provider: 'tripo', label: 'x', basis: CostBasis.credits)
              .centsLabel,
          '40 AE');
    });
  });

  group('Die Grundlage', () {
    test('jede Art sagt, wie belastbar ihre Zahl ist', () {
      for (final basis in CostBasis.values) {
        expect(basis.label, isNotEmpty);
        expect(basis.caveat.length, greaterThan(30), reason: basis.name);
      }
    });

    test('Abo-Credits sind eine Obergrenze, keine Überraschung', () {
      expect(CostBasis.credits.caveat, contains('nie teurer'));
    });

    test('die Anbieter sind richtig zugeordnet', () {
      expect(basisOf('local'), CostBasis.ownHardware);
      expect(basisOf('selfhost'), CostBasis.ownHardware);
      expect(basisOf('stability'), CostBasis.perCall);
      expect(basisOf('tripo'), CostBasis.credits);
      expect(basisOf('meshy'), CostBasis.credits);
      expect(basisOf('fal'), CostBasis.compute);
      expect(basisOf('rodin'), CostBasis.compute);
    });

    test('ein unbekannter Anbieter gilt als Rechenzeit', () {
      // Die vorsichtigere Annahme: schwankend statt fest.
      expect(basisOf('neuerdienst'), CostBasis.compute);
    });
  });

  test('die Zeile nennt Zahl, Stückzahl und Grundlage', () {
    final zeile = unitCostLine(unitCostOf(_schaetzung(0.10, 0.40),
        provider: 'tripo', label: 'Tripo P1', basis: CostBasis.credits));
    expect(zeile, contains('Tripo P1'));
    expect(zeile, contains('AE'));
    expect(zeile, contains('10 €'));
    expect(zeile, contains('Abo-Credits'));
  });
}
