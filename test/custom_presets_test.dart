import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/settings_service.dart';

void main() {
  test('Eigene Vorlagen: 5 Plätze, belegen, überschreiben, löschen', () {
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    expect(settings.customPresets.length, SettingsService.customPresetSlots);
    expect(settings.customPresets.every((e) => e.isEmpty), isTrue,
        reason: 'am Anfang sind alle Plätze frei');

    settings.setCustomPreset(0, '{"name":"Batmobil"}');
    settings.setCustomPreset(4, '{"name":"Druck"}');
    expect(settings.customPresets[0], '{"name":"Batmobil"}');
    expect(settings.customPresets[4], '{"name":"Druck"}');
    expect(settings.customPresets[1], isEmpty);

    // Überschreiben belegt denselben Platz erneut.
    settings.setCustomPreset(0, '{"name":"Batmobil v2"}');
    expect(settings.customPresets[0], '{"name":"Batmobil v2"}');

    // Leerer Text gibt den Platz wieder frei.
    settings.setCustomPreset(0, '');
    expect(settings.customPresets[0], isEmpty);
    expect(settings.customPresets[4], '{"name":"Druck"}');
  });

  test('Eigene Vorlagen: Plätze außerhalb des Bereichs ändern nichts', () {
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    settings.setCustomPreset(-1, '{"name":"x"}');
    settings.setCustomPreset(SettingsService.customPresetSlots, '{"n":1}');
    expect(settings.customPresets.every((e) => e.isEmpty), isTrue);
  });

  test('Eigene Vorlagen melden Änderungen an die Oberfläche', () {
    final settings = SettingsService(keyStore: InMemoryKeyStore());
    var notified = 0;
    settings.addListener(() => notified++);
    settings.setCustomPreset(2, '{"name":"Figur"}');
    expect(notified, 1);
  });
}
