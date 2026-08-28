import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../models/models.dart';
import 'history_store_base.dart';

/// Dateibasierte Ablage im Dokumente-Verzeichnis der App
/// (Windows, Android, iOS).
class IoHistoryStore implements HistoryStore {
  Directory? _cachedDir;

  Future<Directory> _dir() async {
    final cached = _cachedDir;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}bildgenerator');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _cachedDir = dir;
  }

  Future<File> _indexFile() async {
    final dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}history.json');
  }

  Future<File> _imageFile(HistoryEntry entry) async {
    final dir = await _dir();
    final name = entry.fileName ?? '${entry.id}.${entry.fileExtension}';
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<List<HistoryEntry>> loadIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return [];
      return HistoryEntry.decodeList(await file.readAsString());
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveIndex(List<HistoryEntry> entries) async {
    final file = await _indexFile();
    await file.writeAsString(HistoryEntry.encodeList(entries));
  }

  @override
  Future<void> writeImage(HistoryEntry entry, Uint8List bytes) async {
    final file = await _imageFile(entry);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<Uint8List?> readImage(HistoryEntry entry) async {
    try {
      final file = await _imageFile(entry);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteImage(HistoryEntry entry) async {
    try {
      final file = await _imageFile(entry);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Datei ließ sich nicht löschen – Eintrag wird trotzdem entfernt.
    }
  }
}

HistoryStore createStore() => IoHistoryStore();

const bool storeIsPersistent = true;
