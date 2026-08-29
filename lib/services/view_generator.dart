import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/models.dart';
import 'generators.dart';
import 'settings_service.dart';

/// Erzeugt aus einer Textbeschreibung konsistente Ansichten
/// (Vorn/Links/Rechts/Hinten) über den konfigurierten Bild-Provider.
///
/// Konsistenz-Strategie: Zuerst wird die Vorderansicht generiert; die
/// übrigen Ansichten erhalten sie als Referenzbild plus strenge
/// Konsistenz-Anweisungen (identisches Objekt, gleiche Skalierung,
/// orthographische Ansicht, neutraler transparenter Hintergrund).
class GeneratedViews {
  GeneratedViews({required this.views, this.totalTokens});

  /// Schlüssel: 'front', 'left', 'right', 'back'.
  final Map<String, ReferenceImage> views;
  final int? totalTokens;
}

const _tPosePart = 'full body character standing in a strict T-pose, arms '
    'stretched out horizontally to the sides, legs slightly apart, neutral '
    'expression';

/// Rig-Posen je Figurtyp (siehe auto_rig.dart): sorgen dafür, dass die
/// erzeugten Ansichten zur jeweiligen Skelett-Vorlage passen.
const rigPoseParts = {
  'biped': _tPosePart,
  'quadruped': 'full body animal standing squarely on all four straight '
      'legs, legs clearly separated, head raised and facing forward, tail '
      'extended straight behind',
  'insect': 'full body insect or arthropod with the body horizontal and '
      'all legs spread out symmetrically to the sides, every leg clearly '
      'separated and visible',
  'bird': 'full body bird with both wings fully spread out horizontally '
      'to the sides, tail feathers extended behind, legs visible below '
      'the body',
  'snake': 'full body snake stretched out almost straight with only '
      'gentle curves, head clearly visible at one end',
  'fish': 'full body fish with the body straight and horizontal, all '
      'fins spread and clearly visible',
};

const _stagingPart = 'single subject only, perfectly centered, completely '
    'visible with a small margin, orthographic view without perspective '
    'distortion, plain fully transparent background, no ground plane, no '
    'shadow, no reflections, even diffuse studio lighting, crisp details';

String _frontPrompt(String description, String? pose) =>
    '$description. ${pose == null ? '' : '$pose, '}'
    'exact FRONT view (subject facing the camera directly), $_stagingPart';

String _turnPrompt(String viewInstruction) =>
    'Exactly the same subject as in the reference image: identical shape, '
    'proportions, colors, materials, clothing and details – do not change '
    'anything about the subject itself. $viewInstruction Keep exactly the '
    'same scale, framing and camera distance as the reference image, '
    '$_stagingPart';

/// Prüft, dass der konfigurierte Bild-Provider Referenzbilder kann und
/// ein Schlüssel hinterlegt ist; liefert Provider, Schlüssel, Generator.
(GenProvider, String, ImageGenerator) _requireReferenceProvider(
    SettingsService settings) {
  final provider = settings.provider;
  if (!provider.supportsReferences) {
    throw GenerationException(
        'Hierfür wird ein referenzbildfähiger Bild-Provider benötigt '
        '(OpenAI oder Google Gemini). Bitte in den Einstellungen '
        'umstellen.');
  }
  final apiKey = settings.apiKeyFor(provider)?.trim();
  if (apiKey == null || apiKey.isEmpty) {
    throw GenerationException(
        'Für den Bild-Provider ${provider.label} ist kein API-Schlüssel '
        'hinterlegt (wird für die Bild-KI-Schritte des 3D-Generators '
        'genutzt).');
  }
  return (provider, apiKey, ImageGenerator.forProvider(provider));
}

const _viewInstructions = {
  'left': 'Rotate the subject 90 degrees so we see its pure LEFT side view '
      '(the subject\'s left side faces the camera, its front points to the '
      'right edge of the image).',
  'right': 'Rotate the subject 90 degrees so we see its pure RIGHT side '
      'view (the subject\'s right side faces the camera, its front points '
      'to the left edge of the image).',
  'back': 'Rotate the subject 180 degrees so we see its exact BACK view '
      '(seen directly from behind).',
};

/// Erzeugt die vier Ansichten (bzw. nur die Vorderansicht bei
/// [frontOnly]). In [existing] bereits vorhandene Ansichten werden
/// wiederverwendet statt neu generiert – so lassen sich einzelne
/// Ansichten gezielt austauschen. [pose] ist eine optionale
/// Pose-Anweisung (siehe [rigPoseParts]) für rigging-taugliche
/// Ansichten. Wirft [GenerationException] bei Fehlern.
Future<GeneratedViews> generateViewsFromText({
  required SettingsService settings,
  required String description,
  String? pose,
  required void Function(String stage) onProgress,
  required bool Function() isCancelled,
  bool frontOnly = false,
  Map<String, ReferenceImage> existing = const {},
}) async {
  final neededKeys =
      frontOnly ? const ['front'] : const ['front', 'left', 'right', 'back'];
  if (neededKeys.every(existing.containsKey)) {
    return GeneratedViews(
        views: {for (final key in neededKeys) key: existing[key]!});
  }

  final (provider, apiKey, generator) = _requireReferenceProvider(settings);
  var totalTokens = 0;
  var hasTokens = false;

  GenerationRequest buildRequest(String prompt,
      {List<ReferenceImage> references = const []}) {
    return GenerationRequest(
      provider: provider,
      prompt: prompt,
      references: references,
      // Quadratisch und mit echter Transparenz, wo möglich.
      openAiSize: '1024x1024',
      geminiAspect: '1:1',
      quality: settings.quality,
      transparent: provider == GenProvider.openai,
      outputFormat: 'png',
      count: 1,
      model: settings.modelFor(provider),
      geminiImageSize: '1K',
    );
  }

  Future<ReferenceImage> generateOne(String label, String prompt,
      {List<ReferenceImage> references = const []}) async {
    if (isCancelled()) throw GenerationException('Abgebrochen.');
    onProgress('Ansicht „$label“ wird erzeugt …');
    final result =
        await generator.generate(buildRequest(prompt, references: references), apiKey);
    if (result.totalTokens != null) {
      totalTokens += result.totalTokens!;
      hasTokens = true;
    }
    if (result.images.isEmpty) {
      throw GenerationException('Ansicht „$label“ wurde nicht erzeugt.');
    }
    var bytes = result.images.first.bytes;
    // Gemini liefert keine echte Transparenz – Hintergrund freistellen.
    bytes = await ensureTransparentBackground(bytes);
    return ReferenceImage(bytes: bytes, name: 'ansicht_$label.png');
  }

  final front = existing['front'] ??
      await generateOne('Vorn', _frontPrompt(description, pose));
  final views = <String, ReferenceImage>{'front': front};
  if (!frontOnly) {
    const labels = {'left': 'Links', 'right': 'Rechts', 'back': 'Hinten'};
    for (final entry in _viewInstructions.entries) {
      views[entry.key] = existing[entry.key] ??
          await generateOne(
            labels[entry.key]!,
            _turnPrompt(entry.value),
            references: [front],
          );
    }
  }

  return GeneratedViews(
    views: views,
    totalTokens: hasTokens ? totalTokens : null,
  );
}

const _depthPrompt =
    'Precise monocular depth map of the exact subject in the reference '
    'image: identical framing, position and proportions. Grayscale only – '
    'pure white for the surface points closest to the camera, pure black '
    'for the farthest points and the entire background, smooth continuous '
    'gray gradients in between representing true metric depth. No '
    'outlines, no texture or color details, no lighting or shadow '
    'effects, no text or labels.';

/// Erzeugt per Bild-KI eine Tiefenkarte (Graustufen, hell = nah) zum
/// Referenzbild. Wirft [GenerationException] bei Fehlern.
Future<Uint8List> generateDepthMap({
  required SettingsService settings,
  required ReferenceImage source,
  required String label,
  required void Function(String stage) onProgress,
  required bool Function() isCancelled,
}) async {
  final (provider, apiKey, generator) = _requireReferenceProvider(settings);
  if (isCancelled()) throw GenerationException('Abgebrochen.');
  onProgress('Tiefenkarte „$label“ wird geschätzt …');
  final result = await generator.generate(
    GenerationRequest(
      provider: provider,
      prompt: _depthPrompt,
      references: [source],
      openAiSize: '1024x1024',
      geminiAspect: '1:1',
      quality: settings.quality,
      transparent: false,
      outputFormat: 'png',
      count: 1,
      model: settings.modelFor(provider),
      geminiImageSize: '1K',
    ),
    apiKey,
  );
  if (result.images.isEmpty) {
    throw GenerationException('Tiefenkarte „$label“ wurde nicht erzeugt.');
  }
  return result.images.first.bytes;
}

/// Stellt sicher, dass das Bild einen transparenten Hintergrund hat.
///
/// Hat das Bild bereits Alpha-Transparenz, bleibt es unverändert. Sonst
/// wird der zusammenhängende Hintergrund von den Bildrändern aus per
/// Flutlauf (Flood Fill) entfernt – wichtig für den lokalen
/// 3D-Generator, der die Silhouette aus dem Alphakanal liest.
Future<Uint8List> ensureTransparentBackground(Uint8List imageBytes) async {
  final codec = await ui.instantiateImageCodec(imageBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return imageBytes;
    final pixels = raw.buffer.asUint8List();
    final width = image.width, height = image.height;

    var hasAlpha = false;
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] < 250) {
        hasAlpha = true;
        break;
      }
    }
    if (hasAlpha) return imageBytes;

    // Hintergrundfarbe aus den vier Ecken mitteln.
    int cornerOffset(int x, int y) => (y * width + x) * 4;
    final corners = [
      cornerOffset(0, 0),
      cornerOffset(width - 1, 0),
      cornerOffset(0, height - 1),
      cornerOffset(width - 1, height - 1),
    ];
    final bg = List<int>.filled(3, 0);
    for (final o in corners) {
      for (var c = 0; c < 3; c++) {
        bg[c] += pixels[o + c];
      }
    }
    for (var c = 0; c < 3; c++) {
      bg[c] ~/= corners.length;
    }
    bool isBackground(int o) {
      final dr = pixels[o] - bg[0];
      final dg = pixels[o + 1] - bg[1];
      final db = pixels[o + 2] - bg[2];
      return dr * dr + dg * dg + db * db < 2400;
    }

    final visited = Uint8List(width * height);
    final queue = Queue<int>();
    void seed(int x, int y) {
      final index = y * width + x;
      if (visited[index] == 0 && isBackground(index * 4)) {
        visited[index] = 1;
        queue.add(index);
      }
    }

    for (var x = 0; x < width; x++) {
      seed(x, 0);
      seed(x, height - 1);
    }
    for (var y = 0; y < height; y++) {
      seed(0, y);
      seed(width - 1, y);
    }
    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      pixels[index * 4 + 3] = 0;
      final x = index % width, y = index ~/ width;
      if (x > 0) seed(x - 1, y);
      if (x < width - 1) seed(x + 1, y);
      if (y > 0) seed(x, y - 1);
      if (y < height - 1) seed(x, y + 1);
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final outCodec = await descriptor.instantiateCodec();
    final outFrame = await outCodec.getNextFrame();
    try {
      final png =
          await outFrame.image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List() ?? imageBytes;
    } finally {
      outFrame.image.dispose();
    }
  } finally {
    image.dispose();
  }
}
