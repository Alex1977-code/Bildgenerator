import 'dart:typed_data';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/gltf_edit.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/roblox_face_parts.dart';
import 'package:bildgenerator/services/roblox_check.dart';
import 'package:bildgenerator/services/roblox_marketplace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eine Figur mit einem Kopf, der breiter ist als nichts – mehr
/// braucht die Platzierung nicht.
Uint8List _figur({double kopfBreite = 1.5}) {
  final m = LocalMesh();
  final kb = kopfBreite / 2;
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
  quader(-kb, 3.9, -0.7, kb, 5.0, 0.7); // Kopf, so breit wie gewuenscht
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

  test('die Maße hängen an der Kopfbreite, nicht an festen Studs', () {
    expect(ergebnis.report.headWidth, closeTo(1.5, 0.01));
    // Das Kopfband ist das oberste Fünftel von 5,0 Studs.
    expect(ergebnis.report.headHeight, closeTo(1.0, 0.01));
    expect(ergebnis.report.text, contains('Anteile'));

    // Ein breiterer Kopf: Alle Maße wachsen im selben Verhältnis mit.
    final breit = addFaceParts(_figur(kopfBreite: 3.0));
    expect(breit.report.headWidth, closeTo(3.0, 0.01));
    double x(FacePartsResult r, String name) => r.report.parts
        .firstWhere((p) => p.name == name)
        .center[0];
    expect(x(breit, 'RightEye'), closeTo(2 * x(ergebnis, 'RightEye'), 1e-6));
  });

  test('das Rechenbeispiel aus der Übergabe stimmt', () {
    // Kapuzzeee, B = 1,57: Augenradius 0,09, Augenabstand 0,57,
    // Zahnreihe 0,39 Studs breit. Die drei Zahlen sind die Probe auf
    // alle Anteile auf einmal.
    final r = addFaceParts(_figur(kopfBreite: 1.57));
    expect(r.report.headWidth, closeTo(1.57, 0.01));
    final links = r.report.parts.firstWhere((p) => p.name == 'LeftEye');
    final rechts = r.report.parts.firstWhere((p) => p.name == 'RightEye');
    expect(rechts.center[0] - links.center[0], closeTo(0.57, 0.005));
    expect(r.report.text, contains('Augenradius 0.09'));
    expect(r.report.text, contains('Zahnreihe 0.39'));
  });

  test('die Teile sitzen auf den Höhen aus der Übergabe', () {
    // Alles gemessen im Kopfband: unten 4,0, H = 1,0.
    double y(String name) => ergebnis.report.parts
        .firstWhere((p) => p.name == name)
        .center[1];
    expect(y('LeftEye'), closeTo(4.0 + 0.55, 1e-6));
    expect(y('UpperTeeth'), closeTo(4.0 + 0.36, 1e-6));
    // 33 % und der Abstand von 0,01 × H widersprechen sich: Bei 33 %
    // stießen die Reihen aneinander. Der Abstand gewinnt, die
    // Unterzähne rutschen auf 32 %, und der Bericht sagt es an.
    expect(y('LowerTeeth'), closeTo(4.0 + 0.32, 1e-6));
    expect(ergebnis.report.text, contains('32 % statt 33 %'));
    final abstand = (y('UpperTeeth') - 0.015) - (y('LowerTeeth') + 0.015);
    expect(abstand, closeTo(0.01, 1e-6));
    // Die Zunge liegt zwischen den Reihen.
    expect(y('Tongue'), lessThan(y('UpperTeeth')));
    expect(y('Tongue'), greaterThan(y('LowerTeeth')));
  });

  test('die Augen sitzen an der Gesichtsfläche, nicht an der Bandkante',
      () {
    // Vorn ist +z: Die Figur schaut dorthin, wohin ihre Zehen zeigen,
    // und die stehen nach der Vorbereitung auf +Z (Studios glTF-Import
    // spiegelt die Achse). Der Strahl trifft die Vorderfläche bei
    // z = +0,7; der Mittelpunkt liegt 0,4 × Radius dahinter, das Auge
    // schaut um 0,6 × Radius heraus.
    final r = 1.5 * 0.06;
    final auge = ergebnis.report.parts.firstWhere((p) => p.name == 'LeftEye');
    expect(auge.center[2], closeTo(0.7 - 0.4 * r, 1e-6));
    // Und die Zahnreihen stehen mit ihrer Vorderkante auf der Fläche.
    final zahn =
        ergebnis.report.parts.firstWhere((p) => p.name == 'UpperTeeth');
    expect(zahn.center[2], closeTo(0.7 - 1.5 * 0.04 / 2, 1e-6));
  });

  test('die Dreieckszahlen bleiben in den genannten Grenzen', () {
    int tri(String name) => ergebnis.report.parts
        .firstWhere((p) => p.name == name)
        .triangles;
    // Übergabe: 64 bis 96 je Auge, 12 bis 40 je Mundteil.
    for (final auge in ['LeftEye', 'RightEye']) {
      expect(tri(auge), inInclusiveRange(64, 96), reason: auge);
    }
    for (final mund in ['UpperTeeth', 'LowerTeeth', 'Tongue']) {
      expect(tri(mund), inInclusiveRange(12, 40), reason: mund);
    }
    // Und der Bericht rechnet vor, was vom Kopfbudget übrig bleibt.
    expect(ergebnis.report.text, contains('Kopfbudget von 4000'));
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
    // Vorn ist +z: Die Augen liegen vor der Kopfmitte.
    expect(links[2], greaterThan(0));
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
    // Hinter den Zähnen heißt: weiter weg von der Front, also −z.
    expect(z('Tongue'), lessThan(z('UpperTeeth')));
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

  test('nur die Augen wachsen aus der Figur heraus, und nur so weit',
      () async {
    // Die Augen sind um 0,4 × Radius versenkt und schauen deshalb um
    // 0,6 × Radius heraus – so weit und keinen Zehntel weiter darf
    // die Tiefe zulegen. Der Marktplatz misst höchstens 2,00 Studs,
    // und der Bericht sagt den Zuwachs an.
    final vorher = await parseGlbForPreview(_figur());
    final a = measureMarketplaceFigure(vorher.positions, vorher.indices);
    vorher.dispose();
    final nachher = await parseGlbForPreview(ergebnis.glb);
    final b = measureMarketplaceFigure(nachher.positions, nachher.indices);
    nachher.dispose();
    expect(b.width, closeTo(a.width, 0.01));
    final heraus = 1.5 * 0.06 * 0.6;
    // Obergrenze, kein Sollwert: Die Kugel ist facettiert, und ihre
    // vorderste Ecke liegt nicht genau auf dem Pol – gemessen sind
    // rund 0,5 × Radius. Mehr als 0,6 darf es nie werden.
    expect(b.depth - a.depth, lessThanOrEqualTo(heraus + 1e-6));
    expect(b.depth - a.depth, greaterThan(heraus * 0.7));
    // Der Bericht addiert nicht den Radius, sondern misst den
    // Hüllkörper vorher und nachher – nur so stimmt die Aussage auch
    // dort, wo die Augen hinter dem Kapuzenrand liegen.
    expect(ergebnis.report.text, contains('Tiefe des Hüllkörpers: 1.40'));
    expect(ergebnis.report.text, contains('kosten 0.05 Studs'));
  });

  test('hinter der vordersten Kante kosten die Augen keine Tiefe', () {
    // Kapuze: ein Schirm, der weiter vorn steht als das Gesicht. Die
    // Augen sitzen dahinter, der Hüllkörper wächst nicht.
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

    quader(-1.3, 2.25, -0.6, 1.3, 3.9, 0.6);
    quader(-0.75, 3.9, -0.7, 0.75, 5.0, 0.7); // Kopf
    // Der Kapuzenschirm steht 0,3 Studs vor dem Gesicht – vorn ist +z.
    quader(-0.75, 4.75, 0.7, 0.75, 5.0, 1.0);
    quader(-0.95, 0.0, -0.45, -0.25, 2.25, 0.45);
    quader(0.25, 0.0, -0.45, 0.95, 2.25, 0.45);
    final r = addFaceParts(buildGlb(m));
    expect(r.report.text, contains('unverändert'));
    expect(r.report.text, isNot(contains('kosten 0')));
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

  test('jedes Teil ist auch ungeschweißt geschlossen', () {
    // Die Prüfung der App verschweißt vor dem Zählen nach Position –
    // eine UV-Naht ist kein Loch. Blender und Roblox verschweißen
    // nicht. Ein Ellipsoid mit einem doppelten Pol je Spalte und einer
    // wiederholten Nahtspalte ist damit offen: 46 Kanten je Auge. Hier
    // wird deshalb roh gezählt, Index für Index.
    for (final (_, positionen, indizes) in _teile(ergebnis.glb)) {
      final kanten = <String, int>{};
      for (var t = 0; t + 2 < indizes.length; t += 3) {
        for (var k = 0; k < 3; k++) {
          final a = indizes[t + k], b = indizes[t + (k + 1) % 3];
          final schluessel = a < b ? '$a:$b' : '$b:$a';
          kanten[schluessel] = (kanten[schluessel] ?? 0) + 1;
        }
      }
      final offen = kanten.values.where((n) => n != 2).length;
      expect(offen, 0, reason: 'offene Kanten – und Punkte gibt es '
          '${positionen.length ~/ 3}');
    }
  });

  test('jedes Teil ist nach außen gewickelt', () {
    // Einheitlich falsch herum ist einheitlich: Die Wicklungsprüfung
    // der App sah nichts, Blender maß an den Augen ein negatives
    // Volumen. Das Vorzeichen der Summe über alle Dreiecke sagt es
    // eindeutig – bei geschlossenen Netzen.
    for (final (name, positionen, indizes) in _teile(ergebnis.glb)) {
      var v = 0.0;
      for (var t = 0; t + 2 < indizes.length; t += 3) {
        final a = indizes[t] * 3, b = indizes[t + 1] * 3, c = indizes[t + 2] * 3;
        v += (positionen[a] *
                    (positionen[b + 1] * positionen[c + 2] -
                        positionen[b + 2] * positionen[c + 1]) -
                positionen[a + 1] *
                    (positionen[b] * positionen[c + 2] -
                        positionen[b + 2] * positionen[c]) +
                positionen[a + 2] *
                    (positionen[b] * positionen[c + 1] -
                        positionen[b + 1] * positionen[c])) /
            6.0;
      }
      expect(v, greaterThan(0), reason: '$name ist nach innen gewickelt');
    }
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

/// Positionen und Indizes der fünf Gesichtsteile, roh aus der Datei.
List<(String, List<double>, List<int>)> _teile(Uint8List glb) {
  final teil = splitGlb(glb);
  final json = teil.json;
  final out = <(String, List<double>, List<int>)>[];
  for (final mesh in (json['meshes'] as List).cast<Map>()) {
    final name = mesh['name'] as String? ?? '';
    if (!faceMeshNames.contains(name)) continue;
    final prim = (mesh['primitives'] as List).first as Map;
    final pos = readGltfFloats(
        json, teil.bin, (prim['attributes'] as Map)['POSITION'] as int);
    final idx =
        readGltfInts(json, teil.bin, (prim['indices'] as num).toInt());
    out.add((name, pos.toList(), idx));
  }
  expect(out.length, faceMeshNames.length);
  return out;
}
