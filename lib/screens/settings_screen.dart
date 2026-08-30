import 'package:flutter/foundation.dart' show defaultTargetPlatform,
    kIsWeb, TargetPlatform;
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
import '../services/update_check.dart' as update;
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
        // Anbieter und Modell werden im Bild- bzw. 3D-Tab direkt bei
        // „KI-Modell" gewählt – hier stehen nur noch die Schlüssel.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('API-Schlüssel', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Das KI-Modell wird direkt im Bild- und im 3D-Tab '
                  'gewählt; die Liste dort enthält die Modelle aller '
                  'Anbieter. Hier wird nur hinterlegt, womit sich die '
                  'App beim jeweiligen Anbieter anmeldet. Die Schlüssel '
                  'liegen verschlüsselt auf diesem Gerät und gehen nur '
                  'an den Anbieter, dessen Modell gerade läuft.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
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
        const SizedBox(height: 8),
        _TripoVersionCard(settings: settings),
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
        const _ServerUrlCard(kind: 'image'),
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
        const _UpdateCard(),
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
  const _ServerUrlCard({this.kind = '3d'});

  /// '3d' = Bild→3D-Server, 'image' = Text→Bild-Server.
  final String kind;

  @override
  State<_ServerUrlCard> createState() => _ServerUrlCardState();
}

class _ServerUrlCardState extends State<_ServerUrlCard> {
  late final TextEditingController _ctrl;
  String? _status;
  bool _ok = false;
  /// Reine Info (kein Fehler) – dann grau statt rot anzeigen.
  bool _neutral = false;
  bool _checking = false;
  bool _starting = false;
  bool _refreshing = false;

  /// Auf diesem Rechner eingerichtete Server – gemerkte Einträge plus
  /// gefundene Installationen.
  List<setup.InstalledServer> _servers = const [];

  /// Aktuell gewählter Eintrag in seiner Ablageform; leer = „Keiner".
  String _selected = '';

  setup.InstalledServer? get _current {
    for (final entry in _servers) {
      if (entry.encode() == _selected) return entry;
    }
    return null;
  }

  bool get _isImage => widget.kind == 'image';

  /// Ob Bild- und 3D-Server auf dieselbe Adresse zeigen. Das geht
  /// nicht: Zwei Prozesse können denselben Port nicht belegen, und
  /// dann antwortet der falsche.
  bool _sharesAddressWithOther(SettingsService settings) {
    String clean(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');
    final own = clean(_ctrl.text);
    if (own.isEmpty) return false;
    final other = clean(
        _isImage ? settings.selfHostUrl : settings.selfHostImageUrl);
    return other.isNotEmpty && own == other;
  }

  String _storedUrl(SettingsService settings) =>
      _isImage ? settings.selfHostImageUrl : settings.selfHostUrl;

  void _storeUrl(SettingsService settings, String url) => _isImage
      ? settings.setSelfHostImageUrl(url)
      : settings.setSelfHostUrl(url);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: _storedUrl(context.read<SettingsService>()));
    _loadServers();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Liste der Server aufbauen: erst die gemerkten Einträge, dann per
  /// Suche gefundene Installationen (z. B. von Hand eingerichtete).
  Future<void> _loadServers() async {
    final settings = context.read<SettingsService>();
    final list = <setup.InstalledServer>[];
    for (final raw in settings.localServers) {
      final entry = setup.InstalledServer.decode(raw);
      if (entry != null &&
          entry.kind == widget.kind &&
          !list.contains(entry)) {
        list.add(entry);
      }
    }
    if (setup.setupSupported) {
      try {
        for (final found in await setup.detectInstalledServers()) {
          if (found.kind == widget.kind && !list.contains(found)) {
            list.add(found);
          }
        }
      } catch (_) {
        // Ohne Fundliste weiterarbeiten – die Adresse geht immer.
      }
    }
    if (!mounted) return;
    setState(() {
      _servers = list;
      // Vorauswahl: der Server, dessen Adresse gerade eingetragen ist.
      final url = _ctrl.text.trim();
      _selected = '';
      for (final entry in list) {
        if (entry.url == url) {
          _selected = entry.encode();
          break;
        }
      }
    });
  }

  /// Holt Server-Skript und Paketliste neu. Die Installation selbst
  /// (Python-Umgebung, Modelle) bleibt unangetastet – nur die Dateien,
  /// die zur App gehören, werden auf deren Stand gebracht.
  Future<void> _refreshFiles() async {
    final entry = _current;
    if (entry == null) return;
    setState(() {
      _refreshing = true;
      _status = 'Server-Dateien werden geholt …';
      _ok = false;
      _neutral = true;
    });
    try {
      final files = await setup.refreshServerFiles(
          targetDir: entry.dir, backend: entry.backend);
      if (!mounted) return;
      setState(() {
        _status = 'Aktualisiert: ${files.join(', ')}. Läuft der Server '
            'gerade, einmal beenden und neu starten.';
        _ok = true;
        _neutral = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = e.toString().replaceFirst('Exception: ', '');
          _ok = false;
          _neutral = false;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _saveAndTest() async {
    final settings = context.read<SettingsService>();
    final url = _ctrl.text.trim();
    _storeUrl(settings, url);
    if (url.isEmpty) {
      setState(() {
        _status = 'Adresse entfernt.';
        _ok = false;
        _neutral = true;
      });
      return;
    }
    setState(() {
      _checking = true;
      _status = null;
      _neutral = false;
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

  /// Auswahl in der Liste: „Keiner" nimmt die Adresse heraus, ein
  /// Server trägt seine Adresse ein (gestartet wird per Knopf).
  void _selectServer(String? value) {
    setState(() {
      _selected = value ?? '';
      _status = null;
      _ok = false;
      _neutral = false;
    });
    final entry = _current;
    if (entry == null) {
      _ctrl.text = '';
      _storeUrl(context.read<SettingsService>(), '');
      setState(() {
        _status = 'Kein Server ausgewählt.';
        _neutral = true;
      });
    } else {
      _ctrl.text = entry.url;
    }
  }

  /// Startet den gewählten Server und wartet, bis er antwortet.
  Future<void> _startSelected() async {
    final entry = _current;
    if (entry == null) return;
    setState(() {
      _starting = true;
      _ok = false;
      _neutral = true;
      _status = '${entry.label} wird gestartet …';
    });
    try {
      await setup.startServer(
          targetDir: entry.dir,
          backend: entry.backend,
          port: entry.port,
          // Beim Bild-Server gleich das Modell vorwählen, das im
          // Bild-Tab eingestellt ist – sonst lädt er erst seine
          // Vorgabe und beim ersten Bild ein zweites Mal.
          imageModel: entry.backend == 'sd-image'
              ? context.read<SettingsService>().selfHostImageModel
              : '');
      if (!mounted) return;
      _ctrl.text = entry.url;
      _storeUrl(context.read<SettingsService>(), entry.url);
      // Der erste Start lädt das Modell – deshalb geduldig nachfragen,
      // statt sofort „nicht erreichbar" zu melden.
      for (var attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        try {
          final info = await SelfHostService(entry.url).health();
          if (!mounted) return;
          setState(() {
            _status = 'Verbunden – $info.';
            _ok = true;
            _neutral = false;
          });
          return;
        } catch (_) {
          if (mounted) {
            setState(() => _status = '${entry.label} startet – '
                'Modell wird geladen (${(attempt + 1) * 2} s) …');
          }
        }
      }
      if (mounted) {
        setState(() {
          _status = 'Der Server meldet sich noch nicht. Beim ersten '
              'Start lädt er die Modellgewichte – gleich noch einmal '
              'auf „Speichern & testen" tippen.';
          _ok = false;
          _neutral = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = e.toString().replaceFirst('Exception: ', '');
          _ok = false;
          _neutral = false;
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _checking || _starting || _refreshing;
    final settings = context.watch<SettingsService>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isImage
                    ? 'Eigener Bild-Server (Text→Bild, Bild-Bereich)'
                    : 'Eigener 3D-Server (3D-Bereich)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _isImage
                  ? 'Text→Bild auf dem eigenen PC mit NVIDIA-GPU – '
                      'kostenlos, ohne Cloud (Stable Diffusion 1.5, '
                      'SDXL, SD 3.5, FLUX). Im Bild-Tab erscheint der '
                      'Server als Modell „Eigene GPU"; zusammen mit '
                      'einem 3D-Server läuft die ganze Kette '
                      'Text→Bild→3D lokal. Welches Modell rechnet, '
                      'entscheidet allein die Auswahl im Bild-Tab – '
                      'der Server lädt es bei Bedarf nach. „Server '
                      'starten" wählt es gleich vor, damit er nicht '
                      'zweimal lädt.'
                  : 'Bild→3D auf dem eigenen PC mit NVIDIA-GPU – '
                      'kostenlos und komplett lokal '
                      '(Open-Source-Modelle TripoSR, SF3D, SPAR3D, '
                      'TRELLIS). Der Einrichtungs-Assistent '
                      'installiert alles; danach steht der Server hier '
                      'in der Liste und lässt sich mit einem '
                      'Knopfdruck starten.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // Auswahlliste: oben „Keiner", darunter alles, was auf
            // diesem Rechner eingerichtet ist.
            InputDecorator(
              decoration: InputDecoration(
                labelText: _isImage ? 'Bild-Server' : '3D-Server',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selected,
                  isExpanded: true,
                  onChanged: busy ? null : _selectServer,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Keiner'),
                    ),
                    for (final entry in _servers)
                      DropdownMenuItem(
                        value: entry.encode(),
                        child: Text(
                          '${entry.label} · ${entry.dir}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_servers.isEmpty && setup.setupSupported) ...[
              const SizedBox(height: 6),
              Text(
                'Noch kein Server eingerichtet – der '
                'Einrichtungs-Assistent legt einen an.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                labelText: 'Server-Adresse',
                hintText:
                    'http://127.0.0.1:${setup.defaultPort(widget.kind)}',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_sharesAddressWithOther(settings)) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Bild- und 3D-Server stehen auf derselben '
                      'Adresse. Zwei Server können denselben Port aber '
                      'nicht belegen – einer von beiden bekommt keine '
                      'Verbindung. Üblich sind '
                      'http://127.0.0.1:${setup.defaultPort('3d')} für '
                      '3D und '
                      'http://127.0.0.1:${setup.defaultPort('image')} '
                      'für Bilder.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_current != null)
                  // Läuft der Server schon (grüner Haken von
                  // „Speichern & testen"), wäre ein zweiter Start
                  // sinnlos: Er käme auf demselben Port nicht hoch.
                  // Deshalb wird der Knopf dann still gestellt.
                  FilledButton.icon(
                    onPressed: busy || _ok ? null : _startSelected,
                    icon: _starting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_ok ? Icons.check : Icons.play_arrow,
                            size: 18),
                    label: Text(_starting
                        ? 'Startet …'
                        : _ok
                            ? 'Läuft bereits'
                            : 'Server starten'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _saveAndTest,
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
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () async {
                            final url = await showDialog<String>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) =>
                                  _ServerSetupDialog(kind: widget.kind),
                            );
                            if (!mounted) return;
                            await _loadServers();
                            if (url != null && mounted) {
                              _ctrl.text = url;
                              await _saveAndTest();
                            }
                          },
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Einrichtungs-Assistent'),
                  ),
                // Die App entwickelt ihr Server-Skript weiter; eine
                // ältere Installation holt es sich hiermit nach, ohne
                // die ganze Einrichtung zu wiederholen.
                if (_current != null && setup.setupSupported)
                  TextButton.icon(
                    onPressed: busy ? null : _refreshFiles,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 18),
                    label: const Text('Server-Dateien auffrischen'),
                  ),
                if (_current != null)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () {
                            final entry = _current!;
                            context
                                .read<SettingsService>()
                                .forgetLocalServer(entry.encode());
                            setState(() {
                              _servers = [
                                for (final e in _servers)
                                  if (e != entry) e,
                              ];
                              _selected = '';
                            });
                          },
                    icon: const Icon(Icons.remove_circle_outline,
                        size: 18),
                    label: const Text('Aus der Liste nehmen'),
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
                      : (_neutral
                          ? theme.colorScheme.outline
                          : theme.colorScheme.error),
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
  const _ServerSetupDialog({this.kind = '3d'});

  /// '3d' = Bild→3D, 'image' = Text→Bild.
  final String kind;

  @override
  State<_ServerSetupDialog> createState() => _ServerSetupDialogState();
}

class _ServerSetupDialogState extends State<_ServerSetupDialog> {
  late final List<setup.SetupBackend> _backends =
      setup.backendsOfKind(widget.kind);
  late String _backend =
      _backends.isEmpty ? 'sf3d' : _backends.first.id;
  late final TextEditingController _dirCtrl =
      TextEditingController(text: setup.targetDirFor(_backend));
  final _logCtrl = ScrollController();
  final List<String> _log = [];

  Map<String, String?>? _prereq;

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

  /// Pfad des gespeicherten Protokolls (nach einem Fehlschlag).
  String? _logPath;

  late final int _port = setup.defaultPort(widget.kind);

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
      if (mounted) {
        setState(() => _installed = true);
        // Merken, damit der Server später in der Auswahlliste steht.
        context.read<SettingsService>().rememberLocalServer(
              setup.InstalledServer(
                backend: _backend,
                dir: _dirCtrl.text.trim(),
                port: _port,
              ).encode(),
            );
      }
    } catch (e) {
      // Das komplette Protokoll neben die Installation legen – dort
      // steht mehr als in die Fehlerkarte passt.
      final path = await setup.saveSetupLog(_dirCtrl.text.trim(), _log);
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _logPath = path;
        });
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  /// Erkennt am Fehlertext, woran der Bau der C++-Erweiterungen
  /// gescheitert ist: gar kein Compiler, oder erst beim Zusammenbinden.
  bool get _nativeBuildFailed {
    final text = (_error ?? '').toLowerCase();
    return text.contains('wheel') ||
        text.contains('cl.exe') ||
        text.contains('texture_baker') ||
        text.contains('uv_unwrapper');
  }

  /// Linker-Fehler: Übersetzen hat geklappt, das Zusammenbinden nicht.
  bool get _linkerFailed {
    final text = (_error ?? '').toLowerCase();
    return text.contains('link.exe') ||
        text.contains('lnk') ||
        text.contains('unresolved') ||
        text.contains('status 1120');
  }

  /// Fehlt der Compiler selbst?
  bool get _compilerMissing {
    final text = (_error ?? '').toLowerCase();
    return text.contains('visual c++ 14') ||
        text.contains('microsoft visual c++') ||
        text.contains('cl.exe\' failed') ||
        text.contains('cannot open include file');
  }

  String get _nativeHint {
    if (_linkerFailed) {
      return 'Das Übersetzen hat geklappt, erst das Zusammenbinden '
          '(link.exe) schlägt fehl – SF3D und SPAR3D werden vom '
          'Projekt selbst nur unter Linux gebaut. Im gespeicherten '
          'Protokoll stehen über dieser Meldung die Zeilen mit '
          '„LNK2019: unresolved external symbol"; sie nennen die '
          'fehlenden Symbole. Solange das offen ist, führen zwei Wege '
          'sicher zum Ziel: TripoSR als 3D-Server (läuft ohne eigene '
          'C++-Bauteile) und – für Text→Bild – der Bild-Server, der '
          'ebenfalls keinen Compiler braucht.';
    }
    if (_compilerMissing) {
      return 'Für die C++-Erweiterungen von SF3D bzw. SPAR3D werden die '
          '„Visual Studio Build Tools" mit der Arbeitslast '
          '„Desktopentwicklung mit C++" gebraucht – danach hier erneut '
          'auf „Installieren" tippen; bereits geladene Teile werden '
          'übersprungen. Wer sich das sparen möchte, wählt oben '
          'TripoSR: Das kommt ohne eigene C++-Bauteile aus.';
    }
    return 'Das betrifft die C++-Erweiterungen von SF3D bzw. SPAR3D. '
        'Bereits geladene Teile werden übersprungen, ein erneutes '
        '„Installieren" setzt an der fehlgeschlagenen Stelle an. Ohne '
        'eigene C++-Bauteile kommen TripoSR (3D) und der Bild-Server '
        '(Text→Bild) aus.';
  }

  Future<void> _startAndClose() async {
    try {
      final message = await setup.startServer(
          targetDir: _dirCtrl.text.trim(),
          backend: _backend,
          port: _port,
          imageModel: _backend == 'sd-image'
              ? context.read<SettingsService>().selfHostImageModel
              : '');
      if (!mounted) return;
      context.read<SettingsService>().rememberLocalServer(
            setup.InstalledServer(
              backend: _backend,
              dir: _dirCtrl.text.trim(),
              port: _port,
            ).encode(),
          );
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
    // Der Bild-Server braucht kein Git – es wird nichts geklont.
    final needsGit = widget.kind != 'image';
    final ready = python != null && (!needsGit || git != null);
    return AlertDialog(
      title: Text(widget.kind == 'image'
          ? 'Eigenen Bild-Server einrichten'
          : 'Eigenen 3D-Server einrichten'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.kind == 'image'
                    ? 'Richtet Stable Diffusion auf diesem PC ein, damit '
                        'Text→Bild kostenlos auf deiner NVIDIA-GPU '
                        'läuft. Alles landet im gewählten Ordner; dein '
                        'System-Python bleibt unberührt.'
                    : 'Richtet das gewählte Modell auf diesem PC ein, '
                        'damit Bild→3D kostenlos auf deiner NVIDIA-GPU '
                        'läuft. Alles landet im gewählten Ordner; dein '
                        'System-Python bleibt unberührt.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text('Modell', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final backend in _backends)
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
                              _dirCtrl.text =
                                  setup.targetDirFor(_backend);
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
                    hint: 'Wird gebraucht – neuere Versionen brechen '
                        'bei TripoSR ab. Nach der Installation hier auf '
                        '„Erneut prüfen" tippen.',
                    url: 'https://www.python.org/ftp/python/3.11.9/'
                        'python-3.11.9-amd64.exe'),
                if (needsGit)
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
              for (final (title, description, size)
                  in setup.setupStepsFor(widget.kind))
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
                widget.kind == 'image'
                    ? 'Zusammen rund 3,5 GB Download. Die Modellgewichte '
                        'kommen beim ersten Bild dazu – je nach Modell '
                        '2 GB (SD 1.5) bis 24 GB (FLUX).'
                    : 'Zusammen rund 3,5 GB Download. Die Modellgewichte '
                        '(~1,7 GB) kommen beim ersten Generieren dazu.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (_log.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Protokoll', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _log.join('\n')));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Protokoll kopiert.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Kopieren'),
                    ),
                  ],
                ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                              color: theme.colorScheme.onErrorContainer),
                        ),
                        if (_logPath != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Das vollständige Protokoll liegt in '
                            '$_logPath – der Knopf „Kopieren" über dem '
                            'Protokoll legt es auch in die '
                            'Zwischenablage.',
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer),
                          ),
                        ],
                        // Scheitert das Übersetzen der C++-Teile, hilft
                        // meist der fehlende Compiler – oder gleich das
                        // Modell ohne solche Bauteile.
                        if (_nativeBuildFailed) ...[
                          const SizedBox(height: 8),
                          Text(
                            _nativeHint,
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer),
                          ),
                          if (_compilerMissing) ...[
                            const SizedBox(height: 4),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => launchUrl(
                                  Uri.parse('https://visualstudio'
                                      '.microsoft.com/de/'
                                      'visual-cpp-build-tools/'),
                                  mode: LaunchMode.externalApplication),
                              child:
                                  const Text('Build Tools herunterladen'),
                            ),
                          ],
                          if (_linkerFailed) ...[
                            const SizedBox(height: 4),
                            FilledButton.tonalIcon(
                              onPressed: _installing
                                  ? null
                                  : () => setState(() {
                                        _backend = 'triposr';
                                        _dirCtrl.text =
                                            setup.targetDirFor('triposr');
                                        _error = null;
                                        _log.clear();
                                      }),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: const Text('Auf TripoSR wechseln'),
                            ),
                          ],
                        ],
                      ],
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

/// Fassung der Tripo3D-API. Tripo stellt V2 ab: ab 1. Oktober 2026
/// ohne Neuerungen und Support, ab 1. November 2026 nehmen die
/// V2-Endpunkte keine Anfragen mehr an. V3 ist deshalb der Standard;
/// V2 bleibt bis dahin als Rückfallweg wählbar.
class _TripoVersionCard extends StatelessWidget {
  const _TripoVersionCard({required this.settings});

  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onV2 = settings.tripoApiVersion == 'v2';
    final now = DateTime.now().toUtc();
    final gone = now.isAfter(tripoV2Shutdown);
    final frozen = now.isAfter(tripoV2FeatureFreeze);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.api_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Tripo3D-API-Fassung',
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'v3', label: Text('V3 (aktuell)')),
                ButtonSegment(value: 'v2', label: Text('V2 (Auslauf)')),
              ],
              selected: {settings.tripoApiVersion},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  settings.setTripoApiVersion(selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              'Tripo stellt die alte V2-Schnittstelle ab: seit dem '
              '1. Oktober 2026 ohne Neuerungen und Support, seit dem '
              '1. November 2026 nehmen die V2-Endpunkte keine Anfragen '
              'mehr an. Die App spricht deshalb standardmäßig V3.',
              style: theme.textTheme.bodySmall,
            ),
            if (onV2) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                      gone
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                      size: 16,
                      color: gone
                          ? theme.colorScheme.error
                          : Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      gone
                          ? 'V2 ist abgeschaltet – Tripo-Aufträge '
                              'schlagen fehl, bis hier V3 gewählt ist.'
                          : frozen
                              ? 'V2 bekommt keine Neuerungen und keinen '
                                  'Support mehr und endet am '
                                  '1. November 2026.'
                              : 'V2 läuft am 1. November 2026 aus – nur '
                                  'als Rückfallweg gedacht.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: gone
                              ? theme.colorScheme.error
                              : Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Auf V2 zurückschalten hilft nur, wenn ein V3-Aufruf '
              'unerwartet scheitert – etwa weil ein Konto noch nicht '
              'freigeschaltet ist. Sonst V3 lassen.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
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
      final credits = await TripoService(apiKey,
              version: TripoApiVersion.fromName(settings.tripoApiVersion))
          .fetchBalance();
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


/// Prüft, ob eine neuere Fassung veröffentlicht wurde, lädt sie auf
/// Knopfdruck und startet sie – damit niemand von Hand bei GitHub
/// nachsehen muss.
class _UpdateCard extends StatefulWidget {
  const _UpdateCard();

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  bool _busy = false;
  bool _error = false;
  String? _status;
  update.UpdateInfo? _info;

  /// Die Prüfung ist gescheitert (meist 403 = Abfragegrenze). Dann
  /// bleibt der feste Download-Link als Ausweg.
  bool _checkFailed = false;

  bool get _updateAvailable =>
      _info != null && update.isNewer(_info!);

  void _set(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _error = error;
    });
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = false;
      _checkFailed = false;
      _status = 'Es wird nach einer neuen Fassung gesucht …';
    });
    try {
      final info = await update.fetchLatestRelease();
      if (!mounted) return;
      setState(() => _info = info);
      if (info == null) {
        _set(kIsWeb
            ? 'Die Web-Version lädt immer die neueste Fassung – ein '
                'Neuladen mit Strg+F5 genügt.'
            : 'Für diese Plattform wird keine fertige Datei '
                'veröffentlicht.');
      } else if (update.runningBuildSha.isEmpty) {
        _set('Diese Fassung trägt keine Build-Kennung (Eigenbau). '
            'Neueste Veröffentlichung: ${info.shortSha}.');
      } else if (!update.isNewer(info)) {
        _set('Alles aktuell – ${update.runningBuildSha} ist die '
            'neueste Fassung.');
      } else {
        _set('Neue Fassung ${info.shortSha} verfügbar '
            '(${info.sizeLabel}).');
      }
    } on GenerationException catch (e) {
      if (mounted) setState(() => _checkFailed = true);
      _set(e.message, error: true);
    } catch (e) {
      if (mounted) setState(() => _checkFailed = true);
      _set('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ausweg, wenn die Prüfung scheitert: GitHub liefert unter einem
  /// festen Link immer die Datei des neuesten Releases – ohne API und
  /// damit ohne Abfragegrenze. Ob sie wirklich neuer ist, weiß die App
  /// dann nicht; installiert wird sie ohnehin daneben.
  Future<void> _downloadLatestAnyway() async {
    final info = update.latestReleaseWithoutApi();
    if (info == null) {
      _set('Für diese Plattform wird keine fertige Datei '
          'veröffentlicht.', error: true);
      return;
    }
    setState(() => _info = info);
    await _downloadAndRun(unchecked: true);
  }

  Future<void> _downloadAndRun({bool unchecked = false}) async {
    final info = _info;
    if (info == null) return;
    // Android & Co.: Der System-Installer übernimmt, die App darf
    // sich nicht selbst ersetzen.
    if (!update.canInstall) {
      await launchUrl(Uri.parse(info.downloadUrl),
          mode: LaunchMode.externalApplication);
      _set('Download geöffnet – die Datei danach im Browser bzw. in '
          'den Downloads antippen, um sie zu installieren.');
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final bytes = await update.downloadUpdate(info, _set);
      final program = await update.installUpdate(bytes, info, _set);
      if (unchecked) {
        _set('Neueste Fassung geladen und daneben abgelegt – sie wird '
            'jetzt gestartet.');
      }
      _set('Neue Fassung wird gestartet …');
      await update.launchInstalled(program);
      // Kurz warten, damit das neue Fenster oben liegt, dann die alte
      // Fassung schließen.
      await Future<void>.delayed(const Duration(seconds: 2));
      await update.quitApp();
    } on GenerationException catch (e) {
      _set(e.message, error: true);
    } catch (e) {
      _set(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
            Text('Version & Update', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Diese Fassung: $buildInfo',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              kIsWeb
                  ? 'Im Browser genügt ein Neuladen mit Strg+F5.'
                  : (update.canInstall
                      ? 'Die neue Fassung wird in einen eigenen Ordner '
                          'neben die aktuelle gelegt und gestartet; '
                          'Einstellungen, Schlüssel und Galerie bleiben '
                          'erhalten.'
                      : 'Der Download öffnet die Installationsdatei – '
                          'den Rest erledigt das System.'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _check,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update_alt, size: 18),
                  label: const Text('Nach Updates suchen'),
                ),
                if (_updateAvailable)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _downloadAndRun(),
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(update.canInstall
                        ? 'Herunterladen & starten '
                            '(${_info!.sizeLabel})'
                        : 'Download öffnen (${_info!.sizeLabel})'),
                  ),
                // Scheitert die Prüfung (meist 403 wegen der
                // Abfragegrenze), führt der feste Download-Link
                // trotzdem zur neuesten Fassung.
                if (_checkFailed && !kIsWeb) ...[
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _downloadLatestAnyway,
                    icon: const Icon(Icons.download_for_offline_outlined,
                        size: 18),
                    label: const Text('Neueste Fassung trotzdem laden'),
                  ),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                        Uri.parse(update.releasesPageUrl),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Release-Seite öffnen'),
                  ),
                ],
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _error
                      ? theme.colorScheme.error
                      : (_updateAvailable
                          ? Colors.green.shade700
                          : theme.colorScheme.outline),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
