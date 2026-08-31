import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/rig_detect.dart';

/// Punktwolke aus achsparallelen Quadern – reicht, um Form zu
/// vermessen: Die Erkennung schaut auf Standflächen und Proportionen,
/// nicht auf Dreiecke.
class _Cloud {
  final List<double> _points = [];

  /// Ein gefüllter Quader, gerastert. [step] ist die Punktdichte.
  void box(double x0, double y0, double z0, double x1, double y1,
      double z1, {double step = 0.02}) {
    for (var x = x0; x <= x1 + 1e-9; x += step) {
      for (var y = y0; y <= y1 + 1e-9; y += step) {
        for (var z = z0; z <= z1 + 1e-9; z += step) {
          _points.addAll([x, y, z]);
        }
      }
    }
  }

  /// Eine Scheibe in der yz-Ebene (ein Rad): Mittelpunkt (y, z),
  /// Radius r, Dicke in x.
  void wheel(double x0, double x1, double y, double z, double r,
      {double step = 0.02}) {
    for (var dy = -r; dy <= r + 1e-9; dy += step) {
      for (var dz = -r; dz <= r + 1e-9; dz += step) {
        if (dy * dy + dz * dz > r * r) continue;
        for (var x = x0; x <= x1 + 1e-9; x += step) {
          _points.addAll([x, y + dy, z + dz]);
        }
      }
    }
  }

  Float32List get positions => Float32List.fromList(_points);
  RigShape get shape => measureRigShape([positions]);
  List<RigTypeGuess> get guesses => guessRigType(shape);
  String? get best => guesses.isEmpty ? null : guesses.first.type;
}

/// Stehende Figur in T-Pose: zwei Beine, Rumpf, zwei waagerechte Arme.
_Cloud _biped() {
  final c = _Cloud();
  for (final sx in [-1.0, 1.0]) {
    c.box(sx * 0.10 - 0.05, 0, -0.06, sx * 0.10 + 0.05, 0.90, 0.06);
    // Arm, waagerecht abgespreizt.
    c.box(sx > 0 ? 0.20 : -0.52, 1.35, -0.04, sx > 0 ? 0.52 : -0.20, 1.44,
        0.04);
  }
  c.box(-0.18, 0.88, -0.10, 0.18, 1.50, 0.10); // Rumpf
  c.box(-0.12, 1.50, -0.12, 0.12, 1.80, 0.12); // Kopf
  return c;
}

/// Vierbeiner: waagerechter Rumpf auf vier Beinen.
_Cloud _quadruped() {
  final c = _Cloud();
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      c.box(sx * 0.16 - 0.045, 0, sz * 0.36 - 0.045, sx * 0.16 + 0.045,
          0.44, sz * 0.36 + 0.045);
    }
  }
  c.box(-0.20, 0.42, -0.55, 0.20, 0.72, 0.55); // Rumpf
  c.box(-0.13, 0.62, 0.50, 0.13, 0.92, 0.78); // Kopf vorn
  return c;
}

/// Auto: Karosserie auf vier Rädern.
_Cloud _car() {
  final c = _Cloud();
  c.box(-0.38, 0.22, -0.95, 0.38, 0.70, 0.95); // Karosserie
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 1.0]) {
      c.wheel(sx * 0.36 - 0.06, sx * 0.36 + 0.06, 0.22, sz * 0.62, 0.22);
    }
  }
  return c;
}

/// Schlange: langer, dünner Strang am Boden.
_Cloud _snake() {
  final c = _Cloud();
  c.box(-0.09, 0, -1.60, 0.09, 0.17, 1.60);
  return c;
}

/// Fisch: seitlich zusammengedrückt, keine Beine.
_Cloud _fish() {
  final c = _Cloud();
  c.box(-0.05, 0, -0.60, 0.05, 0.50, 0.60);
  return c;
}

/// Insekt: sechs Beine in drei Paaren.
_Cloud _insect() {
  final c = _Cloud();
  for (final sx in [-1.0, 1.0]) {
    for (final sz in [-1.0, 0.0, 1.0]) {
      c.box(sx * 0.22 - 0.035, 0, sz * 0.30 - 0.035, sx * 0.22 + 0.035,
          0.26, sz * 0.30 + 0.035);
    }
  }
  c.box(-0.13, 0.24, -0.55, 0.13, 0.42, 0.55);
  return c;
}

/// Vogel: kurze Beine, waagerechter Rumpf, gespreizte Flügel.
_Cloud _bird() {
  final c = _Cloud();
  for (final sx in [-1.0, 1.0]) {
    c.box(sx * 0.07 - 0.025, 0, -0.025, sx * 0.07 + 0.025, 0.22, 0.025);
  }
  c.box(-0.13, 0.20, -0.34, 0.13, 0.44, 0.34); // Rumpf, waagerecht
  c.box(-0.09, 0.38, 0.26, 0.09, 0.56, 0.44); // Kopf
  for (final sx in [-1.0, 1.0]) {
    // Flügel, seitlich abgespreizt.
    c.box(sx > 0 ? 0.12 : -0.62, 0.30, -0.24, sx > 0 ? 0.62 : -0.12, 0.38,
        0.24);
  }
  return c;
}

/// Ein Haus: ein Klotz ohne Gliedmaßen.
_Cloud _building() {
  final c = _Cloud();
  c.box(-0.5, 0, -0.5, 0.5, 0.9, 0.5);
  return c;
}

void main() {
  group('Formmerkmale messen', () {
    test('Aufrechtheit, Streckung und Flachheit', () {
      final biped = _biped().shape;
      expect(biped.uprightness, greaterThan(1.5));
      final snake = _snake().shape;
      expect(snake.uprightness, lessThan(0.4));
      expect(snake.elongation, greaterThan(3));
      expect(_fish().shape.lateralFlatness, lessThan(0.5));
    });

    test('Standflächen werden gezählt und getrennt', () {
      expect(_biped().shape.ground.length, 2);
      expect(_quadruped().shape.ground.length, 4);
      expect(_insect().shape.ground.length, 6);
      expect(_building().shape.ground.length, 1);
    });

    test('Ein langer Körper am Boden zählt nicht als Rad', () {
      // Sonst wäre eine Schlange ein einachsiges Fahrzeug.
      expect(_snake().shape.wheelish, 0);
      expect(_fish().shape.wheelish, 0);
    });

    test('Ein Rad ist länger als breit, ein Bein ist rund', () {
      // Genau daran hängt die Trennung Auto/Vierbeiner: Beide haben
      // vier Punkte am Boden.
      expect(_car().shape.wheelish, 4);
      expect(_quadruped().shape.wheelish, 0);
    });

    test('Ein leeres Netz liefert keine Messwerte statt eines Absturzes',
        () {
      final leer = measureRigShape([Float32List(0)]);
      expect(leer.points, 0);
      expect(leer.ground, isEmpty);
      expect(guessRigType(leer), isEmpty);
    });
  });

  group('Typ erkennen', () {
    test('Zweibeiner in T-Pose', () {
      final guesses = _biped().guesses;
      expect(guesses.first.type, 'biped');
      expect(guesses.first.solid, isTrue);
      expect(guesses.first.reason, contains('Standflächen'));
    });

    test('Vierbeiner', () {
      expect(_quadruped().best, 'quadruped');
    });

    test('Fahrzeug gewinnt gegen Vierbeiner, obwohl beide vier Punkte '
        'am Boden haben', () {
      final guesses = _car().guesses;
      expect(guesses.first.type, 'vehicle');
      expect(guesses.map((g) => g.type), isNot(contains('quadruped')));
    });

    test('Insekt', () {
      expect(_insect().best, 'insect');
    });

    test('Vogel: zwei Beine, aber ein waagerechter Rumpf', () {
      // Der schwierige Fall – ein Mensch in T-Pose hat ebenfalls zwei
      // Beine und weit abstehende Arme. Getrennt wird am Rumpf.
      expect(_bird().best, 'bird');
      expect(_bird().guesses.first.reason, contains('waagerechter Rumpf'));
      expect(_biped().shape.bodyProportion, lessThan(1));
      expect(_bird().shape.bodyProportion, greaterThan(1));
    });

    test('Schlange und Fisch', () {
      expect(_snake().best, 'snake');
      expect(_fish().best, 'fish');
    });

    test('Ein Haus ergibt keinen Vorschlag', () {
      final klotz = _building();
      expect(klotz.guesses, isEmpty);
      expect(rigDetectFallback(klotz.shape), contains('Gebäude'));
    });

    test('Die Rangliste steht nach Zuversicht', () {
      final guesses = _biped().guesses;
      for (var i = 1; i < guesses.length; i++) {
        expect(guesses[i - 1].confidence,
            greaterThanOrEqualTo(guesses[i].confidence));
      }
    });

    test('Eine gedrehte Figur wird als liegend gemessen', () {
      // Wer ein z-up-Modell importiert, bekommt keinen Zweibeiner
      // vorgeschlagen – und das ist richtig: Der Rigger nimmt
      // ebenfalls y = oben an, das Modell muss erst aufgerichtet
      // werden.
      final stehend = _biped().positions;
      final liegend = Float32List(stehend.length);
      for (var i = 0; i < stehend.length; i += 3) {
        liegend[i] = stehend[i];
        liegend[i + 1] = stehend[i + 2];
        liegend[i + 2] = stehend[i + 1];
      }
      final guesses = guessRigType(measureRigShape([liegend]));
      expect(guesses.where((g) => g.type == 'biped'), isEmpty);
    });
  });

  test('Alle Vorschläge nennen einen bekannten Typ', () {
    const bekannt = {
      'biped',
      'quadruped',
      'insect',
      'bird',
      'snake',
      'fish',
      'vehicle',
    };
    for (final cloud in [
      _biped(),
      _quadruped(),
      _car(),
      _insect(),
      _snake(),
      _fish(),
      _bird(),
      _building(),
    ]) {
      for (final guess in cloud.guesses) {
        expect(bekannt, contains(guess.type));
        expect(guess.confidence, inInclusiveRange(0.0, 1.0));
        expect(guess.reason, isNotEmpty);
      }
    }
  });
}
