import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/wait_motif.dart';
import 'package:bildgenerator/widgets/generation_progress.dart';

void main() {
  Widget rahmen(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, height: 640, child: child)),
      );

  testWidgets('Die Wartegrafik nennt, wer zeichnet', (tester) async {
    await tester.pumpWidget(rahmen(GenerationProgress(
      motif: waitMotifs['banane']!,
      label: 'Bild entsteht …',
      elapsed: const Duration(seconds: 12),
    )));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Nano Banana zeichnet …'), findsOneWidget);
    expect(find.text('Bild entsteht …'), findsOneWidget);
    expect(find.text('12 s'), findsOneWidget);
    // Ein paar Bilder weiterlaufen lassen: Der Painter darf in keiner
    // Phase stolpern.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mit echter Vorschau steht kein Motivname da',
      (tester) async {
    // Ein 1x1-PNG.
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0,
      0x1F, 0x15, 0xC4, 0x89, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99,
      0, 1, 0, 0, 5, 0, 1, 13, 0x0A, 0x2D, 0xB4, 0, 0, 0, 0, 73, 69, 78,
      68, 0xAE, 0x42, 0x60, 0x82,
    ]);
    await tester.pumpWidget(rahmen(GenerationProgress(
      motif: waitMotifs['banane']!,
      preview: png,
      step: 7,
      totalSteps: 28,
    )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Nano Banana zeichnet …'), findsNothing);
    expect(find.textContaining('Schritt 7/28'), findsOneWidget);
  });
}
