import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../services/animation_bake.dart';
import '../services/auto_rig.dart'
    show
        estimateFrontSign,
        injectAutoRig,
        measureRigShapeOfGlb,
        rigTypeOptions,
        rigTypePromptRules;
import '../services/rig_detect.dart';
import '../services/exporter.dart';
import '../services/glb_preview.dart';
import '../services/mesh_check.dart';
import '../services/model_relay.dart';
import '../services/model_import.dart';
import '../services/model_refine.dart' show rotateGlbQuarterTurns;
import '../services/obj_export.dart';
import '../services/preview_animations.dart';
import '../services/glb_textures.dart';
import '../services/roblox_check.dart';
import '../services/roblox_fix.dart';
import '../services/roblox_rig.dart';
import '../services/mesh_budget.dart';
import '../services/roblox_specs_config.dart';
import '../services/roblox_preflight.dart';
import '../services/provenance.dart';
import '../services/settings_service.dart';
import '../services/stl_export.dart';
import '../services/threemf_export.dart';
import '../widgets/mesh_painter.dart';
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
    this.rigInfluence,
    this.onGlbUpdated,
    this.showExport = true,
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

  /// Im Rig-Editor gesetzte Einfluss-Faktoren (Gelenkname → Faktor).
  /// Die Gelenkpositionen stecken im GLB, die Faktoren nur hier – ohne
  /// sie stünde der Regler beim erneuten Öffnen wieder auf 1,0.
  final Map<String, double>? rigInfluence;

  /// Wird nach dem Rig-Editor mit dem neuen GLB aufgerufen (damit das
  /// Ergebnis in der Liste den angepassten Stand exportiert).
  final void Function(Uint8List bytes)? onGlbUpdated;

  /// Export-Menü anzeigen? Aus der Ergebnisliste geöffnete Modelle
  /// exportieren über den Export-Knopf am Ergebnis – der Viewer bleibt
  /// dort aufs Betrachten und Rig-Anpassen fokussiert.
  final bool showExport;

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

  /// Startdrehung: zeigt die erkannte Vorderseite des Modells (bei
  /// Blickrichtung -z um 180° gedreht), leicht schräg für Plastizität.
  double _homeRotY = 0.6;

  late final Ticker _ticker = createTicker(_onTick);
  List<PreviewAnimation> _fileClips = const [];
  List<ProceduralClip> _procClips = const [];

  /// -1 = Standbild; 0..fileClips-1 = Clip aus der Datei; danach die
  /// eingebauten Testanimationen.
  int _clipIndex = -1;
  bool _playing = false;
  bool _showSkeleton = false;

  /// „Animationen ans Modell hängen“: Exporte (Viewer und Ergebnis)
  /// betten die Testanimationen als glTF-Clips in die GLB ein.
  bool _embedAnimations = false;
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
        // Blickrichtung: aus dem eigenen Rig (Skin-Extras), sonst aus
        // der Geometrie geschätzt – so startet die Ansicht mit dem
        // Gesicht zur Kamera statt mit der Rückseite.
        final front =
            rig?.frontSign ?? estimateFrontSign([mesh.positions]);
        _homeRotY = front < 0 ? 0.6 + math.pi : 0.6;
        _rotY = _homeRotY;
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

  /// Passendes Icon je Testanimation (für die seitliche Icon-Leiste).
  static IconData _clipIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('vierbein')) return Icons.pets;
    if (n.contains('rennen')) return Icons.directions_run;
    if (n.contains('gehen')) return Icons.directions_walk;
    if (n.contains('wedel')) return Icons.waving_hand;
    if (n.contains('wink')) return Icons.waving_hand;
    if (n.contains('spring')) return Icons.arrow_upward;
    if (n.contains('verbeug')) return Icons.emoji_people;
    if (n.contains('nicken')) return Icons.expand_circle_down;
    if (n.contains('schütteln')) return Icons.sync_alt;
    if (n.contains('tanz')) return Icons.music_note;
    if (n.contains('atmen')) return Icons.self_improvement;
    if (n.contains('drehen')) return Icons.threesixty;
    if (n.contains('flügel')) return Icons.flight;
    if (n.contains('krabbel')) return Icons.bug_report;
    if (n.contains('schwimm')) return Icons.pool;
    if (n.contains('schläng')) return Icons.waves;
    if (n.contains('kurven')) return Icons.alt_route;
    if (n.contains('fahren')) return Icons.directions_car;
    if (n.contains('wackel')) return Icons.vibration;
    return Icons.movie;
  }

  /// Linke Werkzeugleiste (analog zur Menüleiste des Hauptbildschirms):
  /// Skelett anzeigen, Rig anpassen, Ansicht zurücksetzen.
  Widget _toolRail(ThemeData theme, PreviewRig? rig) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rig != null)
            IconButton(
              tooltip: _showSkeleton
                  ? 'Skelett ausblenden'
                  : 'Skelett anzeigen',
              style: IconButton.styleFrom(
                backgroundColor: _showSkeleton
                    ? theme.colorScheme.primaryContainer
                    : null,
                foregroundColor: _showSkeleton
                    ? theme.colorScheme.onPrimaryContainer
                    : null,
              ),
              icon: const Icon(Icons.polyline),
              onPressed: () =>
                  setState(() => _showSkeleton = !_showSkeleton),
            ),
          if (widget.unriggedGlb != null && widget.rigType != null)
            IconButton(
              tooltip: 'Rig anpassen (Gelenke manuell verschieben)',
              icon: const Icon(Icons.settings_accessibility),
              onPressed: _editRig,
            )
          // Ein Modell ohne Skelett – aus einem Import, aus einem
          // Lauf ohne Auto-Rigging, von einem Anbieter, der nur das
          // Netz liefert. Das Skelett lässt sich nachträglich
          // einbauen; danach steht auch der Rig-Editor offen.
          else if (rig == null)
            IconButton(
              tooltip: 'Skelett nachträglich einbauen',
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _addRig,
            ),
          // Das Dreiecksbudget. Das Face-Limit von Tripo bleibt, wo
          // es ist: Es wirkt vor der Generierung, der Anbieter baut
          // gleich ein schlankeres Netz, und das sieht meist besser
          // aus als jede spätere Reduktion. Nur greift es eben nur
          // bei Tripo – dieser Regler gilt für jede GLB.
          // Der Preflight: Was hindert dieses Modell daran, in
          // Roblox zu landen? Zwei Stufen – Fehler blockieren den
          // Export, Warnungen nicht.
          IconButton(
            tooltip: 'Preflight: für Roblox prüfen',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: _openPreflight,
          ),
          IconButton(
            tooltip: 'Dreiecksbudget (Regler mit Ampel)',
            icon: const Icon(Icons.speed_outlined),
            onPressed: _openBudget,
          ),
          // Roblox in zwei Schritten – an der Datei, nicht nur am
          // frisch erzeugten Ergebnis im 3D-Tab. Ein abgelegtes
          // Modell aus Blender oder aus einem alten Lauf kam dort nie
          // an.
          PopupMenuButton<bool>(
            tooltip: 'Für Roblox herrichten',
            icon: const Icon(Icons.sports_esports_outlined),
            onSelected: (withRig) => _makeRobloxReady(withRig: withRig),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: true,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.accessibility_new),
                  title: Text('Roblox-konform riggen und anpassen'),
                  subtitle: Text('Skelett mit R15-Namen, 5 Studs, '
                      'geschlossene Hülle, Textur 1024'),
                ),
              ),
              PopupMenuItem(
                value: false,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.build_outlined),
                  title: Text('Nur anpassen (ohne Skelett)'),
                  subtitle: Text('Für Accessoires und Props'),
                ),
              ),
            ],
          ),
          // Zubehör zu dieser Figur. Steht auch hier, nicht nur an der
          // Ergebnisliste des 3D-Tabs: Die lebt nur im
          // Arbeitsspeicher, und nach einem Neustart sucht man die
          // Funktion am fertigen Modell in der Galerie – zu Recht.
          IconButton(
            tooltip: 'Passende Gegenstände zu dieser Figur erzeugen',
            icon: const Icon(Icons.category_outlined),
            onPressed: () {
              context.read<ModelRelay>().send(
                    glb: widget.glbBytes,
                    label: widget.title,
                    prompt: widget.provenance?.description ?? '',
                  );
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          // Importierte Dateien aus Blender/CAD stehen oft z-up und
          // liegen dadurch auf der Seite – hier lässt sich das
          // dauerhaft geraderücken (wirkt auch im Export).
          PopupMenuButton<(String, int)>(
            tooltip: 'Modell drehen (90°-Schritte, wirkt im Export)',
            icon: const Icon(Icons.rotate_90_degrees_ccw),
            onSelected: (choice) =>
                _rotateModel(choice.$1, choice.$2),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: ('x', 1),
                child: Text('Aufrichten (X +90°)'),
              ),
              PopupMenuItem(
                value: ('x', -1),
                child: Text('Kippen (X −90°)'),
              ),
              PopupMenuItem(
                value: ('y', 1),
                child: Text('Drehen links (Y +90°)'),
              ),
              PopupMenuItem(
                value: ('y', -1),
                child: Text('Drehen rechts (Y −90°)'),
              ),
              PopupMenuItem(
                value: ('z', 1),
                child: Text('Rollen (Z +90°)'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Ansicht zurücksetzen',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetView,
          ),
        ],
      ),
    );
  }

  /// Seitliche Icon-Leiste zur Animationsauswahl (statt Dropdown).
  Widget _animationStrip(ThemeData theme) {
    final entries = <(int, IconData, String)>[
      (-1, Icons.accessibility_new, 'Standbild'),
      for (var i = 0; i < _fileClips.length; i++)
        (i, Icons.movie, _fileClips[i].name),
      for (var i = 0; i < _procClips.length; i++)
        (
          _fileClips.length + i,
          _clipIcon(_procClips[i].name),
          '${_procClips[i].name} (Test)',
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, icon, label) in entries)
              IconButton(
                tooltip: label,
                style: IconButton.styleFrom(
                  backgroundColor: _clipIndex == index
                      ? theme.colorScheme.primaryContainer
                      : null,
                  foregroundColor: _clipIndex == index
                      ? theme.colorScheme.onPrimaryContainer
                      : null,
                ),
                icon: Icon(icon),
                onPressed: () => _selectClip(index),
              ),
          ],
        ),
      ),
    );
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
      _rotY = _homeRotY;
      _zoom = 1.0;
    });
  }

  /// Schalter „Animationen ans Modell hängen“: bettet die Clips sofort
  /// ein und reicht das Ergebnis an die Ergebnisliste weiter, damit
  /// auch der Export dort die Animationen enthält.
  void _setEmbed(bool value) {
    setState(() => _embedAnimations = value);
    final onUpdated = widget.onGlbUpdated;
    if (onUpdated == null) return;
    try {
      onUpdated(value && _procClips.isNotEmpty
          ? bakeAnimationsIntoGlb(widget.glbBytes, _procClips)
          : widget.glbBytes);
      if (value) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${_procClips.length} Testanimationen sind '
                'jetzt Teil des Modells (auch beim Export am '
                'Ergebnis).')));
      }
    } catch (_) {}
  }

  Future<void> _export({bool withAnimations = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      var bytes = widget.glbBytes;
      var prefix = 'modell';
      if ((withAnimations || _embedAnimations) && _procClips.isNotEmpty) {
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
  /// Dreht das Modell in 90°-Schritten – echte Geometrie, damit auch
  /// Export und Druck stimmen. Bei geriggten Modellen wird die
  /// ungeriggte Fassung gedreht und das Skelett neu eingebaut, sonst
  /// passten Gelenke und Netz nicht mehr zusammen.
  Future<void> _rotateModel(String axis, int turns) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final unrigged = widget.unriggedGlb;
    final rigType = widget.rigType;
    Uint8List rotated;
    Uint8List? rotatedUnrigged;
    try {
      if (unrigged != null && rigType != null) {
        rotatedUnrigged =
            rotateGlbQuarterTurns(unrigged, axis, quarterTurns: turns);
        rotated = injectAutoRig(rotatedUnrigged, rigType: rigType);
      } else {
        rotated = rotateGlbQuarterTurns(widget.glbBytes, axis,
            quarterTurns: turns);
      }
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Drehen nicht möglich: '
              '${e.toString().replaceFirst('Exception: ', '')}')));
      return;
    }
    if (!mounted) return;
    widget.onGlbUpdated?.call(rotated);
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: rotated,
        title: widget.title,
        provenance: widget.provenance,
        unriggedGlb: rotatedUnrigged ?? widget.unriggedGlb,
        rigType: widget.rigType,
        rigInfluence: widget.rigInfluence,
        onGlbUpdated: widget.onGlbUpdated,
      ),
    ));
  }

  /// Aktuelle Gelenkpositionen aus dem geriggten Modell lesen: Die
  /// Skelett-Knoten tragen lokale Translationen, die Kette wird hier
  /// zu absoluten Positionen aufaddiert. So startet der Editor mit dem
  /// zuletzt angepassten Rig statt wieder mit der Automatik.
  Map<String, (double, double, double)>? _currentJointPositions() {
    final rig = _mesh?.rig;
    if (rig == null) return null;
    final world = <int, (double, double, double)>{};
    for (final index in rig.nodeOrder) {
      final node = rig.nodes[index];
      final parent = node.parent >= 0 ? world[node.parent] : null;
      world[index] = (
        (parent?.$1 ?? 0) + node.translation[0],
        (parent?.$2 ?? 0) + node.translation[1],
        (parent?.$3 ?? 0) + node.translation[2],
      );
    }
    final result = <String, (double, double, double)>{};
    for (final nodeIndex in rig.joints) {
      final name = rig.nodes[nodeIndex].name;
      final position = world[nodeIndex];
      if (name.isNotEmpty && position != null) result[name] = position;
    }
    return result.isEmpty ? null : result;
  }

  /// Skelett nachträglich einbauen.
  ///
  /// Der Typ wird an der Form vorgeschlagen (Standflächen am Boden,
  /// Proportionen) und lässt sich überstimmen – erkannt **oder**
  /// gewählt. Danach verhält sich das Modell wie ein frisch geriggtes:
  /// Animationen laufen, der Rig-Editor ist offen.
  Future<void> _addRig() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    List<RigTypeGuess> guesses;
    RigShape? shape;
    try {
      shape = measureRigShapeOfGlb(widget.glbBytes);
      guesses = guessRigType(shape);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Kein Skelett möglich: '
              '${e.toString().replaceFirst('Exception: ', '')}')));
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _RigTypeDialog(guesses: guesses, shape: shape!),
    );
    if (chosen == null || !mounted) return;

    Uint8List rigged;
    try {
      rigged = injectAutoRig(widget.glbBytes,
          rigType: chosen, knownFrontSign: _mesh?.rig?.frontSign);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Rigging fehlgeschlagen: '
              '${e.toString().replaceFirst('Exception: ', '')}')));
      return;
    }
    widget.onGlbUpdated?.call(rigged);
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: rigged,
        title: widget.title,
        provenance: widget.provenance,
        // Das bisherige Netz ist ab jetzt die ungeriggte Fassung –
        // damit kann der Rig-Editor das Skelett neu aufbauen.
        unriggedGlb: widget.glbBytes,
        rigType: chosen,
        onGlbUpdated: widget.onGlbUpdated,
        showExport: widget.showExport,
      ),
    ));
  }

  /// Der Preflight-Bericht.
  Future<void> _openPreflight() async {
    final messenger = ScaffoldMessenger.of(context);
    final gewaehlt = await showModalBottomSheet<PreflightFix>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PreflightSheet(glb: widget.glbBytes),
    );
    if (gewaehlt == null || !mounted) return;
    switch (gewaehlt) {
      case PreflightFix.reduzieren:
        await _openBudget();
      case PreflightFix.huelleSchliessen:
      case PreflightFix.texturVerkleinern:
        await _makeRobloxReady(withRig: false);
      case PreflightFix.rigHerrichten:
        await _makeRobloxReady(withRig: true);
      case PreflightFix.keine:
        messenger.showSnackBar(const SnackBar(
            content: Text('Dafür gibt es keine Reparatur in der App.')));
    }
  }

  /// Der Dreiecksbudget-Regler als Blatt von unten.
  Future<void> _openBudget() async {
    final mesh = _mesh;
    if (mesh == null) return;
    final ergebnis = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BudgetSheet(
        glb: widget.glbBytes,
        triangles: mesh.indices.length ~/ 3,
        hasRig: mesh.rig != null,
      ),
    );
    if (ergebnis == null || !mounted) return;
    widget.onGlbUpdated?.call(ergebnis);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: ergebnis,
        title: widget.title,
        provenance: widget.provenance,
        onGlbUpdated: widget.onGlbUpdated,
        showExport: widget.showExport,
      ),
    ));
  }

  /// Das Modell in einem Zug Roblox-konform machen.
  ///
  /// Bisher lag das nur im 3D-Tab, am frisch erzeugten Ergebnis. Ein
  /// abgelegtes Modell – aus Blender, aus dem Marktplatz, aus einem
  /// alten Lauf – kam da nie an. Hier steht es an der Datei selbst:
  ///
  /// * **Riggen.** Ohne Skelett wird erst eines eingebaut (derselbe
  ///   Weg wie „Skelett nachträglich einbauen"), danach werden die
  ///   Knochen auf die R15-Namen gebracht und Root sowie
  ///   HumanoidRootNode eingezogen.
  /// * **Anpassen.** Löcher schließen, Wicklung vereinheitlichen,
  ///   Texturen auf 1024 verkleinern, auf 5 Studs bringen, Nullpunkt
  ///   an die Hüfte, Blick nach vorn.
  ///
  /// Beides zusammen ist der Knopf „Roblox-konform machen"; wer nur
  /// die Geometrie will, nimmt „Nur anpassen".
  Future<void> _makeRobloxReady({required bool withRig}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var glb = widget.glbBytes;
    var rigType = widget.rigType;
    var unrigged = widget.unriggedGlb;
    final schritte = <String>[];

    // 1. Skelett – nur, wenn gewünscht und noch keines da ist.
    if (withRig && _mesh?.rig == null) {
      RigShape shape;
      try {
        shape = measureRigShapeOfGlb(glb);
      } on Exception catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('Kein Skelett möglich: '
                '${e.toString().replaceFirst('Exception: ', '')}')));
        return;
      }
      if (!mounted) return;
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) =>
            _RigTypeDialog(guesses: guessRigType(shape), shape: shape),
      );
      if (chosen == null || !mounted) return;
      try {
        unrigged = glb;
        glb = injectAutoRig(glb,
            rigType: chosen, knownFrontSign: _mesh?.rig?.frontSign);
        rigType = chosen;
        schritte.add('Skelett eingebaut (Typ: $chosen).');
      } on Exception catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('Rigging fehlgeschlagen: '
                '${e.toString().replaceFirst('Exception: ', '')}')));
        return;
      }
    }

    // 2. Geometrie und Textur – in dieser Reihenfolge, weil das
    // Schließen von Löchern die Indexliste ändert.
    try {
      final fixed = fixGlbForRoblox(glb, closeHoles: true, fixWinding: true);
      if (fixed.report.filledHoles > 0) {
        schritte.add('${fixed.report.filledHoles} Loch/Löcher '
            'geschlossen (${fixed.report.addedTriangles} neue Dreiecke, '
            'keine neuen Vertices).');
      }
      if (fixed.report.flippedFaces > 0) {
        schritte.add('${fixed.report.flippedFaces} Fläche(n) in die '
            'einheitliche Wicklung gedreht.');
      }
      final small =
          await shrinkGlbTextures(fixed.glb, maxSize: robloxMaxTexture);
      for (final change in small.changed) {
        schritte.add('Textur von ${change.fromWidth} auf '
            '${change.toWidth} px verkleinert.');
      }
      glb = small.glb;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }

    // 3. Skelett und Maßstab – nur sinnvoll, wenn eines da ist.
    if (withRig) {
      try {
        final prepared =
            prepareRigForRoblox(glb, targetStuds: robloxCharacterStuds);
        glb = prepared.glb;
        schritte.addAll(robloxPrepareSummary(prepared.report));
      } catch (e) {
        // Ohne Skelett wirft prepareRigForRoblox – die Geometrie ist
        // trotzdem schon in Ordnung, das soll nicht verloren gehen.
        schritte.add('Kein Skelett gefunden – Maßstab und Knochen '
            'blieben unangetastet.');
      }
    }

    if (!mounted) return;
    if (schritte.isEmpty) {
      schritte.add('Es war schon alles in Ordnung – nichts zu ändern.');
    }
    final uebernehmen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Für Roblox angepasst'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final schritt in schritte)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(schritt)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Die Prüfung darüber („Für Roblox prüfen") sagt, was '
                  'danach noch offen ist. Was die App nicht kann: FBX '
                  'schreiben und in Studio hochladen – dafür die GLB in '
                  'Blender öffnen.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Verwerfen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    if (uebernehmen != true || !mounted) return;
    widget.onGlbUpdated?.call(glb);
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: glb,
        title: widget.title,
        provenance: widget.provenance,
        unriggedGlb: unrigged,
        rigType: rigType,
        onGlbUpdated: widget.onGlbUpdated,
        showExport: widget.showExport,
      ),
    ));
  }

  Future<void> _editRig() async {
    final unrigged = widget.unriggedGlb;
    final rigType = widget.rigType;
    if (unrigged == null || rigType == null) return;
    final navigator = Navigator.of(context);
    final edited = await navigator.push<RigEditResult>(MaterialPageRoute(
      builder: (_) => RigEditScreen(
        unriggedGlb: unrigged,
        rigType: rigType,
        title: widget.title,
        // Blickrichtung aus dem bestehenden Rig weitergeben, damit der
        // Editor dasselbe Skelett (inkl. Spiegelung) rekonstruiert.
        knownFrontSign: _mesh?.rig?.frontSign,
        initialJointPositions: _currentJointPositions(),
        initialInfluence: widget.rigInfluence,
      ),
    ));
    if (edited == null || !mounted) return;
    widget.onGlbUpdated?.call(edited.glb);
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: edited.glb,
        title: widget.title,
        provenance: widget.provenance,
        unriggedGlb: unrigged,
        rigType: rigType,
        rigInfluence: edited.influence,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Modell-Viewer'),
            Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (widget.showExport)
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
                      child: Stack(
                        children: [
                          Positioned.fill(
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
                                    _rotX =
                                        _rotX.clamp(-math.pi, math.pi);
                                    if (details.scale != 1.0) {
                                      _zoom = (_zoom *
                                              (details.scale /
                                                  _lastScale))
                                          .clamp(0.3, 8.0);
                                      _lastScale = details.scale;
                                    }
                                  });
                                },
                                child: ClipRect(
                                  child: CustomPaint(
                                    painter: MeshPainter(
                                      mesh: mesh,
                                      positions: _posedPositions ??
                                          mesh.positions,
                                      normals:
                                          _posedNormals ?? mesh.normals,
                                      skeleton: _showSkeleton
                                          ? _jointPositions
                                          : null,
                                      skeletonParents: rig?.jointParents,
                                      rotX: _rotX,
                                      rotY: _rotY,
                                      zoom: _zoom,
                                      background: theme.colorScheme
                                          .surfaceContainerHighest,
                                      // Verlauf statt Fläche und ein
                                      // weicher Bodenschatten: Damit
                                      // hat das Bild ein Oben und ein
                                      // Unten, und das Modell steht
                                      // statt zu schweben.
                                      backgroundBottom: theme
                                          .colorScheme.surfaceContainerLow,
                                      groundShadow: true,
                                    ),
                                    size: Size.infinite,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Seitliche Icon-Leiste: Animationen direkt
                          // anwählbar (statt Dropdown).
                          if (rig != null && _hasClips)
                            Positioned(
                              right: 8,
                              top: 8,
                              bottom: 8,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _animationStrip(theme),
                              ),
                            ),
                          // Linke Werkzeugleiste: Skelett, Rig, Ansicht.
                          Positioned(
                            left: 8,
                            top: 8,
                            child: _toolRail(theme, rig),
                          ),
                        ],
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
                            if (_procClips.isNotEmpty)
                              Expanded(
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text(
                                      'Animationen ans Modell hängen'),
                                  subtitle: const Text(
                                      'Bettet die Testanimationen als '
                                      'loopbare glTF-Clips in die '
                                      'GLB-Datei ein (Export)'),
                                  value: _embedAnimations,
                                  onChanged: (v) => _setEmbed(v),
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

/// Auswahl des Skeletts beim nachträglichen Rigging.
///
/// Oben steht, was die Form hergibt – mit der Begründung, damit die
/// Empfehlung nachprüfbar bleibt und nicht wie ein Orakel wirkt.
/// Darunter stehen alle Typen zur freien Wahl; erkannt **oder**
/// gewählt, beides führt zum selben Skelett.
class _RigTypeDialog extends StatefulWidget {
  const _RigTypeDialog({required this.guesses, required this.shape});

  final List<RigTypeGuess> guesses;
  final RigShape shape;

  @override
  State<_RigTypeDialog> createState() => _RigTypeDialogState();
}

class _RigTypeDialogState extends State<_RigTypeDialog> {
  late String _type =
      widget.guesses.isEmpty ? 'biped' : widget.guesses.first.type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = widget.guesses.isEmpty ? null : widget.guesses.first;
    final rule = rigTypePromptRules[_type];
    return AlertDialog(
      title: const Text('Skelett einbauen'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: best == null
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        best == null
                            ? Icons.help_outline
                            : best.solid
                                ? Icons.check_circle_outline
                                : Icons.lightbulb_outline,
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            best == null
                                ? 'Kein Typ erkannt'
                                : best.solid
                                    ? 'Erkannt: ${_label(best.type)}'
                                    : 'Vermutlich: ${_label(best.type)}',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            best?.reason ?? rigDetectFallback(widget.shape),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Weitere Kandidaten, wenn die Form mehrdeutig ist.
              if (widget.guesses.length > 1) ...[
                const SizedBox(height: 8),
                Text('Käme auch in Frage:',
                    style: theme.textTheme.labelMedium),
                for (final guess in widget.guesses.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• ${_label(guess.type)} – ${guess.reason}',
                        style: theme.textTheme.bodySmall),
                  ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Skelett',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final (value, label) in rigTypeOptions)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (value) =>
                    setState(() => _type = value ?? _type),
              ),
              if (rule != null) ...[
                const SizedBox(height: 12),
                Text('Damit das Skelett greift:',
                    style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(rule, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 12),
              Text(
                'Das Netz bleibt unverändert – es kommen nur Knochen '
                'und Gewichte hinzu. Passt das Ergebnis nicht, lassen '
                'sich die Gelenke danach im Rig-Editor verschieben.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_type),
          child: const Text('Einbauen'),
        ),
      ],
    );
  }

  static String _label(String type) {
    for (final (value, label) in rigTypeOptions) {
      if (value == type) return label;
    }
    return type;
  }
}


/// Der Dreiecksbudget-Regler.
///
/// Der Zähler und die Ampel folgen dem Regler sofort – gerechnet wird
/// erst beim Übernehmen. Das ist Absicht: Die Reduktion sucht ihr
/// Raster binär und braucht bei einem großen Netz spürbar Zeit; bei
/// jedem Reglerschritt neu zu rechnen machte den Regler unbenutzbar.
class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({
    required this.glb,
    required this.triangles,
    required this.hasRig,
  });

  final Uint8List glb;
  final int triangles;

  /// Ob ein Skelett drinsteckt – dann warnt das Blatt, denn beim
  /// Zusammenlegen von Punkten gehen die Gewichte verloren.
  final bool hasRig;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late double _regler = 1.0;
  String _typ = 'rigidAccessory';
  bool _laeuft = false;

  int get _ziel => targetForSlider(_regler, widget.triangles);

  AssetSpec get _spec =>
      robloxSpecs[_typ] ?? robloxSpecs.assetTypes.values.first;

  Future<void> _anwenden() async {
    setState(() => _laeuft = true);
    try {
      final klein = await decimateGlb(widget.glb, _ziel);
      if (mounted) Navigator.of(context).pop(klein);
    } catch (e) {
      if (!mounted) return;
      setState(() => _laeuft = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reduzieren fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urteil = budgetVerdict(_ziel, _spec);
    final farbe = switch (urteil.light) {
      BudgetLight.gruen => Colors.green.shade700,
      BudgetLight.gelb => Colors.orange.shade800,
      BudgetLight.rot => theme.colorScheme.error,
    };
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dreiecksbudget', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Gilt für jede GLB, egal von welchem Anbieter sie kommt. '
            'Das Face-Limit von Tripo bleibt davon unberührt – das '
            'wirkt vorher, beim Erzeugen.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            initialSelection: _typ,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Asset-Typ'),
            dropdownMenuEntries: [
              for (final spec in robloxSpecs.assetTypes.values)
                DropdownMenuEntry(
                    value: spec.id,
                    label: '${spec.label} (${spec.triangles})'),
            ],
            onSelected: (value) {
              if (value != null) setState(() => _typ = value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.circle, size: 14, color: farbe),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_ziel Dreiecke '
                  '${_ziel == widget.triangles ? '(unverändert)' : 'statt '
                      '${widget.triangles}'}',
                  style: theme.textTheme.titleSmall?.copyWith(color: farbe),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: urteil.fill.clamp(0.0, 1.0),
            color: farbe,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 6),
          Text(urteil.text,
              style: theme.textTheme.bodySmall?.copyWith(color: farbe)),
          Slider(
            value: _regler,
            onChanged:
                _laeuft ? null : (v) => setState(() => _regler = v),
          ),
          if (widget.hasRig)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dieses Modell hat ein Skelett. Beim Reduzieren '
                      'werden Punkte zusammengelegt, und welchem '
                      'Knochen der neue Punkt gehört, lässt sich nicht '
                      'mitteln – das Skelett geht dabei verloren. '
                      'Erst reduzieren, dann riggen.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _laeuft || _spec.triangles <= 0
                    ? null
                    : () => setState(() => _regler = sliderForTarget(
                        (_spec.triangles * 0.85).round(),
                        widget.triangles)),
                child: const Text('Aufs Budget setzen'),
              ),
              TextButton(
                onPressed:
                    _laeuft ? null : () => setState(() => _regler = 1.0),
                child: const Text('Zurücksetzen'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _laeuft ? null : () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _laeuft || _ziel >= widget.triangles
                    ? null
                    : _anwenden,
                icon: _laeuft
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: Text(_laeuft ? 'Rechnet …' : 'Übernehmen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Der Preflight-Bericht als Blatt von unten.
///
/// Zwei Stufen, nach Wichtigkeit sortiert: Was in der Praxis zur
/// Ablehnung führt, steht oben. Jeder Punkt sagt, warum – und wo die
/// App reparieren kann, steht der Knopf daneben.
class _PreflightSheet extends StatefulWidget {
  const _PreflightSheet({required this.glb});

  final Uint8List glb;

  @override
  State<_PreflightSheet> createState() => _PreflightSheetState();
}

class _PreflightSheetState extends State<_PreflightSheet> {
  String _typ = 'rigidAccessory';
  PreflightReport? _report;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _pruefen();
  }

  AssetSpec get _spec =>
      robloxSpecs[_typ] ?? robloxSpecs.assetTypes.values.first;

  Future<void> _pruefen() async {
    setState(() {
      _report = null;
      _fehler = null;
    });
    try {
      final r = await preflightGlb(widget.glb, spec: _spec);
      if (mounted) setState(() => _report = r);
    } catch (e) {
      if (mounted) setState(() => _fehler = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preflight', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownMenu<String>(
              initialSelection: _typ,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Asset-Typ'),
              dropdownMenuEntries: [
                for (final spec in robloxSpecs.assetTypes.values)
                  DropdownMenuEntry(value: spec.id, label: spec.label),
              ],
              onSelected: (value) {
                if (value == null) return;
                setState(() => _typ = value);
                _pruefen();
              },
            ),
            const SizedBox(height: 12),
            if (_fehler != null)
              Text('Prüfung fehlgeschlagen: $_fehler',
                  style: TextStyle(color: theme.colorScheme.error))
            else if (report == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Row(
                children: [
                  Icon(
                      report.blocked
                          ? Icons.block
                          : Icons.check_circle_outline,
                      size: 20,
                      color: report.blocked
                          ? theme.colorScheme.error
                          : Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(report.summary,
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: report.blocked
                                ? theme.colorScheme.error
                                : null)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: report.issues.length,
                  itemBuilder: (context, i) {
                    final issue = report.issues[i];
                    final (icon, farbe) = switch (issue.severity) {
                      PreflightSeverity.fehler => (
                          Icons.error_outline,
                          theme.colorScheme.error
                        ),
                      PreflightSeverity.warnung => (
                          Icons.warning_amber_outlined,
                          Colors.orange.shade800
                        ),
                      PreflightSeverity.hinweis => (
                          Icons.info_outline,
                          theme.colorScheme.outline
                        ),
                      PreflightSeverity.ok => (
                          Icons.check,
                          Colors.green.shade700
                        ),
                    };
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 18, color: farbe),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(issue.title,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(color: farbe)),
                                if (issue.reason.isNotEmpty)
                                  Text(issue.reason,
                                      style: theme.textTheme.bodySmall),
                                if (issue.fix != PreflightFix.keine)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => Navigator.of(context)
                                          .pop(issue.fix),
                                      icon: const Icon(Icons.build_outlined,
                                          size: 16),
                                      label: Text(switch (issue.fix) {
                                        PreflightFix.reduzieren =>
                                          'Dreiecke reduzieren',
                                        PreflightFix.huelleSchliessen =>
                                          'Hülle schließen',
                                        PreflightFix.texturVerkleinern =>
                                          'Textur verkleinern',
                                        PreflightFix.rigHerrichten =>
                                          'Für Roblox anpassen',
                                        PreflightFix.keine => '',
                                      }),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: preflightAsText(report, _spec))),
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Bericht kopieren'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Schließen'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
