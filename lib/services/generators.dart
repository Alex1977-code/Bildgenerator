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

/// Ergebnis einer Generierung: Bilder plus Verbrauchsinformationen.
class GenerationResult {
  GenerationResult({
    required this.images,
    this.totalTokens,
    this.creditsRemaining,
    this.note = '',
  });

  final List<GeneratedImage> images;

  /// Verbrauchte Tokens laut Provider (OpenAI/Gemini), falls gemeldet.
  final int? totalTokens;

  /// Verbleibendes Guthaben in Credits (nur Stability).
  final double? creditsRemaining;

  /// Anmerkung des Servers: Das Bild ist da, aber er musste etwas
  /// anders machen als angefragt (z. B. den Prompt kürzen). Leer,
  /// wenn alles glatt lief.
  final String note;
}

/// Gemeinsame Schnittstelle aller Bild-Provider.
abstract class ImageGenerator {
  Future<GenerationResult> generate(GenerationRequest request, String apiKey);

  static ImageGenerator forProvider(GenProvider provider) =>
      switch (provider) {
        GenProvider.openai => OpenAiGenerator(),
        GenProvider.stability => StabilityGenerator(),
        GenProvider.gemini => GeminiGenerator(),
        GenProvider.selfhost => SelfHostImageGenerator(),
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

/// OpenAI GPT Image (z. B. gpt-image-1): Referenzbilder, Größe, Qualität,
/// Transparenz, Ausgabeformat und Batch-Generierung.
class OpenAiGenerator implements ImageGenerator {
  static const _base = 'https://api.openai.com/v1';

  static String _model(GenerationRequest request) =>
      request.model.isEmpty ? 'gpt-image-1' : request.model;

  @override
  Future<GenerationResult> generate(
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
    final images = data
        .map((item) => GeneratedImage(
              bytes: base64Decode(
                  (item as Map<String, dynamic>)['b64_json'] as String),
              format: request.outputFormat,
            ))
        .toList();
    final usage = json['usage'] as Map<String, dynamic>?;
    return GenerationResult(
      images: images,
      totalTokens: (usage?['total_tokens'] as num?)?.toInt(),
    );
  }

  Future<http.Response> _generateFromText(
      GenerationRequest request, String apiKey) {
    final body = <String, dynamic>{
      'model': _model(request),
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
          ..fields['model'] = _model(request)
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
      hint = ' Für GPT-Image-Modelle muss die Organisation bei OpenAI '
          'verifiziert sein (platform.openai.com → Settings → Organization).';
    } else if (response.statusCode == 404) {
      hint = ' Existiert die gewählte Modell-ID? Sie kann in den '
          'Einstellungen angepasst werden.';
    } else if (response.statusCode == 429) {
      hint = detail.contains('insufficient_quota') ||
              detail.contains('exceeded your current quota')
          ? '\n\nHinweis: Das OpenAI-Guthaben ist aufgebraucht. Bitte auf '
              'platform.openai.com → Settings → Billing Guthaben aufladen – '
              'erneutes Versuchen hilft sonst nicht.'
          : ' Rate-Limit erreicht – kurz warten und erneut versuchen.';
    }
    return 'OpenAI-Fehler (${response.statusCode}): $detail$hint';
  }
}

/// Stability AI Stable Image (Engines "core" und "ultra"): Seitenverhältnis,
/// Negativ-Prompt, Seed und Style-Presets (Core).
class StabilityGenerator implements ImageGenerator {
  /// Nur bekannte Engines als URL-Pfad zulassen.
  static String _engine(GenerationRequest request) => switch (request.model) {
        'ultra' => 'ultra',
        'sd3' => 'sd3',
        _ => 'core',
      };

  @override
  Future<GenerationResult> generate(
      GenerationRequest request, String apiKey) async {
    // Die API liefert ein Bild pro Anfrage – für Batches parallel anfragen.
    final futures = List.generate(
      request.count,
      (i) => _generateSingle(request, apiKey, i),
    );
    final images = await Future.wait(futures);
    double? credits;
    try {
      credits = await fetchCredits(apiKey);
    } catch (_) {
      // Guthaben-Abfrage ist optional – Fehler nicht durchreichen.
    }
    return GenerationResult(images: images, creditsRemaining: credits);
  }

  /// Fragt das verbleibende Guthaben (Credits) des Kontos ab.
  static Future<double?> fetchCredits(String apiKey) async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse('https://api.stability.ai/v1/user/balance'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw GenerationException(
          'Guthaben-Abfrage fehlgeschlagen (${response.statusCode}).');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['credits'] as num?)?.toDouble();
  }

  Future<GeneratedImage> _generateSingle(
      GenerationRequest request, String apiKey, int index) async {
    final engine = _engine(request);
    final endpoint =
        'https://api.stability.ai/v2beta/stable-image/generate/$engine';
    final multipart = http.MultipartRequest('POST', Uri.parse(endpoint))
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
    // Style-Presets unterstützt nur die Core-Engine.
    if (request.stylePreset.isNotEmpty && engine == 'core') {
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
    } else if (response.statusCode == 402 ||
        detail.contains('insufficient balance') ||
        detail.contains('credits')) {
      hint = '\n\nHinweis: Die Stability-Credits sind aufgebraucht. Bitte '
          'auf platform.stability.ai → Billing Guthaben aufladen.';
    } else if (response.statusCode == 429) {
      hint = ' Rate-Limit erreicht – kurz warten und erneut versuchen.';
    }
    return 'Stability-AI-Fehler (${response.statusCode}): $detail$hint';
  }
}

/// Google Gemini (Nano Banana, z. B. gemini-2.5-flash-image): Referenzbilder,
/// Seitenverhältnis und – bei Pro-Modellen – Auflösung bis 4K.
class GeminiGenerator implements ImageGenerator {
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  static String _model(GenerationRequest request) =>
      request.model.isEmpty ? 'gemini-2.5-flash-image' : request.model;

  @override
  Future<GenerationResult> generate(
      GenerationRequest request, String apiKey) async {
    // Ein Bild pro Anfrage – für Batches parallel anfragen.
    final futures = List.generate(
      request.count,
      (_) => _generateSingle(request, apiKey),
    );
    final singles = await Future.wait(futures);
    int? totalTokens;
    for (final (_, tokens) in singles) {
      if (tokens != null) totalTokens = (totalTokens ?? 0) + tokens;
    }
    return GenerationResult(
      images: [for (final (image, _) in singles) image],
      totalTokens: totalTokens,
    );
  }

  Future<(GeneratedImage, int?)> _generateSingle(
      GenerationRequest request, String apiKey) async {
    final model = _model(request);
    final imageConfig = <String, dynamic>{
      'aspectRatio': request.geminiAspect,
      // Höhere Auflösungen unterstützen nur die Pro-Modelle.
      if (model.contains('pro') && request.geminiImageSize != '1K')
        'imageSize': request.geminiImageSize,
    };
    final body = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': request.prompt},
            for (final ref in request.references)
              {
                'inlineData': {
                  'mimeType': ref.mimeType,
                  'data': base64Encode(ref.bytes),
                },
              },
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
        'imageConfig': imageConfig,
      },
    };

    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_base/models/$model:generateContent'),
        headers: {
          'x-goog-api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      _throwNetworkError(e);
    }

    if (response.statusCode != 200) {
      throw GenerationException(_readError(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    final blockReason = ((json['promptFeedback']
        as Map<String, dynamic>?)?['blockReason']) as String?;
    if (blockReason != null) {
      throw GenerationException(
          'Gemini hat die Anfrage abgelehnt ($blockReason). '
          'Bitte den Prompt anpassen.');
    }

    final totalTokens = (((json['usageMetadata']
            as Map<String, dynamic>?)?['totalTokenCount']) as num?)
        ?.toInt();
    final candidates = json['candidates'] as List<dynamic>? ?? [];
    for (final candidate in candidates) {
      final parts = (((candidate as Map<String, dynamic>)['content']
              as Map<String, dynamic>?)?['parts'] as List<dynamic>?) ??
          [];
      for (final part in parts) {
        final inline =
            (part as Map<String, dynamic>)['inlineData'] as Map<String, dynamic>?;
        final data = inline?['data'] as String?;
        if (data != null) {
          final mime = inline?['mimeType'] as String? ?? 'image/png';
          return (
            GeneratedImage(
              bytes: base64Decode(data),
              format: mime.contains('/') ? mime.split('/').last : 'png',
            ),
            totalTokens,
          );
        }
      }
    }

    final finishReason = candidates.isNotEmpty
        ? (candidates.first as Map<String, dynamic>)['finishReason'] as String?
        : null;
    throw GenerationException(finishReason == null
        ? 'Gemini hat kein Bild zurückgegeben.'
        : 'Gemini hat kein Bild zurückgegeben ($finishReason). '
            'Bitte den Prompt anpassen.');
  }

  String _readError(http.Response response) {
    var detail = '';
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      detail = ((json['error'] as Map<String, dynamic>?)?['message']
              as String?) ??
          response.body;
    } catch (_) {
      detail = response.body;
    }
    var hint = '';
    if (response.statusCode == 400 || response.statusCode == 401 ||
        response.statusCode == 403) {
      hint = ' Bitte den Gemini-API-Schlüssel in den Einstellungen prüfen '
          '(erhältlich auf aistudio.google.com).';
    } else if (response.statusCode == 404) {
      hint = ' Existiert die gewählte Modell-ID? Sie kann in den '
          'Einstellungen angepasst werden.';
    } else if (response.statusCode == 429) {
      hint = detail.contains('limit: 0')
          ? '\n\nHinweis: „limit: 0“ bedeutet, dass dieses Modell für deinen '
              'Schlüssel KEIN Gratis-Kontingent hat – erneutes Versuchen '
              'hilft nicht. Lösung: In Google AI Studio die Abrechnung '
              'aktivieren (ca. 4 Cent pro Bild) oder in den Einstellungen '
              'einen anderen Provider wählen.'
          : '\n\nHinweis: Kontingent erschöpft – kurz warten und erneut '
              'versuchen. Bleibt der Fehler bestehen, ist vermutlich das '
              'Guthaben aufgebraucht (Prepaid-Plan): in Google AI Studio '
              'unter Billing aufladen.';
    }
    return 'Gemini-Fehler (${response.statusCode}): $detail$hint';
  }
}

/// Text→Bild auf dem eigenen PC (server/local_image_server.py):
/// Stable Diffusion auf der eigenen NVIDIA-GPU – kostenlos, ohne
/// Cloud, alle Daten bleiben lokal. Statt eines API-Schlüssels wird
/// hier die Server-Adresse durchgereicht.
class SelfHostImageGenerator implements ImageGenerator {
  /// „127.0.0.1:8766/" → „http://127.0.0.1:8766".
  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u;
  }

  @override
  Future<GenerationResult> generate(
      GenerationRequest request, String baseUrl) async {
    final url = normalizeBaseUrl(baseUrl);
    if (url.isEmpty) {
      throw GenerationException(
        'Für die eigene GPU fehlt die Adresse des Bild-Servers. '
        'Einstellungen → „Eigener Bild-Server" – dort lässt er sich '
        'auch einrichten und starten.',
      );
    }
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$url/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'prompt': request.prompt,
              'negative_prompt': request.negativePrompt,
              'model': request.model,
              // Der eigene Server nutzt dasselbe Seitenverhältnis-Feld
              // wie Stability.
              'aspect': request.stabilityAspect,
              'count': request.count,
              'transparent': request.transparent,
              if (request.seed != 0) 'seed': request.seed,
            }),
          )
          // Der erste Lauf lädt die Modellgewichte (mehrere GB).
          .timeout(const Duration(minutes: 20));
    } catch (e) {
      throw GenerationException(
        'Der eigene Bild-Server ist nicht erreichbar: $e\n'
        'Läuft er (Einstellungen → Eigener Bild-Server → „Server '
        'starten") und stimmt die Adresse?',
      );
    }
    if (response.statusCode != 200) {
      var detail = response.body;
      try {
        final json = jsonDecode(response.body);
        if (json is Map && json['detail'] != null) {
          detail = json['detail'].toString();
        }
      } catch (_) {}
      throw GenerationException(
          'Bild-Server-Fehler (${response.statusCode}): $detail');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final images = <GeneratedImage>[
      for (final entry in (json['images'] as List? ?? []))
        GeneratedImage(
            bytes: base64Decode(entry.toString()), format: 'png'),
    ];
    if (images.isEmpty) {
      throw GenerationException(
          'Der Bild-Server hat kein Bild geliefert.');
    }
    return GenerationResult(
        images: images, note: (json['note'] as String? ?? '').trim());
  }
}

