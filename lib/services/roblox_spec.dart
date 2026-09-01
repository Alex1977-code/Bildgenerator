/// Die Zahlen und Namen aus Roblox' offizieller Dokumentation – an
/// einer Stelle, jeweils mit der Datei, aus der sie stammen.
///
/// Warum eigens: Die Werte standen bisher verstreut in
/// `roblox_check.dart`, `roblox_rig.dart` und `roblox_prompt.dart`,
/// teils als Faustregel. Wer eine davon ändert, soll sehen, woher sie
/// kommt – und ein Test hält Prüfung, Rigging und Vorlage auf
/// denselben Zahlen.
///
/// Quelle ist das öffentliche Repository `Roblox/creator-docs`; die
/// Pfade unten sind relativ zu `content/en-us/`.
library;

// ----------------------------------------------------------------
// Geometrie – art/modeling/specifications.md
// ----------------------------------------------------------------

/// „Individual meshes can not exceed 20,000 triangles."
const int specMaxMeshTriangles = 20000;

/// „All geometry must be watertight without exposed holes or
/// backfaces."
const String specWatertight =
    'Die Hülle muss geschlossen sein – keine offenen Löcher, keine '
    'Rückseiten.';

/// „Meshes cannot be 0 thickness and must have some volume."
const String specVolume =
    'Kein Teil darf null Dicke haben; alles braucht Volumen.';

/// „Meshes must be in quads where possible."
const String specQuads =
    'Vierecke, wo möglich – keine N-Gons.';

/// „A vertex can not be influenced by more than 4 bones or joints."
const int specMaxInfluences = 4;

// ----------------------------------------------------------------
// Starre Accessoires – avatar/rigid-accessories/specifications.md
// ----------------------------------------------------------------

/// „Rigid accessories can't exceed 4k triangles." Dazu: „Rigid
/// accessories must be a single mesh."
const int specAccessoryTriangles = 4000;

// ----------------------------------------------------------------
// Figurenkörper – avatar/character-bodies/specifications.md
// ----------------------------------------------------------------

/// Das Dreiecksbudget je Marktplatz-Teil eines R15-Körpers. Der
/// Körper wird beim Hochladen in sechs Teile zerlegt.
const Map<String, int> specBodyPartTriangles = {
  'DynamicHead': 4000,
  'Torso': 1750,
  'LeftArm': 1248,
  'RightArm': 1248,
  'LeftLeg': 1248,
  'RightLeg': 1248,
};

/// Die Summe daraus – die Zahl, die in der Tabelle als „Total" steht.
const int specBodyTotalTriangles = 10742;

/// Die 15 Mesh-Objekte eines Figurenkörpers, so benannt, wie der
/// Importer sie erwartet (Endung `_Geo`).
const List<String> specBodyMeshNames = [
  'Head_Geo',
  'UpperTorso_Geo',
  'LowerTorso_Geo',
  'LeftUpperArm_Geo',
  'LeftLowerArm_Geo',
  'LeftHand_Geo',
  'RightUpperArm_Geo',
  'RightLowerArm_Geo',
  'RightHand_Geo',
  'LeftUpperLeg_Geo',
  'LeftLowerLeg_Geo',
  'LeftFoot_Geo',
  'RightUpperLeg_Geo',
  'RightLowerLeg_Geo',
  'RightFoot_Geo',
];

/// Die Knochen-Hierarchie eines Standard-R15-Rigs, Elternteil →
/// Kinder. Genau so steht sie in der Spezifikation.
const Map<String, List<String>> specR15Hierarchy = {
  'Root': ['HumanoidRootNode'],
  'HumanoidRootNode': ['LowerTorso'],
  'LowerTorso': ['UpperTorso', 'LeftUpperLeg', 'RightUpperLeg'],
  'UpperTorso': ['Head', 'LeftUpperArm', 'RightUpperArm'],
  'LeftUpperArm': ['LeftLowerArm'],
  'LeftLowerArm': ['LeftHand'],
  'RightUpperArm': ['RightLowerArm'],
  'RightLowerArm': ['RightHand'],
  'LeftUpperLeg': ['LeftLowerLeg'],
  'LeftLowerLeg': ['LeftFoot'],
  'RightUpperLeg': ['RightLowerLeg'],
  'RightLowerLeg': ['RightFoot'],
};

/// Der oberste Knochen. Er muss im Weltursprung sitzen und darf keine
/// Gewichtung tragen.
const String specRootBone = 'Root';

/// Der Knochen darunter.
///
/// **Achtung, die Dokumentation ist hier nicht einheitlich.** Für den
/// Import eines Figurenkörpers nennen sowohl
/// `avatar/character-bodies/specifications.md` als auch das
/// Prüfwerkzeug (`art/characters/validation-tool.md`: „Root and
/// HumanoidRootNode bones exist") diesen Namen. Die Anleitung zum
/// Export einer Avatar-Animation aus Maya
/// (`art/characters/export-avatar-animations-from-maya.md`) führt an
/// derselben Stelle `HumanoidRootPart` auf. Diese App exportiert
/// Figurenkörper, also gilt hier der erste Fall – beim Einlesen wird
/// weiterhin beides erkannt.
const String specRootNode = 'HumanoidRootNode';

/// „Export your character model in an I-Pose, A-Pose, or T-Pose for
/// the best Studio compatibility."
const List<String> specAllowedPoses = ['I-Pose', 'A-Pose', 'T-Pose'];

/// „The LowerTorso and Root bone or joint position must be set to
/// 0, 0, 0."
const String specOriginRule =
    'Root und LowerTorso müssen im Ursprung liegen.';

// ----------------------------------------------------------------
// Texturen – art/modeling/texture-specifications.md
// ----------------------------------------------------------------

/// „Maximum Texture Resolution — Roblox supports up to 1024×1024
/// pixel spaces for texture maps." (Abschnitt „UV mapping".)
const int specMaxTexture = 1024;

/// „Textures for Marketplace assets can't exceed 2048x2048
/// resolution." Die schärfere Grenze oben gilt für die UV-Fläche;
/// diese hier ist die harte Obergrenze beim Hochladen.
const int specMarketplaceTexture = 2048;

/// Die flache Liste der R15-Gelenke, aus der Hierarchie abgeleitet –
/// ohne den obersten `Root`, weil er kein Gelenk der Figur ist.
///
/// Abgeleitet statt abgeschrieben: So kann die Liste nicht von der
/// Hierarchie abweichen.
List<String> get specR15Joints {
  final out = <String>[];
  void walk(String bone) {
    if (bone != specRootBone) out.add(bone);
    for (final child in specR15Hierarchy[bone] ?? const <String>[]) {
      walk(child);
    }
  }

  walk(specRootBone);
  return out;
}
