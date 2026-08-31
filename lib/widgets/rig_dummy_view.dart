import 'package:flutter/material.dart';

import '../services/rig_dummy.dart';

/// Zeichnet den Dummy neben dem Rig-Editor: Silhouette, empfohlene
/// Gelenkpunkte und deren Einflussbereiche.
///
/// Das angetippte Gelenk wird hervorgehoben – Ring gefüllt, Punkt
/// größer –, damit der Blick zwischen 3D-Ansicht und Anleitung nicht
/// suchen muss.
class RigDummyView extends StatelessWidget {
  const RigDummyView({
    super.key,
    required this.dummy,
    this.highlight,
  });

  final RigDummy dummy;

  /// Name des gerade ausgewählten Gelenks (echter Rig-Name).
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked =
        highlight == null ? null : dummyJointFor(dummy, highlight!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dummy.label, style: theme.textTheme.titleSmall),
        Text(dummy.view,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 0.82,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: CustomPaint(
              painter: _DummyPainter(
                dummy: dummy,
                marked: marked,
                body: theme.colorScheme.outlineVariant,
                joint: theme.colorScheme.primary,
                influence: theme.colorScheme.primary,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (marked != null) ...[
          Text(marked.name, style: theme.textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(marked.hint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.blur_circular,
                  size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Der Ring zeigt, wie weit der Einflussbereich reichen '
                  'sollte: bis das eigene Körperteil hineinpasst, aber '
                  'nicht das benachbarte.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
        ] else
          Text(dummy.note, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _DummyPainter extends CustomPainter {
  _DummyPainter({
    required this.dummy,
    required this.marked,
    required this.body,
    required this.joint,
    required this.influence,
  });

  final RigDummy dummy;
  final DummyJoint? marked;
  final Color body;
  final Color joint;
  final Color influence;

  @override
  void paint(Canvas canvas, Size size) {
    // Quadratischer Maßstab, damit Kreise Kreise bleiben. Die
    // Zeichnung ist 1 hoch und 1 breit (x von −0,5 bis +0,5).
    final scale = size.height < size.width ? size.height : size.width;
    final padding = scale * 0.06;
    final unit = scale - 2 * padding;
    Offset at(double x, double y) => Offset(
          size.width / 2 + x * unit,
          size.height - padding - y * unit,
        );

    final bodyPaint = Paint()
      ..color = body
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final limb in dummy.limbs) {
      bodyPaint.strokeWidth = limb.thickness * unit;
      final a = at(limb.x1, limb.y1);
      final b = at(limb.x2, limb.y2);
      // Anfang = Ende: ein Punkt mit runder Kappe wird zum Kreis.
      canvas.drawLine(a, b == a ? a.translate(0.01, 0) : b, bodyPaint);
    }

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final j in dummy.joints) {
      final center = at(j.x, j.y);
      final isMarked = identical(j, marked);
      if (isMarked) {
        canvas.drawCircle(
            center,
            j.radius * unit,
            Paint()
              ..style = PaintingStyle.fill
              ..color = influence.withValues(alpha: 0.22));
      }
      ringPaint.color =
          influence.withValues(alpha: isMarked ? 0.9 : 0.28);
      canvas.drawCircle(center, j.radius * unit, ringPaint);
      dotPaint.color = isMarked ? joint : joint.withValues(alpha: 0.55);
      canvas.drawCircle(center, isMarked ? 4.5 : 2.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_DummyPainter old) =>
      old.dummy != dummy || old.marked != marked || old.joint != joint;
}
