import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/r15_split.dart';
import 'package:bildgenerator/services/roblox_rig.dart';
import 'package:bildgenerator/services/roblox_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eine stehende Figur mit Armen und Beinen – genug Form, dass der
/// Auto-Rigger alle Gelenke findet.
LocalMesh _figur() {
  final m = LocalMesh();
  void quader(double x0, double y0, double z0, double x1, double y1,
      double z1) {
    final p = [
      m.addVertex(x0, y0, z0, 0, 0),
      m.addVertex(x1, y0, z0, 1, 0),
      m.addVertex(x1, y1, z0, 1, 1),
      m.addVertex(x0, y1, z0, 0, 1),
      m.addVertex(x0, y0, z1, 0, 0),
      m.addVertex(x1, y0, z1, 1, 0),
      m.addVertex(x1, y1, z1, 1, 1),
      m.addVertex(x0, y1, z1, 0, 1),
    ];
    m.addQuad(p[0], p[3], p[2], p[1]);
    m.addQuad(p[4], p[5], p[6], p[7]);
    m.addQuad(p[0], p[1], p[5], p[4]);
    m.addQuad(p[2], p[3], p[7], p[6]);
    m.addQuad(p[1], p[2], p[6], p[5]);
    m.addQuad(p[0], p[4], p[7], p[3]);
  }

  quader(-0.35, 0.9, -0.15, 0.35, 2.1, 0.15); // Rumpf
  quader(-0.22, 2.1, -0.2, 0.22, 2.6, 0.2); // Kopf
  quader(-0.85, 1.2, -0.1, -0.35, 2.05, 0.1); // Arm links
  quader(0.35, 1.2, -0.1, 0.85, 2.05, 0.1); // Arm rechts
  quader(-0.32, 0.0, -0.12, -0.05, 0.9, 0.12); // Bein links
  quader(0.05, 0.0, -0.12, 0.32, 0.9, 0.12); // Bein rechts
  return m;
}

Uint8List _geriggt() {
  final glb = injectAutoRig(buildGlb(_figur()), rigType: 'biped');
  return prepareRigForRoblox(glb).glb;
}

void main() {
  group('Zerlegung in 15 Meshes', () {
    late R15SplitResult ergebnis;

    setUpAll(() {
      ergebnis = splitGlbIntoR15Parts(_geriggt());
    });

    test('kein Dreieck geht verloren', () async {
      final vorher = await parseGlbForPreview(_geriggt());
      final davor = vorher.indices.length ~/ 3;
      vorher.dispose();
      expect(ergebnis.report.totalTriangles, davor);
    });

    test('die Meshes heißen so, wie Roblox sie erwartet', () {
      final json = splitGlb(ergebnis.glb).json;
      final namen = [
        for (final mesh in json['meshes'] as List)
          (mesh as Map)['name'] as String,
      ];
      expect(namen, isNotEmpty);
      for (final name in namen) {
        expect(specBodyMeshNames, contains(name),
            reason: '$name steht nicht in der Spezifikation');
      }
      // Jeder Name höchstens einmal.
      expect(namen.toSet().length, namen.length);
    });

    test('jedes Mesh hängt am Skelett', () {
      final json = splitGlb(ergebnis.glb).json;
      final nodes = (json['nodes'] as List).cast<Map>();
      final mitNetz = [for (final n in nodes) if (n.containsKey('mesh')) n];
      expect(mitNetz.length, (json['meshes'] as List).length);
      for (final node in mitNetz) {
        expect(node['skin'], 0, reason: '${node['name']} ohne Skin');
      }
    });

    test('Rumpf, Kopf, Arme und Beine kommen alle vor', () {
      final belegt = {
        for (final p in ergebnis.report.parts)
          if (!p.isEmpty) p.group,
      };
      expect(belegt, containsAll(<String>[
        'DynamicHead',
        'Torso',
        'LeftArm',
        'RightArm',
        'LeftLeg',
        'RightLeg',
      ]));
    });

    test('Zwischenknochen werden zurückgeführt', () {
      // Der Auto-Rigger setzt „Spine" und „Neck" – beide haben in R15
      // kein Gegenstück und müssen am Vorfahren landen, nicht im
      // Nichts.
      expect(ergebnis.report.tracedBones, greaterThan(0));
      expect(ergebnis.report.unmappedTriangles, 0);
    });

    test('die Gruppen werden gegen ihr Budget gerechnet', () {
      for (final gruppe in ergebnis.report.groupTriangles.keys) {
        expect(specBodyPartTriangles.containsKey(gruppe), isTrue,
            reason: '$gruppe ist keine Marktplatz-Gruppe');
      }
      // Die Testfigur ist winzig; sie muss ins Budget passen.
      expect(ergebnis.report.fitsBudget, isTrue,
          reason: ergebnis.report.overBudget.toString());
    });

    test('das Ergebnis lässt sich wieder lesen', () async {
      final mesh = await parseGlbForPreview(ergebnis.glb);
      try {
        expect(mesh.indices.length ~/ 3, ergebnis.report.totalTriangles);
        expect(mesh.rig, isNotNull);
      } finally {
        mesh.dispose();
      }
    });

    test('die Punkte liegen nach der Zerlegung genauso wie vorher',
        () async {
      // Der Beweis, dass nur getrennt und nichts verschoben wurde:
      // Der umschließende Quader muss auf die dritte Stelle stimmen.
      final vorher = await parseGlbForPreview(_geriggt());
      final nachher = await parseGlbForPreview(ergebnis.glb);
      List<double> box(Float32List p) {
        final lo = [double.infinity, double.infinity, double.infinity];
        final hi = [
          double.negativeInfinity,
          double.negativeInfinity,
          double.negativeInfinity
        ];
        for (var i = 0; i + 2 < p.length; i += 3) {
          for (var k = 0; k < 3; k++) {
            lo[k] = math.min(lo[k], p[i + k]);
            hi[k] = math.max(hi[k], p[i + k]);
          }
        }
        return [...lo, ...hi];
      }

      final a = box(vorher.positions);
      final b = box(nachher.positions);
      vorher.dispose();
      nachher.dispose();
      for (var i = 0; i < 6; i++) {
        expect(b[i], closeTo(a[i], 1e-3), reason: 'Achse $i');
      }
    });

    test('der Bericht nennt Teile, Gruppen und die Summe', () {
      final text = ergebnis.report.text;
      expect(text, contains('_Geo'));
      expect(text, contains('Torso'));
      expect(text, contains('Summe'));
      expect(text, contains('$specBodyTotalTriangles'));
    });
  });

  test('ohne Skelett gibt es eine verständliche Absage', () {
    expect(
      () => splitGlbIntoR15Parts(buildGlb(_figur())),
      throwsA(predicate((e) => '$e'.contains('Skin-Gewichten'))),
    );
  });

  test('jedes Teil kennt seine Marktplatz-Gruppe', () {
    for (final name in r15PartNames) {
      expect(r15PartGroup.containsKey(name), isTrue, reason: name);
    }
    expect(r15PartNames.length, 15);
    expect(r15PartGroup.values.toSet().length, 6);
  });
}
