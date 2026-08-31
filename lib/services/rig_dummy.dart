/// Der Dummy neben dem Rig-Editor: eine gezeichnete Figur des
/// gewählten Typs, an der zu sehen ist, wohin die Gelenkpunkte gehören
/// und wie weit ihr Einflussbereich reichen soll.
///
/// **Warum das nötig ist.** „Schulter" ist keine eindeutige Anweisung:
/// Der Punkt gehört ein Stück *innerhalb* der Silhouette, nicht auf
/// den Ärmelrand; das Fußgelenk an den Knöchel, nicht an die
/// Fußspitze. Am Text allein bleibt das Auslegungssache – am Bild
/// nicht.
///
/// Die Maße hier sind dieselben Anteile, die der Auto-Rigger in
/// `auto_rig.dart` verwendet. Der Dummy zeigt also nicht irgendein
/// Ideal, sondern genau das, was die Automatik anstrebt: Wer davon
/// abweicht, sieht, wie weit.
library;

/// Ein Stück Silhouette: eine Strecke mit Dicke (Kapsel) oder – wenn
/// Anfang und Ende zusammenfallen – ein Kreis.
class DummyLimb {
  const DummyLimb(this.x1, this.y1, this.x2, this.y2, this.thickness);

  /// Anfang und Ende, jeweils −0,5 … +0,5 quer und 0 (Boden) … 1
  /// (oben).
  final double x1, y1, x2, y2;

  /// Dicke der Kapsel, als Anteil der Zeichenhöhe.
  final double thickness;
}

/// Ein empfohlener Gelenkpunkt.
class DummyJoint {
  const DummyJoint(this.name, this.x, this.y, this.radius, this.hint);

  /// Name wie im Skelett (`Hips`, `Shoulder_L`, `Wheel1_L` …).
  final String name;

  /// Lage in der Zeichnung.
  final double x, y;

  /// Empfohlener Einflussbereich als Radius, Anteil der Zeichenhöhe.
  /// Faustregel: so weit, dass das zugehörige Körperteil hineinpasst,
  /// aber das Nachbarteil nicht.
  final double radius;

  /// Was an diesem Punkt zu beachten ist – ein halber Satz, der die
  /// Zeichnung ergänzt.
  final String hint;
}

/// Ein Dummy zu einem Figurtyp.
class RigDummy {
  const RigDummy({
    required this.type,
    required this.label,
    required this.view,
    required this.note,
    required this.limbs,
    required this.joints,
  });

  final String type;

  /// „Zweibeiner", „Vierbeiner" …
  final String label;

  /// Aus welcher Richtung die Zeichnung gesehen ist.
  final String view;

  /// Die eine Regel, an der bei diesem Typ das meiste hängt.
  final String note;

  final List<DummyLimb> limbs;
  final List<DummyJoint> joints;
}

/// Name auf seine Grundform bringen: Nummern raus, Seite getrennt.
/// `Leg2Hip_R` → (`LegHip`, `_R`).
(String, String) _canonical(String name) {
  var base = name;
  var side = '';
  if (base.endsWith('_L') || base.endsWith('_R')) {
    side = base.substring(base.length - 2);
    base = base.substring(0, base.length - 2);
  }
  return (base.replaceAll(RegExp(r'[0-9]+'), '').replaceAll('_', ''), side);
}

/// Sucht zu einem echten Gelenknamen den passenden Punkt im Dummy.
///
/// Erst genau, dann ohne Nummer (ein Insekt hat drei Beinpaare, der
/// Dummy zeigt eines pro Position), zuletzt ohne Seite – bei einer
/// Seitenansicht liegen links und rechts ohnehin übereinander.
DummyJoint? dummyJointFor(RigDummy dummy, String jointName) {
  for (final joint in dummy.joints) {
    if (joint.name == jointName) return joint;
  }
  final (base, side) = _canonical(jointName);
  DummyJoint? sideless;
  for (final joint in dummy.joints) {
    final (otherBase, otherSide) = _canonical(joint.name);
    if (otherBase != base) continue;
    if (otherSide == side) return joint;
    sideless ??= joint;
  }
  return sideless;
}

/// Spiegelt die Punkte einer Seite auf die andere.
List<DummyJoint> _mirrored(List<DummyJoint> left) => [
      for (final j in left)
        if (j.name.endsWith('_L'))
          DummyJoint('${j.name.substring(0, j.name.length - 2)}_R', -j.x,
              j.y, j.radius, j.hint),
    ];

List<DummyLimb> _mirroredLimbs(List<DummyLimb> left) => [
      for (final l in left)
        DummyLimb(-l.x1, l.y1, -l.x2, l.y2, l.thickness),
    ];

/// Zweibeiner von vorn, in T-Pose – so, wie der Rigger die Figur
/// erwartet.
RigDummy _biped() {
  const armLeft = [
    DummyLimb(-0.10, 0.80, -0.46, 0.74, 0.075),
  ];
  const legLeft = [
    DummyLimb(-0.06, 0.50, -0.06, 0.03, 0.095),
  ];
  const jointsLeft = [
    DummyJoint('Shoulder_L', -0.10, 0.80, 0.070,
        'Ein Stück innerhalb der Silhouette, nicht auf dem Ärmelrand.'),
    DummyJoint('Elbow_L', -0.28, 0.77, 0.055,
        'Mitte des ausgestreckten Arms.'),
    DummyJoint('Hand_L', -0.44, 0.74, 0.050,
        'Handwurzel. Bei Fäustlingen in die Handmitte und den '
            'Einflussbereich vergrößern.'),
    DummyJoint('UpperLeg_L', -0.06, 0.48, 0.070,
        'Hüftgelenk, nicht der äußere Rand der Hose.'),
    DummyJoint('Knee_L', -0.06, 0.24, 0.060, 'Kniemitte.'),
    DummyJoint('Foot_L', -0.06, 0.04, 0.050,
        'Knöchel, knapp über der Sohle – nicht die Fußspitze.'),
  ];
  return RigDummy(
    type: 'biped',
    label: 'Zweibeiner',
    view: 'Vorderansicht, T-Pose',
    note: 'Die Kette Hüfte → Wirbelsäule → Brust → Hals → Kopf läuft '
        'mittig **in** der Figur, nicht auf der Bauchdecke. Arme und '
        'Beine sitzen jeweils in der Mitte des Volumens.',
    limbs: [
      const DummyLimb(0, 0.48, 0, 0.84, 0.20), // Rumpf
      const DummyLimb(0, 0.93, 0, 0.93, 0.15), // Kopf
      ...armLeft,
      ..._mirroredLimbs(armLeft),
      ...legLeft,
      ..._mirroredLimbs(legLeft),
    ],
    joints: [
      const DummyJoint('Hips', 0, 0.52, 0.100,
          'Beckenmitte auf Höhe des Hosenbunds – die Wurzel.'),
      const DummyJoint('Spine', 0, 0.63, 0.110, 'Bauchnabelhöhe, mittig.'),
      const DummyJoint('Chest', 0, 0.73, 0.110, 'Brustbeinmitte.'),
      const DummyJoint('Neck', 0, 0.84, 0.070, 'Halsansatz.'),
      const DummyJoint('Head', 0, 0.90, 0.100,
          'Kopfmitte auf Augenhöhe, nicht am Scheitel.'),
      ...jointsLeft,
      ..._mirrored(jointsLeft),
    ],
  );
}

/// Vierbeiner von der Seite; das Gegenbein liegt dahinter.
RigDummy _quadruped() => const RigDummy(
      type: 'quadruped',
      label: 'Vierbeiner',
      view: 'Seitenansicht, Kopf rechts',
      note: 'Die Wirbelsäule läuft waagerecht durch den Rumpf. Vorder- '
          'und Hinterbeine hängen an unterschiedlichen Gliedern: die '
          'vorderen an der Brust, die hinteren am Becken.',
      limbs: [
        DummyLimb(-0.40, 0.60, 0.30, 0.66, 0.26), // Rumpf
        DummyLimb(0.30, 0.66, 0.45, 0.84, 0.12), // Hals
        DummyLimb(0.47, 0.86, 0.47, 0.86, 0.15), // Kopf
        DummyLimb(-0.40, 0.60, -0.50, 0.52, 0.06), // Schwanz
        DummyLimb(0.20, 0.55, 0.20, 0.03, 0.075), // Vorderbein
        DummyLimb(-0.25, 0.55, -0.25, 0.03, 0.085), // Hinterbein
      ],
      joints: [
        DummyJoint('Hips', -0.25, 0.60, 0.110, 'Becken über den '
            'Hinterbeinen.'),
        DummyJoint('Spine', 0, 0.65, 0.120, 'Mitte des Rumpfes.'),
        DummyJoint('Chest', 0.20, 0.65, 0.120, 'Brust über den '
            'Vorderbeinen.'),
        DummyJoint('Neck', 0.35, 0.75, 0.080, 'Halsansatz.'),
        DummyJoint('Head', 0.45, 0.85, 0.110, 'Kopfmitte, etwa auf '
            'Augenhöhe.'),
        DummyJoint('Tail_1', -0.40, 0.60, 0.060, 'Schwanzansatz.'),
        DummyJoint('Tail_2', -0.48, 0.55, 0.050, 'Mitte des Schwanzes.'),
        DummyJoint('FrontUpperLeg_L', 0.20, 0.50, 0.075, 'Schulter des '
            'Vorderbeins, innerhalb des Rumpfes.'),
        DummyJoint('FrontLowerLeg_L', 0.20, 0.25, 0.060, 'Vorderknie.'),
        DummyJoint('FrontFoot_L', 0.20, 0.04, 0.050, 'Fessel knapp über '
            'dem Huf.'),
        DummyJoint('HindUpperLeg_L', -0.25, 0.50, 0.080, 'Hüfte des '
            'Hinterbeins.'),
        DummyJoint('HindLowerLeg_L', -0.25, 0.25, 0.065, 'Sprunggelenk.'),
        DummyJoint('HindFoot_L', -0.25, 0.04, 0.050, 'Fessel knapp über '
            'dem Huf.'),
      ],
    );

/// Insekt von oben – nur so sind alle sechs Beine zu sehen.
RigDummy _insect() {
  const legsLeft = [
    DummyJoint('Leg1Hip_L', -0.07, 0.66, 0.045, 'Ansatz des vorderen '
        'Beinpaars am Brustsegment.'),
    DummyJoint('Leg1Mid_L', -0.20, 0.72, 0.040, 'Knie des vorderen Beins.'),
    DummyJoint('Leg1Foot_L', -0.32, 0.78, 0.035, 'Fußende, am Boden.'),
    DummyJoint('Leg2Hip_L', -0.07, 0.50, 0.045, 'Ansatz des mittleren '
        'Beinpaars.'),
    DummyJoint('Leg2Mid_L', -0.21, 0.50, 0.040, 'Knie des mittleren '
        'Beins.'),
    DummyJoint('Leg2Foot_L', -0.34, 0.50, 0.035, 'Fußende, am Boden.'),
    DummyJoint('Leg3Hip_L', -0.07, 0.34, 0.045, 'Ansatz des hinteren '
        'Beinpaars.'),
    DummyJoint('Leg3Mid_L', -0.20, 0.28, 0.040, 'Knie des hinteren '
        'Beins.'),
    DummyJoint('Leg3Foot_L', -0.32, 0.22, 0.035, 'Fußende, am Boden.'),
  ];
  const limbsLeft = [
    DummyLimb(-0.05, 0.66, -0.32, 0.78, 0.030),
    DummyLimb(-0.05, 0.50, -0.34, 0.50, 0.030),
    DummyLimb(-0.05, 0.34, -0.32, 0.22, 0.030),
  ];
  return RigDummy(
    type: 'insect',
    label: 'Insekt / Mehrbeiner',
    view: 'Draufsicht, Kopf oben',
    note: 'Die drei Beinpaare hängen alle am Brustsegment, nicht am '
        'Hinterleib. Von oben gezeichnet, weil sich die Beine in der '
        'Seitenansicht gegenseitig verdecken.',
    limbs: [
      const DummyLimb(0, 0.36, 0, 0.62, 0.16), // Brust
      const DummyLimb(0, 0.36, 0, 0.14, 0.13), // Hinterleib
      const DummyLimb(0, 0.78, 0, 0.78, 0.11), // Kopf
      ...limbsLeft,
      ..._mirroredLimbs(limbsLeft),
    ],
    joints: [
      const DummyJoint('Thorax', 0, 0.50, 0.100,
          'Mitte des Brustsegments – die Wurzel, alle Beine hängen '
              'daran.'),
      const DummyJoint('Head', 0, 0.72, 0.080, 'Kopfmitte.'),
      const DummyJoint('Abdomen_1', 0, 0.32, 0.090, 'Vorderes Glied des '
          'Hinterleibs.'),
      const DummyJoint('Abdomen_2', 0, 0.20, 0.070, 'Hinteres Glied.'),
      ...legsLeft,
      ..._mirrored(legsLeft),
    ],
  );
}

/// Vogel von vorn – zeigt die Flügelkette und die kurzen Beine.
RigDummy _bird() {
  const wingLeft = [
    DummyJoint('Wing_L', -0.12, 0.62, 0.070, 'Flügelansatz an der '
        'Brust, innerhalb des Körpers.'),
    DummyJoint('WingMid_L', -0.30, 0.62, 0.060, 'Flügelmitte – hier '
        'knickt der Flügel beim Schlagen.'),
  ];
  const legLeft = [
    DummyJoint('Leg_L', -0.07, 0.32, 0.055, 'Beinansatz unter dem '
        'Rumpf.'),
    DummyJoint('Foot_L', -0.07, 0.04, 0.045, 'Fuß knapp über dem '
        'Boden.'),
  ];
  const limbsLeft = [
    DummyLimb(-0.10, 0.62, -0.48, 0.62, 0.070), // Flügel
    DummyLimb(-0.07, 0.36, -0.07, 0.03, 0.045), // Bein
  ];
  return RigDummy(
    type: 'bird',
    label: 'Vogel',
    view: 'Vorderansicht, Flügel gespreizt',
    note: 'Die Flügel brauchen zwei Punkte: Ansatz und Mitte. Nur mit '
        'dem mittleren Gelenk knickt der Flügel beim Schlagen, statt '
        'starr zu kippen.',
    limbs: [
      const DummyLimb(0, 0.36, 0, 0.70, 0.24), // Rumpf
      const DummyLimb(0, 0.82, 0, 0.82, 0.13), // Kopf
      ...limbsLeft,
      ..._mirroredLimbs(limbsLeft),
    ],
    joints: [
      const DummyJoint('Body', 0, 0.50, 0.120,
          'Körpermitte – die Wurzel.'),
      const DummyJoint('Chest', 0, 0.62, 0.110, 'Brust, auf Höhe der '
          'Flügelansätze.'),
      const DummyJoint('Neck', 0, 0.72, 0.070, 'Halsansatz.'),
      const DummyJoint('Head', 0, 0.82, 0.090, 'Kopfmitte.'),
      const DummyJoint('Tail', 0, 0.42, 0.080, 'Schwanzansatz – liegt '
          'in dieser Ansicht hinter dem Rumpf.'),
      ...wingLeft,
      ..._mirrored(wingLeft),
      ...legLeft,
      ..._mirrored(legLeft),
    ],
  );
}

/// Kette aus gleich großen Gliedern (Schlange, Fisch).
RigDummy _chain(String type, String label, int segments, String note,
    List<DummyLimb> extra) {
  final joints = <DummyJoint>[];
  for (var i = 0; i < segments; i++) {
    final t = 0.45 - 0.9 * i / (segments - 1);
    joints.add(DummyJoint(
      i == 0 ? 'Head' : 'Spine_$i',
      t,
      0.5,
      0.075,
      i == 0
          ? 'Kopfmitte am vorderen Ende.'
          : 'Glied $i – gleichmäßig verteilt, mittig im Körper.',
    ));
  }
  return RigDummy(
    type: type,
    label: label,
    view: 'Seitenansicht, Kopf rechts',
    note: note,
    limbs: [
      const DummyLimb(-0.45, 0.5, 0.45, 0.5, 0.20),
      ...extra,
    ],
    joints: joints,
  );
}

/// Fahrzeug von der Seite; das Rad der Gegenseite liegt dahinter.
RigDummy _vehicle() => const RigDummy(
      type: 'vehicle',
      label: 'Fahrzeug',
      view: 'Seitenansicht, Fahrtrichtung rechts',
      note: 'Ein Radpunkt muss genau in der Nabe sitzen – ein paar '
          'Prozent daneben, und das Rad eiert beim Drehen. Der '
          'Einflussbereich reicht bis zum Reifenrand, aber nicht in '
          'die Karosserie.',
      limbs: [
        DummyLimb(-0.38, 0.55, 0.38, 0.55, 0.30), // Karosserie
        DummyLimb(-0.10, 0.75, 0.15, 0.75, 0.18), // Dach
        DummyLimb(0.28, 0.20, 0.28, 0.20, 0.36), // Vorderrad
        DummyLimb(-0.28, 0.20, -0.28, 0.20, 0.36), // Hinterrad
      ],
      joints: [
        DummyJoint('Body', 0, 0.55, 0.180,
            'Fahrzeugmitte auf Höhe der Karosserie – bewegt alles.'),
        DummyJoint('Wheel1_L', 0.28, 0.20, 0.180,
            'Nabe des Vorderrads, genau im Kreismittelpunkt.'),
        DummyJoint('Wheel2_L', -0.28, 0.20, 0.180,
            'Nabe des Hinterrads, genau im Kreismittelpunkt.'),
      ],
    );

/// Der Dummy zu einem Figurtyp – null, wenn es dafür keinen gibt.
RigDummy? rigDummyFor(String rigType) => switch (rigType) {
      'biped' => _biped(),
      'quadruped' => _quadruped(),
      'insect' => _insect(),
      'bird' => _bird(),
      'snake' => _chain(
          'snake',
          'Schlange',
          8,
          'Gleichmäßig verteilte Glieder entlang des Körpers. Sitzen '
              'sie ungleich, knickt die Bewegung an einer Stelle ein '
              'und läuft anderswo tot.',
          const []),
      'fish' => _chain(
          'fish',
          'Fisch',
          6,
          'Die Kette läuft vom Kopf bis zur Schwanzwurzel. Die '
              'Schwanzflosse gehört noch zum letzten Glied – dessen '
              'Einflussbereich also groß genug wählen.',
          const [
            DummyLimb(-0.45, 0.5, -0.32, 0.72, 0.05),
            DummyLimb(-0.45, 0.5, -0.32, 0.28, 0.05),
          ]),
      'vehicle' => _vehicle(),
      _ => null,
    };
