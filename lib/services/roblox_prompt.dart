import 'roblox_check.dart'
    show
        robloxAccessoryTriangles,
        robloxGoalTriangles,
        robloxMaxTexture,
        robloxCharacterStuds;
import 'pose_prompt.dart' show tPoseSuffix;
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
/// * **Tiefe unter zwei Fünfteln der Höhe.** Die Testfigur hatte 49 %,
///   die Grenze liegt bei 40 %. Nachträglich flach drücken geht nicht.
/// * **Saum am Hüftknochen, Beine darunter frei.** „hip-length" hat
///   Tripo als Mitte Oberschenkel gelesen; alles, was von der Hüfte
///   abwärts über beide Beine hängt, landet im Bein-Hüllkörper und
///   reißt Deckung und die Regel LegsSeparated zugleich.
/// * **Schlanke Beine.** Höchstens ein Drittel der Körperhöhe.
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
const String robloxMarketplaceTail =
    'arms straight and angled 45 degrees down in an A-pose, never '
    'horizontal, single connected body, symmetrical, body depth less '
    'than two fifths of body height, flat chest and back, narrow visible neck clearly '
    'separating head from shoulders, mitten hands without fingers, '
    'garment hem ending at the hip bone, thighs uncovered, two '
    'separate leg tubes from the hips down, slim straight legs each '
    'narrower than one third of body height, face fully visible, eye '
    'sockets with eyelids and a mouth with lips shaped into the head, '
    'solid closed volumes with visible wall thickness, closed '
    'watertight shell, one single body mesh, smooth simple surfaces, '
    'few flat separated color areas, uniform material';

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
const String robloxMarketplaceNegative =
    'hood, helmet, mask, visor, deep body, round belly, long hem, '
    'thigh-length, skirt, cape, fingers, T-pose, arms out sideways, '
    'thick legs, floating parts, thin parts, open mesh, holes, base, '
    'pedestal, text, logo, second character, extra limbs, loose cloth';

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
    'PROMPT: small stocky creature character, oversized rounded head, '
    'two large round eyes with thick eyelids, a wide mouth with plump '
    'lips, slim torso, thin plain sweater ending at the hip bone, flat '
    'rounded feet, matte dark charcoal fabric, pale grey skin, '
    '$robloxMarketplaceTail\n'
    'NEGATIV: $robloxMarketplaceNegative';

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
}) {
  final markt = marketplace && !accessory;
  final tail = accessory
      ? robloxAccessoryTail
      : (markt ? robloxMarketplaceTail : robloxFigureTail);
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
              '  1. Was es ist („small stocky creature character").\n'
              '  2. Proportionen („oversized rounded head, slim '
              'torso").\n'
              '  3. Das Gesicht, ausgeschrieben – es ist hier Pflicht, '
              'nicht Schmuck („two large round eyes with thick '
              'eyelids, a wide mouth with plump lips"; „face fully '
              'visible" steht schon im Schwanz). Dann Kleidung und '
              'das erkennende Merkmal mit '
              'Ort am Körper („thin plain sweater ending at the hip '
              'bone"). Knapp genannt geht es unter.\n'
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
      '${markt ? '\nGrenzen des Marktplatz-Validators – gemessen, '
          'nicht dokumentiert (alle Werte bei '
          '${robloxCharacterStuds.toStringAsFixed(0)} Studs Höhe):\n'
          '- Tiefe höchstens 2,00 Studs, also unter zwei Fünfteln der '
          'Höhe. Die abgelehnte Testfigur hatte 2,45 – 49 % statt '
          '40 %.\n'
          '- Jedes Bein höchstens 1,50 breit und 2,00 tief.\n'
          '- Rumpfbreite mindestens 2,54, Armspanne mindestens 6,22 – '
          '„flach" darf nicht „dünn" werden.\n'
          '- Jedes Körperteil muss seinen Hüllkörper ausfüllen: der '
          'Rumpf von vorn zu 50 %, von der Seite zu 46 %; ein Bein '
          'von vorn und von der Seite zu 30 %. Die Testfigur kam am '
          'Bein auf 26 % – nicht weil das Bein zu dünn war, sondern '
          'weil der Saum den Hüllkörper aufblähte.\n'
          '- Der Hals muss höchstens halb so breit sein wie der Kopf. '
          '59 % haben in einem echten Lauf nicht gereicht.\n' : ''}'
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
