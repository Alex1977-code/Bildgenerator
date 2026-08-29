import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/provenance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Erstellungsnachweis-PDF wird erzeugt (gültiger PDF-Header)',
      () async {
    final pdf = await buildProvenancePdf(
      info: const ProvenanceInfo(
        kind: 'Bild',
        description: 'Ein rotes Spielzeugauto – Test äöüß „Zitat“',
        providerLabel: 'OpenAI (GPT Image)',
        model: 'gpt-image-2',
        details: {'Größe': '1024x1024'},
      ),
      fileType: 'PNG',
      fileBytes: Uint8List.fromList(List.generate(64, (i) => i)),
      creatorName: 'Max Muster',
    );
    expect(pdf.length, greaterThan(1000));
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });
}
