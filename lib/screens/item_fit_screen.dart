import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/glb_preview.dart';
import '../services/item_fit.dart';
import '../services/item_prompt.dart';
import '../services/roblox_accessory.dart';

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

  /// Die Platzierung inklusive Anbaupunkt: Die Regler verschieben
  /// gegenüber dem Gelenk, nicht gegenüber dem Ursprung.
  ItemPlacement get _world => _placement.copyWith(
        offsetX: _anchor.$1 + _placement.offsetX,
        offsetY: _anchor.$2 + _placement.offsetY,
        offsetZ: _anchor.$3 + _placement.offsetZ,
      );

  void _apply() {
    try {
      Navigator.of(context).pop(applyPlacementToGlb(
        widget.itemGlb,
        // Für die Datei zählt nur die Größe und die Drehung: Wohin am
        // Körper der Gegenstand gehört, entscheidet in Roblox das
        // Attachment und in Blender der Nutzer. Die Verschiebung zum
        // Gelenk gehört deshalb nicht in die Datei – sonst schwebt das
        // Accessoire beim Anziehen um die eigene Anbauhöhe daneben.
        _placement.copyWith(offsetX: 0, offsetY: 0, offsetZ: 0),
      ));
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
                              placement: _world,
                              anchor: _anchor,
                              rotX: _rotX,
                              rotY: _rotY,
                              zoom: _zoom,
                              background: theme
                                  .colorScheme.surfaceContainerHighest,
                              figureColor: theme.colorScheme.outline,
                              itemColor: theme.colorScheme.primary,
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
            Text(
              'Übernommen werden Größe und Drehung – sie stecken danach '
              'in der Datei des Gegenstands. Die Verschiebung gilt nur '
              'für diese Anprobe: Wohin am Körper das Teil gehört, '
              'entscheidet in Roblox das Attachment.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check),
                label: const Text('Größe und Drehung übernehmen'),
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
/// Flächig, ohne Textur: Beim Anpassen zählt die Silhouette – wo sitzt
/// es, wie groß, steht es richtig herum. Eine Textur würde genau das
/// überdecken. Beide Netze werden in einer gemeinsamen Tiefensortierung
/// gezeichnet, sonst läge der Gegenstand immer vor oder immer hinter
/// der Figur.
class _FitPainter extends CustomPainter {
  _FitPainter({
    required this.figure,
    required this.item,
    required this.placement,
    required this.anchor,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
    required this.figureColor,
    required this.itemColor,
  });

  final PreviewMesh figure;
  final PreviewMesh item;
  final ItemPlacement placement;
  final (double, double, double) anchor;
  final double rotX, rotY, zoom;
  final Color background, figureColor, itemColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final scale =
        0.42 * math.min(size.width, size.height) / figure.extent * zoom;
    final cx = size.width / 2, cy = size.height / 2;
    final centerX = figure.center[0],
        centerY = figure.center[1],
        centerZ = figure.center[2];

    (double, double, double) project(double x0, double y0, double z0) {
      final x = x0 - centerX, y = y0 - centerY, z = z0 - centerZ;
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      final y2 = y * cosX - z1 * sinX;
      final z2 = y * sinX + z1 * cosX;
      return (cx + x1 * scale, cy - y2 * scale, z2);
    }

    // Alle Dreiecke beider Netze in einen Topf – nur so stimmt die
    // Verdeckung zwischen Figur und Gegenstand. Gezeichnet wird alles
    // in **einem** `drawVertices`-Aufruf: Ein Pfad je Dreieck wären
    // bei zwei Modellen zu je zehntausend Dreiecken zwanzigtausend
    // Zeichenbefehle pro Bild – das ruckelt beim Ziehen sichtbar.
    final tris = <(double, int, int, int)>[];
    final vx = <double>[];
    final vy = <double>[];
    final vz = <double>[];
    final tint = <Color>[];

    void collect(PreviewMesh mesh, Color color,
        {ItemPlacement? transform}) {
      final base = vx.length;
      final positions = mesh.positions;
      for (var i = 0; i + 2 < positions.length; i += 3) {
        var x = positions[i], y = positions[i + 1], z = positions[i + 2];
        if (transform != null) {
          final moved = applyPlacement(transform, x, y, z);
          x = moved.$1;
          y = moved.$2;
          z = moved.$3;
        }
        final (px, py, pz) = project(x, y, z);
        vx.add(px);
        vy.add(py);
        vz.add(pz);
        tint.add(color);
      }
      final indices = mesh.indices;
      for (var t = 0; t + 2 < indices.length; t += 3) {
        final a = base + indices[t],
            b = base + indices[t + 1],
            c = base + indices[t + 2];
        // Rückseiten weglassen: halbiert die Fläche und macht die
        // Silhouette klarer.
        final area = (vx[b] - vx[a]) * (vy[c] - vy[a]) -
            (vx[c] - vx[a]) * (vy[b] - vy[a]);
        if (area <= 0) continue;
        tris.add((vz[a] + vz[b] + vz[c], a, b, c));
      }
    }

    collect(figure, figureColor);
    collect(item, itemColor, transform: placement);
    // Maler-Algorithmus: Entferntes zuerst. `drawVertices` zeichnet in
    // der übergebenen Reihenfolge, also genügt es, die Dreiecke
    // sortiert einzutragen.
    tris.sort((a, b) => a.$1.compareTo(b.$1));

    if (tris.isNotEmpty) {
      final points = Float32List(tris.length * 6);
      final colors = Int32List(tris.length * 3);
      for (var t = 0; t < tris.length; t++) {
        final (_, a, b, c) = tris[t];
        // Schattierung aus der Flächennormalen im Blickraum: Flächen,
        // die zum Betrachter zeigen, werden heller. Ohne das wäre das
        // Modell eine flache Silhouette ohne erkennbare Form.
        final ux = vx[b] - vx[a], uy = vy[b] - vy[a], uz = vz[b] - vz[a];
        final wx = vx[c] - vx[a], wy = vy[c] - vy[a], wz = vz[c] - vz[a];
        final nx = uy * wz - uz * wy;
        final ny = uz * wx - ux * wz;
        final nz = ux * wy - uy * wx;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        final facing = len <= 0 ? 0.0 : (nz / len).abs();
        final color = Color.lerp(tint[a], Colors.white, 0.45 * facing)!
            .toARGB32();
        for (final (slot, v) in [(0, a), (1, b), (2, c)]) {
          points[t * 6 + slot * 2] = vx[v];
          points[t * 6 + slot * 2 + 1] = vy[v];
          colors[t * 3 + slot] = color;
        }
      }
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, points, colors: colors),
        // srcOver, nicht dstOver: Die Vertex-Farben sollen über der
        // Farbe des Pinsels liegen. Umgekehrt läge der voreingestellte
        // schwarze Pinsel obenauf und alles wäre schwarz.
        BlendMode.srcOver,
        Paint(),
      );
    }

    // Der Anbaupunkt als Kreuz – so ist zu sehen, woran der
    // Gegenstand hängt.
    final (ax, ay, _) = project(anchor.$1, anchor.$2, anchor.$3);
    final mark = Paint()
      ..color = itemColor
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(ax - 7, ay), Offset(ax + 7, ay), mark);
    canvas.drawLine(Offset(ax, ay - 7), Offset(ax, ay + 7), mark);
  }

  @override
  bool shouldRepaint(_FitPainter old) => true;
}
