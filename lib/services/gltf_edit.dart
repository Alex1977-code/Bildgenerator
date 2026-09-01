/// Kleinwerkzeug zum Ändern einer bereits zerlegten glTF-Datei.
///
/// Wer an einer GLB etwas anhängt – ein neues Attribut, eine zweite
/// Indexliste, ein zerlegtes Netz – muss dreimal dasselbe tun: Bytes
/// hinten an den Puffer, einen `bufferView` darauf, einen `accessor`
/// darauf. Das stand vorher in jeder Datei neu, jedes Mal mit eigenen
/// Ausrichtungsfehlern.
///
/// Hier steht es einmal. Gelesen wird über `glb_preview.dart`; diese
/// Datei ist die Schreibseite.
library;

import 'dart:typed_data';

/// Die Bytes je Komponente eines glTF-Zahlentyps.
int gltfComponentSize(int componentType) => switch (componentType) {
      5120 || 5121 => 1,
      5122 || 5123 => 2,
      _ => 4,
    };

/// Wie viele Komponenten ein Element hat.
int gltfComponentCount(String type) => switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      'MAT4' => 16,
      _ => 1,
    };

/// Sammelt neue Datenblöcke für den Binärteil und legt die passenden
/// `bufferView`- und `accessor`-Einträge an.
///
/// Der Puffer wird dabei **nicht** umgeschrieben: Alles Vorhandene
/// bleibt, wo es ist, und Neues kommt hinten dran. Damit verrutscht
/// kein Accessor, den diese Datei nie gesehen hat.
class GltfAppender {
  GltfAppender(this.json, this.bin) : _length = bin.length;

  final Map<String, dynamic> json;
  final Uint8List bin;

  int _length;
  final List<Uint8List> _blocks = [];

  /// Ob etwas angehängt wurde.
  bool get hasAdditions => _blocks.isNotEmpty;

  /// Hängt Bytes an und gibt den Index des neuen `bufferView` zurück.
  ///
  /// Aufgefüllt wird auf 4 Byte – die glTF-Spezifikation verlangt das
  /// für Accessoren, und manche Leser stürzen sonst ab.
  int addBufferView(Uint8List block, {int? byteStride}) {
    final offset = _length;
    _blocks.add(block);
    _length += block.length;
    final fuellung = (4 - (block.length % 4)) % 4;
    if (fuellung > 0) {
      _blocks.add(Uint8List(fuellung));
      _length += fuellung;
    }
    final views = (json['bufferViews'] as List?) ?? (json['bufferViews'] = []);
    views.add(<String, dynamic>{
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': block.length,
      'byteStride': ?byteStride,
    });
    return views.length - 1;
  }

  /// Legt einen Accessor auf einen bufferView an und gibt seinen
  /// Index zurück.
  int addAccessor({
    required int bufferView,
    required int componentType,
    required int count,
    required String type,
    List<num>? min,
    List<num>? max,
    bool normalized = false,
  }) {
    final accessors = (json['accessors'] as List?) ?? (json['accessors'] = []);
    accessors.add(<String, dynamic>{
      'bufferView': bufferView,
      'componentType': componentType,
      'count': count,
      'type': type,
      'min': ?min,
      'max': ?max,
      if (normalized) 'normalized': true,
    });
    return accessors.length - 1;
  }

  /// Kommazahlen anhängen und den Accessor gleich mit anlegen.
  int addFloats(Float32List values, String type,
      {List<num>? min, List<num>? max}) {
    final view = addBufferView(
        Uint8List.view(values.buffer, values.offsetInBytes,
            values.lengthInBytes));
    return addAccessor(
      bufferView: view,
      componentType: 5126,
      count: values.length ~/ gltfComponentCount(type),
      type: type,
      min: min,
      max: max,
    );
  }

  /// Eine Indexliste anhängen. Unter 65.536 Punkten reicht uint16.
  int addIndices(List<int> indices, int vertexCount) {
    final breit = vertexCount > 65535;
    final block = Uint8List(indices.length * (breit ? 4 : 2));
    final data = ByteData.sublistView(block);
    for (var i = 0; i < indices.length; i++) {
      if (breit) {
        data.setUint32(i * 4, indices[i], Endian.little);
      } else {
        data.setUint16(i * 2, indices[i], Endian.little);
      }
    }
    return addAccessor(
      bufferView: addBufferView(block),
      componentType: breit ? 5125 : 5123,
      count: indices.length,
      type: 'SCALAR',
    );
  }

  /// Ganze Zahlen fester Breite anhängen – für JOINTS_0 (uint16).
  int addUint16(List<int> values, String type) {
    final block = Uint8List(values.length * 2);
    final data = ByteData.sublistView(block);
    for (var i = 0; i < values.length; i++) {
      data.setUint16(i * 2, values[i], Endian.little);
    }
    return addAccessor(
      bufferView: addBufferView(block),
      componentType: 5123,
      count: values.length ~/ gltfComponentCount(type),
      type: type,
    );
  }

  /// Der fertige Binärteil. Zieht dabei die Puffergröße nach.
  Uint8List finish() {
    if (_blocks.isEmpty) return bin;
    final out = Uint8List(_length)..setRange(0, bin.length, bin);
    var pos = bin.length;
    for (final block in _blocks) {
      out.setRange(pos, pos + block.length, block);
      pos += block.length;
    }
    final buffers = (json['buffers'] as List?) ?? const [];
    if (buffers.isNotEmpty) {
      (buffers[0] as Map<String, dynamic>)['byteLength'] = out.length;
    }
    return out;
  }
}

/// Liest einen ganzzahligen Accessor (Indizes, JOINTS_0 …).
///
/// glTF lässt für dieselbe Sache mehrere Breiten zu; wer das nicht
/// beachtet, liest bei uint8-Gelenken Unsinn.
List<int> readGltfInts(
    Map<String, dynamic> json, Uint8List bin, int accessorIndex) {
  final accessor =
      (json['accessors'] as List)[accessorIndex] as Map<String, dynamic>;
  final viewIndex = (accessor['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return const [];
  final view =
      (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  final componentType = (accessor['componentType'] as num).toInt();
  final teile = gltfComponentCount(accessor['type'] as String);
  final size = gltfComponentSize(componentType);
  final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final stride = (view['byteStride'] as num?)?.toInt() ?? size * teile;
  final count = (accessor['count'] as num).toInt();
  final data = ByteData.sublistView(bin);
  final out = <int>[];
  for (var i = 0; i < count; i++) {
    for (var k = 0; k < teile; k++) {
      final at = start + i * stride + k * size;
      out.add(switch (componentType) {
        5120 => data.getInt8(at),
        5121 => data.getUint8(at),
        5122 => data.getInt16(at, Endian.little),
        5123 => data.getUint16(at, Endian.little),
        5125 => data.getUint32(at, Endian.little),
        _ => data.getFloat32(at, Endian.little).round(),
      });
    }
  }
  return out;
}

/// Liest einen Kommazahlen-Accessor und normiert dabei ganzzahlige
/// Gewichte – glTF erlaubt WEIGHTS_0 auch als uint8 oder uint16.
Float32List readGltfNormalizedFloats(
    Map<String, dynamic> json, Uint8List bin, int accessorIndex) {
  final accessor =
      (json['accessors'] as List)[accessorIndex] as Map<String, dynamic>;
  final componentType = (accessor['componentType'] as num).toInt();
  if (componentType == 5126) {
    final teile = gltfComponentCount(accessor['type'] as String);
    final viewIndex = (accessor['bufferView'] as num?)?.toInt();
    if (viewIndex == null) return Float32List(0);
    final view =
        (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
    final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
        ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
    final stride = (view['byteStride'] as num?)?.toInt() ?? teile * 4;
    final count = (accessor['count'] as num).toInt();
    final data = ByteData.sublistView(bin);
    final out = Float32List(count * teile);
    for (var i = 0; i < count; i++) {
      for (var k = 0; k < teile; k++) {
        out[i * teile + k] =
            data.getFloat32(start + i * stride + k * 4, Endian.little);
      }
    }
    return out;
  }
  final roh = readGltfInts(json, bin, accessorIndex);
  final teiler = componentType == 5121 ? 255.0 : 65535.0;
  return Float32List.fromList([for (final v in roh) v / teiler]);
}
