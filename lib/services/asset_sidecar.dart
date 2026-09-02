/// Das Herkunftsprotokoll: eine JSON-Datei neben jedem Asset.
///
/// Es gibt schon den **Erstellungsnachweis** als PDF – der ist für
/// Menschen gemacht, mit Unterschriftszeile und Prüfsumme. Diese Datei
/// ist das Gegenstück für Maschinen: gleiche Angaben, aber als JSON,
/// damit ein Skript, ein Asset-Verwalter oder der nächste Lauf sie
/// lesen kann.
///
/// **Warum das nötig ist.** Nach zwanzig Läufen weiß niemand mehr,
/// welches Modell aus welchem Prompt kam, welche Fassung des Anbieters
/// gerechnet hat und ob der Seed noch bekannt ist. Genau diese Angaben
/// entscheiden aber darüber, ob sich ein Ergebnis wiederholen lässt –
/// und ob man belegen kann, womit es entstanden ist. Ein Asset ohne
/// Herkunft ist beim Hochladen ein Risiko.
///
/// Was drinsteht, und warum jedes Feld:
///
/// * **Anbieter und Modellfassung.** „Tripo" allein reicht nicht: P1
///   und v2.5 liefern grundverschiedene Netze. Die Fassung ist der
///   Unterschied zwischen „nachvollziehbar" und „ungefähr so".
/// * **Prompt und Negativ-Prompt**, wörtlich – auch der Zusatz, den
///   die App angehängt hat. Wer nur den getippten Text speichert,
///   kann den Lauf nicht wiederholen.
/// * **Seed**, wenn der Anbieter einen liefert. Ohne ihn ist auch mit
///   gleichem Prompt jeder Lauf ein anderer.
/// * **Zeitpunkt** in ISO 8601 mit Zeitzone. „31.08.2026, 22:26" ist
///   für Menschen lesbar und für Maschinen mehrdeutig.
/// * **Lizenz** – die des Anbieters für erzeugte Inhalte, so wie sie
///   zum Zeitpunkt des Laufs galt. Sie ändert sich, und dann gilt für
///   das alte Asset weiterhin die alte.
/// * **Prüfsumme** der Werkdatei. Sie verknüpft Protokoll und Datei
///   eindeutig; jede Änderung an der Datei ergibt eine andere.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Die Lizenzlage eines Anbieters für erzeugte Inhalte.
///
/// **Kurzfassung, kein Rechtsrat.** Die Angaben stammen aus den
/// öffentlichen Nutzungsbedingungen zum genannten Stand; sie ändern
/// sich, und im Zweifel gilt der Vertrag, den man selbst
/// abgeschlossen hat. Genau deshalb steht das Datum daneben: Ein
/// Protokoll, das eine Lizenz ohne Stand behauptet, ist schlimmer als
/// keines.
class ProviderLicense {
  const ProviderLicense({
    required this.provider,
    required this.summary,
    required this.commercial,
    required this.checked,
    this.url = '',
  });

  final String provider;

  /// Ein Satz zur Lage.
  final String summary;

  /// Ob kommerzielle Nutzung nach diesen Bedingungen vorgesehen ist.
  final bool commercial;

  /// Stand der Angabe.
  final String checked;

  final String url;

  Map<String, dynamic> toJson() => {
        'anbieter': provider,
        'zusammenfassung': summary,
        'kommerziell': commercial,
        'stand': checked,
        if (url.isNotEmpty) 'quelle': url,
      };
}

/// Was die App über die Lizenzlage weiß.
const Map<String, ProviderLicense> providerLicenses = {
  'openai': ProviderLicense(
    provider: 'OpenAI',
    summary: 'Die Rechte an der Ausgabe liegen laut Nutzungsbedingungen '
        'beim Nutzer; kommerzielle Verwendung ist vorgesehen.',
    commercial: true,
    checked: '2026-09-01',
    url: 'https://openai.com/policies/terms-of-use',
  ),
  'gemini': ProviderLicense(
    provider: 'Google (Gemini)',
    summary: 'Google beansprucht keine Rechte an erzeugten Inhalten; '
        'für die Nutzung gelten die Google-Nutzungsbedingungen.',
    commercial: true,
    checked: '2026-09-01',
    url: 'https://policies.google.com/terms/generative-ai',
  ),
  'stability': ProviderLicense(
    provider: 'Stability AI',
    summary: 'Kommerzielle Nutzung der Ausgabe ist bei bezahlten '
        'Zugängen vorgesehen; für Selbst-Hosting gilt zusätzlich die '
        'Modelllizenz.',
    commercial: true,
    checked: '2026-09-01',
    url: 'https://stability.ai/license',
  ),
  'meshy': ProviderLicense(
    provider: 'Meshy',
    summary: 'Erzeugte Modelle gehören dem Nutzer; kommerzielle '
        'Nutzung ist ab den bezahlten Stufen vorgesehen.',
    commercial: true,
    checked: '2026-09-01',
    url: 'https://www.meshy.ai/terms',
  ),
  'tripo': ProviderLicense(
    provider: 'Tripo3D',
    summary: 'Erzeugte Modelle gehören dem Nutzer; kommerzielle '
        'Nutzung ist bei bezahlten Zugängen vorgesehen.',
    commercial: true,
    checked: '2026-09-01',
    url: 'https://www.tripo3d.ai/terms',
  ),
  'rodin': ProviderLicense(
    provider: 'Rodin (Hyper3D)',
    summary: 'Erzeugte Modelle gehören dem Nutzer; die Bedingungen '
        'unterscheiden nach Zugangsstufe.',
    commercial: true,
    checked: '2026-09-01',
    url: 'https://hyper3d.ai/terms',
  ),
  'local': ProviderLicense(
    provider: 'Lokaler Generator',
    summary: 'Auf dem eigenen Rechner gerechnet – es geht nichts an '
        'einen Dienst. Bei selbst betriebenen Modellen gilt deren '
        'eigene Lizenz (etwa CreativeML Open RAIL-M).',
    commercial: true,
    checked: '2026-09-01',
  ),
};

/// Die Lizenzlage zu einem Anbieter – unbekannt heißt: sagen, dass es
/// unbekannt ist.
ProviderLicense licenseFor(String provider) =>
    providerLicenses[provider] ??
    ProviderLicense(
      provider: provider.isEmpty ? 'unbekannt' : provider,
      summary: 'Für diesen Anbieter liegt der App keine Angabe vor. '
          'Vor einer Veröffentlichung selbst in den '
          'Nutzungsbedingungen nachsehen.',
      commercial: false,
      checked: '',
    );

/// Das Protokoll zu einem Asset.
class AssetSidecar {
  const AssetSidecar({
    required this.fileName,
    required this.kind,
    required this.provider,
    required this.createdAt,
    this.model = '',
    this.modelVersion = '',
    this.prompt = '',
    this.negativePrompt = '',
    this.promptSuffix = '',
    this.seed,
    this.settings = const {},
    this.pipeline = const [],
    this.sourceImages = const [],
    this.appVersion = '',
    this.checksum = '',
  });

  final String fileName;

  /// „Bild" oder „3D-Modell".
  final String kind;

  /// Anbieterkennung, wie die App sie führt: `tripo`, `openai` …
  final String provider;

  final DateTime createdAt;

  final String model;

  /// Die Fassung des Modells – bei Tripo etwa `P1-20260311`.
  ///
  /// Getrennt vom Namen, weil genau daran der Unterschied hängt: P1
  /// und v2.5 liefern grundverschiedene Netze.
  final String modelVersion;

  final String prompt;
  final String negativePrompt;

  /// Was die App an den Prompt gehängt hat (Pose, fester Schwanz).
  ///
  /// Getrennt geführt, damit sich später sagen lässt, welcher Teil vom
  /// Menschen kam und welcher von der App.
  final String promptSuffix;

  final int? seed;

  /// Die Einstellungen des Laufs.
  final Map<String, Object?> settings;

  /// Was nach der Erzeugung mit der Datei passiert ist – in der
  /// Reihenfolge, in der es passiert ist.
  final List<String> pipeline;

  /// Namen der Eingabebilder, falls aus Bildern gerechnet wurde.
  final List<String> sourceImages;

  final String appVersion;

  /// SHA-256 der Werkdatei.
  final String checksum;

  /// Der vollständige Prompt, so wie er beim Anbieter ankam.
  String get fullPrompt =>
      promptSuffix.isEmpty ? prompt : '$prompt, $promptSuffix';

  Map<String, dynamic> toJson() => {
        'protokollFassung': sidecarVersion,
        'datei': fileName,
        'art': kind,
        'erzeugtAm': createdAt.toIso8601String(),
        'anbieter': provider,
        if (model.isNotEmpty) 'modell': model,
        if (modelVersion.isNotEmpty) 'modellFassung': modelVersion,
        if (prompt.isNotEmpty) 'prompt': prompt,
        if (promptSuffix.isNotEmpty) 'promptZusatz': promptSuffix,
        if (prompt.isNotEmpty) 'promptVollstaendig': fullPrompt,
        if (negativePrompt.isNotEmpty) 'negativPrompt': negativePrompt,
        'seed': seed,
        if (settings.isNotEmpty) 'einstellungen': settings,
        if (pipeline.isNotEmpty) 'nachbearbeitung': pipeline,
        if (sourceImages.isNotEmpty) 'eingabebilder': sourceImages,
        if (appVersion.isNotEmpty) 'appFassung': appVersion,
        if (checksum.isNotEmpty) 'pruefsummeSha256': checksum,
        'lizenz': licenseFor(provider).toJson(),
      };

  /// Als JSON-Text, eingerückt – die Datei wird auch gelesen.
  String toJsonText() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  /// Der Dateiname des Protokolls zu einer Werkdatei.
  ///
  /// `.herkunft.json` statt nur `.json`: Ein Modellordner enthält oft
  /// schon JSON-Dateien, und ein Protokoll, das man mit einer
  /// Konfigurationsdatei verwechselt, hilft niemandem.
  static String sidecarNameFor(String assetFile) {
    final punkt = assetFile.lastIndexOf('.');
    final stamm = punkt <= 0 ? assetFile : assetFile.substring(0, punkt);
    return '$stamm.herkunft.json';
  }

  /// Liest ein Protokoll zurück.
  ///
  /// Fehlende Felder sind kein Fehler: Ein älteres Protokoll kennt
  /// weniger, und es soll trotzdem lesbar bleiben.
  static AssetSidecar fromJson(Map<String, dynamic> json) => AssetSidecar(
        fileName: (json['datei'] as String?) ?? '',
        kind: (json['art'] as String?) ?? '',
        provider: (json['anbieter'] as String?) ?? '',
        createdAt: DateTime.tryParse((json['erzeugtAm'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        model: (json['modell'] as String?) ?? '',
        modelVersion: (json['modellFassung'] as String?) ?? '',
        prompt: (json['prompt'] as String?) ?? '',
        negativePrompt: (json['negativPrompt'] as String?) ?? '',
        promptSuffix: (json['promptZusatz'] as String?) ?? '',
        seed: (json['seed'] as num?)?.toInt(),
        settings:
            (json['einstellungen'] as Map?)?.cast<String, Object?>() ??
                const {},
        pipeline: [
          for (final s in (json['nachbearbeitung'] as List?) ?? const [])
            if (s is String) s,
        ],
        sourceImages: [
          for (final s in (json['eingabebilder'] as List?) ?? const [])
            if (s is String) s,
        ],
        appVersion: (json['appFassung'] as String?) ?? '',
        checksum: (json['pruefsummeSha256'] as String?) ?? '',
      );
}

/// Die Fassung des Protokollformats.
///
/// Steht in jeder Datei, damit ein Leser weiß, womit er es zu tun hat.
/// Wird beim nächsten Feld erhöht, das die Bedeutung eines bestehenden
/// ändert – nicht bei jedem neuen Feld.
const int sidecarVersion = 1;

/// Die Prüfsumme einer Werkdatei.
String assetChecksum(Uint8List bytes) => sha256.convert(bytes).toString();
