/// Der Posen-Zusatz für Text→3D – T-Pose oder A-Pose.
///
/// Figuren lassen sich nur dann brauchbar rekonstruieren und riggen,
/// wenn sie mit ausgestreckten Armen dastehen. Die App hängt den
/// Zusatz deshalb bei eingeschaltetem Rigging selbst an den Prompt.
///
/// Zwei Dinge müssen dabei stimmen, und beide gingen schon schief:
///
/// * **Nicht doppelt.** Steht die T-Pose schon im Prompt, kostet der
///   Zusatz nur Platz und verschiebt die Gewichtung – Text→3D-Modelle
///   wichten frühe Begriffe stärker.
/// * **Die Länge zählt nach dem Zusammenbauen.** Tripo misst den
///   fertigen String. Ein Prompt mit 958 Zeichen plus 121 Zeichen
///   Zusatz ergab 1079 und riss die Grenze von 1024 – obwohl das
///   Eingabefeld deutlich darunter lag.
///
/// **Zwei Posen, zwei Empfänger.** Für den Roblox-Importer ist die
/// T-Pose richtig. Für Roblox' Auto Setup ist es die A-Pose: Im
/// ersten echten Lauf wurden die waagerechten Arme der T-Pose vom
/// Segmentierer dem Kopf und dem Rumpf zugeschlagen – heraus kam ein
/// „UpperTorso" von 4,38 Studs Breite. Arme in 45° hängen frei und
/// sind als Arme erkennbar. Roblox nennt A und T gleichwertig; für
/// den Segmentierer ist A eindeutiger.
library;

/// Welche Pose an den Prompt gehängt wird.
enum PoseKind {
  /// Arme waagerecht – so verlangt es der Roblox-Importer.
  tPose,

  /// Arme in etwa 45° hängend – so liest Auto Setup sie als Arme.
  aPose,
}

/// Was an den Prompt gehängt wird, wenn eine T-Pose gebraucht wird.
const String tPoseSuffix =
    'full body character in T-pose, arms stretched out horizontally, '
    'legs slightly apart, facing forward, neutral expression';

/// Dasselbe für die A-Pose.
///
/// Drei Angaben müssen darin stehen, sonst kommt die Pose nicht an:
/// **A-Pose**, **45 Grad nach unten** und **gestreckte Arme**. Das
/// letzte fehlte anfangs – „hanging" allein lässt angewinkelte Arme
/// zu, und die sind für den Segmentierer so unbrauchbar wie
/// waagerechte.
const String aPoseSuffix =
    'full body character in A-pose, arms straight and angled 45 degrees '
    'down, legs slightly apart, facing forward';

/// Der Zusatz zur gewählten Pose.
String poseSuffix(PoseKind kind) =>
    kind == PoseKind.aPose ? aPoseSuffix : tPoseSuffix;

/// Erkennt eine T-Pose-Angabe im Prompt – auch als „T Pose",
/// „t-pose" oder „T_Pose".
final RegExp _tPosePattern = RegExp(r't[\s\-_]?pose', caseSensitive: false);

/// Dasselbe für die A-Pose.
final RegExp _aPosePattern = RegExp(r'a[\s\-_]?pose', caseSensitive: false);

/// Ob der Prompt die T-Pose schon selbst mitbringt.
bool promptHasTPose(String prompt) => _tPosePattern.hasMatch(prompt);

/// Ob der Prompt **irgendeine** Pose schon nennt.
///
/// Geprüft wird auf beide: Steht „A-pose" im Text und die App hängt
/// die T-Pose an, widersprechen sich die beiden Angaben, und das
/// Modell bekommt weder das eine noch das andere sauber.
bool promptHasPose(String prompt) =>
    _tPosePattern.hasMatch(prompt) || _aPosePattern.hasMatch(prompt);

/// Der Prompt, wie er tatsächlich an den Anbieter geht.
///
/// [wanted] ist true, sobald Rigging oder der T-Pose-Schalter aktiv
/// ist. Steht die Pose schon im Text, bleibt er unverändert.
String withTPose(String prompt, {required bool wanted}) =>
    withPose(prompt, wanted: wanted, kind: PoseKind.tPose);

/// Der Prompt mit der gewählten Pose.
///
/// Nennt der Text schon eine Pose – gleich welche –, bleibt er
/// unverändert.
String withPose(String prompt,
    {required bool wanted, PoseKind kind = PoseKind.tPose}) {
  final trimmed = prompt.trim();
  if (!wanted || trimmed.isEmpty) return trimmed;
  if (promptHasPose(trimmed)) return trimmed;
  return '$trimmed, ${poseSuffix(kind)}';
}

/// Wie viele Zeichen der Zusatz beim aktuellen Stand kostet – 0, wenn
/// nichts angehängt wird.
int tPoseExtraChars(String prompt, {required bool wanted}) =>
    poseExtraChars(prompt, wanted: wanted);

/// Dasselbe für eine frei gewählte Pose.
int poseExtraChars(String prompt,
        {required bool wanted, PoseKind kind = PoseKind.tPose}) =>
    withPose(prompt, wanted: wanted, kind: kind).length -
    prompt.trim().length;
