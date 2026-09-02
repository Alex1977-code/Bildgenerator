/// Die Warteschlange der Läufe – ein Zustand der App, kein Dialog.
///
/// **Warum es das gibt.** Ein Massenlauf dauert Minuten bis Stunden
/// (im Protokoll: 3 h 24 min). Bisher lebte sein Fortschritt allein
/// im Bild-Tab: Wer in die Galerie wechselte, sah nichts mehr davon,
/// und wer die App schloss, verlor den Stand. Jetzt steht die Schlange
/// neben den Tabs – als „1 Lauf" in der Leiste und auf dem Handy als
/// eigene Seite –, und sie überlebt einen Neustart.
///
/// **Was sie nicht kann, und das steht auch in der Oberfläche:** Die
/// App rechnet nicht weiter, wenn sie geschlossen ist. Ein Lauf hält
/// dann an; die Schlange merkt sich, welche Bilder noch fehlten, und
/// der Bild-Tab bietet beim nächsten Start an, dort weiterzumachen.
/// Ein Entwurf, der „läuft weiter, auch wenn du die App schließt"
/// verspricht, verspricht etwas, das eine Flutter-App ohne
/// Hintergrunddienst nicht halten kann.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RunJobKind { image, model }

enum RunJobState {
  /// Steht an, noch nicht begonnen.
  waiting,

  /// Rechnet gerade.
  running,

  /// Fertig, mit Ergebnis.
  done,

  /// Abgebrochen mit Fehler.
  failed,

  /// Vom Nutzer abgebrochen – oder beim Schließen der App unterbrochen.
  cancelled,
}

class RunJob {
  RunJob({
    required this.id,
    required this.name,
    required this.kind,
    required this.provider,
    this.state = RunJobState.waiting,
    this.startedAt,
    this.finishedAt,
    this.costUsd = 0,
    this.note = '',
  });

  final String id;

  /// Der Name aus dem Massenprompt (oder ein Kurztext des Prompts).
  final String name;
  final RunJobKind kind;

  /// Wer rechnet – „Nano Banana", „Tripo3D".
  final String provider;

  RunJobState state;
  DateTime? startedAt;
  DateTime? finishedAt;

  /// Geschätzte Kosten in Dollar, sobald bekannt.
  double costUsd;

  /// Kurzer Zwischenstand („Rigging 41 %", „unterbrochen").
  String note;

  bool get isOpen =>
      state == RunJobState.waiting || state == RunJobState.running;

  /// Wie lange der Auftrag lief bzw. läuft.
  Duration? get elapsed {
    final start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'provider': provider,
        'state': state.name,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        'costUsd': costUsd,
        'note': note,
      };

  static RunJob? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    return RunJob(
      id: id,
      name: name,
      kind: RunJobKind.values.firstWhere((k) => k.name == json['kind'],
          orElse: () => RunJobKind.image),
      provider: json['provider'] as String? ?? '',
      state: RunJobState.values.firstWhere((s) => s.name == json['state'],
          orElse: () => RunJobState.waiting),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
      costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
      note: json['note'] as String? ?? '',
    );
  }
}

class RunQueue extends ChangeNotifier {
  /// [persistent] = false hält alles im Speicher – für Tests und für
  /// die Web-Version, wo ohnehin nichts über die Sitzung hinaus bleibt.
  RunQueue({this.persistent = true});

  final bool persistent;
  static const _prefsKey = 'run_queue';

  final List<RunJob> _jobs = [];
  int _counter = 0;

  /// Der Nutzer hat „Abbrechen" gedrückt – von der Warteschlangen-Seite
  /// aus, nicht im Bild-Tab. Der laufende Massenlauf sieht die Bitte
  /// bei seinem nächsten Schritt und hört auf.
  bool cancelRequested = false;

  void requestCancel() {
    cancelRequested = true;
    cancelWaiting();
    notifyListeners();
  }

  /// Ein neuer Lauf beginnt: Eine alte Abbruch-Bitte gilt nicht mehr.
  void clearCancelRequest() {
    cancelRequested = false;
  }

  List<RunJob> get jobs => List.unmodifiable(_jobs);

  Iterable<RunJob> get running =>
      _jobs.where((j) => j.state == RunJobState.running);
  Iterable<RunJob> get waiting =>
      _jobs.where((j) => j.state == RunJobState.waiting);
  Iterable<RunJob> get finished =>
      _jobs.where((j) => j.state == RunJobState.done);

  /// Läuft oder wartet etwas? Das ist die Zahl in der Leiste.
  int get openCount => _jobs.where((j) => j.isOpen).length;

  /// Was ein Neustart unterbrochen hat: Aufträge, die beim letzten
  /// Schließen noch offen waren. Sie werden beim Laden als
  /// „unterbrochen" markiert, bleiben aber auffindbar, damit der
  /// Bild-Tab das Weitermachen anbieten kann.
  List<RunJob> get interrupted => [
        for (final job in _jobs)
          if (job.state == RunJobState.cancelled &&
              job.note == interruptedNote)
            job,
      ];

  static const interruptedNote = 'unterbrochen beim Schließen der App';

  /// Kurze Bilanz für Leiste und Kopfzeile: „1 läuft · 2 warten".
  String get summary {
    final r = running.length, w = waiting.length;
    if (r == 0 && w == 0) return '';
    return [
      if (r > 0) '$r läuft',
      if (w > 0) '$w ${w == 1 ? 'wartet' : 'warten'}',
    ].join(' · ');
  }

  Future<void> init() async {
    if (!persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _load(prefs.getString(_prefsKey) ?? '');
    } catch (_) {
      // Ohne Persistenz weiterlaufen.
    }
  }

  /// Liest eine gespeicherte Schlange ein. Was beim Schließen noch
  /// lief oder wartete, ist jetzt unterbrochen – die App hat ja nicht
  /// weitergerechnet.
  void _load(String stored) {
    _jobs.clear();
    if (stored.isEmpty) return;
    try {
      final list = jsonDecode(stored);
      if (list is! List) return;
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final job = RunJob.fromJson(raw);
        if (job == null) continue;
        if (job.isOpen) {
          job.state = RunJobState.cancelled;
          job.note = interruptedNote;
          job.finishedAt ??= DateTime.now();
        }
        _jobs.add(job);
      }
    } catch (_) {
      _jobs.clear();
    }
  }

  /// Nur für Tests: dieselbe Logik wie [init], aus einem String.
  @visibleForTesting
  void loadFrom(String stored) {
    _load(stored);
    notifyListeners();
  }

  String encode() => jsonEncode([for (final job in _jobs) job.toJson()]);

  Future<void> _save() async {
    notifyListeners();
    if (!persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, encode());
    } catch (_) {}
  }

  /// Stellt einen Auftrag an. Er wartet, bis [start] ihn aufruft.
  RunJob add({
    required String name,
    required RunJobKind kind,
    required String provider,
  }) {
    _counter++;
    final job = RunJob(
      id: '${DateTime.now().microsecondsSinceEpoch}-$_counter',
      name: name,
      kind: kind,
      provider: provider,
    );
    _jobs.add(job);
    // Die Liste bleibt überschaubar: Fertiges über 40 Einträge hinaus
    // fällt vorn weg.
    while (_jobs.length > 60) {
      final index = _jobs.indexWhere((j) => !j.isOpen);
      if (index < 0) break;
      _jobs.removeAt(index);
    }
    _save();
    return job;
  }

  RunJob? _find(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  void start(String id) {
    final job = _find(id);
    if (job == null) return;
    job
      ..state = RunJobState.running
      ..startedAt = DateTime.now()
      ..note = '';
    _save();
  }

  void progress(String id, String note) {
    final job = _find(id);
    if (job == null || job.note == note) return;
    job.note = note;
    notifyListeners();
  }

  void finish(String id, {double costUsd = 0}) {
    final job = _find(id);
    if (job == null) return;
    job
      ..state = RunJobState.done
      ..finishedAt = DateTime.now()
      ..costUsd = costUsd
      ..note = '';
    _save();
  }

  void fail(String id, String reason) {
    final job = _find(id);
    if (job == null) return;
    job
      ..state = RunJobState.failed
      ..finishedAt = DateTime.now()
      ..note = reason;
    _save();
  }

  /// Nimmt alles Wartende heraus – beim Abbrechen eines Laufs. Was
  /// gerade rechnet, wird als abgebrochen markiert, sobald es endet.
  void cancelWaiting() {
    var changed = false;
    for (final job in _jobs) {
      if (job.state != RunJobState.waiting) continue;
      job
        ..state = RunJobState.cancelled
        ..finishedAt = DateTime.now()
        ..note = 'abgebrochen';
      changed = true;
    }
    if (changed) _save();
  }

  void cancel(String id) {
    final job = _find(id);
    if (job == null || !job.isOpen) return;
    job
      ..state = RunJobState.cancelled
      ..finishedAt = DateTime.now()
      ..note = 'abgebrochen';
    _save();
  }

  /// Räumt Fertiges, Gescheitertes und Unterbrochenes weg.
  void clearFinished() {
    _jobs.removeWhere((j) => !j.isOpen);
    _save();
  }
}
