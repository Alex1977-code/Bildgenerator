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

import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart';
import 'roblox_spec.dart';

/// Die Gelenknamen der R15-Konvention, in der Reihenfolge der
/// offiziellen Hierarchie – abgeleitet aus [specR15Hierarchy], damit
/// Liste und Baum nicht auseinanderlaufen können.
final List<String> robloxR15Bones = specR15Joints;

/// Der Wurzelknochen der Figur.
///
/// Hier stand `HumanoidRootPart`, mit dem Kommentar, die
/// Dokumentation sei eindeutig. Ist sie nicht: Für den **Import eines
/// Figurenkörpers** – und das ist der Weg, den diese App geht –
/// nennen die Spezifikation und das Prüfwerkzeug `HumanoidRootNode`,
/// mit einem Knochen `Root` darüber. `HumanoidRootPart` steht in der
/// Anleitung für den **Animations-Export aus Maya**. Siehe
/// [specRootNode].
const String robloxRootBone = specRootNode;

/// Der Knochen über dem Wurzelknochen. Er muss im Ursprung liegen und
/// darf keine Gewichtung tragen.
const String robloxRootParent = specRootBone;

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
    this.structure,
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

  /// Was die Struktur-Erkennung gesehen hat, falls sie gebraucht wurde
  /// (siehe [detectR15ByStructure]) – null, wenn die Namen des
  /// Anbieters schon gereicht haben.
  final R15Structure? structure;

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
  var present = <String>{
    for (final index in joints)
      if (nodes[index]['name'] is String) nodes[index]['name'] as String,
  };

  // Zweiter Anlauf über die Form des Skeletts. Tripo nennt seine
  // Knochen „tripo::0_Left_Limb_2" und „bone_6" – daraus liest kein
  // Namensvergleich eine Rolle heraus, die Gestalt des Skeletts gibt
  // sie aber eindeutig her.
  R15Structure? structure;
  if (present.intersection(robloxR15Bones.toSet()).length <
      robloxR15Bones.length - 4) {
    final parentOf = _parentMap(nodes);
    structure = detectR15ByStructure(
        nodes, joints, parentOf, _worldMatrices(nodes, parentOf));
    for (final entry in (structure?.names ?? const <int, String>{}).entries) {
      final node = nodes[entry.key];
      final current = (node['name'] as String? ?? '').trim();
      if (current == entry.value) continue;
      // Wer schon eine andere R15-Rolle trägt, behält sie.
      if (robloxR15Bones.contains(current)) continue;
      if (taken.contains(entry.value)) continue;
      taken.remove(current);
      taken.add(entry.value);
      node['name'] = entry.value;
      renamed[current.isEmpty ? '(ohne Namen)' : current] = entry.value;
      untouched.remove(current);
    }
    present = <String>{
      for (final index in joints)
        if (nodes[index]['name'] is String) nodes[index]['name'] as String,
    };
  }

  // Wurzelknochen: Über der bisherigen Wurzel entstehen zwei neue,
  // leere Knoten – `Root` ganz oben und darunter
  // `HumanoidRootNode`, genau wie in der Spezifikation
  // (specR15Hierarchy). Beide sitzen im Ursprung und tragen keine
  // Gewichtung; weil sie nicht in die Gelenkliste kommen, bleiben die
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
      // Der Elternknochen `Root` darüber. Das Prüfwerkzeug von Roblox
      // sucht ausdrücklich nach beiden („Root and HumanoidRootNode
      // bones exist").
      final parentIndex = nodes.length;
      nodes.add({
        'name': robloxRootParent,
        'translation': [0.0, 0.0, 0.0],
        'rotation': [0.0, 0.0, 0.0, 1.0],
        'scale': [1.0, 1.0, 1.0],
        'children': [rootIndex],
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
        if (replaced) list.add(parentIndex);
      }
      // Kein Elternknoten mehr für die alten Wurzeln ausser dem neuen.
      for (var i = 0; i < nodes.length - 2; i++) {
        final children = nodes[i]['children'] as List?;
        if (children == null) continue;
        children.removeWhere(roots.contains);
        if (children.isEmpty) nodes[i].remove('children');
      }
      nodes[rootIndex]['children'] = roots;
      skin['skeleton'] = parentIndex;
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
      structure: structure,
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

// ---------------------------------------------------------------------
// Skelett vermessen
//
// Für alles Weitere braucht es drei Dinge: wer ist wessen Elternteil,
// wo steht jeder Knochen in der Welt, und welche Rolle spielt er.
// Namen taugen dafür nur bedingt – Tripo liefert „tripo::0_Left_Limb_2"
// und „bone_6", und die Seitenangabe darin stimmt nicht einmal
// zuverlässig. Die Struktur stimmt dagegen immer: Beine hängen unten,
// Arme zweigen an derselben Stelle nach beiden Seiten ab, der Kopf
// sitzt darüber.
// ---------------------------------------------------------------------

/// Lokale Transformation eines Knotens als 4×4-Matrix (spaltenweise,
/// wie glTF sie ablegt).
Float64List _localMatrix(Map<String, dynamic> node) {
  final raw = node['matrix'];
  if (raw is List && raw.length == 16) {
    return Float64List.fromList(
        [for (final v in raw) (v as num).toDouble()]);
  }
  final t = _vec(node['translation'], const [0.0, 0.0, 0.0]);
  final r = _vec(node['rotation'], const [0.0, 0.0, 0.0, 1.0]);
  final s = _vec(node['scale'], const [1.0, 1.0, 1.0]);
  final x = r[0], y = r[1], z = r[2], w = r[3];
  final m = Float64List(16);
  m[0] = (1 - 2 * (y * y + z * z)) * s[0];
  m[1] = (2 * (x * y + z * w)) * s[0];
  m[2] = (2 * (x * z - y * w)) * s[0];
  m[4] = (2 * (x * y - z * w)) * s[1];
  m[5] = (1 - 2 * (x * x + z * z)) * s[1];
  m[6] = (2 * (y * z + x * w)) * s[1];
  m[8] = (2 * (x * z + y * w)) * s[2];
  m[9] = (2 * (y * z - x * w)) * s[2];
  m[10] = (1 - 2 * (x * x + y * y)) * s[2];
  m[12] = t[0];
  m[13] = t[1];
  m[14] = t[2];
  m[15] = 1;
  return m;
}

List<double> _vec(Object? raw, List<double> fallback) {
  if (raw is List && raw.length >= fallback.length) {
    return [for (var i = 0; i < fallback.length; i++) (raw[i] as num).toDouble()];
  }
  return List<double>.from(fallback);
}

Float64List _matMul(Float64List a, Float64List b) {
  final out = Float64List(16);
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

/// Knoten → Elternknoten.
Map<int, int> _parentMap(List<Map<String, dynamic>> nodes) {
  final out = <int, int>{};
  for (var i = 0; i < nodes.length; i++) {
    for (final child in (nodes[i]['children'] as List? ?? const [])) {
      out[(child as num).toInt()] = i;
    }
  }
  return out;
}

/// Weltmatrizen aller Knoten, von den Wurzeln aus zusammengesetzt.
Map<int, Float64List> _worldMatrices(
    List<Map<String, dynamic>> nodes, Map<int, int> parentOf) {
  final world = <int, Float64List>{};
  void walk(int index, Float64List parent) {
    if (world.containsKey(index)) return; // Zyklen abfangen
    final here = _matMul(parent, _localMatrix(nodes[index]));
    world[index] = here;
    for (final child in (nodes[index]['children'] as List? ?? const [])) {
      walk((child as num).toInt(), here);
    }
  }

  final identity = Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;
  for (var i = 0; i < nodes.length; i++) {
    if (!parentOf.containsKey(i)) walk(i, identity);
  }
  // Knoten in einem Zyklus oder ohne erreichbare Wurzel: als Wurzel
  // behandeln, sonst fehlen sie in der Auswertung.
  for (var i = 0; i < nodes.length; i++) {
    if (!world.containsKey(i)) walk(i, identity);
  }
  return world;
}

/// Das Ergebnis der Struktur-Erkennung.
class R15Structure {
  const R15Structure({
    required this.names,
    required this.forwardAxis,
    required this.forwardSign,
    required this.sideAxis,
    required this.leftSign,
    required this.facingFromToes,
    required this.mirroredNames,
    required this.notes,
  });

  /// Knotenindex → R15-Name.
  final Map<int, String> names;

  /// Achse, in die die Figur blickt: 0 = x, 2 = z, dazu das Vorzeichen.
  final int forwardAxis;
  final double forwardSign;

  /// Achse, auf der die Arme auseinanderstehen, und die Richtung, in
  /// der die **linke** Körperhälfte liegt.
  final int sideAxis;
  final double leftSign;

  /// Ob die Blickrichtung aus den Zehen abgeleitet werden konnte
  /// (sonst steht sie nur auf der Annahme der glTF-Konvention).
  final bool facingFromToes;

  /// Ob die Namen des Anbieters links und rechts vertauscht haben.
  final bool mirroredNames;

  final List<String> notes;

  /// Blickrichtung als Text, etwa „+x".
  String get facing =>
      '${forwardSign < 0 ? '-' : '+'}${forwardAxis == 0 ? 'x' : 'z'}';
}

/// Ordnet die Knochen eines zweibeinigen Skeletts allein anhand seiner
/// Form den R15-Gelenken zu.
///
/// Der Weg dorthin, Schritt für Schritt:
///
/// 1. **Seitenachse.** Von den beiden waagerechten Achsen ist das die
///    mit der größeren Spannweite – bei ausgestreckten Armen die
///    Armspanne. Ist der Unterschied zu klein, ist die Figur nicht
///    eindeutig genug und die Erkennung bricht ab.
/// 2. **Arme.** Die beiden seitlich äußersten Gelenke, von dort
///    aufwärts bis zur ersten gemeinsamen Gabelung: das ist die Brust.
///    Der Ast, der ab der Brust zur Hand führt, ist der Arm; seine
///    letzten drei Gelenke sind Ober-, Unterarm und Hand. „Letzte
///    drei" statt „erste drei", weil manche Rigs davor noch ein
///    Schlüsselbein setzen – und zwar nicht auf beiden Seiten gleich.
/// 3. **Beine.** Dasselbe von unten: die beiden tiefsten Gelenke,
///    aufwärts bis zur Gabelung (der Hüfte). Ab dem Beinansatz die
///    **ersten** drei Gelenke – Zehen hängen hinten dran und haben in
///    R15 kein Gegenstück.
/// 4. **Rumpf.** Der Weg von der Wurzel zur Brust: die Brust wird
///    UpperTorso, das Gelenk direkt über der Wurzel LowerTorso.
/// 5. **Kopf.** Der Ast der Brust, der weder Arm noch Rumpf ist.
/// 6. **Links und rechts.** Erst die Blickrichtung: der Schritt vom
///    Fuß zum Zeh zeigt nach vorn. Links ist dann „oben × vorn". Ohne
///    Zehenknochen bleibt nur die glTF-Konvention (Vorderseite zu
///    +z) – das steht dann so im Bericht.
R15Structure? detectR15ByStructure(
  List<Map<String, dynamic>> nodes,
  List<int> joints,
  Map<int, int> parentOf,
  Map<int, Float64List> world,
) {
  if (joints.length < 10) return null;
  final notes = <String>[];
  final jointSet = joints.toSet();
  List<double> at(int j) {
    final m = world[j]!;
    return [m[12], m[13], m[14]];
  }

  final children = <int, List<int>>{for (final j in joints) j: []};
  final roots = <int>[];
  for (final j in joints) {
    final p = parentOf[j];
    if (p != null && jointSet.contains(p)) {
      children[p]!.add(j);
    } else {
      roots.add(j);
    }
  }
  if (roots.isEmpty) return null;
  int subtreeSize(int j) {
    var n = 1;
    for (final c in children[j]!) {
      n += subtreeSize(c);
    }
    return n;
  }

  roots.sort((a, b) => subtreeSize(b).compareTo(subtreeSize(a)));
  final root = roots.first;

  // 1. Seitenachse
  var minX = double.infinity, maxX = -double.infinity;
  var minZ = double.infinity, maxZ = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final j in joints) {
    final p = at(j);
    minX = math.min(minX, p[0]);
    maxX = math.max(maxX, p[0]);
    minY = math.min(minY, p[1]);
    maxY = math.max(maxY, p[1]);
    minZ = math.min(minZ, p[2]);
    maxZ = math.max(maxZ, p[2]);
  }
  final spreadX = maxX - minX, spreadZ = maxZ - minZ;
  final height = maxY - minY;
  if (height <= 0) return null;
  final sideAxis = spreadX >= spreadZ ? 0 : 2;
  final wide = math.max(spreadX, spreadZ);
  final narrow = math.min(spreadX, spreadZ);
  if (wide < narrow * 1.25) {
    // Zu quadratisch von oben: dann ist nicht zu entscheiden, welche
    // Achse die Armspanne ist. Lieber gar nicht raten.
    return null;
  }
  final forwardAxis = sideAxis == 0 ? 2 : 0;

  List<int> pathToRoot(int j) {
    final out = <int>[];
    int? cur = j;
    while (cur != null && out.length <= joints.length) {
      out.add(cur);
      final p = parentOf[cur];
      cur = (p != null && jointSet.contains(p)) ? p : null;
    }
    return out;
  }

  /// Der tiefste gemeinsame Vorfahre zweier Gelenke.
  int? commonAncestor(int a, int b) {
    final pa = pathToRoot(a).reversed.toList();
    final pb = pathToRoot(b).reversed.toList();
    int? last;
    for (var i = 0; i < math.min(pa.length, pb.length); i++) {
      if (pa[i] != pb[i]) break;
      last = pa[i];
    }
    return last;
  }

  /// Der Ast von [branch] aus, auf dem [leaf] liegt.
  int? branchTowards(int branch, int leaf) {
    final path = pathToRoot(leaf);
    final at = path.indexOf(branch);
    return at > 0 ? path[at - 1] : null;
  }

  List<int> mainChain(int start) {
    final out = [start];
    var cur = start;
    while (children[cur]!.length == 1) {
      cur = children[cur]!.first;
      out.add(cur);
    }
    return out;
  }

  // 2. Arme: die seitlich äußersten Gelenke
  int? farPlus, farMinus;
  for (final j in joints) {
    if (j == root) continue;
    final s = at(j)[sideAxis];
    if (farPlus == null || s > at(farPlus)[sideAxis]) farPlus = j;
    if (farMinus == null || s < at(farMinus)[sideAxis]) farMinus = j;
  }
  if (farPlus == null || farMinus == null || farPlus == farMinus) return null;
  final chest = commonAncestor(farPlus, farMinus);
  if (chest == null) return null;
  final armRootPlus = branchTowards(chest, farPlus);
  final armRootMinus = branchTowards(chest, farMinus);
  if (armRootPlus == null || armRootMinus == null) return null;

  // 3. Beine: die tiefsten Gelenke
  int? lowPlus, lowMinus;
  for (final j in joints) {
    // Die Wurzel bleibt außen vor: Tripo setzt sie auf den Boden,
    // damit wäre sie das tiefste Gelenk – und die Beinsuche liefe an
    // ihr fest.
    if (j == root) continue;
    final p = at(j);
    if (p[sideAxis] >= 0) {
      if (lowPlus == null || p[1] < at(lowPlus)[1]) lowPlus = j;
    } else {
      if (lowMinus == null || p[1] < at(lowMinus)[1]) lowMinus = j;
    }
  }
  if (lowPlus == null || lowMinus == null) return null;
  final hips = commonAncestor(lowPlus, lowMinus);
  if (hips == null) return null;
  final legRootPlus = branchTowards(hips, lowPlus);
  final legRootMinus = branchTowards(hips, lowMinus);
  if (legRootPlus == null || legRootMinus == null) return null;
  if (legRootPlus == armRootPlus || legRootMinus == armRootMinus) return null;

  final armPlus = mainChain(armRootPlus);
  final armMinus = mainChain(armRootMinus);
  final legPlus = mainChain(legRootPlus);
  final legMinus = mainChain(legRootMinus);
  if (armPlus.length < 3 || armMinus.length < 3) return null;
  if (legPlus.length < 3 || legMinus.length < 3) return null;

  // 6. Blickrichtung aus den Zehen
  var forwardSum = 0.0, horizontalSum = 0.0;
  for (final leg in [legPlus, legMinus]) {
    if (leg.length < 4) continue;
    final foot = at(leg[2]);
    final toe = at(leg[3]);
    final df = toe[forwardAxis] - foot[forwardAxis];
    final ds = toe[sideAxis] - foot[sideAxis];
    forwardSum += df;
    horizontalSum += math.sqrt(df * df + ds * ds);
  }
  var facingFromToes = false;
  var forwardSign = 1.0;
  if (horizontalSum > height * 0.005 &&
      forwardSum.abs() > horizontalSum * 0.4) {
    forwardSign = forwardSum < 0 ? -1.0 : 1.0;
    facingFromToes = true;
  } else if (forwardAxis == 2) {
    notes.add('Kein Zehenknochen: Blickrichtung nach der '
        'glTF-Konvention auf +z angenommen.');
  } else {
    notes.add('Kein Zehenknochen und die Armspanne liegt auf z: '
        'Blickrichtung auf +x angenommen. Sitzt die Figur danach '
        'verkehrt herum, im Viewer um 180° drehen.');
  }
  // Links ist „oben × vorn": für vorn = (fx,0,fz) also (fz,0,-fx).
  final leftSign = forwardAxis == 0 ? -forwardSign : forwardSign;

  final leftArm = leftSign > 0 ? armPlus : armMinus;
  final rightArm = leftSign > 0 ? armMinus : armPlus;
  final leftLeg = leftSign > 0 ? legPlus : legMinus;
  final rightLeg = leftSign > 0 ? legMinus : legPlus;

  // Stimmen die Namen des Anbieters mit der Geometrie überein?
  var mirrored = false;
  String nameOf(int j) => (nodes[j]['name'] as String? ?? '').toLowerCase();
  final leftSaysRight = leftArm.any((j) => nameOf(j).contains('right'));
  final rightSaysLeft = rightArm.any((j) => nameOf(j).contains('left'));
  if (leftSaysRight && rightSaysLeft) {
    mirrored = true;
  }

  final names = <int, String>{};
  names[root] = robloxRootBone;
  // 4. Rumpf
  final spine = pathToRoot(chest).reversed.toList(); // Wurzel → Brust
  if (spine.length >= 3) {
    names[spine[1]] = 'LowerTorso';
  }
  if (chest != root) names[chest] = 'UpperTorso';
  // 5. Kopf
  int? head;
  for (final c in children[chest]!) {
    if (c == armRootPlus || c == armRootMinus) continue;
    if (head == null || at(c)[1] > at(head)[1]) head = c;
  }
  if (head != null && at(head)[1] > at(chest)[1]) names[head] = 'Head';

  for (final (side, arm) in [('Left', leftArm), ('Right', rightArm)]) {
    final tail = arm.sublist(arm.length - 3);
    names[tail[0]] = '${side}UpperArm';
    names[tail[1]] = '${side}LowerArm';
    names[tail[2]] = '${side}Hand';
  }
  for (final (side, leg) in [('Left', leftLeg), ('Right', rightLeg)]) {
    names[leg[0]] = '${side}UpperLeg';
    names[leg[1]] = '${side}LowerLeg';
    names[leg[2]] = '${side}Foot';
  }

  return R15Structure(
    names: names,
    forwardAxis: forwardAxis,
    forwardSign: forwardSign,
    sideAxis: sideAxis,
    leftSign: leftSign,
    facingFromToes: facingFromToes,
    mirroredNames: mirrored,
    notes: notes,
  );
}

// ---------------------------------------------------------------------
// Für den Import fertigmachen
//
// Was Roblox über die Namen hinaus verlangt und wo KI-Rigs reihenweise
// hängenbleiben:
//
// * **Scale 1,1,1 und Rotation 0,0,0 an jedem Knochen.** Tripo legt
//   die Knochen in ihrer eigenen Achsenlage ab – 32 von 43 Gelenken
//   tragen dann eine Drehung. Der Importer rechnet sie nicht heraus,
//   er lehnt sie ab. Die Lösung ist nicht, die Drehungen wegzuwerfen:
//   Jedes Gelenk bekommt stattdessen die Verschiebung, die es an
//   dieselbe Weltposition bringt, und die Bind-Matrizen werden dazu
//   passend neu gerechnet. Die Ruhepose sieht danach aus wie vorher,
//   nur ohne Drehungen im Baum.
// * **Wurzelknochen im Ursprung.** Tripos Wurzel steht ein paar
//   Millimeter daneben. Verschoben wird das ganze Modell samt Netz,
//   nicht nur der Knochen – sonst stünde das Skelett neben der Figur.
// * **Blickrichtung.** glTF legt fest: die Vorderseite zeigt nach +z.
//   Tripo liefert die Figur um 90° gedreht, die Armspanne liegt dann
//   auf z statt auf x. In Roblox läuft sie damit seitwärts.
// ---------------------------------------------------------------------

/// Was beim Fertigmachen passiert ist.
class RobloxPrepareReport {
  const RobloxPrepareReport({
    required this.rig,
    required this.structure,
    required this.flattenedRotations,
    required this.flattenedScales,
    required this.unweightedVertices,
    required this.scale,
    required this.heightStuds,
    required this.hipStuds,
    required this.shift,
    required this.turnedDegrees,
    required this.notes,
  });

  /// Das Ergebnis der Umbenennung.
  final RobloxRigReport rig;

  /// Was die Struktur-Erkennung gesehen hat – null, wenn die Form des
  /// Skeletts nicht eindeutig war.
  final R15Structure? structure;

  /// Wie viele Gelenke eine Drehung bzw. Skalierung trugen.
  final int flattenedRotations;
  final int flattenedScales;

  /// Wie viele Vertices dem Wurzelknochen abgenommen wurden.
  final int unweightedVertices;

  /// Mit welchem Faktor das Modell auf Roblox-Maß gebracht wurde
  /// (1 = unverändert).
  final double scale;

  /// Höhe der fertigen Figur in Studs – der Importer liest eine
  /// Datei-Einheit als einen Stud.
  final double heightStuds;

  /// Höhe des Hüftgelenks in Studs. Daraus ergibt sich der Startwert
  /// für die Hip Height im Studio-Skript.
  final double hipStuds;

  /// Um wie viel das ganze Modell verschoben wurde, damit der
  /// Wurzelknochen im Ursprung sitzt.
  final List<double> shift;

  /// Drehung um die Hochachse, in Grad, damit die Figur nach vorn
  /// blickt.
  final int turnedDegrees;

  final List<String> notes;

  bool get moved => shift.any((v) => v.abs() > 1e-6);
  bool get changed =>
      flattenedRotations > 0 ||
      flattenedScales > 0 ||
      unweightedVertices > 0 ||
      (scale - 1).abs() > 1e-6 ||
      moved ||
      turnedDegrees != 0 ||
      rig.renamed.isNotEmpty ||
      rig.rootAdded;
}

class RobloxPrepareResult {
  const RobloxPrepareResult(this.glb, this.report);
  final Uint8List glb;
  final RobloxPrepareReport report;
}

/// Macht eine geriggte GLB importfertig: R15-Namen, Knochen ohne
/// Drehung und Skalierung, Wurzel im Ursprung, Blick nach vorn.
///
/// Jeder Schritt lässt sich einzeln abschalten – wer nur die Namen
/// braucht, nimmt [renameBonesToR15].
RobloxPrepareResult prepareRigForRoblox(
  Uint8List glb, {
  bool flattenBones = true,
  bool rootToOrigin = true,
  bool faceFront = true,
  bool unweightRoot = true,
  double targetStuds = 0,
}) {
  final named = renameBonesToR15(glb);
  final parts = splitGlb(named.glb);
  final json = parts.json;
  var bin = parts.bin;
  final notes = <String>[];
  final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
  final skin = (json['skins'] as List).cast<Map<String, dynamic>>().first;
  final joints = (skin['joints'] as List).cast<int>();
  final parentOf = _parentMap(nodes);
  final world = _worldMatrices(nodes, parentOf);
  final structure = named.report.structure;

  // Die Gelenkwurzel: das Gelenk, über dem kein weiteres steht.
  final jointSet = joints.toSet();
  var rootJoint = joints.firstWhere(
      (j) => !jointSet.contains(parentOf[j]),
      orElse: () => joints.first);
  // Hat die Umbenennung einen HumanoidRootPart darüber gesetzt, gehört
  // er in die Gelenkliste – sonst prüft Roblox weiter den alten
  // Knochen darunter. Gewichte bekommt er dadurch keine: kein Vertex
  // zeigt auf diesen Index.
  final aboveRoot = parentOf[rootJoint];
  if (aboveRoot != null &&
      !jointSet.contains(aboveRoot) &&
      (nodes[aboveRoot]['name'] as String? ?? '') == robloxRootBone) {
    joints.add(aboveRoot);
    jointSet.add(aboveRoot);
    rootJoint = aboveRoot;
  }

  List<double> worldPos(int node) {
    final m = world[node]!;
    return [m[12], m[13], m[14]];
  }

  // Gewichte an der Wurzel abnehmen, solange Netz und Skelett noch in
  // ihrer ursprünglichen Lage stehen – der Notfallweg über den
  // nächstgelegenen Knochen vergleicht beides miteinander.
  final replace = <int, Uint8List>{};
  var unweighted = 0;
  if (unweightRoot) {
    unweighted = _unweightRoot(
      json,
      bin,
      replace,
      joints.indexOf(rootJoint),
      {for (final j in joints) j: worldPos(j)},
      joints,
    );
  }

  // Drehung um die Hochachse, damit die Vorderseite nach +z zeigt.
  var turned = 0;
  if (faceFront && structure != null) {
    turned = switch ((structure.forwardAxis, structure.forwardSign < 0)) {
      (2, false) => 0,
      (0, false) => 90,
      (0, true) => 270,
      _ => 180,
    };
  }
  List<double> turn(List<double> v) => switch (turned) {
        90 => [-v[2], v[1], v[0]],
        270 => [v[2], v[1], -v[0]],
        180 => [-v[0], v[1], -v[2]],
        _ => v,
      };

  // Maßstab. Der Roblox-Importer rechnet die Datei zunächst in Meter
  // um (das erledigt die Scale-Unit-Einstellung) und setzt dann einen
  // Meter gleich einem Stud. Eine Figur von 1,20 glTF-Einheiten kommt
  // also 1,2 Studs hoch an – kniehoch neben einem Standard-Charakter
  // von 5 Studs. Statt das im Importer zu verstellen, bekommt die
  // Datei gleich die richtige Zahl: Höhe in Einheiten = Höhe in Studs.
  var scale = 1.0;
  final heightBefore = _modelHeight(json, bin);
  // Vor dem Umschreiben ablesen: Danach stehen in den Accessoren die
  // schon gedrehten und verschobenen Grenzen.
  final lowestBefore = _modelLowest(json, bin);
  if (targetStuds > 0 && heightBefore > 1e-6) {
    scale = targetStuds / heightBefore;
  }

  // Die Gelenke in ihrer neuen Weltlage.
  final placed = <int, List<double>>{
    for (final j in joints)
      j: [for (final v in turn(worldPos(j))) v * scale],
  };

  // Der Nullpunkt einer R15-Figur.
  //
  // Roblox' Spezifikation für Charakterkörper ist hier wörtlich:
  // „The LowerTorso and Root bone or joint position must be set to
  // 0, 0, 0." Der Ursprung liegt also **an der Hüfte**, nicht am
  // Boden – die Füße stehen im Minus. Legt man ihn stattdessen auf
  // Fußhöhe, landet der HumanoidRootPart zwischen den Füßen, und die
  // Figur schwebt im Spiel um die eingetragene Hip Height nach oben.
  //
  // Verschoben wird deshalb auf den LowerTorso; der Wurzelknochen
  // rückt danach auf denselben Punkt. Er trägt keine Gewichte mehr
  // (siehe [_unweightRoot]), also verformt ihn das nicht.
  var shift = [0.0, 0.0, 0.0];
  if (rootToOrigin) {
    int? anchor;
    for (final j in joints) {
      if ((nodes[j]['name'] as String? ?? '') == 'LowerTorso') anchor = j;
    }
    // Ohne LowerTorso (Prop, Accessoire, unvollständiges Rig) bleibt
    // es beim alten Bezugspunkt: der Wurzelknochen selbst.
    final at = placed[anchor ?? rootJoint]!;
    if (at.any((v) => v.abs() > 1e-6)) {
      shift = [-at[0], -at[1], -at[2]];
    }
    if (anchor == null) {
      notes.add('Kein LowerTorso gefunden – der Ursprung liegt auf dem '
          'Wurzelknochen. Für eine R15-Figur gehört er an die Hüfte.');
    }
  }
  for (final entry in placed.entries) {
    entry.value[0] += shift[0];
    entry.value[1] += shift[1];
    entry.value[2] += shift[2];
  }
  // Wurzelknochen auf denselben Punkt wie der LowerTorso.
  if (rootToOrigin) placed[rootJoint] = [0.0, 0.0, 0.0];

  // Netzdaten mitdrehen, mitskalieren und mitverschieben.
  if (turned != 0 || scale != 1 || shift.any((v) => v != 0)) {
    final done = <int>{};
    for (final meshRaw in (json['meshes'] as List? ?? const [])) {
      final mesh = meshRaw as Map<String, dynamic>;
      for (final primRaw in (mesh['primitives'] as List? ?? const [])) {
        final prim = primRaw as Map<String, dynamic>;
        final targets = <Map<String, dynamic>>[
          (prim['attributes'] as Map<String, dynamic>),
          for (final t in (prim['targets'] as List? ?? const []))
            t as Map<String, dynamic>,
        ];
        for (final attributes in targets) {
          for (final key in const ['POSITION', 'NORMAL', 'TANGENT']) {
            final index = (attributes[key] as num?)?.toInt();
            if (index == null || !done.add(index)) continue;
            // Verschoben wird nur die Lage, nicht die Richtung – und
            // Morph-Ziele sind ohnehin Differenzen.
            final move = key == 'POSITION' && attributes == targets.first;
            // Normalen und Tangenten bleiben Einheitsvektoren: Eine
            // gleichmäßige Skalierung ändert ihre Richtung nicht.
            if (!_turnAccessor(
                json,
                bin,
                replace,
                index,
                turn,
                key == 'POSITION' ? scale : 1.0,
                move ? shift : const [0.0, 0.0, 0.0])) {
              notes.add('$key liegt in einem Format, das die App nicht '
                  'umschreibt – Drehung und Verschiebung bleiben aus.');
            }
          }
        }
      }
    }
  }

  // Knochen glattziehen: keine Drehung, keine Skalierung.
  var rotations = 0, scales = 0;
  if (flattenBones) {
    for (final j in joints) {
      final node = nodes[j];
      final r = _vec(node['rotation'], const [0.0, 0.0, 0.0, 1.0]);
      final s = _vec(node['scale'], const [1.0, 1.0, 1.0]);
      if (node['matrix'] != null ||
          r[0].abs() > 1e-4 ||
          r[1].abs() > 1e-4 ||
          r[2].abs() > 1e-4 ||
          (r[3].abs() - 1).abs() > 1e-4) {
        rotations++;
      }
      if ((s[0] - 1).abs() > 1e-4 ||
          (s[1] - 1).abs() > 1e-4 ||
          (s[2] - 1).abs() > 1e-4) {
        scales++;
      }
    }
    // Die Gelenkwurzel hängt danach direkt in der Szene: so kann kein
    // Knoten darüber noch eine Drehung beisteuern.
    _detachToScene(json, nodes, parentOf, rootJoint);
    for (final j in joints) {
      final node = nodes[j];
      node.remove('matrix');
      node.remove('rotation');
      node.remove('scale');
      final parent = parentOf[j];
      final base = (parent != null && jointSet.contains(parent))
          ? placed[parent]!
          : const [0.0, 0.0, 0.0];
      final local = [
        placed[j]![0] - base[0],
        placed[j]![1] - base[1],
        placed[j]![2] - base[2],
      ];
      if (local.every((v) => v.abs() < 1e-9)) {
        node.remove('translation');
      } else {
        node['translation'] = local;
      }
    }
  }

  // Bind-Matrizen: die Umkehrung der neuen Weltlage. Damit steht die
  // Ruhepose wieder genau dort, wo sie vorher stand.
  if (flattenBones || turned != 0 || shift.any((v) => v != 0)) {
    final matrices = Float32List(joints.length * 16);
    for (var i = 0; i < joints.length; i++) {
      final p = placed[joints[i]]!;
      final at = i * 16;
      matrices[at] = 1;
      matrices[at + 5] = 1;
      matrices[at + 10] = 1;
      matrices[at + 15] = 1;
      matrices[at + 12] = -p[0];
      matrices[at + 13] = -p[1];
      matrices[at + 14] = -p[2];
    }
    _writeMatrices(json, replace, skin, matrices, joints.length);
  }

  if (replace.isNotEmpty) bin = _repackViews(json, bin, replace);

  return RobloxPrepareResult(
    joinGlb(json, bin),
    RobloxPrepareReport(
      rig: named.report,
      structure: structure,
      flattenedRotations: flattenBones ? rotations : 0,
      flattenedScales: flattenBones ? scales : 0,
      unweightedVertices: unweighted,
      scale: scale,
      heightStuds: heightBefore * scale,
      hipStuds: -(lowestBefore * scale + shift[1]),
      shift: shift,
      turnedDegrees: turned,
      notes: [...notes, ...(structure?.notes ?? const [])],
    ),
  );
}

/// Hängt einen Knoten direkt in die Szene, damit über ihm keine
/// fremde Transformation mehr steht.
void _detachToScene(Map<String, dynamic> json,
    List<Map<String, dynamic>> nodes, Map<int, int> parentOf, int node) {
  final parent = parentOf[node];
  if (parent == null) return;
  final siblings = nodes[parent]['children'] as List?;
  siblings?.removeWhere((c) => (c as num).toInt() == node);
  if (siblings != null && siblings.isEmpty) nodes[parent].remove('children');
  parentOf.remove(node);
  final scenes = (json['scenes'] as List?) ?? const [];
  if (scenes.isEmpty) return;
  final index = (json['scene'] as num?)?.toInt() ?? 0;
  final scene =
      scenes[index < scenes.length ? index : 0] as Map<String, dynamic>;
  final list = (scene['nodes'] as List?) ?? [];
  if (!list.any((c) => (c as num).toInt() == node)) list.add(node);
  scene['nodes'] = list;
}

int _componentsOf(String type) => switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      'MAT4' => 16,
      _ => 3,
    };

/// Dreht und verschiebt einen VEC3/VEC4-Accessor. Gibt false zurück,
/// wenn er nicht aus Fließkommazahlen besteht – dann bleibt er, wie er
/// ist, statt beschädigt zu werden.
bool _turnAccessor(
  Map<String, dynamic> json,
  Uint8List bin,
  Map<int, Uint8List> replace,
  int index,
  List<double> Function(List<double>) turn,
  double scale,
  List<double> shift,
) {
  final acc = (json['accessors'] as List)[index] as Map<String, dynamic>;
  if ((acc['componentType'] as num).toInt() != 5126) return false;
  final components = _componentsOf(acc['type'] as String);
  if (components != 3 && components != 4) return false;
  final values = readGltfFloats(json, bin, index);
  final count = (acc['count'] as num).toInt();
  final out = Float32List(count * components);
  final min = List<double>.filled(components, double.infinity);
  final max = List<double>.filled(components, -double.infinity);
  for (var i = 0; i < count; i++) {
    final at = i * components;
    final v = turn([values[at], values[at + 1], values[at + 2]]);
    out[at] = v[0] * scale + shift[0];
    out[at + 1] = v[1] * scale + shift[1];
    out[at + 2] = v[2] * scale + shift[2];
    // Das w einer Tangente ist ein Vorzeichen, keine Koordinate.
    if (components == 4) out[at + 3] = values[at + 3];
    for (var c = 0; c < components; c++) {
      min[c] = math.min(min[c], out[at + c]);
      max[c] = math.max(max[c], out[at + c]);
    }
  }
  if (acc['min'] != null) acc['min'] = min;
  if (acc['max'] != null) acc['max'] = max;
  _putFloats(json, replace, index, out);
  return true;
}

/// Legt die Bind-Matrizen neu ab – notfalls in einem neuen Accessor,
/// falls die Datei bisher ohne auskam.
void _writeMatrices(Map<String, dynamic> json, Map<int, Uint8List> replace,
    Map<String, dynamic> skin, Float32List matrices, int count) {
  var index = (skin['inverseBindMatrices'] as num?)?.toInt();
  final accessors = (json['accessors'] as List);
  if (index == null ||
      (accessors[index] as Map<String, dynamic>)['count'] != count) {
    final views = (json['bufferViews'] as List);
    final viewIndex = views.length;
    views.add(<String, dynamic>{
      'buffer': 0,
      'byteOffset': 0,
      'byteLength': matrices.lengthInBytes,
    });
    replace[viewIndex] = _floatBytes(matrices);
    index = accessors.length;
    accessors.add(<String, dynamic>{
      'bufferView': viewIndex,
      'componentType': 5126,
      'count': count,
      'type': 'MAT4',
    });
    skin['inverseBindMatrices'] = index;
    return;
  }
  _putFloats(json, replace, index, matrices);
}

/// Schreibt Fließkommawerte in einen Accessor zurück.
///
/// Liegt er allein und dicht gepackt in seinem bufferView, werden
/// dessen Bytes ersetzt. Teilt er ihn mit anderen (verschachtelte
/// Attribute), bekommt er einen eigenen – die alten Bytes bleiben
/// liegen, das ist der Preis dafür, die anderen nicht anzufassen.
void _putFloats(Map<String, dynamic> json, Map<int, Uint8List> replace,
    int index, Float32List values) {
  final acc = (json['accessors'] as List)[index] as Map<String, dynamic>;
  final bytes = _floatBytes(values);
  if (_accessorOwnsView(json, index)) {
    replace[(acc['bufferView'] as num).toInt()] = bytes;
    return;
  }
  final views = (json['bufferViews'] as List);
  final viewIndex = views.length;
  views.add(<String, dynamic>{
    'buffer': 0,
    'byteOffset': 0,
    'byteLength': bytes.length,
  });
  replace[viewIndex] = bytes;
  acc['bufferView'] = viewIndex;
  acc['byteOffset'] = 0;
}

bool _accessorOwnsView(Map<String, dynamic> json, int index) {
  final accessors = (json['accessors'] as List);
  final acc = accessors[index] as Map<String, dynamic>;
  if (((acc['byteOffset'] as num?)?.toInt() ?? 0) != 0) return false;
  final viewIndex = (acc['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return false;
  final view = (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  if (view['byteStride'] != null) return false;
  final size = 4 *
      _componentsOf(acc['type'] as String) *
      (acc['count'] as num).toInt();
  if ((view['byteLength'] as num).toInt() != size) return false;
  for (var i = 0; i < accessors.length; i++) {
    if (i == index) continue;
    if (((accessors[i] as Map<String, dynamic>)['bufferView'] as num?)
            ?.toInt() ==
        viewIndex) {
      return false;
    }
  }
  return true;
}

Uint8List _floatBytes(Float32List values) {
  final out = Uint8List(values.length * 4);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return out;
}

/// Baut den Binärteil neu auf. Die Reihenfolge der bufferViews bleibt,
/// nur Länge und Versatz werden nachgezogen.
Uint8List _repackViews(
    Map<String, dynamic> json, Uint8List bin, Map<int, Uint8List> replace) {
  final views = json['bufferViews'] as List;
  int pad4(int n) => (n + 3) & ~3;
  final chunks = <Uint8List>[];
  var total = 0;
  for (var i = 0; i < views.length; i++) {
    final view = views[i] as Map<String, dynamic>;
    final data = replace[i] ?? gltfBufferViewBytes(json, bin, i);
    view['byteOffset'] = total;
    view['byteLength'] = data.length;
    chunks.add(data);
    total += pad4(data.length);
  }
  final out = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += pad4(chunk.length);
  }
  final buffers = json['buffers'] as List?;
  if (buffers != null && buffers.isNotEmpty) {
    (buffers.first as Map<String, dynamic>)['byteLength'] = total;
  }
  return out;
}

/// Nimmt dem Wurzelknochen seine Gewichte ab.
///
/// Roblox will den Wurzelknochen als reinen Aufhängepunkt: Er darf
/// keinen Vertex bewegen. Tripo gewichtet ihn trotzdem – bei der
/// Testfigur 1.667 von 10.572 Vertices, bis zu 0,99 Anteil, vom Fuß
/// bis zur Brust.
///
/// Weggerechnet wird das nicht durch Umhängen auf einen anderen
/// Knochen – das würde Füße am Rumpf festmachen –, sondern indem der
/// Anteil auf die **übrigen Knochen desselben Vertex** verteilt wird.
/// Die Ruhepose ändert sich dadurch nicht (in der Bindepose heben sich
/// Gelenk- und Bindematrix ohnehin auf); es ändert sich nur, wem der
/// Vertex bei einer Bewegung folgt – und das sind dann genau die
/// Knochen daneben. Nur wenn ein Vertex ausschließlich an der Wurzel
/// hängt, bekommt er den nächstgelegenen Knochen.
int _unweightRoot(
  Map<String, dynamic> json,
  Uint8List bin,
  Map<int, Uint8List> replace,
  int rootSlot,
  Map<int, List<double>> jointPositions,
  List<int> joints,
) {
  var moved = 0;
  for (final meshRaw in (json['meshes'] as List? ?? const [])) {
    for (final primRaw in
        ((meshRaw as Map<String, dynamic>)['primitives'] as List? ??
            const [])) {
      final attributes =
          (primRaw as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>;
      final jointAcc = <int>[];
      final weightAcc = <int>[];
      for (var n = 0; attributes['JOINTS_$n'] != null; n++) {
        final ji = (attributes['JOINTS_$n'] as num).toInt();
        final wi = (attributes['WEIGHTS_$n'] as num?)?.toInt();
        if (wi == null) break;
        jointAcc.add(ji);
        weightAcc.add(wi);
      }
      if (jointAcc.isEmpty) continue;
      final jointData = [for (final a in jointAcc) _readInts(json, bin, a)];
      final weightData = [
        for (final a in weightAcc) Float32List.fromList(readGltfFloats(json, bin, a))
      ];
      final count =
          ((json['accessors'] as List)[jointAcc.first] as Map<String, dynamic>)
              ['count'] as int;
      final positionIndex = (attributes['POSITION'] as num?)?.toInt();
      final positions =
          positionIndex == null ? null : readGltfFloats(json, bin, positionIndex);
      var touched = false;
      for (var v = 0; v < count; v++) {
        var rootWeight = 0.0, rest = 0.0;
        for (var s = 0; s < jointAcc.length; s++) {
          for (var k = 0; k < 4; k++) {
            final w = weightData[s][v * 4 + k];
            if (jointData[s][v * 4 + k] == rootSlot) {
              rootWeight += w;
            } else {
              rest += w;
            }
          }
        }
        if (rootWeight <= 1e-4) continue;
        touched = true;
        moved++;
        if (rest > 1e-4) {
          final factor = (rootWeight + rest) / rest;
          for (var s = 0; s < jointAcc.length; s++) {
            for (var k = 0; k < 4; k++) {
              final at = v * 4 + k;
              if (jointData[s][at] == rootSlot) {
                weightData[s][at] = 0;
              } else {
                weightData[s][at] *= factor;
              }
            }
          }
          continue;
        }
        // Hängt nur an der Wurzel: dem nächsten echten Knochen geben.
        var best = -1;
        var bestDistance = double.infinity;
        if (positions != null) {
          final px = positions[v * 3],
              py = positions[v * 3 + 1],
              pz = positions[v * 3 + 2];
          for (var i = 0; i < joints.length; i++) {
            if (i == rootSlot) continue;
            final p = jointPositions[joints[i]];
            if (p == null) continue;
            final dx = p[0] - px, dy = p[1] - py, dz = p[2] - pz;
            final d = dx * dx + dy * dy + dz * dz;
            if (d < bestDistance) {
              bestDistance = d;
              best = i;
            }
          }
        }
        if (best < 0) continue;
        for (var s = 0; s < jointAcc.length; s++) {
          for (var k = 0; k < 4; k++) {
            final at = v * 4 + k;
            weightData[s][at] = 0;
            if (jointData[s][at] == rootSlot) jointData[s][at] = 0;
          }
        }
        jointData[0][v * 4] = best;
        weightData[0][v * 4] = 1;
      }
      if (!touched) continue;
      for (var s = 0; s < jointAcc.length; s++) {
        _putWeights(json, replace, weightAcc[s], weightData[s]);
        _putInts(json, replace, jointAcc[s], jointData[s]);
      }
    }
  }
  return moved;
}

/// Liest einen Ganzzahl-Accessor (JOINTS_n) unverändert aus.
Int32List _readInts(Map<String, dynamic> json, Uint8List bin, int index) {
  final acc = (json['accessors'] as List)[index] as Map<String, dynamic>;
  final count = (acc['count'] as num).toInt();
  final components = _componentsOf(acc['type'] as String);
  final type = (acc['componentType'] as num).toInt();
  final size = switch (type) { 5121 || 5120 => 1, 5123 || 5122 => 2, _ => 4 };
  final viewIndex = (acc['bufferView'] as num).toInt();
  final view = (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  final stride =
      (view['byteStride'] as num?)?.toInt() ?? components * size;
  final bytes = gltfBufferViewBytes(json, bin, viewIndex);
  final data = ByteData.sublistView(bytes);
  final offset = (acc['byteOffset'] as num?)?.toInt() ?? 0;
  final out = Int32List(count * components);
  for (var i = 0; i < count; i++) {
    for (var c = 0; c < components; c++) {
      final at = offset + i * stride + c * size;
      out[i * components + c] = switch (size) {
        1 => data.getUint8(at),
        2 => data.getUint16(at, Endian.little),
        _ => data.getUint32(at, Endian.little),
      };
    }
  }
  return out;
}

/// Schreibt Gewichte zurück. Lagen sie als normalisierte Bytes vor,
/// wird der Accessor auf Fließkomma umgestellt – sonst ginge die
/// Feinheit der neu verteilten Anteile verloren.
void _putWeights(Map<String, dynamic> json, Map<int, Uint8List> replace,
    int index, Float32List values) {
  final acc = (json['accessors'] as List)[index] as Map<String, dynamic>;
  acc['componentType'] = 5126;
  acc.remove('normalized');
  _putFloats(json, replace, index, values);
}

void _putInts(Map<String, dynamic> json, Map<int, Uint8List> replace,
    int index, Int32List values) {
  final acc = (json['accessors'] as List)[index] as Map<String, dynamic>;
  var max = 0;
  for (final v in values) {
    if (v > max) max = v;
  }
  final size = max > 65535 ? 4 : (max > 255 ? 2 : 1);
  acc['componentType'] = switch (size) { 1 => 5121, 2 => 5123, _ => 5125 };
  final bytes = Uint8List(values.length * size);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < values.length; i++) {
    switch (size) {
      case 1:
        data.setUint8(i, values[i]);
      case 2:
        data.setUint16(i * 2, values[i], Endian.little);
      default:
        data.setUint32(i * 4, values[i], Endian.little);
    }
  }
  if (_accessorOwnsRawView(json, index, bytes.length)) {
    replace[(acc['bufferView'] as num).toInt()] = bytes;
    return;
  }
  final views = (json['bufferViews'] as List);
  final viewIndex = views.length;
  views.add(<String, dynamic>{
    'buffer': 0,
    'byteOffset': 0,
    'byteLength': bytes.length,
  });
  replace[viewIndex] = bytes;
  acc['bufferView'] = viewIndex;
  acc['byteOffset'] = 0;
}

bool _accessorOwnsRawView(
    Map<String, dynamic> json, int index, int byteLength) {
  final accessors = (json['accessors'] as List);
  final acc = accessors[index] as Map<String, dynamic>;
  if (((acc['byteOffset'] as num?)?.toInt() ?? 0) != 0) return false;
  final viewIndex = (acc['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return false;
  final view = (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  if (view['byteStride'] != null) return false;
  if ((view['byteLength'] as num).toInt() != byteLength) return false;
  for (var i = 0; i < accessors.length; i++) {
    if (i == index) continue;
    if (((accessors[i] as Map<String, dynamic>)['bufferView'] as num?)
            ?.toInt() ==
        viewIndex) {
      return false;
    }
  }
  return true;
}

/// Der Bericht in Sätzen – für den Dialog und die Kurzanleitung im
/// Paket.
List<String> robloxPrepareSummary(RobloxPrepareReport report) {
  final out = <String>[];
  final rig = report.rig;
  if (rig.renamed.isNotEmpty) {
    out.add('${rig.renamed.length} Knochen auf R15-Namen gesetzt'
        '${report.structure == null ? '' : ' (aus der Form des '
            'Skeletts, nicht aus den Namen des Anbieters)'}.');
  }
  if (rig.rootAdded) {
    out.add('Ein HumanoidRootPart im Ursprung eingezogen, ohne '
        'Gewichtung.');
  }
  if (report.flattenedRotations > 0 || report.flattenedScales > 0) {
    out.add('${report.flattenedRotations} Knochen ohne Drehung und '
        '${report.flattenedScales} ohne Skalierung neu abgelegt; die '
        'Bind-Matrizen sind dazu passend gerechnet, die Ruhepose steht '
        'unverändert.');
  }
  if (report.unweightedVertices > 0) {
    out.add('${report.unweightedVertices} Vertices vom Wurzelknochen '
        'genommen – ihr Anteil ging an die übrigen Knochen desselben '
        'Vertex.');
  }
  if ((report.scale - 1).abs() > 1e-6) {
    out.add('Auf ${report.heightStuds.toStringAsFixed(1)} Studs '
        'gebracht (Faktor ${report.scale.toStringAsFixed(2)}). Der '
        'Importer liest eine Datei-Einheit als einen Stud – ohne das '
        'stünde die Figur kniehoch neben einem Standard-Charakter.');
  }
  if (report.moved) {
    out.add('Nullpunkt auf die Hüfte gelegt: LowerTorso und '
        'Wurzelknochen sitzen bei 0/0/0, die Füße stehen '
        '${report.hipStuds.toStringAsFixed(1)} Studs darunter. So '
        'verlangt es Roblox für R15 – auf Fußhöhe schwebt die Figur '
        'im Spiel um die Hip Height nach oben.');
  }
  if (report.turnedDegrees != 0) {
    out.add('Figur um ${report.turnedDegrees}° um die Hochachse '
        'gedreht: Die Vorderseite zeigt jetzt nach +z, wie glTF und '
        'der Roblox-Importer es erwarten. Vorher lag die Armspanne auf '
        'der Tiefenachse – die Figur wäre seitwärts gelaufen.');
  }
  if (report.structure?.mirroredNames ?? false) {
    out.add('Links und rechts waren beim Anbieter vertauscht; die '
        'Seiten kommen aus der Geometrie (Blickrichtung aus den '
        'Zehenknochen).');
  }
  out.addAll(report.notes);
  return out;
}

/// Höhe des Modells in glTF-Einheiten, aus den POSITION-Grenzen.
double _modelHeight(Map<String, dynamic> json, Uint8List bin) {
  var min = double.infinity;
  var max = -double.infinity;
  for (final meshRaw in (json['meshes'] as List? ?? const [])) {
    for (final primRaw in
        ((meshRaw as Map<String, dynamic>)['primitives'] as List? ??
            const [])) {
      final index = (((primRaw as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>?)?['POSITION'] as num?)
          ?.toInt();
      if (index == null) continue;
      final acc = (json['accessors'] as List)[index] as Map<String, dynamic>;
      final low = acc['min'] as List?;
      final high = acc['max'] as List?;
      if (low != null && high != null && low.length > 1) {
        min = math.min(min, (low[1] as num).toDouble());
        max = math.max(max, (high[1] as num).toDouble());
        continue;
      }
      final values = readGltfFloats(json, bin, index);
      for (var i = 1; i < values.length; i += 3) {
        min = math.min(min, values[i]);
        max = math.max(max, values[i]);
      }
    }
  }
  return min > max ? 0 : max - min;
}

/// Tiefster Punkt des Netzes in glTF-Einheiten, vor Maßstab und
/// Verschiebung.
double _modelLowest(Map<String, dynamic> json, Uint8List bin) {
  var min = double.infinity;
  for (final meshRaw in (json['meshes'] as List? ?? const [])) {
    for (final primRaw in
        ((meshRaw as Map<String, dynamic>)['primitives'] as List? ??
            const [])) {
      final index = (((primRaw as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>?)?['POSITION'] as num?)
          ?.toInt();
      if (index == null) continue;
      final acc = (json['accessors'] as List)[index] as Map<String, dynamic>;
      final low = acc['min'] as List?;
      if (low != null && low.length > 1) {
        min = math.min(min, (low[1] as num).toDouble());
        continue;
      }
      final values = readGltfFloats(json, bin, index);
      for (var i = 1; i < values.length; i += 3) {
        min = math.min(min, values[i]);
      }
    }
  }
  return min == double.infinity ? 0 : min;
}
