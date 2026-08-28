import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/settings_service.dart';

void main() {
  testWidgets('App startet und zeigt die Hauptbereiche',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    final history = HistoryService(store: MemoryHistoryStore());
    await settings.init();
    await history.init();

    await tester.pumpWidget(
        BildgeneratorApp(settings: settings, history: history));
    await tester.pumpAndSettle();

    expect(find.text('Bildgenerator'), findsOneWidget);
    expect(find.text('Generator'), findsWidgets);
    expect(find.text('Galerie'), findsWidgets);
    expect(find.text('Einstellungen'), findsWidgets);
    expect(find.byType(TextField), findsWidgets);
  });
}
