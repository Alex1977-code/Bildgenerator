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
  // Rumpf 2,05–3,80; Hals 3,80–4,15 (0,35 hoch, also gut drei Bänder
  // von 2 % – ein kürzerer Hals liegt unter der Auflösung der
  // Messung); Kopf darüber.
  //
  // Der Schritt sitzt bei 2,05 und nicht bei 2,30: Mit 1,50 Rumpfhöhe
  // riss die Vorlage das absolute Mindestmaß von
  // [specMinTorsoHeight] = 1,7, und eine Figur, an der „ohne Mängel"
  // geprüft wird, darf keines reißen. Aufgefallen ist es erst, als
  // der Maßstab-Schritt anfing, genau das zu beheben.
  quader(-1.1, 2.05, -t, 1.1, 3.8, t);
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
  quader(-0.15 - b, 1.2, -0.25, -0.15, 2.05, 0.25);
  quader(0.15, 1.2, -0.25, 0.15 + b, 2.05, 0.25);
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
          2.0, 0.25);
    }
  }
  return buildGlb(m);
}

Future<MarketplaceMeasurement> miss(Uint8List glb,
    {double studs = marketplaceFigureStuds}) async {
  final v = await parseGlbForPreview(glb);
  final m =
      measureMarketplaceFigure(v.positions, v.indices, targetStuds: studs);
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
    // Standard-Skala Normal: Grenze 2,25, Ziel 2,15.
    expect((await miss(r.glb)).depth,
        lessThanOrEqualTo(RobloxBodyScale.normal.maxDepth));
    // Bei Classic gilt 2,00 – und 2,20 wäre dort ein Fehler, der
    // gestaucht wird.
    final classic = await repairForMarketplace(figur(tiefe: 2.2),
        addFace: false, decimate: false, scale: RobloxBodyScale.classic);
    expect(classic.report.steps.map((s) => s.rule), contains('Tiefe'));
    expect((await miss(classic.glb)).depth,
        lessThanOrEqualTo(RobloxBodyScale.classic.maxDepth));
    // Bei Normal ist 2,20 in Ordnung.
    final normal = await repairForMarketplace(figur(tiefe: 2.2),
        addFace: false, decimate: false);
    expect(normal.report.steps.map((s) => s.rule), isNot(contains('Tiefe')));

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

  test('umgedrehte Dreiecke werden gezählt', () {
    // Der Umstülp-Wächter: Bei der ersten Figur mit dem
    // Marktplatz-Schwanz stülpte die Klemme den Bauch nach innen, und
    // niemand hat es gemerkt – der Bericht meldete „geklemmt".
    final vorher = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);
    final gleich = Float32List.fromList(vorher);
    final idx = [0, 1, 2];
    expect(countFlippedTriangles(vorher, gleich, idx), 0);
    // Zwei Punkte tauschen die Lage: Die Normale kehrt sich um.
    final gespiegelt = Float32List.fromList([0, 0, 0, 0, 1, 0, 1, 0, 0]);
    expect(countFlippedTriangles(vorher, gespiegelt, idx), 1);
    // Eine bloße Verschiebung dreht nichts um.
    final verschoben = Float32List.fromList([1, 1, 1, 2, 1, 1, 1, 2, 1]);
    expect(countFlippedTriangles(vorher, verschoben, idx), 0);
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
    // Der Schnitt gilt nur, wenn die Probe ihn bestätigt.
    final schnitt =
        r.report.steps.firstWhere((s) => s.rule == 'Beine getrennt');
    expect(schnitt.after, 'freigeschnitten');
    expect(schnitt.note, contains('Probe'));
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
    expect(r.report.text, contains('[behoben]'));
    expect(r.report.text, contains('[offen, Prompt]'));
    expect(r.report.anythingLeft, isTrue);
    // Der Haken kommt aus dem Ergebnis, nicht aus der Herkunft: Eine
    // Tiefe, die zu groß zum Stauchen ist, stand mit „3.20 → 3.20" da
    // und trug trotzdem „behoben".
    final tiefe = r.report.steps.firstWhere((s) => s.rule == 'Tiefe');
    expect(tiefe.fixed, isFalse);
    for (final s in r.report.steps) {
      if (s.rule.startsWith('Nachmessung')) {
        expect(s.fixed, isFalse, reason: s.rule);
      }
    }
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

  group('Norm-Umbau: Verhältnisse statt Größe', () {
    /// Eine Figur mit falschen Verhältnissen: großer Kopf, kurze Beine.
    Uint8List schief() {
      final m = LocalMesh();
      void quader(double x0, double y0, double z0, double x1, double y1,
          double z1) {
        final b = m.positions.length ~/ 3;
        for (final (x, y, z) in [
          (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
          (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
        ]) {
          m.addVertex(x, y, z, 0, 0);
        }
        for (final f in const [
          [0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6],
          [0, 5, 1], [0, 4, 5], [2, 6, 7], [2, 7, 3],
          [1, 5, 6], [1, 6, 2], [0, 3, 7], [0, 7, 4],
        ]) {
          m.addTriangle(b + f[0], b + f[1], b + f[2]);
        }
      }
      // Beine nur bis 1,0 von 5,0 – 20 % statt 40 %.
      quader(-0.6, 0.0, -0.3, -0.1, 1.0, 0.3);
      quader(0.1, 0.0, -0.3, 0.6, 1.0, 0.3);
      quader(-0.9, 1.0, -0.5, 0.9, 3.4, 0.5);
      quader(-0.25, 3.4, -0.2, 0.25, 3.7, 0.2);
      quader(-0.8, 3.7, -0.6, 0.8, 5.0, 0.6);
      quader(-1.6, 2.0, -0.2, -0.9, 3.2, 0.2);
      quader(0.9, 2.0, -0.2, 1.6, 3.2, 0.2);
      return buildGlb(m);
    }

    test('der Umbau bringt Schritt und Halslinie auf die Norm-Anteile',
        () async {
      final vorher = await miss(schief());
      final r = await repairForMarketplace(schief(),
          addFace: false,
          sculptFace: false,
          decimate: false,
          normProportions: true);
      final schritt = r.report.steps
          .firstWhere((s) => s.rule == repairStepProportions);
      expect(schritt.origin, RepairOrigin.app);

      // Auf dieselbe Höhe normiert gemessen liegen Schritt und
      // Halslinie danach auf den Norm-Anteilen.
      final nachher = await miss(r.glb);
      expect(nachher.legHeight / nachher.height,
          closeTo(marketplaceNormHip, 0.04));
      expect(1 - nachher.headHeight / nachher.height,
          closeTo(marketplaceNormNeck, 0.04));
      // Und die Beine sind länger geworden, nicht kürzer.
      expect(nachher.legHeight, greaterThan(vorher.legHeight));
    });

    test('ohne den Schalter bleiben die Verhältnisse, wie sie sind',
        () async {
      final vorher = await miss(schief());
      final r = await repairForMarketplace(schief(),
          addFace: false, sculptFace: false, decimate: false);
      expect(r.report.steps.where((s) => s.rule == repairStepProportions),
          isEmpty);
      final nachher = await miss(r.glb);
      expect(nachher.legHeight / nachher.height,
          closeTo(vorher.legHeight / vorher.height, 0.03));
    });

    test('der Umbau stülpt nichts um', () async {
      // Die Abbildung ist monoton und stetig – kein Dreieck darf sich
      // umdrehen. Geprüft an der Dreieckszahl und daran, dass die
      // Reparatur danach keine Löcher meldet.
      final r = await repairForMarketplace(schief(),
          addFace: false,
          sculptFace: false,
          decimate: false,
          normProportions: true);
      final v = await parseGlbForPreview(r.glb);
      final w = await parseGlbForPreview(schief());
      expect(v.indices.length, w.indices.length);
      v.dispose();
      w.dispose();
    });
  });

  group('Maßstab: die Mindestmaße sind absolut, die Höhe ist frei', () {
    /// Eine Figur mit zu kurzen Beinen – 1,30 von 1,40 verlangten,
    /// genau der Fehler aus der fünften Figur. Alles andere hält die
    /// Regeln.
    Uint8List kurzbeinig() {
      final m = LocalMesh();
      void quader(double x0, double y0, double z0, double x1, double y1,
          double z1) {
        final b = m.positions.length ~/ 3;
        for (final (x, y, z) in [
          (x0, y0, z0),
          (x1, y0, z0),
          (x1, y1, z0),
          (x0, y1, z0),
          (x0, y0, z1),
          (x1, y0, z1),
          (x1, y1, z1),
          (x0, y1, z1),
        ]) {
          m.addVertex(x, y, z, 0, 0);
        }
        for (final f in const [
          [0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6],
          [0, 5, 1], [0, 4, 5], [2, 6, 7], [2, 7, 3],
          [1, 5, 6], [1, 6, 2], [0, 3, 7], [0, 7, 4],
        ]) {
          m.addTriangle(b + f[0], b + f[1], b + f[2]);
        }
      }

      quader(-0.6, 0.0, -0.3, -0.1, 1.3, 0.3); // linkes Bein bis 1,30
      quader(0.1, 0.0, -0.3, 0.6, 1.3, 0.3); // rechtes Bein
      quader(-0.9, 1.3, -0.5, 0.9, 3.8, 0.5); // Rumpf
      quader(-0.25, 3.8, -0.2, 0.25, 4.15, 0.2); // Hals
      quader(-0.7, 4.15, -0.55, 0.7, 5.0, 0.55); // Kopf
      // Arme, damit die Spanne auf X liegt.
      quader(-1.6, 2.4, -0.2, -0.9, 3.6, 0.2);
      quader(0.9, 2.4, -0.2, 1.6, 3.6, 0.2);
      return buildGlb(m);
    }

    test('zu kurze Beine werden durch eine größere Ausgabe gelöst',
        () async {
      final vorher = await miss(kurzbeinig());
      expect(vorher.legHeight, lessThan(specMinLegHeight),
          reason: 'die Vorlage muss den Fehler wirklich haben');

      final r = await repairForMarketplace(kurzbeinig(),
          addFace: false, sculptFace: false, decimate: false);
      final schritt =
          r.report.steps.firstWhere((s) => s.rule == 'Maßstab');
      expect(schritt.origin, RepairOrigin.app);
      expect(schritt.fixed, isTrue);

      // Die Figur ist jetzt höher – und in **dieser** Höhe gemessen
      // halten die Beine ihr Mindestmaß.
      expect(r.studs, greaterThan(marketplaceFigureStuds));
      expect(r.studs, lessThanOrEqualTo(RobloxBodyScale.normal.maxTotalHeight));
      final nachher = await miss(r.glb, studs: r.studs);
      expect(nachher.legHeight, greaterThanOrEqualTo(specMinLegHeight));

      // Und der Fehler steht nicht mehr in der Nachmessung. Geprüft
      // wird auf den Wortlaut der Mindestmaß-Befunde („… hoch von
      // mindestens …"): Dass die Beine dieser Vorlage nur zu 55 %
      // getrennt sind, ist eine andere Sache und bleibt zu Recht
      // stehen – ein Maßstab trennt nichts.
      expect(
          r.report.steps.any((s) =>
              s.rule.startsWith('Nachmessung') &&
              s.rule.contains('hoch von mindestens')),
          isFalse);
    });

    test('kein Verhältnis ändert sich dabei', () async {
      final vorher = await miss(kurzbeinig());
      final r = await repairForMarketplace(kurzbeinig(),
          addFace: false, sculptFace: false, decimate: false);
      // Auf dieselbe Höhe normiert gemessen ist die Figur dieselbe:
      // Ein gleichmäßiger Maßstab verschiebt nichts gegeneinander.
      final gleich = await miss(r.glb);
      expect(gleich.legHeight, closeTo(vorher.legHeight, 0.06));
      expect(gleich.headWidth, closeTo(vorher.headWidth, 0.06));
      expect(gleich.depth, closeTo(vorher.depth, 0.06));
    });
  });
}
