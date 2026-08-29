import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'fal_service.dart' show FalService;
import 'generators.dart' show GenerationException;

/// Ein Bild→3D-Modell auf Replicate: API-Kennung (owner/name),
/// Anzeigename und Name des Bild-Eingabefelds.
class ReplicateModel {
  const ReplicateModel(this.id, this.label, {this.imageField = 'image'});

  final String id;
  final String label;
  final String imageField;
}

/// Eingebauter Katalog geprüfter Replicate-Modelle (Bild→3D, GLB).
const replicateModels = [
  ReplicateModel('firtoz/trellis', 'TRELLIS (Microsoft)',
      imageField: 'images'),
  ReplicateModel('tencent/hunyuan3d-2', 'Hunyuan3D 2.0 (Tencent)'),
];

/// Anbindung an Replicate (replicate.com): Prediction über
/// `POST /v1/models/{owner}/{name}/predictions` anlegen (bzw. mit
/// angepinnter Version über `POST /v1/predictions`), Status über die
/// zurückgegebene URL pollen, GLB aus der Ausgabe laden. Größere
/// Bilder gehen vorab über die Files-API, damit das 256-KB-Limit für
/// Data-URIs nicht greift.
class ReplicateService {
  ReplicateService(this.apiKey);

  final String apiKey;

  static const _base = 'https://api.replicate.com/v1';

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
      detail =
          (json['detail'] ?? json['error'] ?? response.body).toString();
    } catch (_) {
      detail = response.body;
    }
    var hint = '';
    if (response.statusCode == 401 || response.statusCode == 403) {
      hint = ' Bitte den Replicate-API-Token in den Einstellungen prüfen '
          '(erhältlich auf replicate.com).';
    } else if (response.statusCode == 402) {
      hint = '\n\nHinweis: Auf replicate.com muss eine Zahlungsmethode '
          'hinterlegt bzw. Guthaben aufgeladen sein.';
    } else if (response.statusCode == 404) {
      hint = '\n\nHinweis: Die Modell-Kennung scheint nicht zu '
          'existieren – Schreibweise (owner/name) mit replicate.com '
          'abgleichen.';
    } else if (response.statusCode == 422) {
      hint = '\n\nHinweis: Das Modell erwartet andere Eingabefelder – '
          'bei eigenen Modell-Kennungen das API-Schema des Modells auf '
          'replicate.com prüfen.';
    }
    return 'Replicate-Fehler (${response.statusCode}): $detail$hint';
  }

  /// Lädt ein Bild über die Files-API hoch und liefert dessen URL;
  /// schlägt das fehl, dient eine Data-URI als Rückfall (funktioniert
  /// laut Doku zuverlässig nur unter 256 KB).
  Future<String> _uploadImage(Uint8List bytes, String mimeType) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$_base/files'));
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.files.add(http.MultipartFile.fromBytes(
        'content',
        bytes,
        filename: mimeType.contains('jpeg') ? 'view.jpg' : 'view.png',
      ));
      final response =
          await http.Response.fromStream(await request.send());
      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final url = (json['urls'] as Map?)?['get'] as String?;
        if (url != null && url.startsWith('http')) return url;
      }
    } catch (_) {}
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  /// Bild→3D: Bilder hochladen, Prediction anlegen, pollen, GLB laden.
  /// [modelId] ist "owner/name" (neueste Version) oder
  /// "owner/name:version" (angepinnte Version).
  Future<Uint8List> generateModel({
    required String modelId,
    required List<(Uint8List, String)> images,
    required void Function(String stage) onProgress,
    required bool Function() isCancelled,
  }) async {
    final imageField = replicateModels
        .firstWhere(
          (m) => m.id == modelId.split(':').first,
          orElse: () => ReplicateModel(modelId, modelId),
        )
        .imageField;
    onProgress('Bilder werden zu Replicate hochgeladen …');
    final urls = <String>[
      for (final (bytes, mimeType) in images)
        await _uploadImage(bytes, mimeType),
    ];
    final input = <String, dynamic>{
      if (imageField == 'images') 'images': urls else imageField: urls.first,
    };

    // "owner/name:version" → generischer Predictions-Endpunkt mit
    // angepinnter Version, sonst der Modell-Endpunkt (neueste Version).
    final Uri createUrl;
    final Map<String, dynamic> body;
    if (modelId.contains(':')) {
      createUrl = Uri.parse('$_base/predictions');
      body = {'version': modelId.split(':').last, 'input': input};
    } else {
      createUrl = Uri.parse('$_base/models/$modelId/predictions');
      body = {'input': input};
    }
    http.Response response;
    try {
      response = await http.post(createUrl,
          headers: _jsonHeaders, body: jsonEncode(body));
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 202) {
      throw GenerationException(_readError(response));
    }
    var prediction = jsonDecode(response.body) as Map<String, dynamic>;
    final pollUrl = (prediction['urls'] as Map?)?['get'] as String?;
    if (pollUrl == null) {
      throw GenerationException(
          'Replicate hat keine Status-URL zurückgegeben: '
          '${response.body}');
    }

    for (var attempt = 0; attempt < 225; attempt++) {
      final status = prediction['status'] as String? ?? '';
      if (status == 'succeeded') break;
      if (status == 'failed' || status == 'canceled') {
        throw GenerationException('Replicate-Lauf fehlgeschlagen: '
            '${prediction['error'] ?? status}');
      }
      if (attempt == 224) {
        throw GenerationException(
            'Zeitüberschreitung – der Replicate-Lauf wurde nicht '
            'rechtzeitig fertig.');
      }
      if (isCancelled()) throw GenerationException('Abgebrochen.');
      onProgress(status == 'starting'
          ? '3D-Modell ($modelId): Server startet …'
          : '3D-Modell wird generiert ($modelId) …');
      await Future<void>.delayed(const Duration(seconds: 4));
      http.Response poll;
      try {
        poll = await http.get(Uri.parse(pollUrl),
            headers: {'Authorization': 'Bearer $apiKey'});
      } catch (e) {
        _throwNetworkError(e);
      }
      if (poll.statusCode != 200) {
        throw GenerationException(_readError(poll));
      }
      prediction = jsonDecode(poll.body) as Map<String, dynamic>;
    }

    // Ausgabe-Formate variieren (model_file, mesh, Listen …) – die
    // rekursive GLB-Suche aus dem fal-Service findet die URL überall.
    final glbUrl = FalService.findGlbUrl(prediction['output']);
    if (glbUrl == null) {
      throw GenerationException(
          'Replicate hat keine GLB-Datei zurückgegeben: '
          '${jsonEncode(prediction['output'])}');
    }
    onProgress('GLB wird heruntergeladen …');
    http.Response file;
    try {
      file = await http.get(Uri.parse(glbUrl));
    } catch (e) {
      _throwNetworkError(e);
    }
    if (file.statusCode != 200) {
      throw GenerationException(
          'Download fehlgeschlagen (${file.statusCode}).');
    }
    return file.bodyBytes;
  }
}
