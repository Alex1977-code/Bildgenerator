/// Die Regeln des Marktplatz-Validators – die, die nirgends stehen.
///
/// Eine Figur kann im eigenen Erlebnis tadellos laufen und trotzdem
/// vom Marktplatz abgelehnt werden. Genau das ist „Kapuzzee" passiert:
/// als Startfigur einwandfrei, beim Hochladen abgewiesen, weil der
/// Rumpf zu tief und die Beine zu breit sind.
///
/// Diese Grenzen stehen **nicht in der Dokumentation**. Sie sind am
/// Validator gemessen (Übergabe vom 31.08.2026) und stammen teils aus
/// dessen Quelltext (`UGCValidation/flags/`). Deshalb tragen sie hier
/// eigene Konstanten und nicht die aus `roblox_spec.dart`: Was
/// dokumentiert ist, gehört dorthin; was gemessen ist, hierher – samt
/// dem Datum, an dem es galt.
///
/// **Der wichtigste Satz aus dem Befund:** Diese Fehler entstehen beim
/// Prompt, nicht beim Export. Eine zu tiefe Figur lässt sich nicht
/// nachträglich flach machen, ohne sie zu verformen. Die Prüfung hier
/// ist deshalb vor allem eine **Frühwarnung** – sie sagt, dass der
/// nächste Lauf einen anderen Prompt braucht.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Das Datum, an dem diese Werte am Validator gemessen wurden.
const String marketplaceMeasuredOn = '2026-08-31';

/// Die Figurenhöhe, auf die alle Grenzen unten bezogen sind.
const double marketplaceFigureStuds = 5.0;

/// Größte Tiefe des Rumpfes (die kleinere waagerechte Achse).
///
/// Kapuzzee: 2,45 – abgelehnt. Der Prompt hatte „chunky" bestellt.
const double marketplaceMaxDepth = 2.00;

/// Größte Breite eines einzelnen Beins.
const double marketplaceMaxLegWidth = 1.50;

/// Größte Tiefe eines einzelnen Beins.
const double marketplaceMaxLegDepth = 2.00;

/// Kleinste Rumpfbreite – „flach" darf nicht „dünn" werden.
const double marketplaceMinTorsoWidth = 2.54;

/// Kleinste Armspanne über beide Arme.
const double marketplaceMinArmSpan = 6.22;

/// Ab wann ein Hals als Hals durchgeht: Die schmalste Stelle zwischen
/// Kopf und Schulter muss **halb so breit** sein wie der Kopf.
///
/// Die Zahl kommt aus einem gescheiterten Lauf, nicht aus einer
/// Schätzung. Erst stand hier 0,80 – „deutlich schmaler". Der erste
/// echte Durchgang durch Roblox' Auto Setup zeigte, dass das nicht
/// reicht: Eine Figur mit 0,92 gegen 1,57 Kopfbreite (59 %) wurde
/// segmentiert, als gehörte die Kapuze bis zu den Schultern zum Kopf –
/// heraus kam ein „Head" von 3,75 Studs Breite. Unter 50 % ist die
/// Einschnürung eindeutig genug.
const double marketplaceNeckRatio = 0.50;

/// Wie weit hinauf vom Boden nach getrennten Beinen gesucht wird.
const double marketplaceLegZone = 0.45;

/// Wie viele der Bänder in dieser Zone zwei getrennte Inseln zeigen
/// müssen.
///
/// Kapuzzee: 50 % – der Hoodie-Saum verband beide Beine. Nach der
/// Prompt-Änderung 76 %, immer noch unter der Grenze, weil Tripo
/// „hip-length" als Mitte Oberschenkel gelesen hat.
const double marketplaceLegSeparation = 0.80;

/// Wie viel Prozent seines Hüllkörpers ein Teil aus welcher Richtung
/// ausfüllen muss. Standardwerte aus `UGCValidation/flags/`.
///
/// Reihenfolge: von vorn, von der Seite, von oben. Ein Wert von 0
/// heißt: aus dieser Richtung wird nicht geprüft.
const Map<String, (int, int, int)> marketplaceCoverage = {
  'DynamicHead': (30, 30, 30),
  'Torso': (50, 46, 10),
  'LeftArm': (0, 0, 10),
  'RightArm': (0, 0, 10),
  'LeftLeg': (30, 30, 10),
  'RightLeg': (30, 30, 10),
};

/// Wie schwer ein Marktplatz-Befund wiegt.
enum MarketplaceLevel {
  /// Der Validator lehnt ab.
  fehler,

  /// Geht durch, ist aber knapp oder aus der Datei nicht sicher zu
  /// messen.
  warnung,

  /// Regel eingehalten.
  ok,
}

/// Ein einzelner Befund.
class MarketplaceFinding {
  const MarketplaceFinding({
    required this.id,
    required this.level,
    required this.title,
    required this.reason,
  });

  final String id;
  final MarketplaceLevel level;
  final String title;

  /// Warum das zählt – und was im **Prompt** dagegen hilft, denn dort
  /// entsteht es.
  final String reason;

  bool get blocks => level == MarketplaceLevel.fehler;
}

/// Was an der Figur gemessen wurde – alles in Studs bei
/// [marketplaceFigureStuds] Höhe.
class MarketplaceMeasurement {
  const MarketplaceMeasurement({
    required this.height,
    required this.width,
    required this.depth,
    required this.widthAxis,
    required this.headWidth,
    required this.neckWidth,
    required this.shoulderWidth,
    required this.legSeparation,
    required this.legWidth,
    required this.scale,
  });

  /// Höhe in Studs nach der Skalierung – immer
  /// [marketplaceFigureStuds], wenn etwas zu messen war.
  final double height;

  /// Die **größere** waagerechte Achse: die Armspanne.
  final double width;

  /// Die kleinere waagerechte Achse: die Tiefe.
  final double depth;

  /// Welche Achse die Armspanne trägt: 0 = x, 2 = z.
  ///
  /// Nicht angenommen, sondern gemessen: Ein Lauf kam mit der
  /// Armspanne auf z herein. Wer x voraussetzt, misst dann die Tiefe
  /// als Breite und lässt eine abgelehnte Figur durchgehen.
  final int widthAxis;

  /// Breiteste Stelle des Kopfes.
  final double headWidth;

  /// Schmalste Stelle zwischen Kopf und Schulter.
  final double neckWidth;

  /// Breite an der Schulter.
  final double shoulderWidth;

  /// Anteil der Bänder in der Beinzone, die in zwei getrennte Inseln
  /// zerfallen (0 bis 1).
  final double legSeparation;

  /// Breite eines einzelnen Beins – die breiteste Stelle unterhalb
  /// der Hüfte, geteilt durch zwei. Null, wenn dort nichts liegt.
  final double legWidth;

  /// Mit welchem Faktor auf [marketplaceFigureStuds] gerechnet wurde.
  final double scale;

  /// Wie schmal der Hals gegenüber Kopf und Schulter ist.
  double get neckRatio {
    final bezug = math.min(headWidth, shoulderWidth);
    return bezug <= 0 ? 1.0 : neckWidth / bezug;
  }

  bool get hasNeck => neckRatio <= marketplaceNeckRatio;
}

/// Misst eine Figur aus ihrer Geometrie.
///
/// Ohne Skelett – und das ist Absicht: Für den Marktplatz-Weg über
/// Roblox' Auto Setup soll die Datei **kein** Skelett tragen, und
/// gerade dort müssen diese Prüfungen greifen.
///
/// Gemessen wird an **Dreiecken, nicht an Punkten**. Der erste Anlauf
/// zählte nur Vertices, und an einer grob unterteilten Stelle zerfiel
/// ein einzelnes Bein dabei in sieben „Inseln": Ein Dreieck, das ein
/// Höhenband überspannt, hat dort gar keinen Punkt. Erst der
/// Querschnitt durch die Dreiecke ergibt eine Silhouette, die dem
/// entspricht, was der Validator sieht.
MarketplaceMeasurement measureMarketplaceFigure(
  Float32List positions,
  List<int> indices, {
  double targetStuds = marketplaceFigureStuds,
  int bands = 50,
}) {
  if (positions.length < 9 || indices.length < 3) {
    return const MarketplaceMeasurement(
      height: 0,
      width: 0,
      depth: 0,
      widthAxis: 0,
      headWidth: 0,
      neckWidth: 0,
      shoulderWidth: 0,
      legSeparation: 0,
      legWidth: 0,
      scale: 1,
    );
  }

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
  if (maxY <= minY) {
    return const MarketplaceMeasurement(
      height: 0,
      width: 0,
      depth: 0,
      widthAxis: 0,
      headWidth: 0,
      neckWidth: 0,
      shoulderWidth: 0,
      legSeparation: 0,
      legWidth: 0,
      scale: 1,
    );
  }

  final scale = targetStuds / (maxY - minY);
  final spanX = (maxX - minX) * scale;
  final spanZ = (maxZ - minZ) * scale;
  // Die Armspanne ist die größere waagerechte Achse. Gemessen, nicht
  // angenommen – siehe [MarketplaceMeasurement.widthAxis].
  final widthAxis = spanX >= spanZ ? 0 : 2;
  final achseMin = widthAxis == 0 ? minX : minZ;
  final achseSpanne = widthAxis == 0 ? maxX - minX : maxZ - minZ;

  final belegt = List<List<bool>>.generate(
      bands, (_) => List<bool>.filled(_zellen, false));
  final bandHoehe = (maxY - minY) / bands;

  for (var t = 0; t + 2 < indices.length; t += 3) {
    final ys = <double>[], us = <double>[];
    for (var e = 0; e < 3; e++) {
      final v = indices[t + e] * 3;
      if (v + 2 >= positions.length) continue;
      ys.add(positions[v + 1]);
      us.add(positions[v + (widthAxis == 0 ? 0 : 2)]);
    }
    if (ys.length < 3) continue;
    final tMin = math.min(ys[0], math.min(ys[1], ys[2]));
    final tMax = math.max(ys[0], math.max(ys[1], ys[2]));
    final vonBand =
        ((tMin - minY) / bandHoehe).floor().clamp(0, bands - 1);
    final bisBand = ((tMax - minY) / bandHoehe).ceil().clamp(0, bands);

    for (var b = vonBand; b < bisBand; b++) {
      final y0 = minY + b * bandHoehe;
      final y1 = y0 + bandHoehe;
      // Die Ausdehnung des Dreiecks in diesem Höhenband: Ecken, die
      // im Band liegen, plus die Punkte, an denen seine Kanten die
      // Bandgrenzen schneiden.
      var lo = double.infinity, hi = double.negativeInfinity;
      void nimm(double u) {
        lo = math.min(lo, u);
        hi = math.max(hi, u);
      }

      for (var e = 0; e < 3; e++) {
        if (ys[e] >= y0 && ys[e] <= y1) nimm(us[e]);
        final f = (e + 1) % 3;
        final dy = ys[f] - ys[e];
        if (dy.abs() < 1e-12) continue;
        for (final grenze in [y0, y1]) {
          final s = (grenze - ys[e]) / dy;
          if (s < 0 || s > 1) continue;
          nimm(us[e] + (us[f] - us[e]) * s);
        }
      }
      if (lo > hi) continue;
      final vonZelle = achseSpanne <= 0
          ? 0
          : (((lo - achseMin) / achseSpanne) * _zellen)
              .floor()
              .clamp(0, _zellen - 1);
      final bisZelle = achseSpanne <= 0
          ? 0
          : (((hi - achseMin) / achseSpanne) * _zellen)
              .floor()
              .clamp(0, _zellen - 1);
      for (var z = vonZelle; z <= bisZelle; z++) {
        belegt[b][z] = true;
      }
    }
  }

  final breiten = List<double>.filled(bands, 0);
  for (var b = 0; b < bands; b++) {
    var lo = -1, hi = -1;
    for (var z = 0; z < _zellen; z++) {
      if (!belegt[b][z]) continue;
      if (lo < 0) lo = z;
      hi = z;
    }
    breiten[b] =
        lo < 0 ? 0 : (hi - lo + 1) / _zellen * achseSpanne * scale;
  }

  // Kopf: das breiteste Band im obersten Fünftel.
  final kopfAb = (bands * 0.8).floor();
  var kopfBand = kopfAb;
  for (var b = kopfAb; b < bands; b++) {
    if (breiten[b] > breiten[kopfBand]) kopfBand = b;
  }
  final kopfBreite = breiten[kopfBand];

  // Schulter: von dort nach unten das erste Band, das mehr als das
  // Doppelte der Kopfbreite misst – dort setzen die Arme an. Findet
  // sich keines, gilt das breiteste Band darunter.
  var schulterBand = kopfBand;
  for (var b = kopfBand - 1; b >= 0; b--) {
    if (breiten[b] > kopfBreite * 2) {
      schulterBand = b;
      break;
    }
    if (breiten[b] > breiten[schulterBand] || schulterBand == kopfBand) {
      schulterBand = b;
    }
  }

  // Hals: das schmalste Band dazwischen.
  var halsBand = kopfBand;
  for (var b = schulterBand; b <= kopfBand; b++) {
    if (breiten[b] > 0 && breiten[b] < breiten[halsBand]) halsBand = b;
  }

  // Beine: In der unteren Zone muss der Querschnitt in zwei Inseln
  // zerfallen.
  final beinBis = (bands * marketplaceLegZone).floor();
  var getrennt = 0, gezaehlt = 0;
  var beinBreite = 0.0;
  for (var b = 0; b < beinBis; b++) {
    if (breiten[b] <= 0) continue;
    gezaehlt++;
    final inseln = _inseln(belegt[b]);
    if (inseln >= 2) getrennt++;
    // Die Breite eines einzelnen Beins: In einem Band mit zwei Inseln
    // ist es die breitere der beiden. Ein Band, in dem beide
    // zusammenhängen, sagt nichts über ein Bein aus – dort steckt
    // fast immer ein Saum.
    if (inseln >= 2) {
      beinBreite = math.max(beinBreite,
          _breitesteInsel(belegt[b]) / _zellen * achseSpanne * scale);
    }
  }

  return MarketplaceMeasurement(
    height: targetStuds,
    width: math.max(spanX, spanZ),
    depth: math.min(spanX, spanZ),
    widthAxis: widthAxis,
    headWidth: kopfBreite,
    neckWidth: breiten[halsBand],
    shoulderWidth: breiten[schulterBand],
    legSeparation: gezaehlt == 0 ? 0 : getrennt / gezaehlt,
    legWidth: beinBreite,
    scale: scale,
  );
}

/// In wie viele Zellen ein Band quer aufgeteilt wird.
///
/// 64 ist fein genug, um zwei Beine mit einem Spalt von 3 % der Breite
/// zu trennen, und grob genug, dass ein einzelner Ausreißer keine
/// dritte Insel erfindet.
const int _zellen = 64;

/// Die Zellenzahl der breitesten zusammenhängenden Insel in einem
/// Band – bei zwei Beinen also die Breite des dickeren.
int _breitesteInsel(List<bool> band) {
  final geglaettet = List<bool>.from(band);
  for (var i = 1; i < band.length - 1; i++) {
    if (!band[i] && band[i - 1] && band[i + 1]) geglaettet[i] = true;
  }
  var beste = 0, laufend = 0;
  for (final zelle in geglaettet) {
    laufend = zelle ? laufend + 1 : 0;
    if (laufend > beste) beste = laufend;
  }
  return beste;
}

/// Zählt zusammenhängende belegte Bereiche in einem Band.
///
/// Einzelne leere Zellen zwischen zwei belegten werden vorher
/// geschlossen: Bei einem groben Raster reißt sonst ein schräger
/// Rand ein Bein in zwei Inseln, und die Figur sähe getrennter aus,
/// als sie ist.
int _inseln(List<bool> band) {
  final geglaettet = List<bool>.from(band);
  for (var i = 1; i < band.length - 1; i++) {
    if (!band[i] && band[i - 1] && band[i + 1]) geglaettet[i] = true;
  }
  var zahl = 0;
  var drin = false;
  for (final zelle in geglaettet) {
    if (zelle && !drin) zahl++;
    drin = zelle;
  }
  return zahl;
}

/// Wie viel seines Hüllkörpers ein Netz aus einer Richtung ausfüllt.
///
/// Der Validator prüft das für jedes Körperteil: Ein Arm, der in
/// seinem Hüllkörper als dünner Faden liegt, wird abgelehnt – und
/// genau das passiert, wenn ein Saum den Hüllkörper aufbläht, während
/// das Bein darin dünn bleibt.
///
/// Gemessen wird als Schattenriss: Die Dreiecke werden auf die Ebene
/// aus [axisU] und [axisV] gerastert, und der Anteil der gefüllten
/// Zellen am ganzen Raster ist das Ergebnis. Die Achsen sind 0 = x,
/// 1 = y, 2 = z; „von vorn" ist also (0, 1), „von der Seite" (2, 1),
/// „von oben" (0, 2).
double silhouetteCoverage(
  Float32List positions,
  List<int> indices, {
  required int axisU,
  required int axisV,
  int grid = 48,
}) {
  if (positions.length < 9 || indices.length < 3) return 0;
  var uMin = double.infinity, uMax = double.negativeInfinity;
  var vMin = double.infinity, vMax = double.negativeInfinity;
  for (var i = 0; i + 2 < positions.length; i += 3) {
    uMin = math.min(uMin, positions[i + axisU]);
    uMax = math.max(uMax, positions[i + axisU]);
    vMin = math.min(vMin, positions[i + axisV]);
    vMax = math.max(vMax, positions[i + axisV]);
  }
  final uSpan = uMax - uMin, vSpan = vMax - vMin;
  if (uSpan <= 0 || vSpan <= 0) return 0;

  final gefuellt = List<bool>.filled(grid * grid, false);
  for (var t = 0; t + 2 < indices.length; t += 3) {
    final us = <double>[], vs = <double>[];
    for (var e = 0; e < 3; e++) {
      final v = indices[t + e] * 3;
      if (v + 2 >= positions.length) break;
      us.add((positions[v + axisU] - uMin) / uSpan * (grid - 1));
      vs.add((positions[v + axisV] - vMin) / vSpan * (grid - 1));
    }
    if (us.length < 3) continue;
    // Ein Dreieck füllen: zeilenweise zwischen den Kanten.
    final vLo = math.min(vs[0], math.min(vs[1], vs[2])).floor().clamp(0, grid - 1);
    final vHi = math.max(vs[0], math.max(vs[1], vs[2])).ceil().clamp(0, grid - 1);
    for (var row = vLo; row <= vHi; row++) {
      final y = row.toDouble();
      var lo = double.infinity, hi = double.negativeInfinity;
      for (var e = 0; e < 3; e++) {
        final f = (e + 1) % 3;
        final dy = vs[f] - vs[e];
        if (dy.abs() < 1e-9) {
          if ((vs[e] - y).abs() <= 0.5) {
            lo = math.min(lo, math.min(us[e], us[f]));
            hi = math.max(hi, math.max(us[e], us[f]));
          }
          continue;
        }
        final s = (y - vs[e]) / dy;
        if (s < 0 || s > 1) continue;
        final u = us[e] + (us[f] - us[e]) * s;
        lo = math.min(lo, u);
        hi = math.max(hi, u);
      }
      if (lo > hi) continue;
      final von = lo.floor().clamp(0, grid - 1);
      final bis = hi.ceil().clamp(0, grid - 1);
      for (var col = von; col <= bis; col++) {
        gefuellt[row * grid + col] = true;
      }
    }
  }
  var zahl = 0;
  for (final z in gefuellt) {
    if (z) zahl++;
  }
  return zahl / (grid * grid);
}

/// Vergleicht die Deckung eines Körperteils mit den Schwellen aus
/// [marketplaceCoverage].
///
/// **Was das ist und was es nicht ist.** Der Validator misst gegen den
/// **Cage** – die Hülle aus Roblox' Vorlage, die die App noch nicht
/// hat (dafür fehlen die offiziellen Cage-Vorlagen). Hier wird
/// stattdessen gegen den **eigenen Hüllquader** des Teils gemessen.
/// Das ist ein anderer Bezug und fällt milder aus: Ein Teil füllt
/// seinen eigenen Quader fast immer ordentlich, den fremden Cage nicht
/// unbedingt.
///
/// Deshalb steht das Ergebnis als **Warnung** und nie als Fehler. Es
/// fängt den groben Fall – ein Teil, das als dünner Faden in einem
/// großen Quader liegt – und nicht den feinen. Wer die Zahl des
/// Validators braucht, braucht den Cage.
List<MarketplaceFinding> checkCoverage(
    String group, Float32List positions, List<int> indices) {
  final schwellen = marketplaceCoverage[group];
  if (schwellen == null) return const [];
  final out = <MarketplaceFinding>[];
  final richtungen = [
    ('von vorn', 0, 1, schwellen.$1),
    ('von der Seite', 2, 1, schwellen.$2),
    ('von oben', 0, 2, schwellen.$3),
  ];
  for (final (label, u, v, schwelle) in richtungen) {
    if (schwelle <= 0) continue;
    final anteil =
        silhouetteCoverage(positions, indices, axisU: u, axisV: v);
    final prozent = (anteil * 100).round();
    if (prozent >= schwelle) continue;
    out.add(MarketplaceFinding(
      id: 'deckung_${group}_$u$v',
      level: MarketplaceLevel.warnung,
      title: '$group füllt $label nur $prozent % (nötig: $schwelle %)',
      reason: 'Zu wenig Deckung heißt fast immer: Etwas bläht den '
          'Hüllkörper auf, ohne selbst Volumen zu haben – bei einer '
          'Kapuzenfigur der Saum, der bis ins Bein reicht. Das lässt '
          'sich nur im Prompt beheben. Gemessen ist hier gegen den '
          'eigenen Hüllquader; der Validator misst gegen den Cage und '
          'fällt damit strenger aus.',
    ));
  }
  return out;
}

/// Beurteilt eine Messung gegen die Marktplatz-Grenzen.
List<MarketplaceFinding> checkMarketplaceFigure(MarketplaceMeasurement m) {
  final out = <MarketplaceFinding>[];
  void add(String id, MarketplaceLevel level, String title, String reason) {
    out.add(MarketplaceFinding(
        id: id, level: level, title: title, reason: reason));
  }

  if (m.height <= 0) {
    add('keine_geometrie', MarketplaceLevel.warnung, 'Nichts zu messen',
        'In der Datei stehen keine Punkte.');
    return out;
  }

  final tiefeProzent = (m.depth / m.height * 100).round();
  if (m.depth > marketplaceMaxDepth) {
    add(
        'tiefe',
        MarketplaceLevel.fehler,
        'Tiefe ${m.depth.toStringAsFixed(2)} von höchstens '
            '$marketplaceMaxDepth Studs',
        'Der Validator lehnt eine Figur ab, die tiefer ist als zwei '
            'Studs bei fünf Studs Höhe (gemessen: $tiefeProzent % der '
            'Höhe, erlaubt sind 40 %). Nachträglich flach drücken geht '
            'nicht, ohne die Figur zu verformen – das muss in den '
            'Prompt: „body depth less than two fifths of body height, '
            'flat chest and back", und „chunky" muss raus.');
  } else {
    add(
        'tiefe',
        MarketplaceLevel.ok,
        'Tiefe ${m.depth.toStringAsFixed(2)} Studs ($tiefeProzent % '
            'der Höhe)',
        '');
  }

  if (m.width < marketplaceMinArmSpan) {
    add(
        'armspanne',
        MarketplaceLevel.warnung,
        'Armspanne ${m.width.toStringAsFixed(2)} von mindestens '
            '$marketplaceMinArmSpan Studs',
        'Zu schmal gebaute Arme reißen die Mindestbreite. Gemessen '
            'wird die größere waagerechte Achse; steht die Figur in '
            'I-Pose statt A- oder T-Pose, ist die Zahl zu klein, ohne '
            'dass am Modell etwas falsch wäre.');
  } else {
    add('armspanne', MarketplaceLevel.ok,
        'Armspanne ${m.width.toStringAsFixed(2)} Studs', '');
  }

  if (!m.hasNeck) {
    add(
        'hals',
        MarketplaceLevel.fehler,
        'Kein erkennbarer Hals',
        'Zwischen Kopf (${m.headWidth.toStringAsFixed(2)}) und '
            'Schulter (${m.shoulderWidth.toStringAsFixed(2)}) liegt '
            'keine deutlich schmalere Stelle – gemessen '
            '${m.neckWidth.toStringAsFixed(2)}, das sind '
            '${(m.neckRatio * 100).round()} % statt höchstens '
            '${(marketplaceNeckRatio * 100).round()} %. Ohne '
            'Einschnürung findet Roblox\' Auto Setup die Grenze '
            'zwischen Kopf und Rumpf nicht. In den Prompt: „visible '
            'neck gap between hood and shoulders".');
  } else {
    add(
        'hals',
        MarketplaceLevel.ok,
        'Hals erkennbar (${(m.neckRatio * 100).round()} % der '
            'Kopfbreite)',
        '');
  }

  if (m.legWidth > 0) {
    if (m.legWidth > marketplaceMaxLegWidth) {
      add(
          'bein_breite',
          MarketplaceLevel.fehler,
          'Bein ${m.legWidth.toStringAsFixed(2)} breit von höchstens '
              '$marketplaceMaxLegWidth Studs',
          'Gemessen am breitesten Band unterhalb der Hüfte, geteilt '
              'durch zwei Beine. Zu breit heißt fast immer: Es ist gar '
              'nicht das Bein, sondern ein Saum, der mitgemessen wird. '
              'In den Prompt: „slim straight legs, each leg narrower '
              'than one third of the body height".');
    } else {
      add('bein_breite', MarketplaceLevel.ok,
          'Bein ${m.legWidth.toStringAsFixed(2)} Studs breit', '');
    }
  }

  final anteil = (m.legSeparation * 100).round();
  if (m.legSeparation < marketplaceLegSeparation) {
    add(
        'beine_getrennt',
        MarketplaceLevel.fehler,
        'Beine nur zu $anteil % getrennt',
        'In den unteren '
            '${(marketplaceLegZone * 100).round()} % der Höhe muss der '
            'Querschnitt in zwei getrennte Inseln zerfallen – '
            'gefordert sind '
            '${(marketplaceLegSeparation * 100).round()} % der Bänder. '
            'Was beide Beine verbindet, ist fast immer ein Saum: Er '
            'bläht den Hüllkörper des Beins auf, während das Bein '
            'darin dünn bleibt, und reißt damit Deckungsprüfung und '
            'die Regel LegsSeparated zugleich. In den Prompt: „hoodie '
            'ending at the hip bone, thighs fully uncovered, two fully '
            'separate leg tubes from the hips down".');
  } else {
    add('beine_getrennt', MarketplaceLevel.ok,
        'Beine zu $anteil % getrennt', '');
  }

  return out;
}

/// Die Befunde als Klartext.
String marketplaceAsText(List<MarketplaceFinding> findings) {
  final zeilen = <String>[
    'Marktplatz-Prüfung (gemessen am Validator, Stand '
        '$marketplaceMeasuredOn – nicht dokumentiert)',
  ];
  for (final f in findings) {
    final zeichen = switch (f.level) {
      MarketplaceLevel.fehler => '✗',
      MarketplaceLevel.warnung => '!',
      MarketplaceLevel.ok => '✔',
    };
    zeilen.add('$zeichen ${f.title}');
    if (f.reason.isNotEmpty) zeilen.add('   ${f.reason}');
  }
  return zeilen.join('\n');
}
