import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/batch_prompt.dart';
import '../services/exporter.dart';
import '../services/generators.dart';
import '../services/history_service.dart';
import '../services/model_catalog.dart';
import '../services/cost_estimator.dart';
import '../services/prompt_relay.dart';
import '../services/provenance.dart';
import '../services/settings_service.dart';
import '../services/watermark.dart';
import '../widgets/common.dart';
import '../widgets/cost_quality_panel.dart';
import 'image_detail_screen.dart';

/// Hauptbildschirm: Prompt, Referenzbilder, Optionen und Ergebnisse.
class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({
    super.key,
    required this.onOpenSettings,
    this.isActive = true,
  });

  final VoidCallback onOpenSettings;

  /// Ob dieser Tab gerade sichtbar ist. Im IndexedStack bleiben alle
  /// Tabs aufgebaut – ohne diese Sperre fingen ihre Drop-Ziele auch
  /// Dateien ab, die auf einen anderen Tab gezogen werden.
  final bool isActive;

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  static const _maxReferences = 16;

  final _promptCtrl = TextEditingController();
  final _negativeCtrl = TextEditingController();
  final _seedCtrl = TextEditingController(text: '0');
  final _picker = ImagePicker();
  final List<ReferenceImage> _references = [];

  List<GeneratedImage> _results = [];
  GenerationRequest? _lastRequest;
  String? _usageInfo;
  bool _generating = false;
  bool _dragOverReferences = false;
  String? _error;
  PromptRelay? _relay;

  /// Massenprompt: ein Text mit den Beschreibungen vieler Bilder, die
  /// nacheinander erzeugt und unter ihrem Namen abgelegt werden.
  bool _batchMode = false;
  final _batchCtrl = TextEditingController();

  /// Ergebnis der letzten Prüfung – null, solange der Text seit der
  /// letzten Änderung nicht geprüft wurde.
  BatchPlan? _batchPlan;

  bool _batchRunning = false;
  bool _batchCancel = false;
  int _batchDone = 0;
  int _batchTotal = 0;
  String _batchCurrent = '';
  DateTime? _batchStart;

  /// Dauer der bereits fertigen Bilder – daraus kommt der Schnitt und
  /// die geschätzte Restzeit.
  final List<Duration> _batchTimes = [];
  final List<String> _batchFailures = [];

  /// Lässt die Anzeige der vergangenen Zeit sekündlich weiterlaufen.
  Timer? _batchTicker;

  @override
  void initState() {
    super.initState();
    // Jede Änderung am Massenprompt macht das Prüfergebnis ungültig –
    // der grüne Haken soll immer zum sichtbaren Text gehören.
    _batchCtrl.addListener(() {
      if (_batchPlan != null && !_batchRunning) {
        setState(() => _batchPlan = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final relay = context.read<PromptRelay>();
    if (!identical(_relay, relay)) {
      _relay?.removeListener(_onPromptRelay);
      _relay = relay..addListener(_onPromptRelay);
    }
  }

  void _onPromptRelay() {
    final pending = _relay?.takePending();
    if (pending != null && mounted) {
      setState(() => _promptCtrl.text = pending);
    }
  }

  @override
  void dispose() {
    _relay?.removeListener(_onPromptRelay);
    _batchTicker?.cancel();
    _promptCtrl.dispose();
    _negativeCtrl.dispose();
    _seedCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  bool _refreshingModels = false;

  /// Holt die aktuell verfügbaren Modelle bei allen Anbietern, für die
  /// ein Schlüssel hinterlegt ist – die Liste enthält ja alle.
  Future<void> _refreshModels() async {
    final settings = context.read<SettingsService>();
    setState(() => _refreshingModels = true);
    var loaded = 0;
    final skipped = <String>[];
    final failed = <String>[];
    try {
      for (final provider in GenProvider.values) {
        final apiKey = settings.apiKeyFor(provider)?.trim() ?? '';
        // Stability hat feste Engines und braucht dafür keinen
        // Schlüssel; die anderen schon.
        if (provider != GenProvider.stability && apiKey.isEmpty) {
          skipped.add(provider.shortLabel);
          continue;
        }
        try {
          final models = await fetchAvailableModels(provider, apiKey);
          await settings.setFetchedModels(provider, models);
          loaded += models.length;
        } on GenerationException {
          failed.add(provider.shortLabel);
        }
      }
      if (mounted) {
        final extra = [
          if (skipped.isNotEmpty) 'ohne Schlüssel: ${skipped.join(', ')}',
          if (failed.isNotEmpty) 'Fehler bei: ${failed.join(', ')}',
        ];
        _showSnack('$loaded Modelle geladen'
            '${extra.isEmpty ? '.' : ' (${extra.join('; ')}).'}');
      }
    } finally {
      if (mounted) setState(() => _refreshingModels = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _appendTemplate(String suffix) {
    final current = _promptCtrl.text.trim();
    setState(() {
      _promptCtrl.text = current.isEmpty ? suffix : '$current, $suffix';
    });
  }

  /// Per Drag & Drop abgelegte Dateien als Referenzbilder übernehmen.
  Future<void> _addDroppedReferences(List<XFile> files) async {
    var skipped = 0;
    for (final file in files) {
      if (_references.length >= _maxReferences) {
        _showSnack('Maximal $_maxReferences Referenzbilder möglich.');
        break;
      }
      final bytes = await file.readAsBytes();
      if (!looksLikeSupportedImage(bytes)) {
        skipped++;
        continue;
      }
      _references.add(ReferenceImage(bytes: bytes, name: file.name));
    }
    if (!mounted) return;
    setState(() => _dragOverReferences = false);
    if (skipped > 0) {
      _showSnack('$skipped Datei(en) übersprungen – unterstützt werden '
          'PNG, JPEG und WebP.');
    }
  }

  Future<void> _pickReferences() async {
    try {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty) return;
      for (final file in files) {
        if (_references.length >= _maxReferences) {
          _showSnack('Maximal $_maxReferences Referenzbilder möglich.');
          break;
        }
        final bytes = await file.readAsBytes();
        _references.add(ReferenceImage(bytes: bytes, name: file.name));
      }
      if (mounted) setState(() {});
    } catch (e) {
      _showSnack('Bilder konnten nicht geladen werden: $e');
    }
  }

  Future<void> _showMissingKeyDialog(GenProvider provider) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(provider.isLocal
            ? 'Bild-Server fehlt'
            : 'API-Schlüssel fehlt'),
        content: Text(
          provider.isLocal
              ? 'Für die eigene GPU wird der lokale Bild-Server '
                  'gebraucht. In den Einstellungen unter „Eigener '
                  'Bild-Server" richtet ihn der Assistent ein und '
                  'startet ihn auf Knopfdruck.'
              : 'Für „${provider.label}“ ist noch kein API-Schlüssel '
                  'hinterlegt. Bitte in den Einstellungen einen '
                  'Schlüssel eintragen.',
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

  /// Baut die Anfrage aus den aktuellen Einstellungen. Prompt,
  /// Negativ-Prompt, Referenzbilder und Anzahl kommen von außen –
  /// beim Massenprompt sind sie für jedes Bild andere.
  GenerationRequest _buildRequest(
    SettingsService settings, {
    required String prompt,
    required String negativePrompt,
    required List<ReferenceImage> references,
    required int count,
  }) {
    final isOpenAi = settings.provider == GenProvider.openai;
    return GenerationRequest(
      provider: settings.provider,
      prompt: prompt,
      negativePrompt: negativePrompt,
      references:
          settings.provider.supportsReferences ? references : const [],
      openAiSize: settings.openAiSize,
      stabilityAspect: settings.stabilityAspect,
      quality: settings.quality,
      transparent: isOpenAi && settings.transparent,
      outputFormat: settings.outputFormat,
      compression: settings.compression,
      count: count,
      seed: int.tryParse(_seedCtrl.text.trim()) ?? 0,
      stylePreset: settings.stylePreset,
      model: settings.modelFor(settings.provider),
      geminiAspect: settings.geminiAspect,
      geminiImageSize: settings.geminiImageSize,
    );
  }

  /// Legt – falls eingeschaltet – das Wasserzeichen auf die Bilder.
  Future<List<GeneratedImage>> _watermarked(
      SettingsService settings, List<GeneratedImage> images) async {
    final logo = settings.watermarkLogo;
    if (!settings.watermarkEnabled || logo == null) return images;
    return [
      for (final image in images)
        GeneratedImage(
          bytes: await applyWatermark(
            image.bytes,
            logo,
            position: settings.watermarkPosition,
            sizePercent: settings.watermarkSizePercent,
            opacityPercent: settings.watermarkOpacity,
          ),
          format: 'png',
        ),
    ];
  }

  Future<void> _generate() async {
    final settings = context.read<SettingsService>();
    final history = context.read<HistoryService>();

    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Bitte zuerst eine Bildbeschreibung eingeben.');
      return;
    }
    final apiKey = settings.apiKeyFor(settings.provider);
    if (apiKey == null || apiKey.trim().isEmpty) {
      await _showMissingKeyDialog(settings.provider);
      return;
    }

    final request = _buildRequest(
      settings,
      prompt: prompt,
      negativePrompt: _negativeCtrl.text,
      references: List.of(_references),
      count: settings.count,
    );

    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final generator = ImageGenerator.forProvider(settings.provider);
      final result = await generator.generate(request, apiKey.trim());
      final watermarkOn = settings.watermarkEnabled &&
          settings.watermarkLogo != null;
      final images = await _watermarked(settings, result.images);
      final usageParts = <String>[
        if (result.totalTokens != null)
          'Verbrauch: ${result.totalTokens} Tokens',
        if (result.creditsRemaining != null)
          'Restguthaben: ${result.creditsRemaining!.toStringAsFixed(1)} '
              'Credits',
      ];
      await history.addResults(request, images, extraParams: {
        if (result.totalTokens != null) 'Tokens': '${result.totalTokens}',
        if (watermarkOn) 'Wasserzeichen': 'ja',
      });
      if (!mounted) return;
      setState(() {
        _results = images;
        _lastRequest = request;
        _usageInfo = usageParts.isEmpty ? null : usageParts.join(' · ');
      });
    } on GenerationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Unerwarteter Fehler: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // --------------------------------------------------------------
  // Massenprompt
  // --------------------------------------------------------------

  /// Prüft den Massenprompt und zeigt das Ergebnis an (grüner Haken
  /// oder die Liste dessen, was noch nicht stimmt).
  void _checkBatch() {
    final settings = context.read<SettingsService>();
    final plan = parseBatchPrompt(
      _batchCtrl.text,
      availableReferences: [for (final ref in _references) ref.name],
      supportsReferences: settings.provider.supportsReferences,
    );
    setState(() {
      _batchPlan = plan;
      _error = null;
    });
  }

  /// Vorlage für die Prompt-KI – mit den Namen der aktuell geladenen
  /// Referenzbilder, damit die KI sie auch nennen kann.
  String _batchBriefing() {
    final names = [for (final ref in _references) ref.name].join(', ');
    return batchPromptBriefing.replaceFirst(
        '[HIER DATEINAMEN ODER „keine"]', names.isEmpty ? 'keine' : names);
  }

  Future<void> _copyBatchBriefing() async {
    await Clipboard.setData(ClipboardData(text: _batchBriefing()));
    if (mounted) {
      _showSnack('Vorlage kopiert – in die Prompt-KI einfügen, Vorgaben '
          'ausfüllen und das Ergebnis hier hereinkopieren.');
    }
  }

  /// Erzeugt alle Bilder des Massenprompts nacheinander.
  Future<void> _generateBatch() async {
    final settings = context.read<SettingsService>();
    final history = context.read<HistoryService>();

    final plan = parseBatchPrompt(
      _batchCtrl.text,
      availableReferences: [for (final ref in _references) ref.name],
      supportsReferences: settings.provider.supportsReferences,
    );
    if (!plan.isValid) {
      setState(() {
        _batchPlan = plan;
        _error = 'Der Massenprompt hat noch offene Punkte – bitte oben '
            'nachsehen.';
      });
      return;
    }
    final apiKey = settings.apiKeyFor(settings.provider);
    if (apiKey == null || apiKey.trim().isEmpty) {
      await _showMissingKeyDialog(settings.provider);
      return;
    }

    setState(() {
      _batchPlan = plan;
      _batchRunning = true;
      _generating = true;
      _batchCancel = false;
      _batchDone = 0;
      _batchTotal = plan.items.length;
      _batchCurrent = plan.items.first.name;
      _batchStart = DateTime.now();
      _batchTimes.clear();
      _batchFailures.clear();
      _results = [];
      _usageInfo = null;
      _error = null;
    });
    // Die vergangene Zeit soll auch zwischen zwei Bildern weiterlaufen.
    _batchTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _batchRunning) setState(() {});
    });

    final produced = <GeneratedImage>[];
    final generator = ImageGenerator.forProvider(settings.provider);
    try {
      for (final item in plan.items) {
        if (_batchCancel) break;
        if (mounted) setState(() => _batchCurrent = item.name);
        final started = DateTime.now();
        try {
          final request = _buildRequest(
            settings,
            prompt: item.prompt,
            negativePrompt: item.negativePrompt.isNotEmpty
                ? item.negativePrompt
                : _negativeCtrl.text,
            references: [
              for (final ref in _references)
                if (item.references.contains(ref.name)) ref,
            ],
            // Im Massenlauf gehört zu jedem Block genau ein Bild –
            // sonst passen Name und Ergebnis nicht mehr zusammen.
            count: 1,
          );
          final result = await generator.generate(request, apiKey.trim());
          final watermarkOn =
              settings.watermarkEnabled && settings.watermarkLogo != null;
          final images = await _watermarked(settings, result.images);
          await history.addResults(request, images,
              name: item.name,
              extraParams: {
                'Massenprompt': 'ja',
                if (result.totalTokens != null)
                  'Tokens': '${result.totalTokens}',
                if (watermarkOn) 'Wasserzeichen': 'ja',
              });
          produced.addAll(images);
          _lastRequest = request;
        } on GenerationException catch (e) {
          _batchFailures.add('${item.name}: ${e.message}');
        } catch (e) {
          _batchFailures.add('${item.name}: $e');
        }
        if (!mounted) return;
        setState(() {
          _batchTimes.add(DateTime.now().difference(started));
          _batchDone++;
          _results = List.of(produced);
        });
      }
    } finally {
      _batchTicker?.cancel();
      _batchTicker = null;
      if (mounted) {
        setState(() {
          _batchRunning = false;
          _generating = false;
          _batchCurrent = '';
        });
      }
    }
  }

  /// Zeitangabe in lesbarer Form („45 s", „3:20 min", „1 h 05 min").
  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '$seconds s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) {
      return '$minutes:${(seconds % 60).toString().padLeft(2, '0')} min';
    }
    return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} '
        'min';
  }

  /// Durchschnittsdauer der bisher fertigen Bilder.
  Duration? get _batchAverage {
    if (_batchTimes.isEmpty) return null;
    final total = _batchTimes.fold<int>(
        0, (sum, duration) => sum + duration.inMilliseconds);
    return Duration(milliseconds: total ~/ _batchTimes.length);
  }

  Future<void> _exportResult(GeneratedImage image, int index) async {
    final fileName =
        'bildgenerator_${DateTime.now().millisecondsSinceEpoch}_$index'
        '.${image.fileExtension}';
    try {
      final message =
          await exportImageBytes(image.bytes, fileName, image.mimeType);
      if (message != null && mounted) _showSnack(message);
    } catch (e) {
      if (mounted) _showSnack('Export fehlgeschlagen: $e');
    }
  }

  /// Erstellungsnachweis-PDF fürs Ergebnisbild (Zeitpunkt, Eingabe,
  /// Dienst/Modell und SHA-256-Prüfsumme) herunterladen/drucken.
  Future<void> _exportProvenance(GeneratedImage image) async {
    final settings = context.read<SettingsService>();
    final name = await askCreatorName(context, settings);
    if (name == null || !mounted) return;
    final request = _lastRequest;
    final details = request?.describeParams() ?? <String, String>{};
    details.remove('Provider');
    details.remove('Modell');
    try {
      final pdf = await buildProvenancePdf(
        info: ProvenanceInfo(
          kind: 'Bild',
          description: request?.prompt ?? _promptCtrl.text.trim(),
          providerLabel: request?.provider.label ?? settings.provider.label,
          model: request?.model,
          details: details,
          previewBytes: image.bytes,
        ),
        fileType: image.fileExtension.toUpperCase(),
        fileBytes: image.bytes,
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

  void _useAsReference(GeneratedImage image) {
    if (_references.length >= _maxReferences) {
      _showSnack('Maximal $_maxReferences Referenzbilder möglich.');
      return;
    }
    setState(() {
      _references.add(ReferenceImage(
        bytes: image.bytes,
        name: 'ergebnis.${image.fileExtension}',
      ));
    });
    _showSnack('Bild als Referenz übernommen.');
  }

  void _openDetail(GeneratedImage image, int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ImageDetailScreen(
        bytes: image.bytes,
        fileName:
            'bildgenerator_${DateTime.now().millisecondsSinceEpoch}_$index'
            '.${image.fileExtension}',
        mimeType: image.mimeType,
        prompt: _lastRequest?.prompt,
        metadata: _lastRequest?.describeParams() ?? const {},
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 460,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _buildControls(settings),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._buildResultsHeader(),
                      Expanded(child: _buildResultsGrid(shrinkWrap: false)),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ..._buildControls(settings),
            const SizedBox(height: 8),
            ..._buildResultsHeader(),
            _buildResultsGrid(shrinkWrap: true),
          ],
        );
      },
    );
  }

  List<Widget> _buildControls(SettingsService settings) {
    final plan = _batchPlan;
    final batchReady = plan != null && plan.isValid;
    return [
      // Einzelbild oder Massenprompt – beides nutzt dieselben
      // Einstellungen darunter (Modell, Format, Referenzbilder).
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
              value: false,
              icon: Icon(Icons.image_outlined, size: 18),
              label: Text('Einzelbild')),
          ButtonSegment(
              value: true,
              icon: Icon(Icons.dynamic_feed, size: 18),
              label: Text('Massenprompt')),
        ],
        selected: {_batchMode},
        onSelectionChanged: _generating
            ? null
            : (selection) => setState(() => _batchMode = selection.first),
      ),
      const SizedBox(height: 12),
      if (_batchMode) _buildBatchCard() else _buildPromptCard(),
      const SizedBox(height: 12),
      _buildReferenceCard(settings.provider.supportsReferences),
      const SizedBox(height: 12),
      _buildOptionsCard(settings),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _generating
            ? null
            : _batchMode
                ? (batchReady ? _generateBatch : null)
                : _generate,
        icon: _generating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_batchMode ? Icons.playlist_play : Icons.auto_awesome),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            _generating
                ? _batchMode
                    ? 'Massenlauf läuft …'
                    : 'Wird generiert …'
                : _batchMode
                    ? batchReady
                        ? '${plan.items.length} Bilder generieren'
                        : 'Erst prüfen, dann generieren'
                    : settings.count > 1
                        ? '${settings.count} Bilder generieren'
                        : 'Bild generieren',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Anbieter und Modell stehen oben in der Auswahlliste; hier bleibt
      // nur der kurze Weg zum Schlüssel, falls einer fehlt.
      Row(
        children: [
          Expanded(
            child: Text(
              '${settings.provider.label} · '
              '${settings.modelFor(settings.provider)}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: widget.onOpenSettings,
            child: const Text('API-Schlüssel'),
          ),
        ],
      ),
      if (_error != null)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// Eingabefeld und Prüfung für den Massenprompt.
  Widget _buildBatchCard() {
    final theme = Theme.of(context);
    final plan = _batchPlan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dynamic_feed, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Massenprompt',
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ein Text mit den Beschreibungen vieler Bilder. Jeder '
              'Block beginnt mit „NAME:" und „PROMPT:", getrennt durch '
              'eine Zeile aus drei Bindestrichen. Die Bilder entstehen '
              'nacheinander und liegen anschließend unter ihrem Namen '
              'in der Galerie.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _batchCtrl,
              minLines: 8,
              maxLines: 18,
              enabled: !_generating,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Massenprompt',
                hintText: 'NAME: burg-01\n'
                    'PROMPT: A medieval castle at night …\n'
                    '---\n'
                    'NAME: burg-02\n'
                    'PROMPT: The same castle at noon …',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _generating ? null : _checkBatch,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Prüfen'),
                ),
                OutlinedButton.icon(
                  onPressed: _generating ? null : _copyBatchBriefing,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Vorlage für Prompt-KI kopieren'),
                ),
                TextButton.icon(
                  onPressed: _generating
                      ? null
                      : () {
                          _batchCtrl.text = batchPromptExample;
                          _checkBatch();
                        },
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Beispiel einfügen'),
                ),
              ],
            ),
            if (plan != null) ...[
              const SizedBox(height: 12),
              _buildBatchResult(plan),
            ],
          ],
        ),
      ),
    );
  }

  /// Ergebnis der Prüfung: grüner Haken samt Zahlen oder die Liste
  /// dessen, was noch fehlt.
  Widget _buildBatchResult(BatchPlan plan) {
    final theme = Theme.of(context);
    final good = plan.isValid;
    final color = good
        ? Colors.green.shade700
        : theme.colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: good
            ? Colors.green.withValues(alpha: 0.08)
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(good ? Icons.check_circle : Icons.error_outline,
                  color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  good
                      ? '${plan.items.length} Bilder erkannt'
                          '${plan.withReferences > 0 ? ', davon '
                              '${plan.withReferences} mit Referenzbild' : ''}'
                          ' – der Massenprompt ist in Ordnung.'
                      : 'Der Massenprompt ist noch nicht startklar:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: good ? color : theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          for (final issue in plan.issues)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 30),
              child: Text('• $issue',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer)),
            ),
          for (final warning in plan.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 30),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('$warning',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline)),
                  ),
                ],
              ),
            ),
          if (good && plan.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 30),
              child: Text(
                'Namen: ${plan.items.take(6).map((i) => i.name).join(', ')}'
                '${plan.items.length > 6 ? ' … (+'
                    '${plan.items.length - 6})' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }

  /// Statusfenster des Massenlaufs: welches Bild gerade entsteht, wie
  /// lange es schon läuft und wie lange es voraussichtlich noch dauert.
  Widget _buildBatchStatus() {
    final theme = Theme.of(context);
    final done = _batchDone;
    final total = _batchTotal;
    final average = _batchAverage;
    final elapsed = _batchStart == null
        ? Duration.zero
        : DateTime.now().difference(_batchStart!);
    final remaining = average == null
        ? null
        : average * (total - done);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_batchRunning ? Icons.playlist_play : Icons.done_all,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _batchRunning
                        ? 'Bild ${done + 1} von $total wird erstellt'
                        : _batchCancel
                            ? 'Abgebrochen nach $done von $total Bildern'
                            : '$done von $total Bildern fertig',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (_batchRunning)
                  TextButton.icon(
                    onPressed: _batchCancel
                        ? null
                        : () => setState(() => _batchCancel = true),
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: Text(_batchCancel ? 'Bricht ab …' : 'Abbrechen'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total == 0 ? null : done / total,
            ),
            const SizedBox(height: 8),
            if (_batchRunning && _batchCurrent.isNotEmpty)
              Text('Gerade in Arbeit: $_batchCurrent',
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              [
                'Vergangen: ${_formatDuration(elapsed)}',
                if (average != null)
                  'Schnitt: ${_formatDuration(average)} je Bild',
                if (_batchRunning && remaining != null && remaining
                    > Duration.zero)
                  'Rest: ca. ${_formatDuration(remaining)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (average == null && _batchRunning)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Die Dauer je Bild steht nach dem ersten fertigen Bild '
                  'fest – daraus wird dann die Restzeit geschätzt.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            if (_batchFailures.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Nicht geklappt (${_batchFailures.length}):',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.error)),
              for (final failure in _batchFailures.take(8))
                Text('• $failure',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              if (_batchFailures.length > 8)
                Text('… und ${_batchFailures.length - 8} weitere',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
            ],
            if (!_batchRunning && done > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Alle fertigen Bilder liegen unter ihrem Namen in der '
                  'Galerie.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _promptCtrl,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'Bildbeschreibung (Prompt)',
                hintText:
                    'Beschreibe das gewünschte Bild so genau wie möglich …',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text('Stil-Vorlagen',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final template in promptTemplates)
                  ActionChip(
                    label: Text(template.$2),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _appendTemplate(template.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceCard(bool supportsReferences) {
    return DropTarget(
      enable: supportsReferences &&
          !_generating &&
          widget.isActive &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      onDragEntered: (_) => setState(() => _dragOverReferences = true),
      onDragExited: (_) => setState(() => _dragOverReferences = false),
      onDragDone: (detail) => _addDroppedReferences(detail.files),
      child: Card(
      shape: _dragOverReferences
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_library_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Referenzbilder (${_references.length}/$_maxReferences)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (supportsReferences)
                  TextButton.icon(
                    onPressed: _generating ? null : _pickReferences,
                    icon: const Icon(Icons.add),
                    label: const Text('Hinzufügen'),
                  ),
              ],
            ),
            if (!supportsReferences)
              Text(
                'Referenzbilder unterstützen OpenAI und Google Gemini – '
                'oben bei „KI-Modell" ein Modell dieser Anbieter wählen, '
                'um sie zu nutzen.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (_references.isEmpty)
              Text(
                'Optional: Bilder als Vorlage hinzufügen (z. B. Produkt, '
                'Person, Stil). Das Ergebnis orientiert sich an ihnen. '
                'Am PC auch einfach per Drag & Drop hierher ziehen.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _references.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final ref = _references[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            ref.bytes,
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () =>
                                setState(() => _references.removeAt(index)),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.close,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildOptionsCard(SettingsService settings) {
    final provider = settings.provider;
    final isOpenAi = provider == GenProvider.openai;
    final isStability = provider == GenProvider.stability;
    final isGemini = provider == GenProvider.gemini;
    // Der eigene Bild-Server nutzt dieselben Seitenverhältnisse wie
    // Stability und rechnet sie in Pixelmaße um.
    final sizeOptions = switch (provider) {
      GenProvider.openai => openAiSizeOptions,
      GenProvider.stability ||
      GenProvider.selfhost =>
        stabilityAspectOptions,
      GenProvider.gemini => geminiAspectOptions,
    };
    final sizeValue = switch (provider) {
      GenProvider.openai => settings.openAiSize,
      GenProvider.stability ||
      GenProvider.selfhost =>
        settings.stabilityAspect,
      GenProvider.gemini => settings.geminiAspect,
    };
    // Alle Modelle aller Anbieter in einer Liste: Der Anbieter wird
    // über das Modell gewählt, nicht mehr getrennt in den
    // Einstellungen. Abgerufene Modelle sind mit dabei, damit neue
    // Modelle ohne App-Update wählbar bleiben.
    final allModels = allImageModels(settings.fetchedModelsFor);
    final currentModel = settings.modelFor(provider);
    final currentKey = '${provider.name}/$currentModel';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('KI-Modell'),
            // Die Liste enthält die Modelle aller Anbieter – der
            // Anbieter ergibt sich aus dem gewählten Modell.
            // Modellwahl mit seitlicher Qualitäts-/Kostenanzeige: auf
            // breiten Layouts rechts daneben, auf schmalen darunter.
            LayoutBuilder(builder: (context, constraints) {
              final panel =
                  CostQualityPanel(estimate: estimateImageRun(settings));
              final modelControls = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: DropdownMenu<String>(
                          key: ValueKey('model-$currentKey'
                              '-${allModels.length}'),
                          initialSelection: currentKey,
                          label: const Text('KI-Modell'),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: [
                            for (final choice in allModels)
                              DropdownMenuEntry(
                                value: choice.key,
                                label: choice.fullLabel,
                                // Fehlt der Schlüssel, ist das Modell
                                // trotzdem wählbar – die App fragt beim
                                // Generieren danach.
                                trailingIcon:
                                    settings.hasApiKeyFor(choice.provider)
                                        ? null
                                        : const Icon(Icons.key_off,
                                            size: 16),
                              ),
                            if (!allModels
                                .any((choice) => choice.key == currentKey))
                              DropdownMenuEntry(
                                value: currentKey,
                                label: '${provider.shortLabel} · '
                                    '$currentModel (eigene ID)',
                              ),
                          ],
                          onSelected: (value) {
                            if (value == null) return;
                            final parsed =
                                ImageModelChoice.parseKey(value);
                            if (parsed == null) return;
                            // Ein Klick setzt Anbieter und Modell.
                            settings.setProvider(parsed.$1);
                            settings.setModelFor(parsed.$1, parsed.$2);
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Aktuelle Modelle bei allen Anbietern '
                            'laden',
                        icon: _refreshingModels
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        onPressed:
                            _refreshingModels ? null : _refreshModels,
                      ),
                    ],
                  ),
                  const SectionLabel('Format & Größe'),
                  DropdownMenu<String>(
                    key: ValueKey(
                        'size-${provider.name}-${settings.stabilityModel}'
                        '-${settings.geminiModel}-${settings.geminiImageSize}'),
                    initialSelection: sizeValue,
                    label:
                        Text(isOpenAi ? 'Bildgröße' : 'Seitenverhältnis'),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      for (final option in sizeOptions)
                        DropdownMenuEntry(
                          value: option.$1,
                          label: _sizeOptionLabel(settings, option),
                        ),
                    ],
                    onSelected: (value) {
                      if (value == null) return;
                      switch (provider) {
                        case GenProvider.openai:
                          settings.setOpenAiSize(value);
                        case GenProvider.stability:
                        case GenProvider.selfhost:
                          settings.setStabilityAspect(value);
                        case GenProvider.gemini:
                          settings.setGeminiAspect(value);
                      }
                    },
                  ),
                  if (isGemini &&
                      settings.geminiModel.contains('pro')) ...[
                    const SizedBox(height: 12),
                    DropdownMenu<String>(
                      key: ValueKey('imgsize-${settings.geminiAspect}'),
                      initialSelection: settings.geminiImageSize,
                      label: const Text('Auflösung'),
                      expandedInsets: EdgeInsets.zero,
                      dropdownMenuEntries: [
                        for (final option in geminiImageSizeOptions)
                          DropdownMenuEntry(
                            value: option.$1,
                            label: '${option.$2} · '
                                '${geminiAspectPixelLabel(settings.geminiAspect, option.$1)}',
                          ),
                      ],
                      onSelected: (value) {
                        if (value != null) {
                          settings.setGeminiImageSize(value);
                        }
                      },
                    ),
                  ],
                  if (!isGemini) ...[
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<String>(
                        segments: [
                          for (final option in formatOptions)
                            ButtonSegment(
                                value: option.$1, label: Text(option.$2)),
                        ],
                        selected: {settings.outputFormat},
                        onSelectionChanged: (selection) =>
                            settings.setOutputFormat(selection.first),
                      ),
                    ),
                  ],
                ],
              );
              if (constraints.maxWidth >= 420) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: modelControls),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: panel,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  modelControls,
                  const SizedBox(height: 12),
                  panel,
                ],
              );
            }),
            if (isOpenAi) ...[
              const SectionLabel('Qualität'),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  segments: [
                    for (final option in qualityOptions)
                      ButtonSegment(value: option.$1, label: Text(option.$2)),
                  ],
                  selected: {settings.quality},
                  onSelectionChanged: (selection) =>
                      settings.setQuality(selection.first),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Transparenter Hintergrund'),
                subtitle: const Text(
                    'Ideal für Logos und Icons – benötigt PNG oder WebP'),
                value: settings.transparent,
                onChanged: settings.setTransparent,
              ),
              if (settings.outputFormat != 'png')
                Row(
                  children: [
                    const Text('Kompression'),
                    Expanded(
                      child: Slider(
                        value: settings.compression.toDouble(),
                        min: 10,
                        max: 100,
                        divisions: 18,
                        label: '${settings.compression} %',
                        onChanged: (value) =>
                            settings.setCompression(value.round()),
                      ),
                    ),
                    Text('${settings.compression} %'),
                  ],
                ),
            ],
            const SectionLabel('Anzahl Bilder'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {settings.count},
              onSelectionChanged: _batchMode
                  ? null
                  : (selection) => settings.setCount(selection.first),
            ),
            const SizedBox(height: 4),
            Text(
              _batchMode
                  ? 'Im Massenprompt entsteht zu jedem Block genau ein '
                      'Bild – sonst passten Name und Ergebnis nicht mehr '
                      'zusammen.'
                  : 'Es sind immer verschiedene Varianten desselben '
                      'Prompts, nie dasselbe Bild mehrfach: OpenAI und '
                      'Gemini würfeln je Bild neu, bei Stability und der '
                      'eigenen GPU zählt der Seed pro Bild hoch '
                      '(Seed, Seed+1 …).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline),
            ),
            if (isStability) ...[
              const SectionLabel('Profi-Optionen'),
              TextField(
                controller: _negativeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Negativ-Prompt',
                  hintText: 'Was im Bild vermieden werden soll …',
                  border: OutlineInputBorder(),
                ),
              ),
              if (settings.stabilityModel == 'core') ...[
                const SizedBox(height: 12),
                DropdownMenu<String>(
                  initialSelection: settings.stylePreset,
                  label: const Text('Style-Preset'),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final option in stylePresetOptions)
                      DropdownMenuEntry(value: option.$1, label: option.$2),
                  ],
                  onSelected: (value) {
                    if (value != null) settings.setStylePreset(value);
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _seedCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Seed (0 = zufällig)',
                  helperText: 'Gleicher Seed + gleicher Prompt = '
                      'reproduzierbares Bild; bei mehreren Bildern zählt '
                      'er pro Bild hoch',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Kosten je Bild im Vergleich'),
              children: [
                Text(
                  'Ungefähre Kosten pro Bild (1024×1024; Hoch-/Querformat '
                  'ca. das 1,5-Fache):\n'
                  '• OpenAI gpt-image-1-mini: ≈ 0,005–0,04 \$ je nach '
                  'Qualität – am günstigsten.\n'
                  '• OpenAI gpt-image-1: niedrig ≈ 0,011 \$, mittel '
                  '≈ 0,042 \$, hoch ≈ 0,167 \$; die neueren '
                  'gpt-image-1.5/2 liegen darüber, mit bester '
                  'Text-Darstellung im Bild.\n'
                  '• Google Gemini 2.5 Flash Image („Nano Banana“): '
                  '≈ 0,039 \$ – bester Allrounder für Referenzbilder '
                  'und die 3D-Ansichten.\n'
                  '• Google Nano Banana Pro (gemini-3-pro-image): '
                  '≈ 0,13 \$ (1K/2K) bis ≈ 0,24 \$ (4K) – höchste '
                  'Qualität und Auflösung.\n'
                  '• Stability Core: ≈ 0,03 \$ (3 Credits) – günstig, '
                  'mit Style-Presets; SD 3.5: ≈ 0,035–0,065 \$; '
                  'Ultra: ≈ 0,08 \$ – beste Stability-Qualität. '
                  'Kein Referenzbild-Support (für die 3D-Pipeline '
                  'OpenAI/Gemini wählen).\n'
                  '• Eigene GPU (lokaler Bild-Server): 0 \$ – Stable '
                  'Diffusion auf dem eigenen Rechner, unbegrenzt viele '
                  'Bilder, alle Daten bleiben lokal. Einrichtung in den '
                  'Einstellungen unter „Eigener Bild-Server".\n'
                  'Faustregel: Zum Experimentieren gpt-image-1-mini oder '
                  'Stability Core, für gute Alltagsbilder Gemini Flash '
                  'Image, für Feinstes gpt-image (hoch) oder Nano Banana '
                  'Pro. Preise laut Anbieter (Stand 2026) – können sich '
                  'ändern.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Beschriftung einer Größen-Option inklusive Pixelmaßen.
  String _sizeOptionLabel(SettingsService settings, Option option) {
    switch (settings.provider) {
      case GenProvider.openai:
        return option.$2;
      case GenProvider.selfhost:
        return option.$2;
      case GenProvider.stability:
        final (w, h) =
            stabilityApproxPixels(option.$1, settings.stabilityModel);
        return '${option.$2} · ca. $w×$h px';
      case GenProvider.gemini:
        final size = settings.geminiModel.contains('pro')
            ? settings.geminiImageSize
            : '1K';
        final pixels = geminiAspectPixelLabel(option.$1, size);
        return pixels.isEmpty ? option.$2 : '${option.$2} · $pixels';
    }
  }

  List<Widget> _buildResultsHeader() {
    return [
      Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Ergebnisse',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          if (_usageInfo != null && !_generating)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _usageInfo!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
        ],
      ),
      // Beim Massenlauf zeigt das Statusfenster, was gerade entsteht
      // und wie lange es noch dauert; es bleibt danach als Bilanz
      // stehen.
      if (_batchTotal > 0) ...[
        _buildBatchStatus(),
        const SizedBox(height: 8),
      ] else if (_generating) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          'Bild wird generiert – das kann je nach Qualität 10–60 Sekunden '
          'dauern.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _buildResultsGrid({required bool shrinkWrap}) {
    if (_results.isEmpty) {
      final placeholder = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'Noch keine Ergebnisse.\nBeschreibung eingeben und '
                '„Bild generieren“ antippen.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
      return placeholder;
    }
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final image = _results[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _openDetail(image, index),
                  child: SizedBox.expand(
                    child: CheckerboardImage(
                        bytes: image.bytes, fit: BoxFit.cover),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Vergrößern',
                    icon: const Icon(Icons.zoom_out_map),
                    onPressed: () => _openDetail(image, index),
                  ),
                  IconButton(
                    tooltip: 'Speichern / Teilen',
                    icon: const Icon(Icons.download),
                    onPressed: () => _exportResult(image, index),
                  ),
                  IconButton(
                    tooltip: 'Als Referenzbild verwenden',
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: () => _useAsReference(image),
                  ),
                  IconButton(
                    tooltip: 'Erstellungsnachweis (PDF)',
                    icon: const Icon(Icons.workspace_premium_outlined),
                    onPressed: () => _exportProvenance(image),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
