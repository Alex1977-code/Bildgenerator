import 'dart:async';

import 'package:http/http.dart' as http;

import 'generators.dart' show GenerationException;

/// Prüft einen API-Schlüssel mit einer günstigen, harmlosen Anfrage
/// (Modell-Liste bzw. Guthaben – kostet keine Credits). Kehrt bei
/// gültigem Schlüssel normal zurück, sonst fliegt eine
/// [GenerationException] mit verständlicher Meldung.
Future<void> validateApiKey(String provider, String apiKey) async {
  final (url, headers) = switch (provider) {
    'openai' => (
        Uri.parse('https://api.openai.com/v1/models'),
        {'Authorization': 'Bearer $apiKey'},
      ),
    'stability' => (
        Uri.parse('https://api.stability.ai/v1/user/balance'),
        {'Authorization': 'Bearer $apiKey'},
      ),
    'gemini' => (
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/'
            'models?pageSize=1&key=$apiKey'),
        const <String, String>{},
      ),
    'meshy' => (
        Uri.parse('https://api.meshy.ai/openapi/v2/text-to-3d'
            '?page_size=1'),
        {'Authorization': 'Bearer $apiKey'},
      ),
    'tripo' => (
        Uri.parse('https://api.tripo3d.ai/v2/openapi/user/balance'),
        {'Authorization': 'Bearer $apiKey'},
      ),
    // fal.ai hat keinen kostenlosen Info-Endpunkt – eine Status-Abfrage
    // zu einer nicht existierenden Anfrage prüft trotzdem die
    // Authentifizierung (404 = Schlüssel gültig, 401/403 = ungültig).
    'fal' => (
        Uri.parse('https://queue.fal.run/fal-ai/trellis/requests/'
            '00000000-0000-0000-0000-000000000000/status'),
        {'Authorization': 'Key $apiKey'},
      ),
    _ => throw GenerationException('Unbekannter Anbieter.'),
  };

  http.Response response;
  try {
    response = await http
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    throw GenerationException(
        'Prüfung nicht möglich – Netzwerkfehler: $e');
  }
  if (response.statusCode == 200) return;
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw GenerationException(
        'Der Schlüssel wurde abgelehnt (${response.statusCode}) – '
        'bitte auf Tippfehler prüfen und neu einfügen.');
  }
  // fal: jede andere Antwort < 500 heißt, die Authentifizierung hat
  // gepasst (die Test-Anfrage selbst ist absichtlich unbekannt).
  if (provider == 'fal' && response.statusCode < 500) return;
  throw GenerationException(
      'Unerwartete Antwort (${response.statusCode}) – der Schlüssel '
      'konnte nicht bestätigt werden.');
}
