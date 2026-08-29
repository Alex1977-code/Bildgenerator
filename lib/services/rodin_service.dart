import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'generators.dart' show GenerationException;

/// Anbindung an Rodin (Hyper3D von Deemos) – Spitzenklasse für
/// Game-Assets: saubere Quad-Topologie, PBR-Texturen, T/A-Pose.
///
/// Ablauf der API (api.hyper3d.com): Auftrag als Multipart-POST an
/// /api/v2/rodin (liefert Task-UUID + subscription_key), Status per
/// POST /api/v2/status pollen, fertige Dateien per POST
/// /api/v2/download abholen.
class RodinService {
  RodinService(this.apiKey);

  final String apiKey;

  static const _base = 'https://api.hyper3d.com/api/v2';

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
      detail = (json['error'] ?? json['message'] ?? response.body).toString();
    } catch (_) {
      detail = response.body;
    }
    var hint = '';
    if (response.statusCode == 401 || response.statusCode == 403) {
      hint = ' Bitte den Rodin-API-Schlüssel in den Einstellungen prüfen '
          '(erhältlich auf hyper3d.ai).';
    } else if (response.statusCode == 402 || response.statusCode == 429) {
      hint = '\n\nHinweis: Vermutlich sind die Rodin-Credits aufgebraucht '
          'oder das Rate-Limit ist erreicht – Guthaben auf hyper3d.ai '
          'prüfen.';
    }
    return 'Rodin-Fehler (${response.statusCode}): $detail$hint';
  }

  /// Legt einen Generierungs-Auftrag an. Ohne [images] ist es natives
  /// Text→3D ([prompt] Pflicht); mit mehreren Bildern werden alle als
  /// Ansichten DESSELBEN Objekts interpretiert (condition_mode=concat).
  /// Liefert (Task-UUID für den Download, subscription_key für den
  /// Status).
  Future<(String, String)> createTask({
    List<(Uint8List, String)> images = const [],
    String? prompt,
    String tier = '',
    bool quadTopology = true,
    int? targetPolycount,
    bool taPose = false,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$_base/rodin'));
    request.headers['Authorization'] = 'Bearer $apiKey';
    var index = 0;
    for (final (bytes, mimeType) in images) {
      request.files.add(http.MultipartFile.fromBytes(
        'images',
        bytes,
        filename:
            'view$index.${mimeType.contains('jpeg') ? 'jpg' : 'png'}',
      ));
      index++;
    }
    if (prompt != null && prompt.isNotEmpty) {
      request.fields['prompt'] = prompt;
    }
    // Nur vom Standard abweichende Werte mitschicken, damit die
    // API-Vorgaben (und künftige Änderungen daran) erhalten bleiben.
    if (tier.isNotEmpty) request.fields['tier'] = tier;
    if (!quadTopology) request.fields['mesh_mode'] = 'Raw';
    if (targetPolycount != null && targetPolycount > 0) {
      request.fields['quality_override'] = '$targetPolycount';
    }
    if (taPose) request.fields['TAPose'] = 'true';
    request.fields['geometry_file_format'] = 'glb';
    if (images.length > 1) request.fields['condition_mode'] = 'concat';

    http.Response response;
    try {
      response =
          await http.Response.fromStream(await request.send());
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw GenerationException(_readError(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null && json['error'].toString() != 'null') {
      throw GenerationException('Rodin-Fehler: ${json['error']}');
    }
    final uuid = json['uuid'] as String?;
    final jobs = json['jobs'] as Map<String, dynamic>?;
    final subscriptionKey = jobs?['subscription_key'] as String?;
    if (uuid == null || subscriptionKey == null) {
      throw GenerationException(
          'Rodin hat keine Task-Daten zurückgegeben: ${response.body}');
    }
    return (uuid, subscriptionKey);
  }

  /// Pollt den Status aller Teil-Jobs bis alle „Done“ sind
  /// (max. ca. 15 Minuten).
  Future<void> waitForTask(
    String subscriptionKey, {
    required void Function(String stage) onProgress,
    required bool Function() isCancelled,
  }) async {
    for (var attempt = 0; attempt < 180; attempt++) {
      if (isCancelled()) throw GenerationException('Abgebrochen.');
      await Future<void>.delayed(const Duration(seconds: 5));
      http.Response response;
      try {
        response = await http.post(
          Uri.parse('$_base/status'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'subscription_key': subscriptionKey}),
        );
      } catch (e) {
        _throwNetworkError(e);
      }
      if (response.statusCode != 200) {
        throw GenerationException(_readError(response));
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final jobs = (json['jobs'] as List?) ?? const [];
      var done = 0;
      for (final job in jobs) {
        final status =
            (job is Map ? job['status'] : null)?.toString() ?? '';
        if (status == 'Failed') {
          throw GenerationException(
              'Rodin-Auftrag fehlgeschlagen: ${response.body}');
        }
        if (status == 'Done') done++;
      }
      if (jobs.isNotEmpty && done == jobs.length) return;
      onProgress('3D-Modell wird generiert (Rodin) … '
          '$done/${jobs.isEmpty ? '?' : jobs.length} Schritte fertig');
    }
    throw GenerationException(
        'Zeitüberschreitung – der Rodin-Auftrag wurde nicht '
        'rechtzeitig fertig.');
  }

  /// Wählt aus der Download-Liste die GLB-Datei aus.
  static String? pickGlbUrl(dynamic list) {
    if (list is! List) return null;
    String? fallback;
    for (final entry in list) {
      if (entry is! Map) continue;
      final url = entry['url']?.toString() ?? '';
      final name = entry['name']?.toString().toLowerCase() ?? '';
      if (!url.startsWith('http')) continue;
      if (name.endsWith('.glb') || url.toLowerCase().contains('.glb')) {
        return url;
      }
      fallback ??= url;
    }
    return fallback;
  }

  /// Holt die Download-Liste des Tasks und lädt die GLB-Datei.
  Future<Uint8List> downloadGlb(String taskUuid) async {
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_base/download'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'task_uuid': taskUuid}),
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw GenerationException(_readError(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final url = pickGlbUrl(json['list']);
    if (url == null) {
      throw GenerationException(
          'Rodin hat keine GLB-Datei zurückgegeben: ${response.body}');
    }
    http.Response file;
    try {
      file = await http.get(Uri.parse(url));
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
