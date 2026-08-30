import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/exporter.dart';
import '../services/history_service.dart';
import '../services/prompt_relay.dart';
import '../services/provenance.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import 'image_detail_screen.dart';
import 'model_preview_screen.dart';

/// Galerie mit allen bisher generierten Bildern.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  /// Läuft gerade ein Sammel-Download? Dann bleibt der Knopf gesperrt
  /// und zeigt den Fortschritt – bei 43 Bildern aus einem Massenlauf
  /// dauert das einen Moment.
  bool _downloading = false;
  int _downloadDone = 0;
  int _downloadTotal = 0;

  /// Alle gerade angezeigten Einträge nacheinander herunterladen.
  ///
  /// Nacheinander und nicht gleichzeitig: Im Browser zählt jeder
  /// Download einzeln, und ein Schwall von vierzig Anfragen auf einmal
  /// wird blockiert. Beim ersten Mal fragt Chrome, ob die Seite
  /// mehrere Dateien speichern darf – das einmal erlauben.
  Future<void> _downloadAll(List<HistoryEntry> entries) async {
    final history = context.read<HistoryService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _downloading = true;
      _downloadDone = 0;
      _downloadTotal = entries.length;
    });
    var failed = 0;
    try {
      for (final entry in entries) {
        try {
          final bytes = await history.readImage(entry);
          if (bytes == null) {
            failed++;
          } else {
            await exportImageBytes(
                bytes, entry.downloadFileName, entry.mimeType);
          }
        } catch (_) {
          failed++;
        }
        if (!mounted) return;
        setState(() => _downloadDone++);
        // Kleine Pause, damit der Browser die Downloads einzeln
        // annimmt statt sie als Schwall abzuweisen.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(failed == 0
          ? '${entries.length} '
              '${entries.length == 1 ? 'Datei' : 'Dateien'} '
              'heruntergeladen.'
          : '${entries.length - failed} von ${entries.length} '
              'heruntergeladen, $failed nicht mehr im Speicher.'),
    ));
  }

  final _searchCtrl = TextEditingController();

  /// Suchbegriff – trifft auf Name und Beschreibung zu. Über den
  /// Namen aus dem Massenprompt ist so jedes Bild wiederzufinden.
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  void _openEntry(
      BuildContext context, HistoryEntry entry, Uint8List bytes) {
    final history = context.read<HistoryService>();
    final relay = context.read<PromptRelay>();
    if (entry.isModel) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ModelPreviewScreen(
          glbBytes: bytes,
          title: entry.prompt,
          provenance: ProvenanceInfo(
            kind: '3D-Modell',
            description: entry.prompt,
            providerLabel: entry.providerLabel,
            details: entry.params,
          ),
        ),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ImageDetailScreen(
        bytes: bytes,
        fileName: entry.fileName ?? '${entry.id}.${entry.fileExtension}',
        mimeType: entry.mimeType,
        prompt: entry.prompt,
        metadata: {
          if (entry.name.isNotEmpty) 'Name': entry.name,
          ...entry.params,
          'Erstellt': _formatDate(entry.createdAt),
        },
        onDelete: () => history.delete(entry),
        onReusePrompt: () => relay.send(entry.prompt),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryService>();
    final all = history.entries;
    final needle = _search.trim().toLowerCase();
    final entries = needle.isEmpty
        ? all
        : [
            for (final entry in all)
              if (entry.name.toLowerCase().contains(needle) ||
                  entry.prompt.toLowerCase().contains(needle))
                entry,
          ];

    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.collections_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'Die Galerie ist noch leer.\nGenerierte Bilder und '
                '3D-Modelle erscheinen hier automatisch.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              labelText: 'Nach Name oder Beschreibung suchen',
              hintText: 'z. B. burg-03',
              border: const OutlineInputBorder(),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Suche leeren',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  needle.isEmpty
                      ? '${entries.length} '
                          '${entries.length == 1 ? 'Eintrag' : 'Einträge'}'
                      : entries.isEmpty
                          ? 'Nichts gefunden – der Name muss so '
                              'geschrieben sein wie im Massenprompt '
                              '(z. B. „burg-03").'
                          : '${entries.length} von ${all.length} '
                              'Einträgen',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (entries.isNotEmpty)
                TextButton.icon(
                  onPressed: _downloading
                      ? null
                      : () => _downloadAll(entries),
                  icon: _downloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_for_offline_outlined,
                          size: 18),
                  label: Text(_downloading
                      ? 'Lädt … $_downloadDone von $_downloadTotal'
                      : needle.isEmpty
                          ? 'Alle herunterladen'
                          : 'Gefundene herunterladen'),
                ),
            ],
          ),
        ),
        if (!history.isPersistent)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Hinweis: In der Web-Version bleibt der Verlauf nur für die '
              'aktuelle Sitzung erhalten. Bilder bei Bedarf herunterladen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _GalleryTile(
                key: ValueKey(entry.id),
                entry: entry,
                dateLabel: _formatDate(entry.createdAt),
                onOpen: (bytes) => _openEntry(context, entry, bytes),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    super.key,
    required this.entry,
    required this.dateLabel,
    required this.onOpen,
  });

  final HistoryEntry entry;
  final String dateLabel;
  final void Function(Uint8List bytes) onOpen;

  /// Erstellungsnachweis-PDF zum Galerie-Eintrag herunterladen: mit
  /// dem gespeicherten Erstellungszeitpunkt, den Original-Angaben und
  /// der SHA-256-Prüfsumme der abgelegten Datei.
  Future<void> _downloadProvenance(BuildContext context) async {
    final history = context.read<HistoryService>();
    final settings = context.read<SettingsService>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await askCreatorName(context, settings);
    if (name == null) return;
    try {
      final fileBytes = await history.readImage(entry);
      if (fileBytes == null) {
        messenger.showSnackBar(const SnackBar(
            content:
                Text('Die Datei ist nicht mehr im Speicher vorhanden.')));
        return;
      }
      final preview = entry.isModel
          ? await history.readThumbnail(entry)
          : fileBytes;
      final pdf = await buildProvenancePdf(
        info: ProvenanceInfo(
          kind: entry.isModel ? '3D-Modell' : 'Bild',
          description: entry.prompt,
          providerLabel: entry.providerLabel,
          details: entry.params,
          previewBytes: preview,
        ),
        fileType: entry.isModel
            ? 'GLB'
            : entry.fileExtension.toUpperCase(),
        fileBytes: fileBytes,
        creatorName: name,
        createdAt: entry.createdAt,
      );
      final message = await exportImageBytes(
          pdf, 'erstellungsnachweis_${entry.id}.pdf', 'application/pdf');
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Nachweis fehlgeschlagen: $e')));
    }
  }

  /// Die Datei selbst herunterladen – ohne den Umweg über die
  /// Detailansicht. Auf dem Desktop landet sie im Downloads-Ordner, im
  /// Web startet der Browser-Download, auf dem Handy öffnet sich das
  /// Teilen-Menü.
  Future<void> _download(BuildContext context) async {
    final history = context.read<HistoryService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await history.readImage(entry);
      if (bytes == null) {
        messenger.showSnackBar(const SnackBar(
            content:
                Text('Die Datei ist nicht mehr im Speicher vorhanden.')));
        return;
      }
      final message = await exportImageBytes(
          bytes, entry.downloadFileName, entry.mimeType);
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Herunterladen fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = context.read<HistoryService>();
    final theme = Theme.of(context);
    final isModel = entry.isModel;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        // Bei Modellen zeigt die Kachel das Vorschaubild; die
        // GLB-Datei wird erst beim Öffnen geladen.
        future:
            isModel ? history.readThumbnail(entry) : history.readImage(entry),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          Future<void> openModel() async {
            final glb = await history.readImage(entry);
            if (glb != null && context.mounted) onOpen(glb);
          }

          return InkWell(
            onTap: isModel
                ? openModel
                : (bytes == null ? null : () => onOpen(bytes)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      bytes == null
                          ? snapshot.connectionState == ConnectionState.done
                              ? Center(
                                  child: Icon(
                                      isModel
                                          ? Icons.view_in_ar
                                          : Icons.broken_image_outlined,
                                      size: isModel ? 48 : 24,
                                      color:
                                          theme.colorScheme.outlineVariant),
                                )
                              : const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                          : CheckerboardImage(
                              bytes: bytes, fit: BoxFit.cover),
                      if (isModel) ...[
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.view_in_ar,
                                    size: 14,
                                    color: theme
                                        .colorScheme.onPrimaryContainer),
                                const SizedBox(width: 3),
                                Text('3D',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                            color: theme.colorScheme
                                                .onPrimaryContainer)),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IconButton(
                            tooltip: 'Aus der Galerie löschen',
                            iconSize: 18,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black38,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => history.delete(entry),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Bilder aus dem Massenprompt tragen ihren
                            // Namen – darunter steht die Beschreibung.
                            if (entry.name.isNotEmpty)
                              Text(
                                entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge,
                              ),
                            Text(
                              entry.prompt,
                              maxLines: entry.name.isEmpty ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: isModel
                            ? 'GLB herunterladen'
                            : 'Bild herunterladen',
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.download_outlined),
                        onPressed: () => _download(context),
                      ),
                      IconButton(
                        tooltip: 'Erstellungsnachweis (PDF)',
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.workspace_premium_outlined),
                        onPressed: () => _downloadProvenance(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
