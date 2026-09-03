/// Das Gesicht nachträglich ins Kopfnetz bauen: Augenhöhlen mit
/// Lidgrat, Mundhöhle mit Lippengrat.
///
/// **Warum.** Fünf Läufe durch Roblox' Auto Setup haben entschieden,
/// was der dynamische Kopf braucht: **Höhlen im Kopfnetz**, nicht
/// eigene Netze davor. Augen und Zähne als separate Volumen ergaben
/// „Cannot detect mouth open / left eye close expression" – die
/// FACS-Posen bewegen die Lider und die Lippen, und ohne Vertiefung
/// dahinter sieht man beim Schließen und Öffnen keinen Unterschied.
/// Ob Tripo aus „eye sockets with eyelids" Geometrie macht, ist nicht
/// verlässlich. Also baut die App sie selbst, nach dem Lauf, vor den
/// Gesichtsteilen.
///
/// **Was passiert.** Zwei Eingriffe, beide rein geometrisch:
///
/// 1. **Verfeinern, wo es nötig ist.** Ein Kopf mit 1.500 Dreiecken
///    hat um das Auge herum vielleicht acht. Aus acht Dreiecken wird
///    keine Höhle mit Rand. Deshalb werden die Dreiecke im
///    Gesichtsbereich geteilt – **konform**: Jede geteilte Kante
///    teilt auch das Nachbardreieck, sonst entstehen T-Stöße, und die
///    reißen die Hülle. Ein Dreieck mit einer markierten Kante wird
///    zu zwei, mit zwei zu drei, mit drei zu vier. Das läuft in
///    Durchgängen, bis die Kanten kurz genug sind oder das Budget
///    erreicht ist.
/// 2. **Verschieben.** Punkte um das Augenzentrum wandern nach hinten
///    (die Höhle), Punkte am Rand darum leicht nach vorn (der
///    Lidgrat). Dasselbe elliptisch für den Mund. Verschoben wird
///    **nur entlang Z**: Die Verschiebung hängt allein von x und y ab,
///    deshalb bewegen sich doppelte Punkte an UV-Nähten gleich, und
///    die Hülle bleibt geschlossen. Nach dem Versatz entlang der
///    Normalen sähe eine Naht anders aus als ihr Gegenstück.
///
/// **Was es nicht ist.** Ein Lidgrat ist kein Überhang. Ein echtes
/// Oberlid hängt über den Augapfel; das lässt sich durch Verschieben
/// vorhandener Punkte nicht bauen. Ob Auto Setup aus Höhle plus Grat
/// FACS-Posen macht, entscheidet Lauf 6 – hier steht die beste
/// Näherung, die ohne neue Topologie geht.
///
/// **Reihenfolge.** Erst Höhlen, dann `addFaceParts`: Die Teile
/// suchen die Gesichtsfläche per Strahl von vorn, und nach dem
/// Eingriff treffen sie den Höhlenboden – das Auge sitzt dann in der
/// Höhle, hinter dem Grat. Umgekehrt würde die Verfeinerung die
/// Teile mit dem Kopf zu einem Netz verschmelzen, und Auto Setup
/// erkennt sie an ihrer Eigenständigkeit.
///
/// **Maße** als Anteile der Kopfbreite B und Kopfhöhe H, wie bei den
/// Gesichtsteilen: Höhlenradius 0,10 × B (das Auge hat 0,06 × B),
/// Höhlentiefe 0,06 × B, Grat 0,015 × B hoch. Mund: Halbachsen
/// 0,16 × B und 0,045 × H, Mitte bei 34 % von H – das umschließt
/// beide Zahnreihen (36 % und 32 %), Tiefe 0,08 × B.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart' show joinGlb, parseGlbForPreview, splitGlb;
import 'local_3d.dart';
import 'mesh_budget.dart' show firstGlbTexturePng;
import 'roblox_face_parts.dart'
    show FaceProportions, faceFrontHitZ, faceMeshNames;

/// Wie viele Dreiecke der Eingriff höchstens hinzufügt.
///
/// Die Zahl gehört ins Dreiecksbudget der Figur: Wer für den
/// Marktplatz mit face_limit 7.000 erzeugt und danach das Gesicht
/// einbaut, landet bei 8.500. Deshalb ziehen die Marktplatz-Vorgabe
/// und die Reparatur diesen Betrag vorher ab – erzeugt und dezimiert
/// wird auf 7.000 minus 1.500, und der Eingriff füllt auf.
const int faceSculptTriangleBudget = 1500;

/// Die Anteile, aus denen Höhlen und Grate gebaut werden.
class FaceSculptProportions {
  const FaceSculptProportions({
    this.socketRadius = 0.10,
    this.socketDepth = 0.06,
    this.lidRise = 0.015,
    this.lidWidth = 0.5,
    this.mouthCenter = 0.34,
    this.mouthHalfWidth = 0.16,
    this.mouthHalfHeight = 0.045,
    this.mouthDepth = 0.08,
    this.lipRise = 0.015,
    this.lipWidth = 0.4,
    this.targetEdge = 0.035,
    this.maxPasses = 3,
    this.maxExtraTriangles = faceSculptTriangleBudget,
  });

  /// Radius der Augenhöhle, × B.
  final double socketRadius;

  /// Tiefe der Augenhöhle in der Mitte, × B.
  final double socketDepth;

  /// Höhe des Lidgrats über der alten Fläche, × B.
  final double lidRise;

  /// Breite des Lidgrats nach außen, × [socketRadius].
  final double lidWidth;

  /// Höhe der Mundmitte im Kopfband, × H.
  final double mouthCenter;

  /// Halbe Mundbreite, × B.
  final double mouthHalfWidth;

  /// Halbe Mundhöhe, × H.
  final double mouthHalfHeight;

  /// Tiefe der Mundhöhle, × B.
  final double mouthDepth;

  /// Höhe des Lippengrats, × B.
  final double lipRise;

  /// Breite des Lippengrats, als Anteil der Halbachsen.
  final double lipWidth;

  /// Ziel-Kantenlänge im Gesichtsbereich, × B.
  final double targetEdge;

  /// Höchstzahl Verfeinerungs-Durchgänge.
  final int maxPasses;

  /// Wie viele Dreiecke die Verfeinerung höchstens hinzufügen darf.
  final int maxExtraTriangles;
}

/// Was an einem Gesicht nachgemessen wurde – vor oder nach dem
/// Eingriff, immer per Strahl von vorn.
class FaceCavities {
  const FaceCavities({
    required this.headWidth,
    required this.headHeight,
    required this.leftEyeDepth,
    required this.rightEyeDepth,
    required this.mouthDepth,
    required this.eyeCenters,
  });

  final double headWidth;
  final double headHeight;

  /// Tiefe der Höhle: Rand minus Mitte. Auf einer konvexen Fläche
  /// ohne Höhle ist das null oder negativ.
  final double leftEyeDepth;
  final double rightEyeDepth;
  final double mouthDepth;

  /// Die beiden Augenzentren (x, y) – für den Bericht.
  final List<List<double>> eyeCenters;

  /// Ab wann eine Vertiefung als Höhle gilt: 3 % der Kopfbreite.
  static const double minDepthOfHeadWidth = 0.03;

  bool get hasEyeSockets =>
      headWidth > 0 &&
      leftEyeDepth >= headWidth * minDepthOfHeadWidth &&
      rightEyeDepth >= headWidth * minDepthOfHeadWidth;

  bool get hasMouthCavity =>
      headWidth > 0 && mouthDepth >= headWidth * minDepthOfHeadWidth;

  bool get hasFace => hasEyeSockets && hasMouthCavity;
}

class FaceSculptReport {
  const FaceSculptReport({
    required this.before,
    required this.after,
    required this.trianglesBefore,
    required this.trianglesAfter,
    required this.passes,
    required this.notes,
  });

  final FaceCavities before;
  final FaceCavities after;
  final int trianglesBefore;
  final int trianglesAfter;
  final int passes;
  final List<String> notes;

  int get addedTriangles => trianglesAfter - trianglesBefore;

  String get text => [
        'Gesicht im Kopfnetz',
        '  Augenhöhlen: links ${_t(before.leftEyeDepth)} → '
            '${_t(after.leftEyeDepth)}, rechts ${_t(before.rightEyeDepth)} → '
            '${_t(after.rightEyeDepth)} Studs tief',
        '  Mundhöhle: ${_t(before.mouthDepth)} → ${_t(after.mouthDepth)} '
            'Studs tief',
        '  Dreiecke: $trianglesBefore → $trianglesAfter '
            '(+$addedTriangles, $passes Durchgänge)',
        ...notes,
      ].join('\n');

  static String _t(double v) => v.toStringAsFixed(3);
}

class FaceSculptResult {
  const FaceSculptResult(this.glb, this.report);
  final Uint8List glb;
  final FaceSculptReport report;
}

/// Baut Augenhöhlen und Mundhöhle ins Kopfnetz.
///
/// Erwartet eine vorbereitete Figur (Zehen nach +Z, Füße auf y = 0)
/// **ohne** die fünf Gesichtsteile – die kommen danach. Wirft, wenn
/// sie schon da sind: Nach der Verfeinerung wären sie mit dem Kopf
/// verschmolzen.
Future<FaceSculptResult> sculptFaceIntoHead(
  Uint8List glb, {
  double headTopFraction = 0.2,
  FaceProportions faceProportions = const FaceProportions(),
  FaceSculptProportions proportions = const FaceSculptProportions(),
}) async {
  final json = splitGlb(glb).json;
  final namen = [
    for (final mesh in ((json['meshes'] as List?) ?? const []).cast<Map>())
      mesh['name'] as String?,
  ];
  final schonDa = faceMeshNames.where(namen.contains).toList();
  if (schonDa.isNotEmpty) {
    throw Exception('Die Gesichtsteile ${schonDa.join(', ')} stehen '
        'schon in der Datei. Erst die Höhlen bauen, dann die Teile – '
        'sonst verschmelzen sie mit dem Kopf.');
  }

  final vorschau = await parseGlbForPreview(glb);
  var pos = Float32List.fromList(vorschau.positions);
  var idx = vorschau.indices.toList();
  var uvs = vorschau.uvs?.toList();
  vorschau.dispose();
  final textur = firstGlbTexturePng(glb);
  final notes = <String>[];

  final kopf = _messeKopf(pos, idx, headTopFraction, faceProportions);
  if (kopf == null) {
    throw Exception('Im oberen Fünftel liegt keine Geometrie – dort '
        'müsste der Kopf sein.');
  }
  final vorher = _messeHoehlen(pos, idx, kopf, proportions);
  final dreieckeVorher = idx.length ~/ 3;

  // Schon da? Dann nichts anfassen. Eine vorbereitete Figur kommt
  // über die Reparatur ein zweites Mal hier vorbei, und ein zweiter
  // Eingriff gräbe die Höhlen doppelt tief.
  if (vorher.hasFace) {
    return FaceSculptResult(
      glb,
      FaceSculptReport(
        before: vorher,
        after: vorher,
        trianglesBefore: dreieckeVorher,
        trianglesAfter: dreieckeVorher,
        passes: 0,
        notes: const [
          'Augenhöhlen und Mundhöhle sind schon da – nichts verändert.',
        ],
      ),
    );
  }

  // Augen als Kugeln aus dem Kopf: Bei der ersten Figur mit dem
  // Marktplatz-Schwanz standen sie 0,38 Studs vor der Gesichtsfläche
  // (Kopfbreite 1,84). In einen Buckel lässt sich keine Höhle
  // schneiden – die Verschiebung macht ihn nur flacher, und das Budget
  // ist vorher aufgebraucht. Das gehört ins Motiv, nicht hierher.
  final buckel = -kopf.width * 0.1;
  if (vorher.leftEyeDepth < buckel && vorher.rightEyeDepth < buckel) {
    notes.add('Die Augen stehen als Kugeln aus dem Kopf '
        '(${(-vorher.leftEyeDepth).toStringAsFixed(2)} / '
        '${(-vorher.rightEyeDepth).toStringAsFixed(2)} Studs vor der '
        'Gesichtsfläche): In einen Buckel lässt sich keine Höhle '
        'schneiden, die Verschiebung macht ihn nur flacher. Ins Motiv '
        '„eyes sunk into the head", ins Negativ „bulging eyes".');
  }

  // 1. Verfeinern.
  final b = kopf.width;
  final zielKante = proportions.targetEdge * b;
  var durchgaenge = 0;
  while (durchgaenge < proportions.maxPasses) {
    final region = _regionDreiecke(pos, idx, kopf, proportions);
    if (region.isEmpty) break;
    // Geteilt wird nur, was noch zu grob ist. Ein Tripo-Kopf hat im
    // Gesicht hunderte Dreiecke, die schon fein genug sind – die
    // mitzuteilen kostete das Budget, bevor der erste Durchgang lief.
    final zuGrob = <int>[];
    var laengste = 0.0;
    for (final t in region) {
      final l = _laengsteKante(pos, idx, t);
      laengste = math.max(laengste, l);
      if (l > zielKante) zuGrob.add(t);
    }
    if (zuGrob.isEmpty) break;
    // Schlimmstenfalls drei neue Dreiecke je geteiltem Dreieck. Passt
    // nicht alles ins Budget, kommen die **gröbsten zuerst** dran –
    // ein halber Durchgang mit den größten Dreiecken bringt mehr als
    // gar keiner. Die Nachbarn mit einer oder zwei markierten Kanten
    // kommen obendrauf; das darf leicht überziehen.
    final platz =
        (proportions.maxExtraTriangles - (idx.length ~/ 3 - dreieckeVorher)) ~/
            3;
    if (platz <= 0) {
      notes.add('Verfeinerung nach $durchgaenge Durchgängen beendet: '
          'Das Budget von ${proportions.maxExtraTriangles} zusätzlichen '
          'Dreiecken ist ausgeschöpft. Längste Kante im Gesicht noch '
          '${laengste.toStringAsFixed(3)} bei Ziel '
          '${zielKante.toStringAsFixed(3)}.');
      break;
    }
    var auswahl = zuGrob;
    if (zuGrob.length > platz) {
      final sortiert = [...zuGrob]..sort((x, y) =>
          _laengsteKante(pos, idx, y).compareTo(_laengsteKante(pos, idx, x)));
      auswahl = sortiert.take(platz).toList();
      notes.add('Durchgang ${durchgaenge + 1}: nur ${auswahl.length} von '
          '${zuGrob.length} zu groben Dreiecken geteilt, die größten '
          'zuerst – mehr passt nicht ins Budget von '
          '${proportions.maxExtraTriangles}.');
    }
    final geteilt = _teileKonform(pos, idx, uvs, auswahl);
    pos = geteilt.$1;
    idx = geteilt.$2;
    uvs = geteilt.$3;
    durchgaenge++;
  }

  // 2. Verschieben – nur entlang Z, siehe oben.
  _verschiebe(pos, kopf, proportions);

  final nachher = _messeHoehlen(pos, idx, kopf, proportions);
  final soup = _soup(pos, idx);
  for (final (name, x) in [
    ('links', kopf.centerX - kopf.eyeX),
    ('rechts', kopf.centerX + kopf.eyeX),
  ]) {
    if (faceFrontHitZ(soup, x, kopf.eyeY, kopf.bottomY) == null) {
      notes.add('Der Strahl auf das Augenzentrum $name traf keine '
          'Fläche – der Kopf ist dort schmaler als das Kopfband breit, '
          'etwa wegen Haaren oder einem Hut zur Seite. Die Höhle liegt '
          'dann neben dem Gesicht; im Viewer nachsehen.');
    }
  }
  if (!nachher.hasEyeSockets) {
    notes.add('Die Augenhöhlen sind flacher als '
        '${(FaceCavities.minDepthOfHeadWidth * 100).round()} % der '
        'Kopfbreite geworden – meist, weil das Netz im Gesicht zu grob '
        'blieb. Im Viewer nachsehen.');
  }
  if (!nachher.hasMouthCavity) {
    notes.add('Die Mundhöhle ist flacher als '
        '${(FaceCavities.minDepthOfHeadWidth * 100).round()} % der '
        'Kopfbreite geworden. Im Viewer nachsehen.');
  }
  notes.add('Lider und Lippen sind Grate, keine Überhänge – mehr geht '
      'ohne neue Topologie nicht. Ob Auto Setup daraus FACS-Posen '
      'baut, zeigt erst der Lauf.');

  return FaceSculptResult(
    _bau(pos, uvs, idx, textur),
    FaceSculptReport(
      before: vorher,
      after: nachher,
      trianglesBefore: dreieckeVorher,
      trianglesAfter: idx.length ~/ 3,
      passes: durchgaenge,
      notes: notes,
    ),
  );
}

/// Misst, ob ein Kopfnetz Augenhöhlen und eine Mundhöhle hat – auf
/// dem Export-Puffer, per Strahl von vorn.
///
/// Gedacht für die Prüfung: Sie soll am fertigen Netz sagen, ob das
/// Gesicht drin ist, nicht nur, ob die fünf Teile daneben stehen.
/// Null, wenn kein Kopf zu finden ist.
FaceCavities? measureFaceCavities(
  Float32List positions,
  List<int> indices, {
  double headTopFraction = 0.2,
  FaceProportions faceProportions = const FaceProportions(),
  FaceSculptProportions proportions = const FaceSculptProportions(),
}) {
  final kopf = _messeKopf(positions, indices, headTopFraction, faceProportions);
  if (kopf == null) return null;
  return _messeHoehlen(positions, indices, kopf, proportions);
}

/// Dieselbe Datei ohne die fünf Gesichtsteile – für die Messung.
///
/// Stehen die Augen schon in der Datei, trifft der Strahl auf das
/// Augenzentrum den Augapfel statt den Höhlenboden, und die Höhle
/// sähe flacher aus, als sie ist. Die Teile bleiben in der Datei; hier
/// werden nur ihre Primitive für die Messung geleert.
Uint8List withoutFaceMeshes(Uint8List glb) {
  final parts = splitGlb(glb);
  final json = parts.json;
  var geleert = false;
  for (final mesh in ((json['meshes'] as List?) ?? const []).cast<Map>()) {
    if (!faceMeshNames.contains(mesh['name'])) continue;
    mesh['primitives'] = <Map<String, dynamic>>[];
    geleert = true;
  }
  if (!geleert) return glb;
  return joinGlb(json, parts.bin);
}

// ---------------------------------------------------------------------
// Kopf
// ---------------------------------------------------------------------

class _Kopf {
  const _Kopf({
    required this.width,
    required this.height,
    required this.bottomY,
    required this.centerX,
    required this.eyeY,
    required this.mouthY,
    required this.eyeX,
    required this.frontZ,
  });

  final double width;
  final double height;
  final double bottomY;
  final double centerX;
  final double eyeY;
  final double mouthY;

  /// Abstand jedes Auges von der Mitte.
  final double eyeX;

  /// Die Gesichtsfläche auf Augenhöhe – die Vorderseite.
  final double frontZ;
}

_Kopf? _messeKopf(Float32List pos, List<int> idx, double headTopFraction,
    FaceProportions fp) {
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (var i = 1; i < pos.length; i += 3) {
    minY = math.min(minY, pos[i]);
    maxY = math.max(maxY, pos[i]);
  }
  if (!(maxY > minY)) return null;
  final kopfAb = maxY - (maxY - minY) * headTopFraction;
  var minX = double.infinity, maxX = double.negativeInfinity;
  var maxZ = double.negativeInfinity;
  var punkte = 0;
  for (var i = 0; i + 2 < pos.length; i += 3) {
    if (pos[i + 1] < kopfAb) continue;
    punkte++;
    minX = math.min(minX, pos[i]);
    maxX = math.max(maxX, pos[i]);
    maxZ = math.max(maxZ, pos[i + 2]);
  }
  if (punkte == 0) return null;
  final b = maxX - minX;
  final h = maxY - kopfAb;
  final mitteX = (minX + maxX) / 2;
  final augeY = kopfAb + h * fp.eyeHeight;
  // Die Mundmitte liegt zwischen den Zahnreihen – nicht auf der Höhe
  // der Oberzähne, damit die Höhle beide umschließt.
  final mundY = kopfAb + h * ((fp.upperTeethHeight + fp.lowerTeethHeight) / 2);
  final tris = _soup(pos, idx);
  final front = faceFrontHitZ(tris, mitteX, augeY, kopfAb) ?? maxZ;
  return _Kopf(
    width: b,
    height: h,
    bottomY: kopfAb,
    centerX: mitteX,
    eyeY: augeY,
    mouthY: mundY,
    eyeX: b * fp.eyeSeparation,
    frontZ: front,
  );
}

List<double> _soup(Float32List pos, List<int> idx) {
  final out = List<double>.filled(idx.length * 3, 0);
  for (var t = 0; t < idx.length; t++) {
    final v = idx[t] * 3;
    out[t * 3] = pos[v];
    out[t * 3 + 1] = pos[v + 1];
    out[t * 3 + 2] = pos[v + 2];
  }
  return out;
}

// ---------------------------------------------------------------------
// Messen
// ---------------------------------------------------------------------

FaceCavities _messeHoehlen(
    Float32List pos, List<int> idx, _Kopf kopf, FaceSculptProportions p) {
  final tris = _soup(pos, idx);
  final b = kopf.width;
  final r = p.socketRadius * b;

  final a = p.mouthHalfWidth * b;
  final c = p.mouthHalfHeight * kopf.height;
  final augen = [kopf.centerX - kopf.eyeX, kopf.centerX + kopf.eyeX];

  // Liegt ein Ringpunkt in der Höhle des **anderen** Merkmals? Dann
  // misst er dessen Boden, nicht den Rand – der Augenring streift bei
  // diesen Proportionen die Mundhöhle.
  bool imAuge(double x, double y) {
    for (final ex in augen) {
      final dx = x - ex, dy = y - kopf.eyeY;
      if (dx * dx + dy * dy < r * r) return true;
    }
    return false;
  }

  bool imMund(double x, double y) {
    final mx = (x - kopf.centerX) / a, my = (y - kopf.mouthY) / c;
    return mx * mx + my * my < 1;
  }

  double tiefe(double cx, double cy, double rx, double ry,
      bool Function(double, double) fremd) {
    final mitte = faceFrontHitZ(tris, cx, cy, kopf.bottomY);
    if (mitte == null) return 0;
    // Der Rand: acht Strahlen auf einem Ring **auf dem Grat** (1,3 ×
    // Radius). Genommen wird der **niedrigste** Treffer: Bei einer
    // Kapuze landen weiter außen liegende Strahlen auf dem
    // Kapuzenrand weit vorn, und mit dem höchsten Treffer sähe jedes
    // Gesicht unter einer Kapuze nach Höhle aus. Eine echte Höhle hat
    // ihren Rand ringsum auf gleicher Höhe – und der Grat ist der
    // Rand, den die Lider bilden.
    var rand = double.infinity;
    var treffer = 0;
    for (var k = 0; k < 8; k++) {
      final w = k * math.pi / 4;
      final x = cx + rx * math.cos(w), y = cy + ry * math.sin(w);
      if (fremd(x, y)) continue;
      final z = faceFrontHitZ(tris, x, y, kopf.bottomY);
      if (z == null) continue;
      treffer++;
      rand = math.min(rand, z);
    }
    if (treffer < 5) return 0;
    return rand - mitte;
  }

  const ring = 1.3;
  final links = tiefe(augen[0], kopf.eyeY, r * ring, r * ring, imMund);
  final rechts = tiefe(augen[1], kopf.eyeY, r * ring, r * ring, imMund);
  final mund = tiefe(kopf.centerX, kopf.mouthY, a * ring, c * ring, imAuge);
  return FaceCavities(
    headWidth: b,
    headHeight: kopf.height,
    leftEyeDepth: links,
    rightEyeDepth: rechts,
    mouthDepth: mund,
    eyeCenters: [
      [kopf.centerX - kopf.eyeX, kopf.eyeY],
      [kopf.centerX + kopf.eyeX, kopf.eyeY],
    ],
  );
}

// ---------------------------------------------------------------------
// Region und Verfeinerung
// ---------------------------------------------------------------------

/// Ob ein Punkt im Einflussbereich von Augen oder Mund liegt – und
/// vorn, nicht am Hinterkopf mit denselben x und y.
bool _imGesicht(double x, double y, double z, _Kopf kopf,
    FaceSculptProportions p) {
  if (y < kopf.bottomY) return false;
  if (z < kopf.frontZ - kopf.width * 0.5) return false;
  final b = kopf.width;
  final rAuge = p.socketRadius * b * (1 + p.lidWidth);
  for (final ex in [kopf.centerX - kopf.eyeX, kopf.centerX + kopf.eyeX]) {
    final dx = x - ex, dy = y - kopf.eyeY;
    if (dx * dx + dy * dy <= rAuge * rAuge) return true;
  }
  final a = p.mouthHalfWidth * b * (1 + p.lipWidth);
  final c = p.mouthHalfHeight * kopf.height * (1 + p.lipWidth);
  final mx = (x - kopf.centerX) / a, my = (y - kopf.mouthY) / c;
  return mx * mx + my * my <= 1;
}

/// Abstand eines Punkts zu einem Dreieck in der Ebene – null, wenn
/// er drinliegt, sonst der Abstand zur nächsten Kante.
double _abstand2d(double px, double py, List<double> x, List<double> y) {
  var innen = true;
  var vorzeichen = 0;
  for (var k = 0; k < 3; k++) {
    final j = (k + 1) % 3;
    final kreuz = (x[j] - x[k]) * (py - y[k]) - (y[j] - y[k]) * (px - x[k]);
    final s = kreuz > 0 ? 1 : (kreuz < 0 ? -1 : 0);
    if (s != 0) {
      if (vorzeichen == 0) {
        vorzeichen = s;
      } else if (s != vorzeichen) {
        innen = false;
      }
    }
  }
  if (innen) return 0;
  var best = double.infinity;
  for (var k = 0; k < 3; k++) {
    final j = (k + 1) % 3;
    final ex = x[j] - x[k], ey = y[j] - y[k];
    final l2 = ex * ex + ey * ey;
    var t = l2 <= 0 ? 0.0 : ((px - x[k]) * ex + (py - y[k]) * ey) / l2;
    t = t.clamp(0.0, 1.0);
    final dx = px - (x[k] + t * ex), dy = py - (y[k] + t * ey);
    best = math.min(best, math.sqrt(dx * dx + dy * dy));
  }
  return best;
}

/// Die Dreiecke, die Augen oder Mund berühren.
///
/// Je **Dreieck**, nicht je Punkt: Ein grobes Netz hat um das Auge
/// herum vielleicht kein einziges Eckpunkt – die Vorderseite eines
/// Kastenkopfs besteht aus zwei Dreiecken mit den Ecken weit außen.
/// Gefragt wird deshalb, ob das Merkmal-Zentrum dem Dreieck in der
/// Ebene näher liegt als sein Einflussradius.
List<int> _regionDreiecke(
    Float32List pos, List<int> idx, _Kopf kopf, FaceSculptProportions p) {
  final b = kopf.width;
  final rAuge = p.socketRadius * b * (1 + p.lidWidth);
  final a = p.mouthHalfWidth * b * (1 + p.lipWidth);
  final c = p.mouthHalfHeight * kopf.height * (1 + p.lipWidth);
  final augen = [kopf.centerX - kopf.eyeX, kopf.centerX + kopf.eyeX];
  final out = <int>[];
  final x = List<double>.filled(3, 0), y = List<double>.filled(3, 0);
  final xm = List<double>.filled(3, 0), ym = List<double>.filled(3, 0);
  for (var t = 0; t + 2 < idx.length; t += 3) {
    var maxZ = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var k = 0; k < 3; k++) {
      final v = idx[t + k] * 3;
      x[k] = pos[v];
      y[k] = pos[v + 1];
      maxY = math.max(maxY, pos[v + 1]);
      maxZ = math.max(maxZ, pos[v + 2]);
      // Für den Mund: die Ellipse auf den Einheitskreis gestaucht.
      xm[k] = (pos[v] - kopf.centerX) / a;
      ym[k] = (pos[v + 1] - kopf.mouthY) / c;
    }
    // Vorn und im Kopfband – dieselben Tore wie beim Verschieben.
    if (maxY < kopf.bottomY) continue;
    if (maxZ < kopf.frontZ - b * 0.5) continue;
    var trifft = false;
    for (final ex in augen) {
      if (_abstand2d(ex, kopf.eyeY, x, y) <= rAuge) {
        trifft = true;
        break;
      }
    }
    if (!trifft && _abstand2d(0, 0, xm, ym) <= 1) trifft = true;
    if (trifft) out.add(t ~/ 3);
  }
  return out;
}

double _laengsteKante(Float32List pos, List<int> idx, int t) {
  var best = 0.0;
  for (var k = 0; k < 3; k++) {
    final a = idx[t * 3 + k] * 3, c = idx[t * 3 + (k + 1) % 3] * 3;
    final dx = pos[a] - pos[c], dy = pos[a + 1] - pos[c + 1],
        dz = pos[a + 2] - pos[c + 2];
    best = math.max(best, math.sqrt(dx * dx + dy * dy + dz * dz));
  }
  return best;
}

/// Punkte nach Position verschweißen: gleiche Stelle, gleiche Nummer.
///
/// Quantisiert auf ein Hunderttausendstel der größten Ausdehnung –
/// fein genug, dass benachbarte Punkte getrennt bleiben, grob genug,
/// dass die beiden Seiten einer UV-Naht zusammenfallen.
Int32List _verschweisse(Float32List pos) {
  final n = pos.length ~/ 3;
  var min = double.infinity, max = double.negativeInfinity;
  for (final v in pos) {
    min = math.min(min, v);
    max = math.max(max, v);
  }
  final quant = math.max(max - min, 1e-9) * 1e-5;
  final ids = <String, int>{};
  final out = Int32List(n);
  for (var v = 0; v < n; v++) {
    final key = '${(pos[v * 3] / quant).round()},'
        '${(pos[v * 3 + 1] / quant).round()},'
        '${(pos[v * 3 + 2] / quant).round()}';
    out[v] = ids.putIfAbsent(key, () => ids.length);
  }
  return out;
}

/// Ein Durchgang konformer Verfeinerung.
///
/// Alle Kanten der Regionsdreiecke werden markiert. Dann bekommt
/// **jedes** Dreieck so viele neue Punkte, wie es markierte Kanten
/// hat – auch die Nachbarn außerhalb der Region, sonst entstünden
/// T-Stöße.
///
/// Markiert wird über **verschweißte** Punkte. Das war der Fund aus
/// Blender: Über die rohen Indizes markiert, sah das Nachbardreieck
/// an einer UV-Naht seine Kante als unmarkiert (andere Indizes,
/// gleiche Stelle), blieb ungeteilt, und auf zwei echten Netzen
/// blieben 90 und 162 Randkanten zurück. Der Kastentest hatte keine
/// Nähte und konnte das nicht sehen. Mittelpunkte werden trotzdem je
/// **rohem** Kantenpaar angelegt: Beide Seiten der Naht bekommen
/// ihren eigenen Mittelpunkt an derselben Stelle, mit ihren eigenen
/// UVs – die Hülle bleibt nach Position geschlossen, die Naht bleibt
/// eine Naht.
(Float32List, List<int>, List<double>?) _teileKonform(
    Float32List pos, List<int> idx, List<double>? uvs, List<int> region) {
  final hatUv = uvs != null && uvs.length == (pos.length ~/ 3) * 2;
  final alteUv = hatUv ? uvs : null;
  final neuePos = pos.toList();
  final neueUv = alteUv?.toList();
  final mitten = <int, int>{};
  final weld = _verschweisse(pos);

  int schluessel(int a, int b) =>
      a < b ? a * 0x40000000 + b : b * 0x40000000 + a;
  int nahtSchluessel(int a, int b) => schluessel(weld[a], weld[b]);

  final markiert = <int>{};
  for (final t in region) {
    for (var k = 0; k < 3; k++) {
      markiert.add(
          nahtSchluessel(idx[t * 3 + k], idx[t * 3 + (k + 1) % 3]));
    }
  }

  int mitte(int a, int b) {
    final s = schluessel(a, b);
    final vorhanden = mitten[s];
    if (vorhanden != null) return vorhanden;
    final n = neuePos.length ~/ 3;
    for (var k = 0; k < 3; k++) {
      neuePos.add((pos[a * 3 + k] + pos[b * 3 + k]) / 2);
    }
    if (neueUv != null && alteUv != null) {
      neueUv.add((alteUv[a * 2] + alteUv[b * 2]) / 2);
      neueUv.add((alteUv[a * 2 + 1] + alteUv[b * 2 + 1]) / 2);
    }
    mitten[s] = n;
    return n;
  }

  final neueIdx = <int>[];
  for (var t = 0; t + 2 < idx.length; t += 3) {
    // So drehen, dass die markierten Kanten vorn stehen: Kante k ist
    // (v[k], v[k+1]).
    var v = [idx[t], idx[t + 1], idx[t + 2]];
    var m = [
      markiert.contains(nahtSchluessel(v[0], v[1])),
      markiert.contains(nahtSchluessel(v[1], v[2])),
      markiert.contains(nahtSchluessel(v[2], v[0])),
    ];
    final anzahl = m.where((x) => x).length;
    if (anzahl == 0) {
      neueIdx.addAll(v);
      continue;
    }
    // Drehen, bis das Muster passt: eine markierte Kante an Position
    // 0; zwei markierte an 0 und 1; drei ist drehinvariant.
    for (var drehung = 0; drehung < 3; drehung++) {
      final passt = anzahl == 3 ||
          (anzahl == 1 && m[0]) ||
          (anzahl == 2 && m[0] && m[1]);
      if (passt) break;
      v = [v[1], v[2], v[0]];
      m = [m[1], m[2], m[0]];
    }
    final a = v[0], b = v[1], c = v[2];
    switch (anzahl) {
      case 1:
        final ab = mitte(a, b);
        neueIdx.addAll([a, ab, c, ab, b, c]);
      case 2:
        final ab = mitte(a, b), bc = mitte(b, c);
        neueIdx.addAll([a, ab, c, ab, b, bc, ab, bc, c]);
      default:
        final ab = mitte(a, b), bc = mitte(b, c), ca = mitte(c, a);
        neueIdx.addAll([a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca]);
    }
  }
  return (Float32List.fromList(neuePos), neueIdx, neueUv);
}

// ---------------------------------------------------------------------
// Verschieben
// ---------------------------------------------------------------------

double _glatt(double d) => d * d * (3 - 2 * d);

void _verschiebe(Float32List pos, _Kopf kopf, FaceSculptProportions p) {
  final b = kopf.width;
  final r = p.socketRadius * b;
  final tiefeAuge = p.socketDepth * b;
  final gratAuge = p.lidRise * b;
  final a = p.mouthHalfWidth * b;
  final c = p.mouthHalfHeight * kopf.height;
  final tiefeMund = p.mouthDepth * b;
  final gratMund = p.lipRise * b;

  double feld(double d, double tiefe, double grat, double breite) {
    if (d < 1) return -tiefe * (1 - _glatt(d));
    if (d < 1 + breite) {
      return grat * math.sin(math.pi * (d - 1) / breite);
    }
    return 0;
  }

  for (var i = 0; i + 2 < pos.length; i += 3) {
    final x = pos[i], y = pos[i + 1], z = pos[i + 2];
    if (!_imGesicht(x, y, z, kopf, p)) continue;
    var dz = 0.0;
    for (final ex in [kopf.centerX - kopf.eyeX, kopf.centerX + kopf.eyeX]) {
      final dx = x - ex, dy = y - kopf.eyeY;
      dz += feld(math.sqrt(dx * dx + dy * dy) / r, tiefeAuge, gratAuge,
          p.lidWidth);
    }
    final mx = (x - kopf.centerX) / a, my = (y - kopf.mouthY) / c;
    dz += feld(math.sqrt(mx * mx + my * my), tiefeMund, gratMund, p.lipWidth);
    pos[i + 2] = z + dz;
  }
}

// ---------------------------------------------------------------------
// Zurückbauen
// ---------------------------------------------------------------------

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
