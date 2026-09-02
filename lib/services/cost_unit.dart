/// Die normierte Kosteneinheit: was ein Asset **wirklich** kostet,
/// über alle Anbieter hinweg vergleichbar.
///
/// **Das Problem.** Die Anbieter rechnen in verschiedenen Währungen im
/// wörtlichen Sinn: Stability nimmt Credits mit festem Dollarwert, fal
/// und Replicate rechnen je Lauf oder nach GPU-Sekunden, Meshy und
/// Tripo verkaufen Abo-Credits, deren Wert vom gebuchten Paket
/// abhängt – dieselbe Zahl Credits kostet im kleinen Abo das Dreifache
/// wie im großen. „0,10 bis 0,40 $" ist deshalb ehrlich, aber zum
/// Vergleichen unbrauchbar: Zwei Anbieter mit überlappenden Spannen
/// lassen sich so nicht ordnen.
///
/// **Die Einheit.** Ein **AE** (Asset-Einheit) ist der Preis eines
/// fertigen Assets bei der jeweils günstigsten regulären Stufe des
/// Anbieters, in Cent. Sie beantwortet die Frage, die man beim
/// Vergleichen wirklich hat: *Wie viele Assets bekomme ich für zehn
/// Euro?*
///
/// Drei Regeln machen sie vergleichbar:
///
/// 1. **Ein Asset ist ein Asset.** Nicht ein Aufruf, nicht ein Credit.
///    Ein Lauf, der vier Ansichten braucht und daraus ein Modell
///    rechnet, kostet vier Bildpreise plus einen Modellpreis – und das
///    ist zusammen eine Asset-Einheit.
/// 2. **Abo-Credits werden zum Listenpreis der günstigsten regulären
///    Stufe gerechnet**, nicht zum Einführungs- oder Jahrespreis. Wer
///    ein größeres Paket hat, zahlt weniger; die Zahl ist damit eine
///    Obergrenze und keine Überraschung nach unten.
/// 3. **Eigene Hardware ist nicht kostenlos**, sie kostet nur nichts
///    *zusätzlich*. Sie steht mit 0 AE da, und daneben steht, warum.
library;

import 'cost_estimator.dart';

/// Wie eine Zahl zustande kommt – das entscheidet, wie belastbar sie
/// ist.
enum CostBasis {
  /// Fester Listenpreis je Aufruf. Verlässlich.
  perCall,

  /// Abo-Credits: Der Wert hängt vom gebuchten Paket ab. Gerechnet
  /// wird mit der günstigsten regulären Stufe.
  credits,

  /// Nach Rechenzeit. Schwankt mit der Last und der Motivgröße.
  compute,

  /// Läuft auf eigener Hardware.
  ownHardware,
}

extension CostBasisLabel on CostBasis {
  String get label => switch (this) {
        CostBasis.perCall => 'fester Preis je Aufruf',
        CostBasis.credits => 'Abo-Credits',
        CostBasis.compute => 'nach Rechenzeit',
        CostBasis.ownHardware => 'eigene Hardware',
      };

  /// Wie belastbar die Zahl ist, in einem Satz.
  String get caveat => switch (this) {
        CostBasis.perCall => 'Fester Listenpreis – die Zahl stimmt.',
        CostBasis.credits =>
          'Gerechnet mit der günstigsten regulären Stufe. Mit einem '
              'größeren Paket wird es billiger, nie teurer.',
        CostBasis.compute =>
          'Rechnet nach Zeit: Ein großes Motiv kostet mehr als ein '
              'kleines. Die Zahl ist ein Mittelwert.',
        CostBasis.ownHardware =>
          'Kostet nichts zusätzlich – Strom und Anschaffung stehen '
              'hier nicht drin, weil sie nicht am Lauf hängen.',
      };
}

/// Was ein Asset bei einem Anbieter kostet, normiert.
class AssetUnitCost {
  const AssetUnitCost({
    required this.provider,
    required this.label,
    required this.cents,
    required this.basis,
    this.note = '',
  });

  final String provider;
  final String label;

  /// Der Preis eines Assets in Cent (US-Cent).
  final double cents;

  final CostBasis basis;
  final String note;

  /// Wie viele Assets für zehn Euro – die Zahl, die man beim
  /// Vergleichen wirklich sucht.
  ///
  /// Gerechnet mit 1 € ≈ 1,08 $; der Kurs steht in
  /// [euroPerDollar], damit er an einer Stelle steht.
  int get assetsPerTenEuro {
    if (cents <= 0) return -1;
    return (1000 * euroPerDollar / cents).floor();
  }

  /// Beschriftung für die Anzeige.
  String get perTenEuroLabel => cents <= 0
      ? 'unbegrenzt'
      : '${_n(assetsPerTenEuro)} Stück für 10 €';

  String get centsLabel => cents <= 0
      ? '0 AE'
      : '${cents.toStringAsFixed(cents < 10 ? 1 : 0).replaceAll('.', ',')} AE';
}

/// Wie viele Dollar ein Euro ist.
///
/// An einer Stelle, weil er altert. Die Zahl ist bewusst grob: Sie
/// dient dem Größenvergleich zwischen Anbietern, nicht der
/// Buchhaltung.
const double euroPerDollar = 1.08;

/// Rechnet eine Schätzung in Asset-Einheiten um.
///
/// Genommen wird der **obere** Rand der Spanne. Wer plant, plant nicht
/// mit dem besten Fall – und bei Abo-Credits ist der untere Rand ein
/// Paket, das man vielleicht gar nicht hat.
AssetUnitCost unitCostOf(
  CostQualityEstimate estimate, {
  required String provider,
  required String label,
  required CostBasis basis,
  String note = '',
}) =>
    AssetUnitCost(
      provider: provider,
      label: label,
      cents: estimate.maxTotal * 100,
      basis: basis,
      note: note,
    );

/// Auf welcher Grundlage ein Anbieter abrechnet.
CostBasis basisOf(String provider) => switch (provider) {
      'local' || 'selfhost' => CostBasis.ownHardware,
      'stability' || 'openai' || 'gemini' => CostBasis.perCall,
      'meshy' || 'tripo' => CostBasis.credits,
      'fal' || 'replicate' || 'rodin' => CostBasis.compute,
      _ => CostBasis.compute,
    };

/// Eine Zeile für den Vergleich, aus einer fertigen Schätzung.
String unitCostLine(AssetUnitCost cost) =>
    '${cost.label}: ${cost.centsLabel} '
    '(${cost.perTenEuroLabel}) – ${cost.basis.label}';

String _n(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
    buffer.write(text[i]);
  }
  return buffer.toString();
}
