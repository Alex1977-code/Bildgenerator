import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/settings_service.dart';

/// Einstellungen: Provider, API-Schlüssel, Design.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link konnte nicht geöffnet werden: $url')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link konnte nicht geöffnet werden: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bild-Provider', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Der Provider erzeugt die Bilder. Dafür wird ein eigener '
                  'API-Schlüssel benötigt (nutzungsbasierte Kosten beim '
                  'jeweiligen Anbieter).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<GenProvider>(
                    segments: const [
                      ButtonSegment(
                        value: GenProvider.openai,
                        label: Text('OpenAI'),
                      ),
                      ButtonSegment(
                        value: GenProvider.stability,
                        label: Text('Stability AI'),
                      ),
                      ButtonSegment(
                        value: GenProvider.gemini,
                        label: Text('Gemini'),
                      ),
                    ],
                    selected: {settings.provider},
                    onSelectionChanged: (selection) =>
                        settings.setProvider(selection.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (settings.provider) {
                    GenProvider.openai =>
                      'OpenAI GPT Image: Referenzbilder, Qualitätsstufen, '
                          'transparenter Hintergrund, PNG/JPEG/WebP.',
                    GenProvider.stability =>
                      'Stability AI Stable Image: Seitenverhältnisse, '
                          'Negativ-Prompt, Seed und Style-Presets.',
                    GenProvider.gemini =>
                      'Google Gemini („Nano Banana“): Referenzbilder, '
                          'Seitenverhältnisse, bis 4K (Pro). API-Schlüssel '
                          'mit kostenlosem Kontingent.',
                  },
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ModelCard(
          key: ValueKey('model-${settings.provider.name}'),
          provider: settings.provider,
          currentModel: settings.modelFor(settings.provider),
          knownModels: switch (settings.provider) {
            GenProvider.openai => openAiModelOptions,
            GenProvider.stability => stabilityModelOptions,
            GenProvider.gemini => geminiModelOptions,
          },
          onChanged: (value) =>
              settings.setModelFor(settings.provider, value),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'OpenAI-API-Schlüssel',
          provider: GenProvider.openai,
          hasKey: settings.hasApiKeyFor(GenProvider.openai),
          helpLabel: 'Schlüssel erstellen auf platform.openai.com',
          onHelp: () => _openUrl('https://platform.openai.com/api-keys'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Stability-AI-API-Schlüssel',
          provider: GenProvider.stability,
          hasKey: settings.hasApiKeyFor(GenProvider.stability),
          helpLabel: 'Schlüssel erstellen auf platform.stability.ai',
          onHelp: () => _openUrl('https://platform.stability.ai/account/keys'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Gemini-API-Schlüssel (Google)',
          provider: GenProvider.gemini,
          hasKey: settings.hasApiKeyFor(GenProvider.gemini),
          helpLabel: 'Schlüssel erstellen auf aistudio.google.com (gratis)',
          onHelp: () => _openUrl('https://aistudio.google.com/apikey'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Design', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) =>
                      settings.setThemeMode(selection.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Über die App', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Bildgenerator erstellt Bilder aus Textbeschreibungen – '
                  'wahlweise mit Referenzbildern, einstellbarer Größe, '
                  'Qualität und transparentem Hintergrund.\n\n'
                  'API-Schlüssel werden ausschließlich lokal und '
                  'verschlüsselt auf diesem Gerät gespeichert und nur an '
                  'den jeweils gewählten Provider übertragen.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ApiKeyCard extends StatefulWidget {
  const _ApiKeyCard({
    required this.title,
    required this.provider,
    required this.hasKey,
    required this.helpLabel,
    required this.onHelp,
  });

  final String title;
  final GenProvider provider;
  final bool hasKey;
  final String helpLabel;
  final VoidCallback onHelp;

  @override
  State<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends State<_ApiKeyCard> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Expliziter Einfügen-Knopf: Safari (iOS) zeigt bei verdeckten
  /// Feldern oft kein „Einsetzen“-Menü an.
  Future<void> _pasteFromClipboard() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Zwischenablage ist leer oder der Zugriff '
                'wurde nicht erlaubt.')));
        return;
      }
      setState(() => _controller.text = text);
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Schlüssel eingefügt – jetzt „Speichern“ antippen.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Einfügen nicht möglich. Alternativ das '
              'Auge-Symbol antippen und den Schlüssel lang gedrückt '
              'ins Feld einsetzen.')));
    }
  }

  Future<void> _save() async {
    final settings = context.read<SettingsService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await settings.setApiKey(widget.provider, _controller.text);
      _controller.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('API-Schlüssel gespeichert.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final settings = context.read<SettingsService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await settings.setApiKey(widget.provider, '');
      messenger.showSnackBar(
        const SnackBar(content: Text('API-Schlüssel entfernt.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Entfernen fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      Text(widget.title, style: theme.textTheme.titleMedium),
                ),
                if (widget.hasKey)
                  Chip(
                    avatar: Icon(Icons.check_circle,
                        size: 18, color: theme.colorScheme.primary),
                    label: const Text('Hinterlegt'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: widget.hasKey
                    ? 'Neuen Schlüssel eingeben (ersetzt den vorhandenen)'
                    : 'API-Schlüssel eingeben',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Aus Zwischenablage einfügen',
                      icon: const Icon(Icons.content_paste),
                      onPressed: _pasteFromClipboard,
                    ),
                    IconButton(
                      tooltip: _obscure ? 'Anzeigen' : 'Verbergen',
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: _save,
                  child: const Text('Speichern'),
                ),
                if (widget.hasKey)
                  TextButton(
                    onPressed: _delete,
                    child: const Text('Entfernen'),
                  ),
                TextButton.icon(
                  onPressed: widget.onHelp,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(widget.helpLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Karte zur Modell-Auswahl des aktiven Providers – inklusive freier
/// Eingabe einer Modell-ID, damit neue Modelle ohne App-Update nutzbar sind.
class _ModelCard extends StatefulWidget {
  const _ModelCard({
    super.key,
    required this.provider,
    required this.currentModel,
    required this.knownModels,
    required this.onChanged,
  });

  final GenProvider provider;
  final String currentModel;
  final List<Option> knownModels;
  final ValueChanged<String> onChanged;

  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentModel);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == widget.currentModel) return;
    widget.onChanged(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modell (${widget.provider.label})',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final option in widget.knownModels)
                  ChoiceChip(
                    label: Text(option.$2),
                    visualDensity: VisualDensity.compact,
                    selected: widget.currentModel == option.$1,
                    onSelected: (_) {
                      _controller.text = option.$1;
                      widget.onChanged(option.$1);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Modell-ID',
                helperText:
                    'Freie Eingabe möglich – neue Modelle des Anbieters '
                    'lassen sich hier sofort nutzen, ohne App-Update.',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
              onSubmitted: _apply,
              onTapOutside: (_) => _apply(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}
