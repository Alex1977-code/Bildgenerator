import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fragt das verbleibende Guthaben eines Providers ab – als Zahl.
///
/// Null heißt: Der Anbieter meldet kein Guthaben (fal, Rodin,
/// Replicate rechnen je Lauf ab und zeigen den Verbrauch nur im
/// Dashboard), oder die Abfrage schlug fehl. Die Anzeige ist rein
/// informativ und darf die Generierung nie stören.
Future<double?> fetchProviderCredits(
    String providerId, String apiKey) async {
  try {
    switch (providerId) {
      case 'stability':
        final r = await http.get(
          Uri.parse('https://api.stability.ai/v1/user/balance'),
          headers: {'Authorization': 'Bearer $apiKey'},
        ).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        return (jsonDecode(r.body)['credits'] as num?)?.toDouble();
      case 'meshy':
        final r = await http.get(
          Uri.parse('https://api.meshy.ai/openapi/v1/balance'),
          headers: {'Authorization': 'Bearer $apiKey'},
        ).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        return (jsonDecode(r.body)['balance'] as num?)?.toDouble();
      case 'tripo':
        final r = await http.get(
          Uri.parse('https://api.tripo3d.ai/v2/openapi/user/balance'),
          headers: {'Authorization': 'Bearer $apiKey'},
        ).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) return null;
        final data = (jsonDecode(r.body) as Map)['data'];
        return (data is Map ? data['balance'] as num? : null)?.toDouble();
      case 'fal':
        // fal.ai bietet keine öffentliche Guthaben-API – der Verbrauch
        // ist im Dashboard (fal.ai/dashboard) einsehbar.
        return null;
      case 'rodin':
        // Rodin (Hyper3D) bietet keine dokumentierte Guthaben-API –
        // der Verbrauch ist auf hyper3d.ai einsehbar.
        return null;
      case 'replicate':
        // Replicate rechnet je Lauf ab; der Verbrauch ist unter
        // replicate.com/account/billing einsehbar.
        return null;
    }
  } catch (_) {
    // Guthaben-Anzeige ist optional.
  }
  return null;
}

/// Welche Anbieter überhaupt ein Guthaben melden.
const Set<String> providersWithBalance = {'stability', 'meshy', 'tripo'};

/// Dasselbe als anzeigefertiger deutscher Satz – oder null.
Future<String?> fetchProviderBalance(
    String providerId, String apiKey) async {
  final credits = await fetchProviderCredits(providerId, apiKey);
  if (credits == null) return null;
  return switch (providerId) {
    'stability' =>
      'Stability-Guthaben: ${credits.toStringAsFixed(1)} Credits',
    'meshy' => 'Meshy-Guthaben: ${credits.toStringAsFixed(0)} Credits',
    'tripo' => 'Tripo-Guthaben: ${credits.toStringAsFixed(0)} Credits',
    _ => null,
  };
}
