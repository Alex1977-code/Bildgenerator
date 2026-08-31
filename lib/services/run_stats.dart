/// Aus den eigenen Läufen lernen.
///
/// Die App merkt sich zu jedem erzeugten Modell, mit welchen
/// Einstellungen es entstanden ist und wie gut es geworden ist, und
/// leitet daraus Empfehlungen ab: „Bei Gebäuden hat bei dir Tripo mit
/// 1024er Textur bisher am besten abgeschnitten (7 Läufe)."
///
/// **Was das ist und was nicht.** Das hier ist kein neuronales Netz.
/// Bei ein paar Dutzend Läufen wäre eines auch das falsche Werkzeug –
/// es hätte mehr Parameter als du Datenpunkte hast und würde vor allem
/// den Zufall der ersten Versuche auswendig lernen. Gerechnet wird
/// stattdessen ein geschrumpfter Mittelwert je Einstellung
/// (Bayes-Mittel): Ein Wert mit zwei Läufen wird zum Gesamtmittel
/// hingezogen, einer mit zwanzig steht für sich. Genau deshalb steht
/// bei jeder Empfehlung, auf wie vielen Läufen sie beruht – eine
/// Empfehlung aus drei Läufen ist eine Vermutung, eine aus dreißig
/// eine Aussage.
///
/// Die Bewertung kommt aus zwei Quellen: der messbaren Beschaffenheit
/// des Netzes (wasserdicht, einheitliche Wicklung, Dreiecke im
/// Zielbereich, Textur vorhanden, nicht flach) und – wenn du sie
/// abgibst – deiner Note. Beides zusammen, weil das eine ohne das
/// andere in die Irre führt: Ein technisch tadelloses Netz kann das
/// Motiv verfehlen, und ein schönes Modell kann Löcher haben.
library;

import 'dart:convert';

/// Ein abgeschlossener Lauf.
class RunRecord {
  const RunRecord({
    required this.at,
    required this.motif,
    required this.provider,
    required this.settings,
    this.meshScore,
    this.rating,
  });

  /// Zeitpunkt – nur für die Anzeige und fürs Aufräumen alter Läufe.
  final DateTime at;

  /// Motivklasse: 'figur', 'gebaeude', 'fahrzeug', 'objekt'. Die
  /// Empfehlungen werden je Klasse getrennt gerechnet, weil sich die
  /// Anbieter dort unterschiedlich schlagen.
  final String motif;

  /// Anbieter samt Modell, etwa 'tripo/v2.5' oder 'server/sf3d'.
  final String provider;

  /// Die Einstellungen dieses Laufs: Name → Wert, beides als Text.
  /// Was darin steht, entscheidet die Oberfläche; der Dienst rechnet
  /// nur damit.
  final Map<String, String> settings;

  /// Gemessene Beschaffenheit des Netzes, 0–1. Null, wenn nichts
  /// gemessen wurde (abgebrochener Lauf, fremdes Format).
  final double? meshScore;

  /// Deine Note, 1–5. Null, solange du keine abgegeben hast.
  final int? rating;

  /// Gesamtbewertung 0–1, aus Messung und Note. Liegt nur eines vor,
  /// zählt dieses allein; die Note wiegt schwerer, weil sie das Motiv
  /// beurteilt und nicht nur die Technik.
  double? get score {
    final measured = meshScore;
    final judged = rating == null ? null : (rating! - 1) / 4.0;
    if (measured == null) return judged;
    if (judged == null) return measured;
    return 0.35 * measured + 0.65 * judged;
  }

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'motif': motif,
        'provider': provider,
        'settings': settings,
        if (meshScore != null) 'mesh': meshScore,
        if (rating != null) 'rating': rating,
      };

  static RunRecord? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    return RunRecord(
      at: at,
      motif: json['motif'] as String? ?? 'objekt',
      provider: json['provider'] as String? ?? '',
      settings: {
        for (final entry in (json['settings'] as Map? ?? const {}).entries)
          '${entry.key}': '${entry.value}',
      },
      meshScore: (json['mesh'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toInt(),
    );
  }

  RunRecord withRating(int value) => RunRecord(
        at: at,
        motif: motif,
        provider: provider,
        settings: settings,
        meshScore: meshScore,
        rating: value.clamp(1, 5),
      );
}

/// Eine Empfehlung für eine einzelne Einstellung.
class RunAdvice {
  const RunAdvice({
    required this.setting,
    required this.value,
    required this.runs,
    required this.average,
    required this.baseline,
  });

  /// Name der Einstellung, etwa 'textur' oder 'anbieter'.
  final String setting;

  /// Der Wert, der bei dir am besten abgeschnitten hat.
  final String value;

  /// Auf wie vielen Läufen die Aussage beruht.
  final int runs;

  /// Geschrumpfter Mittelwert dieses Werts (0–1) …
  final double average;

  /// … und der aller Läufe dieser Motivklasse, als Vergleich.
  final double baseline;

  /// Wie deutlich der Wert über dem Durchschnitt liegt.
  double get lead => average - baseline;

  /// Wie belastbar die Aussage ist. Unter fünf Läufen bleibt es eine
  /// Vermutung – das steht so auch in der Oberfläche.
  bool get solid => runs >= 5;
}

/// Bewertet ein Netz aus den Zahlen, die die Prüfung ohnehin erhebt.
///
/// Bewusst grob und erklärbar: sechs Punkte, jeder zählt gleich viel.
/// Eine feinere Gewichtung würde Genauigkeit vortäuschen, die aus so
/// wenigen Läufen nicht kommen kann.
double meshQualityScore({
  required int triangles,
  required int targetTriangles,
  required bool watertight,
  required int reversedEdges,
  required int degenerateTriangles,
  required int materials,
  required bool hasTexture,
  required double volumeRatio,
}) {
  var points = 0.0;
  if (watertight) points++;
  if (reversedEdges == 0) points++;
  if (degenerateTriangles == 0) points++;
  if (materials == 1) points++;
  if (hasTexture) points++;
  // Nicht flach: ein Relief oder eine Platte hat fast kein Volumen.
  if (volumeRatio > 0.02) points++;
  // Dreiecke: volle Punktzahl im Zielbereich, darüber und darunter
  // gleitend weniger. Zu wenige sind so gut wie zu viele ein Fehler –
  // nur eben ein anderer.
  if (targetTriangles > 0 && triangles > 0) {
    final ratio = triangles / targetTriangles;
    final off = ratio >= 1 ? ratio - 1 : (1 / ratio) - 1;
    points += (1 - off).clamp(0.0, 1.0);
    return points / 7;
  }
  return points / 6;
}

/// Sammelt die Läufe und rechnet daraus die Empfehlungen.
class RunStats {
  RunStats(this._runs);

  /// Aus dem gespeicherten Text (siehe [encode]).
  factory RunStats.decode(String text) {
    if (text.trim().isEmpty) return RunStats([]);
    try {
      final list = jsonDecode(text);
      if (list is! List) return RunStats([]);
      return RunStats([
        for (final entry in list)
          if (entry is Map<String, dynamic>) ?RunRecord.fromJson(entry),
      ]);
    } catch (_) {
      return RunStats([]);
    }
  }

  final List<RunRecord> _runs;

  List<RunRecord> get runs => List.unmodifiable(_runs);

  /// Wie viele Läufe höchstens aufgehoben werden. Ältere fallen weg –
  /// sie sagen ohnehin wenig über die heutige Fassung der Modelle.
  static const int keep = 400;

  /// Ab wie vielen Läufen einer Motivklasse überhaupt etwas empfohlen
  /// wird. Darunter ist jede Aussage Rauschen.
  static const int minRuns = 4;

  /// Wie oft ein einzelner Wert vorkommen muss, um überhaupt
  /// vorgeschlagen zu werden. Ein einziger guter Lauf ist Glück, kein
  /// Befund – und er soll acht gleichmäßig guten nicht den Rang
  /// ablaufen.
  static const int minValueRuns = 2;

  /// Wie stark kleine Stichproben zum Gesamtmittel gezogen werden.
  /// Drei heißt: Ein Wert mit drei Läufen zählt zur Hälfte für sich,
  /// zur Hälfte für den Durchschnitt.
  static const double shrink = 3;

  void add(RunRecord run) {
    _runs.add(run);
    if (_runs.length > keep) _runs.removeRange(0, _runs.length - keep);
  }

  /// Setzt die Note des jüngsten Laufs (der gerade angesehen wird).
  bool rateLatest(int rating) {
    if (_runs.isEmpty) return false;
    _runs[_runs.length - 1] = _runs.last.withRating(rating);
    return true;
  }

  String encode() => jsonEncode([for (final run in _runs) run.toJson()]);

  /// Alle Läufe einer Motivklasse, die eine Bewertung tragen.
  List<RunRecord> _scored(String motif) => [
        for (final run in _runs)
          if (run.motif == motif && run.score != null) run,
      ];

  /// Was bei dieser Motivklasse bisher am besten funktioniert hat.
  ///
  /// Je Einstellung ein Vorschlag, nach Vorsprung sortiert. Leer,
  /// solange zu wenige Läufe vorliegen – lieber nichts sagen als
  /// raten.
  List<RunAdvice> adviceFor(String motif) {
    final scored = _scored(motif);
    if (scored.length < minRuns) return const [];
    final baseline =
        scored.map((r) => r.score!).reduce((a, b) => a + b) / scored.length;

    // Anbieter zählt als Einstellung mit – meist ist er der Hebel mit
    // dem größten Ausschlag.
    final values = <String, Map<String, List<double>>>{};
    for (final run in scored) {
      for (final entry in {
        'anbieter': run.provider,
        ...run.settings,
      }.entries) {
        if (entry.value.trim().isEmpty) continue;
        values
            .putIfAbsent(entry.key, () => {})
            .putIfAbsent(entry.value, () => [])
            .add(run.score!);
      }
    }

    final advice = <RunAdvice>[];
    for (final setting in values.entries) {
      // Bei nur einem beobachteten Wert gibt es nichts zu vergleichen.
      if (setting.value.length < 2) continue;
      RunAdvice? best;
      for (final option in setting.value.entries) {
        final n = option.value.length;
        if (n < minValueRuns) continue;
        final sum = option.value.reduce((a, b) => a + b);
        final mean = (sum + shrink * baseline) / (n + shrink);
        if (best == null || mean > best.average) {
          best = RunAdvice(
            setting: setting.key,
            value: option.key,
            runs: n,
            average: mean,
            baseline: baseline,
          );
        }
      }
      // Ein Vorsprung unter zwei Prozentpunkten ist kein Unterschied.
      if (best != null && best.lead > 0.02) advice.add(best);
    }
    advice.sort((a, b) => b.lead.compareTo(a.lead));
    return advice;
  }

  /// Kurzfassung für die Oberfläche: ein Satz je Empfehlung.
  List<String> adviceText(String motif) => [
        for (final a in adviceFor(motif))
          '${_label(a.setting)}: „${a.value}" – '
              '${(a.average * 100).round()} statt '
              '${(a.baseline * 100).round()} von 100, '
              '${a.runs} ${a.runs == 1 ? 'Lauf' : 'Läufe'}'
              '${a.solid ? '' : ' (noch wenig, eher ein Hinweis)'}',
      ];

  /// Wie viele Läufe dieser Motivklasse schon bewertet sind – die
  /// Oberfläche zeigt damit, wie weit es bis zur ersten Empfehlung
  /// noch ist.
  int ratedCount(String motif) => _scored(motif).length;

  static String _label(String setting) => switch (setting) {
        'anbieter' => 'Anbieter',
        'textur' => 'Textur-Auflösung',
        'polygonzahl' => 'Polygonzahl',
        'polygonform' => 'Polygonform',
        'symmetrie' => 'Symmetrisieren',
        'schaerfen' => 'Textur schärfen',
        'rigging' => 'Rigging',
        'pose' => 'Pose',
        'art' => 'Gegenstandsart',
        'quelle' => 'Quelle',
        'vorlage' => 'Vorlage',
        _ => setting,
      };
}

/// Gegenstandsarten, die bestiegen werden – sie zählen zur Klasse
/// „fortbewegung".
///
/// Steht hier und nicht in `item_prompt.dart`, damit die Statistik
/// ohne den ganzen Katalog auskommt; ein Test hält beide Listen
/// zusammen.
const rideableItemKinds = <String>{
  'reitpferd',
  'reitvogel',
  'reitechse',
  'karren',
  'auto',
  'boot',
  'gleiter',
};

/// Klartext für eine Motivklasse – für Überschriften und Hinweise.
String motifLabel(String motif) => switch (motif) {
      'figur' => 'Figuren',
      'gebaeude' => 'Gebäude',
      'fahrzeug' => 'Fahrzeuge',
      'gegenstand' => 'Gegenstände',
      'fortbewegung' => 'Reittiere und Fahrzeuge',
      _ => 'Objekte',
    };

/// Ordnet einen Prompt grob einer Motivklasse zu – damit die
/// Empfehlungen nicht Gebäude und Figuren in einen Topf werfen.
///
/// Absichtlich ein Wortvergleich und kein Klassifikator: Die Klassen
/// sind wenige, die Wörter eindeutig, und ein gelerntes Modell hätte
/// hier nichts zu holen.
///
/// [itemKind] ist die Kennung einer Gegenstandsart, wenn der Lauf aus
/// der Gegenstands-Reihe stammt. Ein Schwert ist weder Figur noch
/// Gebäude: Es ist klein, hat keine Gliedmaßen und wird ganz anders
/// gut oder schlecht. In denselben Topf geworfen verwässert es die
/// Empfehlungen für Figuren – deshalb eine eigene Klasse. Reittiere
/// und Fahrzeuge bekommen noch eine eigene: Sie sind Figuren für
/// sich, mit Skelett, aber größer als alles andere.
String motifOf(String prompt, {String? figureType, String? itemKind}) {
  if (itemKind != null && itemKind.trim().isNotEmpty) {
    return rideableItemKinds.contains(itemKind)
        ? 'fortbewegung'
        : 'gegenstand';
  }
  if (figureType != null && figureType.trim().isNotEmpty) return 'figur';
  final text = prompt.toLowerCase();
  bool has(List<String> words) => words.any(text.contains);
  if (has(const [
    'haus',
    'hütte',
    'gebäude',
    'turm',
    'kirche',
    'scheune',
    'bäckerei',
    'schmiede',
    'mühle',
    'stall',
    'wirtshaus',
    'house',
    'building',
    'tower',
    'cottage',
    'forge',
    'bakery',
    'barn',
    'mill',
    'smithy',
    'tavern',
    'inn ',
    'workshop',
  ])) {
    return 'gebaeude';
  }
  if (has(const [
    'auto',
    'wagen',
    'fahrzeug',
    'panzer',
    'karren',
    'schiff',
    'flugzeug',
    'car',
    'vehicle',
    'truck',
    'ship',
    'plane',
  ])) {
    return 'fahrzeug';
  }
  if (has(const [
    'figur',
    'charakter',
    'mensch',
    'krieger',
    'ritter',
    'tier',
    'drache',
    'character',
    'knight',
    'creature',
    'dragon',
  ])) {
    return 'figur';
  }
  return 'objekt';
}

/// Rundet einen Zahlenwert auf wenige Stufen – sonst wäre jede
/// Einstellung einmalig und nichts ließe sich vergleichen.
String bucket(num value, List<num> steps) {
  var best = steps.isEmpty ? value : steps.first;
  var bestGap = double.infinity;
  for (final step in steps) {
    final gap = (value - step).abs().toDouble();
    if (gap < bestGap) {
      bestGap = gap;
      best = step;
    }
  }
  return '${best is int ? best : best.round()}';
}
