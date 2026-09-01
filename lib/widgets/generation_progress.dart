import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/wait_motif.dart';

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
    this.motif,
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

  /// Wer da zeichnet, während gewartet wird – je Modell ein eigenes
  /// Motiv. Ohne Angabe der Würfel.
  final WaitMotif? motif;

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
                      painter: _MotifPainter(
                        progress: _controller.value,
                        motif: widget.motif ?? waitMotifs['wuerfel']!,
                        color: theme.colorScheme.primary,
                        accent: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                // Wer da zeichnet, steht dabei. Ohne die Zeile wäre
                // das Motiv ein Rätsel statt einer Auskunft.
                if (widget.preview == null && widget.motif != null)
                  Positioned(
                    left: 8,
                    top: 6,
                    child: Text(
                      '${widget.motif!.name} zeichnet …',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline),
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

/// Die Wartegrafik für Anbieter ohne Zwischenstände: ein Zeichner,
/// der Punkt für Punkt entsteht, und daneben eine Leinwand, auf der
/// sich eine Punktwolke langsam zu einem Bild verdichtet.
///
/// Die erste Fassung ließ Punkte über die ganze Fläche kreisen. Das
/// war unangenehm anzusehen – ständige Bewegung ohne Ruhepunkt.
/// Deshalb gilt hier: **Was gesetzt ist, bleibt stehen.** Jeder Punkt
/// wandert einmal kurz von seiner Streulage an seinen Platz und rührt
/// sich danach nicht mehr. In Bewegung ist nur die vorderste Kante –
/// und der dünne Strich vom Zeichner zum jüngsten Punkt.
///
/// Das Motiv gehört zum Modell, das gerade rechnet (siehe
/// [WaitMotif]): Nano Banana ist eine Banane, hinter Stable Diffusion
/// steht das Hugging-Face-Gesicht. Damit verspricht die Grafik nichts,
/// was sie nicht halten kann – sie zeigt keinen Fortschritt, sondern
/// wer arbeitet.
class _MotifPainter extends CustomPainter {
  _MotifPainter({
    required this.progress,
    required this.motif,
    required this.color,
    required this.accent,
  });

  /// 0 bis 1, läuft langsam durch und beginnt von vorn.
  final double progress;
  final WaitMotif motif;
  final Color color;
  final Color accent;

  /// Wie viele Punkte der Zeichner und wie viele das Bild bekommt.
  static const int _artistPoints = 190;
  static const int _canvasPoints = 150;

  /// Der Zeichner ist ab hier fertig; ab dann entsteht das Bild.
  static const double _artistPhase = 0.42;

  /// Streulage eines Punktes vor dem Setzen – fest gewürfelt, damit
  /// nichts flimmert.
  static double _noise(int seed) {
    var x = (seed * 1103515245 + 12345) % 2147483648;
    x = (x * 1103515245 + 12345) % 2147483648;
    return x / 2147483648;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final artist = samplePoints(motif.artist, _artistPoints);
    final bild = samplePoints(motif.canvas, _canvasPoints);
    if (artist.isEmpty && bild.isEmpty) return;

    // Aufteilung: Zeichner links, Leinwand rechts. Auf schmalen
    // Flächen bleibt das Verhältnis gleich, nur alles kleiner.
    final w = size.width;
    final h = size.height;
    final einheit = math.min(w * 0.42, h * 0.72) / 2;
    final zeichnerMitte = Offset(w * 0.26, h * 0.5);
    final rahmen = Rect.fromCenter(
      center: Offset(w * 0.68, h * 0.48),
      width: einheit * 2.05,
      height: einheit * 1.7,
    );

    final punkt = Paint()..style = PaintingStyle.fill;

    // --- Der Zeichner ---------------------------------------------
    final kante = (progress / _artistPhase) * artist.length;
    for (var i = 0; i < artist.length; i++) {
      final alter = kante - i;
      if (alter <= 0) continue;
      final frisch = (1 - alter / 6).clamp(0.0, 1.0);
      final ziel = zeichnerMitte + artist[i] * einheit;
      // Der Anflug: kurz, dann steht der Punkt.
      final flug = (1 - alter / 3).clamp(0.0, 1.0);
      final streu = Offset(
        (_noise(i * 2 + 1) - 0.5) * einheit * 0.9,
        (_noise(i * 2 + 2) - 0.5) * einheit * 0.9,
      );
      final pos = ziel + streu * flug;
      punkt.color = Color.lerp(color, accent, frisch)!
          .withValues(alpha: (0.35 + 0.55 * (1 - flug)).clamp(0.0, 1.0));
      canvas.drawCircle(pos, 1.5 + 1.1 * frisch, punkt);
    }

    // --- Die Leinwand ---------------------------------------------
    final rahmenAn = ((progress - 0.12) / 0.1).clamp(0.0, 1.0);
    if (rahmenAn > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rahmen, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.18 * rahmenAn),
      );
    }

    // Das Bild entsteht, nachdem der Zeichner steht.
    final bildKante =
        ((progress - _artistPhase) / (1 - _artistPhase)) * bild.length * 1.15;
    var letzter = Offset.zero;
    var etwasGesetzt = false;
    final halb = Offset(rahmen.width / 2, rahmen.height / 2);
    for (var i = 0; i < bild.length; i++) {
      final alter = bildKante - i;
      if (alter <= 0) continue;
      final ziel = rahmen.center +
          Offset(bild[i].dx * halb.dx * 0.8, bild[i].dy * halb.dy * 0.8);
      final flug = (1 - alter / 4).clamp(0.0, 1.0);
      final streu = Offset(
        (_noise(i * 2 + 101) - 0.5) * rahmen.width * 0.55,
        (_noise(i * 2 + 102) - 0.5) * rahmen.height * 0.55,
      );
      final pos = ziel + streu * flug;
      final frisch = (1 - alter / 8).clamp(0.0, 1.0);
      punkt.color = Color.lerp(color, accent, frisch)!
          .withValues(alpha: (0.25 + 0.6 * (1 - flug)).clamp(0.0, 1.0));
      canvas.drawCircle(pos, 1.3 + 0.9 * frisch, punkt);
      letzter = ziel;
      etwasGesetzt = true;
    }

    // --- Der Stift ------------------------------------------------
    // Ein dünner Strich vom Zeichner zum jüngsten Punkt: das einzige
    // Element, das sich bewegt. Ohne ihn sähe es aus, als male sich
    // das Bild von selbst.
    if (etwasGesetzt && progress > _artistPhase) {
      canvas.drawLine(
        zeichnerMitte + Offset(einheit * 0.85, einheit * 0.2),
        letzter,
        Paint()
          ..strokeWidth = 1.0
          ..color = accent.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_MotifPainter old) =>
      old.progress != progress ||
      old.motif.id != motif.id ||
      old.color != color;
}

