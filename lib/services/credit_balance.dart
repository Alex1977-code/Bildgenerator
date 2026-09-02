import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'balance_service.dart';
import 'settings_service.dart';

/// Das Guthaben in der Kopfzeile: „Tripo3D 742 Cr. · Gemini Schlüssel ✓".
///
/// Kosten sind ständiger Begleiter, keine Fußnote. Bisher stand das
/// Restguthaben nur nach einem Lauf als Satz unter den Ergebnissen –
/// jetzt steht es oben, für den Bild- und den 3D-Anbieter, die gerade
/// gewählt sind.
///
/// Zwei Grenzen, die die Anzeige benennt statt versteckt: Nur
/// Stability, Meshy und Tripo melden ein Guthaben über ihre API. Bei
/// OpenAI und Gemini zeigt die Kopfzeile, ob ein Schlüssel hinterlegt
/// ist; die eigene GPU kostet nichts. Und die Zahl ist so alt wie die
/// letzte Abfrage – ein Klick holt sie neu.
class CreditBalances extends ChangeNotifier {
  CreditBalances({this.fetch = fetchProviderCredits});

  /// Austauschbar für Tests.
  final Future<double?> Function(String providerId, String apiKey) fetch;

  final Map<String, double> _credits = {};
  DateTime? lastRefresh;
  bool refreshing = false;

  double? creditsOf(String providerId) => _credits[providerId];

  /// Ein Lauf hat das Restguthaben mitgeliefert – gleich übernehmen,
  /// ohne eine eigene Abfrage.
  void noteRemaining(String providerId, double credits) {
    _credits[providerId] = credits;
    lastRefresh = DateTime.now();
    notifyListeners();
  }

  /// Fragt alle Anbieter mit Guthaben-API ab, für die ein Schlüssel
  /// hinterlegt ist.
  Future<void> refresh(SettingsService settings) async {
    if (refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      final keys = <String, String?>{
        'stability': settings.apiKeyFor(GenProvider.stability),
        'meshy': settings.meshyApiKey,
        'tripo': settings.tripoApiKey,
      };
      for (final entry in keys.entries) {
        final key = entry.value?.trim() ?? '';
        if (key.isEmpty) {
          _credits.remove(entry.key);
          continue;
        }
        final credits = await fetch(entry.key, key);
        if (credits != null) _credits[entry.key] = credits;
      }
      lastRefresh = DateTime.now();
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }
}

/// Ein Eintrag der Guthaben-Anzeige: Anbieter und Wert.
class BalanceChipPart {
  const BalanceChipPart(this.label, this.value, {this.warning = false});

  /// „Tripo3D", „Gemini".
  final String label;

  /// „742 Cr.", „Schlüssel ✓", „kein Schlüssel", „0 $".
  final String value;

  /// Fehlt etwas, das den nächsten Lauf verhindert?
  final bool warning;
}

/// Kennung des 3D-Providers → Anzeigename.
String threeDProviderLabel(String id) => switch (id) {
      'tripo' => 'Tripo3D',
      'meshy' => 'Meshy',
      'stability' => 'Stability',
      'fal' => 'fal.ai',
      'rodin' => 'Rodin',
      'replicate' => 'Replicate',
      'selfhost' => 'Eigener 3D-Server',
      _ => 'Lokal',
    };

String _creditsLabel(double credits) => credits >= 100
    ? '${credits.round()} Cr.'
    : '${credits.toStringAsFixed(1)} Cr.';

/// Was in der Kopfzeile steht – der gewählte Bild-Anbieter und der
/// gewählte 3D-Anbieter, je mit dem, was über sie bekannt ist.
List<BalanceChipPart> balanceChipParts(
    SettingsService settings, CreditBalances balances) {
  final parts = <BalanceChipPart>[];

  // Bild-Anbieter.
  final image = settings.provider;
  if (image.isLocal) {
    parts.add(const BalanceChipPart('Eigene GPU', '0 \$'));
  } else {
    final credits = image == GenProvider.stability
        ? balances.creditsOf('stability')
        : null;
    final hasKey = settings.hasApiKeyFor(image);
    parts.add(BalanceChipPart(
      image.shortLabel,
      credits != null
          ? _creditsLabel(credits)
          : hasKey
              ? 'Schlüssel ✓'
              : 'kein Schlüssel',
      warning: !hasKey,
    ));
  }

  // 3D-Anbieter – nur, wenn er nicht derselbe ist wie oben (Stability
  // stünde sonst zweimal da).
  final threeD = settings.threeDProvider;
  if (threeD == 'local') {
    parts.add(const BalanceChipPart('3D lokal', '0 \$'));
  } else if (threeD == 'stability' && image == GenProvider.stability) {
    // schon oben
  } else {
    final key = switch (threeD) {
      'stability' => settings.apiKeyFor(GenProvider.stability),
      'meshy' => settings.meshyApiKey,
      'tripo' => settings.tripoApiKey,
      'fal' => settings.falApiKey,
      'rodin' => settings.rodinApiKey,
      'replicate' => settings.replicateApiKey,
      'selfhost' => settings.selfHostUrl,
      _ => null,
    };
    final hasKey = (key ?? '').trim().isNotEmpty;
    final credits = balances.creditsOf(threeD);
    parts.add(BalanceChipPart(
      threeDProviderLabel(threeD),
      credits != null
          ? _creditsLabel(credits)
          : threeD == 'selfhost'
              ? (hasKey ? 'bereit' : 'keine Adresse')
              : hasKey
                  ? (providersWithBalance.contains(threeD)
                      ? 'Schlüssel ✓'
                      : 'je Lauf')
                  : 'kein Schlüssel',
      warning: !hasKey,
    ));
  }
  return parts;
}
