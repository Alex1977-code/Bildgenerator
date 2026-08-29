import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../services/animation_bake.dart';
import '../services/exporter.dart';
import '../services/glb_preview.dart';
import '../services/mesh_check.dart';
import '../services/model_import.dart';
import '../services/obj_export.dart';
import '../services/preview_animations.dart';
import '../services/provenance.dart';
import '../services/settings_service.dart';
import '../services/stl_export.dart';
import '../services/threemf_export.dart';
import '../widgets/print_size_dialog.dart';
import 'rig_edit_screen.dart';

/// Frei drehbare 3D-Vorschau eines GLB-Modells (eigener Software-Renderer,
/// läuft auf allen Plattformen inklusive Windows). Geriggte Modelle
/// lassen sich direkt animieren (Clips aus der Datei oder eingebaute
/// Testanimationen), das Skelett kann grafisch eingeblendet werden.
class ModelPreviewScreen extends StatefulWidget {
  const ModelPreviewScreen({
    super.key,
    required this.glbBytes,
    required this.title,
    this.provenance,
    this.unriggedGlb,
    this.rigType,
    this.onGlbUpdated,
  });

  final Uint8List glbBytes;
  final String title;

  /// Metadaten für den Erstellungsnachweis (nur bei in der App
  /// erzeugten Modellen vorhanden – nicht bei importierten Dateien).
  final ProvenanceInfo? provenance;

  /// Modell vor dem eigenen Auto-Rigging + Figurtyp: schaltet den
  /// Rig-Editor frei (Gelenke manuell verschieben, Skelett neu
  /// einbauen).
  final Uint8List? unriggedGlb;
  final String? rigType;

  /// Wird nach dem Rig-Editor mit dem neuen GLB aufgerufen (damit das
  /// Ergebnis in der Liste den angepassten Stand exportiert).
  final void Function(Uint8List bytes)? onGlbUpdated;

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
  Float32List? _posedNormals;
  Float32List? _jointPositions;
  MeshCheckResult? _meshCheck;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _mesh?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final mesh = await parseGlbForPreview(widget.glbBytes);
      if (!mounted) return;
      setState(() {
        _mesh = mesh;
        _meshCheck = checkMeshWatertight(mesh.positions, mesh.indices);
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
    // Beleuchtung folgt der Pose: Normalen aus den bewegten Positionen.
    _posedNormals = _posedPositions == null
        ? null
        : computeSmoothNormals(_posedPositions!, mesh.indices,
            weld: mesh.weldMap);
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

  /// Ersetzt das angezeigte Modell durch eine abgelegte Datei.
  Future<void> _openDropped(DropDoneDetails detail) async {
    final messenger = ScaffoldMessenger.of(context);
    for (final file in detail.files) {
      try {
        final bytes = await file.readAsBytes();
        final glb = importModelToGlb(bytes, file.name);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) =>
              ModelPreviewScreen(glbBytes: glb, title: file.name),
        ));
        return;
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('Modell konnte nicht geladen werden: '
                '${e.toString().replaceFirst('Exception: ', '')}')));
        return;
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

  /// Fragt die Druckgröße (längste Seite in mm) ab und zeigt das
  /// Ergebnis der Wasserdichtheits-Prüfung an.
  Future<double?> _askPrintSize(String title, String note) =>
      askPrintSizeDialog(context,
          title: title, note: note, check: _meshCheck);

  /// Rig-Editor öffnen; danach das Modell mit dem angepassten Skelett
  /// neu laden und dem Aufrufer (Ergebnisliste) mitteilen.
  Future<void> _editRig() async {
    final unrigged = widget.unriggedGlb;
    final rigType = widget.rigType;
    if (unrigged == null || rigType == null) return;
    final navigator = Navigator.of(context);
    final edited = await navigator.push<Uint8List>(MaterialPageRoute(
      builder: (_) => RigEditScreen(
        unriggedGlb: unrigged,
        rigType: rigType,
        title: widget.title,
      ),
    ));
    if (edited == null || !mounted) return;
    widget.onGlbUpdated?.call(edited);
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: edited,
        title: widget.title,
        provenance: widget.provenance,
        unriggedGlb: unrigged,
        rigType: rigType,
        onGlbUpdated: widget.onGlbUpdated,
      ),
    ));
  }

  /// Erstellungsnachweis-PDF fürs Modell (Zeitpunkt, Eingabe, Dienst
  /// und SHA-256-Prüfsumme der GLB-Datei) herunterladen/drucken.
  Future<void> _exportProvenance() async {
    final info = widget.provenance;
    if (info == null) return;
    final settings = context.read<SettingsService>();
    final name = await askCreatorName(context, settings);
    if (name == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdf = await buildProvenancePdf(
        info: info,
        fileType: 'GLB',
        fileBytes: widget.glbBytes,
        creatorName: name,
      );
      final message = await exportImageBytes(
        pdf,
        'erstellungsnachweis_${DateTime.now().millisecondsSinceEpoch}.pdf',
        'application/pdf',
      );
      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Nachweis fehlgeschlagen: $e')));
    }
  }

  /// OBJ-Export (mit Vertexfarben, Originalmaße).
  Future<void> _exportObj() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final obj = await glbToObj(widget.glbBytes);
      final message = await exportImageBytes(
        obj,
        'modell_${DateTime.now().millisecondsSinceEpoch}.obj',
        'model/obj',
      );
      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('OBJ-Export fehlgeschlagen: $e')));
    }
  }

  /// STL-Export (nur Form) mit wählbarer Druckgröße.
  Future<void> _exportStl() async {
    final size = await _askPrintSize(
      'STL für 3D-Druck',
      'STL enthält nur die Form (ohne Farben und Textur). Das Modell '
      'wird aufs Druckbett gedreht und zentriert. Die Datei danach in '
      'einen Slicer laden (z. B. PrusaSlicer, Cura, Bambu Studio) und '
      'von dort drucken – kleine Löcher repariert der Slicer '
      'automatisch.',
    );
    if (size == null || size <= 0 || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final stl = await glbToStl(widget.glbBytes, targetSizeMm: size);
      final message = await exportImageBytes(
        stl,
        'modell_${DateTime.now().millisecondsSinceEpoch}.stl',
        'model/stl',
      );
      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('STL-Export fehlgeschlagen: $e')));
    }
  }

  /// 3MF-Export mit Farben (Material-Palette je Dreieck).
  Future<void> _export3mf() async {
    final size = await _askPrintSize(
      '3MF mit Farben für 3D-Druck',
      '3MF enthält die Form samt Farben (als Material-Palette je '
      'Dreieck) – ideal für Farb-3D-Druck und Druckdienste. Das Modell '
      'wird aufs Druckbett gedreht, zentriert und in mm skaliert. Die '
      'Datei in PrusaSlicer, Bambu Studio oder beim Druckdienst öffnen.',
    );
    if (size == null || size <= 0 || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await glbTo3mf(widget.glbBytes, targetSizeMm: size);
      final message = await exportImageBytes(
        data,
        'modell_${DateTime.now().millisecondsSinceEpoch}.3mf',
        'model/3mf',
      );
      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('3MF-Export fehlgeschlagen: $e')));
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
          if (widget.unriggedGlb != null && widget.rigType != null)
            IconButton(
              tooltip: 'Rig anpassen (Gelenke manuell verschieben)',
              icon: const Icon(Icons.settings_accessibility),
              onPressed: _editRig,
            ),
          IconButton(
            tooltip: 'Ansicht zurücksetzen',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetView,
          ),
          PopupMenuButton<String>(
            tooltip: 'Exportieren',
            icon: const Icon(Icons.download),
            onSelected: (choice) {
              switch (choice) {
                case 'glb':
                  _export();
                case 'glb_anim':
                  _export(withAnimations: true);
                case 'obj':
                  _exportObj();
                case 'stl':
                  _exportStl();
                case '3mf':
                  _export3mf();
                case 'nachweis':
                  _exportProvenance();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'glb', child: Text('GLB exportieren')),
              if (_procClips.isNotEmpty)
                const PopupMenuItem(
                    value: 'glb_anim',
                    child: Text('GLB + Testanimationen exportieren')),
              const PopupMenuItem(
                  value: 'obj',
                  child: Text('OBJ exportieren (mit Vertexfarben)')),
              const PopupMenuItem(
                  value: 'stl',
                  child: Text('STL für 3D-Druck exportieren …')),
              const PopupMenuItem(
                  value: '3mf',
                  child: Text('3MF mit Farben exportieren …')),
              if (widget.provenance != null)
                const PopupMenuItem(
                    value: 'nachweis',
                    child: Text('Erstellungsnachweis (PDF) …')),
            ],
          ),
        ],
      ),
      body: DropTarget(
        onDragDone: _openDropped,
        child: _error != null
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
                                normals: _posedNormals ?? mesh.normals,
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
                        '${mesh.texture != null ? ' · Textur ${mesh.texture!.width} px' : ' · Vertex-Farben'}'
                        '${rig != null ? ' · ${rig.joints.length} Gelenke' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.mesh,
    required this.positions,
    required this.normals,
    required this.skeleton,
    required this.skeletonParents,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.background,
  });

  final PreviewMesh mesh;
  final Float32List positions;
  final Float32List normals;
  final Float32List? skeleton; // x,y,z je Gelenk (Weltkoordinaten)
  final List<int>? skeletonParents;
  final double rotX;
  final double rotY;
  final double zoom;
  final Color background;

  static final Float64List _identityMatrix = Float64List.fromList(
      [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

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

    // Weiche per-Vertex-Beleuchtung aus den mitgedrehten Normalen
    // (Gouraud-Shading statt facettiertem Flat-Shading) – plus
    // PBR-Glanzlichter nach Metall/Rauheit des Materials: Metalle
    // streuen weniger diffus und bekommen einen additiven
    // Spekular-Pass (Blinn-Phong-Näherung).
    final metallic = mesh.metallic;
    final gloss = (1 - mesh.roughness).clamp(0.0, 1.0);
    final shininess = 4 + gloss * gloss * 96;
    final specStrength =
        (0.25 + 0.75 * metallic) * math.pow(gloss, 1.5).toDouble();
    // Halbvektor aus Lichtrichtung (-0.26, 0.44, 0.86) und Blick (0,0,1).
    var hx = -0.26, hy = 0.44, hz = 1.86;
    final hLen = math.sqrt(hx * hx + hy * hy + hz * hz);
    hx /= hLen;
    hy /= hLen;
    hz /= hLen;
    final shade = Float32List(vertexCount);
    final spec = specStrength > 0.01 ? Float32List(vertexCount) : null;
    for (var i = 0; i < vertexCount; i++) {
      final nx = normals[i * 3],
          ny = normals[i * 3 + 1],
          nz = normals[i * 3 + 2];
      final x1 = nx * cosY + nz * sinY;
      final z1 = -nx * sinY + nz * cosY;
      final y2 = ny * cosX - z1 * sinX;
      final z2 = ny * sinX + z1 * cosX;
      // Licht schräg von oben vorn; doppelseitig (Betrag).
      var dot = (-0.26 * x1 + 0.44 * y2 + 0.86 * z2).abs();
      if (dot > 1) dot = 1;
      shade[i] = (0.42 + 0.58 * dot) * (1 - 0.45 * metallic);
      if (spec != null) {
        var hDot = (hx * x1 + hy * y2 + hz * z2).abs();
        if (hDot > 1) hDot = 1;
        spec[i] = specStrength * math.pow(hDot, shininess).toDouble();
      }
    }

    final texture = mesh.texture;
    final uvs = mesh.uvs;
    final textured = texture != null && uvs != null;
    final outPositions = Float32List(triangleCount * 6);
    final outColors = Int32List(triangleCount * 3);
    final outTex = textured ? Float32List(triangleCount * 6) : null;
    final specColors = spec != null ? Int32List(triangleCount * 3) : null;
    var p = 0, c = 0, texOut = 0, scOut = 0;
    for (final t in order) {
      final ia = indices[t * 3],
          ib = indices[t * 3 + 1],
          ic = indices[t * 3 + 2];
      for (final vi in [ia, ib, ic]) {
        outPositions[p++] = sx[vi];
        outPositions[p++] = sy[vi];
        final s = shade[vi];
        if (specColors != null) {
          // Glanzlicht-Farbe: weiß für Nichtmetalle, bei Metallen zur
          // Grundfarbe hin getönt.
          final sv = spec![vi];
          final base = mesh.colors[vi];
          final br = 255 + (((base >> 16) & 0xFF) - 255) * metallic;
          final bg = 255 + (((base >> 8) & 0xFF) - 255) * metallic;
          final bb = 255 + ((base & 0xFF) - 255) * metallic;
          specColors[scOut++] = 0xFF000000 |
              ((sv * br).round().clamp(0, 255) << 16) |
              ((sv * bg).round().clamp(0, 255) << 8) |
              (sv * bb).round().clamp(0, 255);
        }
        if (textured) {
          // wrapUv erhält Werte in [0,1] – insbesondere darf u = 1,0
          // nicht auf 0,0 springen (Schmier-Streifen quer über die
          // Textur bei Dreiecken am Texturrand).
          outTex![texOut++] = wrapUv(uvs[vi * 2]) * texture.width;
          outTex[texOut++] = wrapUv(uvs[vi * 2 + 1]) * texture.height;
          final grey = (s * 255).round().clamp(0, 255);
          outColors[c++] =
              0xFF000000 | (grey << 16) | (grey << 8) | grey;
        } else {
          final color = mesh.colors[vi];
          final r = ((color >> 16) & 0xFF) * s;
          final g = ((color >> 8) & 0xFF) * s;
          final b = (color & 0xFF) * s;
          outColors[c++] = 0xFF000000 |
              (r.round().clamp(0, 255) << 16) |
              (g.round().clamp(0, 255) << 8) |
              b.round().clamp(0, 255);
        }
      }
    }

    if (textured) {
      // Echtes Textur-Mapping: Texturkoordinaten je Vertex, Helligkeit
      // über die Vertex-Farben (modulate) – volle Texturschärfe.
      final paint = Paint()
        ..shader = ui.ImageShader(texture, ui.TileMode.clamp,
            ui.TileMode.clamp, _identityMatrix);
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
            textureCoordinates: outTex, colors: outColors),
        BlendMode.modulate,
        paint,
      );
    } else {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
            colors: outColors),
        BlendMode.dst,
        Paint(),
      );
    }

    // Additiver Glanzlicht-Pass (PBR): hellt dort auf, wo die
    // Oberfläche das Licht zur Kamera spiegelt – sichtbar bei
    // glänzenden und metallischen Materialien.
    if (specColors != null) {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, outPositions,
            colors: specColors),
        BlendMode.dst,
        Paint()..blendMode = BlendMode.plus,
      );
    }

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
      oldDelegate.normals != normals ||
      oldDelegate.skeleton != skeleton ||
      oldDelegate.rotX != rotX ||
      oldDelegate.rotY != rotY ||
      oldDelegate.zoom != zoom ||
      oldDelegate.background != background;
}
