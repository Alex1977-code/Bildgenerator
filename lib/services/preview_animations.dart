import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart';

/// Eingebaute Testanimationen für geriggte Modelle ohne eigene
/// Animations-Clips: bewegen die Gelenke des Standard-Skeletts
/// prozedural (Gehen, Flügelschlag, Schlängeln …), damit sich das
/// Rigging direkt in der App prüfen lässt.
class ProceduralClip {
  ProceduralClip(this.name, this.period, this._pose);

  final String name;

  /// Dauer eines vollständigen Bewegungszyklus in Sekunden – nach
  /// [period] wiederholt sich die Pose exakt (wichtig fürs Einbacken
  /// als loopbarer glTF-Clip).
  final double period;

  final Map<int, Float32List> Function(double t) _pose;

  /// Rotations-Overrides (Knotenindex → Quaternion) zum Zeitpunkt [t].
  Map<int, Float32List> poseAt(double t) => _pose(t);
}

Float32List _axisAngle(double x, double y, double z, double angle) {
  final half = angle / 2;
  final s = math.sin(half);
  return Float32List.fromList([x * s, y * s, z * s, math.cos(half)]);
}

/// Quaternion-Produkt a·b (erst b, dann a anwenden) – für kombinierte
/// Drehungen wie Lenken + Rollen eines Vorderrads.
Float32List _quatMultiply(Float32List a, Float32List b) {
  final ax = a[0], ay = a[1], az = a[2], aw = a[3];
  final bx = b[0], by = b[1], bz = b[2], bw = b[3];
  return Float32List.fromList([
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw,
    aw * bw - ax * bx - ay * by - az * bz,
  ]);
}

/// Passende Testanimationen für das Skelett von [rig] – erkannt an den
/// Gelenknamen des eigenen Auto-Riggers; dazu immer ein generischer
/// „Wackeltest“, der mit jedem Skelett funktioniert.
List<ProceduralClip> proceduralClipsFor(PreviewRig rig) {
  final names = rig.jointNames;
  final byName = <String, int>{
    for (var j = 0; j < rig.joints.length; j++) names[j]: rig.joints[j],
  };
  final clips = <ProceduralClip>[];

  void put(Map<int, Float32List> pose, String? name, Float32List q) {
    final node = byName[name];
    if (node != null) pose[node] = q;
  }

  if (byName.containsKey('Shoulder_L') && byName.containsKey('UpperLeg_L')) {
    clips.add(ProceduralClip('Gehen', 1 / 1.3, (t) {
      // Dezente Ausschläge: großer Armschwung und Rumpf-Drehung ziehen
      // sonst sichtbar an Anzug und Gürtel-Textur.
      final a = 0.42 * math.sin(t * 2 * math.pi * 1.3);
      final knee = 0.3 * (1 + math.sin(t * 2 * math.pi * 1.3 - 1.2)) / 2;
      final pose = <int, Float32List>{};
      put(pose, 'Shoulder_L', _axisAngle(1, 0, 0, a));
      put(pose, 'Shoulder_R', _axisAngle(1, 0, 0, -a));
      put(pose, 'UpperLeg_L', _axisAngle(1, 0, 0, -a * 0.8));
      put(pose, 'UpperLeg_R', _axisAngle(1, 0, 0, a * 0.8));
      put(pose, 'Knee_L', _axisAngle(1, 0, 0, knee));
      put(pose, 'Knee_R', _axisAngle(1, 0, 0, 0.3 - knee));
      put(pose, 'Spine', _axisAngle(0, 1, 0, a * 0.06));
      return pose;
    }));
    clips.add(ProceduralClip('Rennen', 1 / 2.2, (t) {
      final a = 0.62 * math.sin(t * 2 * math.pi * 2.2);
      final knee = 0.55 * (1 + math.sin(t * 2 * math.pi * 2.2 - 1.2)) / 2;
      final pose = <int, Float32List>{};
      put(pose, 'Shoulder_L', _axisAngle(1, 0, 0, a));
      put(pose, 'Shoulder_R', _axisAngle(1, 0, 0, -a));
      put(pose, 'Elbow_L', _axisAngle(1, 0, 0, -0.6));
      put(pose, 'Elbow_R', _axisAngle(1, 0, 0, -0.6));
      put(pose, 'UpperLeg_L', _axisAngle(1, 0, 0, -a));
      put(pose, 'UpperLeg_R', _axisAngle(1, 0, 0, a));
      put(pose, 'Knee_L', _axisAngle(1, 0, 0, knee));
      put(pose, 'Knee_R', _axisAngle(1, 0, 0, 0.55 - knee));
      put(pose, 'Spine', _axisAngle(1, 0, 0, 0.12));
      return pose;
    }));
    clips.add(ProceduralClip('Winken', 1 / 2.5, (t) {
      final a = 0.5 * math.sin(t * 2 * math.pi * 2.5);
      final pose = <int, Float32List>{};
      // Arm moderat heben – das Winken kommt aus dem Ellbogen, so
      // bleibt die Schulterpartie des Anzugs ruhig.
      put(pose, 'Shoulder_R', _axisAngle(0, 0, 1, 0.72));
      put(pose, 'Elbow_R', _axisAngle(0, 0, 1, 0.55 + a * 0.6));
      put(pose, 'Head', _axisAngle(0, 0, 1, a * 0.1));
      return pose;
    }));
    clips.add(ProceduralClip('Springen', 1 / 1.1, (t) {
      // Hocke → Absprung → Landung in einem Zyklus.
      final phase = math.sin(t * 2 * math.pi * 1.1);
      final crouch = phase < 0 ? -phase : 0.0;
      final stretch = phase > 0 ? phase : 0.0;
      final pose = <int, Float32List>{};
      put(pose, 'UpperLeg_L', _axisAngle(1, 0, 0, -0.6 * crouch));
      put(pose, 'UpperLeg_R', _axisAngle(1, 0, 0, -0.6 * crouch));
      put(pose, 'Knee_L', _axisAngle(1, 0, 0, 0.9 * crouch));
      put(pose, 'Knee_R', _axisAngle(1, 0, 0, 0.9 * crouch));
      put(pose, 'Spine', _axisAngle(1, 0, 0, 0.3 * crouch));
      put(pose, 'Shoulder_L', _axisAngle(1, 0, 0, -1.2 * stretch));
      put(pose, 'Shoulder_R', _axisAngle(1, 0, 0, -1.2 * stretch));
      return pose;
    }));
    clips.add(ProceduralClip('Verbeugen', 1 / 0.8, (t) {
      final a = 0.45 * (1 - math.cos(t * 2 * math.pi * 0.8)) / 2;
      final pose = <int, Float32List>{};
      put(pose, 'Spine', _axisAngle(1, 0, 0, a));
      put(pose, 'Chest', _axisAngle(1, 0, 0, a * 0.7));
      put(pose, 'Head', _axisAngle(1, 0, 0, a * 0.4));
      put(pose, 'Shoulder_L', _axisAngle(1, 0, 0, a * 0.3));
      put(pose, 'Shoulder_R', _axisAngle(1, 0, 0, a * 0.3));
      return pose;
    }));
    clips.add(ProceduralClip('Nicken', 1 / 1.6, (t) {
      final a = 0.3 * math.sin(t * 2 * math.pi * 1.6);
      final pose = <int, Float32List>{};
      put(pose, 'Head', _axisAngle(1, 0, 0, a));
      put(pose, 'Neck', _axisAngle(1, 0, 0, a * 0.4));
      return pose;
    }));
    clips.add(ProceduralClip('Kopf schütteln', 1 / 1.8, (t) {
      final a = 0.4 * math.sin(t * 2 * math.pi * 1.8);
      final pose = <int, Float32List>{};
      put(pose, 'Head', _axisAngle(0, 1, 0, a));
      put(pose, 'Neck', _axisAngle(0, 1, 0, a * 0.3));
      return pose;
    }));
    clips.add(ProceduralClip('Tanzen', 1 / 1.0, (t) {
      final a = math.sin(t * 2 * math.pi);
      final b2 = math.sin(t * 2 * math.pi * 2);
      final pose = <int, Float32List>{};
      put(pose, 'Hips', _axisAngle(0, 0, 1, 0.12 * a));
      put(pose, 'Spine', _axisAngle(0, 0, 1, -0.1 * a));
      put(pose, 'Shoulder_L', _axisAngle(0, 0, 1, 0.9 + 0.35 * b2));
      put(pose, 'Shoulder_R', _axisAngle(0, 0, 1, -0.9 + 0.35 * b2));
      put(pose, 'Elbow_L', _axisAngle(0, 0, 1, 0.5 * a));
      put(pose, 'Elbow_R', _axisAngle(0, 0, 1, 0.5 * a));
      put(pose, 'Head', _axisAngle(0, 0, 1, 0.08 * b2));
      return pose;
    }));
    clips.add(ProceduralClip('Atmen (Idle)', 1 / 0.4, (t) {
      final a = math.sin(t * 2 * math.pi * 0.4);
      final pose = <int, Float32List>{};
      put(pose, 'Chest', _axisAngle(1, 0, 0, -0.035 * a));
      put(pose, 'Neck', _axisAngle(1, 0, 0, 0.02 * a));
      put(pose, 'Shoulder_L', _axisAngle(0, 0, 1, 0.03 * a));
      put(pose, 'Shoulder_R', _axisAngle(0, 0, 1, -0.03 * a));
      return pose;
    }));
  }

  if (byName.containsKey('FrontUpperLeg_L')) {
    clips.add(ProceduralClip('Gehen (Vierbeiner)', 2 / 1.5, (t) {
      final a = 0.4 * math.sin(t * 2 * math.pi * 1.5);
      final tail = 0.25 * math.sin(t * 2 * math.pi * 0.75);
      final pose = <int, Float32List>{};
      // Diagonale Beinpaare schwingen gegengleich.
      put(pose, 'FrontUpperLeg_L', _axisAngle(1, 0, 0, a));
      put(pose, 'HindUpperLeg_R', _axisAngle(1, 0, 0, a));
      put(pose, 'FrontUpperLeg_R', _axisAngle(1, 0, 0, -a));
      put(pose, 'HindUpperLeg_L', _axisAngle(1, 0, 0, -a));
      put(pose, 'FrontLowerLeg_L', _axisAngle(1, 0, 0, a * 0.5));
      put(pose, 'HindLowerLeg_R', _axisAngle(1, 0, 0, a * 0.5));
      put(pose, 'FrontLowerLeg_R', _axisAngle(1, 0, 0, -a * 0.5));
      put(pose, 'HindLowerLeg_L', _axisAngle(1, 0, 0, -a * 0.5));
      put(pose, 'Tail_1', _axisAngle(0, 1, 0, tail));
      put(pose, 'Tail_2', _axisAngle(0, 1, 0, tail * 1.4));
      put(pose, 'Neck', _axisAngle(1, 0, 0, a * 0.15));
      return pose;
    }));
    clips.add(ProceduralClip('Schwanzwedeln', 1 / 3.0, (t) {
      final a = 0.5 * math.sin(t * 2 * math.pi * 3.0);
      final pose = <int, Float32List>{};
      put(pose, 'Tail_1', _axisAngle(0, 1, 0, a));
      put(pose, 'Tail_2', _axisAngle(0, 1, 0, a * 1.5));
      put(pose, 'Hips', _axisAngle(0, 1, 0, a * 0.06));
      return pose;
    }));
  }

  if (byName.containsKey('Wing_L')) {
    clips.add(ProceduralClip('Flügelschlag', 1 / 2.4, (t) {
      final a = 0.55 * math.sin(t * 2 * math.pi * 2.4);
      final b = 0.35 * math.sin(t * 2 * math.pi * 2.4 - 0.7);
      final pose = <int, Float32List>{};
      put(pose, 'Wing_L', _axisAngle(0, 0, 1, a));
      put(pose, 'Wing_R', _axisAngle(0, 0, 1, -a));
      put(pose, 'WingMid_L', _axisAngle(0, 0, 1, b));
      put(pose, 'WingMid_R', _axisAngle(0, 0, 1, -b));
      put(pose, 'Tail', _axisAngle(1, 0, 0, a * 0.2));
      return pose;
    }));
  }

  if (byName.containsKey('Leg1Hip_L')) {
    clips.add(ProceduralClip('Krabbeln', 1 / 2.0, (t) {
      final a = 0.35 * math.sin(t * 2 * math.pi * 2.0);
      final pose = <int, Float32List>{};
      // Wechseltritt in zwei Dreiergruppen (Tripod-Gang).
      for (final (leg, sign) in [
        ('Leg1Hip_L', 1.0),
        ('Leg2Hip_R', 1.0),
        ('Leg3Hip_L', 1.0),
        ('Leg1Hip_R', -1.0),
        ('Leg2Hip_L', -1.0),
        ('Leg3Hip_R', -1.0),
      ]) {
        put(pose, leg, _axisAngle(0, 1, 0, sign * a));
      }
      put(pose, 'Abdomen_1', _axisAngle(1, 0, 0, a * 0.2));
      return pose;
    }));
  }

  final isChain = byName.containsKey('Spine_1') &&
      byName.containsKey('Head') &&
      !byName.containsKey('UpperLeg_L') &&
      !byName.containsKey('Wing_L') &&
      !byName.containsKey('Leg1Hip_L') &&
      !byName.containsKey('FrontUpperLeg_L');
  if (isChain) {
    final isFish = rig.joints.length <= 6;
    clips.add(ProceduralClip(isFish ? 'Schwimmen' : 'Schlängeln', 1 / 1.6, (t) {
      final pose = <int, Float32List>{};
      for (var j = 0; j < rig.joints.length; j++) {
        // Welle läuft vom Kopf zum Schwanz; beim Fisch hinten stärker.
        final strength = isFish ? 0.12 + 0.06 * j : 0.3;
        final angle =
            strength * math.sin(t * 2 * math.pi * 1.6 - j * 0.9);
        pose[rig.joints[j]] = _axisAngle(0, 1, 0, angle);
      }
      return pose;
    }));
  }

  // Fahrzeug-Rig: alle Rad-Gelenke (Wheel…), egal ob 1 Rad (Einrad),
  // 2 (Fahrrad/Motorrad), 4 (Auto) oder 6+ (Bus/LKW).
  final wheelJoints = [
    for (var j = 0; j < rig.joints.length; j++)
      if (names[j].startsWith('Wheel')) rig.joints[j],
  ];
  if (wheelJoints.isNotEmpty) {
    clips.add(ProceduralClip('Fahren', 1.2, (t) {
      // Räder drehen kontinuierlich durch (eine volle Umdrehung je
      // Periode – loopt sauber), die Karosserie wippt leicht.
      final angle = -2 * math.pi * (t / 1.2);
      final bounce = 0.015 * math.sin(t * 2 * math.pi * (2 / 1.2));
      final pose = <int, Float32List>{};
      for (final node in wheelJoints) {
        pose[node] = _axisAngle(1, 0, 0, angle);
      }
      put(pose, 'Body', _axisAngle(1, 0, 0, bounce));
      return pose;
    }));
    clips.add(ProceduralClip('Fahren (Kurven)', 2.4, (t) {
      // Rollende Räder plus Lenk-Pendeln der Vorderachse (Wheel1…)
      // und leichte Karosserie-Neigung in die Kurve.
      final angle = -2 * math.pi * (t / 1.2);
      final steer = 0.35 * math.sin(t * 2 * math.pi / 2.4);
      final pose = <int, Float32List>{};
      for (var j = 0; j < rig.joints.length; j++) {
        final name = names[j];
        if (!name.startsWith('Wheel')) continue;
        if (name.startsWith('Wheel1')) {
          // Lenkung (y) und Rollen (x) kombiniert.
          pose[rig.joints[j]] =
              _quatMultiply(_axisAngle(0, 1, 0, steer),
                  _axisAngle(1, 0, 0, angle));
        } else {
          pose[rig.joints[j]] = _axisAngle(1, 0, 0, angle);
        }
      }
      put(pose, 'Body', _axisAngle(0, 0, 1, -steer * 0.08));
      return pose;
    }));
  }

  // Showcase für jedes Skelett: das Wurzelgelenk dreht sich einmal um
  // die eigene Achse (Turntable).
  for (var j = 0; j < rig.joints.length; j++) {
    if (rig.jointParents[j] < 0) {
      final root = rig.joints[j];
      clips.add(ProceduralClip('Drehen (Schau)', 4.0, (t) {
        return {root: _axisAngle(0, 1, 0, 2 * math.pi * t / 4.0)};
      }));
      break;
    }
  }

  // Generischer Test für jedes Skelett (auch fremde Rigs).
  clips.add(ProceduralClip('Wackeltest', 1 / 1.2, (t) {
    final pose = <int, Float32List>{};
    for (var j = 0; j < rig.joints.length; j++) {
      final angle = 0.08 * math.sin(t * 2 * math.pi * 1.2 + j * 0.7);
      pose[rig.joints[j]] = _axisAngle(0, 0, 1, angle);
    }
    return pose;
  }));

  return clips;
}
