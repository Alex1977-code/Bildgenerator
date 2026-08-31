/// Qualitätsstufen für die Bildgenerierung auf der eigenen GPU.
///
/// Der Bild-Server nahm Schrittzahl und Prompt-Treue schon immer
/// entgegen – die App hat sie nie mitgeschickt, es galt also stets die
/// Vorgabe des Modells. Hier entstehen aus einer Stufe die drei Werte,
/// an denen die Qualität wirklich hängt:
///
/// * **Schritte** – wie oft das Rauschen entfernt wird. Mehr Schritte
///   bringen mehr kleine Struktur, mit klar abnehmendem Ertrag: Von 20
///   auf 30 ist ein Unterschied, von 30 auf 60 kaum noch einer.
/// * **Prompt-Treue** (CFG) – wie streng das Modell dem Text folgt.
///   Zu niedrig wird beliebig, zu hoch verbrannt und überzeichnet.
/// * **Detail-Durchgang** – das fertige Bild wird vergrößert und
///   nochmals mit wenig Stärke durch das Modell geschickt. Das ist der
///   eigentliche Hebel für Detailtreue: Der zweite Durchgang malt in
///   die gewonnene Fläche echte Struktur, statt sie hochzurechnen.
///
/// **Die Werte hängen am Modell, nicht an festen Zahlen.** SDXL Turbo
/// und FLUX schnell sind destillierte Modelle: Sie rechnen mit vier
/// Schritten und ganz ohne Prompt-Treue-Regelung. Wer dort auf 40
/// Schritte und CFG 7 stellt, bekommt kein besseres Bild, sondern ein
/// zermatschtes. Deshalb rechnet diese Datei relativ zur Vorgabe des
/// Modells und deckelt destillierte Modelle gesondert.
library;

/// Die wählbaren Stufen.
enum QualityPreset {
  /// Schnell schauen, ob die Bildidee trägt.
  entwurf,

  /// Die Vorgabe des Modells.
  standard,

  /// Mehr Schritte und ein Detail-Durchgang.
  fein,

  /// Deutlich mehr Schritte, größerer Detail-Durchgang.
  sehrFein,
}

/// Was der Server für einen Lauf bekommt.
class QualitySettings {
  const QualitySettings({
    required this.steps,
    required this.guidance,
    required this.detail,
    required this.detailScale,
  });

  /// Zahl der Rechenschritte.
  final int steps;

  /// Prompt-Treue (CFG). 0 = das Modell kennt keine.
  final double guidance;

  /// Stärke des zweiten Durchgangs, 0 = keiner. Über etwa 0,5 erfindet
  /// der zweite Durchgang das Motiv neu, statt es zu schärfen.
  final double detail;

  /// Um wie viel das Bild für den zweiten Durchgang vergrößert wird.
  final double detailScale;

  bool get hasDetailPass => detail > 0 && detailScale > 1;
}

/// Beschriftung und Erklärung einer Stufe.
(String, String) qualityLabel(QualityPreset preset) => switch (preset) {
      QualityPreset.entwurf => (
          'Entwurf',
          'Weniger Schritte – schnell sehen, ob die Bildidee trägt.'
        ),
      QualityPreset.standard => (
          'Standard',
          'Die Vorgabe des Modells. Guter Kompromiss aus Zeit und '
              'Ergebnis.'
        ),
      QualityPreset.fein => (
          'Fein',
          'Mehr Schritte und ein Detail-Durchgang: Das Bild wird '
              'vergrößert und nochmals leicht überarbeitet. Dauert '
              'ungefähr doppelt so lange.'
        ),
      QualityPreset.sehrFein => (
          'Sehr fein',
          'Deutlich mehr Schritte und ein kräftigerer '
              'Detail-Durchgang auf anderthalbfacher Größe. Braucht '
              'Zeit und Grafikspeicher.'
        ),
    };

/// Vorgaben der Modelle des eigenen Bild-Servers: (Schritte,
/// Prompt-Treue, kann Detail-Durchgang).
///
/// Dieselben Zahlen stehen in `server/local_image_server.py` in
/// `MODELS`. Der Server meldet sie unter `/health` auch selbst; diese
/// Tabelle greift, solange noch keine Antwort da ist – die Regler
/// sollen stehen, bevor der Server das erste Mal antwortet.
const localModelDefaults = <String, (int, double, bool)>{
  'sd15': (25, 7.5, true),
  'sdxl-turbo': (4, 0.0, true),
  'sdxl': (30, 7.0, true),
  // SD 3.5 und FLUX rechnen nach einem anderen Verfahren (Flow
  // Matching); der Detail-Durchgang gilt dort nicht.
  'sd35-medium': (28, 4.5, false),
  'sd35-medium-lean': (28, 4.5, false),
  'flux-schnell': (4, 0.0, false),
};

/// Die Vorgaben zu einem Modell – unbekannte Modelle bekommen die
/// üblichen 30 Schritte bei Prompt-Treue 7.
(int, double, bool) localModelDefault(String model) =>
    localModelDefaults[model] ?? (30, 7.0, true);

/// Höchste sinnvolle Schrittzahl für ein destilliertes Modell.
///
/// SDXL Turbo und FLUX schnell sind darauf trainiert, in wenigen
/// Schritten fertig zu sein. Mehr Schritte machen das Bild nicht
/// besser, sondern weichgespült.
const distilledStepCap = 12;

/// Höchste Schrittzahl überhaupt – darüber kostet es nur noch Zeit.
const maxSteps = 60;

/// Rechnet eine Stufe in Server-Werte um.
///
/// [modelSteps] und [modelGuidance] sind die Vorgaben des Modells, wie
/// sie der Server unter `/health` meldet. [supportsDetail] ist falsch,
/// wenn das Modell keinen zweiten Durchgang kann.
QualitySettings qualityFor({
  required QualityPreset preset,
  required int modelSteps,
  required double modelGuidance,
  bool supportsDetail = true,
}) {
  final distilled = modelGuidance <= 0;
  final base = modelSteps > 0 ? modelSteps : 30;
  final (factor, detail, scale) = switch (preset) {
    QualityPreset.entwurf => (0.6, 0.0, 1.0),
    QualityPreset.standard => (1.0, 0.0, 1.0),
    QualityPreset.fein => (1.4, 0.35, 1.25),
    QualityPreset.sehrFein => (1.8, 0.42, 1.5),
  };
  var steps = (base * factor).round();
  if (steps < 1) steps = 1;
  final cap = distilled ? distilledStepCap : maxSteps;
  if (steps > cap) steps = cap;
  return QualitySettings(
    steps: steps,
    guidance: modelGuidance,
    detail: supportsDetail ? detail : 0,
    detailScale: supportsDetail ? scale : 1,
  );
}

/// Warnt vor Werten, die erfahrungsgemäß schaden – für den Hinweis
/// unter den Reglern. Leer, wenn nichts dagegen spricht.
String qualityWarning({
  required int steps,
  required double guidance,
  required double modelGuidance,
}) {
  if (modelGuidance <= 0) {
    if (steps > distilledStepCap) {
      return 'Dieses Modell ist auf wenige Schritte trainiert. Über '
          '$distilledStepCap Schritten wird das Bild weicher, nicht '
          'besser.';
    }
    return '';
  }
  if (guidance >= 12) {
    return 'Hohe Prompt-Treue überzeichnet: harte Kanten, verbrannte '
        'Farben. Über 12 wird es selten besser.';
  }
  if (guidance > 0 && guidance <= 2) {
    return 'Bei so niedriger Prompt-Treue ignoriert das Modell große '
        'Teile der Beschreibung.';
  }
  if (steps > 45) {
    return 'Über etwa 40 Schritten ändert sich kaum noch etwas – die '
        'Zeit steckt besser in einem Detail-Durchgang.';
  }
  return '';
}
