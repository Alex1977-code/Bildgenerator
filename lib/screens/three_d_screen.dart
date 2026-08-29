import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/exporter.dart';
import '../services/generators.dart' show GenerationException;
import '../services/local_3d.dart';
import '../services/meshy_service.dart';
import '../services/settings_service.dart';
import '../services/tripo_service.dart';
import '../widgets/common.dart';
import 'image_detail_screen.dart';

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

  bool _imageMode = false;
  ReferenceImage? _sourceImage;
  bool _texture = true;
  bool _rigging = false;
  String _artStyle = 'realistic';

  // Optionen des lokalen Generators.
  bool _localStandee = false;
  int _localResolution = 96;
  double _localDepth = 0.15;
  bool _localInvert = false;

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
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickSourceImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _sourceImage = ReferenceImage(bytes: bytes, name: file.name);
      });
    } catch (e) {
      _showSnack('Bild konnte nicht geladen werden: $e');
    }
  }

  Future<void> _showMissingKeyDialog(bool isTripo) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isTripo
            ? 'Tripo3D-API-Schlüssel fehlt'
            : 'Meshy-API-Schlüssel fehlt'),
        content: Text(
          isTripo
              ? 'Für Tripo3D wird ein API-Schlüssel benötigt '
                  '(platform.tripo3d.ai – Bezahlung nach Verbrauch, '
                  'Startguthaben für neue Konten). Bitte in den '
                  'Einstellungen hinterlegen.'
              : 'Für Meshy AI wird ein API-Schlüssel benötigt (meshy.ai – '
                  'API-Zugang ab dem Pro-Plan). Bitte in den Einstellungen '
                  'hinterlegen.',
        ),
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
    final apiKey =
        isLocal ? '' : (isTripo ? settings.tripoApiKey : settings.meshyApiKey);
    if (!isLocal && (apiKey == null || apiKey.trim().isEmpty)) {
      await _showMissingKeyDialog(isTripo);
      return;
    }
    final prompt = _promptCtrl.text.trim();
    if (!isLocal && !_imageMode && prompt.isEmpty) {
      setState(() => _error = 'Bitte zuerst eine Beschreibung eingeben.');
      return;
    }
    if ((isLocal || _imageMode) && _sourceImage == null) {
      setState(() => _error = 'Bitte zuerst ein Ausgangsbild wählen.');
      return;
    }

    setState(() {
      _running = true;
      _cancelRequested = false;
      _error = null;
      _stage = 'Task wird angelegt …';
    });
    bool cancelled() => _cancelRequested || !mounted;
    void progress(String stage) {
      if (mounted) setState(() => _stage = stage);
    }

    try {
      if (isLocal) {
        await _runLocal(progress);
      } else if (isTripo) {
        await _runTripo(
            TripoService(apiKey!.trim()), prompt, cancelled, progress);
      } else {
        await _runMeshy(
            MeshyService(apiKey!.trim()), prompt, cancelled, progress);
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

  Future<void> _runLocal(void Function(String) progress) async {
    final source = _sourceImage!;
    progress('Bild wird analysiert …');
    Uint8List glb;
    try {
      glb = await generateLocalGlb(
        source.bytes,
        standee: _localStandee,
        resolution: _localResolution,
        depth: _localDepth,
        invert: _localInvert,
      );
    } on Exception catch (e) {
      throw GenerationException(
          e.toString().replaceFirst('Exception: ', ''));
    }
    _addResult(
      glbBytes: glb,
      label: _localStandee ? 'Standee (lokal)' : 'Relief (lokal)',
      providerLabel: 'Lokal',
      thumbnail: source.bytes,
      rigged: false,
      textured: true,
    );
  }

  Future<void> _runMeshy(
    MeshyService service,
    String prompt,
    bool Function() cancelled,
    void Function(String) progress,
  ) async {
    {
      String taskPath;
      String taskId;
      MeshyTaskStatus status;

      if (_imageMode) {
        final source = _sourceImage!;
        taskPath = 'v1/image-to-3d';
        taskId = await service.createImageTo3d(
          source.bytes,
          source.mimeType,
          texture: _texture,
        );
        status = await service.waitForTask(
          taskPath,
          taskId,
          stageLabel: '3D-Modell aus Bild',
          onProgress: progress,
          isCancelled: cancelled,
        );
      } else {
        // Für Rigging braucht das Modell eine T-Pose – wird automatisch
        // an den Prompt angehängt.
        final effectivePrompt =
            _rigging ? '$prompt, $_tPoseSuffix' : prompt;
        taskPath = 'v2/text-to-3d';
        taskId = await service.createTextPreview(effectivePrompt, _artStyle);
        status = await service.waitForTask(
          taskPath,
          taskId,
          stageLabel: 'Rohmodell (Geometrie)',
          onProgress: progress,
          isCancelled: cancelled,
        );
        if (_texture) {
          final refineId = await service.createTextRefine(taskId);
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
        label: _imageMode ? 'Aus Bild' : prompt,
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
    void Function(String) progress,
  ) async {
    String modelTaskId;
    if (_imageMode) {
      final source = _sourceImage!;
      progress('Bild wird hochgeladen …');
      final token = await service.uploadImage(source.bytes, source.mimeType);
      modelTaskId = await service.createImageTask(
        token,
        source.mimeType,
        texture: _texture,
      );
    } else {
      // Für Rigging braucht das Modell eine T-Pose – wird automatisch
      // an den Prompt angehängt.
      final effectivePrompt = _rigging ? '$prompt, $_tPoseSuffix' : prompt;
      modelTaskId =
          await service.createTextTask(effectivePrompt, texture: _texture);
    }
    final modelData = await service.waitForTask(
      modelTaskId,
      stageLabel: _imageMode ? '3D-Modell aus Bild' : '3D-Modell',
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
      label: _imageMode ? 'Aus Bild' : prompt,
      providerLabel: 'Tripo3D',
      thumbnail: thumbnail,
      rigged: rigged,
      textured: _texture,
    );
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
    return ListView(
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
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'meshy', label: Text('Meshy')),
                      ButtonSegment(value: 'tripo', label: Text('Tripo3D')),
                      ButtonSegment(value: 'local', label: Text('Lokal')),
                    ],
                    selected: {settings.threeDProvider},
                    onSelectionChanged: _running
                        ? null
                        : (selection) =>
                            settings.setThreeDProvider(selection.first),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isLocal
                      ? 'Eigener Generator: rechnet komplett lokal in der '
                          'App – kostenlos, kein API-Schlüssel nötig. '
                          'Baut Relief- und Aufsteller-Modelle aus Bildern.'
                      : isTripo
                          ? 'Tripo3D: Bezahlung nach Verbrauch, Startguthaben '
                              'für neue Konten (platform.tripo3d.ai).'
                          : 'Meshy: ca. 20 Credits pro Modell, API-Zugang ab '
                              'Pro-Plan (meshy.ai).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (!isLocal) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Aus Text')),
                      ButtonSegment(value: true, label: Text('Aus Bild')),
                    ],
                    selected: {_imageMode},
                    onSelectionChanged: (selection) =>
                        setState(() => _imageMode = selection.first),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!isLocal && !_imageMode) ...[
                  TextField(
                    controller: _promptCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung des 3D-Modells',
                      hintText:
                          'z. B. „Ein mittelalterlicher Ritter in voller '
                          'Rüstung mit Schwert“',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (!isTripo) ...[
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
                ] else ...[
                  Row(
                    children: [
                      if (_sourceImage != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _sourceImage!.bytes,
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Icon(Icons.image_outlined,
                            size: 48,
                            color: theme.colorScheme.outlineVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: _running ? null : _pickSourceImage,
                              child: Text(_sourceImage == null
                                  ? 'Bild wählen'
                                  : 'Bild ändern'),
                            ),
                            if (_sourceImage != null)
                              TextButton(
                                onPressed: _running
                                    ? null
                                    : () => setState(
                                        () => _sourceImage = null),
                                child: const Text('Entfernen'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tipp: Ein freigestelltes Objekt bzw. eine Figur in '
                    'T-Pose vor neutralem Hintergrund liefert die besten '
                    'Ergebnisse. Solche Vorlagen lassen sich im '
                    'Generator-Tab erzeugen (transparenter Hintergrund).',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SectionLabel('Optionen'),
                if (isLocal) ...[
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false, label: Text('Relief (Helligkeit)')),
                      ButtonSegment(
                          value: true, label: Text('Standee (Silhouette)')),
                    ],
                    selected: {_localStandee},
                    onSelectionChanged: _running
                        ? null
                        : (selection) =>
                            setState(() => _localStandee = selection.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _localStandee
                        ? 'Extrudiert die Silhouette als Aufsteller – das '
                            'Bild braucht einen transparenten Hintergrund '
                            '(im Generator-Tab erzeugen).'
                        : 'Helligkeit wird zu Höhe – ideal für '
                            'Landschaften, Prägungen und Logos. Kein '
                            'Rigging möglich.',
                    style: theme.textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 90, child: Text('Tiefe')),
                      Expanded(
                        child: Slider(
                          value: _localDepth,
                          min: 0.05,
                          max: 0.5,
                          divisions: 18,
                          label:
                              '${(_localDepth * 100).round()} % der Breite',
                          onChanged: _running
                              ? null
                              : (v) => setState(() => _localDepth = v),
                        ),
                      ),
                      Text('${(_localDepth * 100).round()} %'),
                    ],
                  ),
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
                  if (!_localStandee)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Höhen umkehren'),
                      subtitle:
                          const Text('Dunkle Stellen werden erhaben'),
                      value: _localInvert,
                      onChanged: _running
                          ? null
                          : (v) => setState(() => _localInvert = v),
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
                ],
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
          'dauerhaft in der App gespeichert.',
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
                trailing: FilledButton.tonalIcon(
                  onPressed: () => _exportGlb(result),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('GLB'),
                ),
              ),
            ),
      ],
    );
  }
}
