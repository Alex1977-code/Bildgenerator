import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/batch_prompt.dart';
import '../services/exporter.dart';
import '../services/prompt_briefing.dart';
import '../services/prompt_rewrite.dart';
import '../services/generators.dart';
import '../services/history_service.dart';
import '../services/model_catalog.dart';
import '../services/cost_estimator.dart';
import '../services/prompt_drop.dart';
import '../services/prompt_relay.dart';
import '../services/quality_preset.dart';
import '../services/provenance.dart';
import '../services/self_host_service.dart';
import '../services/settings_service.dart';
import '../services/view_direction.dart';
import '../services/wait_motif.dart';
import '../services/watermark.dart';
import '../widgets/common.dart';
import '../widgets/cost_quality_panel.dart';
import '../widgets/generation_progress.dart';
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

  /// Live-Vorschau des laufenden Bildes (nur eigene GPU – die
  /// Cloud-Anbieter liefern keine Zwischenstände).
  Uint8List? _preview;
  int _previewStep = 0;
  int _previewTotal = 0;
  DateTime? _runStart;
  Timer? _previewTimer;
  String _previewJob = '';

  /// Regeln für Gebäude-Assets: genau ein Gebäude, keine Bodenplatte,
  /// 35° von oben, grobes Mauerwerk. Sie stehen in der Vorlage für die
  /// Prompt-KI und werden beim Prüfen mitkontrolliert.
  final _seedCtrl = TextEditingController(text: '0');
  final _picker = ImagePicker();
  final List<ReferenceImage> _references = [];

  List<GeneratedImage> _results = [];
  GenerationRequest? _lastRequest;
  String? _usageInfo;
  bool _generating = false;
  bool _dragOverReferences = false;

  /// Liegt gerade eine Datei über dem Prompt-Feld?
  bool _dragOverPrompt = false;
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

  /// Blöcke, die nicht durchgingen – damit sich nur diese wiederholen
  /// lassen und nicht der ganze Lauf.
  final List<BatchItem> _batchFailedItems = [];

  /// Anmerkungen des Servers zu gelungenen Bildern (z. B. „Prompt
  /// musste gekürzt werden").
  final List<String> _batchNotes = [];

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
    _previewTimer?.cancel();
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

  /// Startet die Live-Vorschau, sofern der Anbieter welche liefert.
  ///
  /// Nur der eigene Bild-Server legt Zwischenstände ab; OpenAI, Gemini
  /// und Stability antworten erst mit dem fertigen Bild. Ist keine
  /// Vorschau möglich, bleibt die Kennung leer und der Server bekommt
  /// gar keinen Vorschau-Auftrag – dann kostet es auch nichts.
  String _startPreview(SettingsService settings) {
    _previewTimer?.cancel();
    setState(() {
      _preview = null;
      _previewStep = 0;
      _previewTotal = 0;
      _runStart = DateTime.now();
    });
    if (!settings.provider.isLocal) return '';
    final url =
        SelfHostImageGenerator.normalizeBaseUrl(settings.selfHostImageUrl);
    if (url.isEmpty) return '';
    final job = 'app-${DateTime.now().microsecondsSinceEpoch}';
    final service = SelfHostService(url, kindHint: 'image');
    _previewTimer =
        Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (!mounted || !_generating) return;
      final shot = await service.fetchPreview(job);
      if (!mounted || shot == null) {
        // Auch ohne neues Bild soll die Uhr weiterlaufen.
        if (mounted) setState(() {});
        return;
      }
      setState(() {
        _preview = shot.bytes;
        _previewStep = shot.step;
        _previewTotal = shot.total;
      });
    });
    return job;
  }

  void _stopPreview() {
    _previewTimer?.cancel();
    _previewTimer = null;
    if (mounted) {
      setState(() {
        _preview = null;
        _previewStep = 0;
        _previewTotal = 0;
      });
    }
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
    // GPT-Image und Gemini kennen kein Negativ-Feld, verstehen aber
    // Verneinungen. Damit eine Zeile „NEGATIV:" aus dem Massenprompt
    // auch dort wirkt, wandert sie als Satz in den Prompt.
    final withNegative = applyNegativePrompt(
      prompt,
      negativePrompt,
      negativeHandlingFor(
          settings.provider, settings.modelFor(settings.provider)),
    );
    final quality = settings.provider == GenProvider.selfhost
        ? settings.gpuQualitySettings
        // Für die Cloud-Anbieter gilt weiter deren eigene Steuerung
        // (OpenAI-Qualitätsstufe, Stability-Preset); Schritte und
        // Prompt-Treue nehmen sie gar nicht entgegen.
        : const QualitySettings(
            steps: 0, guidance: -1, detail: 0, detailScale: 1);
    return GenerationRequest(
      provider: settings.provider,
      prompt: withNegative.prompt,
      negativePrompt: withNegative.negativePrompt,
      previewJob: _previewJob,
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
      steps: quality.steps,
      guidance: quality.guidance,
      sampler: settings.gpuSampler,
      detail: quality.detail,
      detailScale: quality.detailScale,
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

    setState(() {
      _generating = true;
      _error = null;
    });
    _previewJob = _startPreview(settings);
    final request = _buildRequest(
      settings,
      prompt: prompt,
      negativePrompt: _negativeCtrl.text,
      references: List.of(_references),
      count: settings.count,
    );
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
      _stopPreview();
      _previewJob = '';
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
    setState(() {
      _batchPlan = _parseBatch(settings);
      _error = null;
    });
  }

  /// Schreibt den Massenprompt auf die Schreibweise des gewählten
  /// Modells um.
  ///
  /// Der Anlass: ein Briefing mit 351 Wörtern auf SDXL Base – ganze
  /// Sätze, Verneinungen, Gradzahlen. Die Prüfung hat jeden Punkt
  /// genannt, aber Hinweise lesen und einen 43-Block-Prompt von Hand
  /// umschreiben sind zwei verschiedene Dinge.
  Future<void> _rewriteBatch(SettingsService settings) async {
    final profile = _profile(settings);
    if (profile.style != PromptStyle.keywords) {
      _showSnack('${profile.modelLabel} liest ganze Sätze – da gibt es '
          'nichts umzuschreiben.');
      return;
    }
    final plan = _parseBatch(settings);
    if (plan.items.isEmpty) {
      _showSnack('Kein Block erkannt – erst „Prüfen" drücken.');
      return;
    }
    final result = rewriteBatchText(plan,
        profile: profile, direction: _direction(settings));
    if (result.changedItems == 0) {
      _showSnack('Der Massenprompt passt schon zu '
          '${profile.modelLabel}.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Für dieses Modell umschreiben'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${result.changedItems} von ${plan.items.length} '
                    'Block/Blöcken werden umgeschrieben. Der alte Text '
                    'wird dabei ersetzt – vorher kopieren, wenn er noch '
                    'gebraucht wird.'),
                const SizedBox(height: 10),
                for (final note in result.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $note'),
                  ),
                const SizedBox(height: 6),
                Text('So sieht der erste Block danach aus:',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(
                  result.text.split('\n\n').first,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Umschreiben'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _batchCtrl.text = result.text;
      _batchPlan = _parseBatch(settings);
    });
    _showSnack('${result.changedItems} Block/Blöcke umgeschrieben und '
        'neu geprüft.');
  }

  /// Prüft den Massenprompt gegen das gerade gewählte Bild-Modell:
  /// Höchstlänge, Prompt-Art und der Umgang mit dem Negativ-Prompt
  /// hängen daran.
  BatchPlan _parseBatch(SettingsService settings) => parseBatchPrompt(
        _batchCtrl.text,
        availableReferences: [for (final ref in _references) ref.name],
        supportsReferences: settings.provider.supportsReferences,
        profile: _profile(settings),
        direction: _direction(settings),
      );

  /// Vorlage für die Prompt-KI – mit den Namen der aktuell geladenen
  /// Referenzbilder und den Schreibregeln des gewählten Bild-Modells,
  /// damit die einzelnen PROMPT-Zeilen gleich richtig geschrieben sind.
  String _batchBriefing(SettingsService settings) => batchPromptBriefing(
        _profile(settings),
        references: [for (final ref in _references) ref.name],
        direction: _direction(settings),
      );

  Future<void> _copyBatchBriefing(SettingsService settings) async {
    await Clipboard.setData(ClipboardData(text: _batchBriefing(settings)));
    if (mounted) {
      _showSnack('Vorlage für ${_profile(settings).modelLabel} kopiert – '
          'in die Prompt-KI einfügen, Vorgaben ausfüllen und das '
          'Ergebnis hier hereinkopieren.');
    }
  }

  /// Zeigt die Massenprompt-Vorlage zum Lesen, mit Kopier-Knopf.
  Future<void> _showBatchBriefing(SettingsService settings) async {
    final profile = _profile(settings);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vorlage für den Massenprompt'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.modelLabel,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(profile.negativeNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 12),
                SelectableText(
                  _batchBriefing(settings),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _copyBatchBriefing(settings);
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Kopieren'),
          ),
        ],
      ),
    );
  }

  /// Wiederholt nur die Blöcke, die beim letzten Lauf nicht
  /// durchgingen. Bei 43 Bildern à zehn Minuten ist ein kompletter
  /// Neustart wegen eines Ausfalls keine Option.
  Future<void> _retryFailedBatch() =>
      _generateBatch(only: List.of(_batchFailedItems));

  /// Erzeugt alle Bilder des Massenprompts nacheinander.
  /// [only] beschränkt den Lauf auf diese Blöcke (Wiederholung).
  Future<void> _generateBatch({List<BatchItem>? only}) async {
    final settings = context.read<SettingsService>();
    final history = context.read<HistoryService>();

    final plan = _parseBatch(settings);
    if (!plan.isValid) {
      setState(() {
        _batchPlan = plan;
        _error = 'Der Massenprompt hat noch offene Punkte – bitte oben '
            'nachsehen.';
      });
      return;
    }
    // Beim Wiederholen zählen die Namen aus dem letzten Lauf; sie
    // müssen noch im Text stehen, sonst ist der Block weg.
    final items = only == null || only.isEmpty
        ? plan.items
        : [
            for (final item in plan.items)
              if (only.any((failed) => failed.name == item.name)) item,
          ];
    if (items.isEmpty) {
      setState(() => _error = 'Die zu wiederholenden Blöcke stehen nicht '
          'mehr im Massenprompt.');
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
      _batchTotal = items.length;
      _batchCurrent = items.first.name;
      _batchStart = DateTime.now();
      _batchTimes.clear();
      _batchFailures.clear();
      _batchFailedItems.clear();
      _batchNotes.clear();
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
      for (final item in items) {
        if (_batchCancel) break;
        if (mounted) setState(() => _batchCurrent = item.name);
        final started = DateTime.now();
        _previewJob = _startPreview(settings);
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
          if (result.note.isNotEmpty) {
            _batchNotes.add('${item.name}: ${result.note}');
          }
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
          _batchFailedItems.add(item);
        } catch (e) {
          _batchFailures.add('${item.name}: $e');
          _batchFailedItems.add(item);
        } finally {
          _stopPreview();
          _previewJob = '';
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
      if (_batchMode)
        _buildBatchCard(settings)
      else
        _buildPromptCard(settings),
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
  Widget _buildBatchCard(SettingsService settings) {
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
                // Nur bei Stichwort-Modellen: Bei GPT-Image und Gemini
                // ist ein Briefing genau richtig, da gäbe es nichts zu
                // verbessern.
                if (_profile(settings).style == PromptStyle.keywords)
                  OutlinedButton.icon(
                    onPressed: _generating
                        ? null
                        : () => _rewriteBatch(settings),
                    icon: const Icon(Icons.auto_fix_high_outlined,
                        size: 18),
                    label: const Text('Für dieses Modell umschreiben'),
                  ),
                OutlinedButton.icon(
                  onPressed: _generating
                      ? null
                      : () => _copyBatchBriefing(settings),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Vorlage für Prompt-KI kopieren'),
                ),
                TextButton.icon(
                  onPressed: _generating
                      ? null
                      : () => _showBatchBriefing(settings),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Vorlage ansehen'),
                ),
                TextButton.icon(
                  onPressed: _generating
                      ? null
                      : () {
                          _batchCtrl.text = batchPromptExample(
                              _profile(settings),
                              direction: _direction(settings));
                          _checkBatch();
                        },
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Beispiel einfügen'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Die Vorlage ist auf ${_profile(settings).modelLabel} '
              'zugeschnitten: ${_profile(settings).summary} '
              '${_profile(settings).negativeNote}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            _buildViewDirection(settings),
            if (plan != null) ...[
              const SizedBox(height: 12),
              _buildBatchResult(plan),
            ],
          ],
        ),
      ),
    );
  }

  /// Die gewählte Blickrichtung.
  ViewDirection _direction(SettingsService settings) =>
      viewDirectionById(settings.viewDirection);

  /// Die Auswahl der Blickrichtung. Sie ersetzt den früheren Schalter
  /// „Spielgrafik-Regeln": Der kannte genau eine Kamera und war für
  /// alles andere nutzlos. Die Spielgrafik ist jetzt eine Richtung
  /// unter anderen – sie bringt ihre Zusatzregeln mit.
  Widget _buildViewDirection(SettingsService settings) {
    final theme = Theme.of(context);
    final direction = _direction(settings);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Blickrichtung'),
          DropdownMenu<String>(
            key: ValueKey('richtung-${direction.id}'),
            initialSelection: direction.id,
            expandedInsets: EdgeInsets.zero,
            enabled: !_generating,
            label: const Text('Kamera'),
            dropdownMenuEntries: [
              for (final d in viewDirections)
                DropdownMenuEntry(value: d.id, label: d.label),
            ],
            onSelected: (value) {
              if (value == null) return;
              settings.setViewDirection(value);
              if (_batchPlan != null) _checkBatch();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(direction.hint, style: theme.textTheme.bodySmall),
          ),
          // Was daraus im Prompt wird – in der Schreibweise des
          // gewählten Modells. Ohne diese Zeile bliebe die Auswahl
          // eine Behauptung.
          if (!direction.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _directionPreview(settings, direction),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  /// Der Satz bzw. die Stichworte, die aus der Blickrichtung in den
  /// Prompt gehen – samt dem, was in den Negativ-Block wandert.
  String _directionPreview(
      SettingsService settings, ViewDirection direction) {
    final profile = _profile(settings);
    final teile = viewDirectionParts(
        direction, profile.style, profile.negativeHandling);
    final negativ = teile.negative.isEmpty
        ? ''
        : '\nNegativ: ${teile.negative}';
    return 'Im Prompt: ${teile.prompt}$negativ';
  }

  /// Ergebnis der Prüfung: grüner Haken samt Zahlen oder die Liste
  /// dessen, was noch fehlt.
  Widget _buildBatchResult(BatchPlan plan) {
    final theme = Theme.of(context);
    final good = plan.isValid;
    // Ein grüner Haken über fünf Hinweisen, die genau erklären, warum
    // das Bild danebengeht, ist eine Falschmeldung. Startklar und
    // richtig sind zwei verschiedene Dinge.
    final doubtful = good && plan.warnings.isNotEmpty;
    final color = !good
        ? theme.colorScheme.error
        : doubtful
            ? Colors.orange.shade800
            : Colors.green.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: !good
            ? theme.colorScheme.errorContainer
            : doubtful
                ? Colors.orange.withValues(alpha: 0.08)
                : Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  !good
                      ? Icons.error_outline
                      : doubtful
                          ? Icons.warning_amber_outlined
                          : Icons.check_circle,
                  color: color,
                  size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !good
                      ? 'Der Massenprompt ist noch nicht startklar:'
                      : doubtful
                          ? '${plan.items.length} Bilder erkannt – der '
                              'Lauf ist möglich, aber '
                              '${plan.warnings.length} Punkt(e) '
                              'sprechen gegen das Ergebnis:'
                          : '${plan.items.length} Bilder erkannt'
                              '${plan.withReferences > 0 ? ', davon '
                                  '${plan.withReferences} mit '
                                  'Referenzbild' : ''}'
                              ' – der Massenprompt ist in Ordnung.',
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
                      size: 14,
                      color: doubtful
                          ? Colors.orange.shade800
                          : theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('$warning',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: doubtful
                                ? Colors.orange.shade900
                                : theme.colorScheme.outline)),
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
              if (!_batchRunning && _batchFailedItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _generating ? null : _retryFailedBatch,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_batchFailedItems.length == 1
                      ? 'Das eine Bild wiederholen'
                      : '${_batchFailedItems.length} Bilder wiederholen'),
                ),
                Text(
                  'Wiederholt nur diese Blöcke – die fertigen Bilder '
                  'bleiben in der Galerie.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ],
            if (_batchNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Anmerkungen des Servers (${_batchNotes.length}):',
                  style: theme.textTheme.labelMedium),
              for (final note in _batchNotes.take(5))
                Text('• $note',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              if (_batchNotes.length > 5)
                Text('… und ${_batchNotes.length - 5} weitere',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
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

  /// Verneinungen im Prompt („no text", „ohne Schrift"). Die
  /// Bild-Modelle auf der eigenen GPU können damit nichts anfangen –
  /// sie lesen nur die Stichworte und holen das Gemeinte ins Bild.
  static final _negationPattern = RegExp(
      r'(^|[\s,;.(-])(no|not|without|avoid|keine?|kein|ohne)\s+[a-zA-ZäöüÄÖÜ]',
      caseSensitive: false);

  Widget _buildPromptCard(SettingsService settings) {
    final theme = Theme.of(context);
    final text = _promptCtrl.text;
    final local = settings.provider.isLocal;
    final hints = <String>[
      if (local && _negationPattern.hasMatch(text))
        'Verneinungen wie „no text" oder „ohne Schrift" versteht Stable '
            'Diffusion nicht – es liest nur die Stichworte und holt das '
            'Gemeinte eher ins Bild. Solche Angaben gehören unten in '
            'den Negativ-Prompt.',
      if (local && text.length > 900)
        'Sehr langer Prompt (${text.length} Zeichen). Der Server reicht '
            'ihn inzwischen vollständig durch, die Modelle gewichten '
            'aber den Anfang am stärksten – das Wichtigste (Motiv, '
            'Bauform, Farben) nach vorn, Kamera und Licht ans Ende.',
      if (local && RegExp(r'^[A-Z][A-Z ]{3,}$', multiLine: true)
          .hasMatch(text))
        'Gegliederte Briefings mit Überschriften (SUBJECT, STYLE, '
            'OUTPUT …) sind für GPT-Image und Gemini gedacht. Stable '
            'Diffusion liest alles als eine Stichwortliste – für die '
            'eigene GPU besser ein durchgehender, dichter Satz.',
    ];
    return DropTarget(
      enable: !_generating &&
          widget.isActive &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      onDragEntered: (_) => setState(() => _dragOverPrompt = true),
      onDragExited: (_) => setState(() => _dragOverPrompt = false),
      onDragDone: (detail) => _dropPromptFiles(detail.files, _promptCtrl),
      child: Card(
      shape: _dragOverPrompt
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_dragOverPrompt)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Text- oder Markdown-Datei hier ablegen – der Inhalt '
                  'wird angehängt.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            TextField(
              controller: _promptCtrl,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              onChanged: (_) {
                // Die Hinweise unten hängen am Text.
                if (settings.provider.isLocal) setState(() {});
              },
              decoration: const InputDecoration(
                labelText: 'Bildbeschreibung (Prompt)',
                hintText:
                    'Beschreibe das gewünschte Bild so genau wie möglich …',
                border: OutlineInputBorder(),
              ),
            ),
            for (final hint in hints) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(hint,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            // Der Auftrag für die Prompt-KI hängt am gewählten Modell:
            // GPT-Image und Gemini wollen ein gegliedertes Briefing,
            // Stable Diffusion eine Stichwortkette.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prompt-Vorlage für ${_profile(settings).modelLabel}',
                    style: theme.textTheme.labelMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showPromptBriefing(settings),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Ansehen'),
                ),
                TextButton.icon(
                  onPressed: () => _copyPromptBriefing(settings),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Kopieren'),
                ),
              ],
            ),
            Text(
              _profile(settings).summary,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            _buildViewDirection(settings),
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
    ),
    );
  }

  /// Abgelegte Text- und Markdown-Dateien in ein Prompt-Feld
  /// übernehmen.
  ///
  /// Prompts entstehen selten in der App – sie kommen aus einer
  /// Prompt-KI oder einer Datei mit den Beschreibungen eines ganzen
  /// Spiel-Sets. Bei einem Massenprompt über mehrere Bildschirmseiten
  /// ist Kopieren-und-Einfügen fehleranfällig.
  Future<void> _dropPromptFiles(
      List<XFile> files, TextEditingController target) async {
    setState(() => _dragOverPrompt = false);
    final messenger = ScaffoldMessenger.of(context);
    final accepted = <String>[];
    final rejected = <String>[];
    var text = target.text;
    for (final file in files) {
      if (!isPromptTextFile(file.name)) {
        rejected.add(file.name);
        continue;
      }
      try {
        text = appendPromptText(text, await file.readAsString());
        accepted.add(file.name);
      } catch (e) {
        rejected.add('${file.name} ($e)');
      }
    }
    if (!mounted) return;
    if (accepted.isNotEmpty) {
      setState(() {
        target.text = text;
        target.selection =
            TextSelection.collapsed(offset: text.length);
      });
    }
    messenger.showSnackBar(SnackBar(
        content: Text(promptDropSummary(accepted, rejected))));
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
    // Die Beschriftung der gerade gewählten Größe – sie steht im
    // geschlossenen Feld und geht in den Schlüssel des Dropdowns ein.
    final sizeLabel = _sizeOptionLabel(
        settings,
        sizeOptions.firstWhere((o) => o.$1 == sizeValue,
            orElse: () => (sizeValue, sizeValue)));
    final imageSizeLabel = '${geminiImageSizeOptions.firstWhere(
      (o) => o.$1 == settings.geminiImageSize,
      orElse: () => (settings.geminiImageSize, settings.geminiImageSize),
    ).$2} · '
        '${geminiAspectPixelLabel(settings.geminiAspect, settings.geminiImageSize)}';
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
                  if (_localModelNote(settings) case final note?) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 15,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SectionLabel('Format & Größe'),
                  DropdownMenu<String>(
                    // Der Schlüssel hängt an der angezeigten
                    // Beschriftung, nicht an einer Liste von
                    // Einstellungen. DropdownMenu schreibt seinen Text
                    // nur bei einer geänderten Auswahl nach – ändert
                    // sich nur die Pixelangabe darin (anderes Modell,
                    // andere Auflösung), bliebe im Feld sonst die alte
                    // stehen. Über den Schlüssel entsteht das Feld neu.
                    key: ValueKey('size-${provider.name}-$sizeLabel'),
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
                      key: ValueKey('imgsize-$imageSizeLabel'),
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
            // Den Negativ-Prompt gibt es überall, wo das Modell etwas
            // damit anfängt – bei GPT-Image und Gemini wandert er als
            // Satz in den Prompt. Seed und Style-Presets bleiben bei
            // Stability und dem eigenen Server.
            const SectionLabel('Profi-Optionen'),
            TextField(
              controller: _negativeCtrl,
              decoration: InputDecoration(
                labelText: 'Negativ-Prompt',
                hintText: 'Was im Bild vermieden werden soll …',
                border: const OutlineInputBorder(),
                helperText: _profile(settings).negativeNote,
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            if (isStability || provider.isLocal) ...[
              if (isStability && settings.stabilityModel == 'core') ...[
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
            if (provider == GenProvider.selfhost) ...[
              const SizedBox(height: 12),
              _qualityPanel(settings),
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

  /// Vorlage für die Prompt-KI, passend zum gewählten Modell.
  PromptProfile _profile(SettingsService settings) => promptProfileFor(
        settings.provider,
        settings.modelFor(settings.provider),
        referenceCount: _references.length,
        direction: _direction(settings),
      );

  Future<void> _copyPromptBriefing(SettingsService settings) async {
    final profile = _profile(settings);
    await Clipboard.setData(ClipboardData(text: profile.briefing));
    if (mounted) {
      _showSnack('Vorlage für ${profile.modelLabel} kopiert – in die '
          'Prompt-KI einfügen, Vorgaben ausfüllen, Ergebnis hier '
          'einsetzen.');
    }
  }

  /// Zeigt die Vorlage zum Lesen, mit Kopier-Knopf.
  Future<void> _showPromptBriefing(SettingsService settings) async {
    final profile = _profile(settings);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vorlage für die Prompt-KI'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.modelLabel,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(profile.summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 12),
                SelectableText(
                  profile.briefing,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12.5),
                ),
                if (profile.wantsNegativePrompt) ...[
                  const SizedBox(height: 12),
                  Text('Vorschlag für den Negativ-Prompt',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  SelectableText(profile.negativeExample,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (profile.wantsNegativePrompt)
            TextButton.icon(
              onPressed: () {
                setState(() => _negativeCtrl.text = profile.negativeExample);
                Navigator.of(context).pop();
                _showSnack('Negativ-Prompt eingesetzt.');
              },
              icon: const Icon(Icons.block_flipped, size: 18),
              label: const Text('Negativ-Prompt übernehmen'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _copyPromptBriefing(settings);
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Kopieren'),
          ),
        ],
      ),
    );
  }

  /// Qualität und Detailtreue auf der eigenen GPU.
  ///
  /// Vier Stufen für den Alltag, darunter aufgeklappt die beiden
  /// Regler, an denen es wirklich hängt. Die Stufe rechnet **relativ
  /// zum Modell**: SDXL Turbo bleibt auch bei „Sehr fein" bei wenigen
  /// Schritten, weil es darauf trainiert ist – 40 Schritte machen dort
  /// kein besseres Bild, sondern ein weicheres.
  Widget _qualityPanel(SettingsService settings) {
    final theme = Theme.of(context);
    final model = settings.selfHostImageModel;
    final (modelSteps, modelGuidance, canDetail) =
        localModelDefault(model);
    final effective = settings.gpuQualitySettings;
    // Wollte die Stufe einen Detail-Durchgang, kann das Modell aber
    // keinen? Dann gehört das dazugesagt, statt still zu schweigen.
    final wantsDetail = qualityFor(
      preset: settings.gpuQuality,
      modelSteps: modelSteps,
      modelGuidance: modelGuidance,
    ).hasDetailPass;
    final warning = qualityWarning(
      steps: effective.steps,
      guidance: effective.guidance,
      modelGuidance: modelGuidance,
    );
    final distilled = modelGuidance <= 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18),
                const SizedBox(width: 8),
                // Ohne Expanded lief die Überschrift auf einer
                // schmalen Karte über den Rand hinaus – sichtbar als
                // schwarz-gelbe Streifen.
                Expanded(
                  child: Text('Qualität und Detailtreue',
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<QualityPreset>(
              showSelectedIcon: false,
              segments: [
                for (final preset in QualityPreset.values)
                  ButtonSegment(
                    value: preset,
                    label: Text(qualityLabel(preset).$1),
                  ),
              ],
              selected: {settings.gpuQuality},
              onSelectionChanged: (value) =>
                  settings.setGpuQuality(value.first),
            ),
            const SizedBox(height: 6),
            Text(qualityLabel(settings.gpuQuality).$2,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            // Was tatsächlich gesendet wird – ohne diese Zeile bliebe
            // die Stufe eine Behauptung.
            Text(
              'Daraus wird: ${effective.steps} Schritte'
              '${distilled ? '' : ', Prompt-Treue '
                  '${effective.guidance.toStringAsFixed(1)}'}'
              '${effective.hasDetailPass ? ', Detail-Durchgang auf '
                  '${effective.detailScale.toStringAsFixed(2)}× Größe' : ''}'
              '${wantsDetail && !canDetail ? ' – dieses Modell kennt '
                  'keinen Detail-Durchgang' : ''}.',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            if (warning.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(warning,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
                ],
              ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: const Text('Von Hand einstellen'),
              subtitle: const Text('Schritte, Prompt-Treue, Sampler'),
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text('Schritte ${effective.steps}',
                          style: theme.textTheme.bodySmall),
                    ),
                    Expanded(
                      child: Slider(
                        value: effective.steps
                            .clamp(1, maxSteps)
                            .toDouble(),
                        min: 1,
                        max: maxSteps.toDouble(),
                        divisions: maxSteps - 1,
                        label: '${effective.steps}',
                        onChanged: (v) =>
                            settings.setGpuSteps(v.round()),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        distilled
                            ? 'Prompt-Treue –'
                            : 'Prompt-Treue '
                                '${effective.guidance.toStringAsFixed(1)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              distilled ? theme.colorScheme.outline : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: effective.guidance
                            .clamp(0.0, 15.0)
                            .toDouble(),
                        max: 15,
                        divisions: 30,
                        label: effective.guidance.toStringAsFixed(1),
                        // Destillierte Modelle rechnen ohne
                        // Prompt-Treue; ein Regler wäre dort eine
                        // Attrappe.
                        onChanged: distilled
                            ? null
                            : (v) => settings.setGpuGuidance(v),
                      ),
                    ),
                  ],
                ),
                if (distilled)
                  Text(
                    'Dieses Modell rechnet ohne Prompt-Treue – der '
                    'Regler bliebe wirkungslos.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                const SizedBox(height: 8),
                DropdownMenu<String>(
                  initialSelection: settings.gpuSampler,
                  label: const Text('Sampler'),
                  expandedInsets: EdgeInsets.zero,
                  helperText: canDetail
                      ? 'Bestimmt, wie das Rauschen abgebaut wird – bei '
                          'gleicher Schrittzahl ein sichtbarer '
                          'Unterschied in Schärfe und Struktur.'
                      : 'Dieses Modell rechnet nach einem anderen '
                          'Verfahren und behält seinen eigenen Sampler.',
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(
                        value: '', label: 'Vorgabe des Modells'),
                    DropdownMenuEntry(
                        value: 'dpmpp2m-karras',
                        label: 'DPM++ 2M Karras (fein, Standardwahl)'),
                    DropdownMenuEntry(
                        value: 'dpmpp2m', label: 'DPM++ 2M'),
                    DropdownMenuEntry(
                        value: 'euler', label: 'Euler (ruhig)'),
                    DropdownMenuEntry(
                        value: 'euler-a',
                        label: 'Euler a (mehr Variation)'),
                    DropdownMenuEntry(value: 'ddim', label: 'DDIM'),
                  ],
                  onSelected: (value) =>
                      settings.setGpuSampler(value ?? ''),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        settings.setGpuQuality(settings.gpuQuality),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text('Zurück auf '
                        '„${qualityLabel(settings.gpuQuality).$1}"'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Hinweis zum gewählten Modell der eigenen GPU. Stable Diffusion
  /// liest einen Prompt anders als GPT-Image oder Gemini – wer das
  /// nicht weiß, wundert sich über das Ergebnis.
  String? _localModelNote(SettingsService settings) {
    if (settings.provider != GenProvider.selfhost) return null;
    final model = settings.selfHostImageModel;
    final specific = switch (model) {
      'sdxl-turbo' => 'SDXL Turbo ist auf Tempo gebaut (4 Schritte, '
          'ohne Guidance): Es hält sich nur grob an den Prompt und '
          'wertet den Negativ-Prompt gar nicht aus. Für lange, genaue '
          'Vorgaben besser SDXL Base oder SD 3.5 Medium wählen.',
      'sd15' => 'SD 1.5 ist sparsam, aber das älteste Modell hier – '
          'komplizierte Vorgaben (Proportionen, Pose, Farbwahl) setzt '
          'es oft nur ungefähr um.',
      'sdxl' => 'SDXL Base hält sich gut an den Prompt (30 Schritte, '
          'Guidance 7) und wertet den Negativ-Prompt aus.',
      'sd35-medium' => 'SD 3.5 Medium versteht auch längere, '
          'zusammenhängende Beschreibungen und schreibt Text im Bild '
          'lesbar. Braucht dafür viel Speicher – unter 16 GB VRAM '
          'lagert der Server aus.',
      'sd35-medium-lean' => 'SD 3.5 Medium ohne den T5-Text-Encoder: '
          'passt auf eine 8-GB-Karte statt 16 zu brauchen. Der Preis '
          'ist das Textverständnis – kurze Motivketten gelingen '
          'weiter, lange verschachtelte Sätze und Text im Bild nicht '
          'mehr zuverlässig.',
      'flux-schnell' => 'FLUX.1 schnell liest den Prompt am genauesten, '
          'kennt aber keinen Negativ-Prompt.',
      _ => null,
    };
    return specific;
  }

  /// Beschriftung einer Größen-Option inklusive Pixelmaßen.
  String _sizeOptionLabel(SettingsService settings, Option option) {
    switch (settings.provider) {
      case GenProvider.openai:
        return option.$2;
      case GenProvider.selfhost:
        // Der eigene Server rechnet das Seitenverhältnis selbst in
        // Pixel um – hier stand die Angabe als einzige nicht dabei.
        final (w, h) =
            selfHostPixels(option.$1, settings.selfHostImageModel);
        return '${option.$2} · $w×$h px';
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
        if (_generating) ...[
          const SizedBox(height: 8),
          _buildProgressView(context.read<SettingsService>()),
        ],
        const SizedBox(height: 8),
      ] else if (_generating) ...[
        _buildProgressView(context.read<SettingsService>()),
        const SizedBox(height: 8),
      ],
    ];
  }

  /// Zeigt, wie das Bild entsteht.
  ///
  /// Bei der eigenen GPU kommt alle paar Diffusionsschritte ein echtes
  /// Zwischenbild vom Server – man sieht das Motiv aus dem Rauschen
  /// auftauchen. Die Cloud-Anbieter liefern keine Zwischenstände;
  /// dort läuft eine Wartegrafik, und der Text sagt auch warum.
  Widget _buildProgressView(SettingsService settings) {
    final local = settings.provider.isLocal;
    final elapsed = _runStart == null
        ? Duration.zero
        : DateTime.now().difference(_runStart!);
    return GenerationProgress(
      // Das Wartemotiv gehört zum Modell, das gerade rechnet.
      motif: waitMotifFor(
          settings.provider, settings.modelFor(settings.provider)),
      preview: _preview,
      step: _previewStep,
      totalSteps: _previewTotal,
      elapsed: elapsed,
      aspect: _previewAspect(settings),
      label: _batchTotal > 0
          ? 'Bild „$_batchCurrent" entsteht …'
          : 'Bild entsteht …',
      hint: local
          ? _preview == null
              ? 'Die Vorschau erscheint nach den ersten Schritten. '
                  'Bei SD 3.5 und FLUX gibt es keine – die packen ihre '
                  'Zwischenstände anders.'
              : 'Grobe Vorschau aus den Latents – Form und Farben '
                  'stimmen, Details noch nicht. Das fertige Bild kommt '
                  'in voller Auflösung.'
          : '${settings.provider.label} liefert keine Zwischenstände; '
              'das Bild kommt am Stück. Je nach Qualität 10–60 Sekunden.',
    );
  }

  /// Seitenverhältnis der Vorschaufläche, passend zur Einstellung.
  double _previewAspect(SettingsService settings) {
    final aspect = settings.provider == GenProvider.openai
        ? settings.openAiSize
        : settings.stabilityAspect;
    final parts = aspect.split(RegExp(r'[:x×]'));
    if (parts.length == 2) {
      final w = double.tryParse(parts[0].trim());
      final h = double.tryParse(parts[1].trim());
      if (w != null && h != null && h > 0) return w / h;
    }
    return 1;
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
