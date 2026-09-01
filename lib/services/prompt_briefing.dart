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
import 'view_direction.dart';

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

/// Wie ein Modell mit dem Negativ-Prompt umgeht. Danach richtet sich,
/// was mit einer Zeile „NEGATIV:" aus dem Massenprompt passiert.
enum NegativeHandling {
  /// Eigenes Feld in der Anfrage – Stability und die eigene GPU,
  /// solange sie mit Guidance arbeiten.
  separateField,

  /// Kein eigenes Feld, aber das Modell versteht Sprache: Der
  /// Negativ-Prompt wird als Satz an den Prompt gehängt und wirkt
  /// dadurch trotzdem (GPT-Image, Gemini).
  inPrompt,

  /// Wird gar nicht ausgewertet: SDXL Turbo und FLUX schnell arbeiten
  /// ohne Guidance, ein Negativ-Prompt verpufft dort.
  ignored,
}

/// Alles, was die Oberfläche über die Prompt-Art eines Modells
/// wissen muss.
class PromptProfile {
  const PromptProfile({
    required this.style,
    required this.modelLabel,
    required this.briefing,
    required this.summary,
    required this.negativeHandling,
    this.negativeExample = '',
    this.maxWords = 0,
  });

  final PromptStyle style;

  /// Was mit einem Negativ-Prompt geschieht – eigenes Feld, in den
  /// Prompt eingewoben oder verworfen.
  final NegativeHandling negativeHandling;

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

  /// Ob es sich überhaupt lohnt, einen Negativ-Prompt anzugeben.
  bool get wantsNegativePrompt =>
      negativeHandling != NegativeHandling.ignored;

  /// Ein Satz für die Oberfläche und die Vorlagen: was mit „NEGATIV:"
  /// bei diesem Modell geschieht.
  String get negativeNote => switch (negativeHandling) {
        NegativeHandling.separateField =>
          'Der Negativ-Prompt geht als eigenes Feld an das Modell und '
              'wirkt unmittelbar.',
        NegativeHandling.inPrompt =>
          'Dieses Modell hat kein Negativ-Feld, versteht aber Sprache: '
              'Der Negativ-Prompt wird als Satz „Do not include in the '
              'image: …" an den Prompt gehängt und wirkt dadurch.',
        NegativeHandling.ignored =>
          'Dieses Modell arbeitet ohne Guidance und wertet den '
              'Negativ-Prompt nicht aus – Unerwünschtes muss positiv '
              'formuliert im Prompt stehen.',
      };
}

/// Setzt den Negativ-Prompt so ein, wie das gewählte Modell ihn
/// versteht. Ergebnis ist der fertige Prompt und der Wert für das
/// Negativ-Feld der Anfrage.
///
/// Damit wirkt eine Zeile „NEGATIV:" aus dem Massenprompt auch bei
/// GPT-Image und Gemini, die gar kein Negativ-Feld kennen.
({String prompt, String negativePrompt}) applyNegativePrompt(
  String prompt,
  String negative,
  NegativeHandling handling,
) {
  final cleaned = negative.trim().replaceAll(RegExp(r'[.,;\s]+$'), '');
  if (cleaned.isEmpty) return (prompt: prompt, negativePrompt: '');
  if (handling != NegativeHandling.inPrompt) {
    return (prompt: prompt, negativePrompt: cleaned);
  }
  return (
    prompt: '${prompt.trimRight()}\n\n'
        'Do not include in the image: $cleaned.',
    negativePrompt: cleaned,
  );
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
            'NEGATIV-Block aus. Unter 60 Wörter bleiben, und das Motiv '
            'in die ersten 15: Das Modell gewichtet nach Position und '
            'Menge, ein langer Stil-Teil überstimmt sonst das '
            'Hauptmotiv.',
        'sd35-medium' => '- SD 3.5 Medium versteht auch kurze Wortgruppen '
            'in natürlicher Sprache und schreibt Text im Bild lesbar; '
            'gewünschte Wörter in Anführungszeichen setzen.',
        'sd35-medium-lean' => '- SD 3.5 Medium (sparsam) läuft ohne den '
            'T5-Text-Encoder. Kurze, dichte Ketten versteht es wie das '
            'volle Modell; lange, verschachtelte Sätze NICHT – die in '
            'knappe Wortgruppen zerlegen. Text im Bild gelingt nur noch '
            'grob.',
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
    // Die Grenzen sind Erfahrungswerte, keine harten Abbrüche: Ein
    // CLIP-Block fasst 75 Tokens, also rund 60 Wörter. Der Server
    // reicht zwar mehr durch, aber jenseits davon verwässert das
    // Motiv – ein 97-Wörter-Prompt mit 12 Motivwörtern kam als
    // Lehmkuppel zurück statt als Bäckerei.
    GenProvider.selfhost => switch (id) {
        'sdxl-turbo' => 40,
        'sd15' => 50,
        'sdxl' => 60,
        'sd35-medium' => 120,
        // Ohne T5 zählt wieder die CLIP-Grenze: rund 60 Wörter.
        'sd35-medium-lean' => 60,
        'flux-schnell' => 120,
        _ => 60,
      },
  };
}

/// Wie das Modell mit einem Negativ-Prompt umgeht.
NegativeHandling negativeHandlingFor(GenProvider provider, String model) {
  final id = model.toLowerCase();
  if (provider == GenProvider.stability) {
    return NegativeHandling.separateField;
  }
  if (provider == GenProvider.selfhost) {
    // Turbo und FLUX schnell laufen mit Guidance 1 – dabei bleibt das
    // Negativ-Feld ohne Wirkung.
    return id == 'sdxl-turbo' || id == 'flux-schnell'
        ? NegativeHandling.ignored
        : NegativeHandling.separateField;
  }
  // GPT-Image und Gemini kennen kein Negativ-Feld, verstehen aber
  // Verneinungen im Text.
  return NegativeHandling.inPrompt;
}

/// Der Auftrag für die Prompt-KI, passend zum gewählten Modell.
PromptProfile promptProfileFor(GenProvider provider, String model,
    {int referenceCount = 0,
    ViewDirection direction = freeDirection}) {
  final keywords =
      provider == GenProvider.stability || provider == GenProvider.selfhost;
  final label = _label(provider, model);
  final limit = _maxWords(provider, model);
  final handling = negativeHandlingFor(provider, model);
  final negative = handling == NegativeHandling.separateField;

  final negativeNote = switch (handling) {
    NegativeHandling.separateField =>
      'Alles Unerwünschte gehört in einen eigenen NEGATIV-Block.',
    NegativeHandling.inPrompt =>
      'Dieses Modell hat kein Negativ-Feld. Schreibe Unerwünschtes '
          'als Satz in den Prompt („Do not include in the image: …") – '
          'so wirkt es.',
    NegativeHandling.ignored =>
      'Dieses Modell wertet einen Negativ-Prompt nicht aus.',
  };

  final references = referenceCount > 0
      ? '\n- Es liegen $referenceCount Referenzbild(er) vor. '
          '${provider.supportsReferences ? 'Beschreibe, was daraus '
              'übernommen werden soll.' : 'Dieses Modell wertet '
              'Referenzbilder allerdings nicht aus – beschreibe die '
              'Vorlage stattdessen in Worten.'}'
      : '';

  final style = keywords ? PromptStyle.keywords : PromptStyle.briefing;
  // Die Blickrichtung gehört in jede Vorlage – sie ist die Angabe,
  // die am häufigsten fehlt und sich hinterher nicht reparieren lässt.
  final kamera = '\n\n${viewDirectionBriefing(direction, style, handling, label)}';
  // Die Spielgrafik-Regeln hängen an der isometrischen Ansicht: Wer
  // ein Gebäude-Asset für eine Karte baut, wählt genau die.
  final assets = direction.extraRules == 'spielgrafik'
      ? '\n\n${gameAssetBriefing(style)}'
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
          '$references$kamera$assets\n\n'
          'Meine Vorgaben:\n'
          '- Motiv: [HIER BESCHREIBEN]\n'
          '- Stil: [HIER STIL]\n'
          '- Wichtige Details: [HIER DETAILS]\n'
          '- Soll nicht im Bild sein: [HIER UNERWÜNSCHTES]'
      : 'Du schreibst einen Bild-Prompt für $label. '
          'Das Modell versteht Sprache und befolgt Anweisungen. '
          'Halte dich an diese Regeln:\n'
          '$_briefingRules\n'
          '${_modelRules(provider, model)}\n'
          '- Negativ-Prompt: $negativeNote'
          '$references$kamera$assets\n\n'
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
    style: style,
    modelLabel: label,
    briefing: briefing,
    summary: summary,
    negativeHandling: handling,
    negativeExample: handling == NegativeHandling.ignored
        ? ''
        : 'text, watermark, logo, ui, labels, blurry, extra limbs, '
            'deformed, low quality',
    maxWords: limit,
  );
}

// ----------------------------------------------------------------
// Spielgrafik: Gebäude-Assets für eine Karte
// ----------------------------------------------------------------

/// Warum die Spielgrafik-Regeln nötig sind – dieselbe Begründung, die
/// auch in der Vorlage für die Prompt-KI steht.
const String gameAssetReason =
    'Diese Bilder werden als Spiel-Asset verwendet: Jedes Bild ist '
    'genau ein Gebäude, das auf einen Karten-Knoten gesetzt wird. Der '
    'Renderer malt den festgetretenen Erdsaum selbst um das Gebäude – '
    'ein mitgemalter Boden (Grasfleck, Erdfleck, Platte) läge darüber '
    'und hinterließe beim Freistellen eine harte Kante. Die '
    'Bodenebene ist auf 0,62 verkürzt (ROWH 32 auf TILE 52), das '
    'entspricht einem Blick von etwa 35° von oben: Die Dachfläche '
    'füllt dann rund ein Drittel des Bildes. Ein zu flach gesehenes '
    'Haus kippt neben dem Gelände und lässt sich nachträglich nicht '
    'reparieren. Und das Bild wird rund 13-fach verkleinert (eine '
    'Bäckerei ist im Spiel nur etwa 78 Weltpixel hoch), deshalb '
    'zerfällt kleinteiliges Mauerwerk zu Rauschen.';

/// Die Sätze, die genau so in jeden Prompt eines sprachverstehenden
/// Modells gehören.
const List<String> gameAssetSentences = [
  'Exactly one single building in the image, nothing else beside it.',
  'The building stands on nothing: plain grey background all around '
      'and underneath it — no grass, no soil, no moss, no dirt patch, '
      'no terrain, no base, no plate, no terrace, no paving, no low '
      'wall, no fence, no steps, no platform of any kind.',
  'Camera elevation 35 degrees above the horizon, clearly looking '
      'down onto the roof: the roof surface takes up about a third of '
      'the image, the facade noticeably less than half.',
  'Name the one feature that identifies the building type early and '
      'literally — for a bakery a large domed bread oven attached to '
      'the side wall. It has to be visible as that feature; a chimney '
      'alone does not read as an oven.',
  'Coarse masonry: large, softly shaped stone blocks, at most about '
      '15 courses over the height of a wall — no fine stone mosaic, '
      'the image is downscaled about 13 times in the game.',
];

/// Der feste Stil-Schwanz für Diffusions-Modelle – bewusst **kurz**
/// und in dieser Reihenfolge erprobt.
///
/// Die erste Fassung war 47 Wörter lang und hat das Motiv ertränkt:
/// Bei 12 Motivwörtern blieben nur 20 % des Prompts für das Gebäude
/// übrig, und heraus kamen runde Lehmkuppeln statt einer Bäckerei.
/// SDXL gewichtet nach Position und Menge – der Stil darf das Motiv
/// nicht überstimmen.
///
/// Drei Formulierungen sind ausdrücklich **nicht** dabei:
///
/// * Mengenangaben („at most 15 stone courses") – das Modell zählt
///   nicht, es sieht „stone courses" und macht mehr Stein.
/// * Gradzahlen („camera elevation 35 degrees") – kein Winkelbegriff.
/// * „rounded boulders" – zog ins Gegenteil und machte aus dem groben
///   Mauerwerk Gebäude aus Findlingen.
///
/// Und zwei Dinge sind nach dem zweiten Bäckerei-Bild geändert:
///
/// * **Die Kamera braucht drei Angaben statt einer.** „high angle
///   isometric view" allein blieb zu flach – zu sehen war fast die
///   volle Fassade und vom Dach nur ein Streifen. Jetzt steht die
///   Blickrichtung dreifach da: von hoch oben, auf das Dach herab,
///   gekippte Draufsicht.
/// * **Kein „ground" mehr im positiven Teil.** „centered on empty
///   ground" hat den Bodenfleck zurückgeholt: Das Modell malt, was
///   dasteht, und „ground" steht da. Die Vereinzelung trägt jetzt
///   „single isolated 3d building model", der Boden gehört
///   ausschließlich in den Negativ-Prompt.
const String gameAssetKeywords =
    'single isolated 3d building model, isometric view from high '
    'above, looking down onto the roof, tilted top view, stylized '
    'game asset, chunky rounded shapes, warm matte colors, soft '
    'golden hour light, plain grey background';

/// Was bei Spielgrafiken in den Negativ-Prompt gehört.
///
/// Die Reihenfolge ist nicht beliebig: Die Bodenbegriffe stehen
/// vorn, weil sie zweimal zurückgekommen sind – erst als Teller,
/// dann als ausgefranster Gras- und Erdfleck. „diorama" und
/// „miniature scene" sind aus dem positiven Teil hierher gewandert;
/// beide bringen die Bodenplatte gleich mit.
const String gameAssetNegativeTerms =
    'grass patch, dirt patch, soil, moss, ground plate, base, disc, '
    'platter, pedestal, platform, terrain, island, diorama, '
    'miniature scene, fence, garden, village, many houses, second '
    'building, street, path, trees, bushes, terrace, paving, low '
    'wall, steps, onion dome, blue-grey slate, glossy, harsh '
    'shadows, front view, side view, eye level, low camera angle, '
    'text, watermark, people, blurry, low quality';

/// Der erprobte Block, an dem sich die Aufteilung ablesen lässt:
/// 19 Wörter Motiv voran, dann der feste Stil-Schwanz – zusammen 53
/// Wörter.
const String gameAssetExample =
    'NAME: bld-02-bakery\n'
    'PROMPT: medieval bakery, large domed bread oven attached to the '
    'side wall, timber framed plaster walls, thatched roof, stone '
    'chimney, $gameAssetKeywords\n'
    'NEGATIV: $gameAssetNegativeTerms';

/// Wie viele Wörter am Anfang dem Motiv gehören.
///
/// Von 15 auf 20 erhöht: Das erkennende Merkmal muss ausgeschrieben
/// dastehen („large domed bread oven attached to the side wall"),
/// sonst wird daraus ein zweiter Schornstein. In 15 Wörtern ist
/// dafür kein Platz.
const int gameAssetLeadWords = 20;

/// Was an der Farbwelt schon stimmt und erhalten bleiben soll.
const String gameAssetKeep =
    'Beibehalten: warme Farbwelt, kein blaugrauer Schiefer, matte '
    'Materialien, weiches Licht, gerundete Kanten, Fachwerk und '
    'Reetdach.';

/// Der Spielgrafik-Abschnitt für die Vorlage der Prompt-KI, passend
/// zur Prompt-Art des Modells.
String gameAssetBriefing(PromptStyle style) {
  if (style == PromptStyle.keywords) {
    return 'Spielgrafik (Gebäude-Asset):\n'
        '$gameAssetReason\n'
        '- Aufbau jedes PROMPT: erst das MOTIV in etwa '
        '$gameAssetLeadWords Wörtern, dann wörtlich der feste '
        'Stil-Schwanz. Zusammen unter 60 Wörter. Diffusions-Modelle '
        'gewichten nach Position und Menge – ein langer Stil-Teil '
        'überstimmt sonst das Gebäude.\n'
        '- Das Motiv nennt zuerst die Gebäudeart, dann sofort das '
        'erkennende Merkmal ausgeschrieben und mit Ort am Bau (bei '
        'einer Bäckerei: „large domed bread oven attached to the side '
        'wall"), danach Wände, Dach und ein bis zwei Requisiten. '
        'Nicht mehr. Ein knapp genanntes Merkmal geht unter – aus '
        '„big domed stone oven" wurden zwei Schornsteine.\n'
        '- Danach immer genau diese Kette, unverändert:\n'
        '  $gameAssetKeywords\n'
        '- Und immer genau diese Zeile „NEGATIV:":\n'
        '  $gameAssetNegativeTerms\n'
        '- KEIN Wort über den Boden im PROMPT – auch kein '
        '„centered on empty ground", kein „standing on grass", kein '
        '„on the ground". Das Modell malt, was dasteht: Genau so kam '
        'der Gras- und Erdfleck zurück. Der Boden gehört '
        'ausschließlich in den NEGATIV-Block, die Vereinzelung trägt '
        '„single isolated 3d building model".\n'
        '- Der Blickwinkel braucht alle drei Angaben aus der Kette '
        '(„isometric view from high above", „looking down onto the '
        'roof", „tilted top view"). „high angle isometric view" '
        'allein blieb zu flach: fast die volle Fassade, vom Dach nur '
        'ein Streifen. Richtig sitzt es, wenn die Dachfläche rund ein '
        'Drittel des Bildes einnimmt.\n'
        '- KEIN „diorama" und kein „miniature scene" im PROMPT. Beide '
        'bringen die Bodenplatte mit; sie stehen jetzt im NEGATIV.\n'
        '- KEINE Mengenangaben („at most 15 stone courses", „three '
        'windows"). Das Modell zählt nicht; es sieht nur „stone '
        'courses" und macht mehr Stein.\n'
        '- KEINE Gradzahlen („camera elevation 35 degrees"). Als '
        'Winkel versteht es das nicht – dafür steht die Kamera-Kette '
        'in der Kette.\n'
        '- KEIN „boulders" oder „rounded boulders". Gemeint war grobes '
        'Mauerwerk, angekommen ist „Gebäude aus Findlingen" – runde '
        'Lehmkuppeln ohne Dach.\n'
        '- $gameAssetKeep\n\n'
        'So sieht ein fertiger Block aus ($gameAssetLeadWords Wörter '
        'Motiv, dann die Kette – zusammen 53 Wörter):\n\n'
        '$gameAssetExample';
  }
  return 'Spielgrafik (Gebäude-Asset):\n'
      '$gameAssetReason\n'
      '- Nimm diese ${gameAssetSentences.length} Sätze wörtlich in '
      'jeden PROMPT auf:\n'
      '${gameAssetSentences.map((s) => '  $s').join('\n')}\n'
      '- $gameAssetKeep';
}
