/// Grobe Kosten- und Qualitätsschätzung für die aktuell gewählten
/// Modelle – speist die grafische Anzeige direkt neben den
/// Modell-Einstellungen im Generator- und 3D-Tab.
///
/// Die Preise stammen aus den öffentlichen Preislisten der Anbieter
/// (eingebaute Tabelle, Stand der App-Version) und sind bewusst als
/// Schätzwerte ausgewiesen: Der tatsächliche Abzug ist nach einem Lauf
/// an der Guthaben-/Token-Anzeige ablesbar. Meshy/Tripo rechnen in
/// Abo-Credits, deren Euro-Wert vom gewählten Abo abhängt – dort werden
/// Spannen angezeigt.
library;

import 'settings_service.dart';
import '../models/models.dart';

/// Ein Kostenposten eines Laufs (z. B. „4 × Bild-KI“ oder „3D-Modell“).
class CostItem {
  const CostItem(this.label, this.minUsd, this.maxUsd);

  final String label;
  final double minUsd;
  final double maxUsd;
}

/// Gesamtschätzung: Posten, Qualitätsstufe (1–5) und Beschriftung.
class CostQualityEstimate {
  const CostQualityEstimate({
    required this.items,
    required this.quality,
    required this.qualityLabel,
  });

  final List<CostItem> items;

  /// Qualitätsstufe 1 (Basis) … 5 (Spitzenklasse).
  final int quality;
  final String qualityLabel;

  double get minTotal =>
      items.fold(0.0, (sum, item) => sum + item.minUsd);
  double get maxTotal =>
      items.fold(0.0, (sum, item) => sum + item.maxUsd);

  String get totalLabel => formatUsdRange(minTotal, maxTotal);
}

String _usd(double v) =>
    '${v.toStringAsFixed(2).replaceAll('.', ',')} \$';

/// „kostenlos“, „≈ 0,04 $“ oder „≈ 0,20–0,60 $“.
String formatUsdRange(double min, double max) {
  if (max <= 0) return 'kostenlos';
  if ((max - min).abs() < 0.005) return '≈ ${_usd(max)}';
  return '≈ ${_usd(min)}–${_usd(max)}';
}

const qualityTierLabels = {
  1: 'Basis',
  2: 'Budget – schnell & günstig',
  3: 'Solide Mittelklasse',
  4: 'Hohe Qualität',
  5: 'Spitzenklasse',
};

/// Preis pro Bild und Qualitätsstufe des eingestellten Bild-Modells:
/// (min $, max $, Stufe 1–5).
(double, double, int) imageModelCost(SettingsService settings) {
  final provider = settings.provider;
  final model = settings.modelFor(provider).toLowerCase();
  switch (provider) {
    case GenProvider.openai:
      // gpt-image: Preis hängt an der Qualitätsstufe (auto ≈ medium).
      final mini = model.contains('mini');
      final (low, medium, high) = mini
          ? (0.005, 0.011, 0.036)
          : (0.011, 0.042, 0.167);
      final cost = switch (settings.quality) {
        'low' => low,
        'high' => high,
        _ => medium,
      };
      final tier = mini
          ? 2
          : (model.contains('1.5') || model.contains('image-2') ? 5 : 4);
      return (cost, cost, tier);
    case GenProvider.gemini:
      if (model.contains('pro')) {
        final is4k = settings.geminiImageSize == '4K';
        return (is4k ? 0.24 : 0.134, is4k ? 0.24 : 0.134, 5);
      }
      return (0.039, 0.039, 3);
    case GenProvider.stability:
      return switch (model) {
        'ultra' => (0.08, 0.08, 5),
        'sd3' => (0.065, 0.065, 4),
        'core' => (0.03, 0.03, 2),
        _ => (0.03, 0.08, 3),
      };
    case GenProvider.selfhost:
      // Eigene GPU: keine Kosten, nur Strom und Rechenzeit. Die Stufe
      // richtet sich nach dem geladenen Modell.
      final tier = switch (model) {
        'flux-schnell' => 5,
        'sd35-medium' => 4,
        'sdxl' => 4,
        'sdxl-turbo' => 3,
        'sd15' => 2,
        _ => 3,
      };
      return (0, 0, tier);
  }
}

/// Schätzung für einen Lauf des Bildgenerators (Anzahl × Bildpreis).
CostQualityEstimate estimateImageRun(SettingsService settings) {
  final (min, max, tier) = imageModelCost(settings);
  final count = settings.count;
  return CostQualityEstimate(
    items: [
      CostItem(
          count > 1 ? '$count Bilder' : '1 Bild', min * count, max * count),
    ],
    quality: tier,
    qualityLabel: qualityTierLabels[tier]!,
  );
}

/// Schätzung für einen Lauf des 3D-Generators: Bild-KI-Schritte
/// (Ansichten, Tiefenkarten) plus der 3D-Dienst selbst.
CostQualityEstimate estimate3dRun(
  SettingsService settings, {
  required int viewsToGenerate,
  required int depthMaps,
  required String stabilityEngine,
  required bool rigging,
  String meshyAiModel = '',
  String tripoVersion = '',
  String falModel = '',
  String rodinTier = '',
  String replicateModel = '',
}) {
  final items = <CostItem>[];
  final (imgMin, imgMax, _) = imageModelCost(settings);
  if (viewsToGenerate > 0) {
    items.add(CostItem(
        viewsToGenerate > 1
            ? '$viewsToGenerate Ansichten (Bild-KI)'
            : '1 Ansicht (Bild-KI)',
        imgMin * viewsToGenerate,
        imgMax * viewsToGenerate));
  }
  if (depthMaps > 0) {
    items.add(CostItem('$depthMaps Tiefenkarten (Bild-KI)',
        imgMin * depthMaps, imgMax * depthMaps));
  }

  int tier;
  switch (settings.threeDProvider) {
    case 'local':
      items.add(const CostItem('Lokaler 3D-Generator', 0, 0));
      tier = 1;
    case 'stability':
      final spar = stabilityEngine != 'stable-fast-3d';
      items.add(CostItem(
          spar ? '3D-Modell (Point Aware 3D)' : '3D-Modell (Fast 3D)',
          spar ? 0.04 : 0.02,
          spar ? 0.04 : 0.02));
      tier = spar ? 2 : 1;
    case 'selfhost':
      // Eigener PC: keine laufenden Kosten; Qualität je nach Backend
      // (TripoSR solide, TRELLIS besser) – Mittelklasse als Schätzung.
      items.add(const CostItem('Eigener 3D-Server (TripoSR/TRELLIS)', 0, 0));
      tier = 3;
    case 'fal':
      // Pay per Use, Preis hängt am gewählten Marktplatz-Modell;
      // eigene Modell-IDs bekommen eine breite Spanne.
      final (falLabel, falMin, falMax, falTier) = switch (falModel) {
        'fal-ai/triposr' => ('TripoSR', 0.01, 0.02, 2),
        'fal-ai/trellis' => ('TRELLIS', 0.02, 0.05, 3),
        'fal-ai/trellis-2' => ('TRELLIS.2', 0.05, 0.15, 4),
        'fal-ai/hunyuan3d/v2' => ('Hunyuan3D 2.0', 0.16, 0.48, 4),
        'fal-ai/hunyuan-3d/v3.1/pro/image-to-3d' => (
            'Hunyuan3D 3.1 Pro',
            0.30,
            0.60,
            5
          ),
        _ => ('eigenes Modell', 0.02, 0.60, 3),
      };
      items.add(CostItem('3D-Modell ($falLabel, fal.ai)', falMin, falMax));
      tier = falTier;
    case 'replicate':
      // Abrechnung je Lauf bzw. nach GPU-Sekunden – Spannen je Modell.
      final (repLabel, repMin, repMax, repTier) =
          switch (replicateModel.split(':').first) {
        'firtoz/trellis' => ('TRELLIS', 0.02, 0.06, 3),
        'tencent/hunyuan3d-2' => ('Hunyuan3D 2.0', 0.10, 0.30, 4),
        _ => ('eigenes Modell', 0.02, 0.60, 3),
      };
      items.add(
          CostItem('3D-Modell ($repLabel, Replicate)', repMin, repMax));
      tier = repTier;
    case 'rodin':
      // Pay per Use; Gen-2.5-Medium ist die schnellere, günstigere
      // Variante. Rigging übernimmt der eigene lokale Auto-Rigger.
      final medium = rodinTier == 'Gen-2.5-Medium';
      items.add(CostItem('3D-Modell (Rodin Gen-2.5)', medium ? 0.15 : 0.25,
          medium ? 0.40 : 0.80));
      tier = medium ? 4 : 5;
    case 'tripo':
      // Abo-Credits: Euro-Wert je nach Paket – daher eine Spanne.
      items.add(CostItem(
          rigging ? '3D-Modell + Rigging (Tripo)' : '3D-Modell (Tripo)',
          rigging ? 0.15 : 0.10,
          rigging ? 0.60 : 0.40));
      tier = tripoVersion.startsWith('v3') ? 5 : 4;
    default: // meshy
      items.add(CostItem(
          rigging ? '3D-Modell + Rigging (Meshy)' : '3D-Modell (Meshy)',
          rigging ? 0.20 : 0.15,
          rigging ? 0.70 : 0.50));
      tier = meshyAiModel == 'meshy-6' ||
              meshyAiModel == 'meshy-7' ||
              meshyAiModel == 'latest'
          ? 5
          : 4;
  }

  return CostQualityEstimate(
    items: items,
    quality: tier,
    qualityLabel: qualityTierLabels[tier]!,
  );
}
