import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/mesh_check.dart';
import 'package:bildgenerator/services/roblox_check.dart';
import 'package:bildgenerator/services/roblox_fix.dart';

const _corners = [
  [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, 0.5, -0.5], [-0.5, 0.5, -0.5],
  [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5],
];

/// Die zwölf Dreiecke eines Würfels, alle nach außen gewickelt.
const _faces = [
  [0, 2, 1], [0, 3, 2], // hinten (-z)
  [4, 5, 6], [4, 6, 7], // vorn (+z)
  [0, 4, 7], [0, 7, 3], // links
  [1, 2, 6], [1, 6, 5], // rechts
  [3, 7, 6], [3, 6, 2], // oben
  [0, 1, 5], [0, 5, 4], // unten
];

Uint8List cube({int dropFaces = 0, List<int> flip = const []}) {
  final mesh = LocalMesh();
  for (final c in _corners) {
    mesh.addVertex(c[0], c[1], c[2], 0, 0, r: 0.7, g: 0.5, b: 0.3);
  }
  for (var i = 0; i < _faces.length - dropFaces; i++) {
    final f = _faces[i];
    if (flip.contains(i)) {
      mesh.addTriangle(f[0], f[2], f[1]);
    } else {
      mesh.addTriangle(f[0], f[1], f[2]);
    }
  }
  return buildGlb(mesh);
}

void main() {
  test('Ein Loch wird geschlossen', () async {
    // Zwei Dreiecke fehlen – das ist ein viereckiges Loch mit vier
    // offenen Kanten.
    final before = await readRobloxFacts(cube(dropFaces: 2));
    expect(before.openEdges, greaterThan(0));

    final fixed = fixGlbForRoblox(cube(dropFaces: 2));
    expect(fixed.report.filledHoles, 1);
    expect(fixed.report.addedTriangles, greaterThan(0));

    final after = await readRobloxFacts(fixed.glb);
    expect(after.openEdges, 0);
    // Die vorhandene Geometrie bleibt, es kommt nur der Deckel dazu.
    expect(after.triangles, greaterThan(before.triangles));
  });

  test('Eine falsch gewickelte Fläche wird gedreht', () async {
    final broken = cube(flip: const [3, 7]);
    final before = await readRobloxFacts(broken);
    expect(before.reversedEdges, greaterThan(0));

    final fixed = fixGlbForRoblox(broken);
    expect(fixed.report.flippedFaces, greaterThan(0));

    final after = await readRobloxFacts(fixed.glb);
    expect(after.reversedEdges, 0);
    // Und das Netz zeigt nach außen, nicht nach innen.
    expect(after.signedVolume, greaterThan(0));
  });

  test('Ein komplett nach innen gewickeltes Netz wird umgedreht',
      () async {
    final inside = cube(flip: List.generate(12, (i) => i));
    final before = await readRobloxFacts(inside);
    expect(before.signedVolume, lessThan(0));

    final fixed = fixGlbForRoblox(inside);
    final after = await readRobloxFacts(fixed.glb);
    expect(after.signedVolume, greaterThan(0));
    expect(after.reversedEdges, 0);
  });

  test('Ein heiles Netz bleibt unangetastet', () async {
    final fixed = fixGlbForRoblox(cube());
    expect(fixed.report.filledHoles, 0);
    expect(fixed.report.flippedFaces, 0);
    final after = await readRobloxFacts(fixed.glb);
    expect(after.openEdges, 0);
    expect(after.triangles, 12);
  });

  test('Der Maßstab bringt das Modell auf die Zielhöhe', () async {
    // Der Würfel ist 1 Einheit hoch; 5 Studs sind 1,4 m.
    final fixed = fixGlbForRoblox(cube(), targetStuds: 5);
    expect(fixed.report.scale, closeTo(5 * robloxStudMeters, 1e-6));
    expect(fixed.report.heightBefore, closeTo(1.0, 1e-5));

    final after = await readRobloxFacts(fixed.glb);
    // 5 Studs * 0,28 m = 1,4 m.
    expect(after.height, closeTo(1.4, 1e-3));
  });

  test('Ohne Zielhöhe bleibt die Größe', () async {
    final fixed = fixGlbForRoblox(cube());
    expect(fixed.report.scale, 1);
    final after = await readRobloxFacts(fixed.glb);
    expect(after.height, closeTo(1.0, 1e-5));
  });

  test('Die Prüfung meldet danach nichts mehr an der Geometrie',
      () async {
    final broken = cube(dropFaces: 2, flip: const [1, 5]);
    final fixed = fixGlbForRoblox(broken, targetStuds: 5);
    final facts = await readRobloxFacts(fixed.glb);
    final findings = checkRobloxFacts(facts, RobloxTarget.character);
    final open = findings
        .where((f) => f.level != RobloxLevel.ok)
        .map((f) => f.title)
        .join(' | ');
    expect(open, isNot(contains('Offene Kanten')));
    expect(open, isNot(contains('Uneinheitliche Wicklung')));
  });

  test('Die Normalen werden neu gerechnet', () {
    final fixed = fixGlbForRoblox(cube(flip: const [2]));
    expect(fixed.report.rebuiltNormals, greaterThan(0));
    expect(fixed.report.changed, isTrue);
  });

  test('Orientierungsprüfung bestätigt das Ergebnis', () async {
    final fixed = fixGlbForRoblox(cube(flip: const [4, 9]));
    final facts = await readRobloxFacts(fixed.glb);
    expect(facts.reversedEdges, 0);
    expect(checkMeshOrientation, isNotNull);
  });
}
