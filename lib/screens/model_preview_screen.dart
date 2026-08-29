import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/animation_bake.dart';
import '../services/exporter.dart';
import '../services/glb_preview.dart';
import '../services/preview_animations.dart';

/// Frei drehbare 3D-Vorschau eines GLB-Modells (eigener Software-Renderer,
/// läuft auf allen Plattformen inklusive Windows). Geriggte Modelle
/// lassen sich direkt animieren (Clips aus der Datei oder eingebaute
/// Testanimationen), das Skelett kann grafisch eingeblendet werden.
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

class _ModelPreviewScreenState extends State<ModelPreviewScreen>
    with SingleTickerProviderStateMixin {
  PreviewMesh? _mesh;
  String? _error;

  double _rotX = -0.35;
  double _rotY = 0.6;
  double _zoom = 1.0;
  double _lastScale = 1.0;

  late final Ticker _ticker = createTicker(_onTick);
  List<PreviewAnimation> _fileClips = const [];
  List<ProceduralClip> _procClips = const [];

  /// -1 = Standbild; 0..fileClips-1 = Clip aus der Datei; danach die
  /// eingebauten Testanimationen.
  int _clipIndex = -1;
  bool _playing = false;
  bool _showSkeleton = false;
  double _time = 0;
  Float32List? _posedPositions;
  Float32List? _jointPositions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final mesh = await parseGlbForPreview(widget.glbBytes);
      if (!mounted) return;
      setState(() {
        _mesh = mesh;
        final rig = mesh.rig;
        if (rig != null) {
          _fileClips = rig.animations;
          _procClips = proceduralClipsFor(rig);
          _jointPositions = computeJointPositions(mesh);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Vorschau nicht möglich: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  bool get _hasClips => _fileClips.isNotEmpty || _procClips.isNotEmpty;

  /// Aktualisiert die Pose (Vertices + Gelenkpositionen) für [_time].
  void _computePose() {
    final mesh = _mesh;
    if (mesh == null || mesh.rig == null) return;
    PreviewAnimation? animation;
    Map<int, Float32List>? overrides;
    if (_clipIndex >= 0 && _clipIndex < _fileClips.length) {
      animation = _fileClips[_clipIndex];
    } else if (_clipIndex >= _fileClips.length &&
        _clipIndex < _fileClips.length + _procClips.length) {
      overrides = _procClips[_clipIndex - _fileClips.length].poseAt(_time);
    }
    _posedPositions = _clipIndex < 0
        ? null
        : computeSkinnedPositions(mesh,
            animation: animation, time: _time, rotationOverrides: overrides);
    _jointPositions = computeJointPositions(mesh,
        animation: animation, time: _time, rotationOverrides: overrides);
  }

  void _onTick(Duration elapsed) {
    if (_mesh?.rig == null || _clipIndex < 0) return;
    _time = elapsed.inMicroseconds / 1e6;
    setState(_computePose);
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        if (_clipIndex < 0 && _hasClips) _clipIndex = 0;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    });
  }

  void _selectClip(int index) {
    setState(() {
      _clipIndex = index;
      _time = 0;
      if (index < 0) {
        _ticker.stop();
        _playing = false;
      } else if (!_playing) {
        _playing = true;
        _ticker.start();
      }
      _computePose();
    });
  }

  void _resetView() {
    setState(() {
      _rotX = -0.35;
      _rotY = 0.6;
      _zoom = 1.0;
    });
  }

  Future<void> _export({bool withAnimations = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var bytes = widget.glbBytes;
      var prefix = 'modell';
      if (withAnimations && _procClips.isNotEmpty) {
        bytes = bakeAnimationsIntoGlb(bytes, _procClips);
        prefix = 'modell_animiert';
        messenger.showSnackBar(SnackBar(
            content: Text('${_procClips.length} Testanimationen als '
                'Loop-Clips eingebettet.')));
      }
      final message = await exportImageBytes(
        bytes,
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}.glb',
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
    final rig = mesh?.rig;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (rig != null)
            IconButton(
              tooltip: _showSkeleton
                  ? 'Skelett ausblenden'
                  : 'Skelett anzeigen',
              icon: Icon(
                Icons.polyline,
                color: _showSkeleton ? theme.colorScheme.primary : null,
              ),
              onPressed: () =>
                  setState(() => _showSkeleton = !_showSkeleton),
            ),
          IconButton(
            tooltip: 'Ansicht zurücksetzen',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetView,
          ),
          if (_procClips.isEmpty)
            IconButton(
              tooltip: 'GLB exportieren',
              icon: const Icon(Icons.download),
              onPressed: _export,
            )
          else
            PopupMenuButton<bool>(
              tooltip: 'GLB exportieren',
              icon: const Icon(Icons.download),
              onSelected: (withAnimations) =>
                  _export(withAnimations: withAnimations),
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: false, child: Text('GLB exportieren')),
                PopupMenuItem(
                    value: true,
                    child: Text('GLB + Testanimationen exportieren')),
              ],
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
                                positions:
                                    _posedPositions ?? mesh.positions,
                                skeleton:
                                    _showSkeleton ? _jointPositions : null,
                                skeletonParents: rig?.jointParents,
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
                    if (rig != null && _hasClips)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 4, 12, 0),
                        child: Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip:
                                  _playing ? 'Pause' : 'Abspielen',
                              icon: Icon(_playing
                                  ? Icons.pause
                                  : Icons.play_arrow),
                              onPressed: _togglePlay,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownMenu<int>(
                                key: ValueKey('clip-$_clipIndex'),
                                initialSelection: _clipIndex,
                                label: const Text('Animation'),
                                expandedInsets: EdgeInsets.zero,
                                dropdownMenuEntries: [
                                  const DropdownMenuEntry(
                                      value: -1,
                                      label: 'Keine (Standbild)'),
                                  for (var i = 0;
                                      i < _fileClips.length;
                                      i++)
                                    DropdownMenuEntry(
                                        value: i,
                                        label: _fileClips[i].name),
                                  for (var i = 0;
                                      i < _procClips.length;
                                      i++)
                                    DropdownMenuEntry(
                                        value: _fileClips.length + i,
                                        label:
                                            '${_procClips[i].name} (Test)'),
                                ],
                                onSelected: (value) {
                                  if (value != null) _selectClip(value);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Ziehen = drehen · Zwei Finger/Mausrad = zoomen · '
                        '${mesh.triangleCount} Dreiecke'
                        '${rig != null ? ' · ${rig.joints.length} Gelenke' : ''}',
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
    required this.positions,
    required this.skeleton,
    required this.skeletonParents,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
  });

  final PreviewMesh mesh;
  final Float32List positions;
  final Float32List? skeleton; // x,y,z je Gelenk (Weltkoordinaten)
  final List<int>? skeletonParents;
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
    final centerX = mesh.center[0],
        centerY = mesh.center[1],
        centerZ = mesh.center[2];

    (double, double, double) project(double x0, double y0, double z0) {
      final x = x0 - centerX;
      final y = y0 - centerY;
      final z = z0 - centerZ;
      // Erst um Y, dann um X drehen.
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      final y2 = y * cosX - z1 * sinX;
      final z2 = y * sinX + z1 * cosX;
      return (cx + x1 * scale, cy - y2 * scale, z2);
    }

    final vertexCount = positions.length ~/ 3;
    final sx = Float32List(vertexCount);
    final sy = Float32List(vertexCount);
    final sz = Float32List(vertexCount);
    for (var i = 0; i < vertexCount; i++) {
      final (px, py, pz) = project(positions[i * 3], positions[i * 3 + 1],
          positions[i * 3 + 2]);
      sx[i] = px;
      sy[i] = py;
      sz[i] = pz;
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

    // Skelett-Overlay: Knochenlinien und Gelenkpunkte über dem Modell.
    final joints = skeleton;
    final parents = skeletonParents;
    if (joints != null && parents != null) {
      final jointCount = joints.length ~/ 3;
      final jx = Float32List(jointCount);
      final jy = Float32List(jointCount);
      for (var j = 0; j < jointCount; j++) {
        final (px, py, _) = project(
            joints[j * 3], joints[j * 3 + 1], joints[j * 3 + 2]);
        jx[j] = px;
        jy[j] = py;
      }
      final bonePaint = Paint()
        ..color = const Color(0xFFFFB300)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (var j = 0; j < jointCount; j++) {
        final parent = parents[j];
        if (parent < 0) continue;
        canvas.drawLine(Offset(jx[parent], jy[parent]),
            Offset(jx[j], jy[j]), bonePaint);
      }
      final jointPaint = Paint()..color = const Color(0xFFE65100);
      final jointBorder = Paint()..color = const Color(0xFFFFFFFF);
      for (var j = 0; j < jointCount; j++) {
        canvas.drawCircle(Offset(jx[j], jy[j]), 4.5, jointBorder);
        canvas.drawCircle(Offset(jx[j], jy[j]), 3.2, jointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.positions != positions ||
      oldDelegate.skeleton != skeleton ||
      oldDelegate.rotX != rotX ||
      oldDelegate.rotY != rotY ||
      oldDelegate.zoom != zoom ||
      oldDelegate.background != background;
}
