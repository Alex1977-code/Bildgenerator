import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart' show splitGlb, joinGlb, gltfBufferViewBytes;
import 'roblox_check.dart' show robloxStudMeters;

/// Was die Reparatur getan hat.
class RobloxFixReport {
  const RobloxFixReport({
    this.filledHoles = 0,
    this.addedTriangles = 0,
    this.flippedFaces = 0,
    this.rebuiltNormals = 0,
    this.degenerateRemoved = 0,
    this.scale = 1,
    this.heightBefore = 0,
    this.heightAfter = 0,
    this.skipped = const [],
  });

  final int filledHoles;
  final int addedTriangles;
  final int flippedFaces;
  final int rebuiltNormals;

  /// Dreiecke ohne nennenswerte Fläche, die entfernt wurden. Roblox'
  /// Marktplatz-Validator lehnt sie ab (`TriangleAreaValid`).
  final int degenerateRemoved;

  final double scale;
  final double heightBefore;
  final double heightAfter;

  /// Was bewusst nicht angefasst wurde, mit Begründung.
  final List<String> skipped;

  bool get changed =>
      filledHoles > 0 ||
      flippedFaces > 0 ||
      rebuiltNormals > 0 ||
      degenerateRemoved > 0 ||
      (scale - 1).abs() > 1e-6;
}

class RobloxFixResult {
  const RobloxFixResult(this.glb, this.report);
  final Uint8List glb;
  final RobloxFixReport report;
}

/// Bringt ein Modell auf die Punkte, an denen die Roblox-Prüfung
/// hängenbleibt – so weit sich das rechnen lässt.
///
/// Drei Eingriffe, jeder einzeln abschaltbar:
///
/// * **Löcher schließen.** Kanten, die nur zu einem Dreieck gehören,
///   bilden den Rand eines Lochs. Die Ränder werden zu Schleifen
///   zusammengesetzt und als Fächer geschlossen – ohne neue Vertices,
///   damit UVs, Farben und Gewichte unangetastet bleiben.
/// * **Wicklung vereinheitlichen.** Benachbarte Dreiecke müssen ihre
///   gemeinsame Kante gegenläufig durchlaufen. Ein Flutfüllen dreht
///   die Ausreißer um; zeigt danach das ganze Netz nach innen
///   (negatives Volumen), wird alles gedreht. Anschließend werden die
///   Normalen neu gerechnet.
/// * **Maßstab.** glTF rechnet in Metern, der Roblox-Importer in
///   Studs (1 Stud ≈ 0,28 m). Ein Skalierungsknoten über der Szene
///   bringt das Modell auf die Zielhöhe – das wirkt auch auf ein
///   Skelett, weil die Gelenke mit darunter hängen.
RobloxFixResult fixGlbForRoblox(
  Uint8List glb, {
  double targetStuds = 0,
  bool closeHoles = true,
  bool fixWinding = true,
}) {
  final parts = splitGlb(glb);
  final json = parts.json;
  var bin = parts.bin;

  var filledHoles = 0;
  var addedTriangles = 0;
  var flippedFaces = 0;
  var rebuiltNormals = 0;
  var degenerateRemoved = 0;
  final skipped = <String>[];

  final meshes = (json['meshes'] as List?) ?? const [];
  final replacement = <int, Uint8List>{};

  for (final meshRaw in meshes) {
    final primitives =
        ((meshRaw as Map<String, dynamic>)['primitives'] as List?) ??
            const [];
    for (final primRaw in primitives) {
      final prim = primRaw as Map<String, dynamic>;
      // Nur Dreiecksnetze; alles andere lässt sich so nicht rechnen.
      final mode = (prim['mode'] as num?)?.toInt() ?? 4;
      if (mode != 4) {
        skipped.add('Ein Teilnetz ist kein Dreiecksnetz (mode $mode).');
        continue;
      }
      final attributes = prim['attributes'] as Map<String, dynamic>?;
      final positionIndex = (attributes?['POSITION'] as num?)?.toInt();
      final indexIndex = (prim['indices'] as num?)?.toInt();
      if (positionIndex == null || indexIndex == null) {
        skipped.add('Ein Teilnetz hat keine Indexliste – dort lässt '
            'sich weder ein Loch finden noch eine Wicklung prüfen.');
        continue;
      }
      final positions = _readFloats(json, bin, positionIndex, 3);
      var indices = _readIndices(json, bin, indexIndex);
      if (positions.isEmpty || indices.length < 3) continue;

      if (closeHoles) {
        final filled = _closeHoles(positions, indices);
        if (filled.added.isNotEmpty) {
          indices = Uint32List.fromList([...indices, ...filled.added]);
          filledHoles += filled.loops;
          addedTriangles += filled.added.length ~/ 3;
        }
      }
      if (fixWinding) {
        flippedFaces += _makeWindingConsistent(positions, indices);
      }
      // Zuletzt die nullflächigen Dreiecke – auch die, die schon in
      // der Datei standen. Der Marktplatz-Validator lehnt sie ab, und
      // beim Deckeln können neue entstanden sein.
      if (closeHoles || fixWinding) {
        final (gesaeubert, weg) =
            _dropDegenerateTriangles(positions, indices);
        indices = gesaeubert;
        degenerateRemoved += weg;
      }

      replacement[_bufferViewOf(json, indexIndex)] =
          _packIndices(json, indexIndex, indices);

      // Normalen zur neuen Wicklung – sonst zeigen sie weiter in die
      // alte Richtung und das Modell bleibt von außen dunkel.
      final normalIndex = (attributes?['NORMAL'] as num?)?.toInt();
      if (normalIndex != null && (fixWinding || closeHoles)) {
        final normals = _smoothNormals(positions, indices);
        replacement[_bufferViewOf(json, normalIndex)] =
            _packFloats(json, normalIndex, normals);
        rebuiltNormals++;
      }
    }
  }

  if (replacement.isNotEmpty) {
    bin = _repackBuffer(json, bin, replacement);
  }

  // Maßstab zuletzt: Er hängt an der fertigen Geometrie.
  var scale = 1.0;
  var heightBefore = 0.0;
  var heightAfter = 0.0;
  if (targetStuds > 0) {
    heightBefore = _modelHeight(json, bin);
    final target = targetStuds * robloxStudMeters;
    if (heightBefore > 1e-6 && (heightBefore - target).abs() > 1e-4) {
      scale = target / heightBefore;
      // Ohne Skelett wird der Maßstab in die Punkte gerechnet: Dann
      // sieht ihn jedes Werkzeug, auch eines, das Knotenmatrizen
      // ignoriert. Mit Skelett geht das nicht – Gelenke und
      // Bind-Matrizen müssten mitgerechnet werden –, dort kommt ein
      // Knoten darüber.
      final skins = (json['skins'] as List?) ?? const [];
      if (skins.isEmpty) {
        bin = _scalePositions(json, bin, scale);
      } else {
        _applyRootScale(json, scale);
      }
      heightAfter = target;
    } else {
      heightAfter = heightBefore;
    }
  }

  return RobloxFixResult(
    joinGlb(json, bin),
    RobloxFixReport(
      filledHoles: filledHoles,
      addedTriangles: addedTriangles,
      flippedFaces: flippedFaces,
      rebuiltNormals: rebuiltNormals,
      degenerateRemoved: degenerateRemoved,
      scale: scale,
      heightBefore: heightBefore,
      heightAfter: heightAfter,
      skipped: skipped,
    ),
  );
}

// ----------------------------------------------------------------
// Geometrie
// ----------------------------------------------------------------

/// Schließt die Löcher eines Netzes.
///
/// Eine Kante, die nur zu einem Dreieck gehört, liegt am Rand eines
/// Lochs. Die Ränder ergeben aneinandergereiht geschlossene
/// Schleifen; jede wird als Fächer vom ersten Punkt aus
/// trianguliert. Bewusst **ohne neue Vertices**: Ein zusätzlicher
/// Mittelpunkt bräuchte auch UV, Farbe, Normale und Gewichte, und
/// jede dieser Erfindungen wäre an der Naht sichtbar.
({int loops, List<int> added}) _closeHoles(
    Float32List positions, Uint32List indices) {
  final weld = _weldByPosition(positions);
  // Gerichtete Randkanten: Vorkommen zählen, dann bleibt nur der Rand.
  final counts = <int, int>{};
  int key(int a, int b) => a < b ? a * 0x100000 + b : b * 0x100000 + a;
  for (var i = 0; i + 2 < indices.length; i += 3) {
    final a = weld[indices[i]];
    final b = weld[indices[i + 1]];
    final c = weld[indices[i + 2]];
    if (a == b || b == c || a == c) continue;
    counts.update(key(a, b), (v) => v + 1, ifAbsent: () => 1);
    counts.update(key(b, c), (v) => v + 1, ifAbsent: () => 1);
    counts.update(key(c, a), (v) => v + 1, ifAbsent: () => 1);
  }
  // Die Randkanten in ihrer gerichteten Form einsammeln – die
  // Richtung entscheidet später, wie herum der Deckel liegt.
  final next = <int, int>{};
  // Ein Vertex kann zu mehreren Löchern gehören; dann wird nur das
  // erste geschlossen. Mehr wäre geraten.
  final original = <int, int>{}; // verschweißter Index -> Originalindex
  for (var i = 0; i + 2 < indices.length; i += 3) {
    final tri = [indices[i], indices[i + 1], indices[i + 2]];
    for (var e = 0; e < 3; e++) {
      final from = weld[tri[e]];
      final to = weld[tri[(e + 1) % 3]];
      if (from == to) continue;
      if (counts[key(from, to)] != 1) continue;
      // Der Deckel läuft gegenläufig zur offenen Kante.
      next.putIfAbsent(to, () => from);
      original.putIfAbsent(from, () => tri[e]);
      original.putIfAbsent(to, () => tri[(e + 1) % 3]);
    }
  }

  final added = <int>[];
  var loops = 0;
  final visited = <int>{};
  for (final start in next.keys.toList()) {
    if (visited.contains(start)) continue;
    final loop = <int>[];
    var current = start;
    while (!visited.contains(current)) {
      visited.add(current);
      loop.add(current);
      final step = next[current];
      if (step == null) break;
      current = step;
      if (current == start) break;
    }
    if (loop.length < 3 || current != start) continue;
    // Sehr große Schleifen sind kein Loch, sondern ein offenes Netz
    // (eine Ebene etwa). Die zuzukleben ergäbe Unsinn.
    if (loop.length > 512) continue;
    loops++;
    final ring = [for (final v in loop) original[v]!];
    added.addAll(_triangulateLoop(positions, ring));
  }
  return (loops: loops, added: added);
}

/// Trianguliert eine Randschleife durch **Ear Clipping** in ihrer
/// eigenen Ebene.
///
/// Vorher lag hier ein Fächer: alles vom ersten Punkt aus. Für ein
/// rundes Loch geht das, für eine langgezogene oder eingebuchtete
/// Schleife nicht – dort entstehen extrem schmale und teils
/// nullflächige Dreiecke. Genau die lehnt Roblox' Marktplatz-Validator
/// ab (`TriangleAreaValid`), und im Spiel flimmern sie.
///
/// Ear Clipping schneidet stattdessen immer die Ecke ab, die
/// tatsächlich frei liegt. Gearbeitet wird in 2D: Die Schleife wird
/// auf ihre Ausgleichsebene projiziert (Normale nach Newell), damit
/// „links" und „rechts" überhaupt eine Bedeutung haben.
List<int> _triangulateLoop(Float32List positions, List<int> ring) {
  if (ring.length < 3) return const [];
  if (ring.length == 3) return [ring[0], ring[1], ring[2]];

  // Newell-Normale: funktioniert auch für eine leicht gewellte
  // Schleife, während ein Kreuzprodukt aus drei Punkten dort kippt.
  var nx = 0.0, ny = 0.0, nz = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i] * 3, b = ring[(i + 1) % ring.length] * 3;
    final ax = positions[a], ay = positions[a + 1], az = positions[a + 2];
    final bx = positions[b], by = positions[b + 1], bz = positions[b + 2];
    nx += (ay - by) * (az + bz);
    ny += (az - bz) * (ax + bx);
    nz += (ax - bx) * (ay + by);
  }
  final laenge = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (laenge < 1e-12) return const [];
  nx /= laenge;
  ny /= laenge;
  nz /= laenge;

  // Zwei Achsen in der Ebene aufspannen.
  final hilfsX = nx.abs() < 0.9 ? 1.0 : 0.0;
  final hilfsY = nx.abs() < 0.9 ? 0.0 : 1.0;
  var ux = ny * 0.0 - nz * hilfsY;
  var uy = nz * hilfsX - nx * 0.0;
  var uz = nx * hilfsY - ny * hilfsX;
  final ul = math.sqrt(ux * ux + uy * uy + uz * uz);
  if (ul < 1e-12) return const [];
  ux /= ul;
  uy /= ul;
  uz /= ul;
  final vx = ny * uz - nz * uy;
  final vy = nz * ux - nx * uz;
  final vz = nx * uy - ny * ux;

  final px = <double>[], py = <double>[];
  for (final index in ring) {
    final o = index * 3;
    px.add(positions[o] * ux + positions[o + 1] * uy + positions[o + 2] * uz);
    py.add(positions[o] * vx + positions[o + 1] * vy + positions[o + 2] * vz);
  }

  double flaeche2(int a, int b, int c) =>
      (px[b] - px[a]) * (py[c] - py[a]) -
      (px[c] - px[a]) * (py[b] - py[a]);

  // Umlaufsinn der ganzen Schleife.
  var summe = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final j = (i + 1) % ring.length;
    summe += px[i] * py[j] - px[j] * py[i];
  }
  final gegenUhrzeiger = summe > 0;

  final offen = [for (var i = 0; i < ring.length; i++) i];
  final out = <int>[];
  var wachhund = offen.length * offen.length;
  while (offen.length > 3 && wachhund-- > 0) {
    var geschnitten = false;
    for (var k = 0; k < offen.length; k++) {
      final a = offen[(k - 1 + offen.length) % offen.length];
      final b = offen[k];
      final c = offen[(k + 1) % offen.length];
      final f = flaeche2(a, b, c);
      // Konvex im Sinne des Umlaufs? Eine nullflächige Ecke wird hier
      // nicht abgeschnitten, sondern fällt am Ende weg.
      if (gegenUhrzeiger ? f <= 1e-12 : f >= -1e-12) continue;
      // Kein anderer Punkt darf im Ohr liegen.
      var frei = true;
      for (final m in offen) {
        if (m == a || m == b || m == c) continue;
        final d1 = (px[b] - px[a]) * (py[m] - py[a]) -
            (px[m] - px[a]) * (py[b] - py[a]);
        final d2 = (px[c] - px[b]) * (py[m] - py[b]) -
            (px[m] - px[b]) * (py[c] - py[b]);
        final d3 = (px[a] - px[c]) * (py[m] - py[c]) -
            (px[m] - px[c]) * (py[a] - py[c]);
        final negativ = d1 < 0 || d2 < 0 || d3 < 0;
        final positiv = d1 > 0 || d2 > 0 || d3 > 0;
        if (!(negativ && positiv)) {
          frei = false;
          break;
        }
      }
      if (!frei) continue;
      out.addAll([ring[a], ring[b], ring[c]]);
      offen.removeAt(k);
      geschnitten = true;
      break;
    }
    // Findet sich kein Ohr (selbstüberschneidende Schleife), bleibt
    // der Fächer als Notnagel – besser ein grober Deckel als ein Loch.
    if (!geschnitten) {
      for (var i = 1; i + 1 < offen.length; i++) {
        out.addAll([ring[offen[0]], ring[offen[i]], ring[offen[i + 1]]]);
      }
      return out;
    }
  }
  if (offen.length == 3) {
    out.addAll([ring[offen[0]], ring[offen[1]], ring[offen[2]]]);
  }
  return out;
}

/// Wirft Dreiecke ohne nennenswerte Fläche weg.
///
/// Roblox' Marktplatz-Validator prüft das eigens (`TriangleAreaValid`,
/// `VerticesNotCoincident`). Solche Dreiecke entstehen nicht nur beim
/// Deckeln – manche Generatoren liefern sie mit, und beim Verschweißen
/// fallen weitere an. Die Schwelle ist relativ zur Modellgröße, damit
/// sie bei einer Figur in Metern dasselbe bedeutet wie bei einer in
/// Zentimetern.
(Uint32List, int) _dropDegenerateTriangles(
    Float32List positions, Uint32List indices) {
  if (indices.length < 3) return (indices, 0);
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (var i = 0; i + 2 < positions.length; i += 3) {
    minX = math.min(minX, positions[i]);
    maxX = math.max(maxX, positions[i]);
    minY = math.min(minY, positions[i + 1]);
    maxY = math.max(maxY, positions[i + 1]);
    minZ = math.min(minZ, positions[i + 2]);
    maxZ = math.max(maxZ, positions[i + 2]);
  }
  final groesse = math.max(
      maxX - minX, math.max(maxY - minY, maxZ - minZ));
  if (!groesse.isFinite || groesse <= 0) return (indices, 0);
  // 1e-7 der Modellfläche: klein genug, dass keine echte Facette
  // trifft, groß genug für alles, was aus Rundung entsteht.
  final schwelle = groesse * groesse * 1e-7;

  final bleibt = <int>[];
  var weg = 0;
  for (var t = 0; t + 2 < indices.length; t += 3) {
    final a = indices[t] * 3, b = indices[t + 1] * 3, c = indices[t + 2] * 3;
    if (a + 2 >= positions.length ||
        b + 2 >= positions.length ||
        c + 2 >= positions.length) {
      weg++;
      continue;
    }
    if (indices[t] == indices[t + 1] ||
        indices[t + 1] == indices[t + 2] ||
        indices[t] == indices[t + 2]) {
      weg++;
      continue;
    }
    final ux = positions[b] - positions[a];
    final uy = positions[b + 1] - positions[a + 1];
    final uz = positions[b + 2] - positions[a + 2];
    final vx = positions[c] - positions[a];
    final vy = positions[c + 1] - positions[a + 1];
    final vz = positions[c + 2] - positions[a + 2];
    final cx = uy * vz - uz * vy;
    final cy = uz * vx - ux * vz;
    final cz = ux * vy - uy * vx;
    final flaeche = math.sqrt(cx * cx + cy * cy + cz * cz) / 2;
    if (flaeche < schwelle) {
      weg++;
      continue;
    }
    bleibt.addAll([indices[t], indices[t + 1], indices[t + 2]]);
  }
  if (weg == 0) return (indices, 0);
  return (Uint32List.fromList(bleibt), weg);
}

/// Dreht Dreiecke so, dass benachbarte dieselbe Kante gegenläufig
/// durchlaufen, und kehrt am Ende das ganze Netz um, wenn es nach
/// innen zeigt. Liefert die Zahl der gedrehten Dreiecke.
int _makeWindingConsistent(Float32List positions, Uint32List indices) {
  final weld = _weldByPosition(positions);
  final faceCount = indices.length ~/ 3;
  if (faceCount == 0) return 0;

  // Kante (ungerichtet) -> anliegende Dreiecke.
  final edgeFaces = <int, List<int>>{};
  int key(int a, int b) => a < b ? a * 0x100000 + b : b * 0x100000 + a;
  for (var f = 0; f < faceCount; f++) {
    final a = weld[indices[f * 3]];
    final b = weld[indices[f * 3 + 1]];
    final c = weld[indices[f * 3 + 2]];
    for (final (u, v) in [(a, b), (b, c), (c, a)]) {
      if (u == v) continue;
      edgeFaces.putIfAbsent(key(u, v), () => <int>[]).add(f);
    }
  }

  void flip(int f) {
    final tmp = indices[f * 3 + 1];
    indices[f * 3 + 1] = indices[f * 3 + 2];
    indices[f * 3 + 2] = tmp;
  }

  bool sameDirection(int f, int u, int v) {
    final a = weld[indices[f * 3]];
    final b = weld[indices[f * 3 + 1]];
    final c = weld[indices[f * 3 + 2]];
    return (a == u && b == v) || (b == u && c == v) || (c == u && a == v);
  }

  var flipped = 0;
  final seen = List<bool>.filled(faceCount, false);
  for (var startFace = 0; startFace < faceCount; startFace++) {
    if (seen[startFace]) continue;
    // Jede zusammenhängende Insel für sich – ein Modell kann aus
    // mehreren Teilen bestehen.
    final queue = <int>[startFace];
    seen[startFace] = true;
    while (queue.isNotEmpty) {
      final f = queue.removeLast();
      final a = weld[indices[f * 3]];
      final b = weld[indices[f * 3 + 1]];
      final c = weld[indices[f * 3 + 2]];
      for (final (u, v) in [(a, b), (b, c), (c, a)]) {
        if (u == v) continue;
        for (final other in edgeFaces[key(u, v)] ?? const <int>[]) {
          if (other == f || seen[other]) continue;
          // Der Nachbar muss die Kante andersherum durchlaufen.
          if (sameDirection(other, u, v)) {
            flip(other);
            flipped++;
          }
          seen[other] = true;
          queue.add(other);
        }
      }
    }
  }

  // Zeigt das Ganze nach innen, ist jedes Dreieck falsch herum.
  if (_signedVolume(positions, indices) < 0) {
    for (var f = 0; f < faceCount; f++) {
      flip(f);
    }
    flipped = faceCount - flipped;
  }
  return flipped;
}

/// Eingeschlossenes Volumen über Tetraeder zum Ursprung.
double _signedVolume(Float32List positions, Uint32List indices) {
  var volume = 0.0;
  for (var i = 0; i + 2 < indices.length; i += 3) {
    final a = indices[i] * 3, b = indices[i + 1] * 3, c = indices[i + 2] * 3;
    final ax = positions[a], ay = positions[a + 1], az = positions[a + 2];
    final bx = positions[b], by = positions[b + 1], bz = positions[b + 2];
    final cx = positions[c], cy = positions[c + 1], cz = positions[c + 2];
    volume += (ax * (by * cz - bz * cy) -
            ay * (bx * cz - bz * cx) +
            az * (bx * cy - by * cx)) /
        6.0;
  }
  return volume;
}

/// Glatte Normalen aus der aktuellen Wicklung.
Float32List _smoothNormals(Float32List positions, Uint32List indices) {
  final out = Float32List(positions.length);
  for (var i = 0; i + 2 < indices.length; i += 3) {
    final a = indices[i] * 3, b = indices[i + 1] * 3, c = indices[i + 2] * 3;
    final ux = positions[b] - positions[a];
    final uy = positions[b + 1] - positions[a + 1];
    final uz = positions[b + 2] - positions[a + 2];
    final vx = positions[c] - positions[a];
    final vy = positions[c + 1] - positions[a + 1];
    final vz = positions[c + 2] - positions[a + 2];
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    for (final o in [a, b, c]) {
      out[o] += nx;
      out[o + 1] += ny;
      out[o + 2] += nz;
    }
  }
  for (var i = 0; i + 2 < out.length; i += 3) {
    final len = math.sqrt(out[i] * out[i] +
        out[i + 1] * out[i + 1] +
        out[i + 2] * out[i + 2]);
    if (len < 1e-12) {
      out[i + 1] = 1;
      continue;
    }
    out[i] /= len;
    out[i + 1] /= len;
    out[i + 2] /= len;
  }
  return out;
}

/// Vertices mit praktisch gleicher Position bekommen denselben Index –
/// sonst zählt jede Naht zwischen zwei Primitiven als Loch.
Int32List _weldByPosition(Float32List positions) {
  final count = positions.length ~/ 3;
  final map = Int32List(count);
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  for (var i = 0; i < count; i++) {
    minX = math.min(minX, positions[i * 3]);
    maxX = math.max(maxX, positions[i * 3]);
    minY = math.min(minY, positions[i * 3 + 1]);
    maxY = math.max(maxY, positions[i * 3 + 1]);
    minZ = math.min(minZ, positions[i * 3 + 2]);
    maxZ = math.max(maxZ, positions[i * 3 + 2]);
  }
  final extent = math.max(maxX - minX, math.max(maxY - minY, maxZ - minZ));
  final grid = extent <= 0 ? 1.0 : extent * 1e-5;
  final buckets = <String, int>{};
  for (var i = 0; i < count; i++) {
    final gx = (positions[i * 3] / grid).round();
    final gy = (positions[i * 3 + 1] / grid).round();
    final gz = (positions[i * 3 + 2] / grid).round();
    map[i] = buckets.putIfAbsent('$gx|$gy|$gz', () => i);
  }
  return map;
}

// ----------------------------------------------------------------
// glTF: lesen, schreiben, packen
// ----------------------------------------------------------------

const Map<int, int> _componentSize = {
  5120: 1, // byte
  5121: 1, // unsigned byte
  5122: 2, // short
  5123: 2, // unsigned short
  5125: 4, // unsigned int
  5126: 4, // float
};

Map<String, dynamic> _accessor(Map<String, dynamic> json, int index) =>
    (json['accessors'] as List)[index] as Map<String, dynamic>;

int _bufferViewOf(Map<String, dynamic> json, int accessorIndex) =>
    (_accessor(json, accessorIndex)['bufferView'] as num).toInt();

/// Byte-Abstand zwischen zwei Elementen – ohne Angabe liegen sie
/// dicht an dicht.
int _stride(Map<String, dynamic> json, int accessorIndex, int elementSize) {
  final view = (json['bufferViews'] as List)[
      _bufferViewOf(json, accessorIndex)] as Map<String, dynamic>;
  final stride = (view['byteStride'] as num?)?.toInt() ?? 0;
  return stride > 0 ? stride : elementSize;
}

Float32List _readFloats(
    Map<String, dynamic> json, Uint8List bin, int index, int components) {
  final acc = _accessor(json, index);
  final count = (acc['count'] as num).toInt();
  final offset = (acc['byteOffset'] as num?)?.toInt() ?? 0;
  final bytes = gltfBufferViewBytes(json, bin, _bufferViewOf(json, index));
  final data = ByteData.sublistView(bytes);
  final stride = _stride(json, index, 4 * components);
  final out = Float32List(count * components);
  for (var i = 0; i < count; i++) {
    for (var c = 0; c < components; c++) {
      out[i * components + c] =
          data.getFloat32(offset + i * stride + c * 4, Endian.little);
    }
  }
  return out;
}

Uint32List _readIndices(
    Map<String, dynamic> json, Uint8List bin, int index) {
  final acc = _accessor(json, index);
  final count = (acc['count'] as num).toInt();
  final type = (acc['componentType'] as num).toInt();
  final size = _componentSize[type] ?? 4;
  final offset = (acc['byteOffset'] as num?)?.toInt() ?? 0;
  final bytes = gltfBufferViewBytes(json, bin, _bufferViewOf(json, index));
  final data = ByteData.sublistView(bytes);
  final out = Uint32List(count);
  for (var i = 0; i < count; i++) {
    final at = offset + i * size;
    out[i] = switch (size) {
      1 => data.getUint8(at),
      2 => data.getUint16(at, Endian.little),
      _ => data.getUint32(at, Endian.little),
    };
  }
  return out;
}

/// Schreibt Indizes in einen frischen bufferView und passt den
/// Accessor an. Der Typ wächst mit, wenn die Zahlen größer werden.
Uint8List _packIndices(
    Map<String, dynamic> json, int index, Uint32List values) {
  final acc = _accessor(json, index);
  var max = 0;
  for (final v in values) {
    if (v > max) max = v;
  }
  final type = max > 0xFFFF ? 5125 : (max > 0xFF ? 5123 : 5121);
  final size = _componentSize[type]!;
  final out = Uint8List(values.length * size);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < values.length; i++) {
    switch (size) {
      case 1:
        data.setUint8(i, values[i]);
      case 2:
        data.setUint16(i * 2, values[i], Endian.little);
      default:
        data.setUint32(i * 4, values[i], Endian.little);
    }
  }
  acc['count'] = values.length;
  acc['componentType'] = type;
  acc['byteOffset'] = 0;
  return out;
}

/// Schreibt Fließkommawerte (VEC3) in einen frischen bufferView.
Uint8List _packFloats(
    Map<String, dynamic> json, int index, Float32List values) {
  final acc = _accessor(json, index);
  final out = Uint8List(values.length * 4);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  acc['count'] = values.length ~/ 3;
  acc['byteOffset'] = 0;
  // Der eigene bufferView hat keinen Abstand mehr zwischen den
  // Elementen; ein geerbter byteStride wäre danach falsch.
  final view = (json['bufferViews'] as List)[
      _bufferViewOf(json, index)] as Map<String, dynamic>;
  view.remove('byteStride');
  return out;
}

/// Baut den Binärteil neu auf – wie beim Verkleinern der Texturen.
/// Accessoren zeigen über den Index auf ihren bufferView, die
/// Reihenfolge bleibt also erhalten.
Uint8List _repackBuffer(
  Map<String, dynamic> json,
  Uint8List bin,
  Map<int, Uint8List> replacement,
) {
  final views = json['bufferViews'] as List;
  int pad4(int n) => (n + 3) & ~3;
  final chunks = <Uint8List>[];
  var total = 0;
  for (var i = 0; i < views.length; i++) {
    final view = views[i] as Map<String, dynamic>;
    final data = replacement[i] ?? gltfBufferViewBytes(json, bin, i);
    view['byteOffset'] = total;
    view['byteLength'] = data.length;
    chunks.add(data);
    total += pad4(data.length);
  }
  final out = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += pad4(chunk.length);
  }
  final buffers = json['buffers'] as List?;
  if (buffers != null && buffers.isNotEmpty) {
    (buffers.first as Map<String, dynamic>)['byteLength'] = total;
  }
  return out;
}

/// Höhe des Modells aus den POSITION-Grenzen aller Primitive.
double _modelHeight(Map<String, dynamic> json, Uint8List bin) {
  var min = double.infinity;
  var max = -double.infinity;
  for (final meshRaw in (json['meshes'] as List?) ?? const []) {
    for (final primRaw in
        ((meshRaw as Map<String, dynamic>)['primitives'] as List?) ??
            const []) {
      final index = (((primRaw as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>?)?['POSITION'] as num?)
          ?.toInt();
      if (index == null) continue;
      final acc = _accessor(json, index);
      final accMin = acc['min'] as List?;
      final accMax = acc['max'] as List?;
      if (accMin != null && accMax != null && accMin.length > 1) {
        min = math.min(min, (accMin[1] as num).toDouble());
        max = math.max(max, (accMax[1] as num).toDouble());
        continue;
      }
      final values = _readFloats(json, bin, index, 3);
      for (var i = 1; i < values.length; i += 3) {
        min = math.min(min, values[i]);
        max = math.max(max, values[i]);
      }
    }
  }
  if (min > max) return 0;
  return max - min;
}

/// Legt einen Knoten mit gleichmäßiger Skalierung über die Szene.
///
/// Absichtlich kein Umrechnen der Vertices: Ein Skelett hängt an
/// Gelenkknoten mit eigenen Transformationen und Bind-Matrizen –
/// die müssten sonst alle mitgerechnet werden. Ein Knoten darüber
/// wirkt auf beides.
void _applyRootScale(Map<String, dynamic> json, double scale) {
  final nodes = (json['nodes'] as List?) ?? [];
  final scenes = (json['scenes'] as List?) ?? [];
  if (nodes.isEmpty || scenes.isEmpty) return;
  final sceneIndex = (json['scene'] as num?)?.toInt() ?? 0;
  if (sceneIndex >= scenes.length) return;
  final scene = scenes[sceneIndex] as Map<String, dynamic>;
  final roots = ((scene['nodes'] as List?) ?? []).cast<int>();
  if (roots.isEmpty) return;
  // Steht dort schon ein einzelner Knoten ohne eigene Aufgabe, wird
  // dessen Skalierung nachgezogen statt einen weiteren zu stapeln.
  if (roots.length == 1) {
    final existing = nodes[roots.first] as Map<String, dynamic>;
    if (!existing.containsKey('mesh') &&
        !existing.containsKey('matrix') &&
        !existing.containsKey('skin')) {
      final current = (existing['scale'] as List?)?.cast<num>() ??
          const [1, 1, 1];
      existing['scale'] = [
        current[0] * scale,
        current[1] * scale,
        current[2] * scale,
      ];
      return;
    }
  }
  nodes.add(<String, dynamic>{
    'name': 'roblox_scale',
    'scale': [scale, scale, scale],
    'children': roots,
  });
  scene['nodes'] = [nodes.length - 1];
}


/// Rechnet den Maßstab in die Punkte – nur für Netze ohne Skelett.
Uint8List _scalePositions(
    Map<String, dynamic> json, Uint8List bin, double scale) {
  final replacement = <int, Uint8List>{};
  final seen = <int>{};
  for (final meshRaw in (json['meshes'] as List?) ?? const []) {
    for (final primRaw in
        ((meshRaw as Map<String, dynamic>)['primitives'] as List?) ??
            const []) {
      final index = (((primRaw as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>?)?['POSITION'] as num?)
          ?.toInt();
      if (index == null || !seen.add(index)) continue;
      final values = _readFloats(json, bin, index, 3);
      for (var i = 0; i < values.length; i++) {
        values[i] *= scale;
      }
      replacement[_bufferViewOf(json, index)] =
          _packFloats(json, index, values);
      // min/max gehören zum Accessor und werden von Importern
      // geglaubt – ohne Nachziehen stünde dort die alte Größe.
      final acc = _accessor(json, index);
      final min = (acc['min'] as List?)?.cast<num>();
      final max = (acc['max'] as List?)?.cast<num>();
      if (min != null) acc['min'] = [for (final v in min) v * scale];
      if (max != null) acc['max'] = [for (final v in max) v * scale];
    }
  }
  return replacement.isEmpty ? bin : _repackBuffer(json, bin, replacement);
}
