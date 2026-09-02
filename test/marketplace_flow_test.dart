import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/settings_service.dart';

/// Aus dem Text eine Marktplatz-Figur: Die Vorlage „Roblox:
/// Marktplatz-Avatar" muss den festen Schwanz an den Prompt binden –
/// sichtbar im Hinweis unter dem Feld, der den **fertigen** Text
/// zählt. Vorher stand der Schwanz nur in der kopierbaren Vorlage, und
/// wer ihn nicht zurückholte, schickte ein nacktes Motiv.
void main() {
  Future<void> starte3D(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    final history = HistoryService(store: MemoryHistoryStore());
    await settings.init();
    await history.init();
    await tester.pumpWidget(
        BildgeneratorApp(settings: settings, history: history));
    await tester.pumpAndSettle();
    final ziel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('3D'),
    );
    await tester.tap(ziel.first);
    await tester.pumpAndSettle();
  }

  testWidgets('die Marktplatz-Vorlage bindet den festen Schwanz an den '
      'Prompt', (tester) async {
    await starte3D(tester);
    await tester.tap(find.text('Roblox: Marktplatz-Avatar'));
    await tester.pumpAndSettle();
    // Die Vorlage schaltet auf Text; falls nicht, hier nachhelfen.
    final ausText = find.text('Aus Text');
    if (ausText.evaluate().isNotEmpty) {
      await tester.tap(ausText);
      await tester.pumpAndSettle();
    }
    // Der Hinweis unter dem Prompt-Feld nennt den Schwanz und das
    // Motiv-Budget – das ist die Zeile, die vorher fehlte.
    expect(find.textContaining('Marktplatz-Schwanz'), findsOneWidget);
    // Mit der A-Pose darin – die App hängt keine zweite an.
    expect(find.textContaining('A-Pose enthalten'), findsOneWidget);
  });
}
