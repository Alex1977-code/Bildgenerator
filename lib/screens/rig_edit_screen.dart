import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/auto_rig.dart';
import '../services/glb_preview.dart';

/// Rig-Editor: zeigt das (ungeriggte) Modell mit den automatisch
/// bestimmten Gelenken und lässt sie per Ziehen verschieben. Beim
/// Übernehmen wird das Skelett mit den angepassten Positionen neu ins
/// GLB eingebaut – Knochen und Skin-Gewichte werden dabei aus den
/// verschobenen Gelenken neu berechnet.
class RigEditScreen extends StatefulWidget {
  const RigEditScreen({
    super.key,
    required this.unriggedGlb,
    required this.rigType,
    required this.title,
  });

  final Uint8List unriggedGlb;
  final String rigType;
  final String title;

  @override
  State<RigEditScreen> createState() => _RigEditScreenState();
}

class _RigEditScreenState extends State<RigEditScreen> {
  PreviewMesh? _mesh;
  String? _error;
  List<RigJointInfo> _joints = const [];
  List<List<double>> _positions = const []; // bearbeitbare Kopie x,y,z
  int? _dragJoint;
  bool _symmetric = true;
  bool _applying = false;

  double _rotX = -0.1;
  double _rotY = 0.0;
  double _zoom = 1.0;
  double _lastScale = 1.0;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mesh?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final mesh = await parseGlbForPreview(widget.unriggedGlb);
      final joints =
          computeAutoRigJoints(widget.unriggedGlb, rigType: widget.rigType);
      if (!mounted) return;
      setState(() {
        _mesh = mesh;
        _joints = joints;
        _positions = [
          for (final j in joints) [j.x, j.y, j.z],
        ];
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Rig-Editor nicht möglich: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  void _reset() => setState(() {
        _positions = [
          for (final j in _joints) [j.x, j.y, j.z],
        ];
      });

  double get _scale {
    final mesh = _mesh;
    if (mesh == null || _canvasSize == Size.zero) return 1;
    return 0.42 *
        math.min(_canvasSize.width, _canvasSize.height) /
        mesh.extent *
        _zoom;
  }

  (double, double) _project(double x0, double y0, double z0) {
    final mesh = _mesh!;
    final cosY = math.cos(_rotY), sinY = math.sin(_rotY);
    final cosX = math.cos(_rotX), sinX = math.sin(_rotX);
    final x = x0 - mesh.center[0];
    final y = y0 - mesh.center[1];
    final z = z0 - mesh.center[2];
    final x1 = x * cosY + z * sinY;
    final z1 = -x * sinY + z * cosY;
    final y2 = y * cosX - z1 * sinX;
    return (
      _canvasSize.width / 2 + x1 * _scale,
      _canvasSize.height / 2 - y2 * _scale,
    );
  }

  int? _jointAt(Offset position) {
    if (_mesh == null) return null;
    int? best;
    var bestDist = 24.0 * 24.0;
    for (var j = 0; j < _positions.length; j++) {
      final (px, py) = _project(
          _positions[j][0], _positions[j][1], _positions[j][2]);
      final dx = px - position.dx, dy = py - position.dy;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = j;
      }
    }
    return best;
  }

  /// Spiegel-Gelenk (…_L ↔ …_R) für symmetrisches Bearbeiten.
  int? _mirrorOf(int joint) {
    final name = _joints[joint].name;
    String? other;
    if (name.endsWith('_L')) {
      other = '${name.substring(0, name.length - 2)}_R';
    } else if (name.endsWith('_R')) {
      other = '${name.substring(0, name.length - 2)}_L';
    }
    if (other == null) return null;
    for (var j = 0; j < _joints.length; j++) {
      if (_joints[j].name == other) return j;
    }
    return null;
  }

  void _moveJoint(int joint, Offset delta) {
    final cosY = math.cos(_rotY), sinY = math.sin(_rotY);
    final cosX = math.cos(_rotX), sinX = math.sin(_rotX);
    final dxw = delta.dx / _scale;
    final dyw = -delta.dy / _scale;
    // Bildschirm-Delta zurück in Weltkoordinaten drehen (Bewegung in
    // der Kameraebene; für die Tiefe die Ansicht drehen).
    final wx = dxw * cosY + dyw * sinX * sinY;
    final wy = dyw * cosX;
    final wz = dxw * sinY - dyw * sinX * cosY;
    setState(() {
      _positions[joint][0] += wx;
      _positions[joint][1] += wy;
      _positions[joint][2] += wz;
      if (_symmetric) {
        final mirror = _mirrorOf(joint);
        if (mirror != null && mirror != joint) {
          final centerX = _mesh!.center[0];
          _positions[mirror][0] = 2 * centerX - _positions[joint][0];
          _positions[mirror][1] = _positions[joint][1];
          _positions[mirror][2] = _positions[joint][2];
        }
      }
    });
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final rigged = injectAutoRig(
        widget.unriggedGlb,
        rigType: widget.rigType,
        jointPositions: {
          for (var j = 0; j < _joints.length; j++)
            _joints[j].name: (
              _positions[j][0],
              _positions[j][1],
              _positions[j][2],
            ),
        },
      );
      if (mounted) Navigator.of(context).pop(rigged);
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Skelett-Einbau fehlgeschlagen: '
                '${e.toString().replaceFirst('Exception: ', '')}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mesh = _mesh;
    return Scaffold(
      appBar: AppBar(
        title: Text('Rig anpassen – ${widget.title}',
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Gelenke zurücksetzen',
            icon: const Icon(Icons.restart_alt),
            onPressed: _joints.isEmpty ? null : _reset,
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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _canvasSize = Size(constraints.maxWidth,
                              constraints.maxHeight);
                          return GestureDetector(
                            onScaleStart: (details) {
                              _lastScale = 1.0;
                              _dragJoint =
                                  _jointAt(details.localFocalPoint);
                            },
                            onScaleEnd: (_) => _dragJoint = null,
                            onScaleUpdate: (details) {
                              final joint = _dragJoint;
                              if (joint != null && details.scale == 1.0) {
                                _moveJoint(
                                    joint, details.focalPointDelta);
                                return;
                              }
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
                                painter: _RigEditPainter(
                                  mesh: mesh,
                                  jointPositions: _positions,
                                  jointParents: [
                                    for (final j in _joints) j.parent,
                                  ],
                                  selected: _dragJoint,
                                  rotX: _rotX,
                                  rotY: _rotY,
                                  zoom: _zoom,
                                  background: theme
                                      .colorScheme.surfaceContainerHighest,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Text(
                        'Gelenk antippen und ziehen – die Bewegung folgt '
                        'der Bildschirmebene; für die Tiefe die Ansicht '
                        'vorher drehen. Leere Fläche ziehen = drehen. '
                        'Beim Übernehmen werden Knochen und Gewichte aus '
                        'den neuen Gelenkpositionen neu berechnet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Symmetrisch'),
                              subtitle: const Text(
                                  'Links/Rechts spiegeln (…_L ↔ …_R)'),
                              value: _symmetric,
                              onChanged: (v) =>
                                  setState(() => _symmetric = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _applying ? null : _apply,
                            icon: _applying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.check),
                            label: const Text('Skelett übernehmen'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _RigEditPainter extends CustomPainter {
  _RigEditPainter({
    required this.mesh,
    required this.jointPositions,
    required this.jointParents,
    required this.selected,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
  });

  final PreviewMesh mesh;
  final List<List<double>> jointPositions;
  final List<int> jointParents;
  final int? selected;
  final double rotX;
  final double rotY;
  final double zoom;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final scale =
        0.42 * math.min(size.width, size.height) / mesh.extent * zoom;
    final cx = size.width / 2, cy = size.height / 2;

    (double, double, double) project(double x0, double y0, double z0) {
      final x = x0 - mesh.center[0];
      final y = y0 - mesh.center[1];
      final z = z0 - mesh.center[2];
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      final y2 = y * cosX - z1 * sinX;
      final z2 = y * sinX + z1 * cosX;
      return (cx + x1 * scale, cy - y2 * scale, z2);
    }

    // Modell halbtransparent als Orientierung (Vertex-Farben mit
    // einfacher Beleuchtung, Maler-Algorithmus).
    final positions = mesh.positions;
    final normals = mesh.normals;
    final indices = mesh.indices;
    final vertexCount = positions.length ~/ 3;
    final sx = Float32List(vertexCount);
    final sy = Float32List(vertexCount);
    final sz = Float32List(vertexCount);
    final shade = Float32List(vertexCount);
    for (var i = 0; i < vertexCount; i++) {
      final (px, py, pz) = project(positions[i * 3],
          positions[i * 3 + 1], positions[i * 3 + 2]);
      sx[i] = px;
      sy[i] = py;
      sz[i] = pz;
      final nx = normals[i * 3],
          ny = normals[i * 3 + 1],
          nz = normals[i * 3 + 2];
      final x1 = nx * cosY + nz * sinY;
      final z1 = -nx * sinY + nz * cosY;
      final y2 = ny * cosX - z1 * sinX;
      final z2 = ny * sinX + z1 * cosX;
      var dot = (-0.26 * x1 + 0.44 * y2 + 0.86 * z2).abs();
      if (dot > 1) dot = 1;
      shade[i] = 0.42 + 0.58 * dot;
    }
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
      for (final vi in [
        indices[t * 3],
        indices[t * 3 + 1],
        indices[t * 3 + 2]
      ]) {
        outPositions[p++] = sx[vi];
        outPositions[p++] = sy[vi];
        final color = mesh.colors[vi];
        final s = shade[vi];
        outColors[c++] = 0xD0000000 |
            ((((color >> 16) & 0xFF) * s).round().clamp(0, 255) << 16) |
            ((((color >> 8) & 0xFF) * s).round().clamp(0, 255) << 8) |
            ((color & 0xFF) * s).round().clamp(0, 255);
      }
    }
    canvas.drawVertices(
      ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
          colors: outColors),
      BlendMode.dst,
      Paint(),
    );

    // Skelett darüber: Knochenlinien + Gelenkpunkte (ausgewähltes
    // Gelenk hervorgehoben).
    final jx = Float32List(jointPositions.length);
    final jy = Float32List(jointPositions.length);
    for (var j = 0; j < jointPositions.length; j++) {
      final (px, py, _) = project(jointPositions[j][0],
          jointPositions[j][1], jointPositions[j][2]);
      jx[j] = px;
      jy[j] = py;
    }
    final bonePaint = Paint()
      ..color = const Color(0xFFFFB300)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var j = 0; j < jointPositions.length; j++) {
      final parent = jointParents[j];
      if (parent < 0) continue;
      canvas.drawLine(Offset(jx[parent], jy[parent]),
          Offset(jx[j], jy[j]), bonePaint);
    }
    final jointBorder = Paint()..color = const Color(0xFFFFFFFF);
    final jointPaint = Paint()..color = const Color(0xFFE65100);
    final selectedPaint = Paint()..color = const Color(0xFF2962FF);
    for (var j = 0; j < jointPositions.length; j++) {
      final isSelected = j == selected;
      canvas.drawCircle(
          Offset(jx[j], jy[j]), isSelected ? 8.0 : 5.5, jointBorder);
      canvas.drawCircle(Offset(jx[j], jy[j]), isSelected ? 6.2 : 4.0,
          isSelected ? selectedPaint : jointPaint);
    }
  }

  @override
  bool shouldRepaint(_RigEditPainter oldDelegate) => true;
}
