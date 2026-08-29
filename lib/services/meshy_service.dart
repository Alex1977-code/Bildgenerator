import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'generators.dart' show GenerationException;

/// Zustand eines asynchronen Meshy-Tasks.
class MeshyTaskStatus {
  MeshyTaskStatus({
    required this.status,
    required this.progress,
    this.errorMessage,
    this.glbUrl,
    this.thumbnailUrl,
  });

  final String status; // PENDING, IN_PROGRESS, SUCCEEDED, FAILED, CANCELED
  final int progress; // 0–100
  final String? errorMessage;
  final String? glbUrl;
  final String? thumbnailUrl;

  bool get isDone => status == 'SUCCEEDED';
  bool get isFailed => status == 'FAILED' || status == 'CANCELED';
}

/// Anbindung an die Meshy-API (Text→3D, Bild→3D, Auto-Rigging).
///
/// Alle Endpunkte arbeiten asynchron: Task anlegen, Status pollen,
/// fertige Modelle über signierte URLs herunterladen.
class MeshyService {
  MeshyService(this.apiKey);

  final String apiKey;

  static const _base = 'https://api.meshy.ai/openapi';

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

  String _readError(http.Response response) {
    var detail = '';
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      detail = json['message'] as String? ?? response.body;
    } catch (_) {
      detail = response.body;
    }
    var hint = '';
    if (response.statusCode == 401) {
      hint = ' Bitte den Meshy-API-Schlüssel in den Einstellungen prüfen '
          '(erhältlich auf meshy.ai).';
    } else if (response.statusCode == 402 || response.statusCode == 429) {
      hint = '\n\nHinweis: Vermutlich sind die Meshy-Credits aufgebraucht '
          'oder das Rate-Limit ist erreicht. Guthaben auf meshy.ai prüfen '
          '(neue Konten erhalten kostenlose Credits).';
    }
    return 'Meshy-Fehler (${response.statusCode}): $detail$hint';
  }

  Future<String> _createTask(String path, Map<String, dynamic> body) async {
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_base/$path'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200 && response.statusCode != 202) {
      throw GenerationException(_readError(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final id = json['result'] as String?;
    if (id == null || id.isEmpty) {
      throw GenerationException(
          'Meshy hat keine Task-ID zurückgegeben: ${response.body}');
    }
    return id;
  }

  /// Qualitäts-Optionen, die alle Meshy-Endpunkte verstehen. Nur vom
  /// Standard abweichende Werte werden mitgeschickt, damit die
  /// API-Vorgaben (und künftige Änderungen daran) erhalten bleiben.
  Map<String, dynamic> _qualityFields({
    String? aiModel,
    bool quadTopology = false,
    int? targetPolycount,
    String? symmetryMode,
  }) =>
      {
        if (aiModel != null && aiModel.isNotEmpty) 'ai_model': aiModel,
        if (quadTopology) 'topology': 'quad',
        if (targetPolycount != null && targetPolycount > 0)
          'target_polycount': targetPolycount,
        if (symmetryMode != null && symmetryMode != 'auto')
          'symmetry_mode': symmetryMode,
      };

  /// Schritt 1 bei Text→3D: unbemalte Geometrie (Preview).
  Future<String> createTextPreview(
    String prompt,
    String artStyle, {
    String? aiModel,
    bool quadTopology = false,
    int? targetPolycount,
    String? symmetryMode,
    String? negativePrompt,
  }) =>
      _createTask('v2/text-to-3d', {
        'mode': 'preview',
        'prompt': prompt,
        'art_style': artStyle,
        'should_remesh': true,
        if (negativePrompt != null && negativePrompt.isNotEmpty)
          'negative_prompt': negativePrompt,
        ..._qualityFields(
          aiModel: aiModel,
          quadTopology: quadTopology,
          targetPolycount: targetPolycount,
          symmetryMode: symmetryMode,
        ),
      });

  /// Schritt 2 bei Text→3D: Texturierung des Preview-Modells.
  Future<String> createTextRefine(
    String previewTaskId, {
    bool enablePbr = true,
    String? texturePrompt,
  }) =>
      _createTask('v2/text-to-3d', {
        'mode': 'refine',
        'preview_task_id': previewTaskId,
        'enable_pbr': enablePbr,
        if (texturePrompt != null && texturePrompt.isNotEmpty)
          'texture_prompt': texturePrompt,
      });

  /// Bild→3D (liefert direkt ein – optional texturiertes – Modell).
  Future<String> createImageTo3d(
    Uint8List imageBytes,
    String mimeType, {
    required bool texture,
    String? aiModel,
    bool quadTopology = false,
    int? targetPolycount,
    String? symmetryMode,
    bool enablePbr = true,
    String? texturePrompt,
  }) =>
      _createTask('v1/image-to-3d', {
        'image_url': 'data:$mimeType;base64,${base64Encode(imageBytes)}',
        'should_remesh': true,
        'should_texture': texture,
        'enable_pbr': texture && enablePbr,
        if (texture && texturePrompt != null && texturePrompt.isNotEmpty)
          'texture_prompt': texturePrompt,
        ..._qualityFields(
          aiModel: aiModel,
          quadTopology: quadTopology,
          targetPolycount: targetPolycount,
          symmetryMode: symmetryMode,
        ),
      });

  /// Mehrbild→3D: 1–4 Ansichten desselben Objekts; das erste Bild ist
  /// die Vorderansicht, die Reihenfolge der übrigen ist egal.
  Future<String> createMultiImageTo3d(
    List<(Uint8List, String)> images, {
    required bool texture,
    String? aiModel,
    bool quadTopology = false,
    int? targetPolycount,
    String? symmetryMode,
    bool enablePbr = true,
    String? texturePrompt,
  }) =>
      _createTask('v1/multi-image-to-3d', {
        'image_urls': [
          for (final (bytes, mimeType) in images)
            'data:$mimeType;base64,${base64Encode(bytes)}',
        ],
        'should_remesh': true,
        'should_texture': texture,
        'enable_pbr': texture && enablePbr,
        if (texture && texturePrompt != null && texturePrompt.isNotEmpty)
          'texture_prompt': texturePrompt,
        ..._qualityFields(
          aiModel: aiModel,
          quadTopology: quadTopology,
          targetPolycount: targetPolycount,
          symmetryMode: symmetryMode,
        ),
      });

  /// Auto-Rigging für Figuren (Skelett + Basis-Animationen).
  Future<String> createRigging(String inputTaskId) =>
      _createTask('v1/rigging', {
        'input_task_id': inputTaskId,
        'height_meters': 1.7,
      });

  /// Sucht rekursiv nach einer GLB-URL; geriggte Varianten haben Vorrang.
  static String? _findGlbUrl(dynamic node, {bool preferRigged = false}) {
    String? fallback;
    String? rigged;
    void walk(dynamic n, String keyPath) {
      if (n is String) {
        if (n.startsWith('http') && n.contains('.glb')) {
          if (keyPath.contains('rigged') || keyPath.contains('rig')) {
            rigged ??= n;
          }
          fallback ??= n;
        }
      } else if (n is Map) {
        // Bevorzugt das offizielle Feld model_urls.glb.
        final modelUrls = n['model_urls'];
        if (modelUrls is Map && modelUrls['glb'] is String) {
          fallback ??= modelUrls['glb'] as String;
        }
        n.forEach((k, v) => walk(v, '$keyPath/${k.toString().toLowerCase()}'));
      } else if (n is List) {
        for (final item in n) {
          walk(item, keyPath);
        }
      }
    }

    walk(node, '');
    if (preferRigged && rigged != null) return rigged;
    return fallback;
  }

  static String? _findThumbnailUrl(Map<String, dynamic> json) {
    final direct = json['thumbnail_url'];
    if (direct is String && direct.startsWith('http')) return direct;
    return null;
  }

  Future<MeshyTaskStatus> getTask(String path, String id,
      {bool preferRigged = false}) async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_base/$path/$id'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw GenerationException(_readError(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return MeshyTaskStatus(
      status: json['status'] as String? ?? 'PENDING',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      errorMessage:
          ((json['task_error'] as Map<String, dynamic>?)?['message'])
              as String?,
      glbUrl: _findGlbUrl(json, preferRigged: preferRigged),
      thumbnailUrl: _findThumbnailUrl(json),
    );
  }

  /// Pollt einen Task bis zum Abschluss (max. ca. 15 Minuten).
  Future<MeshyTaskStatus> waitForTask(
    String path,
    String id, {
    required String stageLabel,
    required void Function(String stage) onProgress,
    required bool Function() isCancelled,
    bool preferRigged = false,
  }) async {
    for (var attempt = 0; attempt < 180; attempt++) {
      if (isCancelled()) {
        throw GenerationException('Abgebrochen.');
      }
      final status = await getTask(path, id, preferRigged: preferRigged);
      onProgress('$stageLabel … ${status.progress} %');
      if (status.isDone) return status;
      if (status.isFailed) {
        throw GenerationException(
            'Meshy-Task fehlgeschlagen: ${status.errorMessage ?? status.status}');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw GenerationException(
        'Zeitüberschreitung – der Meshy-Task wurde nicht rechtzeitig fertig.');
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
