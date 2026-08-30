/// Vorlagen für die Prompt-KI – zugeschnitten auf das gewählte
/// Bild-Modell.
///
/// Die Bild-Modelle unterscheiden sich grundlegend darin, wie sie
/// einen Prompt lesen: GPT-Image und Gemini sind sprachverstehend und
/// befolgen ein gegliedertes Briefing mit Anweisungen und
/// Verneinungen. Stable Diffusion (Stability, eigene GPU) hat kein
/// Sprachverständnis, sondern gewichtet Stichworte – dort schadet
/// genau dieselbe Gliederung.
///
/// Wer den Prompt von einer Prompt-KI schreiben lässt, muss ihr das
/// mitteilen. Diese Datei liefert je Modell den passenden Auftrag zum
/// Kopieren.
library;

import '../models/models.dart';

/// Wie ein Modell seinen Prompt liest.
enum PromptStyle {
  /// Sprachverstehende Modelle (GPT-Image, Gemini): ein gegliedertes
  /// Briefing mit Anweisungen, Verneinungen wirken.
  briefing,

  /// Diffusions-Modelle (Stable Diffusion, SDXL, FLUX): eine dichte,
  /// gewichtete Stichwortkette, Verneinungen gehören in den
  /// Negativ-Prompt.
  keywords,
}

/// Alles, was die Oberfläche über die Prompt-Art eines Modells
/// wissen muss.
class PromptProfile {
  const PromptProfile({
    required this.style,
    required this.modelLabel,
    required this.briefing,
    required this.summary,
    this.negativeExample = '',
    this.maxWords = 0,
  });

  final PromptStyle style;

  /// Anbieter und Modell im Klartext, z. B. „Google Gemini · Nano
  /// Banana Pro".
  final String modelLabel;

  /// Der komplette Auftrag für die Prompt-KI zum Kopieren.
  final String briefing;

  /// Ein Satz für die Oberfläche, worauf es bei diesem Modell ankommt.
  final String summary;

  /// Vorschlag für den Negativ-Prompt – leer, wenn das Modell keinen
  /// auswertet.
  final String negativeExample;

  /// Empfohlene Höchstlänge in Wörtern (0 = keine sinnvolle Grenze).
  final int maxWords;

  bool get wantsNegativePrompt => negativeExample.isNotEmpty;
}

const _briefingRules = '''
- Schreibe einen zusammenhängenden, gegliederten Auftrag in ganzen
  Sätzen. Das Modell versteht Sprache und befolgt Anweisungen.
- Gliedere in Abschnitte mit Überschriften: MOTIV, AUFBAU, STIL,
  KAMERA, LICHT, HINTERGRUND, AUSGABE.
- Verneinungen sind erlaubt und wirken („kein Text im Bild", „keine
  zweite Figur").
- Nenne Maße, Proportionen und Farben so genau wie möglich; das
  Modell hält sich daran.
- Sprache: Englisch bringt hier meist etwas bessere Ergebnisse,
  Deutsch funktioniert aber ebenfalls.''';

const _keywordRules = '''
- Schreibe KEIN gegliedertes Briefing mit Überschriften. Das Modell
  versteht keine Sprache, es gewichtet Stichworte.
- Ergebnis ist eine einzige, dichte Kette aus Stichworten und kurzen
  Wortgruppen, durch Kommas getrennt, auf Englisch.
- Reihenfolge ist Gewichtung: Motiv und Bauform zuerst, dann Material
  und Farben, dann Stil und Technik, zuletzt Kamera, Licht und
  Hintergrund.
- KEINE Verneinungen im Prompt. „no text", „ohne Schrift" liest das
  Modell als „text", „Schrift" und holt sie eher ins Bild. Alles
  Unerwünschte kommt in einen zweiten Block.
- Keine Sätze, keine Anweisungen wie „stelle sicher, dass …", keine
  Überschriften, keine Aufzählungszeichen.
- Gib das Ergebnis in genau zwei Blöcken aus:

  PROMPT: <die Stichwortkette>
  NEGATIV: <unerwünschte Stichworte, ebenfalls durch Kommas>''';

/// Zusatzregeln je Modell – das, was nur dort gilt.
String _modelRules(GenProvider provider, String model) {
  final id = model.toLowerCase();
  return switch (provider) {
    GenProvider.openai => id.contains('mini')
        ? '- Dieses Modell ist das sparsame: Halte den Auftrag knapp '
            'und konkret, drei bis fünf Abschnitte reichen.\n'
            '- Schrift im Bild gelingt nur bei kurzen Wörtern.'
        : '- Dieses Modell setzt auch Schrift im Bild zuverlässig um: '
            'Gewünschte Wörter in Anführungszeichen und in Großschreibung '
            'angeben.\n'
            '- Es hält sich sehr genau an Mengenangaben („genau drei '
            'Objekte") und an Bildaufteilung.',
    GenProvider.gemini => id.contains('pro')
        ? '- Nano Banana Pro kann 2K und 4K: Nenne im Abschnitt AUSGABE '
            'die gewünschte Auflösung und dass Kanten scharf bleiben '
            'sollen.\n'
            '- Es ist stark im Zusammenspiel mehrerer Referenzbilder – '
            'wenn welche vorliegen, beschreibe, was aus welchem Bild '
            'übernommen wird.'
        : '- Nano Banana ist der Allrounder für Referenzbilder: Wenn '
            'welche vorliegen, beschreibe genau, was aus ihnen '
            'übernommen wird (Gesicht, Kleidung, Farbe, Stil).\n'
            '- Bei Figuren lohnt sich ein Satz zur Blickrichtung und zur '
            'Pose.',
    GenProvider.stability => id.contains('ultra')
        ? '- Stability Ultra verträgt lange Stichwortketten (bis etwa '
            '120 Wörter) und liefert die feinsten Details.'
        : id.contains('sd3')
            ? '- SD 3.5 versteht auch kurze Wortgruppen in halbwegs '
                'natürlicher Sprache und schreibt Text im Bild lesbar; '
                'gewünschte Wörter in Anführungszeichen setzen.'
            : '- Stability Core mag kurze, klare Ketten (etwa 40–60 '
                'Wörter) und arbeitet zusätzlich mit Style-Presets, die '
                'in der App gewählt werden – Stilworte im Prompt können '
                'dann entfallen.',
    GenProvider.selfhost => switch (id) {
        'sdxl-turbo' => '- SDXL Turbo arbeitet mit 4 Schritten und ohne '
            'Guidance: Es wertet den NEGATIV-Block NICHT aus und hält '
            'sich nur grob an den Prompt. Halte die Kette kurz (höchstens '
            '40 Wörter) und beschränke dich auf das Wichtigste.',
        'sd15' => '- SD 1.5 ist das älteste Modell hier: Kurze Kette '
            '(höchstens 50 Wörter), einfache Motive, keine komplizierten '
            'Proportions- oder Posenangaben – die setzt es nicht um.',
        'sdxl' => '- SDXL Base folgt der Kette genau und wertet den '
            'NEGATIV-Block aus. Bis etwa 100 Wörter sind sinnvoll; '
            'Qualitätsworte am Ende („highly detailed, sharp focus, '
            'studio lighting") helfen.',
        'sd35-medium' => '- SD 3.5 Medium versteht auch kurze Wortgruppen '
            'in natürlicher Sprache und schreibt Text im Bild lesbar; '
            'gewünschte Wörter in Anführungszeichen setzen.',
        'flux-schnell' => '- FLUX.1 schnell liest den Prompt am '
            'genauesten und verträgt auch beschreibende Wortgruppen, '
            'wertet aber den NEGATIV-Block NICHT aus – alles Unerwünschte '
            'muss durch positive Formulierungen ersetzt werden („leerer '
            'grauer Hintergrund" statt „keine Requisiten").',
        _ => '- Stable Diffusion auf der eigenen GPU: kurze, dichte '
            'Kette, keine Verneinungen im Prompt.',
      },
  };
}

/// Modell-Label im Klartext für die Kopfzeile des Auftrags.
String _label(GenProvider provider, String model) {
  for (final option in staticModelOptions(provider)) {
    if (option.$1 == model) return '${provider.label} · ${option.$2}';
  }
  return '${provider.label} · $model';
}

/// Empfohlene Höchstlänge in Wörtern – 0, wenn es keine sinnvolle
/// Grenze gibt (sprachverstehende Modelle).
int _maxWords(GenProvider provider, String model) {
  final id = model.toLowerCase();
  return switch (provider) {
    GenProvider.openai || GenProvider.gemini => 0,
    GenProvider.stability => id.contains('ultra')
        ? 120
        : id.contains('sd3')
            ? 90
            : 60,
    GenProvider.selfhost => switch (id) {
        'sdxl-turbo' => 40,
        'sd15' => 50,
        'sdxl' => 100,
        'sd35-medium' => 120,
        'flux-schnell' => 120,
        _ => 60,
      },
  };
}

/// Passt ein Modell Verneinungen im Negativ-Prompt aus?
bool _hasNegative(GenProvider provider, String model) {
  final id = model.toLowerCase();
  if (provider == GenProvider.stability) return true;
  if (provider == GenProvider.selfhost) {
    return id != 'sdxl-turbo' && id != 'flux-schnell';
  }
  return false;
}

/// Der Auftrag für die Prompt-KI, passend zum gewählten Modell.
PromptProfile promptProfileFor(GenProvider provider, String model,
    {int referenceCount = 0}) {
  final keywords =
      provider == GenProvider.stability || provider == GenProvider.selfhost;
  final label = _label(provider, model);
  final limit = _maxWords(provider, model);
  final negative = _hasNegative(provider, model);

  final references = referenceCount > 0
      ? '\n- Es liegen $referenceCount Referenzbild(er) vor. '
          '${provider.supportsReferences ? 'Beschreibe, was daraus '
              'übernommen werden soll.' : 'Dieses Modell wertet '
              'Referenzbilder allerdings nicht aus – beschreibe die '
              'Vorlage stattdessen in Worten.'}'
      : '';

  final briefing = keywords
      ? 'Du schreibst einen Bild-Prompt für $label. '
          'Das ist ein Diffusions-Modell ohne Sprachverständnis. '
          'Halte dich genau an diese Regeln:\n'
          '$_keywordRules\n'
          '${_modelRules(provider, model)}\n'
          '- Höchstlänge des PROMPT-Blocks: etwa $limit Wörter.'
          '${negative ? '' : '\n- Dieses Modell wertet den NEGATIV-Block '
              'nicht aus. Gib ihn trotzdem aus, aber formuliere das '
              'Wichtige positiv im PROMPT-Block.'}'
          '$references\n\n'
          'Meine Vorgaben:\n'
          '- Motiv: [HIER BESCHREIBEN]\n'
          '- Stil: [HIER STIL]\n'
          '- Wichtige Details: [HIER DETAILS]\n'
          '- Soll nicht im Bild sein: [HIER UNERWÜNSCHTES]'
      : 'Du schreibst einen Bild-Prompt für $label. '
          'Das Modell versteht Sprache und befolgt Anweisungen. '
          'Halte dich an diese Regeln:\n'
          '$_briefingRules\n'
          '${_modelRules(provider, model)}'
          '$references\n\n'
          'Gib ausschließlich den fertigen Prompt aus – keine '
          'Erklärungen, keine Code-Blöcke.\n\n'
          'Meine Vorgaben:\n'
          '- Motiv: [HIER BESCHREIBEN]\n'
          '- Stil: [HIER STIL]\n'
          '- Wichtige Details: [HIER DETAILS]\n'
          '- Soll nicht im Bild sein: [HIER UNERWÜNSCHTES]';

  final summary = keywords
      ? 'Dichte Stichwortkette auf Englisch, Wichtigstes zuerst, '
          'keine Verneinungen im Prompt'
          '${negative ? ' – die kommen in den Negativ-Prompt.' : '; dieses '
              'Modell kennt keinen Negativ-Prompt.'}'
          ' Etwa $limit Wörter.'
      : 'Gegliedertes Briefing in ganzen Sätzen; Verneinungen und '
          'genaue Vorgaben wirken. Länge nach Bedarf.';

  return PromptProfile(
    style: keywords ? PromptStyle.keywords : PromptStyle.briefing,
    modelLabel: label,
    briefing: briefing,
    summary: summary,
    negativeExample:
        negative ? 'text, watermark, logo, ui, labels, blurry, extra '
            'limbs, deformed, low quality' : '',
    maxWords: limit,
  );
}
