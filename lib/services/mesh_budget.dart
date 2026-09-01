/// Das Dreiecksbudget: Ampel, Reglerkennlinie und die Reduktion einer
/// fertigen GLB.
///
/// Warum nach dem Herunterladen und nicht beim Anbieter: Das
/// Face-Limit von Tripo wirkt **vorher** – der Anbieter baut gleich
/// ein schlankeres Netz, was meist besser aussieht als jede spätere
/// Reduktion. Es bleibt deshalb, wo es ist. Nur greift es eben nur bei
/// Tripo. Meshy, Rodin, Stability, fal, Replicate und der lokale
/// Generator liefern, was sie liefern; und ein Modell aus der Galerie
/// oder per Drag & Drop ist ohnehin schon da. Für die gilt dieser
/// Regler: eine Stufe, die auf jede GLB passt, egal woher sie kommt.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart';
import 'local_3d.dart' show LocalMesh, buildGlb, decimateLocalMesh;
import 'roblox_specs_config.dart';

/// Wie das Netz zum Budget steht.
enum BudgetLight {
  /// Reichlich Luft.
  gruen,

  /// Passt noch, aber knapp – für Cage, Naht und Export bleibt wenig.
  gelb,

  /// Über dem Budget: Roblox nimmt das so nicht an.
  rot,
}

/// Das Urteil samt Begründung.
class BudgetVerdict {
  const BudgetVerdict({
    required this.light,
    required this.triangles,
    required this.budget,
    required this.text,
  });

  final BudgetLight light;
  final int triangles;
  final int budget;

  /// Ein Satz, der die Ampel erklärt – die Farbe allein sagt nicht,
  /// was zu tun ist.
  final String text;

  /// Wie voll das Budget ist (1.0 = genau ausgeschöpft).
  double get fill => budget <= 0 ? 0 : triangles / budget;

  bool get blocks => light == BudgetLight.rot;
}

/// Ab welchem Anteil des Budgets die Ampel von grün auf gelb springt.
///
/// 90 %: Darüber passt es zwar noch, aber jede spätere Änderung –
/// Löcher schließen, Cage anlegen, Naht auftrennen – bringt Dreiecke
/// dazu. Wer mit 99 % exportiert, fällt beim nächsten Schritt durch.
const double budgetTightFrom = 0.9;

/// Beurteilt eine Dreieckszahl gegen das Budget eines Asset-Typs.
BudgetVerdict budgetVerdict(int triangles, AssetSpec spec) {
  final budget = spec.triangles;
  if (budget <= 0) {
    return BudgetVerdict(
      light: BudgetLight.gruen,
      triangles: triangles,
      budget: 0,
      text: 'Für „${spec.label}" ist kein Budget hinterlegt.',
    );
  }
  final anteil = triangles / budget;
  if (anteil > 1.0) {
    final zuviel = triangles - budget;
    return BudgetVerdict(
      light: BudgetLight.rot,
      triangles: triangles,
      budget: budget,
      text: '$zuviel Dreiecke über dem Budget von $budget '
          '(${spec.label}). So nimmt Roblox das Modell nicht an – den '
          'Regler nach links ziehen.',
    );
  }
  if (anteil >= budgetTightFrom) {
    return BudgetVerdict(
      light: BudgetLight.gelb,
      triangles: triangles,
      budget: budget,
      text: 'Knapp: ${(anteil * 100).round()} % des Budgets von '
          '$budget. Es passt, aber Löcher schließen, Cage und Naht '
          'bringen noch Dreiecke dazu.',
    );
  }
  return BudgetVerdict(
    light: BudgetLight.gruen,
    triangles: triangles,
    budget: budget,
    text: '${(anteil * 100).round()} % des Budgets von $budget '
        '(${spec.label}).',
  );
}

/// Die Zieldreieckszahl zu einer Reglerstellung.
///
/// Der Regler läuft von 0 bis 1 und ist bewusst **nicht** linear über
/// die Dreieckszahl gelegt, sondern über den Zehnerlogarithmus: Der
/// interessante Bereich liegt zwischen ein paar hundert und ein paar
/// tausend Dreiecken. Linear läge das alles im linken Zehntel, und
/// die rechten neun Zehntel wären für den Unterschied zwischen 90.000
/// und 100.000 reserviert – für Roblox völlig belanglos.
///
/// Rechts steht immer das unveränderte Netz ([original]), links
/// [minTriangles].
int targetForSlider(double value, int original,
    {int minTriangles = 200}) {
  if (original <= minTriangles) return original;
  final t = value.clamp(0.0, 1.0);
  if (t >= 1.0) return original;
  if (t <= 0.0) return minTriangles;
  final lo = math.log(minTriangles.toDouble());
  final hi = math.log(original.toDouble());
  return math.exp(lo + (hi - lo) * t).round().clamp(minTriangles, original);
}

/// Die Reglerstellung zu einer Zieldreieckszahl – die Umkehrung, für
/// den Knopf „aufs Budget setzen".
double sliderForTarget(int target, int original,
    {int minTriangles = 200}) {
  if (original <= minTriangles) return 1.0;
  final ziel = target.clamp(minTriangles, original);
  final lo = math.log(minTriangles.toDouble());
  final hi = math.log(original.toDouble());
  return ((math.log(ziel.toDouble()) - lo) / (hi - lo)).clamp(0.0, 1.0);
}

/// Reduziert eine GLB auf ungefähr [targetTriangles].
///
/// Die Textur wird mitgenommen: Die erste Fassung lieferte ein graues
/// Netz zurück, weil Vertex-Clustering die UVs verwarf. Jetzt werden
/// sie wie Position und Farbe gemittelt und das Bild unverändert
/// wieder eingebettet.
///
/// **Was dabei verloren geht**, und das ist kein Versehen: ein
/// vorhandenes Skelett samt Gewichten. Vertex-Clustering legt Punkte
/// zusammen, und welchem Knochen der neue Punkt gehört, lässt sich
/// nicht mitteln, ohne dass die Haut an den Gelenken reißt. Deshalb
/// prüft [glbTriangleCount] vorher, und die Oberfläche warnt.
Future<Uint8List> decimateGlb(Uint8List glb, int targetTriangles) async {
  final preview = await parseGlbForPreview(glb);
  try {
    final count = preview.indices.length ~/ 3;
    if (targetTriangles <= 0 || count <= targetTriangles) return glb;

    final mesh = LocalMesh();
    final uvs = preview.uvs;
    final hatUvs = uvs != null && uvs.length == preview.positions.length ~/ 3 * 2;
    final vCount = preview.positions.length ~/ 3;
    for (var v = 0; v < vCount; v++) {
      final farbe = v * 4 + 3 < preview.colors.length * 4
          ? preview.colors[v]
          : 0xFFFFFFFF;
      mesh.addVertex(
        preview.positions[v * 3],
        preview.positions[v * 3 + 1],
        preview.positions[v * 3 + 2],
        hatUvs ? uvs[v * 2] : 0,
        hatUvs ? uvs[v * 2 + 1] : 0,
        r: ((farbe >> 16) & 0xFF) / 255,
        g: ((farbe >> 8) & 0xFF) / 255,
        b: (farbe & 0xFF) / 255,
      );
    }
    for (var i = 0; i + 2 < preview.indices.length; i += 3) {
      mesh.addTriangle(
          preview.indices[i], preview.indices[i + 1], preview.indices[i + 2]);
    }
    final klein = decimateLocalMesh(mesh, targetTriangles);
    final textur = hatUvs ? firstGlbTexturePng(glb) : null;
    return buildGlb(klein, pngTexture: textur);
  } finally {
    preview.dispose();
  }
}

/// Die Dreieckszahl einer GLB, ohne sie zu zeichnen.
Future<int> glbTriangleCount(Uint8List glb) async {
  final preview = await parseGlbForPreview(glb);
  try {
    return preview.indices.length ~/ 3;
  } finally {
    preview.dispose();
  }
}

/// Das erste eingebettete Bild einer GLB als PNG/JPEG-Bytes – oder
/// null, wenn keines drin ist.
Uint8List? firstGlbTexturePng(Uint8List glb) {
  try {
    final parts = splitGlb(glb);
    final images = parts.json['images'] as List?;
    if (images == null || images.isEmpty) return null;
    final image = images.first as Map<String, dynamic>;
    final view = image['bufferView'];
    if (view is! num) return null;
    return Uint8List.fromList(
        gltfBufferViewBytes(parts.json, parts.bin, view.toInt()));
  } catch (_) {
    return null;
  }
}
