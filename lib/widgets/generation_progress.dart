import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Zeigt während eines Laufs, dass etwas entsteht.
///
/// Zwei Fälle, und der Unterschied wird ausgesprochen statt kaschiert:
///
/// * **Echte Vorschau.** Der eigene Bild-Server legt alle paar
///   Schritte ein Zwischenbild ab. Dann steht hier das Bild selbst, wie
///   es aus dem Rauschen auftaucht – samt Schrittzähler.
/// * **Keine Vorschau möglich.** OpenAI, Gemini, Stability und die
///   3D-Dienste liefern keine Zwischenstände; sie antworten erst mit
///   dem fertigen Ergebnis. Dort läuft eine Aufbau-Animation, die
///   ausdrücklich als Wartezeichen beschriftet ist – kein Fortschritt,
///   der keiner ist.
class GenerationProgress extends StatefulWidget {
  const GenerationProgress({
    super.key,
    this.preview,
    this.step = 0,
    this.totalSteps = 0,
    this.elapsed = Duration.zero,
    this.label = '',
    this.hint = '',
    this.aspect = 1,
  });

  /// Letzter Zwischenstand, falls der Anbieter welche liefert.
  final Uint8List? preview;

  /// Schritt und Gesamtzahl der Diffusionsschritte.
  final int step;
  final int totalSteps;

  /// Wie lange der Lauf schon dauert.
  final Duration elapsed;

  /// Was gerade passiert („Bild wird erzeugt …").
  final String label;

  /// Zusatz darunter, z. B. warum es keine Vorschau gibt.
  final String hint;

  /// Seitenverhältnis der Fläche (Breite/Höhe).
  final double aspect;

  @override
  State<GenerationProgress> createState() => _GenerationProgressState();
}

class _GenerationProgressState extends State<GenerationProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _time {
    final seconds = widget.elapsed.inSeconds;
    if (seconds < 60) return '$seconds s';
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSteps = widget.totalSteps > 0 && widget.step > 0;
    final fraction =
        hasSteps ? (widget.step / widget.totalSteps).clamp(0.0, 1.0) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: widget.aspect <= 0 ? 1 : widget.aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: theme.colorScheme.surfaceContainerHighest),
                if (widget.preview != null)
                  // Das Zwischenbild ist absichtlich weich gezeichnet:
                  // Es ist klein und wird hochskaliert.
                  Image.memory(
                    widget.preview!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  )
                else
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _EmergingPainter(
                        progress: _controller.value,
                        color: theme.colorScheme.primary,
                        background: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                // Ein schmaler Streifen, der über das Bild wandert –
                // macht sichtbar, dass gerade gerechnet wird, auch
                // wenn sich das Zwischenbild kaum ändert.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => LinearProgressIndicator(
                      value: fraction,
                      minHeight: 3,
                      backgroundColor: Colors.black26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label.isEmpty ? 'Wird erzeugt …' : widget.label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              hasSteps
                  ? 'Schritt ${widget.step}/${widget.totalSteps} · $_time'
                  : _time,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        if (widget.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              widget.hint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
      ],
    );
  }
}

/// Die Wartegrafik für Anbieter ohne Zwischenstände: Punkte, die sich
/// aus dem Nichts zu einer Form verdichten und wieder auflösen.
///
/// Sie zeigt bewusst **kein** Motiv und keinen Fortschritt – sonst
/// verspräche sie etwas, das der Anbieter nicht liefert.
class _EmergingPainter extends CustomPainter {
  _EmergingPainter({
    required this.progress,
    required this.color,
    required this.background,
  });

  final double progress;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.32;
    // Der Zyklus läuft zweimal je Umlauf: verdichten, auflösen.
    final wave = (math.sin(progress * math.pi * 2) + 1) / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(7);
    // Feste Punktwolke, damit das Bild ruhig wirkt und nur die
    // Verdichtung sich ändert.
    for (var i = 0; i < 90; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final spread = 0.4 + random.nextDouble() * 1.6;
      // Ziel: ein Ring; Start: weit verstreut.
      final target = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius * 0.85,
      );
      final scattered = Offset(
        center.dx + math.cos(angle) * radius * spread,
        center.dy + math.sin(angle) * radius * spread,
      );
      final point = Offset.lerp(scattered, target, wave)!;
      paint.color = color.withValues(alpha: 0.10 + 0.45 * wave);
      canvas.drawCircle(point, 1.6 + 1.4 * wave, paint);
    }
  }

  @override
  bool shouldRepaint(_EmergingPainter old) =>
      old.progress != progress || old.color != color;
}
