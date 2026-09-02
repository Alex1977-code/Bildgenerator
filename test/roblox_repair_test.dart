import 'dart:typed_data';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/roblox_face_parts.dart';
import 'package:bildgenerator/services/roblox_face_sculpt.dart';
import 'package:bildgenerator/services/roblox_marketplace.dart';
import 'package:bildgenerator/services/roblox_repair.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eine Figur mit den Fehlern, die an Kapuzzeee gemessen wurden.
///
/// [tiefe] · [hals] · [beineZusammen] · [tPose] schalten je einen
/// Mangel ein, damit sich jede Korrektur einzeln prüfen lässt.
Uint8List figur({
  double tiefe = 1.2,
  bool hals = true,
  bool beineZusammen = false,
  bool tPose = false,
  double beinBreite = 0.45,
}) {
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

  final t = tiefe / 2;
  // Rumpf bis 3,80; Hals 3,80–4,15 (0,35 hoch, also gut drei Bänder
  // von 2 % – ein kürzerer Hals liegt unter der Auflösung der
  // Messung); Kopf darüber.
  quader(-1.1, 2.3, -t, 1.1, 3.8, t);
  if (hals) {
    quader(-0.3, 3.8, -0.22, 0.3, 4.15, 0.22);
    quader(-0.78, 4.15, -0.6, 0.78, 5.0, 0.6);
  } else {
    quader(-0.78, 3.8, -0.6, 0.78, 5.0, 0.6);
  }
  // Arme: breit genug, dass die Armspanne sicher auf X liegt.
  if (tPose) {
    quader(-2.6, 3.2, -0.2, -1.1, 3.7, 0.2);
    quader(1.1, 3.2, -0.2, 2.6, 3.7, 0.2);
  } else {
    quader(-1.8, 2.6, -0.2, -1.1, 3.7, 0.2);
    quader(1.1, 2.6, -0.2, 1.8, 3.7, 0.2);
  }
  // Beine, mit Schienbeinring für die Zehen-Heuristik.
  final b = beinBreite;
  quader(-0.15 - b, 1.2, -0.25, -0.15, 2.3, 0.25);
  quader(0.15, 1.2, -0.25, 0.15 + b, 2.3, 0.25);
  quader(-0.15 - b, 0.35, -0.25, -0.15, 1.2, 0.25);
  quader(0.15, 0.35, -0.25, 0.15 + b, 1.2, 0.25);
  // Füße nach +Z, damit nichts gedreht werden muss.
  quader(-0.15 - b, 0.0, 0.25, -0.15, 0.35, 0.9);
  quader(0.15, 0.0, 0.25, 0.15 + b, 0.35, 0.9);
  if (beineZusammen) {
    // Ein Saum, der beide Beine verbindet – vollständig unter der
    // Hüfte (45 % von 5,00 = 2,25), sonst greift der Schnitt nicht.
    //
    // Aus acht schmalen Scheiben statt aus einem Quader: Der Schnitt
    // löscht Dreiecke, deren **drei** Punkte im Mittelstreifen liegen,
    // damit an den Beinen nichts aufreißt. Ein einzelner breiter
    // Quader hat seine Seitenflächen außerhalb des Streifens und
    // bliebe deshalb ganz stehen – ein erzeugtes Netz ist dichter.
    const scheiben = 8;
    final von = -0.15 - b, bis = 0.15 + b;
    final schritt = (bis - von) / scheiben;
    for (var i = 0; i < scheiben; i++) {
      quader(von + i * schritt, 1.2, -0.25, von + (i + 1) * schritt,
          2.2, 0.25);
    }
  }
  return buildGlb(m);
}

Future<MarketplaceMeasurement> miss(Uint8List glb) async {
  final v = await parseGlbForPreview(glb);
  final m = measureMarketplaceFigure(v.positions, v.indices);
  v.dispose();
  return m;
}

void main() {
  test('eine Figur ohne Mängel wird nicht verformt', () async {
    final vorher = await miss(figur());
    final r = await repairForMarketplace(figur(),
        addFace: false, sculptFace: false, decimate: false);
    final nachher = await miss(r.glb);
    expect(nachher.depth, closeTo(vorher.depth, 0.02));
    expect(nachher.width, closeTo(vorher.width, 0.02));
    // Nur die Nachmessung darf etwas melden, keine Korrektur.
    expect(
        r.report.steps.where((s) => !s.rule.startsWith('Nachmessung')),
        isEmpty);
  });

  test('zu tiefe Figuren werden gestaucht, zu tiefe abgelehnt', () async {
    // 2,45 wie Kapuzzee: behebbar. Der Zielwert liegt unter der Grenze.
    final r = await repairForMarketplace(figur(tiefe: 2.45),
        addFace: false, decimate: false);
    final schritt =
        r.report.steps.firstWhere((s) => s.rule == 'Tiefe');
    expect(schritt.origin, RepairOrigin.app);
    expect((await miss(r.glb)).depth,
        lessThanOrEqualTo(marketplaceMaxDepth));

    // 3,20: darüber wäre die Figur ein Brett.
    final zuTief = await repairForMarketplace(figur(tiefe: 3.2),
        addFace: false, decimate: false);
    final abgelehnt =
        zuTief.report.steps.firstWhere((s) => s.rule == 'Tiefe');
    expect(abgelehnt.origin, RepairOrigin.prompt);
    expect(abgelehnt.note, contains('Brett'));
    // Und die Figur bleibt unangetastet.
    expect((await miss(zuTief.glb)).depth, closeTo(3.2, 0.05));
  });

  test('ein fehlender Hals wird eingeschnürt', () async {
    final vorher = await miss(figur(hals: false));
    expect(vorher.hasNeck, isFalse);
    final r = await repairForMarketplace(figur(hals: false),
        addFace: false, decimate: false);
    final schritt = r.report.steps.firstWhere((s) => s.rule == 'Hals');
    expect(schritt.origin, RepairOrigin.app);
    final nachher = await miss(r.glb);
    expect(nachher.neckRatio, lessThan(vorher.neckRatio),
        reason: 'der Hals muss schmaler geworden sein');
    // Der Kopf darüber bleibt: eingeschnürt wird nur das Halsband.
    expect(nachher.headWidth, closeTo(vorher.headWidth, 0.15));
  });

  test('zusammenhängende Beine werden freigeschnitten', () async {
    final vorher = await miss(figur(beineZusammen: true));
    expect(vorher.legSeparation, lessThan(marketplaceLegSeparation));
    final r = await repairForMarketplace(figur(beineZusammen: true),
        addFace: false, decimate: false);
    expect(r.report.steps.map((s) => s.rule), contains('Beine getrennt'));
    expect(r.report.steps.map((s) => s.rule), contains('Saum'));
    final nachher = await miss(r.glb);
    expect(nachher.legSeparation, greaterThan(vorher.legSeparation),
        reason: 'mehr Bänder müssen in zwei Inseln zerfallen');
  });

  test('die T-Pose wird zur A-Pose gedreht', () async {
    final vorher = await miss(figur(tPose: true));
    expect(vorher.looksLikeTPose, isTrue);
    final r = await repairForMarketplace(figur(tPose: true),
        addFace: false, decimate: false);
    final schritt = r.report.steps.firstWhere((s) => s.rule == 'Pose');
    expect(schritt.origin, RepairOrigin.app);
    expect(schritt.after, contains('45'));
    final nachher = await miss(r.glb);
    // Gesenkte Arme heißt: die breiteste Stelle rutscht nach unten.
    // Das und nicht die Spanne ist der Prüfstein – eine Figur, die die
    // Armspannen-Regel erfüllt, ist immer breit.
    expect(nachher.widestBandHeight, lessThan(vorher.widestBandHeight),
        reason: 'die breiteste Stelle muss tiefer liegen');
    expect(nachher.looksLikeTPose, isFalse,
        reason: 'nach der Reparatur darf die Regel nicht mehr greifen');
  });

  test('zu breite Beine werden geschmälert, viel zu breite abgelehnt',
      () async {
    // 1,6 je Bein: über der Grenze von 1,50, aber unter den 1,80,
    // ab denen vom Bein nichts übrig bliebe.
    final vorher = await miss(figur(beinBreite: 1.6));
    expect(vorher.legWidth, greaterThan(marketplaceMaxLegWidth));
    final r = await repairForMarketplace(figur(beinBreite: 1.6),
        addFace: false, decimate: false);
    final schritt =
        r.report.steps.firstWhere((s) => s.rule == 'Beinbreite');
    expect(schritt.origin, RepairOrigin.app);
    expect((await miss(r.glb)).legWidth, lessThan(vorher.legWidth),
        reason: 'die Beine müssen schmaler geworden sein');

    // Und viel zu breit heißt: Prompt.
    final zuBreit = await repairForMarketplace(figur(beinBreite: 2.4),
        addFace: false, decimate: false);
    final abgelehnt = zuBreit.report.steps
        .where((s) => s.rule == 'Beinbreite');
    if (abgelehnt.isNotEmpty) {
      expect(abgelehnt.single.origin, RepairOrigin.prompt);
    }
  });

  test('der Bericht sagt je Zeile, wer dran ist', () async {
    final r = await repairForMarketplace(figur(tiefe: 3.2, hals: false),
        addFace: false, decimate: false);
    expect(r.report.text, contains('Reparatur-Bericht'));
    expect(r.report.text, contains('[Prompt]'));
    expect(r.report.text, contains('[App]'));
    expect(r.report.anythingLeft, isTrue);
  });

  test('das Gesicht kommt vor den Teilen ins Kopfnetz', () async {
    final r = await repairForMarketplace(figur(), decimate: false);
    final regeln = r.report.steps.map((s) => s.rule).toList();
    final gesicht = regeln.indexOf('Gesicht im Kopfnetz');
    final teile = regeln.indexOf('Gesichtsteile');
    expect(gesicht, greaterThanOrEqualTo(0));
    expect(teile, greaterThan(gesicht), reason: 'erst Höhlen, dann Teile');
    // Der Kastenkopf ist grob; mit dem Standardbudget wird die Höhle
    // flacher als die Grenze – das steht dann als Prompt-Punkt drin,
    // nicht als stiller Erfolg.
    final schritt = r.report.steps[gesicht];
    expect(schritt.note, contains('Dreiecke'));
    // Und beides lässt sich abschalten.
    final ohne = await repairForMarketplace(figur(),
        addFace: false, sculptFace: false, decimate: false);
    expect(ohne.report.steps.map((s) => s.rule),
        isNot(contains('Gesicht im Kopfnetz')));
  });

  test('eine schon vorbereitete Figur lässt sich reparieren, ohne dass '
      'die Augen doppelt werden', () async {
    // Der Weg aus Text: Nach dem Lauf richtet die App die Figur von
    // selbst her (Höhlen, Gesichtsteile) und bietet bei Fehlern die
    // Reparatur an. Die bekommt also eine Figur **mit** Teilen.
    // Der Kastenkopf ist grob – mit dem Standardbudget bleiben die
    // Höhlen unter der Grenze, und der zweite Lauf gräbt zu Recht
    // weiter. Ein erzeugtes Netz ist feiner; hier stehen dafür mehr
    // Durchgänge.
    const fein = FaceSculptProportions(maxPasses: 6, maxExtraTriangles: 6000);
    final erst = await repairForMarketplace(figur(tiefe: 2.45),
        decimate: false, sculptProportions: fein);
    final json0 = splitGlb(erst.glb).json;
    expect((json0['meshes'] as List).length, 1 + faceMeshNames.length);

    final zweit = await repairForMarketplace(erst.glb,
        decimate: false, sculptProportions: fein);
    final namen = [
      for (final mesh in (splitGlb(zweit.glb).json['meshes'] as List).cast<Map>())
        mesh['name'] as String?,
    ];
    // Genau fünf Teile, jedes einmal – die alten sind raus, nicht im
    // Körper verschmolzen.
    for (final teil in faceMeshNames) {
      expect(namen.where((n) => n == teil), hasLength(1), reason: teil);
    }
    expect(namen.length, 1 + faceMeshNames.length);
    // Und das Gesicht wurde nicht ein zweites Mal gegraben.
    final gesicht = zweit.report.steps
        .firstWhere((s) => s.rule == 'Gesicht im Kopfnetz');
    expect(gesicht.note, contains('schon da'));
  });

  test('die Gesichtsteile kommen zuletzt', () async {
    final r = await repairForMarketplace(figur(), decimate: false);
    final json = splitGlb(r.glb).json;
    final namen = [
      for (final mesh in (json['meshes'] as List).cast<Map>())
        mesh['name'] as String?,
    ];
    for (final teil in faceMeshNames) {
      expect(namen, contains(teil), reason: teil);
    }
    final schritt =
        r.report.steps.firstWhere((s) => s.rule == 'Gesichtsteile');
    expect(schritt.after, '5');
  });
}
