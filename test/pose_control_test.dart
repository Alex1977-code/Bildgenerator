import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/settings_service.dart';

/// Der Posen-Zusatz steht für sich.
///
/// Vorher waren es zwei Bedienelemente: ein Schalter „Pose-Zusatz",
/// den eingeschaltetes Rigging erzwang und dann ausgraute, und daneben
/// die Wahl zwischen T und A. Wer eine geriggte Figur ohne Zusatz
/// wollte, kam nicht hin; wo der Schalter aus war, war die Wahl
/// unsichtbar. Diese Tests halten den neuen Zustand fest.
void main() {
  Future<void> starte3D(WidgetTester tester) async {
    // Großes Fenster statt Scrollen: Die 3D-Seite ist lang, und ein
    // Test, der sich durchscrollt, misst am Ende die Scrollmechanik.
    tester.view.physicalSize = const Size(1400, 2600);
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
    // In den 3D-Bereich – über die Leiste, nicht über den Inhalt.
    final ziel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('3D'),
    );
    await tester.tap(ziel.first);
    await tester.pumpAndSettle();
    // In den Text-Modus: Der Posen-Zusatz gehört zum Prompt, und den
    // gibt es nur dort. „Aus Bild" ist der Ausgangszustand.
    await tester.tap(find.text('Aus Text'));
    await tester.pumpAndSettle();
  }

  /// Schaltet das eigene Auto-Rigging aus.
  ///
  /// Beim Ausgangsanbieter „Lokal" ist es an, und dann kommt die Pose
  /// aus dem Figurtyp – der Zusatz bleibt außen vor. Das ist so
  /// gewollt und in einem eigenen Test festgehalten.
  Future<void> riggingAus(WidgetTester tester) async {
    await tester.tap(find.text('Rigging (Skelett für Animation)').first);
    await tester.pumpAndSettle();
  }

  testWidgets('beim eigenen Auto-Rigging entscheidet der Figurtyp',
      (tester) async {
    // Der Ausgangszustand: Anbieter „Lokal", Rigging an. Dort erzeugt
    // die App die Ansichten selbst und nimmt die Pose zum Figurtyp –
    // ein Zusatz daneben würde ihr widersprechen. Der Schalter steht
    // trotzdem da, gesperrt und mit Begründung.
    await starte3D(tester);
    expect(find.text('Posen-Zusatz'), findsOneWidget);
    expect(find.textContaining('kommt die Pose aus dem Figurtyp'),
        findsOneWidget);
  });

  testWidgets('drei Werte, und keiner ist der Ausgangszustand',
      (tester) async {
    await starte3D(tester);
    await riggingAus(tester);
    for (final label in ['Keiner', 'T-Pose', 'A-Pose']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Ohne Rigging steht der Zusatz auf „keiner", und der Hinweis
    // sagt, was das kostet.
    expect(find.textContaining('Kein Zusatz'), findsOneWidget);
  });

  testWidgets('die Wahl lässt sich ohne Rigging treffen', (tester) async {
    await starte3D(tester);
    await riggingAus(tester);
    await tester.tap(find.text('A-Pose'));
    await tester.pumpAndSettle();
    // Der Hinweistext folgt der Wahl – und nennt die A-Pose-Gründe.
    expect(find.textContaining('45°'), findsOneWidget);
    expect(find.textContaining('Auto Setup'), findsWidgets);

    await tester.tap(find.text('Keiner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kein Zusatz'), findsOneWidget);
  });

  testWidgets('Rigging setzt die Pose vor, erzwingt sie aber nicht',
      (tester) async {
    // Bei Meshy/Tripo geht der Zusatz in den Prompt, dort ist der
    // Schalter also bedienbar. Genau da lag die Lücke: Rigging schaltete
    // den Zusatz ein und graute ihn aus.
    await starte3D(tester);
    await tester.tap(find.text('Tripo3D'));
    await tester.pumpAndSettle();
    await riggingAus(tester);
    await tester.tap(find.text('Keiner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kein Zusatz'), findsOneWidget);

    // Rigging an: Die App setzt die T-Pose vor.
    await tester.tap(find.text('Rigging (Skelett für Animation)').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Arme waagerecht'), findsOneWidget);

    // Und sie bleibt abwählbar – genau das ging vorher nicht.
    await tester.tap(find.text('Keiner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kein Zusatz'), findsOneWidget);
    // Dann sagt die App, was das für das Skelett bedeutet.
    expect(find.textContaining('Rigging ist an, aber keine Pose'),
        findsOneWidget);
  });
}
