import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Verfügbare Bild-Provider.
enum GenProvider {
  openai('OpenAI (GPT Image)'),
  stability('Stability AI (Stable Image)'),
  gemini('Google Gemini (Nano Banana)');

  const GenProvider(this.label);
  final String label;

  /// Unterstützt der Provider Referenzbilder?
  bool get supportsReferences => this != GenProvider.stability;

  static GenProvider fromName(String? name) => GenProvider.values.firstWhere(
        (p) => p.name == name,
        orElse: () => GenProvider.openai,
      );
}

/// Ein vom Nutzer gewähltes Referenzbild.
class ReferenceImage {
  ReferenceImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  /// MIME-Typ anhand der Magic Bytes bestimmen.
  String get mimeType {
    final b = bytes;
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
      return 'image/png';
    }
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) {
      return 'image/jpeg';
    }
    if (b.length > 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45) {
      return 'image/webp';
    }
    return 'image/png';
  }
}

/// Alle Parameter einer Generierungsanfrage.
class GenerationRequest {
  GenerationRequest({
    required this.provider,
    required this.prompt,
    this.negativePrompt = '',
    this.references = const [],
    this.openAiSize = 'auto',
    this.stabilityAspect = '1:1',
    this.quality = 'auto',
    this.transparent = false,
    this.outputFormat = 'png',
    this.compression = 90,
    this.count = 1,
    this.seed = 0,
    this.stylePreset = '',
    this.model = '',
    this.geminiAspect = '1:1',
    this.geminiImageSize = '1K',
  });

  final GenProvider provider;
  final String prompt;
  final String negativePrompt;
  final List<ReferenceImage> references;

  /// Modell-ID bzw. Engine des Providers ('' = Standardmodell).
  final String model;

  /// Gemini: Seitenverhältnis ('1:1', '16:9', …).
  final String geminiAspect;

  /// Gemini (nur Pro-Modelle): Auflösung '1K', '2K' oder '4K'.
  final String geminiImageSize;

  /// OpenAI: 'auto', '1024x1024', '1536x1024', '1024x1536'
  final String openAiSize;

  /// Stability: '1:1', '16:9', ...
  final String stabilityAspect;

  /// OpenAI: 'auto', 'low', 'medium', 'high'
  final String quality;

  /// Transparenter Hintergrund (nur OpenAI, erzwingt PNG/WebP).
  final bool transparent;

  /// 'png', 'jpeg', 'webp'
  final String outputFormat;

  /// Kompression 0–100 (nur JPEG/WebP bei OpenAI).
  final int compression;

  /// Anzahl der Bilder (1–4).
  final int count;

  /// Seed (0 = zufällig, nur Stability).
  final int seed;

  /// Style-Preset (nur Stability, '' = keins).
  final String stylePreset;

  /// Lesbare Parameter-Zusammenfassung für Verlauf/Metadaten.
  Map<String, String> describeParams() {
    final map = <String, String>{'Provider': provider.label};
    if (model.isNotEmpty) map['Modell'] = model;
    switch (provider) {
      case GenProvider.openai:
        map['Größe'] = openAiSize;
        map['Qualität'] = quality;
        map['Transparenz'] = transparent ? 'ja' : 'nein';
      case GenProvider.stability:
        map['Seitenverhältnis'] = stabilityAspect;
        if (negativePrompt.trim().isNotEmpty) {
          map['Negativ-Prompt'] = negativePrompt.trim();
        }
        if (stylePreset.isNotEmpty) map['Style'] = stylePreset;
        if (seed != 0) map['Seed'] = '$seed';
      case GenProvider.gemini:
        map['Seitenverhältnis'] = geminiAspect;
        if (model.contains('pro')) map['Auflösung'] = geminiImageSize;
    }
    if (references.isNotEmpty) {
      map['Referenzbilder'] = '${references.length}';
    }
    map['Format'] = outputFormat.toUpperCase();
    return map;
  }
}

/// Ein generiertes Bild (Bytes + Format).
class GeneratedImage {
  GeneratedImage({required this.bytes, required this.format});

  final Uint8List bytes;

  /// 'png', 'jpeg', 'webp'
  final String format;

  String get mimeType => 'image/$format';

  String get fileExtension => format == 'jpeg' ? 'jpg' : format;
}

/// Ein Eintrag im Verlauf (Galerie).
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.prompt,
    required this.providerLabel,
    required this.createdAt,
    required this.params,
    required this.format,
    this.fileName,
  });

  final String id;
  final String prompt;
  final String providerLabel;
  final DateTime createdAt;
  final Map<String, String> params;
  final String format;

  /// Dateiname im lokalen Speicher (nur native Plattformen).
  final String? fileName;

  String get mimeType => 'image/$format';

  String get fileExtension => format == 'jpeg' ? 'jpg' : format;

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'providerLabel': providerLabel,
        'createdAt': createdAt.toIso8601String(),
        'params': params,
        'format': format,
        'fileName': fileName,
      };

  static HistoryEntry fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String,
        prompt: json['prompt'] as String? ?? '',
        providerLabel: json['providerLabel'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        params: (json['params'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, '$v')),
        format: json['format'] as String? ?? 'png',
        fileName: json['fileName'] as String?,
      );

  static String encodeList(List<HistoryEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  static List<HistoryEntry> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Ein fertiges 3D-Ergebnis (gilt für die aktuelle Sitzung).
class ThreeDResult {
  ThreeDResult({
    required this.glbBytes,
    required this.label,
    required this.providerLabel,
    this.thumbnailBytes,
    this.rigged = false,
    this.textured = false,
  });

  final Uint8List glbBytes;
  final String label;
  final String providerLabel;
  final Uint8List? thumbnailBytes;
  final bool rigged;
  final bool textured;
}

/// Auswahloptionen (Wert, Anzeigename).
typedef Option = (String value, String label);

const List<Option> openAiSizeOptions = [
  ('auto', 'Automatisch'),
  ('1024x1024', 'Quadrat (1024×1024)'),
  ('1536x1024', 'Querformat (1536×1024)'),
  ('1024x1536', 'Hochformat (1024×1536)'),
];

const List<Option> stabilityAspectOptions = [
  ('1:1', 'Quadrat (1:1)'),
  ('16:9', 'Breitbild (16:9)'),
  ('9:16', 'Hochkant (9:16)'),
  ('3:2', 'Foto quer (3:2)'),
  ('2:3', 'Foto hoch (2:3)'),
  ('21:9', 'Ultrabreit (21:9)'),
  ('9:21', 'Ultrahoch (9:21)'),
  ('4:5', 'Portrait (4:5)'),
  ('5:4', 'Landschaft (5:4)'),
];

const List<Option> qualityOptions = [
  ('auto', 'Auto'),
  ('low', 'Niedrig'),
  ('medium', 'Mittel'),
  ('high', 'Hoch'),
];

const List<Option> formatOptions = [
  ('png', 'PNG'),
  ('jpeg', 'JPEG'),
  ('webp', 'WebP'),
];

const List<Option> geminiAspectOptions = [
  ('1:1', 'Quadrat (1:1)'),
  ('16:9', 'Breitbild (16:9)'),
  ('9:16', 'Hochkant (9:16)'),
  ('3:2', 'Foto quer (3:2)'),
  ('2:3', 'Foto hoch (2:3)'),
  ('4:3', 'Klassisch quer (4:3)'),
  ('3:4', 'Klassisch hoch (3:4)'),
  ('4:5', 'Portrait (4:5)'),
  ('5:4', 'Landschaft (5:4)'),
  ('21:9', 'Ultrabreit (21:9)'),
];

const List<Option> geminiImageSizeOptions = [
  ('1K', '1K (Standard)'),
  ('2K', '2K'),
  ('4K', '4K'),
];

/// Pixelmaße je Seitenverhältnis bei Gemini (1K-Basis, laut API-Doku).
/// 2K verdoppelt, 4K vervierfacht beide Kanten.
const Map<String, (int, int)> geminiAspectBaseSizes = {
  '1:1': (1024, 1024),
  '16:9': (1344, 768),
  '9:16': (768, 1344),
  '3:2': (1248, 832),
  '2:3': (832, 1248),
  '4:3': (1184, 864),
  '3:4': (864, 1184),
  '4:5': (896, 1152),
  '5:4': (1152, 896),
  '21:9': (1536, 672),
};

/// Pixelangabe für ein Gemini-Seitenverhältnis, z. B. "1344×768 px".
String geminiAspectPixelLabel(String aspect, String imageSize) {
  final base = geminiAspectBaseSizes[aspect];
  if (base == null) return '';
  final factor = imageSize == '4K'
      ? 4
      : imageSize == '2K'
          ? 2
          : 1;
  return '${base.$1 * factor}×${base.$2 * factor} px';
}

/// Ungefähre Pixelmaße bei Stability: Core liefert ca. 1,5 Megapixel,
/// Ultra ca. 1 Megapixel; die Kanten sind Vielfache von 64.
(int, int) stabilityApproxPixels(String aspect, String engine) {
  final parts = aspect.split(':');
  final ratio = int.parse(parts[0]) / int.parse(parts[1]);
  final megapixels = engine == 'ultra' ? 1000000.0 : 1500000.0;
  int roundTo64(double v) => ((v / 64).round()) * 64;
  final width = roundTo64(math.sqrt(megapixels * ratio));
  final height = roundTo64(width / ratio);
  return (width, height);
}

/// Bekannte Modelle je Provider. Über die Einstellungen kann auch eine
/// beliebige andere Modell-ID eingetragen werden (z. B. wenn ein Anbieter
/// ein neueres Modell veröffentlicht).
const List<Option> openAiModelOptions = [
  ('gpt-image-1', 'gpt-image-1 (Standard)'),
  ('gpt-image-1-mini', 'gpt-image-1-mini (günstiger)'),
];

const List<Option> stabilityModelOptions = [
  ('core', 'Core (günstig, Style-Presets)'),
  ('ultra', 'Ultra (höchste Qualität)'),
];

const List<Option> geminiModelOptions = [
  ('gemini-2.5-flash-image', 'Nano Banana (schnell)'),
  ('gemini-3-pro-image-preview', 'Nano Banana Pro (bis 4K)'),
];

const List<Option> stylePresetOptions = [
  ('', 'Kein Style'),
  ('photographic', 'Fotografisch'),
  ('cinematic', 'Filmisch'),
  ('digital-art', 'Digital Art'),
  ('anime', 'Anime'),
  ('comic-book', 'Comic'),
  ('fantasy-art', 'Fantasy'),
  ('3d-model', '3D-Modell'),
  ('analog-film', 'Analogfilm'),
  ('line-art', 'Line Art'),
  ('isometric', 'Isometrisch'),
  ('low-poly', 'Low Poly'),
  ('neon-punk', 'Neon Punk'),
  ('origami', 'Origami'),
  ('pixel-art', 'Pixel Art'),
  ('tile-texture', 'Kachel-Textur'),
];

/// Prompt-Vorlagen, die an den Prompt angehängt werden können.
const List<Option> promptTemplates = [
  ('fotorealistisch, hohe Detailtiefe, natürliches Licht', 'Fotorealistisch'),
  ('als Ölgemälde im impressionistischen Stil', 'Ölgemälde'),
  ('als Aquarell mit weichen Farbverläufen', 'Aquarell'),
  ('als minimalistisches flaches Vektor-Logo', 'Logo/Icon'),
  ('als hochwertiger 3D-Render, Studio-Beleuchtung', '3D-Render'),
  ('im Anime-Stil, klare Linien, lebendige Farben', 'Anime'),
  ('als Pixel-Art im Retro-Spielstil', 'Pixel-Art'),
  ('als Produktfoto vor neutralem Hintergrund', 'Produktfoto'),
];
