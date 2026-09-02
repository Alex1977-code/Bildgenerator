import 'dart:typed_data';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/mesh_check.dart';
import 'package:bildgenerator/services/roblox_face_parts.dart';
import 'package:bildgenerator/services/roblox_face_sculpt.dart';
import 'package:bildgenerator/services/roblox_check.dart';
import 'package:bildgenerator/services/roblox_marketplace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eine Figur mit Kastenkopf: 1,56 breit, von 4,15 bis 5,00 hoch,
/// Vorderseite bei z = 0,6. Das Gesicht ist eine ebene Fläche aus
/// zwei Dreiecken – der härteste Fall für die Verfeinerung.
Uint8List figur() {
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

  quader(-1.1, 2.3, -0.6, 1.1, 3.8, 0.6);
  quader(-0.3, 3.8, -0.22, 0.3, 4.15, 0.22);
  quader(-0.78, 4.15, -0.6, 0.78, 5.0, 0.6);
  quader(-1.8, 2.6, -0.2, -1.1, 3.7, 0.2);
  quader(1.1, 2.6, -0.2, 1.8, 3.7, 0.2);
  quader(-0.6, 0.35, -0.25, -0.15, 2.3, 0.25);
  quader(0.15, 0.35, -0.25, 0.6, 2.3, 0.25);
  // Die Füße berühren die Beine nicht: Zwei Kästen mit gemeinsamen
  // Eckpunkten ergäben nach dem Verschweißen Kanten mit vier
  // Dreiecken, und die Dichtheitsprüfung meldete das – am Rohling,
  // nicht am Eingriff.
  quader(-0.6, 0.0, 0.25, -0.15, 0.30, 0.9);
  quader(0.15, 0.0, 0.25, 0.6, 0.30, 0.9);
  return buildGlb(m);
}

/// Dieselbe Figur, aber **mit UV-Nähten**: Jede Kastenfläche hat
/// ihre eigenen vier Punkte, wie bei einem texturierten Netz mit
/// Inseln. Der Fund aus Blender: Über rohe Indizes markiert, blieb das
/// Nachbardreieck an der Naht ungeteilt – ein T-Stoß je Nahtkante.
Uint8List figurMitNaehten() {
  final m = LocalMesh();
  void flaeche(List<List<double>> ecken) {
    final p = [
      for (final e in ecken) m.addVertex(e[0], e[1], e[2], 0, 0),
    ];
    m.addQuad(p[0], p[1], p[2], p[3]);
  }

  void quader(double x0, double y0, double z0, double x1, double y1,
      double z1) {
    flaeche([[x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [x1, y0, z0]]);
    flaeche([[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]]);
    flaeche([[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]]);
    flaeche([[x1, y1, z0], [x0, y1, z0], [x0, y1, z1], [x1, y1, z1]]);
    flaeche([[x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [x1, y0, z1]]);
    flaeche([[x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0]]);
  }

  quader(-1.1, 2.3, -0.6, 1.1, 3.8, 0.6);
  quader(-0.3, 3.8, -0.22, 0.3, 4.15, 0.22);
  quader(-0.78, 4.15, -0.6, 0.78, 5.0, 0.6);
  quader(-0.6, 0.35, -0.25, -0.15, 2.3, 0.25);
  quader(0.15, 0.35, -0.25, 0.6, 2.3, 0.25);
  quader(-0.6, 0.0, 0.25, -0.15, 0.30, 0.9);
  quader(0.15, 0.0, 0.25, 0.6, 0.30, 0.9);
  return buildGlb(m);
}

/// Für den Kasten braucht es mehr Durchgänge als für ein erzeugtes
/// Netz: Die Vorderseite besteht aus zwei Dreiecken mit 1,56 Kante.
const grob = FaceSculptProportions(maxPasses: 6, maxExtraTriangles: 6000);

Future<PreviewMesh> lies(Uint8List glb) => parseGlbForPreview(glb);

void main() {
  test('vorher gibt es keine Höhlen, nachher schon', () async {
    final v = await lies(figur());
    final vorher = measureFaceCavities(v.positions, v.indices.toList())!;
    v.dispose();
    expect(vorher.hasEyeSockets, isFalse);
    expect(vorher.hasMouthCavity, isFalse);
    expect(vorher.headWidth, closeTo(1.56, 0.01));

    final r = await sculptFaceIntoHead(figur(), proportions: grob);
    final n = await lies(r.glb);
    final nachher = measureFaceCavities(n.positions, n.indices.toList())!;
    n.dispose();
    expect(nachher.hasEyeSockets, isTrue,
        reason: 'links ${nachher.leftEyeDepth}, rechts ${nachher.rightEyeDepth}');
    expect(nachher.hasMouthCavity, isTrue, reason: '${nachher.mouthDepth}');
    // Die Höhle ist etwa so tief wie bestellt: 0,06 × B plus der
    // Grat von 0,015 × B, denn gemessen wird Rand minus Mitte.
    expect(nachher.leftEyeDepth, closeTo(1.56 * 0.06, 1.56 * 0.03));
    expect(nachher.mouthDepth, closeTo(1.56 * 0.08, 1.56 * 0.03));
    // Und der Bericht sagt dasselbe.
    expect(r.report.after.hasFace, isTrue);
    expect(r.report.text, contains('Augenhöhlen'));
  });

  test('die Hülle bleibt geschlossen und nach außen gewickelt', () async {
    // Der Rohling ist dicht – sonst prüfte der Test das Falsche.
    final roh = await lies(figur());
    final rohDicht = checkMeshWatertight(roh.positions, roh.indices);
    roh.dispose();
    expect(rohDicht.openEdges, 0);
    expect(rohDicht.nonManifoldEdges, 0);

    final r = await sculptFaceIntoHead(figur(), proportions: grob);
    final n = await lies(r.glb);
    final dicht = checkMeshWatertight(n.positions, n.indices);
    // Konforme Verfeinerung: keine T-Stöße, also keine offenen
    // Kanten – auch **unverschweißt** nicht, an den UV-Nähten
    // entstehen die Mittelpunkte paarweise an derselben Stelle.
    expect(dicht.openEdges, 0);
    expect(dicht.nonManifoldEdges, 0);
    final wick = checkMeshOrientation(n.positions, n.indices);
    expect(wick.reversedEdges, 0);
    expect(wick.invertedParts, 0);
    n.dispose();
  });

  test('auch mit UV-Nähten bleibt die Hülle geschlossen', () async {
    // Vorher: nach Position dicht, roh aber lauter Nahtkanten.
    final roh = await lies(figurMitNaehten());
    final rohDicht = checkMeshWatertight(roh.positions, roh.indices);
    roh.dispose();
    expect(rohDicht.openEdges, 0);
    expect(rohDicht.rawOpenEdges, greaterThan(0), reason: 'Nähte');

    final r = await sculptFaceIntoHead(figurMitNaehten(), proportions: grob);
    expect(r.report.addedTriangles, greaterThan(0));
    final n = await lies(r.glb);
    final dicht = checkMeshWatertight(n.positions, n.indices);
    // Nach Position weiterhin dicht: Die Naht-Nachbarn wurden
    // mitgeteilt. Das ist die Zeile, die Blender vorher widerlegt hat.
    expect(dicht.openEdges, 0);
    expect(dicht.nonManifoldEdges, 0);
    final wick = checkMeshOrientation(n.positions, n.indices);
    expect(wick.reversedEdges, 0);
    expect(wick.invertedParts, 0);
    // Und die Höhlen sind trotzdem da.
    final c = measureFaceCavities(n.positions, n.indices.toList())!;
    expect(c.hasFace, isTrue,
        reason: '${c.leftEyeDepth} / ${c.rightEyeDepth} / ${c.mouthDepth}');
    n.dispose();
  });

  test('die Verfeinerung bleibt auf das Gesicht beschränkt', () async {
    final r = await sculptFaceIntoHead(figur(), proportions: grob);
    expect(r.report.addedTriangles, greaterThan(0));
    expect(r.report.addedTriangles, lessThanOrEqualTo(6000));
    // Der Rumpf darf nicht verfeinert werden: Alle neuen Punkte liegen
    // im Kopfband.
    final n = await lies(r.glb);
    final v0 = await lies(figur());
    for (var i = v0.positions.length; i + 2 < n.positions.length; i += 3) {
      expect(n.positions[i + 1], greaterThanOrEqualTo(4.0 - 1e-6),
          reason: 'neuer Punkt bei y=${n.positions[i + 1]}');
    }
    v0.dispose();
    n.dispose();
  });

  test('das Budget beendet die Verfeinerung und der Bericht sagt es',
      () async {
    final knapp = const FaceSculptProportions(
        maxPasses: 6, maxExtraTriangles: 60);
    final r = await sculptFaceIntoHead(figur(), proportions: knapp);
    // Die Schätzung zählt die geteilten Dreiecke; die Nachbarn mit
    // einer oder zwei Kanten dürfen leicht überziehen.
    expect(r.report.addedTriangles, lessThanOrEqualTo(60 + 3 * 24));
    expect(r.report.notes.join(' '), contains('Budget'));
  });

  test('die Maße der Figur ändern sich nicht', () async {
    final v0 = await lies(figur());
    final vorher = measureMarketplaceFigure(v0.positions, v0.indices);
    v0.dispose();
    final r = await sculptFaceIntoHead(figur(), proportions: grob);
    final n = await lies(r.glb);
    final nachher = measureMarketplaceFigure(n.positions, n.indices);
    n.dispose();
    expect(nachher.headWidth, closeTo(vorher.headWidth, 0.02));
    expect(nachher.width, closeTo(vorher.width, 0.02));
    // Der Grat steht 0,015 × B vor – das darf die Tiefe kosten, mehr
    // nicht.
    expect(nachher.depth, lessThanOrEqualTo(vorher.depth + 1.56 * 0.02));
  });

  test('die Gesichtsteile sitzen danach in den Höhlen', () async {
    final r = await sculptFaceIntoHead(figur(), proportions: grob);
    final mit = addFaceParts(r.glb);
    final auge = mit.report.parts.firstWhere((p) => p.name == 'LeftEye');
    // Der Augapfel sitzt hinter der alten Fläche (z = 0,6): Mittelpunkt
    // im Höhlenboden, 0,4 r versenkt.
    final rAuge = 1.56 * 0.06;
    final boden = 0.6 - 1.56 * 0.06;
    expect(auge.center[2], closeTo(boden - 0.4 * rAuge, 0.03));
    // Vorderkante des Auges bleibt hinter dem Grat.
    final gratZ = 0.6 + 1.56 * 0.015;
    expect(auge.center[2] + rAuge, lessThan(gratZ));
    // Die Zähne stehen in der Mundhöhle.
    final zaehne =
        mit.report.parts.firstWhere((p) => p.name == 'UpperTeeth');
    expect(zaehne.center[2], lessThan(0.6));
  });

  test('sind die Teile schon da, verweigert der Eingriff', () async {
    final mit = addFaceParts(figur()).glb;
    expect(() => sculptFaceIntoHead(mit), throwsA(isA<Exception>()));
  });

  test('ein erzeugtes Netz braucht keinen Kasten-Sonderfall', () async {
    // Ein Kopf, der schon feiner ist: Die Standardwerte (drei
    // Durchgänge, 1.500 Dreiecke) müssen dann reichen.
    final r0 = await sculptFaceIntoHead(figur(), proportions: grob);
    // Das Ergebnis noch einmal als Eingabe – jetzt ist das Gesicht
    // fein, und die Standardwerte greifen. Die Höhlen werden dabei
    // tiefer, das ist hier egal; es geht um die Durchgänge.
    final r1 = await sculptFaceIntoHead(r0.glb);
    expect(r1.report.passes, lessThanOrEqualTo(3));
    expect(r1.report.addedTriangles, lessThanOrEqualTo(1500));
  });

  test('die Prüfung meldet das Gesicht im Netz – vorher fehlend, '
      'nachher da', () async {
    final vorher = checkRobloxFacts(
        await readRobloxFacts(figur()), RobloxTarget.marketplaceAvatar);
    final fehlt = vorher.where((f) => f.title.startsWith('Gesicht im Kopfnetz'));
    expect(fehlt, hasLength(1));
    expect(fehlt.single.level, RobloxLevel.warning);
    expect(fehlt.single.title, contains('fehlen'));

    final r = await sculptFaceIntoHead(figur(), proportions: grob);
    final nachher = checkRobloxFacts(
        await readRobloxFacts(addFaceParts(r.glb).glb),
        RobloxTarget.marketplaceAvatar);
    final da = nachher.where((f) => f.title.startsWith('Gesicht im Kopfnetz'));
    expect(da, hasLength(1));
    expect(da.single.level, RobloxLevel.ok, reason: da.single.detail);
  });
}
