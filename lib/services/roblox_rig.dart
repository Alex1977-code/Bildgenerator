/// R15-Benennung für Roblox: der Schritt, an dem alles hängt.
///
/// Eine Figur muss für Roblox **nicht** in 15 MeshParts zerschnitten
/// werden. Es reicht, die Knochen nach der R15-Konvention zu benennen
/// und auf ein einziges Mesh zu skinnen. Genau daran scheitern
/// KI-Rigs: Tripos Auto-Rig mit `spec: "mixamo"` liefert Namen wie
/// `mixamorig:Hips`, der eigene Auto-Rigger dieser App `Hips`,
/// `Chest`, `Shoulder_L` – Roblox erwartet `LowerTorso`, `UpperTorso`,
/// `LeftUpperArm`.
///
/// Diese Datei nimmt das Umbenennen ab. Sie fasst nur die Namen im
/// JSON-Teil der GLB an; Geometrie, Gewichte und Texturen bleiben Byte
/// für Byte unberührt.
///
/// Eine Eigenheit von R15 wird dabei mitgebaut: Der Wurzelknochen muss
/// **HumanoidRootPart** heißen, im Ursprung sitzen und **keine**
/// Vertices beeinflussen. KI-Rigs haben stattdessen die Hüfte als
/// Wurzel, und die ist gewichtet. Deshalb wird ein neuer, leerer
/// Knoten darüber gesetzt – er kommt bewusst nicht in die
/// Skin-Gelenkliste, dadurch ist er garantiert ohne Gewichtung.
library;

import 'dart:typed_data';

import 'glb_preview.dart';

/// Die 15 Gelenknamen der R15-Konvention, in der Reihenfolge, in der
/// Roblox sie aufführt.
const List<String> robloxR15Bones = [
  'HumanoidRootPart',
  'LowerTorso',
  'UpperTorso',
  'Head',
  'LeftUpperArm',
  'LeftLowerArm',
  'LeftHand',
  'RightUpperArm',
  'RightLowerArm',
  'RightHand',
  'LeftUpperLeg',
  'LeftLowerLeg',
  'LeftFoot',
  'RightUpperLeg',
  'RightLowerLeg',
  'RightFoot',
];

/// Der Wurzelknochen. Roblox' Dokumentation ist hier eindeutig: nicht
/// „HumanoidRootNode", sondern genau dieser Name.
const String robloxRootBone = 'HumanoidRootPart';

/// Übersetzt einen vorhandenen Knochennamen in seinen R15-Namen.
///
/// Erkannt werden die Mixamo-Namen (mit und ohne `mixamorig:`), die
/// Namen des eigenen Auto-Riggers und die geläufigen Schreibweisen
/// anderer Werkzeuge. Liefert null, wenn der Knochen in R15 kein
/// Gegenstück hat (etwa Finger, ein zweiter Wirbelsäulenknochen oder
/// die Knochenspitzen).
String? mapBoneToR15(String raw) {
  var name = raw.trim();
  // Mixamo hängt allem ein „mixamorig:" voran, Blender an Duplikate
  // ein „.001".
  final colon = name.lastIndexOf(':');
  if (colon >= 0) name = name.substring(colon + 1);
  name = name.replaceAll(RegExp(r'\.\d+$'), '');
  final key = name.toLowerCase().replaceAll(RegExp(r'[ _\-.]'), '');

  // Seite und Rolle getrennt bestimmen: „LeftForeArm", „Elbow_L" und
  // „L Elbow" meinen dasselbe.
  var side = '';
  var rest = key;
  for (final (prefix, value) in [('left', 'Left'), ('right', 'Right')]) {
    if (rest.startsWith(prefix)) {
      side = value;
      rest = rest.substring(prefix.length);
      break;
    }
  }
  if (side.isEmpty) {
    for (final (suffix, value) in [
      ('left', 'Left'),
      ('right', 'Right'),
      ('l', 'Left'),
      ('r', 'Right'),
    ]) {
      if (rest.length > suffix.length && rest.endsWith(suffix)) {
        side = value;
        rest = rest.substring(0, rest.length - suffix.length);
        break;
      }
    }
  }

  if (side.isEmpty) {
    return switch (rest) {
      'hips' || 'hip' || 'pelvis' || 'lowertorso' => 'LowerTorso',
      'chest' ||
      'spine2' ||
      'upperchest' ||
      'uppertorso' =>
        'UpperTorso',
      'head' => 'Head',
      'humanoidrootpart' || 'humanoidrootnode' || 'root' => robloxRootBone,
      _ => null,
    };
  }
  return switch (rest) {
    'shoulder' || 'arm' || 'upperarm' => '${side}UpperArm',
    'elbow' || 'forearm' || 'lowerarm' => '${side}LowerArm',
    'hand' => '${side}Hand',
    'upperleg' || 'upleg' || 'thigh' => '${side}UpperLeg',
    'knee' || 'leg' || 'lowerleg' || 'shin' || 'calf' => '${side}LowerLeg',
    'foot' || 'ankle' => '${side}Foot',
    _ => null,
  };
}

/// Was beim Umbenennen herauskam.
class RobloxRigReport {
  const RobloxRigReport({
    required this.renamed,
    required this.missing,
    required this.untouched,
    required this.rootAdded,
    required this.alreadyR15,
  });

  /// Alter Name → R15-Name.
  final Map<String, String> renamed;

  /// R15-Gelenke, für die sich kein Knochen fand. Ohne sie taugt die
  /// Figur nur für den Import-Weg „Custom", nicht als StarterCharacter.
  final List<String> missing;

  /// Knochen ohne R15-Gegenstück – sie bleiben, wie sie heißen
  /// (Finger, zusätzliche Wirbel, Knochenspitzen).
  final List<String> untouched;

  /// Ob ein HumanoidRootPart über der bisherigen Wurzel eingezogen
  /// wurde.
  final bool rootAdded;

  /// Ob die Datei schon vorher R15-Namen trug.
  final bool alreadyR15;

  bool get complete => missing.isEmpty;

  /// Wie viele der 15 Gelenke stehen.
  int get found => robloxR15Bones.length - missing.length;
}

/// Ergebnis von [renameBonesToR15]: die neue Datei und der Bericht.
class RobloxRigResult {
  const RobloxRigResult(this.glb, this.report);

  final Uint8List glb;
  final RobloxRigReport report;
}

/// Benennt die Knochen einer geriggten GLB nach R15 um.
///
/// Wirft eine [Exception], wenn die Datei gar kein Skelett trägt –
/// dann ist der Rig-Weg ohnehin nicht gangbar.
RobloxRigResult renameBonesToR15(Uint8List glb) {
  final parts = splitGlb(glb);
  final json = parts.json;
  final nodes = (json['nodes'] as List?)?.cast<Map<String, dynamic>>();
  final skins = (json['skins'] as List?)?.cast<Map<String, dynamic>>();
  if (nodes == null || skins == null || skins.isEmpty) {
    throw Exception(
        'Diese Datei trägt kein Skelett – für den Roblox-Rig-Weg '
        'braucht es eine geriggte Figur.');
  }

  final skin = skins.first;
  final joints = (skin['joints'] as List? ?? const []).cast<int>();
  if (joints.isEmpty) {
    throw Exception('Das Skelett enthält keine Gelenke.');
  }

  final renamed = <String, String>{};
  final untouched = <String>[];
  final taken = <String>{
    for (final node in nodes)
      if (node['name'] is String) node['name'] as String,
  };
  var alreadyR15 = 0;

  for (final index in joints) {
    final node = nodes[index];
    final current = (node['name'] as String? ?? '').trim();
    if (robloxR15Bones.contains(current)) {
      alreadyR15++;
      continue;
    }
    final target = mapBoneToR15(current);
    if (target == null) {
      if (current.isNotEmpty) untouched.add(current);
      continue;
    }
    // Zwei Knochen auf denselben R15-Namen abzubilden würde das Rig
    // unbrauchbar machen – der zweite behält seinen Namen.
    if (taken.contains(target) && current != target) {
      untouched.add(current);
      continue;
    }
    taken.remove(current);
    taken.add(target);
    node['name'] = target;
    renamed[current] = target;
  }

  // Welche der 15 stehen jetzt?
  final present = <String>{
    for (final index in joints)
      if (nodes[index]['name'] is String) nodes[index]['name'] as String,
  };

  // Wurzelknochen: Er muss HumanoidRootPart heißen, im Ursprung
  // sitzen und ohne Gewichtung sein. Ein neuer, leerer Knoten über der
  // bisherigen Wurzel erfüllt alle drei Bedingungen auf einmal – und
  // weil er nicht in die Gelenkliste kommt, bleiben die
  // Gewichts-Indizes unverändert.
  var rootAdded = false;
  if (!present.contains(robloxRootBone)) {
    final jointSet = joints.toSet();
    final childOf = <int, int>{};
    for (var i = 0; i < nodes.length; i++) {
      for (final child in (nodes[i]['children'] as List? ?? const [])) {
        childOf[child as int] = i;
      }
    }
    final roots = [
      for (final joint in joints)
        if (!jointSet.contains(childOf[joint])) joint,
    ];
    if (roots.isNotEmpty) {
      final rootIndex = nodes.length;
      nodes.add({
        'name': robloxRootBone,
        'translation': [0.0, 0.0, 0.0],
        'rotation': [0.0, 0.0, 0.0, 1.0],
        'scale': [1.0, 1.0, 1.0],
        'children': roots,
      });
      // Die alten Wurzeln hängen jetzt unter dem neuen Knoten; in der
      // Szene steht an ihrer Stelle er.
      for (final scene in (json['scenes'] as List? ?? const [])) {
        final list = (scene as Map<String, dynamic>)['nodes'] as List?;
        if (list == null) continue;
        var replaced = false;
        for (final root in roots) {
          if (list.remove(root)) replaced = true;
        }
        if (replaced) list.add(rootIndex);
      }
      // Kein Elternknoten mehr für die alten Wurzeln ausser dem neuen.
      for (var i = 0; i < nodes.length - 1; i++) {
        final children = nodes[i]['children'] as List?;
        if (children == null) continue;
        children.removeWhere(roots.contains);
        if (children.isEmpty) nodes[i].remove('children');
      }
      nodes[rootIndex]['children'] = roots;
      skin['skeleton'] = rootIndex;
      present.add(robloxRootBone);
      rootAdded = true;
    }
  }

  final missing = [
    for (final bone in robloxR15Bones)
      if (!present.contains(bone)) bone,
  ];

  return RobloxRigResult(
    joinGlb(json, parts.bin),
    RobloxRigReport(
      renamed: renamed,
      missing: missing,
      untouched: untouched,
      rootAdded: rootAdded,
      alreadyR15: alreadyR15 >= robloxR15Bones.length - 1,
    ),
  );
}

/// Liest die Knochennamen einer GLB – für die Prüfliste, ohne die
/// Datei zu ändern.
List<String> readBoneNames(Uint8List glb) {
  final parts = splitGlb(glb);
  final nodes = (parts.json['nodes'] as List?)?.cast<Map<String, dynamic>>();
  final skins = (parts.json['skins'] as List?)?.cast<Map<String, dynamic>>();
  if (nodes == null || skins == null || skins.isEmpty) return const [];
  final joints = (skins.first['joints'] as List? ?? const []).cast<int>();
  return [
    for (final index in joints)
      if (index < nodes.length && nodes[index]['name'] is String)
        nodes[index]['name'] as String,
  ];
}

/// Welche der 15 R15-Gelenke in dieser Namensliste fehlen.
List<String> missingR15Bones(List<String> names) {
  final present = names.toSet();
  return [
    for (final bone in robloxR15Bones)
      if (!present.contains(bone)) bone,
  ];
}
