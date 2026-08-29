import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'history/history_store_base.dart';
import 'history/history_store_memory.dart'
    if (dart.library.io) 'history/history_store_io.dart' as store_impl;

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
    notifyListeners();
  }

  /// Speichert die Ergebnisse einer Generierung im Verlauf.
  Future<void> addResults(
      GenerationRequest request, List<GeneratedImage> images,
      {Map<String, String> extraParams = const {}}) async {
    for (final image in images) {
      final id = const Uuid().v4();
      final entry = HistoryEntry(
        id: id,
        prompt: request.prompt,
        providerLabel: request.provider.label,
        createdAt: DateTime.now(),
        params: {...request.describeParams(), ...extraParams},
        format: image.format,
        fileName: '$id.${image.fileExtension}',
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

  Future<Uint8List?> readImage(HistoryEntry entry) async {
    final cached = _cache[entry.id];
    if (cached != null) return cached;
    final bytes = await _store.readImage(entry);
    if (bytes != null) {
      _rememberInCache(entry.id, bytes);
    }
    return bytes;
  }

  Future<void> delete(HistoryEntry entry) async {
    _entries.removeWhere((e) => e.id == entry.id);
    _cache.remove(entry.id);
    await _store.deleteImage(entry);
    try {
      await _store.saveIndex(_entries);
    } catch (_) {}
    notifyListeners();
  }

  void _rememberInCache(String id, Uint8List bytes) {
    _cache[id] = bytes;
    if (_cache.length > 40) {
      _cache.remove(_cache.keys.first);
    }
  }
}
