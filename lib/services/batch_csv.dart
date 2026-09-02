/// CSV einlesen: aus einer Tabelle wird ein Massenprompt.
///
/// Prompts entstehen selten in der App. Wer vierzig Assets plant, hat
/// sie in einer Tabelle – Name, Prompt, vielleicht ein Negativ – und
/// müsste sie bisher von Hand in Blöcke mit „NAME:" und „PROMPT:"
/// umschreiben. Das hier tut es: Trennzeichen erkennen, Kopfzeile
/// erkennen, Anführungszeichen auflösen, Blöcke schreiben.
library;

class CsvImport {
  const CsvImport({
    required this.text,
    required this.rows,
    required this.skipped,
    required this.delimiter,
  });

  /// Der fertige Massenprompt.
  final String text;

  /// Wie viele Zeilen zu Blöcken wurden.
  final int rows;

  /// Zeilen ohne Prompt, die übersprungen wurden.
  final int skipped;

  /// Das erkannte Trennzeichen – für die Rückmeldung.
  final String delimiter;

  String get summary => rows == 0
      ? 'Keine Zeile mit Name und Prompt gefunden.'
      : '$rows ${rows == 1 ? 'Zeile' : 'Zeilen'} übernommen'
          '${skipped > 0 ? ', $skipped ohne Prompt übersprungen' : ''}.';
}

/// Zerlegt eine CSV-Zeile mit Anführungszeichen nach RFC 4180.
List<String> splitCsvLine(String line, String delimiter) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        buffer.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == delimiter) {
      fields.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  fields.add(buffer.toString());
  return [for (final f in fields) f.trim()];
}

/// Rät das Trennzeichen aus der ersten nicht leeren Zeile: das mit den
/// meisten Treffern außerhalb von Anführungszeichen.
String detectCsvDelimiter(String text) {
  final first = text
      .split(RegExp(r'\r?\n'))
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  var best = ';';
  var bestCount = -1;
  for (final candidate in [';', ',', '\t', '|']) {
    final count = splitCsvLine(first, candidate).length - 1;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

/// Spaltennamen, an denen die Kopfzeile erkannt wird.
const _nameHeads = {'name', 'asset', 'id', 'datei', 'file'};
const _promptHeads = {'prompt', 'beschreibung', 'description', 'text'};
const _negativeHeads = {'negativ', 'negative', 'neg'};
const _referenceHeads = {'referenz', 'reference', 'ref', 'referenzbild'};

/// Baut aus einer CSV den Massenprompt.
///
/// Ohne Kopfzeile gilt: erste Spalte Name, zweite Prompt, dritte
/// Negativ, vierte Referenz. Mit Kopfzeile werden die Spalten an ihren
/// Namen erkannt, in beliebiger Reihenfolge.
CsvImport batchTextFromCsv(String csv) {
  final delimiter = detectCsvDelimiter(csv);
  final lines = [
    for (final line in csv.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) line,
  ];
  if (lines.isEmpty) {
    return CsvImport(text: '', rows: 0, skipped: 0, delimiter: delimiter);
  }

  var nameCol = 0, promptCol = 1, negativeCol = 2, referenceCol = 3;
  var start = 0;
  final head = [
    for (final f in splitCsvLine(lines.first, delimiter)) f.toLowerCase(),
  ];
  final hasHeader = head.any(_promptHeads.contains) ||
      head.any(_nameHeads.contains);
  if (hasHeader) {
    int find(Set<String> names, int fallback) {
      final index = head.indexWhere(names.contains);
      return index < 0 ? fallback : index;
    }

    nameCol = find(_nameHeads, -1);
    promptCol = find(_promptHeads, -1);
    negativeCol = find(_negativeHeads, -1);
    referenceCol = find(_referenceHeads, -1);
    // Eine Kopfzeile ohne Prompt-Spalte: Dann ist der Prompt die erste
    // Spalte, die weder Name noch Negativ noch Referenz ist.
    if (promptCol < 0) {
      for (var i = 0; i < head.length; i++) {
        if (i != nameCol && i != negativeCol && i != referenceCol) {
          promptCol = i;
          break;
        }
      }
    }
    start = 1;
  }

  final blocks = <String>[];
  var skipped = 0;
  var number = 0;
  for (var i = start; i < lines.length; i++) {
    final fields = splitCsvLine(lines[i], delimiter);
    String at(int col) => col >= 0 && col < fields.length ? fields[col] : '';
    final prompt = at(promptCol);
    if (prompt.isEmpty) {
      skipped++;
      continue;
    }
    number++;
    var name = at(nameCol);
    if (name.isEmpty) name = 'zeile-${number.toString().padLeft(2, '0')}';
    final negative = at(negativeCol);
    final reference = at(referenceCol);
    blocks.add([
      'NAME: $name',
      'PROMPT: $prompt',
      if (negative.isNotEmpty) 'NEGATIV: $negative',
      if (reference.isNotEmpty) 'REFERENZ: $reference',
    ].join('\n'));
  }
  return CsvImport(
    text: blocks.join('\n---\n'),
    rows: blocks.length,
    skipped: skipped,
    delimiter: delimiter,
  );
}

/// Dateiendungen, die als Tabelle gelesen werden.
bool isCsvFile(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.csv') || lower.endsWith('.tsv');
}
