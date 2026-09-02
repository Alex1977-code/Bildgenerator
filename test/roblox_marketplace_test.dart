import 'dart:typed_data';

import 'dart:math' as math;

import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/roblox_marketplace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Baut eine Figur aus Quadern und liefert Punkte samt Indizes.
class _Bau {
  final List<double> p = [];
  final List<int> i = [];

  void quader(double x0, double y0, double z0, double x1, double y1,
      double z1) {
    final b = p.length ~/ 3;
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
      p.addAll([x, y, z]);
    }
    const flaechen = [
      [0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6],
      [0, 5, 1], [0, 4, 5], [2, 6, 7], [2, 7, 3],
      [1, 5, 6], [1, 6, 2], [0, 3, 7], [0, 7, 4],
    ];
    for (final f in flaechen) {
      i.addAll([b + f[0], b + f[1], b + f[2]]);
    }
  }

  Float32List get positions => Float32List.fromList(p);
}

/// Eine Figur, die die Marktplatz-Regeln einhält: flach, schlanke
/// getrennte Beine, erkennbarer Hals, Arme weit auseinander.
/// Maße in Einheiten, die auf 5 Studs Höhe hochgerechnet werden.
_Bau _guteFigur() {
  final b = _Bau();
  // Die Hüfte sitzt bei 45 % der Höhe – so steht ein R15-Körper.
  b.quader(-1.3, 2.25, -0.6, 1.3, 3.9, 0.6); // Rumpf
  b.quader(-0.35, 3.9, -0.35, 0.35, 4.2, 0.35); // Hals, schmal
  b.quader(-0.8, 4.2, -0.7, 0.8, 5.0, 0.7); // Kopf
  b.quader(-3.2, 2.6, -0.4, -1.3, 3.85, 0.4); // Arm links
  b.quader(1.3, 2.6, -0.4, 3.2, 3.85, 0.4); // Arm rechts
  b.quader(-0.95, 0.0, -0.45, -0.25, 2.25, 0.45); // Bein links
  b.quader(0.25, 0.0, -0.45, 0.95, 2.25, 0.45); // Bein rechts
  return b;
}

/// Dieselbe Figur als „Kapuzzee": zu tief, ohne Hals, mit einem Saum,
/// der beide Beine verbindet.
_Bau _schlechteFigur() {
  final b = _Bau();
  b.quader(-1.3, 2.25, -1.3, 1.3, 3.9, 1.3); // tiefer Rumpf
  b.quader(-0.8, 3.9, -0.9, 0.8, 5.0, 0.9); // Kopf sitzt direkt auf
  b.quader(-3.2, 2.6, -0.4, -1.3, 3.85, 0.4);
  b.quader(1.3, 2.6, -0.4, 3.2, 3.85, 0.4);
  b.quader(-1.2, 1.0, -0.7, 1.2, 2.3, 0.7); // Saum über beide Beine
  b.quader(-0.95, 0.0, -0.45, -0.25, 2.25, 0.45);
  b.quader(0.25, 0.0, -0.45, 0.95, 2.25, 0.45);
  return b;
}

MarketplaceFinding _finde(List<MarketplaceFinding> f, String id) =>
    f.firstWhere((x) => x.id == id);

void main() {
  group('Messung', () {
    test('die Armspanne ist die größere waagerechte Achse', () {
      final b = _guteFigur();
      final m = measureMarketplaceFigure(b.positions, b.i);
      expect(m.widthAxis, 0);
      expect(m.width, greaterThan(m.depth));
      expect(m.height, marketplaceFigureStuds);
    });

    test('eine um 90° gedrehte Figur wird trotzdem richtig gemessen', () {
      // Ein Lauf kam mit der Armspanne auf z herein. Wer x
      // voraussetzt, misst dann die Tiefe als Breite und lässt eine
      // abgelehnte Figur durch.
      final b = _guteFigur();
      final gedreht = Float32List(b.p.length);
      for (var i = 0; i + 2 < b.p.length; i += 3) {
        gedreht[i] = b.p[i + 2];
        gedreht[i + 1] = b.p[i + 1];
        gedreht[i + 2] = b.p[i];
      }
      final gerade = measureMarketplaceFigure(b.positions, b.i);
      final quer = measureMarketplaceFigure(gedreht, b.i);
      expect(quer.widthAxis, 2);
      expect(quer.width, closeTo(gerade.width, 1e-3));
      expect(quer.depth, closeTo(gerade.depth, 1e-3));
    });

    test('die Höhe wird immer auf 5 Studs gerechnet', () {
      final b = _guteFigur();
      final gross = Float32List.fromList([for (final v in b.p) v * 7.3]);
      final a = measureMarketplaceFigure(b.positions, b.i);
      final c = measureMarketplaceFigure(gross, b.i);
      expect(c.width, closeTo(a.width, 1e-3));
      expect(c.depth, closeTo(a.depth, 1e-3));
    });

    test('leere Geometrie stürzt nicht ab', () {
      final m = measureMarketplaceFigure(Float32List(0), const []);
      expect(m.height, 0);
      final f = checkMarketplaceFigure(m);
      expect(f.single.id, 'keine_geometrie');
    });
  });

  group('Taille und Pose, gemessen am Ergebnis', () {
    test('eine Taille unter der Schulter ist ein Prompt-Fehler', () {
      // „hoodie ending at the hip bone" hat einen Bund erzeugt, der
      // schmaler war als der Hals. Auto Setup setzt die
      // Kopf-Rumpf-Grenze an die schmalste Stelle – bei Kapuzzeee kam
      // ein „Head" von 3,16 Studen Breite heraus.
      final m = const MarketplaceMeasurement(
        height: 5,
        width: 3.2,
        depth: 1.5,
        widthAxis: 0,
        headWidth: 1.3,
        neckWidth: 0.81,
        shoulderWidth: 2.6,
        legSeparation: 1,
        legWidth: 0.5,
        scale: 1,
        waistWidth: 0.68,
      );
      expect(m.hasWaist, isTrue);
      final f = checkMarketplaceFigure(m).where((f) => f.id == 'taille');
      expect(f, hasLength(1));
      expect(f.single.level, MarketplaceLevel.fehler);
      expect(f.single.origin, MarketplaceOrigin.prompt);
      expect(f.single.reason, contains('cinched waist'));

      // Ohne Bund keine Meldung.
      expect(
          checkMarketplaceFigure(const MarketplaceMeasurement(
            height: 5,
            width: 3.2,
            depth: 1.5,
            widthAxis: 0,
            headWidth: 1.3,
            neckWidth: 0.6,
            shoulderWidth: 2.6,
            legSeparation: 1,
            legWidth: 0.5,
            scale: 1,
            waistWidth: 1.4,
          )).where((f) => f.id == 'taille'),
          isEmpty);
    });

    test('T-Pose wird am Ergebnis erkannt, nicht am Prompt', () {
      // Zweimal stand der A-Pose-Text im Prompt, und zweimal kam die
      // Figur waagerecht zurück. Armspanne 5,06 bei 5,00 Höhe.
      const tPose = MarketplaceMeasurement(
        height: 5,
        width: 5.06,
        depth: 1.5,
        widthAxis: 0,
        headWidth: 1.3,
        neckWidth: 0.6,
        shoulderWidth: 2.6,
        legSeparation: 1,
        legWidth: 0.5,
        scale: 1,
        topBandWidth: 4.4,
      );
      expect(tPose.looksLikeTPose, isTrue);
      final f = checkMarketplaceFigure(tPose).where((f) => f.id == 'pose');
      expect(f, hasLength(1));
      expect(f.single.origin, MarketplaceOrigin.prompt);
      expect(f.single.title, contains('T-Pose gemessen'));

      // Beide Bedingungen müssen zusammenkommen: Eine breite Figur mit
      // hängenden Armen ist keine T-Pose, und ein breites Band allein
      // kann ein Umhang sein.
      expect(
          const MarketplaceMeasurement(
            height: 5,
            width: 5.06,
            depth: 1.5,
            widthAxis: 0,
            headWidth: 1.3,
            neckWidth: 0.6,
            shoulderWidth: 2.6,
            legSeparation: 1,
            legWidth: 0.5,
            scale: 1,
            topBandWidth: 2.0,
          ).looksLikeTPose,
          isFalse);
      expect(
          const MarketplaceMeasurement(
            height: 5,
            width: 3.0,
            depth: 1.5,
            widthAxis: 0,
            headWidth: 1.3,
            neckWidth: 0.6,
            shoulderWidth: 2.6,
            legSeparation: 1,
            legWidth: 0.5,
            scale: 1,
            topBandWidth: 4.4,
          ).looksLikeTPose,
          isFalse);
    });
  });

  group('Die gute Figur besteht', () {
    late List<MarketplaceFinding> befunde;
    setUpAll(() {
      final b = _guteFigur();
      befunde =
          checkMarketplaceFigure(measureMarketplaceFigure(b.positions, b.i));
    });

    test('keine Fehler', () {
      expect(befunde.where((f) => f.blocks), isEmpty,
          reason: befunde.where((f) => f.blocks).map((f) => f.title).join('; '));
    });

    test('Tiefe unter der Grenze', () {
      expect(_finde(befunde, 'tiefe').level, MarketplaceLevel.ok);
    });

    test('Hals erkannt', () {
      expect(_finde(befunde, 'hals').level, MarketplaceLevel.ok);
    });

    test('Beine getrennt', () {
      expect(_finde(befunde, 'beine_getrennt').level, MarketplaceLevel.ok);
    });

    test('Bein-Breite unter der Grenze', () {
      expect(_finde(befunde, 'bein_breite').level, MarketplaceLevel.ok);
    });
  });

  group('Die Kapuzzee-Figur fällt durch – an den richtigen Stellen', () {
    late MarketplaceMeasurement mass;
    late List<MarketplaceFinding> befunde;
    setUpAll(() {
      final b = _schlechteFigur();
      mass = measureMarketplaceFigure(b.positions, b.i);
      befunde = checkMarketplaceFigure(mass);
    });

    test('zu tief', () {
      final f = _finde(befunde, 'tiefe');
      expect(f.level, MarketplaceLevel.fehler);
      expect(mass.depth, greaterThan(marketplaceMaxDepth));
      // Der Befund muss sagen, was im Prompt zu tun ist – nachträglich
      // flach drücken geht nicht.
      expect(f.reason, contains('flat chest and back'));
      expect(f.reason, contains('chunky'));
    });

    test('kein Hals', () {
      final f = _finde(befunde, 'hals');
      expect(f.level, MarketplaceLevel.fehler);
      expect(mass.neckRatio, greaterThan(marketplaceNeckRatio));
      expect(f.reason, contains('neck gap'));
    });

    test('der Saum verbindet die Beine', () {
      final f = _finde(befunde, 'beine_getrennt');
      expect(f.level, MarketplaceLevel.fehler);
      expect(mass.legSeparation, lessThan(marketplaceLegSeparation));
      expect(f.reason, contains('separate leg tubes'));
    });

    test('ein Hals, der knapp nicht reicht, gilt nicht als Hals', () {
      // 59 % der Kopfbreite hat beim echten Auto-Setup-Lauf nicht
      // gereicht: Die Kapuze wurde bis zu den Schultern dem Kopf
      // zugeschlagen. Die Schwelle liegt deshalb bei 50 %.
      expect(marketplaceNeckRatio, 0.50);
      final b = _Bau();
      b.quader(-1.3, 2.25, -0.6, 1.3, 3.9, 0.6);
      b.quader(-0.47, 3.9, -0.47, 0.47, 4.2, 0.47); // Hals, 59 %
      b.quader(-0.8, 4.2, -0.7, 0.8, 5.0, 0.7);
      b.quader(-3.2, 2.6, -0.4, -1.3, 3.85, 0.4);
      b.quader(1.3, 2.6, -0.4, 3.2, 3.85, 0.4);
      b.quader(-0.95, 0.0, -0.45, -0.25, 2.25, 0.45);
      b.quader(0.25, 0.0, -0.45, 0.95, 2.25, 0.45);
      final m = measureMarketplaceFigure(b.positions, b.i);
      expect(m.neckRatio, greaterThan(0.5));
      expect(m.hasNeck, isFalse);
    });

    test('der Text nennt Datum und Herkunft der Werte', () {
      final text = marketplaceAsText(befunde);
      expect(text, contains(marketplaceMeasuredOn));
      expect(text, contains('nicht dokumentiert'));
    });
  });

  group('Deckung', () {
    test('ein voller Quader deckt fast alles ab', () {
      final b = _Bau()..quader(0, 0, 0, 1, 1, 1);
      final anteil =
          silhouetteCoverage(b.positions, b.i, axisU: 0, axisV: 1);
      expect(anteil, greaterThan(0.95));
    });

    test('ein dünner Faden in einem weiten Quader fällt auf', () {
      // Der Fall aus dem Befund: Der Saum bläht den Hüllkörper auf,
      // das Bein darin bleibt dünn.
      final b = _Bau()
        ..quader(-0.03, 0, -0.03, 0.03, 1, 0.03)
        ..quader(-1, 0.98, -1, 1, 1.0, 1);
      final anteil =
          silhouetteCoverage(b.positions, b.i, axisU: 0, axisV: 1);
      expect(anteil, lessThan(0.3));
      final befunde = checkCoverage('LeftLeg', b.positions, b.i);
      expect(befunde, isNotEmpty);
      expect(befunde.first.level, MarketplaceLevel.warnung);
      // Der Bezug muss dabeistehen: eigener Hüllquader, nicht Cage.
      expect(befunde.first.reason, contains('Cage'));
    });

    test('für Arme wird von vorn nicht geprüft', () {
      // Die Schwelle steht im Validator auf 0 – ein Arm darf von vorn
      // ein Strich sein.
      expect(marketplaceCoverage['LeftArm']!.$1, 0);
      final b = _Bau()..quader(-0.02, 0, -0.02, 0.02, 1, 0.02);
      final ids = [
        for (final f in checkCoverage('LeftArm', b.positions, b.i)) f.id,
      ];
      expect(ids.any((id) => id.endsWith('01')), isFalse);
    });
  });

  group('Vorbereitung für Auto Setup', () {
    /// Dieselbe gute Figur, aber wie ein Anbieter sie liefert: viel zu
    /// klein, mit der Armspanne auf z statt auf x.
    Uint8List wieVomAnbieter() {
      final b = _guteFigur();
      final mesh = LocalMesh();
      for (var i = 0; i + 2 < b.p.length; i += 3) {
        // 90° gedreht und auf ein Fünftel geschrumpft.
        mesh.addVertex(-b.p[i + 2] * 0.2, b.p[i + 1] * 0.2,
            b.p[i] * 0.2, 0, 0);
      }
      for (var i = 0; i + 2 < b.i.length; i += 3) {
        mesh.addTriangle(b.i[i], b.i[i + 1], b.i[i + 2]);
      }
      return buildGlb(mesh);
    }

    test('bringt die Figur auf fünf Studs', () async {
      final ergebnis = prepareForAutoSetup(wieVomAnbieter());
      final mesh = await parseGlbForPreview(ergebnis.glb);
      var lo = double.infinity, hi = double.negativeInfinity;
      for (var i = 1; i < mesh.positions.length; i += 3) {
        lo = math.min(lo, mesh.positions[i]);
        hi = math.max(hi, mesh.positions[i]);
      }
      mesh.dispose();
      expect(hi - lo, closeTo(marketplaceFigureStuds, 1e-3));
      expect(lo, closeTo(0, 1e-3), reason: 'steht nicht auf dem Boden');
      expect(ergebnis.report.text, contains('Studs'));
    });

    test('dreht die Armspanne zurück auf x', () async {
      final ergebnis = prepareForAutoSetup(wieVomAnbieter());
      final mesh = await parseGlbForPreview(ergebnis.glb);
      final m = measureMarketplaceFigure(mesh.positions, mesh.indices);
      mesh.dispose();
      expect(m.widthAxis, 0);
      expect(ergebnis.report.turnedDegrees % 90, 0);
      expect(ergebnis.report.text, contains('90°'));
    });

    test('ein zweiter Durchlauf ändert nichts mehr', () {
      final einmal = prepareForAutoSetup(wieVomAnbieter());
      final zweimal = prepareForAutoSetup(einmal.glb);
      expect(zweimal.report.changed, isFalse,
          reason: zweimal.report.text);
    });

    /// Baut die Testfigur mit Zehen in die angegebene Richtung.
    ///
    /// Die Beine bekommen dafür einen Ring auf Schienbeinhöhe – die
    /// Heuristik misst den Fuß gegen das Schienbein, und ein Quader
    /// hat dort keine Punkte.
    Uint8List mitZehen(double richtung) {
      final b = _guteFigur()
        ..quader(-0.95, 0.35, -0.45, -0.25, 1.2, 0.45)
        ..quader(0.25, 0.35, -0.45, 0.95, 1.2, 0.45);
      if (richtung > 0) {
        b
          ..quader(-0.95, 0.0, 0.45, -0.25, 0.35, 1.1)
          ..quader(0.25, 0.0, 0.45, 0.95, 0.35, 1.1);
      } else {
        b
          ..quader(-0.95, 0.0, -1.1, -0.25, 0.35, -0.45)
          ..quader(0.25, 0.0, -1.1, 0.95, 0.35, -0.45);
      }
      final mesh = LocalMesh();
      for (var i = 0; i + 2 < b.p.length; i += 3) {
        mesh.addVertex(b.p[i], b.p[i + 1], b.p[i + 2], 0, 0);
      }
      for (var i = 0; i + 2 < b.i.length; i += 3) {
        mesh.addTriangle(b.i[i], b.i[i + 1], b.i[i + 2]);
      }
      return buildGlb(mesh);
    }

    test('die Zehen müssen in der Datei nach +Z zeigen', () {
      // Verkehrt herum gedacht und trotzdem richtig: Roblox verlangt
      // die Front auf −Z, aber Studios glTF-Import spiegelt Z. Was in
      // der GLB auf −Z liegt, kommt in Studio auf +Z heraus. Zwei
      // Auto-Setup-Läufe sind mit einer rückwärts stehenden Figur
      // gelaufen, weil die Vorbereitung der Doku gefolgt ist statt der
      // Messung.
      //
      // Zehen schon auf +Z: nichts zu tun.
      final schon = prepareForAutoSetup(mitZehen(1));
      expect(schon.report.turnedDegrees, 0);

      // Zehen auf −Z: umdrehen.
      final gedreht = prepareForAutoSetup(mitZehen(-1));
      expect(gedreht.report.turnedDegrees, 180);
      expect(gedreht.report.text, contains('spiegelt Z'));

      // Und danach ist Schluss: ein zweiter Durchlauf dreht nicht.
      expect(prepareForAutoSetup(gedreht.glb).report.turnedDegrees, 0);
    });

    test('bei unklarer Blickrichtung wird nichts gedreht, und das '
        'steht im Bericht', () {
      final ergebnis = prepareForAutoSetup(wieVomAnbieter());
      expect(ergebnis.report.text, contains('nicht bestimmbar'));
    });

    test('ein mitgebrachtes Skelett fällt weg, die Punkte bleiben', () {
      // Vorher gab es hier eine Absage. Die war in der Sache falsch:
      // Auto Setup verwirft das Skelett ohnehin, und die Datei lässt
      // sich in zwei Handgriffen brauchbar machen.
      final geriggt = injectAutoRig(wieVomAnbieter(), rigType: 'biped');
      final vorher = splitGlb(geriggt).json;
      expect((vorher['skins'] as List).length, greaterThan(0));

      final ergebnis = prepareForAutoSetup(geriggt);
      final json = splitGlb(ergebnis.glb).json;

      // Kein Skelett, keine Gewichte.
      expect(json.containsKey('skins'), isFalse);
      expect(json.containsKey('animations'), isFalse);
      for (final mesh in (json['meshes'] as List).cast<Map>()) {
        for (final prim in (mesh['primitives'] as List).cast<Map>()) {
          final attribute = (prim['attributes'] as Map).keys.cast<String>();
          expect(attribute.where((k) => k.startsWith('JOINTS_')), isEmpty);
          expect(attribute.where((k) => k.startsWith('WEIGHTS_')), isEmpty);
        }
      }
      expect(ergebnis.report.bonesRemoved, greaterThan(0));
      expect(ergebnis.report.text, contains('Bindepose'));

      // Das Netz hängt ohne Elterntransformation direkt in der Szene.
      // Ohne Skin gilt die glTF-Regel nicht mehr, dass die
      // Transformation ignoriert wird – eine geerbte würde die Figur
      // verschieben.
      final nodes = (json['nodes'] as List).cast<Map>();
      final wurzeln =
          (((json['scenes'] as List)[0] as Map)['nodes'] as List).cast<int>();
      final netzKnoten = [
        for (var i = 0; i < nodes.length; i++)
          if (nodes[i].containsKey('mesh')) i,
      ];
      expect(netzKnoten, isNotEmpty);
      for (final i in netzKnoten) {
        expect(wurzeln, contains(i), reason: 'Netz hängt nicht in der Szene');
        for (final key in ['matrix', 'translation', 'rotation', 'scale']) {
          expect(nodes[i].containsKey(key), isFalse, reason: key);
        }
        // Und es ist nirgends zusätzlich Kind – sonst käme es zweimal
        // vor, einmal mit fremder Transformation.
        for (final node in nodes) {
          expect(((node['children'] as List?) ?? const []).cast<int>(),
              isNot(contains(i)));
        }
      }
      // Kein Kind zeigt ins Leere.
      for (final node in nodes) {
        for (final c in ((node['children'] as List?) ?? const []).cast<int>()) {
          expect(c, lessThan(nodes.length));
        }
      }
    });

    test('das Entfernen selbst rührt die Punkte nicht an', () {
      // prepareForAutoSetup skaliert und verschiebt danach – das darf
      // den Nachweis nicht verwischen. Deshalb hier nur der Schnitt.
      final geriggt = injectAutoRig(wieVomAnbieter(), rigType: 'biped');
      final teil = splitGlb(geriggt);
      final json = teil.json;
      final vorher = [
        for (final mesh in (json['meshes'] as List).cast<Map>())
          for (final prim in (mesh['primitives'] as List).cast<Map>())
            readGltfFloats(json, teil.bin,
                (prim['attributes'] as Map)['POSITION'] as int),
      ];
      final bericht = stripRigForAutoSetup(json);
      expect(bericht.didSomething, isTrue);
      final nachher = [
        for (final mesh in (json['meshes'] as List).cast<Map>())
          for (final prim in (mesh['primitives'] as List).cast<Map>())
            readGltfFloats(json, teil.bin,
                (prim['attributes'] as Map)['POSITION'] as int),
      ];
      expect(nachher.length, vorher.length);
      for (var i = 0; i < vorher.length; i++) {
        expect(nachher[i].length, vorher[i].length);
        for (var k = 0; k < vorher[i].length; k++) {
          expect(nachher[i][k], vorher[i][k]);
        }
      }
    });

    test('ohne Skelett ändert sich nichts', () {
      final json = splitGlb(wieVomAnbieter()).json;
      final vorher = (json['nodes'] as List).length;
      final bericht = stripRigForAutoSetup(json);
      expect(bericht.didSomething, isFalse);
      expect(bericht.bones, 0);
      expect((json['nodes'] as List).length, vorher);
    });
  });
}
