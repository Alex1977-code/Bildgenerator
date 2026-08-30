import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../models/models.dart';
import '../services/animation_bake.dart';
import '../services/auto_rig.dart';
import '../services/balance_service.dart';
import '../services/cost_estimator.dart';
import '../services/exporter.dart';
import '../services/fal_service.dart';
import '../services/generators.dart' show GenerationException;
import '../services/glb_preview.dart';
import '../services/history_service.dart';
import '../services/local_3d.dart';
import '../services/mesh_check.dart';
import '../services/meshy_service.dart';
import '../services/model_import.dart';
import '../services/model_refine.dart';
import '../services/obj_export.dart';
import '../services/preview_animations.dart';
import '../services/provenance.dart';
import '../services/replicate_service.dart';
import '../services/rodin_service.dart';
import '../services/stl_export.dart';
import '../services/threemf_export.dart';
import '../widgets/print_size_dialog.dart';
import '../services/self_host_service.dart';
import '../services/settings_service.dart';
import '../services/stability_3d_service.dart';
import '../services/tripo_service.dart';
import '../services/view_generator.dart';
import '../widgets/common.dart';
import '../widgets/cost_quality_panel.dart';
import 'image_detail_screen.dart';
import 'model_preview_screen.dart';

/// 3D-Bereich: Figuren und Objekte aus Text oder Bild generieren
/// (Meshy AI), optional mit Textur und Auto-Rigging, Export als GLB.
class ThreeDScreen extends StatefulWidget {
  const ThreeDScreen({
    super.key,
    required this.onOpenSettings,
    this.isActive = true,
  });

  final VoidCallback onOpenSettings;

  /// Ob dieser Tab gerade sichtbar ist (siehe GeneratorScreen.isActive).
  final bool isActive;

  @override
  State<ThreeDScreen> createState() => _ThreeDScreenState();
}

class _ThreeDScreenState extends State<ThreeDScreen> {
  final _promptCtrl = TextEditingController();

  /// Negativ-Prompt für natives Text→3D (Meshy/Tripo): was das Modell
  /// vermeiden soll (z. B. „blobby, floating parts, base, pedestal“).
  final _negative3dCtrl = TextEditingController();
  final _picker = ImagePicker();

  bool _imageMode = true;
  /// Ansichten: 'front' ist Pflicht, 'left'/'right'/'back' optional
  /// für Rundum-Modelle.
  final Map<String, ReferenceImage?> _views = {
    'front': null,
    'left': null,
    'right': null,
    'back': null,
  };

  ReferenceImage? get _front => _views['front'];

  List<ReferenceImage> get _extraViews => [
        for (final key in ['left', 'right', 'back'])
          if (_views[key] != null) _views[key]!,
      ];
  bool _texture = true;
  bool _rigging = true;
  String _artStyle = 'realistic';

  /// Text-Modus bei Meshy/Tripo: statt des nativen Text→3D erst
  /// konsistente Ansichten-Bilder per Bild-KI erzeugen und daraus das
  /// Modell bauen. Beim lokalen Generator ist das im Text-Modus immer so.
  bool _viewsFromText = false;

  /// T-Pose auch ohne Rigging – Figuren mit gespreizten Armen lassen
  /// sich deutlich besser räumlich rekonstruieren.
  bool _tPose = false;

  /// Bild-Modus: fehlende Ansichten (links/rechts/hinten) automatisch
  /// per Bild-KI aus der Vorderansicht ergänzen, damit ein konsistenter
  /// 4-Ansichten-Satz als Referenz entsteht.
  bool _completeViews = true;

  // Qualitäts-Optionen (Profi) für Meshy/Tripo. Leer/0/auto = die
  // API-Vorgabe wird nicht überschrieben.
  String _meshyAiModel = '';

  /// Meshy 7 Ultra Mode: maximale Geometrie-Treue (nur Einzelbild→3D).
  bool _meshyUltra = false;
  int _meshyPolycount = 0;
  String _symmetryMode = 'auto';
  bool _quadTopology = false; // Meshy topology=quad bzw. Tripo quad=true
  bool _pbr = true;
  String _tripoVersion = '';
  bool _tripoDetailedTexture = false;
  final _texturePromptCtrl = TextEditingController();

  /// fal.ai: gewähltes Katalog-Modell plus optionale eigene Modell-ID
  /// (überschreibt den Katalog – für neue Marktplatz-Modelle).
  String _falModel = 'fal-ai/trellis';
  final _falCustomCtrl = TextEditingController();

  String get _falModelEffective {
    final custom = _falCustomCtrl.text.trim();
    return custom.isNotEmpty ? custom : _falModel;
  }

  /// Replicate: gewähltes Katalog-Modell plus optionale eigene
  /// Modell-Kennung „owner/name“ oder „owner/name:version“
  /// (überschreibt den Katalog).
  String _replicateModel = 'firtoz/trellis';
  final _replicateCustomCtrl = TextEditingController();

  String get _replicateModelEffective {
    final custom = _replicateCustomCtrl.text.trim();
    return custom.isNotEmpty ? custom : _replicateModel;
  }

  /// Eigener Server: Qualitäts-Optionen, die das laufende Backend
  /// laut /health unterstützt (siehe SelfHostService.lastCapabilities).
  int _serverTextureRes = 1024;
  String _serverRemesh = 'none';
  int _serverTargetCount = 0;
  int _serverResolution = 256;
  bool _serverBakeTexture = true;

  /// Rodin (Hyper3D): Generation/Tier ('' = API-Vorgabe),
  /// Quad-Topologie (Standard – ideal für Game-Assets) und optionale
  /// Ziel-Polygonzahl (0 = API-Vorgabe).
  String _rodinTier = '';
  bool _rodinQuad = true;
  int _rodinPolycount = 0;

  String _stabilityEngine = 'stable-point-aware-3d';
  int _stabilityTextureRes = 2048;

  /// Stability: Polygonform ('none', 'quad', 'triangle'), optionale
  /// Ziel-Polygonzahl (0 = keine Reduktion) und Detailgrad-Vorwahl.
  String _stabilityRemesh = 'none';
  int _stabilityPolycount = 0;
  String _stabilityDetail = 'auto'; // 'auto' | 'fine' | 'safe'

  /// Veredelung (lokale Nachbearbeitung): schwächere Modellhälfte
  /// durch die gespiegelte bessere ersetzen (Fahrzeuge & symmetrische
  /// Motive).
  bool _refineSymmetrize = false;

  /// Veredelung: das scharfe Ausgangsbild zurück auf die sichtbare
  /// Seite projizieren (ersetzt dort die weiche Stability-Textur).
  bool _refineProjectTexture = true;

  /// Lokaler Generator: Vertiefungen per KI-Tiefenkarte formen.
  bool _localDepthAi = false;

  /// Figurtyp fürs eigene Auto-Rigging (Lokal/Stability), siehe
  /// [rigTypeOptions]: Zweibeiner, Vierbeiner, Insekt, Vogel, Schlange,
  /// Fisch.
  String _rigType = 'biped';

  // Optionen des lokalen Generators (360°-Modell).
  int _localResolution = 96;
  int _localTargetTriangles = 0; // 0 = alle Polygone behalten
  int _localSmoothing = 2; // Glättungsdurchläufe 0–5
  String _localSurface = 'matt';

  /// Textur-Modus des lokalen Generators: hochauflösender Atlas
  /// (2048/1024 px) oder kompakte Vertex-Farben.
  String _localTextureMode = 'atlas2048';

  /// Zuletzt angewendete Vorlage als Anzeigetext (nur informativ –
  /// danach lassen sich alle Optionen weiterhin einzeln ändern).
  String? _lastPresetInfo;

  /// Bewährte Voreinstellungen: (Kennung, Name, Symbol, 3D-Provider,
  /// Kurzbeschreibung). Eine Vorlage setzt Provider, Modell und alle
  /// Qualitäts-Optionen in einem Rutsch auf eine erprobte Kombination.
  static const _presets = <(String, String, IconData, String, String)>[
    (
      'vehicle',
      'Fahrzeug (Game-Asset)',
      Icons.directions_car_outlined,
      'rodin',
      'Rodin Gen-2.5 High, Quad-Netz mit ca. 10.000 Polygonen, '
          'Fahrzeug-Rig mit automatischer Rad-Erkennung, symmetrisiert'
    ),
    (
      'figure',
      'Figur (Game-Asset)',
      Icons.person_outline,
      'rodin',
      'Rodin Gen-2.5 High mit T/A-Pose, Quad-Netz mit ca. 30.000 '
          'Polygonen, Zweibeiner-Skelett aus dem eigenen Auto-Rigger'
    ),
    (
      'quicktest',
      'Schnelltest',
      Icons.bolt_outlined,
      'fal',
      'fal.ai TRELLIS aus einem Bild – wenige Cent pro Lauf, ideal '
          'zum Ausprobieren von Beschreibung und Ansicht'
    ),
    (
      'owngpu',
      'Eigene GPU',
      Icons.memory,
      'selfhost',
      'Eigener Server (TripoSR/TRELLIS) – kostet nur Strom, alle '
          'Bilder bleiben auf dem eigenen PC'
    ),
    (
      'topquality',
      'Höchste Detailtreue',
      Icons.auto_awesome_outlined,
      'meshy',
      'Meshy 7 mit Ultra Mode und Quad-Topologie – die schärfsten '
          'Texturen, dafür der teuerste Lauf'
    ),
    (
      'print3d',
      '3D-Druck',
      Icons.print_outlined,
      'local',
      'Lokaler Generator mit 128er-Raster und KI-Tiefenkarten, ohne '
          'Skelett – geschlossene Form für den Druck-Export'
    ),
  ];

  /// Wendet eine Vorlage an. Danach bleibt alles weiterhin einzeln
  /// änderbar – die Vorlage ist nur ein guter Startpunkt.
  void _applyPreset(String id) {
    final settings = context.read<SettingsService>();
    final preset = _presets.firstWhere((p) => p.$1 == id);
    final previousSubject = _promptSubject;
    settings.setThreeDProvider(preset.$4);
    setState(() {
      _lastPresetInfo = '${preset.$2} – ${preset.$5}';
      // Gemeinsame Grundlage aller Vorlagen.
      _texture = true;
      _pbr = true;
      _refineProjectTexture = true;
      _refineSymmetrize = false;
      _tPose = false;
      _falCustomCtrl.clear();
      _replicateCustomCtrl.clear();
      switch (id) {
        case 'vehicle':
          _promptSubject = 'object';
          _rigging = true;
          _rigType = 'vehicle';
          _rodinTier = 'Gen-2.5-High';
          _rodinQuad = true;
          _rodinPolycount = 10000;
          // Fahrzeuge sind symmetrisch – die vom Foto abgewandte
          // Hälfte gewinnt dadurch deutlich.
          _refineSymmetrize = true;
        case 'figure':
          _promptSubject = 'figure';
          _rigging = true;
          _rigType = 'biped';
          _rodinTier = 'Gen-2.5-High';
          _rodinQuad = true;
          _rodinPolycount = 30000;
        case 'quicktest':
          _falModel = 'fal-ai/trellis';
          _rigging = false;
        case 'owngpu':
          _rigging = false;
        case 'topquality':
          _meshyAiModel = 'meshy-7';
          _meshyUltra = true;
          _quadTopology = true;
          _meshyPolycount = 0;
          _symmetryMode = 'auto';
          _rigging = false;
        case 'print3d':
          _rigging = false;
          _localResolution = 128;
          _localSmoothing = 3;
          _localTargetTriangles = 0;
          _localDepthAi = true;
          _localSurface = 'matt';
      }
      // Figur und Objekt brauchen unterschiedliche Ansichten – eine
      // automatisch erzeugte Kachel würde sonst still weiterverwendet.
      if (_promptSubject != previousSubject &&
          _views['front']?.name == 'ansicht_Vorn.png') {
        _views['front'] = null;
      }
    });
    // Fehlenden Zugang sofort melden statt erst beim Generieren.
    final access = switch (preset.$4) {
      'rodin' => settings.rodinApiKey,
      'fal' => settings.falApiKey,
      'meshy' => settings.meshyApiKey,
      'selfhost' => settings.selfHostUrl,
      _ => 'ok',
    };
    final missing = (access ?? '').trim().isEmpty;
    _showSnack('Vorlage „${preset.$2}“: ${preset.$5}.'
        '${missing ? ' Achtung: Der Zugang für diesen Anbieter fehlt '
            'noch – bitte in den Einstellungen hinterlegen.' : ''}');
  }

  /// Alle Einstellungen des 3D-Tabs als speicherbare Karte – die
  /// Grundlage der eigenen Vorlagen.
  Map<String, dynamic> _snapshotSettings(SettingsService settings) => {
        'provider': settings.threeDProvider,
        'imageMode': _imageMode,
        'promptSubject': _promptSubject,
        'texture': _texture,
        'rigging': _rigging,
        'rigType': _rigType,
        'tPose': _tPose,
        'artStyle': _artStyle,
        'viewsFromText': _viewsFromText,
        'completeViews': _completeViews,
        'negativePrompt': _negative3dCtrl.text,
        'texturePrompt': _texturePromptCtrl.text,
        'meshyAiModel': _meshyAiModel,
        'meshyUltra': _meshyUltra,
        'meshyPolycount': _meshyPolycount,
        'symmetryMode': _symmetryMode,
        'quadTopology': _quadTopology,
        'pbr': _pbr,
        'tripoVersion': _tripoVersion,
        'tripoDetailedTexture': _tripoDetailedTexture,
        'falModel': _falModel,
        'falCustom': _falCustomCtrl.text,
        'replicateModel': _replicateModel,
        'replicateCustom': _replicateCustomCtrl.text,
        'rodinTier': _rodinTier,
        'rodinQuad': _rodinQuad,
        'rodinPolycount': _rodinPolycount,
        'stabilityEngine': _stabilityEngine,
        'stabilityTextureRes': _stabilityTextureRes,
        'stabilityRemesh': _stabilityRemesh,
        'stabilityPolycount': _stabilityPolycount,
        'stabilityDetail': _stabilityDetail,
        'refineSymmetrize': _refineSymmetrize,
        'refineProjectTexture': _refineProjectTexture,
        'localDepthAi': _localDepthAi,
        'localResolution': _localResolution,
        'localTargetTriangles': _localTargetTriangles,
        'localSmoothing': _localSmoothing,
        'localSurface': _localSurface,
        'localTextureMode': _localTextureMode,
      };

  /// Setzt eine gespeicherte Karte wieder ein. Unbekannte oder
  /// beschädigte Werte behalten den aktuellen Stand – so bleiben auch
  /// Vorlagen aus älteren App-Versionen brauchbar.
  void _restoreSettings(
      Map<String, dynamic> data, SettingsService settings) {
    T pick<T>(String key, T fallback) {
      final value = data[key];
      return value is T ? value : fallback;
    }

    final previousSubject = _promptSubject;
    settings.setThreeDProvider(pick('provider', settings.threeDProvider));
    setState(() {
      _imageMode = pick('imageMode', _imageMode);
      _promptSubject = pick('promptSubject', _promptSubject);
      _texture = pick('texture', _texture);
      _rigging = pick('rigging', _rigging);
      _rigType = pick('rigType', _rigType);
      _tPose = pick('tPose', _tPose);
      _artStyle = pick('artStyle', _artStyle);
      _viewsFromText = pick('viewsFromText', _viewsFromText);
      _completeViews = pick('completeViews', _completeViews);
      _negative3dCtrl.text = pick('negativePrompt', _negative3dCtrl.text);
      _texturePromptCtrl.text =
          pick('texturePrompt', _texturePromptCtrl.text);
      _meshyAiModel = pick('meshyAiModel', _meshyAiModel);
      _meshyUltra = pick('meshyUltra', _meshyUltra);
      _meshyPolycount = pick('meshyPolycount', _meshyPolycount);
      _symmetryMode = pick('symmetryMode', _symmetryMode);
      _quadTopology = pick('quadTopology', _quadTopology);
      _pbr = pick('pbr', _pbr);
      _tripoVersion = pick('tripoVersion', _tripoVersion);
      _tripoDetailedTexture =
          pick('tripoDetailedTexture', _tripoDetailedTexture);
      _falModel = pick('falModel', _falModel);
      _falCustomCtrl.text = pick('falCustom', _falCustomCtrl.text);
      _replicateModel = pick('replicateModel', _replicateModel);
      _replicateCustomCtrl.text =
          pick('replicateCustom', _replicateCustomCtrl.text);
      _rodinTier = pick('rodinTier', _rodinTier);
      _rodinQuad = pick('rodinQuad', _rodinQuad);
      _rodinPolycount = pick('rodinPolycount', _rodinPolycount);
      _stabilityEngine = pick('stabilityEngine', _stabilityEngine);
      _stabilityTextureRes =
          pick('stabilityTextureRes', _stabilityTextureRes);
      _stabilityRemesh = pick('stabilityRemesh', _stabilityRemesh);
      _stabilityPolycount = pick('stabilityPolycount', _stabilityPolycount);
      _stabilityDetail = pick('stabilityDetail', _stabilityDetail);
      _refineSymmetrize = pick('refineSymmetrize', _refineSymmetrize);
      _refineProjectTexture =
          pick('refineProjectTexture', _refineProjectTexture);
      _localDepthAi = pick('localDepthAi', _localDepthAi);
      _localResolution =
          pick<int>('localResolution', _localResolution).clamp(48, 160);
      _localTargetTriangles =
          pick('localTargetTriangles', _localTargetTriangles);
      _localSmoothing =
          pick<int>('localSmoothing', _localSmoothing).clamp(0, 5);
      _localSurface = pick('localSurface', _localSurface);
      _localTextureMode = pick('localTextureMode', _localTextureMode);
      // Figur und Objekt brauchen unterschiedliche Ansichten – eine
      // automatisch erzeugte Kachel würde sonst still weiterverwendet.
      if (_promptSubject != previousSubject &&
          _views['front']?.name == 'ansicht_Vorn.png') {
        _views['front'] = null;
      }
    });
  }

  /// Name einer eigenen Vorlage (null = freier Platz).
  String? _customPresetName(SettingsService settings, int index) {
    final raw = settings.customPresets[index];
    if (raw.isEmpty) return null;
    try {
      final name =
          ((jsonDecode(raw) as Map<String, dynamic>)['name'] as String?)
              ?.trim();
      return (name == null || name.isEmpty)
          ? 'Vorlage ${index + 1}'
          : name;
    } catch (_) {
      return 'Vorlage ${index + 1}';
    }
  }

  void _applyCustomPreset(int index, SettingsService settings) {
    final name = _customPresetName(settings, index) ?? 'Vorlage';
    try {
      _restoreSettings(
          jsonDecode(settings.customPresets[index]) as Map<String, dynamic>,
          settings);
    } catch (_) {
      _showSnack('Die Vorlage „$name“ konnte nicht gelesen werden.');
      return;
    }
    setState(() => _lastPresetInfo = 'eigene Vorlage „$name“');
    _showSnack('Eigene Vorlage „$name“ angewendet.');
  }

  Future<void> _saveCustomPreset(SettingsService settings) async {
    final free = settings.customPresets.indexWhere((e) => e.isEmpty);
    var slot = free >= 0 ? free : 0;
    final nameCtrl = TextEditingController(
        text: _customPresetName(settings, slot) ??
            'Eigene Vorlage ${slot + 1}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Eigene Vorlage speichern'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Sichert alle aktuellen Einstellungen des 3D-Tabs: '
                    'Anbieter, Modell, Qualitäts-Optionen, Rigging und '
                    'Veredelung.'),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name der Vorlage',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Platz (belegte werden überschrieben):'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0;
                        i < SettingsService.customPresetSlots;
                        i++)
                      ChoiceChip(
                        label: Text('${i + 1} · '
                            '${_customPresetName(settings, i) ?? 'frei'}'),
                        selected: slot == i,
                        onSelected: (_) => setDialogState(() {
                          slot = i;
                          nameCtrl.text =
                              _customPresetName(settings, i) ??
                                  'Eigene Vorlage ${i + 1}';
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (saved != true || !mounted) return;
    final label = name.isEmpty ? 'Eigene Vorlage ${slot + 1}' : name;
    settings.setCustomPreset(
        slot,
        jsonEncode({
          ..._snapshotSettings(settings),
          'name': label,
        }));
    setState(() => _lastPresetInfo = 'eigene Vorlage „$label“ (gesichert)');
    _showSnack('Eigene Vorlage „$label“ auf Platz ${slot + 1} '
        'gespeichert.');
  }

  Future<void> _deleteCustomPreset(
      int index, SettingsService settings) async {
    final name = _customPresetName(settings, index) ?? 'Vorlage';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eigene Vorlage löschen'),
        content: Text('„$name“ von Platz ${index + 1} entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    settings.setCustomPreset(index, '');
    _showSnack('Eigene Vorlage „$name“ gelöscht.');
  }

  /// Fünf frei belegbare Plätze für eigene Vorlagen.
  Widget _customPresetBar(ThemeData theme, SettingsService settings) {
    final saved = <(int, String)>[
      for (var i = 0; i < SettingsService.customPresetSlots; i++)
        if (_customPresetName(settings, i) case final name?) (i, name),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Eigene Vorlagen (${saved.length} von '
          '${SettingsService.customPresetSlots} Plätzen belegt): beliebige '
          'Kombination aus Anbieter, Modell und Optionen sichern und '
          'jederzeit zurückholen – bleibt auch nach einem Neustart '
          'erhalten.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (index, name) in saved)
              InputChip(
                avatar: const Icon(Icons.bookmark_outline, size: 18),
                label: Text(name),
                onPressed: _running
                    ? null
                    : () => _applyCustomPreset(index, settings),
                onDeleted: _running
                    ? null
                    : () => _deleteCustomPreset(index, settings),
                deleteButtonTooltipMessage: 'Vorlage löschen',
              ),
            ActionChip(
              avatar: const Icon(Icons.save_outlined, size: 18),
              label: Text(saved.length >= SettingsService.customPresetSlots
                  ? 'Platz überschreiben'
                  : 'Aktuelle Einstellungen sichern'),
              onPressed: _running ? null : () => _saveCustomPreset(settings),
            ),
          ],
        ),
      ],
    );
  }

  /// Oberflächen-Vorwahlen (PBR): (Wert, Name, Metall, Rauheit).
  static const _surfaceOptions = [
    ('matt', 'Matt (Standard)', 0.0, 0.95),
    ('silk', 'Seidenmatt', 0.0, 0.6),
    ('gloss', 'Glänzend', 0.0, 0.3),
    ('metal', 'Metallisch', 0.9, 0.35),
  ];

  bool _running = false;
  bool _cancelRequested = false;
  String? _stage;
  String? _error;
  String? _usageInfo;
  final List<ThreeDResult> _results = [];

  /// Kopierbare Anleitungen für eine externe Prompt-KI (ChatGPT,
  /// Claude & Co.): enthalten alle Regeln, damit der erzeugte Prompt
  /// perfekt zu unserer 3D-Pipeline passt. (Titel, Kurzbeschreibung,
  /// Vorlagentext).
  static const _promptTemplates = [
    (
      'Figur für Bild→3D',
      'Charakter/Person/Tier als 3D-taugliche Bildvorlage',
      'Aufgabe: Schreibe einen englischen Bild-Prompt für einen '
          'KI-Bildgenerator. Das Bild dient als Vorlage für eine '
          '3D-Rekonstruktion (Image-to-3D) – dafür gelten besondere '
          'Regeln:\n\n'
          '- GENAU EINE Figur, Ganzkörper, vollständig sichtbar mit '
          'etwas Rand – nichts anschneiden.\n'
          '- Exakte Vorderansicht, Figur schaut direkt in die Kamera, '
          'aufrecht stehend.\n'
          '- T-Pose oder A-Pose: Arme seitlich ausgestreckt, Beine '
          'leicht auseinander – Gliedmaßen dürfen Körper und Kopf '
          'NICHT berühren oder verdecken (sonst verschmelzen sie im '
          '3D-Modell).\n'
          '- Komplett transparenter oder einfarbig neutraler '
          'Hintergrund, kein Boden, kein Schatten, keine Spiegelung.\n'
          '- Gleichmäßiges, weiches Studiolicht ohne harte Schatten, '
          'keine dramatische Beleuchtung.\n'
          '- Klare, kräftige Farben, deutlich lesbare Materialien, '
          'scharfe Details.\n'
          '- KEIN Text, kein Wasserzeichen, keine Requisiten, die die '
          'Silhouette überlappen.\n'
          '- Stil nennen (z. B. Pixar-Stil, realistisch, Chibi) und '
          '2–4 markante Merkmale der Figur hervorheben.\n\n'
          'Meine Figur: [HIER BESCHREIBEN]\n\n'
          'Gib nur den fertigen englischen Prompt aus.',
    ),
    (
      'Objekt/Fahrzeug für Bild→3D',
      'Auto, Haus, Möbel, Gerät … als 3D-taugliche Bildvorlage',
      'Aufgabe: Schreibe einen englischen Bild-Prompt für einen '
          'KI-Bildgenerator. Das Bild dient als Vorlage für eine '
          '3D-Rekonstruktion (Image-to-3D) – dafür gelten besondere '
          'Regeln:\n\n'
          '- GENAU EIN freistehendes Objekt, vollständig sichtbar mit '
          'etwas Rand.\n'
          '- Dreiviertelansicht: schräg von vorn und leicht erhöht, '
          'sodass Front UND eine Seite gleichzeitig sichtbar sind. '
          'WICHTIG: KEINE reine Frontal- oder Seitenansicht ohne '
          'Perspektive – daraus rekonstruiert die 3D-KI nur eine '
          'flache Platte ohne Tiefe.\n'
          '- Bei Fahrzeugen: eben auf allen Rädern stehend, Räder '
          'sichtbar und deutlich vom Aufbau getrennt, Fahrzeugflanke '
          'im Bild.\n'
          '- Transparenter oder neutraler Hintergrund, kein Boden, '
          'kein Schatten, keine Umgebungs-Spiegelungen im Lack.\n'
          '- Gleichmäßiges, weiches Studiolicht.\n'
          '- Symmetrie betonen, klare Kanten (Hard-Surface), gut '
          'lesbare Materialien und Farben.\n'
          '- KEIN Text, Logo, Sockel, Podest und keine Person im '
          'Bild.\n\n'
          'Mein Objekt: [HIER BESCHREIBEN]\n\n'
          'Gib nur den fertigen englischen Prompt aus.',
    ),
    (
      'Motiv-Beschreibung (App erzeugt die Ansichten)',
      'Nur das Motiv – Ansicht, Pose, Licht und Hintergrund ergänzt '
          'die App selbst',
      'Aufgabe: Schreibe eine englische MOTIV-BESCHREIBUNG für eine '
          '3D-Pipeline. WICHTIG: Die App ergänzt Ansicht/Kamerawinkel, '
          'Pose, Beleuchtung und Hintergrund automatisch selbst – die '
          'Beschreibung darf NUR das Motiv enthalten:\n\n'
          '- KEINE Kamera- oder Ansichts-Wörter (front view, '
          'three-quarter, orthographic, camera, telephoto, '
          'perspective …).\n'
          '- KEINE Licht-, Hintergrund- oder Studio-Angaben (lighting, '
          'background, shadow, reflections, studio …) und KEINE '
          'Qualitäts-Floskeln (8k, photorealistic, sharp focus).\n'
          '- KEINE Pose- oder Aufstellungs-Anweisungen (T-pose, '
          'standing, facing …) – die App wählt die zum Figurtyp '
          'passende Pose.\n'
          '- Nur das Motiv: Objektklasse zuerst, dann Silhouette und '
          'Proportionen, dann markante Details, Materialien und '
          'Farben – als kommagetrennte Stichwortliste in einer '
          'Zeile.\n\n'
          'Mein Motiv: [HIER BESCHREIBEN]\n\n'
          'Gib nur die fertige englische Beschreibung aus.',
    ),
    (
      'Natives Text→3D (Meshy/Tripo)',
      'Knapper 3D-Prompt + Negativ-Prompt',
      'Aufgabe: Schreibe einen KNAPPEN englischen Text-zu-3D-Prompt '
          '(kein Bild-Prompt!). Regeln:\n\n'
          '- Reihenfolge: Objektklasse zuerst → Silhouette und '
          'Proportionen → 2–4 markante Merkmale → knappe Material-/'
          'Farbangabe.\n'
          '- KEINE Kamera-, Licht- oder Qualitätswörter („8k“, '
          '„photorealistic“, „studio lighting“) – Text-zu-3D-Modelle '
          'ignorieren sie oder werden schlechter.\n'
          '- Kurz halten: eine Zeile im Stichwort-Stil mit Kommas. '
          'Wird das Ergebnis matschig, kürzen statt ergänzen.\n'
          '- Bei Figuren ergänzen: "standing in T-pose, arms '
          'stretched out".\n'
          '- Erzeuge zusätzlich einen englischen Negativ-Prompt '
          '(z. B. "low poly, blobby, melted, floating parts, base, '
          'pedestal, text").\n\n'
          'Mein Motiv: [HIER BESCHREIBEN]\n\n'
          'Gib Prompt und Negativ-Prompt getrennt aus.',
    ),
  ];

  Future<void> _copyTemplate(String title, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showSnack('Vorlage „$title“ kopiert – bei deiner Prompt-KI '
          'einfügen und das Motiv ergänzen.');
    }
  }

  /// Motivart für die Prompt-Hilfe neben der Eingabe ('figure'/'object').
  String _promptSubject = 'figure';

  /// Prompt-Hilfe direkt an der Eingabe: Schalter Figur/Objekt und ein
  /// Knopf, der die jeweils passende Vorlage für die Prompt-KI kopiert.
  /// [mode]: 'images' = eigene Bildvorlagen (Aus Bild) → vollständige
  /// Bild-Prompts mit Kamera/Licht; 'wrapped' = die App erzeugt die
  /// Ansichten aus der Beschreibung (Lokal, Stability,
  /// Ansichten-Pipeline) → reine Motiv-Beschreibung, denn Kamera, Pose,
  /// Licht und Hintergrund hängt die App selbst an; 'native' =
  /// direktes Text→3D (Meshy/Tripo) → knapper 3D-Prompt.
  Widget _promptHelp(ThemeData theme, {required String mode}) {
    final (title, _, text) = switch (mode) {
      'images' => _promptSubject == 'figure'
          ? _promptTemplates[0]
          : _promptTemplates[1],
      'wrapped' => _promptTemplates[2],
      _ => _promptTemplates[3],
    };
    final String hint;
    if (mode == 'native') {
      hint = 'Kopiert die Anleitung für knappe native Text→3D-Prompts '
          '(inkl. Negativ-Prompt) – gilt für Figuren und Objekte.';
    } else if (mode == 'wrapped') {
      hint = 'Kopiert das Briefing „Motiv-Beschreibung“: Deine '
          'Prompt-KI liefert NUR das Motiv – Ansicht (Figur: '
          'Vorderansicht, Objekt: Dreiviertelansicht), Pose, Licht und '
          'Hintergrund ergänzt die App automatisch.';
    } else if (_promptSubject == 'figure') {
      hint = 'Kopiert das Briefing „Figur“ (Vorderansicht, T-Pose): bei '
          'deiner Prompt-KI einfügen und das Motiv ergänzen.';
    } else {
      hint = 'Kopiert das Briefing „Objekt/Fahrzeug“ '
          '(Dreiviertelansicht – aus reiner Frontalansicht entsteht nur '
          'eine flache Platte): bei deiner Prompt-KI einfügen.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (mode != 'native')
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'figure',
                      label: Text('Figur'),
                      icon: Icon(Icons.person_outline)),
                  ButtonSegment(
                      value: 'object',
                      label: Text('Objekt/Fahrzeug'),
                      icon: Icon(Icons.directions_car_outlined)),
                ],
                selected: {_promptSubject},
                showSelectedIcon: false,
                style:
                    const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (selection) => setState(() {
                  _promptSubject = selection.first;
                  // Automatisch erzeugte Vorderansicht verwerfen:
                  // Figur (frontal) und Objekt (Dreiviertelansicht)
                  // brauchen unterschiedliche Ansichten – eine alte
                  // Kachel würde sonst still wiederverwendet und den
                  // Lauf sabotieren. Eigene Bilder bleiben stehen.
                  if (_views['front']?.name == 'ansicht_Vorn.png') {
                    _views['front'] = null;
                  }
                }),
              ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Prompt-Vorlage kopieren'),
              onPressed: () => _copyTemplate(title, text),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(hint, style: theme.textTheme.bodySmall),
      ],
    );
  }

  static const _tPoseSuffix =
      'full body character in T-pose, arms stretched out horizontally, '
      'legs slightly apart, facing forward, neutral expression';

  @override
  void dispose() {
    _cancelRequested = true;
    _promptCtrl.dispose();
    _negative3dCtrl.dispose();
    _texturePromptCtrl.dispose();
    _falCustomCtrl.dispose();
    _replicateCustomCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _dragOverSlot;

  /// Öffnet abgelegte 3D-Dateien (GLB/STL/OBJ) direkt im Viewer;
  /// Bilddateien bleiben den Ansichten-Kacheln überlassen.
  Future<void> _openDroppedModel(List<XFile> files) async {
    for (final file in files) {
      final name = file.name.toLowerCase();
      if (!name.endsWith('.glb') &&
          !name.endsWith('.stl') &&
          !name.endsWith('.obj')) {
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        final glb = importModelToGlb(bytes, file.name);
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              ModelPreviewScreen(glbBytes: glb, title: file.name),
        ));
      } catch (e) {
        _showSnack('Modell konnte nicht geladen werden: '
            '${e.toString().replaceFirst('Exception: ', '')}');
      }
      return;
    }
  }

  Future<void> _dropOnSlot(String key, List<XFile> files) async {
    setState(() => _dragOverSlot = null);
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (!looksLikeSupportedImage(bytes)) continue;
      if (!mounted) return;
      setState(() {
        _views[key] = ReferenceImage(bytes: bytes, name: file.name);
      });
      return;
    }
    _showSnack('Keine unterstützte Bilddatei – bitte PNG, JPEG oder WebP '
        'ablegen.');
  }

  Future<void> _pickView(String key) async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _views[key] = ReferenceImage(bytes: bytes, name: file.name);
      });
    } catch (e) {
      _showSnack('Bild konnte nicht geladen werden: $e');
    }
  }

  Future<void> _showMissingKeyDialog(String provider) async {
    final (title, message) = switch (provider) {
      'tripo' => (
          'Tripo3D-API-Schlüssel fehlt',
          'Für Tripo3D wird ein API-Schlüssel benötigt '
              '(platform.tripo3d.ai – Bezahlung nach Verbrauch, '
              'Startguthaben für neue Konten). Bitte in den Einstellungen '
              'hinterlegen.'
        ),
      'stability' => (
          'Stability-API-Schlüssel fehlt',
          'Stability-3D nutzt denselben Stability-AI-Schlüssel wie die '
              'Bilderzeugung (platform.stability.ai). Bitte in den '
              'Einstellungen hinterlegen.'
        ),
      'fal' => (
          'fal.ai-API-Schlüssel fehlt',
          'Für fal.ai wird ein API-Schlüssel benötigt (fal.ai – '
              'Bezahlung pro Lauf, Startguthaben für neue Konten). '
              'Bitte in den Einstellungen hinterlegen.'
        ),
      'replicate' => (
          'Replicate-API-Token fehlt',
          'Für Replicate wird ein API-Token benötigt (replicate.com – '
              'Bezahlung pro Lauf, Zahlungsmethode erforderlich). '
              'Bitte in den Einstellungen hinterlegen.'
        ),
      'rodin' => (
          'Rodin-API-Schlüssel fehlt',
          'Für Rodin (Hyper3D) wird ein API-Schlüssel benötigt '
              '(hyper3d.ai – Bezahlung nach Verbrauch). Bitte in den '
              'Einstellungen hinterlegen.'
        ),
      'selfhost' => (
          'Server-Adresse fehlt',
          'Für den eigenen 3D-Server die Adresse in den Einstellungen '
              'eintragen (z. B. http://127.0.0.1:8765). Einrichtung mit '
              'NVIDIA-GPU und Python: Anleitung in server/README.md im '
              'Projekt.'
        ),
      _ => (
          'Meshy-API-Schlüssel fehlt',
          'Für Meshy AI wird ein API-Schlüssel benötigt (meshy.ai – '
              'API-Zugang ab dem Pro-Plan). Bitte in den Einstellungen '
              'hinterlegen.'
        ),
    };
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenSettings();
            },
            child: const Text('Zu den Einstellungen'),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final settings = context.read<SettingsService>();
    final isLocal = settings.threeDProvider == 'local';
    final isTripo = settings.threeDProvider == 'tripo';
    final isStability = settings.threeDProvider == 'stability';
    final isFal = settings.threeDProvider == 'fal';
    final isSelfHost = settings.threeDProvider == 'selfhost';
    final isRodin = settings.threeDProvider == 'rodin';
    final isReplicate = settings.threeDProvider == 'replicate';
    // Beim eigenen Server steht an Stelle des Schlüssels die Adresse.
    final apiKey = isLocal
        ? ''
        : isStability
            ? settings.apiKeyFor(GenProvider.stability)
            : isFal
                ? settings.falApiKey
                : isSelfHost
                    ? settings.selfHostUrl
                    : isRodin
                        ? settings.rodinApiKey
                        : isReplicate
                            ? settings.replicateApiKey
                            : (isTripo
                                ? settings.tripoApiKey
                                : settings.meshyApiKey);
    if (!isLocal && (apiKey == null || apiKey.trim().isEmpty)) {
      await _showMissingKeyDialog(settings.threeDProvider);
      return;
    }
    final prompt = _promptCtrl.text.trim();
    // Text-Modus: „Lokal“, Stability, fal.ai, Replicate und der eigene
    // Server gehen immer über KI-Ansichten, bei Meshy/Tripo ist die
    // Pipeline zuschaltbar.
    final viewPipeline = !_imageMode &&
        (isLocal ||
            isStability ||
            isFal ||
            isSelfHost ||
            isReplicate ||
            _viewsFromText);
    // Bild-Modus: fehlende Ansichten optional per Bild-KI ergänzen –
    // gleiche Konsistenz-Prompts, Vorderansicht als Referenz.
    final augmentViews = _imageMode &&
        _completeViews &&
        !isStability &&
        !isFal &&
        !isSelfHost &&
        !isReplicate &&
        _views.values.any((view) => view == null);
    if (!_imageMode && prompt.isEmpty) {
      setState(() => _error = 'Bitte zuerst eine Beschreibung eingeben.');
      return;
    }
    if (_imageMode && _front == null) {
      setState(() => _error = 'Bitte zuerst die Vorderansicht wählen.');
      return;
    }

    setState(() {
      _running = true;
      _cancelRequested = false;
      _error = null;
      _stage = viewPipeline || augmentViews
          ? 'Ansichten werden vorbereitet …'
          : 'Task wird angelegt …';
    });
    bool cancelled() => _cancelRequested || !mounted;
    void progress(String stage) {
      if (mounted) setState(() => _stage = stage);
    }

    var usedTokens = 0;
    try {
      if (viewPipeline || augmentViews) {
        // Pose der Ansichten: beim eigenen Auto-Rigging die zum
        // Figurtyp passende Rig-Pose, sonst optional T-Pose.
        String? pose;
        if (_rigging &&
            (isLocal ||
                isStability ||
                isFal ||
                isSelfHost ||
                isRodin ||
                isReplicate)) {
          pose = rigPoseParts[_rigType];
        } else if (_rigging || _tPose) {
          pose = rigPoseParts['biped'];
        }
        final generated = await generateViewsFromText(
          settings: settings,
          description: prompt,
          pose: pose,
          onProgress: progress,
          isCancelled: cancelled,
          // Stability, fal.ai, Replicate und der eigene Server brauchen
          // nur ein Bild – das spart Kosten.
          frontOnly: isStability || isFal || isSelfHost || isReplicate,
          // Objekte/Fahrzeuge aus EINEM Bild: Dreiviertelansicht statt
          // Frontalansicht, sonst rekonstruiert Stability nur eine
          // flache Platte ohne Tiefe. Figuren behalten die bewährte
          // Vorderansicht.
          threeQuarterFront:
              (isStability || isFal || isSelfHost || isReplicate) &&
                  (_promptSubject == 'object' ||
                      (_rigging && _rigType == 'vehicle')),
          // Bereits gefüllte Ansichten-Kacheln werden wiederverwendet.
          existing: {
            for (final entry in _views.entries)
              if (entry.value != null) entry.key: entry.value!,
          },
        );
        if (cancelled()) throw GenerationException('Abgebrochen.');
        setState(() {
          for (final entry in generated.views.entries) {
            _views[entry.key] = entry.value;
          }
        });
        if (generated.totalTokens != null) {
          usedTokens = generated.totalTokens!;
          _showSnack(
              'Ansichten erzeugt (${generated.totalTokens} Tokens).');
        }
      }
      final useImages = _imageMode || viewPipeline;
      final label = _imageMode ? 'Aus Bild' : prompt;
      if (isLocal) {
        await _runLocal(settings, cancelled, progress,
            label: viewPipeline ? prompt : null);
      } else if (isStability) {
        await _runStability(Stability3dService(apiKey!.trim()), progress,
            label: label);
      } else if (isFal) {
        await _runFal(FalService(apiKey!.trim()), cancelled, progress,
            label: label);
      } else if (isSelfHost) {
        await _runSelfHost(
            SelfHostService(apiKey!.trim()), cancelled, progress,
            label: label);
      } else if (isRodin) {
        await _runRodin(
            RodinService(apiKey!.trim()), prompt, cancelled, progress,
            useImages: useImages, label: label);
      } else if (isReplicate) {
        await _runReplicate(
            ReplicateService(apiKey!.trim()), cancelled, progress,
            label: label);
      } else if (isTripo) {
        await _runTripo(
            TripoService(apiKey!.trim()), prompt, cancelled, progress,
            useImages: useImages, label: label);
      } else {
        await _runMeshy(
            MeshyService(apiKey!.trim()), prompt, cancelled, progress,
            useImages: useImages, label: label);
      }
      // Verbrauch und Restguthaben anzeigen: Tokens der Bild-KI-Schritte
      // (Ansichten/Tiefenkarten) plus aktuelles Provider-Guthaben.
      final usageParts = <String>[
        if (usedTokens > 0) 'Bild-KI-Ansichten: $usedTokens Tokens',
      ];
      if (!isLocal && apiKey != null) {
        final balance = await fetchProviderBalance(
            settings.threeDProvider, apiKey.trim());
        if (balance != null) usageParts.add(balance);
      }
      if (mounted) {
        setState(() => _usageInfo =
            usageParts.isEmpty ? null : usageParts.join(' · '));
      }
    } on GenerationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Unerwarteter Fehler: $e');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _stage = null;
        });
      }
    }
  }

  void _addResult({
    required Uint8List glbBytes,
    required String label,
    required String providerLabel,
    Uint8List? thumbnail,
    required bool rigged,
    required bool textured,
    Uint8List? unriggedGlb,
    String? rigTypeUsed,
  }) {
    if (!mounted) return;
    setState(() {
      _results.insert(
        0,
        ThreeDResult(
          glbBytes: glbBytes,
          label: label,
          providerLabel: providerLabel,
          thumbnailBytes: thumbnail,
          rigged: rigged,
          textured: textured,
          unriggedGlb: unriggedGlb,
          rigTypeUsed: rigTypeUsed,
        ),
      );
    });
    // Auch in der Galerie ablegen (auf nativen Plattformen dauerhaft).
    context.read<HistoryService>().addModel(
      glbBytes: glbBytes,
      thumbnail: thumbnail,
      label: label,
      providerLabel: providerLabel,
      params: {
        'Texturiert': textured ? 'ja' : 'nein',
        'Rigging': rigged ? 'ja' : 'nein',
      },
    );
  }

  Future<void> _runLocal(
    SettingsService settings,
    bool Function() cancelled,
    void Function(String) progress, {
    String? label,
  }) async {
    final source = _front;
    if (source == null) {
      throw GenerationException('Keine Vorderansicht vorhanden.');
    }

    // Optional: Tiefenkarten per Bild-KI für plastische Vertiefungen.
    Uint8List? frontDepthMap;
    Uint8List? backDepthMap;
    if (_localDepthAi) {
      frontDepthMap = await generateDepthMap(
        settings: settings,
        source: source,
        label: 'Vorn',
        onProgress: progress,
        isCancelled: cancelled,
      );
      final backView = _views['back'];
      if (backView != null) {
        backDepthMap = await generateDepthMap(
          settings: settings,
          source: backView,
          label: 'Hinten',
          onProgress: progress,
          isCancelled: cancelled,
        );
      }
      if (cancelled()) throw GenerationException('Abgebrochen.');
    }

    progress('Ansichten werden ausgewertet, Volumen wird geschnitzt …');
    Uint8List glb;
    try {
      final (_, _, metallic, roughness) = _surfaceOptions
          .firstWhere((s) => s.$1 == _localSurface,
              orElse: () => _surfaceOptions.first);
      glb = await generateLocalHullGlb(
        frontBytes: source.bytes,
        leftBytes: _views['left']?.bytes,
        rightBytes: _views['right']?.bytes,
        backBytes: _views['back']?.bytes,
        frontDepthBytes: frontDepthMap,
        backDepthBytes: backDepthMap,
        resolution: _localResolution.clamp(48, 160),
        smoothingPasses: _localSmoothing,
        targetTriangles: _localTargetTriangles,
        metallic: metallic,
        roughness: roughness,
        bakeTexture: _localTextureMode != 'vertex',
        textureSize: _localTextureMode == 'atlas1024' ? 1024 : 2048,
      );
    } on Exception catch (e) {
      throw GenerationException(
          e.toString().replaceFirst('Exception: ', ''));
    }
    final unrigged = glb;
    // Der lokale Generator baut die Vorderansicht nach +z.
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress,
        knownFrontSign: 1);
    _addResult(
      glbBytes: glb,
      label: label ?? '360°-Modell (lokal)',
      providerLabel: 'Lokal',
      thumbnail: source.bytes,
      rigged: rigged,
      textured: true,
      unriggedGlb: rigged ? unrigged : null,
      rigTypeUsed: rigged ? _rigType : null,
    );
  }

  /// Baut bei aktivem Rigging das lokale Standard-Skelett ins GLB ein.
  /// Liefert true, wenn das Modell geriggt wurde. [knownFrontSign]
  /// gibt Pipeline-Wissen über die Blickrichtung weiter (Stability
  /// rekonstruiert die Bildseite nach -z, der lokale Generator baut
  /// nach +z) – zuverlässiger als die geometrische Schätzung.
  bool _maybeInjectRig(Uint8List Function() getGlb,
      void Function(Uint8List) setGlb, void Function(String) progress,
      {int? knownFrontSign}) {
    if (!_rigging) return false;
    progress('Skelett wird eingebaut …');
    try {
      setGlb(injectAutoRig(getGlb(),
          rigType: _rigType, knownFrontSign: knownFrontSign));
      return true;
    } on Exception catch (e) {
      _showSnack('Rigging nicht möglich: '
          '${e.toString().replaceFirst('Exception: ', '')} – das Modell '
          'wird ohne Skelett geliefert.');
      return false;
    }
  }

  Future<void> _runStability(
    Stability3dService service,
    void Function(String) progress, {
    required String label,
  }) async {
    final source = _front;
    if (source == null) {
      throw GenerationException('Keine Vorderansicht vorhanden.');
    }
    progress(_stabilityEngine == 'stable-fast-3d'
        ? 'Modell wird generiert (Stable Fast 3D) …'
        : 'Modell wird generiert (Stable Point Aware 3D) …');
    // Detailgrad → foreground_ratio je Engine (Wertebereiche
    // unterscheiden sich, siehe Stability3dService.generateModel).
    // „Fein“ bewusst moderat: Extremwerte ohne Rand (SPAR3D 1.0)
    // liegen außerhalb der Trainingsverteilung und haben in Tests
    // Formen aufgebläht und Texturen verschmiert.
    final isSpar = _stabilityEngine == 'stable-point-aware-3d';
    final foregroundRatio = switch (_stabilityDetail) {
      'fine' => isSpar ? 1.15 : 0.9,
      'safe' => isSpar ? 1.85 : 0.6,
      _ => 0.0, // API-Vorgabe
    };
    var glb = await service.generateModel(
      imageBytes: source.bytes,
      mimeType: source.mimeType,
      engine: _stabilityEngine,
      textureResolution: _stabilityTextureRes,
      remesh: _stabilityRemesh,
      targetPolycount: _stabilityPolycount,
      foregroundRatio: foregroundRatio,
    );
    glb = await _applyLocalRefinements(glb, source.bytes, progress);
    final unrigged = glb;
    // Stability rekonstruiert im Kamera-Raum: Die im Bild sichtbare
    // Seite (Vorderansicht) zeigt im Modell nach -z.
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress,
        knownFrontSign: -1);
    _addResult(
      glbBytes: glb,
      label: label,
      providerLabel: 'Stability',
      thumbnail: source.bytes,
      rigged: rigged,
      textured: true,
      unriggedGlb: rigged ? unrigged : null,
      rigTypeUsed: rigged ? _rigType : null,
    );
  }

  /// Lokale Veredelung nach der Generierung: Textur aus dem
  /// Originalbild schärfen (greift nur, wenn die automatische
  /// Kalibrierung Bild und Modell sicher zusammenbringt), fürs
  /// Fahrzeug-Rig gerade ausrichten, optional symmetrisieren.
  Future<Uint8List> _applyLocalRefinements(
    Uint8List glb,
    Uint8List? sourceImageBytes,
    void Function(String) progress,
  ) async {
    final refineNotes = <String>[];
    if (_refineProjectTexture && sourceImageBytes != null) {
      progress('Veredelung: Textur wird aus dem Originalbild geschärft …');
      try {
        final sharpened =
            await reprojectSourceImageTexture(glb, sourceImageBytes);
        if (sharpened != null) {
          glb = sharpened;
          refineNotes.add('Textur aus dem Originalbild geschärft');
        }
      } catch (_) {}
    }
    if (_rigging && _rigType == 'vehicle') {
      progress('Veredelung: Ausrichtung wird geprüft …');
      try {
        final (aligned, degrees) = canonicalizeYawGlb(glb);
        if (degrees != 0) {
          glb = aligned;
          refineNotes.add('um ${degrees.abs().round()}° gerade '
              'ausgerichtet');
        }
      } catch (_) {}
    }
    if (_refineSymmetrize) {
      progress('Veredelung: Modell wird symmetrisiert …');
      try {
        glb = await mirrorSymmetrizeGlb(glb);
        refineNotes.add('symmetrisiert (bessere Hälfte gespiegelt)');
      } on Exception catch (e) {
        _showSnack('Symmetrisieren nicht möglich: '
            '${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (refineNotes.isNotEmpty) {
      _showSnack('Veredelung: ${refineNotes.join(' · ')}.');
    }
    return glb;
  }

  Future<void> _runFal(
    FalService service,
    bool Function() cancelled,
    void Function(String) progress, {
    required String label,
  }) async {
    final source = _front;
    if (source == null) {
      throw GenerationException('Keine Vorderansicht vorhanden.');
    }
    final modelId = _falModelEffective;
    progress('3D-Modell wird generiert ($modelId) …');
    var glb = await service.generateModel(
      modelId: modelId,
      imageBytes: source.bytes,
      mimeType: source.mimeType,
      onProgress: progress,
      isCancelled: cancelled,
    );
    // Die Ausrichtung der Marktplatz-Modelle variiert je nach Anbieter –
    // beim Rigging entscheidet daher die geometrische
    // Blickrichtungs-Schätzung statt Pipeline-Wissen.
    glb = await _applyLocalRefinements(glb, source.bytes, progress);
    final unrigged = glb;
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress);
    _addResult(
      glbBytes: glb,
      label: label,
      providerLabel: 'fal.ai',
      thumbnail: source.bytes,
      rigged: rigged,
      textured: true,
      unriggedGlb: rigged ? unrigged : null,
      rigTypeUsed: rigged ? _rigType : null,
    );
  }

  Future<void> _runSelfHost(
    SelfHostService service,
    bool Function() cancelled,
    void Function(String) progress, {
    required String label,
  }) async {
    final source = _front;
    if (source == null) {
      throw GenerationException('Keine Vorderansicht vorhanden.');
    }
    final can = SelfHostService.lastCapabilities;
    var glb = await service.generateModel(
      imageBytes: source.bytes,
      mimeType: source.mimeType,
      onProgress: progress,
      // Nur Backends mit „multiview" werten weitere Ansichten aus.
      extraViews: can.contains('multiview')
          ? [for (final view in _extraViews) (view.bytes, view.mimeType)]
          : const [],
      textureResolution:
          can.contains('texture_resolution') ? _serverTextureRes : null,
      remesh: can.contains('remesh') ? _serverRemesh : null,
      targetCount:
          can.contains('target_count') ? _serverTargetCount : null,
      resolution: can.contains('resolution') ? _serverResolution : null,
      bakeTexture:
          can.contains('bake_texture') ? _serverBakeTexture : null,
    );
    if (cancelled()) throw GenerationException('Abgebrochen.');
    // Wie bei fal.ai: Ausrichtung je nach Backend unterschiedlich –
    // Blickrichtung fürs Rigging per geometrischer Schätzung.
    glb = await _applyLocalRefinements(glb, source.bytes, progress);
    final unrigged = glb;
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress);
    _addResult(
      glbBytes: glb,
      label: label,
      providerLabel: 'Eigener Server',
      thumbnail: source.bytes,
      rigged: rigged,
      textured: true,
      unriggedGlb: rigged ? unrigged : null,
      rigTypeUsed: rigged ? _rigType : null,
    );
  }

  Future<void> _runReplicate(
    ReplicateService service,
    bool Function() cancelled,
    void Function(String) progress, {
    required String label,
  }) async {
    final source = _front;
    if (source == null) {
      throw GenerationException('Keine Vorderansicht vorhanden.');
    }
    final modelId = _replicateModelEffective;
    var glb = await service.generateModel(
      modelId: modelId,
      images: [(source.bytes, source.mimeType)],
      onProgress: progress,
      isCancelled: cancelled,
    );
    // Wie bei fal.ai: Ausrichtung je nach Modell unterschiedlich –
    // Blickrichtung fürs Rigging per geometrischer Schätzung.
    glb = await _applyLocalRefinements(glb, source.bytes, progress);
    final unrigged = glb;
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress);
    _addResult(
      glbBytes: glb,
      label: label,
      providerLabel: 'Replicate',
      thumbnail: source.bytes,
      rigged: rigged,
      textured: true,
      unriggedGlb: rigged ? unrigged : null,
      rigTypeUsed: rigged ? _rigType : null,
    );
  }

  Future<void> _runRodin(
    RodinService service,
    String prompt,
    bool Function() cancelled,
    void Function(String) progress, {
    required bool useImages,
    required String label,
  }) async {
    var images = const <(Uint8List, String)>[];
    if (useImages) {
      final source = _front;
      if (source == null) {
        throw GenerationException('Keine Vorderansicht vorhanden.');
      }
      images = [
        (source.bytes, source.mimeType),
        for (final view in _extraViews) (view.bytes, view.mimeType),
      ];
    }
    progress('Auftrag wird angelegt (Rodin) …');
    final (taskUuid, subscriptionKey) = await service.createTask(
      images: images,
      // Ohne Bilder: natives Text→3D von Rodin.
      prompt: useImages ? null : prompt,
      tier: _rodinTier,
      quadTopology: _rodinQuad,
      targetPolycount: _rodinPolycount,
      // Rodins eigener T/A-Pose-Parameter ersetzt den Prompt-Zusatz.
      taPose: !useImages && (_rigging || _tPose),
    );
    await service.waitForTask(subscriptionKey,
        onProgress: progress, isCancelled: cancelled);
    progress('GLB wird heruntergeladen …');
    var glb = await service.downloadGlb(taskUuid);
    // Veredelung + eigenes Rigging wie bei fal.ai; ohne Ausgangsbild
    // (natives Text→3D) entfällt nur die Textur-Reprojektion.
    glb = await _applyLocalRefinements(glb, _front?.bytes, progress);
    final unrigged = glb;
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress);
    _addResult(
      glbBytes: glb,
      label: label,
      providerLabel: 'Rodin',
      thumbnail: _front?.bytes,
      rigged: rigged,
      textured: true,
      unriggedGlb: rigged ? unrigged : null,
      rigTypeUsed: rigged ? _rigType : null,
    );
  }

  Future<void> _runMeshy(
    MeshyService service,
    String prompt,
    bool Function() cancelled,
    void Function(String) progress, {
    required bool useImages,
    required String label,
  }) async {
    {
      String taskPath;
      String taskId;
      MeshyTaskStatus status;

      if (useImages) {
        final source = _front;
        if (source == null) {
          throw GenerationException('Keine Vorderansicht vorhanden.');
        }
        final extras = _extraViews;
        if (extras.isNotEmpty) {
          // Mehrere Ansichten → Multi-Image-Endpunkt (Vorn zuerst).
          taskPath = 'v1/multi-image-to-3d';
          taskId = await service.createMultiImageTo3d(
            [
              (source.bytes, source.mimeType),
              for (final view in extras) (view.bytes, view.mimeType),
            ],
            texture: _texture,
            aiModel: _meshyAiModel,
            quadTopology: _quadTopology,
            targetPolycount: _meshyPolycount,
            symmetryMode: _symmetryMode,
            enablePbr: _pbr,
            texturePrompt: _texturePromptCtrl.text.trim(),
          );
        } else {
          taskPath = 'v1/image-to-3d';
          taskId = await service.createImageTo3d(
            source.bytes,
            source.mimeType,
            texture: _texture,
            aiModel: _meshyAiModel,
            quadTopology: _quadTopology,
            targetPolycount: _meshyPolycount,
            symmetryMode: _symmetryMode,
            enablePbr: _pbr,
            texturePrompt: _texturePromptCtrl.text.trim(),
            ultraMode: _meshyUltra && _meshyAiModel == 'meshy-7',
          );
        }
        status = await service.waitForTask(
          taskPath,
          taskId,
          stageLabel: extras.isEmpty
              ? '3D-Modell aus Bild'
              : '3D-Modell aus ${extras.length + 1} Ansichten',
          onProgress: progress,
          isCancelled: cancelled,
        );
      } else {
        // Für Rigging (oder auf Wunsch) braucht das Modell eine T-Pose –
        // wird automatisch an den Prompt angehängt.
        final effectivePrompt =
            _rigging || _tPose ? '$prompt, $_tPoseSuffix' : prompt;
        taskPath = 'v2/text-to-3d';
        taskId = await service.createTextPreview(
          effectivePrompt,
          _artStyle,
          aiModel: _meshyAiModel,
          quadTopology: _quadTopology,
          targetPolycount: _meshyPolycount,
          symmetryMode: _symmetryMode,
          negativePrompt: _negative3dCtrl.text.trim(),
        );
        status = await service.waitForTask(
          taskPath,
          taskId,
          stageLabel: 'Rohmodell (Geometrie)',
          onProgress: progress,
          isCancelled: cancelled,
        );
        if (_texture) {
          final refineId = await service.createTextRefine(
            taskId,
            enablePbr: _pbr,
            texturePrompt: _texturePromptCtrl.text.trim(),
          );
          status = await service.waitForTask(
            taskPath,
            refineId,
            stageLabel: 'Textur',
            onProgress: progress,
            isCancelled: cancelled,
          );
          taskId = refineId;
        }
      }

      var glbUrl = status.glbUrl;
      var rigged = false;
      if (_rigging) {
        try {
          final rigId = await service.createRigging(taskId);
          final rigStatus = await service.waitForTask(
            'v1/rigging',
            rigId,
            stageLabel: 'Rigging (Skelett)',
            onProgress: progress,
            isCancelled: cancelled,
            preferRigged: true,
          );
          glbUrl = rigStatus.glbUrl ?? glbUrl;
          rigged = true;
        } on GenerationException catch (e) {
          // Rigging kann bei Nicht-Figuren scheitern – Modell trotzdem
          // liefern und den Grund anzeigen.
          _showSnack('Rigging nicht möglich: ${e.message} – '
              'das Modell wird ohne Skelett exportiert.');
        }
      }

      if (glbUrl == null) {
        throw GenerationException(
            'Meshy hat keine GLB-Datei zurückgegeben.');
      }
      progress('GLB wird heruntergeladen …');
      final glbBytes = await service.downloadFile(glbUrl);

      Uint8List? thumbnail;
      final thumbnailUrl = status.thumbnailUrl;
      if (thumbnailUrl != null) {
        try {
          thumbnail = await service.downloadFile(thumbnailUrl);
        } catch (_) {}
      }

      _addResult(
        glbBytes: glbBytes,
        label: label,
        providerLabel: 'Meshy',
        thumbnail: thumbnail,
        rigged: rigged,
        textured: _texture,
      );
    }
  }

  Future<void> _runTripo(
    TripoService service,
    String prompt,
    bool Function() cancelled,
    void Function(String) progress, {
    required bool useImages,
    required String label,
  }) async {
    String modelTaskId;
    if (useImages) {
      final source = _front;
      if (source == null) {
        throw GenerationException('Keine Vorderansicht vorhanden.');
      }
      if (_extraViews.isNotEmpty) {
        // Multiview: Reihenfolge Vorn, Links, Hinten, Rechts.
        progress('Ansichten werden hochgeladen …');
        Future<(String, String)?> upload(String key) async {
          final view = _views[key];
          if (view == null) return null;
          final token =
              await service.uploadImage(view.bytes, view.mimeType);
          return (token, view.mimeType);
        }

        modelTaskId = await service.createMultiviewTask(
          [
            await upload('front'),
            await upload('left'),
            await upload('back'),
            await upload('right'),
          ],
          texture: _texture,
          modelVersion: _tripoVersion,
          quad: _quadTopology,
          detailedTexture: _tripoDetailedTexture,
        );
      } else {
        progress('Bild wird hochgeladen …');
        final token =
            await service.uploadImage(source.bytes, source.mimeType);
        modelTaskId = await service.createImageTask(
          token,
          source.mimeType,
          texture: _texture,
          modelVersion: _tripoVersion,
          quad: _quadTopology,
          detailedTexture: _tripoDetailedTexture,
        );
      }
    } else {
      // Für Rigging (oder auf Wunsch) braucht das Modell eine T-Pose –
      // wird automatisch an den Prompt angehängt.
      final effectivePrompt =
          _rigging || _tPose ? '$prompt, $_tPoseSuffix' : prompt;
      modelTaskId = await service.createTextTask(
        effectivePrompt,
        texture: _texture,
        modelVersion: _tripoVersion,
        quad: _quadTopology,
        detailedTexture: _tripoDetailedTexture,
        negativePrompt: _negative3dCtrl.text.trim(),
      );
    }
    final modelData = await service.waitForTask(
      modelTaskId,
      stageLabel: useImages ? '3D-Modell aus Bild' : '3D-Modell',
      onProgress: progress,
      isCancelled: cancelled,
    );

    var glbUrl = TripoService.findGlbUrl(modelData);
    var rigged = false;
    if (_rigging) {
      try {
        final checkId = await service.createPrerigCheck(modelTaskId);
        final checkData = await service.waitForTask(
          checkId,
          stageLabel: 'Rigging-Prüfung',
          onProgress: progress,
          isCancelled: cancelled,
        );
        final output = checkData['output'];
        final riggable = output is Map && output['riggable'] == true;
        if (!riggable) {
          throw GenerationException(
              'Tripo3D hat keine riggbare Figur erkannt.');
        }
        final rigId = await service.createRig(modelTaskId);
        final rigData = await service.waitForTask(
          rigId,
          stageLabel: 'Rigging (Skelett)',
          onProgress: progress,
          isCancelled: cancelled,
        );
        glbUrl = TripoService.findGlbUrl(rigData) ?? glbUrl;
        rigged = true;
      } on GenerationException catch (e) {
        // Rigging kann bei Nicht-Figuren scheitern – Modell trotzdem
        // liefern und den Grund anzeigen.
        _showSnack('Rigging nicht möglich: ${e.message} – '
            'das Modell wird ohne Skelett exportiert.');
      }
    }

    if (glbUrl == null) {
      throw GenerationException(
          'Tripo3D hat keine GLB-Datei zurückgegeben.');
    }
    progress('GLB wird heruntergeladen …');
    final glbBytes = await service.downloadFile(glbUrl);

    Uint8List? thumbnail;
    final thumbnailUrl = TripoService.findThumbnailUrl(modelData);
    if (thumbnailUrl != null) {
      try {
        thumbnail = await service.downloadFile(thumbnailUrl);
      } catch (_) {}
    }

    _addResult(
      glbBytes: glbBytes,
      label: label,
      providerLabel: 'Tripo3D',
      thumbnail: thumbnail,
      rigged: rigged,
      textured: _texture,
    );
  }

  /// Kleiner Infotext unter einer Option.
  Widget _optionInfo(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );

  /// Rigging-Schalter für Lokal und Stability: eigenes Auto-Rigging,
  /// das lokal ein Standard-Skelett ins GLB einbaut – mit wählbarem
  /// Figurtyp (Zweibeiner, Vierbeiner, Insekt, Vogel, Schlange, Fisch).
  Widget _autoRigSwitch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rigging (Skelett für Animation)'),
          subtitle: const Text(
              'Baut lokal ein Standard-Skelett direkt ins GLB ein – für '
              'Animationen in Blender/Unity/Godot. Bei erzeugten '
              'Ansichten wird automatisch die passende Rig-Pose '
              'verwendet.'),
          value: _rigging,
          onChanged: _running ? null : (v) => setState(() => _rigging = v),
        ),
        if (_rigging) ...[
          DropdownMenu<String>(
            key: ValueKey('rigtype-$_rigType'),
            enabled: !_running,
            initialSelection: _rigType,
            label: const Text('Figurtyp (Skelett)'),
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              for (final (value, name) in rigTypeOptions)
                DropdownMenuEntry(value: value, label: name),
            ],
            onSelected: (value) {
              if (value != null) setState(() => _rigType = value);
            },
          ),
          const SizedBox(height: 4),
          Text(
            _rigType == 'vehicle'
                ? 'Karosserie-Knochen plus automatisch erkannte Räder: '
                    'Achsen werden aus der bodennahen Geometrie erkannt '
                    '– vom Einrad über Fahrrad/Motorrad (Einzelräder) '
                    'bis Bus/LKW (bis zu 5 Achsen mit 10 Rädern).'
                : 'Heuristisches Standard-Skelett mit '
                    '${rigJointCounts[_rigType]} Gelenken. Das Motiv '
                    'sollte in der passenden Rig-Pose stehen – bei '
                    'automatisch erzeugten Ansichten passiert das von '
                    'selbst.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// Auswahl-Kachel für eine Ansicht (Vorn/Links/Rechts/Hinten).
  Widget _viewSlot(String key, String label) {
    final theme = Theme.of(context);
    final image = _views[key];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: DropTarget(
            enable: !_running &&
                widget.isActive &&
                (ModalRoute.of(context)?.isCurrent ?? true),
            onDragEntered: (_) => setState(() => _dragOverSlot = key),
            onDragExited: (_) => setState(() => _dragOverSlot = null),
            onDragDone: (detail) => _dropOnSlot(key, detail.files),
            child: Stack(
            children: [
              InkWell(
                onTap: _running ? null : () => _pickView(key),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _dragOverSlot == key
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: _dragOverSlot == key ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: image == null
                      ? Icon(Icons.add_photo_alternate_outlined,
                          color: theme.colorScheme.outline)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.memory(image.bytes,
                              fit: BoxFit.cover,
                              width: 72,
                              height: 72),
                        ),
                ),
              ),
              if (image != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    onTap: _running
                        ? null
                        : () => setState(() => _views[key] = null),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }

  ProvenanceInfo _provenanceFor(ThreeDResult result) => ProvenanceInfo(
        kind: '3D-Modell',
        description: result.label,
        providerLabel: result.providerLabel,
        details: {
          'Texturiert': result.textured ? 'ja' : 'nein',
          'Rigging': result.rigged ? 'ja' : 'nein',
        },
        previewBytes: result.thumbnailBytes,
      );

  void _openModelPreview(ThreeDResult result) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: result.glbBytes,
        title: result.label,
        provenance: _provenanceFor(result),
        unriggedGlb: result.unriggedGlb,
        rigType: result.rigTypeUsed,
        // Exportiert wird über den Export-Knopf am Ergebnis.
        showExport: false,
        onGlbUpdated: (bytes) {
          // Ergebnis (und damit der GLB-Export) übernimmt das im
          // Rig-Editor angepasste Modell.
          if (mounted) setState(() => result.glbBytes = bytes);
        },
      ),
    ));
  }

  /// Erstellungsnachweis-PDF direkt vom Ergebnis aus (auch im Viewer
  /// unter Export zu finden).
  Future<void> _exportModelProvenance(ThreeDResult result) async {
    final settings = context.read<SettingsService>();
    final name = await askCreatorName(context, settings);
    if (name == null || !mounted) return;
    try {
      final pdf = await buildProvenancePdf(
        info: _provenanceFor(result),
        fileType: 'GLB',
        fileBytes: result.glbBytes,
        creatorName: name,
      );
      final message = await exportImageBytes(
        pdf,
        'erstellungsnachweis_${DateTime.now().millisecondsSinceEpoch}.pdf',
        'application/pdf',
      );
      if (message != null && mounted) _showSnack(message);
    } catch (e) {
      if (mounted) _showSnack('Nachweis fehlgeschlagen: $e');
    }
  }

  Future<void> _exportGlb(ThreeDResult result) async {
    final fileName =
        'modell_${DateTime.now().millisecondsSinceEpoch}.glb';
    try {
      final message = await exportImageBytes(
          result.glbBytes, fileName, 'model/gltf-binary');
      if (message != null && mounted) _showSnack(message);
    } catch (e) {
      if (mounted) _showSnack('Export fehlgeschlagen: $e');
    }
  }

  /// Export-Menü direkt am Ergebnis: alle Formate wie im Viewer.
  void _showExportMenu(ThreeDResult result) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_in_ar),
              title: const Text('GLB exportieren'),
              subtitle:
                  const Text('Original mit Textur und ggf. Rigging'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exportGlb(result);
              },
            ),
            ListTile(
              leading: const Icon(Icons.polyline_outlined),
              title: const Text('OBJ exportieren (mit Vertexfarben)'),
              subtitle: const Text('Für Blender, MeshLab & Co.'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exportResultAs(result, 'obj');
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('STL für 3D-Druck …'),
              subtitle: const Text(
                  'Nur Form – aufs Druckbett gedreht, Größe in mm'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exportResultAs(result, 'stl');
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('3MF mit Farben …'),
              subtitle:
                  const Text('Für Farb-3D-Druck und Druckdienste'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exportResultAs(result, '3mf');
              },
            ),
            ListTile(
              enabled: result.rigged,
              leading: const Icon(Icons.movie_outlined),
              title: const Text('GLB mit Testanimationen'),
              subtitle: Text(result.rigged
                  ? 'Bettet die Testanimationen als loopbare Clips ein'
                  : 'Nur bei geriggten Modellen verfügbar'),
              onTap: result.rigged
                  ? () {
                      Navigator.of(sheetContext).pop();
                      _exportResultAs(result, 'glb_anim');
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportResultAs(ThreeDResult result, String format) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      switch (format) {
        case 'glb_anim':
          final mesh = await parseGlbForPreview(result.glbBytes);
          final rig = mesh.rig;
          if (rig == null) {
            mesh.dispose();
            _showSnack('Das Modell trägt kein Skelett.');
            return;
          }
          final clips = proceduralClipsFor(rig);
          mesh.dispose();
          final baked = bakeAnimationsIntoGlb(result.glbBytes, clips);
          final message = await exportImageBytes(
              baked, 'modell_animiert_$ts.glb', 'model/gltf-binary');
          if (message != null && mounted) {
            _showSnack('${clips.length} Testanimationen eingebettet – '
                '$message');
          }
        case 'obj':
          final obj = await glbToObj(result.glbBytes);
          final message = await exportImageBytes(
              obj, 'modell_$ts.obj', 'model/obj');
          if (message != null && mounted) _showSnack(message);
        case 'stl':
        case '3mf':
          // Wasserdichtheits-Prüfung wie im Viewer.
          MeshCheckResult? check;
          try {
            final mesh = await parseGlbForPreview(result.glbBytes);
            check = checkMeshWatertight(mesh.positions, mesh.indices);
            mesh.dispose();
          } catch (_) {}
          if (!mounted) return;
          final size = await askPrintSizeDialog(
            context,
            title: format == 'stl'
                ? 'STL für 3D-Druck'
                : '3MF mit Farben für 3D-Druck',
            note: format == 'stl'
                ? 'STL enthält nur die Form (ohne Farben und Textur). '
                    'Das Modell wird aufs Druckbett gedreht und '
                    'zentriert. Die Datei danach in einen Slicer laden '
                    '(z. B. PrusaSlicer, Cura, Bambu Studio).'
                : '3MF enthält die Form samt Farben (Material-Palette '
                    'je Dreieck) – ideal für Farb-3D-Druck und '
                    'Druckdienste. Gedreht, zentriert und in mm '
                    'skaliert.',
            check: check,
          );
          if (size == null || size <= 0 || !mounted) return;
          final bytes = format == 'stl'
              ? await glbToStl(result.glbBytes, targetSizeMm: size)
              : await glbTo3mf(result.glbBytes, targetSizeMm: size);
          final message = await exportImageBytes(
              bytes,
              'modell_$ts.$format',
              format == 'stl' ? 'model/stl' : 'model/3mf');
          if (message != null && mounted) _showSnack(message);
      }
    } catch (e) {
      if (mounted) _showSnack('Export fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsService>();
    final isTripo = settings.threeDProvider == 'tripo';
    final isLocal = settings.threeDProvider == 'local';
    final isStability = settings.threeDProvider == 'stability';
    final isFal = settings.threeDProvider == 'fal';
    final isSelfHost = settings.threeDProvider == 'selfhost';
    final isRodin = settings.threeDProvider == 'rodin';
    final isReplicate = settings.threeDProvider == 'replicate';
    final riggingForcesTPose = _rigging;
    // Beim eigenen Auto-Rigging kommt die Pose aus dem Figurtyp –
    // der T-Pose-Schalter wäre dann irreführend.
    final rigPoseActive = _rigging &&
        (isLocal ||
            isStability ||
            isFal ||
            isSelfHost ||
            isRodin ||
            isReplicate);
    return DropTarget(
      enable: widget.isActive &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      onDragDone: (detail) => _openDroppedModel(detail.files),
      // Auf breiten Bildschirmen begrenzte Inhaltsbreite: Optionen und
      // ihre Schalter bleiben beieinander, die Seite wirkt aufgeräumt.
      // Der Scrollbereich läuft dabei über die VOLLE Breite (Padding
      // statt schmaler Spalte) – so scrollt die Seite überall und der
      // Scrollbalken sitzt am Fensterrand.
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
      padding: EdgeInsets.symmetric(
        vertical: 16,
        horizontal: constraints.maxWidth > 892
            ? (constraints.maxWidth - 860) / 2
            : 16,
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('3D-Figuren & Objekte',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Erzeugt ein 3D-Modell aus einer Beschreibung oder einem '
                  'Foto – optional mit Textur und Skelett (Rigging) für '
                  'Animationen. Export als GLB (Blender, Unity, Unreal, '
                  'Godot …).',
                  style: theme.textTheme.bodySmall,
                ),
                const SectionLabel('Vorlagen'),
                Text(
                  'Bewährte Kombinationen aus Anbieter, Modell und '
                  'Qualitäts-Optionen – ein Klick setzt alles passend, '
                  'danach lässt sich jede Option weiterhin einzeln '
                  'ändern.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final preset in _presets)
                      ActionChip(
                        avatar: Icon(preset.$3, size: 18),
                        label: Text(preset.$2),
                        onPressed:
                            _running ? null : () => _applyPreset(preset.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _customPresetBar(theme, settings),
                if (_lastPresetInfo != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Zuletzt angewendet: $_lastPresetInfo.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
                const SectionLabel('3D-Provider'),
                Builder(builder: (context) {
                  // Grüner Haken = einsatzbereit (Schlüssel hinterlegt
                  // bzw. Lokal ohne Schlüssel). Acht Provider: Chips
                  // brechen auf schmalen Bildschirmen um und bleiben –
                  // anders als die frühere Segmentleiste – lesbar.
                  Widget ready(bool available) => available
                      ? const Icon(Icons.check_circle,
                          color: Colors.green, size: 16)
                      : const Icon(Icons.key_off, size: 16);
                  bool hasKey(String? key) =>
                      key?.trim().isNotEmpty ?? false;
                  final providers = <(String, String, bool)>[
                    ('local', 'Lokal', true),
                    (
                      'stability',
                      'Stability',
                      settings.hasApiKeyFor(GenProvider.stability)
                    ),
                    ('meshy', 'Meshy', hasKey(settings.meshyApiKey)),
                    ('tripo', 'Tripo3D', hasKey(settings.tripoApiKey)),
                    ('fal', 'fal.ai', hasKey(settings.falApiKey)),
                    ('rodin', 'Rodin', hasKey(settings.rodinApiKey)),
                    (
                      'replicate',
                      'Replicate',
                      hasKey(settings.replicateApiKey)
                    ),
                    (
                      'selfhost',
                      'Server',
                      settings.selfHostUrl.trim().isNotEmpty
                    ),
                  ];
                  return Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (value, name, available) in providers)
                        ChoiceChip(
                          avatar: settings.threeDProvider == value
                              ? null
                              : ready(available),
                          label: Text(name),
                          selected: settings.threeDProvider == value,
                          onSelected: _running
                              ? null
                              : (selected) {
                                  if (selected) {
                                    settings.setThreeDProvider(value);
                                  }
                                },
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  'Grüner Haken = einsatzbereit (API-Schlüssel hinterlegt '
                  'bzw. Lokal ohne Schlüssel).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  isLocal
                      ? 'Eigener Generator: rechnet komplett lokal in der '
                          'App – kostenlos, kein API-Schlüssel nötig. Baut '
                          'aus bis zu 4 Ansichten ein farbiges 360°-Modell '
                          '(optional mit KI-Ansichten und Tiefenschätzung).'
                      : isStability
                          ? 'Stability 3D: trainierte generative Modelle '
                              '(Stable Fast 3D / Point Aware 3D) – '
                              'rekonstruieren aus einem einzigen Bild auch '
                              'Rückseite, Vertiefungen und Hohlräume. Nutzt '
                              'den Stability-Bildschlüssel, wenige Credits '
                              'pro Modell.'
                          : isTripo
                              ? 'Tripo3D: ca. 35–75 Credits je Modell '
                                  '(Rohmodell + Textur + Rigging), '
                                  '10 € = 1000 Credits; Startguthaben für '
                                  'neue Konten (platform.tripo3d.ai).'
                              : isFal
                                  ? 'fal.ai (Beta): Pay-per-Use-Marktplatz '
                                      'für Bild→3D-Modelle (TRELLIS, '
                                      'TripoSR, Hunyuan3D) – Abrechnung '
                                      'pro Lauf ab ca. 1–2 US-Cent, '
                                      'Schlüssel und Verbrauch auf fal.ai.'
                                  : isRodin
                                      ? 'Rodin (Hyper3D, Beta): '
                                          'Spitzenklasse für Game-Assets '
                                          '– saubere Quad-Topologie, '
                                          'PBR-Texturen, T/A-Pose für '
                                          'Figuren; Text→3D und Bild→3D '
                                          'mit mehreren Ansichten, '
                                          'Bezahlung nach Verbrauch '
                                          '(hyper3d.ai).'
                                      : isReplicate
                                          ? 'Replicate (Beta): '
                                              'Pay-per-Use-Plattform '
                                              'mit tausenden Modellen '
                                              '(TRELLIS, Hunyuan3D u. '
                                              'v. m.) – Token und '
                                              'Verbrauch auf '
                                              'replicate.com '
                                              '(Zahlungsmethode nötig).'
                                          : isSelfHost
                                      ? 'Eigener Server: TripoSR oder '
                                          'TRELLIS (MIT-Lizenz) auf dem '
                                          'eigenen PC mit NVIDIA-GPU – '
                                          'kostenlos, alle Daten bleiben '
                                          'lokal. Einrichtung: '
                                          'server/README.md im Projekt, '
                                          'Adresse in den Einstellungen.'
                                      : 'Meshy: ca. 20 Credits pro '
                                          'Modell, API-Zugang ab '
                                          'Pro-Plan (meshy.ai).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Aus Text')),
                    ButtonSegment(value: true, label: Text('Aus Bild')),
                  ],
                  selected: {_imageMode},
                  onSelectionChanged: _running
                      ? null
                      : (selection) =>
                          setState(() => _imageMode = selection.first),
                ),
                const SizedBox(height: 12),
                if (!_imageMode) ...[
                  TextField(
                    controller: _promptCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung des 3D-Modells',
                      hintText:
                          'z. B. „Ein mittelalterlicher Ritter in voller '
                          'Rüstung mit Schwert“',
                      helperText:
                          'Tipp für Text→3D: knapp bleiben – '
                          'Objektklasse zuerst, dann Silhouette, dann '
                          'wenige markante Merkmale; ein einzelnes, '
                          'freistehendes Objekt. Kamera-, Licht- und '
                          'Qualitätswörter („8k“, „photorealistic“) '
                          'weglassen – 3D-Modelle ignorieren sie oder '
                          'werden schlechter. Wird das Ergebnis '
                          'matschig, hilft Kürzen mehr als Ergänzen.',
                      helperMaxLines: 6,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _promptHelp(theme,
                      mode: isLocal ||
                              isStability ||
                              isFal ||
                              isSelfHost ||
                              isReplicate ||
                              _viewsFromText
                          ? 'wrapped'
                          : 'native'),
                  if (!isLocal &&
                      !isStability &&
                      !isFal &&
                      !isSelfHost &&
                      !isRodin &&
                      !isReplicate &&
                      !_viewsFromText) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _negative3dCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Negativ-Prompt (optional)',
                        hintText: 'z. B. „low poly, blobby, floating '
                            'parts, base, pedestal“',
                        helperText:
                            'Was das Modell vermeiden soll – geht '
                            'direkt an Meshy/Tripo.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  // Kunststil ist ein reiner Meshy-Parameter – bei
                  // allen anderen Providern ohne Wirkung, versteckt.
                  if (!isTripo &&
                      !isLocal &&
                      !isStability &&
                      !isFal &&
                      !isSelfHost &&
                      !isRodin &&
                      !isReplicate) ...[
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'realistic', label: Text('Realistisch')),
                        ButtonSegment(
                            value: 'sculpture', label: Text('Skulptur')),
                      ],
                      selected: {_artStyle},
                      onSelectionChanged: (selection) =>
                          setState(() => _artStyle = selection.first),
                    ),
                  ],
                  if (!rigPoseActive)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('T-Pose (für Figuren empfohlen)'),
                      subtitle: Text(riggingForcesTPose
                          ? 'Durch Rigging automatisch aktiv – gespreizte '
                              'Arme lassen sich am besten rekonstruieren.'
                          : 'Figur mit gespreizten Armen erzeugen – lässt '
                              'sich deutlich besser räumlich '
                              'rekonstruieren, auch ohne Rigging. Für '
                              'Objekte (Gebäude, Fahrzeuge …) '
                              'ausschalten.'),
                      value: _tPose || riggingForcesTPose,
                      onChanged: _running || riggingForcesTPose
                          ? null
                          : (v) => setState(() => _tPose = v),
                    ),
                  const SizedBox(height: 4),
                  if (isLocal ||
                      isStability ||
                      isFal ||
                      isSelfHost ||
                      isReplicate)
                    Text(
                      isFal || isSelfHost || isReplicate
                          ? 'Die Ansicht wird automatisch mit der '
                              'Bild-KI aus dem Generator-Tab '
                              '(${settings.provider.label}) erzeugt; '
                              '${isFal ? 'das gewählte fal.ai-Modell' : isReplicate ? 'das gewählte Replicate-Modell' : 'dein eigener Server (TripoSR/TRELLIS)'} '
                              'rekonstruiert daraus das komplette '
                              '3D-Modell inklusive Rückseite.'
                          : isStability
                          ? 'Die Ansicht wird automatisch mit der '
                              'Bild-KI aus dem Generator-Tab '
                              '(${settings.provider.label}) erzeugt; das '
                              'trainierte Stability-Modell rekonstruiert '
                              'daraus das komplette 3D-Modell inklusive '
                              'Rückseite. Ehrlich: Die Textur erzeugt '
                              'Stability intern mit fester Auflösung – '
                              'ein noch schärferes Ausgangsbild bringt ab '
                              'einem Punkt nichts mehr, und weniger Rand '
                              '(„Fein“) hilft nur begrenzt. Spürbar mehr '
                              'Schärfe gibt es erst mit Meshy/Tripo '
                              '(Spitzenklasse).'
                          : 'Die 4 Ansichten (vorn/links/rechts/hinten) '
                              'werden automatisch mit der Bild-KI aus dem '
                              'Generator-Tab (${settings.provider.label}) '
                              'erzeugt – mit abgestimmten Prompts, damit '
                              'sie perfekt zusammenpassen.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          const Text('Ansichten-Bilder per Bild-KI erzeugen'),
                      subtitle: Text(
                          'Erzeugt zuerst 4 konsistente Ansichten '
                          '(vorn/links/rechts/hinten) mit '
                          '${settings.provider.label} aus dem Generator-Tab '
                          'und baut daraus ein Rundum-Modell – meist '
                          'detailtreuer als das direkte Text→3D. Kostet '
                          'zusätzlich ca. 4 Bildgenerierungen.'),
                      value: _viewsFromText,
                      onChanged: _running
                          ? null
                          : (v) => setState(() => _viewsFromText = v),
                    ),
                  if (isLocal ||
                      isStability ||
                      isFal ||
                      isSelfHost ||
                      isReplicate ||
                      _viewsFromText) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      // Der eigene Server zeigt alle vier Kacheln,
                      // sobald das Backend Multiview beherrscht.
                      final serverMultiview = isSelfHost &&
                          SelfHostService.lastCapabilities
                              .contains('multiview');
                      final showAllViews = (!isStability &&
                              !isFal &&
                              !isSelfHost &&
                              !isReplicate) ||
                          serverMultiview;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _viewSlot('front', 'Vorn'),
                          if (showAllViews) ...[
                            _viewSlot('left', 'Links'),
                            _viewSlot('right', 'Rechts'),
                            _viewSlot('back', 'Hinten'),
                          ],
                        ],
                      );
                    }),
                    const SizedBox(height: 4),
                    Text(
                      'Die erzeugten Ansichten erscheinen hier und werden '
                      'beim nächsten Lauf wiederverwendet. Einzelne '
                      'Ansichten löschen (X) oder ersetzen, damit sie neu '
                      'erzeugt werden.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ] else ...[
                  // Prompt-Hilfe auch im Bild-Modus: Die Bildvorlagen
                  // entstehen meist im Generator-Tab – hier steht die
                  // passende Vorlage zum Kopieren bereit.
                  _promptHelp(theme, mode: 'images'),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final serverMultiview = isSelfHost &&
                        SelfHostService.lastCapabilities
                            .contains('multiview');
                    final showAllViews = (!isStability &&
                            !isFal &&
                            !isSelfHost &&
                            !isReplicate) ||
                        serverMultiview;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _viewSlot('front', 'Vorn *'),
                        if (showAllViews) ...[
                          _viewSlot('left', 'Links'),
                          _viewSlot('right', 'Rechts'),
                          _viewSlot('back', 'Hinten'),
                        ],
                      ],
                    );
                  }),
                  const SizedBox(height: 4),
                  Text(
                    isStability || isFal || isSelfHost || isReplicate
                        ? 'Dieser 3D-Dienst nutzt genau ein Bild: '
                            'Rückseite, Vertiefungen und Verdecktes '
                            'rekonstruiert das trainierte Modell selbst.'
                        : isLocal
                            ? 'Vorderansicht ist Pflicht; je mehr echte '
                                'Ansichten (links/rechts/hinten), desto '
                                'genauer wird das räumliche Modell. Alle '
                                'Bilder: dasselbe Motiv in gleicher Pose, '
                                'möglichst transparenter Hintergrund.'
                            : 'Nur die Vorderansicht ist Pflicht. Mit '
                                'Ansichten von links, rechts und hinten '
                                'entsteht ein deutlich genaueres '
                                'Rundum-Modell.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (!isStability && !isFal && !isSelfHost && !isReplicate)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                          'Fehlende Ansichten per Bild-KI ergänzen'),
                      subtitle: Text(
                          'Erzeugt fehlende Ansichten automatisch aus der '
                          'Vorderansicht – mit denselben '
                          'Konsistenz-Vorgaben wie im Text-Modus '
                          '(identisches Motiv, gleiche Skalierung, '
                          'orthographisch, transparenter Hintergrund). '
                          'Nutzt ${settings.provider.label} aus dem '
                          'Generator-Tab, ca. 1 Bildgenerierung je '
                          'fehlender Ansicht.'),
                      value: _completeViews,
                      onChanged: _running
                          ? null
                          : (v) => setState(() => _completeViews = v),
                    ),
                ],
                const SectionLabel('Modell & Kosten'),
                // Bild-KI-Modell direkt im 3D-Tab wählbar plus
                // seitliche Qualitäts-/Kostenanzeige für den gesamten
                // Lauf (Bild-KI-Schritte + 3D-Dienst).
                Builder(builder: (context) {
                  final viewKeys =
                      isStability || isFal || isSelfHost || isReplicate
                          ? const ['front']
                          : const ['front', 'left', 'right', 'back'];
                  final generatesViews = (!_imageMode &&
                          (isLocal ||
                              isStability ||
                              isFal ||
                              isSelfHost ||
                              isReplicate ||
                              _viewsFromText)) ||
                      (_imageMode &&
                          _completeViews &&
                          !isStability &&
                          !isFal &&
                          !isSelfHost &&
                          !isReplicate);
                  final viewsToGenerate = generatesViews
                      ? viewKeys
                          .where((key) => _views[key] == null)
                          .length
                      : 0;
                  final estimate = estimate3dRun(
                    settings,
                    viewsToGenerate: viewsToGenerate,
                    depthMaps: isLocal && _localDepthAi ? 2 : 0,
                    stabilityEngine: _stabilityEngine,
                    rigging: _rigging &&
                        !isLocal &&
                        !isStability &&
                        !isFal &&
                        !isSelfHost &&
                        !isRodin &&
                        !isReplicate,
                    meshyAiModel: _meshyAiModel,
                    tripoVersion: _tripoVersion,
                    falModel: _falModelEffective,
                    rodinTier: _rodinTier,
                    replicateModel: _replicateModelEffective,
                  );
                  final usesImageAi =
                      generatesViews || (isLocal && _localDepthAi);
                  final provider = settings.provider;
                  final staticModels = switch (provider) {
                    GenProvider.openai => openAiModelOptions,
                    GenProvider.stability => stabilityModelOptions,
                    GenProvider.gemini => geminiModelOptions,
                  };
                  final knownModels = [
                    ...staticModels,
                    for (final id
                        in settings.fetchedModelsFor(provider))
                      if (!staticModels.any((o) => o.$1 == id)) (id, id),
                  ];
                  final currentModel = settings.modelFor(provider);
                  final controls = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 3D-Modell zuerst: bestimmt die Qualitätsstufe.
                      if (isStability) ...[
                        DropdownMenu<String>(
                          key: ValueKey('sengine-$_stabilityEngine'),
                          enabled: !_running,
                          initialSelection: _stabilityEngine,
                          label: const Text('3D-Modell (Engine)'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: [
                            for (final (value, name)
                                in Stability3dService.engines)
                              DropdownMenuEntry(
                                  value: value, label: name),
                          ],
                          onSelected: (value) {
                            if (value != null) {
                              setState(() => _stabilityEngine = value);
                            }
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Point Aware 3D rekonstruiert Rückseite und '
                          'Hohlräume am besten; Fast 3D ist die '
                          'schnellere, einfachere Variante.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                      ] else if (isReplicate) ...[
                        DropdownMenu<String>(
                          key: ValueKey('repmodel-$_replicateModel'),
                          enabled: !_running,
                          initialSelection: _replicateModel,
                          label: const Text('3D-Modell (Replicate)'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: [
                            for (final model in replicateModels)
                              DropdownMenuEntry(
                                  value: model.id, label: model.label),
                          ],
                          onSelected: (value) {
                            if (value != null) {
                              setState(() => _replicateModel = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _replicateCustomCtrl,
                          enabled: !_running,
                          decoration: const InputDecoration(
                            labelText:
                                'Eigene Replicate-Kennung (optional)',
                            hintText: 'z. B. owner/name oder '
                                'owner/name:version',
                            helperText:
                                'Überschreibt die Auswahl oben – für '
                                'weitere Bild→3D-Modelle von '
                                'replicate.com. Beta: Modelle mit '
                                'abweichenden Eingabefeldern melden '
                                'einen Fehler mit dem erwarteten '
                                'Feldnamen.',
                            helperMaxLines: 4,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                      ] else if (isRodin) ...[
                        DropdownMenu<String>(
                          key: ValueKey('rodintier-$_rodinTier'),
                          enabled: !_running,
                          initialSelection: _rodinTier,
                          label: const Text('3D-Modell (Generation)'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: const [
                            DropdownMenuEntry(
                                value: '',
                                label: 'Standard (API-Vorgabe)'),
                            DropdownMenuEntry(
                                value: 'Gen-2.5-High',
                                label:
                                    'Gen-2.5 High (beste Qualität)'),
                            DropdownMenuEntry(
                                value: 'Gen-2.5-Medium',
                                label:
                                    'Gen-2.5 Medium (schneller & '
                                    'günstiger)'),
                          ],
                          onSelected: (value) {
                            if (value != null) {
                              setState(() => _rodinTier = value);
                            }
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Rodin Gen-2.5 (SIGGRAPH-Best-Paper-'
                          'Forschung): produktionsreife Meshes mit '
                          'sauberer Topologie – ideal für Fahrzeuge, '
                          'Gebäude und andere Game-Assets.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                      ] else if (isSelfHost) ...[
                        Builder(builder: (context) {
                          final backend = SelfHostService.lastBackend;
                          final can = SelfHostService.lastCapabilities;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                backend.isEmpty
                                    ? 'Das Modell bestimmt dein Server '
                                        'beim Start. Adresse: '
                                        '${settings.selfHostUrl.trim().isEmpty ? 'noch nicht eingetragen' : settings.selfHostUrl} '
                                        '– in den Einstellungen auf '
                                        '„Speichern & testen“ tippen, '
                                        'dann erscheinen hier die '
                                        'passenden Optionen.'
                                    : 'Läuft: $backend auf '
                                        '${settings.selfHostUrl}. Die '
                                        'folgenden Optionen meldet '
                                        'dieses Modell selbst.',
                                style: theme.textTheme.bodySmall,
                              ),
                              if (can.contains('multiview')) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Dieses Modell wertet mehrere '
                                  'Ansichten gemeinsam aus – die '
                                  'Kacheln für links/rechts/hinten '
                                  'sind deshalb oben freigeschaltet.',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                          color:
                                              theme.colorScheme.primary),
                                ),
                              ],
                              if (can.contains('texture_resolution')) ...[
                                const SizedBox(height: 12),
                                DropdownMenu<int>(
                                  key: ValueKey(
                                      'srvtex-$_serverTextureRes'),
                                  enabled: !_running,
                                  initialSelection: _serverTextureRes,
                                  label: const Text('Textur-Auflösung'),
                                  expandedInsets: EdgeInsets.zero,
                                  dropdownMenuEntries: const [
                                    DropdownMenuEntry(
                                        value: 512, label: '512 px'),
                                    DropdownMenuEntry(
                                        value: 1024,
                                        label: '1024 px (Standard)'),
                                    DropdownMenuEntry(
                                        value: 2048,
                                        label: '2048 px (am schärfsten)'),
                                  ],
                                  onSelected: (value) {
                                    if (value != null) {
                                      setState(() =>
                                          _serverTextureRes = value);
                                    }
                                  },
                                ),
                              ],
                              if (can.contains('remesh')) ...[
                                const SizedBox(height: 12),
                                DropdownMenu<String>(
                                  key:
                                      ValueKey('srvremesh-$_serverRemesh'),
                                  enabled: !_running,
                                  initialSelection: _serverRemesh,
                                  label: const Text('Polygonform'),
                                  expandedInsets: EdgeInsets.zero,
                                  dropdownMenuEntries: const [
                                    DropdownMenuEntry(
                                        value: 'none',
                                        label: 'Original (Standard)'),
                                    DropdownMenuEntry(
                                        value: 'quad',
                                        label: 'Vierecke (Quads)'),
                                    DropdownMenuEntry(
                                        value: 'triangle',
                                        label: 'Dreiecke, neu vernetzt'),
                                  ],
                                  onSelected: (value) {
                                    if (value != null) {
                                      setState(
                                          () => _serverRemesh = value);
                                    }
                                  },
                                ),
                              ],
                              if (can.contains('target_count')) ...[
                                const SizedBox(height: 12),
                                DropdownMenu<int>(
                                  key: ValueKey(
                                      'srvpoly-$_serverTargetCount'),
                                  enabled: !_running,
                                  initialSelection: _serverTargetCount,
                                  label: const Text('Polygonzahl'),
                                  expandedInsets: EdgeInsets.zero,
                                  dropdownMenuEntries: const [
                                    DropdownMenuEntry(
                                        value: 0,
                                        label: 'Maximum (Standard)'),
                                    DropdownMenuEntry(
                                        value: 30000,
                                        label: '≈ 30.000 (hoch)'),
                                    DropdownMenuEntry(
                                        value: 10000,
                                        label: '≈ 10.000 (Spiele/AR)'),
                                    DropdownMenuEntry(
                                        value: 4000,
                                        label: '≈ 4.000 (sehr schlank)'),
                                  ],
                                  onSelected: (value) {
                                    if (value != null) {
                                      setState(() =>
                                          _serverTargetCount = value);
                                    }
                                  },
                                ),
                              ],
                              if (can.contains('resolution')) ...[
                                const SizedBox(height: 12),
                                DropdownMenu<int>(
                                  key:
                                      ValueKey('srvres-$_serverResolution'),
                                  enabled: !_running,
                                  initialSelection: _serverResolution,
                                  label: const Text(
                                      'Detailgrad (Schnitz-Raster)'),
                                  expandedInsets: EdgeInsets.zero,
                                  dropdownMenuEntries: const [
                                    DropdownMenuEntry(
                                        value: 256,
                                        label: '256 (Standard)'),
                                    DropdownMenuEntry(
                                        value: 320,
                                        label: '320 (feiner)'),
                                    DropdownMenuEntry(
                                        value: 384,
                                        label:
                                            '384 (am feinsten, langsamer)'),
                                  ],
                                  onSelected: (value) {
                                    if (value != null) {
                                      setState(() =>
                                          _serverResolution = value);
                                    }
                                  },
                                ),
                              ],
                              if (can.contains('bake_texture'))
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                      'Textur backen statt Vertex-Farben'),
                                  subtitle: const Text(
                                      'Erzeugt eine echte UV-Textur – die '
                                      'Farbschärfe hängt dann nicht mehr '
                                      'an der Netzdichte. Braucht die '
                                      'Pakete xatlas und moderngl im '
                                      'Server.'),
                                  value: _serverBakeTexture,
                                  onChanged: _running
                                      ? null
                                      : (v) => setState(
                                          () => _serverBakeTexture = v),
                                ),
                            ],
                          );
                        }),
                        const SizedBox(height: 12),
                      ] else if (isFal) ...[
                        DropdownMenu<String>(
                          key: ValueKey('falmodel-$_falModel'),
                          enabled: !_running,
                          initialSelection: _falModel,
                          label: const Text('3D-Modell (fal.ai)'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: [
                            for (final model in falModels)
                              DropdownMenuEntry(
                                  value: model.id, label: model.label),
                          ],
                          onSelected: (value) {
                            if (value != null) {
                              setState(() => _falModel = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _falCustomCtrl,
                          enabled: !_running,
                          decoration: const InputDecoration(
                            labelText:
                                'Eigene fal.ai-Modell-ID (optional)',
                            hintText: 'z. B. fal-ai/hunyuan3d/v2/mini',
                            helperText:
                                'Überschreibt die Auswahl oben – für '
                                'weitere Bild→3D-Modelle vom '
                                'fal.ai-Marktplatz (Kennung von '
                                'fal.ai/models). Beta: Modelle mit '
                                'abweichenden Eingabefeldern melden '
                                'einen 422-Fehler mit dem erwarteten '
                                'Feldnamen.',
                            helperMaxLines: 5,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'TRELLIS: bester Einstieg (Preis/Leistung) · '
                          'TripoSR: am schnellsten · Hunyuan3D: beste '
                          'Qualität für Objekte wie Fahrzeuge und '
                          'Gebäude (Game-Assets).',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                      ] else if (!isLocal) ...[
                        DropdownMenu<String>(
                          key: ValueKey(
                              'gen-${settings.threeDProvider}'
                              '-${isTripo ? _tripoVersion : _meshyAiModel}'),
                          enabled: !_running,
                          initialSelection:
                              isTripo ? _tripoVersion : _meshyAiModel,
                          label: const Text('3D-Modell (KI-Generation)'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: isTripo
                              ? const [
                                  DropdownMenuEntry(
                                      value: '',
                                      label:
                                          'Standard (v2.5, bewährt)'),
                                  DropdownMenuEntry(
                                      value: 'v3.0-20250812',
                                      label: 'v3.0 (H3)'),
                                  DropdownMenuEntry(
                                      value: 'v3.1-20260211',
                                      label:
                                          'Neueste (H3.1, beste Qualität)'),
                                ]
                              : const [
                                  DropdownMenuEntry(
                                      value: '',
                                      label: 'Standard (API-Vorgabe)'),
                                  DropdownMenuEntry(
                                      value: 'meshy-5',
                                      label: 'Meshy 5'),
                                  DropdownMenuEntry(
                                      value: 'meshy-6',
                                      label: 'Meshy 6'),
                                  DropdownMenuEntry(
                                      value: 'meshy-7',
                                      label:
                                          'Meshy 7 (neueste Generation)'),
                                  DropdownMenuEntry(
                                      value: 'latest',
                                      label:
                                          'Neueste (beste Qualität)'),
                                ],
                          onSelected: (value) {
                            if (value == null) return;
                            setState(() {
                              if (isTripo) {
                                _tripoVersion = value;
                              } else {
                                _meshyAiModel = value;
                              }
                            });
                          },
                        ),
                        if (!isTripo && _meshyAiModel == 'meshy-7')
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Ultra Mode (Meshy 7)'),
                            subtitle: const Text(
                                'Maximale Geometrie-Treue zum Bild – '
                                'wirkt nur bei Einzelbild→3D (bei '
                                'mehreren Ansichten ohne Wirkung), '
                                'höhere Credit-Kosten.'),
                            value: _meshyUltra,
                            onChanged: _running
                                ? null
                                : (v) =>
                                    setState(() => _meshyUltra = v),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (usesImageAi) ...[
                        DropdownMenu<String>(
                          key: ValueKey(
                              '3d-model-${provider.name}-$currentModel'),
                          initialSelection: currentModel,
                          label: Text(
                              'Bild-KI-Modell (${provider.label})'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: [
                            for (final option in knownModels)
                              DropdownMenuEntry(
                                  value: option.$1, label: option.$2),
                            if (!knownModels
                                .any((o) => o.$1 == currentModel))
                              DropdownMenuEntry(
                                value: currentModel,
                                label: '$currentModel (eigene ID)',
                              ),
                          ],
                          onSelected: (value) {
                            if (value != null) {
                              settings.setModelFor(provider, value);
                            }
                          },
                        ),
                        if (provider == GenProvider.gemini &&
                            settings.geminiModel.contains('pro')) ...[
                          const SizedBox(height: 12),
                          DropdownMenu<String>(
                            key: ValueKey(
                                '3d-imgsize-${settings.geminiImageSize}'),
                            initialSelection: settings.geminiImageSize,
                            label: const Text('Auflösung der Ansichten'),
                            expandedInsets: EdgeInsets.zero,
                            dropdownMenuEntries: [
                              for (final option in geminiImageSizeOptions)
                                DropdownMenuEntry(
                                    value: option.$1, label: option.$2),
                            ],
                            onSelected: (value) {
                              if (value != null) {
                                settings.setGeminiImageSize(value);
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Der Bild-Provider selbst wird im '
                          'Generator-Tab gewählt; die Ansichten-Schärfe '
                          'bestimmt die Textur-Schärfe des Modells.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ] else
                        Text(
                          'Dieser Lauf nutzt keine Bild-KI-Schritte – '
                          'die Kosten entstehen nur beim 3D-Dienst.',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  );
                  final panel = CostQualityPanel(estimate: estimate);
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 460) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: controls),
                            const SizedBox(width: 12),
                            panel,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          controls,
                          const SizedBox(height: 12),
                          panel,
                        ],
                      );
                    },
                  );
                }),
                const SizedBox(height: 8),
                const SectionLabel('Optionen'),
                if (isLocal) ...[
                  Text(
                    'Echtes räumliches 360°-Modell: Aus den Silhouetten '
                    'von Vorn/Links/Rechts/Hinten wird ein Volumen '
                    'geschnitzt (Visual Hull), die Oberfläche geglättet '
                    'und mit den Bildfarben eingefärbt – die Ansichten '
                    'werden dabei weich nach Blickrichtung gemischt '
                    '(keine harten Farbnähte).',
                    style: theme.textTheme.bodySmall,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('KI-Tiefenschätzung (Vertiefungen)'),
                    subtitle: Text(
                        'Formt Mulden und Vertiefungen: Per '
                        '${settings.provider.label} geschätzte '
                        'Tiefenkarten der Vorder-/Rückansicht schieben '
                        'die Oberfläche nach innen – überwindet die '
                        'Silhouetten-Grenze des Visual Hull. '
                        'Ca. 1 Bild je Tiefenkarte.'),
                    value: _localDepthAi,
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _localDepthAi = v),
                  ),
                  _autoRigSwitch(),
                  Row(
                    children: [
                      const SizedBox(width: 90, child: Text('Detailgrad')),
                      Expanded(
                        child: Slider(
                          value: _localResolution.toDouble(),
                          min: 48,
                          max: 160,
                          divisions: 14,
                          label: '$_localResolution',
                          onChanged: _running
                              ? null
                              : (v) => setState(
                                  () => _localResolution = v.round()),
                        ),
                      ),
                      Text('$_localResolution'),
                    ],
                  ),
                  _optionInfo(
                      'Auflösung des Schnitz-Rasters (Voxel je Achse): '
                      'höher = feinere Details und mehr Polygone, aber '
                      'spürbar mehr Rechenzeit. 96 ist ein guter '
                      'Kompromiss, 160 das Maximum für feinste Details.'),
                  Row(
                    children: [
                      const SizedBox(width: 90, child: Text('Glättung')),
                      Expanded(
                        child: Slider(
                          value: _localSmoothing.toDouble(),
                          min: 0,
                          max: 5,
                          divisions: 5,
                          label: '$_localSmoothing',
                          onChanged: _running
                              ? null
                              : (v) => setState(
                                  () => _localSmoothing = v.round()),
                        ),
                      ),
                      Text('$_localSmoothing'),
                    ],
                  ),
                  _optionInfo(
                      'Glättungsdurchläufe der Oberfläche: mehr = '
                      'weichere, organischere Formen; weniger = kantiger '
                      'und erhält kleine Details. 2 ist der bewährte '
                      'Standard.'),
                  DropdownMenu<int>(
                    key: ValueKey('ltris-$_localTargetTriangles'),
                    enabled: !_running,
                    initialSelection: _localTargetTriangles,
                    label: const Text('Polygonzahl (Dreiecke)'),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(
                          value: 0, label: 'Alle behalten (Standard)'),
                      DropdownMenuEntry(
                          value: 50000, label: '≈ 50.000 (hohe Qualität)'),
                      DropdownMenuEntry(
                          value: 20000, label: '≈ 20.000 (Spiele/AR)'),
                      DropdownMenuEntry(
                          value: 10000, label: '≈ 10.000 (Web/Vorschau)'),
                      DropdownMenuEntry(
                          value: 5000, label: '≈ 5.000 (sehr schlank)'),
                    ],
                    onSelected: (value) {
                      if (value != null) {
                        setState(() => _localTargetTriangles = value);
                      }
                    },
                  ),
                  _optionInfo(
                      'Reduziert das fertige Netz auf ungefähr diese '
                      'Dreieckszahl (Vertex-Clustering, die Farben '
                      'bleiben erhalten) – kleinere Dateien für Spiele, '
                      'AR und Web. Für 3D-Druck besser „Alle behalten“.'),
                  DropdownMenu<String>(
                    key: ValueKey('ltex-$_localTextureMode'),
                    enabled: !_running,
                    initialSelection: _localTextureMode,
                    label: const Text('Textur-Modus'),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(
                          value: 'atlas2048',
                          label:
                              'Hochauflösende Textur 2048 px (Standard)'),
                      DropdownMenuEntry(
                          value: 'atlas1024',
                          label:
                              'Hochauflösende Textur 1024 px (kleiner)'),
                      DropdownMenuEntry(
                          value: 'vertex',
                          label: 'Vertex-Farben (kompakt, ohne Textur)'),
                    ],
                    onSelected: (value) {
                      if (value != null) {
                        setState(() => _localTextureMode = value);
                      }
                    },
                  ),
                  _optionInfo(
                      'Hochauflösende Textur: Die Ansichtsfarben werden '
                      'in einen echten Textur-Atlas gebacken – jedes '
                      'Dreieck erhält viele Farbpixel statt nur drei '
                      'Vertex-Farben, die Oberfläche wird deutlich '
                      'schärfer (etwas größere Datei und Rechenzeit). '
                      '„Vertex-Farben“ ist die kompakte Variante, deren '
                      'Farbschärfe an der Netzdichte hängt.'),
                  DropdownMenu<String>(
                    key: ValueKey('lsurf-$_localSurface'),
                    enabled: !_running,
                    initialSelection: _localSurface,
                    label: const Text('Oberfläche (PBR-Material)'),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      for (final (value, name, _, _) in _surfaceOptions)
                        DropdownMenuEntry(value: value, label: name),
                    ],
                    onSelected: (value) {
                      if (value != null) {
                        setState(() => _localSurface = value);
                      }
                    },
                  ),
                  _optionInfo(
                      'PBR-Materialwerte (Metall/Rauheit) im GLB: '
                      'bestimmen, wie das Modell beleuchtet wird – von '
                      'matt bis metallisch glänzend. Die 3D-Vorschau '
                      'zeigt den Effekt direkt (Glanzlichter), Blender, '
                      'Unity & Co. nutzen dieselben Werte.'),
                ] else if (isStability) ...[
                  Text(
                    'Textur (PBR) ist immer im Modell enthalten. '
                    'Realistische Erwartung: Stability ist die schnelle, '
                    'sehr günstige Variante (wenige Cent pro Modell) – '
                    'feine Details wie Gesichter werden weich, eng '
                    'anliegende Arme/Beine können mit dem Körper '
                    'verschmelzen. Tipp: Ausgangsbild mit frei '
                    'stehenden Gliedmaßen (z. B. T-Pose) verwenden. Für '
                    'Figuren in Top-Qualität Meshy oder Tripo wählen '
                    '(siehe „Kosten & Qualität im Vergleich“).',
                    style: theme.textTheme.bodySmall,
                  ),
                  _autoRigSwitch(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    initiallyExpanded: true,
                    title: const Text('Qualitäts-Optionen (Profi)'),
                    subtitle: Text(
                      'Textur, Polygonform & -zahl, Detailgrad – die '
                      'Engine steht oben bei „Modell & Kosten“',
                      style: theme.textTheme.bodySmall,
                    ),
                    children: [
                      DropdownMenu<int>(
                        key: ValueKey('stex-$_stabilityTextureRes'),
                        enabled: !_running,
                        initialSelection: _stabilityTextureRes,
                        label: const Text('Textur-Auflösung'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(
                              value: 512, label: '512 px (klein)'),
                          DropdownMenuEntry(
                              value: 1024, label: '1024 px'),
                          DropdownMenuEntry(
                              value: 2048,
                              label: '2048 px (Standard, am schärfsten)'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            setState(() => _stabilityTextureRes = value);
                          }
                        },
                      ),
                      _optionInfo(
                          'Größe der Textur im GLB: 2048 px liefert die '
                          'schärfsten Oberflächen, 512 px die kleinste '
                          'Datei. Kosten bleiben gleich.'),
                      DropdownMenu<String>(
                        key: ValueKey('sremesh-$_stabilityRemesh'),
                        enabled: !_running,
                        initialSelection: _stabilityRemesh,
                        label: const Text('Polygonform (Remesh)'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(
                              value: 'none',
                              label: 'Original (Standard – volle Details)'),
                          DropdownMenuEntry(
                              value: 'quad',
                              label: 'Vierecke (Quads)'),
                          DropdownMenuEntry(
                              value: 'triangle',
                              label: 'Dreiecke (gleichmäßig neu vernetzt)'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            setState(() => _stabilityRemesh = value);
                          }
                        },
                      ),
                      _optionInfo(
                          'Form der Polygone: „Vierecke“ erzeugt ein '
                          'sauberes Quad-Netz – ideal für Blender, '
                          'Animation und Weiterbearbeitung; „Dreiecke“ '
                          'vernetzt gleichmäßig neu; „Original“ behält '
                          'das unveränderte Netz mit allen Details.'),
                      DropdownMenu<int>(
                        key: ValueKey('spoly-$_stabilityPolycount'),
                        enabled: !_running,
                        initialSelection: _stabilityPolycount,
                        label: const Text('Polygonzahl'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(
                              value: 0,
                              label: 'Maximum (Standard – keine Reduktion)'),
                          DropdownMenuEntry(
                              value: 20000, label: '≈ 20.000 (hoch)'),
                          DropdownMenuEntry(
                              value: 10000, label: '≈ 10.000 (Spiele/AR)'),
                          DropdownMenuEntry(
                              value: 5000, label: '≈ 5.000 (Web)'),
                          DropdownMenuEntry(
                              value: 2000, label: '≈ 2.000 (sehr schlank)'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            setState(() => _stabilityPolycount = value);
                          }
                        },
                      ),
                      _optionInfo(
                          'Ziel-Polygonzahl des Modells: „Maximum“ '
                          'behält die volle Geometrie; kleinere Werte '
                          'lassen Stability das Netz direkt auf die '
                          'Zielzahl reduzieren (bei Fast 3D wirksam in '
                          'Kombination mit einem Remesh).'),
                      DropdownMenu<String>(
                        key: ValueKey('sdetail-$_stabilityDetail'),
                        enabled: !_running,
                        initialSelection: _stabilityDetail,
                        label: const Text('Detailgrad'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(
                              value: 'auto',
                              label: 'Ausgewogen (Standard – API-Vorgabe)'),
                          DropdownMenuEntry(
                              value: 'fine',
                              label: 'Fein (etwas weniger Rand)'),
                          DropdownMenuEntry(
                              value: 'safe',
                              label: 'Sicher (mehr Rand ums Objekt)'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            setState(() => _stabilityDetail = value);
                          }
                        },
                      ),
                      _optionInfo(
                          '„Fein“ rückt das Objekt moderat näher (etwas '
                          'mehr Pixel pro Fläche). Ganz ohne Rand '
                          'verformt Stability Modelle nachweislich '
                          '(aufgeblähte Formen) – deshalb ist '
                          '„Ausgewogen“ die empfohlene Vorgabe; '
                          '„Sicher“ lässt extra viel Rand.'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                            'Symmetrisieren (lokale Veredelung)'),
                        subtitle: const Text(
                            'Ersetzt die vom Foto abgewandte, '
                            'verwaschene Modellhälfte durch die '
                            'gespiegelte bessere Hälfte – ideal für '
                            'Fahrzeuge und andere symmetrische Motive; '
                            'bei bewusst unsymmetrischen Motiven '
                            'ausschalten. Läuft komplett lokal (keine '
                            'Zusatzkosten); PBR-Zusatztexturen werden '
                            'dabei zu Pauschalwerten.'),
                        value: _refineSymmetrize,
                        onChanged: _running
                            ? null
                            : (v) =>
                                setState(() => _refineSymmetrize = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                            'Textur aus Originalbild schärfen '
                            '(lokale Veredelung)'),
                        subtitle: const Text(
                            'Projiziert das scharfe Ausgangsbild zurück '
                            'auf die sichtbare Seite des Modells und '
                            'ersetzt dort die weiche Stability-Textur – '
                            'mit automatischer Kalibrierung; verdeckte '
                            'und abgewandte Flächen bleiben unberührt. '
                            'Greift nur, wenn Bild und Modell '
                            'zusammenpassen; komplett lokal, keine '
                            'Zusatzkosten.'),
                        value: _refineProjectTexture,
                        onChanged: _running
                            ? null
                            : (v) => setState(
                                () => _refineProjectTexture = v),
                      ),
                    ],
                  ),
                ] else if (isRodin) ...[
                  Text(
                    'Textur (PBR) ist immer im Modell enthalten; bei '
                    'aktiver T-Pose bzw. Rigging erzeugt Rodin Figuren '
                    'direkt in T/A-Pose. Rigging übernimmt der eigene '
                    'lokale Auto-Rigger (kostenlos).',
                    style: theme.textTheme.bodySmall,
                  ),
                  _autoRigSwitch(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    initiallyExpanded: true,
                    title: const Text('Qualitäts-Optionen (Profi)'),
                    subtitle: Text(
                      'Topologie & Polygonzahl – die Generation steht '
                      'oben bei „Modell & Kosten“',
                      style: theme.textTheme.bodySmall,
                    ),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Quad-Topologie'),
                        subtitle: const Text(
                            'Sauberes Vierecks-Netz (Rodins '
                            'Spezialität) – ideal für Blender, '
                            'Animation und Game-Engines. Aus = rohes '
                            'Dreiecks-Netz mit maximaler '
                            'Detaildichte.'),
                        value: _rodinQuad,
                        onChanged: _running
                            ? null
                            : (v) => setState(() => _rodinQuad = v),
                      ),
                      DropdownMenu<int>(
                        key: ValueKey('rodinpoly-$_rodinPolycount'),
                        enabled: !_running,
                        initialSelection: _rodinPolycount,
                        label: const Text('Polygonzahl'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(
                              value: 0,
                              label: 'Standard (API-Vorgabe)'),
                          DropdownMenuEntry(
                              value: 100000,
                              label: '≈ 100.000 (sehr hoch)'),
                          DropdownMenuEntry(
                              value: 30000, label: '≈ 30.000 (hoch)'),
                          DropdownMenuEntry(
                              value: 10000,
                              label: '≈ 10.000 (Spiele/AR)'),
                          DropdownMenuEntry(
                              value: 4000,
                              label: '≈ 4.000 (sehr schlank)'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            setState(() => _rodinPolycount = value);
                          }
                        },
                      ),
                      _optionInfo(
                          'Ziel-Polygonzahl des Meshes '
                          '(quality_override): „Standard“ überlässt '
                          'Rodin die Wahl; kleinere Werte liefern '
                          'direkt engine-fertige Assets.'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                            'Symmetrisieren (lokale Veredelung)'),
                        subtitle: const Text(
                            'Ersetzt die schwächere Modellhälfte durch '
                            'die gespiegelte bessere – für Fahrzeuge '
                            'und andere symmetrische Motive; bei '
                            'unsymmetrischen Motiven ausschalten. '
                            'Komplett lokal, keine Zusatzkosten.'),
                        value: _refineSymmetrize,
                        onChanged: _running
                            ? null
                            : (v) =>
                                setState(() => _refineSymmetrize = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                            'Textur aus Originalbild schärfen '
                            '(lokale Veredelung)'),
                        subtitle: const Text(
                            'Projiziert das scharfe Ausgangsbild '
                            'zurück auf die sichtbare Modellseite – '
                            'greift nur, wenn die automatische '
                            'Kalibrierung Bild und Modell sicher '
                            'zusammenbringt; ohne Ausgangsbild '
                            '(natives Text→3D) ohne Wirkung. Komplett '
                            'lokal, keine Zusatzkosten.'),
                        value: _refineProjectTexture,
                        onChanged: _running
                            ? null
                            : (v) => setState(
                                () => _refineProjectTexture = v),
                      ),
                    ],
                  ),
                ] else if (isFal || isSelfHost || isReplicate) ...[
                  Text(
                    isSelfHost
                        ? 'Der Server liefert das Modell inklusive '
                            'Farben – alles kostenlos auf der eigenen '
                            'GPU. Rigging übernimmt der eigene lokale '
                            'Auto-Rigger, die lokale Veredelung '
                            '(Symmetrisieren, Textur schärfen) steht '
                            'wie bei Stability zur Verfügung.'
                        : 'Textur ist im Modell enthalten. Rigging '
                            'übernimmt der eigene lokale Auto-Rigger '
                            '(kostenlos) – die lokale Veredelung '
                            '(Symmetrisieren, Textur schärfen) steht '
                            'wie bei Stability zur Verfügung.',
                    style: theme.textTheme.bodySmall,
                  ),
                  _autoRigSwitch(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title:
                        const Text('Symmetrisieren (lokale Veredelung)'),
                    subtitle: const Text(
                        'Ersetzt die schwächere Modellhälfte durch die '
                        'gespiegelte bessere – für Fahrzeuge und andere '
                        'symmetrische Motive; bei unsymmetrischen '
                        'Motiven ausschalten. Komplett lokal, keine '
                        'Zusatzkosten.'),
                    value: _refineSymmetrize,
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _refineSymmetrize = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                        'Textur aus Originalbild schärfen '
                        '(lokale Veredelung)'),
                    subtitle: const Text(
                        'Projiziert das scharfe Ausgangsbild zurück auf '
                        'die sichtbare Modellseite – greift nur, wenn '
                        'die automatische Kalibrierung Bild und Modell '
                        'sicher zusammenbringt (die Ausrichtung dieser '
                        'Modelle variiert je nach Anbieter). '
                        'Komplett lokal, keine Zusatzkosten.'),
                    value: _refineProjectTexture,
                    onChanged: _running
                        ? null
                        : (v) =>
                            setState(() => _refineProjectTexture = v),
                  ),
                ] else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Textur (bemalte Oberfläche)'),
                    subtitle: const Text(
                        'Aus: nur Geometrie – schneller und günstiger'),
                    value: _texture,
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _texture = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rigging (Skelett für Animation)'),
                    subtitle: Text(_imageMode
                        ? 'Nur für Figuren/Charaktere geeignet'
                        : 'Nur für Figuren – „T-Pose“ wird automatisch an '
                            'den Prompt angehängt'),
                    value: _rigging,
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _rigging = v),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    initiallyExpanded: true,
                    title: const Text('Qualitäts-Optionen (Profi)'),
                    subtitle: Text(
                      isTripo
                          ? 'Textur-Qualität, Topologie – die '
                              'KI-Generation steht oben bei '
                              '„Modell & Kosten“'
                          : 'Polygone, Symmetrie, PBR … – die '
                              'KI-Generation steht oben bei '
                              '„Modell & Kosten“',
                      style: theme.textTheme.bodySmall,
                    ),
                    children: [
                      if (!isTripo) ...[
                        DropdownMenu<int>(
                          key: ValueKey('poly-$_meshyPolycount'),
                          enabled: !_running,
                          initialSelection: _meshyPolycount,
                          label: const Text('Detailgrad (Polygone)'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: const [
                            DropdownMenuEntry(
                                value: 0, label: 'Standard (ca. 30.000)'),
                            DropdownMenuEntry(
                                value: 10000,
                                label: 'Niedrig (10.000) – für Spiele'),
                            DropdownMenuEntry(
                                value: 100000, label: 'Hoch (100.000)'),
                            DropdownMenuEntry(
                                value: 300000, label: 'Ultra (300.000)'),
                          ],
                          onSelected: (value) {
                            if (value != null) {
                              setState(() => _meshyPolycount = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 90, child: Text('Symmetrie')),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                        value: 'auto', label: Text('Auto')),
                                    ButtonSegment(
                                        value: 'on', label: Text('An')),
                                    ButtonSegment(
                                        value: 'off', label: Text('Aus')),
                                  ],
                                  selected: {_symmetryMode},
                                  onSelectionChanged: _running
                                      ? null
                                      : (selection) => setState(() =>
                                          _symmetryMode = selection.first),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '„An“ hilft bei Figuren, Fahrzeugen und Gebäuden; '
                          '„Aus“ für bewusst asymmetrische Motive.',
                          style: theme.textTheme.bodySmall,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('PBR-Material'),
                          subtitle: const Text(
                              'Zusätzliche Material-Maps (Metall, Rauheit, '
                              'Normal) für realistischere Oberflächen'),
                          value: _pbr,
                          onChanged: _running
                              ? null
                              : (v) => setState(() => _pbr = v),
                        ),
                      ],
                      if (isTripo)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Textur-Qualität „detailliert“'),
                          subtitle: const Text(
                              'Höher aufgelöste Texturen – kostet '
                              'zusätzliche Credits'),
                          value: _tripoDetailedTexture,
                          onChanged: _running || !_texture
                              ? null
                              : (v) =>
                                  setState(() => _tripoDetailedTexture = v),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Quad-Topologie'),
                        subtitle: const Text(
                            'Viereck-Netz statt Dreiecke – sauberer für '
                            'Blender, Animation und Weiterbearbeitung'),
                        value: _quadTopology,
                        onChanged: _running
                            ? null
                            : (v) => setState(() => _quadTopology = v),
                      ),
                      if (!isTripo && _texture) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _texturePromptCtrl,
                          enabled: !_running,
                          decoration: const InputDecoration(
                            labelText: 'Textur-Beschreibung (optional)',
                            hintText: 'z. B. „abgenutztes dunkles Metall '
                                'mit Kratzern“',
                            helperText:
                                'Beschreibt nur die Oberfläche – die Form '
                                'kommt aus dem Haupt-Prompt bzw. Bild.',
                            helperMaxLines: 2,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  leading: const Icon(Icons.lightbulb_outline),
                  title: const Text('Tipps für bessere 3D-Modelle'),
                  children: [
                    Text(
                      '• Ein Motiv pro Modell: ein einzelnes, '
                      'freistehendes Objekt beschreiben oder zeigen – '
                      'keine Szenen mit mehreren Objekten.\n'
                      '• Figuren in T-Pose erzeugen (Schalter im '
                      'Text-Modus) – gespreizte Arme rekonstruieren sich '
                      'deutlich besser, auch ohne Rigging. Beim Rigging '
                      'von Tieren, Robotern oder Fantasy-Wesen den '
                      'passenden Figurtyp wählen – die richtige Rig-Pose '
                      'wird automatisch verwendet.\n'
                      '• Erzeugte Ansichten kurz prüfen: eine unpassende '
                      'Ansicht löschen (X) und neu erzeugen lassen kostet '
                      'nur ein Bild, verbessert das Modell aber stark.\n'
                      '• Eigene Bilder: Motiv vollständig sichtbar, '
                      'möglichst transparenter oder neutraler Hintergrund, '
                      'gleichmäßiges Licht ohne harte Schatten. Fehlende '
                      'Ansichten ergänzt die Bild-KI auf Wunsch '
                      'automatisch und konsistent.\n'
                      '• Meshy/Tripo: In den Qualitäts-Optionen die '
                      'neueste KI-Generation wählen – der größte '
                      'Qualitätssprung. Mehr Polygone und PBR bzw. '
                      '„detailliert“ für feinere Details.\n'
                      '• Lokal (360°-Modell): je mehr Ansichten, desto '
                      'genauer. Mulden und Vertiefungen entstehen mit der '
                      'KI-Tiefenschätzung; echte Hohlräume und komplexe '
                      'Figuren beherrschen die trainierten generativen '
                      'Provider (Stability, Meshy, Tripo) am besten.\n'
                      '• Text→3D-Prompts knapp halten: Objektklasse → '
                      'Silhouette → wenige markante Merkmale. Der '
                      'Negativ-Prompt (Meshy/Tripo) hilft gegen '
                      '„blobby“, schwebende Teile oder ungewollte '
                      'Sockel.\n'
                      '• Fahrzeuge & Hard-Surface: Text→3D ist vor '
                      'allem auf Charaktere und Props trainiert – Räder '
                      'und Radkästen gelingen über den Bild-Weg (erst '
                      'Bild generieren, dann „Aus Bild“) fast immer '
                      'besser. Als Bildvorlage eine Dreiviertelansicht '
                      '(schräg von vorn, Seite sichtbar) verwenden – '
                      'aus einer reinen Frontalansicht ohne Perspektive '
                      'entsteht nur eine flache Platte.\n'
                      '• Saubere Topologie: Die Ausgabe ist ein dichtes, '
                      'unregelmäßiges Dreiecksnetz. Für scharfe Kanten '
                      '„Vierecke (Quads)“ bzw. Quad-Topologie wählen und '
                      'für professionelle Weiterbearbeitung eine '
                      'Retopologie in Blender einplanen.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  leading: const Icon(Icons.savings_outlined),
                  title: const Text('Kosten & Qualität im Vergleich'),
                  children: [
                    Text(
                      'Gesamtkosten je Komplettmodell mit Textur und '
                      'Rigging:\n'
                      '• Lokal: 0 € – Auto-Rigging der App inklusive; '
                      '„Textur“ sind Vertex-Farben statt echter '
                      'Textur-Maps, keine Hohlräume. Per Text nur '
                      'Bildkosten (ca. 4–6 Bilder, wenige Cent).\n'
                      '• Stability + App-Rigging: ca. 4–10 Credits '
                      '(≈ 0,04–0,10 \$) – echte PBR-Texturen sind immer '
                      'dabei, das Skelett baut die App kostenlos ein. '
                      'Günstigste Variante mit echter Textur.\n'
                      '• Tripo3D: ca. 75 Credits komplett (35 Rohmodell '
                      '+ 20 Textur + 20 Rigging) ≈ 0,75 € – kleinstes '
                      'Paket 10 € = 1000 Credits, also ~13 '
                      'Komplettmodelle; Startguthaben für neue Konten. '
                      'Höchste Qualität und professionelles natives '
                      'Rigging.\n'
                      '• Meshy: ca. 20–30 Credits (Geometrie + Textur + '
                      'Rigging), API aber nur mit Pro-Abo '
                      '(≈ 16 \$/Monat = 1000 Credits) – Top-Qualität, '
                      'lohnt bei regelmäßiger Nutzung.\n'
                      'Empfehlung: Am günstigsten mit echter Textur und '
                      'Skelett ist Stability plus App-Rigging (wenige '
                      'Cent). Die beste Rigging-Qualität liefert Tripo3D '
                      '(~0,75 € je Komplettmodell). Preise laut Anbieter '
                      '(Stand 2026) – können sich ändern.\n\n'
                      'Kommerzielle Nutzung: Alle vier Wege liefern '
                      'kommerziell nutzbare Modelle. Lokal erzeugte '
                      'Modelle gehören vollständig dir. Stability: frei '
                      'kommerziell nutzbar bis 1 Mio. \$ Jahresumsatz '
                      '(darüber Enterprise-Lizenz nötig). Tripo3D über '
                      'API/bezahlte Credits und Meshy ab Pro-Abo: volle '
                      'kommerzielle Rechte, Modelle bleiben privat und '
                      'werden nicht fürs Training verwendet. Nur die '
                      'Gratis-Webportale von Meshy/Tripo vergeben '
                      'CC-BY-Lizenzen mit Namensnennung – die nutzt '
                      'diese App nicht. Wichtig bleibt: keine fremden '
                      'Marken oder geschützten Charaktere als Motiv.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _running ? null : _generate,
                        icon: _running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.view_in_ar),
                        label: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            _running
                                ? 'Wird generiert …'
                                : '3D-Modell generieren',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                    if (_running) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () =>
                            setState(() => _cancelRequested = true),
                        child: const Text('Abbrechen'),
                      ),
                    ],
                  ],
                ),
                if (_running && _stage != null) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Text(
                    isLocal
                        ? '$_stage'
                        : '$_stage\nEine 3D-Generierung dauert je nach '
                            'Optionen 2–10 Minuten.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              _error!,
                              style: TextStyle(
                                  color:
                                      theme.colorScheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Ergebnisse (diese Sitzung)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Generierte Modelle landen zusätzlich in der Galerie '
          '(Web: nur für die aktuelle Sitzung). Eigene GLB-, STL- oder '
          'OBJ-Dateien einfach per Drag & Drop hierher ziehen – sie '
          'öffnen sich im Viewer.',
          style: theme.textTheme.bodySmall,
        ),
        if (_usageInfo != null) ...[
          const SizedBox(height: 4),
          Text(
            _usageInfo!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
        const SizedBox(height: 8),
        if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.view_in_ar_outlined,
                      size: 64, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  Text('Noch keine 3D-Modelle generiert.',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          )
        else
          for (final result in _results)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.all(8),
                leading: result.thumbnailBytes != null
                    ? InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ImageDetailScreen(
                                bytes: result.thumbnailBytes!,
                                fileName: 'vorschau.png',
                                mimeType: 'image/png',
                                prompt: result.label,
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(result.thumbnailBytes!,
                              width: 64, height: 64, fit: BoxFit.cover),
                        ),
                      )
                    : const Icon(Icons.view_in_ar, size: 40),
                title: Text(result.label,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  result.providerLabel,
                  '${(result.glbBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB',
                  result.textured ? 'mit Textur' : 'ohne Textur',
                  if (result.rigged) 'geriggt',
                ].join(' · ')),
                onTap: () => _openModelPreview(result),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '3D-Ansicht (frei drehbar)',
                      icon: const Icon(Icons.threed_rotation),
                      onPressed: () => _openModelPreview(result),
                    ),
                    IconButton(
                      tooltip: 'Erstellungsnachweis (PDF)',
                      icon: const Icon(Icons.workspace_premium_outlined),
                      onPressed: () => _exportModelProvenance(result),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _showExportMenu(result),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Export'),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        // Versions-Kennung: zeigt, welcher Stand wirklich läuft (der
        // Web-Cache liefert nach Updates gern noch die alte Version –
        // dann erneut neu laden).
        Center(
          child: Text(
            '3DGenerator · Stand: $buildInfo',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ],
        ),
      ),
    );
  }
}
