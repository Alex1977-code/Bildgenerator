import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
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

  group('Dateiname beim Herunterladen', () {
    HistoryEntry eintrag({String name = '', String kind = 'image'}) =>
        HistoryEntry(
          id: 'abc123',
          prompt: 'egal',
          providerLabel: 'test',
          createdAt: DateTime(2026, 8, 30, 12),
          params: const {},
          format: 'png',
          kind: kind,
          name: name,
        );

    test('Der selbst vergebene Name wird zum Dateinamen', () {
      expect(eintrag(name: 'bld-02-bakery').downloadFileName,
          'bld-02-bakery.png');
    });

    test('Ohne Namen bleibt die Kennung', () {
      expect(eintrag().downloadFileName, 'bild_abc123.png');
      expect(eintrag(kind: 'model').downloadFileName, 'modell_abc123.glb');
    });

    test('Zeichen, die Windows nicht erlaubt, werden ersetzt', () {
      // Ein Name aus dem Massenprompt kann alles Moegliche enthalten;
      // ein Doppelpunkt oder Schrägstrich darin macht den Download
      // sonst stillschweigend kaputt.
      expect(eintrag(name: 'turm: nord/süd').downloadFileName,
          'turm-_nord-süd.png');
      expect(eintrag(name: 'a b').downloadFileName, 'a_b.png');
    });
  });

}
