import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bildgenerator/services/mesh_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sammelt Punkte und Dreiecke mehrerer Körper in einem Netz.
class _Netz {
  final List<double> punkte = [];
  final List<int> indizes = [];

  int punkt(double x, double y, double z) {
    punkte.addAll([x, y, z]);
    return punkte.length ~/ 3 - 1;
  }

  void dreieck(int a, int b, int c) => indizes.addAll([a, b, c]);

  Float32List get positions => Float32List.fromList(punkte);
  Uint32List get indices => Uint32List.fromList(indizes);
}

/// Ein geschlossener Quader, nach außen gewickelt.
void _quader(_Netz n, double cx, double cy, double cz, double b) {
  final h = b / 2;
  final p = [
    for (final (sx, sy, sz) in [
      (-1, -1, -1),
      (1, -1, -1),
      (1, 1, -1),
      (-1, 1, -1),
      (-1, -1, 1),
      (1, -1, 1),
      (1, 1, 1),
      (-1, 1, 1),
    ])
      n.punkt(cx + sx * h, cy + sy * h, cz + sz * h),
  ];
  for (final f in const [
    [0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
    [0, 1, 5], [0, 5, 4], [2, 3, 7], [2, 7, 6],
    [1, 2, 6], [1, 6, 5], [0, 4, 7], [0, 7, 3],
  ]) {
    n.dreieck(p[f[0]], p[f[1]], p[f[2]]);
  }
}

/// Eine Kugel – wahlweise mit doppelten Punkten an Polen und Naht,
/// wahlweise nach innen gewickelt. Genau die zwei Fehler, die der App
/// durchgerutscht sind, bis Blender sie zeigte.
void _kugel(
  _Netz n, {
  required bool doppeltePunkte,
  bool nachInnen = false,
  double cx = 0,
  double cy = 0,
  double cz = 0,
  double r = 1,
  int steps = 10,
}) {
  final ringe = steps ~/ 2;
  late final int Function(int, int) at;

  if (doppeltePunkte) {
    // Der naheliegende Aufbau: je Pol ein ganzer Ring gleicher Punkte,
    // und die erste Längsspalte am Ende noch einmal.
    final basis = n.punkte.length ~/ 3;
    for (var i = 0; i <= ringe; i++) {
      final phi = math.pi * i / ringe;
      for (var j = 0; j <= steps; j++) {
        final theta = 2 * math.pi * j / steps;
        n.punkt(
          cx + r * math.sin(phi) * math.cos(theta),
          cy + r * math.cos(phi),
          cz + r * math.sin(phi) * math.sin(theta),
        );
      }
    }
    at = (i, j) => basis + i * (steps + 1) + j;
  } else {
    // Ein Punkt je Pol, die letzte Spalte greift auf die erste zurück.
    final nord = n.punkt(cx, cy + r, cz);
    final ringBasis = n.punkte.length ~/ 3;
    for (var i = 1; i < ringe; i++) {
      final phi = math.pi * i / ringe;
      for (var j = 0; j < steps; j++) {
        final theta = 2 * math.pi * j / steps;
        n.punkt(
          cx + r * math.sin(phi) * math.cos(theta),
          cy + r * math.cos(phi),
          cz + r * math.sin(phi) * math.sin(theta),
        );
      }
    }
    final sued = n.punkt(cx, cy - r, cz);
    at = (i, j) => i <= 0
        ? nord
        : i >= ringe
            ? sued
            : ringBasis + (i - 1) * steps + j % steps;
  }

  void tri(int a, int b, int c) =>
      nachInnen ? n.dreieck(a, c, b) : n.dreieck(a, b, c);
  for (var i = 0; i < ringe; i++) {
    for (var j = 0; j < steps; j++) {
      if (i > 0) tri(at(i, j), at(i, j + 1), at(i + 1, j + 1));
      if (i < ringe - 1) tri(at(i, j), at(i + 1, j + 1), at(i + 1, j));
    }
  }
}

void main() {
  group('Randkanten mit und ohne Verschweißen', () {
    test('eine Kugel ohne Duplikate ist auch ungeschweißt geschlossen',
        () {
      final n = _Netz();
      _kugel(n, doppeltePunkte: false);
      final r = checkMeshWatertight(n.positions, n.indices);
      expect(r.openEdges, 0);
      expect(r.rawOpenEdges, 0);
      expect(r.seamEdges, 0);
      expect(r.watertight, isTrue);
      expect(r.watertightUnwelded, isTrue);
    });

    test('doppelte Pole und Naht sind ungeschweißt 46 Randkanten', () {
      // Der Fund aus Blender, nachgestellt: 2 × 10 Kanten je Pol plus
      // 5 Kanten an der Naht, dazu die Kappenkanten – zusammen 46.
      // Verschweißt meldet dieselbe Kugel null.
      final n = _Netz();
      _kugel(n, doppeltePunkte: true);
      final r = checkMeshWatertight(n.positions, n.indices);
      expect(r.openEdges, 0, reason: 'geometrisch ist sie geschlossen');
      expect(r.rawOpenEdges, 46);
      expect(r.seamEdges, 46);
      expect(r.watertight, isTrue);
      expect(r.watertightUnwelded, isFalse,
          reason: 'Blender und Roblox verschweißen nicht');
    });
  });

  group('Volumen mit Vorzeichen je Teil', () {
    test('jedes Teil einzeln, größtes zuerst', () {
      final n = _Netz();
      _quader(n, 0, 0, 0, 2); // Volumen 8
      _kugel(n, doppeltePunkte: false, cx: 10, r: 1);
      final r = checkMeshOrientation(n.positions, n.indices);
      expect(r.partVolumes.length, 2);
      expect(r.partVolumes.first, closeTo(8.0, 1e-4));
      // Die facettierte Kugel bleibt etwas unter 4/3·π.
      expect(r.partVolumes.last, closeTo(3.8, 0.4));
      expect(r.invertedParts, 0);
    });

    test('ein falsch gewickeltes Teil verschwindet nicht in der Summe',
        () {
      // Genau der Fall aus dem Gesichtsteile-Fund: ein großer richtiger
      // Körper und eine kleine Kugel verkehrt herum. Die Summe bleibt
      // deutlich positiv – die Kugel ist trotzdem falsch.
      final n = _Netz();
      _quader(n, 0, 0, 0, 4); // Volumen 64
      _kugel(n, doppeltePunkte: false, nachInnen: true, cx: 10, r: 0.5);
      final r = checkMeshOrientation(n.positions, n.indices);
      expect(r.signedVolume, greaterThan(60));
      expect(r.normalsInverted, isFalse,
          reason: 'die Summe allein verschweigt es');
      expect(r.invertedParts, 1);
      expect(r.partVolumes.where((v) => v < 0).length, 1);
    });

    test('alles verkehrt herum: jedes Teil zählt', () {
      final n = _Netz();
      _kugel(n, doppeltePunkte: false, nachInnen: true, r: 1);
      _kugel(n, doppeltePunkte: false, nachInnen: true, cx: 10, r: 1);
      final r = checkMeshOrientation(n.positions, n.indices);
      expect(r.invertedParts, 2);
      expect(r.normalsInverted, isTrue);
    });

    test('die Wicklung bleibt einheitlich, auch verkehrt herum', () {
      // Verkehrt herum heißt nicht uneinheitlich: Die Kantenzählung
      // meldet nichts, nur das Vorzeichen tut es. Deshalb braucht die
      // Prüfung beides.
      final n = _Netz();
      _kugel(n, doppeltePunkte: false, nachInnen: true);
      final r = checkMeshOrientation(n.positions, n.indices);
      expect(r.reversedEdges, 0);
      expect(r.windingConsistent, isTrue);
      expect(r.invertedParts, 1);
    });
  });
}
