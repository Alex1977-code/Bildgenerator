import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/run_queue.dart';
import '../services/wait_motif.dart';
import '../widgets/generation_progress.dart';
import '../widgets/option_card.dart';

/// Die Warteschlange als Seite: Was läuft, was wartet, was fertig ist.
///
/// Auf dem Handy die dritte Ansicht neben Prompt und Galerie; auf dem
/// Desktop erreichbar über „1 Lauf" in der Leiste. Sie zeigt, **wer
/// rechnet**, und nie einen erfundenen Fortschritt: Die Cloud-Anbieter
/// liefern keine Zwischenstände, also läuft dort ein Wartezeichen und
/// der Text sagt das auch.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Die Uhr an den laufenden Aufträgen soll weitergehen.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String formatDuration(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '$s s';
    final m = s ~/ 60;
    if (m < 60) return '$m:${(s % 60).toString().padLeft(2, '0')} min';
    return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
  }

  /// Das Wartemotiv zum Auftrag: Der Anbieter steht als Name drin, und
  /// die Motive heißen genauso.
  WaitMotif _motifFor(RunJob job) {
    for (final motif in waitMotifs.values) {
      if (motif.name == job.provider) return motif;
    }
    return job.kind == RunJobKind.model
        ? waitMotifs['wuerfel']!
        : waitMotifs['blitz']!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = context.watch<RunQueue>();
    final running = queue.running.toList();
    final waiting = queue.waiting.toList();
    final others = [
      for (final job in queue.jobs.reversed)
        if (!job.isOpen) job,
    ];
    final active = running.length + waiting.length;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Lauf'),
            const SizedBox(width: 10),
            if (active > 0) Badge2('$active aktiv', tone: BadgeTone.primary),
          ],
        ),
        actions: [
          if (active > 0)
            TextButton(
              onPressed: () {
                queue.requestCancel();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Wartende Aufträge abgebrochen – was '
                        'gerade rechnet, endet noch.')));
              },
              child: const Text('Abbrechen'),
            )
          else if (others.isNotEmpty)
            TextButton(
              onPressed: queue.clearFinished,
              child: const Text('Verlauf leeren'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (running.isEmpty && waiting.isEmpty && others.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.hourglass_empty,
                      size: 48, color: scheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text('Nichts in der Warteschlange.',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          for (final job in running) ...[
            _RunningCard(job: job, motif: _motifFor(job)),
            const SizedBox(height: 14),
          ],
          if (waiting.isNotEmpty || others.isNotEmpty) ...[
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 6),
          ],
          for (final job in waiting) _JobTile(job: job, dim: true),
          for (final job in others) _JobTile(job: job),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Die App rechnet nur, solange sie offen ist. Wird sie '
              'geschlossen, hält der Lauf an; beim nächsten Start bietet '
              'der Bild-Tab an, die fehlenden Bilder nachzuholen. Fertige '
              'Bilder liegen unter ihrem Namen in der Galerie.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.job, required this.motif});

  final RunJob job;
  final WaitMotif motif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = job.elapsed ?? Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GenerationProgress(
          motif: motif,
          elapsed: elapsed,
          label: job.name,
          hint: job.note.isNotEmpty
              ? job.note
              : '${job.provider} liefert keine Zwischenstände – hier '
                  'läuft ein Wartezeichen, kein Fortschritt.',
        ),
        const SizedBox(height: 4),
        MonoText(
            '${job.kind == RunJobKind.model ? '3D' : 'Bild'} · '
            '${job.provider}',
            color: theme.colorScheme.outline),
      ],
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, this.dim = false});

  final RunJob job;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color, status) = switch (job.state) {
      RunJobState.waiting => (
          Icons.schedule,
          scheme.outline,
          'wartet'
        ),
      RunJobState.running => (Icons.sync, scheme.primary, 'läuft'),
      RunJobState.done => (
          Icons.check_circle_outline,
          Colors.green.shade700,
          'fertig'
              '${job.elapsed != null ? ' · ${_RunScreenState.formatDuration(job.elapsed!)}' : ''}'
              '${job.costUsd > 0 ? ' · ${job.costUsd.toStringAsFixed(2).replaceAll('.', ',')} \$' : ''}'
        ),
      RunJobState.failed => (
          Icons.error_outline,
          scheme.error,
          job.note.isEmpty ? 'fehlgeschlagen' : job.note
        ),
      RunJobState.cancelled => (
          Icons.block,
          scheme.outline,
          job.note.isEmpty ? 'abgebrochen' : job.note
        ),
    };
    return Opacity(
      opacity: dim ? 0.7 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                  job.kind == RunJobKind.model
                      ? Icons.view_in_ar_outlined
                      : Icons.image_outlined,
                  size: 20,
                  color: scheme.outline),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  MonoText('${job.provider} · $status',
                      color: scheme.outline, size: 11),
                ],
              ),
            ),
            Icon(icon, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
