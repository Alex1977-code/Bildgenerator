import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/auto_rig.dart';
import '../services/glb_preview.dart';
import '../services/rig_dummy.dart';
import '../widgets/rig_dummy_view.dart';

/// Ergebnis einer Rig-Bearbeitung: die neue GLB samt der
/// Einfluss-Faktoren. Die Gelenkpositionen stecken bereits im GLB und
/// werden beim nächsten Öffnen von dort gelesen; die Faktoren wirken
/// dagegen nur auf die Gewichte und müssen mitgereicht werden.
class RigEditResult {
  const RigEditResult(this.glb, this.influence);

  final Uint8List glb;
  final Map<String, double> influence;
}

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
    this.knownFrontSign,
    this.initialJointPositions,
    this.initialInfluence,
  });

  final Uint8List unriggedGlb;
  final String rigType;
  final String title;

  /// Bekannte Blickrichtung des Modells (+1/-1) aus dem bestehenden
  /// Rig – hält den Editor konsistent zur ursprünglichen Erkennung.
  final int? knownFrontSign;

  /// Bereits angepasste Gelenkpositionen (Name → x,y,z) aus einem
  /// früheren Durchgang – ohne sie stünde beim erneuten Öffnen wieder
  /// das automatische Standard-Skelett da.
  final Map<String, (double, double, double)>? initialJointPositions;

  /// Bereits gesetzte Einfluss-Faktoren (Gelenkname → Faktor).
  final Map<String, double>? initialInfluence;

  @override
  State<RigEditScreen> createState() => _RigEditScreenState();
}

class _RigEditScreenState extends State<RigEditScreen> {
  PreviewMesh? _mesh;
  String? _error;
  List<RigJointInfo> _joints = const [];
  List<List<double>> _positions = const []; // bearbeitbare Kopie x,y,z
  int? _dragJoint;
  bool _dragMoved = false;

  /// Mehrfachauswahl: angetippte Gelenke; beim Ziehen eines
  /// ausgewählten Gelenks bewegt sich die ganze Auswahl mit.
  final Set<int> _selected = {};
  bool _symmetric = true;

  /// Unsichtbares Snap-Raster (Standard an): Gelenke rasten beim
  /// Verschieben auf feste Rasterpunkte ein – so bleiben Positionen
  /// sauber ausgerichtet.
  bool _snap = true;
  bool _applying = false;

  /// Einflussbereich je Gelenk (Faktor auf die Knochen-Radien der
  /// Abstands-Gewichtung): 1,0 = Automatik; größer = das Gelenk nimmt
  /// mehr umliegende Geometrie mit, kleiner = schärfere Abgrenzung.
  final Map<int, double> _influence = {};

  double _rotX = -0.1;
  double _rotY = 0.0;
  double _zoom = 1.0;
  double _lastScale = 1.0;
  Size _canvasSize = Size.zero;

  /// Erkannte Blickrichtung (+1 = +z, -1 = -z): richtet die
  /// Ansichts-Presets Vorn/Hinten am Gesicht des Modells aus.
  int _frontSign = 1;

  /// Gezeichnete Anleitung zum Figurtyp – zeigt seitlich, wohin die
  /// Gelenke gehören und wie weit ihr Einfluss reichen soll.
  late final RigDummy? _dummy = rigDummyFor(widget.rigType);

  /// Auf schmalen Fenstern ist für die Anleitung kein Platz; dort
  /// liegt sie hinter einem Knopf in der Titelleiste.
  bool _dummyInline = false;

  /// Name des zuletzt angetippten Gelenks – danach richtet sich, was
  /// im Dummy hervorgehoben wird.
  String? get _markedJoint {
    if (_selected.isEmpty) return null;
    final index = _selected.last;
    return index < _joints.length ? _joints[index].name : null;
  }

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
      final joints = computeAutoRigJoints(widget.unriggedGlb,
          rigType: widget.rigType,
          knownFrontSign: widget.knownFrontSign);
      if (!mounted) return;
      setState(() {
        _mesh = mesh;
        _joints = joints;
        // Vorhandene Anpassungen übernehmen, sonst die Automatik.
        final saved = widget.initialJointPositions;
        _positions = [
          for (final j in joints)
            if (saved?[j.name] case final p?)
              [p.$1, p.$2, p.$3]
            else
              [j.x, j.y, j.z],
        ];
        _influence.clear();
        final savedInfluence = widget.initialInfluence;
        if (savedInfluence != null) {
          for (var j = 0; j < joints.length; j++) {
            final factor = savedInfluence[joints[j].name];
            if (factor != null) _influence[j] = factor;
          }
        }
        _frontSign =
            widget.knownFrontSign ?? estimateFrontSign([mesh.positions]);
        _rotY = _frontSign < 0 ? math.pi : 0.0;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Rig-Editor nicht möglich: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  /// Setzt auf das automatisch berechnete Skelett zurück – verwirft
  /// also auch übernommene Anpassungen aus früheren Durchgängen.
  void _reset() => setState(() {
        _positions = [
          for (final j in _joints) [j.x, j.y, j.z],
        ];
        _selected.clear();
        _influence.clear();
      });

  /// Mittlerer Einfluss-Faktor der aktuellen Auswahl (für den Regler).
  double get _selectedInfluence {
    if (_selected.isEmpty) return 1.0;
    var sum = 0.0;
    for (final j in _selected) {
      sum += _influence[j] ?? 1.0;
    }
    return sum / _selected.length;
  }

  /// Rasterweite des unsichtbaren Snap-Rasters (1/64 der Modellgröße).
  double get _gridStep => (_mesh?.extent ?? 1) / 64;

  /// Wirksame (ggf. eingerastete) Position eines Gelenks – die rohe
  /// Position bleibt erhalten, damit auch feine Bewegungen unterhalb
  /// der Rasterweite aufsummiert werden.
  (double, double, double) _effective(int j) {
    final p = _positions[j];
    if (!_snap) return (p[0], p[1], p[2]);
    final s = _gridStep;
    return (
      (p[0] / s).round() * s,
      (p[1] / s).round() * s,
      (p[2] / s).round() * s,
    );
  }

  /// Feste Ansicht einstellen (Vorn/Hinten/Seiten).
  void _setView(double rotY) => setState(() {
        _rotX = 0;
        _rotY = rotY;
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
      final (ex, ey, ez) = _effective(j);
      final (px, py) = _project(ex, ey, ez);
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
    // Ausgewähltes Gelenk ziehen bewegt die ganze Auswahl mit.
    final moved = _selected.contains(joint)
        ? Set<int>.of(_selected)
        : {joint};
    setState(() {
      for (final j in moved) {
        _positions[j][0] += wx;
        _positions[j][1] += wy;
        _positions[j][2] += wz;
      }
      if (_symmetric) {
        final centerX = _mesh!.center[0];
        for (final j in moved) {
          final mirror = _mirrorOf(j);
          if (mirror != null && mirror != j && !moved.contains(mirror)) {
            _positions[mirror][0] = 2 * centerX - _positions[j][0];
            _positions[mirror][1] = _positions[j][1];
            _positions[mirror][2] = _positions[j][2];
          }
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
        knownFrontSign: widget.knownFrontSign,
        jointPositions: {
          for (var j = 0; j < _joints.length; j++)
            _joints[j].name: _effective(j),
        },
        jointInfluence: {
          for (final entry in _influence.entries)
            if (entry.value != 1.0) _joints[entry.key].name: entry.value,
        },
      );
      if (mounted) {
        Navigator.of(context).pop(RigEditResult(rigged, {
          for (final entry in _influence.entries)
            if (entry.value != 1.0) _joints[entry.key].name: entry.value,
        }));
      }
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
          // Auf schmalen Fenstern steht die Anleitung nicht daneben –
          // dann ist sie über diesen Knopf zu erreichen.
          if (_dummy != null && !_dummyInline)
            IconButton(
              tooltip: 'Anleitung: Wohin gehören die Gelenke?',
              icon: const Icon(Icons.help_outline),
              onPressed: _showDummyDialog,
            ),
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
              : _withDummy(theme, Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _canvasSize = Size(constraints.maxWidth,
                              constraints.maxHeight);
                          return GestureDetector(
                            onScaleStart: (details) {
                              _lastScale = 1.0;
                              _dragMoved = false;
                              _dragJoint =
                                  _jointAt(details.localFocalPoint);
                            },
                            onScaleEnd: (_) {
                              // Kurzes Antippen (ohne Ziehen) wählt das
                              // Gelenk aus bzw. ab (Mehrfachauswahl).
                              final joint = _dragJoint;
                              if (joint != null && !_dragMoved) {
                                setState(() {
                                  if (!_selected.remove(joint)) {
                                    _selected.add(joint);
                                  }
                                });
                              }
                              _dragJoint = null;
                            },
                            onScaleUpdate: (details) {
                              final joint = _dragJoint;
                              if (joint != null && details.scale == 1.0) {
                                if (details.focalPointDelta
                                        .distanceSquared >
                                    0) {
                                  _dragMoved = true;
                                }
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
                                  jointPositions: [
                                    for (var j = 0;
                                        j < _positions.length;
                                        j++)
                                      [
                                        _effective(j).$1,
                                        _effective(j).$2,
                                        _effective(j).$3,
                                      ],
                                  ],
                                  jointParents: [
                                    for (final j in _joints) j.parent,
                                  ],
                                  selected: _dragJoint,
                                  selectedJoints: _selected,
                                  jointRadii: [
                                    for (final j in _joints) j.radius,
                                  ],
                                  jointInfluence: _influence,
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
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final (label, rotY) in [
                            ('Vorn', _frontSign < 0 ? math.pi : 0.0),
                            ('Seite links', -math.pi / 2),
                            ('Seite rechts', math.pi / 2),
                            ('Hinten', _frontSign < 0 ? 0.0 : math.pi),
                          ])
                            OutlinedButton(
                              onPressed: () => _setView(rotY),
                              child: Text(label),
                            ),
                          if (_selected.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setState(_selected.clear),
                              icon: const Icon(Icons.deselect, size: 18),
                              label: Text(
                                  'Auswahl (${_selected.length}) leeren'),
                            ),
                        ],
                      ),
                    ),
                    // Kurzanleitung zum angetippten Gelenk: wohin der
                    // Punkt gehört und was er steuert.
                    if (_selected.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Card(
                          margin: EdgeInsets.zero,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                for (final index in _selected.toList()
                                  ..sort())
                                  if (index < _joints.length)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 2),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.place_outlined,
                                              size: 16,
                                              color: theme
                                                  .colorScheme.primary),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: RichText(
                                              text: TextSpan(
                                                style: theme
                                                    .textTheme.bodySmall,
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        '${_joints[index].name}: ',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight
                                                                .w600),
                                                  ),
                                                  TextSpan(
                                                      text: jointGuide(
                                                          _joints[index]
                                                              .name)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Immer sichtbar, damit die Einstellung auffindbar
                    // ist – ohne Auswahl deaktiviert mit Hinweis.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              _selected.isEmpty
                                  ? 'Einflussbereich'
                                  : 'Einflussbereich '
                                      '×${_selectedInfluence.toStringAsFixed(1)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _selected.isEmpty
                                    ? theme.colorScheme.outline
                                    : null,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _selectedInfluence
                                  .clamp(0.4, 2.5)
                                  .toDouble(),
                              min: 0.4,
                              max: 2.5,
                              divisions: 21,
                              label:
                                  '×${_selectedInfluence.toStringAsFixed(1)}',
                              onChanged: _selected.isEmpty
                                  ? null
                                  : (v) => setState(() {
                                        for (final j in _selected) {
                                          _influence[j] = v;
                                        }
                                      }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selected.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        child: Text(
                          'Zum Einstellen zuerst ein Gelenk antippen – '
                          'die blaue Kugel zeigt dann, wie weit es '
                          'greift.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Text(
                        'Antippen = Gelenk auswählen (mehrere möglich), '
                        'Ziehen = verschieben – eine Auswahl bewegt sich '
                        'gemeinsam. „Einflussbereich“ skaliert die als '
                        'blaue Kugel gezeigten Wirkungs-Radien der '
                        'Gelenke: kleiner = schärfere Abgrenzung (z. B. '
                        'Arm nimmt weniger Anzug mit), größer = weichere, '
                        'weitere Verformung. Beim Übernehmen werden '
                        'Knochen und Gewichte neu berechnet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text('Symmetrisch'),
                                  subtitle: const Text(
                                      'Links/Rechts spiegeln'),
                                  value: _symmetric,
                                  onChanged: (v) =>
                                      setState(() => _symmetric = v),
                                ),
                              ),
                              Expanded(
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text('Raster-Fang'),
                                  subtitle: const Text(
                                      'Auf unsichtbare Rasterpunkte '
                                      'einrasten'),
                                  value: _snap,
                                  onChanged: (v) =>
                                      setState(() => _snap = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
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
                          ),
                        ],
                      ),
                    ),
                  ],
                )),
    );
  }

  /// Legt die gezeichnete Anleitung neben den Editor – wenn das
  /// Fenster breit genug ist. Darunter würde die Zeichnung die
  /// 3D-Ansicht auf einen Streifen zusammendrücken; dort wandert sie
  /// hinter den Knopf in der Titelleiste.
  Widget _withDummy(ThemeData theme, Widget editor) {
    final dummy = _dummy;
    if (dummy == null) return editor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline = constraints.maxWidth >= 780;
        // Nur melden, wenn sich etwas ändert – sonst baut jeder
        // Layout-Durchlauf den Rahmen neu auf.
        if (inline != _dummyInline) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _dummyInline = inline);
          });
        }
        if (!inline) return editor;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: editor),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 260,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('So sitzen die Gelenke',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    RigDummyView(dummy: dummy, highlight: _markedJoint),
                    const SizedBox(height: 10),
                    if (_markedJoint != null)
                      Text(dummy.note, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Dieselbe Anleitung als Dialog – für schmale Fenster und Handys.
  Future<void> _showDummyDialog() async {
    final dummy = _dummy;
    if (dummy == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('So sitzen die Gelenke'),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RigDummyView(dummy: dummy, highlight: _markedJoint),
                if (_markedJoint != null) ...[
                  const SizedBox(height: 10),
                  Text(dummy.note,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
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
    required this.selectedJoints,
    required this.jointRadii,
    required this.jointInfluence,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
  });

  final PreviewMesh mesh;
  final List<List<double>> jointPositions;
  final List<int> jointParents;
  final int? selected;
  final Set<int> selectedJoints;

  /// Wirkungs-Radius je Gelenk (Faktor der Gewichtung) und die
  /// manuelle Skalierung aus dem Regler – zusammen ergeben sie die
  /// gezeichnete Kugel.
  final List<double> jointRadii;
  final Map<int, double> jointInfluence;
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
    // Wirkungsbereich der ausgewählten Gelenke als Kugel: zeigt, wie
    // weit ein Gelenk umliegende Geometrie mitnimmt. Der Regler
    // skaliert genau diesen Radius.
    final influenceFill = Paint()
      ..color = const Color(0x222962FF)
      ..style = PaintingStyle.fill;
    final influenceRing = Paint()
      ..color = const Color(0x882962FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final j in selectedJoints) {
      if (j >= jointPositions.length) continue;
      final factor = jointInfluence[j] ?? 1.0;
      final base = j < jointRadii.length ? jointRadii[j] : 1.0;
      // 9 % der Modellgröße als Bezug – dieselbe Größenordnung wie die
      // Abstände, mit denen die Gewichtung rechnet.
      final r = 0.09 * mesh.extent * base * factor * scale;
      canvas.drawCircle(Offset(jx[j], jy[j]), r, influenceFill);
      canvas.drawCircle(Offset(jx[j], jy[j]), r, influenceRing);
    }
    final jointBorder = Paint()..color = const Color(0xFFFFFFFF);
    final jointPaint = Paint()..color = const Color(0xFFE65100);
    final selectedPaint = Paint()..color = const Color(0xFF2962FF);
    for (var j = 0; j < jointPositions.length; j++) {
      final isDragged = j == selected;
      final isPicked = selectedJoints.contains(j);
      final radius = isDragged ? 8.0 : (isPicked ? 6.5 : 5.5);
      canvas.drawCircle(Offset(jx[j], jy[j]), radius, jointBorder);
      canvas.drawCircle(
          Offset(jx[j], jy[j]),
          radius - 1.8,
          (isDragged || isPicked) ? selectedPaint : jointPaint);
    }
  }

  @override
  bool shouldRepaint(_RigEditPainter oldDelegate) => true;
}
