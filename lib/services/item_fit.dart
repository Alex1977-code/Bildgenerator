/// Gegenstand und Figur zusammen ansehen – und den Gegenstand daran
/// anpassen.
///
/// Bis hierher entstehen Figur und Gegenstand getrennt. Ob das Schwert
/// wirklich in der Hand liegt und der Helm auf den Kopf passt, sieht
/// man erst, wenn beides zusammensteht – bisher also erst in Studio
/// oder Blender.
///
/// Diese Datei rechnet dafür zwei Dinge:
///
/// * **Wohin.** Zu jeder Gegenstandsart gehört ein Gelenk der Figur:
///   das Schwert an die Hand, der Helm an den Kopf, der Rucksack an
///   die Brust. Aus dem Skelett der Figur kommt die Weltposition
///   dieses Gelenks.
/// * **Wie groß und wie gedreht.** Der Gegenstand wird auf die Größe
///   skaliert, die [itemSize] für diese Figur vorsieht, und so
///   verschoben, dass sein Griff bzw. seine Unterseite am Gelenk
///   sitzt.
///
/// Das Ergebnis wird als Transformation **in die GLB des Gegenstands**
/// geschrieben, nicht in eine zusammengeführte Datei. Genau das
/// brauchen die Zielplattformen: Roblox und Blender wollen das
/// Accessoire als eigenes Asset in der richtigen Größe und Lage,
/// nicht mit der Figur verschweißt.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'item_prompt.dart';
import 'model_refine.dart' show bakeScaleAndRotationIntoGlb;

/// An welches Gelenk ein Gegenstand gehört.
///
/// Mehrere Namen = Vorlieben in dieser Reihenfolge; genommen wird der
/// erste, den das Skelett der Figur hat. Ohne Treffer bleibt der
/// Ursprung, und die Oberfläche sagt es.
const itemAttachJoints = <String, List<String>>{
  // In die Hand – rechte Hand zuerst, weil die meisten Rigs sie
  // führen.
  'hand': ['Hand_R', 'Hand_L', 'Wheel1_R'],
  'kopf': ['Head', 'Neck'],
  'gesicht': ['Head'],
  'hals': ['Neck', 'Chest'],
  'ruecken': ['Chest', 'Spine'],
  'schulter': ['Shoulder_R', 'Chest'],
  'huefte': ['Hips', 'Spine'],
  'boden': ['Hips'],
};

/// Welcher Anbaupunkt zu einer Gegenstandsart gehört.
String itemSlotFor(ItemKind kind) {
  if (kind.rideable) return 'boden';
  return switch (kind.robloxAccessoryType) {
    'Hat' || 'Hair' => 'kopf',
    'Face' => 'gesicht',
    'Neck' => 'hals',
    'Back' || 'Front' => 'ruecken',
    'Shoulder' => 'schulter',
    'Waist' => 'huefte',
    _ => kind.group == 'Umgebung' ? 'boden' : 'hand',
  };
}

/// Wie der Gegenstand am Gelenk steht.
class ItemPlacement {
  const ItemPlacement({
    this.scale = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.offsetZ = 0,
    this.rotX = 0,
    this.rotY = 0,
    this.rotZ = 0,
  });

  /// Gleichmäßige Skalierung des Gegenstands.
  final double scale;

  /// Verschiebung gegenüber dem Gelenk, in Einheiten der Figur.
  final double offsetX, offsetY, offsetZ;

  /// Drehung in Bogenmaß um die drei Achsen (in dieser Reihenfolge
  /// angewendet: x, dann y, dann z).
  final double rotX, rotY, rotZ;

  ItemPlacement copyWith({
    double? scale,
    double? offsetX,
    double? offsetY,
    double? offsetZ,
    double? rotX,
    double? rotY,
    double? rotZ,
  }) =>
      ItemPlacement(
        scale: scale ?? this.scale,
        offsetX: offsetX ?? this.offsetX,
        offsetY: offsetY ?? this.offsetY,
        offsetZ: offsetZ ?? this.offsetZ,
        rotX: rotX ?? this.rotX,
        rotY: rotY ?? this.rotY,
        rotZ: rotZ ?? this.rotZ,
      );
}

/// Erster Vorschlag: die Größe stimmt, der Rest ist neutral.
///
/// [itemLongest] ist die längste Kante des erzeugten Gegenstands,
/// [figureHeight] die Höhe der Figur – beide in Modelleinheiten. Der
/// Maßstab kommt aus derselben Tabelle, die schon den Prompt bestimmt
/// hat: Wenn das Bildmodell die Proportion getroffen hat, ist der
/// Faktor nahe 1 und der Vorschlag ändert kaum etwas. Hat es sie
/// verfehlt, rückt er sie gerade.
ItemPlacement autoPlacement({
  required ItemKind kind,
  required double figureHeight,
  required double itemLongest,
}) {
  if (itemLongest <= 1e-6 || figureHeight <= 1e-6) {
    return const ItemPlacement();
  }
  final wanted = itemSize(kind, figureHeight);
  return ItemPlacement(scale: wanted / itemLongest);
}

/// Multipliziert zwei 4×4-Matrizen (Spaltenreihenfolge wie in glTF).
List<double> _mul(List<double> a, List<double> b) {
  final out = List<double>.filled(16, 0);
  for (var c = 0; c < 4; c++) {
    for (var r = 0; r < 4; r++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[k * 4 + r] * b[c * 4 + k];
      }
      out[c * 4 + r] = sum;
    }
  }
  return out;
}

/// Die Matrix einer Platzierung – Skalierung, dann Drehung, dann
/// Verschiebung.
List<double> placementMatrix(ItemPlacement p) {
  final s = [
    p.scale, 0.0, 0.0, 0.0, //
    0.0, p.scale, 0.0, 0.0, //
    0.0, 0.0, p.scale, 0.0, //
    0.0, 0.0, 0.0, 1.0,
  ];
  final cx = math.cos(p.rotX), sx = math.sin(p.rotX);
  final cy = math.cos(p.rotY), sy = math.sin(p.rotY);
  final cz = math.cos(p.rotZ), sz = math.sin(p.rotZ);
  final rx = [
    1.0, 0.0, 0.0, 0.0, //
    0.0, cx, sx, 0.0, //
    0.0, -sx, cx, 0.0, //
    0.0, 0.0, 0.0, 1.0,
  ];
  final ry = [
    cy, 0.0, -sy, 0.0, //
    0.0, 1.0, 0.0, 0.0, //
    sy, 0.0, cy, 0.0, //
    0.0, 0.0, 0.0, 1.0,
  ];
  final rz = [
    cz, sz, 0.0, 0.0, //
    -sz, cz, 0.0, 0.0, //
    0.0, 0.0, 1.0, 0.0, //
    0.0, 0.0, 0.0, 1.0,
  ];
  final rot = _mul(rz, _mul(ry, rx));
  final m = _mul(rot, s);
  m[12] = p.offsetX;
  m[13] = p.offsetY;
  m[14] = p.offsetZ;
  return m;
}

/// Wendet eine Platzierung auf einen Punkt an – für die Vorschau, die
/// beide Netze zeichnet, ohne sie zusammenzuführen.
(double, double, double) applyPlacement(
    ItemPlacement p, double x, double y, double z) {
  final m = placementMatrix(p);
  return (
    m[0] * x + m[4] * y + m[8] * z + m[12],
    m[1] * x + m[5] * y + m[9] * z + m[13],
    m[2] * x + m[6] * y + m[10] * z + m[14],
  );
}

int _pad4(int n) => (n + 3) & ~3;

/// Schreibt Größe, Drehung **und Versatz** in die GLB des Gegenstands.
///
/// **Bevorzugt ins Netz gebacken.** Eine Wurzel-Matrix am Knoten sehen
/// nur Programme, die Knoten-Transformationen auswerten – die
/// Größenprüfung dieser App liest die Positionen roh und hätte weiter
/// die alte Größe gemeldet: Man stellt das Schwert auf 40 % und die
/// Prüfung meldet unverändert „zu groß". Ins Netz gebacken sehen
/// Vorschau, Prüfung und Import dasselbe.
///
/// **Der Versatz gehört dazu.** Er war zuerst ausgenommen, aus der
/// Überlegung, das Accessoire würde sonst um die Anbauhöhe daneben
/// schweben. Das war falsch herum gedacht: In Roblox fällt das
/// `Attachment` im `Handle` mit dem Punkt am Körper zusammen. Der
/// Abstand des Netzes zu seinem eigenen Ursprung **ist** damit der
/// Abstand zum Körperpunkt – genau das, was in der Anprobe eingestellt
/// wird. Ohne ihn wäre die Anprobe Zierde gewesen: Man hätte etwas
/// hingeschoben, und in Studio läge es woanders.
///
/// **Der Rückfall auf die Wurzel-Matrix** greift bei Modellen mit
/// Skelett (Reittiere, Fahrzeuge): Dort müssten die Bind-Matrizen
/// mitgerechnet werden, und ein falsch gebackenes Rig zerreißt das
/// Modell. Für die gilt die Größentabelle ohnehin nicht – sie sind
/// keine Accessoires, sondern Modelle mit einem Sitz.
Uint8List applyPlacementToGlb(Uint8List glb, ItemPlacement placement) {
  try {
    return bakeScaleAndRotationIntoGlb(
      glb,
      scale: placement.scale,
      rotX: placement.rotX,
      rotY: placement.rotY,
      rotZ: placement.rotZ,
      offsetX: placement.offsetX,
      offsetY: placement.offsetY,
      offsetZ: placement.offsetZ,
    );
  } on Exception {
    // Skelett oder eigene Knoten-Transformationen – dann der Weg über
    // den Wurzelknoten.
    return _placementAsRootNode(glb, placement);
  }
}

/// Der Rückfall: ein Wurzelknoten mit der Matrix, unter den die
/// bisherigen Wurzelknoten wandern. Die Netzdaten bleiben unangetastet,
/// und erneutes Anwenden ersetzt den Knoten statt zu stapeln.
Uint8List _placementAsRootNode(Uint8List glb, ItemPlacement placement) {
  if (glb.length < 20) throw Exception('Ungültige GLB-Datei.');
  final header = ByteData.sublistView(glb);
  if (header.getUint32(0, Endian.little) != 0x46546C67) {
    throw Exception('Ungültige GLB-Datei.');
  }
  final jsonLength = header.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  final binStart = 20 + _pad4(jsonLength);
  var bin = Uint8List(0);
  if (binStart + 8 <= glb.length &&
      header.getUint32(binStart + 4, Endian.little) == 0x004E4942) {
    final binLength = header.getUint32(binStart, Endian.little);
    bin = glb.sublist(binStart + 8, binStart + 8 + binLength);
  }

  final nodes = (json['nodes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final scenes = (json['scenes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  if (nodes.isEmpty || scenes.isEmpty) {
    throw Exception('Die GLB hat keine Szene, an der sich etwas '
        'ausrichten ließe.');
  }
  final sceneIndex = (json['scene'] as int?) ?? 0;
  final scene = scenes[sceneIndex.clamp(0, scenes.length - 1)];
  final roots = ((scene['nodes'] as List?) ?? []).cast<int>();

  // Eine frühere Anpassung wird ersetzt, nicht gestapelt: Der eigene
  // Knoten ist am Namen zu erkennen.
  const marker = 'DreiDGeneratorPlatzierung';
  if (roots.length == 1 && nodes[roots.first]['name'] == marker) {
    nodes[roots.first]['matrix'] = placementMatrix(placement);
  } else {
    nodes.add(<String, dynamic>{
      'name': marker,
      'children': List<int>.from(roots),
      'matrix': placementMatrix(placement),
    });
    scene['nodes'] = [nodes.length - 1];
  }
  json['nodes'] = nodes;

  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadded = _pad4(jsonBytes.length);
  final binPadded = _pad4(bin.length);
  final total = 12 + 8 + jsonPadded + (bin.isEmpty ? 0 : 8 + binPadded);
  final out = Uint8List(total);
  final view = ByteData.sublistView(out);
  view.setUint32(0, 0x46546C67, Endian.little);
  view.setUint32(4, 2, Endian.little);
  view.setUint32(8, total, Endian.little);
  view.setUint32(12, jsonPadded, Endian.little);
  view.setUint32(16, 0x4E4F534A, Endian.little);
  out.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var i = 20 + jsonBytes.length; i < 20 + jsonPadded; i++) {
    out[i] = 0x20; // JSON wird mit Leerzeichen aufgefüllt
  }
  if (bin.isNotEmpty) {
    final offset = 20 + jsonPadded;
    view.setUint32(offset, binPadded, Endian.little);
    view.setUint32(offset + 4, 0x004E4942, Endian.little);
    out.setRange(offset + 8, offset + 8 + bin.length, bin);
  }
  return out;
}

/// Anbaupunkte, wenn die Figur **kein Skelett** hat.
///
/// Aus einer Bounding Box lässt sich erstaunlich viel ableiten: Der
/// Kopf sitzt oben in der Mitte, die Hüfte auf halber Höhe, die Hand
/// seitlich auf etwa 55 %, der Rücken hinten in der Brustmitte. Das
/// ist nicht so genau wie ein Gelenk, aber es ist ein Startpunkt –
/// und ohne diesen Rückfall bliebe die Vorschau bei jedem ungeriggten
/// Modell im Ursprung, also im Boden.
///
/// [minY]/[maxY] sind unten/oben, [minZ]/[maxZ] hinten/vorn (Blick
/// nach +z), [halfWidth] die halbe Breite. Alles in Modelleinheiten.
Map<String, (double, double, double)> figureAnchors({
  required double minY,
  required double maxY,
  required double minZ,
  required double maxZ,
  required double halfWidth,
}) {
  final height = maxY - minY;
  final cz = (minZ + maxZ) / 2;
  return {
    'kopf': (0.0, minY + 0.90 * height, cz),
    'gesicht': (0.0, minY + 0.88 * height, maxZ),
    'hals': (0.0, minY + 0.80 * height, cz),
    'schulter': (halfWidth * 0.6, minY + 0.78 * height, cz),
    'ruecken': (0.0, minY + 0.68 * height, minZ),
    'hand': (halfWidth * 0.75, minY + 0.55 * height, cz),
    'huefte': (0.0, minY + 0.50 * height, cz),
    'boden': (0.0, minY, cz),
  };
}

/// Der Anbaupunkt für eine Art: aus dem Skelett, sonst aus der Box.
///
/// [joints] ist Gelenkname → Weltposition (leer, wenn es kein Skelett
/// gibt). Zurück kommt die Position **und** woher sie stammt – die
/// Oberfläche soll sagen können, ob sie geraten hat.
((double, double, double), String) attachPointFor({
  required ItemKind kind,
  required Map<String, (double, double, double)> joints,
  required Map<String, (double, double, double)> anchors,
}) {
  final slot = itemSlotFor(kind);
  for (final name in itemAttachJoints[slot] ?? const <String>[]) {
    final joint = joints[name];
    if (joint != null) return (joint, name);
  }
  final fallback = anchors[slot];
  if (fallback != null) return (fallback, 'geschätzt ($slot)');
  return ((0.0, 0.0, 0.0), 'Ursprung');
}
