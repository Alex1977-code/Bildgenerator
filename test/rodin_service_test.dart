import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/rodin_service.dart';

void main() {
  test('pickGlbUrl: bevorzugt die GLB-Datei aus der Download-Liste', () {
    final url = RodinService.pickGlbUrl([
      {'url': 'https://cdn.example.com/preview.png', 'name': 'preview.png'},
      {'url': 'https://cdn.example.com/model.glb', 'name': 'model.glb'},
      {'url': 'https://cdn.example.com/model.fbx', 'name': 'model.fbx'},
    ]);
    expect(url, 'https://cdn.example.com/model.glb');
  });

  test('pickGlbUrl: Rückfall auf ersten Eintrag ohne GLB-Endung', () {
    final url = RodinService.pickGlbUrl([
      {'url': 'https://cdn.example.com/output', 'name': 'output'},
    ]);
    expect(url, 'https://cdn.example.com/output');
  });

  test('pickGlbUrl: leere oder falsche Liste → null', () {
    expect(RodinService.pickGlbUrl([]), isNull);
    expect(RodinService.pickGlbUrl(null), isNull);
    expect(RodinService.pickGlbUrl('kaputt'), isNull);
  });
}
