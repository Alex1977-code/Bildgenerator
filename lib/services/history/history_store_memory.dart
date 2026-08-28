import 'dart:typed_data';

import '../../models/models.dart';
import 'history_store_base.dart';

/// In-Memory-Ablage für Plattformen ohne Dateisystem (Web).
/// Der Verlauf geht beim Neuladen der Seite verloren.
class MemoryHistoryStore implements HistoryStore {
  final List<HistoryEntry> _index = [];
  final Map<String, Uint8List> _images = {};

  @override
  Future<List<HistoryEntry>> loadIndex() async => List.of(_index);

  @override
  Future<void> saveIndex(List<HistoryEntry> entries) async {
    _index
      ..clear()
      ..addAll(entries);
  }

  @override
  Future<void> writeImage(HistoryEntry entry, Uint8List bytes) async {
    _images[entry.id] = bytes;
  }

  @override
  Future<Uint8List?> readImage(HistoryEntry entry) async => _images[entry.id];

  @override
  Future<void> deleteImage(HistoryEntry entry) async {
    _images.remove(entry.id);
  }
}

HistoryStore createStore() => MemoryHistoryStore();

const bool storeIsPersistent = false;
