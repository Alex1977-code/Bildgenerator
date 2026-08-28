import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/history_service.dart';
import '../services/prompt_relay.dart';
import '../widgets/common.dart';
import 'image_detail_screen.dart';

/// Galerie mit allen bisher generierten Bildern.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  void _openEntry(
      BuildContext context, HistoryEntry entry, Uint8List bytes) {
    final history = context.read<HistoryService>();
    final relay = context.read<PromptRelay>();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ImageDetailScreen(
        bytes: bytes,
        fileName: entry.fileName ?? '${entry.id}.${entry.fileExtension}',
        mimeType: entry.mimeType,
        prompt: entry.prompt,
        metadata: {
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
    final entries = history.entries;

    if (entries.isEmpty) {
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
                'Die Galerie ist noch leer.\nGenerierte Bilder erscheinen '
                'hier automatisch.',
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

  @override
  Widget build(BuildContext context) {
    final history = context.read<HistoryService>();
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: history.readImage(entry),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          return InkWell(
            onTap: bytes == null ? null : () => onOpen(bytes),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox.expand(
                    child: bytes == null
                        ? snapshot.connectionState == ConnectionState.done
                            ? Center(
                                child: Icon(Icons.broken_image_outlined,
                                    color: theme.colorScheme.outlineVariant),
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                        : CheckerboardImage(bytes: bytes, fit: BoxFit.cover),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline),
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
