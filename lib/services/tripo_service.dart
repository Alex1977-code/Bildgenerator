import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'generators.dart' show GenerationException;

/// Anbindung an die Tripo3D-API (Text→3D, Bild→3D, Auto-Rigging).
///
/// Tripo arbeitet mit asynchronen Tasks: anlegen, Status pollen, fertige
/// Modelle über signierte URLs herunterladen. Antworten sind in
/// `{"code": 0, "data": {...}}` verpackt.
class TripoService {
  TripoService(this.apiKey);

  final String apiKey;

  static const _base = 'https://api.tripo3d.ai/v2/openapi';

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  Never _throwNetworkError(Object e) {
    throw GenerationException(
      'Netzwerkfehler: $e\n'
      'Bitte Internetverbindung prüfen. Hinweis: Im Browser (Web-Version) '
      'können CORS-Beschränkungen Anfragen blockieren – die nativen Apps '
      'sind davon nicht betroffen.',
    );
  }

  GenerationException _error(int httpStatus, String body) {
    var detail = body;
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      detail = (json['message'] ?? json['suberror'] ?? body).toString();
    } catch (_) {}
    var hint = '';
    if (httpStatus == 401 || httpStatus == 403) {
      hint = ' Bitte den Tripo3D-API-Schlüssel in den Einstellungen prüfen '
          '(erhältlich auf platform.tripo3d.ai).';
    } else if (httpStatus == 402 ||
        detail.toLowerCase().contains('balance') ||
        detail.toLowerCase().contains('credit')) {
      hint = '\n\nHinweis: Vermutlich ist das Tripo-Guthaben aufgebraucht – '
          'auf platform.tripo3d.ai Credits aufladen.';
    }
    return GenerationException('Tripo3D-Fehler ($httpStatus): $detail$hint');
  }

  Map<String, dynamic> _unwrap(http.Response response) {
    if (response.statusCode != 200) {
      throw _error(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final code = (json['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw _error(response.statusCode, response.body);
    }
    return json['data'] as Map<String, dynamic>? ?? {};
  }

  Future<Map<String, dynamic>> _postTask(Map<String, dynamic> body) async {
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_base/task'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    return _unwrap(response);
  }

  Future<String> _createTask(Map<String, dynamic> body) async {
    final data = await _postTask(body);
    final id = data['task_id'] as String?;
    if (id == null || id.isEmpty) {
      throw GenerationException('Tripo3D hat keine Task-ID zurückgegeben.');
    }
    return id;
  }

  /// Lädt ein Ausgangsbild hoch und liefert das Datei-Token.
  Future<String> uploadImage(Uint8List bytes, String mimeType) async {
    final subtype = mimeType.split('/').last;
    Future<http.Response> tryUpload(String path) async {
      final request = http.MultipartRequest('POST', Uri.parse('$_base/$path'))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'vorlage.${subtype == 'jpeg' ? 'jpg' : subtype}',
          contentType: MediaType('image', subtype),
        ));
      return http.Response.fromStream(await request.send());
    }

    http.Response response;
    try {
      response = await tryUpload('upload');
      if (response.statusCode == 404) {
        // Ältere/neuere API-Versionen nutzen einen anderen Pfad.
        response = await tryUpload('upload/sts');
      }
    } catch (e) {
      _throwNetworkError(e);
    }
    final data = _unwrap(response);
    final token =
        (data['image_token'] ?? data['file_token'] ?? data['token'])
            as String?;
    if (token == null || token.isEmpty) {
      throw GenerationException(
          'Tripo3D hat kein Datei-Token zurückgegeben.');
    }
    return token;
  }

  /// Qualitäts-Optionen, die alle Modell-Endpunkte verstehen. Nur vom
  /// Standard abweichende Werte werden mitgeschickt.
  Map<String, dynamic> _qualityFields({
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
  }) =>
      {
        if (modelVersion != null && modelVersion.isNotEmpty)
          'model_version': modelVersion,
        if (quad) 'quad': true,
        if (texture && detailedTexture) 'texture_quality': 'detailed',
      };

  Future<String> createTextTask(
    String prompt, {
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
    String? negativePrompt,
  }) =>
      _createTask({
        'type': 'text_to_model',
        'prompt': prompt,
        'texture': texture,
        'pbr': texture,
        if (negativePrompt != null && negativePrompt.isNotEmpty)
          'negative_prompt': negativePrompt,
        ..._qualityFields(
          texture: texture,
          modelVersion: modelVersion,
          quad: quad,
          detailedTexture: detailedTexture,
        ),
      });

  Future<String> createImageTask(
    String fileToken,
    String mimeType, {
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
  }) {
    final subtype = mimeType.split('/').last;
    return _createTask({
      'type': 'image_to_model',
      'file': {
        'type': subtype == 'jpeg' ? 'jpg' : subtype,
        'file_token': fileToken,
      },
      'texture': texture,
      'pbr': texture,
      ..._qualityFields(
        texture: texture,
        modelVersion: modelVersion,
        quad: quad,
        detailedTexture: detailedTexture,
      ),
    });
  }

  /// Multiview→Modell: Ansichten in der Reihenfolge Vorn, Links, Hinten,
  /// Rechts; fehlende Ansichten als leere Einträge.
  Future<String> createMultiviewTask(
    List<(String, String)?> views, {
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
  }) {
    Map<String, dynamic> fileEntry((String, String)? view) {
      if (view == null) return <String, dynamic>{};
      final (token, mimeType) = view;
      final subtype = mimeType.split('/').last;
      return {
        'type': subtype == 'jpeg' ? 'jpg' : subtype,
        'file_token': token,
      };
    }

    return _createTask({
      'type': 'multiview_to_model',
      'files': [for (final view in views) fileEntry(view)],
      'texture': texture,
      'pbr': texture,
      ..._qualityFields(
        texture: texture,
        modelVersion: modelVersion,
        quad: quad,
        detailedTexture: detailedTexture,
      ),
    });
  }

  /// Prüft, ob das Modell riggbar ist (Figur erkannt).
  Future<String> createPrerigCheck(String modelTaskId) => _createTask({
        'type': 'animate_prerigcheck',
        'original_model_task_id': modelTaskId,
      });

  Future<String> createRig(String modelTaskId) => _createTask({
        'type': 'animate_rig',
        'original_model_task_id': modelTaskId,
        'out_format': 'glb',
      });

  Future<Map<String, dynamic>> getTask(String id) async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_base/task/$id'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    return _unwrap(response);
  }

  /// Pollt einen Task bis zum Abschluss (max. ca. 15 Minuten).
  Future<Map<String, dynamic>> waitForTask(
    String id, {
    required String stageLabel,
    required void Function(String stage) onProgress,
    required bool Function() isCancelled,
  }) async {
    for (var attempt = 0; attempt < 180; attempt++) {
      if (isCancelled()) {
        throw GenerationException('Abgebrochen.');
      }
      final data = await getTask(id);
      final status = (data['status'] as String? ?? 'queued').toLowerCase();
      final progress = (data['progress'] as num?)?.toInt() ?? 0;
      onProgress('$stageLabel … $progress %');
      if (status == 'success') return data;
      if (status == 'failed' ||
          status == 'cancelled' ||
          status == 'banned' ||
          status == 'expired') {
        throw GenerationException('Tripo3D-Task fehlgeschlagen ($status).');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw GenerationException(
        'Zeitüberschreitung – der Tripo3D-Task wurde nicht rechtzeitig '
        'fertig.');
  }

  /// GLB-URL aus einer Task-Antwort lesen (PBR-Variante bevorzugt).
  static String? findGlbUrl(Map<String, dynamic> data) {
    final output = data['output'];
    if (output is Map) {
      for (final key in ['pbr_model', 'model', 'base_model']) {
        final value = output[key];
        if (value is String && value.startsWith('http')) return value;
      }
    }
    String? found;
    void walk(dynamic node) {
      if (found != null) return;
      if (node is String &&
          node.startsWith('http') &&
          node.contains('.glb')) {
        found = node;
      } else if (node is Map) {
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(data);
    return found;
  }

  static String? findThumbnailUrl(Map<String, dynamic> data) {
    final output = data['output'];
    if (output is Map) {
      final value = output['rendered_image'];
      if (value is String && value.startsWith('http')) return value;
    }
    return null;
  }

  /// Verbleibendes Guthaben (Credits) des Kontos.
  Future<double?> fetchBalance() async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_base/user/balance'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    final data = _unwrap(response);
    return (data['balance'] as num?)?.toDouble();
  }

  /// Lädt eine Datei (z. B. das fertige GLB) herunter.
  Future<Uint8List> downloadFile(String url) async {
    http.Response response;
    try {
      response = await http.get(Uri.parse(url));
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw GenerationException(
          'Download fehlgeschlagen (${response.statusCode}).');
    }
    return response.bodyBytes;
  }
}
