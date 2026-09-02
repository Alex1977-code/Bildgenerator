import 'package:flutter/material.dart';

/// Bausteine des aufgeräumten Bild-Tabs.
///
/// Eine Regel für alle: **Zahl statt Absatz.** Jede Erklärung wird zu
/// Wert, Badge oder Tooltip; Prosa gibt es nur noch auf Abruf. Und
/// **eine Entscheidung pro Fläche**: Modell, Format, Menge, Stufe sind
/// vier Karten, nicht eine Liste.

/// Kleine Überschrift in Versalien mit Sperrung – die Beschriftung
/// jeder Karte.
class MonoLabel extends StatelessWidget {
  const MonoLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
        fontSize: 10.5,
        color: color ?? theme.colorScheme.outline,
      ),
    );
  }
}

/// Eine Options-Karte: Beschriftung oben, der gewählte Wert groß,
/// darunter eine Zeile in Schreibmaschinenschrift. Ein Klick öffnet
/// die Auswahl.
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.onTap,
    this.trailing,
  });

  final String label;

  /// Der Wert – ein Text oder ein eigenes Widget (die Zahlen-Knöpfe,
  /// die Stufen-Balken).
  final Widget value;
  final Widget? sub;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MonoLabel(label),
                    const SizedBox(height: 7),
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      child: value,
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 3),
                      DefaultTextStyle.merge(
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.outline,
                        ),
                        child: sub!,
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (onTap != null && trailing == null)
                Icon(Icons.unfold_more,
                    size: 16, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein kleines Etikett, wie „schnell" oder „Schlüssel ✓".
class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key, this.tone = BadgeTone.neutral});

  final String text;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      BadgeTone.good => (
          Colors.green.withValues(alpha: 0.14),
          Colors.green.shade800
        ),
      BadgeTone.warn => (
          Colors.orange.withValues(alpha: 0.16),
          Colors.orange.shade900
        ),
      BadgeTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      BadgeTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: fg,
            ),
      ),
    );
  }
}

enum BadgeTone { neutral, good, warn, primary }

/// Fünf Balken für die Qualitätsstufe.
class QualityBars extends StatelessWidget {
  const QualityBars({super.key, required this.level, this.height = 7});

  /// 1–5.
  final int level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tierColor = switch (level) {
      <= 2 => Colors.orange.shade700,
      3 => scheme.primary,
      _ => Colors.green.shade600,
    };
    return Row(
      children: [
        for (var i = 0; i < 5; i++)
          Expanded(
            child: Container(
              height: height,
              margin: EdgeInsets.only(right: i < 4 ? 3 : 0),
              decoration: BoxDecoration(
                color: i < level
                    ? tierColor
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

/// Die Zahlen-Knöpfe „1 2 3 4".
class CountPicker extends StatelessWidget {
  const CountPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 4,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 1; n <= max; n++)
          Padding(
            padding: EdgeInsets.only(right: n < max ? 5 : 0),
            child: Material(
              color: n == value ? scheme.primary : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
                side: n == value
                    ? BorderSide.none
                    : BorderSide(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onChanged == null ? null : () => onChanged!(n),
                child: SizedBox(
                  width: 30,
                  height: 28,
                  child: Center(
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        fontWeight:
                            n == value ? FontWeight.w600 : FontWeight.w400,
                        color: n == value
                            ? scheme.onPrimary
                            : onChanged == null
                                ? scheme.outlineVariant
                                : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum NoticeTone { info, warning, error, success }

/// Eine Hinweiszeile mit Symbol, Text und rechts einer Aktion –
/// die Warnung als Chip, nicht als Absatz.
class NoticeRow extends StatelessWidget {
  const NoticeRow({
    super.key,
    required this.text,
    this.tone = NoticeTone.warning,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final NoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, border, fg, icon) = switch (tone) {
      NoticeTone.warning => (
          Colors.orange.withValues(alpha: 0.10),
          Colors.orange.withValues(alpha: 0.45),
          Colors.orange.shade900,
          Icons.warning_amber_rounded
        ),
      NoticeTone.error => (
          scheme.errorContainer,
          scheme.error.withValues(alpha: 0.5),
          scheme.onErrorContainer,
          Icons.error_outline
        ),
      NoticeTone.success => (
          Colors.green.withValues(alpha: 0.10),
          Colors.green.withValues(alpha: 0.45),
          Colors.green.shade800,
          Icons.check_circle_outline
        ),
      NoticeTone.info => (
          scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          scheme.outlineVariant,
          scheme.onSurfaceVariant,
          Icons.info_outline
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(color: fg)),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(actionLabel!,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: fg, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Umschalter in Pillenform: „Massenprompt | Einzelbild".
class PillSegments<T> extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in segments)
            Material(
              color: value == selected ? scheme.surface : Colors.transparent,
              elevation: value == selected ? 1 : 0,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(7),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: onChanged == null ? null : () => onChanged!(value),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: value == selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Text in Schreibmaschinenschrift, wie Zahlen und Kennungen im
/// Entwurf.
class MonoText extends StatelessWidget {
  const MonoText(this.text,
      {super.key, this.color, this.size = 11.5, this.bold = false});

  final String text;
  final Color? color;
  final double size;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: size,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color ?? Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
