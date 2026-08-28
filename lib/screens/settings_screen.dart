import 'package:flutter/material.dart';
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
                SegmentedButton<GenProvider>(
                  segments: const [
                    ButtonSegment(
                      value: GenProvider.openai,
                      label: Text('OpenAI'),
                      icon: Icon(Icons.auto_awesome),
                    ),
                    ButtonSegment(
                      value: GenProvider.stability,
                      label: Text('Stability AI'),
                      icon: Icon(Icons.blur_on),
                    ),
                  ],
                  selected: {settings.provider},
                  onSelectionChanged: (selection) =>
                      settings.setProvider(selection.first),
                ),
                const SizedBox(height: 8),
                Text(
                  settings.provider == GenProvider.openai
                      ? 'OpenAI gpt-image-1: Referenzbilder, Qualitätsstufen, '
                          'transparenter Hintergrund, PNG/JPEG/WebP.'
                      : 'Stability AI Stable Image Core: Seitenverhältnisse, '
                          'Negativ-Prompt, Seed und Style-Presets.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
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
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Anzeigen' : 'Verbergen',
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
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
