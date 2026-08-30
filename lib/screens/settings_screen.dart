import 'package:flutter/foundation.dart' show defaultTargetPlatform,
    TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../build_info.dart';
import '../models/models.dart';
import '../services/generators.dart';
import '../services/key_check.dart';
import '../services/self_host_service.dart';
import '../services/server_setup.dart' as setup;
import '../services/settings_service.dart';
import '../services/tripo_service.dart';
import '../services/watermark.dart';
import '../widgets/common.dart';

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

  /// Kurzvorschau des gespeicherten Schlüssels, z. B. "AIza…f2k · 39 Zeichen".
  String? _keySummary(String? rawKey) {
    final key = rawKey?.trim();
    if (key == null || key.isEmpty) return null;
    if (key.length <= 8) return '••• · ${key.length} Zeichen';
    return '${key.substring(0, 4)}…${key.substring(key.length - 3)}'
        ' · ${key.length} Zeichen';
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
          knownModels: [
            ...switch (settings.provider) {
              GenProvider.openai => openAiModelOptions,
              GenProvider.stability => stabilityModelOptions,
              GenProvider.gemini => geminiModelOptions,
            },
            // Vom Anbieter abgerufene Modelle (Aktualisieren-Knopf im
            // Generator-Tab) ergänzen die eingebaute Liste.
            for (final id in settings.fetchedModelsFor(settings.provider))
              if (!switch (settings.provider) {
                GenProvider.openai => openAiModelOptions,
                GenProvider.stability => stabilityModelOptions,
                GenProvider.gemini => geminiModelOptions,
              }.any((option) => option.$1 == id))
                (id, id),
          ],
          onChanged: (value) =>
              settings.setModelFor(settings.provider, value),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'OpenAI-API-Schlüssel',
          providerId: 'openai',
          currentKey: settings.apiKeyFor(GenProvider.openai),
          onSave: (value) => settings.setApiKey(GenProvider.openai, value),
          keySummary: _keySummary(settings.apiKeyFor(GenProvider.openai)),
          helpLabel: 'Schlüssel erstellen auf platform.openai.com',
          onHelp: () => _openUrl('https://platform.openai.com/api-keys'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Stability-AI-API-Schlüssel',
          providerId: 'stability',
          currentKey: settings.apiKeyFor(GenProvider.stability),
          onSave: (value) =>
              settings.setApiKey(GenProvider.stability, value),
          keySummary: _keySummary(settings.apiKeyFor(GenProvider.stability)),
          helpLabel: 'Schlüssel erstellen auf platform.stability.ai',
          onHelp: () => _openUrl('https://platform.stability.ai/account/keys'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Gemini-API-Schlüssel (Google)',
          providerId: 'gemini',
          currentKey: settings.apiKeyFor(GenProvider.gemini),
          onSave: (value) => settings.setApiKey(GenProvider.gemini, value),
          keySummary: _keySummary(settings.apiKeyFor(GenProvider.gemini)),
          helpLabel: 'Schlüssel erstellen auf aistudio.google.com (gratis)',
          onHelp: () => _openUrl('https://aistudio.google.com/apikey'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Meshy-API-Schlüssel (3D-Bereich)',
          providerId: 'meshy',
          currentKey: settings.meshyApiKey,
          onSave: settings.setMeshyApiKey,
          keySummary: _keySummary(settings.meshyApiKey),
          helpLabel: 'Schlüssel erstellen auf meshy.ai (API ab Pro-Plan)',
          onHelp: () => _openUrl('https://www.meshy.ai/api'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Tripo3D-API-Schlüssel (3D-Bereich)',
          providerId: 'tripo',
          currentKey: settings.tripoApiKey,
          onSave: settings.setTripoApiKey,
          keySummary: _keySummary(settings.tripoApiKey),
          helpLabel:
              'Schlüssel erstellen auf platform.tripo3d.ai (Startguthaben)',
          onHelp: () => _openUrl('https://platform.tripo3d.ai/api-keys'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'fal.ai-API-Schlüssel (3D-Bereich)',
          providerId: 'fal',
          currentKey: settings.falApiKey,
          onSave: settings.setFalApiKey,
          keySummary: _keySummary(settings.falApiKey),
          helpLabel:
              'Schlüssel erstellen auf fal.ai (Pay per Use, Startguthaben)',
          onHelp: () => _openUrl('https://fal.ai/dashboard/keys'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Rodin-API-Schlüssel (Hyper3D, 3D-Bereich)',
          providerId: 'rodin',
          currentKey: settings.rodinApiKey,
          onSave: settings.setRodinApiKey,
          keySummary: _keySummary(settings.rodinApiKey),
          helpLabel:
              'Schlüssel erstellen auf hyper3d.ai (Bezahlung nach '
              'Verbrauch)',
          onHelp: () => _openUrl('https://hyper3d.ai/api'),
        ),
        const SizedBox(height: 12),
        _ApiKeyCard(
          title: 'Replicate-API-Token (3D-Bereich)',
          providerId: 'replicate',
          currentKey: settings.replicateApiKey,
          onSave: settings.setReplicateApiKey,
          keySummary: _keySummary(settings.replicateApiKey),
          helpLabel:
              'Token erstellen auf replicate.com (Bezahlung pro Lauf)',
          onHelp: () =>
              _openUrl('https://replicate.com/account/api-tokens'),
        ),
        const SizedBox(height: 12),
        const _ServerUrlCard(),
        const SizedBox(height: 12),
        _UsageCard(
          hasStabilityKey: settings.hasApiKeyFor(GenProvider.stability),
          hasTripoKey:
              settings.tripoApiKey != null &&
                  settings.tripoApiKey!.trim().isNotEmpty,
          onOpenUrl: _openUrl,
        ),
        const SizedBox(height: 12),
        const _WatermarkCard(),
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
                  '3DGenerator erstellt Bilder und 3D-Modelle aus Textbeschreibungen – '
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
        const SizedBox(height: 12),
        // Versions-Kennung aus der CI: Commit und Build-Datum – zum
        // schnellen Prüfen, ob nach einem Update wirklich die neue
        // Version läuft (der Web-Cache liefert sonst gern noch einmal
        // die alte aus; dann erneut neu laden).
        Center(
          child: Text(
            '3DGenerator · Stand: $buildInfo',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ],
    );
  }
}

/// Karte für den eigenen 3D-Server (server/local3d_server.py):
/// Adresse eintragen, speichern und per /health-Endpunkt testen.
class _ServerUrlCard extends StatefulWidget {
  const _ServerUrlCard();

  @override
  State<_ServerUrlCard> createState() => _ServerUrlCardState();
}

class _ServerUrlCardState extends State<_ServerUrlCard> {
  late final TextEditingController _ctrl;
  String? _status;
  bool _ok = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: context.read<SettingsService>().selfHostUrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final settings = context.read<SettingsService>();
    final url = _ctrl.text.trim();
    settings.setSelfHostUrl(url);
    if (url.isEmpty) {
      setState(() {
        _status = 'Adresse entfernt.';
        _ok = false;
      });
      return;
    }
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      final info = await SelfHostService(url).health();
      if (mounted) {
        setState(() {
          _status = 'Verbunden – $info.';
          _ok = true;
        });
      }
    } on GenerationException catch (e) {
      if (mounted) {
        setState(() {
          _status = e.message;
          _ok = false;
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
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
            Text('Eigener 3D-Server (3D-Bereich)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Bild→3D auf dem eigenen PC mit NVIDIA-GPU – kostenlos '
              'und komplett lokal (Open-Source-Modelle TripoSR/TRELLIS, '
              'MIT-Lizenz). Einrichtung: Ordner „server“ im Projekt, '
              'Anleitung in server/README.md.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: 'Server-Adresse',
                hintText: 'http://127.0.0.1:8765',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _checking ? null : _saveAndTest,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link, size: 18),
                  label: const Text('Speichern & testen'),
                ),
                // Der Assistent nimmt die komplette Einrichtung ab –
                // nur auf dem Desktop, wo Python und GPU vorhanden
                // sein können.
                if (setup.setupSupported)
                  FilledButton.icon(
                    onPressed: _checking
                        ? null
                        : () async {
                            final url = await showDialog<String>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) =>
                                  const _ServerSetupDialog(),
                            );
                            if (url != null && mounted) {
                              _ctrl.text = url;
                              await _saveAndTest();
                            }
                          },
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Einrichtungs-Assistent'),
                  ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _ok
                      ? Colors.green.shade700
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Führt die komplette Einrichtung des eigenen 3D-Servers durch:
/// Voraussetzungen prüfen, TripoSR samt Python-Umgebung installieren,
/// Server starten. Gibt beim Schließen die Server-Adresse zurück.
class _ServerSetupDialog extends StatefulWidget {
  const _ServerSetupDialog();

  @override
  State<_ServerSetupDialog> createState() => _ServerSetupDialogState();
}

class _ServerSetupDialogState extends State<_ServerSetupDialog> {
  late final TextEditingController _dirCtrl =
      TextEditingController(text: setup.defaultTargetDir());
  final _logCtrl = ScrollController();
  final List<String> _log = [];

  Map<String, String?>? _prereq;
  String _backend = 'sf3d';

  /// Grafikspeicher der erkannten Karte in GB (aus nvidia-smi, z. B.
  /// „NVIDIA GeForce RTX 3070, 8192 MiB"). Null = unbekannt.
  double? get _gpuMemoryGb {
    final gpu = _prereq?['gpu'];
    if (gpu == null) return null;
    final match = RegExp(r'(\d+)\s*MiB').firstMatch(gpu);
    if (match == null) return null;
    return int.parse(match.group(1)!) / 1024.0;
  }

  bool _checking = true;
  bool _installing = false;
  bool _installed = false;
  String? _error;

  static const _port = 8765;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _dirCtrl.dispose();
    _logCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final result = await setup.checkPrerequisites();
    if (!mounted) return;
    setState(() {
      _prereq = result;
      _checking = false;
    });
  }

  void _append(String line) {
    setState(() => _log.add(line));
    // Ans Ende scrollen, sobald die Zeile gezeichnet ist.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logCtrl.hasClients) {
        _logCtrl.jumpTo(_logCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _install() async {
    final pythonEntry = _prereq?['python'];
    if (pythonEntry == null) return;
    final pythonExe = pythonEntry.split('|').first;
    setState(() {
      _installing = true;
      _error = null;
      _log.clear();
    });
    try {
      await for (final line in setup.installServer(
        targetDir: _dirCtrl.text.trim(),
        pythonExe: pythonExe,
        backend: _backend,
      )) {
        if (!mounted) return;
        _append(line);
      }
      if (mounted) setState(() => _installed = true);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _startAndClose() async {
    try {
      final message = await setup.startServer(
          targetDir: _dirCtrl.text.trim(), backend: _backend);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop('http://127.0.0.1:$_port');
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Widget _prereqRow(ThemeData theme, String label, String? value,
      {required bool required, String? hint, String? url}) {
    final ok = value != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok
                ? Icons.check_circle
                : (required ? Icons.cancel : Icons.info_outline),
            size: 18,
            color: ok
                ? Colors.green.shade600
                : (required
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label: ${value ?? 'nicht gefunden'}',
                    style: theme.textTheme.bodySmall),
                if (!ok && hint != null)
                  Text(hint,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                if (!ok && url != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication),
                    child: const Text('Download öffnen'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final python = _prereq?['python'];
    final git = _prereq?['git'];
    final gpu = _prereq?['gpu'];
    final ready = python != null && git != null;
    return AlertDialog(
      title: const Text('Eigenen 3D-Server einrichten'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Richtet TripoSR auf diesem PC ein, damit Bild→3D '
                'kostenlos auf deiner NVIDIA-GPU läuft. Alles landet im '
                'gewählten Ordner; dein System-Python bleibt unberührt.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text('Modell', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final backend in setup.setupBackends)
                Builder(builder: (context) {
                  final fits = _gpuMemoryGb == null ||
                      _gpuMemoryGb! + 0.5 >= backend.minVramGb;
                  final onWindows =
                      defaultTargetPlatform == TargetPlatform.windows;
                  final blocked = onWindows && !backend.nativeOnWindows;
                  return RadioMenuButton<String>(
                    value: backend.id,
                    groupValue: _backend,
                    onChanged: (_installing || blocked)
                        ? null
                        : (value) => setState(() {
                              _backend = value ?? _backend;
                              // Jedes Modell in einen eigenen Ordner,
                              // damit sie sich nicht überschreiben.
                              final base = setup.defaultTargetDir();
                              final cut =
                                  base.lastIndexOf(RegExp(r'[\\/]'));
                              _dirCtrl.text = cut < 0
                                  ? base
                                  : '${base.substring(0, cut + 1)}'
                                      '${_backend.toUpperCase()}';
                            }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${backend.name} · '
                                  '${backend.vramLabel}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Abgleich mit der erkannten Karte.
                              if (_gpuMemoryGb != null)
                                Icon(
                                  fits
                                      ? Icons.check_circle
                                      : Icons.warning_amber,
                                  size: 15,
                                  color: fits
                                      ? Colors.green.shade600
                                      : Colors.orange.shade700,
                                ),
                            ],
                          ),
                          Text(backend.description,
                              style: theme.textTheme.bodySmall),
                          if (blocked)
                            Text(
                              'Unter Windows nur über WSL2 (Ubuntu) – '
                              'siehe server/README.md.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error),
                            )
                          else if (!fits)
                            Text(
                              'Deine Karte hat '
                              '${_gpuMemoryGb!.toStringAsFixed(0)} GB – '
                              'das wird knapp bis unmöglich.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.orange.shade800),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              TextField(
                controller: _dirCtrl,
                enabled: !_installing,
                decoration: const InputDecoration(
                  labelText: 'Zielordner',
                  helperText: 'Wird angelegt, falls er noch nicht '
                      'existiert. Kein Systemordner wie C:\\Windows.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Voraussetzungen',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  if (_checking)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      tooltip: 'Erneut prüfen',
                      visualDensity: VisualDensity.compact,
                      onPressed: _installing ? null : _check,
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                ],
              ),
              if (!_checking) ...[
                _prereqRow(theme, 'Python 3.11',
                    python?.split('|').last, required: true,
                    hint: 'Wird zwingend gebraucht – neuere Versionen '
                        'brechen bei TripoSR ab. Nach der Installation '
                        'hier auf „Erneut prüfen" tippen.',
                    url: 'https://www.python.org/ftp/python/3.11.9/'
                        'python-3.11.9-amd64.exe'),
                _prereqRow(theme, 'Git', git,
                    required: true,
                    hint: 'Zum Laden des Modell-Quellcodes.',
                    url: 'https://git-scm.com/download/win'),
                _prereqRow(theme, 'NVIDIA-GPU', gpu,
                    required: false,
                    hint: 'Ohne GPU läuft es auf der CPU – sehr langsam, '
                        'aber die Einrichtung funktioniert trotzdem.'),
              ],
              const SizedBox(height: 16),
              Text('Was installiert wird',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final (title, description, size) in setup.setupSteps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodySmall,
                            children: [
                              TextSpan(
                                  text: title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              TextSpan(text: ' – $description'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(size,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Zusammen rund 3,5 GB Download. Die Modellgewichte '
                '(~1,7 GB) kommen beim ersten Generieren dazu.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (_log.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Protokoll', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Container(
                  height: 180,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    controller: _logCtrl,
                    itemCount: _log.length,
                    itemBuilder: (context, index) {
                      final line = _log[index];
                      final isStep = line.startsWith('#');
                      return Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight:
                              isStep ? FontWeight.w700 : FontWeight.w400,
                          color: isStep ? theme.colorScheme.primary : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.errorContainer,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _installing ? null : () => Navigator.of(context).pop(),
          child: Text(_installed ? 'Schließen' : 'Abbrechen'),
        ),
        if (!_installed)
          FilledButton.icon(
            onPressed: (_installing || !ready) ? null : _install,
            icon: _installing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download, size: 18),
            label: Text(_installing
                ? 'Installiert …'
                : (ready
                    ? 'Installieren'
                    : 'Voraussetzungen fehlen')),
          )
        else
          FilledButton.icon(
            onPressed: _startAndClose,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Server starten & übernehmen'),
          ),
      ],
    );
  }
}

class _ApiKeyCard extends StatefulWidget {
  const _ApiKeyCard({
    required this.title,
    required this.onSave,
    required this.keySummary,
    required this.helpLabel,
    required this.onHelp,
    required this.providerId,
    required this.currentKey,
  });

  final String title;

  /// Anbieter-Kennung für die Schlüssel-Prüfung (validateApiKey).
  final String providerId;

  /// Aktuell gespeicherter Schlüssel (für die Prüfung ohne Neueingabe).
  final String? currentKey;

  /// Speichert den Schlüssel; ein leerer Wert löscht ihn.
  final Future<void> Function(String value) onSave;

  /// Vorschau des gespeicherten Schlüssels (null = keiner hinterlegt).
  final String? keySummary;
  final String helpLabel;
  final VoidCallback onHelp;

  bool get hasKey => keySummary != null;

  @override
  State<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends State<_ApiKeyCard> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _validating = false;
  bool _validated = false;
  String? _validationError;

  /// Prüft den eingegebenen bzw. gespeicherten Schlüssel per
  /// Test-Anfrage und zeigt das Ergebnis als grünen Haken oder Fehler.
  Future<void> _validate() async {
    final key = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : (widget.currentKey ?? '').trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Bitte zuerst einen Schlüssel eingeben oder speichern.')));
      return;
    }
    setState(() {
      _validating = true;
      _validated = false;
      _validationError = null;
    });
    try {
      await validateApiKey(widget.providerId, key);
      if (mounted) setState(() => _validated = true);
    } on GenerationException catch (e) {
      if (mounted) setState(() => _validationError = e.message);
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

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
      messenger.showSnackBar(SnackBar(
          content: Text('Schlüssel eingefügt (${text.length} Zeichen) – '
              'jetzt „Speichern“ antippen.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Einfügen nicht möglich. Alternativ das '
              'Auge-Symbol antippen und den Schlüssel lang gedrückt '
              'ins Feld einsetzen.')));
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSave(_controller.text);
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSave('');
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
                    label: Text(widget.keySummary!),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              // Sichtbar geschaltet darf der Schlüssel umbrechen, damit er
              // vollständig kontrolliert werden kann.
              maxLines: _obscure ? 1 : 4,
              minLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {
                _validated = false;
                _validationError = null;
              }),
              decoration: InputDecoration(
                labelText: widget.hasKey
                    ? 'Neuen Schlüssel eingeben (ersetzt den vorhandenen)'
                    : 'API-Schlüssel eingeben',
                counterText: _controller.text.isEmpty
                    ? ''
                    : '${_controller.text.length} Zeichen',
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
                  onPressed: _validating ? null : _validate,
                  icon: _validating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user, size: 16),
                  label: const Text('Prüfen'),
                ),
                TextButton.icon(
                  onPressed: widget.onHelp,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(widget.helpLabel),
                ),
              ],
            ),
            if (_validated || _validationError != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _validated ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: _validated ? Colors.green : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _validated
                          ? 'Schlüssel geprüft – gültig und einsatzbereit.'
                          : _validationError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _validated
                            ? Colors.green
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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

/// Karte "Guthaben & Verbrauch": Stability-Guthaben live abfragen,
/// für OpenAI/Google die Verbrauchs-Dashboards verlinken (diese Anbieter
/// bieten keine Guthaben-Abfrage per API an).
class _UsageCard extends StatefulWidget {
  const _UsageCard({
    required this.hasStabilityKey,
    required this.hasTripoKey,
    required this.onOpenUrl,
  });

  final bool hasStabilityKey;
  final bool hasTripoKey;
  final Future<void> Function(String url) onOpenUrl;

  @override
  State<_UsageCard> createState() => _UsageCardState();
}

class _UsageCardState extends State<_UsageCard> {
  String? _stabilityBalance;
  String? _tripoBalance;
  bool _loading = false;

  Future<void> _fetchStabilityBalance() async {
    final settings = context.read<SettingsService>();
    final apiKey = settings.apiKeyFor(GenProvider.stability)?.trim();
    if (apiKey == null || apiKey.isEmpty) return;
    setState(() {
      _loading = true;
      _stabilityBalance = null;
    });
    try {
      final credits = await StabilityGenerator.fetchCredits(apiKey);
      if (!mounted) return;
      setState(() {
        _stabilityBalance = credits == null
            ? 'Keine Angabe erhalten'
            : '${credits.toStringAsFixed(1)} Credits';
      });
    } catch (e) {
      if (mounted) setState(() => _stabilityBalance = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchTripoBalance() async {
    final settings = context.read<SettingsService>();
    final apiKey = settings.tripoApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return;
    setState(() {
      _loading = true;
      _tripoBalance = null;
    });
    try {
      final credits = await TripoService(apiKey).fetchBalance();
      if (!mounted) return;
      setState(() {
        _tripoBalance = credits == null
            ? 'Keine Angabe erhalten'
            : '${credits.toStringAsFixed(1)} Credits';
      });
    } catch (e) {
      if (mounted) setState(() => _tripoBalance = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
            Text('Guthaben & Verbrauch', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Nach jeder Generierung zeigt der Generator die verbrauchten '
              'Tokens (OpenAI/Gemini) bzw. das Restguthaben (Stability) an.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (widget.hasStabilityKey)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _stabilityBalance == null
                          ? 'Stability-Guthaben'
                          : 'Stability-Guthaben: $_stabilityBalance',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton.icon(
                          onPressed: _fetchStabilityBalance,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Abrufen'),
                        ),
                ],
              ),
            if (widget.hasTripoKey)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _tripoBalance == null
                          ? 'Tripo3D-Guthaben'
                          : 'Tripo3D-Guthaben: $_tripoBalance',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton.icon(
                          onPressed: _fetchTripoBalance,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Abrufen'),
                        ),
                ],
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      widget.onOpenUrl('https://platform.openai.com/usage'),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('OpenAI-Verbrauch'),
                ),
                TextButton.icon(
                  onPressed: () =>
                      widget.onOpenUrl('https://aistudio.google.com/usage'),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Google-Gemini-Verbrauch'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Karte "Wasserzeichen": eigenes Logo, das nach der Generierung
/// automatisch auf jedes Bild gelegt wird.
class _WatermarkCard extends StatelessWidget {
  const _WatermarkCard();

  Future<void> _pickLogo(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Das Logo ist größer als 2 MB – bitte eine '
                'kleinere Datei wählen.')));
        return;
      }
      settings.setWatermarkLogo(bytes);
      messenger.showSnackBar(
          const SnackBar(content: Text('Logo übernommen.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Logo konnte nicht geladen werden: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme = Theme.of(context);
    final logo = settings.watermarkLogo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wasserzeichen (eigenes Logo)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Wird nach der Generierung automatisch auf jedes Bild gelegt. '
              'Empfohlen: PNG mit transparentem Hintergrund. Das Ergebnis '
              'wird als PNG gespeichert.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (logo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CustomPaint(
                      painter: CheckerboardPainter(
                          dark: theme.brightness == Brightness.dark),
                      child: Image.memory(logo,
                          width: 56, height: 56, fit: BoxFit.contain),
                    ),
                  )
                else
                  Icon(Icons.branding_watermark_outlined,
                      size: 40, color: theme.colorScheme.outlineVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _pickLogo(context),
                        child: Text(
                            logo == null ? 'Logo wählen' : 'Logo ändern'),
                      ),
                      if (logo != null)
                        TextButton(
                          onPressed: () =>
                              settings.setWatermarkLogo(null),
                          child: const Text('Entfernen'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (logo != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Wasserzeichen automatisch einfügen'),
                value: settings.watermarkEnabled,
                onChanged: settings.setWatermarkEnabled,
              ),
              DropdownMenu<String>(
                initialSelection: settings.watermarkPosition,
                label: const Text('Position'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final option in watermarkPositionOptions)
                    DropdownMenuEntry(value: option.$1, label: option.$2),
                ],
                onSelected: (value) {
                  if (value != null) settings.setWatermarkPosition(value);
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('Größe')),
                  Expanded(
                    child: Slider(
                      value: settings.watermarkSizePercent.toDouble(),
                      min: 5,
                      max: 40,
                      divisions: 35,
                      label: '${settings.watermarkSizePercent} %',
                      onChanged: (value) =>
                          settings.setWatermarkSizePercent(value.round()),
                    ),
                  ),
                  Text('${settings.watermarkSizePercent} %'),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 90, child: Text('Deckkraft')),
                  Expanded(
                    child: Slider(
                      value: settings.watermarkOpacity.toDouble(),
                      min: 10,
                      max: 100,
                      divisions: 18,
                      label: '${settings.watermarkOpacity} %',
                      onChanged: (value) =>
                          settings.setWatermarkOpacity(value.round()),
                    ),
                  ),
                  Text('${settings.watermarkOpacity} %'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
