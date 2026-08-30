/// Der T-Pose-Zusatz für Text→3D.
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
library;

/// Was an den Prompt gehängt wird, wenn eine T-Pose gebraucht wird.
const String tPoseSuffix =
    'full body character in T-pose, arms stretched out horizontally, '
    'legs slightly apart, facing forward, neutral expression';

/// Erkennt eine T-Pose-Angabe im Prompt – auch als „T Pose",
/// „t-pose" oder „T_Pose".
final RegExp _tPosePattern = RegExp(r't[\s\-_]?pose', caseSensitive: false);

/// Ob der Prompt die T-Pose schon selbst mitbringt.
bool promptHasTPose(String prompt) => _tPosePattern.hasMatch(prompt);

/// Der Prompt, wie er tatsächlich an den Anbieter geht.
///
/// [wanted] ist true, sobald Rigging oder der T-Pose-Schalter aktiv
/// ist. Steht die Pose schon im Text, bleibt er unverändert.
String withTPose(String prompt, {required bool wanted}) {
  final trimmed = prompt.trim();
  if (!wanted || trimmed.isEmpty) return trimmed;
  if (promptHasTPose(trimmed)) return trimmed;
  return '$trimmed, $tPoseSuffix';
}

/// Wie viele Zeichen der Zusatz beim aktuellen Stand kostet – 0, wenn
/// nichts angehängt wird.
int tPoseExtraChars(String prompt, {required bool wanted}) =>
    withTPose(prompt, wanted: wanted).length - prompt.trim().length;
