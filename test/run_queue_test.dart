import 'package:bildgenerator/services/run_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// Die Warteschlange: ein Zustand der App, der Tabwechsel und Neustart
/// überlebt – und ehrlich sagt, was ein Neustart mit ihr macht.
void main() {
  RunQueue frisch() => RunQueue(persistent: false);

  test('anstellen, starten, fertig: die Bilanz stimmt an jeder Stelle',
      () {
    final q = frisch();
    final a = q.add(
        name: 'ic3-01-siedler', kind: RunJobKind.image, provider: 'Nano Banana');
    final b = q.add(
        name: 'ic3-02-erz', kind: RunJobKind.image, provider: 'Nano Banana');
    expect(q.openCount, 2);
    expect(q.summary, '2 warten');

    q.start(a.id);
    expect(q.summary, '1 läuft · 1 wartet');
    expect(a.elapsed, isNotNull);

    q.finish(a.id, costUsd: 0.039);
    expect(a.state, RunJobState.done);
    expect(a.costUsd, closeTo(0.039, 1e-9));
    expect(q.openCount, 1);

    q.fail(b.id, 'Schlüssel abgelaufen');
    expect(q.summary, '');
    expect(q.openCount, 0);
    expect(b.note, 'Schlüssel abgelaufen');
  });

  test('Abbrechen nimmt das Wartende heraus, das Laufende endet selbst',
      () {
    final q = frisch();
    final a = q.add(name: 'a', kind: RunJobKind.image, provider: 'x');
    final b = q.add(name: 'b', kind: RunJobKind.image, provider: 'x');
    q.start(a.id);
    q.requestCancel();
    expect(q.cancelRequested, isTrue);
    expect(a.state, RunJobState.running);
    expect(b.state, RunJobState.cancelled);
    // Der Lauf sieht die Bitte und räumt sie beim nächsten Start weg.
    q.clearCancelRequest();
    expect(q.cancelRequested, isFalse);
  });

  test('nach dem Neustart ist Offenes unterbrochen, nicht verschwunden',
      () {
    final q = frisch();
    final a = q.add(name: 'a', kind: RunJobKind.image, provider: 'x');
    final b = q.add(name: 'b', kind: RunJobKind.image, provider: 'x');
    final c = q.add(name: 'c', kind: RunJobKind.model, provider: 'Tripo3D');
    q.start(a.id);
    q.finish(a.id);
    q.start(b.id);
    final gespeichert = q.encode();

    final neu = frisch()..loadFrom(gespeichert);
    expect(neu.jobs.length, 3);
    expect(neu.jobs[0].state, RunJobState.done);
    // b lief, c wartete – beides hat die App nicht weitergerechnet.
    expect(neu.jobs[1].state, RunJobState.cancelled);
    expect(neu.jobs[1].note, RunQueue.interruptedNote);
    expect(neu.jobs[2].state, RunJobState.cancelled);
    expect(neu.interrupted.map((j) => j.name), ['b', 'c']);
    expect(neu.openCount, 0);
    // Der Name des 3D-Auftrags bleibt erhalten, damit der Nutzer weiß,
    // was fehlt.
    expect(neu.jobs[2].kind, RunJobKind.model);
    expect(neu.jobs[2].provider, 'Tripo3D');
    expect(c.id, neu.jobs[2].id);
  });

  test('ein kaputter Speicherstand macht nichts kaputt', () {
    final q = frisch()..loadFrom('{nicht: json');
    expect(q.jobs, isEmpty);
    final r = frisch()..loadFrom('[{"id": 1}]');
    expect(r.jobs, isEmpty);
  });

  test('die Liste bleibt überschaubar', () {
    final q = frisch();
    for (var i = 0; i < 80; i++) {
      final j = q.add(name: 'n$i', kind: RunJobKind.image, provider: 'x');
      q.start(j.id);
      q.finish(j.id);
    }
    expect(q.jobs.length, lessThanOrEqualTo(60));
    // Das Neueste bleibt.
    expect(q.jobs.last.name, 'n79');
  });

  test('Verlauf leeren lässt Offenes stehen', () {
    final q = frisch();
    final a = q.add(name: 'a', kind: RunJobKind.image, provider: 'x');
    final b = q.add(name: 'b', kind: RunJobKind.image, provider: 'x');
    q.start(a.id);
    q.finish(a.id);
    q.clearFinished();
    expect(q.jobs.map((j) => j.id), [b.id]);
  });
}
