import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'generators.dart' show GenerationException;

/// Ein Bild→3D-Modell auf dem fal.ai-Marktplatz: API-Kennung,
/// Anzeigename und Name des Bild-Eingabefelds – die Modelle stammen
/// von unterschiedlichen Teams und benennen das Feld unterschiedlich.
class FalModel {
  const FalModel(
    this.id,
    this.label, {
    this.imageField = 'image_url',
    this.textToModel = false,
  });

  final String id;
  final String label;
  final String imageField;

  /// True bei Modellen, die direkt aus Text ein 3D-Modell bauen –
  /// ohne den Umweg über ein erzeugtes Bild.
  final bool textToModel;
}

/// Eingebauter Katalog geprüfter fal.ai-Modelle (Bild→3D, GLB-Ausgabe).
const falModels = [
  FalModel('fal-ai/trellis', 'TRELLIS (Microsoft – günstig & solide)'),
  FalModel('fal-ai/trellis-2', 'TRELLIS.2 (neueste Generation)'),
  FalModel('fal-ai/triposr', 'TripoSR (am schnellsten & günstigsten)'),
  FalModel('fal-ai/hunyuan3d/v2', 'Hunyuan3D 2.0 (Tencent)',
      imageField: 'input_image_url'),
  FalModel('fal-ai/hunyuan-3d/v3.1/pro/image-to-3d',
      'Hunyuan3D 3.1 Pro (Spitzenklasse)'),
  FalModel('fal-ai/hyper3d/rodin/v2.5/text-to-3d',
      'Rodin 2.5 – direkt aus Text (ohne Bild-Umweg)',
      textToModel: true),
];

/// Nachschlagen im Katalog; unbekannte (selbst eingetragene) IDs
/// bekommen sinnvolle Vorgaben.
FalModel falModelFor(String modelId) => falModels.firstWhere(
      (m) => m.id == modelId,
      // Eigene Modell-IDs: Hunyuan3D 2.x nennt das Feld
      // input_image_url, praktisch alle anderen image_url.
      orElse: () => FalModel(
        modelId,
        modelId,
        imageField: modelId.contains('hunyuan3d/v2')
            ? 'input_image_url'
            : 'image_url',
        textToModel: modelId.contains('text-to-3d'),
      ),
    );

/// Anbindung an die fal.ai-Queue-API: ein Auftrag wird per POST an
/// `queue.fal.run/<modell-id>` angelegt; Status- und Ergebnis-URL
/// kommen aus der Antwort (nicht selbst zusammensetzen – Modell-IDs
/// mit Unterpfaden haben eigene Queue-Pfade).
class FalService {
  FalService(this.apiKey);

  final String apiKey;

  static const _queueBase = 'https://queue.fal.run';

  Map<String, String> get _authHeader => {'Authorization': 'Key $apiKey'};

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
      final json = jsonDecode(response.body);
      // Validierungsfehler kommen als {"detail":[{loc,msg},…]} –
      // die Meldungen samt Feldname anzeigen, damit sich abweichende
      // Eingabefelder eigener Modell-IDs direkt erkennen lassen.
      final d = (json as Map<String, dynamic>)['detail'];
      if (d is List) {
        detail = d
            .map((e) => e is Map
                ? '${(e['loc'] as List?)?.join('.') ?? ''}: ${e['msg']}'
                : e.toString())
            .join('; ');
      } else {
        detail = d?.toString() ?? json['message']?.toString() ?? response.body;
      }
    } catch (_) {
      detail = response.body;
    }
    var hint = '';
    if (response.statusCode == 401 || response.statusCode == 403) {
      hint = ' Bitte den fal.ai-API-Schlüssel in den Einstellungen prüfen '
          '(erhältlich auf fal.ai).';
    } else if (response.statusCode == 402) {
      hint = '\n\nHinweis: Vermutlich ist das fal.ai-Guthaben aufgebraucht – '
          'auf fal.ai/dashboard prüfen.';
    } else if (response.statusCode == 404) {
      hint = '\n\nHinweis: Die Modell-ID scheint nicht zu existieren – '
          'Schreibweise mit fal.ai/models abgleichen.';
    } else if (response.statusCode == 422) {
      hint = '\n\nHinweis: Das Modell erwartet andere Eingabefelder – '
          'bei eigenen Modell-IDs die API-Doku des Modells auf fal.ai '
          'prüfen.';
    }
    return 'fal.ai-Fehler (${response.statusCode}): $detail$hint';
  }

  /// Sucht rekursiv nach der GLB-Datei im Ergebnis-JSON – die Modelle
  /// benennen das Feld unterschiedlich (model_mesh, model_glb, …),
  /// liefern aber alle {url, content_type, file_name}-Objekte.
  static String? findGlbUrl(dynamic node) {
    String? found;
    void walk(dynamic n) {
      if (found != null) return;
      if (n is String) {
        if (n.startsWith('http') && n.toLowerCase().contains('.glb')) {
          found = n;
        }
      } else if (n is Map) {
        final url = n['url'];
        if (url is String && url.startsWith('http')) {
          final contentType =
              (n['content_type'] as String? ?? '').toLowerCase();
          final fileName = (n['file_name'] as String? ?? '').toLowerCase();
          if (contentType.contains('gltf') ||
              fileName.endsWith('.glb') ||
              url.toLowerCase().contains('.glb')) {
            found = url;
            return;
          }
        }
        n.values.forEach(walk);
      } else if (n is List) {
        n.forEach(walk);
      }
    }

    walk(node);
    return found;
  }

  /// Bild→3D bzw. Text→3D: Auftrag anlegen, Queue pollen, GLB
  /// herunterladen. Bei Text→3D-Modellen entfällt [imageBytes] und es
  /// zählt allein der [prompt].
  Future<Uint8List> generateModel({
    required String modelId,
    Uint8List? imageBytes,
    String mimeType = 'image/png',
    String prompt = '',
    required void Function(String stage) onProgress,
    required bool Function() isCancelled,
  }) async {
    final model = falModelFor(modelId);
    if (model.textToModel && prompt.trim().isEmpty) {
      throw GenerationException(
          'Für „${model.label}" wird eine Beschreibung gebraucht.');
    }
    if (!model.textToModel && imageBytes == null) {
      throw GenerationException(
          'Für „${model.label}" wird ein Bild gebraucht.');
    }

    http.Response submit;
    try {
      submit = await http.post(
        Uri.parse('$_queueBase/$modelId'),
        headers: {..._authHeader, 'Content-Type': 'application/json'},
        body: jsonEncode(model.textToModel
            ? {'prompt': prompt.trim()}
            : {
                model.imageField:
                    'data:$mimeType;base64,${base64Encode(imageBytes!)}',
                // Eine Beschreibung hilft manchen Modellen zusätzlich;
                // Modelle ohne dieses Feld ignorieren es nicht, deshalb
                // nur mitschicken, wenn eines vorliegt.
                if (prompt.trim().isNotEmpty && model.id.contains('rodin'))
                  'prompt': prompt.trim(),
              }),
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    if (submit.statusCode != 200 &&
        submit.statusCode != 201 &&
        submit.statusCode != 202) {
      throw GenerationException(_readError(submit));
    }
    final submitted = jsonDecode(submit.body) as Map<String, dynamic>;
    final statusUrl = submitted['status_url'] as String?;
    final responseUrl = submitted['response_url'] as String?;
    if (statusUrl == null || responseUrl == null) {
      throw GenerationException(
          'fal.ai hat keine Status-URL zurückgegeben: ${submit.body}');
    }

    // Pollen bis COMPLETED (max. ca. 18 Minuten).
    var completed = false;
    for (var attempt = 0; attempt < 360 && !completed; attempt++) {
      if (isCancelled()) throw GenerationException('Abgebrochen.');
      await Future<void>.delayed(const Duration(seconds: 3));
      http.Response statusResponse;
      try {
        statusResponse =
            await http.get(Uri.parse(statusUrl), headers: _authHeader);
      } catch (e) {
        _throwNetworkError(e);
      }
      if (statusResponse.statusCode != 200 &&
          statusResponse.statusCode != 202) {
        throw GenerationException(_readError(statusResponse));
      }
      final status = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      final state = status['status'] as String? ?? '';
      switch (state) {
        case 'COMPLETED':
          completed = true;
        case 'FAILED':
        case 'CANCELLED':
        case 'ERROR':
          throw GenerationException(
              'fal.ai-Auftrag fehlgeschlagen: ${statusResponse.body}');
        case 'IN_QUEUE':
          final position = status['queue_position'];
          onProgress(position is num
              ? '3D-Modell ($modelId): Warteschlange, Position '
                  '${position.toInt() + 1} …'
              : '3D-Modell ($modelId): in der Warteschlange …');
        default:
          onProgress('3D-Modell wird generiert ($modelId) …');
      }
    }
    if (!completed) {
      throw GenerationException(
          'Zeitüberschreitung – der fal.ai-Auftrag wurde nicht '
          'rechtzeitig fertig.');
    }

    http.Response result;
    try {
      result = await http.get(Uri.parse(responseUrl), headers: _authHeader);
    } catch (e) {
      _throwNetworkError(e);
    }
    if (result.statusCode != 200) {
      throw GenerationException(_readError(result));
    }
    final glbUrl = findGlbUrl(jsonDecode(result.body));
    if (glbUrl == null) {
      throw GenerationException(
          'fal.ai hat keine GLB-Datei zurückgegeben: ${result.body}');
    }
    onProgress('GLB wird heruntergeladen …');
    return downloadFile(glbUrl);
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
