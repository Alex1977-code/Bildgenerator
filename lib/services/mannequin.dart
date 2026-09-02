/// Das Mannequin: ein Größenmaßstab in der Vorschau.
///
/// **Wofür.** Ob eine Figur 3 oder 7 Studs hoch ist, sieht man ihr im
/// Viewer nicht an – dort füllt jedes Modell das Fenster. Erst neben
/// einem Standard-Avatar wird es sichtbar. Und die Größe ist keine
/// Kleinigkeit: Eine Figur mit 1,20 Einheiten kam in Roblox kniehoch
/// an, und niemand hat es vor dem Import gemerkt.
///
/// **Woher die Maße kommen – und woher nicht.** Roblox liefert die
/// Mannequins als FBX zum Herunterladen. Diese Datei baut sie
/// **nicht** daraus nach, sondern aus den dokumentierten Proportionen
/// eines R15-Körpers: Gesamthöhe, Kopfanteil, Rumpfanteil, Beinanteil,
/// Schulterbreite. Das genügt für einen Maßstab und hat einen
/// handfesten Vorteil – es funktioniert ohne die Vorlagendateien, die
/// die App nicht mitliefern darf.
///
/// Was es dadurch **nicht** ist: kein Cage, kein Rig, keine Vorlage zum
/// Darüberlegen. Wer die echten Hüllkörper braucht, braucht die
/// offiziellen Dateien. Das steht auch in der Oberfläche.
library;

import 'dart:typed_data';

/// Ein Körpertyp mit seinen Maßen in Studs.
class Mannequin {
  const Mannequin({
    required this.id,
    required this.label,
    required this.studs,
    required this.shoulderStuds,
    required this.depthStuds,
    required this.note,
  });

  final String id;
  final String label;

  /// Gesamthöhe in Studs.
  final double studs;

  /// Schulterbreite (ohne ausgestreckte Arme) in Studs.
  final double shoulderStuds;

  /// Tiefe des Rumpfes in Studs.
  final double depthStuds;

  /// Wofür dieser Typ steht.
  final String note;

  /// Die Höhe in Metern, wenn man einen Stud mit 0,28 m rechnet.
  ///
  /// Nur zum Einordnen: Der Roblox-Importer rechnet **nicht** damit,
  /// er setzt eine Datei-Einheit gleich einem Stud.
  double get meters => studs * 0.28;
}

/// Die drei Körpertypen, zwischen denen man wählt.
///
/// Die Zahlen sind die geläufigen Maße der jeweiligen Bauart, nicht
/// aus einer Vorlagendatei ausgemessen – siehe Kopf dieser Datei.
const List<Mannequin> mannequins = [
  Mannequin(
    id: 'classic',
    label: 'Classic',
    studs: 5.0,
    shoulderStuds: 2.0,
    depthStuds: 1.0,
    note: 'Der klassische Klotz-Avatar. 5 Studs hoch – das Maß, auf '
        'das die App eine Figur bringt und an dem der '
        'Marktplatz-Validator alle Grenzen misst.',
  ),
  Mannequin(
    id: 'normal',
    label: 'Rthro Normal',
    studs: 5.75,
    shoulderStuds: 2.6,
    depthStuds: 1.4,
    note: 'Die menschlichere Bauart, etwas höher und breiter. '
        'Accessoire-Grenzen sind auf diesen Typ bezogen.',
  ),
  Mannequin(
    id: 'slender',
    label: 'Rthro Slender',
    studs: 6.5,
    shoulderStuds: 2.3,
    depthStuds: 1.3,
    note: 'Die schlanke Bauart, die höchste der drei. Wer für sie '
        'baut, hat bei den anderen beiden Luft.',
  ),
];

/// Der Körpertyp zu einer Kennung – unbekannt heißt Classic, weil das
/// der Bezug der Roblox-Grenzen ist.
Mannequin mannequinById(String? id) {
  for (final m in mannequins) {
    if (m.id == id) return m;
  }
  return mannequins.first;
}

/// Die Umrisslinien eines Mannequins, als Strecken in Studs.
///
/// Kein Netz, sondern ein Drahtgitter: Es soll **hinter** dem Modell
/// stehen und es nicht verdecken. Ein gefüllter Körper an dieser
/// Stelle nähme genau die Sicht weg, für die er da ist.
///
/// Koordinaten: x nach rechts, y nach oben (Füße bei 0), z nach vorn.
List<List<double>> mannequinOutline(Mannequin m) {
  // Die Anteile eines R15-Körpers an der Gesamthöhe. Kopf gut ein
  // Fünftel, Rumpf ein Drittel, Beine der Rest.
  final kopfUnten = m.studs * 0.80;
  final schulter = m.studs * 0.76;
  final huefte = m.studs * 0.45;
  final knie = m.studs * 0.22;

  final halb = m.shoulderStuds / 2;
  final kopfHalb = m.shoulderStuds * 0.28;
  final hueftHalb = halb * 0.82;
  final beinX = halb * 0.42;
  final armX = halb + m.shoulderStuds * 0.16;
  final z = m.depthStuds / 2;

  final linien = <List<double>>[];
  void strecke(double x1, double y1, double z1, double x2, double y2,
      double z2) {
    linien.add([x1, y1, z1, x2, y2, z2]);
  }

  // Kopf als Kasten.
  for (final s in [-1.0, 1.0]) {
    strecke(kopfHalb * s, kopfUnten, z * s, kopfHalb * s, m.studs, z * s);
    strecke(-kopfHalb, kopfUnten, z * s, kopfHalb, kopfUnten, z * s);
    strecke(-kopfHalb, m.studs, z * s, kopfHalb, m.studs, z * s);
  }
  // Hals.
  strecke(0, schulter, 0, 0, kopfUnten, 0);
  // Rumpf.
  for (final s in [-1.0, 1.0]) {
    strecke(halb * s, schulter, z * s, hueftHalb * s, huefte, z * s);
    strecke(-halb, schulter, z * s, halb, schulter, z * s);
    strecke(-hueftHalb, huefte, z * s, hueftHalb, huefte, z * s);
  }
  // Arme, hängend.
  for (final s in [-1.0, 1.0]) {
    strecke(halb * s, schulter, 0, armX * s, huefte, 0);
    strecke(armX * s, huefte, 0, armX * s, huefte - m.studs * 0.16, 0);
  }
  // Beine.
  for (final s in [-1.0, 1.0]) {
    strecke(beinX * s, huefte, 0, beinX * s, knie, 0);
    strecke(beinX * s, knie, 0, beinX * s, 0, 0);
    // Fuß nach vorn.
    strecke(beinX * s, 0, 0, beinX * s, 0, -m.depthStuds * 0.55);
  }
  // Boden: ein Kreuz unter den Füßen, damit die Standfläche sichtbar
  // ist.
  strecke(-halb, 0, 0, halb, 0, 0);
  strecke(0, 0, -z, 0, 0, z);
  return linien;
}

/// Die Umrisse als flaches Feld – so nimmt der Zeichner sie entgegen.
Float32List mannequinSegments(Mannequin m) {
  final linien = mannequinOutline(m);
  final out = Float32List(linien.length * 6);
  for (var i = 0; i < linien.length; i++) {
    out.setRange(i * 6, i * 6 + 6, linien[i]);
  }
  return out;
}

/// Wie ein Modell zum Mannequin steht.
class MannequinComparison {
  const MannequinComparison({
    required this.mannequin,
    required this.modelStuds,
    required this.modelShoulder,
    required this.modelDepth,
  });

  final Mannequin mannequin;

  /// Die gemessene Höhe des Modells in Datei-Einheiten. Der
  /// Roblox-Importer setzt eine Einheit gleich einem Stud – deshalb ist
  /// das zugleich die Höhe in Studs.
  final double modelStuds;

  final double modelShoulder;
  final double modelDepth;

  /// Wie viel größer oder kleiner das Modell ist, als Faktor.
  double get heightRatio =>
      mannequin.studs <= 0 ? 1 : modelStuds / mannequin.studs;

  /// Ein Satz zur Größe.
  String get heightText {
    final prozent = ((heightRatio - 1) * 100).round();
    if (prozent.abs() <= 3) {
      return 'Passt: ${modelStuds.toStringAsFixed(2)} Studs gegen '
          '${mannequin.studs.toStringAsFixed(2)} des '
          '${mannequin.label}-Mannequins.';
    }
    return '${modelStuds.toStringAsFixed(2)} Studs – '
        '${prozent > 0 ? '$prozent % größer' : '${-prozent} % kleiner'} '
        'als das ${mannequin.label}-Mannequin '
        '(${mannequin.studs.toStringAsFixed(2)} Studs). '
        '${prozent < -20 ? 'So klein kommt die Figur kniehoch an.' : ''}'
        '${prozent > 20 ? 'So groß überragt sie jeden Standard-Avatar.' : ''}';
  }
}
