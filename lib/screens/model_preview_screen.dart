import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/exporter.dart';
import '../services/glb_preview.dart';

/// Frei drehbare 3D-Vorschau eines GLB-Modells (eigener Software-Renderer,
/// läuft auf allen Plattformen inklusive Windows).
class ModelPreviewScreen extends StatefulWidget {
  const ModelPreviewScreen({
    super.key,
    required this.glbBytes,
    required this.title,
  });

  final Uint8List glbBytes;
  final String title;

  @override
  State<ModelPreviewScreen> createState() => _ModelPreviewScreenState();
}

class _ModelPreviewScreenState extends State<ModelPreviewScreen> {
  PreviewMesh? _mesh;
  String? _error;

  double _rotX = -0.35;
  double _rotY = 0.6;
  double _zoom = 1.0;
  double _lastScale = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mesh = await parseGlbForPreview(widget.glbBytes);
      if (mounted) setState(() => _mesh = mesh);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Vorschau nicht möglich: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  void _resetView() {
    setState(() {
      _rotX = -0.35;
      _rotY = 0.6;
      _zoom = 1.0;
    });
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await exportImageBytes(
        widget.glbBytes,
        'modell_${DateTime.now().millisecondsSinceEpoch}.glb',
        'model/gltf-binary',
      );
      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mesh = _mesh;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ansicht zurücksetzen',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetView,
          ),
          IconButton(
            tooltip: 'GLB exportieren',
            icon: const Icon(Icons.download),
            onPressed: _export,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : mesh == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent) {
                            setState(() {
                              _zoom = (_zoom *
                                      (event.scrollDelta.dy > 0
                                          ? 0.9
                                          : 1.1))
                                  .clamp(0.3, 8.0);
                            });
                          }
                        },
                        child: GestureDetector(
                          onScaleStart: (_) => _lastScale = 1.0,
                          onScaleUpdate: (details) {
                            setState(() {
                              _rotY +=
                                  details.focalPointDelta.dx * 0.01;
                              _rotX +=
                                  details.focalPointDelta.dy * 0.01;
                              _rotX = _rotX.clamp(-math.pi, math.pi);
                              if (details.scale != 1.0) {
                                _zoom = (_zoom *
                                        (details.scale / _lastScale))
                                    .clamp(0.3, 8.0);
                                _lastScale = details.scale;
                              }
                            });
                          },
                          child: ClipRect(
                            child: CustomPaint(
                              painter: _MeshPainter(
                                mesh: mesh,
                                rotX: _rotX,
                                rotY: _rotY,
                                zoom: _zoom,
                                background:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Ziehen = drehen · Zwei Finger/Mausrad = zoomen · '
                        '${mesh.triangleCount} Dreiecke',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.mesh,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
  });

  final PreviewMesh mesh;
  final double rotX;
  final double rotY;
  final double zoom;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final scale = 0.42 * math.min(size.width, size.height) /
        mesh.extent *
        zoom;
    final cx = size.width / 2, cy = size.height / 2;

    final vertexCount = mesh.vertexCount;
    final sx = Float32List(vertexCount);
    final sy = Float32List(vertexCount);
    final sz = Float32List(vertexCount);
    final positions = mesh.positions;
    final centerX = mesh.center[0],
        centerY = mesh.center[1],
        centerZ = mesh.center[2];
    for (var i = 0; i < vertexCount; i++) {
      final x = positions[i * 3] - centerX;
      final y = positions[i * 3 + 1] - centerY;
      final z = positions[i * 3 + 2] - centerZ;
      // Erst um Y, dann um X drehen.
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      final y2 = y * cosX - z1 * sinX;
      final z2 = y * sinX + z1 * cosX;
      sx[i] = cx + x1 * scale;
      sy[i] = cy - y2 * scale;
      sz[i] = z2;
    }

    // Maler-Algorithmus: entfernte Dreiecke zuerst.
    final indices = mesh.indices;
    final triangleCount = indices.length ~/ 3;
    final order = List<int>.generate(triangleCount, (i) => i);
    final depth = Float32List(triangleCount);
    for (var t = 0; t < triangleCount; t++) {
      depth[t] = sz[indices[t * 3]] +
          sz[indices[t * 3 + 1]] +
          sz[indices[t * 3 + 2]];
    }
    order.sort((a, b) => depth[a].compareTo(depth[b]));

    final outPositions = Float32List(triangleCount * 6);
    final outColors = Int32List(triangleCount * 3);
    var p = 0, c = 0;
    for (final t in order) {
      final ia = indices[t * 3], ib = indices[t * 3 + 1], ic = indices[t * 3 + 2];
      // Beleuchtung aus der Bildschirm-Normalen (flach schattiert).
      final ux = sx[ib] - sx[ia], uy = sy[ib] - sy[ia], uz = sz[ib] - sz[ia];
      final vx = sx[ic] - sx[ia], vy = sy[ic] - sy[ia], vz = sz[ic] - sz[ia];
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      final intensity =
          length < 1e-9 ? 1.0 : 0.35 + 0.65 * (nz.abs() / length);

      for (final vi in [ia, ib, ic]) {
        outPositions[p++] = sx[vi];
        outPositions[p++] = sy[vi];
        final color = mesh.colors[vi];
        final r = ((color >> 16) & 0xFF) * intensity;
        final g = ((color >> 8) & 0xFF) * intensity;
        final b = (color & 0xFF) * intensity;
        outColors[c++] = 0xFF000000 |
            (r.round().clamp(0, 255) << 16) |
            (g.round().clamp(0, 255) << 8) |
            b.round().clamp(0, 255);
      }
    }

    final vertices =
        ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
            colors: outColors);
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.rotX != rotX ||
      oldDelegate.rotY != rotY ||
      oldDelegate.zoom != zoom ||
      oldDelegate.background != background;
}
