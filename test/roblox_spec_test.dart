import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/roblox_check.dart';
import 'package:bildgenerator/services/roblox_prompt.dart';
import 'package:bildgenerator/services/roblox_rig.dart';
import 'package:bildgenerator/services/roblox_spec.dart';

/// Prüfung, Rigging und Vorlage müssen auf denselben Zahlen stehen.
/// Vorher lagen sie verstreut, teils als Faustregel – wer eine änderte,
/// merkte nicht, dass die anderen nicht mitgingen.
void main() {
  group('Die Zahlen stimmen überein', () {
    test('Prüfung und Spezifikation', () {
      expect(robloxMaxTriangles, specMaxMeshTriangles);
      expect(robloxAccessoryTriangles, specAccessoryTriangles);
      expect(robloxMaxTexture, specMaxTexture);
      expect(robloxMaxInfluences, specMaxInfluences);
    });

    test('Das Arbeitsziel bleibt unter dem Marktplatz-Budget', () {
      // 10.000 als runde Zahl, aber nicht über dem, was ein zerlegter
      // R15-Körper zusammen ausgeben darf.
      expect(robloxGoalTriangles, lessThanOrEqualTo(specBodyTotalTriangles));
      expect(robloxGoalTriangles, lessThan(specMaxMeshTriangles));
    });

    test('Die Einzelbudgets ergeben die Summe der Tabelle', () {
      final summe = specBodyPartTriangles.values
          .fold<int>(0, (a, b) => a + b);
      expect(summe, specBodyTotalTriangles);
    });

    test('Die Marktplatz-Textur ist die weitere Grenze', () {
      expect(specMarketplaceTexture, greaterThan(specMaxTexture));
    });
  });

  group('Die Namen stimmen überein', () {
    test('Die Gelenkliste entsteht aus der Hierarchie', () {
      expect(robloxR15Bones, specR15Joints);
      expect(robloxR15Bones.first, specRootNode);
      // 15 Gelenke der Figur plus der Wurzelknoten.
      expect(robloxR15Bones.length, 16);
    });

    test('Jedes Gelenk der Hierarchie hat genau einen Elternteil', () {
      final kinder = <String, int>{};
      for (final entry in specR15Hierarchy.entries) {
        for (final kind in entry.value) {
          kinder[kind] = (kinder[kind] ?? 0) + 1;
        }
      }
      for (final name in specR15Joints) {
        expect(kinder[name], 1, reason: name);
      }
      // Nur die Wurzel hat keinen.
      expect(kinder[specRootBone], isNull);
    });

    test('Zu jedem Körperteil gehört ein Mesh-Name auf _Geo', () {
      expect(specBodyMeshNames.length, 15);
      for (final name in specBodyMeshNames) {
        expect(name, endsWith('_Geo'));
        final gelenk = name.substring(0, name.length - 4);
        expect(specR15Joints, contains(gelenk), reason: name);
      }
      // Umgekehrt: alle Gelenke außer dem Wurzelknoten haben ein Mesh.
      for (final gelenk in specR15Joints) {
        if (gelenk == specRootNode) continue;
        expect(specBodyMeshNames, contains('${gelenk}_Geo'),
            reason: gelenk);
      }
    });

    test('Der Wurzelknochen folgt der Körper-Spezifikation', () {
      expect(robloxRootBone, specRootNode);
      expect(robloxRootBone, 'HumanoidRootNode');
      expect(robloxRootParent, specRootBone);
      expect(robloxRootParent, 'Root');
    });
  });

  group('Die Vorlage nennt die Vorgaben', () {
    test('Figur: Dreiecke, Hülle, Volumen, Rig, Pose', () {
      final text = robloxPromptRules(accessory: false);
      expect(text, contains('20.000'));
      expect(text, contains('10.742'));
      expect(text, contains('geschlossen'));
      expect(text, contains('Volumen'));
      expect(text, contains('R15-Gelenke'));
      expect(text, contains('LowerTorso'));
      for (final pose in specAllowedPoses) {
        expect(text, contains(pose), reason: pose);
      }
    });

    test('Accessoire: ein Mesh, 4.000 Dreiecke, kein Rig', () {
      final text = robloxPromptRules(accessory: true);
      expect(text, contains('4.000'));
      expect(text, contains('Ein einziges Mesh'));
      expect(text, isNot(contains('R15-Gelenke')));
      // Die Körper-Budgets gelten hier nicht.
      expect(text, isNot(contains('10.742')));
    });

    test('Die Texturgrenze steht in beiden', () {
      for (final accessory in [true, false]) {
        expect(robloxPromptRules(accessory: accessory),
            contains('${specMaxTexture}er-Textur'));
      }
    });
  });
}
