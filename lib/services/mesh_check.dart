import 'dart:typed_data';

/// Wasserdichtheits-Prüfung für den 3D-Druck: Ein Netz ist geschlossen
/// (wasserdicht), wenn jede Kante zu genau zwei Dreiecken gehört.
/// Vorher werden Vertices mit (praktisch) gleicher Position
/// verschweißt, damit Nahtstellen zwischen Primitiven nicht fälschlich
/// als offene Kanten zählen.
class MeshCheckResult {
  const MeshCheckResult({
    required this.triangles,
    required this.openEdges,
    required this.rawOpenEdges,
    required this.nonManifoldEdges,
  });

  final int triangles;

  /// Kanten, die nur zu einem Dreieck gehören (Loch im Netz).
  ///
  /// Gezählt **nach** dem Verschweißen nach Position: Eine UV-Naht
  /// verdoppelt Punkte, ist aber kein Loch.
  final int openEdges;

  /// Dieselbe Zählung **ohne** Verschweißen – so, wie die Datei
  /// geschrieben wird.
  ///
  /// Wer nicht verschweißt, sieht jede Naht und jeden doppelten Punkt
  /// als Rand. Blender tut das, Roblox tut das. Die Differenz zu
  /// [openEdges] sind genau die doppelten Punkte: bei einer Textur
  /// harmlos, bei einem doppelten Kugelpol ein Modellierfehler. Die
  /// App hat sich an dieser Stelle selbst belogen, bis Blender an
  /// einem erzeugten Auge 46 Randkanten zählte, wo sie 0 meldete.
  final int rawOpenEdges;

  /// Kanten mit mehr als zwei Dreiecken (Berührungsstellen) – für
  /// Slicer in der Regel unkritisch.
  final int nonManifoldEdges;

  bool get watertight => openEdges == 0;

  /// Wasserdicht auch für ein Werkzeug, das nicht verschweißt.
  bool get watertightUnwelded => rawOpenEdges == 0;

  /// Randkanten, die es nur wegen doppelter Punkte gibt.
  int get seamEdges => rawOpenEdges - openEdges;
}

MeshCheckResult checkMeshWatertight(
    Float32List positions, Uint32List indices) {
  final vertexCount = positions.length ~/ 3;

  // Grenzen für die Quantisierung bestimmen.
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (var v = 0; v < vertexCount; v++) {
    final x = positions[v * 3], y = positions[v * 3 + 1],
        z = positions[v * 3 + 2];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;
  }
  var extent = maxX - minX;
  if (maxY - minY > extent) extent = maxY - minY;
  if (maxZ - minZ > extent) extent = maxZ - minZ;
  if (extent <= 0) extent = 1;
  final quantum = extent * 1e-5;

  // Vertices nach quantisierter Position verschweißen.
  final welded = Int32List(vertexCount);
  final canonical = <String, int>{};
  var weldedCount = 0;
  for (var v = 0; v < vertexCount; v++) {
    final key = '${(positions[v * 3] / quantum).round()}_'
        '${(positions[v * 3 + 1] / quantum).round()}_'
        '${(positions[v * 3 + 2] / quantum).round()}';
    welded[v] = canonical.putIfAbsent(key, () => weldedCount++);
  }

  // Ungerichtete Kanten zählen – einmal verschweißt, einmal roh.
  final edgeUse = <int, int>{};
  final rawEdgeUse = <int, int>{};
  var triangles = 0;
  for (var t = 0; t < indices.length; t += 3) {
    final ia = indices[t], ib = indices[t + 1], ic = indices[t + 2];
    final a = welded[ia];
    final b = welded[ib];
    final c = welded[ic];
    if (a == b || b == c || a == c) continue; // degeneriert
    triangles++;
    for (final (p, q) in [(a, b), (b, c), (c, a)]) {
      final low = p < q ? p : q;
      final high = p < q ? q : p;
      final key = low * weldedCount + high;
      edgeUse[key] = (edgeUse[key] ?? 0) + 1;
    }
    for (final (p, q) in [(ia, ib), (ib, ic), (ic, ia)]) {
      final low = p < q ? p : q;
      final high = p < q ? q : p;
      final key = low * vertexCount + high;
      rawEdgeUse[key] = (rawEdgeUse[key] ?? 0) + 1;
    }
  }

  var openEdges = 0;
  var nonManifoldEdges = 0;
  for (final count in edgeUse.values) {
    if (count == 1) {
      openEdges++;
    } else if (count > 2) {
      nonManifoldEdges++;
    }
  }
  var rawOpenEdges = 0;
  for (final count in rawEdgeUse.values) {
    if (count == 1) rawOpenEdges++;
  }
  return MeshCheckResult(
    triangles: triangles,
    openEdges: openEdges,
    rawOpenEdges: rawOpenEdges,
    nonManifoldEdges: nonManifoldEdges,
  );
}

/// Orientierung und Volumen eines Netzes.
///
/// Zwei Fehler, die eine reine Löcher-Prüfung nicht findet und die in
/// Spiele-Engines sofort auffallen:
///
/// * **Backfaces**: Zeigen die Normalen nach innen (oder sind sie
///   uneinheitlich gewickelt), ist das Modell von außen teilweise
///   unsichtbar. Messbar an gerichteten Kanten – bei einheitlicher
///   Wicklung kommt jede Kante genau einmal in jeder Richtung vor.
/// * **Nullstärke**: Eine hauchdünne Fläche (Umhang, Schleier, Blatt)
///   hat kein Volumen. Messbar am Verhältnis von eingeschlossenem
///   Volumen zur Ausdehnung.
class MeshOrientationResult {
  const MeshOrientationResult({
    required this.reversedEdges,
    required this.signedVolume,
    required this.partVolumes,
    required this.degenerateTriangles,
    required this.size,
  });

  /// Kanten, die zweimal in derselben Richtung vorkommen – dann sind
  /// die beiden angrenzenden Dreiecke gegenläufig gewickelt.
  final int reversedEdges;

  /// Eingeschlossenes Volumen mit Vorzeichen. Negativ heißt: Die
  /// Normalen zeigen insgesamt nach innen.
  final double signedVolume;

  /// Dreiecke ohne Fläche (zwei gleiche Ecken oder alle drei auf einer
  /// Linie).
  final int degenerateTriangles;

  /// Das vorzeichenbehaftete Volumen **je zusammenhängendem Teil**,
  /// größtes zuerst.
  ///
  /// Die Summe allein genügt nicht: Ein Modell aus Körper und fünf
  /// Gesichtsteilen kann insgesamt positiv sein und trotzdem eine
  /// nach innen gewickelte Kugel enthalten – der große positive
  /// Körper überdeckt sie. Genau so ist es passiert. Positiv heißt
  /// außen, und das gilt für jedes Teil einzeln.
  final List<double> partVolumes;

  /// Ausdehnung der Bounding Box in x, y, z.
  final List<double> size;

  /// Teile, deren Wicklung nach innen zeigt.
  int get invertedParts => partVolumes.where((v) => v < 0).length;

  double get largestSide => size.reduce((a, b) => a > b ? a : b);
  double get smallestSide => size.reduce((a, b) => a < b ? a : b);

  /// Verhältnis des Volumens zum Würfel der größten Kante – bei einer
  /// hauchdünnen Fläche praktisch null.
  double get volumeRatio {
    final side = largestSide;
    if (side <= 0) return 0;
    return signedVolume.abs() / (side * side * side);
  }

  bool get normalsInverted => signedVolume < 0;
  bool get windingConsistent => reversedEdges == 0;
}

/// Misst Wicklung, Volumen und degenerierte Flächen.
MeshOrientationResult checkMeshOrientation(
    Float32List positions, Uint32List indices) {
  final vertexCount = positions.length ~/ 3;
  final min = [double.infinity, double.infinity, double.infinity];
  final max = [
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  ];
  for (var v = 0; v < vertexCount; v++) {
    for (var k = 0; k < 3; k++) {
      final value = positions[v * 3 + k];
      if (value < min[k]) min[k] = value;
      if (value > max[k]) max[k] = value;
    }
  }
  final size = [
    for (var k = 0; k < 3; k++)
      max[k].isFinite && min[k].isFinite ? max[k] - min[k] : 0.0,
  ];

  // Für die Kantenrichtung müssen Vertices an derselben Stelle als
  // derselbe Punkt gelten – sonst zählt jede Naht als offene Kante.
  final welded = _weldByPosition(positions, size);
  final weldedCount = welded.isEmpty
      ? 0
      : welded.reduce((a, b) => a > b ? a : b) + 1;

  final directed = <int, int>{};
  var degenerate = 0;
  var volume = 0.0;
  for (var t = 0; t + 2 < indices.length; t += 3) {
    final ia = indices[t], ib = indices[t + 1], ic = indices[t + 2];
    final a = welded[ia], b = welded[ib], c = welded[ic];
    if (a == b || b == c || a == c) {
      degenerate++;
      continue;
    }
    // Signiertes Tetraeder-Volumen gegen den Ursprung; die Summe über
    // ein geschlossenes Netz ist das eingeschlossene Volumen.
    final ax = positions[ia * 3], ay = positions[ia * 3 + 1],
        az = positions[ia * 3 + 2];
    final bx = positions[ib * 3], by = positions[ib * 3 + 1],
        bz = positions[ib * 3 + 2];
    final cx = positions[ic * 3], cy = positions[ic * 3 + 1],
        cz = positions[ic * 3 + 2];
    final crossX = by * cz - bz * cy;
    final crossY = bz * cx - bx * cz;
    final crossZ = bx * cy - by * cx;
    final det = ax * crossX + ay * crossY + az * crossZ;
    if (det == 0) degenerate++;
    volume += det / 6.0;

    for (final (p, q) in [(a, b), (b, c), (c, a)]) {
      final key = p * weldedCount + q;
      directed[key] = (directed[key] ?? 0) + 1;
    }
  }

  // Eine Kante, die zweimal in derselben Richtung vorkommt, trennt zwei
  // gegenläufig gewickelte Dreiecke – auf einer Mantelkante mit genau
  // zwei Dreiecken. An einer Innenwand (drei und mehr an der Kante)
  // durchläuft eine Fläche die Kante zwangsläufig wie eine der beiden
  // anderen; das ist keine falsche Wicklung, sondern eine Innenwand,
  // und die zählt die Netzprüfung als nonManifoldEdges. Bei der ersten
  // Figur mit dem Marktplatz-Schwanz standen hier 42 Kanten, die die
  // Vereinheitlichung dann „behob", indem sie 1.737 Dreiecke drehte.
  var reversed = 0;
  for (final entry in directed.entries) {
    if (entry.value < 2) continue;
    final p = entry.key ~/ weldedCount, q = entry.key % weldedCount;
    final zurueck = directed[q * weldedCount + p] ?? 0;
    if (entry.value + zurueck != 2) continue;
    reversed++;
  }

  return MeshOrientationResult(
    reversedEdges: reversed,
    signedVolume: volume,
    partVolumes: _partVolumes(positions, indices, welded, weldedCount),
    degenerateTriangles: degenerate,
    size: size,
  );
}

/// Verschweißt Vertices mit (praktisch) gleicher Position und liefert
/// je Vertex den Index seines kanonischen Punktes.
Int32List _weldByPosition(Float32List positions, List<double> size) {
  final vertexCount = positions.length ~/ 3;
  var extent = size.reduce((a, b) => a > b ? a : b);
  if (extent <= 0) extent = 1;
  final quantum = extent * 1e-5;
  final welded = Int32List(vertexCount);
  final canonical = <String, int>{};
  var next = 0;
  for (var v = 0; v < vertexCount; v++) {
    final key = '${(positions[v * 3] / quantum).round()}_'
        '${(positions[v * 3 + 1] / quantum).round()}_'
        '${(positions[v * 3 + 2] / quantum).round()}';
    welded[v] = canonical.putIfAbsent(key, () => next++);
  }
  return welded;
}

/// Das vorzeichenbehaftete Volumen je zusammenhängendem Teil.
///
/// Zusammenhang wird über die **verschweißten** Punkte bestimmt – ein
/// Körper, dessen Textur ihn in UV-Inseln zerlegt, ist trotzdem ein
/// Teil. Das Volumen selbst kommt aus den echten Positionen, so wie
/// sie in der Datei stehen.
List<double> _partVolumes(Float32List positions, Uint32List indices,
    Int32List welded, int weldedCount) {
  if (weldedCount == 0) return const [];
  // Union-Find über die Dreieckskanten.
  final eltern = Int32List(weldedCount);
  for (var i = 0; i < weldedCount; i++) {
    eltern[i] = i;
  }
  int wurzel(int a) {
    var r = a;
    while (eltern[r] != r) {
      r = eltern[r];
    }
    // Pfad kürzen, sonst wird das bei zehntausend Dreiecken zäh.
    var k = a;
    while (eltern[k] != r) {
      final next = eltern[k];
      eltern[k] = r;
      k = next;
    }
    return r;
  }

  void verbinde(int a, int b) {
    final ra = wurzel(a), rb = wurzel(b);
    if (ra != rb) eltern[ra] = rb;
  }

  for (var t = 0; t + 2 < indices.length; t += 3) {
    final a = welded[indices[t]];
    final b = welded[indices[t + 1]];
    final c = welded[indices[t + 2]];
    verbinde(a, b);
    verbinde(b, c);
  }

  final proTeil = <int, double>{};
  for (var t = 0; t + 2 < indices.length; t += 3) {
    final ia = indices[t], ib = indices[t + 1], ic = indices[t + 2];
    final a = welded[ia], b = welded[ib], c = welded[ic];
    if (a == b || b == c || a == c) continue;
    final ax = positions[ia * 3], ay = positions[ia * 3 + 1],
        az = positions[ia * 3 + 2];
    final bx = positions[ib * 3], by = positions[ib * 3 + 1],
        bz = positions[ib * 3 + 2];
    final cx = positions[ic * 3], cy = positions[ic * 3 + 1],
        cz = positions[ic * 3 + 2];
    final det = ax * (by * cz - bz * cy) -
        ay * (bx * cz - bz * cx) +
        az * (bx * cy - by * cx);
    final schluessel = wurzel(a);
    proTeil[schluessel] = (proTeil[schluessel] ?? 0) + det / 6.0;
  }
  final werte = proTeil.values.toList()
    ..sort((a, b) => b.abs().compareTo(a.abs()));
  return werte;
}
