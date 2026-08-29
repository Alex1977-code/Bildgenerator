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
