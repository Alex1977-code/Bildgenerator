/// Die Wartegrafik, während ein Modell rechnet – je Modell ein
/// eigenes Motiv.
///
/// Warum überhaupt Motive statt eines Balkens: Anbieter wie OpenAI,
/// Gemini und Stability liefern keine Zwischenbilder, sie antworten
/// erst mit dem fertigen Ergebnis. Ein Fortschrittsbalken wäre dort
/// gelogen. Gezeigt wird deshalb eine Zeichnung, die entsteht – und
/// zwar eine, die zum arbeitenden Modell passt: Nano Banana ist eine
/// Banane, hinter Stable Diffusion steht das Hugging-Face-Gesicht,
/// der eigene Server ist ein Chip.
///
/// Der Zeichner selbst entsteht Punkt für Punkt, und auf seiner
/// Leinwand verdichtet sich eine zweite Punktwolke langsam zu einem
/// Bild. Beides steht still, sobald es gesetzt ist: Eine Fassung mit
/// dauernd kreisenden Punkten war unangenehm anzusehen.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/models.dart';

/// Ein Strich des Motivs – eine Folge von Stützpunkten in einem
/// Koordinatensystem von -1 bis 1, x nach rechts, y nach unten.
class MotifStroke {
  const MotifStroke(this.points, {this.closed = false, this.weight = 1.0});

  final List<Offset> points;

  /// Ob der letzte Punkt wieder mit dem ersten verbunden wird.
  final bool closed;

  /// Wie viele Punkte dieser Strich im Verhältnis zu seiner Länge
  /// bekommt. Über 1 für Stellen, die dichter wirken sollen (Augen,
  /// Kerne), unter 1 für lange ruhige Konturen.
  final double weight;
}

/// Ein vollständiges Motiv: der Zeichner und das Bild, das auf seiner
/// Leinwand entsteht.
class WaitMotif {
  const WaitMotif({
    required this.id,
    required this.name,
    required this.note,
    required this.artist,
    required this.canvas,
  });

  /// Kennung für Tests und für den Vergleich beim Neuzeichnen.
  final String id;

  /// Wer da zeichnet, im Klartext – steht unter der Grafik.
  final String name;

  /// Ein Satz dazu, warum gerade dieses Motiv.
  final String note;

  /// Der Zeichner. Punkte in -1 bis 1.
  final List<MotifStroke> artist;

  /// Das Bild auf der Leinwand. Eigenes Koordinatensystem, ebenfalls
  /// -1 bis 1; die Fläche wird beim Zeichnen in den Rahmen gelegt.
  final List<MotifStroke> canvas;
}

/// Verteilt [count] Punkte gleichmäßig über die Striche – in der
/// Reihenfolge der Striche, damit das Aufbauen wie Zeichnen aussieht.
///
/// Gewichtet wird nach Länge mal [MotifStroke.weight]: Ein doppelt so
/// langer Strich bekommt doppelt so viele Punkte, ein Auge mit
/// weight 2 doppelt so dichte.
List<Offset> samplePoints(List<MotifStroke> strokes, int count) {
  if (count <= 0 || strokes.isEmpty) return const [];
  // Länge je Strich, schon gewichtet.
  final laengen = <double>[];
  var gesamt = 0.0;
  for (final stroke in strokes) {
    var laenge = 0.0;
    final pts = stroke.points;
    for (var i = 0; i + 1 < pts.length; i++) {
      laenge += (pts[i + 1] - pts[i]).distance;
    }
    if (stroke.closed && pts.length > 2) {
      laenge += (pts.first - pts.last).distance;
    }
    // Ein Strich aus einem einzigen Punkt hat keine Länge, soll aber
    // trotzdem gezeichnet werden (Pupille, Nabel).
    final gewichtet = math.max(laenge, 1e-6) * stroke.weight;
    laengen.add(gewichtet);
    gesamt += gewichtet;
  }
  final out = <Offset>[];
  for (var s = 0; s < strokes.length; s++) {
    final anteil = laengen[s] / gesamt;
    final n = math.max(1, (count * anteil).round());
    out.addAll(_alongStroke(strokes[s], n));
  }
  return out;
}

List<Offset> _alongStroke(MotifStroke stroke, int n) {
  final pts = [
    ...stroke.points,
    if (stroke.closed && stroke.points.length > 2) stroke.points.first,
  ];
  if (pts.length == 1) return List.filled(n, pts.first);
  final segmente = <double>[];
  var gesamt = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    final d = (pts[i + 1] - pts[i]).distance;
    segmente.add(d);
    gesamt += d;
  }
  if (gesamt <= 0) return List.filled(n, pts.first);
  final out = <Offset>[];
  for (var k = 0; k < n; k++) {
    // Punkte liegen mittig im jeweiligen Abschnitt, damit Anfang und
    // Ende nicht doppelt besetzt sind.
    final ziel = gesamt * (k + 0.5) / n;
    var gelaufen = 0.0;
    for (var i = 0; i < segmente.length; i++) {
      if (gelaufen + segmente[i] >= ziel || i == segmente.length - 1) {
        final t = segmente[i] <= 0 ? 0.0 : (ziel - gelaufen) / segmente[i];
        out.add(Offset.lerp(pts[i], pts[i + 1], t.clamp(0.0, 1.0))!);
        break;
      }
      gelaufen += segmente[i];
    }
  }
  return out;
}

/// Ein Kreisbogen als Stützpunkte – die Grundform fast aller Motive.
List<Offset> _arc(double cx, double cy, double rx, double ry,
    double fromDeg, double toDeg,
    {int steps = 24}) {
  final out = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final deg = fromDeg + (toDeg - fromDeg) * i / steps;
    final rad = deg * math.pi / 180;
    out.add(Offset(cx + rx * math.cos(rad), cy + ry * math.sin(rad)));
  }
  return out;
}

List<Offset> _circle(double cx, double cy, double r, {int steps = 28}) =>
    _arc(cx, cy, r, r, 0, 360, steps: steps);

// ----------------------------------------------------------------
// Die Bilder, die auf der Leinwand entstehen
// ----------------------------------------------------------------

/// Ein Häuschen mit Sonne – das Bild, das die Banane malt.
const List<MotifStroke> _bildHaus = [
  MotifStroke([
    Offset(-0.55, 0.55),
    Offset(-0.55, -0.05),
    Offset(0.0, -0.5),
    Offset(0.55, -0.05),
    Offset(0.55, 0.55),
  ], closed: true),
  MotifStroke([
    Offset(-0.15, 0.55),
    Offset(-0.15, 0.15),
    Offset(0.15, 0.15),
    Offset(0.15, 0.55),
  ]),
];

/// Berge mit Sonne – für das Hugging Face.
const List<MotifStroke> _bildBerge = [
  MotifStroke([
    Offset(-0.8, 0.5),
    Offset(-0.3, -0.35),
    Offset(0.05, 0.15),
    Offset(0.3, -0.15),
    Offset(0.8, 0.5),
  ], closed: true),
  MotifStroke([Offset(-0.8, 0.5), Offset(0.8, 0.5)], weight: 0.6),
];

/// Ein Bildnis – für die Rosette.
final List<MotifStroke> _bildPortrait = [
  MotifStroke(_circle(0, -0.2, 0.32)),
  MotifStroke([
    Offset(-0.55, 0.62),
    Offset(-0.4, 0.2),
    Offset(0.4, 0.2),
    Offset(0.55, 0.62),
  ]),
];

/// Ein Würfel in Schrägsicht – für Chip und 3D.
const List<MotifStroke> _bildWuerfel = [
  MotifStroke([
    Offset(-0.45, -0.15),
    Offset(0.0, -0.45),
    Offset(0.45, -0.15),
    Offset(0.45, 0.35),
    Offset(0.0, 0.6),
    Offset(-0.45, 0.35),
  ], closed: true),
  MotifStroke([Offset(-0.45, -0.15), Offset(0.0, 0.1), Offset(0.45, -0.15)]),
  MotifStroke([Offset(0.0, 0.1), Offset(0.0, 0.6)]),
];

/// Ein Segelboot – für den Chip. Ein eigenes Bild, damit nicht zwei
/// Motive dieselbe Leinwand malen.
const List<MotifStroke> _bildBoot = [
  MotifStroke([
    Offset(-0.6, 0.3),
    Offset(0.6, 0.3),
    Offset(0.4, 0.6),
    Offset(-0.4, 0.6),
  ], closed: true),
  MotifStroke([Offset(0.0, 0.3), Offset(0.0, -0.6)]),
  MotifStroke([
    Offset(0.05, -0.55),
    Offset(0.5, 0.22),
    Offset(0.05, 0.22),
  ], closed: true),
  MotifStroke([
    Offset(-0.05, -0.45),
    Offset(-0.4, 0.22),
    Offset(-0.05, 0.22),
  ], closed: true),
];

/// Ein Stern – für den Blitz, der schnell fertig ist.
final List<MotifStroke> _bildStern = [
  MotifStroke([
    for (var i = 0; i < 10; i++)
      Offset(
        math.cos((-90 + i * 36) * math.pi / 180) * (i.isEven ? 0.55 : 0.24),
        math.sin((-90 + i * 36) * math.pi / 180) * (i.isEven ? 0.55 : 0.24),
      ),
  ], closed: true),
];

// ----------------------------------------------------------------
// Die Zeichner
// ----------------------------------------------------------------

/// Die Banane – Nano Banana.
///
/// Die Sichel entsteht aus zwei Bögen um denselben Mittelpunkt: dem
/// äußeren Bauch und dem inneren Rücken. Die erste Fassung nahm zwei
/// Bögen mit verschobenen Mittelpunkten und legte sie beide über die
/// untere Hälfte – herausgekommen ist ein Lächeln, keine Banane.
final List<MotifStroke> _banane = [
  MotifStroke([
    ..._arc(0, -0.35, 0.85, 0.85, 160, 20),
    ..._arc(0, -0.35, 0.58, 0.58, 20, 160),
  ], closed: true),
  // Der Stiel an der linken Spitze.
  MotifStroke([
    Offset(-0.72, -0.1),
    Offset(-0.85, -0.24),
    Offset(-0.8, -0.4),
  ], weight: 1.6),
];

/// Das umarmende Gesicht – Hugging Face, wo die Stable-Diffusion-
/// Gewichte liegen.
final List<MotifStroke> _huggingFace = [
  MotifStroke(_circle(0, -0.05, 0.6)),
  // Zwei Augen.
  MotifStroke(_circle(-0.22, -0.18, 0.09, steps: 12), weight: 2.0),
  MotifStroke(_circle(0.22, -0.18, 0.09, steps: 12), weight: 2.0),
  // Ein breites Lächeln.
  MotifStroke(_arc(0, -0.02, 0.3, 0.26, 25, 155), weight: 1.4),
  // Die zwei Hände links und rechts.
  MotifStroke(_arc(-0.72, 0.05, 0.24, 0.3, 60, 300), weight: 1.2),
  MotifStroke(_arc(0.72, 0.05, 0.24, 0.3, 240, 480), weight: 1.2),
];

/// Eine sechsblättrige Rosette – für GPT-Image.
final List<MotifStroke> _rosette = [
  for (var i = 0; i < 6; i++)
    MotifStroke(_arc(
      math.cos(i * 60 * math.pi / 180) * 0.34,
      math.sin(i * 60 * math.pi / 180) * 0.34,
      0.36,
      0.36,
      0,
      360,
      steps: 20,
    )),
];

/// Ein Chip mit Beinchen – die eigene Grafikkarte.
final List<MotifStroke> _chip = [
  const MotifStroke([
    Offset(-0.5, -0.5),
    Offset(0.5, -0.5),
    Offset(0.5, 0.5),
    Offset(-0.5, 0.5),
  ], closed: true),
  const MotifStroke([
    Offset(-0.22, -0.22),
    Offset(0.22, -0.22),
    Offset(0.22, 0.22),
    Offset(-0.22, 0.22),
  ], closed: true),
  for (var i = 0; i < 4; i++) ...[
    MotifStroke([
      Offset(-0.5, -0.3 + i * 0.2),
      Offset(-0.72, -0.3 + i * 0.2),
    ], weight: 1.6),
    MotifStroke([
      Offset(0.5, -0.3 + i * 0.2),
      Offset(0.72, -0.3 + i * 0.2),
    ], weight: 1.6),
  ],
];

/// Ein Blitz – die Modelle, die in vier Schritten fertig sind.
const List<MotifStroke> _blitz = [
  MotifStroke([
    Offset(0.18, -0.78),
    Offset(-0.42, 0.06),
    Offset(-0.04, 0.06),
    Offset(-0.22, 0.78),
    Offset(0.42, -0.1),
    Offset(0.04, -0.1),
  ], closed: true),
];

/// Ein Würfel – der 3D-Bereich.
final List<MotifStroke> _wuerfel = [
  const MotifStroke([
    Offset(-0.6, -0.25),
    Offset(0.0, -0.6),
    Offset(0.6, -0.25),
    Offset(0.6, 0.45),
    Offset(0.0, 0.8),
    Offset(-0.6, 0.45),
  ], closed: true),
  const MotifStroke([
    Offset(-0.6, -0.25),
    Offset(0.0, 0.1),
    Offset(0.6, -0.25),
  ]),
  const MotifStroke([Offset(0.0, 0.1), Offset(0.0, 0.8)]),
];

const WaitMotif _neutral = WaitMotif(
  id: 'wuerfel',
  name: '3D-Modell',
  note: 'Die 3D-Dienste liefern keine Zwischenbilder – hier entsteht '
      'stattdessen ein Würfel.',
  artist: [],
  canvas: [],
);

/// Alle Motive, über ihre Kennung erreichbar.
final Map<String, WaitMotif> waitMotifs = {
  'banane': WaitMotif(
    id: 'banane',
    name: 'Nano Banana',
    note: 'Nano Banana malt ein Häuschen, während dein Bild entsteht.',
    artist: _banane,
    canvas: _bildHaus,
  ),
  'hugging': WaitMotif(
    id: 'hugging',
    name: 'Hugging Face',
    note: 'Hinter Stable Diffusion steht Hugging Face – hier malt es '
        'eine Berglandschaft.',
    artist: _huggingFace,
    canvas: _bildBerge,
  ),
  'rosette': WaitMotif(
    id: 'rosette',
    name: 'GPT-Image',
    note: 'Die Rosette zeichnet ein Bildnis, während GPT-Image rechnet.',
    artist: _rosette,
    canvas: _bildPortrait,
  ),
  'chip': WaitMotif(
    id: 'chip',
    name: 'Eigene GPU',
    note: 'Der Chip malt ein Segelboot – gerechnet wird auf deiner '
        'eigenen Karte.',
    artist: _chip,
    canvas: _bildBoot,
  ),
  'blitz': WaitMotif(
    id: 'blitz',
    name: 'Schnellmodell',
    note: 'Vier Schritte, dann ist das Bild da – der Blitz zeichnet '
        'einen Stern.',
    artist: _blitz,
    canvas: _bildStern,
  ),
  'wuerfel': WaitMotif(
    id: 'wuerfel',
    name: '3D-Modell',
    note: _neutral.note,
    artist: _wuerfel,
    canvas: _bildWuerfel,
  ),
};

/// Das Motiv zum gewählten Bild-Modell.
///
/// Die Zuordnung ist nicht bloß Dekoration: Sie sagt, wer gerade
/// rechnet. Wer zwischen Anbietern wechselt, sieht das an der Grafik,
/// bevor er auf die Beschriftung schaut.
WaitMotif waitMotifFor(GenProvider provider, String model) {
  final id = model.toLowerCase();
  switch (provider) {
    case GenProvider.openai:
      return waitMotifs['rosette']!;
    case GenProvider.gemini:
      return waitMotifs['banane']!;
    case GenProvider.stability:
      return waitMotifs['hugging']!;
    case GenProvider.selfhost:
      // Die Modelle ohne Guidance sind in vier Schritten fertig – das
      // ist der Blitz. Alles andere rechnet lange genug für den Chip.
      return id.contains('turbo') || id.contains('schnell')
          ? waitMotifs['blitz']!
          : waitMotifs['chip']!;
  }
}

/// Das Motiv für den 3D-Bereich. Der eigene Rechner bekommt den Chip,
/// alles andere den Würfel.
WaitMotif waitMotifForThreeD(String provider) =>
    provider == 'local' || provider == 'selfhost'
        ? waitMotifs['chip']!
        : waitMotifs['wuerfel']!;
