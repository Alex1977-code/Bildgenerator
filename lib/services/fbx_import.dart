/// FBX einlesen – so weit, wie es für diese App nötig ist.
///
/// Warum überhaupt: FBX ist das Format, in dem Roblox-Figuren
/// üblicherweise die Runde machen. Blender, Maya und die
/// Marktplatz-Vorlagen geben FBX aus, und der Roblox-Importer
/// bevorzugt es für gerigte Figuren. Bisher nahm der Viewer nur GLB,
/// STL und OBJ – wer eine FBX ablegte, bekam eine Absage.
///
/// Was gelesen wird: die Netzgeometrie (Punkte und Polygone) aller
/// `Geometry`-Knoten, in Dreiecke zerlegt und über den eigenen
/// glTF-Writer als GLB zurückgegeben. Beides, die binäre und die
/// Text-Fassung.
///
/// Was **nicht** gelesen wird, und das ausdrücklich: Skelett,
/// Gewichte, Materialien, Texturen und Animationen. Ein FBX kann all
/// das enthalten, aber ein vollständiger Leser dafür wäre ein eigenes
/// Vorhaben. Für den Zweck hier – ein vorhandenes Netz ansehen,
/// nachträglich riggen und für Roblox herrichten – reicht die
/// Geometrie: Das Skelett baut die App ohnehin selbst.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'fbx_reader.dart' show readFbxTree;
import 'local_3d.dart' show LocalMesh, buildGlb;

/// Die Kennung am Anfang jeder binären FBX-Datei.
const String fbxBinaryMagic = 'Kaydara FBX Binary  ';

bool isBinaryFbx(Uint8List bytes) {
  if (bytes.length < fbxBinaryMagic.length) return false;
  return String.fromCharCodes(
          bytes.sublist(0, fbxBinaryMagic.length)) ==
      fbxBinaryMagic;
}

/// Die Text-Fassung erkennt man an den Schlüsselwörtern; eine feste
/// Kennung wie bei der Binärdatei gibt es nicht.
bool isAsciiFbx(Uint8List bytes) {
  final head = latin1.decode(
      bytes.sublist(0, math.min(bytes.length, 4096)),
      allowInvalid: true);
  return head.contains('FBXHeaderExtension') ||
      (head.contains('Objects:') && head.contains('Geometry:'));
}

bool looksLikeFbx(Uint8List bytes) =>
    isBinaryFbx(bytes) || isAsciiFbx(bytes);

// ----------------------------------------------------------------
// Der Baum
// ----------------------------------------------------------------

/// Ein Knoten der FBX-Baumstruktur. Beide Fassungen – binär und Text –
/// werden zuerst hierher gelesen; erst danach wird gedeutet. Sonst
/// stünde die Auswertung zweimal da.
class FbxNode {
  FbxNode(this.name, this.properties, this.children, this.arrays);

  final String name;

  /// Einzelwerte: Zahlen und Zeichenketten.
  final List<Object?> properties;

  /// Zahlenfelder (Vertices, Indizes …).
  final List<List<num>> arrays;

  final List<FbxNode> children;

  Iterable<FbxNode> named(String name) =>
      children.where((c) => c.name == name);

  /// Alle Zahlen der Felder dieses Knotens als Kommazahlen.
  List<double> doubles() => [
        for (final array in arrays)
          for (final value in array) value.toDouble(),
      ];

  /// Dasselbe als ganze Zahlen – Indizes stehen je nach Werkzeug als
  /// int32 oder als double in der Datei.
  List<int> ints() => [
        for (final array in arrays)
          for (final value in array) value.round(),
      ];

  FbxNode? first(String name) {
    for (final child in children) {
      if (child.name == name) return child;
    }
    return null;
  }

  /// Der Wert einer Eigenschaft aus `Properties70`, z. B.
  /// `Lcl Translation` – FBX legt Vektoren als drei Einzelwerte am
  /// Ende der P-Zeile ab.
  List<double> property70(String key, List<double> fallback) {
    final props = first('Properties70');
    if (props == null) return fallback;
    for (final p in props.named('P')) {
      if (p.properties.isEmpty || p.properties.first != key) continue;
      final zahlen = [
        for (final value in p.properties.skip(4))
          if (value is num) value.toDouble(),
      ];
      if (zahlen.isEmpty) return fallback;
      return [
        for (var i = 0; i < fallback.length; i++)
          i < zahlen.length ? zahlen[i] : fallback[i],
      ];
    }
    return fallback;
  }

  double property70Single(String key, double fallback) =>
      property70(key, [fallback]).first;

  /// Die Kennung eines Objekts – die erste Eigenschaft von
  /// `Geometry`- und `Model`-Knoten.
  int? get id {
    final value = properties.isEmpty ? null : properties.first;
    return value is num ? value.toInt() : null;
  }
}

/// Das eingelesene Netz, bevor daraus eine GLB wird.
class FbxMesh {
  FbxMesh(this.positions, this.polygons,
      {this.unitScale = 1.0, this.upAxis = 1, this.objects = 0});

  /// x, y, z je Punkt – bereits in Weltlage und in Metern.
  final List<double> positions;

  /// Die Polygone als Punktindizes, jedes mit beliebig vielen Ecken.
  final List<List<int>> polygons;

  /// `UnitScaleFactor` aus den GlobalSettings. FBX zählt in
  /// Zentimetern; der Faktor sagt, wie viele Zentimeter eine Einheit
  /// der Datei sind.
  final double unitScale;

  /// `UpAxis`: 0 = X, 1 = Y, 2 = Z.
  final int upAxis;

  /// Wie viele Netz-Objekte zusammengefasst wurden.
  final int objects;

  int get triangleCount =>
      polygons.fold(0, (sum, p) => sum + math.max(0, p.length - 2));
}

/// Wandelt eine FBX-Datei in eine GLB um. Wirft [Exception] mit
/// verständlicher Meldung, wenn nichts Lesbares darin steht.
Uint8List fbxToGlb(Uint8List bytes) {
  final parsed = readFbxMesh(bytes);
  if (parsed.polygons.isEmpty) {
    throw Exception(
        'Die FBX-Datei enthält kein lesbares Netz. Möglich ist auch, '
        'dass sie nur ein Skelett oder eine Animation enthält – dann '
        'in Blender öffnen und mit Geometrie neu ausgeben.');
  }
  final mesh = LocalMesh();
  for (var i = 0; i + 2 < parsed.positions.length; i += 3) {
    mesh.addVertex(parsed.positions[i], parsed.positions[i + 1],
        parsed.positions[i + 2], 0, 0);
  }
  final vertexCount = mesh.positions.length ~/ 3;
  for (final polygon in parsed.polygons) {
    // Fächer-Triangulierung: FBX erlaubt N-Ecke, glTF kennt nur
    // Dreiecke.
    for (var k = 1; k + 1 < polygon.length; k++) {
      final a = polygon[0], b = polygon[k], c = polygon[k + 1];
      if (a < 0 || b < 0 || c < 0) continue;
      if (a >= vertexCount || b >= vertexCount || c >= vertexCount) {
        continue;
      }
      mesh.addTriangle(a, b, c);
    }
  }
  if (mesh.indices.isEmpty) {
    throw Exception('Die FBX-Datei enthält keine gültigen Flächen.');
  }
  return buildGlb(mesh);
}

/// Liest Punkte und Polygone aus einer FBX-Datei – binär oder Text.
FbxMesh readFbxMesh(Uint8List bytes) => interpretFbx(readFbxTree(bytes));

// ----------------------------------------------------------------
// Deutung: Geometrie, Modelle, Verbindungen
// ----------------------------------------------------------------

/// Rechnet den Baum in ein Netz in Weltlage um.
///
/// Ohne diesen Schritt fällt jedes Objekt in den Ursprung: FBX legt
/// die Punkte eines Netzes in seinem **eigenen** Koordinatensystem ab.
/// Wo es steht, wie es gedreht und skaliert ist, steht am zugehörigen
/// `Model`; welches Model zu welcher Geometrie gehört, steht in
/// `Connections`. Blender packt sogar den Maßstab dort hinein – ein
/// Würfel mit Kantenlänge 2 kommt als Kantenlänge 2 mit
/// `Lcl Scaling: 100` an, weil die Datei in Zentimetern zählt.
FbxMesh interpretFbx(List<FbxNode> roots) {
  FbxNode? finde(String name) {
    for (final root in roots) {
      if (root.name == name) return root;
    }
    return null;
  }

  final settings = finde('GlobalSettings');
  final unitScale =
      settings?.property70Single('UnitScaleFactor', 1.0) ?? 1.0;
  final upAxis =
      (settings?.property70Single('UpAxis', 1.0) ?? 1.0).round();
  // FBX zählt in Zentimetern: Ein Faktor von 1 heißt „eine Einheit ist
  // ein Zentimeter", 100 heißt „ein Meter". glTF und Roblox rechnen in
  // Metern.
  final metersPerUnit = unitScale <= 0 ? 0.01 : unitScale / 100.0;

  final objects = finde('Objects');
  final connections = finde('Connections');
  final positions = <double>[];
  final polygons = <List<int>>[];
  if (objects == null) {
    return FbxMesh(positions, polygons,
        unitScale: unitScale, upAxis: upAxis);
  }

  // Kind → Elternteil aus den Verbindungen („OO" = Objekt an Objekt).
  final parentOf = <int, int>{};
  for (final c in connections?.named('C') ?? const <FbxNode>[]) {
    final props = c.properties;
    if (props.length < 3 || props.first != 'OO') continue;
    final child = props[1], parent = props[2];
    if (child is num && parent is num) {
      parentOf[child.toInt()] = parent.toInt();
    }
  }

  final models = <int, FbxNode>{};
  for (final model in objects.named('Model')) {
    final id = model.id;
    if (id != null) models[id] = model;
  }

  var count = 0;
  for (final geometry in objects.named('Geometry')) {
    final vertices = geometry.first('Vertices')?.doubles() ?? const [];
    final indices = geometry.first('PolygonVertexIndex')?.ints() ?? const [];
    if (vertices.isEmpty || indices.isEmpty) continue;
    final matrix = _worldMatrix(geometry.id, models, parentOf);
    final offset = positions.length ~/ 3;
    for (var i = 0; i + 2 < vertices.length; i += 3) {
      final p = _apply(matrix, vertices[i], vertices[i + 1], vertices[i + 2]);
      positions.addAll([
        p[0] * metersPerUnit,
        p[1] * metersPerUnit,
        p[2] * metersPerUnit,
      ]);
    }
    polygons.addAll(_toPolygons(indices, offset: offset));
    count++;
  }
  return FbxMesh(positions, polygons,
      unitScale: unitScale, upAxis: upAxis, objects: count);
}

/// Die Weltmatrix einer Geometrie: ihr Model und alle Models darüber,
/// jeweils Translation × Rotation × Skalierung, dazu die
/// „Geometric"-Verschiebung, die Maya kennt.
List<double> _worldMatrix(
    int? geometryId, Map<int, FbxNode> models, Map<int, int> parentOf) {
  var matrix = _identity();
  if (geometryId == null) return matrix;
  // Von der Geometrie zum Model und von dort nach oben. Die Kette ist
  // kurz; die Schranke schützt vor einer kaputten Datei mit Zyklus.
  final kette = <FbxNode>[];
  var current = parentOf[geometryId];
  for (var guard = 0; guard < 64 && current != null && current != 0; guard++) {
    final model = models[current];
    if (model != null) kette.add(model);
    current = parentOf[current];
  }
  // Von außen nach innen multiplizieren: Der äußerste Elternteil wirkt
  // zuerst.
  for (final model in kette.reversed) {
    matrix = _multiply(matrix, _localMatrix(model));
  }
  final eigenes = kette.isEmpty ? null : kette.first;
  if (eigenes != null) {
    matrix = _multiply(matrix, _geometricMatrix(eigenes));
  }
  return matrix;
}

List<double> _localMatrix(FbxNode model) {
  final t = model.property70('Lcl Translation', [0, 0, 0]);
  final r = model.property70('Lcl Rotation', [0, 0, 0]);
  final s = model.property70('Lcl Scaling', [1, 1, 1]);
  return _compose(t, r, s);
}

List<double> _geometricMatrix(FbxNode model) => _compose(
      model.property70('GeometricTranslation', [0, 0, 0]),
      model.property70('GeometricRotation', [0, 0, 0]),
      model.property70('GeometricScaling', [1, 1, 1]),
    );

/// Translation × Rotation × Skalierung, Rotation in Grad und in der
/// Reihenfolge X, dann Y, dann Z (FBX-Vorgabe `eEulerXYZ`).
List<double> _compose(List<double> t, List<double> r, List<double> s) {
  final rad = [
    r[0] * math.pi / 180,
    r[1] * math.pi / 180,
    r[2] * math.pi / 180,
  ];
  final cx = math.cos(rad[0]), sx = math.sin(rad[0]);
  final cy = math.cos(rad[1]), sy = math.sin(rad[1]);
  final cz = math.cos(rad[2]), sz = math.sin(rad[2]);
  // R = Rz · Ry · Rx
  final m = <double>[
    cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx, //
    sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx,
    -sy, cy * sx, cy * cx,
  ];
  return [
    m[0] * s[0], m[1] * s[1], m[2] * s[2], t[0], //
    m[3] * s[0], m[4] * s[1], m[5] * s[2], t[1],
    m[6] * s[0], m[7] * s[1], m[8] * s[2], t[2],
  ];
}

List<double> _identity() =>
    [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0];

List<double> _multiply(List<double> a, List<double> b) {
  final out = List<double>.filled(12, 0);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      var sum = 0.0;
      for (var k = 0; k < 3; k++) {
        sum += a[row * 4 + k] * b[k * 4 + col];
      }
      out[row * 4 + col] = sum;
    }
    out[row * 4 + 3] = a[row * 4] * b[3] +
        a[row * 4 + 1] * b[7] +
        a[row * 4 + 2] * b[11] +
        a[row * 4 + 3];
  }
  return out;
}

List<double> _apply(List<double> m, double x, double y, double z) => [
      m[0] * x + m[1] * y + m[2] * z + m[3],
      m[4] * x + m[5] * y + m[6] * z + m[7],
      m[8] * x + m[9] * y + m[10] * z + m[11],
    ];

/// FBX schreibt die Ecken eines Polygons hintereinander und markiert
/// die letzte durch ein negatives Vorzeichen: `~index`, also
/// `-index - 1`.
List<List<int>> _toPolygons(List<int> indices, {int offset = 0}) {
  final out = <List<int>>[];
  var current = <int>[];
  for (final raw in indices) {
    if (raw < 0) {
      current.add(-raw - 1 + offset);
      if (current.length >= 3) out.add(current);
      current = <int>[];
    } else {
      current.add(raw + offset);
    }
  }
  // Ein Rest ohne Abschlussmarke ist abgeschnitten und wird verworfen.
  return out;
}
