import 'dart:typed_data';
import 'dart:ui' as ui;

import 'glb_preview.dart' show splitGlb, joinGlb, gltfBufferViewBytes;

/// Ergebnis einer Textur-Verkleinerung.
class GlbShrinkResult {
  const GlbShrinkResult({
    required this.glb,
    required this.changed,
    required this.untouched,
    required this.external,
    required this.bytesBefore,
    required this.bytesAfter,
  });

  final Uint8List glb;

  /// Je verkleinertes Bild: vorherige und neue Kantenlänge.
  final List<({int fromWidth, int fromHeight, int toWidth, int toHeight})>
      changed;

  /// Bilder, die schon klein genug waren.
  final int untouched;

  /// Bilder, die nicht im Puffer liegen (externe oder data:-URI) und
  /// deshalb nicht angefasst wurden.
  final int external;

  final int bytesBefore;
  final int bytesAfter;

  bool get didSomething => changed.isNotEmpty;
}

/// Verkleinert alle eingebetteten Texturen auf höchstens [maxSize]
/// Pixel Kantenlänge – das Seitenverhältnis bleibt erhalten.
///
/// Roblox lehnt Bilder über 1024×1024 ab. Das war bisher eine
/// Sackgasse: Die Prüfung nannte den Fehler, beheben ließ er sich nur
/// außerhalb der App. Der Puffer wird dabei neu gepackt, die alten
/// großen Bilddaten fallen also weg.
///
/// Neu kodiert wird als PNG – Flutter kann nichts anderes schreiben.
/// Bei JPEG-Quellen (Tripo liefert PBR-Texturen als JPEG) kann die
/// Datei dadurch trotz kleinerer Bilder wachsen. Das Ergebnis nennt
/// deshalb die gemessene Größe vorher und nachher, statt etwas zu
/// versprechen.
///
/// Angefasst werden nur Bilder, die als `bufferView` im GLB stecken.
/// Bilder mit `uri` bleiben unverändert und werden gezählt.
Future<GlbShrinkResult> shrinkGlbTextures(
  Uint8List glb, {
  int maxSize = 1024,
}) async {
  final parts = splitGlb(glb);
  final json = parts.json;
  final bin = parts.bin;
  final images = (json['images'] as List?) ?? const [];
  final views = (json['bufferViews'] as List?) ?? const [];
  if (images.isEmpty || views.isEmpty) {
    return GlbShrinkResult(
      glb: glb,
      changed: const [],
      untouched: images.length,
      external: 0,
      bytesBefore: glb.length,
      bytesAfter: glb.length,
    );
  }

  // Neue Bilddaten je bufferView-Index; alles andere wird unverändert
  // umkopiert.
  final replacement = <int, Uint8List>{};
  final changed =
      <({int fromWidth, int fromHeight, int toWidth, int toHeight})>[];
  var untouched = 0;
  var external = 0;

  for (final entry in images) {
    final image = entry as Map<String, dynamic>;
    final viewIndex = (image['bufferView'] as num?)?.toInt();
    if (viewIndex == null || viewIndex >= views.length) {
      external++;
      continue;
    }
    final bytes = gltfBufferViewBytes(json, bin, viewIndex);
    final size = await _imageSize(bytes);
    if (size == null) {
      untouched++;
      continue;
    }
    final (width, height) = size;
    final longest = width > height ? width : height;
    if (longest <= maxSize) {
      untouched++;
      continue;
    }
    final scale = maxSize / longest;
    // Mindestens 1 Pixel, sonst schlägt der Codec fehl.
    final newWidth = (width * scale).round().clamp(1, maxSize);
    final newHeight = (height * scale).round().clamp(1, maxSize);
    final png = await _resizeToPng(bytes, newWidth, newHeight);
    if (png == null) {
      untouched++;
      continue;
    }
    replacement[viewIndex] = png;
    image['mimeType'] = 'image/png';
    changed.add((
      fromWidth: width,
      fromHeight: height,
      toWidth: newWidth,
      toHeight: newHeight,
    ));
  }

  if (replacement.isEmpty) {
    return GlbShrinkResult(
      glb: glb,
      changed: const [],
      untouched: untouched,
      external: external,
      bytesBefore: glb.length,
      bytesAfter: glb.length,
    );
  }

  final packed = _repackBuffer(json, bin, replacement);
  final out = joinGlb(json, packed);
  return GlbShrinkResult(
    glb: out,
    changed: changed,
    untouched: untouched,
    external: external,
    bytesBefore: glb.length,
    bytesAfter: out.length,
  );
}

/// Baut den Binärteil neu auf: jeder bufferView bekommt seine Daten
/// hintereinander, auf 4 Byte ausgerichtet, mit neuem `byteOffset`.
///
/// Accessoren zeigen über den Index auf ihren bufferView und rechnen
/// ihren eigenen `byteOffset` relativ dazu – die Reihenfolge bleibt
/// deshalb erhalten, und nichts anderes muss angefasst werden.
Uint8List _repackBuffer(
  Map<String, dynamic> json,
  Uint8List bin,
  Map<int, Uint8List> replacement,
) {
  final views = json['bufferViews'] as List;
  final chunks = <Uint8List>[];
  var total = 0;
  int pad4(int n) => (n + 3) & ~3;

  for (var i = 0; i < views.length; i++) {
    final view = views[i] as Map<String, dynamic>;
    final data = replacement[i] ?? gltfBufferViewBytes(json, bin, i);
    view['byteOffset'] = total;
    view['byteLength'] = data.length;
    chunks.add(data);
    total += pad4(data.length);
  }

  final out = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += pad4(chunk.length);
  }
  final buffers = json['buffers'] as List?;
  if (buffers != null && buffers.isNotEmpty) {
    (buffers.first as Map<String, dynamic>)['byteLength'] = total;
  }
  return out;
}

/// Kantenlängen eines kodierten Bildes – null, wenn es sich nicht
/// dekodieren lässt.
Future<(int, int)?> _imageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// Skaliert ein kodiertes Bild und gibt es als PNG zurück.
Future<Uint8List?> _resizeToPng(
    Uint8List bytes, int width, int height) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: width, targetHeight: height);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
