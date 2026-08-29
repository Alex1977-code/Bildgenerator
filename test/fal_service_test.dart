import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/fal_service.dart';

void main() {
  test('findGlbUrl: TRELLIS-Antwort (model_mesh mit file_name)', () {
    final url = FalService.findGlbUrl({
      'model_mesh': {
        'url': 'https://v3.fal.media/files/abc/model.glb',
        'content_type': 'application/octet-stream',
        'file_name': 'model.glb',
        'file_size': 123456,
      },
      'timings': {'inference': 12.3},
    });
    expect(url, 'https://v3.fal.media/files/abc/model.glb');
  });

  test('findGlbUrl: Hunyuan-Antwort (content_type gltf-binary)', () {
    final url = FalService.findGlbUrl({
      'model_glb': {
        'url': 'https://v3.fal.media/files/def/output',
        'content_type': 'model/gltf-binary',
        'file_name': 'output',
      },
    });
    expect(url, 'https://v3.fal.media/files/def/output');
  });

  test('findGlbUrl: nackte GLB-URL in einer Liste', () {
    final url = FalService.findGlbUrl({
      'outputs': ['https://cdn.example.com/x.glb?sig=1'],
    });
    expect(url, 'https://cdn.example.com/x.glb?sig=1');
  });

  test('findGlbUrl: nichts Passendes → null', () {
    final url = FalService.findGlbUrl({
      'image': {
        'url': 'https://v3.fal.media/files/ghi/preview.png',
        'content_type': 'image/png',
        'file_name': 'preview.png',
      },
      'note': 'https://example.com/docs',
    });
    expect(url, isNull);
  });

  test('Katalog: Hunyuan 2.x nutzt input_image_url, Rest image_url', () {
    final hunyuanV2 =
        falModels.firstWhere((m) => m.id == 'fal-ai/hunyuan3d/v2');
    expect(hunyuanV2.imageField, 'input_image_url');
    final trellis = falModels.firstWhere((m) => m.id == 'fal-ai/trellis');
    expect(trellis.imageField, 'image_url');
  });
}
