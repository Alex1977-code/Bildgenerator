import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'history/history_store_base.dart';
import 'history/history_store_memory.dart'
    if (dart.library.io) 'history/history_store_io.dart' as store_impl;
import 'project_tree.dart';

/// Verwaltet den Verlauf generierter Bilder (Galerie).
class HistoryService extends ChangeNotifier {
  HistoryService({HistoryStore? store})
      : _store = store ?? store_impl.createStore(),
        isPersistent = store == null && store_impl.storeIsPersistent;

  final HistoryStore _store;
  final List<HistoryEntry> _entries = [];
  final Map<String, Uint8List> _cache = {};

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// Ob der Verlauf Neustarts übersteht (im Web nur pro Sitzung).
  final bool isPersistent;

  Future<void> init() async {
    try {
      final loaded = await _store.loadIndex();
      _entries
        ..clear()
        ..addAll(loaded);
    } catch (_) {
      // Ohne gespeicherten Verlauf starten.
    }
    await _loadProjects();
    notifyListeners();
  }

  /// Speichert die Ergebnisse einer Generierung im Verlauf.
  ///
  /// [name] ist der im Massenprompt vergebene Name: Unter ihm liegt
  /// die Datei auf der Platte und über ihn ist das Bild in der
  /// Galerie zu finden. Entstehen mehrere Bilder auf einmal, bekommen
  /// sie „-1", „-2" … angehängt.
  ///
  /// [project] ist der Ordner aus dem Projektwähler – das Bild liegt
  /// damit gleich richtig, statt später einsortiert zu werden.
  Future<void> addResults(
      GenerationRequest request, List<GeneratedImage> images,
      {Map<String, String> extraParams = const {},
      String name = '',
      String project = ''}) async {
    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      final id = const Uuid().v4();
      final base = name.trim().isEmpty
          ? id
          : _freeFileBase(images.length == 1
              ? name.trim()
              : '${name.trim()}-${index + 1}');
      final entry = HistoryEntry(
        id: id,
        prompt: request.prompt,
        providerLabel: request.provider.label,
        createdAt: DateTime.now(),
        params: {...request.describeParams(), ...extraParams},
        format: image.format,
        fileName: '$base.${image.fileExtension}',
        name: name.trim().isEmpty ? '' : base,
        project: normalizeProject(project),
      );
      try {
        await _store.writeImage(entry, image.bytes);
        _rememberInCache(id, image.bytes);
        _entries.insert(0, entry);
      } catch (_) {
        // Eintrag konnte nicht gespeichert werden – überspringen.
      }
    }
    try {
      await _store.saveIndex(_entries);
    } catch (_) {}
    notifyListeners();
  }

  /// Speichert ein generiertes 3D-Modell (GLB) samt Vorschaubild im
  /// Verlauf – erscheint in der Galerie neben den Bildern.
  Future<void> addModel({
    required Uint8List glbBytes,
    Uint8List? thumbnail,
    required String label,
    required String providerLabel,
    Map<String, String> params = const {},
    String project = '',
  }) async {
    final id = const Uuid().v4();
    final entry = HistoryEntry(
      id: id,
      prompt: label,
      providerLabel: providerLabel,
      createdAt: DateTime.now(),
      params: params,
      format: 'glb',
      fileName: '$id.glb',
      kind: 'model',
      thumbFileName: thumbnail != null ? '${id}_vorschau.png' : null,
      project: normalizeProject(project),
    );
    try {
      await _store.writeImage(entry, glbBytes);
      if (thumbnail != null) {
        await _store.writeImage(_thumbProxy(entry), thumbnail);
      }
      _entries.insert(0, entry);
      await _store.saveIndex(_entries);
      notifyListeners();
    } catch (_) {
      // Verlauf ist optional – Fehler beim Speichern nicht eskalieren.
    }
  }

  /// Hilfs-Eintrag, unter dem das Vorschaubild eines Modells liegt.
  HistoryEntry _thumbProxy(HistoryEntry entry) => HistoryEntry(
        id: '${entry.id}_vorschau',
        prompt: '',
        providerLabel: '',
        createdAt: entry.createdAt,
        params: const {},
        format: 'png',
        fileName: entry.thumbFileName,
      );

  /// Vorschaubild eines Modell-Eintrags (oder null).
  Future<Uint8List?> readThumbnail(HistoryEntry entry) async {
    if (entry.thumbFileName == null) return null;
    final cached = _cache['${entry.id}_vorschau'];
    if (cached != null) return cached;
    final bytes = await _store.readImage(_thumbProxy(entry));
    if (bytes != null) _rememberInCache('${entry.id}_vorschau', bytes);
    return bytes;
  }

  Future<Uint8List?> readImage(HistoryEntry entry) async {
    final cached = _cache[entry.id];
    if (cached != null) return cached;
    final bytes = await _store.readImage(entry);
    if (bytes != null) {
      _rememberInCache(entry.id, bytes);
    }
    return bytes;
  }

  /// Alle vergebenen Projektpfade – Grundlage für den Ordnerbaum.
  List<String> get projectPaths =>
      [for (final entry in _entries) entry.project];

  /// Angelegte, aber (noch) leere Projekte.
  ///
  /// Der Ordnerbaum entsteht sonst allein aus den Pfaden der Einträge –
  /// ein frisch angelegtes Projekt wäre damit unsichtbar, bis das
  /// erste Bild darin landet. Man legt einen Ordner an, und nichts
  /// passiert. Deshalb werden angelegte Ordner eigens gemerkt.
  Set<String> get emptyProjects {
    final belegt = <String>{
      for (final entry in _entries)
        for (final level in projectTrail(entry.project)) level,
    };
    return {
      for (final path in _projects)
        if (!belegt.contains(path)) path,
    };
  }

  final Set<String> _projects = {};

  /// Legt ein Projekt an, ohne etwas hineinzulegen.
  Future<void> createProject(String path) async {
    final clean = normalizeProject(path);
    if (clean.isEmpty || !_projects.add(clean)) return;
    await _saveProjects();
    notifyListeners();
  }

  /// Vergisst ein angelegtes Projekt samt seinen Unterordnern –
  /// aufgerufen beim Auflösen und Umbenennen.
  Future<void> _forgetProject(String path, {String? renamedTo}) async {
    final old = normalizeProject(path);
    if (old.isEmpty) return;
    final betroffen = [
      for (final p in _projects)
        if (projectIsInside(p, old)) p,
    ];
    if (betroffen.isEmpty) return;
    for (final p in betroffen) {
      _projects.remove(p);
      if (renamedTo != null) {
        final neu = reparentProject(p, old, renamedTo);
        if (neu.isNotEmpty) _projects.add(neu);
      }
    }
    await _saveProjects();
  }

  Future<void> _saveProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('galerieProjekte', _projects.toList());
    } catch (_) {
      // Ohne Ablage gilt die Liste für diese Sitzung.
    }
  }

  Future<void> _loadProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _projects
        ..clear()
        ..addAll(prefs.getStringList('galerieProjekte') ?? const []);
    } catch (_) {
      // Beim Test ohne Ablage bleibt die Liste leer.
    }
  }

  /// Einträge in ein Projekt verschieben (leerer Pfad = wieder heraus).
  ///
  /// Verschoben wird nur der Pfad im Eintrag; die Dateien bleiben, wo
  /// sie liegen. Ein falsch einsortiertes Bild ist damit ein Klick
  /// zurück, ohne dass etwas kopiert oder verloren gehen kann.
  Future<void> moveToProject(
      Iterable<HistoryEntry> entries, String project) async {
    final target = normalizeProject(project);
    final ids = {for (final entry in entries) entry.id};
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      if (ids.contains(_entries[i].id) && _entries[i].project != target) {
        _entries[i] = _entries[i].withProject(target);
        changed = true;
      }
    }
    if (changed) await _persistIndex();
  }

  /// Einen Ordner samt Unterordnern umbenennen oder verschieben.
  /// Leeres [replacement] holt alles auf die oberste Ebene.
  Future<void> renameProject(String from, String replacement) async {
    final old = normalizeProject(from);
    if (old.isEmpty) return;
    await _forgetProject(old, renamedTo: normalizeProject(replacement));
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      final path = _entries[i].project;
      final moved = reparentProject(path, old, replacement);
      if (moved != path) {
        _entries[i] = _entries[i].withProject(moved);
        changed = true;
      }
    }
    if (changed) {
      await _persistIndex();
    } else {
      // Auch ein leerer Ordner soll den neuen Namen tragen.
      notifyListeners();
    }
  }

  /// Einen Ordner auflösen: Die Einträge bleiben, sie liegen danach
  /// eine Ebene höher. Löschen tut dieser Weg nichts – dafür ist
  /// [delete] da, und das soll man nicht versehentlich auslösen, wenn
  /// man nur aufräumen wollte.
  Future<void> dissolveProject(String path) =>
      renameProject(path, parentProject(path));

  Future<void> _persistIndex() async {
    try {
      await _store.saveIndex(_entries);
    } catch (_) {
      // Ohne Persistenz gilt die Änderung für diese Sitzung.
    }
    notifyListeners();
  }

  Future<void> delete(HistoryEntry entry) async {
    _entries.removeWhere((e) => e.id == entry.id);
    _cache.remove(entry.id);
    _cache.remove('${entry.id}_vorschau');
    await _store.deleteImage(entry);
    if (entry.thumbFileName != null) {
      await _store.deleteImage(_thumbProxy(entry));
    }
    try {
      await _store.saveIndex(_entries);
    } catch (_) {}
    notifyListeners();
  }

  /// Sorgt dafür, dass ein Name nicht zweimal vergeben wird – sonst
  /// überschriebe ein späterer Lauf die Bilder eines früheren.
  String _freeFileBase(String wish) {
    final taken = {
      for (final entry in _entries)
        if (entry.name.isNotEmpty) entry.name.toLowerCase(),
    };
    if (!taken.contains(wish.toLowerCase())) return wish;
    for (var suffix = 2; suffix < 1000; suffix++) {
      final candidate = '$wish-$suffix';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }
    return '$wish-${DateTime.now().millisecondsSinceEpoch}';
  }

  void _rememberInCache(String id, Uint8List bytes) {
    _cache[id] = bytes;
    if (_cache.length > 40) {
      _cache.remove(_cache.keys.first);
    }
  }
}
