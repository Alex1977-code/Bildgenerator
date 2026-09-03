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
  const RepairResult(this.glb, this.report);
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
/// Bänder von 2 % der Höhe, wie im Pflichtenheft. Gerechnet wird an
/// Punkten, nicht an Dreiecken: Für Hüfte, Schulter und Beinmitten
/// genügt das, und die Insel-Zählung, für die es nicht genügt, macht
/// [measureMarketplaceFigure].
_Zonen _messeZonen(Float32List pos) {
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
  for (var i = 0; i + 2 < pos.length; i += 3) {
    if (hoehe <= 0) continue;
    final b = (((pos[i + 1] - minY) / hoehe) * bands)
        .floor()
        .clamp(0, bands - 1);
    loX[b] = math.min(loX[b], pos[i]);
    hiX[b] = math.max(hiX[b], pos[i]);
  }
  for (var b = 0; b < bands; b++) {
    breite[b] = loX[b].isFinite ? hiX[b] - loX[b] : 0;
  }

  // Kopf: breitestes Band im obersten Fünftel. Schulter: von dort nach
  // unten das erste Band über dem Anderthalbfachen davon.
  var kopfBand = (bands * 0.8).floor();
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

/// Dreht die Arme aus der Waagerechten nach unten.
///
/// Gedreht wird um das Schultergelenk, jede Seite um ihre eigene
/// Achse, mit weichem Übergang über [weich] Studs zum Rumpf hin –
/// sonst reißt die Schulter.
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

  var mass = measureMarketplaceFigure(pos, idx, targetStuds: targetStuds);
  var zonen = _messeZonen(pos);
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
          'Tiefe',
          mass.depth.toStringAsFixed(2),
          tiefeGrenze.goal.toStringAsFixed(2),
          RepairOrigin.app,
          'Z gestaucht um die Mitte; die Silhouette von vorn bleibt, '
              'die UVs bleiben.');
    } else {
      notiere(
          'Tiefe',
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
            'Hals',
            '${(mass.neckRatio * 100).round()} %',
            'verworfen',
            RepairOrigin.prompt,
            '$flips Dreiecke hätten sich beim Einschnüren umgedreht – '
                'zwischen Kopf und Schulter sitzt hier ein Kragen oder '
                'eine Kapuze, kein Hals. Ins Motiv: „narrow visible '
                'neck between head and shoulders".');
      } else {
        notiere(
            'Hals',
            '${(mass.neckRatio * 100).round()} %',
            '${(repairNeckGoal * 100).round()} %',
            RepairOrigin.app,
            'Radial eingeschnürt, Glockenkurve über ± 6 % der Höhe – '
                'ohne weichen Übergang entsteht eine sichtbare Kante.');
      }
    } else {
      notiere('Hals', '${(mass.neckRatio * 100).round()} %', '–',
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
          targetStuds: targetStuds);
      probe.dispose();
      final besser = probeMass.legSeparation > mass.legSeparation &&
          probeMass.legHeight >= mass.legHeight - 0.05;
      if (!besser) {
        pos = posVor;
        idx = idxVor;
        final kurz = mass.legHeight < specMinLegHeight;
        notiere(
            'Beine getrennt',
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
                    '„sturdy legs a third of body height, gap between '
                    'the thighs", ins Negativ „short legs".' : 'Was die '
                    'Beine verbindet, ist kein Saum, den ein '
                    'Streifenschnitt löst. Ins Motiv: „gap between the '
                    'thighs".'}');
      } else {
        notiere(
            'Beine getrennt',
            '${(mass.legSeparation * 100).round()} %',
            'freigeschnitten',
            RepairOrigin.app,
            'Dreiecke im Mittelstreifen unter der Hüfte entfernt; die '
                'Löcher schließt die Nachbearbeitung mit echter '
                'Triangulierung. Probe: Trennung '
                '${(probeMass.legSeparation * 100).round()} %, Schritt '
                '${probeMass.legHeight.toStringAsFixed(2)} Studs.');
        if (klemmeVerworfen) {
          notiere('Saum', 'Trichter', 'nicht geklemmt', RepairOrigin.prompt,
              '$klemmFlips Dreiecke hätten sich umgedreht – unter der '
                  'Hüfte sitzt hier Bauch oder Hose, kein Saum; die '
                  'Klemme ist zurückgenommen.');
        } else {
          notiere('Saum', 'Trichter', 'geklemmt', RepairOrigin.app,
              'Unter der Hüfte auf höchstens '
                  '${repairLegClampRadius.toStringAsFixed(2)} Studs '
                  'Abstand zur Beinmitte gezogen – ohne eine Fläche zu '
                  'löschen.');
        }
      }
    } else {
      notiere('Beine getrennt',
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
        notiere('Beinbreite', mass.legWidth.toStringAsFixed(2),
            'verworfen', RepairOrigin.prompt,
            '$flips Dreiecke hätten sich beim Schmälern umgedreht – '
                'die Beine sind hier nicht zwei Röhren um je eine '
                'Mitte. Ins Motiv: „two separate legs".');
      } else {
        notiere(
            'Beinbreite',
            mass.legWidth.toStringAsFixed(2),
            repairLegWidth.goal.toStringAsFixed(2),
            RepairOrigin.app,
            'Jedes Bein um seine eigene Mitte geschmälert.');
      }
    } else {
      notiere('Beinbreite', mass.legWidth.toStringAsFixed(2), '–',
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
          'Pose',
          'T (breiteste Stelle auf '
              '${(mass.widestBandHeight * 100).round()} % der Höhe)',
          'verworfen',
          RepairOrigin.prompt,
          '$flips Dreiecke hätten sich beim Senken der Arme umgedreht '
              '– die Schulter lässt sich hier nicht als Gelenk fassen. '
              'Die A-Pose gehört in den Prompt.');
    } else {
      notiere(
          'Pose',
          'T (breiteste Stelle auf '
              '${(mass.widestBandHeight * 100).round()} % der Höhe)',
          'A (${repairArmDrop.round()}°)',
          RepairOrigin.app,
          'Um das Schultergelenk gedreht, weicher Anlauf zum Rumpf. '
              'Waagerechte Arme hat der Segmentierer zweimal dem Kopf '
              'und dem Rumpf zugeschlagen.');
    }
  }

  // Zurückbauen und die Geometrie in Ordnung bringen: Der Schnitt hat
  // Löcher hinterlassen, und die Wicklung muss stimmen.
  arbeit = _bau(pos, uvs, idx, textur);
  final geheilt = fixGlbForRoblox(arbeit, closeHoles: true, fixWinding: true);
  arbeit = geheilt.glb;
  if (geheilt.report.filledHoles > 0) {
    notiere('Löcher', '${geheilt.report.filledHoles}', '0',
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
      notiere('Dreiecke', '$vorher', '$nachher', RepairOrigin.app,
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
  if (sculptFace) {
    try {
      final gesicht =
          await sculptFaceIntoHead(arbeit, proportions: sculptProportions);
      arbeit = gesicht.glb;
      final r = gesicht.report;
      notiere(
          'Gesicht im Kopfnetz',
          r.before.hasFace ? 'Höhlen da' : 'keine Höhlen',
          r.after.hasFace
              ? 'Höhlen ${r.after.leftEyeDepth.toStringAsFixed(2)} / '
                  '${r.after.mouthDepth.toStringAsFixed(2)} tief'
              : 'zu flach',
          r.after.hasFace ? RepairOrigin.app : RepairOrigin.prompt,
          '+${r.addedTriangles} Dreiecke in ${r.passes} Durchgängen. '
              '${r.notes.join(' ')}');
    } on Exception catch (e) {
      notiere('Gesicht im Kopfnetz', '–', '–', RepairOrigin.prompt, '$e');
    }
  }

  // 8. Gesichtsteile – zuletzt, damit ihre Dreiecke exakt bleiben.
  if (addFace) {
    try {
      final gesicht = addFaceParts(arbeit);
      arbeit = gesicht.glb;
      notiere('Gesichtsteile', '0', '${gesicht.report.parts.length}',
          RepairOrigin.app,
          '${gesicht.report.triangles} Dreiecke. '
              '${sculptFace ? 'Die Augen sitzen in den Höhlen hinter '
                  'dem Lidgrat. Ob Auto Setup daraus FACS-Posen baut, '
                  'zeigt der Lauf.' : 'Ohne Lider und Lippen im '
                  'Kopfnetz baut Auto Setup keine FACS-Posen – dafür '
                  'ist „Gesicht ins Kopfnetz bauen" da.'}');
    } on Exception catch (e) {
      notiere('Gesichtsteile', '0', '0', RepairOrigin.prompt, '$e');
    }
  }

  // 9. Nachmessen.
  final nach = await parseGlbForPreview(arbeit);
  final endmass = measureMarketplaceFigure(nach.positions, nach.indices,
      targetStuds: targetStuds);
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

  return RepairResult(arbeit, RepairReport(schritte));
}

/// Das Dreiecksziel, ab dem reduziert wird – hier gespiegelt, damit
/// dieser Dienst nicht von der Prüfung abhängt.
const int robloxAutoSetupTrianglesLocal = 7000;
