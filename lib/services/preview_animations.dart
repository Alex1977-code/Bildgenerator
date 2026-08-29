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
      final a = 0.5 * math.sin(t * 2 * math.pi * 1.3);
      final knee = 0.3 * (1 + math.sin(t * 2 * math.pi * 1.3 - 1.2)) / 2;
      final pose = <int, Float32List>{};
      put(pose, 'Shoulder_L', _axisAngle(1, 0, 0, a));
      put(pose, 'Shoulder_R', _axisAngle(1, 0, 0, -a));
      put(pose, 'UpperLeg_L', _axisAngle(1, 0, 0, -a * 0.8));
      put(pose, 'UpperLeg_R', _axisAngle(1, 0, 0, a * 0.8));
      put(pose, 'Knee_L', _axisAngle(1, 0, 0, knee));
      put(pose, 'Knee_R', _axisAngle(1, 0, 0, 0.3 - knee));
      put(pose, 'Spine', _axisAngle(0, 1, 0, a * 0.1));
      return pose;
    }));
    clips.add(ProceduralClip('Winken', 1 / 2.5, (t) {
      final a = 0.5 * math.sin(t * 2 * math.pi * 2.5);
      final pose = <int, Float32List>{};
      put(pose, 'Shoulder_R', _axisAngle(0, 0, 1, 0.9));
      put(pose, 'Elbow_R', _axisAngle(0, 0, 1, 0.5 + a * 0.6));
      put(pose, 'Head', _axisAngle(0, 0, 1, a * 0.1));
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

  if (byName.containsKey('Wheel_FL')) {
    clips.add(ProceduralClip('Fahren', 1.2, (t) {
      // Räder drehen kontinuierlich durch (eine volle Umdrehung je
      // Periode – loopt sauber), die Karosserie wippt leicht.
      final angle = -2 * math.pi * (t / 1.2);
      final bounce = 0.015 * math.sin(t * 2 * math.pi * (2 / 1.2));
      final pose = <int, Float32List>{};
      for (final wheel in ['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR']) {
        put(pose, wheel, _axisAngle(1, 0, 0, angle));
      }
      put(pose, 'Body', _axisAngle(1, 0, 0, bounce));
      return pose;
    }));
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
