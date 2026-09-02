import 'package:flutter/material.dart';

import '../services/cost_estimator.dart';
import '../services/cost_unit.dart';

/// Grafische Anzeige neben den Modell-Einstellungen: Qualitätsstufe
/// (5er-Skala) und geschätzte Gesamtkosten pro Lauf mit Aufschlüsselung.
class CostQualityPanel extends StatelessWidget {
  const CostQualityPanel(
      {super.key, required this.estimate, this.provider = ''});

  final CostQualityEstimate estimate;

  /// Der Anbieter – für die normierte Einheit. Leer heißt: nur die
  /// Spanne anzeigen, wie bisher.
  final String provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Skalenfarbe: unten Richtung Orange, oben Richtung Grün – gleiche
    // Logik in hell und dunkel gut lesbar.
    final tierColor = switch (estimate.quality) {
      <= 2 => Colors.orange.shade700,
      3 => scheme.primary,
      _ => Colors.green.shade600,
    };
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('QUALITÄTSSTUFE',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.outline, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i < 4 ? 3 : 0),
                    decoration: BoxDecoration(
                      color: i < estimate.quality
                          ? tierColor
                          : scheme.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(estimate.qualityLabel,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text('KOSTEN PRO LAUF',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.outline, letterSpacing: 0.6)),
          const SizedBox(height: 2),
          Text(estimate.totalLabel,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final item in estimate.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${item.label}: '
                '${formatUsdRange(item.minUsd, item.maxUsd)}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          // Die normierte Einheit. Zwei Anbieter mit überlappenden
          // Spannen lassen sich als Spanne nicht ordnen – als Zahl
          // schon, und die Frage dahinter ist ohnehin: Wie viele
          // Assets bekomme ich für zehn Euro?
          if (provider.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('VERGLEICHSWERT',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.outline, letterSpacing: 0.6)),
            const SizedBox(height: 2),
            Builder(builder: (context) {
              final ae = unitCostOf(estimate,
                  provider: provider,
                  label: provider,
                  basis: basisOf(provider));
              return Tooltip(
                message: ae.basis.caveat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ae.perTenEuroLabel,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${ae.centsLabel} je Asset · ${ae.basis.label}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.outline)),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 4),
          Text(
            'Schätzwerte laut Preisliste – realer Abzug siehe '
            'Guthaben-Anzeige nach dem Lauf.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.outline, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
