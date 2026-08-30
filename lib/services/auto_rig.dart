/// Eigenes Auto-Rigging: baut ein Standard-Skelett (Heuristik aus der
/// Bounding Box) direkt in eine GLB-Datei ein – komplett lokal, ohne
/// API. Die Skin-Gewichte entstehen über den Abstand jedes Vertex zu
/// den Knochensegmenten (die zwei nächsten Knochen werden gemischt).
///
/// Es gibt Skelett-Vorlagen für Zweibeiner (Mensch/Roboter/Fantasy in
/// T-Pose), Vierbeiner, Insekten/Mehrbeiner, Vögel (gespreizte Flügel),
/// Schlangen und Fische. Konvention: y = oben, Blick/Kopf nach +z.
/// Bei Zweibeinern wird die tatsächliche Blickrichtung zusätzlich aus
/// der Geometrie geschätzt ([estimateFrontSign]) – Bild→3D-Dienste wie
/// Stability liefern Figuren mit dem Gesicht nach -z, dann werden
/// Fußspitzen und Animations-Biegerichtungen gespiegelt.
/// Texturen, Materialien und alle übrigen Daten der GLB bleiben
/// unverändert; es kommen nur Skelett-Knoten, ein Skin und
/// JOINTS_0/WEIGHTS_0-Attribute hinzu.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Was die Beschreibung zeigen muss, damit sich ein Modell dieses
/// Typs überhaupt riggen lässt.
///
/// Ein Skelett kann nur an Gliedmaßen andocken, die im Netz auch als
/// getrennte Volumen vorhanden sind. Arme, die am Körper anliegen,
/// verschmelzen bei der Rekonstruktion mit dem Rumpf – danach ist
/// nichts mehr zu trennen, weder vom Auto-Rigger dieser App noch von
/// Tripos. Deshalb gehört der Hinweis in den Prompt, nicht in die
/// Nachbearbeitung.
const rigTypePromptRules = <String, String>{
  'biped': 'Zwei Beine und zwei Arme, deutlich vom Rumpf abgesetzt und '
      'nicht am Körper anliegend; Hände und Füße als eigene Volumen '
      'erkennbar. Ein Umhang oder ein Rock, der Beine oder Arme '
      'verdeckt, macht die Figur unriggbar.',
  'quadruped': 'Vier Beine, alle vier sichtbar und einzeln getrennt, '
      'Kopf am Halsansatz abgesetzt, Schwanz frei. Keine sitzende, '
      'liegende oder zusammengekauerte Haltung – stehend auf allen '
      'vieren.',
  'insect': 'Sechs Beine, paarweise getrennt und vom Körper abstehend; '
      'der Körper in Kopf, Brust und Hinterleib gegliedert. Fühler und '
      'Flügel dick genug, dass sie Volumen haben.',
  'bird': 'Zwei gespreizte Flügel, zwei Beine, Schwanzfedern als '
      'eigenes Volumen. Angelegte Flügel verschmelzen mit dem Rumpf.',
  'snake': 'Langgestreckter Körper ohne Gliedmaßen, gleichmäßig dick, '
      'nicht eingerollt und nicht verknotet – sonst lässt sich die '
      'Gelenkkette nicht sauber legen.',
  'fish': 'Rumpf mit deutlich abgesetzten Flossen und Schwanzflosse, '
      'seitlich symmetrisch. Flossen mit sichtbarer Dicke, nicht als '
      'hauchdünne Fahnen.',
  'vehicle': 'Räder als eigene runde Volumen, vom Chassis abgesetzt und '
      'vollständig sichtbar – die App erkennt Achsen und Radzahl an '
      'der bodennahen Geometrie.',
};

/// Verfügbare Figurtypen: (Wert, deutsche Bezeichnung).
const rigTypeOptions = [
  ('biped', 'Mensch / Roboter / Fantasy (2 Beine)'),
  ('quadruped', 'Vierbeiner (Hund, Pferd, Katze …)'),
  ('insect', 'Insekt / Mehrbeiner'),
  ('bird', 'Vogel (gespreizte Flügel)'),
  ('snake', 'Schlange / ohne Beine'),
  ('fish', 'Fisch'),
  ('vehicle', 'Fahrzeug (Räder automatisch)'),
];

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x, y, z;
}

class _Joint {
  const _Joint(this.name, this.parent, this.position);
  final String name;
  final int parent; // -1 = Wurzel
  final _Vec3 position;
}

class _Bone {
  const _Bone(this.joint, this.from, this.to,
      [this.radius = 1.0, this.fromJoint = -1, this.toJoint = -1]);
  final int joint; // Index des steuernden Gelenks
  final _Vec3 from;
  final _Vec3 to;

  /// Relativer Einflussradius: dickere Körperteile (Kopf, Rumpf)
  /// „gewinnen“ gegen dünne (Arme), damit z. B. Haare zum Kopf gehören
  /// und nicht zum nächstgelegenen Armknochen.
  final double radius;

  /// Gelenk-Anker der Endpunkte (für den Rig-Editor): verschobene
  /// Gelenke ziehen ihre Knochen mit. -1 = fester Punkt (Spitzen
  /// behalten ihren Versatz relativ zu [fromJoint]).
  final int fromJoint;
  final int toJoint;
}

/// Aus dem Netz vermessene Körper-Proportionen einer stehenden Figur –
/// macht das Skelett unabhängig von festen Standard-Prozenten (wichtig
/// für Chibi-/Comic-Figuren mit großem Kopf und kurzen Beinen).
class _BodyProfile {
  const _BodyProfile({
    required this.crotchY,
    required this.neckY,
    required this.legX,
    this.shoulderY,
    this.armInnerX,
    this.armOuterX,
  });

  final double crotchY; // Beinansatz (absolute y-Koordinate)
  final double neckY; // Halsansatz (absolute y-Koordinate)
  final double legX; // Abstand der Beinmitte von der Körpermitte

  /// Schulterhöhe aus erkannten, seitlich abstehenden Armen (absolute
  /// y-Koordinate) – zuverlässiger als die Halsschätzung, besonders
  /// bei Frisuren, die den Kopf breit umschließen. Null, wenn keine
  /// getrennten Arme erkennbar sind (z. B. echte T-Pose).
  final double? shoulderY;

  /// Wo der Arm den Rumpf verlässt und wo er endet – jeweils als
  /// Abstand von der Körpermitte. Gemessen an den Inseln des
  /// Arm-Bands; null, wenn keine freistehenden Arme erkennbar sind.
  ///
  /// Vorher standen dafür feste Anteile der Modellbreite. Bei einer
  /// T-Pose **ist** die Modellbreite aber die Armspanne, und ein
  /// Zehntel davon liegt mitten im Rumpf – die Schulter landete
  /// entsprechend zu weit innen.
  final double? armInnerX;
  final double? armOuterX;
}

/// Vermisst die Figur über ein Höhenprofil: Beinspalt (zwei getrennte
/// Cluster unten), engste Stelle zwischen Rumpf und Kopf (Hals) und
/// mittlerer Beinabstand. Liefert null, wenn nichts erkennbar ist.
_BodyProfile _analyzeBipedProfile(
    List<(Map<String, dynamic>, Float32List)> primitives,
    double minX, double maxX, double minY, double maxY) {
  const bins = 64;
  const xBins = 48;
  final height = maxY - minY;
  final width = maxX - minX;
  if (height <= 0 || width <= 0) {
    return _BodyProfile(
        crotchY: minY + 0.48 * height,
        neckY: minY + 0.84 * height,
        legX: 0.06 * width);
  }
  final cx = (minX + maxX) / 2;
  final hasLeft = List<bool>.filled(bins, false);
  final hasRight = List<bool>.filled(bins, false);
  final hasCenter = List<bool>.filled(bins, false);
  final halfWidth = List<double>.filled(bins, 0);
  final legXSum = List<double>.filled(bins, 0);
  final legXCount = List<int>.filled(bins, 0);
  // 2D-Belegungsraster (Höhe × Breite): erkennt getrennte „Inseln“ je
  // Zeile – seitlich abstehende Arme (Arm–Rumpf–Arm = 3 Inseln) und
  // feine Beinspalte, die das grobe Mittelband übersieht.
  final occ = Uint8List(bins * xBins);
  for (final (_, positions) in primitives) {
    for (var i = 0; i < positions.length; i += 3) {
      final x = positions[i] - cx;
      final y = positions[i + 1];
      var bin = ((y - minY) / height * bins).floor();
      if (bin < 0) bin = 0;
      if (bin >= bins) bin = bins - 1;
      if (x.abs() > halfWidth[bin]) halfWidth[bin] = x.abs();
      legXSum[bin] += x.abs();
      legXCount[bin]++;
      var xbin = ((positions[i] - minX) / width * xBins).floor();
      if (xbin < 0) xbin = 0;
      if (xbin >= xBins) xbin = xBins - 1;
      occ[bin * xBins + xbin] = 1;
    }
  }
  double binY(int bin) => minY + (bin + 0.5) / bins * height;

  // Körperbreite statt Modellbreite. Bei einer T-Pose ist die
  // Modellbreite die Armspanne – ein daran bemessenes Mittelband ist
  // breiter als der Beinspalt, und der Spalt wird nie als frei
  // erkannt. Gemessen wird deshalb in Hüfthöhe, wo keine Arme sind.
  var bodyHalf = 0.0;
  for (var bin = (bins * 0.25).floor(); bin < (bins * 0.45).floor(); bin++) {
    if (halfWidth[bin] > bodyHalf) bodyHalf = halfWidth[bin];
  }
  if (bodyHalf <= 0) bodyHalf = 0.5 * width;
  final centerBand = 0.12 * bodyHalf;
  final middleCell = xBins ~/ 2;
  final centerCells = (centerBand / (width / xBins)).ceil();
  for (var bin = 0; bin < bins; bin++) {
    for (var x = 0; x < xBins; x++) {
      if (occ[bin * xBins + x] == 0) continue;
      if (x < middleCell - centerCells) {
        hasLeft[bin] = true;
      } else if (x > middleCell + centerCells) {
        hasRight[bin] = true;
      } else {
        hasCenter[bin] = true;
      }
    }
  }

  /// Abstand einer Rasterzelle von der Körpermitte.
  double cellX(int cell) => (minX + (cell + 0.5) * width / xBins - cx).abs();

  // Inseln einer Zeile: zusammenhängende belegte x-Zellen; Lücken von
  // einer Zelle werden überbrückt (Rauschen), ab zwei leeren Zellen
  // beginnt eine neue Insel.
  List<(int, int)> islandsOf(int bin) {
    final islands = <(int, int)>[];
    var start = -1;
    var gap = 0;
    for (var x = 0; x < xBins; x++) {
      if (occ[bin * xBins + x] != 0) {
        if (start < 0) start = x;
        gap = 0;
      } else if (start >= 0) {
        gap++;
        if (gap > 1) {
          islands.add((start, x - gap));
          start = -1;
          gap = 0;
        }
      }
    }
    if (start >= 0) islands.add((start, xBins - 1 - gap));
    return islands;
  }

  // Beinspalt über die Inseln: Vom Boden aufwärts zerfällt jede Zeile
  // in genau zwei Inseln, solange die Beine getrennt sind. Wo sie
  // wieder zu einer werden, sitzt der Beinansatz.
  //
  // Das grobe Mittelband (hasLeft/hasRight/hasCenter) taugt dafür
  // nicht: Seine Breite hängt an der Körperbreite, der Beinspalt ist
  // oft schmaler, und schon eine Zelle Bein im Band lässt die Zeile
  // als „nicht geteilt" durchgehen. Gemessen an einer Figur im Mantel
  // fand es nur noch den Spalt zwischen den Schuhen – das Skelett
  // wurde dadurch ins untere Zehntel gequetscht.
  var crotchBin = -1;
  if (islandsOf(0).length == 2 || islandsOf(1).length == 2) {
    var top = -1;
    for (var bin = 0; bin < (bins * 0.7).floor(); bin++) {
      if (islandsOf(bin).length == 2) {
        top = bin;
      } else if (top >= 0) {
        break;
      }
    }
    // Ein Spalt von nur zwei, drei Zeilen ist der Abstand zwischen den
    // Schuhspitzen, kein Beinansatz.
    if (top >= (bins * 0.06).ceil()) crotchBin = top;
  }
  bool split(int bin) => hasLeft[bin] && hasRight[bin] && !hasCenter[bin];
  if (crotchBin < 0) {
    for (var bin = 0; bin < (bins * 0.7).floor(); bin++) {
      if (split(bin)) {
        var top = bin;
        while (top + 1 < bins && split(top + 1)) {
          top++;
        }
        if (top - bin >= 2) crotchBin = top;
        break;
      }
    }
  }
  if (crotchBin < 0) {
    // Feiner Beinspalt über die Inseln (z. B. eng stehende Stiefel,
    // deren Spalt schmaler als das Mittelband ist). Nur akzeptieren,
    // wenn der geteilte Bereich ganz unten beginnt – sonst wären es
    // Arme, keine Beine.
    bool legRow(int bin) => islandsOf(bin).length >= 2;
    for (var bin = 0; bin < (bins * 0.2).floor(); bin++) {
      if (legRow(bin)) {
        var top = bin;
        while (top + 1 < bins && legRow(top + 1)) {
          top++;
        }
        if (top - bin >= 2 && top < (bins * 0.7).floor()) crotchBin = top;
        break;
      }
    }
  }
  final crotchY =
      crotchBin >= 0 ? binY(crotchBin) : minY + 0.48 * height;

  // Arm-Band: Zeilen mit mindestens 3 Inseln (Arm–Rumpf–Arm), bei
  // denen die MITTLERE Insel die breiteste ist (der Rumpf) – das
  // schließt Bein-plus-Stoff-Zeilen aus, wo die äußeren Inseln (Beine)
  // breiter wären. Das unterste Band liefert die Schulterhöhe.
  bool armRow(int bin) {
    final islands = islandsOf(bin);
    if (islands.length < 3) return false;
    final centerCell = xBins ~/ 2;
    var centerWidth = 0, widest = 0;
    for (final (s, e) in islands) {
      final islandWidth = e - s + 1;
      if (islandWidth > widest) widest = islandWidth;
      if (s <= centerCell && centerCell <= e) centerWidth = islandWidth;
    }
    return centerWidth >= 4 && centerWidth == widest;
  }

  var armTopBin = -1;
  var armBottomBin = -1;
  final armSearchFrom =
      crotchBin >= 0 ? crotchBin + 1 : (bins * 0.2).floor();
  for (var bin = armSearchFrom; bin < bins - 1; bin++) {
    if (armRow(bin) && armRow(bin + 1)) {
      armBottomBin = bin;
      var top = bin + 1;
      while (top + 1 < bins && armRow(top + 1)) {
        top++;
      }
      armTopBin = top;
      break;
    }
  }
  // Nur verwenden, wenn die Arme über eine deutliche Höhe frei stehen
  // (mindestens 10 % der Figur). Ein kurzes Band sind nur die Hände
  // herabhängender, mit dem Rumpf verschmolzener Arme – die Schulter
  // läge dann weit darüber (dort greift die Halsmessung).
  // Zweiter Weg, wenn die Inseln nichts hergeben: über die Breite.
  //
  // Bei einer Figur im Mantel füllt der Stoff die Achsel – im Umriss
  // sind Arm und Rumpf dann nicht getrennt, und die Insel-Suche findet
  // nichts. Dass dort Arme sind, sieht man trotzdem: Genau auf
  // Armhöhe ist die Figur weit breiter als ihr Rumpf.
  // Ein Band von nur ein, zwei Zeilen ist Rauschen im Raster, kein
  // Arm – dann denselben Weg gehen wie ohne jeden Fund.
  final minArmBins = (bins * 0.10).ceil();
  if (armTopBin - armBottomBin + 1 < minArmBins) {
    armTopBin = -1;
    armBottomBin = -1;
  }
  if (armTopBin < 0) {
    for (var bin = (bins * 0.35).floor(); bin < bins - 1; bin++) {
      if (halfWidth[bin] > bodyHalf * 1.35 &&
          halfWidth[bin + 1] > bodyHalf * 1.35) {
        armBottomBin = bin;
        var top = bin + 1;
        while (top + 1 < bins && halfWidth[top + 1] > bodyHalf * 1.35) {
          top++;
        }
        armTopBin = top;
        break;
      }
    }
  }

  final armSpanOk =
      armTopBin >= 0 && (armTopBin - armBottomBin + 1) >= minArmBins;
  // Die Mitte des Bands ist die Achse des Arms; die Oberkante war die
  // Oberseite des Ärmels und lag damit zu hoch.
  final shoulderY =
      armSpanOk ? binY((armBottomBin + armTopBin) ~/ 2) : null;

  // Wo der Arm den Rumpf verlässt und wo er endet: die äußere Kante
  // der mittleren Insel (Rumpf) und die äußere Kante der äußersten.
  // Über alle Zeilen des Bands gemittelt, damit ein einzelner
  // Ausreißer nichts verschiebt.
  double? armInnerX, armOuterX;
  if (armSpanOk) {
    var innerSum = 0.0, outerSum = 0.0;
    var rows = 0;
    for (var bin = armBottomBin; bin <= armTopBin; bin++) {
      final islands = islandsOf(bin);
      if (islands.length < 3) continue;
      var inner = 0.0, outer = 0.0;
      for (final (start, end) in islands) {
        if (start <= middleCell && middleCell <= end) {
          inner = math.max(cellX(start), cellX(end));
        }
        outer = math.max(outer, math.max(cellX(start), cellX(end)));
      }
      if (inner <= 0 || outer <= inner) continue;
      innerSum += inner;
      outerSum += outer;
      rows++;
    }
    if (rows > 0) {
      armInnerX = innerSum / rows;
      armOuterX = outerSum / rows;
    }
    // Wieder über die Breite, wenn die Inseln nichts hergaben: Der Arm
    // beginnt am Rumpfrand und endet an der breitesten Stelle.
    if (armInnerX == null) {
      var reach = 0.0;
      for (var bin = armBottomBin; bin <= armTopBin; bin++) {
        if (halfWidth[bin] > reach) reach = halfWidth[bin];
      }
      if (reach > bodyHalf) {
        armInnerX = bodyHalf;
        armOuterX = reach;
      }
    }
  }

  // Hals: schmalste Stelle zwischen Rumpf-Oberkante und der breitesten
  // Kopf-/Haarstelle (darüber wird der Kopf wieder schmaler – dort
  // liegt kein Hals). Bei gleicher Breite gewinnt die höchste Stelle.
  final searchFrom =
      (((crotchY - minY) / height + 0.18) * bins).floor().clamp(0, bins - 1);
  final searchTo = (bins * 0.95).floor();
  var peakBin = -1;
  var peakWidth = 0.0;
  for (var bin = searchFrom; bin < searchTo; bin++) {
    if (legXCount[bin] == 0) continue;
    if (halfWidth[bin] >= peakWidth) {
      peakWidth = halfWidth[bin];
      peakBin = bin;
    }
  }
  var neckBin = -1;
  var minWidth = double.infinity;
  for (var bin = searchFrom; bin <= peakBin; bin++) {
    if (legXCount[bin] == 0) continue;
    if (halfWidth[bin] <= minWidth) {
      minWidth = halfWidth[bin];
      neckBin = bin;
    }
  }
  final distinct =
      peakWidth > 0 && (peakWidth - minWidth) / peakWidth > 0.15;
  final neckY = (neckBin >= 0 && distinct)
      ? binY(neckBin)
      : crotchY + 0.62 * (maxY - crotchY);

  // Mittlerer Beinabstand aus der unteren Beinhälfte.
  var legSum = 0.0;
  var legCount = 0;
  final legTop = crotchBin >= 0 ? crotchBin : (bins * 0.3).floor();
  for (var bin = 1; bin < legTop; bin++) {
    legSum += legXSum[bin];
    legCount += legXCount[bin];
  }
  final legX = legCount > 0
      ? (legSum / legCount).clamp(0.03 * width, 0.25 * width)
      : 0.06 * width;

  return _BodyProfile(
      crotchY: crotchY,
      neckY: neckY,
      legX: legX,
      shoulderY: shoulderY,
      armInnerX: armInnerX,
      armOuterX: armOuterX);
}

/// Schätzt die Blickrichtung einer stehenden Figur aus der Geometrie:
/// +1 = Gesicht Richtung +z (Rig-Konvention), -1 = Gesicht Richtung -z
/// (so liefern es z. B. Stability-Bild→3D-Modelle). Zwei an echten
/// Modellen vermessene Signale werden kombiniert: Füße/Schuhe ragen
/// nach vorn (unterstes Viertel gegenüber dem Rumpf) und der Kopf sitzt
/// vor der Brustmitte. Klare Fälle liegen bei |Signal| ≥ 0,2 der
/// Modelltiefe; bei schwachem Signal (symmetrische Geometrie,
/// Fahrzeuge, Reliefs) bleibt es bei +1.
int estimateFrontSign(List<Float32List> positionLists) {
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (final positions in positionLists) {
    for (var i = 0; i < positions.length; i += 3) {
      final y = positions[i + 1], z = positions[i + 2];
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }
  }
  final height = maxY - minY, depth = maxZ - minZ;
  if (height <= 0 || depth <= 0) return 1;
  // Gemessen wird am Fuß, nicht am Rumpf.
  //
  // Vorher stand hier „Füße gegen Rumpf" und „Kopf gegen Brust". Beide
  // Bezugspunkte sind unzuverlässig: Ein Bauch wandert nach vorn, eine
  // Kapuze nach hinten – bei einer Figur mit beidem zeigten beide
  // Signale in die falsche Richtung, und die Figur verbeugte sich nach
  // hinten. Der Fuß gegen das Schienbein darüber ist unabhängig
  // davon, was der Oberkörper macht.
  final sums = Float64List(4);
  final counts = Int32List(4);
  // 0 = Fuß, 1 = Schienbein, 2 = Brust, 3 = Kopf.
  const bands = [(0.0, 0.08), (0.12, 0.28), (0.45, 0.70), (0.75, 1.01)];
  var footFront = double.negativeInfinity, footBack = double.infinity;
  for (final positions in positionLists) {
    for (var i = 0; i < positions.length; i += 3) {
      final f = (positions[i + 1] - minY) / height;
      final z = positions[i + 2];
      for (var k = 0; k < bands.length; k++) {
        if (f >= bands[k].$1 && f < bands[k].$2) {
          sums[k] += z;
          counts[k]++;
        }
      }
      if (f < bands[0].$2) {
        if (z > footFront) footFront = z;
        if (z < footBack) footBack = z;
      }
    }
  }
  if (counts[0] == 0 || counts[1] == 0) return 1;
  final shin = sums[1] / counts[1];
  // Zwei Signale, beide am Fuß: seine Mitte liegt vor dem Schienbein,
  // und er ragt nach vorn weiter über das Schienbein hinaus als nach
  // hinten (Zehen gegen Ferse).
  final footShift = (sums[0] / counts[0] - shin) / depth;
  final toeShift = footFront.isFinite && footBack.isFinite
      ? ((footFront - shin) - (shin - footBack)) / depth
      : 0.0;
  var signal = footShift * 2 + toeShift;
  // Kopf gegen Brust nur noch als Stichentscheid bei unklarem Fuß –
  // Kapuzen, Helme und Frisuren machen dieses Signal unzuverlässig.
  if (signal.abs() < 0.05 && counts[2] > 0 && counts[3] > 0) {
    signal = (sums[3] / counts[3] - sums[2] / counts[2]) / depth;
  }
  return signal < -0.02 ? -1 : 1;
}

/// Ein erkanntes Rad bzw. Radpaar (eine Achse) des Fahrzeug-Rigs.
class _WheelAxle {
  const _WheelAxle({
    required this.z,
    required this.y,
    required this.radius,
    required this.paired,
    required this.xOff,
  });

  final double z; // Achsposition (absolut; Fahrtrichtung +z)
  final double y; // Radmitte (absolut)
  final double radius; // geschätzter Radradius
  final bool paired; // Radpaar links/rechts oder Einzelrad in der Mitte
  final double xOff; // Radabstand von der Fahrzeugmitte (nur bei paired)
}

/// Standard-Achsen (Auto mit 4 Rädern), wenn nichts erkennbar ist.
List<_WheelAxle> _defaultAxles(double minY, double maxY, double w,
    double d, double cz) {
  final h = maxY - minY;
  return [
    for (final sz in [1.0, -1.0])
      _WheelAxle(
        z: cz + sz * 0.32 * d,
        y: minY + 0.16 * h,
        radius: 0.16 * h,
        paired: true,
        xOff: 0.38 * w,
      ),
  ];
}

/// Erkennt Achsen und Räder aus der bodennahen Geometrie: Histogramm
/// der tiefsten Vertices entlang der Fahrzeuglänge (z) – dort steht
/// praktisch nur, was den Boden berührt. Zusammenhängende Bereiche sind
/// Achsen; liegt die Geometrie dort links UND rechts, aber nicht in der
/// Mitte, ist es ein Radpaar (Auto, Bus, LKW), sonst ein Einzelrad in
/// der Spur (Fahrrad, Motorrad, Einrad). So funktionieren 1–10 Räder
/// (bis zu 5 Achsen) ohne weitere Einstellung.
List<_WheelAxle> _analyzeVehicleAxles(
    List<(Map<String, dynamic>, Float32List)> primitives,
    double minX,
    double maxX,
    double minY,
    double maxY,
    double minZ,
    double maxZ) {
  const bins = 48;
  final h = maxY - minY, w = maxX - minX, d = maxZ - minZ;
  final cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  if (h <= 0 || w <= 0 || d <= 0) {
    return _defaultAxles(minY, maxY, w, d, cz);
  }

  final yCut = minY + 0.15 * h;
  final centerBand = 0.08 * w;
  final count = List<int>.filled(bins, 0);
  final xAbsSum = List<double>.filled(bins, 0);
  final hasLeft = List<bool>.filled(bins, false);
  final hasRight = List<bool>.filled(bins, false);
  final hasCenter = List<bool>.filled(bins, false);
  for (final (_, positions) in primitives) {
    for (var i = 0; i < positions.length; i += 3) {
      if (positions[i + 1] > yCut) continue;
      final x = positions[i] - cx;
      var bin = ((positions[i + 2] - minZ) / d * bins).floor();
      if (bin < 0) bin = 0;
      if (bin >= bins) bin = bins - 1;
      count[bin]++;
      xAbsSum[bin] += x.abs();
      if (x < -centerBand) hasLeft[bin] = true;
      if (x > centerBand) hasRight[bin] = true;
      if (x.abs() <= centerBand) hasCenter[bin] = true;
    }
  }
  var maxCount = 0;
  for (final c in count) {
    if (c > maxCount) maxCount = c;
  }
  if (maxCount == 0) return _defaultAxles(minY, maxY, w, d, cz);
  final threshold = (maxCount * 0.2).ceil();
  bool isWheelBin(int b) => count[b] >= threshold;

  final axles = <_WheelAxle>[];
  var bin = 0;
  while (bin < bins) {
    if (!isWheelBin(bin)) {
      bin++;
      continue;
    }
    // Lauf zusammenhängender Rad-Bins (eine Lücke von 1 Bin erlaubt).
    var end = bin;
    while (end + 1 < bins &&
        (isWheelBin(end + 1) ||
            (end + 2 < bins && isWheelBin(end + 2)))) {
      end++;
    }
    var runCount = 0;
    var zSum = 0.0, xSum = 0.0;
    var left = false, right = false, center = false;
    for (var b = bin; b <= end; b++) {
      runCount += count[b];
      zSum += count[b] * (minZ + (b + 0.5) / bins * d);
      xSum += xAbsSum[b];
      left = left || hasLeft[b];
      right = right || hasRight[b];
      center = center || hasCenter[b];
    }
    // Räder sind rund: Die z-Ausdehnung des Laufs nähert den
    // Durchmesser an, daraus folgt die Höhe der Radmitte.
    final zExtent = (end - bin + 1) / bins * d;
    final radius = (zExtent / 2).clamp(0.06 * h, 0.45 * h);
    final paired = left && right && !center;
    axles.add(_WheelAxle(
      z: zSum / runCount,
      y: minY + radius,
      radius: radius,
      paired: paired,
      xOff: paired ? (xSum / runCount).clamp(0.15 * w, 0.48 * w) : 0.0,
    ));
    bin = end + 1;
  }
  if (axles.isEmpty) return _defaultAxles(minY, maxY, w, d, cz);
  axles.sort((a, b) => b.z.compareTo(a.z)); // vorn (+z) zuerst
  if (axles.length > 5) axles.removeRange(5, axles.length);
  return axles;
}

int _pad4(int n) => (n + 3) & ~3;

double _distToSegmentSq(double px, double py, double pz, _Vec3 a, _Vec3 b) {
  final abx = b.x - a.x, aby = b.y - a.y, abz = b.z - a.z;
  final apx = px - a.x, apy = py - a.y, apz = pz - a.z;
  final abLenSq = abx * abx + aby * aby + abz * abz;
  var t = abLenSq < 1e-12
      ? 0.0
      : (apx * abx + apy * aby + apz * abz) / abLenSq;
  t = t.clamp(0.0, 1.0);
  final dx = px - (a.x + abx * t);
  final dy = py - (a.y + aby * t);
  final dz = pz - (a.z + abz * t);
  return dx * dx + dy * dy + dz * dz;
}

/// Sammelt Gelenke und Knochen: Jedes Gelenk (außer der Wurzel)
/// erzeugt automatisch einen Knochen vom Elternteil, der vom Elternteil
/// gesteuert wird; [tip] hängt an Blatt-Gelenke ein virtuelles
/// Endsegment für die Gewichtsverteilung an.
class _SkeletonBuilder {
  final joints = <_Joint>[];
  final bones = <_Bone>[];

  int joint(String name, int parent, _Vec3 position,
      {double boneRadius = 1.0}) {
    joints.add(_Joint(name, parent, position));
    if (parent >= 0) {
      bones.add(_Bone(parent, joints[parent].position, position,
          boneRadius, parent, joints.length - 1));
    }
    return joints.length - 1;
  }

  void tip(int jointIndex, _Vec3 to, {double radius = 1.0}) =>
      bones.add(_Bone(jointIndex, joints[jointIndex].position, to, radius,
          jointIndex, -1));
}

/// Baut das Skelett des gewünschten Figurtyps aus der Bounding Box
/// (bei Zweibeinern zusätzlich aus dem vermessenen [profile]).
/// Konvention: y = oben, Kopf/Blick nach +z.
(List<_Joint>, List<_Bone>) _skeletonFor(String rigType, double minX,
    double maxX, double minY, double maxY, double minZ, double maxZ,
    {_BodyProfile? profile, List<_WheelAxle>? vehicleAxles}) {
  final h = maxY - minY;
  final w = maxX - minX;
  final d = maxZ - minZ;
  final cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  _Vec3 p(double x, double yFraction, [double z = 0]) =>
      _Vec3(cx + x, minY + h * yFraction, cz + z);
  final b = _SkeletonBuilder();

  switch (rigType) {
    case 'quadruped':
      final hips = b.joint('Hips', -1, p(0, 0.6, -0.25 * d));
      final spine = b.joint('Spine', hips, p(0, 0.65, 0), boneRadius: 1.4);
      final chest = b.joint('Chest', spine, p(0, 0.65, 0.2 * d), boneRadius: 1.4);
      final neck = b.joint('Neck', chest, p(0, 0.75, 0.35 * d), boneRadius: 1.3);
      final head = b.joint('Head', neck, p(0, 0.85, 0.45 * d), boneRadius: 1.7);
      b.tip(head, p(0, 0.88, 0.52 * d), radius: 1.9);
      final tail1 = b.joint('Tail_1', hips, p(0, 0.6, -0.4 * d), boneRadius: 1.2);
      final tail2 = b.joint('Tail_2', tail1, p(0, 0.55, -0.48 * d));
      b.tip(tail2, p(0, 0.5, -0.55 * d));
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        for (final (prefix, legRoot, legZ) in [
          ('Front', chest, 0.2 * d),
          ('Hind', hips, -0.25 * d),
        ]) {
          final upper = b.joint('${prefix}UpperLeg_$suffix', legRoot,
              p(sign * 0.22 * w, 0.5, legZ));
          final knee = b.joint('${prefix}LowerLeg_$suffix', upper,
              p(sign * 0.24 * w, 0.25, legZ));
          final foot = b.joint(
              '${prefix}Foot_$suffix', knee, p(sign * 0.25 * w, 0.04, legZ));
          b.tip(foot, p(sign * 0.25 * w, 0.02, legZ + 0.06 * d));
        }
      }
    case 'insect':
      final root = b.joint('Thorax', -1, p(0, 0.55, 0));
      final head = b.joint('Head', root, p(0, 0.6, 0.32 * d), boneRadius: 1.5);
      b.tip(head, p(0, 0.6, 0.5 * d), radius: 1.6);
      final abdomen1 =
          b.joint('Abdomen_1', root, p(0, 0.52, -0.25 * d), boneRadius: 1.5);
      final abdomen2 =
          b.joint('Abdomen_2', abdomen1, p(0, 0.48, -0.42 * d));
      b.tip(abdomen2, p(0, 0.45, -0.52 * d));
      var pair = 0;
      for (final legZ in [0.18 * d, 0.0, -0.18 * d]) {
        pair++;
        for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
          final hip = b.joint(
              'Leg${pair}Hip_$suffix', root, p(sign * 0.14 * w, 0.5, legZ));
          final mid = b.joint('Leg${pair}Mid_$suffix', hip,
              p(sign * 0.32 * w, 0.32, legZ));
          final foot = b.joint('Leg${pair}Foot_$suffix', mid,
              p(sign * 0.46 * w, 0.04, legZ));
          b.tip(foot, p(sign * 0.5 * w, 0.02, legZ));
        }
      }
    case 'bird':
      final root = b.joint('Body', -1, p(0, 0.5, 0));
      final chest = b.joint('Chest', root, p(0, 0.6, 0.12 * d), boneRadius: 1.5);
      final neck = b.joint('Neck', chest, p(0, 0.72, 0.28 * d), boneRadius: 1.3);
      final head = b.joint('Head', neck, p(0, 0.82, 0.4 * d), boneRadius: 1.6);
      b.tip(head, p(0, 0.85, 0.5 * d), radius: 1.8);
      final tail = b.joint('Tail', root, p(0, 0.45, -0.4 * d));
      b.tip(tail, p(0, 0.42, -0.52 * d));
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        final wing = b.joint(
            'Wing_$suffix', chest, p(sign * 0.12 * w, 0.62, 0),
            boneRadius: 1.4);
        final wingMid = b.joint(
            'WingMid_$suffix', wing, p(sign * 0.3 * w, 0.62, 0),
            boneRadius: 1.4);
        b.tip(wingMid, p(sign * 0.5 * w, 0.62, 0), radius: 1.4);
        final leg = b.joint('Leg_$suffix', root, p(sign * 0.07 * w, 0.32, 0));
        final foot =
            b.joint('Foot_$suffix', leg, p(sign * 0.07 * w, 0.04, 0));
        b.tip(foot, p(sign * 0.07 * w, 0.02, 0.06 * d));
      }
    case 'snake' || 'fish':
      // Gelenk-Kette entlang der längeren horizontalen Achse, Kopf am
      // +Ende (bei z: vorn).
      final segments = rigType == 'snake' ? 8 : 6;
      final alongZ = d >= w;
      var parent = -1;
      for (var i = 0; i < segments; i++) {
        final t = 0.45 - 0.9 * i / (segments - 1);
        parent = b.joint(
          i == 0 ? 'Head' : 'Spine_$i',
          parent,
          alongZ ? p(0, 0.5, t * d) : p(t * w, 0.5),
        );
      }
      b.tip(parent, alongZ ? p(0, 0.5, -0.55 * d) : p(-0.55 * w, 0.5));
      b.tip(0, alongZ ? p(0, 0.5, 0.55 * d) : p(0.55 * w, 0.5));
    case 'vehicle':
      // Karosserie als dominanter Knochen; je erkannter Achse ein
      // Radpaar (links/rechts) oder ein Einzelrad in der Spur
      // (Fahrrad/Motorrad/Einrad). Die Räder drehen um die x-Achse
      // (Fahren-Animation, Blender/Unity).
      final axles =
          vehicleAxles ?? _defaultAxles(minY, maxY, w, d, cz);
      // Bei Einzelrädern (Zweirad/Einrad) sitzt Rahmen/Lenker hoch –
      // Karosserie-Knochen entsprechend nach oben legen.
      final bodyY = axles.any((a) => !a.paired) ? 0.72 : 0.5;
      final body = b.joint('Body', -1, p(0, bodyY, 0));
      b.tip(body, p(0, bodyY, 0.46 * d), radius: 2.4);
      b.tip(body, p(0, bodyY, -0.46 * d), radius: 2.4);
      var axleIndex = 0;
      for (final axle in axles) {
        axleIndex++;
        // Rad-„Scheibe“: Segmente über den Raddurchmesser, damit auch
        // der obere Radkranz mit dem Rad rotiert.
        void disc(int wheel, _Vec3 c, double tipRadius) {
          b.tip(wheel, _Vec3(c.x, c.y + axle.radius, c.z),
              radius: tipRadius);
          b.tip(wheel, _Vec3(c.x, c.y - axle.radius, c.z),
              radius: tipRadius);
          b.tip(wheel, _Vec3(c.x, c.y, c.z + axle.radius),
              radius: tipRadius);
          b.tip(wheel, _Vec3(c.x, c.y, c.z - axle.radius),
              radius: tipRadius);
        }

        if (axle.paired) {
          for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
            final pos = _Vec3(cx + sign * axle.xOff, axle.y, axle.z);
            final wheel = b.joint('Wheel${axleIndex}_$suffix', body, pos,
                boneRadius: 0.55);
            // Achsstummel nach außen: konzentriert Gewichte aufs Rad.
            b.tip(
                wheel,
                _Vec3(cx + sign * (axle.xOff + 0.12 * w), axle.y,
                    axle.z),
                radius: 1.1);
            disc(wheel, pos, 1.2);
          }
        } else {
          final pos = _Vec3(cx, axle.y, axle.z);
          final wheel =
              b.joint('Wheel$axleIndex', body, pos, boneRadius: 0.55);
          disc(wheel, pos, 1.6);
        }
      }
    default: // 'biped'
      // Vermessene Proportionen (Beinansatz, Hals, Beinabstand) statt
      // fester Standard-Prozente – wichtig für Chibi-/Comic-Figuren
      // mit großem Kopf: sonst laufen Armknochen durchs Haar und die
      // Wirbelsäule durch den Kopf.
      final crotch = ((profile?.crotchY ?? (minY + 0.48 * h)) - minY) / h;
      // Nur bei Chibi-Proportionen (Beine enden weit unten) die
      // vermessene Halshöhe nutzen – normale T-Pose-Figuren behalten
      // die bewährten Standardwerte.
      final chibi = crotch < 0.35 && profile != null;
      final legX = profile?.legX ?? 0.06 * w;
      final hipsF = crotch + 0.04;
      final measuredShoulder = profile?.shoulderY;
      double neckF;
      double shoulderF;
      if (measuredShoulder != null) {
        // Schulterhöhe direkt aus den erkannten Armen – zuverlässiger
        // als die Halsschätzung, besonders bei Frisuren, die den Kopf
        // breit umschließen (dort liegt das Breiten-Minimum sonst auf
        // Gesichtshöhe und die Arme wandern in die Haare).
        shoulderF =
            ((measuredShoulder - minY) / h).clamp(hipsF + 0.05, 0.92);
        neckF = (shoulderF + 0.06).clamp(0.0, 0.95);
      } else {
        neckF = chibi ? (profile.neckY - minY) / h : 0.84;
        shoulderF = (neckF - 0.04).clamp(hipsF + 0.05, 0.95);
      }
      final headF = neckF + 0.4 * (1 - neckF);
      final kneeF = crotch * 0.5;

      final hips = b.joint('Hips', -1, p(0, hipsF));
      final spine = b.joint('Spine', hips,
          p(0, hipsF + 0.33 * (neckF - hipsF)),
          boneRadius: 1.4);
      final chest = b.joint('Chest', spine,
          p(0, hipsF + 0.66 * (neckF - hipsF)),
          boneRadius: 1.4);
      final neck =
          b.joint('Neck', chest, p(0, neckF), boneRadius: 1.4);
      final head =
          b.joint('Head', neck, p(0, headF), boneRadius: 1.8);
      b.tip(head, p(0, 1.0), radius: 2.4);
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        // Schulter und Hand aus den gemessenen Arminseln, sonst wie
        // bisher als Anteil der Modellbreite. Der Unterschied ist
        // groß: Bei einer T-Pose ist die Modellbreite die Armspanne,
        // und „0,10 davon" liegt mitten im Rumpf.
        final inner = profile?.armInnerX ?? 0.10 * w;
        final outer = profile?.armOuterX ?? 0.50 * w;
        final reach = (outer - inner).abs();
        // Leicht abfallend – passt für T-Pose wie für die typische
        // A-Pose von Spielfiguren. Schmale Einflussradien (0,85),
        // damit der Rumpf (Anzug/Jacke) beim Chest-Knochen bleibt
        // und beim Arm-Anheben nicht mitgezogen wird.
        final shoulder = b.joint('Shoulder_$suffix', chest,
            p(sign * inner, shoulderF),
            boneRadius: 1.1);
        final elbow = b.joint('Elbow_$suffix', shoulder,
            p(sign * (inner + 0.45 * reach), shoulderF - 0.03),
            boneRadius: 0.85);
        final hand = b.joint('Hand_$suffix', elbow,
            p(sign * (inner + 0.85 * reach), shoulderF - 0.06),
            boneRadius: 0.85);
        b.tip(hand, p(sign * outer, shoulderF - 0.08), radius: 0.85);
      }
      for (final (suffix, sign) in [('L', -1.0), ('R', 1.0)]) {
        final upper = b.joint(
            'UpperLeg_$suffix', hips, p(sign * legX, crotch),
            boneRadius: 1.2);
        // Oberschenkel schmaler (0,9): Gürtel/Hüftbereich bleibt beim
        // Hips-Knochen und schert beim Gehen nicht mit den Beinen.
        final knee = b.joint('Knee_$suffix', upper, p(sign * legX, kneeF),
            boneRadius: 0.9);
        final foot =
            b.joint('Foot_$suffix', knee, p(sign * legX, 0.04));
        b.tip(foot, p(sign * legX, 0.02, 0.2 * d));
      }
  }
  return (b.joints, b.bones);
}

/// Liest die Positionen eines POSITION-Accessors (float32 VEC3).
Float32List _readPositions(Map<String, dynamic> json, Uint8List bin,
    int accessorIndex) {
  final accessor =
      (json['accessors'] as List)[accessorIndex] as Map<String, dynamic>;
  if (accessor['componentType'] != 5126 ||
      accessor['type'] != 'VEC3' ||
      accessor.containsKey('sparse')) {
    throw Exception('Positionsformat wird nicht unterstützt.');
  }
  final viewIndex = accessor['bufferView'] as int?;
  if (viewIndex == null) {
    throw Exception('Positions-Accessor ohne Daten.');
  }
  final view =
      (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  final count = accessor['count'] as int;
  final stride = (view['byteStride'] as int?) ?? 12;
  final start = ((view['byteOffset'] as int?) ?? 0) +
      ((accessor['byteOffset'] as int?) ?? 0);
  final data = ByteData.sublistView(bin);
  final out = Float32List(count * 3);
  for (var i = 0; i < count; i++) {
    final o = start + i * stride;
    out[i * 3] = data.getFloat32(o, Endian.little);
    out[i * 3 + 1] = data.getFloat32(o + 4, Endian.little);
    out[i * 3 + 2] = data.getFloat32(o + 8, Endian.little);
  }
  return out;
}

/// Zwischenergebnis der GLB-Analyse (JSON, Binärdaten, Geometrie).
class _GlbAnalysis {
  _GlbAnalysis(this.json, this.bin, this.primitives, this.minX, this.maxX,
      this.minY, this.maxY, this.minZ, this.maxZ);

  final Map<String, dynamic> json;
  final Uint8List bin;
  final List<(Map<String, dynamic>, Float32List)> primitives;
  final double minX, maxX, minY, maxY, minZ, maxZ;
}

/// GLB zerlegen, Positionen einlesen, Bounding Box bestimmen.
_GlbAnalysis _analyzeGlb(Uint8List glb) {
  if (glb.length < 20) throw Exception('Ungültige GLB-Datei.');
  final header = ByteData.sublistView(glb);
  if (header.getUint32(0, Endian.little) != 0x46546C67 ||
      header.getUint32(4, Endian.little) != 2) {
    throw Exception('Ungültige GLB-Datei.');
  }
  final jsonLength = header.getUint32(12, Endian.little);
  if (header.getUint32(16, Endian.little) != 0x4E4F534A) {
    throw Exception('GLB ohne JSON-Chunk.');
  }
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  final binHeaderOffset = 20 + _pad4(jsonLength);
  var bin = Uint8List(0);
  if (binHeaderOffset + 8 <= glb.length &&
      header.getUint32(binHeaderOffset + 4, Endian.little) == 0x004E4942) {
    final binLength = header.getUint32(binHeaderOffset, Endian.little);
    bin = glb.sublist(binHeaderOffset + 8, binHeaderOffset + 8 + binLength);
  }

  if ((json['skins'] as List?)?.isNotEmpty ?? false) {
    throw Exception('Das Modell besitzt bereits ein Skelett.');
  }
  final meshes = (json['meshes'] as List?) ?? [];
  if (meshes.isEmpty) throw Exception('Die GLB enthält kein Mesh.');

  final primitives = <(Map<String, dynamic>, Float32List)>[];
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (final mesh in meshes) {
    for (final primitive in (mesh as Map)['primitives'] as List) {
      final attributes =
          (primitive as Map)['attributes'] as Map<String, dynamic>;
      final positionIndex = attributes['POSITION'] as int?;
      if (positionIndex == null) continue;
      final positions = _readPositions(json, bin, positionIndex);
      primitives.add((primitive.cast<String, dynamic>(), positions));
      for (var i = 0; i < positions.length; i += 3) {
        final x = positions[i], y = positions[i + 1], z = positions[i + 2];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }
    }
  }
  if (primitives.isEmpty) {
    throw Exception('Keine Geometrie mit Positionsdaten gefunden.');
  }
  return _GlbAnalysis(
      json, bin, primitives, minX, maxX, minY, maxY, minZ, maxZ);
}

/// Skelett-Vorlage für die analysierte GLB berechnen. Liefert
/// zusätzlich die Blickrichtung (+1 = +z, -1 = -z): aus
/// [knownFrontSign] (die Pipeline weiß, wohin das Ausgangsbild zeigt –
/// Stability rekonstruiert die Bildseite nach -z, der lokale Generator
/// baut nach +z), sonst bei Zweibeinern aus der Geometrie geschätzt.
/// Bei -z wird das komplette Skelett an der Modellmitte gespiegelt
/// (Fußspitzen, Kopf/Schwanz von Vierbeinern und Vögeln usw.).
(List<_Joint>, List<_Bone>, int) _skeletonForGlb(
    _GlbAnalysis a, String rigType,
    {int? knownFrontSign}) {
  final height = a.maxY - a.minY, width = a.maxX - a.minX;
  final depth = a.maxZ - a.minZ;
  if (height <= 0 || width <= 0) {
    throw Exception('Die Geometrie ist leer oder flach.');
  }
  if (rigType == 'biped' && height < 0.4 * width) {
    throw Exception(
        'Das Modell wirkt nicht wie eine aufrecht stehende Figur '
        '(zu breit/flach) – ggf. einen anderen Figurtyp wählen.');
  }
  if (rigType == 'vehicle' && depth < 0.35 * height) {
    throw Exception(
        'Das Modell ist entlang der Fahrtrichtung fast flach – es wirkt '
        'wie eine aufrecht stehende Platte statt eines fahrbereiten '
        'Fahrzeugs. Das passiert bei Bild→3D aus einer reinen '
        'Frontalansicht ohne Perspektive; am besten eine '
        'Dreiviertelansicht (schräg von vorn, Fahrzeugseite sichtbar) '
        'als Bildvorlage verwenden.');
  }
  final profile = rigType == 'biped'
      ? _analyzeBipedProfile(a.primitives, a.minX, a.maxX, a.minY, a.maxY)
      : null;
  var vehicleAxles = rigType == 'vehicle'
      ? _analyzeVehicleAxles(
          a.primitives, a.minX, a.maxX, a.minY, a.maxY, a.minZ, a.maxZ)
      : null;
  // Mehr als zwei Einzelräder hintereinander gibt es real nicht
  // (Fahrrad = 2, Einrad = 1) – so viele „Achsen“ heißen: Die
  // bodennahe Geometrie taugt nicht zur Rad-Erkennung (z. B. flacher
  // Unterboden). Dann lieber das Standard-Fahrwerk (4 Räder) statt
  // vieler Phantom-Räder.
  if (vehicleAxles != null &&
      vehicleAxles.where((axle) => !axle.paired).length >= 3) {
    vehicleAxles = _defaultAxles(a.minY, a.maxY, width, depth,
        (a.minZ + a.maxZ) / 2);
  }
  // Fahrzeuge behalten die +z-Konvention (die Achsen sind vorn-zuerst
  // sortiert und die Räder rollen richtungsunabhängig um x).
  final frontSign = rigType == 'vehicle'
      ? 1
      : knownFrontSign != null
          ? (knownFrontSign < 0 ? -1 : 1)
          : rigType == 'biped'
              ? estimateFrontSign(
                  [for (final (_, positions) in a.primitives) positions])
              : 1;
  var (joints, bones) = _skeletonFor(
      rigType, a.minX, a.maxX, a.minY, a.maxY, a.minZ, a.maxZ,
      profile: profile, vehicleAxles: vehicleAxles);
  if (frontSign < 0) {
    // Ganzes Skelett an der Modellmitte spiegeln: Kopf-/Schwanz-Enden,
    // Fußspitzen und alle Knochen zeigen dann Richtung -z.
    final cz = a.minZ + depth / 2;
    _Vec3 flip(_Vec3 v) => _Vec3(v.x, v.y, 2 * cz - v.z);
    joints = [
      for (final j in joints) _Joint(j.name, j.parent, flip(j.position)),
    ];
    bones = [
      for (final b in bones)
        _Bone(b.joint, flip(b.from), flip(b.to), b.radius, b.fromJoint,
            b.toJoint),
    ];
  }
  return (joints, bones, frontSign);
}

/// Öffentliche Gelenk-Info (für den Rig-Editor).
/// Kurzanleitung je Gelenk: wo der Punkt am Modell sitzen soll.
/// Wird im Rig-Editor beim Antippen angezeigt, damit klar ist, was ein
/// Punkt steuert und wohin er gehört. Die Namen kommen aus
/// [_skeletonForGlb]; Seiten-Endungen (_L/_R) und Nummern (Achse,
/// Beinpaar, Wirbel) werden vorher abgetrennt.
String jointGuide(String jointName) {
  var base = jointName;
  var side = '';
  if (base.endsWith('_L')) {
    side = ' (linke Seite der Figur)';
    base = base.substring(0, base.length - 2);
  } else if (base.endsWith('_R')) {
    side = ' (rechte Seite der Figur)';
    base = base.substring(0, base.length - 2);
  }
  // Nummerierte Namen vereinheitlichen: Leg2Foot -> LegFoot,
  // Spine_3 -> Spine, Wheel2 -> Wheel.
  final generic = base.replaceAll(RegExp(r'[0-9]+'), '').replaceAll('_', '');
  final text = switch (generic) {
    'Hips' =>
      'Beckenmitte, etwa auf Höhe des Hosenbunds – die Wurzel des '
          'Skeletts. Bewegt die ganze Figur.',
    'Spine' =>
      'Untere Wirbelsäule, etwa auf Bauchnabelhöhe, mittig in der '
          'Figur (nicht auf der Bauchdecke).',
    'Chest' =>
      'Brustbeinmitte, zwischen den Schultern und mittig in der Tiefe.',
    'Neck' => 'Halsansatz, dort wo der Kopf auf den Schultern sitzt.',
    'Head' =>
      'Kopfmitte, etwa auf Augenhöhe und mittig in der Tiefe – nicht '
          'an der Nasenspitze und nicht am Scheitel.',
    'Shoulder' =>
      'Schultergelenk, wo der Arm am Rumpf ansetzt – etwas innerhalb '
          'der Silhouette$side.',
    'Elbow' => 'Ellenbogen, in der Mitte des ausgestreckten Arms$side.',
    'Hand' =>
      'Handwurzel, wo die Hand am Unterarm ansetzt$side. Bei Fäustlingen '
          'oder Handschuhen den Punkt eher in die Handmitte legen und '
          'den Einflussbereich vergrößern, damit Daumen und Finger '
          'mitgehen.',
    'UpperLeg' =>
      'Hüftgelenk, wo das Bein am Becken ansetzt$side – nicht am '
          'äußeren Rand der Hose.',
    'Knee' => 'Kniemitte$side.',
    'Foot' =>
      'Fußgelenk, kurz über der Sohle$side – der Punkt gehört an den '
          'Knöchel, nicht an die Fußspitze.',
    'LegHip' => 'Ansatz des Beins am Körper$side.',
    'LegMid' => 'Mittleres Gelenk dieses Beins$side.',
    'LegFoot' => 'Fußende dieses Beins, knapp über dem Boden$side.',
    'Wing' => 'Flügelansatz am Rumpf$side.',
    'WingTip' => 'Flügelspitze$side.',
    'Tail' => 'Schwanzansatz bzw. Schwanzglied, mittig im Körper.',
    'Body' =>
      'Fahrzeugmitte auf Höhe der Karosserie – bewegt das ganze '
          'Fahrzeug.',
    'Wheel' =>
      'Radmitte (Nabe)$side. Der Punkt muss genau im Radzentrum sitzen, '
          'sonst eiert das Rad beim Drehen.',
    'Root' => 'Wurzel des Skeletts, mittig im Modell.',
    _ => '',
  };
  if (text.isNotEmpty) return text;
  // Endsegmente (…_Tip) und alles Unbekannte.
  if (jointName.toLowerCase().contains('tip')) {
    return 'Endpunkt des Knochens – bestimmt nur, wie weit die '
        'Gewichtung nach außen reicht.';
  }
  return 'Gelenk „$jointName" – mittig im zugehörigen Körperteil '
      'platzieren.';
}

class RigJointInfo {
  const RigJointInfo(this.name, this.parent, this.x, this.y, this.z,
      {this.radius = 1.0});

  final String name;
  final int parent; // -1 = Wurzel
  final double x, y, z;

  /// Wirkungs-Radius der Knochen dieses Gelenks (Faktor der
  /// Abstands-Gewichtung, 1,0 = Standard). Der Rig-Editor zeichnet ihn
  /// als Kugel, damit sichtbar wird, wie weit das Gelenk greift.
  final double radius;
}

/// Berechnet die Gelenkpositionen, die [injectAutoRig] für diese GLB
/// verwenden würde – Ausgangspunkt fürs manuelle Nachjustieren im
/// Rig-Editor.
List<RigJointInfo> computeAutoRigJoints(Uint8List glb,
    {String rigType = 'biped', int? knownFrontSign}) {
  final (joints, bones, _) = _skeletonForGlb(_analyzeGlb(glb), rigType,
      knownFrontSign: knownFrontSign);
  // Größter Knochen-Radius je Gelenk – das ist der Wert, den der
  // Einflussregler im Editor skaliert.
  final radii = List<double>.filled(joints.length, 1.0);
  for (final bone in bones) {
    if (bone.joint >= 0 && bone.joint < radii.length) {
      final current = radii[bone.joint];
      if (bone.radius > current) radii[bone.joint] = bone.radius;
    }
  }
  return [
    for (var j = 0; j < joints.length; j++)
      RigJointInfo(joints[j].name, joints[j].parent, joints[j].position.x,
          joints[j].position.y, joints[j].position.z,
          radius: radii[j]),
  ];
}

/// Baut das Standard-Skelett des gewählten [rigType] in die GLB ein und
/// liefert die neue Datei. Mit [jointPositions] (Gelenkname →
/// absolute Position) lassen sich die automatisch bestimmten Gelenke
/// manuell übersteuern – die Knochen und Skin-Gewichte folgen den
/// verschobenen Gelenken. [jointInfluence] (Gelenkname → Faktor)
/// skaliert den Einflussradius aller Knochen des jeweiligen Gelenks:
/// größer = das Gelenk „greift“ mehr umliegende Geometrie, kleiner =
/// schärfere Abgrenzung. [knownFrontSign] übergibt Pipeline-Wissen
/// über die Blickrichtung (-1 = Gesicht nach -z, z. B. Stability;
/// +1 = nach +z, z. B. lokaler Generator) und ersetzt dann die
/// geometrische Schätzung. Wirft [Exception] mit verständlicher
/// Meldung, wenn das nicht geht.
Uint8List injectAutoRig(Uint8List glb,
    {String rigType = 'biped',
    Map<String, (double, double, double)>? jointPositions,
    Map<String, double>? jointInfluence,
    int? knownFrontSign}) {
  final analysis = _analyzeGlb(glb);
  final json = analysis.json;
  final bin = analysis.bin;
  final primitives = analysis.primitives;
  final height = analysis.maxY - analysis.minY;
  var (joints, bones, frontSign) = _skeletonForGlb(analysis, rigType,
      knownFrontSign: knownFrontSign);

  if (jointPositions != null && jointPositions.isNotEmpty) {
    // Manuell verschobene Gelenke übernehmen; Knochen-Endpunkte folgen
    // den Gelenken, Spitzen behalten ihren Versatz zum eigenen Gelenk.
    final newPos =
        List<_Vec3>.generate(joints.length, (j) => joints[j].position);
    for (var j = 0; j < joints.length; j++) {
      final o = jointPositions[joints[j].name];
      if (o != null) newPos[j] = _Vec3(o.$1, o.$2, o.$3);
    }
    bones = [
      for (final bone in bones)
        _Bone(
          bone.joint,
          bone.fromJoint >= 0 ? newPos[bone.fromJoint] : bone.from,
          bone.toJoint >= 0
              ? newPos[bone.toJoint]
              : _Vec3(
                  newPos[bone.fromJoint].x +
                      bone.to.x -
                      joints[bone.fromJoint].position.x,
                  newPos[bone.fromJoint].y +
                      bone.to.y -
                      joints[bone.fromJoint].position.y,
                  newPos[bone.fromJoint].z +
                      bone.to.z -
                      joints[bone.fromJoint].position.z,
                ),
          bone.radius,
          bone.fromJoint,
          bone.toJoint,
        ),
    ];
    joints = [
      for (var j = 0; j < joints.length; j++)
        _Joint(joints[j].name, joints[j].parent, newPos[j]),
    ];
  }

  // Neue Binärdaten: pro Primitive JOINTS_0 (ubyte VEC4) und WEIGHTS_0
  // (float VEC4), dazu die inversen Bind-Matrizen (MAT4 float).
  final bufferViews =
      ((json['bufferViews'] as List?) ?? []).cast<dynamic>().toList();
  final accessors =
      ((json['accessors'] as List?) ?? []).cast<dynamic>().toList();
  final appendParts = <Uint8List>[];
  var appendCursor = _pad4(bin.length);
  final appendOffsets = <int>[];
  int addPart(Uint8List part) {
    appendOffsets.add(appendCursor);
    appendParts.add(part);
    appendCursor = _pad4(appendCursor + part.length);
    return appendOffsets.length - 1;
  }

  // Effektive Einflussradien (inkl. manueller Skalierung je Gelenk aus
  // dem Rig-Editor).
  final boneRadius = Float64List(bones.length);
  for (var b = 0; b < bones.length; b++) {
    final scale =
        (jointInfluence?[joints[bones[b].joint].name] ?? 1.0)
            .clamp(0.2, 4.0);
    boneRadius[b] = bones[b].radius * scale;
  }

  for (final (primitive, positions) in primitives) {
    final vertexCount = positions.length ~/ 3;
    final jointData = Uint8List(vertexCount * 4);
    final weightData = Float32List(vertexCount * 4);
    for (var v = 0; v < vertexCount; v++) {
      final px = positions[v * 3],
          py = positions[v * 3 + 1],
          pz = positions[v * 3 + 2];
      // Die zwei nächsten Knochen bestimmen.
      var best = -1, second = -1;
      var bestD = double.infinity, secondD = double.infinity;
      for (var b = 0; b < bones.length; b++) {
        final bone = bones[b];
        final d = _distToSegmentSq(px, py, pz, bone.from, bone.to) /
            (boneRadius[b] * boneRadius[b]);
        if (d < bestD) {
          second = best;
          secondD = bestD;
          best = b;
          bestD = d;
        } else if (d < secondD) {
          second = b;
          secondD = d;
        }
      }
      final eps = 1e-6 * height * height;
      final w0 = 1.0 / (bestD + eps);
      final w1 = second >= 0 ? 1.0 / (secondD + eps) : 0.0;
      final sum = w0 + w1;
      jointData[v * 4] = bones[best].joint;
      jointData[v * 4 + 1] = second >= 0 ? bones[second].joint : 0;
      weightData[v * 4] = w0 / sum;
      weightData[v * 4 + 1] = second >= 0 ? w1 / sum : 0.0;
    }

    final jointPart = addPart(jointData);
    final weightPart =
        addPart(weightData.buffer.asUint8List(0, weightData.lengthInBytes));
    bufferViews.add({
      'buffer': 0,
      'byteOffset': appendOffsets[jointPart],
      'byteLength': jointData.length,
      'target': 34962,
    });
    accessors.add({
      'bufferView': bufferViews.length - 1,
      'componentType': 5121,
      'count': vertexCount,
      'type': 'VEC4',
    });
    primitive['attributes']['JOINTS_0'] = accessors.length - 1;
    bufferViews.add({
      'buffer': 0,
      'byteOffset': appendOffsets[weightPart],
      'byteLength': weightData.lengthInBytes,
      'target': 34962,
    });
    accessors.add({
      'bufferView': bufferViews.length - 1,
      'componentType': 5126,
      'count': vertexCount,
      'type': 'VEC4',
    });
    primitive['attributes']['WEIGHTS_0'] = accessors.length - 1;
  }

  // Inverse Bind-Matrizen (reine Translationen).
  final ibm = Float32List(joints.length * 16);
  for (var j = 0; j < joints.length; j++) {
    final p = joints[j].position;
    final o = j * 16;
    ibm[o] = 1;
    ibm[o + 5] = 1;
    ibm[o + 10] = 1;
    ibm[o + 12] = -p.x;
    ibm[o + 13] = -p.y;
    ibm[o + 14] = -p.z;
    ibm[o + 15] = 1;
  }
  final ibmPart = addPart(ibm.buffer.asUint8List(0, ibm.lengthInBytes));
  bufferViews.add({
    'buffer': 0,
    'byteOffset': appendOffsets[ibmPart],
    'byteLength': ibm.lengthInBytes,
  });
  accessors.add({
    'bufferView': bufferViews.length - 1,
    'componentType': 5126,
    'count': joints.length,
    'type': 'MAT4',
  });
  final ibmAccessor = accessors.length - 1;

  // Skelett-Knoten anhängen (lokale Translationen relativ zum Elternteil).
  final nodes = ((json['nodes'] as List?) ?? []).cast<dynamic>().toList();
  final jointBase = nodes.length;
  for (var j = 0; j < joints.length; j++) {
    final joint = joints[j];
    final parentPos = joint.parent >= 0
        ? joints[joint.parent].position
        : const _Vec3(0, 0, 0);
    final children = [
      for (var c = 0; c < joints.length; c++)
        if (joints[c].parent == j) jointBase + c,
    ];
    nodes.add({
      'name': joint.name,
      'translation': [
        joint.position.x - parentPos.x,
        joint.position.y - parentPos.y,
        joint.position.z - parentPos.z,
      ],
      if (children.isNotEmpty) 'children': children,
    });
  }
  // Skin registrieren und den Mesh-Knoten zuweisen. Die erkannte
  // Blickrichtung wandert in die Skin-Extras, damit Testanimationen
  // und Viewer-Startansicht sie auch nach dem Neuladen kennen.
  json['skins'] = [
    {
      'joints': [for (var j = 0; j < joints.length; j++) jointBase + j],
      'inverseBindMatrices': ibmAccessor,
      'skeleton': jointBase,
      'extras': {'front_z': frontSign},
    }
  ];
  for (final node in nodes) {
    if (node is Map && node.containsKey('mesh')) {
      node['skin'] = 0;
    }
  }
  json['nodes'] = nodes;
  json['bufferViews'] = bufferViews;
  json['accessors'] = accessors;
  for (final scene in (json['scenes'] as List?) ?? []) {
    ((scene as Map)['nodes'] as List?)?.add(jointBase);
  }

  // Binärpuffer zusammensetzen.
  final newBinLength = appendCursor;
  final newBin = Uint8List(newBinLength);
  newBin.setRange(0, bin.length, bin);
  for (var i = 0; i < appendParts.length; i++) {
    newBin.setRange(appendOffsets[i],
        appendOffsets[i] + appendParts[i].length, appendParts[i]);
  }
  (json['buffers'] as List)[0]['byteLength'] = newBinLength;

  // GLB neu schreiben.
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadded = Uint8List(_pad4(jsonBytes.length))
    ..fillRange(0, _pad4(jsonBytes.length), 0x20)
    ..setRange(0, jsonBytes.length, jsonBytes);
  final total = 12 + 8 + jsonPadded.length + 8 + newBinLength;
  final out = ByteData(total);
  var o = 0;
  void u32(int value) {
    out.setUint32(o, value, Endian.little);
    o += 4;
  }

  u32(0x46546C67);
  u32(2);
  u32(total);
  u32(jsonPadded.length);
  u32(0x4E4F534A);
  out.buffer.asUint8List().setRange(o, o + jsonPadded.length, jsonPadded);
  o += jsonPadded.length;
  u32(newBinLength);
  u32(0x004E4942);
  out.buffer.asUint8List().setRange(o, o + newBinLength, newBin);
  return out.buffer.asUint8List();
}

/// Für Tests und Anzeige: Gelenkzahl je Figurtyp. Beim Fahrzeug-Rig
/// ist die Zahl variabel (Karosserie + automatisch erkannte Räder,
/// 1–10 Räder), daher taucht 'vehicle' hier nicht auf.
const rigJointCounts = {
  'biped': 17,
  'quadruped': 19,
  'insect': 22,
  'bird': 13,
  'snake': 8,
  'fish': 6,
};

/// Kleiner Selbsttest-Helfer: prüft, ob eine GLB ein Skin trägt.
bool glbHasSkin(Uint8List glb) {
  final header = ByteData.sublistView(glb);
  final jsonLength = header.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  return (json['skins'] as List?)?.isNotEmpty ?? false;
}
