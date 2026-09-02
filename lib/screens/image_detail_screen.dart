import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/exporter.dart';
import '../widgets/common.dart';

/// Vollbildansicht eines Bildes mit Zoom, Metadaten und Export.
class ImageDetailScreen extends StatelessWidget {
  const ImageDetailScreen({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.prompt,
    this.metadata = const {},
    this.onDelete,
    this.onReusePrompt,
    this.onSendToThreeD,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String? prompt;
  final Map<String, String> metadata;
  final Future<void> Function()? onDelete;
  final VoidCallback? onReusePrompt;

  /// „→ 3D": das Bild als Vorderansicht in den 3D-Tab.
  final VoidCallback? onSendToThreeD;

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await exportImageBytes(bytes, fileName, mimeType);
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bild löschen?'),
        content: const Text(
            'Das Bild wird endgültig aus dem Verlauf entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onDelete?.call();
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildansicht'),
        actions: [
          if (onSendToThreeD != null)
            TextButton.icon(
              icon: const Icon(Icons.view_in_ar_outlined, size: 18),
              label: const Text('→ 3D'),
              onPressed: () {
                onSendToThreeD!();
                Navigator.of(context).pop();
              },
            ),
          IconButton(
            tooltip: 'Speichern / Teilen',
            icon: const Icon(Icons.download),
            onPressed: () => _export(context),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(child: CheckerboardImage(bytes: bytes)),
            ),
          ),
          if (prompt != null || metadata.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              color: theme.colorScheme.surfaceContainerHighest,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (prompt != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text('Prompt',
                                style: theme.textTheme.titleSmall),
                          ),
                          IconButton(
                            tooltip: 'Prompt kopieren',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: prompt!));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Prompt kopiert.')),
                                );
                              }
                            },
                          ),
                          if (onReusePrompt != null)
                            TextButton.icon(
                              icon: const Icon(Icons.replay, size: 18),
                              label: const Text('Erneut verwenden'),
                              onPressed: () {
                                onReusePrompt!();
                                Navigator.of(context).pop();
                              },
                            ),
                        ],
                      ),
                      Text(prompt!, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                    ],
                    for (final entry in metadata.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('${entry.key}: ${entry.value}',
                            style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
