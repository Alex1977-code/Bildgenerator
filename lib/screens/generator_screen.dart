import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/batch_csv.dart';
import '../services/batch_prompt.dart';
import '../services/credit_balance.dart';
import '../services/exporter.dart';
import '../services/prompt_briefing.dart';
import '../services/prompt_rewrite.dart';
import '../services/generators.dart';
import '../services/history_service.dart';
import '../services/image_relay.dart';
import '../services/model_catalog.dart';
import '../services/cost_estimator.dart';
import '../services/cost_unit.dart';
import '../services/prompt_drop.dart';
import '../services/project_tree.dart';
import '../services/prompt_relay.dart';
import '../services/run_queue.dart';
import '../services/quality_preset.dart';
import '../services/provenance.dart';
import '../services/self_host_service.dart';
import '../services/settings_service.dart';
import '../services/view_direction.dart';
import '../services/wait_motif.dart';
import '../services/watermark.dart';
import '../widgets/app_header.dart';
import '../widgets/common.dart';
import '../widgets/generation_progress.dart';
import '../widgets/option_card.dart';
import 'image_detail_screen.dart';

/// Hauptbildschirm: Prompt, Referenzbilder, Optionen und Ergebnisse.
class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({
    super.key,
    required this.onOpenSettings,
    this.onOpenRuns,
    this.isActive = true,
  });

  final VoidCallback onOpenSettings;

  /// Öffnet die Warteschlange (Handy: der Chip in der Titelzeile).
  final VoidCallback? onOpenRuns;

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

  /// Die Blöcke, die im laufenden Massenlauf noch anstehen – für die
  /// gestrichelten Karten „in Warteschlange".
  final List<String> _batchPending = [];

  /// Zeit und Kosten je Ergebnis – „11 s · 0,04 \$" an der Karte.
  final List<_ResultMeta> _resultMeta = [];

  /// Massenprompt: Editor (true) oder die Tabelle der Blöcke.
  bool _batchEditing = true;

  /// „Profi-Optionen" aufgeklappt?
  bool _proOpen = false;

  /// Der Massenprompt-Text wurde nach dem Start zurückgeholt.
  bool _batchRestored = false;

  SettingsService? _settings;

  /// Der Plan zum gerade sichtbaren Text – ohne Klick auf „Prüfen".
  /// Gemerkt je Text, damit nicht jeder Bildaufbau neu parst.
  String _planCacheText = '\u0000';
  BatchPlan? _planCache;
  String _planCacheKey = '';

  BatchPlan _livePlan(SettingsService settings) {
    final key = '${settings.provider.name}/${settings.modelFor(settings.provider)}'
        '/${settings.viewDirection}/${_references.length}';
    if (_planCache == null ||
        _planCacheText != _batchCtrl.text ||
        _planCacheKey != key) {
      _planCacheText = _batchCtrl.text;
      _planCacheKey = key;
      _planCache = _parseBatch(settings);
    }
    return _planCache!;
  }

  @override
  void initState() {
    super.initState();
    // Jede Änderung am Massenprompt macht das Prüfergebnis ungültig –
    // der grüne Haken soll immer zum sichtbaren Text gehören.
    _batchCtrl.addListener(() {
      if (_batchPlan != null && !_batchRunning) {
        setState(() => _batchPlan = null);
      }
      // Der Text überlebt den Neustart – und die Tabelle folgt ihm.
      _settings?.rememberBatchText(_batchCtrl.text);
      if (mounted) setState(() {});
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
    final settings = context.read<SettingsService>();
    _settings = settings;
    if (!_batchRestored) {
      _batchRestored = true;
      if (settings.lastBatchText.trim().isNotEmpty) {
        _batchCtrl.text = settings.lastBatchText;
        _batchMode = true;
        _batchEditing = false;
      }
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
      _batchPending.clear();
    });
    final queue = context.read<RunQueue>();
    final balances = context.read<CreditBalances>();
    final job = queue.add(
      name: prompt.length > 40 ? '${prompt.substring(0, 40)} …' : prompt,
      kind: RunJobKind.image,
      provider: _motif(settings).name,
    );
    queue.start(job.id);
    final started = DateTime.now();
    _previewJob = _startPreview(settings);
    final request = _buildRequest(
      settings,
      prompt: prompt,
      negativePrompt: _negativeCtrl.text,
      references: List.of(_references),
      count: settings.count,
    );
    final (costMin, costMax, _) = imageModelCost(settings);
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
      if (result.creditsRemaining != null) {
        balances.noteRemaining(settings.provider.name, result.creditsRemaining!);
      }
      await history.addResults(request, images,
          project: settings.currentProject,
          extraParams: {
            if (result.totalTokens != null) 'Tokens': '${result.totalTokens}',
            if (watermarkOn) 'Wasserzeichen': 'ja',
          });
      final elapsed = DateTime.now().difference(started);
      queue.finish(job.id, costUsd: costMax * images.length);
      if (!mounted) return;
      setState(() {
        _results = images;
        _resultMeta
          ..clear()
          ..addAll([
            for (var i = 0; i < images.length; i++)
              _ResultMeta(
                  name: '',
                  elapsed: elapsed,
                  costUsd: costMax,
                  costMinUsd: costMin),
          ]);
        _lastRequest = request;
        _usageInfo = usageParts.isEmpty ? null : usageParts.join(' · ');
      });
    } on GenerationException catch (e) {
      queue.fail(job.id, e.message);
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      queue.fail(job.id, 'Unerwarteter Fehler: $e');
      if (mounted) setState(() => _error = 'Unerwarteter Fehler: $e');
    } finally {
      _stopPreview();
      _previewJob = '';
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Wer da rechnet – das Motiv gehört zum Modell.
  WaitMotif _motif(SettingsService settings) =>
      waitMotifFor(settings.provider, settings.modelFor(settings.provider));

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
      _batchPending
        ..clear()
        ..addAll([for (final item in items) item.name]);
      _results = [];
      _resultMeta.clear();
      _usageInfo = null;
      _error = null;
    });
    // Die vergangene Zeit soll auch zwischen zwei Bildern weiterlaufen.
    _batchTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _batchRunning) setState(() {});
    });

    // Jeder Block ein Auftrag in der Warteschlange – sichtbar aus
    // jedem Tab, und nach einem Neustart weiß die App, was fehlte.
    final queue = context.read<RunQueue>()..clearCancelRequest();
    final balances = context.read<CreditBalances>();
    final motifName = _motif(settings).name;
    final jobs = <String, RunJob>{
      for (final item in items)
        item.name: queue.add(
            name: item.name, kind: RunJobKind.image, provider: motifName),
    };
    final (costMin, costMax, _) = imageModelCost(settings);

    final produced = <GeneratedImage>[];
    final generator = ImageGenerator.forProvider(settings.provider);
    try {
      for (final item in items) {
        if (_batchCancel || queue.cancelRequested) break;
        if (mounted) {
          setState(() {
            _batchCurrent = item.name;
            _batchPending.remove(item.name);
          });
        }
        final job = jobs[item.name]!;
        queue.start(job.id);
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
          if (result.creditsRemaining != null) {
            balances.noteRemaining(
                settings.provider.name, result.creditsRemaining!);
          }
          final watermarkOn =
              settings.watermarkEnabled && settings.watermarkLogo != null;
          final images = await _watermarked(settings, result.images);
          await history.addResults(request, images,
              name: item.name,
              project: settings.currentProject,
              extraParams: {
                'Massenprompt': 'ja',
                if (result.totalTokens != null)
                  'Tokens': '${result.totalTokens}',
                if (watermarkOn) 'Wasserzeichen': 'ja',
              });
          produced.addAll(images);
          final elapsed = DateTime.now().difference(started);
          for (final _ in images) {
            _resultMeta.add(_ResultMeta(
                name: item.name,
                elapsed: elapsed,
                costUsd: costMax,
                costMinUsd: costMin));
          }
          queue.finish(job.id, costUsd: costMax);
          _lastRequest = request;
        } on GenerationException catch (e) {
          _batchFailures.add('${item.name}: ${e.message}');
          _batchFailedItems.add(item);
          queue.fail(job.id, e.message);
        } catch (e) {
          _batchFailures.add('${item.name}: $e');
          _batchFailedItems.add(item);
          queue.fail(job.id, '$e');
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
      // Was nicht mehr drankam, ist abgebrochen – nicht „wartet".
      for (final job in jobs.values) {
        if (job.isOpen) queue.cancel(job.id);
      }
      if (mounted) {
        setState(() {
          _batchRunning = false;
          _generating = false;
          _batchCurrent = '';
          _batchPending.clear();
        });
      }
    }
  }

  /// Ein Lauf wurde beim Schließen der App unterbrochen: die Blöcke,
  /// die noch fehlen und im Text noch stehen.
  List<BatchItem> _interruptedItems(SettingsService settings) {
    final queue = context.read<RunQueue>();
    final offen = {
      for (final job in queue.interrupted)
        if (job.kind == RunJobKind.image) job.name,
    };
    if (offen.isEmpty) return const [];
    return [
      for (final item in _livePlan(settings).items)
        if (offen.contains(item.name)) item,
    ];
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
    _settings = settings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          // 588 wie im Entwurf; auf schmaleren Fenstern die Hälfte.
          final left = math.min(588.0, constraints.maxWidth * 0.5);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: left,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                        children: _buildControls(settings),
                      ),
                    ),
                    _buildFooter(settings),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _buildResultsPane(settings)),
            ],
          );
        }
        return _buildNarrow(settings);
      },
    );
  }

  /// Die linke Spalte: Auftrag, Warnungen, Referenzen, vier Karten,
  /// Profi-Optionen. Der Knopf steht darunter fest (siehe
  /// [_buildFooter]).
  List<Widget> _buildControls(SettingsService settings) {
    return [
      _buildModeRow(settings),
      const SizedBox(height: 14),
      if (_batchMode)
        _buildBatchCard(settings)
      else
        _buildPromptCard(settings),
      for (final notice in _buildNotices(settings)) ...[
        const SizedBox(height: 12),
        notice,
      ],
      const SizedBox(height: 16),
      _buildReferenceRow(settings.provider.supportsReferences),
      const SizedBox(height: 16),
      _buildOptionGrid(settings),
      const SizedBox(height: 12),
      _buildProOptions(settings),
    ];
  }

  /// Handy: Titelzeile, Auftrag, zwei Knöpfe, unten das Feld mit
  /// Modell, Format, Stufe und dem Knopf – wie im Entwurf 1d.
  Widget _buildNarrow(SettingsService settings) {
    final theme = Theme.of(context);
    final queue = context.watch<RunQueue>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Row(
            children: [
              Text('Bild',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (queue.openCount > 0) ...[
                ActionChip(
                  avatar: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5)),
                  label: Text(queue.summary),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onOpenRuns,
                ),
                const SizedBox(width: 8),
              ],
              const ProjectChip(compact: true),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              _buildModeRow(settings, compact: true),
              const SizedBox(height: 12),
              if (_batchMode)
                _buildBatchCard(settings)
              else
                _buildPromptCard(settings),
              for (final notice in _buildNotices(settings)) ...[
                const SizedBox(height: 10),
                notice,
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showReferenceSheet(settings),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(_references.isEmpty
                          ? 'Referenz'
                          : 'Referenz ${_references.length}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showTemplateSheet(settings),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Vorlage'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildMobilePanel(settings),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _buildErrorCard(),
              ],
              const SizedBox(height: 18),
              ..._buildResultsHeader(settings),
              const SizedBox(height: 8),
              _buildResultsGrid(settings, shrinkWrap: true),
            ],
          ),
        ),
      ],
    );
  }

  /// „Massenprompt | Einzelbild", der Zähler, „Vorlage laden".
  ///
  /// [compact]: auf dem Handy ohne das Menü – dort gibt es den Knopf
  /// „Vorlage" darunter, und die Zeile ist nur 350 Punkte breit.
  Widget _buildModeRow(SettingsService settings, {bool compact = false}) {
    final plan = _batchMode ? _livePlan(settings) : null;
    final n = plan?.items.length ?? settings.count;
    return LayoutBuilder(builder: (context, constraints) {
      // Unter 460 Punkten wird aus „Vorlage laden" ein Symbol – und
      // ein Wrap statt einer Row: Passt der Zähler nicht mehr neben
      // den Umschalter, rutscht er in die nächste Zeile, statt
      // überzulaufen.
      final narrow = constraints.maxWidth < 460;
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          PillSegments<bool>(
            segments: const [(true, 'Massenprompt'), (false, 'Einzelbild')],
            selected: _batchMode,
            onChanged: _generating
                ? null
                : (value) => setState(() => _batchMode = value),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MonoText(
                _batchMode
                    ? '$n ${n == 1 ? 'Block' : 'Blöcke'} · $n ${n == 1 ? 'Bild' : 'Bilder'}'
                    : '$n ${n == 1 ? 'Bild' : 'Bilder'}',
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                _templateMenu(settings, iconOnly: narrow),
              ],
            ],
          ),
        ],
      );
    });
  }

  /// Das Menü „Vorlage laden": alles, was den Text füllt oder prüft.
  Widget _templateMenu(SettingsService settings, {bool iconOnly = false}) {
    final theme = Theme.of(context);
    final profile = _profile(settings);
    if (iconOnly) {
      return PopupMenuButton<String>(
        tooltip: 'Vorlage laden',
        enabled: !_generating,
        iconSize: 18,
        icon: Icon(Icons.auto_awesome_outlined,
            color: theme.colorScheme.primary),
        onSelected: (value) => _templateAction(settings, value),
        itemBuilder: (context) => _templateEntries(settings, profile),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Vorlagen und Werkzeuge für den Text',
      enabled: !_generating,
      onSelected: (value) => _templateAction(settings, value),
      itemBuilder: (context) => _templateEntries(settings, profile),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text('Vorlage laden',
            style: theme.textTheme.labelMedium?.copyWith(
                color: _generating
                    ? theme.colorScheme.outlineVariant
                    : theme.colorScheme.primary)),
      ),
    );
  }

  List<PopupMenuEntry<String>> _templateEntries(
      SettingsService settings, PromptProfile profile) {
    PopupMenuItem<String> item(String value, IconData icon, String text) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(text)),
            ],
          ),
        );
    return [
      if (_batchMode) ...[
        item('beispiel', Icons.lightbulb_outline, 'Beispiel einfügen'),
        item('csv', Icons.table_chart_outlined, 'CSV einlesen …'),
        item('pruefen', Icons.fact_check_outlined, 'Prüfbericht ansehen'),
        if (profile.style == PromptStyle.keywords)
          item('umschreiben', Icons.auto_fix_high_outlined,
              'Für ${profile.modelLabel} umschreiben'),
        const PopupMenuDivider(),
      ],
      item('ansehen', Icons.visibility_outlined,
          'Vorlage für die Prompt-KI ansehen'),
      item('kopieren', Icons.copy_all_outlined, 'Vorlage kopieren'),
      if (!_batchMode) ...[
        const PopupMenuDivider(),
        for (final template in promptTemplates)
          item('stil:${template.$1}', Icons.style_outlined, template.$2),
      ],
    ];
  }

  Future<void> _templateAction(SettingsService settings, String value) async {
    switch (value) {
      case 'beispiel':
        setState(() {
          _batchCtrl.text = batchPromptExample(_profile(settings),
              direction: _direction(settings));
          _batchEditing = false;
        });
      case 'csv':
        await _importCsv();
      case 'pruefen':
        _checkBatch();
        await _showPlanDialog(settings);
      case 'umschreiben':
        await _rewriteBatch(settings);
      case 'ansehen':
        _batchMode
            ? await _showBatchBriefing(settings)
            : await _showPromptBriefing(settings);
      case 'kopieren':
        _batchMode
            ? await _copyBatchBriefing(settings)
            : await _copyPromptBriefing(settings);
      default:
        if (value.startsWith('stil:')) _appendTemplate(value.substring(5));
    }
  }

  /// Eine Tabelle öffnen und zu Blöcken machen.
  Future<void> _importCsv() async {
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'Tabelle', extensions: ['csv', 'tsv', 'txt']),
      ]);
    } catch (e) {
      _showSnack('Datei konnte nicht geöffnet werden: $e');
      return;
    }
    if (file == null) return;
    try {
      final import = batchTextFromCsv(await file.readAsString());
      if (import.rows == 0) {
        _showSnack(import.summary);
        return;
      }
      setState(() {
        _batchCtrl.text = appendPromptText(_batchCtrl.text, import.text);
        _batchEditing = false;
      });
      _showSnack('${file.name}: ${import.summary}');
    } catch (e) {
      _showSnack('CSV konnte nicht gelesen werden: $e');
    }
  }

  /// Der ganze Prüfbericht – auf Abruf, nicht als Wand.
  Future<void> _showPlanDialog(SettingsService settings) async {
    final plan = _livePlan(settings);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Prüfbericht Massenprompt'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: _buildBatchResult(plan)),
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

  /// Warnungen als Zeilen, nicht als Absätze. Der erste Punkt steht
  /// da, der Rest hinter „Details".
  List<Widget> _buildNotices(SettingsService settings) {
    final notices = <Widget>[];
    if (_batchMode) {
      final plan = _livePlan(settings);
      if (plan.issues.isNotEmpty) {
        final first = plan.issues.first;
        notices.add(NoticeRow(
          tone: NoticeTone.error,
          text: '$first'
              '${plan.issues.length > 1 ? ' (+${plan.issues.length - 1})' : ''}',
          actionLabel: 'Details',
          onAction: () => _showPlanDialog(settings),
        ));
      }
      if (plan.warnings.isNotEmpty) {
        final first = plan.warnings.first;
        notices.add(NoticeRow(
          tone: NoticeTone.warning,
          text: '${first.message}'
              '${plan.warnings.length > 1 ? ' (+${plan.warnings.length - 1})' : ''}',
          actionLabel: 'Details',
          onAction: () => _showPlanDialog(settings),
        ));
      }
      final fehlend = _interruptedItems(settings);
      if (fehlend.isNotEmpty && !_generating) {
        notices.add(NoticeRow(
          tone: NoticeTone.info,
          text: 'Unterbrochener Lauf: ${fehlend.length} '
              '${fehlend.length == 1 ? 'Bild fehlt' : 'Bilder fehlen'} '
              'noch – die App hat beim Schließen aufgehört.',
          actionLabel: 'Nachholen',
          onAction: () {
            context.read<RunQueue>().clearFinished();
            _generateBatch(only: fehlend);
          },
        ));
      }
    } else if (settings.provider.supportsReferences == false &&
        _references.isNotEmpty) {
      notices.add(NoticeRow(
        tone: NoticeTone.warning,
        text: '${settings.provider.shortLabel} nimmt keine Referenzbilder '
            '– die ${_references.length} geladenen bleiben außen vor.',
      ));
    }
    return notices;
  }

  /// Der Knopf und die Kosten – fest unter der Spalte.
  Widget _buildFooter(SettingsService settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = _plannedCount(settings);
    final (costMin, costMax, tier) = imageModelCost(settings);
    final estimate = CostQualityEstimate(
      items: [CostItem('$n Bilder', costMin * n, costMax * n)],
      quality: tier,
      qualityLabel: qualityTierLabels[tier]!,
    );
    final unit = unitCostOf(estimate,
        provider: settings.provider.name,
        label: settings.provider.shortLabel,
        basis: basisOf(settings.provider.name));
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('$n ${n == 1 ? 'Bild' : 'Bilder'} · ',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        MonoText(formatUsdRange(costMin * n, costMax * n),
                            bold: true, color: scheme.onSurface, size: 12.5),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: unit.basis.caveat,
                      child: Text(
                        '${unit.perTenEuroLabel} · Schätzwert, echter '
                        'Abzug nach dem Lauf',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _startButton(settings),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _buildErrorCard(),
          ],
        ],
      ),
    );
  }

  int _plannedCount(SettingsService settings) =>
      _batchMode ? _livePlan(settings).items.length : settings.count;

  Widget _startButton(SettingsService settings, {bool wide = false}) {
    final plan = _batchMode ? _livePlan(settings) : null;
    final n = _plannedCount(settings);
    final label = _generating
        ? (_batchMode ? 'Massenlauf läuft …' : 'Wird generiert …')
        : wide
            ? '$n ${n == 1 ? 'Bild' : 'Bilder'} generieren'
            : 'Lauf starten';
    return FilledButton.icon(
      onPressed: _generating
          ? null
          : _batchMode
              ? (plan!.isValid
                  ? _generateBatch
                  : () => _showPlanDialog(settings))
              : _generate,
      icon: _generating
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow, size: 18),
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: wide ? 16 : 14),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      label: Text(label),
    );
  }

  Widget _buildErrorCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(_error!,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12.5)),
          ),
          IconButton(
            tooltip: 'Ausblenden',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  /// Handy: das Feld unten – Modell, Seitenverhältnis, Stufe, Kosten,
  /// Knopf. Alles Seltene hinter „Mehr Optionen".
  Widget _buildMobilePanel(SettingsService settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (costMin, costMax, tier) = imageModelCost(settings);
    final n = _plannedCount(settings);
    final options = _sizeOptions(settings);
    final current = _sizeValue(settings);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_modelTitle(settings),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                onPressed: _generating ? null : () => _pickModel(settings),
                child: const Text('wechseln ▸'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final option in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_shortSizeLabel(option.$2),
                          style: const TextStyle(fontFamily: 'monospace')),
                      selected: option.$1 == current,
                      showCheckmark: false,
                      onSelected: (_) => _setSize(settings, option.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QualityBars(level: tier, height: 6),
                    const SizedBox(height: 5),
                    Text(qualityTierLabels[tier]!,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.outline)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              MonoText(formatUsdRange(costMin * n, costMax * n),
                  bold: true, size: 15, color: Colors.green.shade700),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _startButton(settings, wide: true),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showProSheet(settings),
              child: const Text('Mehr Optionen'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReferenceSheet(SettingsService settings) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReferenceRow(settings.provider.supportsReferences,
                  onChanged: () => setSheet(() {})),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showTemplateSheet(SettingsService settings) async {
    final profile = _profile(settings);
    final entries = _templateEntries(settings, profile);
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in entries)
              if (entry is PopupMenuItem<String>)
                ListTile(
                  title: entry.child,
                  onTap: () => Navigator.of(context).pop(entry.value),
                )
              else
                const Divider(height: 1),
          ],
        ),
      ),
    );
    if (value != null && mounted) await _templateAction(settings, value);
  }

  Future<void> _showProSheet(SettingsService settings) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => Consumer<SettingsService>(
          builder: (context, settings, _) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text('Profi-Optionen',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._proOptionChildren(settings),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Der Massenprompt: als Tabelle der Blöcke, solange nicht getippt
  /// wird – eine Zeile je Asset, Name und Prompt –, und als Editor,
  /// sobald man hineinklickt. Beides ist derselbe Text.
  Widget _buildBatchCard(SettingsService settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plan = _livePlan(settings);
    final showTable = !_batchEditing && plan.items.isNotEmpty;
    return DropTarget(
      enable: !_generating &&
          widget.isActive &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      onDragEntered: (_) => setState(() => _dragOverPrompt = true),
      onDragExited: (_) => setState(() => _dragOverPrompt = false),
      onDragDone: (detail) => _dropPromptFiles(detail.files, _batchCtrl),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _dragOverPrompt ? scheme.primary : scheme.outlineVariant,
              width: _dragOverPrompt ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: showTable
            ? Column(
                children: [
                  for (var i = 0; i < math.min(plan.items.length, 12); i++)
                    _blockRow(
                      number: (i + 1).toString().padLeft(2, '0'),
                      name: plan.items[i].name,
                      prompt: plan.items[i].prompt,
                      onTap: _generating
                          ? null
                          : () => setState(() => _batchEditing = true),
                    ),
                  if (plan.items.length > 12)
                    _blockRow(
                      number: '…',
                      name: '',
                      prompt: '+ ${plan.items.length - 12} weitere Blöcke',
                      onTap: () => setState(() => _batchEditing = true),
                      dim: true,
                    ),
                  _blockRow(
                    number: '+',
                    name: '',
                    prompt: 'Neuer Block — Name · Prompt, eine Zeile pro '
                        'Asset',
                    dim: true,
                    onTap: _generating
                        ? null
                        : () {
                            final text = _batchCtrl.text.trimRight();
                            setState(() {
                              _batchCtrl.text =
                                  '$text\n---\nNAME: \nPROMPT: ';
                              _batchCtrl.selection = TextSelection.collapsed(
                                  offset: _batchCtrl.text.length);
                              _batchEditing = true;
                            });
                          },
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_dragOverPrompt)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Text-, Markdown- oder CSV-Datei hier ablegen.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                    TextField(
                      controller: _batchCtrl,
                      minLines: 6,
                      maxLines: 16,
                      enabled: !_generating,
                      autofocus: plan.items.isNotEmpty,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'NAME: burg-01\n'
                            'PROMPT: A medieval castle at night …\n'
                            '---\n'
                            'NAME: burg-02\n'
                            'PROMPT: The same castle at noon …',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: 'Jeder Block: NAME: und PROMPT:, '
                                'dazu NEGATIV: und REFERENZ: nach Bedarf. '
                                '„---" oder ein neues NAME: trennt.\n'
                                'Die Vorlage ist auf '
                                '${_profile(settings).modelLabel} '
                                'zugeschnitten: ${_profile(settings).summary}',
                            child: MonoText(
                                'NAME: · PROMPT: · NEGATIV: · --- trennt',
                                size: 10.5),
                          ),
                        ),
                        if (plan.items.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setState(() => _batchEditing = false),
                            child: const Text('Als Tabelle'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _blockRow({
    required String number,
    required String name,
    required String prompt,
    VoidCallback? onTap,
    bool dim = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: dim ? scheme.surfaceContainerLow : null,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 11),
              color: scheme.surfaceContainerLow,
              child: Center(
                child: MonoText(number,
                    size: 11, bold: !dim, color: scheme.outline),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5,
                        color: dim ? scheme.outline : scheme.onSurface),
                    children: [
                      if (name.isNotEmpty) ...[
                        TextSpan(
                          text: name,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              color: scheme.primary),
                        ),
                        const TextSpan(text: ' · '),
                      ],
                      TextSpan(text: prompt),
                    ],
                  ),
                ),
              ),
            ),
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

  /// Die Liste der Ausfälle und Anmerkungen – auf Abruf.
  Future<void> _showRunNotes() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bilanz des Laufs'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_batchFailures.isNotEmpty) ...[
                  Text('Nicht geklappt (${_batchFailures.length}):',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.error)),
                  for (final failure in _batchFailures)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText('• $failure'),
                    ),
                  const SizedBox(height: 12),
                ],
                if (_batchNotes.isNotEmpty) ...[
                  Text('Anmerkungen des Servers (${_batchNotes.length}):',
                      style: Theme.of(context).textTheme.labelLarge),
                  for (final note in _batchNotes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText('• $note'),
                    ),
                ],
                if (_batchDone > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Alle fertigen Bilder liegen unter ihrem Namen in '
                      'der Galerie.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (!_batchRunning && _batchFailedItems.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).pop();
                _retryFailedBatch();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_batchFailedItems.length == 1
                  ? 'Das eine Bild wiederholen'
                  : '${_batchFailedItems.length} Bilder wiederholen'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
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
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Prompt',
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
            const SizedBox(height: 8),
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
      // Eine Tabelle wird erst zu Blöcken – aber nur im Massenprompt;
      // im Einzelbild wäre eine CSV nur Text mit Semikolons.
      if (identical(target, _batchCtrl) && isCsvFile(file.name)) {
        try {
          final import = batchTextFromCsv(await file.readAsString());
          if (import.rows > 0) {
            text = appendPromptText(text, import.text);
            accepted.add('${file.name} (${import.summary})');
          } else {
            rejected.add('${file.name} – ${import.summary}');
          }
        } catch (e) {
          rejected.add('${file.name} ($e)');
        }
        continue;
      }
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

  /// „REFERENZBILDER 1 / 16 … + Hinzufügen", darunter die Kacheln.
  Widget _buildReferenceRow(bool supportsReferences,
      {VoidCallback? onChanged}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void changed() {
      if (mounted) setState(() {});
      onChanged?.call();
    }

    return DropTarget(
      enable: supportsReferences &&
          !_generating &&
          widget.isActive &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      onDragEntered: (_) => setState(() => _dragOverReferences = true),
      onDragExited: (_) => setState(() => _dragOverReferences = false),
      onDragDone: (detail) async {
        await _addDroppedReferences(detail.files);
        changed();
      },
      child: Container(
        padding: _dragOverReferences ? const EdgeInsets.all(6) : EdgeInsets.zero,
        decoration: _dragOverReferences
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary, width: 2))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const MonoLabel('Referenzbilder'),
                const SizedBox(width: 8),
                MonoText('${_references.length} / $_maxReferences', size: 11),
                const Spacer(),
                if (supportsReferences)
                  TextButton(
                    onPressed: _generating
                        ? null
                        : () async {
                            await _pickReferences();
                            changed();
                          },
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('+ Hinzufügen'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (!supportsReferences)
              Text(
                'Referenzbilder nehmen OpenAI und Gemini – oben bei '
                '„KI-Modell" eines davon wählen.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.outline),
              )
            else
              SizedBox(
                height: 78,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _references.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 9),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.memory(
                                _references[i].bytes,
                                width: 78,
                                height: 78,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: InkWell(
                                onTap: _generating
                                    ? null
                                    : () {
                                        _references.removeAt(i);
                                        changed();
                                      },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
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
                    Tooltip(
                      message: 'Bild als Vorlage hinzufügen – oder per '
                          'Drag & Drop hierher ziehen',
                      child: Material(
                        color: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _generating
                              ? null
                              : () async {
                                  await _pickReferences();
                                  changed();
                                },
                          child: SizedBox(
                            width: 78,
                            height: 78,
                            child: Icon(Icons.add,
                                size: 22, color: scheme.outline),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Die vier Karten
  // ----------------------------------------------------------------

  List<Option> _sizeOptions(SettingsService settings) =>
      switch (settings.provider) {
        GenProvider.openai => openAiSizeOptions,
        GenProvider.stability || GenProvider.selfhost => stabilityAspectOptions,
        GenProvider.gemini => geminiAspectOptions,
      };

  String _sizeValue(SettingsService settings) => switch (settings.provider) {
        GenProvider.openai => settings.openAiSize,
        GenProvider.stability || GenProvider.selfhost => settings.stabilityAspect,
        GenProvider.gemini => settings.geminiAspect,
      };

  void _setSize(SettingsService settings, String value) {
    switch (settings.provider) {
      case GenProvider.openai:
        settings.setOpenAiSize(value);
      case GenProvider.stability:
      case GenProvider.selfhost:
        settings.setStabilityAspect(value);
      case GenProvider.gemini:
        settings.setGeminiAspect(value);
    }
  }

  /// „Quadrat (1:1)" → „1:1" für die Chips auf dem Handy.
  String _shortSizeLabel(String label) {
    final m = RegExp(r'\(([^)]+)\)').firstMatch(label);
    return m?.group(1) ?? label;
  }

  ImageModelChoice? _currentChoice(SettingsService settings) {
    final key = '${settings.provider.name}/${settings.modelFor(settings.provider)}';
    for (final choice in allImageModels(settings.fetchedModelsFor)) {
      if (choice.key == key) return choice;
    }
    return null;
  }

  /// „Gemini · Nano Banana" – Anbieter und der Name ohne Klammer.
  String _modelTitle(SettingsService settings) {
    final choice = _currentChoice(settings);
    final name = choice?.label.split(' (').first ??
        settings.modelFor(settings.provider);
    return '${settings.provider.shortLabel} · $name';
  }

  Widget _buildOptionGrid(SettingsService settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = settings.provider;
    final (costMin, costMax, tier) = imageModelCost(settings);
    final hasKey = settings.hasApiKeyFor(provider);
    final sizeLabel = _sizeOptionLabel(
        settings,
        _sizeOptions(settings).firstWhere((o) => o.$1 == _sizeValue(settings),
            orElse: () => (_sizeValue(settings), _sizeValue(settings))));
    final sizeParts = sizeLabel.split(' · ');
    final sizeValue = sizeParts.first
        .replaceAllMapped(RegExp(r'\((\d+[:×x]\d+)\)'), (m) => m.group(1)!);
    final sizeSub = [
      if (sizeParts.length > 1) sizeParts.sublist(1).join(' · '),
      if (provider == GenProvider.gemini && settings.geminiModel.contains('pro'))
        settings.geminiImageSize,
      if (provider != GenProvider.gemini) settings.outputFormat.toUpperCase(),
    ].join(' · ');

    final cards = <Widget>[
      OptionCard(
        label: 'KI-Modell',
        value: Text(_modelTitle(settings),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        sub: Row(
          children: [
            Badge2(
              provider.isLocal
                  ? '0 \$'
                  : hasKey
                      ? 'Schlüssel ✓'
                      : 'kein Schlüssel',
              tone: provider.isLocal
                  ? BadgeTone.good
                  : hasKey
                      ? BadgeTone.good
                      : BadgeTone.warn,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text('${formatUsdRange(costMin, costMax)} / Bild',
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        onTap: _generating ? null : () => _pickModel(settings),
      ),
      OptionCard(
        label: 'Format',
        value: Text(sizeValue, maxLines: 1, overflow: TextOverflow.ellipsis),
        sub: Text(sizeSub.isEmpty ? ' ' : sizeSub,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: _generating ? null : () => _pickFormat(settings),
      ),
      OptionCard(
        label: _batchMode ? 'Anzahl je Block' : 'Anzahl',
        value: CountPicker(
          value: _batchMode ? 1 : settings.count,
          onChanged: _batchMode || _generating ? null : settings.setCount,
        ),
        sub: Text(_batchMode
            ? 'je Block genau ein Bild'
            : settings.count > 1
                ? 'Varianten desselben Prompts'
                : ' '),
        trailing: Tooltip(
          message: _batchMode
              ? 'Im Massenprompt entsteht zu jedem Block genau ein Bild – '
                  'sonst passten Name und Ergebnis nicht mehr zusammen.'
              : 'Es sind immer verschiedene Varianten desselben Prompts: '
                  'OpenAI und Gemini würfeln je Bild neu, bei Stability und '
                  'der eigenen GPU zählt der Seed pro Bild hoch.',
          child: Icon(Icons.info_outline, size: 15, color: scheme.outline),
        ),
      ),
      OptionCard(
        label: 'Qualitätsstufe',
        value: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            QualityBars(level: tier),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: Text(qualityTierLabels[tier]!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                MonoText('$tier/5', size: 11),
              ],
            ),
          ],
        ),
        onTap: _generating ? null : () => _pickQuality(settings),
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 380) {
        return Column(
          children: [
            for (final card in cards) ...[card, const SizedBox(height: 12)],
          ],
        );
      }
      return Column(
        children: [
          for (var row = 0; row < 2; row++) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[row * 2]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[row * 2 + 1]),
                ],
              ),
            ),
            if (row == 0) const SizedBox(height: 12),
          ],
        ],
      );
    });
  }

  /// Die Modellwahl: alle Modelle aller Anbieter in einer Liste.
  Future<void> _pickModel(SettingsService settings) async {
    final allModels = allImageModels(settings.fetchedModelsFor);
    final currentKey =
        '${settings.provider.name}/${settings.modelFor(settings.provider)}';
    await showDialog<void>(
      context: context,
      builder: (context) => Consumer<SettingsService>(
        builder: (context, settings, _) => AlertDialog(
          title: const Text('KI-Modell'),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          content: SizedBox(
            width: 520,
            height: 460,
            child: Column(
              children: [
                Expanded(
                  child: RadioGroup<String>(
                    groupValue: currentKey,
                    onChanged: (value) {
                      final parsed =
                          value == null ? null : ImageModelChoice.parseKey(value);
                      if (parsed != null) {
                        // Ein Klick setzt Anbieter und Modell.
                        settings.setProvider(parsed.$1);
                        settings.setModelFor(parsed.$1, parsed.$2);
                      }
                      Navigator.of(context).pop();
                    },
                    child: ListView(
                      children: [
                        for (final choice in allModels)
                          RadioListTile<String>(
                            value: choice.key,
                            dense: true,
                            title: Text(choice.fullLabel),
                            secondary: settings.hasApiKeyFor(choice.provider)
                                ? null
                                : Tooltip(
                                    message: 'Kein Schlüssel hinterlegt – '
                                        'die App fragt beim Generieren '
                                        'danach.',
                                    child: Icon(Icons.key_off,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline)),
                          ),
                        if (!allModels.any((c) => c.key == currentKey))
                          RadioListTile<String>(
                            value: currentKey,
                            dense: true,
                            title: Text('${settings.provider.shortLabel} · '
                                '${settings.modelFor(settings.provider)} '
                                '(eigene ID)'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_localModelNote(settings) case final note?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(note,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: _refreshingModels
                  ? null
                  : () async {
                      await _refreshModels();
                    },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Aktuelle Modelle laden'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen'),
            ),
          ],
        ),
      ),
    );
  }

  /// Seitenverhältnis bzw. Bildgröße, dazu Auflösung (Nano Banana
  /// Pro) und Dateiformat.
  Future<void> _pickFormat(SettingsService settings) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Consumer<SettingsService>(
        builder: (context, settings, _) {
          final isOpenAi = settings.provider == GenProvider.openai;
          final isGemini = settings.provider == GenProvider.gemini;
          final options = _sizeOptions(settings);
          final current = _sizeValue(settings);
          return AlertDialog(
            title: Text(isOpenAi ? 'Bildgröße' : 'Seitenverhältnis'),
            contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioGroup<String>(
                      groupValue: current,
                      onChanged: (value) {
                        if (value != null) _setSize(settings, value);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final option in options)
                            RadioListTile<String>(
                              value: option.$1,
                              dense: true,
                              title: Text(_sizeOptionLabel(settings, option)),
                            ),
                        ],
                      ),
                    ),
                    if (isGemini && settings.geminiModel.contains('pro'))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const MonoLabel('Auflösung'),
                            const SizedBox(height: 6),
                            SegmentedButton<String>(
                              segments: [
                                for (final option in geminiImageSizeOptions)
                                  ButtonSegment(
                                      value: option.$1,
                                      label: Text(option.$2)),
                              ],
                              selected: {settings.geminiImageSize},
                              onSelectionChanged: (s) =>
                                  settings.setGeminiImageSize(s.first),
                            ),
                          ],
                        ),
                      ),
                    if (!isGemini)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const MonoLabel('Dateiformat'),
                            const SizedBox(height: 6),
                            SegmentedButton<String>(
                              segments: [
                                for (final option in formatOptions)
                                  ButtonSegment(
                                      value: option.$1,
                                      label: Text(option.$2)),
                              ],
                              selected: {settings.outputFormat},
                              onSelectionChanged: (s) =>
                                  settings.setOutputFormat(s.first),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fertig'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Die Stufe: bei OpenAI die eigene Qualitätswahl, auf der eigenen
  /// GPU die vier Stufen mit Detail-Durchgang, sonst hängt sie am
  /// Modell – und das steht dann auch da.
  Future<void> _pickQuality(SettingsService settings) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Consumer<SettingsService>(
        builder: (context, settings, _) {
          final (_, _, tier) = imageModelCost(settings);
          final isOpenAi = settings.provider == GenProvider.openai;
          return AlertDialog(
            title: const Text('Qualitätsstufe'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QualityBars(level: tier),
                    const SizedBox(height: 6),
                    Text('${qualityTierLabels[tier]} · $tier/5',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    if (isOpenAi) ...[
                      const MonoLabel('OpenAI-Qualität'),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: [
                          for (final option in qualityOptions)
                            ButtonSegment(
                                value: option.$1, label: Text(option.$2)),
                        ],
                        selected: {settings.quality},
                        onSelectionChanged: (s) => settings.setQuality(s.first),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Transparenter Hintergrund'),
                        subtitle: const Text(
                            'Für Logos und Icons – braucht PNG oder WebP'),
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
                    ] else if (settings.provider == GenProvider.selfhost)
                      _qualityPanel(settings)
                    else
                      Text(
                        'Die Stufe hängt am Modell: ${_modelTitle(settings)} '
                        'liefert immer dieselbe Qualität. Eine andere Stufe '
                        'heißt ein anderes Modell – bei „KI-Modell" wählen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fertig'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// „Profi-Optionen  Negativ-Prompt, Seed, Blickrichtung ▾"
  Widget _buildProOptions(SettingsService settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _proOpen = !_proOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              child: Row(
                children: [
                  Text('Profi-Optionen',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Negativ-Prompt, Blickrichtung, Seed, Format',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(_proOpen ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: scheme.outline),
                ],
              ),
            ),
          ),
          if (_proOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _proOptionChildren(settings),
              ),
            ),
        ],
      ),
    );
  }

  /// Der Inhalt der Profi-Optionen – am Desktop aufgeklappt, auf dem
  /// Handy im Bottom-Sheet.
  ///
  /// Felder, die das gewählte Modell nicht braucht, sind **ausgegraut,
  /// nicht versteckt**: Wer den Seed sucht, sieht ihn – und liest, dass
  /// er hier keine Wirkung hat und bei welchem Modell er eine hätte.
  List<Widget> _proOptionChildren(SettingsService settings) {
    final provider = settings.provider;
    final isStability = provider == GenProvider.stability;
    final profile = _profile(settings);
    final negativeWorks =
        profile.negativeHandling != NegativeHandling.ignored;
    final seedWorks = isStability || provider.isLocal;
    final styleWorks = isStability && settings.stabilityModel == 'core';
    return [
      TextField(
        controller: _negativeCtrl,
        enabled: negativeWorks,
        decoration: InputDecoration(
          labelText: 'Negativ-Prompt',
          hintText: 'Was im Bild vermieden werden soll …',
          border: const OutlineInputBorder(),
          helperText: profile.negativeNote,
          helperMaxLines: 3,
          isDense: true,
        ),
      ),
      _buildViewDirection(settings),
      const SizedBox(height: 12),
      DropdownMenu<String>(
        initialSelection: settings.stylePreset,
        enabled: styleWorks,
        label: const Text('Style-Preset'),
        helperText: styleWorks
            ? null
            : 'Nur Stability Core kennt Style-Presets.',
        expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          for (final option in stylePresetOptions)
            DropdownMenuEntry(value: option.$1, label: option.$2),
        ],
        onSelected: (value) {
          if (value != null) settings.setStylePreset(value);
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _seedCtrl,
        enabled: seedWorks,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Seed (0 = zufällig)',
          helperText: seedWorks
              ? 'Gleicher Seed + gleicher Prompt = reproduzierbares '
                  'Bild; bei mehreren Bildern zählt er pro Bild hoch'
              : '${provider.shortLabel} nimmt keinen Seed entgegen – '
                  'jedes Bild wird neu gewürfelt. Seeds gibt es bei '
                  'Stability und der eigenen GPU.',
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
      if (provider == GenProvider.selfhost) ...[
        const SizedBox(height: 12),
        _qualityPanel(settings),
      ],
      const SizedBox(height: 8),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.savings_outlined, size: 20),
        title: const Text('Kosten je Bild im Vergleich',
            style: TextStyle(fontSize: 13.5)),
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
    ];
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

  /// Die rechte Spalte.
  Widget _buildResultsPane(SettingsService settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildResultsHeader(settings),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: _buildResultsGrid(settings, shrinkWrap: false),
          ),
        ),
      ],
    );
  }

  /// „Ergebnisse  2 / 3 fertig … Schnitt 11 s je Bild · Alle
  /// herunterladen" – und darunter, nur wenn es sie gibt, die Zeilen
  /// zu Ausfällen und Anmerkungen.
  List<Widget> _buildResultsHeader(SettingsService settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final average = _batchAverage;
    final remaining = average == null || !_batchRunning
        ? null
        : average * (_batchTotal - _batchDone);
    final elapsed = _batchStart == null || !_batchRunning
        ? null
        : DateTime.now().difference(_batchStart!);
    return [
      Row(
        children: [
          Text('Ergebnisse',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          if (_batchTotal > 0)
            Badge2('$_batchDone / $_batchTotal fertig',
                tone: _batchRunning ? BadgeTone.primary : BadgeTone.good)
          else if (_results.isNotEmpty)
            Badge2('${_results.length} fertig', tone: BadgeTone.good),
          const Spacer(),
          if (average != null || elapsed != null)
            Flexible(
              child: MonoText(
                [
                  if (elapsed != null) 'Vergangen ${_formatDuration(elapsed)}',
                  if (average != null)
                    'Schnitt ${_formatDuration(average)} je Bild',
                  if (remaining != null && remaining > Duration.zero)
                    'Rest ca. ${_formatDuration(remaining)}',
                ].join(' · '),
              ),
            ),
          if (_batchRunning) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _batchCancel
                  ? null
                  : () {
                      setState(() => _batchCancel = true);
                      context.read<RunQueue>().cancelWaiting();
                    },
              child: Text(_batchCancel ? 'Bricht ab …' : 'Abbrechen'),
            ),
          ] else if (_results.isNotEmpty) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _generating ? null : () => _downloadAll(settings),
              child: const Text('Alle herunterladen'),
            ),
          ],
        ],
      ),
      if (_usageInfo != null && !_generating)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: MonoText(_usageInfo!, size: 11),
        ),
      if (_batchFailures.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: NoticeRow(
            tone: NoticeTone.error,
            text: '${_batchFailures.length} nicht geklappt: '
                '${_batchFailures.first}'
                '${_batchFailures.length > 1 ? ' (+${_batchFailures.length - 1})' : ''}',
            actionLabel: !_batchRunning && _batchFailedItems.isNotEmpty
                ? 'Wiederholen'
                : 'Details',
            onAction: !_batchRunning && _batchFailedItems.isNotEmpty
                ? _retryFailedBatch
                : _showRunNotes,
          ),
        ),
      if (_batchNotes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: NoticeRow(
            tone: NoticeTone.info,
            text: 'Anmerkung: ${_batchNotes.first}'
                '${_batchNotes.length > 1 ? ' (+${_batchNotes.length - 1})' : ''}',
            actionLabel: 'Details',
            onAction: _showRunNotes,
          ),
        ),
      if (!_generating && _batchTotal > 0 && _batchDone > 0 &&
          _batchFailures.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Alle fertigen Bilder liegen unter ihrem Namen in der '
            'Galerie'
            '${settings.currentProject.isEmpty ? '' : ', Projekt „${projectName(settings.currentProject)}"'}.',
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          ),
        ),
    ];
  }

  Future<void> _downloadAll(SettingsService settings) async {
    final files = <({Uint8List bytes, String fileName, String mimeType})>[
      for (var i = 0; i < _results.length; i++)
        (
          bytes: _results[i].bytes,
          fileName:
              '${i < _resultMeta.length && _resultMeta[i].name.isNotEmpty ? _resultMeta[i].name : 'bild_${i + 1}'}'
              '.${_results[i].fileExtension}',
          mimeType: _results[i].mimeType,
        ),
    ];
    try {
      final r = await exportManyBytes(files,
          suggestedFolderName: settings.currentProject.isEmpty
              ? 'bilder'
              : projectName(settings.currentProject));
      if (r != null && mounted) _showSnack(r.message);
    } catch (e) {
      if (mounted) _showSnack('Export fehlgeschlagen: $e');
    }
  }

  /// Die laufende Karte: Wer zeichnet, wie lange schon – und ob es
  /// eine Vorschau geben kann.
  Widget _runningCard(SettingsService settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final local = settings.provider.isLocal;
    final elapsed = _runStart == null
        ? Duration.zero
        : DateTime.now().difference(_runStart!);
    final hasSteps = _previewTotal > 0 && _previewStep > 0;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: GenerationProgress(
              compact: true,
              motif: _motif(settings),
              preview: _preview,
              step: _previewStep,
              totalSteps: _previewTotal,
              elapsed: elapsed,
              aspect: 1,
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurface),
                      children: [
                        TextSpan(
                            text: _batchCurrent.isEmpty
                                ? 'Bild entsteht'
                                : _batchCurrent),
                        TextSpan(
                          text: ' · ${_formatDuration(elapsed)}',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w400,
                              color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
                ),
                Tooltip(
                  message: local
                      ? _preview == null
                          ? 'Die Vorschau erscheint nach den ersten '
                              'Schritten. Bei SD 3.5 und FLUX gibt es '
                              'keine – die packen ihre Zwischenstände '
                              'anders.'
                          : 'Grobe Vorschau aus den Latents – Form und '
                              'Farben stimmen, Details noch nicht.'
                      : '${settings.provider.label} liefert keine '
                          'Zwischenstände; das Bild kommt am Stück. Je nach '
                          'Qualität 10–60 Sekunden.',
                  child: MonoText(
                    hasSteps
                        ? 'Schritt $_previewStep/$_previewTotal'
                        : local
                            ? 'Vorschau folgt'
                            : 'keine Vorschau möglich',
                    size: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsGrid(SettingsService settings,
      {required bool shrinkWrap}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tiles = <Widget>[
      for (var i = 0; i < _results.length; i++) _resultCard(i),
      if (_generating) _runningCard(settings),
      for (final name in _batchPending) _queuedCard(name),
    ];
    if (tiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined,
                  size: 64, color: scheme.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'Noch keine Ergebnisse.\nBeschreibung eingeben und '
                '„Lauf starten“ antippen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.86,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, index) => tiles[index],
    );
  }

  Widget _resultCard(int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final image = _results[index];
    final meta = index < _resultMeta.length ? _resultMeta[index] : null;
    final costText = meta == null
        ? ''
        : formatUsdRange(meta.costMinUsd, meta.costUsd)
            .replaceFirst('≈ ', '');
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                InkWell(
                  onTap: () => _openDetail(image, index),
                  child: CheckerboardImage(bytes: image.bytes, fit: BoxFit.cover),
                ),
                if (meta != null && meta.name.isNotEmpty)
                  Positioned(
                    top: 9,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(meta.name,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87)),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: MonoText(
                    meta == null
                        ? ''
                        : '${_formatDuration(meta.elapsed)}'
                            '${costText.isEmpty ? '' : ' · $costText'}',
                    size: 11,
                  ),
                ),
                IconButton(
                  tooltip: 'Vergrößern',
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_full),
                  onPressed: () => _openDetail(image, index),
                ),
                IconButton(
                  tooltip: 'Speichern / Teilen',
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _exportResult(image, index),
                ),
                Tooltip(
                  message: 'Als Vorderansicht in den 3D-Tab',
                  child: Material(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(7),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(7),
                      onTap: () => _sendToThreeD(image, index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        child: Text('→ 3D',
                            style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer)),
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mehr',
                  iconSize: 17,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'ref') _useAsReference(image);
                    if (value == 'pdf') _exportProvenance(image);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'ref', child: Text('Als Referenzbild')),
                    PopupMenuItem(
                        value: 'pdf', child: Text('Erstellungsnachweis (PDF)')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// „→ 3D": das Bild wird zur Vorderansicht im 3D-Tab.
  void _sendToThreeD(GeneratedImage image, int index) {
    final meta = index < _resultMeta.length ? _resultMeta[index] : null;
    final name = meta != null && meta.name.isNotEmpty
        ? meta.name
        : 'bild_${index + 1}';
    context.read<ImageRelay>().send(
          bytes: image.bytes,
          name: '$name.${image.fileExtension}',
          prompt: _lastRequest?.prompt ?? _promptCtrl.text,
        );
  }

  Widget _queuedCard(String name) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MonoText('in Warteschlange', size: 11),
              const SizedBox(height: 4),
              MonoText(name, size: 11, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Was an einer Ergebniskarte steht: Name, Dauer, Kosten.
class _ResultMeta {
  const _ResultMeta({
    required this.name,
    required this.elapsed,
    required this.costUsd,
    required this.costMinUsd,
  });

  final String name;
  final Duration elapsed;
  final double costUsd;
  final double costMinUsd;
}
