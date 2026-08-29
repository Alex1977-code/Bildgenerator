import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/exporter.dart';
import '../services/generators.dart';
import '../services/history_service.dart';
import '../services/prompt_relay.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import 'image_detail_screen.dart';

/// Hauptbildschirm: Prompt, Referenzbilder, Optionen und Ergebnisse.
class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

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
        title: const Text('API-Schlüssel fehlt'),
        content: Text(
          'Für „${provider.label}“ ist noch kein API-Schlüssel hinterlegt. '
          'Bitte in den Einstellungen einen Schlüssel eintragen.',
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
      final usageParts = <String>[
        if (result.totalTokens != null)
          'Verbrauch: ${result.totalTokens} Tokens',
        if (result.creditsRemaining != null)
          'Restguthaben: ${result.creditsRemaining!.toStringAsFixed(1)} '
              'Credits',
      ];
      await history.addResults(request, result.images, extraParams: {
        if (result.totalTokens != null) 'Tokens': '${result.totalTokens}',
      });
      if (!mounted) return;
      setState(() {
        _results = result.images;
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
      Row(
        children: [
          Expanded(
            child: Text(
              'Provider: ${settings.provider.label}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: widget.onOpenSettings,
            child: const Text('Ändern'),
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
    return Card(
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
                'Referenzbilder werden von den Providern OpenAI und '
                'Google Gemini unterstützt. Provider in den Einstellungen '
                'wechseln, um sie zu nutzen.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (_references.isEmpty)
              Text(
                'Optional: Bilder als Vorlage hinzufügen (z. B. Produkt, '
                'Person, Stil). Das Ergebnis orientiert sich an ihnen.',
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
    );
  }

  Widget _buildOptionsCard(SettingsService settings) {
    final provider = settings.provider;
    final isOpenAi = provider == GenProvider.openai;
    final isStability = provider == GenProvider.stability;
    final isGemini = provider == GenProvider.gemini;
    final sizeOptions = switch (provider) {
      GenProvider.openai => openAiSizeOptions,
      GenProvider.stability => stabilityAspectOptions,
      GenProvider.gemini => geminiAspectOptions,
    };
    final sizeValue = switch (provider) {
      GenProvider.openai => settings.openAiSize,
      GenProvider.stability => settings.stabilityAspect,
      GenProvider.gemini => settings.geminiAspect,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Format & Größe'),
            DropdownMenu<String>(
              key: ValueKey('size-${provider.name}-${settings.stabilityModel}'
                  '-${settings.geminiModel}-${settings.geminiImageSize}'),
              initialSelection: sizeValue,
              label: Text(isOpenAi ? 'Bildgröße' : 'Seitenverhältnis'),
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
                    settings.setStabilityAspect(value);
                  case GenProvider.gemini:
                    settings.setGeminiAspect(value);
                }
              },
            ),
            if (isGemini && settings.geminiModel.contains('pro')) ...[
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
                  if (value != null) settings.setGeminiImageSize(value);
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
                      ButtonSegment(value: option.$1, label: Text(option.$2)),
                  ],
                  selected: {settings.outputFormat},
                  onSelectionChanged: (selection) =>
                      settings.setOutputFormat(selection.first),
                ),
              ),
            ],
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
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
