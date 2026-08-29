import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auto_rig.dart';
import '../services/exporter.dart';
import '../services/generators.dart' show GenerationException;
import '../services/local_3d.dart';
import '../services/meshy_service.dart';
import '../services/model_import.dart';
import '../services/provenance.dart';
import '../services/settings_service.dart';
import '../services/stability_3d_service.dart';
import '../services/tripo_service.dart';
import '../services/view_generator.dart';
import '../widgets/common.dart';
import 'image_detail_screen.dart';
import 'model_preview_screen.dart';

/// 3D-Bereich: Figuren und Objekte aus Text oder Bild generieren
/// (Meshy AI), optional mit Textur und Auto-Rigging, Export als GLB.
class ThreeDScreen extends StatefulWidget {
  const ThreeDScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<ThreeDScreen> createState() => _ThreeDScreenState();
}

class _ThreeDScreenState extends State<ThreeDScreen> {
  final _promptCtrl = TextEditingController();
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
  bool _rigging = false;
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
  int _meshyPolycount = 0;
  String _symmetryMode = 'auto';
  bool _quadTopology = false; // Meshy topology=quad bzw. Tripo quad=true
  bool _pbr = true;
  String _tripoVersion = '';
  bool _tripoDetailedTexture = false;
  final _texturePromptCtrl = TextEditingController();
  String _stabilityEngine = 'stable-point-aware-3d';
  int _stabilityTextureRes = 2048;

  /// Lokaler Generator: Vertiefungen per KI-Tiefenkarte formen.
  bool _localDepthAi = false;

  /// Figurtyp fürs eigene Auto-Rigging (Lokal/Stability), siehe
  /// [rigTypeOptions]: Zweibeiner, Vierbeiner, Insekt, Vogel, Schlange,
  /// Fisch.
  String _rigType = 'biped';

  // Optionen des lokalen Generators (360°-Modell).
  int _localResolution = 96;

  bool _running = false;
  bool _cancelRequested = false;
  String? _stage;
  String? _error;
  final List<ThreeDResult> _results = [];

  static const _tPoseSuffix =
      'full body character in T-pose, arms stretched out horizontally, '
      'legs slightly apart, facing forward, neutral expression';

  @override
  void dispose() {
    _cancelRequested = true;
    _promptCtrl.dispose();
    _texturePromptCtrl.dispose();
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
    final apiKey = isLocal
        ? ''
        : isStability
            ? settings.apiKeyFor(GenProvider.stability)
            : (isTripo ? settings.tripoApiKey : settings.meshyApiKey);
    if (!isLocal && (apiKey == null || apiKey.trim().isEmpty)) {
      await _showMissingKeyDialog(settings.threeDProvider);
      return;
    }
    final prompt = _promptCtrl.text.trim();
    // Text-Modus: „Lokal“ und Stability gehen immer über KI-Ansichten,
    // bei Meshy/Tripo ist die Ansichten-Pipeline zuschaltbar.
    final viewPipeline =
        !_imageMode && (isLocal || isStability || _viewsFromText);
    // Bild-Modus: fehlende Ansichten optional per Bild-KI ergänzen –
    // gleiche Konsistenz-Prompts, Vorderansicht als Referenz.
    final augmentViews = _imageMode &&
        _completeViews &&
        !isStability &&
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

    try {
      if (viewPipeline || augmentViews) {
        // Pose der Ansichten: beim eigenen Auto-Rigging die zum
        // Figurtyp passende Rig-Pose, sonst optional T-Pose.
        String? pose;
        if (_rigging && (isLocal || isStability)) {
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
          // Stability braucht nur ein Bild – das spart Kosten.
          frontOnly: isStability,
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
      } else if (isTripo) {
        await _runTripo(
            TripoService(apiKey!.trim()), prompt, cancelled, progress,
            useImages: useImages, label: label);
      } else {
        await _runMeshy(
            MeshyService(apiKey!.trim()), prompt, cancelled, progress,
            useImages: useImages, label: label);
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
        ),
      );
    });
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
      glb = await generateLocalHullGlb(
        frontBytes: source.bytes,
        leftBytes: _views['left']?.bytes,
        rightBytes: _views['right']?.bytes,
        backBytes: _views['back']?.bytes,
        frontDepthBytes: frontDepthMap,
        backDepthBytes: backDepthMap,
        resolution: _localResolution.clamp(48, 120),
      );
    } on Exception catch (e) {
      throw GenerationException(
          e.toString().replaceFirst('Exception: ', ''));
    }
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress);
    _addResult(
      glbBytes: glb,
      label: label ?? '360°-Modell (lokal)',
      providerLabel: 'Lokal',
      thumbnail: source.bytes,
      rigged: rigged,
      textured: true,
    );
  }

  /// Baut bei aktivem Rigging das lokale Standard-Skelett ins GLB ein.
  /// Liefert true, wenn das Modell geriggt wurde.
  bool _maybeInjectRig(Uint8List Function() getGlb,
      void Function(Uint8List) setGlb, void Function(String) progress) {
    if (!_rigging) return false;
    progress('Skelett wird eingebaut …');
    try {
      setGlb(injectAutoRig(getGlb(), rigType: _rigType));
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
    var glb = await service.generateModel(
      imageBytes: source.bytes,
      mimeType: source.mimeType,
      engine: _stabilityEngine,
      textureResolution: _stabilityTextureRes,
      quadRemesh: _quadTopology,
    );
    final rigged = _maybeInjectRig(() => glb, (v) => glb = v, progress);
    _addResult(
      glbBytes: glb,
      label: label,
      providerLabel: 'Stability',
      thumbnail: source.bytes,
      rigged: rigged,
      textured: true,
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
            enable: !_running,
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

  void _openModelPreview(ThreeDResult result) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ModelPreviewScreen(
        glbBytes: result.glbBytes,
        title: result.label,
        provenance: ProvenanceInfo(
          kind: '3D-Modell',
          description: result.label,
          providerLabel: result.providerLabel,
          details: {
            'Texturiert': result.textured ? 'ja' : 'nein',
            'Rigging': result.rigged ? 'ja' : 'nein',
          },
          previewBytes: result.thumbnailBytes,
        ),
      ),
    ));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsService>();
    final isTripo = settings.threeDProvider == 'tripo';
    final isLocal = settings.threeDProvider == 'local';
    final isStability = settings.threeDProvider == 'stability';
    final riggingForcesTPose = _rigging;
    // Beim eigenen Auto-Rigging kommt die Pose aus dem Figurtyp –
    // der T-Pose-Schalter wäre dann irreführend.
    final rigPoseActive = _rigging && (isLocal || isStability);
    return DropTarget(
      onDragDone: (detail) => _openDroppedModel(detail.files),
      child: ListView(
      padding: const EdgeInsets.all(16),
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
                const SectionLabel('3D-Provider'),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Builder(builder: (context) {
                    // Grüner Haken = einsatzbereit (Schlüssel hinterlegt
                    // bzw. Lokal ohne Schlüssel).
                    Widget? ready(bool available) => available
                        ? const Icon(Icons.check_circle,
                            color: Colors.green, size: 16)
                        : const Icon(Icons.key_off, size: 16);
                    final hasMeshy =
                        settings.meshyApiKey?.trim().isNotEmpty ?? false;
                    final hasTripo =
                        settings.tripoApiKey?.trim().isNotEmpty ?? false;
                    return SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: 'local',
                            label: const Text('Lokal'),
                            icon: ready(true)),
                        ButtonSegment(
                            value: 'stability',
                            label: const Text('Stability'),
                            icon: ready(settings
                                .hasApiKeyFor(GenProvider.stability))),
                        ButtonSegment(
                            value: 'meshy',
                            label: const Text('Meshy'),
                            icon: ready(hasMeshy)),
                        ButtonSegment(
                            value: 'tripo',
                            label: const Text('Tripo3D'),
                            icon: ready(hasTripo)),
                      ],
                      selected: {settings.threeDProvider},
                      onSelectionChanged: _running
                          ? null
                          : (selection) =>
                              settings.setThreeDProvider(selection.first),
                    );
                  }),
                ),
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
                              : 'Meshy: ca. 20 Credits pro Modell, '
                                  'API-Zugang ab Pro-Plan (meshy.ai).',
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
                          'Tipp: ein einzelnes, freistehendes Objekt '
                          'beschreiben – Szenen mit mehreren Objekten '
                          'eignen sich nicht für 3D.',
                      helperMaxLines: 3,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (!isTripo && !isLocal) ...[
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
                  if (isLocal || isStability)
                    Text(
                      isStability
                          ? 'Die Vorderansicht wird automatisch mit der '
                              'Bild-KI aus dem Generator-Tab '
                              '(${settings.provider.label}) erzeugt; das '
                              'trainierte Stability-Modell rekonstruiert '
                              'daraus das komplette 3D-Modell inklusive '
                              'Rückseite.'
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
                  if (isLocal || isStability || _viewsFromText) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final showAllViews = !isStability;
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
                  Builder(builder: (context) {
                    final showAllViews = !isStability;
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
                    isStability
                        ? 'Stability nutzt genau ein Bild: Rückseite, '
                            'Vertiefungen und Verdecktes rekonstruiert '
                            'das trainierte Modell selbst.'
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
                  if (!isStability)
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
                const SectionLabel('Optionen'),
                if (isLocal) ...[
                  Text(
                    'Echtes räumliches 360°-Modell: Aus den Silhouetten '
                    'von Vorn/Links/Rechts/Hinten wird ein Volumen '
                    'geschnitzt (Visual Hull), die Oberfläche geglättet '
                    'und mit den Bildfarben eingefärbt.',
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
                ] else if (isStability) ...[
                  Text(
                    'Textur (PBR) ist immer im Modell enthalten.',
                    style: theme.textTheme.bodySmall,
                  ),
                  _autoRigSwitch(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    initiallyExpanded: true,
                    title: const Text('Qualitäts-Optionen (Profi)'),
                    subtitle: Text(
                      'Engine, Textur-Auflösung, Topologie',
                      style: theme.textTheme.bodySmall,
                    ),
                    children: [
                      DropdownMenu<String>(
                        key: ValueKey('sengine-$_stabilityEngine'),
                        enabled: !_running,
                        initialSelection: _stabilityEngine,
                        label: const Text('Engine'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: [
                          for (final (value, name)
                              in Stability3dService.engines)
                            DropdownMenuEntry(value: value, label: name),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            setState(() => _stabilityEngine = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
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
                              value: 2048, label: '2048 px (Standard)'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            setState(() => _stabilityTextureRes = value);
                          }
                        },
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
                    ],
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
                          ? 'KI-Generation, Textur-Qualität, Topologie'
                          : 'KI-Generation, Polygone, Symmetrie, PBR …',
                      style: theme.textTheme.bodySmall,
                    ),
                    children: [
                      DropdownMenu<String>(
                        key: ValueKey('gen-${settings.threeDProvider}'
                            '-${isTripo ? _tripoVersion : _meshyAiModel}'),
                        enabled: !_running,
                        initialSelection:
                            isTripo ? _tripoVersion : _meshyAiModel,
                        label: const Text('KI-Generation'),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: isTripo
                            ? const [
                                DropdownMenuEntry(
                                    value: '',
                                    label: 'Standard (v2.5, bewährt)'),
                                DropdownMenuEntry(
                                    value: 'v3.0-20250812',
                                    label: 'Neueste (v3.0, beste Qualität)'),
                              ]
                            : const [
                                DropdownMenuEntry(
                                    value: '',
                                    label: 'Standard (API-Vorgabe)'),
                                DropdownMenuEntry(
                                    value: 'meshy-5', label: 'Meshy 5'),
                                DropdownMenuEntry(
                                    value: 'meshy-6', label: 'Meshy 6'),
                                DropdownMenuEntry(
                                    value: 'latest',
                                    label: 'Neueste (beste Qualität)'),
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
                      const SizedBox(height: 12),
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
                      'Provider (Stability, Meshy, Tripo) am besten.',
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
          'GLB-Dateien zum Behalten exportieren – sie werden nicht '
          'dauerhaft in der App gespeichert. Eigene GLB-, STL- oder '
          'OBJ-Dateien einfach per Drag & Drop hierher ziehen – sie '
          'öffnen sich im Viewer.',
          style: theme.textTheme.bodySmall,
        ),
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
                    FilledButton.tonalIcon(
                      onPressed: () => _exportGlb(result),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('GLB'),
                    ),
                  ],
                ),
              ),
            ),
      ],
      ),
    );
  }
}
