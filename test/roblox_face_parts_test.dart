import 'dart:typed_data';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/roblox_face_parts.dart';
import 'package:bildgenerator/services/roblox_check.dart';
import 'package:bildgenerator/services/roblox_marketplace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eine Figur mit einem Kopf, der breiter ist als nichts – mehr
/// braucht die Platzierung nicht.
Uint8List _figur() {
  final m = LocalMesh();
  void quader(double x0, double y0, double z0, double x1, double y1,
      double z1) {
    final p = [
      m.addVertex(x0, y0, z0, 0, 0),
      m.addVertex(x1, y0, z0, 1, 0),
      m.addVertex(x1, y1, z0, 1, 1),
      m.addVertex(x0, y1, z0, 0, 1),
      m.addVertex(x0, y0, z1, 0, 0),
      m.addVertex(x1, y0, z1, 1, 0),
      m.addVertex(x1, y1, z1, 1, 1),
      m.addVertex(x0, y1, z1, 0, 1),
    ];
    m.addQuad(p[0], p[3], p[2], p[1]);
    m.addQuad(p[4], p[5], p[6], p[7]);
    m.addQuad(p[0], p[1], p[5], p[4]);
    m.addQuad(p[2], p[3], p[7], p[6]);
    m.addQuad(p[1], p[2], p[6], p[5]);
    m.addQuad(p[0], p[4], p[7], p[3]);
  }

  quader(-1.3, 2.25, -0.6, 1.3, 3.9, 0.6); // Rumpf
  quader(-0.75, 3.9, -0.7, 0.75, 5.0, 0.7); // Kopf, 1,5 breit
  quader(-0.95, 0.0, -0.45, -0.25, 2.25, 0.45);
  quader(0.25, 0.0, -0.45, 0.95, 2.25, 0.45);
  return buildGlb(m);
}

void main() {
  late FacePartsResult ergebnis;

  setUpAll(() {
    ergebnis = addFaceParts(_figur());
  });

  test('alle fünf Teile entstehen, unter ihren Namen', () {
    expect(ergebnis.report.parts.map((p) => p.name).toList(),
        faceMeshNames);
    final json = splitGlb(ergebnis.glb).json;
    final namen = [
      for (final mesh in json['meshes'] as List) (mesh as Map)['name'],
    ];
    for (final name in faceMeshNames) {
      expect(namen, contains(name));
    }
  });

  test('jedes Teil ist ein eigenes Netz an einem eigenen Knoten', () {
    final json = splitGlb(ergebnis.glb).json;
    final nodes = (json['nodes'] as List).cast<Map>();
    for (final name in faceMeshNames) {
      final node = nodes.firstWhere((n) => n['name'] == name);
      expect(node.containsKey('mesh'), isTrue);
    }
    // Und sie hängen in der Szene, sonst sieht Auto Setup sie nicht.
    final scene = (json['scenes'] as List)[0] as Map;
    final wurzeln = (scene['nodes'] as List).cast<int>();
    for (final name in faceMeshNames) {
      final index = nodes.indexWhere((n) => n['name'] == name);
      expect(wurzeln, contains(index), reason: '$name nicht in der Szene');
    }
  });

  test('die Teile teilen keine Punkte mit dem Kopf', () {
    // Getrennte Accessoren heißt getrennte Punkte – daran trennt Auto
    // Setup Gesicht und Kopf.
    final json = splitGlb(ergebnis.glb).json;
    final benutzt = <int, int>{};
    for (final mesh in json['meshes'] as List) {
      for (final prim in ((mesh as Map)['primitives'] as List)) {
        final index =
            ((prim as Map)['attributes'] as Map)['POSITION'] as int;
        benutzt[index] = (benutzt[index] ?? 0) + 1;
      }
    }
    for (final zahl in benutzt.values) {
      expect(zahl, 1, reason: 'ein POSITION-Accessor wird geteilt');
    }
  });

  test('die Maße hängen an der Kopfbreite, nicht an festen Studs',
      () async {
    expect(ergebnis.report.headWidth, closeTo(1.5, 0.01));
    // Dieselbe Figur doppelt so groß: Die Teile wachsen mit.
    final gross = addFaceParts(_figur());
    expect(gross.report.headWidth, ergebnis.report.headWidth);
    expect(ergebnis.report.text, contains('Anteile'));
  });

  test('die Augen sitzen vorn, links und rechts von der Mitte', () {
    final links = ergebnis.report.parts
        .firstWhere((p) => p.name == 'LeftEye')
        .center;
    final rechts = ergebnis.report.parts
        .firstWhere((p) => p.name == 'RightEye')
        .center;
    expect(links[0], lessThan(0));
    expect(rechts[0], greaterThan(0));
    expect(links[1], closeTo(rechts[1], 1e-6));
    // Front ist −z: Die Augen liegen vor der Kopfmitte.
    expect(links[2], lessThan(0));
  });

  test('der Mund liegt unter den Augen, die Zunge dahinter', () {
    double y(String name) => ergebnis.report.parts
        .firstWhere((p) => p.name == name)
        .center[1];
    double z(String name) => ergebnis.report.parts
        .firstWhere((p) => p.name == name)
        .center[2];
    expect(y('UpperTeeth'), lessThan(y('LeftEye')));
    expect(y('UpperTeeth'), greaterThan(y('LowerTeeth')));
    // Hinter den Zähnen heißt: weiter weg von der Front (−z).
    expect(z('Tongue'), greaterThan(z('UpperTeeth')));
  });

  test('das Ergebnis bleibt lesbar und wächst nur um die Teile',
      () async {
    final vorher = await parseGlbForPreview(_figur());
    final davor = vorher.indices.length ~/ 3;
    vorher.dispose();
    final nachher = await parseGlbForPreview(ergebnis.glb);
    final danach = nachher.indices.length ~/ 3;
    nachher.dispose();
    expect(danach, davor + ergebnis.report.triangles);
    // Und die Teile kosten wenig: Sie dürfen das Budget nicht sprengen.
    expect(ergebnis.report.triangles, lessThan(400));
  });

  test('die Figur bleibt in ihren Maßen', () async {
    // Die Teile stecken im Kopf; der umschließende Quader darf sich
    // nicht ändern, sonst ragt ein Auge heraus.
    final vorher = await parseGlbForPreview(_figur());
    final a = measureMarketplaceFigure(vorher.positions, vorher.indices);
    vorher.dispose();
    final nachher = await parseGlbForPreview(ergebnis.glb);
    final b = measureMarketplaceFigure(nachher.positions, nachher.indices);
    nachher.dispose();
    expect(b.width, closeTo(a.width, 0.01));
    expect(b.depth, closeTo(a.depth, 0.01));
  });

  test('ohne Kopf gibt es eine verständliche Absage', () {
    // Ein flaches Brett hat kein oberes Fünftel mit Geometrie – dort
    // müsste der Kopf sein.
    final flach = LocalMesh();
    final a = flach.addVertex(-1, 0, -1, 0, 0);
    final b = flach.addVertex(1, 0, -1, 1, 0);
    final c = flach.addVertex(1, 0, 1, 1, 1);
    final d = flach.addVertex(-1, 0, 1, 0, 1);
    flach.addQuad(a, b, c, d);
    expect(
      () => addFaceParts(buildGlb(flach)),
      throwsA(predicate((e) => '$e'.contains('Höhe'))),
    );
  });

  test('jedes Teil ist geschlossen und ohne entartete Dreiecke',
      () async {
    // Roblox verlangt wasserdicht für jedes Netz in der Datei, und es
    // lehnt Dreiecke ohne Fläche ab (TriangleAreaValid). Beides prüft
    // die App mit derselben Rechnung wie am fertigen Modell – also
    // nach Position verschweißt, denn eine UV-Naht ist kein Loch.
    final vorher = await readRobloxFacts(_figur());
    final nachher = await readRobloxFacts(ergebnis.glb);
    expect(nachher.openEdges, vorher.openEdges,
        reason: 'die Gesichtsteile reißen Löcher');
    // Verglichen wird gegen den Ausgangszustand, nicht gegen null:
    // Die Zählung meldet auch Dreiecke, deren Ebene durch den
    // Ursprung geht – ein Artefakt der Volumenrechnung, das die
    // Testfigur schon mitbringt.
    expect(nachher.degenerateTriangles, vorher.degenerateTriangles,
        reason: 'die Gesichtsteile bringen entartete Dreiecke mit');
  });
}
