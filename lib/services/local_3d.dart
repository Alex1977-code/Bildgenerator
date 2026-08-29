import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Eigener, komplett lokaler 3D-Generator: baut aus einem Bild ein
/// texturiertes 3D-Modell und schreibt es als binäres glTF 2.0 (GLB).
///
/// Zwei Verfahren:
/// - Relief: Helligkeit → Höhe (Landschaften, Prägungen, Lithophanie-Stil)
/// - Standee: Alpha-Silhouette → extrudierter Aufsteller
///
/// Es wird keine externe API benötigt.
class LocalMesh {
  LocalMesh()
      : positions = <double>[],
        uvs = <double>[],
        colors = <double>[],
        indices = <int>[];

  final List<double> positions; // x,y,z je Vertex
  final List<double> uvs; // u,v je Vertex
  final List<double> colors; // r,g,b je Vertex (optional statt Textur)
  final List<int> indices;

  int addVertex(double x, double y, double z, double u, double v,
      {double? r, double? g, double? b}) {
    positions.addAll([x, y, z]);
    uvs.addAll([u, v]);
    if (r != null) colors.addAll([r, g ?? r, b ?? r]);
    return positions.length ~/ 3 - 1;
  }

  void addTriangle(int a, int b, int c) => indices.addAll([a, b, c]);

  void addQuad(int a, int b, int c, int d) {
    addTriangle(a, b, c);
    addTriangle(a, c, d);
  }

  /// Glatte Normalen: Flächennormalen auf die Vertices akkumulieren.
  Float32List computeNormals() {
    final normals = Float32List(positions.length);
    for (var i = 0; i < indices.length; i += 3) {
      final ia = indices[i] * 3, ib = indices[i + 1] * 3, ic = indices[i + 2] * 3;
      final ax = positions[ia], ay = positions[ia + 1], az = positions[ia + 2];
      final bx = positions[ib], by = positions[ib + 1], bz = positions[ib + 2];
      final cx = positions[ic], cy = positions[ic + 1], cz = positions[ic + 2];
      final ux = bx - ax, uy = by - ay, uz = bz - az;
      final vx = cx - ax, vy = cy - ay, vz = cz - az;
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      for (final idx in [ia, ib, ic]) {
        normals[idx] += nx;
        normals[idx + 1] += ny;
        normals[idx + 2] += nz;
      }
    }
    for (var i = 0; i < normals.length; i += 3) {
      final len = math.sqrt(normals[i] * normals[i] +
          normals[i + 1] * normals[i + 1] +
          normals[i + 2] * normals[i + 2]);
      if (len > 1e-12) {
        normals[i] /= len;
        normals[i + 1] /= len;
        normals[i + 2] /= len;
      } else {
        normals[i + 2] = 1;
      }
    }
    return normals;
  }
}

/// Zugriff auf die RGBA-Pixel eines Bildes.
class RgbaImage {
  RgbaImage(this.bytes, this.width, this.height);

  final Uint8List bytes; // width*height*4 (RGBA)
  final int width;
  final int height;

  int _offset(double u, double v) {
    final x = (u * (width - 1)).round().clamp(0, width - 1);
    final y = (v * (height - 1)).round().clamp(0, height - 1);
    return (y * width + x) * 4;
  }

  /// Helligkeit 0–1 an normierter Position (transparent = 0).
  double luminanceAt(double u, double v) {
    final o = _offset(u, v);
    if (bytes[o + 3] < 16) return 0;
    return (0.299 * bytes[o] + 0.587 * bytes[o + 1] + 0.114 * bytes[o + 2]) /
        255.0;
  }

  bool opaqueAt(double u, double v) => bytes[_offset(u, v) + 3] > 127;

  /// Farbe (r,g,b je 0–1) an normierter Position; Grau bei Transparenz.
  (double, double, double) colorAt(double u, double v) {
    final o = _offset(u, v);
    if (bytes[o + 3] < 16) return (0.6, 0.6, 0.6);
    return (bytes[o] / 255.0, bytes[o + 1] / 255.0, bytes[o + 2] / 255.0);
  }
}

/// Relief: Höhenfeld aus der Bildhelligkeit, mit Seitenwänden und Boden.
LocalMesh buildReliefMesh(
  RgbaImage image, {
  required int resolution,
  required double depth,
  required bool invert,
}) {
  final aspect = image.height / image.width;
  final vw = (aspect <= 1 ? resolution : (resolution / aspect).round())
          .clamp(8, 256) +
      1;
  final vh = (aspect <= 1 ? (resolution * aspect).round() : resolution)
          .clamp(8, 256) +
      1;
  final ratio = image.height / image.width;

  final mesh = LocalMesh();
  double px(int x) => x / (vw - 1) - 0.5;
  double py(int y) => (0.5 - y / (vh - 1)) * ratio;

  // Deckfläche (Höhenfeld).
  for (var y = 0; y < vh; y++) {
    for (var x = 0; x < vw; x++) {
      final u = x / (vw - 1);
      final v = y / (vh - 1);
      var h = image.luminanceAt(u, v);
      if (invert) h = 1 - h;
      mesh.addVertex(px(x), py(y), 0.02 + h * depth, u, v);
    }
  }
  for (var y = 0; y < vh - 1; y++) {
    for (var x = 0; x < vw - 1; x++) {
      final a = y * vw + x;
      mesh.addQuad(a, a + 1, a + vw + 1, a + vw);
    }
  }

  // Umlaufender Rand (oben → unten auf z = 0) und Bodenplatte.
  final ring = <int>[];
  for (var x = 0; x < vw; x++) {
    ring.add(x);
  }
  for (var y = 1; y < vh; y++) {
    ring.add(y * vw + (vw - 1));
  }
  for (var x = vw - 2; x >= 0; x--) {
    ring.add((vh - 1) * vw + x);
  }
  for (var y = vh - 2; y >= 1; y--) {
    ring.add(y * vw);
  }
  final bottomRing = <int>[];
  for (final top in ring) {
    final o = top * 3;
    bottomRing.add(mesh.addVertex(mesh.positions[o], mesh.positions[o + 1], 0,
        mesh.uvs[top * 2], mesh.uvs[top * 2 + 1]));
  }
  for (var i = 0; i < ring.length; i++) {
    final j = (i + 1) % ring.length;
    mesh.addQuad(ring[i], ring[j], bottomRing[j], bottomRing[i]);
  }
  final c0 = mesh.addVertex(px(0), py(0), 0, 0, 0);
  final c1 = mesh.addVertex(px(vw - 1), py(0), 0, 1, 0);
  final c2 = mesh.addVertex(px(vw - 1), py(vh - 1), 0, 1, 1);
  final c3 = mesh.addVertex(px(0), py(vh - 1), 0, 0, 1);
  mesh.addQuad(c0, c1, c2, c3);
  return mesh;
}

/// Standee: extrudiert die Alpha-Silhouette als Aufsteller-Figur.
LocalMesh buildStandeeMesh(
  RgbaImage image, {
  required int resolution,
  required double depth,
}) {
  final aspect = image.height / image.width;
  final cw =
      (aspect <= 1 ? resolution : (resolution / aspect).round()).clamp(8, 224);
  final ch =
      (aspect <= 1 ? (resolution * aspect).round() : resolution).clamp(8, 224);
  final ratio = image.height / image.width;

  final mask = List.generate(
    ch,
    (cy) => List.generate(cw, (cx) {
      return image.opaqueAt((cx + 0.5) / cw, (cy + 0.5) / ch);
    }),
  );
  bool filled(int cx, int cy) =>
      cx >= 0 && cy >= 0 && cx < cw && cy < ch && mask[cy][cx];

  final mesh = LocalMesh();
  double px(int x) => x / cw - 0.5;
  double py(int y) => (0.5 - y / ch) * ratio;
  double u(int x) => x / cw;
  double v(int y) => y / ch;

  for (var cy = 0; cy < ch; cy++) {
    for (var cx = 0; cx < cw; cx++) {
      if (!mask[cy][cx]) continue;
      final x0 = px(cx), x1 = px(cx + 1);
      final y0 = py(cy), y1 = py(cy + 1);
      final u0 = u(cx), u1 = u(cx + 1);
      final v0 = v(cy), v1 = v(cy + 1);

      // Vorderseite (Textur) und Rückseite.
      final f0 = mesh.addVertex(x0, y0, depth, u0, v0);
      final f1 = mesh.addVertex(x1, y0, depth, u1, v0);
      final f2 = mesh.addVertex(x1, y1, depth, u1, v1);
      final f3 = mesh.addVertex(x0, y1, depth, u0, v1);
      mesh.addQuad(f0, f1, f2, f3);
      final b0 = mesh.addVertex(x0, y0, 0, u0, v0);
      final b1 = mesh.addVertex(x1, y0, 0, u1, v0);
      final b2 = mesh.addVertex(x1, y1, 0, u1, v1);
      final b3 = mesh.addVertex(x0, y1, 0, u0, v1);
      mesh.addQuad(b3, b2, b1, b0);

      // Wände an offenen Kanten.
      void wall(double ax, double ay, double bx, double by, double wu,
          double wv) {
        final t0 = mesh.addVertex(ax, ay, depth, wu, wv);
        final t1 = mesh.addVertex(bx, by, depth, wu, wv);
        final w0 = mesh.addVertex(bx, by, 0, wu, wv);
        final w1 = mesh.addVertex(ax, ay, 0, wu, wv);
        mesh.addQuad(t0, t1, w0, w1);
      }

      final mu = (u0 + u1) / 2, mv = (v0 + v1) / 2;
      if (!filled(cx, cy - 1)) wall(x0, y0, x1, y0, mu, v0);
      if (!filled(cx, cy + 1)) wall(x1, y1, x0, y1, mu, v1);
      if (!filled(cx - 1, cy)) wall(x0, y1, x0, y0, u0, mv);
      if (!filled(cx + 1, cy)) wall(x1, y0, x1, y1, u1, mv);
    }
  }
  return mesh;
}

/// Schreibt das Mesh als binäres glTF 2.0 (GLB).
///
/// Entweder mit eingebetteter PNG-Textur ([pngTexture]) oder – falls das
/// Mesh Vertex-Farben trägt – mit COLOR_0-Attribut statt Textur.
Uint8List buildGlb(LocalMesh mesh,
    {Uint8List? pngTexture, bool alphaMask = false}) {
  final positions = Float32List.fromList(mesh.positions);
  final normals = mesh.computeNormals();
  final vertexCount = positions.length ~/ 3;
  final hasTexture = pngTexture != null;
  final hasColors = !hasTexture && mesh.colors.length == vertexCount * 3;
  final indices = Uint32List.fromList(mesh.indices);

  final minPos = [double.infinity, double.infinity, double.infinity];
  final maxPos = [
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity
  ];
  for (var i = 0; i < positions.length; i += 3) {
    for (var k = 0; k < 3; k++) {
      final value = positions[i + k];
      if (value < minPos[k]) minPos[k] = value;
      if (value > maxPos[k]) maxPos[k] = value;
    }
  }

  // BIN-Teile in fester Reihenfolge; Attribute vor Indizes vor Textur.
  final binParts = <Uint8List>[
    positions.buffer.asUint8List(0, positions.lengthInBytes),
    normals.buffer.asUint8List(0, normals.lengthInBytes),
    if (hasTexture)
      Float32List.fromList(mesh.uvs)
          .buffer
          .asUint8List(0, mesh.uvs.length * 4),
    if (hasColors)
      Float32List.fromList(mesh.colors)
          .buffer
          .asUint8List(0, mesh.colors.length * 4),
    indices.buffer.asUint8List(0, indices.lengthInBytes),
    if (hasTexture) pngTexture,
  ];
  final indexPart = 2 + (hasTexture ? 1 : 0) + (hasColors ? 1 : 0);
  final texturePart = indexPart + 1;

  int pad4(int n) => (n + 3) & ~3;
  final offsets = <int>[];
  var cursor = 0;
  for (final part in binParts) {
    offsets.add(cursor);
    cursor = pad4(cursor + part.length);
  }
  final binLength = cursor;
  final bin = Uint8List(binLength);
  for (var i = 0; i < binParts.length; i++) {
    bin.setRange(offsets[i], offsets[i] + binParts[i].length, binParts[i]);
  }

  final bufferViews = <Map<String, dynamic>>[];
  for (var i = 0; i < binParts.length; i++) {
    bufferViews.add({
      'buffer': 0,
      'byteOffset': offsets[i],
      'byteLength': binParts[i].length,
      if (i < indexPart) 'target': 34962,
      if (i == indexPart) 'target': 34963,
    });
  }

  final accessors = <Map<String, dynamic>>[
    {
      'bufferView': 0,
      'componentType': 5126,
      'count': vertexCount,
      'type': 'VEC3',
      'min': minPos,
      'max': maxPos,
    },
    {
      'bufferView': 1,
      'componentType': 5126,
      'count': vertexCount,
      'type': 'VEC3',
    },
    if (hasTexture)
      {
        'bufferView': 2,
        'componentType': 5126,
        'count': vertexCount,
        'type': 'VEC2',
      },
    if (hasColors)
      {
        'bufferView': 2,
        'componentType': 5126,
        'count': vertexCount,
        'type': 'VEC3',
      },
    {
      'bufferView': indexPart,
      'componentType': 5125,
      'count': indices.length,
      'type': 'SCALAR',
    },
  ];

  final attributes = <String, int>{
    'POSITION': 0,
    'NORMAL': 1,
    if (hasTexture) 'TEXCOORD_0': 2,
    if (hasColors) 'COLOR_0': 2,
  };
  final indicesAccessor = accessors.length - 1;

  final gltf = {
    'asset': {'version': '2.0', 'generator': 'Bildgenerator (lokal)'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0]
      }
    ],
    'nodes': [
      {'mesh': 0, 'name': 'Modell'}
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': attributes,
            'indices': indicesAccessor,
            'material': 0,
          }
        ]
      }
    ],
    'materials': [
      {
        'pbrMetallicRoughness': {
          if (hasTexture) 'baseColorTexture': {'index': 0},
          if (!hasTexture) 'baseColorFactor': [1.0, 1.0, 1.0, 1.0],
          'metallicFactor': 0.0,
          'roughnessFactor': 0.9,
        },
        'doubleSided': true,
        if (alphaMask) 'alphaMode': 'MASK',
        if (alphaMask) 'alphaCutoff': 0.5,
      }
    ],
    if (hasTexture)
      'textures': [
        {'source': 0, 'sampler': 0}
      ],
    if (hasTexture)
      'samplers': [
        {'magFilter': 9729, 'minFilter': 9729, 'wrapS': 33071, 'wrapT': 33071}
      ],
    if (hasTexture)
      'images': [
        {'bufferView': texturePart, 'mimeType': 'image/png'}
      ],
    'buffers': [
      {'byteLength': binLength}
    ],
    'bufferViews': bufferViews,
    'accessors': accessors,
  };

  final jsonBytes = utf8.encode(jsonEncode(gltf));
  final jsonPadded = Uint8List(pad4(jsonBytes.length))
    ..fillRange(0, pad4(jsonBytes.length), 0x20)
    ..setRange(0, jsonBytes.length, jsonBytes);

  final total = 12 + 8 + jsonPadded.length + 8 + binLength;
  final out = ByteData(total);
  var o = 0;
  void u32(int value) {
    out.setUint32(o, value, Endian.little);
    o += 4;
  }

  u32(0x46546C67); // 'glTF'
  u32(2);
  u32(total);
  u32(jsonPadded.length);
  u32(0x4E4F534A); // 'JSON'
  out.buffer.asUint8List().setRange(o, o + jsonPadded.length, jsonPadded);
  o += jsonPadded.length;
  u32(binLength);
  u32(0x004E4942); // 'BIN\0'
  out.buffer.asUint8List().setRange(o, o + binLength, bin);
  return out.buffer.asUint8List();
}

/// Dekodiert Bildbytes zu RGBA-Pixeln plus (neu kodierter) PNG-Textur.
Future<(RgbaImage, Uint8List)> decodeForLocal3d(Uint8List imageBytes) async {
  final codec = await ui.instantiateImageCodec(imageBytes,
      targetWidth: 1024, allowUpscaling: false);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (raw == null || png == null) {
      throw Exception('Bild konnte nicht dekodiert werden.');
    }
    return (
      RgbaImage(raw.buffer.asUint8List(), image.width, image.height),
      png.buffer.asUint8List(),
    );
  } finally {
    image.dispose();
  }
}

/// Komplettpaket: Bild → GLB (Relief oder Standee).
Future<Uint8List> generateLocalGlb(
  Uint8List imageBytes, {
  required bool standee,
  required int resolution,
  required double depth,
  required bool invert,
}) async {
  final (rgba, png) = await decodeForLocal3d(imageBytes);
  final mesh = standee
      ? buildStandeeMesh(rgba, resolution: resolution, depth: depth)
      : buildReliefMesh(rgba,
          resolution: resolution, depth: depth, invert: invert);
  if (mesh.indices.isEmpty) {
    throw Exception(standee
        ? 'Keine Silhouette gefunden – das Bild braucht einen '
            'transparenten Hintergrund (im Generator-Tab mit '
            '„Transparenter Hintergrund“ erzeugen).'
        : 'Aus dem Bild ließ sich kein Relief erzeugen.');
  }
  return buildGlb(mesh, pngTexture: png, alphaMask: standee);
}

/// 360°-Modell per Visual Hull: Aus den Silhouetten von Vorder-, Seiten-
/// und Rückansicht wird ein Voxel-Volumen "geschnitzt" und als farbiges
/// Mesh (Vertex-Farben) ausgegeben.
///
/// Konvention: Alle Bilder zeigen das Objekt vor transparentem
/// Hintergrund. +z zeigt zur Vorderansicht; in der Links-Ansicht zeigt
/// die Objekt-Front im Bild nach rechts, in der Rechts-Ansicht nach links.
LocalMesh buildVisualHullMesh({
  required RgbaImage front,
  RgbaImage? left,
  RgbaImage? right,
  RgbaImage? back,
  required int resolution,
}) {
  final side = left ?? right;
  final yExtent = front.height / front.width; // xExtent = 1
  final zExtent =
      side == null ? 0.5 : (side.width / side.height) * yExtent;

  final maxExtent = math.max(1.0, math.max(yExtent, zExtent));
  final cell = maxExtent / resolution;
  final nx = (1.0 / cell).round().clamp(4, 200);
  final ny = (yExtent / cell).round().clamp(4, 200);
  final nz = (zExtent / cell).round().clamp(4, 200);

  // Silhouetten-Test im Objektraum (x,y,z jeweils 0..Extent).
  bool solidAt(double x, double y, double z) {
    final uF = x; // 0..1
    final vF = 1 - y / yExtent;
    if (!front.opaqueAt(uF, vF)) return false;
    if (back != null && !back.opaqueAt(1 - uF, vF)) return false;
    if (left != null && !left.opaqueAt(z / zExtent, vF)) return false;
    if (right != null && !right.opaqueAt(1 - z / zExtent, vF)) {
      return false;
    }
    return true;
  }

  final solid = List.generate(
    nx,
    (ix) => List.generate(ny, (iy) {
      final row = List<bool>.filled(nz, false);
      for (var iz = 0; iz < nz; iz++) {
        row[iz] = solidAt(
          (ix + 0.5) / nx,
          (iy + 0.5) / ny * yExtent,
          (iz + 0.5) / nz * zExtent,
        );
      }
      return row;
    }),
  );
  bool filled(int ix, int iy, int iz) =>
      ix >= 0 &&
      iy >= 0 &&
      iz >= 0 &&
      ix < nx &&
      iy < ny &&
      iz < nz &&
      solid[ix][iy][iz];

  // Farbwahl je Blickrichtung der Fläche.
  (double, double, double) faceColor(
      int axis, int dir, double x, double y, double z) {
    final uF = x, vF = 1 - y / yExtent;
    if (axis == 2) {
      if (dir > 0) return front.colorAt(uF, vF);
      return (back ?? front).colorAt(back != null ? 1 - uF : uF, vF);
    }
    if (axis == 0) {
      if (dir < 0 && left != null) return left.colorAt(z / zExtent, vF);
      if (dir > 0 && right != null) {
        return right.colorAt(1 - z / zExtent, vF);
      }
      final mirror = left ?? right;
      if (mirror != null) {
        return mirror.colorAt(
            left != null ? z / zExtent : 1 - z / zExtent, vF);
      }
    }
    return front.colorAt(uF, vF);
  }

  final mesh = LocalMesh();
  final sx = 1.0 / nx, sy = yExtent / ny, sz = zExtent / nz;
  void addFace(List<List<double>> corners, (double, double, double) color) {
    final (r, g, b) = color;
    final ids = [
      for (final c in corners)
        mesh.addVertex(c[0] - 0.5, c[1] - yExtent / 2, c[2] - zExtent / 2,
            0, 0,
            r: r, g: g, b: b)
    ];
    mesh.addQuad(ids[0], ids[1], ids[2], ids[3]);
  }

  for (var ix = 0; ix < nx; ix++) {
    for (var iy = 0; iy < ny; iy++) {
      for (var iz = 0; iz < nz; iz++) {
        if (!solid[ix][iy][iz]) continue;
        final x0 = ix * sx, x1 = x0 + sx;
        final y0 = iy * sy, y1 = y0 + sy;
        final z0 = iz * sz, z1 = z0 + sz;
        final cx = x0 + sx / 2, cy = y0 + sy / 2, cz = z0 + sz / 2;
        if (!filled(ix, iy, iz + 1)) {
          addFace([
            [x0, y0, z1],
            [x1, y0, z1],
            [x1, y1, z1],
            [x0, y1, z1],
          ], faceColor(2, 1, cx, cy, cz));
        }
        if (!filled(ix, iy, iz - 1)) {
          addFace([
            [x1, y0, z0],
            [x0, y0, z0],
            [x0, y1, z0],
            [x1, y1, z0],
          ], faceColor(2, -1, cx, cy, cz));
        }
        if (!filled(ix + 1, iy, iz)) {
          addFace([
            [x1, y0, z1],
            [x1, y0, z0],
            [x1, y1, z0],
            [x1, y1, z1],
          ], faceColor(0, 1, cx, cy, cz));
        }
        if (!filled(ix - 1, iy, iz)) {
          addFace([
            [x0, y0, z0],
            [x0, y0, z1],
            [x0, y1, z1],
            [x0, y1, z0],
          ], faceColor(0, -1, cx, cy, cz));
        }
        if (!filled(ix, iy + 1, iz)) {
          addFace([
            [x0, y1, z1],
            [x1, y1, z1],
            [x1, y1, z0],
            [x0, y1, z0],
          ], faceColor(1, 1, cx, cy, cz));
        }
        if (!filled(ix, iy - 1, iz)) {
          addFace([
            [x0, y0, z0],
            [x1, y0, z0],
            [x1, y0, z1],
            [x0, y0, z1],
          ], faceColor(1, -1, cx, cy, cz));
        }
      }
    }
  }
  return mesh;
}

/// Komplettpaket: bis zu vier Ansichten → farbiges 360°-GLB.
Future<Uint8List> generateLocalHullGlb({
  required Uint8List frontBytes,
  Uint8List? leftBytes,
  Uint8List? rightBytes,
  Uint8List? backBytes,
  required int resolution,
}) async {
  Future<RgbaImage?> decode(Uint8List? bytes) async {
    if (bytes == null) return null;
    final (rgba, _) = await decodeForLocal3d(bytes);
    return rgba;
  }

  final front = (await decode(frontBytes))!;
  final mesh = buildVisualHullMesh(
    front: front,
    left: await decode(leftBytes),
    right: await decode(rightBytes),
    back: await decode(backBytes),
    resolution: resolution,
  );
  if (mesh.indices.isEmpty) {
    throw Exception(
        'Keine Silhouette gefunden – die Ansichten brauchen einen '
        'transparenten Hintergrund (im Generator-Tab mit „Transparenter '
        'Hintergrund“ erzeugen).');
  }
  return buildGlb(mesh);
}
