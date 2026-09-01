/// Die Blickrichtung als eigener Baustein jeder Prompt-Vorlage.
///
/// Warum eigens: Die Kamera ist die Angabe, die am häufigsten fehlt
/// und am teuersten nachzubessern ist. Ein Gebäude, das zu flach
/// gesehen wurde, kippt neben dem Gelände; eine Figur im Profil taugt
/// nicht als Vorderansicht für die 3D-Pipeline. Beides lässt sich
/// nachträglich nicht reparieren – der Lauf ist verloren.
///
/// Vorher stand die Kamera nur im Spielgrafik-Block, und den gab es
/// nur über einen Schalter. Jetzt gehört sie zu jeder Vorlage, und
/// zwar in der Sprache, die das gewählte Modell versteht:
///
/// * **Sprachverstehende Modelle** (GPT-Image, Gemini) bekommen einen
///   Satz und dürfen Verneinungen lesen.
/// * **Diffusions-Modelle** bekommen Stichworte, und die
///   unerwünschten Blickwinkel wandern in den Negativ-Block.
/// * **Modelle ohne Guidance** (SDXL Turbo, FLUX schnell) werten
///   keinen Negativ-Block aus – dort muss die Blickrichtung im
///   positiven Teil kräftiger dastehen.
library;

import 'prompt_briefing.dart';

/// Eine Blickrichtung mit allem, was sie in einem Prompt braucht.
class ViewDirection {
  const ViewDirection({
    required this.id,
    required this.label,
    required this.hint,
    required this.sentence,
    required this.keywords,
    this.negativeTerms = '',
    this.extraRules = '',
  });

  /// Kennung, wie sie in den Einstellungen steht.
  final String id;

  /// Was in der Auswahlliste steht.
  final String label;

  /// Wofür diese Richtung taugt – eine Zeile unter der Auswahl.
  final String hint;

  /// Der Satz für sprachverstehende Modelle.
  final String sentence;

  /// Die Stichworte für Diffusions-Modelle, in der Reihenfolge, in
  /// der sie in die Kette gehören.
  final String keywords;

  /// Die Blickwinkel, die dabei nicht herauskommen sollen. Sie
  /// gehören in den Negativ-Block – bei Modellen ohne Negativ-Feld
  /// bleiben sie weg.
  final String negativeTerms;

  /// Zusatzregeln, die nur diese Richtung braucht (Spielgrafik).
  final String extraRules;

  bool get isEmpty => id == 'frei';
}

/// „Keine Vorgabe" – ausdrücklich vorhanden, damit sich die Kamera
/// auch weglassen lässt, ohne dass die Vorlage etwas behauptet.
const ViewDirection freeDirection = ViewDirection(
  id: 'frei',
  label: 'Keine Vorgabe',
  hint: 'Die Kamera bleibt offen – das Modell entscheidet.',
  sentence: '',
  keywords: '',
);

const List<ViewDirection> viewDirections = [
  freeDirection,
  ViewDirection(
    id: 'front',
    label: 'Vorderansicht (frontal)',
    hint: 'Für Figuren, die später ein 3D-Modell werden: Der Vorderblick '
        'ist die Ansicht, aus der die Pipeline rechnet.',
    sentence: 'Camera exactly at the front, at eye level with the '
        'subject, looking straight at it: the subject faces the viewer '
        'head-on, both sides equally visible, no rotation to either '
        'side and no tilt.',
    keywords: 'front view, facing the viewer, straight-on camera, '
        'centered, symmetrical',
    negativeTerms: 'three quarter view, side view, profile, back view, '
        'from above, from below, tilted camera, dutch angle',
  ),
  ViewDirection(
    id: 'threequarter',
    label: 'Dreiviertelansicht (¾)',
    hint: 'Der übliche Blick auf Charaktere und Objekte: zeigt Front '
        'und Seite zugleich, wirkt räumlich.',
    sentence: 'Camera at a three quarter angle, about 35 degrees to '
        'the side and slightly above eye level: front and one side are '
        'visible at the same time, the subject reads as a solid body.',
    keywords: 'three quarter view, slightly turned to the side, '
        'slightly above eye level',
    negativeTerms: 'flat front view, profile, back view, top down, '
        'extreme perspective',
  ),
  ViewDirection(
    id: 'side',
    label: 'Seitenansicht (Profil)',
    hint: 'Reines Profil – für Referenzblätter und Silhouetten.',
    sentence: 'Camera exactly at the side, at eye level: a clean '
        'profile, the subject looks to the left, no rotation towards '
        'the viewer.',
    keywords: 'side view, profile, orthographic side, flat silhouette',
    negativeTerms: 'front view, three quarter view, back view, from '
        'above, perspective distortion',
  ),
  ViewDirection(
    id: 'back',
    label: 'Rückansicht',
    hint: 'Für die Rückseite einer Figur – Teil eines vollständigen '
        'Referenzblatts.',
    sentence: 'Camera exactly behind the subject, at eye level: only '
        'the back is visible, the face is turned away.',
    keywords: 'back view, seen from behind, facing away',
    negativeTerms: 'front view, face visible, three quarter view, '
        'profile',
  ),
  ViewDirection(
    id: 'iso35',
    label: 'Spielgrafik: isometrisch, 35° von oben',
    hint: 'Für Gebäude-Assets auf einer Karte. Bringt die vollständigen '
        'Spielgrafik-Regeln mit: genau ein Gebäude, kein Boden, grobes '
        'Mauerwerk.',
    sentence: 'Camera elevation 35 degrees above the horizon, clearly '
        'looking down onto the roof: the roof surface takes up about a '
        'third of the image, the facade noticeably less than half.',
    keywords: 'isometric view from high above, looking down onto the '
        'roof, tilted top view',
    negativeTerms: 'front view, side view, eye level, low camera angle',
    extraRules: 'spielgrafik',
  ),
  ViewDirection(
    id: 'top',
    label: 'Draufsicht (senkrecht von oben)',
    hint: 'Für Karten, Grundrisse und Kacheln: die Kamera steht genau '
        'senkrecht.',
    sentence: 'Camera directly overhead, pointing straight down: a '
        'true top-down view with no perspective, no side walls visible.',
    keywords: 'top down view, directly overhead, orthographic, flat lay',
    negativeTerms: 'perspective, side walls visible, horizon, eye '
        'level, isometric',
  ),
  ViewDirection(
    id: 'eye',
    label: 'Augenhöhe (Szene)',
    hint: 'Der neutrale Blick für Szenen und Illustrationen.',
    sentence: 'Camera at eye level, horizon in the middle, natural '
        'perspective without tilt.',
    keywords: 'eye level, natural perspective, horizon centered',
    negativeTerms: 'top down, bird eye view, worm eye view, tilted '
        'camera, dutch angle',
  ),
  ViewDirection(
    id: 'low',
    label: 'Untersicht (von unten)',
    hint: 'Lässt das Motiv groß und mächtig wirken – für Helden und '
        'Türme.',
    sentence: 'Camera below the subject, looking up: the subject towers '
        'over the viewer, the horizon sits low in the frame.',
    keywords: 'low angle view, looking up, towering, heroic angle',
    negativeTerms: 'top down, from above, eye level, flat view',
  ),
];

/// Die Blickrichtung zu einer Kennung. Unbekannt oder leer heißt
/// „keine Vorgabe" – so kann eine alte Einstellung nichts kaputt
/// machen.
ViewDirection viewDirectionById(String id) => viewDirections.firstWhere(
      (d) => d.id == id,
      orElse: () => freeDirection,
    );

/// Was von der Blickrichtung in den Prompt gehört und was in den
/// Negativ-Block – abhängig davon, wie das gewählte Modell liest.
///
/// Drei Fälle:
///
/// * **Briefing** (GPT-Image, Gemini): ein Satz im Abschnitt KAMERA.
///   Der Negativ-Teil geht als Verneinung mit in den Prompt, denn
///   diese Modelle lesen sie.
/// * **Stichworte mit Negativ-Feld** (Stability, SDXL, SD 3.5): die
///   Stichworte in die Kette, die anderen Blickwinkel in den
///   Negativ-Block.
/// * **Stichworte ohne Negativ-Feld** (SDXL Turbo, FLUX schnell): nur
///   die Kette – dort verpufft ein Negativ-Block. Damit die Richtung
///   trotzdem sitzt, steht sie doppelt: einmal als Kette, einmal als
///   ausdrückliche Wiederholung des wichtigsten Begriffs.
({String prompt, String negative}) viewDirectionParts(
    ViewDirection direction, PromptStyle style, NegativeHandling handling) {
  if (direction.isEmpty) return (prompt: '', negative: '');
  if (style == PromptStyle.briefing) {
    return (
      prompt: direction.sentence,
      negative: direction.negativeTerms,
    );
  }
  if (handling == NegativeHandling.ignored) {
    // Ohne Negativ-Feld muss der positive Teil tragen. Der erste
    // Begriff der Kette ist der aussagekräftigste – er kommt noch
    // einmal ans Ende.
    final erste = direction.keywords.split(',').first.trim();
    return (
      prompt: erste.isEmpty
          ? direction.keywords
          : '${direction.keywords}, $erste',
      negative: '',
    );
  }
  return (prompt: direction.keywords, negative: direction.negativeTerms);
}

/// Der Abschnitt für die Vorlage der Prompt-KI: was die Blickrichtung
/// bedeutet und wie sie einzubauen ist.
String viewDirectionBriefing(ViewDirection direction, PromptStyle style,
    NegativeHandling handling, String modelLabel) {
  if (direction.isEmpty) {
    return 'Blickrichtung: keine Vorgabe. Wähle die Kamera passend zum '
        'Motiv und schreibe sie ausdrücklich in den Prompt – ohne '
        'Angabe entscheidet das Modell, und das Ergebnis lässt sich '
        'nicht wiederholen.';
  }
  final teile = viewDirectionParts(direction, style, handling);
  final kopf = 'Blickrichtung: ${direction.label}.\n${direction.hint}';
  if (style == PromptStyle.briefing) {
    return '$kopf\n'
        '- Dieser Satz gehört wörtlich in den Abschnitt KAMERA:\n'
        '  ${direction.sentence}\n'
        '- Und dieser Halbsatz an das Ende des Prompts, weil dieses '
        'Modell Verneinungen liest:\n'
        '  Not this: ${direction.negativeTerms}.';
  }
  if (handling == NegativeHandling.ignored) {
    return '$kopf\n'
        '- Diese Stichworte gehören in die Kette, direkt vor Licht und '
        'Hintergrund:\n'
        '  ${teile.prompt}\n'
        '- $modelLabel wertet den NEGATIV-Block NICHT aus. '
        'Deshalb steht der wichtigste Begriff doppelt in der Kette – '
        'nicht streichen. Andere Blickwinkel dürfen im PROMPT nicht '
        'vorkommen, auch nicht verneint.';
  }
  return '$kopf\n'
      '- Diese Stichworte gehören in die Kette, direkt vor Licht und '
      'Hintergrund:\n'
      '  ${teile.prompt}\n'
      '- Und diese in den NEGATIV-Block, damit kein anderer Blickwinkel '
      'dazwischenkommt:\n'
      '  ${teile.negative}';
}
