import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/rig_dummy.dart';

/// Ein grober Körper aus zwei Beinen, Rumpf, Kopf und vier Rädern –
/// genug, dass jede Skelett-Vorlage etwas zu greifen hat.
LocalMesh _testBody() {
  final mesh = LocalMesh();
  void box(double x0, double x1, double y0, double y1, double z0,
      double z1) {
    final v = <int>[];
    for (final x in [x0, x1]) {
      for (final y in [y0, y1]) {
        for (final z in [z0, z1]) {
          v.add(mesh.addVertex(x, y, z, 0.5, 0.5));
        }
      }
    }
    for (var i = 0; i + 2 < v.length; i++) {
      mesh.addTriangle(v[i], v[i + 1], v[i + 2]);
    }
  }

  box(-0.5, -0.2, 0, 0.5, -0.4, 0.4); // linkes Bein / linke Räder
  box(0.2, 0.5, 0, 0.5, -0.4, 0.4); // rechtes Bein / rechte Räder
  box(-0.4, 0.4, 0.5, 1.0, -0.3, 0.3); // Rumpf
  box(-0.2, 0.2, 1.0, 1.3, -0.2, 0.2); // Kopf
  return mesh;
}

void main() {
  test('Zu jedem Figurtyp gibt es einen Dummy', () {
    for (final (type, _) in rigTypeOptions) {
      final dummy = rigDummyFor(type);
      expect(dummy, isNotNull, reason: 'kein Dummy für $type');
      expect(dummy!.type, type);
      expect(dummy.joints, isNotEmpty);
      expect(dummy.limbs, isNotEmpty);
      expect(dummy.note, isNotEmpty);
      expect(dummy.view, isNotEmpty);
    }
    expect(rigDummyFor('gibtsnicht'), isNull);
  });

  test('Alle Punkte liegen im Zeichenfeld', () {
    for (final (type, _) in rigTypeOptions) {
      final dummy = rigDummyFor(type)!;
      for (final joint in dummy.joints) {
        expect(joint.x, inInclusiveRange(-0.5, 0.5),
            reason: '$type/${joint.name}');
        expect(joint.y, inInclusiveRange(0.0, 1.0),
            reason: '$type/${joint.name}');
        expect(joint.radius, greaterThan(0));
        expect(joint.hint, isNotEmpty);
      }
    }
  });

  group('Gelenkname findet seinen Punkt', () {
    test('Genau, ohne Nummer, ohne Seite', () {
      final biped = rigDummyFor('biped')!;
      expect(dummyJointFor(biped, 'Shoulder_L')!.name, 'Shoulder_L');
      // Die Seite stimmt: links liegt links.
      expect(dummyJointFor(biped, 'Shoulder_L')!.x,
          lessThan(dummyJointFor(biped, 'Shoulder_R')!.x));

      // Ein Insekt hat drei Beinpaare; der Dummy zeigt jedes, aber
      // ein viertes Paar fiele auf das erste zurück.
      final insect = rigDummyFor('insect')!;
      expect(dummyJointFor(insect, 'Leg2Hip_R')!.name, 'Leg2Hip_R');
      expect(dummyJointFor(insect, 'Leg9Hip_R'), isNotNull);

      // In der Seitenansicht gibt es nur eine Seite – die andere liegt
      // dahinter und bekommt denselben Punkt.
      final vehicle = rigDummyFor('vehicle')!;
      expect(dummyJointFor(vehicle, 'Wheel1_R')!.name, 'Wheel1_L');
      expect(dummyJointFor(vehicle, 'Wheel4_R'), isNotNull);
    });

    test('Unbekannte Namen liefern nichts statt eines falschen Punktes',
        () {
      expect(dummyJointFor(rigDummyFor('biped')!, 'Sonderling'), isNull);
    });
  });

  test('Jedes Gelenk des echten Skeletts steht im Dummy', () {
    // Der eigentliche Zweck der Anleitung: Wer im Editor einen Punkt
    // antippt, soll ihn in der Zeichnung wiederfinden. Die Namen
    // kommen deshalb aus dem echten Rigger, nicht aus einer von Hand
    // gepflegten Liste – sonst liefe die Zeichnung irgendwann neben
    // dem Skelett her.
    final glb = buildGlb(_testBody());
    for (final (type, _) in rigTypeOptions) {
      final dummy = rigDummyFor(type)!;
      final joints = computeAutoRigJoints(glb, rigType: type);
      expect(joints, isNotEmpty, reason: type);
      for (final joint in joints) {
        expect(dummyJointFor(dummy, joint.name), isNotNull,
            reason: '$type: „${joint.name}" fehlt in der Zeichnung');
      }
    }
  });

  test('Die empfohlenen Einflussbereiche überdecken sich nicht völlig',
      () {
    // Zwei Punkte, deren Ringe ineinanderliegen, wären als Anleitung
    // wertlos – dann sähe man nicht, wo das eine Körperteil aufhört.
    for (final (type, _) in rigTypeOptions) {
      final dummy = rigDummyFor(type)!;
      for (var i = 0; i < dummy.joints.length; i++) {
        for (var j = i + 1; j < dummy.joints.length; j++) {
          final a = dummy.joints[i], b = dummy.joints[j];
          final dx = a.x - b.x, dy = a.y - b.y;
          final distance = dx * dx + dy * dy;
          expect(distance, greaterThan(0),
              reason: '$type: ${a.name} und ${b.name} liegen aufeinander');
        }
      }
    }
  });
}
