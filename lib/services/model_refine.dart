/// Lokale Veredelungs-Stufen für generierte 3D-Modelle – die
/// Nachbearbeitungs-Schritte einer professionellen 3D-Pipeline,
/// komplett in der App (ohne weitere API-Kosten):
///
/// 1. **Kanonische Ausrichtung** ([canonicalizeYawGlb]): richtet die
///    horizontale Hauptachse des Modells auf die Tiefenachse (+z) aus –
///    ein schräg im Raum stehendes Fahrzeug (typisch bei
///    Einzelbild-Rekonstruktion aus einer Dreiviertelansicht) steht
///    danach gerade, und die automatische Rad-Erkennung greift.
/// 2. **Spiegel-Symmetrisierung** ([mirrorSymmetrizeGlb]): ersetzt die
///    schwächere Modellhälfte (weniger Netzdetail – bei
///    Einzelbild-Rekonstruktion die vom Foto abgewandte Seite) durch
///    die gespiegelte bessere Hälfte. Bei symmetrischen Motiven
///    (Fahrzeuge!) verschwindet so der „verwaschene“ Teil.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'glb_preview.dart' show parseGlbForPreview;
import 'local_3d.dart' show LocalMesh, buildGlb;

int _pad4(int n) => (n + 3) & ~3;

(Map<String, dynamic>, Uint8List) _parseGlb(Uint8List glb) {
  if (glb.length < 20) throw Exception('Ungültige GLB-Datei.');
  final header = ByteData.sublistView(glb);
  if (header.getUint32(0, Endian.little) != 0x46546C67 ||
      header.getUint32(4, Endian.little) != 2) {
    throw Exception('Ungültige GLB-Datei.');
  }
  final jsonLength = header.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(glb.sublist(20, 20 + jsonLength)))
      as Map<String, dynamic>;
  final binHeaderOffset = 20 + _pad4(jsonLength);
  var bin = Uint8List(0);
  if (binHeaderOffset + 8 <= glb.length &&
      header.getUint32(binHeaderOffset + 4, Endian.little) == 0x004E4942) {
    final binLength = header.getUint32(binHeaderOffset, Endian.little);
    bin = Uint8List.fromList(
        glb.sublist(binHeaderOffset + 8, binHeaderOffset + 8 + binLength));
  }
  return (json, bin);
}

Uint8List _writeGlb(Map<String, dynamic> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadded = Uint8List(_pad4(jsonBytes.length))
    ..fillRange(0, _pad4(jsonBytes.length), 0x20)
    ..setRange(0, jsonBytes.length, jsonBytes);
  final binPadded = Uint8List(_pad4(bin.length))
    ..setRange(0, bin.length, bin);
  final total = 12 + 8 + jsonPadded.length + 8 + binPadded.length;
  final out = ByteData(total);
  var o = 0;
  void u32(int value) {
    out.setUint32(o, value, Endian.little);
    o += 4;
  }

  u32(0x46546C67);
  u32(2);
  u32(total);
  u32(jsonPadded.length);
  u32(0x4E4F534A);
  out.buffer.asUint8List().setRange(o, o + jsonPadded.length, jsonPadded);
  o += jsonPadded.length;
  u32(binPadded.length);
  u32(0x004E4942);
  out.buffer.asUint8List().setRange(o, o + binPadded.length, binPadded);
  return out.buffer.asUint8List();
}

/// Ruft [visit] für jeden Vektor eines float32-Accessors auf; [write]
/// schreibt die (ggf. veränderten) Komponenten zurück.
void _forEachVector(Map<String, dynamic> json, Uint8List bin, int accessor,
    int components, void Function(Float64List v) visit,
    {bool write = false}) {
  final acc = (json['accessors'] as List)[accessor] as Map<String, dynamic>;
  if (acc['componentType'] != 5126 || acc.containsKey('sparse')) return;
  final viewIndex = acc['bufferView'] as int?;
  if (viewIndex == null) return;
  final view =
      (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  final count = acc['count'] as int;
  final stride = (view['byteStride'] as int?) ?? components * 4;
  final start = ((view['byteOffset'] as int?) ?? 0) +
      ((acc['byteOffset'] as int?) ?? 0);
  final data = ByteData.sublistView(bin);
  final v = Float64List(components);
  for (var i = 0; i < count; i++) {
    final o = start + i * stride;
    for (var k = 0; k < components; k++) {
      v[k] = data.getFloat32(o + k * 4, Endian.little);
    }
    visit(v);
    if (write) {
      for (var k = 0; k < components; k++) {
        data.setFloat32(o + k * 4, v[k], Endian.little);
      }
    }
  }
}

/// Aktualisiert min/max eines VEC3-Accessors nach einer Änderung.
void _refreshMinMax(Map<String, dynamic> json, Uint8List bin, int accessor) {
  final acc = (json['accessors'] as List)[accessor] as Map<String, dynamic>;
  if (!acc.containsKey('min') && !acc.containsKey('max')) return;
  final mn = [double.infinity, double.infinity, double.infinity];
  final mx = [
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity
  ];
  _forEachVector(json, bin, accessor, 3, (v) {
    for (var k = 0; k < 3; k++) {
      if (v[k] < mn[k]) mn[k] = v[k];
      if (v[k] > mx[k]) mx[k] = v[k];
    }
  });
  acc['min'] = mn;
  acc['max'] = mx;
}

/// Sammelt die Attribut-Accessoren aller Primitives (dedupliziert).
Set<int> _attributeAccessors(Map<String, dynamic> json, String attribute) {
  final result = <int>{};
  for (final mesh in (json['meshes'] as List?) ?? []) {
    for (final primitive in (mesh as Map)['primitives'] as List) {
      final index =
          ((primitive as Map)['attributes'] as Map)[attribute] as int?;
      if (index != null) result.add(index);
    }
  }
  return result;
}

/// Dreht das Modell in 90°-Schritten um eine Achse ('x', 'y' oder 'z')
/// und schreibt die gedrehte Geometrie zurück – anders als eine reine
/// Ansichts-Drehung wirkt das auch im Export (Druck, Engine).
///
/// Wirft eine [Exception], wenn das Modell ein Skelett trägt oder die
/// Mesh-Knoten eigene Transformationen haben: Dann müssten Gelenke und
/// Bind-Matrizen mitgedreht werden, sonst zerreißt das Rig.
/// [quarterTurns] zählt Vierteldrehungen im Uhrzeigersinn um die Achse
/// (mathematisch positiv, von der Achsenspitze aus gesehen).
Uint8List rotateGlbQuarterTurns(Uint8List glb, String axis,
    {int quarterTurns = 1}) {
  final turns = ((quarterTurns % 4) + 4) % 4;
  if (turns == 0) return glb;
  final (json, bin) = _parseGlb(glb);
  if ((json['skins'] as List?)?.isNotEmpty ?? false) {
    throw Exception('Das Modell trägt ein Skelett – bitte zuerst das '
        'Rigging ausschalten bzw. das ungeriggte Modell drehen, sonst '
        'passen Gelenke und Netz nicht mehr zusammen.');
  }
  for (final node in (json['nodes'] as List?) ?? []) {
    final map = node as Map;
    if (map.containsKey('mesh') &&
        (map.containsKey('rotation') ||
            map.containsKey('scale') ||
            map.containsKey('matrix'))) {
      throw Exception('Dieses Modell hat eigene Knoten-Transformationen '
          '– Drehen würde die Darstellung verfälschen.');
    }
  }
  final positionAccessors = _attributeAccessors(json, 'POSITION');
  if (positionAccessors.isEmpty) {
    throw Exception('Keine Geometrie zum Drehen gefunden.');
  }

  // 90°-Schritte exakt: nur Vertauschen und Vorzeichenwechsel, keine
  // Sinus-/Kosinus-Rundungsfehler.
  final angle = turns * math.pi / 2;
  final c = math.cos(angle).round().toDouble();
  final sn = math.sin(angle).round().toDouble();
  late final void Function(Float64List) rotate;
  switch (axis) {
    case 'x':
      rotate = (v) {
        final y = v[1], z = v[2];
        v[1] = y * c - z * sn;
        v[2] = y * sn + z * c;
      };
    case 'z':
      rotate = (v) {
        final x = v[0], y = v[1];
        v[0] = x * c - y * sn;
        v[1] = x * sn + y * c;
      };
    default: // 'y'
      rotate = (v) {
        final x = v[0], z = v[2];
        v[0] = x * c + z * sn;
        v[2] = -x * sn + z * c;
      };
  }

  for (final a in positionAccessors) {
    _forEachVector(json, bin, a, 3, rotate, write: true);
    _refreshMinMax(json, bin, a);
  }
  for (final a in _attributeAccessors(json, 'NORMAL')) {
    _forEachVector(json, bin, a, 3, rotate, write: true);
    _refreshMinMax(json, bin, a);
  }
  for (final a in _attributeAccessors(json, 'TANGENT')) {
    // VEC4: xyz drehen, w (Händigkeit) bleibt.
    _forEachVector(json, bin, a, 4, rotate, write: true);
  }
  return _writeGlb(json, bin);
}

/// Kanonische Ausrichtung: dreht das Modell um die y-Achse, sodass die
/// horizontale Hauptachse (PCA über x/z) auf der Tiefenachse z liegt –
/// die Fahrzeug-Konvention des Auto-Riggers. Liefert die neue GLB und
/// den angewendeten Winkel in Grad (0 = nichts zu tun, z. B. wenn das
/// Modell bereits ausgerichtet ist, ein Skelett trägt oder die
/// Mesh-Knoten eigene Transformationen haben).
(Uint8List, double) canonicalizeYawGlb(Uint8List glb,
    {double minAngleDeg = 5}) {
  final (json, bin) = _parseGlb(glb);
  if ((json['skins'] as List?)?.isNotEmpty ?? false) return (glb, 0);
  // Nur sicher bei Knoten ohne eigene Rotation/Skalierung.
  for (final node in (json['nodes'] as List?) ?? []) {
    final map = node as Map;
    if (map.containsKey('mesh') &&
        (map.containsKey('rotation') ||
            map.containsKey('scale') ||
            map.containsKey('matrix'))) {
      return (glb, 0);
    }
  }
  final positionAccessors = _attributeAccessors(json, 'POSITION');
  if (positionAccessors.isEmpty) return (glb, 0);

  // Kovarianz der Grundriss-Koordinaten (x, z).
  var n = 0;
  var mx = 0.0, mz = 0.0;
  for (final a in positionAccessors) {
    _forEachVector(json, bin, a, 3, (v) {
      mx += v[0];
      mz += v[2];
      n++;
    });
  }
  if (n < 3) return (glb, 0);
  mx /= n;
  mz /= n;
  var sxx = 0.0, sxz = 0.0, szz = 0.0;
  for (final a in positionAccessors) {
    _forEachVector(json, bin, a, 3, (v) {
      final dx = v[0] - mx, dz = v[2] - mz;
      sxx += dx * dx;
      sxz += dx * dz;
      szz += dz * dz;
    });
  }
  // Winkel der Hauptachse zur x-Achse; Drehung um (alpha - 90°) bringt
  // sie auf die z-Achse. Modulo 180° minimal drehen (vorn/hinten ist
  // für die Ausrichtung egal).
  final alpha = 0.5 * math.atan2(2 * sxz, sxx - szz);
  var theta = alpha - math.pi / 2;
  while (theta > math.pi / 2) {
    theta -= math.pi;
  }
  while (theta <= -math.pi / 2) {
    theta += math.pi;
  }
  final degrees = theta * 180 / math.pi;
  if (degrees.abs() < minAngleDeg) return (glb, 0);

  final cosT = math.cos(theta), sinT = math.sin(theta);
  void rotate(Float64List v) {
    final x = v[0], z = v[2];
    v[0] = x * cosT + z * sinT;
    v[2] = -x * sinT + z * cosT;
  }

  for (final a in positionAccessors) {
    _forEachVector(json, bin, a, 3, rotate, write: true);
    _refreshMinMax(json, bin, a);
  }
  for (final a in _attributeAccessors(json, 'NORMAL')) {
    _forEachVector(json, bin, a, 3, rotate, write: true);
    _refreshMinMax(json, bin, a);
  }
  for (final a in _attributeAccessors(json, 'TANGENT')) {
    // VEC4: xyz drehen, w (Händigkeit) bleibt.
    _forEachVector(json, bin, a, 4, rotate, write: true);
  }
  return (_writeGlb(json, bin), degrees);
}

Future<(Uint8List, int, int)> _decodeRgba(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) throw Exception('Bild konnte nicht gelesen werden.');
    return (raw.buffer.asUint8List(), image.width, image.height);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodePngRgba(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(buffer,
      width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  try {
    final png =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw Exception('PNG konnte nicht erzeugt werden.');
    return png.buffer.asUint8List();
  } finally {
    frame.image.dispose();
  }
}

/// Ersetzt die Basecolor-Textur einer GLB durch [pngBytes] (die alten
/// Bilddaten bleiben ungenutzt im Puffer – einfach und verlustfrei).
Uint8List _replaceBaseColorImage(Uint8List glb, Uint8List pngBytes) {
  final (json, bin) = _parseGlb(glb);
  // Basecolor-Bild über Material → Textur → Bild auflösen; Rückfall:
  // erstes Bild.
  var imageIndex = 0;
  final materials = json['materials'] as List?;
  final textures = json['textures'] as List?;
  if (materials != null && materials.isNotEmpty && textures != null) {
    final pbr = (materials.first as Map)['pbrMetallicRoughness'];
    final baseTexture =
        pbr is Map ? pbr['baseColorTexture'] : null;
    final textureIndex =
        baseTexture is Map ? baseTexture['index'] as int? : null;
    if (textureIndex != null && textureIndex < textures.length) {
      imageIndex =
          (textures[textureIndex] as Map)['source'] as int? ?? 0;
    }
  }
  final images = json['images'] as List?;
  if (images == null || imageIndex >= images.length) {
    throw Exception('Die GLB enthält kein Texturbild.');
  }

  final offset = _pad4(bin.length);
  final newBin = Uint8List(offset + pngBytes.length)
    ..setRange(0, bin.length, bin)
    ..setRange(offset, offset + pngBytes.length, pngBytes);
  final bufferViews =
      ((json['bufferViews'] as List?) ?? []).cast<dynamic>().toList();
  bufferViews.add({
    'buffer': 0,
    'byteOffset': offset,
    'byteLength': pngBytes.length,
  });
  json['bufferViews'] = bufferViews;
  final image = (images[imageIndex] as Map).cast<String, dynamic>();
  image['bufferView'] = bufferViews.length - 1;
  image['mimeType'] = 'image/png';
  image.remove('uri');
  images[imageIndex] = image;
  (json['buffers'] as List)[0]['byteLength'] = newBin.length;
  return _writeGlb(json, newBin);
}

/// Textur-Stufe der Veredelung: projiziert das scharfe Ausgangsbild
/// zurück auf die der Kamera zugewandte Seite des Modells und ersetzt
/// dort die weiche, generierte Textur. Die Abbildung (Maßstab,
/// Versatz, Perspektive) wird automatisch kalibriert, indem die
/// Übereinstimmung zwischen projizierten Bildfarben und der
/// vorhandenen Textur maximiert wird; verdeckte und abgewandte
/// Flächen bleiben unangetastet (Tiefenpuffer + Normalen-Test), die
/// Ränder werden weich eingeblendet. Liefert null, wenn Bild und
/// Modell nicht zusammenpassen (Kalibrierung schlägt fehl) – dann
/// bleibt die Original-Textur unverändert.
Future<Uint8List?> reprojectSourceImageTexture(
    Uint8List glb, Uint8List sourceImageBytes) async {
  final mesh = await parseGlbForPreview(glb);
  try {
    final uvs = mesh.uvs;
    final texture = mesh.texture;
    if (uvs == null || texture == null || mesh.rig != null) return null;
    final positions = mesh.positions;
    final indices = mesh.indices;
    final extent = mesh.extent;
    if (extent <= 0 || indices.length < 3) return null;

    final texData =
        await texture.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (texData == null) return null;
    final tex = texData.buffer.asUint8List();
    final tw = texture.width, th = texture.height;
    final (src, sw, sh) = await _decodeRgba(sourceImageBytes);

    // Dreiecksnormalen (Blickrichtung: Kamera schaut entlang +z auf
    // die -z-Seite; sichtbar sind Flächen mit Normalen-z < 0).
    final triCount = indices.length ~/ 3;
    final faceNz = Float32List(triCount);
    for (var t = 0; t < triCount; t++) {
      final a = indices[t * 3] * 3,
          b = indices[t * 3 + 1] * 3,
          c = indices[t * 3 + 2] * 3;
      final abx = positions[b] - positions[a],
          aby = positions[b + 1] - positions[a + 1],
          abz = positions[b + 2] - positions[a + 2];
      final acx = positions[c] - positions[a],
          acy = positions[c + 1] - positions[a + 1],
          acz = positions[c + 2] - positions[a + 2];
      final nx = aby * acz - abz * acy;
      final nyv = abz * acx - abx * acz;
      final nz = abx * acy - aby * acx;
      final len = math.sqrt(nx * nx + nyv * nyv + nz * nz);
      faceNz[t] = len > 1e-12 ? nz / len : 0;
    }

    // Ausgangs-Schätzung der Abbildung: Begrenzungsrahmen der
    // kamerazugewandten Geometrie auf den deckenden Bildbereich legen.
    var mnX = double.infinity, mxX = double.negativeInfinity;
    var mnY = double.infinity, mxY = double.negativeInfinity;
    var mnZ = double.infinity, mxZ = double.negativeInfinity;
    for (var t = 0; t < triCount; t++) {
      if (faceNz[t] >= -0.2) continue;
      for (var k = 0; k < 3; k++) {
        final v = indices[t * 3 + k] * 3;
        final x = positions[v], y = positions[v + 1], z = positions[v + 2];
        if (x < mnX) mnX = x;
        if (x > mxX) mxX = x;
        if (y < mnY) mnY = y;
        if (y > mxY) mxY = y;
        if (z < mnZ) mnZ = z;
        if (z > mxZ) mxZ = z;
      }
    }
    if (!mnX.isFinite || mxX - mnX < 1e-6 || mxY - mnY < 1e-6) return null;
    var sMnX = sw, sMxX = 0, sMnY = sh, sMxY = 0;
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        if (src[(y * sw + x) * 4 + 3] > 128) {
          if (x < sMnX) sMnX = x;
          if (x > sMxX) sMxX = x;
          if (y < sMnY) sMnY = y;
          if (y > sMxY) sMxY = y;
        }
      }
    }
    if (sMxX <= sMnX || sMxY <= sMnY) return null;
    final scale0 = 0.5 *
        ((sMxX - sMnX) / (mxX - mnX) + (sMxY - sMnY) / (mxY - mnY));
    final cxm = (mnX + mxX) / 2, cym = (mnY + mxY) / 2;
    final czm = (mnZ + mxZ) / 2;
    final ox0 = (sMnX + sMxX) / 2 - 0.0;
    final oy0 = (sMnY + sMxY) / 2 - 0.0;

    // Stichproben: Schwerpunkte kamerazugewandter Dreiecke samt
    // vorhandener Texturfarbe.
    final sampleX = <double>[], sampleY = <double>[], sampleZ = <double>[];
    final sampleR = <int>[], sampleG = <int>[], sampleB = <int>[];
    final step = math.max(1, triCount ~/ 1500);
    for (var t = 0; t < triCount; t += step) {
      if (faceNz[t] >= -0.4) continue;
      final a = indices[t * 3], b = indices[t * 3 + 1], c = indices[t * 3 + 2];
      final px = (positions[a * 3] + positions[b * 3] + positions[c * 3]) / 3;
      final py = (positions[a * 3 + 1] +
              positions[b * 3 + 1] +
              positions[c * 3 + 1]) /
          3;
      final pz = (positions[a * 3 + 2] +
              positions[b * 3 + 2] +
              positions[c * 3 + 2]) /
          3;
      final u = ((uvs[a * 2] + uvs[b * 2] + uvs[c * 2]) / 3)
          .clamp(0.0, 1.0);
      final v = ((uvs[a * 2 + 1] + uvs[b * 2 + 1] + uvs[c * 2 + 1]) / 3)
          .clamp(0.0, 1.0);
      final txp = (u * (tw - 1)).round(), typ = (v * (th - 1)).round();
      final o = (typ * tw + txp) * 4;
      sampleX.add(px);
      sampleY.add(py);
      sampleZ.add(pz);
      sampleR.add(tex[o]);
      sampleG.add(tex[o + 1]);
      sampleB.add(tex[o + 2]);
    }
    if (sampleX.length < 4) return null;

    // Kalibrierung: Maßstab, Versatz und ein Perspektiv-Faktor werden
    // über die Farb-Übereinstimmung gesucht (grob, dann fein).
    double bestScore = double.infinity;
    var bestScale = scale0, bestOx = ox0, bestOy = oy0, bestP = 0.0;
    double evaluate(double scale, double ox, double oy, double p) {
      var sum = 0.0;
      var hit = 0;
      for (var i = 0; i < sampleX.length; i++) {
        final persp = 1.0 + p * (sampleZ[i] - czm) / extent;
        if (persp <= 0.2) return double.infinity;
        final u = ox + (sampleX[i] - cxm) * scale / persp;
        final v = oy - (sampleY[i] - cym) * scale / persp;
        final xi = u.round(), yi = v.round();
        if (xi < 0 || yi < 0 || xi >= sw || yi >= sh) continue;
        final o = (yi * sw + xi) * 4;
        if (src[o + 3] <= 128) continue;
        hit++;
        sum += (src[o] - sampleR[i]).abs() +
            (src[o + 1] - sampleG[i]).abs() +
            (src[o + 2] - sampleB[i]).abs();
      }
      if (hit < sampleX.length * 0.6) return double.infinity;
      return sum / hit / 3;
    }

    void search(List<double> scales, List<double> oxs, List<double> oys,
        List<double> ps) {
      for (final s in scales) {
        for (final p in ps) {
          for (final ox in oxs) {
            for (final oy in oys) {
              final score = evaluate(s, ox, oy, p);
              if (score < bestScore) {
                bestScore = score;
                bestScale = s;
                bestOx = ox;
                bestOy = oy;
                bestP = p;
              }
            }
          }
        }
      }
    }

    List<double> around(double center, double radius, int steps) => [
          for (var i = 0; i <= steps; i++)
            center - radius + 2 * radius * i / steps,
        ];
    search(around(scale0, scale0 * 0.15, 4), around(ox0, sw * 0.06, 4),
        around(oy0, sh * 0.06, 4), const [0.0, 0.2, 0.4, 0.6]);
    search(
        around(bestScale, bestScale * 0.05, 4),
        around(bestOx, sw * 0.02, 4),
        around(bestOy, sh * 0.02, 4),
        around(bestP, 0.1, 2));
    // Passt das Bild nicht zum Modell (falsches Paar, andere Ansicht),
    // bleibt die Übereinstimmung schlecht – dann nichts verändern.
    if (bestScore > 55) return null;

    double projU(double x, double z) =>
        bestOx + (x - cxm) * bestScale / (1.0 + bestP * (z - czm) / extent);
    double projV(double y, double z) =>
        bestOy - (y - cym) * bestScale / (1.0 + bestP * (z - czm) / extent);

    // Tiefenpuffer in Bildauflösung: nächstliegende Fläche je Pixel.
    final zbuf = Float32List(sw * sh)
      ..fillRange(0, sw * sh, double.infinity);
    for (var t = 0; t < triCount; t++) {
      final a = indices[t * 3], b = indices[t * 3 + 1], c = indices[t * 3 + 2];
      final za = positions[a * 3 + 2],
          zb = positions[b * 3 + 2],
          zc = positions[c * 3 + 2];
      final xa = projU(positions[a * 3], za),
          ya = projV(positions[a * 3 + 1], za);
      final xb = projU(positions[b * 3], zb),
          yb = projV(positions[b * 3 + 1], zb);
      final xc = projU(positions[c * 3], zc),
          yc = projV(positions[c * 3 + 1], zc);
      final minX = math.max(0, math.min(xa, math.min(xb, xc)).floor());
      final maxX =
          math.min(sw - 1, math.max(xa, math.max(xb, xc)).ceil());
      final minY = math.max(0, math.min(ya, math.min(yb, yc)).floor());
      final maxY =
          math.min(sh - 1, math.max(ya, math.max(yb, yc)).ceil());
      if (maxX < minX || maxY < minY) continue;
      final det = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc);
      if (det.abs() < 1e-9) continue;
      for (var y = minY; y <= maxY; y++) {
        for (var x = minX; x <= maxX; x++) {
          final l1 = ((yb - yc) * (x - xc) + (xc - xb) * (y - yc)) / det;
          final l2 = ((yc - ya) * (x - xc) + (xa - xc) * (y - yc)) / det;
          final l3 = 1 - l1 - l2;
          if (l1 < -0.02 || l2 < -0.02 || l3 < -0.02) continue;
          final z = l1 * za + l2 * zb + l3 * zc;
          final o = y * sw + x;
          if (z < zbuf[o]) zbuf[o] = z;
        }
      }
    }

    // Textur neu einfärben: je Texel der kamerazugewandten Dreiecke
    // die Bildfarbe übernehmen (weich nach Blickwinkel eingeblendet).
    final newTex = Uint8List.fromList(tex);
    final depthTolerance = extent * 0.02;
    for (var t = 0; t < triCount; t++) {
      final facing = -faceNz[t];
      if (facing < 0.25) continue;
      final blend = ((facing - 0.25) / 0.35).clamp(0.0, 1.0);
      final a = indices[t * 3], b = indices[t * 3 + 1], c = indices[t * 3 + 2];
      final ua = uvs[a * 2] * (tw - 1), va = uvs[a * 2 + 1] * (th - 1);
      final ub = uvs[b * 2] * (tw - 1), vb = uvs[b * 2 + 1] * (th - 1);
      final uc = uvs[c * 2] * (tw - 1), vc = uvs[c * 2 + 1] * (th - 1);
      final minU = math.max(0, math.min(ua, math.min(ub, uc)).floor());
      final maxU =
          math.min(tw - 1, math.max(ua, math.max(ub, uc)).ceil());
      final minV = math.max(0, math.min(va, math.min(vb, vc)).floor());
      final maxV =
          math.min(th - 1, math.max(va, math.max(vb, vc)).ceil());
      final det = (vb - vc) * (ua - uc) + (uc - ub) * (va - vc);
      if (det.abs() < 1e-9) continue;
      for (var v = minV; v <= maxV; v++) {
        for (var u = minU; u <= maxU; u++) {
          final l1 = ((vb - vc) * (u - uc) + (uc - ub) * (v - vc)) / det;
          final l2 = ((vc - va) * (u - uc) + (ua - uc) * (v - vc)) / det;
          final l3 = 1 - l1 - l2;
          if (l1 < -0.05 || l2 < -0.05 || l3 < -0.05) continue;
          final px = l1 * positions[a * 3] +
              l2 * positions[b * 3] +
              l3 * positions[c * 3];
          final py = l1 * positions[a * 3 + 1] +
              l2 * positions[b * 3 + 1] +
              l3 * positions[c * 3 + 1];
          final pz = l1 * positions[a * 3 + 2] +
              l2 * positions[b * 3 + 2] +
              l3 * positions[c * 3 + 2];
          final sx = projU(px, pz), sy = projV(py, pz);
          final xi = sx.round(), yi = sy.round();
          if (xi < 0 || yi < 0 || xi >= sw || yi >= sh) continue;
          final so = (yi * sw + xi) * 4;
          if (src[so + 3] <= 200) continue;
          if (pz > zbuf[yi * sw + xi] + depthTolerance) continue;
          final to = (v * tw + u) * 4;
          newTex[to] =
              (newTex[to] + (src[so] - newTex[to]) * blend).round();
          newTex[to + 1] =
              (newTex[to + 1] + (src[so + 1] - newTex[to + 1]) * blend)
                  .round();
          newTex[to + 2] =
              (newTex[to + 2] + (src[so + 2] - newTex[to + 2]) * blend)
                  .round();
        }
      }
    }

    final png = await _encodePngRgba(newTex, tw, th);
    return _replaceBaseColorImage(glb, png);
  } finally {
    mesh.dispose();
  }
}

/// Erste eingebettete Bilddatei einer GLB (Basecolor-Textur).
Uint8List? _firstImageBytes(Uint8List glb) {
  final (json, bin) = _parseGlb(glb);
  for (final image in (json['images'] as List?) ?? []) {
    final viewIndex = (image as Map)['bufferView'] as int?;
    if (viewIndex == null) continue;
    final view =
        (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
    final offset = (view['byteOffset'] as int?) ?? 0;
    return Uint8List.sublistView(bin, offset, offset + (view['byteLength'] as int));
  }
  return null;
}

/// Spiegel-Symmetrisierung: schneidet das Modell an der Mittelebene
/// (x = 0), behält die Hälfte mit mehr Netzdetail (mehr Vertices) und
/// ersetzt die andere durch deren Spiegelbild. Erwartet ein
/// texturiertes, ungeriggtes Modell; die Basecolor-Textur bleibt
/// erhalten (PBR-Zusatztexturen werden zu Pauschalwerten). Wirft
/// [Exception] mit verständlicher Meldung, wenn das nicht geht.
Future<Uint8List> mirrorSymmetrizeGlb(Uint8List glb) async {
  final mesh = await parseGlbForPreview(glb);
  try {
    if (mesh.rig != null) {
      throw Exception('Symmetrisieren erwartet ein Modell ohne Skelett '
          '(vor dem Rigging anwenden).');
    }
    final uvs = mesh.uvs;
    final texture = mesh.texture;
    if (uvs == null || texture == null) {
      throw Exception(
          'Symmetrisieren benötigt ein texturiertes Modell (UV-Koordinaten).');
    }
    final positions = mesh.positions;
    final indices = mesh.indices;

    // Bessere Hälfte = mehr Netzdetail (Einzelbild-Rekonstruktionen
    // legen auf die abgewandte Seite deutlich weniger Vertices).
    var negative = 0, positive = 0;
    for (var i = 0; i < positions.length; i += 3) {
      if (positions[i] < 0) {
        negative++;
      } else if (positions[i] > 0) {
        positive++;
      }
    }
    final keepNegative = negative >= positive;
    final eps = mesh.extent * 1e-6;
    // Abstand zur Halteseite: d <= 0 wird behalten.
    double d(int vertex) => keepNegative
        ? positions[vertex * 3]
        : -positions[vertex * 3];

    final outPositions = <double>[];
    final outUvs = <double>[];
    final outIndices = <int>[];

    int emit(double x, double y, double z, double u, double v) {
      outPositions.addAll([x, y, z]);
      outUvs.addAll([u, v]);
      return outPositions.length ~/ 3 - 1;
    }

    // Unveränderte Vertices werden wiederverwendet (hält die Datei
    // klein); nur Schnittpunkte entstehen neu.
    final vertexMap = <int, int>{};
    int emitVertex(int vertex) => vertexMap.putIfAbsent(
          vertex,
          () => emit(
            positions[vertex * 3],
            positions[vertex * 3 + 1],
            positions[vertex * 3 + 2],
            uvs[vertex * 2],
            uvs[vertex * 2 + 1],
          ),
        );

    int emitLerp(int a, int b, double t) => emit(
          positions[a * 3] + (positions[b * 3] - positions[a * 3]) * t,
          positions[a * 3 + 1] +
              (positions[b * 3 + 1] - positions[a * 3 + 1]) * t,
          positions[a * 3 + 2] +
              (positions[b * 3 + 2] - positions[a * 3 + 2]) * t,
          uvs[a * 2] + (uvs[b * 2] - uvs[a * 2]) * t,
          uvs[a * 2 + 1] + (uvs[b * 2 + 1] - uvs[a * 2 + 1]) * t,
        );

    // Dreiecke gegen die Halbebene d <= 0 clippen
    // (Sutherland-Hodgman, ergibt 3 oder 4 Eckpunkte).
    for (var t = 0; t < indices.length; t += 3) {
      final tri = [indices[t], indices[t + 1], indices[t + 2]];
      final dist = [for (final v in tri) d(v)];
      if (dist.every((value) => value <= eps)) {
        outIndices.addAll([for (final v in tri) emitVertex(v)]);
        continue;
      }
      if (dist.every((value) => value >= -eps)) continue;
      final poly = <int>[];
      for (var k = 0; k < 3; k++) {
        final a = tri[k], b = tri[(k + 1) % 3];
        final da = dist[k], db = dist[(k + 1) % 3];
        if (da <= eps) poly.add(emitVertex(a));
        if ((da < -eps && db > eps) || (da > eps && db < -eps)) {
          poly.add(emitLerp(a, b, da / (da - db)));
        }
      }
      for (var k = 2; k < poly.length; k++) {
        outIndices.addAll([poly[0], poly[k - 1], poly[k]]);
      }
    }
    if (outIndices.isEmpty) {
      throw Exception('Die Geometrie liegt komplett auf einer Seite – '
          'nichts zu symmetrisieren.');
    }

    // Gespiegelte Kopie der behaltenen Hälfte anhängen (x negiert,
    // Umlaufrichtung getauscht, damit die Normalen außen bleiben).
    final halfVertexCount = outPositions.length ~/ 3;
    final halfIndexCount = outIndices.length;
    for (var v = 0; v < halfVertexCount; v++) {
      emit(-outPositions[v * 3], outPositions[v * 3 + 1],
          outPositions[v * 3 + 2], outUvs[v * 2], outUvs[v * 2 + 1]);
    }
    for (var i = 0; i < halfIndexCount; i += 3) {
      outIndices.addAll([
        outIndices[i] + halfVertexCount,
        outIndices[i + 2] + halfVertexCount,
        outIndices[i + 1] + halfVertexCount,
      ]);
    }

    // Basecolor-Textur übernehmen (JPEG wird nach PNG gewandelt, da
    // buildGlb PNG einbettet).
    var png = _firstImageBytes(glb);
    final isPng = png != null &&
        png.length > 3 &&
        png[0] == 0x89 &&
        png[1] == 0x50;
    if (!isPng) {
      final data =
          await texture.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw Exception('Die Textur konnte nicht übernommen werden.');
      }
      png = data.buffer.asUint8List();
    }

    final out = LocalMesh();
    for (var v = 0; v < outPositions.length ~/ 3; v++) {
      out.addVertex(outPositions[v * 3], outPositions[v * 3 + 1],
          outPositions[v * 3 + 2], outUvs[v * 2], outUvs[v * 2 + 1]);
    }
    out.indices.addAll(outIndices);
    return buildGlb(out,
        pngTexture: png,
        metallic: mesh.metallic,
        roughness: mesh.roughness);
  } finally {
    mesh.dispose();
  }
}

/// Backt eine Skalierung und eine Drehung in die Geometrie.
///
/// Gedacht für die Anprobe: Wird der Gegenstand dort kleiner gestellt,
/// muss diese Änderung überall ankommen – in der eigenen Vorschau, in
/// der Roblox-Größenprüfung, im Import. Als Wurzel-Matrix am Knoten
/// wäre sie nur für Programme sichtbar, die Knoten-Transformationen
/// auswerten; die Prüfung dieser App liest die Positionen roh und hätte
/// weiter die alte Größe gemeldet. Ins Netz gebacken sehen alle
/// dasselbe.
///
/// Die Reihenfolge ist dieselbe wie bei der Anzeige: erst skalieren,
/// dann um x, y, z drehen. Normalen werden mitgedreht (bei
/// gleichmäßiger Skalierung bleibt ihre Richtung erhalten), Tangenten
/// ebenso, das w der Tangente bleibt.
///
/// Wirft, wenn das Modell ein Skelett trägt oder die Mesh-Knoten eigene
/// Transformationen haben – dann müssten Bind-Matrizen mitgerechnet
/// werden, und ein falsch gebackenes Rig zerreißt das Modell.
Uint8List bakeScaleAndRotationIntoGlb(
  Uint8List glb, {
  double scale = 1,
  double rotX = 0,
  double rotY = 0,
  double rotZ = 0,
}) {
  if (scale == 1 && rotX == 0 && rotY == 0 && rotZ == 0) return glb;
  if (scale <= 0) throw Exception('Die Größe muss über null liegen.');
  final (json, bin) = _parseGlb(glb);
  if ((json['skins'] as List?)?.isNotEmpty ?? false) {
    throw Exception('Das Modell trägt ein Skelett – Größe und Drehung '
        'lassen sich hier nicht ins Netz backen.');
  }
  for (final node in (json['nodes'] as List?) ?? []) {
    final map = node as Map;
    if (map.containsKey('mesh') &&
        (map.containsKey('rotation') ||
            map.containsKey('scale') ||
            map.containsKey('matrix'))) {
      throw Exception('Dieses Modell hat eigene Knoten-Transformationen '
          '– das Backen würde die Darstellung verfälschen.');
    }
  }
  final positions = _attributeAccessors(json, 'POSITION');
  if (positions.isEmpty) {
    throw Exception('Keine Geometrie gefunden.');
  }

  final cx = math.cos(rotX), sx = math.sin(rotX);
  final cy = math.cos(rotY), sy = math.sin(rotY);
  final cz = math.cos(rotZ), sz = math.sin(rotZ);
  void rotate(Float64List v) {
    var x = v[0], y = v[1], z = v[2];
    // x-Achse
    final y1 = y * cx - z * sx;
    final z1 = y * sx + z * cx;
    // y-Achse
    final x2 = x * cy + z1 * sy;
    final z2 = -x * sy + z1 * cy;
    // z-Achse
    final x3 = x2 * cz - y1 * sz;
    final y3 = x2 * sz + y1 * cz;
    v[0] = x3;
    v[1] = y3;
    v[2] = z2;
  }

  for (final a in positions) {
    _forEachVector(json, bin, a, 3, (v) {
      v[0] *= scale;
      v[1] *= scale;
      v[2] *= scale;
      rotate(v);
    }, write: true);
    _refreshMinMax(json, bin, a);
  }
  // Normalen nur drehen: Eine gleichmäßige Skalierung ändert ihre
  // Richtung nicht, und skalierte Normalen wären nicht mehr
  // Einheitsvektoren – die Beleuchtung würde flackern.
  for (final a in _attributeAccessors(json, 'NORMAL')) {
    _forEachVector(json, bin, a, 3, rotate, write: true);
    _refreshMinMax(json, bin, a);
  }
  for (final a in _attributeAccessors(json, 'TANGENT')) {
    _forEachVector(json, bin, a, 4, rotate, write: true);
  }
  return _writeGlb(json, bin);
}
