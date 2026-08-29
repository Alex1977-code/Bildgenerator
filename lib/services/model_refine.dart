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
