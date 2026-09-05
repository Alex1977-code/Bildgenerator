import 'dart:typed_data';

import 'dart:math' as math;

import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/roblox_face_parts.dart'
    show headBottomBand;
import 'package:bildgenerator/services/roblox_marketplace.dart';
import 'package:bildgenerator/services/roblox_prompt.dart'
    show robloxMarketplaceTail;
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
///
/// Die Arme stehen in **A-Pose**, aus Treppenstufen gebaut: von der
/// Schulter bei 3,85 schräg nach unten außen bis zur Hand auf 1,95.
/// Vorher lagen sie waagerecht, und das war ein Fehler in der Vorlage,
/// keiner in der Prüfung – die Figur stand in T-Pose und der Prüfer
/// hat recht behalten, als er das gemeldet hat.
_Bau _guteFigur() {
  final b = _Bau();
  // Die Hüfte sitzt bei 45 % der Höhe – so steht ein R15-Körper.
  // Der Schritt bei 2,15: Vom Halsband (3,9) bis dorthin sind es
  // 1,75 – über den absoluten 1,70, die die Doku für den Rumpf
  // verlangt. Bei 2,25 wären es 1,65, und die gute Figur fiele an der
  // Regel, die seit August 2026 geprüft wird.
  b.quader(-1.3, 2.15, -0.6, 1.3, 3.9, 0.6); // Rumpf
  b.quader(-0.35, 3.9, -0.35, 0.35, 4.2, 0.35); // Hals, schmal
  b.quader(-0.8, 4.2, -0.7, 0.8, 5.0, 0.7); // Kopf
  // Arme, je fünf Stufen von der Schulter (x 1,30 / y 3,85) zur Hand
  // (x 3,20 / y 1,95): 1,90 nach außen auf 1,90 nach unten, also
  // genau 45°. Die Armspanne bleibt bei 6,40 – über den geforderten
  // 6,22 –, aber die breiteste Stelle liegt jetzt unten.
  const stufen = 5;
  for (var i = 0; i < stufen; i++) {
    final xa = 1.3 + 1.9 * i / stufen;
    final xb = 1.3 + 1.9 * (i + 1) / stufen;
    final yo = 3.85 - 1.9 * i / stufen;
    final yu = yo - 0.5;
    b.quader(-xb, yu, -0.4, -xa, yo, 0.4); // Arm links
    b.quader(xa, yu, -0.4, xb, yo, 0.4); // Arm rechts
  }
  b.quader(-0.95, 0.0, -0.45, -0.25, 2.15, 0.45); // Bein links
  b.quader(0.25, 0.0, -0.45, 0.95, 2.15, 0.45); // Bein rechts
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

      // Ohne Bund eine Bestätigung statt eines Fehlers: Jede
      // messbare Vorgabe meldet sich, damit man sieht, dass sie
      // geprüft wurde.
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
          )).where((f) => f.id == 'taille').single.level,
          MarketplaceLevel.ok);
    });

    test('T-Pose wird am Ergebnis erkannt, nicht am Prompt', () {
      // Zweimal stand der A-Pose-Text im Prompt, und zweimal kam die
      // Figur waagerecht zurück. Armspanne 5,06 bei 5,00 Höhe, und die
      // breiteste Stelle sitzt auf Schulterhöhe.
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
        widestBandHeight: 0.77,
      );
      expect(tPose.looksLikeTPose, isTrue);
      final f = checkMarketplaceFigure(tPose).where((f) => f.id == 'pose');
      expect(f, hasLength(1));
      expect(f.single.origin, MarketplaceOrigin.prompt);
      expect(f.single.title, contains('T-Pose gemessen'));
      expect(f.single.title, contains('77 %'));

      // Dieselbe Spanne, aber die breiteste Stelle liegt unten: Das
      // sind hängende Arme, keine T-Pose. Der Unterschied ist die
      // Höhe, nicht die Breite – die Armspanne **muss** über
      // 1,24 × Höhe liegen, sonst fällt die Figur an der
      // Armspannen-Regel durch.
      expect(
          const MarketplaceMeasurement(
            height: 5,
            width: 6.4,
            depth: 1.5,
            widthAxis: 0,
            headWidth: 1.3,
            neckWidth: 0.6,
            shoulderWidth: 2.6,
            legSeparation: 1,
            legWidth: 0.5,
            scale: 1,
            topBandWidth: 5.4,
            widestBandHeight: 0.47,
          ).looksLikeTPose,
          isFalse);
      // Und eine schmale Figur ist auch dann keine T-Pose, wenn sie
      // oben am breitesten ist – das kann ein Sonnenhut sein.
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
            topBandWidth: 3.0,
            widestBandHeight: 0.9,
          ).looksLikeTPose,
          isFalse);
    });
  });

  group('Die gute Figur besteht', () {
    late List<MarketplaceFinding> befunde;
    late MarketplaceMeasurement mass;
    setUpAll(() {
      final b = _guteFigur();
      mass = measureMarketplaceFigure(b.positions, b.i);
      befunde = checkMarketplaceFigure(mass);
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

    test('die Höhen stimmen: Rumpf, Beine, Kopf, Arm', () {
      // Absolute Mindestmaße aus der Doku: Rumpf 1,7, Bein 1,4, Arm
      // 1,5. Gemessen am Netz, nicht angenommen.
      expect(mass.torsoHeight, greaterThanOrEqualTo(specMinTorsoHeight));
      expect(mass.legHeight, greaterThanOrEqualTo(specMinLegHeight));
      expect(mass.armLength, greaterThanOrEqualTo(specMinArmLength));
      expect(mass.headHeight, lessThan(RobloxBodyScale.normal.maxHeadHeight));
      for (final id in ['rumpf_hoehe', 'bein_hoehe', 'hoehenrechnung']) {
        expect(_finde(befunde, id).level, MarketplaceLevel.ok, reason: id);
      }
      expect(_finde(befunde, 'kopf_breite').level, MarketplaceLevel.ok);
      expect(_finde(befunde, 'arme_frei').level, MarketplaceLevel.ok);
    });

    test('hängende Arme heißen I-Pose, nicht „Arm zu kurz"', () {
      // Die dritte echte Figur: Spanne 1,77 bei einem Rumpf von 1,00 –
      // die Arme liegen am Körper. Vorher standen dafür zwei
      // Warnungen da („Arm etwa 0,55 lang" und „Armspanne 1,77 von
      // 4,69"), beide mit dem Zusatz „in I-Pose sagt die Zahl nichts",
      // ohne die I-Pose je zu erkennen. Auto Setup nennt sie
      // ausdrücklich schlechter.
      const i = MarketplaceMeasurement(
        height: 5,
        width: 1.77,
        depth: 1.18,
        widthAxis: 0,
        headWidth: 1.22,
        neckWidth: 0.44,
        shoulderWidth: 1.2,
        spanTorsoWidth: 1.0,
        legSeparation: 1,
        legWidth: 0.47,
        scale: 1,
        headHeight: 1.3,
        torsoHeight: 2.0,
        legHeight: 1.7,
        armLength: 0.55,
      );
      final f = _finde(checkMarketplaceFigure(i), 'arme_frei');
      expect(f.level, MarketplaceLevel.warnung);
      expect(f.origin, MarketplaceOrigin.prompt);
      expect(f.title, contains('stehen nur'));
      expect(f.reason, contains('I-Pose'));
      // Und die Zahl wird nicht als Armlänge ausgegeben: Die lässt
      // sich an dieser Silhouette nicht messen.
      expect(f.reason, contains('ungeprüft'));
      // Genau **ein** Befund zu den Armen, nicht zwei.
      expect(checkMarketplaceFigure(i).where((x) => x.id == 'armspanne'),
          isEmpty);
    });

    test('der Bericht sagt, was er nicht prüfen kann', () {
      // „keine Fehler" las sich wie „darf hochgeladen werden". Der
      // Modesty-Layer ist eine Frage ans Aussehen, nicht an die Form.
      final text = marketplaceAsText(checkMarketplaceFigure(mass));
      expect(text, contains('Nicht messbar'));
      expect(text, contains('Modesty-Layer'));
      expect(text, contains('FACS'));
    });

    test('die Skala entscheidet: derselbe Kopf fällt bei Classic durch',
        () {
      // Kopf 1,6 breit: Normal erlaubt 3, Classic 1,5.
      final classic =
          checkMarketplaceFigure(mass, scale: RobloxBodyScale.classic);
      final kopf = _finde(classic, 'kopf_breite');
      expect(kopf.level, MarketplaceLevel.fehler);
      expect(kopf.reason, contains('Rthro'));
      // Die Tiefe ist absolut: 2,2 geht bei Normal (2,25), nicht bei
      // Classic (2,00) – unabhängig von der Höhe.
      const tief = MarketplaceMeasurement(
        height: 5,
        width: 6.4,
        depth: 2.2,
        widthAxis: 0,
        headWidth: 1.3,
        neckWidth: 0.6,
        shoulderWidth: 2.6,
        legSeparation: 1,
        legWidth: 0.5,
        scale: 1,
        widestBandHeight: 0.47,
      );
      expect(_finde(checkMarketplaceFigure(tief), 'tiefe').level,
          MarketplaceLevel.ok);
      expect(
          _finde(checkMarketplaceFigure(tief, scale: RobloxBodyScale.classic),
                  'tiefe')
              .level,
          MarketplaceLevel.fehler);
    });

    test('ein zu großer Kopf sprengt die Höhenrechnung', () {
      // 2,0 Studs Kopf bei 5,0 Höhe: darunter bleiben 3,0, Rumpf und
      // Beine brauchen 3,1.
      const gross = MarketplaceMeasurement(
        height: 5,
        width: 6.4,
        depth: 1.5,
        widthAxis: 0,
        headWidth: 2.4,
        neckWidth: 0.8,
        shoulderWidth: 2.6,
        legSeparation: 1,
        legWidth: 0.5,
        scale: 1,
        widestBandHeight: 0.47,
        headHeight: 2.0,
        torsoHeight: 1.6,
        legHeight: 1.4,
        armLength: 2.0,
      );
      final f = checkMarketplaceFigure(gross);
      expect(_finde(f, 'hoehenrechnung').level, MarketplaceLevel.fehler);
      expect(_finde(f, 'hoehenrechnung').reason, contains('6 Studs'));
      expect(_finde(f, 'rumpf_hoehe').level, MarketplaceLevel.fehler);
      // Bei Normal geht der 2,4er Kopf, bei Slender (2,0) nicht.
      expect(_finde(f, 'kopf_breite').level, MarketplaceLevel.ok);
      expect(
          _finde(checkMarketplaceFigure(gross, scale: RobloxBodyScale.slender),
                  'kopf_breite')
              .level,
          MarketplaceLevel.fehler);
    });

    test('die Deckung verlangt 50 % für jedes Teil, auch den Kopf', () {
      for (final entry in marketplaceCoverage.entries) {
        expect(entry.value.$1, specMinCoveragePercent, reason: entry.key);
        expect(entry.value.$2, specMinCoveragePercent, reason: entry.key);
      }
    });

    test('die A-Pose wird nicht als T-Pose gemeldet', () {
      // Der Punkt, an dem die frühere Erkennung zerbrach: Die
      // Armspanne muss über 6,22 Studs liegen, also über 1,24 × Höhe –
      // damit ist die Spanne allein nie ein Unterscheidungsmerkmal.
      expect(mass.width, greaterThanOrEqualTo(marketplaceMinArmSpan));
      expect(mass.width,
          greaterThan(mass.height * marketplaceTPoseSpan));
      // Entscheidend ist die Höhe der breitesten Stelle: an den
      // hängenden Händen, nicht an der Schulter.
      expect(mass.widestBandHeight,
          lessThan(marketplaceTPoseHeight));
      expect(mass.looksLikeTPose, isFalse);
      expect(_finde(befunde, 'pose').level, MarketplaceLevel.ok);
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
      expect(f.reason, contains('narrow visible neck'));
    });

    test('der Saum verbindet die Beine', () {
      final f = _finde(befunde, 'beine_getrennt');
      expect(f.level, MarketplaceLevel.fehler);
      expect(mass.legSeparation, lessThan(marketplaceLegSeparation));
      expect(f.reason, contains('gap between the thighs'));
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

    test('auch Arme müssen 50 % füllen – wie jedes Teil', () {
      // Vorher stand die Schwelle für Arme auf 0 („ein Arm darf von
      // vorn ein Strich sein"). Die Doku sagt 50 % für jedes Teil, und
      // seit August 2026 wird darauf geprüft. Ein voller Quader füllt
      // seinen eigenen Hüllkörper – gemessen wird hier gegen den
      // eigenen, nicht gegen den Cage; der ist strenger.
      expect(marketplaceCoverage['LeftArm']!.$1, specMinCoveragePercent);
      expect(marketplaceCoverage['DynamicHead']!.$1, specMinCoveragePercent);
      final b = _Bau()..quader(-0.02, 0, -0.02, 0.02, 1, 0.02);
      expect(checkCoverage('LeftArm', b.positions, b.i), isEmpty);
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

  group('Jede Vorgabe hat einen Zuständigen, und die Prüfung nennt ihn',
      () {
    // Der Anspruch: Der Nutzer beschreibt nur die Figur, alles Übrige
    // steht fest, und die Prüfung bestätigt es Punkt für Punkt. Diese
    // Tests halten beide Richtungen fest.

    test('jeder Satz der Tabelle steht wörtlich im Schwanz', () {
      for (final r in marketplaceRules) {
        if (r.clause.isEmpty) continue;
        expect(robloxMarketplaceTail, contains(r.clause),
            reason: 'Die Vorgabe „${r.demand}" beruft sich auf einen '
                'Satz, der nicht (mehr) im Marktplatz-Schwanz steht: '
                '„${r.clause}"');
      }
    });

    test('im Schwanz steht nichts, was zu keiner Vorgabe gehört', () {
      // Die Gegenrichtung zum Test darüber – und die eigentliche
      // Zusage: Der Prompt beschreibt genau das, was Roblox
      // vorschreibt, nichts weniger und nichts mehr. Geprüft wird am
      // Standard-Schwanz (Normal, 5 Studs); bei anderen Skalen wechselt
      // nur das Tiefenwort, siehe robloxDepthWords.
      var rest = robloxMarketplaceTail;
      // Längste zuerst, damit ein kurzer Satz keinen längeren
      // zerreißt.
      final saetze = marketplacePromptClauses()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final satz in saetze) {
        expect(rest, contains(satz),
            reason: 'Der Satz „$satz“ steht nicht (mehr) im Schwanz.');
        rest = rest.replaceFirst(satz, '');
      }
      final uebrig = rest.replaceAll(RegExp(r'[,\s]+'), '');
      expect(uebrig, isEmpty,
          reason: 'Im Marktplatz-Schwanz steht „$uebrig“ – ein Satz, '
              'den keine Vorgabe in marketplaceRules beansprucht. '
              'Entweder gehört er dort eingetragen (mit Belegstelle), '
              'oder er hat im Prompt nichts zu suchen.');
    });

    test('jede Regel, die die Prüfung melden kann, steht in der Tabelle',
        () {
      // Einmal an einer guten und einmal an einer mangelhaften Figur,
      // damit beide Zweige jeder Regel vorkommen.
      final b = _guteFigur();
      final gut = measureMarketplaceFigure(b.positions, b.i);
      const schlecht = MarketplaceMeasurement(
        height: 5,
        width: 4.8,
        depth: 2.6,
        widthAxis: 0,
        headWidth: 3.4,
        neckWidth: 3.2,
        shoulderWidth: 3.3,
        legSeparation: 0.2,
        legWidth: 1.9,
        scale: 1,
        waistWidth: 1.0,
        headHeight: 2.4,
        torsoHeight: 1.1,
        legHeight: 0.9,
        armLength: 0.4,
        spanTorsoWidth: 2.0,
        widestBandHeight: 0.8,
      );
      final ids = <String>{
        for (final f in checkMarketplaceFigure(gut)) f.id,
        for (final f in checkMarketplaceFigure(schlecht)) f.id,
        for (final f in checkMarketplaceFigure(
            const MarketplaceMeasurement(
                height: 0,
                width: 0,
                depth: 0,
                widthAxis: 0,
                headWidth: 0,
                neckWidth: 0,
                shoulderWidth: 0,
                legSeparation: 0,
                legWidth: 0,
                scale: 1)))
          f.id,
      };
      for (final id in ids) {
        expect(marketplaceRuleFor(id), isNotNull,
            reason: 'Die Prüfung meldet „$id", aber in '
                'marketplaceRules steht dazu nichts – dann kann die '
                'Anzeige auch nicht sagen, wer dafür sorgt.');
      }
      // Und jede Zeile der Prüfung trägt ihre Regel mit.
      for (final f in checkMarketplaceFigure(gut)) {
        expect(f.rule, isNotNull);
      }
    });

    test('an der guten Figur bestätigt die Prüfung jede messbare '
        'Vorgabe', () {
      final b = _guteFigur();
      final befunde = checkMarketplaceFigure(
          measureMarketplaceFigure(b.positions, b.i));
      final gemeldet = {for (final f in befunde) f.id};
      for (final r in marketplaceRules) {
        if (r.id.isEmpty || r.id == 'keine_geometrie') continue;
        expect(gemeldet, contains(r.id),
            reason: 'Die Vorgabe „${r.demand}" wird an einer '
                'einwandfreien Figur gar nicht erwähnt – dann sieht '
                'niemand, dass sie geprüft wurde.');
      }
      // Und zwar bestätigend, nicht bemängelnd.
      expect(befunde.where((f) => f.level == MarketplaceLevel.fehler),
          isEmpty);
    });

    test('keine Vorgabe ohne Zuständigen', () {
      for (final r in marketplaceRules) {
        if (r.owner != MarketplaceRuleOwner.nobody) continue;
        // Genau zwei Ausnahmen, beide mit Begründung im Feld note.
        expect(r.note, isNotEmpty,
            reason: 'Für „${r.demand}" sorgt niemand, und es steht '
                'nicht dabei, warum.');
      }
      // Was die Prüfung messen kann, muss auch jemand herstellen
      // können – Prompt oder Reparatur.
      for (final r in marketplaceRules) {
        if (r.id.isEmpty || r.id == 'keine_geometrie') continue;
        expect(r.clause.isNotEmpty || r.repairStep.isNotEmpty, isTrue,
            reason: 'Die Regel „${r.id}" wird gemessen, aber weder der '
                'Prompt noch die Reparatur stellen sie her.');
      }
    });

    test('die Liste „anderswo erledigt" nennt genau die Vorgaben ohne '
        'Messung', () {
      final zeilen = marketplaceHandledElsewhere();
      expect(zeilen.length,
          marketplaceRules.where((r) => r.id.isEmpty).length);
      expect(zeilen.join(' '), contains('Auto Setup 7'),
          reason: 'die Vorderseite auf −Z macht die Vorbereitung');
      expect(zeilen.join(' '), contains('Auto Setup 12'),
          reason: 'die Textur legt der Export bei');
    });
  });

  group('Kopfunterkante statt oberstes Fünftel', () {
    test('das Breitenprofil verrät, wo der Kopf aufhört', () {
      // 50 Bänder: unten Rumpf (1,8), dann Schulter, ein schmaler
      // Hals bei 40–42, darüber der Kopf.
      final profil = <double>[
        for (var b = 0; b < 40; b++) 1.8,
        for (var b = 40; b < 43; b++) 0.26,
        for (var b = 43; b < 50; b++) 0.62,
      ];
      expect(headBottomBand(profil), 43);

      // Eine Säule ohne jede Einschnürung hat keine Kopfgrenze.
      expect(headBottomBand(List<double>.filled(50, 1.0)), isNull);

      // Und ein leeres Profil auch nicht.
      expect(headBottomBand(List<double>.filled(50, 0)), isNull);
    });

    test('ein kleiner Kopf über breiten Schultern wird richtig '
        'gemessen – und sein Hals gefunden', () async {
      // Der Fall aus der vierten und fünften Figur: Kopf 0,62 breit,
      // Schultern 1,80, und die Schultern ragen ins oberste Fünftel.
      // Mit „das oberste Fünftel ist der Kopf" wurde die Schulter zur
      // Kopfbreite (1,80). Dann liegt der echte Hals **über** dem so
      // bestimmten Kopfband, und die Suche nach der schmalsten Stelle
      // darunter kann ihn gar nicht finden: gemessen 1,80 von 1,80,
      // also 100 % – „kein erkennbarer Hals" für eine Figur, die
      // einen hat.
      final b = _Bau();
      b.quader(-0.7, 0.0, -0.5, -0.1, 2.1, 0.5); // linkes Bein
      b.quader(0.1, 0.0, -0.5, 0.7, 2.1, 0.5); // rechtes Bein
      b.quader(-0.7, 2.1, -0.5, 0.7, 3.9, 0.5); // Rumpf
      b.quader(-0.9, 3.9, -0.5, 0.9, 4.05, 0.5); // Schultern, 1,80
      b.quader(-0.13, 4.05, -0.13, 0.13, 4.3, 0.13); // Hals, 0,26
      b.quader(-0.31, 4.3, -0.31, 0.31, 5.0, 0.31); // Kopf, 0,62

      final m = measureMarketplaceFigure(b.positions, b.i);
      expect(m.headWidth, closeTo(0.62, 0.08),
          reason: 'die Kopfbreite, nicht die Schulterbreite');
      expect(m.shoulderWidth, closeTo(1.8, 0.08));
      expect(m.neckWidth, closeTo(0.26, 0.08));
      expect(m.neckRatio, closeTo(0.42, 0.06));
      expect(m.hasNeck, isTrue,
          reason: 'Hals 0,26 gegen Kopf 0,62 sind 42 %, erlaubt sind 50');
    });
  });

  group('Maßstab gegen die absoluten Mindestmaße', () {
    // Die Mindestmaße sind absolut, die Gesamthöhe ist frei (3,6 bis
    // 9,5 Studs). Also lässt sich „Bein 1,30 von mindestens 1,4"
    // durch eine größere Ausgabe lösen – ohne ein einziges Verhältnis
    // zu ändern.
    MarketplaceMeasurement mass({
      double height = 5.0,
      double legHeight = 1.3,
      double torsoHeight = 1.9,
      double headHeight = 1.2,
      double headWidth = 1.0,
      double depth = 1.5,
      double width = 3.0,
      double torsoWidth = 1.4,
      double legWidth = 0.6,
    }) =>
        MarketplaceMeasurement(
          height: height,
          width: width,
          widthAxis: 0,
          depth: depth,
          headWidth: headWidth,
          neckWidth: headWidth * 0.4,
          shoulderWidth: torsoWidth,
          legSeparation: 1.0,
          headHeight: headHeight,
          torsoHeight: torsoHeight,
          legHeight: legHeight,
          legWidth: legWidth,
          spanTorsoWidth: torsoWidth,
          scale: 1.0,
        );

    test('kurze Beine bestimmen den Faktor, die Höhe folgt', () {
      final fit = fitMarketplaceScale(mass());
      expect(fit.needsScaling, isTrue);
      expect(fit.possible, isTrue);
      expect(fit.forcedBy, 'Beinhöhe');
      expect(fit.needed, closeTo(1.4 / 1.3 * marketplaceScaleMargin, 0.001));
      expect(fit.height, closeTo(5.41, 0.02));
      // Der Aufschlag muss die Grenze wirklich überschreiten – genau
      // treffen reicht nicht, siehe [marketplaceScaleMargin].
      expect(1.3 * fit.needed, greaterThan(specMinLegHeight));
    });

    test('eine Figur, die alle Mindestmaße hält, wird nicht '
        'angefasst', () {
      final fit = fitMarketplaceScale(mass(legHeight: 1.6));
      expect(fit.needsScaling, isFalse);
      expect(fit.needed, 1.0);
    });

    test('die Tiefe deckelt den Maßstab – aber die gestauchte', () {
      // Roh 2,20 tief: Platz bis 2,25 ist nur der Faktor 1,023, und
      // der reicht für die Beine nicht. Nach dem Stauchen auf 1,95
      // sind es 1,154 – und dann geht es.
      final roh = fitMarketplaceScale(mass(depth: 2.2));
      expect(roh.possible, isFalse);
      expect(roh.limitedBy, 'Tiefe');

      final nachStauchen =
          fitMarketplaceScale(mass(depth: 2.2), depthAfterRepair: 1.95);
      expect(nachStauchen.possible, isTrue);
      expect(nachStauchen.allowed, closeTo(2.25 / 1.95, 0.001));
    });

    test('falsche Verhältnisse rettet kein Maßstab', () {
      // Ein Kopf, der schon 2,0 Studs hoch ist, darf nicht größer
      // werden – gleichzeitig bräuchten die Beine mehr.
      final fit = fitMarketplaceScale(mass(headHeight: 2.0));
      expect(fit.needsScaling, isTrue);
      expect(fit.possible, isFalse);
      expect(fit.limitedBy, 'Kopfhöhe');
    });

    test('die Skala setzt die Höchstgrenzen', () {
      // Classic deckelt den Kopf bei 1,5 Studs Breite, Normal bei 3.
      final classic = fitMarketplaceScale(mass(headWidth: 1.45),
          scale: RobloxBodyScale.classic);
      expect(classic.limitedBy, 'Kopfbreite');
      expect(classic.possible, isFalse);
      final normal = fitMarketplaceScale(mass(headWidth: 1.45));
      expect(normal.possible, isTrue);
    });
  });
}
