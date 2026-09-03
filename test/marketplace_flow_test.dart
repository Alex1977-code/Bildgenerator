import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/roblox_prompt.dart';
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

  testWidgets('beim Marktplatz-Ziel ist der Posen-Schalter gesperrt',
      (tester) async {
    // Die A-Pose steht im festen Schwanz. Ein Zusatz obendrauf stünde
    // doppelt drin und schöbe den Text über Tripos Grenze – gekürzt
    // wird hinten, und hinten stehen die Regeln. Deshalb nicht nur
    // „steht auf Keiner", sondern gesperrt.
    await starte3D(tester);
    await tester.tap(find.text('Roblox: Marktplatz-Avatar'));
    await tester.pumpAndSettle();
    final ausText = find.text('Aus Text');
    if (ausText.evaluate().isNotEmpty) {
      await tester.tap(ausText);
      await tester.pumpAndSettle();
    }
    final schalter = tester.widget<SegmentedButton<String>>(
        find.byWidgetPredicate((w) =>
            w is SegmentedButton<String> &&
            w.segments.any((seg) => seg.value == 'keine')));
    expect(schalter.selected, {'keine'});
    expect(schalter.onSelectionChanged, isNull);
    expect(find.textContaining('und ist gesperrt'), findsOneWidget);
  });

  testWidgets('die kopierte Vorlage nennt Schalter und Budget zum Ziel',
      (tester) async {
    // Als fester Text sagte die Vorlage „für eine riggbare Figur muss
    // der Schalter an sein" und „höchstens 850 Zeichen, 120 für den
    // Posen-Zusatz" – beides beim Marktplatz falsch. Jetzt steht drin,
    // was der Hinweis unter dem Feld rechnet.
    String? kopiert;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        kopiert = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await starte3D(tester);
    await tester.tap(find.text('Roblox: Marktplatz-Avatar'));
    await tester.pumpAndSettle();
    final ausText = find.text('Aus Text');
    if (ausText.evaluate().isNotEmpty) {
      await tester.tap(ausText);
      await tester.pumpAndSettle();
    }
    final knopf = find.textContaining('Prompt-Vorlage kopieren');
    expect(knopf, findsOneWidget);
    await tester.ensureVisible(knopf);
    await tester.tap(knopf);
    await tester.pumpAndSettle();
    expect(kopiert, isNotNull);
    final text = kopiert!;
    expect(text, contains('bleibt auf „Keiner"'));
    final budget = marketplacePrompt('').motifBudget;
    expect(text, contains('rund $budget Zeichen fürs Motiv'));
    for (final alt in ['850', 'muss er an sein', '[POSE UND LÄNGE]']) {
      expect(text, isNot(contains(alt)), reason: alt);
    }
  });
}
