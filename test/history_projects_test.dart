import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/history/history_store_base.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/project_tree.dart';

HistoryEntry _entry(String id, {String project = ''}) => HistoryEntry(
      id: id,
      prompt: 'Prompt $id',
      providerLabel: 'Test',
      createdAt: DateTime(2026, 1, 1),
      params: const {},
      format: 'png',
      fileName: '$id.png',
      name: id,
      project: project,
    );

/// Ablage, die zählt, wie oft der Verlauf geschrieben wurde – so lässt
/// sich prüfen, dass eine Verschiebung ohne Änderung nichts schreibt.
class _CountingStore extends MemoryHistoryStore {
  int saves = 0;

  @override
  Future<void> saveIndex(List<HistoryEntry> entries) {
    saves++;
    return super.saveIndex(entries);
  }
}

Future<HistoryService> _serviceWith(
  List<HistoryEntry> entries, {
  HistoryStore? store,
}) async {
  final backing = store ?? MemoryHistoryStore();
  await backing.saveIndex(entries);
  final service = HistoryService(store: backing);
  await service.init();
  return service;
}

void main() {
  test('Ein nachbearbeitetes Modell ersetzt seine Datei in der Galerie',
      () async {
    // Der Fund hinter „3D-Viewer aus dem 3D-Bereich und Galerie-Ansicht
    // zeigen bei gleicher Figur Verschiedenes": Der 3D-Bereich richtet
    // nach dem Lauf her, repariert und riggt weiter; die Galerie behielt
    // die Fassung, die der Anbieter geliefert hat. Dieselbe Figur stand
    // dort mit 16.352 Dreiecken in I-Pose, hier mit 7.117 und
    // abgespreizten Armen - und der Download dort lieferte eine andere
    // Datei als der Export hier.
    final service = HistoryService(store: MemoryHistoryStore());
    await service.init();
    final id = await service.addModel(
      glbBytes: Uint8List.fromList([1, 2, 3]),
      label: 'Figur',
      providerLabel: 'Test',
      params: const {'Texturiert': 'ja'},
    );
    expect(id, isNotNull, reason: 'addModel gibt die Kennung zurück.');

    final ersetzt = await service.replaceModel(
        id!, Uint8List.fromList([9, 9, 9, 9]), {'Nachbearbeitet': 'Reparatur'});
    expect(ersetzt, isTrue);
    final entry = service.entries.single;
    // Kennung, Platz und Name bleiben – es ist derselbe Eintrag.
    expect(entry.id, id);
    expect(entry.params['Texturiert'], 'ja');
    expect(entry.params['Nachbearbeitet'], 'Reparatur');
    expect(await service.readImage(entry), [9, 9, 9, 9]);
  });

  test('Ohne passenden Eintrag wird nichts ersetzt', () async {
    final service = HistoryService(store: MemoryHistoryStore());
    await service.init();
    expect(await service.replaceModel('gibtesnicht', Uint8List(1), const {}),
        isFalse);
  });

  test('Einträge wandern in ein Projekt und wieder heraus', () async {
    final service = await _serviceWith([_entry('a'), _entry('b')]);
    await service.moveToProject([service.entries.first], 'Burgenspiel/Türme');
    expect(service.entries.first.project, 'Burgenspiel/Türme');
    expect(service.entries.last.project, isEmpty);

    await service.moveToProject([service.entries.first], '');
    expect(service.entries.first.project, isEmpty);
  });

  test('Der Pfad wird beim Verschieben aufgeräumt', () async {
    final service = await _serviceWith([_entry('a')]);
    await service.moveToProject(service.entries, ' Spiel // Figuren ');
    expect(service.entries.single.project, 'Spiel/Figuren');
  });

  test('Umbenennen nimmt die Unterordner mit', () async {
    final service = await _serviceWith([
      _entry('a', project: 'Spiel/Gebäude/Türme'),
      _entry('b', project: 'Spiel/Figuren'),
      _entry('c', project: 'Anderes'),
    ]);
    await service.renameProject('Spiel', 'Burgenspiel');
    expect(
      service.projectPaths,
      ['Burgenspiel/Gebäude/Türme', 'Burgenspiel/Figuren', 'Anderes'],
    );
  });

  test('Ein Ordner mit ähnlichem Namen bleibt unberührt', () async {
    final service = await _serviceWith([
      _entry('a', project: 'Burg/Turm'),
      _entry('b', project: 'Burgenspiel/Turm'),
    ]);
    await service.renameProject('Burg', 'Festung');
    expect(service.projectPaths, ['Festung/Turm', 'Burgenspiel/Turm']);
  });

  test('Auflösen hebt den Inhalt eine Ebene höher, löscht aber nichts',
      () async {
    final service = await _serviceWith([
      _entry('a', project: 'Spiel/Gebäude/Türme'),
      _entry('b', project: 'Spiel/Gebäude'),
    ]);
    await service.dissolveProject('Spiel/Gebäude');
    expect(service.entries.length, 2);
    expect(service.projectPaths, ['Spiel/Türme', 'Spiel']);
  });

  test('Auflösen auf der obersten Ebene sortiert wieder aus', () async {
    final service = await _serviceWith([_entry('a', project: 'Spiel/Türme')]);
    await service.dissolveProject('Spiel');
    expect(service.entries.single.project, 'Türme');
  });

  test('Die Einsortierung übersteht einen Neustart', () async {
    final store = MemoryHistoryStore();
    final service = await _serviceWith([_entry('a')], store: store);
    await service.moveToProject(service.entries, 'Spiel/Figuren');

    // Zweite Sitzung auf derselben Ablage.
    final wieder = HistoryService(store: store);
    await wieder.init();
    expect(wieder.entries.single.project, 'Spiel/Figuren');
  });

  test('Eine Verschiebung ohne Wirkung schreibt den Verlauf nicht neu',
      () async {
    final store = _CountingStore();
    final service =
        await _serviceWith([_entry('a', project: 'Spiel')], store: store);
    final vorher = store.saves;
    await service.moveToProject(service.entries, 'Spiel');
    expect(store.saves, vorher);
    await service.renameProject('Gibtsnicht', 'Egal');
    expect(store.saves, vorher);
  });

  group('Leere Projekte', () {
    test('Ein angelegtes Projekt ist da, bevor etwas darin liegt',
        () async {
      // Sonst legt man einen Ordner an und nichts passiert – der Baum
      // entsteht ja aus den Pfaden der Einträge.
      final service = await _serviceWith([_entry('a')]);
      await service.createProject('Burgenspiel/Türme');
      expect(service.emptyProjects, contains('Burgenspiel/Türme'));
      final tree = buildProjectTree(service.projectPaths,
          empty: service.emptyProjects);
      expect(tree.single.name, 'Burgenspiel');
    });

    test('Sobald etwas darin liegt, zählt es normal', () async {
      final service = await _serviceWith([_entry('a')]);
      await service.createProject('Spiel');
      await service.moveToProject(service.entries, 'Spiel');
      // Nicht mehr leer – sonst stünde es doppelt im Baum.
      expect(service.emptyProjects, isEmpty);
    });

    test('Der Pfad wird beim Anlegen aufgeräumt', () async {
      final service = await _serviceWith([]);
      await service.createProject('  Spiel // Figuren ');
      expect(service.emptyProjects, {'Spiel/Figuren'});
      // Zweimal dasselbe legt nichts doppelt an.
      await service.createProject('Spiel/Figuren');
      expect(service.emptyProjects.length, 1);
      // Ein leerer Name legt gar nichts an.
      await service.createProject('  ');
      expect(service.emptyProjects.length, 1);
    });

    test('Umbenennen nimmt auch leere Ordner mit', () async {
      final service = await _serviceWith([]);
      await service.createProject('Burg/Turm');
      await service.renameProject('Burg', 'Festung');
      expect(service.emptyProjects, contains('Festung/Turm'));
      expect(service.emptyProjects, isNot(contains('Burg/Turm')));
    });

    test('Auflösen entfernt den leeren Ordner', () async {
      final service = await _serviceWith([]);
      await service.createProject('Spiel/Weg');
      await service.dissolveProject('Spiel/Weg');
      expect(service.emptyProjects, isNot(contains('Spiel/Weg')));
    });
  });

  test('Ein Modell behält beim Verschieben sein Vorschaubild', () async {
    final store = MemoryHistoryStore();
    final service = HistoryService(store: store);
    await service.init();
    await service.addModel(
      glbBytes: Uint8List.fromList([1, 2, 3]),
      thumbnail: Uint8List.fromList([4, 5, 6]),
      label: 'Turm',
      providerLabel: 'Lokal',
    );
    await service.moveToProject(service.entries, 'Spiel');
    final entry = service.entries.single;
    expect(entry.project, 'Spiel');
    expect(await service.readImage(entry), [1, 2, 3]);
    expect(await service.readThumbnail(entry), [4, 5, 6]);
  });
}
