import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Schachbrettmuster als Hintergrund, damit Transparenz sichtbar wird.
class CheckerboardPainter extends CustomPainter {
  CheckerboardPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 10.0;
    final light = Paint()
      ..color = dark ? const Color(0xFF3A3A3A) : const Color(0xFFF2F2F2);
    final shade = Paint()
      ..color = dark ? const Color(0xFF2C2C2C) : const Color(0xFFD9D9D9);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if ((x + y).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          shade,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

/// Zeigt Bildbytes auf einem Schachbrett-Hintergrund an.
class CheckerboardImage extends StatelessWidget {
  const CheckerboardImage({super.key, required this.bytes, this.fit});

  final Uint8List bytes;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: CheckerboardPainter(dark: dark),
      child: Image.memory(
        bytes,
        fit: fit ?? BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}

/// Abschnittsüberschrift innerhalb der Options-Karten.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
