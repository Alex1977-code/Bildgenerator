import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/models.dart';

/// Fehler bei der Bildgenerierung mit verständlicher Meldung.
class GenerationException implements Exception {
  GenerationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Gemeinsame Schnittstelle aller Bild-Provider.
abstract class ImageGenerator {
  Future<List<GeneratedImage>> generate(GenerationRequest request, String apiKey);

  static ImageGenerator forProvider(GenProvider provider) =>
      switch (provider) {
        GenProvider.openai => OpenAiGenerator(),
        GenProvider.stability => StabilityGenerator(),
      };
}

MediaType _mediaType(String mimeType) {
  final parts = mimeType.split('/');
  return MediaType(parts.first, parts.last);
}

Never _throwNetworkError(Object e) {
  throw GenerationException(
    'Netzwerkfehler: $e\n'
    'Bitte Internetverbindung prüfen. Hinweis: Im Browser (Web-Version) '
    'können CORS-Beschränkungen des Providers Anfragen blockieren – die '
    'nativen Apps (Windows/Android/iOS) sind davon nicht betroffen.',
  );
}

/// OpenAI gpt-image-1: Referenzbilder, Größe, Qualität, Transparenz,
/// Ausgabeformat und Batch-Generierung.
class OpenAiGenerator implements ImageGenerator {
  static const _base = 'https://api.openai.com/v1';

  @override
  Future<List<GeneratedImage>> generate(
      GenerationRequest request, String apiKey) async {
    http.Response response;
    try {
      if (request.references.isEmpty) {
        response = await _generateFromText(request, apiKey);
      } else {
        response = await _generateWithReferences(request, apiKey);
      }
    } on GenerationException {
      rethrow;
    } catch (e) {
      _throwNetworkError(e);
    }

    if (response.statusCode != 200) {
      throw GenerationException(_readError(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];
    if (data.isEmpty) {
      throw GenerationException('OpenAI hat keine Bilder zurückgegeben.');
    }
    return data
        .map((item) => GeneratedImage(
              bytes: base64Decode(
                  (item as Map<String, dynamic>)['b64_json'] as String),
              format: request.outputFormat,
            ))
        .toList();
  }

  Future<http.Response> _generateFromText(
      GenerationRequest request, String apiKey) {
    final body = <String, dynamic>{
      'model': 'gpt-image-1',
      'prompt': request.prompt,
      'n': request.count,
      'size': request.openAiSize,
      'quality': request.quality,
      'background': request.transparent ? 'transparent' : 'auto',
      'output_format': request.outputFormat,
      if (request.outputFormat != 'png')
        'output_compression': request.compression,
    };
    return http.post(
      Uri.parse('$_base/images/generations'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _generateWithReferences(
      GenerationRequest request, String apiKey) async {
    final multipart =
        http.MultipartRequest('POST', Uri.parse('$_base/images/edits'))
          ..headers['Authorization'] = 'Bearer $apiKey'
          ..fields['model'] = 'gpt-image-1'
          ..fields['prompt'] = request.prompt
          ..fields['n'] = '${request.count}'
          ..fields['size'] = request.openAiSize
          ..fields['quality'] = request.quality
          ..fields['background'] =
              request.transparent ? 'transparent' : 'auto'
          ..fields['output_format'] = request.outputFormat;
    if (request.outputFormat != 'png') {
      multipart.fields['output_compression'] = '${request.compression}';
    }
    for (var i = 0; i < request.references.length; i++) {
      final ref = request.references[i];
      multipart.files.add(http.MultipartFile.fromBytes(
        'image[]',
        ref.bytes,
        filename: ref.name.isEmpty ? 'referenz_$i.png' : ref.name,
        contentType: _mediaType(ref.mimeType),
      ));
    }
    return http.Response.fromStream(await multipart.send());
  }

  String _readError(http.Response response) {
    var detail = '';
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      detail = (json['error'] as Map<String, dynamic>?)?['message'] as String? ??
          response.body;
    } catch (_) {
      detail = response.body;
    }
    var hint = '';
    if (response.statusCode == 401) {
      hint = ' Bitte den OpenAI-API-Schlüssel in den Einstellungen prüfen.';
    } else if (response.statusCode == 403) {
      hint = ' Für gpt-image-1 muss die Organisation bei OpenAI verifiziert '
          'sein (platform.openai.com → Settings → Organization).';
    }
    return 'OpenAI-Fehler (${response.statusCode}): $detail$hint';
  }
}

/// Stability AI Stable Image Core: Seitenverhältnis, Negativ-Prompt,
/// Seed und Style-Presets.
class StabilityGenerator implements ImageGenerator {
  static const _endpoint =
      'https://api.stability.ai/v2beta/stable-image/generate/core';

  @override
  Future<List<GeneratedImage>> generate(
      GenerationRequest request, String apiKey) async {
    // Core liefert ein Bild pro Anfrage – für Batches parallel anfragen.
    final futures = List.generate(
      request.count,
      (i) => _generateSingle(request, apiKey, i),
    );
    return Future.wait(futures);
  }

  Future<GeneratedImage> _generateSingle(
      GenerationRequest request, String apiKey, int index) async {
    final multipart = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Accept'] = 'application/json'
      ..fields['prompt'] = request.prompt
      ..fields['aspect_ratio'] = request.stabilityAspect
      ..fields['output_format'] = request.outputFormat;
    if (request.negativePrompt.trim().isNotEmpty) {
      multipart.fields['negative_prompt'] = request.negativePrompt.trim();
    }
    if (request.seed != 0) {
      multipart.fields['seed'] = '${request.seed + index}';
    }
    if (request.stylePreset.isNotEmpty) {
      multipart.fields['style_preset'] = request.stylePreset;
    }

    http.Response response;
    try {
      response = await http.Response.fromStream(await multipart.send());
    } catch (e) {
      _throwNetworkError(e);
    }

    if (response.statusCode != 200) {
      throw GenerationException(_readError(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final finishReason = json['finish_reason'] as String?;
    if (finishReason == 'CONTENT_FILTERED') {
      throw GenerationException(
          'Stability AI hat das Ergebnis aus Inhaltsgründen gefiltert. '
          'Bitte den Prompt anpassen.');
    }
    final b64 = json['image'] as String?;
    if (b64 == null) {
      throw GenerationException('Stability AI hat kein Bild zurückgegeben.');
    }
    return GeneratedImage(
      bytes: base64Decode(b64),
      format: request.outputFormat,
    );
  }

  String _readError(http.Response response) {
    var detail = '';
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errors = json['errors'];
      detail = errors is List
          ? errors.join('; ')
          : (json['message'] as String? ?? response.body);
    } catch (_) {
      detail = response.body;
    }
    var hint = '';
    if (response.statusCode == 401) {
      hint = ' Bitte den Stability-API-Schlüssel in den Einstellungen prüfen.';
    }
    return 'Stability-AI-Fehler (${response.statusCode}): $detail$hint';
  }
}
