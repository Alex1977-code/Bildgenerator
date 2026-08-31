/// Rig-Typ aus dem Netz erkennen.
///
/// Vor dem Rigging muss feststehen, welches Skelett gebaut wird: zwei
/// Beine, vier, sechs, ein Fisch oder ein Fahrzeug. Bisher war das eine
/// reine Einstellung – wer sie vergaß, bekam ein Zweibeiner-Skelett in
/// ein Pferd gebaut.
///
/// Erkannt wird an vier Messwerten, die sich ohne Bildverstehen aus den
/// Punkten ablesen lassen:
///
/// * **Bodenkontakt-Inseln.** Im untersten Sechstel der Höhe wird ein
///   Raster über Grundriss (x × z) gelegt und in zusammenhängende
///   Flächen zerlegt. Zwei Inseln = zwei Beine, vier = vier Beine bzw.
///   vier Räder, sechs = Insekt.
/// * **Rad oder Bein.** Ein Rad ist in Fahrtrichtung viel länger als
///   quer (an dieser Höhe schneidet man fast den ganzen Durchmesser
///   an), ein Bein ist rund. Das trennt das Auto vom Vierbeiner –
///   beides hat vier Punkte am Boden.
/// * **Aufrechtheit.** Höhe geteilt durch die größere Grundfläche:
///   Ein Mensch steht (> 1), ein Hund liegt darunter, eine Schlange
///   ganz unten.
/// * **Schlankheit und Flachheit.** Eine Schlange ist lang und dünn,
///   ein Fisch ist seitlich zusammengedrückt.
///
/// Alles bleibt ein Vorschlag: [guessRigType] liefert eine Rangliste
/// mit Begründung, und die Auswahl steht weiter offen. Wo nichts
/// zusammenpasst – ein Haus, ein Fass –, sagt die Liste das ehrlich,
/// statt zu raten.
library;

import 'dart:typed_data';

/// Eine zusammenhängende Fläche am Boden (Fuß, Huf, Rad, Sockel).
class GroundIsland {
  const GroundIsland({
    required this.centerX,
    required this.centerZ,
    required this.extentX,
    required this.extentZ,
    required this.depthShare,
    required this.cells,
  });

  /// Mitte der Insel, jeweils als Anteil der Modellbreite bzw. -tiefe
  /// vom Modellmittelpunkt aus (−0,5 … +0,5).
  final double centerX, centerZ;

  /// Ausdehnung in Modelleinheiten.
  final double extentX, extentZ;

  /// Anteil der Modelltiefe, den die Insel einnimmt – ein Rad ist ein
  /// kleiner Fleck, ein liegender Schlangenkörper nicht.
  final double depthShare;

  /// Belegte Rasterzellen – Maß für die Größe der Fläche.
  final int cells;

  /// Länge in Fahrtrichtung geteilt durch Breite. Ein Rad liegt
  /// deutlich über 1, ein Bein bei etwa 1.
  double get lengthRatio => extentX <= 0 ? 0 : extentZ / extentX;

  /// Sieht aus wie der Anschnitt eines Rades: lang in Fahrtrichtung,
  /// schmal quer – und dabei ein Fleck, nicht das halbe Modell. Ohne
  /// die zweite Bedingung zählte auch der lang hingestreckte Körper
  /// einer Schlange als Rad.
  bool get wheelLike => lengthRatio >= 1.8 && depthShare < 0.5;
}

/// Die am Netz gemessenen Formmerkmale.
class RigShape {
  const RigShape({
    required this.width,
    required this.height,
    required this.depth,
    required this.ground,
    required this.armSpan,
    required this.bodyProportion,
    required this.bodyBottom,
    required this.points,
  });

  /// Ausdehnung der Bounding Box.
  final double width, height, depth;

  /// Bodenkontakt-Inseln, von vorn (+z) nach hinten sortiert.
  final List<GroundIsland> ground;

  /// Größte Breite der oberen Hälfte, geteilt durch die Breite des
  /// Rumpfes. Über etwa 1,8 stehen Arme oder Flügel ab (T-Pose,
  /// gespreizte Schwingen); ein Fass liegt bei 1.
  final double armSpan;

  /// Der Körper über den Beinen: Tiefe geteilt durch Höhe. Ein Mensch
  /// ist dort hoch und schmal (deutlich unter 1), ein Vogel oder ein
  /// Vierbeiner trägt einen waagerechten Rumpf (über 1).
  final double bodyProportion;

  /// Unterkante des zusammenhängenden Körpers als Anteil der Höhe –
  /// bei einem Menschen etwa 0,5 (Schritt), bei einem Auto dort, wo
  /// die Karosserie beginnt.
  final double bodyBottom;

  /// Zahl der ausgewerteten Punkte. Unter ein paar hundert taugt keine
  /// der Messungen etwas.
  final int points;

  /// Höhe im Verhältnis zur größeren Grundfläche.
  double get uprightness {
    final base = width > depth ? width : depth;
    return base <= 0 ? 0 : height / base;
  }

  /// Längste Achse geteilt durch die zweitlängste.
  double get elongation {
    final dims = [width, height, depth]..sort();
    return dims[1] <= 0 ? 0 : dims[2] / dims[1];
  }

  /// Wie flach das Modell quer zur Längsachse ist (Fisch: klein).
  double get lateralFlatness {
    final other = height < depth ? height : depth;
    return other <= 0 ? 1 : width / other;
  }

  /// Inseln, die eher ein Rad als ein Bein sind.
  int get wheelish => ground.where((i) => i.wheelLike).length;
}

/// Ein Vorschlag samt Begründung.
class RigTypeGuess {
  const RigTypeGuess(this.type, this.confidence, this.reason);

  /// Wert aus `rigTypeOptions`.
  final String type;

  /// 0 … 1. Ab 0,6 zeigt die Oberfläche den Vorschlag als gesetzt an,
  /// darunter als Vermutung.
  final double confidence;

  /// Ein deutscher Satz mit den Zahlen, die dazu geführt haben.
  final String reason;

  bool get solid => confidence >= 0.6;
}

/// Misst die Formmerkmale eines Netzes.
///
/// [positionLists] sind POSITION-Accessoren (x, y, z je Punkt);
/// y = oben. Das Modell muss stehen – ein auf der Seite liegender
/// Import wird als liegend gemessen, und genau das soll er auch, weil
/// der Rigger ebenfalls y = oben annimmt.
RigShape measureRigShape(Iterable<Float32List> positionLists) {
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  var points = 0;
  for (final positions in positionLists) {
    for (var i = 0; i + 2 < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
      points++;
    }
  }
  final width = points == 0 ? 0.0 : maxX - minX;
  final height = points == 0 ? 0.0 : maxY - minY;
  final depth = points == 0 ? 0.0 : maxZ - minZ;
  if (points == 0 || height <= 0 || width <= 0 || depth <= 0) {
    return RigShape(
      width: width,
      height: height,
      depth: depth,
      ground: const [],
      armSpan: 1,
      bodyProportion: 1,
      bodyBottom: 0,
      points: points,
    );
  }

  // Quadratische Rasterzellen. Ein Raster mit fester Spaltenzahl je
  // Achse hätte bei einer T-Pose (breit, aber flach) Zellen von
  // 4 cm × 3 mm – ein Bein zerfiele darin in ein Dutzend Streifen,
  // und ein rundes Bein sähe aus wie ein Rad. Die Zellengröße richtet
  // sich deshalb nach der größeren Grundflächen-Achse.
  //
  // 64 Zellen auf diese Achse: Zusammen mit dem Verdicken um eine
  // Zelle in [_islands] werden Lücken bis etwa 3 % der Modellgröße
  // geschlossen (Löcher in einem grob unterteilten Fuß), während
  // Beine, die weiter auseinanderstehen, getrennt bleiben. Bei einem
  // Vogel mit gespreizten Flügeln ist das der Unterschied zwischen
  // zwei Beinen und einem verschmolzenen Klumpen.
  final cell = (width > depth ? width : depth) / 64;
  final gx = (width / cell).ceil().clamp(2, 160);
  final gz = (depth / cell).ceil().clamp(2, 160);
  final floor = Uint8List(gx * gz);

  // Höhenprofil je Band: Punktzahl (für die Rumpf-Unterkante) und
  // Ausdehnung (für Armspanne und Körperform).
  const bins = 40;
  final rowCells = List<int>.filled(bins, 0);
  final rowMinX = List<double>.filled(bins, double.infinity);
  final rowMaxX = List<double>.filled(bins, double.negativeInfinity);
  final rowMinZ = List<double>.filled(bins, double.infinity);
  final rowMaxZ = List<double>.filled(bins, double.negativeInfinity);
  final cx = (minX + maxX) / 2;
  final yCut = minY + height / 6;
  for (final positions in positionLists) {
    for (var i = 0; i + 2 < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      if (y <= yCut) {
        final ix = ((x - minX) / width * gx).floor().clamp(0, gx - 1);
        final iz = ((z - minZ) / depth * gz).floor().clamp(0, gz - 1);
        floor[iz * gx + ix] = 1;
      }
      final bin = ((y - minY) / height * bins).floor().clamp(0, bins - 1);
      rowCells[bin]++;
      if (x < rowMinX[bin]) rowMinX[bin] = x;
      if (x > rowMaxX[bin]) rowMaxX[bin] = x;
      if (z < rowMinZ[bin]) rowMinZ[bin] = z;
      if (z > rowMaxZ[bin]) rowMaxZ[bin] = z;
    }
  }

  final ground = _islands(floor, gx, gz, width, depth);
  ground.sort((a, b) => b.centerZ.compareTo(a.centerZ));
  final bodyBottom = _bodyBottom(rowCells, bins);

  // Rumpfbreite aus dem Bauchband (25–45 % der Höhe): dort steht bei
  // jeder Bauform der Körper und sonst nichts.
  var torso = 0.0;
  for (var b = (bins * 0.25).floor(); b < (bins * 0.45).ceil(); b++) {
    if (rowCells[b] == 0) continue;
    final half = (rowMaxX[b] - rowMinX[b]) / 2;
    if (half > torso) torso = half;
  }
  var upper = 0.0;
  for (var b = (bins * 0.55).floor(); b < bins; b++) {
    if (rowCells[b] == 0) continue;
    final half = [
      (rowMaxX[b] - cx).abs(),
      (cx - rowMinX[b]).abs(),
    ].reduce((a, c) => a > c ? a : c);
    if (half > upper) upper = half;
  }

  // Körper über den Beinen: waagerecht (Vogel, Vierbeiner) oder
  // aufrecht (Mensch)?
  var bodyDepth = 0.0;
  final firstBodyBin = (bodyBottom * bins).floor().clamp(0, bins - 1);
  for (var b = firstBodyBin; b < bins; b++) {
    if (rowCells[b] == 0) continue;
    final span = rowMaxZ[b] - rowMinZ[b];
    if (span > bodyDepth) bodyDepth = span;
  }
  final bodyHeight = (1 - bodyBottom) * height;

  return RigShape(
    width: width,
    height: height,
    depth: depth,
    ground: ground,
    armSpan: torso <= 0 ? 1 : upper / torso,
    bodyProportion: bodyHeight <= 0 ? 1 : bodyDepth / bodyHeight,
    bodyBottom: bodyBottom,
    points: points,
  );
}

/// Unterkante des Rumpfes: Von unten nach oben die erste Höhe, ab der
/// deutlich mehr Punkte liegen als in den Beinen darunter. Bei einem
/// Menschen ist das der Schritt, beim Auto die Karosserie.
double _bodyBottom(List<int> rowCells, int bins) {
  var densest = 0;
  for (final c in rowCells) {
    if (c > densest) densest = c;
  }
  if (densest == 0) return 0;
  for (var b = 0; b < bins; b++) {
    if (rowCells[b] >= densest * 0.5) return (b + 0.5) / bins;
  }
  return 0;
}

/// Zusammenhängende Flächen im Grundriss.
///
/// Gezählt wird auf einem um eine Zelle **verdickten** Abbild und
/// gemessen auf dem echten. Der Grund: In einer GLB liegen Punkte nur
/// auf der Oberfläche, bei grober Unterteilung mit Lücken dazwischen.
/// Ohne das Verdicken zerfiele ein Fuß in ein Dutzend Flecken, und aus
/// zwei Beinen würden zwanzig „Beine".
List<GroundIsland> _islands(
    Uint8List grid, int gx, int gz, double width, double depth) {
  final thick = Uint8List(gx * gz);
  for (var z = 0; z < gz; z++) {
    for (var x = 0; x < gx; x++) {
      if (grid[z * gx + x] == 0) continue;
      for (var dz = -1; dz <= 1; dz++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, nz = z + dz;
          if (nx < 0 || nx >= gx || nz < 0 || nz >= gz) continue;
          thick[nz * gx + nx] = 1;
        }
      }
    }
  }

  // Zusammenhangskomponenten des verdickten Abbilds beschriften.
  final label = Int32List(gx * gz)..fillRange(0, gx * gz, -1);
  final stack = <int>[];
  var count = 0;
  for (var start = 0; start < thick.length; start++) {
    if (thick[start] == 0 || label[start] >= 0) continue;
    final id = count++;
    stack
      ..clear()
      ..add(start);
    label[start] = id;
    while (stack.isNotEmpty) {
      final cellIndex = stack.removeLast();
      final x = cellIndex % gx, z = cellIndex ~/ gx;
      for (final (dx, dz) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx, nz = z + dz;
        if (nx < 0 || nx >= gx || nz < 0 || nz >= gz) continue;
        final next = nz * gx + nx;
        if (thick[next] == 0 || label[next] >= 0) continue;
        label[next] = id;
        stack.add(next);
      }
    }
  }
  if (count == 0) return [];

  // Ausdehnung und Schwerpunkt aus den echten Zellen.
  final cells = List<int>.filled(count, 0);
  final sumX = List<int>.filled(count, 0), sumZ = List<int>.filled(count, 0);
  final minCx = List<int>.filled(count, 1 << 30);
  final maxCx = List<int>.filled(count, -1);
  final minCz = List<int>.filled(count, 1 << 30);
  final maxCz = List<int>.filled(count, -1);
  for (var cellIndex = 0; cellIndex < grid.length; cellIndex++) {
    if (grid[cellIndex] == 0) continue;
    final id = label[cellIndex];
    final x = cellIndex % gx, z = cellIndex ~/ gx;
    cells[id]++;
    sumX[id] += x;
    sumZ[id] += z;
    if (x < minCx[id]) minCx[id] = x;
    if (x > maxCx[id]) maxCx[id] = x;
    if (z < minCz[id]) minCz[id] = z;
    if (z > maxCz[id]) maxCz[id] = z;
  }

  var largest = 0;
  for (final c in cells) {
    if (c > largest) largest = c;
  }
  final result = <GroundIsland>[];
  for (var id = 0; id < count; id++) {
    // Ein einzelner Fleck ist Rauschen (ein Zipfel des Umhangs, die
    // Schwanzspitze), keine Standfläche – ebenso alles, was neben der
    // größten Fläche verschwindet.
    if (cells[id] < 2 || cells[id] < largest * 0.15) continue;
    result.add(GroundIsland(
      centerX: (sumX[id] / cells[id] + 0.5) / gx - 0.5,
      centerZ: (sumZ[id] / cells[id] + 0.5) / gz - 0.5,
      extentX: (maxCx[id] - minCx[id] + 1) / gx * width,
      extentZ: (maxCz[id] - minCz[id] + 1) / gz * depth,
      depthShare: (maxCz[id] - minCz[id] + 1) / gz,
      cells: cells[id],
    ));
  }
  return result;
}

/// Wie viele Gruppen bilden die Inseln entlang der Fahrtrichtung? Vier
/// Beine stehen in zwei Paaren (vorn/hinten), vier Räder auf zwei
/// Achsen – ein Zweibeiner hat beide Füße in einer Gruppe.
int _zGroups(List<GroundIsland> islands) {
  if (islands.isEmpty) return 0;
  final zs = [for (final i in islands) i.centerZ]..sort();
  var groups = 1;
  for (var i = 1; i < zs.length; i++) {
    if (zs[i] - zs[i - 1] > 0.18) groups++;
  }
  return groups;
}

String _n(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

/// Schätzt den Rig-Typ. Bestes Ergebnis zuerst; eine leere Liste
/// bedeutet, dass sich keine Form abzeichnet.
List<RigTypeGuess> guessRigType(RigShape shape) {
  if (shape.points < 200 || shape.height <= 0) return const [];
  final out = <RigTypeGuess>[];
  final legs = shape.ground.length;
  final zGroups = _zGroups(shape.ground);
  final upright = shape.uprightness;

  // Fahrzeug: mindestens zwei radförmige Standflächen auf zwei
  // Gruppen hintereinander, und das Ganze breiter als hoch.
  if (shape.wheelish >= 2 && zGroups >= 2 && upright < 1.1) {
    final confidence = shape.wheelish >= 4 ? 0.85 : 0.7;
    out.add(RigTypeGuess(
      'vehicle',
      confidence,
      '${shape.wheelish} radförmige Standflächen auf $zGroups Achsen – '
          'in Fahrtrichtung deutlich länger als quer, wie der '
          'Anschnitt eines Rades.',
    ));
  }

  // Schlange: lang, dünn, flach am Boden, ohne getrennte Standflächen.
  if (upright < 0.4 && shape.elongation >= 3.0 && legs <= 2) {
    out.add(RigTypeGuess(
      'snake',
      shape.elongation >= 5 ? 0.8 : 0.6,
      'Langgestreckt (${_n(shape.elongation)}-mal so lang wie dick) und '
          'flach am Boden, ohne getrennte Standflächen.',
    ));
  }

  // Fisch: seitlich zusammengedrückt, keine Beine.
  if (shape.lateralFlatness < 0.5 && legs <= 2 && upright < 1.2) {
    out.add(RigTypeGuess(
      'fish',
      0.6,
      'Seitlich zusammengedrückt (Breite nur das '
          '${_n(shape.lateralFlatness)}-Fache der Höhe) und ohne Beine – '
          'die Form eines Fisches.',
    ));
  }

  // Insekt/Mehrbeiner: sechs und mehr Standflächen.
  if (legs >= 6 && shape.wheelish < 2) {
    out.add(RigTypeGuess(
      'insect',
      legs >= 6 && legs <= 10 ? 0.8 : 0.6,
      '$legs getrennte Standflächen – mehr als vier Beine.',
    ));
  }

  // Vierbeiner: vier Standflächen in zwei Gruppen hintereinander,
  // Rumpf waagerecht.
  if (legs >= 3 && legs <= 5 && zGroups >= 2 && shape.wheelish < 2) {
    out.add(RigTypeGuess(
      'quadruped',
      legs == 4 && upright < 1.0 ? 0.85 : 0.6,
      '$legs Standflächen in $zGroups Gruppen hintereinander und ein '
          'waagerechter Rumpf (Höhe ${_n(upright)}-mal die Grundfläche).',
    ));
  }

  // Vogel und Zweibeiner haben beide zwei Beine nebeneinander.
  // Getrennt werden sie am Körper darüber: Ein Mensch ist dort hoch
  // und schmal, ein Vogel trägt einen waagerechten Rumpf mit
  // abstehenden Flügeln.
  if (legs == 2 && zGroups == 1) {
    final waagerecht = shape.bodyProportion >= 1.0;
    final fluegel = shape.armSpan >= 1.8;
    if (waagerecht && fluegel && upright < 1.6) {
      out.add(RigTypeGuess(
        'bird',
        0.6,
        'Zwei Beine, darüber ein waagerechter Rumpf (${_n(shape.bodyProportion)}-'
            'mal so tief wie hoch) und seitlich abstehende Flächen – '
            'gespreizte Flügel.',
      ));
    }
    if (upright >= 1.1 && !waagerecht) {
      out.add(RigTypeGuess(
        'biped',
        upright >= 1.5 ? 0.85 : 0.65,
        'Zwei Standflächen nebeneinander und aufrecht '
            '(${_n(upright)}-mal so hoch wie breit)'
            '${fluegel ? ', die Arme stehen seitlich ab (T-Pose)' : ''}.',
      ));
    }
  }

  out.sort((a, b) => b.confidence.compareTo(a.confidence));
  return out;
}

/// Warum nichts erkannt wurde – ein Satz für die Oberfläche.
String rigDetectFallback(RigShape shape) {
  if (shape.points < 200) {
    return 'Zu wenige Punkte im Netz, um die Form zu vermessen.';
  }
  final legs = shape.ground.length;
  return 'Keine der Formen passt: ${legs == 0 ? 'keine' : '$legs'} '
      'getrennte Standflächen, Höhe ${_n(shape.uprightness)}-mal die '
      'Grundfläche. Bei einem Gebäude oder einem Gegenstand ist das '
      'richtig so – die bewegt kein Skelett. Sonst den Typ selbst '
      'wählen.';
}
