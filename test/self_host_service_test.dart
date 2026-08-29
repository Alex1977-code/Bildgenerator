import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/self_host_service.dart';

void main() {
  test('normalizeBaseUrl: Schema ergänzen und Slashes entfernen', () {
    expect(SelfHostService.normalizeBaseUrl('127.0.0.1:8765'),
        'http://127.0.0.1:8765');
    expect(SelfHostService.normalizeBaseUrl(' http://127.0.0.1:8765/ '),
        'http://127.0.0.1:8765');
    expect(SelfHostService.normalizeBaseUrl('https://mein-pc:8765//'),
        'https://mein-pc:8765');
    expect(SelfHostService.normalizeBaseUrl(''), '');
  });
}
