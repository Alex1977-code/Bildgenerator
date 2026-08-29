import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fragt das verbleibende Guthaben eines 3D-Providers ab und liefert
/// einen anzeigefertigen deutschen Text – oder null, wenn der Anbieter
/// kein Guthaben meldet oder die Abfrage fehlschlägt (die Anzeige ist
/// rein informativ und darf die Generierung nie stören).
Future<String?> fetchProviderBalance(
    String providerId, String apiKey) async {
  try {
    switch (providerId) {
      case 'stability':
        final r = await http.get(
          Uri.parse('https://api.stability.ai/v1/user/balance'),
          headers: {'Authorization': 'Bearer $apiKey'},
        ).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        final credits =
            (jsonDecode(r.body)['credits'] as num?)?.toDouble();
        if (credits == null) return null;
        return 'Stability-Guthaben: ${credits.toStringAsFixed(1)} Credits';
      case 'meshy':
        final r = await http.get(
          Uri.parse('https://api.meshy.ai/openapi/v1/balance'),
          headers: {'Authorization': 'Bearer $apiKey'},
        ).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        final balance =
            (jsonDecode(r.body)['balance'] as num?)?.toDouble();
        if (balance == null) return null;
        return 'Meshy-Guthaben: ${balance.toStringAsFixed(0)} Credits';
      case 'tripo':
        final r = await http.get(
          Uri.parse('https://api.tripo3d.ai/v2/openapi/user/balance'),
          headers: {'Authorization': 'Bearer $apiKey'},
        ).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        final data = (jsonDecode(r.body) as Map)['data'];
        final balance =
            (data is Map ? data['balance'] as num? : null)?.toDouble();
        if (balance == null) return null;
        return 'Tripo-Guthaben: ${balance.toStringAsFixed(0)} Credits';
    }
  } catch (_) {
    // Guthaben-Anzeige ist optional.
  }
  return null;
}
