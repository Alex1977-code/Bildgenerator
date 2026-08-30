import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'generators.dart' show GenerationException;

/// Anbindung an den eigenen 3D-Server (server/local3d_server.py):
/// MIT-lizenzierte Open-Source-Modelle (TripoSR, TRELLIS) auf dem
/// eigenen PC mit NVIDIA-GPU – kostenlos, alle Daten bleiben lokal.
/// Die App schickt die Vorderansicht, der Server antwortet direkt mit
/// der fertigen GLB-Datei.
class SelfHostService {
  SelfHostService(String baseUrl) : baseUrl = normalizeBaseUrl(baseUrl);

  final String baseUrl;

  /// „127.0.0.1:8765/“ → „http://127.0.0.1:8765“ (Schema ergänzen,
  /// Slashes am Ende entfernen).
  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isNotEmpty &&
        !u.startsWith('http://') &&
        !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u;
  }

  Never _throwNetworkError(Object e) {
    throw GenerationException(
      'Der eigene 3D-Server ist nicht erreichbar: $e\n'
      'Läuft der Server (python local3d_server.py) und stimmt die '
      'Adresse in den Einstellungen? Bei einem anderen PC im Netzwerk '
      'auch die Firewall prüfen (Anleitung: server/README.md).',
    );
  }

  String _readError(http.Response response) {
    var detail = '';
    try {
      final json = jsonDecode(response.body);
      detail = (json is Map ? json['detail']?.toString() : null) ??
          response.body;
    } catch (_) {
      detail = response.body;
    }
    return 'Server-Fehler (${response.statusCode}): $detail';
  }

  /// Was das laufende Backend kann (z. B. 'multiview',
  /// 'texture_resolution', 'remesh', 'target_count',
  /// 'resolution', 'bake_texture') – der 3D-Tab blendet danach
  /// seine Bedienelemente ein. Wird von [health] gefüllt.
  static List<String> lastCapabilities = const [];

  /// Name des laufenden Backends (triposr, sf3d, spar3d,
  /// trellis) bzw. beim Bild-Server das Modell.
  static String lastBackend = '';

  /// '3d' oder 'image' – der Bild-Server meldet seine Art selbst.
  static String lastKind = '3d';

  /// Fragt den /health-Endpunkt ab und liefert eine Kurzinfo,
  /// z. B. „triposr auf cuda (NVIDIA GeForce RTX 4070)“.
  Future<String> health() async {
    http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw GenerationException(_readError(response));
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      lastKind = json['kind']?.toString() ?? '3d';
      // Der Bild-Server nennt sein Modell statt eines Backends.
      lastBackend =
          (json['backend'] ?? json['model'])?.toString() ?? '';
      lastCapabilities = [
        for (final c in (json['capabilities'] as List?) ?? [])
          c.toString(),
      ];
      final missing = [
        for (final m in (json['missing'] as List?) ?? []) m.toString(),
      ];
      final gpu = json['gpu']?.toString() ?? '';
      final where =
          gpu.isEmpty ? '${json['device']}' : '${json['device']} ($gpu)';
      final info = '$lastBackend auf $where';
      // Der 3D-Server hängt fehlende Pakete schon selbst an.
      return missing.isEmpty || info.contains('FEHLEN')
          ? info
          : '$info – es fehlen noch: ${missing.join(', ')}';
    } catch (_) {
      return 'erreichbar';
    }
  }

  /// Bild→3D: ein synchroner Aufruf, der Server antwortet direkt mit
  /// den GLB-Bytes (TripoSR: Sekunden, TRELLIS: wenige Minuten).
  Future<Uint8List> generateModel({
    required Uint8List imageBytes,
    required String mimeType,
    required void Function(String stage) onProgress,
    List<(Uint8List, String)> extraViews = const [],
    int? textureResolution,
    String? remesh,
    int? targetCount,
    int? resolution,
    bool? bakeTexture,
  }) async {
    onProgress('3D-Modell wird auf dem eigenen Server berechnet …');
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'image': base64Encode(imageBytes),
              'mime_type': mimeType,
              // Weitere Ansichten nutzt nur ein Backend mit
              // „multiview"; die anderen ignorieren sie.
              if (extraViews.isNotEmpty)
                'images': [
                  for (final (bytes, _) in extraViews)
                    base64Encode(bytes),
                ],
              'texture_resolution': ?textureResolution,
              if (remesh != null && remesh.isNotEmpty) 'remesh': remesh,
              if (targetCount != null && targetCount > 0)
                'target_count': targetCount,
              'resolution': ?resolution,
              'bake_texture': ?bakeTexture,
            }),
          )
          .timeout(const Duration(minutes: 15));
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw GenerationException(_readError(response));
    }
    final bytes = response.bodyBytes;
    // GLB-Magic „glTF“ prüfen, damit eine HTML-Fehlerseite (falscher
    // Port, Proxy …) nicht als Modell in der Galerie landet.
    if (bytes.length < 12 ||
        bytes[0] != 0x67 ||
        bytes[1] != 0x6C ||
        bytes[2] != 0x54 ||
        bytes[3] != 0x46) {
      throw GenerationException(
          'Der Server hat keine GLB-Datei geliefert '
          '(${response.headers['content-type'] ?? 'unbekannter Typ'}) – '
          'Adresse und Server-Log prüfen.');
    }
    return bytes;
  }
}
