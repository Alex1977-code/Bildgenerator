import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/glb_preview.dart';
import '../services/item_fit.dart';
import '../services/item_prompt.dart';
import '../services/roblox_accessory.dart';
import '../widgets/mesh_painter.dart';

/// Figur und Gegenstand zusammen – und der Gegenstand daran anpassbar.
///
/// Bis hierher entstanden beide getrennt, und ob das Schwert in der
/// Hand liegt, sah man erst in Studio. Hier stehen sie nebeneinander
/// im selben Maßstab: die Figur grau, der Gegenstand farbig, mit
/// Reglern für Größe, Lage und Drehung.
///
/// Gezeichnet wird bewusst **ohne Textur**. Beim Anpassen zählt die
/// Silhouette – wo sitzt es, wie groß ist es, steht es richtig herum.
/// Eine Textur würde genau das überdecken.
class ItemFitScreen extends StatefulWidget {
  const ItemFitScreen({
    super.key,
    required this.figureGlb,
    required this.itemGlb,
    required this.kind,
    required this.itemLabel,
  });

  final Uint8List figureGlb;
  final Uint8List itemGlb;
  final ItemKind kind;
  final String itemLabel;

  @override
  State<ItemFitScreen> createState() => _ItemFitScreenState();
}

class _ItemFitScreenState extends State<ItemFitScreen> {
  PreviewMesh? _figure;
  PreviewMesh? _item;
  String? _error;

  ItemPlacement _placement = const ItemPlacement();
  (double, double, double) _anchor = (0, 0, 0);
  String _anchorSource = '';
  double _figureHeight = 1;
  double _itemLongest = 1;
  AccessoryFit? _fit;

  /// Deckkraft der Figur. Voreingestellt halb durchsichtig: So ist
  /// zu sehen, wo am Körper man ist, und der Gegenstand bleibt auch
  /// dann erkennbar, wenn er dahinter oder darin liegt.
  double _figureOpacity = 0.5;

  double _rotX = -0.2;
  double _rotY = 0.6;
  double _zoom = 1.0;
  double _lastScale = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _figure?.dispose();
    _item?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final figure = await parseGlbForPreview(widget.figureGlb);
      final item = await parseGlbForPreview(widget.itemGlb);
      // Gelenke der Figur, wenn sie ein Skelett hat.
      final joints = <String, (double, double, double)>{};
      final rig = figure.rig;
      if (rig != null) {
        final world = computeJointPositions(figure);
        for (var i = 0; i < rig.joints.length; i++) {
          final name = rig.nodes[rig.joints[i]].name;
          if (name.isEmpty) continue;
          joints[name] =
              (world[i * 3], world[i * 3 + 1], world[i * 3 + 2]);
        }
      }
      final box = _bounds(figure.positions);
      final anchors = figureAnchors(
        minY: box.$3,
        maxY: box.$4,
        minZ: box.$5,
        maxZ: box.$6,
        halfWidth: (box.$2 - box.$1) / 2,
      );
      final (anchor, source) = attachPointFor(
        kind: widget.kind,
        joints: joints,
        anchors: anchors,
      );
      final itemBox = _bounds(item.positions);
      final longest = [
        itemBox.$2 - itemBox.$1,
        itemBox.$4 - itemBox.$3,
        itemBox.$6 - itemBox.$5,
      ].reduce(math.max);
      if (!mounted) return;
      setState(() {
        _figure = figure;
        _item = item;
        _figureHeight = box.$4 - box.$3;
        _itemLongest = longest;
        _anchor = anchor;
        _anchorSource = source;
        _placement = autoPlacement(
          kind: widget.kind,
          figureHeight: _figureHeight,
          itemLongest: longest,
        );
      });
      _updateFit();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Die Vorschau ließ sich nicht aufbauen: '
            '${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  /// Größe des Gegenstands nach der aktuellen Skalierung, gemessen in
  /// Studs einer 5-Studs-Figur – damit steht die Roblox-Grenze schon
  /// hier und nicht erst beim Hochladen.
  void _updateFit() {
    final item = _item;
    if (item == null) return;
    final box = _bounds(item.positions);
    final perUnit = _figureHeight <= 0 ? 1.0 : 5.0 / _figureHeight;
    setState(() {
      _fit = accessoryFitFromSize(
        [
          (box.$2 - box.$1) * _placement.scale,
          (box.$4 - box.$3) * _placement.scale,
          (box.$6 - box.$5) * _placement.scale,
        ],
        widget.kind,
        studsPerUnit: perUnit,
      );
    });
  }

  /// (minX, maxX, minY, maxY, minZ, maxZ)
  (double, double, double, double, double, double) _bounds(
      Float32List positions) {
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    var minZ = double.infinity, maxZ = double.negativeInfinity;
    for (var i = 0; i + 2 < positions.length; i += 3) {
      minX = math.min(minX, positions[i]);
      maxX = math.max(maxX, positions[i]);
      minY = math.min(minY, positions[i + 1]);
      maxY = math.max(maxY, positions[i + 1]);
      minZ = math.min(minZ, positions[i + 2]);
      maxZ = math.max(maxZ, positions[i + 2]);
    }
    if (minX > maxX) return (0, 0, 0, 0, 0, 0);
    return (minX, maxX, minY, maxY, minZ, maxZ);
  }

  /// Die Punkte des Gegenstands an ihrem Platz – für die Anzeige.
  Float32List _placedPositions(PreviewMesh item) {
    final p = _world;
    final out = Float32List(item.positions.length);
    for (var i = 0; i + 2 < item.positions.length; i += 3) {
      final (x, y, z) = applyPlacement(p, item.positions[i],
          item.positions[i + 1], item.positions[i + 2]);
      out[i] = x;
      out[i + 1] = y;
      out[i + 2] = z;
    }
    return out;
  }

  /// Die Normalen dazu: nur drehen, nicht verschieben und nicht
  /// skalieren – eine Richtung hat keinen Ort, und eine skalierte
  /// Normale wäre kein Einheitsvektor mehr.
  Float32List _placedNormals(PreviewMesh item) {
    final only = ItemPlacement(
      rotX: _placement.rotX,
      rotY: _placement.rotY,
      rotZ: _placement.rotZ,
    );
    final out = Float32List(item.normals.length);
    for (var i = 0; i + 2 < item.normals.length; i += 3) {
      final (x, y, z) = applyPlacement(only, item.normals[i],
          item.normals[i + 1], item.normals[i + 2]);
      out[i] = x;
      out[i + 1] = y;
      out[i + 2] = z;
    }
    return out;
  }

  /// Die Platzierung inklusive Anbaupunkt: Die Regler verschieben
  /// gegenüber dem Gelenk, nicht gegenüber dem Ursprung.
  ItemPlacement get _world => _placement.copyWith(
        offsetX: _anchor.$1 + _placement.offsetX,
        offsetY: _anchor.$2 + _placement.offsetY,
        offsetZ: _anchor.$3 + _placement.offsetZ,
      );

  void _apply() {
    try {
      // Alles drei kommt in die Datei: Größe, Drehung und der Versatz
      // zum Anbaupunkt. Der Versatz ist genau das, was das Attachment
      // in Roblox braucht – ohne ihn wäre die Anprobe Zierde.
      Navigator.of(context).pop(
          applyPlacementToGlb(widget.itemGlb, _placement));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Übernehmen fehlgeschlagen: '
              '${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final figure = _figure;
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        title: Text('Anprobe – ${widget.itemLabel}',
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Vorschlag wiederherstellen',
            icon: const Icon(Icons.restart_alt),
            onPressed: () {
              setState(() => _placement = autoPlacement(
                    kind: widget.kind,
                    figureHeight: _figureHeight,
                    itemLongest: _itemLongest,
                  ));
              _updateFit();
            },
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
          : figure == null || item == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onScaleStart: (_) => _lastScale = 1.0,
                        onScaleUpdate: (details) => setState(() {
                          _rotY += details.focalPointDelta.dx * 0.01;
                          _rotX += details.focalPointDelta.dy * 0.01;
                          _rotX = _rotX.clamp(-math.pi, math.pi);
                          if (details.scale != 1.0) {
                            _zoom = (_zoom *
                                    (details.scale / _lastScale))
                                .clamp(0.3, 8.0);
                            _lastScale = details.scale;
                          }
                        }),
                        child: ClipRect(
                          child: CustomPaint(
                            painter: _FitPainter(
                              figure: figure,
                              item: item,
                              itemPositions: _placedPositions(item),
                              itemNormals: _placedNormals(item),
                              placement: _world,
                              anchor: _anchor,
                              figureOpacity: _figureOpacity,
                              rotX: _rotX,
                              rotY: _rotY,
                              zoom: _zoom,
                              background: theme
                                  .colorScheme.surfaceContainerHighest,
                              markColor: theme.colorScheme.primary,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                    _controls(theme),
                  ],
                ),
    );
  }

  Widget _controls(ThemeData theme) {
    final fit = _fit;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Angebaut an: $_anchorSource · '
              '${itemScaleNote(widget.kind, 5)}',
              style: theme.textTheme.bodySmall,
            ),
            if (fit != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  fit.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fit.ok
                        ? theme.colorScheme.outline
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            _slider(theme, 'Figur sichtbar', _figureOpacity, 0.0, 1.0,
                (v) => _figureOpacity = v,
                format: (v) => '${(v * 100).round()} %'),
            _slider(theme, 'Größe', _placement.scale, 0.05, 3.0,
                (v) => _placement = _placement.copyWith(scale: v),
                format: (v) => '×${v.toStringAsFixed(2)}'),
            _slider(theme, 'Höhe', _placement.offsetY,
                -_figureHeight / 2, _figureHeight / 2,
                (v) => _placement = _placement.copyWith(offsetY: v)),
            _slider(theme, 'Vor / Zurück', _placement.offsetZ,
                -_figureHeight / 2, _figureHeight / 2,
                (v) => _placement = _placement.copyWith(offsetZ: v)),
            _slider(theme, 'Seitlich', _placement.offsetX,
                -_figureHeight / 2, _figureHeight / 2,
                (v) => _placement = _placement.copyWith(offsetX: v)),
            _slider(theme, 'Kippen', _placement.rotX, -math.pi, math.pi,
                (v) => _placement = _placement.copyWith(rotX: v),
                format: _grad),
            _slider(theme, 'Drehen', _placement.rotY, -math.pi, math.pi,
                (v) => _placement = _placement.copyWith(rotY: v),
                format: _grad),
            _slider(theme, 'Neigen', _placement.rotZ, -math.pi, math.pi,
                (v) => _placement = _placement.copyWith(rotZ: v),
                format: _grad),
            const SizedBox(height: 4),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Was „Übernehmen" tut',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Größe, Drehung und Versatz werden in die Punkte '
                      'des Gegenstands gerechnet und als neue Fassung '
                      'gespeichert – in der Ergebnisliste und in der '
                      'Galerie als „(angepasst)". Das ursprüngliche '
                      'Modell bleibt daneben erhalten, nichts wird '
                      'überschrieben.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Der Versatz ist der zum Anbaupunkt. In Roblox '
                      'fällt das Attachment im Handle mit dem Punkt am '
                      'Körper zusammen – der Abstand, den du hier '
                      'einstellst, ist also genau der Abstand am '
                      'fertigen Avatar. Die Figur hier ist eine '
                      'Näherung: Ihr Kopfgelenk liegt nicht auf den '
                      'Millimeter dort, wo Roblox sein '
                      'HatAttachment hat. Für den Feinschliff gibt es '
                      'in Studio das Accessory Fitting Tool.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check),
                label: const Text('Größe, Drehung und Lage übernehmen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _grad(double value) =>
      '${(value * 180 / math.pi).round()}°';

  Widget _slider(ThemeData theme, String label, double value, double min,
      double max, void Function(double) set,
      {String Function(double)? format}) {
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            '$label ${(format ?? (v) => v.toStringAsFixed(2))(value)}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) {
              setState(() => set(v));
              _updateFit();
            },
          ),
        ),
      ],
    );
  }
}

/// Zeichnet Figur und Gegenstand im selben Maßstab.
///
/// Beide über denselben Renderer wie der Viewer – mit Textur, Licht
/// und allem. Die erste Fassung zeichnete flache Silhouetten; an
/// einer grauen Fläche ließ sich aber nicht erkennen, wo an der Figur
/// man eigentlich ist. Die Figur lässt sich stattdessen **durchsichtig
/// stellen**: Dann sieht man den Gegenstand auch, wenn er dahinter
/// oder darin liegt.
///
/// Beide Netze bekommen denselben Mittelpunkt und dieselbe
/// Ausdehnung übergeben – sonst zeichnete jedes für sich
/// formatfüllend, und ein Schwert sähe so groß aus wie die Figur.
class _FitPainter extends CustomPainter {
  _FitPainter({
    required this.figure,
    required this.item,
    required this.itemPositions,
    required this.itemNormals,
    required this.placement,
    required this.anchor,
    required this.figureOpacity,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
    required this.markColor,
  });

  final PreviewMesh figure;
  final PreviewMesh item;

  /// Der Gegenstand, bereits an seinen Platz gerechnet.
  final Float32List itemPositions;
  final Float32List itemNormals;

  final ItemPlacement placement;
  final (double, double, double) anchor;
  final double figureOpacity;
  final double rotX, rotY, zoom;
  final Color background, markColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Gemeinsamer Bezug: die Figur. Sie gibt Maßstab und Mitte vor.
    final center = figure.center;
    final extent = figure.extent;

    MeshPainter(
      mesh: figure,
      positions: figure.positions,
      normals: figure.normals,
      skeleton: null,
      skeletonParents: null,
      rotX: rotX,
      rotY: rotY,
      zoom: zoom,
      background: background,
      viewCenter: center,
      viewExtent: extent,
      opacity: figureOpacity,
    ).paint(canvas, size);

    MeshPainter(
      mesh: item,
      positions: itemPositions,
      normals: itemNormals,
      skeleton: null,
      skeletonParents: null,
      rotX: rotX,
      rotY: rotY,
      zoom: zoom,
      // Kein zweiter Hintergrund – sonst wäre die Figur wieder weg.
      background: null,
      viewCenter: center,
      viewExtent: extent,
    ).paint(canvas, size);

    // Der Anbaupunkt als Kreuz – so ist zu sehen, woran der
    // Gegenstand hängt.
    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final scale =
        0.42 * math.min(size.width, size.height) / extent * zoom;
    final x = anchor.$1 - center[0];
    final y = anchor.$2 - center[1];
    final z = anchor.$3 - center[2];
    final x1 = x * cosY + z * sinY;
    final z1 = -x * sinY + z * cosY;
    final y2 = y * cosX - z1 * sinX;
    final ax = size.width / 2 + x1 * scale;
    final ay = size.height / 2 - y2 * scale;
    final mark = Paint()
      ..color = markColor
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(ax - 8, ay), Offset(ax + 8, ay), mark);
    canvas.drawLine(Offset(ax, ay - 8), Offset(ax, ay + 8), mark);
  }

  @override
  bool shouldRepaint(_FitPainter old) => true;
}
