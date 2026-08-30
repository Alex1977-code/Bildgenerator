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
}
