import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/run_queue.dart';
import 'package:bildgenerator/services/settings_service.dart';
import 'package:bildgenerator/widgets/app_header.dart';
import 'package:bildgenerator/widgets/option_card.dart';

/// Der aufgeräumte Bild-Tab (Entwurf 1a): Kopfzeile, vier Karten,
/// Kosten im Knopf, Warteschlange in der Leiste – und auf dem Handy
/// dieselbe Sprache.
void main() {
  Future<SettingsService> start(WidgetTester tester,
      {Size size = const Size(1400, 1000),
      RunQueue? queue,
      void Function(SettingsService)? einrichten}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    final history = HistoryService(store: MemoryHistoryStore());
    await settings.init();
    await history.init();
    einrichten?.call(settings);
    await tester.pumpWidget(BildgeneratorApp(
        settings: settings, history: history, queue: queue));
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('Desktop: Kopfzeile, vier Karten und der Knopf mit Kosten',
      (tester) async {
    await start(tester, einrichten: (s) => s.setProvider(GenProvider.gemini));
    // Kopfzeile: Projekt und Guthaben.
    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.text('Projekt '), findsOneWidget);
    expect(find.text('Guthaben'), findsOneWidget);
    // Die vier Karten.
    for (final label in ['KI-MODELL', 'FORMAT', 'ANZAHL', 'QUALITÄTSSTUFE']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byType(QualityBars), findsWidgets);
    // Nano Banana: 0,039 $ je Bild, ein Bild – der Knopf sagt es.
    expect(find.text('1 Bild · '), findsOneWidget);
    expect(find.text('≈ 0,04 \$'), findsOneWidget);
    expect(find.textContaining('Schätzwert, echter Abzug'), findsOneWidget);
    expect(find.text('Lauf starten'), findsOneWidget);
    // Der Umschalter.
    expect(find.text('Massenprompt'), findsOneWidget);
    expect(find.text('Einzelbild'), findsOneWidget);
    // Die Warteschlange in der Leiste, leer.
    expect(find.text('Lauf'), findsOneWidget);
  });

  testWidgets('Massenprompt: Zähler, Tabelle und Kosten folgen dem Text',
      (tester) async {
    await start(tester, einrichten: (s) => s.setProvider(GenProvider.gemini));
    await tester.tap(find.text('Massenprompt'));
    await tester.pumpAndSettle();
    expect(find.text('0 Blöcke · 0 Bilder'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first,
        'NAME: ic3-01-siedler\nPROMPT: low-poly settler\n---\n'
        'NAME: ic3-02-erz\nPROMPT: pickaxe in a rock');
    await tester.pumpAndSettle();
    expect(find.text('2 Blöcke · 2 Bilder'), findsOneWidget);
    expect(find.text('2 Bilder · '), findsOneWidget);
    expect(find.text('≈ 0,08 \$'), findsOneWidget);
    // Als Tabelle: eine Zeile je Block, mit Nummer.
    await tester.tap(find.text('Als Tabelle'));
    await tester.pumpAndSettle();
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.textContaining('Neuer Block', findRichText: true),
        findsOneWidget);
    // Im Massenprompt ist die Anzahl je Block fest.
    expect(find.text('ANZAHL JE BLOCK'), findsOneWidget);
    expect(find.text('je Block genau ein Bild'), findsOneWidget);
  });

  testWidgets('die Warteschlange zeigt sich in der Leiste', (tester) async {
    final queue = RunQueue(persistent: false);
    await start(tester, queue: queue);
    final job = queue.add(
        name: 'ic3-03-fackel', kind: RunJobKind.image, provider: 'Nano Banana');
    queue.start(job.id);
    // Kein pumpAndSettle: Der Ring in der Leiste dreht sich, solange
    // etwas läuft – das kommt nie zur Ruhe.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 Lauf'), findsOneWidget);
    expect(find.text('1 läuft'), findsOneWidget);
    queue.finish(job.id);
    await tester.pumpAndSettle();
    expect(find.text('Lauf'), findsOneWidget);
  });

  testWidgets('Handy: Titelzeile, Feld unten, Knopf mit Anzahl',
      (tester) async {
    await start(tester,
        size: const Size(390, 844),
        einrichten: (s) => s.setProvider(GenProvider.gemini));
    // Keine Kopfzeile, dafür der Titel im Tab.
    expect(find.byType(AppHeader), findsNothing);
    expect(find.text('Bild'), findsWidgets);
    expect(find.text('Referenz'), findsOneWidget);
    expect(find.text('Vorlage'), findsOneWidget);
    expect(find.text('wechseln ▸'), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);
    expect(find.text('1 Bild generieren'), findsOneWidget);
    expect(find.text('Mehr Optionen'), findsOneWidget);
    // Unten heißt es „Mehr", nicht „Einstellungen".
    expect(find.text('Mehr'), findsOneWidget);
  });
}
