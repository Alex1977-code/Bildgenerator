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

/// Der feste Schwanz für einen Marktplatz-Körper.
///
/// **Jede Angabe darin steht so in Roblox' Dokumentation.** Was nur
/// gut gemeint war, ist raus – Stand 3. September 2026, geprüft gegen
/// den öffentlichen Doku-Spiegel `Roblox/creator-docs`:
///
/// * A = `avatar-setup/auto-setup-requirements.md`, „Mesh
///   requirements" – was Auto Setup als Eingabe verlangt.
/// * B = `marketplace/marketplace-policy.md`, „Avatar body
///   guidelines".
/// * C = `avatar/character-bodies/specifications.md`.
///
/// | Angabe | Beleg |
/// | --- | --- |
/// | upright A-pose, arms angled down | A 6 „should form an upright A-pose or T-Pose" |
/// | clear of the torso | A 6 „no limbs obscure or overlap each other from the front view" |
/// | symmetrical | A 8 „Asymmetrical character bodies may work on a case-to-case basis" |
/// | humanoid, one head/torso, two arms with hands, two legs with feet | A 5 „Humanoid shape"; B „Each body can only include the following parts" |
/// | distinct narrow neck not merged with the shoulders | A 11 „Keep the neck distinct and not merged with the shoulders or upper torso" |
/// | head about one quarter, hips at mid body height | C „Body scale": Rumpf mindestens 1,7 und Bein 1,4 Studs bei 5 Studs Gesamthöhe – in Anteile übersetzt, weil ein Text-zu-3D-Modell keine Studs kennt |
/// | body depth less than two fifths of body height | C „Body scale": Tiefe höchstens 2,00 (Classic, Slender) oder 2,25 (Normal); [robloxDepthWords] rechnet das Wort aus |
/// | thick enough to fill their outlines | C „Visibility": „must take up at least 50% of body part's bounding box" |
/// | two separate legs with a gap | A 6, siehe oben |
/// | opaque clothing covering upper and lower torso | B „Modesty layers": „a layer of clothing that covers an avatar's upper torso and lower torso"; C „Body parts must be fully opaque" |
/// | face uncovered | A 10 „Do not include any accessories … hair, eyebrows, beards" |
/// | two eye sockets each holding a half-sphere eye | A 2 „2 connected eyebags containing half-sphere eyes" |
/// | an open mouth cavity | A 2 „a connected mouthbag that houses the upper teeth, lower teeth, and tongue" |
/// | watertight, apart from the eye and mouth openings | A 9 „watertight in all regions with the exception of the eyes and mouth" |
/// | one single body mesh | A 1 „Avatar Setup accepts character bodies comprised of 1 or more meshes" – eines ist der einfachste Fall, und es ist der Marker, an dem die App den Schwanz wiedererkennt |
///
/// **Was gestrichen wurde, weil es nirgends gefordert ist:** „never
/// horizontal" (A 6 erlaubt die T-Pose ausdrücklich), „mitten hands
/// without fingers" (Finger sind nirgends verboten; die Grenze ist
/// das Dreiecksbudget, und das stellt die App am Anbieter ein),
/// „eyelids" und „lips" (B: „does not need to have an eyeball or
/// eyelid" und „does not need to have lips, teeth or tongue"),
/// „in a contrasting colour" (B verlangt eine Schicht Kleidung, keine
/// Farbe), „few flat separated color areas" und „uniform material"
/// (Stil; das Material setzt der Export), „flat chest and back"
/// (dieselbe Regel wie die Tiefe, doppelt), „solid closed volumes with
/// visible wall thickness" (dieselbe Regel wie wasserdicht).
///
/// Der Schwanz ist damit von 745 auf 629 Zeichen geschrumpft; dem
/// Motiv bleiben 393 statt 277.
const String robloxMarketplaceTail = _tailNormal5;

/// Der Schwanz für die Standardhöhe und -skala – als Konstante, weil
/// die Vorlagen ihn wörtlich zitieren.
const String _tailNormal5 =
    'upright A-pose, arms angled down and clear of the torso, symmetrical, '
    'humanoid with one head, one torso, two arms with hands, two legs with '
    'feet, distinct narrow neck not merged with the shoulders, head about one '
    'quarter of body height, hips at mid body height, body depth less than two '
    'fifths of body height, arms and legs thick enough to fill their outlines, '
    'two separate legs with a gap between the thighs, opaque clothing covering '
    'upper and lower torso, face uncovered, two eye sockets each holding a '
    'half-sphere eye, an open mouth cavity, watertight closed surface apart '
    'from the eye and mouth openings, one single body mesh';

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
    'hood, helmet, mask, visor, hair, beard, eyebrows, eyelashes, tail, wings, '
    'horns, pointed ears, extra limbs, second character, deep body, long hem, '
    'skirt, cape, spindly limbs, thin arms, short legs, bulging eyes, closed '
    'mouth, floating parts, holes, base';

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
    'PROMPT: compact humanoid, round head a quarter of body height, two eye '
    'sockets with half-sphere eyes, open mouth cavity, straight torso, fitted '
    'sweater, tight dark shorts, hips at mid body height, sturdy legs with a '
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
              '  1. Was es ist („compact humanoid"). Auto Setup '
              'verlangt eine humanoide Form mit zwei Armen, zwei '
              'Beinen, einem Rumpf und einem Kopf.\n'
              '  2. Proportionen („round head a quarter of body '
              'height, hips at mid body height"). Das ist die '
              'Größentabelle in Anteile übersetzt: Rumpf mindestens '
              '1,7 und Bein mindestens 1,4 Studs, bei 5 Studs '
              'Gesamthöhe. Die Hüftlinie wirkt, eine Beinlänge nicht: '
              'Die Beine sind, was unter der Hüfte übrig bleibt.\n'
              '  3. Das Gesicht („two eye sockets with half-sphere '
              'eyes, open mouth cavity"). Auto Setup verlangt fünf '
              'Kopfteile: zwei Augensäcke mit Halbkugel-Augen und '
              'einen Mundsack mit Ober-, Unterzähnen und Zunge, keiner '
              'davon teilt Punkte mit dem Kopf. Die fünf Teile baut '
              'die App; die **Höhlen** dafür muss der Prompt liefern – '
              'in einen vorstehenden Augapfel lässt sich keine '
              'schneiden.\n'
              '  4. Kleidung: eine Schicht über Ober- und Unterkörper, '
              'undurchsichtig („fitted sweater, tight dark shorts"). '
              'Dazu das erkennende Merkmal mit Ort am Körper („one '
              'white stripe across the chest"); knapp genannt geht es '
              'unter.\n'
              '  5. Farben und Material („matte charcoal fabric, pale '
              'grey skin").\n'
              '  6. Dann wörtlich der feste Schwanz (siehe unten).\n'
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
      ? '- Die Pose: A oder T, aufrecht. Auto Setup erlaubt beide '
          'ausdrücklich und nennt die I-Pose („Arme am Körper") '
          'schlechter. Der feste Schwanz bestellt die A-Pose; ein '
          'eigener Posen-Zusatz ist deshalb überflüssig. Dazu die '
          'Regel „no limbs obscure or overlap each other from the '
          'front view": Von vorn darf keine Gliedmaße eine andere '
          'verdecken.\n'
          '- KEINE Accessoires im Netz: Haare, Augenbrauen, Bart, '
          'Wimpern nennt Auto Setup namentlich („Do not include any '
          'accessories"). Augenbrauen und Wimpern gehören als eigene '
          'Accessory-Objekte ans Bundle, nicht ins Körpernetz. Was '
          'das Gesicht verdeckt – Kapuze, Helm, Maske, Visier – wird '
          'ein eigenes Accessoire und kommt danach auf die Figur.\n'
          '- KEINE Anbauten am Körper: Die Policy zählt abschließend '
          'auf, was ein Körper haben darf – ein Kopf, ein Rumpf, je '
          'ein Arm aus Ober-, Unterarm und Hand, je ein Bein aus '
          'Ober-, Unterschenkel und Fuß – „and cannot have additional '
          'appendages". Schwanz, Flügel, Hörner, abstehende Ohren '
          'werden eigene Accessoires. Bei einem „creature" ist das die '
          'naheliegendste Fehlerquelle; deshalb steht im Beispiel '
          '„humanoid".\n'
          '- Modesty-Layer: eine Schicht Kleidung über Ober- **und** '
          'Unterkörper. Die Policy verlangt sie, sobald die Figur an '
          'Brust und Schritt eine glatte, hautartige Fläche hat, und '
          'lässt sie bei Tieren und Gegenständen weg. Eine bestimmte '
          'Farbe verlangt sie nicht; undurchsichtig müssen die '
          'Körperteile ohnehin sein.\n'
          '- KEINE dünnen Gliedmaßen: Jedes Teil muss 50 % seines '
          'Hüllkörpers füllen, von vorn, von der Seite und von hinten, '
          'der Kopf eingeschlossen („must take up at least 50% of body '
          'part\'s bounding box"). „slim legs" bestellt genau das '
          'Falsche – „thick legs" aber auch: Die Grenze nach oben ist '
          'die Größentabelle, nicht ein Wort im Negativ.\n'
          '- Ein deutlicher Hals: „Keep the neck distinct and not '
          'merged with the shoulders or upper torso." Ohne ihn findet '
          'Auto Setup die Grenze zwischen Kopf und Rumpf nicht.\n'
          '- Wasserdicht, **außer an Augen und Mund**: Genau dort '
          'sollen Öffnungen sein – die Augensäcke und der Mundsack. '
          'Sonst keine Löcher und keine Rückseiten.\n'
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
