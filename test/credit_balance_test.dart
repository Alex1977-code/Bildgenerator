import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/credit_balance.dart';
import 'package:bildgenerator/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Guthaben-Anzeige in der Kopfzeile sagt, was sie weiß – und
/// benennt, was sie nicht wissen kann.
void main() {
  Future<SettingsService> einstellungen() async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsService(keyStore: InMemoryKeyStore());
    await s.init();
    return s;
  }

  test('ohne Schlüssel steht das auch da', () async {
    final s = await einstellungen();
    s.setProvider(GenProvider.gemini);
    s.setThreeDProvider('tripo');
    final parts = balanceChipParts(s, CreditBalances());
    expect(parts.map((p) => p.label), ['Gemini', 'Tripo3D']);
    expect(parts[0].value, 'kein Schlüssel');
    expect(parts[0].warning, isTrue);
    expect(parts[1].value, 'kein Schlüssel');
  });

  test('Gemini hat keine Guthaben-API – dann zählt der Schlüssel',
      () async {
    final s = await einstellungen();
    s.setProvider(GenProvider.gemini);
    await s.setApiKey(GenProvider.gemini, 'g-key');
    s.setThreeDProvider('local');
    final parts = balanceChipParts(s, CreditBalances());
    expect(parts[0].value, 'Schlüssel ✓');
    expect(parts[0].warning, isFalse);
    expect(parts[1].label, '3D lokal');
    expect(parts[1].value, '0 \$');
  });

  test('Tripo meldet Credits, und die Zahl kommt aus der Abfrage',
      () async {
    final s = await einstellungen();
    s.setProvider(GenProvider.selfhost);
    s.setThreeDProvider('tripo');
    await s.setTripoApiKey('t-key');
    final gefragt = <String>[];
    final b = CreditBalances(fetch: (id, key) async {
      gefragt.add('$id:$key');
      return id == 'tripo' ? 742 : null;
    });
    await b.refresh(s);
    // Nur die Anbieter mit Schlüssel werden gefragt.
    expect(gefragt, ['tripo:t-key']);
    expect(b.lastRefresh, isNotNull);
    final parts = balanceChipParts(s, b);
    expect(parts[0].label, 'Eigene GPU');
    expect(parts[0].value, '0 \$');
    expect(parts[1].label, 'Tripo3D');
    expect(parts[1].value, '742 Cr.');
  });

  test('ein Lauf liefert das Restguthaben mit – ohne neue Abfrage',
      () async {
    final s = await einstellungen();
    s.setProvider(GenProvider.stability);
    await s.setApiKey(GenProvider.stability, 's-key');
    s.setThreeDProvider('stability');
    final b = CreditBalances(fetch: (_, _) async => null);
    b.noteRemaining('stability', 17.5);
    final parts = balanceChipParts(s, b);
    // Stability als Bild- und 3D-Anbieter steht nur einmal da.
    expect(parts.length, 1);
    expect(parts[0].value, '17.5 Cr.');
  });

  test('Anbieter ohne Guthaben-API: „je Lauf"', () async {
    final s = await einstellungen();
    s.setProvider(GenProvider.selfhost);
    s.setThreeDProvider('fal');
    await s.setFalApiKey('f');
    final parts = balanceChipParts(s, CreditBalances());
    expect(parts[1].label, 'fal.ai');
    expect(parts[1].value, 'je Lauf');
  });
}
