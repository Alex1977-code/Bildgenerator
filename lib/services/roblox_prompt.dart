import 'roblox_check.dart'
    show
        robloxAccessoryTriangles,
        robloxGoalTriangles,
        robloxMaxTexture,
        robloxCharacterStuds;
import 'item_prompt.dart' show mergeTerms;
import 'pose_prompt.dart' show tPoseSuffix;
import 'roblox_marketplace.dart' show RobloxBodyScale, marketplaceFigureStuds;
import 'roblox_spec.dart';
import 'tripo_service.dart' show TripoService;

/// Der feste Schwanz für eine Roblox-Figur.
///
/// Vier Angaben darin entscheiden über „besteht die Prüfung":
/// **ein zusammenhängender Körper**, **massive Volumen mit sichtbarer
/// Wandstärke**, **geschlossene Hülle**, **ein Mesh**. Sie standen
/// bisher nur in Ratschlägen; damit ein Prompt ohne Nachfrage richtig
/// wird, gehören sie wörtlich in die Vorlage.
const String robloxFigureTail =
    'single connected body, symmetrical, compact chunky silhouette, '
    'solid closed volumes with visible wall thickness, closed '
    'watertight shell, single mesh, smooth simple surfaces, low '
    'detail density, clean readable outline, few flat separated '
    'color areas, uniform material';

/// Dasselbe für ein Accessoire – kein Körper, kein Rig, ein Viertel
/// der Dreiecke.
const String robloxAccessoryTail =
    'single solid object, thick rounded shapes with visible wall '
    'thickness, closed watertight shell, single mesh, smooth simple '
    'surfaces, low detail density, clean readable silhouette, few '
    'flat separated color areas, uniform material';

/// Die Formworte des Accessoire-Schwanzes für einen **Bild**-Prompt.
///
/// Die kopierten Gegenstands-Prompts gehen in den Massenprompt des
/// Bild-Tabs, also an ein Bildmodell. Dem sagen „closed watertight
/// shell" und „single mesh" nichts; was es braucht, sind die Formworte
/// – die vererben sich über das Bild in die Rekonstruktion. Der
/// vollständige [robloxAccessoryTail] ist für Text→3D.
const String robloxAccessoryImageTail =
    'thick rounded shapes, smooth simple surfaces, low detail density, '
    'clean readable silhouette, few flat separated color areas, '
    'uniform material';

/// Der feste Schwanz für einen **Marktplatz-Körper**.
///
/// Ein eigener, weil hier fünf Formregeln dazukommen, an denen eine
/// Figur scheitert, die im eigenen Erlebnis tadellos läuft. Alle fünf
/// sind an Roblox' Validator gemessen, nicht der Doku entnommen:
///
/// * **Tiefe unter der absoluten Grenze.** 2,00 Studs bei Classic und
///   Slender, 2,25 bei Normal – die Testfigur hatte 2,45. Dass das bei
///   5 Studs „49 % statt 40 %" ergab, war Zufall der Größe.
/// * **Eng anliegende Shorts statt Saum.** Alles, was von der Hüfte
///   abwärts über beide Beine hängt, ragt aus dem Outer Cage des Beins
///   und reißt Deckung und LegsSeparated zugleich. Nackte Oberschenkel
///   sind keine Lösung – der Marktplatz verlangt Bedeckung von der
///   Hüfte bis unter Schritt und Gesäß.
/// * **Kräftige Beine, kein „slim".** Jedes Teil muss 50 % seines
///   Hüllkörpers füllen; höchstens 1,50 breit.
/// * **Fäustlinge statt Finger.** Ausmodellierte Finger kosteten je
///   Hand über 1.280 Dreiecke – mehr als das Budget des ganzen Arms.
/// * **Sichtbarer Hals.** Ohne Einschnürung findet Roblox' Auto Setup
///   die Grenze zwischen Kopf und Rumpf nicht: In einem echten Lauf
///   wurde die Kapuze bis zu den Schultern zum „Kopf" von 3,75 Studs
///   Breite.
///
/// Dazu zwei Dinge, die nicht die Form, sondern die Weiterverarbeitung
/// betreffen: **A-Pose statt T-Pose** – die waagerechten Arme wurden
/// dem Rumpf zugeschlagen – und **ein sichtbares Gesicht mit Lidern
/// und Lippen im Kopfnetz**. Der Marktplatz verlangt für den Kopf
/// eines Ganzkörper-Bundles einen dynamischen Kopf mit FACS-Posen, und
/// Auto Setup baut die nur, wenn es im Kopfnetz Augenhöhlen mit Lidern
/// und eine Mundhöhle mit Lippen findet. Hier stand vorher „two
/// hemisphere eyes and a mouth modelled as separate volumes" – und
/// Lauf 5 hat entschieden, dass genau das nicht reicht: Augen und
/// Zähne als eigene Netze ergeben „Cannot detect mouth open / left eye
/// close expression", egal wo sie sitzen. Bestellt wird deshalb, was
/// Auto Setup braucht, nicht, was sich nachträglich anbauen lässt.
///
/// „chunky" fehlt hier bewusst: Genau dieses Wort hat die Tiefe
/// bestellt, die jetzt abgelehnt wird.
///
/// **Nach der Doku-Prüfung vom 3. September 2026 geändert:**
///
/// * Die Tiefe ist absolut begrenzt (2,00 Studs bei Classic und
///   Slender, 2,25 bei Normal), der Prompt kennt nur Verhältnisse.
///   Der Schwanz rechnet sein Wort deshalb aus Höhe und Skala – siehe
///   [robloxMarketplaceTailFor] – und nimmt nie eines, das über der
///   Grenze liegt. Bei 5 Studs heißt das für alle drei Skalen „less
///   than two fifths of body height" (2,0): unter Normals 2,25 und
///   gerade an Classics 2,0. Eine Zwischenfassung sagte „less than
///   half" – das sind 2,5, mehr als jede Skala erlaubt.
/// * „slim straight legs narrower than one third" bestellte, was seit
///   dem 17. August 2026 durchfällt: Jedes Teil muss 50 % seines
///   Hüllkörpers füllen. Jetzt „sturdy arms and legs filling their
///   outlines".
/// * „garment hem ending at the hip bone, thighs uncovered" ließ
///   nackte Haut, wo der Marktplatz Bedeckung verlangt (Hüfte bis
///   unter Schritt und Gesäß). Jetzt eng anliegende Shorts, die der
///   Beinform folgen – kein hängender Saum, also kein Konflikt mit
///   getrennten Beinen.
/// * „head about one quarter of body height" ist neu: Die
///   Mindesthöhen (Rumpf 1,7, Bein 1,4) sind absolut, und ein Kopf
///   von 2 Studs lässt bei 5 Studs nicht genug darunter.
///
/// **Nach der ersten Figur mit diesem Schwanz geändert** (Tripo,
/// Beispielmotiv, 5.321 Dreiecke): Sie kam in A-Pose, als ein Netz,
/// mit Gesicht – und mit dem Schritt bei 0,9 Studs, Augen als Kugeln
/// 0,38 Studs aus dem Kopf, dem Hals bei 55 % der Kopfbreite.
///
/// * „two separate leg tubes from the hips down" sagte nichts über
///   die Länge; jetzt „two separate legs one third of body height
///   with a gap between the thighs". Bein 1,4 von 5 sind 28 %.
/// * „eye sockets with eyelids" wurde zu Kugeln mit Lidern; jetzt
///   „eyes sunk into sockets with eyelids". Im Negativ „bulging
///   eyes" und „short legs" – dafür „logo" und „arms out sideways"
///   raus (das deckt „T-pose").
/// * Gekürzt, damit das Motiv Platz behält: „narrow visible neck
///   between head and shoulders", Shorts ohne „following the leg
///   shape" (das sagt jetzt die Lücke zwischen den Schenkeln). Das
///   Beispielmotiv war mit 329 Zeichen über dem Budget von 285 –
///   Tripo hätte „few flat separated color areas, uniform material"
///   abgeschnitten.
const String robloxMarketplaceTail = _tailNormal5;

/// Der Schwanz für die Standardhöhe und -skala – als Konstante, weil
/// die Vorlagen ihn wörtlich zitieren.
const String _tailNormal5 =
    'arms straight and angled 45 degrees down in an A-pose, never horizontal, '
    'single connected body, symmetrical, head about one quarter of body '
    'height, body depth less than two fifths of body height, flat chest and '
    'back, narrow visible neck between head and shoulders, mitten hands '
    'without fingers, sturdy arms and legs filling their outlines, tight '
    'opaque shorts in a contrasting colour covering hips, crotch and buttocks, '
    'two separate legs one third of body height with a gap between the thighs, '
    'face fully visible, eyes sunk into sockets with eyelids and a mouth with '
    'lips shaped into the head, solid closed volumes with visible wall '
    'thickness, closed watertight shell, one single body mesh, few flat '
    'separated color areas, uniform material';

/// Das Wort für die erlaubte Tiefe: Die Grenze ist absolut, der
/// Prompt kennt nur Verhältnisse – also wird das Verhältnis aus
/// Grenze und Höhe gerechnet, und genommen wird das größte Wort, das
/// noch **unter** der Grenze bleibt. Nie eines darüber: Bei 2,25 zu 5
/// (0,45) stand hier einmal „less than half", und das bestellt 2,5.
String robloxDepthWords(double maxDepth, double studs) {
  final anteil = studs <= 0 ? 0.4 : maxDepth / studs;
  // Ein Hauch Toleranz gegen 2,0 / 6 = 0,3333…, das ein Drittel ist.
  const eps = 1e-9;
  if (anteil + eps >= 0.50) return 'less than half of body height';
  if (anteil + eps >= 0.40) return 'less than two fifths of body height';
  if (anteil + eps >= 1 / 3) return 'less than one third of body height';
  if (anteil + eps >= 0.25) return 'less than a quarter of body height';
  return 'less than a fifth of body height';
}

/// Der Bruch, den ein Wort aus [robloxDepthWords] bestellt – damit ein
/// Test nachrechnen kann, dass Wort mal Höhe nie über der Grenze liegt.
double robloxDepthFraction(String words) => switch (words) {
      'less than half of body height' => 0.50,
      'less than two fifths of body height' => 0.40,
      'less than one third of body height' => 1 / 3,
      'less than a quarter of body height' => 0.25,
      'less than a fifth of body height' => 0.20,
      _ => throw ArgumentError.value(words, 'words', 'kein Tiefenwort'),
    };

/// Der Marktplatz-Schwanz für eine Höhe und eine Skala.
///
/// Bei 5 Studs und Normal ist das wörtlich [robloxMarketplaceTail].
String robloxMarketplaceTailFor(
    {double studs = marketplaceFigureStuds,
    RobloxBodyScale scale = RobloxBodyScale.normal}) {
  final wort = robloxDepthWords(scale.maxDepth, studs);
  return _tailNormal5.replaceFirst(
      'body depth less than two fifths of body height', 'body depth $wort');
}

/// Ein Stück des Schwanzes, das in keinem Motiv vorkommt – daran
/// erkennt die App, dass er schon im Prompt steht.
const String robloxMarketplaceTailMarker = 'one single body mesh';

/// Der fertige Marktplatz-Prompt aus einem Motiv.
class MarketplacePrompt {
  const MarketplacePrompt({
    required this.prompt,
    required this.negative,
    required this.tailAppended,
    required this.motifChars,
    required this.motifBudget,
    required this.notes,
    this.tailChars = 0,
  });

  /// Länge des festen Schwanzes, der angehängt wird.
  final int tailChars;

  /// Was an Tripo geht: Motiv plus fester Schwanz (mit A-Pose).
  final String prompt;

  /// Die NEGATIV-Zeile: eigene Begriffe zuerst, dann die festen, ohne
  /// Doppelte, in Tripos Grenze.
  final String negative;

  /// False, wenn der Schwanz schon im Motiv stand.
  final bool tailAppended;

  final int motifChars;

  /// Was dem Motiv bleibt, wenn der Schwanz drin sein soll.
  final int motifBudget;

  final List<String> notes;

  bool get motifTooLong => motifChars > motifBudget;
}

/// Macht aus einem Motiv den Prompt, der beim Marktplatz-Ziel wirklich
/// an Tripo geht.
///
/// Bisher stand der feste Schwanz nur in der kopierbaren Vorlage: Wer
/// ihn nicht über die Prompt-KI zurück ins Feld holte, schickte ein
/// nacktes Motiv plus A-Pose – und bekam eine Figur, die keine der
/// Formregeln kannte. Jetzt hängt die App ihn selbst an, sobald das
/// Ziel Marktplatz-Avatar ist. Steht er schon im Text (die Vorlage
/// wurde zurückkopiert), bleibt es bei einem.
MarketplacePrompt marketplacePrompt(
  String motif, {
  String negative = '',
  double studs = marketplaceFigureStuds,
  RobloxBodyScale scale = RobloxBodyScale.normal,
}) {
  final text = motif.trim();
  final notes = <String>[];
  final tail = robloxMarketplaceTailFor(studs: studs, scale: scale);
  final budget = TripoService.maxPromptChars - tail.length - 2;
  final schonDa = text.toLowerCase().contains(robloxMarketplaceTailMarker);
  final prompt = schonDa || text.isEmpty ? text : '$text, $tail';
  if (schonDa) {
    notes.add('Der feste Marktplatz-Schwanz steht schon im Prompt – er '
        'wird nicht ein zweites Mal angehängt.');
  } else if (text.length > budget) {
    notes.add('Das Motiv hat ${text.length} Zeichen, mit dem festen '
        'Schwanz bleiben ihm $budget. Tripo kürzt hinten – und hinten '
        'stehen die Regeln. Das Motiv kürzen.');
  }
  final eigene = negative.trim();
  var neg = eigene.isEmpty
      ? robloxMarketplaceNegative
      : mergeTerms([eigene, robloxMarketplaceNegative]);
  if (neg.length > TripoService.maxNegativePromptChars) {
    final vorher = neg.length;
    neg = TripoService.clipToLimit(neg, TripoService.maxNegativePromptChars);
    notes.add('Die NEGATIV-Zeile hatte $vorher Zeichen, Tripo nimmt '
        '${TripoService.maxNegativePromptChars}: hinten gekürzt, die '
        'eigenen Begriffe vorn bleiben.');
  }
  return MarketplacePrompt(
    prompt: prompt,
    negative: neg,
    tailAppended: !schonDa && text.isNotEmpty,
    motifChars: text.length,
    motifBudget: budget,
    tailChars: tail.length,
    notes: notes,
  );
}

/// Die NEGATIV-Zeile für einen Marktplatz-Körper.
///
/// Ganz vorn steht, was das Gesicht verdeckt: Kapuze, Helm, Maske,
/// Visier. Das ist der einzige Fehler, den weder Prompt noch
/// Reparatur nachträglich beheben – ohne Lider und Lippen im Kopfnetz
/// gibt es keine FACS-Posen und damit keinen Marktplatz. Danach die
/// Formfehler, vor allem Kosmetischen: Tripo gewichtet die vorderen
/// Begriffe stärker, und `deep body` sowie `long hem` sind die beiden,
/// an denen die Figur abgelehnt wurde. „painted flat eyes" ist dafür
/// gewichen: Das bestellt der Schwanz jetzt positiv.
///
/// „thick legs" ist raus – das drückte die Figur genau dorthin, wo sie
/// seit August 2026 scheitert (Teile unter 50 % Deckung). Stattdessen
/// „spindly limbs". Und die Anbauten sind neu: Schwanz, Flügel, Hörner,
/// abstehende Ohren, Haarsträhnen dürfen nicht im Körpernetz stecken;
/// erlaubt sind genau ein Kopf, ein Rumpf, zwei Arme, zwei Beine.
const String robloxMarketplaceNegative =
    'hood, helmet, mask, visor, tail, wings, horns, pointed ears, hair '
    'strands, deep body, long hem, skirt, cape, fingers, T-pose, spindly '
    'limbs, thin arms, short legs, bulging eyes, floating parts, open mesh, '
    'holes, base, text, second character, extra limbs';

/// Das Marktplatz-Beispiel – **ohne Kapuze**.
///
/// Vorher stand hier die Kapuzenfigur mit „eyes and a small mouth
/// inside the hood opening". Das ist wörtlich das Konzept, das
/// fünfmal gescheitert ist, und das Konzept-Gate hält es nicht auf,
/// weil „eyes" und „mouth" dastehen. Wer das Beispiel übernahm, bekam
/// die nächste Kapuzenfigur. Jetzt steht hier die Figur **unter** der
/// Kapuze: sichtbares Gesicht, Lider, Lippen. Die Kapuze kommt als
/// eigenes Accessoire dazu (Gegenstandsart „Kapuze") – aus einer
/// unmöglichen Aufgabe werden zwei lösbare.
const String robloxMarketplaceExample =
    'PROMPT: compact humanoid, round head a quarter of body height, big round '
    'eyes sunk into the head, wide mouth with plump lips, straight torso, '
    'fitted sweater, tight dark shorts, sturdy legs a third of body height, '
    'gap between the thighs, matte charcoal fabric, pale grey skin, '
    '$robloxMarketplaceTail'
    '\nNEGATIV: $robloxMarketplaceNegative';

/// Die NEGATIV-Zeile für eine Figur (248 Zeichen – Tripo nimmt 255).
///
/// Hier stand „arms down". Das passte zur T-Pose, aber der
/// Posen-Schalter erlaubt auf dem Figur-Weg auch die A-Pose – und dann
/// stand „angled 45 degrees down" im Prompt gegen „arms down" im
/// Negativ. Gemeint war nie die Richtung, sondern das Anliegen: Arme
/// am Körper verschmelzen mit dem Rumpf, und dort kann kein Skelett
/// andocken.
const String robloxFigureNegative =
    'low poly, blobby, melted, floating parts, thin parts, open '
    'mesh, holes, base, pedestal, text, logo, second character, '
    'companion animal, extra limbs, arms along the body, dynamic pose, '
    'noisy surface, cluttered details, drawstrings, loose cloth, cape';

/// Die NEGATIV-Zeile für ein Accessoire (202 Zeichen).
const String robloxAccessoryNegative =
    'character, head, body, person, mannequin, base, pedestal, '
    'stand, thin parts, open mesh, holes, floating parts, text, '
    'logo, noisy surface, cluttered details, low poly, blobby, '
    'melted, blurry, low quality';

/// Ein vollständiger, erprobter Block als Vorbild.
const String robloxFigureExample =
    'PROMPT: hooded creature character, oversized rounded head, wide '
    'shoulders, thick torso, short stubby legs, thick knee-length '
    'hoodie with few broad rounded folds, deep recessed hood opening '
    'in shadow, two glowing cyan oval eyes inside the hood, long '
    'sleeves fully covering the hands as rounded stumps, thick '
    'rounded cuffs, thick rounded hem, flat rounded feet, matte dark '
    'charcoal fabric, lighter grey hood interior, $robloxFigureTail\n'
    'NEGATIV: $robloxFigureNegative';

const String robloxAccessoryExample =
    'PROMPT: wide-brimmed pointed wizard hat, thick rounded brim, '
    'tall soft-cornered cone, matte deep blue felt, one gold band, '
    '$robloxAccessoryTail\n'
    'NEGATIV: $robloxAccessoryNegative';

/// Der Regelblock, der an die kopierte Prompt-Vorlage gehängt wird.
///
/// Er nennt nicht nur, was zu vermeiden ist, sondern gibt den Bauplan
/// und die festen Textbausteine mit – sonst muss die Prompt-KI raten,
/// und genau daran sind die ersten Läufe gescheitert.
/// [marketplace] schaltet auf den Marktplatz-Körper um: dieselbe
/// Bauanleitung, aber mit den fünf Formregeln, an denen eine Figur
/// scheitert, die im eigenen Erlebnis läuft. Wirkt nur zusammen mit
/// `accessory: false` – ein Accessoire hat weder Beine noch Hals.
String robloxPromptRules({
  required bool accessory,
  bool marketplace = false,
  double studs = marketplaceFigureStuds,
  RobloxBodyScale scale = RobloxBodyScale.normal,
}) {
  final markt = marketplace && !accessory;
  final tail = accessory
      ? robloxAccessoryTail
      : (markt
          ? robloxMarketplaceTailFor(studs: studs, scale: scale)
          : robloxFigureTail);
  final negative = accessory
      ? robloxAccessoryNegative
      : (markt ? robloxMarketplaceNegative : robloxFigureNegative);
  final example = accessory
      ? robloxAccessoryExample
      : (markt ? robloxMarketplaceExample : robloxFigureExample);
  final triangles = accessory
      ? robloxAccessoryTriangles
      : (markt ? specBodyTotalTriangles : robloxGoalTriangles);
  final was = accessory
      ? 'das Accessoire'
      : (markt ? 'den Marktplatz-Körper' : 'die Figur');
  // Was vom Prompt fürs Motiv übrig bleibt: Grenze minus Schwanz
  // (mit Komma und Leerzeichen) minus Posen-Zusatz. Beim Marktplatz
  // steht die Pose schon im Schwanz, beim Accessoire gibt es keine.
  final motivBudget = TripoService.maxPromptChars -
      tail.length -
      2 -
      (accessory || markt ? 0 : tPoseSuffix.length + 2);

  final aufbau = accessory
      ? '- AUFBAU des PROMPT, in dieser Reihenfolge:\n'
          '  1. Was es ist („wide-brimmed pointed wizard hat").\n'
          '  2. Die Grundform in groben Volumen („thick rounded '
          'brim, tall soft-cornered cone").\n'
          '  3. Ein bis zwei Merkmale, ausgeschrieben und mit Ort am '
          'Teil („one gold band around the base").\n'
          '  4. Farben und Material („matte deep blue felt").\n'
          '  5. Dann wörtlich der feste Schwanz (siehe unten).\n'
      : markt
          ? '- AUFBAU des PROMPT, in dieser Reihenfolge:\n'
              '  1. Was es ist („compact humanoid"). Nicht „small '
              'stocky": Die erste Figur mit diesem Schwanz war klein '
              'und stämmig – mit Stummelbeinen und dem Schritt bei 0,9 '
              'Studs.\n'
              '  2. Proportionen („round head a quarter of body height, '
              'sturdy legs a third of body height, gap between the '
              'thighs"). Kein übergroßer Kopf, keine kurzen Beine: Die '
              'Mindesthöhen für Rumpf (1,7) und Beine (1,4) sind '
              'absolut, und bei 5 Studs bleibt unter einem 2-Studs-Kopf '
              'nicht genug.\n'
              '  3. Das Gesicht, ausgeschrieben – es ist hier Pflicht, '
              'nicht Schmuck („big round eyes sunk into the head, wide '
              'mouth with plump lips"; „face fully visible" und die '
              'Lider stehen schon im Schwanz). „sunk into the head", '
              'weil Tripo aus „large round eyes" Kugeln macht, die aus '
              'dem Kopf stehen – und in einen Buckel lässt sich keine '
              'Augenhöhle bauen. Dann Kleidung und das erkennende '
              'Merkmal mit Ort am Körper („fitted sweater with one '
              'white stripe across the chest"). Knapp genannt geht es '
              'unter.\n'
              '  4. Farben und Material („matte dark charcoal fabric, '
              'pale grey skin").\n'
              '  5. Dann wörtlich der feste Schwanz (siehe unten).\n'
          : '- AUFBAU des PROMPT, in dieser Reihenfolge:\n'
              '  1. Was es ist („hooded creature character").\n'
              '  2. Proportionen („oversized rounded head, wide '
              'shoulders, thick torso, short stubby legs").\n'
              '  3. Kleidung und das erkennende Merkmal – '
              'ausgeschrieben und mit Ort am Körper („thick '
              'knee-length hoodie", „two glowing cyan oval eyes '
              'inside the hood"). Knapp genannt geht es unter.\n'
              '  4. Farben und Material („matte dark charcoal fabric, '
              'lighter grey hood interior").\n'
              '  5. Dann wörtlich der feste Schwanz (siehe unten).\n';

  final poseRegel = accessory
      ? '- KEINE Pose, kein Körper, keine Hand, die es hält. Das Teil '
          'schwebt frei und vollständig sichtbar.\n'
      : markt
      ? '- KEINE T-Pose. Für den Marktplatz-Weg steht die A-Pose '
          'schon im festen Schwanz, und sie ist dort die bessere: In '
          'einem echten Lauf durch Roblox\' Auto Setup wurden die '
          'waagerechten Arme der T-Pose dem Kopf und dem Rumpf '
          'zugeschlagen – heraus kam ein „UpperTorso" von 4,38 Studs '
          'Breite. Arme in 45° hängen frei und sind als Arme '
          'erkennbar.\n'
          '- KEINE Umhänge, Röcke, langen Mäntel oder Schleier. Für '
          'den Marktplatz kommt dazu: **nichts, was von der Hüfte '
          'abwärts über beide Beine hängt.** Ein Saum bläht den '
          'Hüllkörper des Beins auf, während das Bein darin dünn '
          'bleibt – das reißt die Deckungsprüfung und die Regel '
          'LegsSeparated zugleich.\n'
          '- KEIN verdecktes Gesicht: keine Kapuze, kein Helm, keine '
          'Maske, kein Visier, kein „Gesicht im Schatten". Der '
          'Marktplatz verlangt für den Kopf eines Ganzkörper-Bundles '
          'einen dynamischen Kopf mit FACS-Posen, und Auto Setup baut '
          'die nur, wenn das Kopfnetz Augenhöhlen mit Lidern und eine '
          'Mundhöhle mit Lippen hat. Fünf Läufe haben das entschieden: '
          'Augen und Zähne als eigene Volumen reichen nicht, egal wo '
          'sie sitzen. Was das Gesicht verdeckt, wird ein eigenes '
          'Accessoire (Gegenstandsart „Kapuze", „Helm", „Maske") und '
          'kommt danach auf die Figur.\n'
          '- KEINE Anbauten am Körper: Schwanz, Flügel, Hörner, Geweih, '
          'abstehende Ohren, Haarsträhnen. Erlaubt sind genau ein Kopf, '
          'ein Rumpf, zwei Arme, zwei Beine – alles andere wird ein '
          'eigenes Accessoire (Marktplatz-Policy: „tails, wings, extra '
          'limbs … must be uploaded separately"). Bei einem „creature" '
          'ist das die naheliegendste Fehlerquelle; deshalb steht im '
          'Beispiel „humanoid".\n'
          '- KEINE nackte Haut von der Hüfte bis unter Schritt und '
          'Gesäß (Modesty-Layer): Der Marktplatz verlangt dort volle, '
          'undurchsichtige Bedeckung in einer anderen Farbe als die '
          'Haut. Der Schwanz bestellt deshalb eng anliegende Shorts, '
          'die der Beinform folgen – kein hängender Saum, sonst kollidiert '
          'es mit den getrennten Beinen. Ausnahme laut Policy: Figuren, '
          'die Tieren oder Gegenständen gleichen.\n'
          '- KEINE dünnen Gliedmaßen: Jedes Teil muss 50 % seines '
          'Hüllkörpers füllen, von vorn, von der Seite und von hinten, '
          'der Kopf eingeschlossen. Seit dem 17. August 2026 prüft der '
          'Validator das schärfer, gegen zu kleine Körperteile. „slim '
          'legs" und „thick legs" im Negativ bestellten genau das '
          'Falsche.\n'
      : '- KEINE T-Pose in den Prompt schreiben. Der Importer '
          'verlangt sie, aber die App hängt sie über den '
          'Posen-Schalter selbst an (${tPoseSuffix.length + 2} '
          'Zeichen; beim Roblox-Ziel „Figur im Erlebnis" steht er '
          'auf T-Pose) – doppelt kostet nur Platz und verschiebt die '
          'Gewichtung.\n'
          '- KEINE Umhänge, Röcke, langen Mäntel oder Schleier, die '
          'Arme oder Beine verdecken: Was verdeckt ist, verschmilzt '
          'bei der Rekonstruktion mit dem Rumpf, und dort kann kein '
          'Skelett andocken.\n';

  final posen = specAllowedPoses.join(', ');
  return '\n\nZUSÄTZLICH – das Modell wird '
      '${accessory ? 'als UGC-Accessoire ' : ''}'
      '${markt ? 'als Figurenkörper auf den Roblox-Marktplatz '
          'hochgeladen. Der Importer ist dabei die kleinere Hürde: '
          'Über ihn hinaus prüft der Marktplatz-Validator Maße, die '
          'in keiner Dokumentation stehen, und die entstehen alle '
          'beim Prompt. Deshalb muss er so gebaut sein' : 'nach '
          'Roblox hochgeladen. Damit der Importer es annimmt, muss '
          'der Prompt so gebaut sein'}:\n\n'
      '$aufbau'
      '\n- Der FESTE SCHWANZ, wörtlich und unverändert ans Ende:\n'
      '  $tail\n'
      '\n- Die NEGATIV-Zeile, wörtlich:\n'
      '  $negative\n'
      '\nWas den Prompt kaputtmacht:\n'
      '$poseRegel'
      '- KEINE Verneinungen im PROMPT („no fingers"). '
      'Text→3D-Modelle lesen sie nicht als Ausschluss, sondern sehen '
      'das Substantiv. Positiv formulieren '
      '${markt ? '(„mitten hands without fingers" ist die Ausnahme, '
          'weil „mitten hands" das Substantiv trägt; „face fully '
          'visible" statt „no hood")' : '(„deep recessed hood '
          'opening in shadow")'} und Auszuschließendes in die '
      'NEGATIV-Zeile.\n'
      '- KEINE dünnen Kleinteile: Schnüre, Ketten, Schnallen, '
      'einzelne Haarsträhnen, Federn, Netze, Bänder. Unter '
      '${_n(triangles)} Dreiecken werden daraus Splitter oder nichts, '
      'und sie reißen Löcher in die Hülle.\n'
      '- KEINE Schrift, keine Logos, keine Marken- oder '
      'Figurenbezüge: Alles Hochgeladene geht durch die '
      'Roblox-Moderation.\n'
      '${markt ? '\nGrenzen des Marktplatz-Validators – aus der '
          'Dokumentation (Character body specifications, Tabellen je '
          'Skala, nachgesehen 3. September 2026), alle Werte absolut '
          'in Studs, gewählt: ${scale.label}, Figur '
          '${studs.toStringAsFixed(studs == studs.roundToDouble() ? 0 : 2)} '
          'Studs hoch:\n'
          '- Tiefe höchstens ${scale.maxDepth.toStringAsFixed(2)} '
          '(Classic und Slender 2,00, Normal 2,25) – bei dieser Höhe '
          '${(scale.maxDepth / studs * 100).round()} %. Die abgelehnte '
          'Testfigur hatte 2,45, bei jeder Skala zu viel.\n'
          '- Kopf höchstens ${scale.maxHeadWidth.toStringAsFixed(1)} '
          'breit (Classic 1,5, Slender 2, Normal 3). Ein großer Kopf '
          'passt nur in Normal: im Importer „Rig Scale: '
          '${scale.rigScale}".\n'
          '- Mindestmaße, für alle Skalen: Rumpf 1,7 hoch und 0,85 '
          'breit, Bein 1,4 hoch, Arm 1,5 lang, Kopf 0,5, Körper 3,6. '
          'Bei ${studs.toStringAsFixed(0)} Studs bleibt unter dem Kopf '
          'für Rumpf und Beine genug, wenn der Kopf etwa ein Viertel '
          'und die Beine etwa ein Drittel der Höhe haben. Zu kurze '
          'Beine sind der häufigste Fehlschlag: Aus „sturdy legs" '
          'machte Tripo Beine von 0,9 Studs, und die Reparatur kann '
          'sie nicht verlängern.\n'
          '- Jedes Bein höchstens 1,50 breit.\n'
          '- Jedes Körperteil füllt seinen Hüllkörper zu mindestens '
          '50 %, von vorn, von der Seite, von hinten – auch der Kopf. '
          'Zu wenig Deckung heißt fast immer: Etwas ragt aus dem Outer '
          'Cage, den Auto Setup um das Teil legt, ohne selbst Volumen '
          'zu haben – der Saum.\n'
          '- Sicherheitsaufschlag aus einem echten Validator-Lauf, '
          'nicht aus der Doku: Rumpfbreite mindestens 2,54, Armspanne '
          'mindestens 6,22, Hals höchstens halb so breit wie der Kopf '
          '(59 % haben nicht gereicht). Zwischen Doku und Validator gibt '
          'es dazu offene Bugreports; die Doku ist die harte Grenze, '
          'diese Werte sind die Reserve.\n'
          '- Dynamischer Kopf: mindestens 17 FACS-Posen, und der '
          'Validator prüft, ob sich Lider und Lippen für Blinzeln, '
          'Mundöffnen, fröhlich und traurig wirklich bewegen. '
          'Augenbrauen und Wimpern gehören als Accessoires ans '
          'Bundle, nicht ins Kopfnetz.\n' : ''}'
      '\nGrenzen, die das Ziel setzt (aus Roblox\' Spezifikation):\n'
      '- Höchstens ${_n(triangles)} Dreiecke – deshalb grobe Volumen '
      'statt Zierrat. '
      '${markt ? 'Und zwar über alle sechs Gruppen zusammen, je '
          'Gruppe begrenzt: Kopf '
          '${_n(specBodyPartTriangles['DynamicHead']!)}, Rumpf '
          '${_n(specBodyPartTriangles['Torso']!)}, je Arm und Bein '
          '${_n(specBodyPartTriangles['LeftArm']!)}. Der Arm zählt '
          'Ober, Unter und Hand zusammen – deshalb Fäustlinge: '
          'ausmodellierte Finger kosteten je Hand über 1.280 '
          'Dreiecke, mehr als der ganze Arm haben darf. Für Roblox\' '
          'Auto Setup das Modell mit face_limit 7.000 erzeugen, '
          'nicht 10.000: Das Werkzeug reduziert nicht selbst, und bei '
          '9.627 Dreiecken bekam jede Gliedmaße 2.304. ' : ''}'
      '${accessory ? 'Für starre Accessoires ist das die harte '
          'Grenze; der Importer nimmt je Mesh nie mehr als '
          '${_n(specMaxMeshTriangles)}.' : 'Die harte Grenze des '
          'Importers liegt bei ${_n(specMaxMeshTriangles)} je Mesh; '
          'ein Figurenkörper für den Marktplatz darf über seine sechs '
          'Teile zusammen ${_n(specBodyTotalTriangles)} haben (Kopf '
          '${_n(specBodyPartTriangles['DynamicHead']!)}, Rumpf '
          '${_n(specBodyPartTriangles['Torso']!)}, je Arm und Bein '
          '${_n(specBodyPartTriangles['LeftArm']!)}).'}\n'
      '- Die Hülle muss geschlossen sein – keine offenen Löcher, keine '
      'Rückseiten. Nichts darf null Dicke haben; jedes Teil braucht '
      'Volumen. Ein einziges Mesh'
      '${accessory ? ' – bei starren Accessoires ausdrücklich '
          'gefordert' : ''}.\n'
      '${accessory ? '' : '- Das Modell muss riggbar bleiben: Arme und '
          'Beine frei und vom Rumpf getrennt, damit die 15 '
          'R15-Gelenke (LowerTorso, UpperTorso, Head, '
          'LeftUpperArm … RightFoot) darin Platz haben. Roblox nimmt '
          '$posen – die App hängt die gewählte Pose über den '
          'Posen-Schalter selbst an.\n'}'
      '- Ein Material je Mesh, alles in einer einzigen '
      '${robloxMaxTexture}er-Textur: wenige, klar getrennte '
      'Farbflächen.\n'
      '${accessory ? '' : '- ${robloxCharacterStuds.toStringAsFixed(0)} '
          'Studs hoch (rund 1,4 m) – kompakte, gedrungene '
          'Proportionen wirken auf diese Größe besser als schlanke.\n'}'
      '- Der PROMPT darf höchstens '
      '${_n(TripoService.maxPromptChars)} Zeichen haben. Der feste '
      'Schwanz belegt davon ${_n(tail.length)}'
      '${accessory || markt ? '' : ', der T-Pose-Zusatz weitere '
          '${tPoseSuffix.length + 2}'}, für das MOTIV bleiben also '
      'rund ${_n(motivBudget)} Zeichen. Wird es länger, kürzt Tripo '
      'hinten – und hinten stehen die Regeln. Die NEGATIV-Zeile '
      'höchstens ${_n(TripoService.maxNegativePromptChars)}.\n'
      '\nSo sieht ein fertiger Block für $was aus:\n\n'
      '$example';
}

String _n(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
    buffer.write(text[i]);
  }
  return buffer.toString();
}
