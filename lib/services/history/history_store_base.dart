import 'dart:typed_data';

import '../../models/models.dart';

/// Plattformabhängige Ablage für Verlaufseinträge und Bilddateien.
abstract class HistoryStore {
  Future<List<HistoryEntry>> loadIndex();
  Future<void> saveIndex(List<HistoryEntry> entries);
  Future<void> writeImage(HistoryEntry entry, Uint8List bytes);
  Future<Uint8List?> readImage(HistoryEntry entry);
  Future<void> deleteImage(HistoryEntry entry);
}
