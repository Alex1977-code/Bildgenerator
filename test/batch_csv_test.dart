import 'package:bildgenerator/services/batch_csv.dart';
import 'package:bildgenerator/services/batch_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

/// CSV einlesen: aus der Tabelle wird der Massenprompt – und der
/// muss durch dieselbe Prüfung gehen wie ein getippter.
void main() {
  test('Semikolon mit Kopfzeile, Spalten in beliebiger Reihenfolge', () {
    final r = batchTextFromCsv('Prompt;Name;Negativ\n'
        'low-poly settler figure, hooded;ic3-01-siedler;text, watermark\n'
        'pickaxe stuck in a rock;ic3-02-erz;\n');
    expect(r.delimiter, ';');
    expect(r.rows, 2);
    expect(r.skipped, 0);
    expect(r.text, 'NAME: ic3-01-siedler\n'
        'PROMPT: low-poly settler figure, hooded\n'
        'NEGATIV: text, watermark\n'
        '---\n'
        'NAME: ic3-02-erz\n'
        'PROMPT: pickaxe stuck in a rock');
    // Und der Massenprompt-Parser liest es genauso.
    final plan = parseBatchPrompt(r.text);
    expect(plan.items.map((i) => i.name), ['ic3-01-siedler', 'ic3-02-erz']);
    expect(plan.items.first.negativePrompt, 'text, watermark');
  });

  test('Komma ohne Kopfzeile: erste Spalte Name, zweite Prompt', () {
    final r = batchTextFromCsv('burg-01,castle at night\n'
        'burg-02,"castle at noon, clear sky"\n');
    expect(r.delimiter, ',');
    expect(r.rows, 2);
    // Das Komma in Anführungszeichen trennt nicht.
    expect(r.text, contains('PROMPT: castle at noon, clear sky'));
  });

  test('Tabulator und doppelte Anführungszeichen', () {
    final r = batchTextFromCsv('name\tprompt\n'
        'a\t"a ""quoted"" word"\n');
    expect(r.delimiter, '\t');
    expect(r.text, contains('PROMPT: a "quoted" word'));
  });

  test('Zeilen ohne Prompt werden übersprungen und gezählt', () {
    final r = batchTextFromCsv('name;prompt\n'
        'a;\n'
        'b;something\n'
        ';\n');
    expect(r.rows, 1);
    expect(r.skipped, 2);
    expect(r.summary, '1 Zeile übernommen, 2 ohne Prompt übersprungen.');
  });

  test('ohne Namen bekommt die Zeile eine Nummer', () {
    final r = batchTextFromCsv('prompt\n'
        'first thing\n'
        'second thing\n');
    expect(r.text, contains('NAME: zeile-01'));
    expect(r.text, contains('NAME: zeile-02'));
  });

  test('leere Datei', () {
    final r = batchTextFromCsv('\n\n');
    expect(r.rows, 0);
    expect(r.summary, contains('Keine Zeile'));
  });

  test('Referenzspalte wird übernommen', () {
    final r = batchTextFromCsv('name;prompt;referenz\n'
        'a;thing;textur.png\n');
    expect(r.text, contains('REFERENZ: textur.png'));
  });

  test('Dateiendungen', () {
    expect(isCsvFile('assets.CSV'), isTrue);
    expect(isCsvFile('assets.tsv'), isTrue);
    expect(isCsvFile('prompts.txt'), isFalse);
  });
}
