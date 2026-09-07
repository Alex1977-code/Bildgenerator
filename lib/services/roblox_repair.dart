/// Reparatur-Modus: eine bestehende Figur marktplatzfähig machen.
///
/// **Warum das der Weg ist.** Drei Prompt-Varianten haben die
/// Segmentierung nicht gerettet; Hals-Einschnürung plus Arm-Drehung
/// haben es beim ersten Versuch getan. Aus einem „Head" von 3,16 Studs
/// Breite und Beinen ohne Höhe wurden 1,28 und symmetrische
/// Gliedmaßen, und von 123 Validierungsmeldungen blieben vier – alle
/// zum Gesichtsrig, keine zum Körper.
///
/// **Was hier passiert und was nicht.** Jede Regel hat eine Grenze,
/// bis zu der die App sie beheben darf. Darüber lautet die Meldung
/// „Prompt: neu erzeugen", weil die Korrektur die Figur sonst so
/// verformt, dass sie nicht mehr wie das Konzept aussieht. Eine Figur
/// mit 2,45 Studs Tiefe lässt sich auf 1,95 stauchen; eine mit 3,50
/// wäre danach ein Brett.
///
/// **Die Reihenfolge ist nicht beliebig:** Geometrie vor der
/// Dezimierung, damit der Trichter am Saum keine Dreiecke frisst, die
/// danach fehlen; Gesichtsteile nach der Dezimierung, damit ihre
/// Dreiecke exakt bleiben.
///
/// Alles ohne Rig, auf dem Einzelmesh, **nach** der Vorbereitung: Die
/// Messungen brauchen 5,00 Studs Höhe und die Zehen auf +Z.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart';
import 'local_3d.dart';
import 'mesh_budget.dart'
    show decimateGlb, firstGlbTexturePng, glbTriangleCount;
import 'roblox_face_parts.dart';
import 'roblox_face_sculpt.dart';
import 'roblox_fix.dart';
import 'roblox_marketplace.dart';

/// Wie weit eine Regel gehen darf, bevor der Prompt dran ist.
class RepairLimit {
  const RepairLimit(this.id, this.label, this.goal, this.repairableTo);

  final String id;
  final String label;

  /// Der Zielwert, auf den repariert wird.
  final double goal;

  /// Der schlechteste Ausgangswert, bei dem sich das noch lohnt.
  final double repairableTo;
}

/// Die Grenzen aus dem Pflichtenheft, gemessen an zwei Figuren.
/// Tiefe für Classic und Slender (Grenze 2,00). Normal erlaubt 2,25 –
/// siehe [repairDepthFor].
const repairDepth = RepairLimit('tiefe', 'Tiefe', 1.95, 2.60);

/// Die Tiefengrenze je Skala: Ziel 0,10 unter der absoluten Grenze,
/// behebbar bis 0,60 darüber – mehr wäre ein Brett.
RepairLimit repairDepthFor(RobloxBodyScale scale) => RepairLimit(
    'tiefe', 'Tiefe', scale.maxDepth - 0.10, scale.maxDepth + 0.60);
const repairLegWidth = RepairLimit('bein_breite', 'Beinbreite', 1.45, 1.80);

/// Auf welchen Anteil der Kopfbreite der Hals eingeschnürt wird.
///
/// Die Grenze liegt bei 50 %; das Ziel liegt darunter, damit eine
/// Messung mit anderen Bändern nicht wieder darüber landet.
const double repairNeckGoal = 0.45;

/// Radius der Zylinder-Klemme unter der Hüfte, in Studs.
const double repairLegClampRadius = 0.75;

/// Um wie viel Grad die Arme aus der T- in die A-Pose fallen.
const double repairArmDrop = 45;

/// Wie weit herabhängende Arme abgespreizt werden (Grad).
///
/// Die Gegenbewegung zu [repairArmDrop] und derselbe Winkel: Der
/// Posen-Zusatz an die Ansichten bestellt „arms straight and angled 45
/// degrees down", und genau dorthin bringt der Schritt eine I-Pose.
const double repairArmSpread = 45;

/// Dreiecksziel nach der Dezimierung – etwas unter der Grenze, damit
/// die Gesichtsteile noch hineinpassen.
const int repairTriangleGoal = 6800;

enum RepairOrigin {
  /// Die App hat es behoben.
  app,

  /// Zu weit weg – das muss der Prompt richten.
  prompt,
}

class RepairStep {
  const RepairStep({
    required this.rule,
    required this.before,
    required this.after,
    required this.origin,
    required this.note,
    this.fixed = true,
  });

  final String rule;
  final String before;
  final String after;
  final RepairOrigin origin;
  final String note;

  /// Ob dieser Schritt die Regel wirklich erfüllt hat.
  ///
  /// Der Bericht zeigte den grünen Haken nach [origin]: Wer ihn trug,
  /// galt als behoben. Eine Nachmessung mit Herkunft „Export" – etwa
  /// die Armspanne – bekam ihn deshalb ebenfalls, obwohl daneben
  /// „offen" stand. Wer nur auf die Haken sah, hielt eine Figur für
  /// fertig, die es nicht war.
  final bool fixed;

  bool get changed => before != after;
}

class RepairReport {
  const RepairReport(this.steps);

  final List<RepairStep> steps;

  bool get anythingLeft => steps.any((s) => !s.fixed);

  String get text => [
        'Reparatur-Bericht',
        for (final s in steps)
          '  ${s.rule}: ${s.before} → ${s.after} '
              '[${s.fixed ? 'behoben' : 'offen, '
                  '${s.origin == RepairOrigin.app ? 'Export' : 'Prompt'}'}] '
              '${s.note}',
      ].join('\n');
}

class RepairResult {
  const RepairResult(this.glb, this.report,
      {this.studs = marketplaceFigureStuds});

  /// Wie hoch die Figur am Ende ist, Studs.
  ///
  /// Nicht immer die angefragte Höhe: Erfüllt ein gleichmäßiger
  /// Maßstab die absoluten Mindestmaße, nimmt die Reparatur ihn –
  /// siehe [fitMarketplaceScale]. Die Prüfung danach muss mit
  /// **dieser** Zahl rechnen, sonst misst sie die alte Figur.
  final double studs;
  final Uint8List glb;
  final RepairReport report;
}

/// Zwischenmaße, die der Reparatur-Modus braucht und die die
/// Marktplatz-Messung nicht liefert.
class _Zonen {
  _Zonen(this.hipY, this.shoulderY, this.neckY, this.headWidth,
      this.legCenters, this.armSpan, this.height);

  final double hipY;
  final double shoulderY;
  final double neckY;
  final double headWidth;

  /// Die X-Mitten der beiden Beine, aus dem Knieband.
  final List<double> legCenters;
  final double armSpan;
  final double height;
}

/// Misst die Zonen, die für die Korrekturen gebraucht werden.
///
/// Bänder von 2 % der Höhe, wie im Pflichtenheft, gefüllt über
/// **Dreiecke**. Über Punkte ging es lange gut und dann nicht mehr:
/// Ein Kasten hat zwischen Unter- und Oberkante keine Punkte, ein
/// punktweise gefülltes Band ist dort leer, und der Hals einer
/// solchen Figur war unsichtbar. Dieselbe Falle war in [headBottomY]
/// schon behoben – hier nicht.
///
/// Die Insel-Zählung, für die auch Dreiecksbänder nicht genügen,
/// macht weiter [measureMarketplaceFigure].
_Zonen _messeZonen(Float32List pos, List<int> idx) {
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minX = double.infinity, maxX = double.negativeInfinity;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    minY = math.min(minY, pos[i + 1]);
    maxY = math.max(maxY, pos[i + 1]);
    minX = math.min(minX, pos[i]);
    maxX = math.max(maxX, pos[i]);
  }
  final hoehe = maxY - minY;
  const bands = 50;
  final breite = List<double>.filled(bands, 0);
  final loX = List<double>.filled(bands, double.infinity);
  final hiX = List<double>.filled(bands, double.negativeInfinity);
  if (hoehe > 0) {
    int band(double y) =>
        (((y - minY) / hoehe) * bands).floor().clamp(0, bands - 1);
    for (var t = 0; t + 2 < idx.length; t += 3) {
      var yLo = double.infinity, yHi = double.negativeInfinity;
      var xLo = double.infinity, xHi = double.negativeInfinity;
      for (var k = 0; k < 3; k++) {
        final v = idx[t + k] * 3;
        if (v + 2 >= pos.length) continue;
        yLo = math.min(yLo, pos[v + 1]);
        yHi = math.max(yHi, pos[v + 1]);
        xLo = math.min(xLo, pos[v]);
        xHi = math.max(xHi, pos[v]);
      }
      if (!yLo.isFinite) continue;
      for (var b = band(yLo); b <= band(yHi); b++) {
        loX[b] = math.min(loX[b], xLo);
        hiX[b] = math.max(hiX[b], xHi);
      }
    }
  }
  for (var b = 0; b < bands; b++) {
    breite[b] = loX[b].isFinite ? hiX[b] - loX[b] : 0;
  }

  // Kopf: das breiteste Band über der **gemessenen** Unterkante –
  // dieselbe Regel wie beim Einbau der Gesichtsteile und bei der
  // Messung. Vorher stand hier „das oberste Fünftel". Bei einer Figur
  // mit kleinem Kopf steckten die Schultern in diesem Fünftel; dann
  // ist breite[kopfBand] die Schulterbreite, die Suche nach einer
  // Schulter über dem Anderthalbfachen davon findet nichts, und die
  // Einschnürung setzt am Kopf selbst an – sie schrumpft ihn mit, und
  // das Verhältnis bleibt, wie es war. Genau der Fall, den der
  // Rückfall unten auffangen sollte und nicht auffing.
  var kopfBand = headBottomBand(breite) ?? (bands * 0.8).floor();
  for (var b = kopfBand; b < bands; b++) {
    if (breite[b] > breite[kopfBand]) kopfBand = b;
  }
  var schulterBand = kopfBand;
  for (var b = kopfBand - 1; b >= 0; b--) {
    if (breite[b] > breite[kopfBand] * 1.5) {
      schulterBand = b;
      break;
    }
  }
  var halsBand = kopfBand;
  for (var b = schulterBand; b <= kopfBand; b++) {
    if (breite[b] > 0 && breite[b] < breite[halsBand]) halsBand = b;
  }
  // Kein Band ist schmaler als der Kopf? Dann gibt es keinen Hals –
  // und genau dann soll einer entstehen. Eingeschnürt wird direkt
  // über der Schulter; das ist die Stelle, an der Auto Setup die
  // Grenze zwischen Kopf und Rumpf sucht. Ohne diesen Fall
  // schrumpfte die Einschnürung den Kopf mit, und das Verhältnis
  // blieb, wie es war.
  if (halsBand >= kopfBand && schulterBand < kopfBand) {
    halsBand = math.min(schulterBand + 1, kopfBand - 1);
  }

  double bandY(int b) => minY + (b + 0.5) / bands * hoehe;

  // Hüfte bei 45 % der Höhe; die Beinmitten kommen aus dem Knieband
  // (25 %), wo die Beine sicher getrennt sind.
  final hueftY = minY + hoehe * marketplaceLegZone;
  final knieB = (bands * 0.25).floor();
  final links = <double>[];
  final rechts = <double>[];
  final mitteX = (minX + maxX) / 2;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    final b = hoehe <= 0
        ? 0
        : (((pos[i + 1] - minY) / hoehe) * bands)
            .floor()
            .clamp(0, bands - 1);
    if (b != knieB) continue;
    (pos[i] < mitteX ? links : rechts).add(pos[i]);
  }
  double mittel(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  return _Zonen(
    hueftY,
    bandY(schulterBand),
    bandY(halsBand),
    breite[kopfBand],
    [
      if (links.isNotEmpty) mittel(links),
      if (rechts.isNotEmpty) mittel(rechts),
    ],
    maxX - minX,
    hoehe,
  );
}

/// Zählt die Dreiecke, deren Normale sich zwischen zwei Punktlagen
/// umgedreht hat – das Maß dafür, dass eine Verformung ein Netz
/// umgestülpt hat, statt es zu formen.
///
/// Bei der ersten Figur mit dem Marktplatz-Schwanz zog die Klemme
/// unter der Hüfte den Bauch nach innen: 1.400 Dreiecke zeigten
/// danach zusätzlich nach innen, und die Beine waren schlechter
/// getrennt als vorher. Seitdem misst jede Verformung an einer Kopie
/// nach und nimmt sich zurück, wenn sie umstülpt.
int countFlippedTriangles(
    Float32List vorher, Float32List nachher, List<int> idx) {
  var n = 0;
  final grenze = math.min(vorher.length, nachher.length);
  for (var t = 0; t + 2 < idx.length; t += 3) {
    final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
    if (a + 2 >= grenze || b + 2 >= grenze || c + 2 >= grenze) continue;
    final nv = _normale(vorher, a, b, c);
    final nn = _normale(nachher, a, b, c);
    if (nv[0] * nn[0] + nv[1] * nn[1] + nv[2] * nn[2] < 0) n++;
  }
  return n;
}

List<double> _normale(Float32List p, int a, int b, int c) {
  final ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
  final vx = p[c] - p[a], vy = p[c + 1] - p[a + 1], vz = p[c + 2] - p[a + 2];
  return [uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx];
}

/// Staucht die Tiefe um die Z-Mitte.
void _tiefeStauchen(Float32List pos, double faktor, double mitte) {
  for (var i = 2; i < pos.length; i += 3) {
    pos[i] = mitte + (pos[i] - mitte) * faktor;
  }
}

/// Schnürt den Hals ein.
///
/// Radial zur Y-Achse, mit einer Glockenkurve über ± [halbe] Studs um
/// [halsY]: In der Mitte greift der volle Faktor, am Rand gar keiner.
/// Ohne den weichen Übergang entsteht eine Kante, und die sieht man.
void _halsEinschnueren(
    Float32List pos, double halsY, double halbe, double faktor,
    double mitteX, double mitteZ) {
  for (var i = 0; i + 2 < pos.length; i += 3) {
    final d = (pos[i + 1] - halsY).abs();
    if (d >= halbe) continue;
    // Glocke: cos²-Verlauf von 1 in der Mitte auf 0 am Rand.
    final t = math.cos(d / halbe * math.pi / 2);
    final f = 1 - (1 - faktor) * t * t;
    pos[i] = mitteX + (pos[i] - mitteX) * f;
    pos[i + 2] = mitteZ + (pos[i + 2] - mitteZ) * f;
  }
}

/// Bildet die Höhe stückweise linear auf die Norm-Anteile ab.
///
/// **Was das ist.** Der Maßstab-Schritt macht die Figur als Ganzes
/// größer und trifft damit die absoluten Mindestmaße, ohne ein
/// Verhältnis zu ändern. Stimmen die Verhältnisse selbst nicht – ein
/// Kopf, der ein Drittel der Höhe einnimmt, Beine, die bei 22 % enden
/// –, hilft das nicht. Dann bleibt nur, die Höhe umzurechnen: Schritt
/// und Halslinie wandern, Boden und Scheitel bleiben, wo sie sind,
/// dazwischen wird linear gestreckt oder gestaucht.
///
/// **Wohin sie wandern, entscheidet die aufrufende Stelle** – und
/// zwar auf das **kleinste** Maß, mit dem die Mindestmaße stimmen,
/// nicht auf die Norm-Anteile. Der Unterschied ist an einer echten
/// Figur gemessen: Auf 40 % / 75 % gezwungen wurden die Beine um das
/// 1,82-fache gestreckt und der Rumpf auf 0,58 gestaucht – die Textur
/// zog sichtbar mit. Nur so weit wie nötig sind es 1,28 und 0,90, und
/// der Kopf bleibt ganz unberührt. Die Regel gilt eingehalten oder
/// nicht; darüber hinaus zu verformen bringt nichts und kostet das
/// Aussehen.
///
/// **Was das kostet.** Es ist eine echte Verformung: Wo gestreckt
/// wird, wird die Textur mitgezogen, und ein gestauchter Kopf ist ein
/// flacherer Kopf. Deshalb ist es abschaltbar und standardmäßig aus.
///
/// **Was es nicht kaputtmacht.** Die Abbildung ist monoton steigend
/// und stetig: Kein Dreieck stülpt sich um, keine Fläche reißt auf,
/// die Hülle bleibt so dicht, wie sie war. X und Z bleiben
/// unangetastet – Breite und Tiefe ändern sich nicht.
void _proportionenNormen(Float32List pos, double minY, double hoehe,
    double ySchritt, double yHals, double zielSchritt, double zielHals) {
  if (hoehe <= 0) return;
  // Stützstellen: Boden, Schritt, Halslinie, Scheitel.
  final von = [minY, ySchritt, yHals, minY + hoehe];
  final nach = [
    minY,
    minY + hoehe * zielSchritt,
    minY + hoehe * zielHals,
    minY + hoehe,
  ];
  // Ohne strenge Ordnung wäre die Abbildung nicht mehr monoton – dann
  // lieber gar nichts tun.
  for (var i = 1; i < von.length; i++) {
    if (von[i] <= von[i - 1] || nach[i] <= nach[i - 1]) return;
  }
  for (var i = 1; i < pos.length; i += 3) {
    final y = pos[i];
    for (var k = 1; k < von.length; k++) {
      if (y > von[k] && k < von.length - 1) continue;
      final t = ((y - von[k - 1]) / (von[k] - von[k - 1])).clamp(0.0, 1.0);
      pos[i] = nach[k - 1] + (nach[k] - nach[k - 1]) * t;
      break;
    }
  }
}

/// Zieht alles unter der Hüfte auf höchstens [radius] Studs Abstand
/// zur nächsten Beinmitte – der Trichter am Saum verschwindet, ohne
/// dass eine Fläche gelöscht wird.
void _zylinderKlemme(Float32List pos, double hueftY,
    List<double> beinMitten, double radius, double mitteZ) {
  if (beinMitten.isEmpty) return;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    if (pos[i + 1] >= hueftY) continue;
    var beste = beinMitten.first;
    for (final m in beinMitten) {
      if ((pos[i] - m).abs() < (pos[i] - beste).abs()) beste = m;
    }
    final dx = pos[i] - beste;
    final dz = pos[i + 2] - mitteZ;
    final r = math.sqrt(dx * dx + dz * dz);
    if (r <= radius || r <= 0) continue;
    final f = radius / r;
    pos[i] = beste + dx * f;
    pos[i + 2] = mitteZ + dz * f;
  }
}

/// Macht die Beine schmaler – jedes um seine eigene Mitte.
void _beinBreite(Float32List pos, double hueftY, List<double> beinMitten,
    double faktor) {
  if (beinMitten.isEmpty) return;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    if (pos[i + 1] >= hueftY) continue;
    var beste = beinMitten.first;
    for (final m in beinMitten) {
      if ((pos[i] - m).abs() < (pos[i] - beste).abs()) beste = m;
    }
    pos[i] = beste + (pos[i] - beste) * faktor;
  }
}

/// Wie fein der Querschnitt für die Armsuche gerastert wird.
const int _armBaender = 50;
const int _armZellen = 192;

/// Wo die Arme stecken – Band für Band **gemessen**, mit weichem
/// Übergang zur Schulter.
///
/// Der erste Anlauf hat die Achsel geraten (halbe Rumpfbreite oder
/// Kopfbreite mal 0,9) und alles außerhalb gedreht und gestreckt. An
/// einer Figur im langen Mantel war das der halbe Mantel: Der Saum
/// ist dort breiter als die Arme, er drehte mit und wurde zur Glocke.
/// Und weil der Rumpf mit auseinanderging, wuchs die gemessene
/// Rumpfbreite genauso schnell wie die Spanne – der Abstand blieb
/// klein, die Suche eskalierte auf 45° samt 1,6-facher Streckung, und
/// die Arme standen hinterher als Splitter ab.
///
/// Hier wird stattdessen im Querschnitt nachgesehen. Wo der Arm als
/// **eigene Insel** neben dem Rumpf steht, ist die Kante messbar, und
/// der Schnitt läuft durch die Lücke – durch leeren Raum, kein
/// Dreieck geht darüber. Weiter oben, wo Arm und Rumpf verschmelzen,
/// ist keine Kante zu messen; dort entsteht das Gewicht durch
/// **Diffusion**: Arm 1, Rumpf 0, und dazwischen glättet sich das
/// Feld über das Blech, das beide verbindet. Das ist derselbe
/// Kunstgriff, mit dem eine Skinning-Gewichtung entsteht, und er
/// verteilt den Übergang über die ganze Schulter statt über ein Band.
class _Armfeld {
  _Armfeld({
    required this.minY,
    required this.minX,
    required this.hoehe,
    required this.breite,
    required this.mitteX,
    required this.gewichte,
    required this.belegt,
    required this.schulterY,
    required this.drehpunktL,
    required this.drehpunktR,
    required this.armOben,
    required this.armUnten,
  });

  final double minY;
  final double minX;
  final double hoehe;
  final double breite;
  final double mitteX;

  /// Das geglättete Gewichtsfeld über dem Raster: 0 = Rumpf, 1 = Arm.
  final List<List<double>> gewichte;

  /// Welche Rasterzellen überhaupt Material enthalten.
  final List<List<bool>> belegt;

  final double schulterY;
  final double drehpunktL;
  final double drehpunktR;

  /// Ober- und Unterkante des gemessenen Armstücks, für den Bericht.
  final double armOben;
  final double armUnten;

  /// Wie stark ein Punkt der Drehung folgt – bilinear aus dem Raster,
  /// aber **nur über belegte Zellen**.
  ///
  /// Leere Zellen fließen nicht ein. Zählten sie als 0, sackte das
  /// Gewicht an jeder dünnen Stelle ab - Finger, Handkante -, und die
  /// Hand blieb hinter dem Unterarm zurück: aus den Fingern wurden
  /// Spitzen. Zählten sie mit dem Wert des Nachbarn (so stand es hier
  /// einen Anlauf lang), trug der leere Raum neben einem Arm dessen
  /// Gewicht in die Nachbarschaft und zog einen Mantelsaum mit, der
  /// eine Zelle darunter lag.
  double gewicht(double x, double y) {
    if (hoehe <= 0 || breite <= 0) return 0;
    final fb = ((y - minY) / hoehe) * _armBaender - 0.5;
    final fz = ((x - minX) / breite) * (_armZellen - 1);
    final b0 = fb.floor(), z0 = fz.floor();
    final tb = fb - b0, tz = fz - z0;
    var summe = 0.0, anteil = 0.0;
    void nimm(int b, int z, double c) {
      if (b < 0 || b >= _armBaender || z < 0 || z >= _armZellen) return;
      if (!belegt[b][z]) return;
      summe += c * gewichte[b][z];
      anteil += c;
    }

    nimm(b0, z0, (1 - tb) * (1 - tz));
    nimm(b0, z0 + 1, (1 - tb) * tz);
    nimm(b0 + 1, z0, tb * (1 - tz));
    nimm(b0 + 1, z0 + 1, tb * tz);
    if (anteil > 0.001) return summe / anteil;
    // Kein belegter Nachbar – dann die eigene Zelle, falls es sie gibt.
    final b = (fb + 0.5).floor().clamp(0, _armBaender - 1);
    final z = fz.round().clamp(0, _armZellen - 1);
    return belegt[b][z] ? gewichte[b][z] : 0;
  }
}

/// Die zusammenhängenden belegten Bereiche eines Bandes.
///
/// Einzelne leere Zellen zwischen zwei belegten werden vorher
/// geschlossen – sonst reißt ein schräger Rand eine Insel entzwei.
List<List<int>> _inselListe(List<bool> band) {
  final geglaettet = List<bool>.from(band);
  for (var i = 1; i < band.length - 1; i++) {
    if (!band[i] && band[i - 1] && band[i + 1]) geglaettet[i] = true;
  }
  final out = <List<int>>[];
  var i = 0;
  while (i < geglaettet.length) {
    if (!geglaettet[i]) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < geglaettet.length && geglaettet[j + 1]) {
      j++;
    }
    out.add([i, j]);
    i = j + 1;
  }
  return out;
}

/// Sucht die Arme im Querschnitt und baut das Gewichtsfeld.
///
/// Gibt null zurück, wenn auf einer Seite kein Arm als eigene Insel
/// zu sehen ist. Dann wird nicht gedreht: Was hier nicht zu messen
/// ist, lässt sich auch nicht sauber bewegen.
_Armfeld? _findeArme(Float32List pos, List<int> idx, double schulterY) {
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minX = double.infinity, maxX = double.negativeInfinity;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    minY = math.min(minY, pos[i + 1]);
    maxY = math.max(maxY, pos[i + 1]);
    minX = math.min(minX, pos[i]);
    maxX = math.max(maxX, pos[i]);
  }
  final hoehe = maxY - minY, breite = maxX - minX;
  if (!(hoehe > 0) || !(breite > 0)) return null;

  // Rastern über **Dreiecke**: Ein Kasten hat zwischen Ober- und
  // Unterkante keine Punkte, punktweise bliebe das Band dort leer.
  final belegt =
      List.generate(_armBaender, (_) => List<bool>.filled(_armZellen, false));
  for (var t = 0; t + 2 < idx.length; t += 3) {
    var yLo = double.infinity, yHi = double.negativeInfinity;
    var xLo = double.infinity, xHi = double.negativeInfinity;
    for (var k = 0; k < 3; k++) {
      final v = idx[t + k] * 3;
      if (v + 2 >= pos.length) continue;
      yLo = math.min(yLo, pos[v + 1]);
      yHi = math.max(yHi, pos[v + 1]);
      xLo = math.min(xLo, pos[v]);
      xHi = math.max(xHi, pos[v]);
    }
    if (!yLo.isFinite || !xLo.isFinite) continue;
    final b0 =
        (((yLo - minY) / hoehe) * _armBaender).floor().clamp(0, _armBaender - 1);
    final b1 =
        (((yHi - minY) / hoehe) * _armBaender).ceil().clamp(1, _armBaender);
    final z0 = (((xLo - minX) / breite) * (_armZellen - 1))
        .floor()
        .clamp(0, _armZellen - 1);
    final z1 = (((xHi - minX) / breite) * (_armZellen - 1))
        .ceil()
        .clamp(0, _armZellen - 1);
    for (var b = b0; b < math.max(b1, b0 + 1); b++) {
      for (var z = z0; z <= z1; z++) {
        belegt[b][z] = true;
      }
    }
  }

  final mitteZelle = (_armZellen - 1) ~/ 2;
  final schulterBand = (((schulterY - minY) / hoehe) * _armBaender)
      .floor()
      .clamp(0, _armBaender - 1);
  // Je Band die Kante des Rumpfes zu jeder Seite – gesetzt nur dort,
  // wo daneben wirklich eine eigene Insel steht.
  final kanteL = List<double>.filled(_armBaender, double.nan);
  final kanteR = List<double>.filled(_armBaender, double.nan);
  final inselnJeBand = <List<List<int>>>[];
  for (var b = 0; b < _armBaender; b++) {
    final inseln = _inselListe(belegt[b]);
    inselnJeBand.add(inseln);
    if (b > schulterBand) continue;
    final k = inseln.indexWhere((i) => i[0] <= mitteZelle && mitteZelle <= i[1]);
    if (k < 0) continue;
    if (k > 0) kanteL[b] = inseln[k][0].toDouble();
    if (k < inseln.length - 1) kanteR[b] = inseln[k][1].toDouble();
  }
  var obenL = -1, untenL = -1, obenR = -1, untenR = -1;
  for (var b = 0; b < _armBaender; b++) {
    if (!kanteL[b].isNaN) {
      if (untenL < 0) untenL = b;
      obenL = b;
    }
    if (!kanteR[b].isNaN) {
      if (untenR < 0) untenR = b;
      obenR = b;
    }
  }
  // Auf beiden Seiten muss ein Arm über mindestens vier Bänder frei
  // stehen; ein einzelnes Band ist Rauschen.
  if (obenL - untenL < 3 || obenR - untenR < 3) return null;

  final gewichte =
      List.generate(_armBaender, (_) => List<double>.filled(_armZellen, 0));
  final fest =
      List.generate(_armBaender, (_) => List<bool>.filled(_armZellen, false));
  void setze(int b, int z, double w) {
    gewichte[b][z] = w;
    fest[b][z] = true;
  }

  for (var b = 0; b < _armBaender; b++) {
    for (final insel in inselnJeBand[b]) {
      for (var z = insel[0]; z <= insel[1]; z++) {
        if (!belegt[b][z]) continue;
        if (b > schulterBand) {
          setze(b, z, 0);
        } else if (!kanteL[b].isNaN && z < kanteL[b]) {
          setze(b, z, 1);
        } else if (!kanteR[b].isNaN && z > kanteR[b]) {
          setze(b, z, 1);
        } else if (!kanteL[b].isNaN || !kanteR[b].isNaN) {
          setze(b, z, 0);
        }
      }
    }
  }
  // Der Kern bleibt der Kern.
  //
  // Was näher an der Achse liegt als die **schmalste** gemessene
  // Rumpfkante, ist kein Arm - Beine, Füße, Rumpf, der innere Teil
  // eines Mantelsaums. Ohne diese Festlegung hängt an einer Figur mit
  // Saum die ganze untere Hälfte frei in der Ausgleichsrechnung: Sie
  // ist über den Saum mit dem Arm verbunden, hat aber nach unten
  // nichts, was sie auf null hält, und wandert mit hoch. An einer
  // Testfigur drehten sich so die Beine mit.
  var kernHalb = double.infinity;
  for (var b = 0; b < _armBaender; b++) {
    if (!kanteL[b].isNaN) {
      kernHalb = math.min(kernHalb, (mitteZelle - kanteL[b]).abs());
    }
    if (!kanteR[b].isNaN) {
      kernHalb = math.min(kernHalb, (kanteR[b] - mitteZelle).abs());
    }
  }
  if (kernHalb.isFinite) {
    for (var b = 0; b <= schulterBand && b < _armBaender; b++) {
      for (var z = 0; z < _armZellen; z++) {
        if (!belegt[b][z] || fest[b][z]) continue;
        if ((z - mitteZelle).abs() < kernHalb) setze(b, z, 0);
      }
    }
  }

  // Unter dem tiefsten gemessenen Band hängen noch Hände: Bänder
  // unterhalb des Schritts zerfallen in Beine, die Mitte ist frei,
  // und dann ist keine Rumpfkante zu messen. Was dort **deutlich**
  // außerhalb der letzten Kante liegt, gehört zum Arm.
  void handNachUnten(int unten, double kante, bool links) {
    final marge = _armZellen * 0.03;
    for (var b = unten - 1; b >= 0; b--) {
      var etwas = false;
      for (final insel in inselnJeBand[b]) {
        final drin = links
            ? insel[1] < kante - marge
            : insel[0] > kante + marge;
        if (!drin) continue;
        etwas = true;
        for (var z = insel[0]; z <= insel[1]; z++) {
          if (belegt[b][z]) setze(b, z, 1);
        }
      }
      if (!etwas) break;
    }
  }

  handNachUnten(untenL, kanteL[untenL], true);
  handNachUnten(untenR, kanteR[untenR], false);

  // Diffusion über das Blech: Wo nichts festgesetzt ist – die
  // verschmolzene Schulter –, mittelt sich das Gewicht aus den
  // Nachbarn. Leere Zellen leiten nicht; über die Lücke zwischen Arm
  // und Rumpf kann also nichts überspringen. Der Übergang entsteht so
  // über die ganze Höhe, über die beide zusammenhängen.
  var feld = gewichte;
  for (var runde = 0; runde < 400; runde++) {
    final neu = List.generate(
        _armBaender, (b) => List<double>.from(feld[b]));
    for (var b = 0; b < _armBaender; b++) {
      for (var z = 0; z < _armZellen; z++) {
        if (fest[b][z] || !belegt[b][z]) continue;
        var summe = 0.0;
        var n = 0;
        void nimm(int bb, int zz) {
          if (bb < 0 || bb >= _armBaender || zz < 0 || zz >= _armZellen) return;
          if (!belegt[bb][zz]) return;
          summe += feld[bb][zz];
          n++;
        }

        nimm(b - 1, z);
        nimm(b + 1, z);
        nimm(b, z - 1);
        nimm(b, z + 1);
        if (n > 0) neu[b][z] = summe / n;
      }
    }
    feld = neu;
  }

  double xVon(double zelle) => minX + zelle / (_armZellen - 1) * breite;
  double yVon(int band) => minY + (band + 0.5) / _armBaender * hoehe;
  return _Armfeld(
    minY: minY,
    minX: minX,
    hoehe: hoehe,
    breite: breite,
    mitteX: (minX + maxX) / 2,
    gewichte: feld,
    belegt: belegt,
    schulterY: schulterY,
    drehpunktL: xVon(kanteL[obenL]),
    drehpunktR: xVon(kanteR[obenR]),
    armOben: yVon(math.max(obenL, obenR)),
    armUnten: yVon(math.min(untenL, untenR)),
  );
}

/// Spreizt die gefundenen Arme um [grad] nach außen ab.
///
/// Gedreht wird um das Schultergelenk – für jede Seite um ihren
/// eigenen Punkt –, und zwar anteilig nach dem Gewichtsfeld. Am Rumpf
/// ist das Gewicht null: Dort bleibt jeder Punkt, wo er ist. Genau
/// darauf kommt es an, denn gemessen wird der Abstand als Spanne
/// **minus Rumpfbreite**; geht der Rumpf mit auseinander, bringt das
/// Drehen nichts.
///
/// Ohne Klemme und ohne Streckung. Beides stand hier: Die Klemme
/// („nichts steigt über die Schulter") legte alles, was sich hob, auf
/// eine Ebene und machte aus dem Arm ein Blatt; die Streckung sollte
/// nachhelfen, was nur nötig schien, weil der Rumpf mitging.
void _armeAbspreizen(Float32List pos, _Armfeld feld, double grad) {
  final theta = grad * math.pi / 180;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    final x = pos[i], y = pos[i + 1];
    final w = feld.gewicht(x, y);
    if (w <= 0.001) continue;
    final links = x < feld.mitteX;
    final px = links ? feld.drehpunktL : feld.drehpunktR;
    final phi = (links ? -1 : 1) * theta * w;
    final dx = x - px, dy = y - feld.schulterY;
    final c = math.cos(phi), s = math.sin(phi);
    pos[i] = px + dx * c - dy * s;
    pos[i + 1] = feld.schulterY + dx * s + dy * c;
  }
}

/// Zählt die Kanten, die eine Verformung über [faktor] gedehnt hat.
///
/// Der Umstülp-Wächter allein hat nicht gereicht: Beim ersten
/// Abspreizen wurde die Schulter flachgeklemmt und der Mantelsaum
/// mitgezogen. Kein Dreieck drehte sich dabei um – die Zählung stand
/// bei null –, und trotzdem standen die Arme hinterher als Splitter
/// ab. Eine gerissene Stelle ist an den Kanten zu sehen, die dabei
/// lang werden.
int countStretchedEdges(
    Float32List vorher, Float32List nachher, List<int> idx,
    {double faktor = 3.0}) {
  var n = 0;
  final grenze = math.min(vorher.length, nachher.length);
  double laenge(Float32List p, int a, int b) {
    final dx = p[b] - p[a];
    final dy = p[b + 1] - p[a + 1];
    final dz = p[b + 2] - p[a + 2];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  for (var t = 0; t + 2 < idx.length; t += 3) {
    for (var e = 0; e < 3; e++) {
      final a = idx[t + e] * 3, b = idx[t + (e + 1) % 3] * 3;
      if (a + 2 >= grenze || b + 2 >= grenze) continue;
      final vor = laenge(vorher, a, b);
      if (vor <= 0) continue;
      if (laenge(nachher, a, b) > vor * faktor) n++;
    }
  }
  return n;
}

void _armeSenken(Float32List pos, double schulterY, double schulterHalb,
    double grad, double weich) {
  final rad = grad * math.pi / 180;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    final x = pos[i];
    final seite = x < 0 ? -1.0 : 1.0;
    final ausserhalb = x.abs() - schulterHalb;
    if (ausserhalb <= 0) continue;
    // Weicher Anlauf: direkt an der Schulter fast nichts, weiter außen
    // die volle Drehung.
    final t = (ausserhalb / weich).clamp(0.0, 1.0);
    final w = rad * t;
    final gx = seite * schulterHalb;
    final dx = x - gx;
    final dy = pos[i + 1] - schulterY;
    // Nach unten heißt: auf der linken Seite andersherum als rechts.
    final c = math.cos(w), s = math.sin(w);
    pos[i] = gx + dx * c - seite * dy * s * -1;
    pos[i + 1] = schulterY + dy * c - seite * dx * s;
  }
}

/// Schneidet den Steg zwischen den Beinen heraus.
///
/// Gelöscht werden Dreiecke, deren **drei** Punkte unter der Hüfte und
/// im Mittelstreifen liegen – ein Dreieck mit einer Ecke am Bein bleibt
/// stehen, sonst reißt die Naht auf. Die Löcher schließt danach
/// [fixGlbForRoblox] mit echter Triangulierung.
(Float32List, List<int>) _beineFreischneiden(Float32List pos,
    List<int> idx, double hueftY, double streifen, double mitteX) {
  final behalten = <int>[];
  for (var t = 0; t + 2 < idx.length; t += 3) {
    var drin = 0;
    for (var k = 0; k < 3; k++) {
      final v = idx[t + k] * 3;
      if (v + 2 >= pos.length) continue;
      if (pos[v + 1] < hueftY && (pos[v] - mitteX).abs() < streifen) {
        drin++;
      }
    }
    if (drin == 3) continue;
    behalten.addAll([idx[t], idx[t + 1], idx[t + 2]]);
  }
  return (pos, behalten);
}

/// Baut aus Punkten, UVs und Indizes wieder eine GLB.
Uint8List _bau(Float32List pos, List<double>? uvs, List<int> idx,
    Uint8List? textur) {
  final m = LocalMesh();
  final n = pos.length ~/ 3;
  final hatUv = uvs != null && uvs.length == n * 2;
  for (var v = 0; v < n; v++) {
    m.addVertex(pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2],
        hatUv ? uvs[v * 2] : 0, hatUv ? uvs[v * 2 + 1] : 0);
  }
  for (var t = 0; t + 2 < idx.length; t += 3) {
    m.addTriangle(idx[t], idx[t + 1], idx[t + 2]);
  }
  return buildGlb(m, pngTexture: hatUv ? textur : null);
}

/// Misst, behebt, misst nach.
///
/// [glb] muss vorbereitet sein: [targetStuds] hoch, Zehen auf +Z. Ohne
/// das messen die Bänder etwas anderes, als sie sollen.
Future<RepairResult> repairForMarketplace(
  Uint8List glb, {
  double targetStuds = marketplaceFigureStuds,
  bool addFace = true,
  bool sculptFace = true,
  FaceSculptProportions sculptProportions = const FaceSculptProportions(),
  bool decimate = true,
  bool normProportions = false,
  RobloxBodyScale scale = RobloxBodyScale.normal,
}) async {
  final tiefeGrenze = repairDepthFor(scale);
  final schritte = <RepairStep>[];
  // Ohne die fünf Gesichtsteile: Eine schon vorbereitete Figur bringt
  // sie mit, und der Umbau unten verschmölze sie mit dem Körper –
  // danach kämen fünf neue dazu, und die alten Augäpfel steckten im
  // Kopf. Sie werden am Ende neu gesetzt.
  var arbeit = withoutFaceMeshes(glb);

  var vorschau = await parseGlbForPreview(arbeit);
  var pos = Float32List.fromList(vorschau.positions);
  var idx = vorschau.indices.toList();
  final uvs = vorschau.uvs?.toList();
  vorschau.dispose();
  final textur = firstGlbTexturePng(glb);

  // Die Höhe ist von hier an veränderlich: Der Maßstab-Schritt darf
  // sie anheben, und jede spätere Messung muss mit der neuen rechnen.
  var hoehe = targetStuds;
  var mass = measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
  var zonen = _messeZonen(pos, idx);
  var mitteX = 0.0, mitteZ = 0.0;
  {
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minZ = double.infinity, maxZ = double.negativeInfinity;
    for (var i = 0; i + 2 < pos.length; i += 3) {
      minX = math.min(minX, pos[i]);
      maxX = math.max(maxX, pos[i]);
      minZ = math.min(minZ, pos[i + 2]);
      maxZ = math.max(maxZ, pos[i + 2]);
    }
    mitteX = (minX + maxX) / 2;
    mitteZ = (minZ + maxZ) / 2;
  }

  // Der Haken kommt aus der Herkunft: „App" heißt, die Reparatur hat
  // es getan, „Prompt" heißt, sie konnte es nicht. Nur die Nachmessung
  // muss ihn ausdrücklich verneinen – dort steht auch bei Herkunft
  // „Export" ein offener Befund.
  void notiere(String regel, String vorher, String nachher,
      RepairOrigin herkunft, String hinweis,
      {bool? fixed}) {
    schritte.add(RepairStep(
        rule: regel,
        before: vorher,
        after: nachher,
        origin: herkunft,
        note: hinweis,
        fixed: fixed ?? herkunft == RepairOrigin.app));
  }

  // 1. Tiefe – gegen die absolute Grenze der gewählten Skala (2,00
  // bei Classic und Slender, 2,25 bei Normal), nicht gegen ein
  // Verhältnis zur Höhe.
  if (mass.depth > scale.maxDepth) {
    if (mass.depth <= tiefeGrenze.repairableTo) {
      _tiefeStauchen(pos, tiefeGrenze.goal / mass.depth, mitteZ);
      notiere(
          repairStepDepth,
          mass.depth.toStringAsFixed(2),
          tiefeGrenze.goal.toStringAsFixed(2),
          RepairOrigin.app,
          'Z gestaucht um die Mitte; die Silhouette von vorn bleibt, '
              'die UVs bleiben.');
    } else {
      notiere(
          repairStepDepth,
          mass.depth.toStringAsFixed(2),
          mass.depth.toStringAsFixed(2),
          RepairOrigin.prompt,
          'Über ${tiefeGrenze.repairableTo.toStringAsFixed(2)} wäre die '
              'Figur danach ein Brett. Die Grenze ist absolut '
              '(${scale.maxDepth.toStringAsFixed(2)} Studs bei '
              '${scale.label}); ins Motiv gehört „flat chest and back", '
              'und „chunky" muss raus.');
    }
  }

  // Der Umstülp-Wächter: mehr als ein halbes Prozent der Dreiecke
  // (mindestens 20) umgedreht, und die Verformung wird zurückgenommen.
  int flipGrenze() => math.max(20, idx.length ~/ 600);

  // 1a. Proportionen auf die Norm – nur auf Wunsch.
  //
  // Vor dem Maßstab: Stimmen die Verhältnisse erst einmal, braucht es
  // hinterher weniger oder gar keine Vergrößerung mehr.
  if (normProportions) {
    var minYp = double.infinity, maxYp = double.negativeInfinity;
    for (var i = 1; i < pos.length; i += 3) {
      minYp = math.min(minYp, pos[i]);
      maxYp = math.max(maxYp, pos[i]);
    }
    final hoeheMesh = maxYp - minYp;
    final schrittAnteil =
        mass.height <= 0 ? 0.0 : mass.legHeight / mass.height;
    final halsAnteil =
        mass.height <= 0 ? 0.0 : 1 - mass.headHeight / mass.height;
    if (hoeheMesh > 0 && schrittAnteil > 0.05 && halsAnteil < 0.98) {
      final vorher = mass;
      // Die kleinste Verschiebung, mit der die Mindestmaße stimmen –
      // nicht die Norm-Anteile. Gerechnet in Studs bei der aktuellen
      // Höhe, dann zurück in Anteile.
      const m = marketplaceScaleMargin;
      var zielSchrittStuds =
          math.max(mass.legHeight, specMinLegHeight * m);
      var zielHalsStuds = math.max(
          hoehe - mass.headHeight, zielSchrittStuds + specMinTorsoHeight * m);
      // Der Kopf darf dabei nicht unter sein Mindestmaß rutschen; wenn
      // doch, muss der Schritt weiter herunter statt der Hals hinauf.
      final kopfGrenze = hoehe - specMinHeadSize * m;
      if (zielHalsStuds > kopfGrenze) {
        zielHalsStuds = kopfGrenze;
        zielSchrittStuds = math.min(
            zielSchrittStuds, zielHalsStuds - specMinTorsoHeight * m);
      }
      final zielSchritt = (zielSchrittStuds / hoehe).clamp(0.02, 0.96);
      final zielHals = (zielHalsStuds / hoehe).clamp(zielSchritt + 0.02, 0.98);
      // Stimmt schon alles, wird nicht angefasst: Jede Verformung
      // kostet Textur, und für nichts ist sie nicht zu haben.
      final bewegt = (zielSchritt - schrittAnteil).abs() > 0.005 ||
          (zielHals - halsAnteil).abs() > 0.005;
      if (!bewegt) {
        notiere(repairStepProportions,
            'Schritt bei ${(schrittAnteil * 100).round()} %, Halslinie '
                'bei ${(halsAnteil * 100).round()} %',
            'nichts zu tun', RepairOrigin.app,
            'Die Verhältnisse halten die Mindestmaße schon ein. Eine '
                'Verformung, die nichts löst, unterbleibt – sie würde '
                'nur die Textur ziehen.');
      } else {
        _proportionenNormen(
            pos,
            minYp,
            hoeheMesh,
            minYp + hoeheMesh * schrittAnteil,
            minYp + hoeheMesh * halsAnteil,
            zielSchritt,
            zielHals);
        mass = measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
        zonen = _messeZonen(pos, idx);
        double faktor(double vor, double nach) =>
            vor <= 0 ? 1 : nach / vor;
        notiere(
            repairStepProportions,
            'Schritt bei ${(schrittAnteil * 100).round()} %, Halslinie '
                'bei ${(halsAnteil * 100).round()} %',
            'Schritt bei ${(zielSchritt * 100).round()} %, Halslinie '
                'bei ${(zielHals * 100).round()} %',
            RepairOrigin.app,
            'Die Höhe stückweise linear umgerechnet, Boden und Scheitel '
                'bleiben; Breite und Tiefe bleiben unangetastet. '
                'Verschoben wird nur so weit, wie die Mindestmaße es '
                'verlangen – auf die Norm-Anteile '
                '(${(marketplaceNormHip * 100).round()} / '
                '${(marketplaceNormNeck * 100).round()} %) zu zwingen, '
                'verformt mehr, ohne mehr zu lösen. Beine '
                '${vorher.legHeight.toStringAsFixed(2)} → '
                '${mass.legHeight.toStringAsFixed(2)} '
                '(x${faktor(vorher.legHeight, mass.legHeight)
                    .toStringAsFixed(2)}), Rumpf '
                '${vorher.torsoHeight.toStringAsFixed(2)} → '
                '${mass.torsoHeight.toStringAsFixed(2)} '
                '(x${faktor(vorher.torsoHeight, mass.torsoHeight)
                    .toStringAsFixed(2)}), Kopf '
                '${vorher.headHeight.toStringAsFixed(2)} → '
                '${mass.headHeight.toStringAsFixed(2)} '
                '(x${faktor(vorher.headHeight, mass.headHeight)
                    .toStringAsFixed(2)}). Wo gestreckt wird, zieht die '
                'Textur mit.');
      }
    } else {
      notiere(repairStepProportions, '–', 'nicht möglich',
          RepairOrigin.prompt,
          'Schritt und Halslinie lassen sich an dieser Figur nicht '
              'auseinanderhalten – ohne zwei getrennte Beine und einen '
              'Kopf über der Schulter gibt es keine Stützstellen, '
              'zwischen denen sich umrechnen ließe.');
    }
  }

  // 1b. Maßstab – der einzige Hebel gegen zu kleine Teile.
  //
  // Muss nach dem Stauchen kommen: Die Tiefe deckelt den Maßstab, und
  // gestaucht ist sie eine andere. Und vor allem Weiteren, weil jede
  // spätere Zone in Mesh-Koordinaten liegt und ein Maßstab sie
  // verschöbe.
  {
    mass = measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
    final fit = fitMarketplaceScale(mass, scale: scale);
    if (fit.needsScaling && fit.possible) {
      var minY = double.infinity;
      for (var i = 1; i < pos.length; i += 3) {
        minY = math.min(minY, pos[i]);
      }
      final f = fit.needed;
      for (var i = 0; i + 2 < pos.length; i += 3) {
        pos[i] = mitteX + (pos[i] - mitteX) * f;
        pos[i + 1] = minY + (pos[i + 1] - minY) * f;
        pos[i + 2] = mitteZ + (pos[i + 2] - mitteZ) * f;
      }
      hoehe = fit.height;
      mass = measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
      zonen = _messeZonen(pos, idx);
      notiere(
          repairStepScale,
          '${fit.fromHeight.toStringAsFixed(2)} Studs',
          '${hoehe.toStringAsFixed(2)} Studs',
          RepairOrigin.app,
          'Die Mindestmaße sind absolut, die Gesamthöhe ist frei '
              '(${specMinBodyHeight.toStringAsFixed(1)} bis '
              '${scale.maxTotalHeight.toStringAsFixed(1)} Studs bei '
              '${scale.label}). Gefordert hat den Faktor '
              '${f.toStringAsFixed(3)} die ${fit.forcedBy}; gedeckelt '
              'wäre er bei ${fit.allowed.toStringAsFixed(3)} durch die '
              '${fit.limitedBy}. Kein Verhältnis ändert sich dabei – '
              'die Figur wird als Ganzes größer ausgegeben, und der '
              'Importer nimmt eine glTF-Einheit als einen Stud.');
    } else if (fit.needsScaling) {
      notiere(
          repairStepScale,
          '${fit.fromHeight.toStringAsFixed(2)} Studs',
          'nicht möglich',
          RepairOrigin.prompt,
          'Die ${fit.forcedBy} bräuchte den Faktor '
              '${fit.needed.toStringAsFixed(3)} '
              '(${fit.height.toStringAsFixed(2)} Studs), die '
              '${fit.limitedBy} lässt nur '
              '${fit.allowed.toStringAsFixed(3)} zu '
              '(${(fit.fromHeight * fit.allowed).toStringAsFixed(2)} '
              'Studs). Ein Maßstab ändert kein Verhältnis: Hier stimmen '
              'die Proportionen nicht, und das richtet nur der Prompt.');
    }
  }

  // 2. Hals.
  if (!mass.hasNeck) {
    final bezug = math.min(mass.headWidth, mass.shoulderWidth);
    if (zonen.headWidth > 0 && bezug > 0 && mass.neckWidth > 0) {
      final ziel = bezug * repairNeckGoal;
      final faktor = (ziel / mass.neckWidth).clamp(0.2, 1.0);
      final kopie = Float32List.fromList(pos);
      _halsEinschnueren(pos, zonen.neckY, zonen.height * 0.06, faktor,
          mitteX, mitteZ);
      final flips = countFlippedTriangles(kopie, pos, idx);
      if (flips > flipGrenze()) {
        pos.setAll(0, kopie);
        notiere(
            repairStepNeck,
            '${(mass.neckRatio * 100).round()} %',
            'verworfen',
            RepairOrigin.prompt,
            '$flips Dreiecke hätten sich beim Einschnüren umgedreht – '
                'zwischen Kopf und Schulter sitzt hier ein Kragen oder '
                'eine Kapuze, kein Hals. Ins Motiv: „narrow visible '
                'neck not merged with the shoulders".');
      } else {
        // Nachmessen statt behaupten.
        //
        // Der Schritt meldete bisher sein **Ziel** (45 %), nicht sein
        // Ergebnis. An einer echten Figur waren es 50 % – exakt die
        // Grenze, ab der die Prüfung „kein Hals" sagt, und das nur
        // durch Zufall auf der richtigen Seite. Die Glocke schnürt um
        // halsY; das Band, an dem die Messung den Hals abliest, liegt
        // nicht zwangsläufig in ihrer Mitte. Also: messen, und mit dem
        // Rest nachziehen, höchstens zweimal.
        var erreicht =
            measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
        var runden = 1;
        // Bis zum **Ziel** nachziehen, nicht bis zur Grenze: Genau
        // auf 50 % zu landen hieße, dass jede Messtoleranz von Roblox
        // die Figur kippt. Der Aufschlag ist derselbe Gedanke wie bei
        // [marketplaceScaleMargin].
        for (var i = 0;
            i < 2 && erreicht.neckRatio > repairNeckGoal + 0.01;
            i++) {
          final bezug2 =
              math.min(erreicht.headWidth, erreicht.shoulderWidth);
          if (bezug2 <= 0 || erreicht.neckWidth <= 0) break;
          final faktor2 =
              (bezug2 * repairNeckGoal / erreicht.neckWidth).clamp(0.2, 1.0);
          if (faktor2 >= 0.999) break;
          final kopie2 = Float32List.fromList(pos);
          _halsEinschnueren(pos, zonen.neckY, zonen.height * 0.06,
              faktor2, mitteX, mitteZ);
          if (countFlippedTriangles(kopie2, pos, idx) > flipGrenze()) {
            pos.setAll(0, kopie2);
            break;
          }
          runden++;
          erreicht = measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
        }
        notiere(
            repairStepNeck,
            '${(mass.neckRatio * 100).round()} %',
            '${(erreicht.neckRatio * 100).round()} %',
            erreicht.hasNeck ? RepairOrigin.app : RepairOrigin.prompt,
            'Radial eingeschnürt, Glockenkurve über ± 6 % der Höhe – '
                'ohne weichen Übergang entsteht eine sichtbare Kante. '
                '$runden Durchgang(e), danach gemessen; Ziel sind '
                '${(repairNeckGoal * 100).round()} %, die Grenze liegt '
                'bei ${(marketplaceNeckRatio * 100).round()} %.'
                '${erreicht.hasNeck ? '' : ' Weiter einzuschnüren würde '
                    'den Kopf mitziehen – hier sitzt ein Kragen, kein '
                    'Hals. Ins Motiv: „collarless top", und der feste '
                    'Satz „distinct narrow neck not merged with the '
                    'shoulders" muss beim Bildmodell ankommen.'}');
      }
    } else {
      notiere(repairStepNeck, '${(mass.neckRatio * 100).round()} %', '–',
          RepairOrigin.prompt,
          'Kein Kopf-Maximum über der Schulter: Was eingeschnürt '
              'werden soll, ist nicht auffindbar.');
    }
  }

  // 3. Beine freischneiden, wenn sie zusammenhängen – auf Probe: Der
  // Schnitt gilt nur, wenn die Trennung danach besser ist und der
  // Schritt nicht tiefer liegt. Bei der ersten Figur mit dem
  // Marktplatz-Schwanz saß der Schritt bei 0,9 Studs; das war kein
  // Saum vor zwei Beinen, sondern ein Rumpf bis kurz über den Boden,
  // und der Schnitt machte aus 50 % Trennung 41 %.
  if (mass.legSeparation < marketplaceLegSeparation) {
    if (zonen.legCenters.length == 2) {
      final posVor = Float32List.fromList(pos);
      final idxVor = List<int>.of(idx);
      final abstand = (zonen.legCenters[1] - zonen.legCenters[0]).abs();
      (pos, idx) = _beineFreischneiden(
          pos, idx, zonen.hipY, abstand * 0.5, mitteX);
      // 4. Zylinder-Klemme gegen den Trichter am Saum – mit Wächter:
      // Unter der Hüfte kann auch ein Bauch sitzen, und den stülpt
      // die Klemme nach innen.
      final kopie = Float32List.fromList(pos);
      _zylinderKlemme(
          pos, zonen.hipY, zonen.legCenters, repairLegClampRadius, mitteZ);
      final klemmFlips = countFlippedTriangles(kopie, pos, idx);
      final klemmeVerworfen = klemmFlips > flipGrenze();
      if (klemmeVerworfen) pos.setAll(0, kopie);
      // Die Probe: geheilt und nachgemessen, wie es am Ende auch
      // geschieht.
      final probeGlb = fixGlbForRoblox(_bau(pos, uvs, idx, textur),
              closeHoles: true, fixWinding: true)
          .glb;
      final probe = await parseGlbForPreview(probeGlb);
      final probeMass = measureMarketplaceFigure(
          probe.positions, probe.indices,
          targetStuds: hoehe);
      probe.dispose();
      final besser = probeMass.legSeparation > mass.legSeparation &&
          probeMass.legHeight >= mass.legHeight - 0.05;
      if (!besser) {
        pos = posVor;
        idx = idxVor;
        final kurz = mass.legHeight < specMinLegHeight;
        notiere(
            repairStepLegsApart,
            '${(mass.legSeparation * 100).round()} %',
            'verworfen',
            RepairOrigin.prompt,
            'Der Schnitt brachte die Trennung von '
                '${(mass.legSeparation * 100).round()} auf '
                '${(probeMass.legSeparation * 100).round()} % und den '
                'Schritt von ${mass.legHeight.toStringAsFixed(2)} auf '
                '${probeMass.legHeight.toStringAsFixed(2)} Studs – '
                'zurückgenommen. '
                '${kurz ? 'Bei einem Schritt von '
                    '${mass.legHeight.toStringAsFixed(2)} Studs (Bein '
                    'mindestens ${specMinLegHeight.toStringAsFixed(1)}) '
                    'ist das kein Saum vor zwei Beinen, sondern ein '
                    'Rumpf, der bis kurz über den Boden reicht; ein '
                    'Schnitt macht die Beine nicht länger. Ins Motiv: '
                    '„hips at about two fifths of body height, two separate legs '
                    'with a gap between '
                    'the thighs", ins Negativ „short legs".' : 'Was die '
                    'Beine verbindet, ist kein Saum, den ein '
                    'Streifenschnitt löst. Ins Motiv: „gap between the '
                    'thighs".'}');
      } else {
        notiere(
            repairStepLegsApart,
            '${(mass.legSeparation * 100).round()} %',
            'freigeschnitten',
            RepairOrigin.app,
            'Dreiecke im Mittelstreifen unter der Hüfte entfernt; die '
                'Löcher schließt die Nachbearbeitung mit echter '
                'Triangulierung. Probe: Trennung '
                '${(probeMass.legSeparation * 100).round()} %, Schritt '
                '${probeMass.legHeight.toStringAsFixed(2)} Studs.');
        if (klemmeVerworfen) {
          notiere(repairStepHem, 'Trichter', 'nicht geklemmt', RepairOrigin.prompt,
              '$klemmFlips Dreiecke hätten sich umgedreht – unter der '
                  'Hüfte sitzt hier Bauch oder Hose, kein Saum; die '
                  'Klemme ist zurückgenommen.');
        } else {
          notiere(repairStepHem, 'Trichter', 'geklemmt', RepairOrigin.app,
              'Unter der Hüfte auf höchstens '
                  '${repairLegClampRadius.toStringAsFixed(2)} Studs '
                  'Abstand zur Beinmitte gezogen – ohne eine Fläche zu '
                  'löschen.');
        }
      }
    } else {
      notiere(repairStepLegsApart,
          '${(mass.legSeparation * 100).round()} %', '–',
          RepairOrigin.prompt,
          'Unter der Hüfte sind nirgends zwei Inseln zu finden – das '
              'ist ein Block bis zu den Füßen, kein Saum.');
    }
  }

  // 5. Beinbreite.
  if (mass.legWidth > marketplaceMaxLegWidth) {
    if (mass.legWidth <= repairLegWidth.repairableTo &&
        zonen.legCenters.isNotEmpty) {
      final kopie = Float32List.fromList(pos);
      _beinBreite(pos, zonen.hipY, zonen.legCenters,
          repairLegWidth.goal / mass.legWidth);
      final flips = countFlippedTriangles(kopie, pos, idx);
      if (flips > flipGrenze()) {
        pos.setAll(0, kopie);
        notiere(repairStepLegWidth, mass.legWidth.toStringAsFixed(2),
            'verworfen', RepairOrigin.prompt,
            '$flips Dreiecke hätten sich beim Schmälern umgedreht – '
                'die Beine sind hier nicht zwei Röhren um je eine '
                'Mitte. Ins Motiv: „two separate legs".');
      } else {
        notiere(
            repairStepLegWidth,
            mass.legWidth.toStringAsFixed(2),
            repairLegWidth.goal.toStringAsFixed(2),
            RepairOrigin.app,
            'Jedes Bein um seine eigene Mitte geschmälert.');
      }
    } else {
      notiere(repairStepLegWidth, mass.legWidth.toStringAsFixed(2), '–',
          RepairOrigin.prompt,
          'Über ${repairLegWidth.repairableTo.toStringAsFixed(2)} '
              'bleibt vom Bein nichts übrig, was noch wie eines '
              'aussieht.');
    }
  }

  // 6. A-Pose.
  if (mass.looksLikeTPose) {
    final kopie = Float32List.fromList(pos);
    _armeSenken(pos, zonen.shoulderY, zonen.headWidth * 0.9,
        repairArmDrop, zonen.height * 0.04);
    final flips = countFlippedTriangles(kopie, pos, idx);
    if (flips > flipGrenze()) {
      pos.setAll(0, kopie);
      notiere(
          repairStepPose,
          'T (breiteste Stelle auf '
              '${(mass.widestBandHeight * 100).round()} % der Höhe)',
          'verworfen',
          RepairOrigin.prompt,
          '$flips Dreiecke hätten sich beim Senken der Arme umgedreht '
              '– die Schulter lässt sich hier nicht als Gelenk fassen. '
              'Die A-Pose bestellt jeder Marktplatz-Lauf selbst (Auto '
              'Setup 6): die Ansichten als eigenen Zusatz, der '
              'Text→3D-Weg als Satz „upright A-pose". Steht hier '
              'trotzdem eine T-Pose, hat das Bildmodell sie nicht '
              'umgesetzt – das ändert kein Zusatz im Motiv, nur ein '
              'neuer Lauf.');
    } else {
      notiere(
          repairStepPose,
          'T (breiteste Stelle auf '
              '${(mass.widestBandHeight * 100).round()} % der Höhe)',
          'A (${repairArmDrop.round()}°)',
          RepairOrigin.app,
          'Um das Schultergelenk gedreht, weicher Anlauf zum Rumpf. '
              'Waagerechte Arme hat der Segmentierer zweimal dem Kopf '
              'und dem Rumpf zugeschlagen.');
    }
  }

  // 6b. I-Pose: Arme abspreizen.
  //
  // Schritt 6 kannte nur die T-Pose und ließ die I-Pose stehen - dabei
  // ist sie der Fall, den Auto Setup ausdrücklich schlechter nennt
  // („Character bodies with I-pose may yield lower quality results").
  // Der Bericht riet stattdessen zum Prompt, obwohl der die A-Pose
  // längst zweimal bestellt; das Bildmodell hatte sie nur nicht
  // geliefert.
  //
  // Gedreht wird um die Achsel (Rumpfkante auf Schulterhöhe), nach
  // außen statt nach unten - dieselbe Rechnung wie beim Senken, nur
  // mit negativem Winkel.
  //
  // Gemessen wird **hier** neu statt [mass] zu benutzen: Die Schritte
  // davor haben die Figur verändert, und wer nach alten Zahlen dreht,
  // dreht am falschen Ort. Und was dabei herauskommt, wird
  // nachgemessen: Das Abspreizen hebt die Arme, und damit wandert das
  // breiteste Band nach oben - an Testfiguren aus Quadern hat das
  // Rumpf- und Beinhöhe verschoben. Wird irgendeine Vorgabe dabei
  // schlechter, gilt der Schritt als misslungen und wird
  // zurückgenommen: eine Warnung weniger ist keinen neuen Fehler wert.
  if (!mass.looksLikeTPose) {
    final davor = measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
    final steht = davor.width - davor.spanTorsoWidth;
    // Hier stand zusätzlich „nur wenn überhaupt etwas absteht". Das
    // war die Bedingung, die den einzigen Fall ausschloss, für den es
    // den Schritt gibt: Bei einer I-Pose steht eben nichts ab (0,04
    // Studs an der echten Figur).
    if (!davor.armsFree && davor.spanTorsoWidth > 0) {
      // Die offenen Regeln, nicht ihre **Anzahl**.
      //
      // Gezählt wurde einmal, und das ging so aus: Das Abspreizen
      // schloss „arme_frei" und riss dafür „bein_hoehe" auf - eine
      // offene Vorgabe vorher, eine nachher, der Zähler sagte „gleich
      // geblieben", und die Figur kam mit einem neuen Fehler heraus.
      // Verglichen werden deshalb die Namen: Eine Regel, die vorher
      // hielt, darf nicht brechen.
      final offenVorher = checkMarketplaceFigure(davor, scale: scale)
          .where((f) => f.level != MarketplaceLevel.ok)
          .map((f) => f.id)
          .toSet();
      final urzustand = Float32List.fromList(pos);
      // Erst suchen, dann drehen.
      //
      // Wo die Achsel liegt, wurde hier zweimal **geraten** – halbe
      // Rumpfbreite oder Kopfbreite mal 0,9 – und alles außerhalb
      // gedreht. Bei einer I-Pose ist die gemessene Rumpfbreite aber
      // die ganze Silhouette, weil Arm und Rumpf eine Insel bilden;
      // beide Schätzungen lagen deshalb mitten im Mantel. [_findeArme]
      // sieht stattdessen im Querschnitt nach, wo der Arm als eigene
      // Insel steht, und baut daraus ein Gewichtsfeld.
      final feld = _findeArme(pos, idx, zonen.shoulderY);
      // Die **kleinste** Bewegung, die die Regel erfüllt.
      //
      // Derselbe Grundsatz wie beim Norm-Umbau: Die Regel gilt
      // eingehalten oder nicht; darüber hinaus zu verformen bringt
      // nichts und kostet das Aussehen. Der erste Anlauf nahm die
      // größte Reichweite und kam an einer echten Figur auf 4,98 statt
      // der nötigen 2,12 Studs - eine Armspanne von 6,38 bei 5,00
      // Studs Höhe.
      final noetig = 2 * specMinArmLength / math.sqrt2;
      Float32List? bestes;
      var besteReichweite = steht;
      var besteWinkel = 0.0;
      var besteOffen = offenVorher;
      // Der Riss-Wächter.
      //
      // Gemessen an der sauberen Drehung: Dort werden 0,5 % der Kanten
      // um mehr als die Hälfte länger (die Schulter, die sich mitdreht)
      // und **keine einzige** um mehr als das Dreifache. Ein Riss sieht
      // anders aus - er zieht einzelne Kanten weit auf. Die Grenze
      // liegt deshalb beim Dreifachen, und ein halbes Promille darf es
      // sein.
      final dehnGrenze = math.max(10, idx.length ~/ 2000);
      for (final grad in feld == null
          ? const <double>[]
          : const <double>[
              12.0,
              16.0,
              20.0,
              25.0,
              30.0,
              35.0,
              40.0,
              repairArmSpread
            ]) {
        pos.setAll(0, urzustand);
        _armeAbspreizen(pos, feld!, grad);
        if (countFlippedTriangles(urzustand, pos, idx) > flipGrenze()) {
          continue;
        }
        if (countStretchedEdges(urzustand, pos, idx) > dehnGrenze) continue;
        final n = measureMarketplaceFigure(pos, idx, targetStuds: hoehe);
        final reichweite = n.width - n.spanTorsoWidth;
        final offen = checkMarketplaceFigure(n, scale: scale)
            .where((f) => f.level != MarketplaceLevel.ok)
            .map((f) => f.id)
            .toSet();
        // Drei Bedingungen, alle aus Fehlversuchen gelernt.
        //
        // **Keine neue offene Regel.** Gezählt wurde einmal nur die
        // Anzahl, und das ging so aus: „arme_frei" ging zu,
        // „bein_hoehe" auf, der Zähler sagte „gleich geblieben".
        //
        // **Entweder ganz oder gar nicht.** Hier stand „besser als
        // bisher", und damit nahm der Schritt an einer Testfigur eine
        // Verbesserung von 0,00 auf 0,05 Studs mit: verformt, und die
        // Warnung stand hinterher genauso da. Gemessen wird deshalb an
        // der Regel selbst - sie muss zugehen.
        //
        // **Der Rumpf bleibt, wie er ist.** Das war der eigentliche
        // Fehler des ersten Anlaufs: Weil der Mantel mitging, wuchs
        // die Rumpfbreite genauso schnell wie die Spanne, der Abstand
        // blieb klein, und die Suche verformte immer weiter. Hier
        // standen vorher drei Bedingungen für Kopf-, Rumpf- und
        // Beinhöhe. Die messen inzwischen nur noch sich selbst: Was
        // kein Armgewicht trägt, wird gar nicht angefasst, die
        // Geometrie dort ist Byte für Byte dieselbe - nur die
        // Bänder-Messung liest sie anders, wenn sich die Silhouette
        // daneben ändert. An einer Testfigur verwarf das eine
        // einwandfreie Drehung, bei der alle Regeln zugingen.
        if (offen.difference(offenVorher).isNotEmpty ||
            offen.contains(marketplaceRuleArmsFree) ||
            n.spanTorsoWidth > davor.spanTorsoWidth + hoehe * 0.02) {
          continue;
        }
        besteReichweite = reichweite;
        besteWinkel = grad;
        besteOffen = offen;
        bestes = Float32List.fromList(pos);
        break;
      }
      if (bestes == null) {
        pos.setAll(0, urzustand);
        notiere(
            repairStepArmsApart,
            '${steht.toStringAsFixed(2)} Studs',
            'verworfen',
            RepairOrigin.prompt,
            feld == null
                ? 'Im Querschnitt steht auf keiner Seite ein Arm als '
                    'eigene Insel neben dem Rumpf – er klebt über die '
                    'ganze Höhe daran, oder es ist keiner. Was hier '
                    'nicht zu messen ist, lässt sich auch nicht sauber '
                    'bewegen: Der erste Anlauf hat an dieser Stelle '
                    'geraten und den halben Mantel mitgedreht. Die '
                    'A-Pose bestellt der Marktplatz-Lauf ohnehin '
                    'zweimal; hilft das nicht, hilft nur ein neuer Lauf.'
                : 'Die Arme sind gefunden (von '
                    '${feld.armUnten.toStringAsFixed(2)} bis '
                    '${feld.armOben.toStringAsFixed(2)} in Modellmaßen), '
                    'aber selbst um ${repairArmSpread.round()}° '
                    'abgespreizt bleiben sie unter den geforderten '
                    '${noetig.toStringAsFixed(2)} Studs Abstand – oder '
                    'die Drehung reißt anderswo etwas auf. Der Abstand '
                    'ist die Armlänge mal cos 45°: So kurze Arme werden '
                    'nur im Bild länger, nicht hier.');
      } else {
        pos.setAll(0, bestes);
        notiere(
            repairStepArmsApart,
            '${steht.toStringAsFixed(2)} Studs',
            '${besteReichweite.toStringAsFixed(2)} Studs',
            RepairOrigin.app,
            'Um ${besteWinkel.round()}° um das Schultergelenk nach '
                'außen gedreht, anteilig nach einem gemessenen '
                'Gewichtsfeld – der Rumpf bleibt dabei stehen. Offene '
                'Vorgaben ${offenVorher.length} → ${besteOffen.length}, '
                'keine neue. Damit steht der geforderte Abstand von '
                '${noetig.toStringAsFixed(2)} Studs.',
            fixed: true);
      }
    }
  }

  // Zurückbauen und die Geometrie in Ordnung bringen: Der Schnitt hat
  // Löcher hinterlassen, und die Wicklung muss stimmen.
  arbeit = _bau(pos, uvs, idx, textur);
  final geheilt = fixGlbForRoblox(arbeit, closeHoles: true, fixWinding: true);
  arbeit = geheilt.glb;
  if (geheilt.report.filledHoles > 0) {
    notiere(repairStepHoles, '${geheilt.report.filledHoles}', '0',
        RepairOrigin.app,
        '${geheilt.report.addedTriangles} Dreiecke ergänzt, keine neuen '
            'Punkte.');
  }

  // 7. Dezimierung – nach der Geometrie, vor den Gesichtsteilen.
  if (decimate) {
    final vorher = await glbTriangleCount(arbeit);
    // Mit Platz für das Gesicht: Der Einbau fügt bis zu
    // [faceSculptTriangleBudget] Dreiecke hinzu, und die müssen unter
    // dem Ziel bleiben – sonst käme die Figur mit 8.300 zurück.
    final ziel = repairTriangleGoal -
        (sculptFace ? faceSculptTriangleBudget : 0);
    if (vorher > ziel) {
      arbeit = await decimateGlb(arbeit, ziel);
      final nachher = await glbTriangleCount(arbeit);
      notiere(repairStepDecimate, '$vorher', '$nachher', RepairOrigin.app,
          'Auto Setup reduziert selbst nicht; bei 9.627 bekam jede '
              'Gliedmaße 2.304 bei einem Budget von 1.248.'
              '${sculptFace ? ' Ziel $ziel statt $repairTriangleGoal, '
                  'damit das Gesicht mit bis zu '
                  '$faceSculptTriangleBudget Dreiecken noch Platz hat.' : ''}');
    }
  }

  // 7b. Das Gesicht ins Kopfnetz: Augenhöhlen mit Lidgrat, Mundhöhle
  // mit Lippengrat – nach der Dezimierung (sonst glättete sie die
  // Höhlen wieder weg) und vor den Teilen (sonst verschmölzen die mit
  // dem Kopf).
  // Ob am Ende echte Höhlen im Kopfnetz stehen – davon hängt ab, was
  // über die Gesichtsteile zu sagen ist.
  var hoehlenDa = false;
  if (sculptFace) {
    try {
      final gesicht =
          await sculptFaceIntoHead(arbeit, proportions: sculptProportions);
      arbeit = gesicht.glb;
      final r = gesicht.report;
      hoehlenDa = r.after.hasFace;
      notiere(
          repairStepFaceSculpt,
          r.before.hasFace ? 'Höhlen da' : 'keine Höhlen',
          // Die Zahlen, auf denen das Urteil beruht - nicht andere.
          //
          // Hier standen leftEyeDepth und mouthDepth: die Ring-Messung
          // (Rand minus Mitte). Entschieden wird aber über eyeBulge
          // und mouthBulge, den Rest gegen die an das Gesicht
          // angepasste Fläche. An einer echten Figur stand deshalb in
          // einer **grünen** Zeile „Höhlen -0,66 tief" - eine negative
          // Tiefe, also ein Augapfel, in einer Zeile, die Höhlen
          // bescheinigt. Zwei Messungen in einem Satz, und der Leser
          // konnte nicht wissen, welche zählt. eyeBulge ist bei einer
          // Höhle negativ, deshalb das Minus.
          r.after.hasFace
              ? 'Höhlen ${(-r.after.eyeBulge).toStringAsFixed(2)} / '
                  '${(-r.after.mouthBulge).toStringAsFixed(2)} tief'
              : 'zu flach',
          r.after.hasFace ? RepairOrigin.app : RepairOrigin.prompt,
          '+${r.addedTriangles} Dreiecke in ${r.passes} Durchgängen. '
              '${r.notes.join(' ')}');
    } on Exception catch (e) {
      notiere(repairStepFaceSculpt, '–', '–', RepairOrigin.prompt, '$e');
    }
  }

  // 8. Gesichtsteile – zuletzt, damit ihre Dreiecke exakt bleiben.
  if (addFace) {
    try {
      final gesicht = addFaceParts(arbeit);
      arbeit = gesicht.glb;
      notiere(repairStepFaceParts, '0', '${gesicht.report.parts.length}',
          RepairOrigin.app,
          '${gesicht.report.triangles} Dreiecke. '
              '${hoehlenDa ? 'Die Augen sitzen in den Höhlen hinter dem '
                  'Lidgrat. Ob Auto Setup daraus FACS-Posen baut, zeigt '
                  'der Lauf.' : 'Es gibt keine Höhlen im Kopfnetz: Die '
                  'Kugeln sitzen auf der Gesichtsfläche, versenkt und '
                  'sichtbar, aber ohne Vertiefung dahinter. Für die '
                  'FACS-Posen fehlt sie. '
                  '${marketplaceClauseAdvice(marketplaceFaceClause,
                      negative: 'bulging eyes')}'}'
              '${gesicht.report.notes.isEmpty ? '' : ' '
                  '${gesicht.report.notes.join(' ')}'}');
    } on Exception catch (e) {
      notiere(repairStepFaceParts, '0', '0', RepairOrigin.prompt, '$e');
    }
  }

  // 9. Nachmessen.
  final nach = await parseGlbForPreview(arbeit);
  final endmass = measureMarketplaceFigure(nach.positions, nach.indices,
      targetStuds: hoehe);
  nach.dispose();
  for (final f in checkMarketplaceFigure(endmass, scale: scale)) {
    if (f.level == MarketplaceLevel.ok) continue;
    notiere('Nachmessung: ${f.title}', '–', 'offen',
        f.origin == MarketplaceOrigin.prompt
            ? RepairOrigin.prompt
            : RepairOrigin.app,
        f.reason,
        fixed: false);
  }

  return RepairResult(arbeit, RepairReport(schritte), studs: hoehe);
}

/// Das Dreiecksziel, ab dem reduziert wird – hier gespiegelt, damit
/// dieser Dienst nicht von der Prüfung abhängt.
const int robloxAutoSetupTrianglesLocal = 7000;
