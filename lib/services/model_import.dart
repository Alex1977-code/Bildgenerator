import 'dart:convert';
import 'dart:typed_data';

import 'local_3d.dart' show LocalMesh, buildGlb;

/// Import fremder 3D-Dateien für den Viewer: GLB wird durchgereicht,
/// STL (binär und ASCII) und OBJ (inklusive Vertexfarben) werden über
/// den eigenen glTF-Writer in GLB umgewandelt. Wirft [Exception] mit
/// verständlicher Meldung bei unbekannten Formaten.
Uint8List importModelToGlb(Uint8List bytes, String fileName) {
  if (bytes.length >= 4 &&
      ByteData.sublistView(bytes).getUint32(0, Endian.little) ==
          0x46546C67) {
    return bytes; // bereits GLB
  }
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.stl')) return _stlToGlb(bytes);
  if (lower.endsWith('.obj')) return _objToGlb(bytes);
  if (_looksLikeBinaryStl(bytes) || _looksLikeAsciiStl(bytes)) {
    return _stlToGlb(bytes);
  }
  throw Exception(
      'Nicht unterstütztes Format – bitte GLB-, STL- oder OBJ-Dateien '
      'ablegen.');
}

bool _looksLikeBinaryStl(Uint8List bytes) {
  if (bytes.length < 84) return false;
  final count =
      ByteData.sublistView(bytes).getUint32(80, Endian.little);
  return 84 + count * 50 == bytes.length && count > 0;
}

bool _looksLikeAsciiStl(Uint8List bytes) {
  final head = String.fromCharCodes(
      bytes.sublist(0, bytes.length < 512 ? bytes.length : 512));
  return head.trimLeft().startsWith('solid') && head.contains('facet');
}

Uint8List _stlToGlb(Uint8List bytes) {
  final mesh = LocalMesh();
  if (_looksLikeBinaryStl(bytes)) {
    final data = ByteData.sublistView(bytes);
    final count = data.getUint32(80, Endian.little);
    var o = 84;
    for (var t = 0; t < count; t++) {
      o += 12; // Normale überspringen
      final ids = <int>[];
      for (var v = 0; v < 3; v++) {
        ids.add(mesh.addVertex(
          data.getFloat32(o, Endian.little),
          data.getFloat32(o + 4, Endian.little),
          data.getFloat32(o + 8, Endian.little),
          0,
          0,
        ));
        o += 12;
      }
      o += 2; // Attribut-Bytes
      mesh.addTriangle(ids[0], ids[1], ids[2]);
    }
  } else {
    // ASCII-STL: „vertex x y z“-Zeilen in Dreiergruppen.
    final pending = <int>[];
    for (final line in const LineSplitter()
        .convert(String.fromCharCodes(bytes))) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('vertex')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      pending.add(mesh.addVertex(
        double.tryParse(parts[1]) ?? 0,
        double.tryParse(parts[2]) ?? 0,
        double.tryParse(parts[3]) ?? 0,
        0,
        0,
      ));
      if (pending.length == 3) {
        mesh.addTriangle(pending[0], pending[1], pending[2]);
        pending.clear();
      }
    }
  }
  if (mesh.indices.isEmpty) {
    throw Exception('Die STL-Datei enthält keine Dreiecke.');
  }
  return buildGlb(mesh);
}

Uint8List _objToGlb(Uint8List bytes) {
  final positions = <double>[];
  final colors = <double>[];
  final faces = <List<int>>[];
  for (final line
      in const LineSplitter().convert(utf8.decode(bytes,
          allowMalformed: true))) {
    final trimmed = line.trim();
    if (trimmed.startsWith('v ')) {
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      positions.addAll([
        double.tryParse(parts[1]) ?? 0,
        double.tryParse(parts[2]) ?? 0,
        double.tryParse(parts[3]) ?? 0,
      ]);
      if (parts.length >= 7) {
        colors.addAll([
          double.tryParse(parts[4]) ?? 0.7,
          double.tryParse(parts[5]) ?? 0.7,
          double.tryParse(parts[6]) ?? 0.7,
        ]);
      }
    } else if (trimmed.startsWith('f ')) {
      final vertexCount = positions.length ~/ 3;
      final refs = <int>[];
      for (final part in trimmed.split(RegExp(r'\s+')).skip(1)) {
        final index = int.tryParse(part.split('/').first);
        if (index == null || index == 0) continue;
        // OBJ ist 1-basiert; negative Indizes zählen vom Ende.
        refs.add(index > 0 ? index - 1 : vertexCount + index);
      }
      if (refs.length >= 3) faces.add(refs);
    }
  }
  final vertexCount = positions.length ~/ 3;
  if (vertexCount == 0 || faces.isEmpty) {
    throw Exception('Die OBJ-Datei enthält keine Flächen.');
  }
  final hasColors = colors.length == vertexCount * 3;

  final mesh = LocalMesh();
  for (var v = 0; v < vertexCount; v++) {
    if (hasColors) {
      mesh.addVertex(positions[v * 3], positions[v * 3 + 1],
          positions[v * 3 + 2], 0, 0,
          r: colors[v * 3], g: colors[v * 3 + 1], b: colors[v * 3 + 2]);
    } else {
      mesh.addVertex(positions[v * 3], positions[v * 3 + 1],
          positions[v * 3 + 2], 0, 0);
    }
  }
  for (final face in faces) {
    // Polygone als Fächer triangulieren.
    for (var i = 1; i + 1 < face.length; i++) {
      final a = face[0], b = face[i], c = face[i + 1];
      if (a < vertexCount && b < vertexCount && c < vertexCount) {
        mesh.addTriangle(a, b, c);
      }
    }
  }
  if (mesh.indices.isEmpty) {
    throw Exception('Die OBJ-Datei enthält keine gültigen Flächen.');
  }
  return buildGlb(mesh);
}
