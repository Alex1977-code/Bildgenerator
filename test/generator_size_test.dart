import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/settings_service.dart';
import 'package:bildgenerator/widgets/option_card.dart';

/// Die Pixelangabe an der Format-Karte.
///
/// Vorher stand sie im geschlossenen Dropdown-Feld und verschwand
/// dort, wenn sich nur die Zahl änderte (anderes Modell, andere
/// Auflösung), nicht die Auswahl. Jetzt steht sie als Zeile auf der
/// Karte – und muss bei jeder Änderung mitgehen.
Iterable<String> _formatKarte(WidgetTester tester) {
  final karte = find.ancestor(
      of: find.text('FORMAT'), matching: find.byType(OptionCard));
  return tester
      .widgetList<Text>(find.descendant(of: karte, matching: find.byType(Text)))
      .map((t) => t.data ?? '');
}

/// Öffnet die Format-Karte und wählt den Eintrag, der [teil] enthält.
Future<void> _waehleFormat(WidgetTester tester, String teil) async {
  await tester.tap(find.text('FORMAT'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(teil).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fertig'));
  await tester.pumpAndSettle();
}

Future<SettingsService> _start(
    WidgetTester tester, void Function(SettingsService) einrichten) async {
  tester.view.physicalSize = const Size(1400, 1100);
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
  group('Pixelangabe an der Format-Karte', () {
    testWidgets('Eigener Server: die Angabe steht da und bleibt stehen',
        (tester) async {
      final settings =
          await _start(tester, (s) => s.setProvider(GenProvider.selfhost));
      // sdxl-turbo rechnet mit 512.
      expect(_formatKarte(tester), contains('Quadrat 1:1'));
      expect(_formatKarte(tester), contains('512×512 px · PNG'));
      await _waehleFormat(tester, 'Breitbild');
      expect(_formatKarte(tester), contains('Breitbild 16:9'));
      expect(_formatKarte(tester), contains('704×384 px · PNG'));
      expect(settings.stabilityAspect, '16:9');
    });

    testWidgets('Ein anderes Modell ändert die Angabe auf der Karte',
        (tester) async {
      final settings =
          await _start(tester, (s) => s.setProvider(GenProvider.selfhost));
      expect(_formatKarte(tester), contains('512×512 px · PNG'));
      // SDXL rechnet mit 1024.
      settings.setModelFor(GenProvider.selfhost, 'sdxl');
      await tester.pumpAndSettle();
      expect(_formatKarte(tester), contains('1024×1024 px · PNG'));
    });

    testWidgets('Gemini Pro: die Auflösung wirkt auf die Karte',
        (tester) async {
      await _start(tester, (s) {
        s.setProvider(GenProvider.gemini);
        s.setModelFor(GenProvider.gemini, 'gemini-3-pro-image-preview');
      });
      expect(_formatKarte(tester), contains('1024×1024 px · 1K'));
      await tester.tap(find.text('FORMAT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2K'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();
      expect(_formatKarte(tester), contains('2048×2048 px · 2K'));
    });

    testWidgets('Stability: die Angabe überlebt das Umschalten',
        (tester) async {
      await _start(tester, (s) => s.setProvider(GenProvider.stability));
      expect(_formatKarte(tester).any((t) => t.contains(' px')), isTrue);
      await _waehleFormat(tester, 'Hochkant');
      expect(_formatKarte(tester), contains('Hochkant 9:16'));
      expect(_formatKarte(tester), contains('ca. 896×1600 px · PNG'));
    });

    testWidgets('OpenAI: „Automatisch" sagt, warum keine Zahl dasteht',
        (tester) async {
      await _start(tester, (s) => s.setProvider(GenProvider.openai));
      await _waehleFormat(tester, 'Automatisch');
      expect(_formatKarte(tester), contains('Automatisch (das Modell wählt)'));
      await _waehleFormat(tester, 'Querformat');
      expect(_formatKarte(tester), contains('Querformat 1536×1024'));
    });
  });
}
