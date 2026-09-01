/// Die beiden Leser für das FBX-Dateiformat – binär und Text.
///
/// Getrennt von `fbx_import.dart`, weil dort gedeutet wird (was ist
/// eine Geometrie, wo steht sie) und hier nur gelesen: Beide Fassungen
/// ergeben denselben Baum aus [FbxNode], und die Deutung steht danach
/// nur einmal da.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'fbx_import.dart' show FbxNode, isAsciiFbx, isBinaryFbx;

/// Liest die Baumstruktur einer FBX-Datei, ohne sie zu deuten.
List<FbxNode> readFbxTree(Uint8List bytes) {
  if (isBinaryFbx(bytes)) return readBinaryFbxTree(bytes);
  if (isAsciiFbx(bytes)) return readAsciiFbxTree(bytes);
  throw Exception('Das ist keine FBX-Datei.');
}

// ----------------------------------------------------------------
// Binaerfassung
// ----------------------------------------------------------------

/// Der Aufbau: Nach dem 27 Byte langen Kopf folgen Datensätze. Jeder
/// nennt seine Endposition, die Zahl seiner Eigenschaften, die Länge
/// des Eigenschaftsblocks und seinen Namen; dahinter stehen die
/// Eigenschaften und danach die Kinder, abgeschlossen durch einen
/// Datensatz aus lauter Nullen.
List<FbxNode> readBinaryFbxTree(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final version = data.getUint32(23, Endian.little);
  // Ab Fassung 7.5 stehen die Längenangaben als 64-Bit-Zahlen.
  final wide = version >= 7500;
  final out = <FbxNode>[];
  var pos = 27;
  var guard = 0;
  while (pos < bytes.length && guard++ < 100000) {
    final node = _readNode(data, bytes, pos, wide);
    if (node == null) break;
    out.add(node.$1);
    if (node.$2 <= pos) break;
    pos = node.$2;
  }
  return out;
}

/// Liest einen Knoten samt Kindern; liefert ihn und die Position
/// dahinter.
(FbxNode, int)? _readNode(
    ByteData data, Uint8List bytes, int pos, bool wide) {
  final size = wide ? 8 : 4;
  if (pos + size * 3 + 1 > bytes.length) return null;
  int readLen(int at) => wide
      ? data.getUint64(at, Endian.little)
      : data.getUint32(at, Endian.little);
  final endOffset = readLen(pos);
  final numProperties = readLen(pos + size);
  final propertyLen = readLen(pos + size * 2);
  final nameLen = data.getUint8(pos + size * 3);
  // Der Null-Datensatz schließt eine Kinderliste ab.
  if (endOffset == 0 && numProperties == 0 && nameLen == 0) return null;
  var cursor = pos + size * 3 + 1;
  if (cursor + nameLen > bytes.length) return null;
  final name = String.fromCharCodes(bytes.sublist(cursor, cursor + nameLen));
  cursor += nameLen;
  final propertyEnd = math.min(cursor + propertyLen, bytes.length);
  final properties = <Object?>[];
  final arrays = <List<num>>[];
  for (var i = 0; i < numProperties && cursor < propertyEnd; i++) {
    final result = _readProperty(data, bytes, cursor);
    if (result == null) break;
    cursor = result.$2;
    final value = result.$1;
    if (value is List<num>) {
      arrays.add(value);
    } else {
      properties.add(value);
    }
  }
  final children = <FbxNode>[];
  final ende = endOffset == 0 ? bytes.length : endOffset;
  var childPos = propertyEnd;
  var guard = 0;
  while (childPos < ende && guard++ < 100000) {
    final child = _readNode(data, bytes, childPos, wide);
    if (child == null) break;
    children.add(child.$1);
    if (child.$2 <= childPos) break;
    childPos = child.$2;
  }
  return (FbxNode(name, properties, children, arrays), ende);
}

/// Liest eine Eigenschaft; liefert Wert und die neue Position.
(Object?, int)? _readProperty(ByteData data, Uint8List bytes, int pos) {
  if (pos >= bytes.length) return null;
  final type = bytes[pos];
  final cursor = pos + 1;
  switch (type) {
    case 0x59: // Y - int16
      return (data.getInt16(cursor, Endian.little), cursor + 2);
    case 0x43: // C - bool
      return (bytes[cursor] != 0, cursor + 1);
    case 0x49: // I - int32
      return (data.getInt32(cursor, Endian.little), cursor + 4);
    case 0x46: // F - float
      return (data.getFloat32(cursor, Endian.little), cursor + 4);
    case 0x44: // D - double
      return (data.getFloat64(cursor, Endian.little), cursor + 8);
    case 0x4C: // L - int64
      return (data.getInt64(cursor, Endian.little), cursor + 8);
    case 0x53: // S - Zeichenkette
    case 0x52: // R - Rohdaten
      if (cursor + 4 > bytes.length) return null;
      final len = data.getUint32(cursor, Endian.little);
      final start = cursor + 4;
      final end = math.min(start + len, bytes.length);
      // In Objektnamen trennt FBX Name und Klasse durch zwei
      // Steuerzeichen (0 und 1); nur der Teil davor ist der Name.
      final text =
          latin1.decode(bytes.sublist(start, end), allowInvalid: true);
      final schnitt = text.indexOf(String.fromCharCode(0));
      return (schnitt < 0 ? text : text.substring(0, schnitt), end);
    case 0x66: // f - float[]
    case 0x64: // d - double[]
    case 0x6C: // l - int64[]
    case 0x69: // i - int32[]
    case 0x62: // b - bool[]
      return _readArray(data, bytes, pos);
    default:
      return null;
  }
}

/// Zahlenfelder stehen roh oder mit zlib gepackt in der Datei
/// (Kodierung 1).
(List<num>, int)? _readArray(ByteData data, Uint8List bytes, int pos) {
  final type = bytes[pos];
  var cursor = pos + 1;
  if (cursor + 12 > bytes.length) return null;
  final length = data.getUint32(cursor, Endian.little);
  final encoding = data.getUint32(cursor + 4, Endian.little);
  final compressed = data.getUint32(cursor + 8, Endian.little);
  cursor += 12;
  final end = math.min(cursor + compressed, bytes.length);
  var payload = bytes.sublist(cursor, end);
  if (encoding == 1) {
    try {
      payload = Uint8List.fromList(const ZLibDecoder().decodeBytes(payload));
    } catch (_) {
      return (const <num>[], end);
    }
  }
  final view = ByteData.sublistView(payload);
  final out = <num>[];
  switch (type) {
    case 0x66:
      for (var i = 0; i < length && i * 4 + 4 <= payload.length; i++) {
        out.add(view.getFloat32(i * 4, Endian.little));
      }
    case 0x64:
      for (var i = 0; i < length && i * 8 + 8 <= payload.length; i++) {
        out.add(view.getFloat64(i * 8, Endian.little));
      }
    case 0x6C:
      for (var i = 0; i < length && i * 8 + 8 <= payload.length; i++) {
        out.add(view.getInt64(i * 8, Endian.little));
      }
    case 0x69:
      for (var i = 0; i < length && i * 4 + 4 <= payload.length; i++) {
        out.add(view.getInt32(i * 4, Endian.little));
      }
    case 0x62:
      for (var i = 0; i < length && i < payload.length; i++) {
        out.add(payload[i]);
      }
  }
  return (out, end);
}

// ----------------------------------------------------------------
// Textfassung
// ----------------------------------------------------------------

/// Derselbe Baum, nur mit geschweiften Klammern statt Längenangaben:
/// `Name: wert, wert { Kind: … }`. Blender schreibt sie nicht mehr,
/// Maya und ältere Werkzeuge schon.
List<FbxNode> readAsciiFbxTree(Uint8List bytes) =>
    _AsciiScanner(latin1.decode(bytes, allowInvalid: true))
        .parseNodes(top: true);

class _AsciiScanner {
  _AsciiScanner(this.text);

  final String text;
  int pos = 0;

  bool get done => pos >= text.length;

  void _skipSpace() {
    while (pos < text.length) {
      final c = text[pos];
      if (c == ';') {
        // Kommentar bis zum Zeilenende.
        while (pos < text.length && text[pos] != '\n') {
          pos++;
        }
      } else if (c == ' ' ||
          c == '\t' ||
          c == '\r' ||
          c == '\n' ||
          c == ',') {
        pos++;
      } else {
        return;
      }
    }
  }

  void _skipInLine() {
    while (pos < text.length && (text[pos] == ' ' || text[pos] == '\t')) {
      pos++;
    }
  }

  List<FbxNode> parseNodes({bool top = false}) {
    final out = <FbxNode>[];
    var guard = 0;
    while (!done && guard++ < 200000) {
      _skipSpace();
      if (done) break;
      if (text[pos] == '}') {
        if (!top) pos++;
        return out;
      }
      final before = pos;
      final node = _parseNode();
      if (node != null && node.name.isNotEmpty) out.add(node);
      if (pos <= before) pos = before + 1;
    }
    return out;
  }

  FbxNode? _parseNode() {
    final start = pos;
    while (pos < text.length &&
        text[pos] != ':' &&
        text[pos] != '\n' &&
        text[pos] != '}') {
      pos++;
    }
    if (pos >= text.length || text[pos] != ':') {
      // Keine gültige Zeile – bis zum Zeilenende überspringen, damit
      // der Leser nicht stehenbleibt.
      while (pos < text.length && text[pos] != '\n') {
        pos++;
      }
      return null;
    }
    final name = text.substring(start, pos).trim();
    pos++;
    final properties = <Object?>[];
    final arrays = <List<num>>[];
    while (pos < text.length) {
      _skipInLine();
      if (pos >= text.length) break;
      final c = text[pos];
      if (c == '{' || c == '\n' || c == '}') break;
      if (c == '*') {
        // Ein Zahlenfeld: *N { a: … }
        pos++;
        while (pos < text.length && text[pos] != '{' && text[pos] != '\n') {
          pos++;
        }
        if (pos < text.length && text[pos] == '{') {
          arrays.add(_readArrayBlock());
        }
        break;
      }
      if (c == '"') {
        pos++;
        final ende = text.indexOf('"', pos);
        if (ende < 0) break;
        final roh = text.substring(pos, ende);
        final schnitt = roh.indexOf(String.fromCharCode(0));
        properties.add(schnitt < 0 ? roh : roh.substring(0, schnitt));
        pos = ende + 1;
      } else {
        final wortStart = pos;
        while (pos < text.length &&
            !',\n{}'.contains(text[pos]) &&
            text[pos] != ' ') {
          pos++;
        }
        final wort = text.substring(wortStart, pos).trim();
        if (wort.isEmpty) {
          pos++;
          continue;
        }
        properties.add(double.tryParse(wort) ?? wort);
      }
      _skipInLine();
      if (pos < text.length && text[pos] == ',') pos++;
    }
    final children = <FbxNode>[];
    _skipSpace();
    if (!done && text[pos] == '{') {
      pos++;
      children.addAll(parseNodes());
    }
    return FbxNode(name, properties, children, arrays);
  }

  /// `{ a: 1,2,3 }` – das Feld selbst.
  List<num> _readArrayBlock() {
    pos++; // Klammer auf
    final ende = text.indexOf('}', pos);
    final block = text.substring(pos, ende < 0 ? text.length : ende);
    pos = ende < 0 ? text.length : ende + 1;
    final werte = <num>[];
    final nachA = block.contains('a:')
        ? block.substring(block.indexOf('a:') + 2)
        : block;
    for (final teil in nachA.split(',')) {
      final zahl = double.tryParse(teil.trim());
      if (zahl != null) werte.add(zahl);
    }
    return werte;
  }
}
