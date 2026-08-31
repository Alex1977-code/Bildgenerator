import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/settings_service.dart';

/// Der Text, der im geschlossenen Feld steht – das ist die Stelle, an
/// der die Pixelangabe verschwand.
String _feld(WidgetTester tester, String label) {
  final menu = find.ancestor(
      of: find.text(label), matching: find.byType(DropdownMenu<String>));
  final feld = find.descendant(of: menu, matching: find.byType(TextField));
  return tester.widget<TextField>(feld.first).controller!.text;
}

Future<void> _waehle(
    WidgetTester tester, String label, String teil) async {
  await tester.tap(find.ancestor(
      of: find.text(label), matching: find.byType(DropdownMenu<String>)));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(teil).last);
  await tester.pumpAndSettle();
}

Future<SettingsService> _start(
    WidgetTester tester, void Function(SettingsService) einrichten) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService(keyStore: InMemoryKeyStore());
  final history = HistoryService(store: MemoryHistoryStore());
  await settings.init();
  await history.init();
  einrichten(settings);
  await tester
      .pumpWidget(BildgeneratorApp(settings: settings, history: history));
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  group('Pixelangabe im Größen-Dropdown', () {
    testWidgets('Eigener Server: die Angabe steht da und bleibt stehen',
        (tester) async {
      final settings =
          await _start(tester, (s) => s.setProvider(GenProvider.selfhost));
      // sdxl-turbo rechnet mit 512.
      expect(_feld(tester, 'Seitenverhältnis'),
          'Quadrat (1:1) · 512×512 px');
      await _waehle(tester, 'Seitenverhältnis', 'Breitbild');
      expect(_feld(tester, 'Seitenverhältnis'),
          'Breitbild (16:9) · 704×384 px');
      expect(settings.stabilityAspect, '16:9');
    });

    testWidgets('Ein anderes Modell ändert die Angabe im Feld',
        (tester) async {
      final settings =
          await _start(tester, (s) => s.setProvider(GenProvider.selfhost));
      expect(_feld(tester, 'Seitenverhältnis'),
          'Quadrat (1:1) · 512×512 px');
      // SDXL rechnet mit 1024. Vorher blieb im geschlossenen Feld die
      // alte Zahl stehen: DropdownMenu schreibt seinen Text nur bei
      // geänderter Auswahl nach, und die Auswahl war ja dieselbe.
      settings.setModelFor(GenProvider.selfhost, 'sdxl');
      await tester.pumpAndSettle();
      expect(_feld(tester, 'Seitenverhältnis'),
          'Quadrat (1:1) · 1024×1024 px');
    });

    testWidgets('Gemini Pro: die Auflösung wirkt auf beide Felder',
        (tester) async {
      await _start(tester, (s) {
        s.setProvider(GenProvider.gemini);
        s.setModelFor(GenProvider.gemini, 'gemini-3-pro-image-preview');
      });
      expect(_feld(tester, 'Seitenverhältnis'),
          'Quadrat (1:1) · 1024×1024 px');
      await _waehle(tester, 'Auflösung', '2K');
      expect(_feld(tester, 'Auflösung'), '2K · 2048×2048 px');
      expect(_feld(tester, 'Seitenverhältnis'),
          'Quadrat (1:1) · 2048×2048 px');
    });

    testWidgets('Stability: die Angabe überlebt das Umschalten',
        (tester) async {
      await _start(tester, (s) => s.setProvider(GenProvider.stability));
      expect(_feld(tester, 'Seitenverhältnis'), contains(' px'));
      await _waehle(tester, 'Seitenverhältnis', 'Hochkant');
      expect(_feld(tester, 'Seitenverhältnis'),
          'Hochkant (9:16) · ca. 896×1600 px');
    });

    testWidgets('OpenAI: „Automatisch" sagt, warum keine Zahl dasteht',
        (tester) async {
      await _start(tester, (s) => s.setProvider(GenProvider.openai));
      await _waehle(tester, 'Bildgröße', 'Automatisch');
      expect(_feld(tester, 'Bildgröße'), 'Automatisch (das Modell wählt)');
      await _waehle(tester, 'Bildgröße', 'Querformat');
      expect(_feld(tester, 'Bildgröße'), 'Querformat (1536×1024)');
    });
  });
}
