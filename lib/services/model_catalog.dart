import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'generators.dart' show GenerationException;

/// Holt die aktuell verfügbaren Bild-Modelle direkt vom Anbieter, damit
/// neue Modelle (z. B. gpt-image-2-Nachfolger) ohne App-Update wählbar
/// sind. Stability hat keine Modell-Liste – dort sind die Engines fest.
Future<List<String>> fetchAvailableModels(
    GenProvider provider, String apiKey) async {
  try {
    switch (provider) {
      case GenProvider.openai:
        final response = await http.get(
          Uri.parse('https://api.openai.com/v1/models'),
          headers: {'Authorization': 'Bearer $apiKey'},
        );
        if (response.statusCode != 200) {
          throw GenerationException(
              'Modell-Liste nicht abrufbar (${response.statusCode}). '
              'Bitte den OpenAI-Schlüssel prüfen.');
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final ids = <String>[
          for (final model in json['data'] as List? ?? [])
            (model as Map)['id'] as String? ?? '',
        ];
        final images = [
          for (final id in ids)
            if (id.startsWith('gpt-image') || id.startsWith('dall-e')) id,
        ]..sort();
        if (images.isEmpty) {
          throw GenerationException(
              'OpenAI hat keine Bild-Modelle gemeldet.');
        }
        return images;
      case GenProvider.gemini:
        final response = await http.get(Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models'
            '?pageSize=200&key=$apiKey'));
        if (response.statusCode != 200) {
          throw GenerationException(
              'Modell-Liste nicht abrufbar (${response.statusCode}). '
              'Bitte den Google-Schlüssel prüfen.');
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final images = <String>[];
        for (final model in json['models'] as List? ?? []) {
          final map = model as Map;
          final name = (map['name'] as String? ?? '')
              .replaceFirst('models/', '');
          final methods = [
            for (final m in map['supportedGenerationMethods'] as List? ?? [])
              m.toString(),
          ];
          // Nur Bild-Modelle, die über generateContent laufen (wie der
          // eingebaute Gemini-Generator).
          if (name.contains('image') &&
              methods.contains('generateContent')) {
            images.add(name);
          }
        }
        images.sort();
        if (images.isEmpty) {
          throw GenerationException(
              'Google hat keine passenden Bild-Modelle gemeldet.');
        }
        return images;
      case GenProvider.stability:
        // Feste Engines – die API bietet keine Modell-Liste.
        return [for (final option in stabilityModelOptions) option.$1];
    }
  } on GenerationException {
    rethrow;
  } catch (e) {
    throw GenerationException('Modell-Liste nicht abrufbar: $e');
  }
}

/// Alle Bild-Modelle aller Anbieter in einer Liste. Damit lässt sich
/// der Anbieter direkt über das Modell wählen – ohne ihn vorher in den
/// Einstellungen umzustellen. [fetchedModels] liefert die vom Anbieter
/// abgerufenen IDs, damit auch brandneue Modelle auftauchen.
List<ImageModelChoice> allImageModels(
    List<String> Function(GenProvider provider) fetchedModels) {
  final all = <ImageModelChoice>[];
  for (final provider in GenProvider.values) {
    final statics = staticModelOptions(provider);
    for (final option in statics) {
      all.add(ImageModelChoice(
          provider: provider, id: option.$1, label: option.$2));
    }
    for (final id in fetchedModels(provider)) {
      if (!statics.any((option) => option.$1 == id)) {
        all.add(ImageModelChoice(provider: provider, id: id, label: id));
      }
    }
  }
  return all;
}
