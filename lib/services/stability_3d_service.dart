import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'generators.dart' show GenerationException;

/// Stability AI 3D: trainierte generative Modelle (Stable Fast 3D und
/// Stable Point Aware 3D), die aus einem einzelnen Bild ein komplettes
/// 3D-Modell rekonstruieren – inklusive Rückseite, Vertiefungen und
/// Hohlräumen, die das Bild nicht zeigt.
///
/// Die Antwort kommt synchron als binäres GLB (kein Task-Polling).
/// Es wird derselbe API-Schlüssel wie für die Stability-Bilderzeugung
/// genutzt.
class Stability3dService {
  Stability3dService(this.apiKey);

  final String apiKey;

  static const _base = 'https://api.stability.ai/v2beta/3d';

  /// Engine-Optionen: (API-Pfad, Anzeigename).
  static const engines = [
    (
      'stable-point-aware-3d',
      'Point Aware 3D – beste Qualität, formt Rückseite & Hohlräume'
    ),
    ('stable-fast-3d', 'Fast 3D – besonders schnell'),
  ];

  Never _throwNetworkError(Object e) {
    throw GenerationException(
      'Netzwerkfehler: $e\n'
      'Bitte Internetverbindung prüfen. Hinweis: Im Browser (Web-Version) '
      'können CORS-Beschränkungen Anfragen blockieren – die nativen Apps '
      'sind davon nicht betroffen.',
    );
  }

  GenerationException _error(int status, Uint8List body) {
    var detail = '';
    try {
      final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      final errors = json['errors'];
      detail = errors is List
          ? errors.join(' ')
          : (json['message'] ?? json['name'] ?? '').toString();
    } catch (_) {
      detail = utf8.decode(body, allowMalformed: true);
      if (detail.length > 300) detail = detail.substring(0, 300);
    }
    var hint = '';
    if (status == 401 || status == 403) {
      hint = ' Bitte den Stability-AI-Schlüssel in den Einstellungen '
          'prüfen (derselbe wie für die Bilderzeugung).';
    } else if (status == 402 ||
        detail.toLowerCase().contains('credit') ||
        detail.toLowerCase().contains('balance')) {
      hint = '\n\nHinweis: Vermutlich sind die Stability-Credits '
          'aufgebraucht – unter platform.stability.ai aufladen.';
    }
    return GenerationException('Stability-3D-Fehler ($status): $detail$hint');
  }

  /// Erzeugt aus einem Bild ein GLB-Modell.
  Future<Uint8List> generateModel({
    required Uint8List imageBytes,
    required String mimeType,
    required String engine,
    int textureResolution = 1024,
    bool quadRemesh = false,
  }) async {
    final subtype = mimeType.split('/').last;
    final request = http.MultipartRequest('POST', Uri.parse('$_base/$engine'))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['texture_resolution'] = '$textureResolution'
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'vorlage.${subtype == 'jpeg' ? 'jpg' : subtype}',
        contentType: MediaType('image', subtype),
      ));
    if (quadRemesh) request.fields['remesh'] = 'quad';

    http.Response response;
    try {
      response = await http.Response.fromStream(await request.send());
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw _error(response.statusCode, response.bodyBytes);
    }
    final bytes = response.bodyBytes;
    // GLB beginnt mit dem Magic "glTF".
    if (bytes.length < 12 ||
        ByteData.sublistView(bytes).getUint32(0, Endian.little) !=
            0x46546C67) {
      throw GenerationException(
          'Stability hat keine gültige GLB-Datei zurückgegeben.');
    }
    return bytes;
  }
}
