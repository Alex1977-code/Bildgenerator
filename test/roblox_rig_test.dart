import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/roblox_rig.dart';

/// Baut eine GLB, die nur ein Skelett trägt – für die Namensarbeit
/// braucht es keine Geometrie.
Uint8List _riggedGlb(List<String> boneNames, {bool chainFromFirst = true}) {
  final nodes = <Map<String, dynamic>>[
    for (final name in boneNames) {'name': name},
  ];
  if (chainFromFirst) {
    // Eine einfache Kette: jeder Knochen ist Kind des vorigen.
    for (var i = 0; i < nodes.length - 1; i++) {
      nodes[i]['children'] = [i + 1];
    }
  }
  final json = <String, dynamic>{
    'asset': {'version': '2.0'},
    'scenes': [
      {
        'nodes': [0]
      }
    ],
    'scene': 0,
    'nodes': nodes,
    'skins': [
      {
        'joints': [for (var i = 0; i < boneNames.length; i++) i]
      }
    ],
  };
  return joinGlb(json, Uint8List(0));
}

Map<String, dynamic> _jsonOf(Uint8List glb) => splitGlb(glb).json;

void main() {
  group('Knochennamen auf R15 abbilden', () {
    test('Mixamo-Namen werden erkannt', () {
      expect(mapBoneToR15('mixamorig:Hips'), 'LowerTorso');
      expect(mapBoneToR15('mixamorig:Spine2'), 'UpperTorso');
      expect(mapBoneToR15('mixamorig:Head'), 'Head');
      expect(mapBoneToR15('mixamorig:LeftArm'), 'LeftUpperArm');
      expect(mapBoneToR15('mixamorig:LeftForeArm'), 'LeftLowerArm');
      expect(mapBoneToR15('mixamorig:RightHand'), 'RightHand');
      expect(mapBoneToR15('mixamorig:LeftUpLeg'), 'LeftUpperLeg');
      expect(mapBoneToR15('mixamorig:RightLeg'), 'RightLowerLeg');
      expect(mapBoneToR15('mixamorig:LeftFoot'), 'LeftFoot');
    });

    test('Die Namen des eigenen Auto-Riggers werden erkannt', () {
      expect(mapBoneToR15('Hips'), 'LowerTorso');
      expect(mapBoneToR15('Chest'), 'UpperTorso');
      expect(mapBoneToR15('Head'), 'Head');
      expect(mapBoneToR15('Shoulder_L'), 'LeftUpperArm');
      expect(mapBoneToR15('Elbow_R'), 'RightLowerArm');
      expect(mapBoneToR15('Hand_L'), 'LeftHand');
      expect(mapBoneToR15('UpperLeg_R'), 'RightUpperLeg');
      expect(mapBoneToR15('Knee_L'), 'LeftLowerLeg');
      expect(mapBoneToR15('Foot_R'), 'RightFoot');
    });

    test('Schreibweisen und Blender-Duplikate stören nicht', () {
      expect(mapBoneToR15('left upper arm'), 'LeftUpperArm');
      expect(mapBoneToR15('LeftUpperArm.001'), 'LeftUpperArm');
      expect(mapBoneToR15('  RIGHT_FOOT  '), 'RightFoot');
    });

    test('Der Wurzelknochen heißt HumanoidRootPart, nicht -Node', () {
      expect(mapBoneToR15('HumanoidRootNode'), 'HumanoidRootPart');
      expect(mapBoneToR15('root'), 'HumanoidRootPart');
      expect(robloxRootBone, 'HumanoidRootPart');
    });

    test('Was R15 nicht kennt, bleibt unangetastet', () {
      expect(mapBoneToR15('mixamorig:LeftHandIndex1'), isNull);
      expect(mapBoneToR15('Neck'), isNull);
      expect(mapBoneToR15('Spine'), isNull);
      expect(mapBoneToR15('Tail_03'), isNull);
    });
  });

  group('GLB umbenennen', () {
    // Der Zweibeiner des eigenen Auto-Riggers.
    const eigene = [
      'Hips', 'Spine', 'Chest', 'Neck', 'Head', //
      'Shoulder_L', 'Elbow_L', 'Hand_L',
      'Shoulder_R', 'Elbow_R', 'Hand_R',
      'UpperLeg_L', 'Knee_L', 'Foot_L',
      'UpperLeg_R', 'Knee_R', 'Foot_R',
    ];

    test('Alle 15 Gelenke entstehen aus dem eigenen Rig', () {
      final result = renameBonesToR15(_riggedGlb(eigene));
      expect(result.report.complete, isTrue,
          reason: 'fehlt: ${result.report.missing}');
      expect(result.report.found, robloxR15Bones.length);
      expect(result.report.renamed['Hips'], 'LowerTorso');
      expect(result.report.renamed['Chest'], 'UpperTorso');
      expect(result.report.renamed['Shoulder_L'], 'LeftUpperArm');
      // Spine und Neck haben in R15 kein Gegenstück und behalten ihren
      // Namen.
      expect(result.report.untouched, containsAll(['Spine', 'Neck']));

      final names = readBoneNames(result.glb);
      expect(names, containsAll(['LowerTorso', 'UpperTorso', 'Head']));
      expect(names, contains('Spine'));
    });

    test('Ein HumanoidRootPart wird über der Hüfte eingezogen', () {
      final result = renameBonesToR15(_riggedGlb(eigene));
      expect(result.report.rootAdded, isTrue);

      final json = _jsonOf(result.glb);
      final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
      final root = nodes.lastWhere((n) => n['name'] == robloxRootBone);
      // Im Ursprung, ohne Drehung, ohne Skalierung – so verlangt es
      // der Importer.
      expect(root['translation'], [0.0, 0.0, 0.0]);
      expect(root['rotation'], [0.0, 0.0, 0.0, 1.0]);
      expect(root['scale'], [1.0, 1.0, 1.0]);

      // Er ist NICHT in der Gelenkliste – dadurch ist er garantiert
      // ohne Gewichtung.
      final joints =
          ((json['skins'] as List).first as Map)['joints'] as List;
      expect(joints, isNot(contains(nodes.indexOf(root))));
      // Die Szene zeigt jetzt auf ihn, und die alte Wurzel hängt
      // darunter.
      expect(((json['scenes'] as List).first as Map)['nodes'],
          contains(nodes.indexOf(root)));
      expect(root['children'], contains(0));
      expect(nodes[0]['name'], 'LowerTorso');
    });

    test('Mixamo-Rig von Tripo wird vollständig übersetzt', () {
      const mixamo = [
        'mixamorig:Hips', 'mixamorig:Spine', 'mixamorig:Spine1',
        'mixamorig:Spine2', 'mixamorig:Neck', 'mixamorig:Head',
        'mixamorig:LeftArm', 'mixamorig:LeftForeArm', 'mixamorig:LeftHand',
        'mixamorig:RightArm', 'mixamorig:RightForeArm',
        'mixamorig:RightHand',
        'mixamorig:LeftUpLeg', 'mixamorig:LeftLeg', 'mixamorig:LeftFoot',
        'mixamorig:RightUpLeg', 'mixamorig:RightLeg',
        'mixamorig:RightFoot',
      ];
      final result = renameBonesToR15(_riggedGlb(mixamo));
      expect(result.report.complete, isTrue,
          reason: 'fehlt: ${result.report.missing}');
      expect(readBoneNames(result.glb), containsAll(robloxR15Bones
          .where((b) => b != robloxRootBone)));
    });

    test('Fehlende Gelenke werden benannt', () {
      // Ohne Beine bleibt nur der Import-Weg „Custom".
      final result = renameBonesToR15(
          _riggedGlb(['Hips', 'Chest', 'Head', 'Shoulder_L']));
      expect(result.report.complete, isFalse);
      expect(result.report.missing, contains('LeftFoot'));
      expect(result.report.missing, contains('RightUpperArm'));
      expect(result.report.missing, isNot(contains('HumanoidRootPart')));
    });

    test('Zwei Knochen auf denselben Namen: der zweite bleibt', () {
      final result =
          renameBonesToR15(_riggedGlb(['Hips', 'Pelvis', 'Head']));
      expect(result.report.renamed['Hips'], 'LowerTorso');
      expect(result.report.untouched, contains('Pelvis'));
      expect(readBoneNames(result.glb).where((n) => n == 'LowerTorso'),
          hasLength(1));
    });

    test('Eine schon benannte Datei bleibt, wie sie ist', () {
      final result = renameBonesToR15(_riggedGlb(
          robloxR15Bones.where((b) => b != robloxRootBone).toList()));
      expect(result.report.renamed, isEmpty);
      expect(result.report.complete, isTrue);
    });

    test('Ohne Skelett gibt es eine verständliche Meldung', () {
      final json = {
        'asset': {'version': '2.0'},
        'nodes': [
          {'name': 'Mesh'}
        ],
      };
      expect(
          () => renameBonesToR15(joinGlb(json, Uint8List(0))),
          throwsA(predicate(
              (e) => e.toString().contains('kein Skelett'))));
    });

    test('Die Datei bleibt eine gültige GLB', () {
      final result = renameBonesToR15(_riggedGlb(eigene));
      final parts = splitGlb(result.glb);
      expect(parts.json['asset'], isNotNull);
      // Und lässt sich erneut lesen, ohne dass etwas wächst.
      expect(jsonEncode(parts.json), isNotEmpty);
      expect(missingR15Bones(readBoneNames(result.glb)),
          ['HumanoidRootPart']);
    });
  });

  _rigStructureTests();
}

/// Ein zweibeiniges Skelett, gebaut wie Tripo es liefert: Namen ohne
/// verwertbare Rolle („bone_10"), Seitenangaben, die nicht zur
/// Geometrie passen, Armspanne auf der Tiefenachse und eine Wurzel
/// dicht neben dem Ursprung unter einem verschobenen Armature-Knoten.
///
/// Aufbau (Weltlage, Meter):
///   Wurzel 0/0,02/0 – Rumpf hoch – Arme zweigen bei 0,72 nach ±z ab,
///   Beine bei 0,35, Zehen zeigen nach +x. Damit blickt die Figur nach
///   +x, ihre linke Seite liegt auf −z – die mit „Left" benannten
///   Knochen liegen aber auf +z.
({Uint8List glb, Map<String, List<double>> world}) _tripoBiped({
  bool withBindMatrices = true,
}) {
  final world = <String, List<double>>{
    'tripo::Root': [0, 0.02, 0],
    'tripo::Spine_0': [0, 0.50, 0],
    'tripo::Spine_1': [0, 0.62, 0],
    'tripo::Head_0': [0, 0.72, 0],
    'tripo::Head_1': [0, 0.90, 0],
    'tripo::Head_2': [0, 1.00, 0],
    'tripo::0_Left_Limb_0': [0, 0.80, 0.10],
    'tripo::0_Left_Limb_1': [0, 0.80, 0.25],
    'tripo::0_Left_Limb_2': [0, 0.80, 0.45],
    'tripo::0_Left_Limb_3': [0, 0.80, 0.60],
    'bone_10': [0.02, 0.80, 0.66],
    'bone_11': [-0.02, 0.80, 0.66],
    'tripo::0_Right_Limb_0': [0, 0.80, -0.10],
    'tripo::0_Right_Limb_1': [0, 0.80, -0.25],
    'tripo::0_Right_Limb_2': [0, 0.80, -0.45],
    'tripo::0_Right_Limb_3': [0, 0.80, -0.60],
    'bone_20': [0.02, 0.80, -0.66],
    'bone_21': [-0.02, 0.80, -0.66],
    'tripo::1_Left_Limb_0': [0, 0.35, 0.09],
    'tripo::1_Left_Limb_1': [0, 0.20, 0.09],
    'tripo::1_Left_Limb_2': [0, 0.05, 0.09],
    'tripo::1_Left_Limb_3': [0.08, 0.02, 0.09],
    'tripo::1_Right_Limb_0': [0, 0.35, -0.09],
    'tripo::1_Right_Limb_1': [0, 0.20, -0.09],
    'tripo::1_Right_Limb_2': [0, 0.05, -0.09],
    'tripo::1_Right_Limb_3': [0.08, 0.02, -0.09],
  };
  const parents = <String, String>{
    'tripo::Spine_0': 'tripo::Root',
    'tripo::Spine_1': 'tripo::Spine_0',
    'tripo::Head_0': 'tripo::Spine_1',
    'tripo::Head_1': 'tripo::Head_0',
    'tripo::Head_2': 'tripo::Head_1',
    'tripo::0_Left_Limb_0': 'tripo::Head_0',
    'tripo::0_Left_Limb_1': 'tripo::0_Left_Limb_0',
    'tripo::0_Left_Limb_2': 'tripo::0_Left_Limb_1',
    'tripo::0_Left_Limb_3': 'tripo::0_Left_Limb_2',
    'bone_10': 'tripo::0_Left_Limb_3',
    'bone_11': 'tripo::0_Left_Limb_3',
    'tripo::0_Right_Limb_0': 'tripo::Head_0',
    'tripo::0_Right_Limb_1': 'tripo::0_Right_Limb_0',
    'tripo::0_Right_Limb_2': 'tripo::0_Right_Limb_1',
    'tripo::0_Right_Limb_3': 'tripo::0_Right_Limb_2',
    'bone_20': 'tripo::0_Right_Limb_3',
    'bone_21': 'tripo::0_Right_Limb_3',
    'tripo::1_Left_Limb_0': 'tripo::Root',
    'tripo::1_Left_Limb_1': 'tripo::1_Left_Limb_0',
    'tripo::1_Left_Limb_2': 'tripo::1_Left_Limb_1',
    'tripo::1_Left_Limb_3': 'tripo::1_Left_Limb_2',
    'tripo::1_Right_Limb_0': 'tripo::Root',
    'tripo::1_Right_Limb_1': 'tripo::1_Right_Limb_0',
    'tripo::1_Right_Limb_2': 'tripo::1_Right_Limb_1',
    'tripo::1_Right_Limb_3': 'tripo::1_Right_Limb_2',
  };

  final names = world.keys.toList();
  final index = {for (var i = 0; i < names.length; i++) names[i]: i};
  final nodes = <Map<String, dynamic>>[];
  for (final name in names) {
    final parent = parents[name];
    // Der Armature-Knoten steht 0,5 m hoch; die Wurzel gleicht das aus.
    final base = parent == null ? [0.0, 0.5, 0.0] : world[parent]!;
    nodes.add(<String, dynamic>{
      'name': name,
      'translation': [
        world[name]![0] - base[0],
        world[name]![1] - base[1],
        world[name]![2] - base[2],
      ],
    });
  }
  for (final entry in parents.entries) {
    final parent = nodes[index[entry.value]!];
    (parent['children'] ??= <int>[]) as List;
    (parent['children'] as List).add(index[entry.key]!);
  }
  // Drehung und Skalierung nur an Blättern: Sie ändern die Weltlage
  // der übrigen Knochen nicht, machen die Datei aber genauso
  // „unbrauchbar für Roblox" wie das echte Tripo-Ergebnis.
  nodes[index['bone_10']!]['rotation'] = [0.0, 0.0, 0.38268, 0.92388];
  nodes[index['bone_20']!]['rotation'] = [0.38268, 0.0, 0.0, 0.92388];
  nodes[index['tripo::Head_2']!]['scale'] = [1.2, 1.0, 1.0];

  // Ein winziges Netz: zwei Dreiecke, eines davon an der Wurzel
  // gewichtet.
  final positions = <double>[
    0, 0.02, 0, //
    0.05, 0.30, 0, //
    -0.05, 0.30, 0, //
    0, 0.80, 0.30, //
    0.05, 0.85, 0.30, //
    -0.05, 0.85, 0.30,
  ];
  final joints = <int>[
    index['tripo::Root']!, index['tripo::Spine_0']!, 0, 0, //
    index['tripo::Root']!, index['tripo::Spine_0']!, 0, 0, //
    index['tripo::Spine_0']!, 0, 0, 0, //
    index['tripo::0_Left_Limb_1']!, 0, 0, 0, //
    index['tripo::0_Left_Limb_1']!, 0, 0, 0, //
    index['tripo::0_Left_Limb_2']!, 0, 0, 0,
  ];
  final weights = <double>[
    0.5, 0.5, 0, 0, //
    0.8, 0.2, 0, 0, //
    1, 0, 0, 0, //
    1, 0, 0, 0, //
    1, 0, 0, 0, //
    1, 0, 0, 0,
  ];
  final indices = <int>[0, 1, 2, 3, 4, 5];

  final bytes = BytesBuilder();
  int add(List<int> data) {
    final at = bytes.length;
    bytes.add(data);
    return at;
  }

  final posBytes = Float32List.fromList(
      positions.map((e) => e.toDouble()).toList());
  final weightBytes = Float32List.fromList(weights);
  final posAt = add(posBytes.buffer.asUint8List());
  final jointAt = add(Uint8List.fromList(joints));
  final weightAt = add(weightBytes.buffer.asUint8List());
  final indexAt = add(Uint16List.fromList(indices).buffer.asUint8List());
  final bindAt = withBindMatrices
      ? add(Float32List(names.length * 16).buffer.asUint8List())
      : 0;

  final views = <Map<String, dynamic>>[
    {'buffer': 0, 'byteOffset': posAt, 'byteLength': posBytes.lengthInBytes},
    {'buffer': 0, 'byteOffset': jointAt, 'byteLength': joints.length},
    {
      'buffer': 0,
      'byteOffset': weightAt,
      'byteLength': weightBytes.lengthInBytes
    },
    {'buffer': 0, 'byteOffset': indexAt, 'byteLength': indices.length * 2},
    if (withBindMatrices)
      {'buffer': 0, 'byteOffset': bindAt, 'byteLength': names.length * 64},
  ];
  final accessors = <Map<String, dynamic>>[
    {
      'bufferView': 0,
      'componentType': 5126,
      'count': 6,
      'type': 'VEC3',
      'min': [-0.05, 0.02, 0.0],
      'max': [0.05, 0.85, 0.30],
    },
    {'bufferView': 1, 'componentType': 5121, 'count': 6, 'type': 'VEC4'},
    {'bufferView': 2, 'componentType': 5126, 'count': 6, 'type': 'VEC4'},
    {'bufferView': 3, 'componentType': 5123, 'count': 6, 'type': 'SCALAR'},
    if (withBindMatrices)
      {
        'bufferView': 4,
        'componentType': 5126,
        'count': names.length,
        'type': 'MAT4'
      },
  ];

  final meshNode = nodes.length;
  nodes.add(<String, dynamic>{'name': 'figur', 'mesh': 0, 'skin': 0});
  final armature = nodes.length;
  nodes.add(<String, dynamic>{
    'name': 'Armature',
    'translation': [0.0, 0.5, 0.0],
    'children': [index['tripo::Root']!, meshNode],
  });

  final json = <String, dynamic>{
    'asset': {'version': '2.0', 'generator': 'Tripo'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [armature]
      }
    ],
    'nodes': nodes,
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'JOINTS_0': 1, 'WEIGHTS_0': 2},
            'indices': 3,
          }
        ]
      }
    ],
    'skins': [
      {
        'joints': [for (var i = 0; i < names.length; i++) i],
        if (withBindMatrices) 'inverseBindMatrices': 4,
      }
    ],
    'buffers': [
      {'byteLength': bytes.length}
    ],
    'bufferViews': views,
    'accessors': accessors,
  };
  return (glb: joinGlb(json, bytes.toBytes()), world: world);
}

/// Weltpositionen der Gelenke aus einer fertigen Datei – gültig, weil
/// nach [prepareRigForRoblox] keine Drehung und keine Skalierung mehr
/// im Baum steht.
Map<String, List<double>> _jointWorld(Map<String, dynamic> json) {
  final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
  final parentOf = <int, int>{};
  for (var i = 0; i < nodes.length; i++) {
    for (final child in (nodes[i]['children'] as List? ?? const [])) {
      parentOf[child as int] = i;
    }
  }
  List<double> at(int node) {
    var x = 0.0, y = 0.0, z = 0.0;
    int? cur = node;
    while (cur != null) {
      final t = nodes[cur]['translation'] as List?;
      if (t != null) {
        x += (t[0] as num).toDouble();
        y += (t[1] as num).toDouble();
        z += (t[2] as num).toDouble();
      }
      cur = parentOf[cur];
    }
    return [x, y, z];
  }

  final joints = ((json['skins'] as List).first
      as Map<String, dynamic>)['joints'] as List;
  return {
    for (final j in joints.cast<int>())
      (nodes[j]['name'] as String? ?? '$j'): at(j),
  };
}

void _rigStructureTests() {
  group('Tripo-Skelett ohne verwertbare Namen', () {
    test('Die Rollen kommen aus der Form, die Seiten aus der Geometrie',
        () {
      final built = _tripoBiped();
      final result = prepareRigForRoblox(built.glb);
      final report = result.report;

      expect(report.rig.missing, isEmpty,
          reason: 'alle 16 R15-Gelenke müssen stehen');
      // Tripo nennt die +z-Seite „Left"; die Figur blickt aber nach
      // +x, damit liegt ihre linke Seite auf −z.
      expect(report.rig.renamed['tripo::0_Left_Limb_1'], 'RightUpperArm');
      expect(report.rig.renamed['tripo::0_Right_Limb_1'], 'LeftUpperArm');
      expect(report.rig.renamed['tripo::1_Left_Limb_0'], 'RightUpperLeg');
      expect(report.rig.renamed['tripo::1_Right_Limb_2'], 'LeftFoot');
      expect(report.rig.renamed['tripo::Spine_0'], 'LowerTorso');
      expect(report.rig.renamed['tripo::Head_0'], 'UpperTorso');
      expect(report.rig.renamed['tripo::Head_1'], 'Head');
      expect(report.structure?.mirroredNames, isTrue);
      expect(report.structure?.facingFromToes, isTrue);
      expect(report.structure?.facing, '+x');
    });

    test('Knochen ohne Drehung und Skalierung, Wurzel im Ursprung', () {
      final result = prepareRigForRoblox(_tripoBiped().glb);
      final json = splitGlb(result.glb).json;
      final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
      final joints = ((json['skins'] as List).first
          as Map<String, dynamic>)['joints'] as List;
      for (final j in joints.cast<int>()) {
        expect(nodes[j]['rotation'], isNull);
        expect(nodes[j]['scale'], isNull);
        expect(nodes[j]['matrix'], isNull);
      }
      expect(result.report.flattenedRotations, 2);
      expect(result.report.flattenedScales, 1);

      final world = _jointWorld(json);
      for (final value in world['HumanoidRootPart']!) {
        expect(value.abs(), lessThan(1e-6));
      }
    });

    test('Die Figur wird nach vorn gedreht, das Netz dreht mit', () {
      final built = _tripoBiped();
      final result = prepareRigForRoblox(built.glb);
      expect(result.report.turnedDegrees, 90);

      // 90°: (x,y,z) → (−z,y,x); danach um die Wurzel nach unten.
      final world = _jointWorld(splitGlb(result.glb).json);
      final head = built.world['tripo::Head_1']!;
      expect(world['Head']![0], closeTo(-head[2], 1e-5));
      expect(world['Head']![1], closeTo(head[1] - 0.02, 1e-5));
      expect(world['Head']![2], closeTo(head[0], 1e-5));

      // Das Netz macht dieselbe Bewegung mit – sonst stünde das
      // Skelett neben der Figur.
      final parts = splitGlb(result.glb);
      final positions = readGltfFloats(parts.json, parts.bin, 0);
      expect(positions[3], closeTo(0, 1e-5)); // −z des zweiten Vertex
      expect(positions[4], closeTo(0.30 - 0.02, 1e-5));
      expect(positions[5], closeTo(0.05, 1e-5));
      final min = ((parts.json['accessors'] as List).first
          as Map<String, dynamic>)['min'] as List;
      expect((min[1] as num).toDouble(), closeTo(0.0, 1e-5));
    });

    test('Die Bind-Matrizen kehren die neue Weltlage um', () {
      for (final withBind in [true, false]) {
        final result = prepareRigForRoblox(
            _tripoBiped(withBindMatrices: withBind).glb);
        final parts = splitGlb(result.glb);
        final skin = (parts.json['skins'] as List).first
            as Map<String, dynamic>;
        final matrices = readGltfFloats(
            parts.json, parts.bin, (skin['inverseBindMatrices'] as num).toInt());
        final joints = (skin['joints'] as List).cast<int>();
        final nodes =
            (parts.json['nodes'] as List).cast<Map<String, dynamic>>();
        final world = _jointWorld(parts.json);
        for (var i = 0; i < joints.length; i++) {
          final name = nodes[joints[i]]['name'] as String;
          final p = world[name]!;
          expect(matrices[i * 16 + 12], closeTo(-p[0], 1e-5), reason: name);
          expect(matrices[i * 16 + 13], closeTo(-p[1], 1e-5), reason: name);
          expect(matrices[i * 16 + 14], closeTo(-p[2], 1e-5), reason: name);
          expect(matrices[i * 16], closeTo(1, 1e-6));
          expect(matrices[i * 16 + 5], closeTo(1, 1e-6));
          expect(matrices[i * 16 + 10], closeTo(1, 1e-6));
        }
      }
    });

    test('Der Wurzelknochen verliert seine Gewichte', () {
      final result = prepareRigForRoblox(_tripoBiped().glb);
      expect(result.report.unweightedVertices, 2);
      final parts = splitGlb(result.glb);
      final prim = ((parts.json['meshes'] as List).first
              as Map<String, dynamic>)['primitives'] as List;
      final attributes = (prim.first as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>;
      final weights = readGltfFloats(
          parts.json, parts.bin, (attributes['WEIGHTS_0'] as num).toInt());
      final skin =
          (parts.json['skins'] as List).first as Map<String, dynamic>;
      final joints = (skin['joints'] as List).cast<int>();
      final nodes =
          (parts.json['nodes'] as List).cast<Map<String, dynamic>>();
      final rootSlot = joints
          .indexWhere((j) => nodes[j]['name'] == robloxRootBone);
      final vertexJoints = splitGlb(result.glb);
      final raw = readGltfFloats(vertexJoints.json, vertexJoints.bin,
          (attributes['JOINTS_0'] as num).toInt());
      for (var v = 0; v < 6; v++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          final w = weights[v * 4 + k];
          sum += w;
          // JOINTS_0 liegt als Byte vor und wird beim Lesen auf 0–1
          // normiert; der Wurzelplatz ist daran wiedererkennbar.
          if ((raw[v * 4 + k] * 255).round() == rootSlot) {
            expect(w, lessThan(1e-4),
                reason: 'Vertex $v hängt noch an der Wurzel');
          }
        }
        expect(sum, closeTo(1, 1e-4), reason: 'Vertex $v summiert nicht 1');
      }
    });

    test('Ohne Zehen bleibt die Blickrichtung eine Annahme', () {
      // Ein Skelett mit Armspanne auf x und ohne Zehenknochen: Die
      // Seiten kommen dann nur noch aus der glTF-Konvention.
      final built = _tripoBiped();
      final json = splitGlb(built.glb).json;
      final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
      final skin = (json['skins'] as List).first as Map<String, dynamic>;
      final joints = (skin['joints'] as List);
      for (final name in const [
        'tripo::1_Left_Limb_3',
        'tripo::1_Right_Limb_3'
      ]) {
        final at = nodes.indexWhere((n) => n['name'] == name);
        final parent = nodes.firstWhere((n) =>
            (n['children'] as List? ?? const []).contains(at));
        (parent['children'] as List).remove(at);
        joints.remove(at);
      }
      final result = prepareRigForRoblox(joinGlb(json, splitGlb(built.glb).bin));
      expect(result.report.structure?.facingFromToes, isFalse);
      expect(result.report.notes.join(' '), contains('Zehenknochen'));
    });
  });
}
