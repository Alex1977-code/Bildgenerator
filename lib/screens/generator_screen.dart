import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
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
    _promptCtrl.dispose();
    _negativeCtrl.dispose();
    _seedCtrl.dispose();
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

    final isOpenAi = settings.provider == GenProvider.openai;
    final request = GenerationRequest(
      provider: settings.provider,
      prompt: prompt,
      negativePrompt: _negativeCtrl.text,
      references: settings.provider.supportsReferences
          ? List.of(_references)
          : const [],
      openAiSize: settings.openAiSize,
      stabilityAspect: settings.stabilityAspect,
      quality: settings.quality,
      transparent: isOpenAi && settings.transparent,
      outputFormat: settings.outputFormat,
      compression: settings.compression,
      count: settings.count,
      seed: int.tryParse(_seedCtrl.text.trim()) ?? 0,
      stylePreset: settings.stylePreset,
      model: settings.modelFor(settings.provider),
      geminiAspect: settings.geminiAspect,
      geminiImageSize: settings.geminiImageSize,
    );

    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final generator = ImageGenerator.forProvider(settings.provider);
      final result = await generator.generate(request, apiKey.trim());
      var images = result.images;
      final logo = settings.watermarkLogo;
      final watermarked = settings.watermarkEnabled && logo != null;
      if (watermarked) {
        images = [
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
      final usageParts = <String>[
        if (result.totalTokens != null)
          'Verbrauch: ${result.totalTokens} Tokens',
        if (result.creditsRemaining != null)
          'Restguthaben: ${result.creditsRemaining!.toStringAsFixed(1)} '
              'Credits',
      ];
      await history.addResults(request, images, extraParams: {
        if (result.totalTokens != null) 'Tokens': '${result.totalTokens}',
        if (watermarked) 'Wasserzeichen': 'ja',
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
    return [
      _buildPromptCard(),
      const SizedBox(height: 12),
      _buildReferenceCard(settings.provider.supportsReferences),
      const SizedBox(height: 12),
      _buildOptionsCard(settings),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _generating ? null : _generate,
        icon: _generating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            _generating
                ? 'Wird generiert …'
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
              onSelectionChanged: (selection) =>
                  settings.setCount(selection.first),
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
                  helperText:
                      'Gleicher Seed + gleicher Prompt = reproduzierbares Bild',
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
      if (_generating) ...[
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
