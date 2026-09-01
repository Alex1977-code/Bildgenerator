/// Die Beleuchtung und der Hintergrund der 3D-Ansichten.
///
/// Beides stand bisher fest im Painter: eine Lichtrichtung, eine
/// einzige Hintergrundfarbe. Für den Viewer reichte das; bei der
/// Anprobe nicht. Dort geht es darum zu beurteilen, ob ein Gegenstand
/// an der Figur sitzt – und auf einer gleichmäßig grauen Fläche, bei
/// einem Licht, das nie wandert, sieht man weder, wo oben ist, noch
/// wo der Gegenstand aufhört und die Figur anfängt.
///
/// Diese Datei liefert beides als reine Daten: benannte
/// Lichtaufstellungen und die Maße des Bodenschattens. Reine
/// Rechnung, kein Bildschirm – deshalb prüfbar.
library;

import 'dart:math' as math;

/// Eine Lichtaufstellung: Richtung, aus der das Licht kommt, plus die
/// Grundhelligkeit.
///
/// Die Richtung zeigt **zum Licht hin** (nicht in Ausbreitungs-
/// richtung) und steht im Kamerasystem: x nach rechts, y nach oben,
/// z zum Betrachter. So lässt sie sich unmittelbar gegen die gedrehte
/// Normale rechnen.
class StudioLight {
  const StudioLight({
    required this.id,
    required this.label,
    required this.hint,
    required this.x,
    required this.y,
    required this.z,
    this.ambient = 0.42,
  });

  final String id;
  final String label;

  /// Wofür diese Aufstellung taugt.
  final String hint;

  final double x, y, z;

  /// Wie hell die abgewandte Seite bleibt. Ohne Grundhelligkeit wäre
  /// die Schattenseite schwarz und man sähe dort gar nichts mehr.
  final double ambient;

  /// Die Richtung auf Länge 1 – so gerechnet, wie der Painter sie
  /// braucht.
  (double, double, double) get direction {
    final len = math.sqrt(x * x + y * y + z * z);
    if (len <= 0) return (0, 0, 1);
    return (x / len, y / len, z / len);
  }
}

/// Die Aufstellungen zur Auswahl. Die erste ist die bisherige – wer
/// nichts umstellt, sieht, was er bisher sah.
const List<StudioLight> studioLights = [
  StudioLight(
    id: 'studio',
    label: 'Studio (von vorn oben)',
    hint: 'Der ruhige Standard: Licht schräg von vorn oben, weiche '
        'Schatten, alles gut lesbar.',
    x: -0.26,
    y: 0.44,
    z: 0.86,
  ),
  StudioLight(
    id: 'oben',
    label: 'Von oben',
    hint: 'Zeigt Aufsicht und Silhouette – gut für Hüte, Helme und '
        'alles, was auf dem Kopf sitzt.',
    x: 0.0,
    y: 1.0,
    z: 0.25,
    ambient: 0.38,
  ),
  StudioLight(
    id: 'seite',
    label: 'Von der Seite',
    hint: 'Streiflicht: Wölbungen und Kanten treten hervor – so fällt '
        'auf, ob ein Teil in der Figur steckt.',
    x: 0.92,
    y: 0.24,
    z: 0.3,
    ambient: 0.3,
  ),
  StudioLight(
    id: 'gegen',
    label: 'Gegenlicht',
    hint: 'Licht von hinten: Der Umriss steht scharf – zum Prüfen, ob '
        'der Gegenstand über die Figur hinausragt.',
    x: -0.5,
    y: 0.35,
    z: -0.79,
    ambient: 0.5,
  ),
  StudioLight(
    id: 'flach',
    label: 'Ohne Schatten',
    hint: 'Gleichmäßig ausgeleuchtet – zeigt die reinen Farben, ohne '
        'dass Licht sie verfälscht.',
    x: 0.0,
    y: 0.0,
    z: 1.0,
    ambient: 0.95,
  ),
];

/// Die Aufstellung zu einer Kennung; unbekannt heißt Studio.
StudioLight studioLightById(String id) => studioLights.firstWhere(
      (l) => l.id == id,
      orElse: () => studioLights.first,
    );

/// Wo der Bodenschatten liegt und wie groß er ist.
///
/// Der Schatten ist keine Physik, sondern eine Lesehilfe: eine weiche
/// Ellipse unter dem Modell. Ohne sie schwebt alles im Nichts, und
/// gerade bei der Anprobe fehlt dann der Bezug, wie hoch etwas sitzt.
class GroundShadow {
  const GroundShadow(this.centerX, this.centerY, this.radiusX, this.radiusY);

  final double centerX, centerY, radiusX, radiusY;

  bool get isEmpty => radiusX <= 0 || radiusY <= 0;
}

/// Rechnet den Bodenschatten aus der Ausdehnung des Modells und der
/// aktuellen Ansicht.
///
/// [extent] ist die halbe Diagonale des Modells, [scale] die Zahl, mit
/// der der Painter Weltmaße in Bildpunkte umrechnet, [tiltX] die
/// Neigung der Kamera. Wird von oben geschaut, wird die Ellipse
/// runder; steht die Kamera waagerecht, wird sie flach – so wie ein
/// Schatten auf dem Boden aussieht.
GroundShadow groundShadowFor({
  required double width,
  required double height,
  required double extent,
  required double scale,
  required double tiltX,
  double zoom = 1.0,
}) {
  if (extent <= 0 || scale <= 0) return const GroundShadow(0, 0, 0, 0);
  final radiusX = extent * scale * 0.62;
  // Die Höhe der Ellipse folgt der Neigung: waagerechte Kamera =
  // flacher Strich, Blick von oben = runder Fleck.
  final neigung = math.sin(tiltX.abs()).clamp(0.0, 1.0);
  final radiusY = radiusX * (0.12 + 0.55 * neigung);
  final centerY = height / 2 + extent * scale * 0.72;
  return GroundShadow(width / 2, centerY, radiusX, radiusY);
}
