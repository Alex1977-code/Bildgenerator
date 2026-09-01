/// Die Zerlegung einer geriggten Figur in die 15 Meshes, die Roblox
/// für einen Figurenkörper verlangt.
///
/// Roblox nimmt einen Körper nicht als ein Netz an. Er will 15
/// benannte Meshes (`Head_Geo`, `UpperTorso_Geo`, …), alle an
/// dasselbe R15-Skelett gehäutet. Die KI liefert dagegen **ein** Netz
/// – und das ist gut so, denn nur daran lassen sich Skin-Gewichte
/// sinnvoll erzeugen.
///
/// Diese Datei macht aus dem einen die fünfzehn. Der Maßstab ist das
/// Gewicht: Jedes Dreieck kommt zu dem Teil, dessen Knochen an seinen
/// drei Ecken am schwersten wiegt. Kein Punkt wird verschoben, kein
/// Dreieck geteilt – die Naht liegt genau dort, wo die Häutung sie
/// ohnehin schon hat.
///
/// **Zwischenknochen sind unschädlich.** Tripo liefert 43 Knochen,
/// von denen 16 R15-Namen tragen; `tripo::Spine_1` und Geschwister
/// werden auf ihren nächsten R15-Vorfahren zurückgeführt. Ein Dreieck
/// an einem Zwischenwirbel landet damit im Torso, nicht im Nichts.
///
/// Roblox rechnet das Dreiecksbudget nicht je Mesh, sondern je
/// **Gruppe**: Kopf 4.000, Torso 1.750 (Ober + Unter), je Arm 1.248
/// (Ober + Unter + Hand), je Bein 1.248. Der Bericht nennt beide
/// Ebenen, weil eine Hand mit 1.374 Dreiecken das Budget des ganzen
/// Arms sprengt, ohne dass irgendeine Mesh-Grenze reißt.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart' show splitGlb, joinGlb, readGltfFloats;
import 'gltf_edit.dart';
import 'roblox_rig.dart' show mapBoneToR15, robloxRootBone;
import 'roblox_spec.dart';

/// Welche der sechs Marktplatz-Gruppen ein R15-Teil trägt.
///
/// Sechs, nicht fünfzehn: So rechnet Roblox das Budget, und so steht
/// es in `avatar/character-bodies/specifications.md`.
const Map<String, String> r15PartGroup = {
  'Head': 'DynamicHead',
  'UpperTorso': 'Torso',
  'LowerTorso': 'Torso',
  'LeftUpperArm': 'LeftArm',
  'LeftLowerArm': 'LeftArm',
  'LeftHand': 'LeftArm',
  'RightUpperArm': 'RightArm',
  'RightLowerArm': 'RightArm',
  'RightHand': 'RightArm',
  'LeftUpperLeg': 'LeftLeg',
  'LeftLowerLeg': 'LeftLeg',
  'LeftFoot': 'LeftLeg',
  'RightUpperLeg': 'RightLeg',
  'RightLowerLeg': 'RightLeg',
  'RightFoot': 'RightLeg',
};

/// Wie viele Dreiecke beide Hände zusammen höchstens haben sollten.
///
/// **Nicht dokumentiert, sondern gemessen** (Übergabe vom 31.08.2026):
/// Roblox rechnet das Budget je Arm – Ober, Unter und Hand zusammen
/// 1.248. Tripo modelliert Finger aus und liefert dafür regelmäßig
/// über 1.200 Dreiecke je Hand; damit ist der Arm gesprengt, ohne
/// dass irgendeine Mesh-Grenze reißt. 1.000 für beide Hände zusammen
/// lässt Ober- und Unterarm den Rest.
///
/// Die Abhilfe steht im Prompt, nicht im Netz: „rounded mitten stumps
/// without separate fingers" nimmt der Hand zwei Drittel ihrer
/// Dreiecke. Nachträglich zu dezimieren zerstört gerade an der Hand
/// die Form.
const int r15HandTriangleLimit = 1000;

/// Die 15 Teile in der Reihenfolge, in der sie im Explorer stehen
/// sollen – abgeleitet aus [specBodyMeshNames], damit die Namen nicht
/// zweimal im Quelltext stehen.
List<String> get r15PartNames =>
    [for (final name in specBodyMeshNames) name.replaceAll('_Geo', '')];

/// Ein zerlegtes Teil.
class R15Part {
  const R15Part({
    required this.bone,
    required this.triangles,
    required this.vertices,
    this.positions,
    this.indices,
  });

  /// Der R15-Knochen, also `LeftHand`.
  final String bone;

  /// Der Mesh-Name, den Roblox erwartet: `LeftHand_Geo`.
  String get meshName => '${bone}_Geo';

  /// Die Marktplatz-Gruppe, in der das Budget gerechnet wird.
  String get group => r15PartGroup[bone] ?? 'Torso';

  final int triangles;
  final int vertices;

  /// Die Geometrie des Teils – für die Deckungsprüfung des
  /// Marktplatz-Validators. Null, wenn nichts zusammenkam.
  final Float32List? positions;
  final List<int>? indices;

  bool get isEmpty => triangles == 0;
}

/// Was die Zerlegung ergeben hat.
class R15SplitReport {
  const R15SplitReport({
    required this.parts,
    required this.groupTriangles,
    required this.tracedBones,
    required this.unmappedTriangles,
    required this.notes,
  });

  final List<R15Part> parts;

  /// Dreiecke je Marktplatz-Gruppe.
  final Map<String, int> groupTriangles;

  /// Wie viele Knochen auf einen R15-Vorfahren zurückgeführt wurden.
  final int tracedBones;

  /// Dreiecke, für die sich kein R15-Teil finden ließ. Sie landen im
  /// Torso – verlorengehen darf keines, sonst hat die Figur Löcher.
  final int unmappedTriangles;

  final List<String> notes;

  /// Teile ohne ein einziges Dreieck. Roblox verlangt alle 15; ein
  /// leeres Teil heißt, dass der Figur etwas fehlt (oder dass die
  /// Gewichte dort nicht angekommen sind).
  List<R15Part> get emptyParts => [for (final p in parts) if (p.isEmpty) p];

  int get totalTriangles =>
      parts.fold(0, (sum, p) => sum + p.triangles);

  /// Gruppen über ihrem Budget, mit der Zahl darüber.
  Map<String, int> get overBudget {
    final out = <String, int>{};
    groupTriangles.forEach((group, count) {
      final budget = specBodyPartTriangles[group];
      if (budget != null && count > budget) out[group] = count - budget;
    });
    return out;
  }

  bool get fitsBudget => overBudget.isEmpty;

  /// Dreiecke beider Hände zusammen.
  int get handTriangles => parts.fold(
      0,
      (sum, p) =>
          sum + (p.bone == 'LeftHand' || p.bone == 'RightHand' ? p.triangles : 0));

  /// Ob die Hände im Rahmen bleiben – siehe [r15HandTriangleLimit].
  bool get handsFit => handTriangles <= r15HandTriangleLimit;

  String get text {
    final zeilen = <String>['R15-Zerlegung: 15 Meshes'];
    for (final entry in groupTriangles.entries) {
      final budget = specBodyPartTriangles[entry.key];
      zeilen.add('${entry.key}: ${entry.value}'
          '${budget == null ? '' : ' von $budget'}'
          '${budget != null && entry.value > budget ? ' – zu viel' : ''}');
    }
    for (final part in parts) {
      zeilen.add('  ${part.meshName}: ${part.triangles} Dreiecke');
    }
    zeilen.add('Summe: $totalTriangles von $specBodyTotalTriangles');
    zeilen.add('Hände zusammen: $handTriangles von '
        '$r15HandTriangleLimit${handsFit ? '' : ' – zu viel'}');
    for (final note in notes) {
      zeilen.add('Hinweis: $note');
    }
    return zeilen.join('\n');
  }
}

class R15SplitResult {
  const R15SplitResult(this.glb, this.report);

  /// Dieselbe Figur, aber als 15 benannte Meshes an einem Skelett.
  final Uint8List glb;
  final R15SplitReport report;
}

/// Zerlegt eine geriggte GLB in die 15 R15-Meshes.
///
/// Erwartet wird eine Datei mit genau einem Skin – so liefert sie
/// `prepareRigForRoblox`. Ohne Skin gibt es nichts zu zerlegen, denn
/// die Zuordnung hängt allein an den Gewichten.
R15SplitResult splitGlbIntoR15Parts(Uint8List glb) {
  final parts = splitGlb(glb);
  final json = parts.json;
  final skins = (json['skins'] as List?) ?? const [];
  if (skins.isEmpty) {
    throw Exception('Die Datei trägt kein Skelett. Die Zerlegung in 15 '
        'Meshes richtet sich nach den Skin-Gewichten – ohne die gibt '
        'es keinen Maßstab dafür, welches Dreieck zu welchem Teil '
        'gehört.');
  }
  final skin = skins.first as Map<String, dynamic>;
  final joints = ((skin['joints'] as List?) ?? const []).cast<num>();
  final nodes = (json['nodes'] as List?) ?? const [];

  // 1. Jedes Gelenk auf sein R15-Teil zurückführen.
  final (teilJeGelenk, zurueckgefuehrt, notes) =
      _mapJointsToParts(nodes, joints);

  // 2. Die Teilnetze durchgehen und jedes Dreieck zuordnen.
  final meshes = (json['meshes'] as List?) ?? const [];
  final anhang = GltfAppender(json, parts.bin);
  final neueMeshes = <Map<String, dynamic>>[];
  final neueNodes = <int>[];
  final zaehler = <String, int>{for (final name in r15PartNames) name: 0};
  final punkte = <String, int>{for (final name in r15PartNames) name: 0};
  final geometrie = <String, (Float32List, List<int>)>{};
  var ohneZuordnung = 0;

  for (final meshRaw in meshes) {
    final primitives =
        ((meshRaw as Map<String, dynamic>)['primitives'] as List?) ?? const [];
    for (final primRaw in primitives) {
      final prim = primRaw as Map<String, dynamic>;
      final attribute = prim['attributes'] as Map<String, dynamic>?;
      if (attribute == null) continue;
      final positionIndex = (attribute['POSITION'] as num?)?.toInt();
      final indexIndex = (prim['indices'] as num?)?.toInt();
      final jointIndex = (attribute['JOINTS_0'] as num?)?.toInt();
      final weightIndex = (attribute['WEIGHTS_0'] as num?)?.toInt();
      if (positionIndex == null ||
          indexIndex == null ||
          jointIndex == null ||
          weightIndex == null) {
        continue;
      }

      final indices = readGltfInts(json, parts.bin, indexIndex);
      final vertexJoints = readGltfInts(json, parts.bin, jointIndex);
      final vertexWeights =
          readGltfNormalizedFloats(json, parts.bin, weightIndex);

      // Je Dreieck: Gewichte der drei Ecken je Teil summieren, das
      // schwerste Teil gewinnt. Über die drei Ecken zu summieren
      // statt je Ecke zu entscheiden verhindert Einzeldreiecke, die
      // mitten in einer Fläche in ein Nachbarteil springen.
      final zuordnung = List<String>.filled(indices.length ~/ 3, '');
      final summe = <String, double>{};
      for (var t = 0; t + 2 < indices.length; t += 3) {
        summe.clear();
        for (var e = 0; e < 3; e++) {
          final v = indices[t + e];
          for (var k = 0; k < 4; k++) {
            final slot = v * 4 + k;
            if (slot >= vertexJoints.length || slot >= vertexWeights.length) {
              continue;
            }
            final gewicht = vertexWeights[slot];
            if (gewicht <= 0) continue;
            final teil = teilJeGelenk[vertexJoints[slot]];
            if (teil == null) continue;
            summe[teil] = (summe[teil] ?? 0) + gewicht;
          }
        }
        var bestes = '';
        var besterWert = 0.0;
        summe.forEach((teil, wert) {
          if (wert > besterWert) {
            besterWert = wert;
            bestes = teil;
          }
        });
        if (bestes.isEmpty) {
          // Kein Gewicht, kein Teil – ins Zentrum, damit kein Loch
          // bleibt. Ein fehlendes Dreieck sieht man der Figur an.
          bestes = 'LowerTorso';
          ohneZuordnung++;
        }
        zuordnung[t ~/ 3] = bestes;
      }

      _emitParts(
        json: json,
        bin: parts.bin,
        anhang: anhang,
        prim: prim,
        attribute: attribute,
        indices: indices,
        zuordnung: zuordnung,
        neueMeshes: neueMeshes,
        zaehler: zaehler,
        punkte: punkte,
        geometrie: geometrie,
      );
    }
  }

  // 3. Die neuen Meshes eintragen und die alten ersetzen.
  const skinIndex = 0;
  json['meshes'] = neueMeshes;
  final knoten = (json['nodes'] as List).cast<Map<String, dynamic>>();
  // Alte Netz-Knoten verlieren ihr Netz; die Gelenke bleiben, wo sie
  // sind – daran hängt die ganze Bindepose.
  final verwaist = <int>{};
  for (var i = 0; i < knoten.length; i++) {
    final node = knoten[i];
    if (!node.containsKey('mesh')) continue;
    node.remove('mesh');
    node.remove('skin');
    // Ein Knoten, der nur noch einen Namen trägt, ist Ballast: Der
    // glTF-Leser macht daraus ein leeres Objekt im Explorer, und in
    // Studio steht es dann neben den 15 Teilen herum.
    final rest = node.keys.toSet()..removeAll(['name']);
    if (rest.isEmpty) verwaist.add(i);
  }
  if (verwaist.isNotEmpty) {
    // Die Knoten bleiben im Feld stehen – ein Entfernen würde jeden
    // Index dahinter verschieben, und daran hängen Skin, Szene und
    // Animationen. Es reicht, sie aus dem Baum zu nehmen.
    for (final node in knoten) {
      final children = (node['children'] as List?)?.cast<num>();
      if (children == null) continue;
      final bleibt = [
        for (final c in children)
          if (!verwaist.contains(c.toInt())) c.toInt(),
      ];
      if (bleibt.length == children.length) continue;
      if (bleibt.isEmpty) {
        node.remove('children');
      } else {
        node['children'] = bleibt;
      }
    }
  }
  for (var i = 0; i < neueMeshes.length; i++) {
    knoten.add(<String, dynamic>{
      'name': neueMeshes[i]['name'],
      'mesh': i,
      'skin': skinIndex,
    });
    neueNodes.add(knoten.length - 1);
  }
  final scenes = (json['scenes'] as List);
  final sceneIndex = (json['scene'] as num?)?.toInt() ?? 0;
  final scene = scenes[sceneIndex] as Map<String, dynamic>;
  scene['nodes'] = [
    for (final v in ((scene['nodes'] as List?) ?? const []).cast<num>())
      if (!verwaist.contains(v.toInt())) v.toInt(),
    ...neueNodes,
  ];

  final teile = [
    for (final name in r15PartNames)
      R15Part(
        bone: name,
        triangles: zaehler[name] ?? 0,
        vertices: punkte[name] ?? 0,
        positions: geometrie[name]?.$1,
        indices: geometrie[name]?.$2,
      ),
  ];
  final gruppen = <String, int>{};
  for (final part in teile) {
    gruppen[part.group] = (gruppen[part.group] ?? 0) + part.triangles;
  }
  if (ohneZuordnung > 0) {
    notes.add('$ohneZuordnung Dreieck(e) trugen kein Gewicht und '
        'liegen jetzt im LowerTorso – verlorengehen darf keines.');
  }

  return R15SplitResult(
    joinGlb(json, anhang.finish()),
    R15SplitReport(
      parts: teile,
      groupTriangles: gruppen,
      tracedBones: zurueckgefuehrt,
      unmappedTriangles: ohneZuordnung,
      notes: notes,
    ),
  );
}

/// Ordnet jedem Gelenk sein R15-Teil zu.
///
/// Trägt ein Gelenk selbst keinen R15-Namen, wird die Elternkette
/// hochgegangen, bis einer kommt. Genau das macht Tripos
/// Zwischenknochen unschädlich: `tripo::Spine_1` hängt unter
/// `LowerTorso` und erbt dessen Teil.
(Map<int, String>, int, List<String>) _mapJointsToParts(
    List<dynamic> nodes, List<num> joints) {
  final elternteil = <int, int>{};
  for (var i = 0; i < nodes.length; i++) {
    for (final child in ((nodes[i] as Map)['children'] as List?) ?? const []) {
      elternteil[(child as num).toInt()] = i;
    }
  }
  final gueltig = r15PartNames.toSet();

  String? direkt(int node) {
    final name = (nodes[node] as Map)['name'] as String?;
    if (name == null) return null;
    if (gueltig.contains(name)) return name;
    final abgebildet = mapBoneToR15(name);
    // Der Wurzelknoten trägt selbst kein Netz.
    if (abgebildet == null || abgebildet == robloxRootBone) return null;
    return gueltig.contains(abgebildet) ? abgebildet : null;
  }

  final out = <int, String>{};
  var zurueckgefuehrt = 0;
  final unbekannt = <String>[];
  for (var i = 0; i < joints.length; i++) {
    final node = joints[i].toInt();
    var aktuell = node;
    String? teil;
    var schritte = 0;
    while (schritte++ < 64) {
      teil = direkt(aktuell);
      if (teil != null) break;
      final oben = elternteil[aktuell];
      if (oben == null) break;
      aktuell = oben;
    }
    if (teil == null) {
      final name = (nodes[node] as Map)['name'] as String? ?? 'Knochen $node';
      if (unbekannt.length < 6) unbekannt.add(name);
      continue;
    }
    // Der Index in JOINTS_0 zählt die Gelenke des Skins, nicht die
    // Knoten der Datei.
    out[i] = teil;
    if (aktuell != node) zurueckgefuehrt++;
  }

  final notes = <String>[];
  if (zurueckgefuehrt > 0) {
    notes.add('$zurueckgefuehrt Zwischenknochen auf ihren nächsten '
        'R15-Vorfahren zurückgeführt.');
  }
  if (unbekannt.isNotEmpty) {
    notes.add('Ohne R15-Zuordnung geblieben: ${unbekannt.join(', ')}.');
  }
  return (out, zurueckgefuehrt, notes);
}

/// Schreibt je Teil ein eigenes Mesh mit eigenen Accessoren.
void _emitParts({
  required Map<String, dynamic> json,
  required Uint8List bin,
  required GltfAppender anhang,
  required Map<String, dynamic> prim,
  required Map<String, dynamic> attribute,
  required List<int> indices,
  required List<String> zuordnung,
  required List<Map<String, dynamic>> neueMeshes,
  required Map<String, int> zaehler,
  required Map<String, int> punkte,
  required Map<String, (Float32List, List<int>)> geometrie,
}) {
  // Die Attribute einmal lesen; die Teile schneiden daraus aus.
  final quellen = <String, List<num>>{};
  final typen = <String, String>{};
  for (final key in attribute.keys) {
    final index = (attribute[key] as num).toInt();
    final accessor = (json['accessors'] as List)[index] as Map;
    typen[key] = accessor['type'] as String;
    quellen[key] = key == 'JOINTS_0'
        ? readGltfInts(json, bin, index)
        : (key == 'WEIGHTS_0'
            ? readGltfNormalizedFloats(json, bin, index)
            : readGltfFloats(json, bin, index));
  }

  for (final name in r15PartNames) {
    final dreiecke = <int>[];
    for (var t = 0; t < zuordnung.length; t++) {
      if (zuordnung[t] == name) dreiecke.add(t);
    }
    if (dreiecke.isEmpty) {
      // Roblox will alle 15. Ein leeres Mesh anzulegen wäre schlimmer
      // als keins: Der Validator lehnt Netze ohne Volumen ab. Der
      // Bericht nennt das Teil stattdessen als leer.
      continue;
    }

    // Punkte umnummerieren: Jedes Teil bekommt nur die Punkte, die es
    // braucht, in eigener Zählung.
    final neuIndex = <int, int>{};
    final neueIndices = <int>[];
    for (final t in dreiecke) {
      for (var e = 0; e < 3; e++) {
        final alt = indices[t * 3 + e];
        neueIndices.add(neuIndex.putIfAbsent(alt, () => neuIndex.length));
      }
    }
    final reihenfolge = List<int>.filled(neuIndex.length, 0);
    neuIndex.forEach((alt, neu) => reihenfolge[neu] = alt);

    final neueAttribute = <String, dynamic>{};
    for (final key in quellen.keys) {
      final teile = gltfComponentCount(typen[key]!);
      final quelle = quellen[key]!;
      if (key == 'JOINTS_0') {
        final werte = <int>[];
        for (final alt in reihenfolge) {
          for (var k = 0; k < teile; k++) {
            werte.add(quelle[alt * teile + k].toInt());
          }
        }
        neueAttribute[key] = anhang.addUint16(werte, typen[key]!);
        continue;
      }
      final werte = Float32List(reihenfolge.length * teile);
      for (var i = 0; i < reihenfolge.length; i++) {
        for (var k = 0; k < teile; k++) {
          werte[i * teile + k] =
              quelle[reihenfolge[i] * teile + k].toDouble();
        }
      }
      // POSITION braucht min/max – ohne die rechnen manche Leser die
      // Szene falsch aus.
      List<num>? min, max;
      if (key == 'POSITION' && teile == 3) {
        min = [double.infinity, double.infinity, double.infinity];
        max = [
          double.negativeInfinity,
          double.negativeInfinity,
          double.negativeInfinity
        ];
        for (var i = 0; i < werte.length; i += 3) {
          for (var k = 0; k < 3; k++) {
            min[k] = math.min(min[k].toDouble(), werte[i + k]);
            max[k] = math.max(max[k].toDouble(), werte[i + k]);
          }
        }
      }
      neueAttribute[key] =
          anhang.addFloats(werte, typen[key]!, min: min, max: max);
    }

    neueMeshes.add(<String, dynamic>{
      'name': '${name}_Geo',
      'primitives': [
        <String, dynamic>{
          'attributes': neueAttribute,
          'indices': anhang.addIndices(neueIndices, reihenfolge.length),
          if (prim['material'] != null) 'material': prim['material'],
          'mode': 4,
        }
      ],
    });
    zaehler[name] = (zaehler[name] ?? 0) + dreiecke.length;
    punkte[name] = (punkte[name] ?? 0) + reihenfolge.length;
    // Für die Deckungsprüfung: die Geometrie des Teils, wie sie in
    // der Datei landet.
    final positionAccessor = neueAttribute['POSITION'] as int?;
    if (positionAccessor != null) {
      final quelle = quellen['POSITION']!;
      final werte = Float32List(reihenfolge.length * 3);
      for (var i = 0; i < reihenfolge.length; i++) {
        for (var k = 0; k < 3; k++) {
          werte[i * 3 + k] = quelle[reihenfolge[i] * 3 + k].toDouble();
        }
      }
      geometrie[name] = (werte, neueIndices);
    }
  }
}
