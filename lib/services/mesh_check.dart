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
    required this.nonManifoldEdges,
  });

  final int triangles;

  /// Kanten, die nur zu einem Dreieck gehören (Loch im Netz).
  final int openEdges;

  /// Kanten mit mehr als zwei Dreiecken (Berührungsstellen) – für
  /// Slicer in der Regel unkritisch.
  final int nonManifoldEdges;

  bool get watertight => openEdges == 0;
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

  // Ungerichtete Kanten zählen.
  final edgeUse = <int, int>{};
  var triangles = 0;
  for (var t = 0; t < indices.length; t += 3) {
    final a = welded[indices[t]];
    final b = welded[indices[t + 1]];
    final c = welded[indices[t + 2]];
    if (a == b || b == c || a == c) continue; // degeneriert
    triangles++;
    for (final (p, q) in [(a, b), (b, c), (c, a)]) {
      final low = p < q ? p : q;
      final high = p < q ? q : p;
      final key = low * weldedCount + high;
      edgeUse[key] = (edgeUse[key] ?? 0) + 1;
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
  return MeshCheckResult(
    triangles: triangles,
    openEdges: openEdges,
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

  /// Ausdehnung der Bounding Box in x, y, z.
  final List<double> size;

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
  // gegenläufig gewickelte Dreiecke.
  var reversed = 0;
  for (final entry in directed.entries) {
    if (entry.value > 1) reversed += entry.value - 1;
  }

  return MeshOrientationResult(
    reversedEdges: reversed,
    signedVolume: volume,
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
