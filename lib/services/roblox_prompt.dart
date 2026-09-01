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

/// Die NEGATIV-Zeile für eine Figur (238 Zeichen – Tripo nimmt 255).
const String robloxFigureNegative =
    'low poly, blobby, melted, floating parts, thin parts, open '
    'mesh, holes, base, pedestal, text, logo, second character, '
    'companion animal, extra limbs, arms down, dynamic pose, noisy '
    'surface, cluttered details, drawstrings, loose cloth, cape';

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
String robloxPromptRules({required bool accessory}) {
  final tail = accessory ? robloxAccessoryTail : robloxFigureTail;
  final negative =
      accessory ? robloxAccessoryNegative : robloxFigureNegative;
  final example =
      accessory ? robloxAccessoryExample : robloxFigureExample;
  final triangles = accessory ? robloxAccessoryTriangles : robloxGoalTriangles;
  final was = accessory ? 'das Accessoire' : 'die Figur';

  final aufbau = accessory
      ? '- AUFBAU des PROMPT, in dieser Reihenfolge:\n'
          '  1. Was es ist („wide-brimmed pointed wizard hat").\n'
          '  2. Die Grundform in groben Volumen („thick rounded '
          'brim, tall soft-cornered cone").\n'
          '  3. Ein bis zwei Merkmale, ausgeschrieben und mit Ort am '
          'Teil („one gold band around the base").\n'
          '  4. Farben und Material („matte deep blue felt").\n'
          '  5. Dann wörtlich der feste Schwanz (siehe unten).\n'
      : '- AUFBAU des PROMPT, in dieser Reihenfolge:\n'
          '  1. Was es ist („hooded creature character").\n'
          '  2. Proportionen („oversized rounded head, wide '
          'shoulders, thick torso, short stubby legs").\n'
          '  3. Kleidung und das erkennende Merkmal – '
          'ausgeschrieben und mit Ort am Körper („thick knee-length '
          'hoodie", „two glowing cyan oval eyes inside the hood"). '
          'Knapp genannt geht es unter.\n'
          '  4. Farben und Material („matte dark charcoal fabric, '
          'lighter grey hood interior").\n'
          '  5. Dann wörtlich der feste Schwanz (siehe unten).\n';

  final poseRegel = accessory
      ? '- KEINE Pose, kein Körper, keine Hand, die es hält. Das Teil '
          'schwebt frei und vollständig sichtbar.\n'
      : '- KEINE T-Pose in den Prompt schreiben. Der Importer '
          'verlangt sie, aber die App hängt sie bei eingeschaltetem '
          'Rigging selbst an (${tPoseSuffix.length + 2} Zeichen) – '
          'doppelt kostet nur Platz und verschiebt die Gewichtung.\n'
          '- KEINE Umhänge, Röcke, langen Mäntel oder Schleier, die '
          'Arme oder Beine verdecken: Was verdeckt ist, verschmilzt '
          'bei der Rekonstruktion mit dem Rumpf, und dort kann kein '
          'Skelett andocken.\n';

  final posen = specAllowedPoses.join(', ');
  return '\n\nZUSÄTZLICH – das Modell wird '
      '${accessory ? 'als UGC-Accessoire ' : ''}nach Roblox '
      'hochgeladen. Damit der Importer es annimmt, muss der Prompt so '
      'gebaut sein:\n\n'
      '$aufbau'
      '\n- Der FESTE SCHWANZ, wörtlich und unverändert ans Ende:\n'
      '  $tail\n'
      '\n- Die NEGATIV-Zeile, wörtlich:\n'
      '  $negative\n'
      '\nWas den Prompt kaputtmacht:\n'
      '$poseRegel'
      '- KEINE Verneinungen im PROMPT („no visible face"). '
      'Text→3D-Modelle lesen sie nicht als Ausschluss, sondern sehen '
      'das Substantiv. Positiv formulieren („deep recessed hood '
      'opening in shadow") und Auszuschließendes in die '
      'NEGATIV-Zeile.\n'
      '- KEINE dünnen Kleinteile: Schnüre, Ketten, Schnallen, '
      'einzelne Haarsträhnen, Federn, Netze, Bänder. Unter '
      '${_n(triangles)} Dreiecken werden daraus Splitter oder nichts, '
      'und sie reißen Löcher in die Hülle.\n'
      '- KEINE Schrift, keine Logos, keine Marken- oder '
      'Figurenbezüge: Alles Hochgeladene geht durch die '
      'Roblox-Moderation.\n'
      '\nGrenzen, die das Ziel setzt (aus Roblox\' Spezifikation):\n'
      '- Höchstens ${_n(triangles)} Dreiecke – deshalb grobe Volumen '
      'statt Zierrat. '
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
          '$posen – die App hängt die T-Pose '
          'selbst an.\n'}'
      '- Ein Material je Mesh, alles in einer einzigen '
      '${robloxMaxTexture}er-Textur: wenige, klar getrennte '
      'Farbflächen.\n'
      '${accessory ? '' : '- ${robloxCharacterStuds.toStringAsFixed(0)} '
          'Studs hoch (rund 1,4 m) – kompakte, gedrungene '
          'Proportionen wirken auf diese Größe besser als schlanke.\n'}'
      '- Der PROMPT darf höchstens '
      '${_n(TripoService.maxPromptChars)} Zeichen haben'
      '${accessory ? '' : ' (davon gehen '
          '${tPoseSuffix.length + 2} für den T-Pose-Zusatz ab)'}, '
      'die NEGATIV-Zeile höchstens '
      '${_n(TripoService.maxNegativePromptChars)}.\n'
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
