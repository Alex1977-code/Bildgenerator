/// Eigenes Auto-Rigging: baut ein Standard-Skelett (Heuristik aus der
/// Bounding Box) direkt in eine GLB-Datei ein – komplett lokal, ohne
/// API. Die Skin-Gewichte entstehen über den Abstand jedes Vertex zu
/// den Knochensegmenten (die zwei nächsten Knochen werden gemischt).
///
/// Es gibt Skelett-Vorlagen für Zweibeiner (Mensch/Roboter/Fantasy in
/// T-Pose), Vierbeiner, Insekten/Mehrbeiner, Vögel (gespreizte Flügel),
/// Schlangen und Fische. Konvention: y = oben, Blick/Kopf nach +z –
/// genau das, was die App bei aktivem Rigging erzeugt.
/// Texturen, Materialien und alle übrigen Daten der GLB bleiben
/// unverändert; es kommen nur Skelett-Knoten, ein Skin und
/// JOINTS_0/WEIGHTS_0-Attribute hinzu.
library;

import 'dart:convert';
import 'dart:typed_data';

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
  });

  final double crotchY; // Beinansatz (absolute y-Koordinate)
  final double neckY; // Halsansatz (absolute y-Koordinate)
  final double legX; // Abstand der Beinmitte von der Körpermitte

  /// Schulterhöhe aus erkannten, seitlich abstehenden Armen (absolute
  /// y-Koordinate) – zuverlässiger als die Halsschätzung, besonders
  /// bei Frisuren, die den Kopf breit umschließen. Null, wenn keine
  /// getrennten Arme erkennbar sind (z. B. echte T-Pose).
  final double? shoulderY;
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
  final centerBand = 0.06 * width;
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
      if (x < -centerBand) hasLeft[bin] = true;
      if (x > centerBand) hasRight[bin] = true;
      if (x.abs() <= centerBand) hasCenter[bin] = true;
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

  // Beinspalt: zusammenhängender Bereich von unten, in dem links und
  // rechts belegt sind, die Mitte aber frei bleibt.
  bool split(int bin) => hasLeft[bin] && hasRight[bin] && !hasCenter[bin];
  var crotchBin = -1;
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
  final armSpanOk = armTopBin >= 0 &&
      (armTopBin - armBottomBin + 1) >= (bins * 0.10).ceil();
  final shoulderY =
      armSpanOk ? binY(armTopBin) + 0.04 * height : null;

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
      crotchY: crotchY, neckY: neckY, legX: legX, shoulderY: shoulderY);
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
        final shoulder = b.joint('Shoulder_$suffix', chest,
            p(sign * 0.10 * w, shoulderF),
            boneRadius: 1.1);
        // Leicht abfallend – passt für T-Pose wie für die typische
        // A-Pose von Spielfiguren. Schmale Einflussradien (0,85),
        // damit der Rumpf (Anzug/Jacke) beim Chest-Knochen bleibt
        // und beim Arm-Anheben nicht mitgezogen wird.
        final elbow = b.joint('Elbow_$suffix', shoulder,
            p(sign * 0.28 * w, shoulderF - 0.03),
            boneRadius: 0.85);
        final hand = b.joint('Hand_$suffix', elbow,
            p(sign * 0.43 * w, shoulderF - 0.06),
            boneRadius: 0.85);
        b.tip(hand, p(sign * 0.5 * w, shoulderF - 0.08), radius: 0.85);
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

/// Skelett-Vorlage für die analysierte GLB berechnen.
(List<_Joint>, List<_Bone>) _skeletonForGlb(_GlbAnalysis a, String rigType) {
  final height = a.maxY - a.minY, width = a.maxX - a.minX;
  if (height <= 0 || width <= 0) {
    throw Exception('Die Geometrie ist leer oder flach.');
  }
  if (rigType == 'biped' && height < 0.4 * width) {
    throw Exception(
        'Das Modell wirkt nicht wie eine aufrecht stehende Figur '
        '(zu breit/flach) – ggf. einen anderen Figurtyp wählen.');
  }
  final profile = rigType == 'biped'
      ? _analyzeBipedProfile(a.primitives, a.minX, a.maxX, a.minY, a.maxY)
      : null;
  final vehicleAxles = rigType == 'vehicle'
      ? _analyzeVehicleAxles(
          a.primitives, a.minX, a.maxX, a.minY, a.maxY, a.minZ, a.maxZ)
      : null;
  return _skeletonFor(
      rigType, a.minX, a.maxX, a.minY, a.maxY, a.minZ, a.maxZ,
      profile: profile, vehicleAxles: vehicleAxles);
}

/// Öffentliche Gelenk-Info (für den Rig-Editor).
class RigJointInfo {
  const RigJointInfo(this.name, this.parent, this.x, this.y, this.z);

  final String name;
  final int parent; // -1 = Wurzel
  final double x, y, z;
}

/// Berechnet die Gelenkpositionen, die [injectAutoRig] für diese GLB
/// verwenden würde – Ausgangspunkt fürs manuelle Nachjustieren im
/// Rig-Editor.
List<RigJointInfo> computeAutoRigJoints(Uint8List glb,
    {String rigType = 'biped'}) {
  final (joints, _) = _skeletonForGlb(_analyzeGlb(glb), rigType);
  return [
    for (final j in joints)
      RigJointInfo(j.name, j.parent, j.position.x, j.position.y,
          j.position.z),
  ];
}

/// Baut das Standard-Skelett des gewählten [rigType] in die GLB ein und
/// liefert die neue Datei. Mit [jointPositions] (Gelenkname →
/// absolute Position) lassen sich die automatisch bestimmten Gelenke
/// manuell übersteuern – die Knochen und Skin-Gewichte folgen den
/// verschobenen Gelenken. Wirft [Exception] mit verständlicher
/// Meldung, wenn das nicht geht.
Uint8List injectAutoRig(Uint8List glb,
    {String rigType = 'biped',
    Map<String, (double, double, double)>? jointPositions}) {
  final analysis = _analyzeGlb(glb);
  final json = analysis.json;
  final bin = analysis.bin;
  final primitives = analysis.primitives;
  final height = analysis.maxY - analysis.minY;
  var (joints, bones) = _skeletonForGlb(analysis, rigType);

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
            (bone.radius * bone.radius);
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
  // Skin registrieren und den Mesh-Knoten zuweisen.
  json['skins'] = [
    {
      'joints': [for (var j = 0; j < joints.length; j++) jointBase + j],
      'inverseBindMatrices': ibmAccessor,
      'skeleton': jointBase,
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
