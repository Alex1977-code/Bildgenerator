import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bildgenerator/main.dart';
import 'package:bildgenerator/services/history/history_store_memory.dart';
import 'package:bildgenerator/services/history_service.dart';
import 'package:bildgenerator/services/settings_service.dart';

void main() {
  testWidgets('Nach dem Anlegen bleibt die Ansicht stehen',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    final history = HistoryService(store: MemoryHistoryStore());
    await settings.init();
    await history.init();
    await history.addModel(
      glbBytes: Uint8List.fromList(const [1, 2, 3]),
      label: 'Turm',
      providerLabel: 'Test',
    );

    await tester.pumpWidget(
        BildgeneratorApp(settings: settings, history: history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Neues Projekt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Burgenspiel');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Der Ordner ist da …
    expect(history.emptyProjects, contains('Burgenspiel'));
    // … aber wir stehen weiter oben. Vorher landete man mit Enter im
    // leeren Ordner und musste erst wieder heraus.
    expect(find.text('Turm'), findsWidgets,
        reason: 'Die Kacheln der Ebene sind weiterhin zu sehen');
    expect(find.text('Neues Projekt'), findsOneWidget,
        reason: 'Auf oberster Ebene heißt der Knopf „Neues Projekt"');
    // Und der Hinweis bietet den Weg hinein an.
    expect(find.text('Öffnen'), findsOneWidget);
  });

  testWidgets('Ein angelegter, noch leerer Ordner steht in „Einsortieren"',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    final history = HistoryService(store: MemoryHistoryStore());
    await settings.init();
    await history.init();

    // Ein Eintrag, damit es etwas zum Einsortieren gibt …
    await history.addModel(
      glbBytes: Uint8List.fromList(const [1, 2, 3]),
      label: 'Turm',
      providerLabel: 'Test',
    );
    // … und zwei Ordner: einer mit Inhalt, einer frisch angelegt und
    // noch leer. Der zweite fehlte bisher in der Auswahl.
    await history.createProject('Burgenspiel');
    await history.moveToProject(history.entries, 'Burgenspiel');
    await history.createProject('Raumschiff');

    await tester.pumpWidget(
        BildgeneratorApp(settings: settings, history: history));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie').last);
    await tester.pumpAndSettle();

    // Beide Ordner sind angelegt – der leere zählt null.
    expect(history.emptyProjects, contains('Raumschiff'));

    await tester.tap(find.text('Auswählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turm').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einsortieren …'));
    await tester.pumpAndSettle();

    Finder imDialog(String name) => find.descendant(
        of: find.byType(SimpleDialog), matching: find.text(name));
    expect(imDialog('Burgenspiel'), findsOneWidget);
    expect(imDialog('Raumschiff'), findsOneWidget,
        reason: 'Der leere Ordner fehlte in der Auswahl');
  });
}
