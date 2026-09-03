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

import 'auto_rig.dart' show estimateFrontSignal;
import 'glb_preview.dart' show splitGlb, joinGlb, readGltfFloats;

/// Das Datum, an dem diese Werte am Validator gemessen wurden.
const String marketplaceMeasuredOn = '2026-08-31';

/// Die Figurenhöhe, auf die alle Grenzen unten bezogen sind.
const double marketplaceFigureStuds = 5.0;

/// Die drei Körper-Skalen des Marktplatzes.
///
/// Die Grenzen sind **absolut in Studs**, nicht relativ zur Höhe, und
/// sie stehen in der Dokumentation (avatar/character-bodies/
/// specifications.md, Tabellen „Body scale"). Die Zahlen hier sind
/// daraus abgeschrieben, Stand 3. September 2026. Der Kopf entscheidet
/// die Skala: Classic deckelt ihn bei 1,5 Studs Breite, Slender bei 2,
/// Normal bei 3. Ein übergroßer Kopf passt nur in Normal – im Importer
/// heißt das „Rig Scale: Rthro".
enum RobloxBodyScale {
  classic,
  normal,
  slender;

  String get label => switch (this) {
        RobloxBodyScale.classic => 'Classic',
        RobloxBodyScale.normal => 'Normal (Rthro)',
        RobloxBodyScale.slender => 'Slender (Rthro Slender)',
      };

  /// Was im Importer unter „Rig Scale" zu wählen ist.
  String get rigScale => switch (this) {
        RobloxBodyScale.classic => 'R15',
        RobloxBodyScale.normal => 'Rthro',
        RobloxBodyScale.slender => 'Rthro Slender',
      };

  /// Größte Tiefe des ganzen Körpers, Studs.
  double get maxDepth => switch (this) {
        RobloxBodyScale.classic => 2.0,
        RobloxBodyScale.normal => 2.25,
        RobloxBodyScale.slender => 2.0,
      };

  /// Größte Kopfbreite, Studs.
  double get maxHeadWidth => switch (this) {
        RobloxBodyScale.classic => 1.5,
        RobloxBodyScale.normal => 3.0,
        RobloxBodyScale.slender => 2.0,
      };

  /// Größte Kopfhöhe, Studs.
  double get maxHeadHeight => switch (this) {
        RobloxBodyScale.classic => 1.8,
        RobloxBodyScale.normal => 2.0,
        RobloxBodyScale.slender => 2.0,
      };

  /// Größte Rumpfbreite, Studs.
  double get maxTorsoWidth => switch (this) {
        RobloxBodyScale.classic => 4.0,
        RobloxBodyScale.normal => 4.6,
        RobloxBodyScale.slender => 3.0,
      };

  /// Größte Gesamtbreite (Armspanne), Studs.
  double get maxTotalWidth => switch (this) {
        RobloxBodyScale.classic => 8.0,
        RobloxBodyScale.normal => 8.6,
        RobloxBodyScale.slender => 6.0,
      };

  /// Größte Gesamthöhe, Studs.
  double get maxTotalHeight => switch (this) {
        RobloxBodyScale.classic => 9.1,
        RobloxBodyScale.normal => 9.5,
        RobloxBodyScale.slender => 9.5,
      };
}

/// Mindestmaße, für alle Skalen gleich (Doku, Tabelle „Minimum").
///
/// Das sind die Zahlen, an denen die verschärfte Prüfung seit dem
/// 17. August 2026 ansetzt: Körperteile unter diesen Maßen kommen nicht
/// mehr durch. Sie sind absolut – bei 5 Studs Gesamthöhe und einem Kopf
/// von 2 Studs bleiben 3,0 für Rumpf und Beine, die brauchen aber 3,1,
/// den Hals nicht gerechnet.
const double specMinTorsoHeight = 1.7;
const double specMinTorsoWidth = 0.85;
const double specMinLegHeight = 1.4;
const double specMinLegWidth = 0.25;
const double specMinArmLength = 1.5;
const double specMinHeadSize = 0.5;
const double specMinBodyHeight = 3.6;

/// Wie viel Prozent seines Hüllkörpers jedes Teil füllen muss – laut
/// Doku 50 %, von vorn, von der Seite und von hinten, der Kopf
/// eingeschlossen.
const int specMinCoveragePercent = 50;

/// Größte Tiefe des Rumpfes (die kleinere waagerechte Achse) für
/// Classic und Slender. Normal erlaubt 2,25 – siehe
/// [RobloxBodyScale.maxDepth]. Die Grenze ist **absolut**: Dass 2,00
/// bei 5,00 Studs Höhe „40 %" ergab, war Zufall der Größe; wer die
/// Höhe ändert, darf nicht mit dem Verhältnis rechnen.
///
/// Kapuzzee: 2,45 – abgelehnt, bei jeder Skala. Der Prompt hatte
/// „chunky" bestellt.
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
const double marketplaceLegSeparation = 0.90;

/// Ab welcher Armspanne (× Höhe) die Arme waagerecht liegen.
///
/// Gemessen an drei Läufen: Kapuzzeee kam mit 5,06 bei 5,00 Höhe
/// zurück, also 1,01. Roblox' eigenes Mannequin steht in A-Pose und
/// liegt deutlich darunter.
const double marketplaceTPoseSpan = 0.95;

/// Und ab welcher Bandbreite in der oberen Hälfte.
const double marketplaceTPoseBand = 3.5;

/// Wie hoch das breiteste Band liegen muss, damit es die Schulter ist.
///
/// Die Armspanne allein reicht als Erkennungsmerkmal **nicht**, und
/// das ist kein Feinschliff, sondern ein Widerspruch: Der Marktplatz
/// verlangt mindestens [marketplaceMinArmSpan] = 6,22 Studs Spanne bei
/// 5,00 Studs Höhe, also 1,24 × Höhe. Jede zulässige Figur liegt damit
/// über den 0,95 × Höhe, ab denen die Spanne allein nach T-Pose
/// aussieht – auch eine tadellose A-Pose. Wer nur die Spanne misst,
/// meldet für jede Figur, die die Armspannen-Regel erfüllt, eine
/// T-Pose.
///
/// Der Unterschied liegt nicht in der Breite, sondern in der **Höhe**:
/// In der T-Pose ist die Figur an der Schulter am breitesten (rund
/// 77 % der Höhe), in der A-Pose an den Händen, und die hängen bei
/// 45° auf etwa 40 %. 68 % trennt beides sauber und lässt leicht
/// gesenkte Arme (rund 20°) noch durch.
const double marketplaceTPoseHeight = 0.68;

/// Wie viel Prozent seines Hüllkörpers ein Teil aus welcher Richtung
/// ausfüllen muss.
///
/// Laut Doku **50 % für jedes Teil**, von vorn, von der Seite und von
/// hinten – der Kopf eingeschlossen. Vorher standen hier die Werte aus
/// `UGCValidation/flags/` (Rumpf 50/46, Beine 30, Kopf 30, Arme gar
/// nicht): Die waren kein Ziel, sondern ein Grenzfall, den die
/// verschärfte Prüfung seit August 2026 nicht mehr durchlässt.
///
/// Reihenfolge: von vorn, von der Seite, von oben. Von oben prüft die
/// Doku nicht; die 10 % fangen nur den Faden im Quader.
const Map<String, (int, int, int)> marketplaceCoverage = {
  'DynamicHead': (specMinCoveragePercent, specMinCoveragePercent, 30),
  'Torso': (specMinCoveragePercent, specMinCoveragePercent, 10),
  'LeftArm': (specMinCoveragePercent, specMinCoveragePercent, 10),
  'RightArm': (specMinCoveragePercent, specMinCoveragePercent, 10),
  'LeftLeg': (specMinCoveragePercent, specMinCoveragePercent, 10),
  'RightLeg': (specMinCoveragePercent, specMinCoveragePercent, 10),
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
    this.origin = MarketplaceOrigin.prompt,
  });

  final String id;
  final MarketplaceLevel level;
  final String title;

  /// Wo der Befund entsteht – und damit, wer ihn beheben kann.
  final MarketplaceOrigin origin;

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
    this.spanTorsoWidth = 0,
    required this.legSeparation,
    required this.legWidth,
    this.waistWidth = 0,
    this.topBandWidth = 0,
    this.widestBandHeight = 0,
    this.headHeight = 0,
    this.torsoHeight = 0,
    this.legHeight = 0,
    this.armLength = 0,
    required this.scale,
  });

  /// Höhe des Kopfs: vom Halsband bis zum Scheitel, Studs.
  final double headHeight;

  /// Höhe des Rumpfs: vom Halsband bis zum Schritt, Studs.
  final double torsoHeight;

  /// Höhe der Beine: vom Boden bis zum Schritt, Studs.
  final double legHeight;

  /// Armlänge, **geschätzt** aus Armspanne und Rumpfbreite im
  /// breitesten Band: (Spanne − Rumpf) / 2, in A-Pose mal √2,
  /// in T-Pose unverändert. Welche der beiden Posen gilt, sagt die
  /// Messung selbst ([looksLikeTPose]) – vorher stand hier immer √2,
  /// und eine T-Pose-Figur bekam 41 % zu viel.
  ///
  /// In I-Pose (Arme am Körper) sagt die Zahl nichts: Dort steckt der
  /// Arm in der Rumpfinsel, und die Differenz wird null.
  final double armLength;

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

  /// Breite des ganzen Bandes an der Schulter – **mit** den Armen,
  /// wenn sie dort schon abstehen.
  final double shoulderWidth;

  /// Breite allein des Rumpfes **in dem Band, in dem die Spanne
  /// gemessen wird** – die Insel, die die Mitte enthält, ohne die
  /// Arme daneben. Null, wenn die Mitte dort frei ist; dann trägt
  /// nicht der Arm die Spanne, und [armLength] sagt nichts.
  ///
  /// Für die Armlänge ist das die richtige Bezugsgröße: Beides muss
  /// aus derselben Höhe kommen. Gegen [shoulderWidth] gerechnet zog
  /// sich der Arm selbst ab – an der Schulter hängt er am Rumpf und
  /// steckt in derselben Insel. Eine A-Pose-Figur mit 4,12 Spanne kam
  /// so auf 0,87 statt 1,71, und die Prüfung meldete einen zu kurzen
  /// Arm, der in Wahrheit über dem Mindestmaß lag.
  final double spanTorsoWidth;

  /// Anteil der Bänder in der Beinzone, die in zwei getrennte Inseln
  /// zerfallen (0 bis 1).
  final double legSeparation;

  /// Breite eines einzelnen Beins – die breiteste Stelle unterhalb
  /// der Hüfte, geteilt durch zwei. Null, wenn dort nichts liegt.
  final double legWidth;

  /// Das schmalste Band **unter** der Schulter und über der Beinzone.
  ///
  /// „hoodie ending at the hip bone" hat einen Bund erzeugt, der
  /// schmaler war als der Hals (0,68 gegen 0,81). Der Segmentierer
  /// setzt die Kopf-Rumpf-Grenze an die schmalste Stelle – also an die
  /// Taille, und der halbe Oberkörper wurde zum Kopf.
  final double waistWidth;

  /// Das breiteste Band in der oberen Hälfte.
  ///
  /// Waagerechte Arme auf Schulterhöhe machen daraus ein Band von
  /// über 3,5 Studs.
  final double topBandWidth;

  /// Auf welcher Höhe das breiteste Band liegt – 0 am Boden, 1 am
  /// Scheitel.
  ///
  /// Das ist die eigentliche Signatur der Pose: In der T-Pose ist die
  /// breiteste Stelle die Schulter und liegt oben, in der A-Pose sind
  /// es die Hände, und die hängen tief. Gemessen am Ergebnis, nicht am
  /// Prompt – zweimal stand der A-Pose-Text drin und die Figur kam
  /// trotzdem waagerecht zurück.
  final double widestBandHeight;

  /// Mit welchem Faktor auf [marketplaceFigureStuds] gerechnet wurde.
  final double scale;

  /// Wie schmal der Hals gegenüber Kopf und Schulter ist.
  double get neckRatio {
    final bezug = math.min(headWidth, shoulderWidth);
    return bezug <= 0 ? 1.0 : neckWidth / bezug;
  }

  bool get hasNeck => neckRatio <= marketplaceNeckRatio;

  /// Gibt es unter der Schulter eine Stelle, die schmaler ist als der
  /// Hals? Dann setzt der Segmentierer dort die Kopfgrenze.
  bool get hasWaist =>
      waistWidth > 0 && neckWidth > 0 && waistWidth < neckWidth;

  /// Steht die Figur in T-Pose?
  ///
  /// Zwei Bedingungen zusammen, weil jede für sich täuscht: Ein hoch
  /// liegendes breitestes Band allein kann ein Umhang oder ein
  /// Sonnenhut sein, und eine große Armspanne hat auch die A-Pose –
  /// sie **muss** sie sogar haben, siehe [marketplaceTPoseHeight].
  bool get looksLikeTPose =>
      height > 0 &&
      width >= height * marketplaceTPoseSpan &&
      widestBandHeight >= marketplaceTPoseHeight;
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
  // **Anderthalbfache** der Kopfbreite misst – dort setzen die Arme
  // an. Findet sich keines, gilt das breiteste Band darunter.
  //
  // Vorher stand hier das Doppelte, und das war zu streng: Eine Figur
  // mit Armen von nur 1,9 × Kopfbreite hatte danach gar keine
  // Schulter, und ohne Schulterband gibt es kein Halsband – die
  // Halsprüfung meldete für jede solche Figur „Kopfbreite gleich
  // Halsbreite" und damit 100 %.
  var schulterBand = kopfBand;
  for (var b = kopfBand - 1; b >= 0; b--) {
    if (breiten[b] > kopfBreite * 1.5) {
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

  // Taille: das schmalste Band unter der Schulter und über der
  // Beinzone. Der Segmentierer setzt die Kopf-Rumpf-Grenze an die
  // schmalste Stelle – liegt die unter der Schulter, wird der halbe
  // Oberkörper zum Kopf.
  final beinZone = (bands * marketplaceLegZone).floor();
  var taille = 0.0;
  for (var b = beinZone; b < schulterBand; b++) {
    if (breiten[b] <= 0) continue;
    if (taille <= 0 || breiten[b] < taille) taille = breiten[b];
  }

  // Das breiteste Band in der oberen Hälfte.
  var obenBreit = 0.0;
  for (var b = (bands / 2).floor(); b < bands; b++) {
    obenBreit = math.max(obenBreit, breiten[b]);
  }

  // Auf welcher Höhe die Figur am breitesten ist – die Signatur der
  // Pose. Genommen wird das **oberste** Band, das (bis auf 2 %) die
  // größte Breite erreicht: In der T-Pose ist der ganze Armbalken vom
  // Achselband bis zur Schulter gleich breit, und die Schulter oben
  // ist die aussagekräftige Kante. In der A-Pose steht ohnehin nur
  // die Hand ganz außen.
  var maxBreite = 0.0;
  for (final w in breiten) {
    maxBreite = math.max(maxBreite, w);
  }
  var breitestesBand = 0;
  for (var b = bands - 1; b >= 0; b--) {
    if (breiten[b] >= maxBreite * 0.98) {
      breitestesBand = b;
      break;
    }
  }
  final breitesteHoehe =
      bands <= 1 ? 0.0 : (breitestesBand + 0.5) / bands;

  // Der Schritt: das höchste Band unterhalb von 60 % der Höhe, in dem
  // die **Mitte frei** ist und der Querschnitt in mindestens zwei
  // Inseln zerfällt. Zwei Inseln allein reichen nicht: Hängende Arme
  // neben dem Rumpf sind auch Inseln, und dann läge der Schritt auf
  // Schulterhöhe. Zwischen zwei Beinen ist die Mitte leer. Zerfällt
  // kein Band, gilt die Beinzone als Schritt.
  var schrittBand = beinZone;
  for (var b = (bands * 0.6).floor(); b >= 0; b--) {
    if (breiten[b] > 0 && _mitteFrei(belegt[b]) && _inseln(belegt[b]) >= 2) {
      schrittBand = b + 1;
      break;
    }
  }
  final bandStuds = bandHoehe * scale;
  final beinHoehe = schrittBand * bandStuds;
  final rumpfHoehe = math.max(0, halsBand - schrittBand) * bandStuds;
  final kopfHoehe = (bands - halsBand) * bandStuds;
  // Armlänge aus Spanne und Rumpfbreite – beides aus **demselben
  // Band**, dem breitesten. An der Schulter gemessen zog sich der Arm
  // selbst ab: Dort hängt er am Rumpf und steckt in derselben Insel.
  // Im breitesten Band steht in der A-Pose die Hand frei daneben.
  final spannenRumpf =
      _mittelInsel(belegt[breitestesBand]) / _zellen * achseSpanne * scale;
  // Und mit dem Winkel, der wirklich gemessen wurde: In T-Pose ist der
  // Arm waagerecht, in A-Pose steht er 45° schräg.
  final spanne = math.max(spanX, spanZ);
  final tPose = spanne >= targetStuds * marketplaceTPoseSpan &&
      (maxBreite <= 0 ? 0.0 : breitesteHoehe) >= marketplaceTPoseHeight;
  // Ist die Mitte im breitesten Band frei, liegt die Spanne nicht an
  // den Armen (breite Füße unter dem Schritt) – dann keine Schätzung.
  final armLaenge = spannenRumpf <= 0
      ? 0.0
      : math.max(
          0.0, (spanne - spannenRumpf) / 2 * (tPose ? 1.0 : math.sqrt2));

  // Beine: In der unteren Zone muss der Querschnitt in zwei Inseln
  // zerfallen. Die Zone bleibt fest bei 45 % – wer sie am gemessenen
  // Schritt festmachte, übersähe den Saum, der den Schritt nach unten
  // drückt.
  final beinBis = beinZone;
  var getrennt = 0, gezaehlt = 0;
  var beinBreite = 0.0;
  for (var b = 0; b < beinBis; b++) {
    if (breiten[b] <= 0) continue;
    gezaehlt++;
    final inseln = _inseln(belegt[b]);
    if (inseln >= 2) getrennt++;
    // Die Breite eines einzelnen Beins: In einem Band mit freier Mitte
    // ist es die breitere der Inseln. Ein Band, in dem beide Beine
    // zusammenhängen, sagt nichts über ein Bein aus – dort steckt fast
    // immer ein Saum. Und ein Band mit belegter Mitte über dem
    // Schritt ist der Rumpf, dessen Inseln die hängenden Arme sind.
    if (inseln >= 2 && b < schrittBand && _mitteFrei(belegt[b])) {
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
    spanTorsoWidth: spannenRumpf,
    legSeparation: gezaehlt == 0 ? 0 : getrennt / gezaehlt,
    legWidth: beinBreite,
    scale: scale,
    waistWidth: taille,
    topBandWidth: obenBreit,
    widestBandHeight: maxBreite <= 0 ? 0 : breitesteHoehe,
    headHeight: kopfHoehe,
    torsoHeight: rumpfHoehe,
    legHeight: beinHoehe,
    armLength: armLaenge,
  );
}

/// Ob die Mitte eines Bands frei ist – die drei Zellen um die Achse.
///
/// Zwischen zwei Beinen ist sie leer; im Rumpf, auch mit hängenden
/// Armen daneben, ist sie belegt.
bool _mitteFrei(List<bool> band) {
  final m = band.length ~/ 2;
  for (var z = m - 1; z <= m + 1; z++) {
    if (z >= 0 && z < band.length && band[z]) return false;
  }
  return true;
}

/// Die Zellenzahl der Insel, die die **Mitte** des Bandes enthält –
/// bei einer stehenden Figur der Rumpf, ohne die Arme daneben.
///
/// Null, wenn die Mitte frei ist (unter dem Schritt).
int _mittelInsel(List<bool> band) {
  final geglaettet = List<bool>.from(band);
  for (var i = 1; i < band.length - 1; i++) {
    if (!band[i] && band[i - 1] && band[i + 1]) geglaettet[i] = true;
  }
  final m = geglaettet.length ~/ 2;
  if (!geglaettet[m]) return 0;
  var von = m, bis = m;
  while (von > 0 && geglaettet[von - 1]) {
    von--;
  }
  while (bis < geglaettet.length - 1 && geglaettet[bis + 1]) {
    bis++;
  }
  return bis - von + 1;
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
List<MarketplaceFinding> checkMarketplaceFigure(MarketplaceMeasurement m,
    {RobloxBodyScale scale = RobloxBodyScale.normal}) {
  final out = <MarketplaceFinding>[];
  void add(String id, MarketplaceLevel level, String title, String reason,
      {MarketplaceOrigin origin = MarketplaceOrigin.prompt}) {
    out.add(MarketplaceFinding(
        id: id,
        level: level,
        title: title,
        reason: reason,
        origin: origin));
  }

  if (m.height <= 0) {
    add('keine_geometrie', MarketplaceLevel.warnung, 'Nichts zu messen',
        'In der Datei stehen keine Punkte.');
    return out;
  }

  final tiefeProzent = (m.depth / m.height * 100).round();
  final maxTiefe = scale.maxDepth;
  if (m.depth > maxTiefe) {
    add(
        'tiefe',
        MarketplaceLevel.fehler,
        'Tiefe ${m.depth.toStringAsFixed(2)} von höchstens '
            '${maxTiefe.toStringAsFixed(2)} Studs (${scale.label})',
        'Die Grenze ist absolut: ${maxTiefe.toStringAsFixed(2)} Studs '
            'bei ${scale.label}, egal wie hoch die Figur ist – bei '
            '${m.height.toStringAsFixed(2)} Studs Höhe sind das '
            '${(maxTiefe / m.height * 100).round()} %, gemessen '
            '$tiefeProzent %. Nachträglich flach drücken geht nur im '
            'Reparatur-Modus, und der verformt; besser in den Prompt: '
            '„flat chest and back", und „chunky" muss raus.');
  } else {
    add(
        'tiefe',
        MarketplaceLevel.ok,
        'Tiefe ${m.depth.toStringAsFixed(2)} Studs ($tiefeProzent % '
            'der Höhe, erlaubt ${maxTiefe.toStringAsFixed(2)} bei '
            '${scale.label})',
        '');
  }

  // Der Kopf entscheidet die Skala – und die Höhenrechnung.
  if (m.headWidth > scale.maxHeadWidth) {
    final passt = RobloxBodyScale.values
        .where((v) => v.maxHeadWidth >= m.headWidth)
        .toList();
    add(
        'kopf_breite',
        MarketplaceLevel.fehler,
        'Kopf ${m.headWidth.toStringAsFixed(2)} breit von höchstens '
            '${scale.maxHeadWidth.toStringAsFixed(1)} Studs (${scale.label})',
        'Classic deckelt den Kopf bei 1,5 Studs, Slender bei 2, Normal '
            'bei 3. '
            '${passt.isEmpty ? 'Für diese Breite gibt es keine Skala – der '
                'Kopf muss kleiner werden.' : 'Passend wäre die Skala '
                '${passt.first.label}: im Importer „Rig Scale: '
                '${passt.first.rigScale}".'}');
  } else {
    add(
        'kopf_breite',
        MarketplaceLevel.ok,
        'Kopf ${m.headWidth.toStringAsFixed(2)} Studs breit (erlaubt '
            '${scale.maxHeadWidth.toStringAsFixed(1)} bei ${scale.label}, '
            'Rig Scale ${scale.rigScale})',
        '');
  }

  // Mindestmaße sind absolut. Bei einem übergroßen Kopf reicht die
  // Höhe für Rumpf und Beine nicht mehr.
  if (m.torsoHeight > 0 && m.torsoHeight < specMinTorsoHeight) {
    add(
        'rumpf_hoehe',
        MarketplaceLevel.fehler,
        'Rumpf ${m.torsoHeight.toStringAsFixed(2)} hoch von mindestens '
            '$specMinTorsoHeight Studs',
        'Vom Halsband bis zum Schritt gemessen. Die Mindesthöhen sind '
            'absolut (Rumpf $specMinTorsoHeight, Bein $specMinLegHeight, '
            'Arm $specMinArmLength) und seit dem 17. August 2026 wird '
            'darauf geprüft. Entweder der Kopf wird kleiner (etwa ein '
            'Viertel der Höhe), oder die Figur bekommt mehr Studs – bei '
            '6 statt 5 reicht es auch mit großem Kopf.');
  }
  if (m.legHeight > 0 && m.legHeight < specMinLegHeight) {
    add(
        'bein_hoehe',
        MarketplaceLevel.fehler,
        'Beine ${m.legHeight.toStringAsFixed(2)} hoch von mindestens '
            '$specMinLegHeight Studs',
        'Vom Boden bis zum Schritt gemessen – dem höchsten Band, in dem '
            'der Querschnitt noch in zwei Beine zerfällt. Zu kurze '
            'Beine heißt: zu viel Kopf, ein Saum, der den Schritt nach '
            'unten drückt – oder ein Rumpf, der zu weit hinunter '
            'reicht. Die Beine sind, was unter der Hüfte übrig bleibt: '
            'Eine Länge zu bestellen half nicht („a third of body '
            'height" gab 1,0), eine Linie schon. Ins Motiv „hips at '
            'mid body height, two separate legs with a clear gap '
            'between the thighs", ins Negativ „short legs".');
  }
  if (m.headHeight > 0 && m.torsoHeight > 0) {
    final rest = m.height - m.headHeight;
    final noetig = specMinTorsoHeight + specMinLegHeight;
    if (rest < noetig) {
      add(
          'hoehenrechnung',
          MarketplaceLevel.fehler,
          'Kopf ${m.headHeight.toStringAsFixed(2)} hoch: unter ihm '
              'bleiben ${rest.toStringAsFixed(2)} Studs, Rumpf und '
              'Beine brauchen ${noetig.toStringAsFixed(1)}',
          'Die Mindesthöhen sind absolut, nicht relativ. Zwei Wege: '
              'Kopf auf rund ein Viertel der Höhe, oder Gesamthöhe auf '
              '${(m.headHeight + noetig + 0.3).ceil()} Studs – dann '
              'bleibt unter dem Kopf genug, den Hals eingerechnet.');
    }
  }
  if (m.armLength > 0 && m.armLength < specMinArmLength) {
    add(
        'arm_laenge',
        MarketplaceLevel.warnung,
        'Arm etwa ${m.armLength.toStringAsFixed(2)} lang von mindestens '
            '$specMinArmLength Studs',
        'Geschätzt aus der Spanne (${m.width.toStringAsFixed(2)}) und '
            'dem Rumpf daneben '
            '(${m.spanTorsoWidth.toStringAsFixed(2)}), '
            '${m.looksLikeTPose ? 'waagerecht gerechnet (T-Pose)' : 'für '
                '45° zurückgerechnet (A-Pose)'}. In I-Pose steckt der '
            'Arm in der Rumpfinsel; dann sagt die Zahl nichts. Ins '
            'Motiv: „long arms reaching mid thigh".');
  }

  // Die 6,22 stammen aus einem T-Pose-Lauf. Der Marktplatz-Schwanz
  // bestellt aber eine A-Pose, und dort ist dieselbe Armlänge um
  // cos 45° schmaler – die Schwelle unverändert anzulegen, meldete
  // jede A-Pose-Figur als zu schmal. Umgerechnet wird über den
  // gemessenen Rumpf an der Schulter: Was an ihm hängt, klappt um 45°
  // ein, der Rumpf selbst nicht.
  final spannenGrenze = m.looksLikeTPose || m.spanTorsoWidth <= 0
      ? marketplaceMinArmSpan
      : m.spanTorsoWidth +
          (marketplaceMinArmSpan - m.spanTorsoWidth) / math.sqrt2;
  if (m.width < spannenGrenze) {
    add(
        'armspanne',
        MarketplaceLevel.warnung,
        'Armspanne ${m.width.toStringAsFixed(2)} von mindestens '
            '${spannenGrenze.toStringAsFixed(2)} Studs'
            '${m.looksLikeTPose ? '' : ' (A-Pose; in T-Pose wären es '
                '$marketplaceMinArmSpan)'}',
        'Die Doku nennt keine Mindestspanne, nur Mindestmaße je Teil '
            '(Arm $specMinArmLength lang); die $marketplaceMinArmSpan '
            'stammen aus einem echten Validator-Lauf in T-Pose und '
            'stehen hier als Sicherheitsaufschlag. Der '
            'Marktplatz-Schwanz bestellt eine A-Pose, und dort ist '
            'dieselbe Armlänge um cos 45° schmaler – deshalb wird die '
            'Schwelle über den Rumpf im breitesten Band '
            '(${m.spanTorsoWidth.toStringAsFixed(2)}) umgerechnet. '
            'Gemessen wird die größere waagerechte Achse; steht die '
            'Figur in I-Pose, ist die Zahl zu klein, ohne dass am '
            'Modell etwas falsch wäre.',
        origin: MarketplaceOrigin.export);
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
            'zwischen Kopf und Rumpf nicht. In den Prompt: „narrow '
            'visible neck not merged with the shoulders" – bei der ersten '
            'Figur mit dem Marktplatz-Schwanz war es der Pulloverkragen, '
            'der den Hals auf 55 % brachte.');
  } else {
    add(
        'hals',
        MarketplaceLevel.ok,
        'Hals erkennbar (${(m.neckRatio * 100).round()} % der '
            'Kopfbreite)',
        '');
  }

  // Taille: Der Segmentierer setzt die Kopf-Rumpf-Grenze an die
  // schmalste Stelle. Liegt die unter der Schulter, wird der halbe
  // Oberkörper zum Kopf – bei Kapuzzeee kam ein „Head" von 3,16 Studen
  // Breite heraus.
  if (m.hasWaist) {
    add(
        'taille',
        MarketplaceLevel.fehler,
        'Taille schmaler als der Hals '
            '(${m.waistWidth.toStringAsFixed(2)} gegen '
            '${m.neckWidth.toStringAsFixed(2)})',
        'Auto Setup sucht die Kopf-Rumpf-Grenze an der schmalsten '
            'Stelle. Ist die Taille schmaler als der Hals, liegt die '
            'Grenze dort, und der halbe Oberkörper wird zum Kopf. Der '
            'Bund kommt meist von „hoodie ending at the hip bone". In '
            'den Prompt: „straight boxy hoodie without a cinched '
            'waist".');
  }

  // Pose am Ergebnis, nicht am Prompt. Zweimal ist der A-Pose-Text im
  // Prompt gelandet und die Figur kam trotzdem waagerecht zurück.
  if (m.looksLikeTPose) {
    add(
        'pose',
        MarketplaceLevel.fehler,
        'T-Pose gemessen (breiteste Stelle auf '
            '${(m.widestBandHeight * 100).round()} % der Höhe, '
            'Armspanne ${m.width.toStringAsFixed(2)})',
        'Waagerechte Arme auf Schulterhöhe schlägt der Segmentierer '
            'dem Kopf und dem Rumpf zu; zweimal wurden daraus ein '
            '„Head" von über 3 Studen Breite und Arme, die zu Beinen '
            'wurden. Der Prompt allein hat das nicht verhindert – der '
            'A-Pose-Text stand drin, Tripo hat ihn übergangen. Neu '
            'erzeugen oder die Arme im Reparatur-Modus um 45° drehen.');
  }

  if (m.legWidth > 0) {
    if (m.legWidth > marketplaceMaxLegWidth) {
      add(
          'bein_breite',
          MarketplaceLevel.fehler,
          'Bein ${m.legWidth.toStringAsFixed(2)} breit von höchstens '
              '$marketplaceMaxLegWidth Studs',
          'Gemessen am breitesten Band unterhalb des Schritts, das '
              'breitere der beiden Beine. Zu breit heißt fast immer: '
              'Es ist gar nicht das Bein, sondern ein Saum, der '
              'mitgemessen wird. Nicht „slim legs" bestellen – zu dünne '
              'Beine füllen ihren Hüllkörper nicht zu 50 %. In den '
              'Prompt: „two separate legs with a gap between the '
              'thighs".');
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
            'die Regel LegsSeparated zugleich – genauer: Das Netz ragt '
            'aus dem Outer Cage des Beins heraus, den Auto Setup um '
            'das Bein legt. Liegt der Schritt dazu tief (Bein unter '
            '1,4 Studs), ist es kein Saum, sondern ein Rumpf bis kurz '
            'über den Boden – bei der ersten Figur mit dem '
            'Marktplatz-Schwanz waren es „small stocky … sturdy legs". '
            'In den Prompt: „hips at mid body height, two separate legs '
            'with a gap between the thighs, opaque clothing covering '
            'upper and lower torso", ins Negativ „short legs". Nackte '
            'Oberschenkel '
            'sind keine Lösung: Der Marktplatz verlangt eine Bedeckung '
            'von der Hüfte bis unter Schritt und Gesäß.');
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
    zeilen.add('$zeichen [${f.origin.label}] ${f.title}');
    if (f.reason.isNotEmpty) zeilen.add('   ${f.reason}');
  }
  return zeilen.join('\n');
}

/// Ab welchem Signal die Blickrichtung als bestimmt gilt.
///
/// [estimateFrontSignal] misst, wie weit die Zehen über das Schienbein
/// hinausragen, bezogen auf die Modelltiefe. Unter diesem Wert ist die
/// Figur vorn wie hinten zu ähnlich – dann wird **nicht** gedreht,
/// sondern gesagt, dass es nicht bestimmbar war.
const double marketplaceFrontThreshold = 0.02;

/// Ob ein Befund beim **Prompt** oder beim **Export** entsteht.
///
/// Der Unterschied entscheidet, was zu tun ist: Ein Formfehler lässt
/// sich nicht wegrechnen – da muss der nächste Lauf einen anderen
/// Prompt bekommen. Ein Exportfehler dagegen ist Sache der App.
/// Deshalb steht er in jeder Meldung.
enum MarketplaceOrigin {
  /// Entsteht beim Prompt. Nachträglich nicht zu beheben.
  prompt,

  /// Entsteht beim Export. Die App bringt es in Ordnung.
  export,
}

extension MarketplaceOriginLabel on MarketplaceOrigin {
  String get label => switch (this) {
        MarketplaceOrigin.prompt => 'Prompt',
        MarketplaceOrigin.export => 'Export',
      };
}

/// Was die Vorbereitung für Auto Setup getan hat.
class AutoSetupPrepReport {
  const AutoSetupPrepReport({
    required this.steps,
    required this.scale,
    required this.turnedDegrees,
    required this.shift,
    this.colorsRemoved = 0,
    this.bonesRemoved = 0,
  });

  final List<String> steps;
  final double scale;
  final int turnedDegrees;
  final List<double> shift;

  /// Wie viele Vertexfarben-Spuren entfernt wurden.
  final int colorsRemoved;

  /// Wie viele Knochen entfernt wurden – Auto Setup baut sein eigenes
  /// Rig.
  final int bonesRemoved;

  bool get changed =>
      (scale - 1).abs() > 1e-6 ||
      turnedDegrees != 0 ||
      shift.any((v) => v.abs() > 1e-6) ||
      colorsRemoved > 0 ||
      bonesRemoved > 0;

  String get text => ['Für Auto Setup vorbereitet', ...steps].join('\n');
}

class AutoSetupPrepResult {
  const AutoSetupPrepResult(this.glb, this.report);
  final Uint8List glb;
  final AutoSetupPrepReport report;
}

/// Bringt ein **ungeriggtes** Netz in die Lage, die Roblox' Auto Setup
/// erwartet: [targetStuds] hoch, Zehen in der Datei nach +Z, Nullpunkt
/// mittig unter der Figur.
///
/// Warum eigens und nicht über `prepareRigForRoblox`: Das dort ist an
/// ein Skelett gebunden – es liest die Gelenke, um Vorn und Hüfte zu
/// bestimmen. Auf dem Marktplatz-Weg gibt es keines, und genau das ist
/// richtig so: Auto Setup baut sein eigenes Rig und verwirft ein
/// mitgebrachtes.
///
/// Beides muss trotzdem stimmen, und beides kam bei einem echten Lauf
/// falsch aus dem Anbieter: die Figur **1,00 Einheiten hoch** statt 5
/// (auch mit Tripos `auto_size`), und mit der **Armspanne auf Z** statt
/// auf X, also der Front auf X. Aus der Geometrie ist beides
/// bestimmbar – die Armspanne ist die größere waagerechte Achse, und
/// wohin die Figur schaut, verraten die Zehen.
///
/// **Die Zehen zeigen in der Datei nach +Z.** Das klingt verkehrt –
/// Roblox verlangt die Front auf −Z –, ist aber gemessen: Studios
/// glTF-Import spiegelt die Z-Achse, was in der GLB auf −Z liegt,
/// kommt in Studio auf +Z heraus. Zwei Auto-Setup-Läufe standen
/// rückwärts, weil die Vorbereitung der Dokumentation gefolgt ist
/// statt der Messung (Übergabe 02.09.2026). Nachprüfen lässt es sich
/// nur in Studio: EditableMesh laden, mittleres Z der untersten 8 %
/// (Zehen) minus mittleres Z bei 15–25 % (Schienbein) muss negativ
/// sein.
AutoSetupPrepResult prepareForAutoSetup(
  Uint8List glb, {
  double targetStuds = marketplaceFigureStuds,
}) {
  final parts = splitGlb(glb);
  final json = parts.json;
  final bin = Uint8List.fromList(parts.bin);
  final steps = <String>[];

  // 0. Ein mitgebrachtes Skelett fällt weg.
  //
  // Vorher stand hier eine Absage („bei Tripo ohne Rigging erzeugen").
  // Die war richtig gemeint und in der Sache falsch: Sie ließ den
  // Marktplatz-Weg für jede vorhandene geriggte Figur ins Leere
  // laufen, obwohl die Datei sich in zwei Handgriffen brauchbar machen
  // lässt. Auto Setup verwirft das Skelett ohnehin.
  final skelett = stripRigForAutoSetup(json);
  steps.addAll(skelett.notes);

  // 1. Ausrichtung. Erst so drehen, dass die Armspanne auf x liegt –
  // danach greift die vorhandene Zehen-Heuristik, die entlang z misst.
  final positionen = _positionAccessors(json);
  var alle = <Float32List>[
    for (final index in positionen) readGltfFloats(json, bin, index),
  ];
  var (minX, maxX, minY, maxY, minZ, maxZ) = _spanne(alle);
  var turned = (maxX - minX) >= (maxZ - minZ) ? 0 : 90;
  if (turned != 0) {
    alle = [for (final p in alle) _dreheUmY(p, turned)];
    steps.add('Um 90° gedreht: Die Armspanne lag auf z statt auf x.');
  }
  // Jetzt sagt das Signal, wohin die Figur schaut.
  //
  // **Die Zehen müssen in der Datei nach +Z zeigen.** Das steht so in
  // keiner Dokumentation und klingt verkehrt herum – Roblox verlangt
  // die Front auf −Z. Studios glTF-Import spiegelt aber die Z-Achse:
  // Was in der GLB auf −Z liegt, kommt in Studio auf +Z heraus. Zwei
  // Auto-Setup-Läufe sind mit einer rückwärts stehenden Figur
  // gelaufen, weil die Vorbereitung der Doku gefolgt ist statt der
  // Messung (Übergabe 02.09.2026).
  //
  // Nachprüfen lässt es sich nur in Studio: EditableMesh laden,
  // mittleres Z der untersten 8 % (Zehen) minus mittleres Z bei 15–25 %
  // (Schienbein) muss **negativ** sein.
  //
  // Gedreht wird nur bei einem **eindeutigen** Signal. Bei einer vorn
  // wie hinten gleichen Figur weiß niemand, wo vorn ist – dort würde
  // ein zweiter Durchlauf sonst erneut drehen, und das Ergebnis hinge
  // davon ab, wie oft man den Knopf gedrückt hat.
  final signal = estimateFrontSignal(alle);
  if (signal < -marketplaceFrontThreshold) {
    turned = (turned + 180) % 360;
    alle = [for (final p in alle) _dreheUmY(p, 180)];
    steps.add('Um 180° gedreht: Die Zehen zeigten in der Datei nach −Z. '
        'Studios glTF-Import spiegelt Z – für eine Front auf −Z in '
        'Studio müssen sie in der GLB nach +Z zeigen.');
  } else if (signal.abs() <= marketplaceFrontThreshold) {
    steps.add('Blickrichtung nicht bestimmbar (Signal '
        '${signal.toStringAsFixed(3)}): Die Figur ist von vorn und '
        'hinten zu ähnlich. Nichts gedreht – im Viewer prüfen und '
        'notfalls mit den 90°-Knöpfen nachhelfen.');
  }

  // 2. Maßstab.
  (minX, maxX, minY, maxY, minZ, maxZ) = _spanne(alle);
  final hoehe = maxY - minY;
  var scale = 1.0;
  if (hoehe > 1e-6 && (hoehe - targetStuds).abs() > 1e-4) {
    scale = targetStuds / hoehe;
    steps.add('Auf ${targetStuds.toStringAsFixed(0)} Studs gebracht '
        '(Faktor ${scale.toStringAsFixed(3)}) – der Validator misst '
        'alle Grenzen bei dieser Höhe, und der Anbieter lieferte '
        '${hoehe.toStringAsFixed(2)}.');
  }

  // 3. Nullpunkt mittig unter die Figur.
  final shift = [
    -(minX + maxX) / 2 * scale,
    -minY * scale,
    -(minZ + maxZ) / 2 * scale,
  ];
  if (shift.any((v) => v.abs() > 1e-4)) {
    steps.add('Nullpunkt mittig unter die Figur gelegt.');
  }

  // Alles in einem Durchgang in die Punkte rechnen.
  for (var i = 0; i < positionen.length; i++) {
    final werte = _dreheUmY(
        readGltfFloats(json, bin, positionen[i]), turned);
    for (var k = 0; k + 2 < werte.length; k += 3) {
      werte[k] = werte[k] * scale + shift[0];
      werte[k + 1] = werte[k + 1] * scale + shift[1];
      werte[k + 2] = werte[k + 2] * scale + shift[2];
    }
    _schreibeFloats(json, bin, positionen[i], werte);
  }
  // Normalen nur drehen: Skalierung und Verschiebung ändern ihre
  // Richtung nicht.
  if (turned != 0) {
    for (final index in _normalAccessors(json)) {
      _schreibeFloats(json, bin, index,
          _dreheUmY(readGltfFloats(json, bin, index), turned));
    }
  }

  // 4. Vertexfarben raus.
  //
  // Roblox erwartet an einem Marktplatz-Körper VertexColor 1,1,1.
  // Eine COLOR_0-Spur färbt das Netz zusätzlich ein, und die Farbe
  // steckt dann doppelt drin: einmal in der Textur, einmal in den
  // Punkten. Beim Hochladen sieht die Figur anders aus als in der
  // Vorschau, und niemand findet den Grund.
  var farbenWeg = 0;
  for (final mesh in (json['meshes'] as List?) ?? const []) {
    for (final prim in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final attribute = (prim as Map)['attributes'] as Map?;
      if (attribute == null) continue;
      final weg = [
        for (final key in attribute.keys)
          if (key is String && key.startsWith('COLOR_')) key,
      ];
      for (final key in weg) {
        attribute.remove(key);
        farbenWeg++;
      }
    }
  }
  if (farbenWeg > 0) {
    steps.add('$farbenWeg Vertexfarben-Spur(en) entfernt – Roblox '
        'erwartet VertexColor 1,1,1, sonst färbt sich die Figur '
        'doppelt ein.');
  }

  if (steps.isEmpty) steps.add('Lag schon richtig – nichts geändert.');
  return AutoSetupPrepResult(
    joinGlb(json, bin),
    AutoSetupPrepReport(
      steps: steps,
      scale: scale,
      turnedDegrees: turned,
      shift: shift,
      colorsRemoved: farbenWeg,
      bonesRemoved: skelett.bones,
    ),
  );
}

/// Dreht Punkte um die Hochachse in 90°-Schritten – ohne Sinus und
/// Kosinus, damit keine Rundungsfehler entstehen.
Float32List _dreheUmY(Float32List werte, int grad) {
  if (grad % 360 == 0) return werte;
  final out = Float32List(werte.length);
  for (var i = 0; i + 2 < werte.length; i += 3) {
    final x = werte[i], y = werte[i + 1], z = werte[i + 2];
    switch (((grad % 360) + 360) % 360) {
      case 90:
        out[i] = -z;
        out[i + 1] = y;
        out[i + 2] = x;
      case 180:
        out[i] = -x;
        out[i + 1] = y;
        out[i + 2] = -z;
      case 270:
        out[i] = z;
        out[i + 1] = y;
        out[i + 2] = -x;
      default:
        out[i] = x;
        out[i + 1] = y;
        out[i + 2] = z;
    }
  }
  return out;
}

(double, double, double, double, double, double) _spanne(
    List<Float32List> listen) {
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (final p in listen) {
    for (var i = 0; i + 2 < p.length; i += 3) {
      minX = math.min(minX, p[i]);
      maxX = math.max(maxX, p[i]);
      minY = math.min(minY, p[i + 1]);
      maxY = math.max(maxY, p[i + 1]);
      minZ = math.min(minZ, p[i + 2]);
      maxZ = math.max(maxZ, p[i + 2]);
    }
  }
  return (minX, maxX, minY, maxY, minZ, maxZ);
}

List<int> _positionAccessors(Map<String, dynamic> json) =>
    _attributAccessors(json, 'POSITION');

List<int> _normalAccessors(Map<String, dynamic> json) =>
    _attributAccessors(json, 'NORMAL');

List<int> _attributAccessors(Map<String, dynamic> json, String name) {
  final out = <int>{};
  for (final mesh in (json['meshes'] as List?) ?? const []) {
    for (final prim in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final index = ((prim as Map)['attributes'] as Map?)?[name] as num?;
      if (index != null) out.add(index.toInt());
    }
  }
  return out.toList();
}

/// Schreibt einen VEC3-Kommazahlen-Accessor an derselben Stelle
/// zurück und zieht min/max nach.
void _schreibeFloats(Map<String, dynamic> json, Uint8List bin, int index,
    Float32List werte) {
  final accessor = (json['accessors'] as List)[index] as Map<String, dynamic>;
  if (accessor['componentType'] != 5126 || accessor['type'] != 'VEC3') {
    return;
  }
  final viewIndex = (accessor['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return;
  final view =
      (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final stride = (view['byteStride'] as num?)?.toInt() ?? 12;
  final data = ByteData.sublistView(bin);
  final count = (accessor['count'] as num).toInt();
  for (var i = 0; i < count && i * 3 + 2 < werte.length; i++) {
    for (var k = 0; k < 3; k++) {
      data.setFloat32(
          start + i * stride + k * 4, werte[i * 3 + k], Endian.little);
    }
  }
  if (accessor.containsKey('min') || accessor.containsKey('max')) {
    final lo = [double.infinity, double.infinity, double.infinity];
    final hi = [
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity
    ];
    for (var i = 0; i + 2 < werte.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        lo[k] = math.min(lo[k], werte[i + k]);
        hi[k] = math.max(hi[k], werte[i + k]);
      }
    }
    accessor['min'] = lo;
    accessor['max'] = hi;
  }
}

/// Was beim Entfernen des Skeletts weggefallen ist.
class RigStripReport {
  const RigStripReport({
    required this.bones,
    required this.animations,
    required this.meshes,
    required this.notes,
  });

  /// Entfernte Knochenknoten.
  final int bones;

  /// Entfernte Animationen – ihre Spuren zeigten auf die Knochen.
  final int animations;

  /// Netze, die ihre Gewichte verloren haben.
  final int meshes;

  final List<String> notes;

  bool get didSomething => bones > 0 || meshes > 0 || animations > 0;
}

/// Nimmt einer Datei Skelett und Gewichte – für Auto Setup.
///
/// **Warum das richtig ist.** Roblox' Auto Setup zerlegt das rohe Netz
/// selbst, baut sein eigenes R15-Rig, die Cages und die Attachments.
/// Ein mitgebrachtes Skelett verwirft es. Es bleibt also im besten Fall
/// wirkungslos, kostet Dateigröße, und im schlechteren Fall macht es
/// die Datei mehrdeutig: Der Importer sieht ein geriggtes Modell, wo
/// ein Netz erwartet wird.
///
/// **Warum sich dabei nichts bewegt.** Bei einem Netz in Bindepose
/// sind die Punkte in der Datei genau die Punkte, die man sieht: Die
/// Skinning-Matrix ist Gelenk-Weltmatrix × inverse Bindematrix, und in
/// der Bindepose ist das die Einheitsmatrix. Fällt das Skelett weg,
/// bleibt die Geometrie also stehen — **wenn** zwei Dinge stimmen, und
/// um die kümmert sich diese Funktion:
///
/// * Die glTF-Regel „bei einem geskinnten Netz wird die Transformation
///   des Knotens **und seiner Eltern** ignoriert". Fällt das Skelett
///   weg, gilt sie nicht mehr, und eine Elterntransformation würde die
///   Figur auf einmal verschieben. Das Netz hängt danach deshalb
///   direkt in der Szene, mit Einheitsmatrix.
/// * Die Gelenke stehen in der Bindepose. Steht die Figur in der Datei
///   in einer anderen Haltung als in den Bindematrizen, wäre das
///   Ergebnis eine andere Haltung – das steht als Hinweis im Bericht,
///   messen lässt es sich hier nicht.
///
/// Übrig bleiben ungenutzte Accessoren (die Bindematrizen). Sie stören
/// keinen Importer; die Datei wird davon nicht kleiner.
RigStripReport stripRigForAutoSetup(Map<String, dynamic> json) {
  final skins = (json['skins'] as List?) ?? const [];
  final nodes = (json['nodes'] as List?) ?? const [];
  final notes = <String>[];
  if (skins.isEmpty || nodes.isEmpty) {
    return const RigStripReport(
        bones: 0, animations: 0, meshes: 0, notes: []);
  }

  // 1. Wer ist Gelenk?
  final gelenke = <int>{};
  for (final skin in skins) {
    for (final j in ((skin as Map)['joints'] as List?) ?? const []) {
      gelenke.add((j as num).toInt());
    }
    final wurzel = (skin['skeleton'] as num?)?.toInt();
    if (wurzel != null) gelenke.add(wurzel);
  }

  // 2. Die geskinnten Netze lösen: kein Skin, keine Gewichte, keine
  // geerbte Transformation.
  var netze = 0;
  final losgeloest = <int>[];
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i] as Map<String, dynamic>;
    if (!node.containsKey('skin')) continue;
    node.remove('skin');
    for (final key in ['matrix', 'translation', 'rotation', 'scale']) {
      node.remove(key);
    }
    losgeloest.add(i);
    final mesh = (node['mesh'] as num?)?.toInt();
    if (mesh == null) continue;
    final meshes = (json['meshes'] as List?) ?? const [];
    if (mesh >= meshes.length) continue;
    var beruehrt = false;
    for (final prim
        in ((meshes[mesh] as Map)['primitives'] as List?) ?? const []) {
      final attribute = (prim as Map)['attributes'] as Map?;
      if (attribute == null) continue;
      final weg = [
        for (final key in attribute.keys)
          if (key is String &&
              (key.startsWith('JOINTS_') || key.startsWith('WEIGHTS_')))
            key,
      ];
      for (final key in weg) {
        attribute.remove(key);
        beruehrt = true;
      }
    }
    if (beruehrt) netze++;
  }

  // 3. Skelett und Animationen weg. Die Animationsspuren zeigen auf
  // die Gelenke; ohne sie wäre die Datei ungültig.
  json.remove('skins');
  final anim = ((json['animations'] as List?) ?? const []).length;
  if (anim > 0) json.remove('animations');

  // 4. Knochenknoten aus dem Baum nehmen – aber nur solche, an denen
  // keine Geometrie hängt. Ein Knochen mit einem Netz darunter (etwa
  // ein Gegenstand in der Hand) bleibt samt seiner Transformation
  // stehen; ihn zu entfernen würde das Netz verschieben.
  final behalten = List<bool>.filled(nodes.length, false);
  void markiere(int index) {
    if (index < 0 || index >= nodes.length || behalten[index]) return;
    behalten[index] = true;
    final node = nodes[index] as Map<String, dynamic>;
    for (final c in (node['children'] as List?) ?? const []) {
      markiere((c as num).toInt());
    }
  }

  bool hatGeometrie(int index, Set<int> gesehen) {
    if (!gesehen.add(index)) return false;
    final node = nodes[index] as Map<String, dynamic>;
    if (node.containsKey('mesh') || node.containsKey('camera')) return true;
    for (final c in (node['children'] as List?) ?? const []) {
      if (hatGeometrie((c as num).toInt(), gesehen)) return true;
    }
    return false;
  }

  for (var i = 0; i < nodes.length; i++) {
    if (gelenke.contains(i) && !hatGeometrie(i, <int>{})) continue;
    behalten[i] = true;
  }
  // Kinder eines behaltenen Knotens bleiben ebenfalls – sonst reißt der
  // Baum. (Ein Gelenk unter einem Netzknoten kommt vor.)
  for (var i = 0; i < nodes.length; i++) {
    if (behalten[i] && !gelenke.contains(i)) markiere(i);
  }

  final knochen = behalten.where((b) => !b).length;

  // 5. Neu durchnummerieren.
  final neuerIndex = List<int>.filled(nodes.length, -1);
  final neueNodes = <dynamic>[];
  for (var i = 0; i < nodes.length; i++) {
    if (!behalten[i]) continue;
    neuerIndex[i] = neueNodes.length;
    neueNodes.add(nodes[i]);
  }
  for (final node in neueNodes) {
    final kinder = (node as Map<String, dynamic>)['children'] as List?;
    if (kinder == null) continue;
    final neu = [
      for (final c in kinder)
        if (neuerIndex[(c as num).toInt()] >= 0) neuerIndex[c.toInt()],
    ];
    if (neu.isEmpty) {
      node.remove('children');
    } else {
      node['children'] = neu;
    }
  }
  json['nodes'] = neueNodes;

  // 6. Die gelösten Netze hängen jetzt direkt in der Szene – und sonst
  // nirgends mehr.
  for (final scene in (json['scenes'] as List?) ?? const []) {
    final map = scene as Map<String, dynamic>;
    final wurzeln = <int>{
      for (final n in (map['nodes'] as List?) ?? const [])
        if (neuerIndex[(n as num).toInt()] >= 0) neuerIndex[n.toInt()],
    };
    for (final alt in losgeloest) {
      if (neuerIndex[alt] >= 0) wurzeln.add(neuerIndex[alt]);
    }
    map['nodes'] = wurzeln.toList()..sort();
  }
  // Ein gelöstes Netz darf nicht zusätzlich Kind eines anderen Knotens
  // bleiben – es käme sonst zweimal vor, einmal mit fremder
  // Transformation.
  final geloest = {
    for (final alt in losgeloest)
      if (neuerIndex[alt] >= 0) neuerIndex[alt],
  };
  for (final node in neueNodes) {
    final kinder = (node as Map<String, dynamic>)['children'] as List?;
    if (kinder == null) continue;
    final neu = [
      for (final c in kinder)
        if (!geloest.contains((c as num).toInt())) c,
    ];
    if (neu.length == kinder.length) continue;
    if (neu.isEmpty) {
      node.remove('children');
    } else {
      node['children'] = neu;
    }
  }

  if (netze > 0) {
    notes.add('$knochen Knochen und die Gewichte von $netze Netz(en) '
        'entfernt: Auto Setup baut Zerlegung, R15-Rig, Cages und '
        'Attachments selbst und verwirft ein mitgebrachtes Skelett.');
    notes.add('Die Punkte bleiben, wo sie waren – in der Bindepose ist '
        'die Skinning-Matrix die Einheitsmatrix. Das Netz hängt jetzt '
        'ohne Elterntransformation direkt in der Szene, damit das auch '
        'so bleibt. Stand die Figur in der Datei in einer anderen '
        'Haltung als in den Bindematrizen, sieht man sie danach in der '
        'Bindepose – im Viewer nachsehen.');
  }
  if (anim > 0) {
    notes.add('$anim Animation(en) entfernt: Ihre Spuren zeigten auf '
        'die Knochen.');
  }
  return RigStripReport(
      bones: knochen, animations: anim, meshes: netze, notes: notes);
}
