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
    // Langsam: Der Aufbau soll ruhig wirken, nicht flimmern.
    duration: const Duration(seconds: 6),
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
                      painter: _MeshPainter(
                        progress: _controller.value,
                        color: theme.colorScheme.primary,
                        accent: theme.colorScheme.tertiary,
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

/// Die Wartegrafik für Anbieter ohne Zwischenstände: ein Drahtnetz,
/// das sich Linie für Linie aufbaut.
///
/// Die erste Fassung ließ Punkte kreisen und sich verdichten. Das war
/// unangenehm anzusehen – ständige Bewegung über die ganze Fläche,
/// ohne Ruhepunkt. Jetzt bleibt jede gezeichnete Linie stehen, und
/// nur die vorderste Kante wandert weiter: Man sieht, dass etwas
/// entsteht, ohne dass sich das Bild bewegt.
///
/// Gezeichnet wird ein Gitter über einer Kugel – kein Motiv, denn der
/// Anbieter liefert keines. Es verspricht damit nichts, was es nicht
/// halten kann.
class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.progress,
    required this.color,
    required this.accent,
  });

  /// 0 bis 1, läuft langsam durch und beginnt von vorn.
  final double progress;
  final Color color;
  final Color accent;

  /// Längengrade und Breitengrade des Netzes.
  static const int _columns = 14;
  static const int _rows = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.33;

    // Ein Punkt auf der Kugel, leicht gekippt, in die Fläche
    // projiziert. Fest berechnet – nichts dreht sich.
    Offset point(double u, double v) {
      final theta = u * math.pi * 2;
      final phi = v * math.pi;
      final x = math.sin(phi) * math.cos(theta);
      final y = math.cos(phi);
      final z = math.sin(phi) * math.sin(theta);
      // Leichte Kippung um die x-Achse, damit das Netz nicht wie ein
      // flacher Kreis wirkt.
      const tilt = 0.35;
      final ry = y * math.cos(tilt) - z * math.sin(tilt);
      final rz = y * math.sin(tilt) + z * math.cos(tilt);
      // Schwache Perspektive: hinten liegende Linien rücken zusammen.
      final scale = 1 / (1.8 - rz * 0.4);
      return Offset(
        center.dx + x * radius * scale * 1.8,
        center.dy + ry * radius * scale * 1.8,
      );
    }

    // Tiefe für die Helligkeit: vorne hell, hinten blass.
    double depth(double u, double v) {
      final theta = u * math.pi * 2;
      final phi = v * math.pi;
      final y = math.cos(phi);
      final z = math.sin(phi) * math.sin(theta);
      const tilt = 0.35;
      return (y * math.sin(tilt) + z * math.cos(tilt) + 1) / 2;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    // Der Aufbau läuft von oben nach unten durch und beginnt von
    // vorn; die Kante ist hell, alles davor bleibt ruhig stehen.
    final edge = progress * (_rows + 2);
    for (var row = 0; row <= _rows; row++) {
      final v = row / _rows;
      final age = edge - row;
      if (age <= 0) continue;
      // Frisch gezeichnete Reihen leuchten kurz auf.
      final fresh = (1 - age).clamp(0.0, 1.0);
      for (var col = 0; col < _columns; col++) {
        final u0 = col / _columns;
        final u1 = (col + 1) / _columns;
        final near = depth(u0, v);
        final alpha =
            ((0.12 + 0.5 * near) * (0.45 + 0.55 * fresh)).clamp(0.0, 1.0);
        paint.color =
            Color.lerp(color, accent, fresh)!.withValues(alpha: alpha);
        canvas.drawLine(point(u0, v), point(u1, v), paint);
        // Die Längslinie zur nächsten Reihe – nur, wenn die schon da
        // ist, sonst hinge sie in der Luft.
        if (row < _rows && age > 1) {
          paint.color = color.withValues(alpha: 0.10 + 0.35 * near);
          canvas.drawLine(point(u0, v), point(u0, (row + 1) / _rows), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.progress != progress || old.color != color;
}
