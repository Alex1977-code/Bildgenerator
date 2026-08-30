/// Massenprompt: ein Text, der die Beschreibungen für viele Bilder
/// enthält. Die Bilder werden nacheinander erzeugt, unter dem im
/// Prompt genannten Namen gespeichert und sind darüber in der Galerie
/// wiederzufinden.
///
/// Aufbau (Blöcke, getrennt durch eine Zeile aus mindestens drei
/// Bindestrichen):
///
///     NAME: burg-nacht
///     REF: burg.png
///     PROMPT: A medieval castle at night, full moon, …
///     NEGATIV: people, text
///     ---
///     NAME: burg-tag
///     PROMPT: The same castle at noon, …
library;

/// Ein Bild aus dem Massenprompt.
class BatchItem {
  const BatchItem({
    required this.name,
    required this.prompt,
    this.references = const [],
    this.negativePrompt = '',
    this.line = 0,
  });

  /// Eindeutiger Name – wird Dateiname und Titel in der Galerie.
  final String name;
  final String prompt;

  /// Namen der Referenzbilder, die dieses Bild nutzen soll.
  final List<String> references;
  final String negativePrompt;

  /// Zeile im Massenprompt, in der der Block beginnt (1-basiert).
  final int line;
}

/// Ein Fund der Prüfung – mit Zeilennummer, damit man ihn im Text
/// wiederfindet.
class BatchIssue {
  const BatchIssue(this.line, this.message);

  final int line;
  final String message;

  @override
  String toString() => line > 0 ? 'Zeile $line: $message' : message;
}

/// Ergebnis der Prüfung: die erkannten Bilder plus alles, was
/// dagegenspricht.
class BatchPlan {
  const BatchPlan({
    required this.items,
    required this.issues,
    required this.warnings,
  });

  final List<BatchItem> items;

  /// Blockierende Funde – solange welche vorliegen, wird nicht
  /// generiert.
  final List<BatchIssue> issues;

  /// Hinweise, die den Lauf nicht verhindern.
  final List<BatchIssue> warnings;

  bool get isValid => issues.isEmpty && items.isNotEmpty;

  /// Wie viele Bilder Referenzbilder verwenden.
  int get withReferences =>
      items.where((item) => item.references.isNotEmpty).length;
}

/// Obergrenze pro Lauf – schützt vor einem versehentlich riesigen
/// Prompt (und der zugehörigen Rechnung).
const int batchMaxItems = 200;

/// Macht aus einem Namen einen unbedenklichen Dateinamen-Bestandteil.
String sanitizeBatchName(String name) {
  final cleaned = name
      .trim()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('Ä', 'Ae')
      .replaceAll('Ö', 'Oe')
      .replaceAll('Ü', 'Ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  final short = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  return short.isEmpty ? 'bild' : short;
}

/// Vergleichsform für Referenzbild-Namen: Groß-/Kleinschreibung und
/// Dateiendung sollen keine Rolle spielen.
String _refKey(String name) {
  var key = name.trim().toLowerCase();
  final dot = key.lastIndexOf('.');
  if (dot > 0) key = key.substring(0, dot);
  return key;
}

const _keyPattern =
    r'^\s*(name|prompt|ref|refs|referenz|referenzen|negativ|negative)\s*:';

/// Liest einen Massenprompt und prüft ihn.
///
/// [availableReferences] sind die Dateinamen der aktuell geladenen
/// Referenzbilder; genannte, aber fehlende Vorlagen sind ein
/// blockierender Fund.
BatchPlan parseBatchPrompt(
  String text, {
  List<String> availableReferences = const [],
  bool supportsReferences = true,
}) {
  final items = <BatchItem>[];
  final issues = <BatchIssue>[];
  final warnings = <BatchIssue>[];

  final available = {
    for (final name in availableReferences) _refKey(name): name,
  };

  final lines = text.split(RegExp(r'\r?\n'));
  // Blöcke sammeln: (Startzeile, Zeilen)
  final blocks = <(int, List<String>)>[];
  var current = <String>[];
  var start = 1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (RegExp(r'^\s*-{3,}\s*$').hasMatch(line)) {
      blocks.add((start, current));
      current = [];
      start = i + 2;
      continue;
    }
    current.add(line);
  }
  blocks.add((start, current));

  final usedNames = <String, int>{};
  var autoNumber = 0;

  for (final (blockStart, blockLines) in blocks) {
    if (blockLines.every((l) => l.trim().isEmpty)) continue;
    autoNumber++;

    String? name;
    final promptParts = <String>[];
    final references = <String>[];
    var negative = '';
    String? activeKey;
    var nameLine = blockStart;

    for (var i = 0; i < blockLines.length; i++) {
      final raw = blockLines[i];
      final lineNumber = blockStart + i;
      final match = RegExp(_keyPattern, caseSensitive: false).firstMatch(raw);
      if (match != null) {
        final key = match.group(1)!.toLowerCase();
        final value = raw.substring(match.end).trim();
        switch (key) {
          case 'name':
            name = value;
            nameLine = lineNumber;
            activeKey = null;
          case 'prompt':
            if (value.isNotEmpty) promptParts.add(value);
            activeKey = 'prompt';
          case 'negativ':
          case 'negative':
            negative = value;
            activeKey = 'negativ';
          default:
            for (final part in value.split(RegExp(r'[,;]'))) {
              if (part.trim().isNotEmpty) references.add(part.trim());
            }
            activeKey = null;
        }
        continue;
      }
      // Fortsetzungszeilen gehören zum zuletzt begonnenen Feld.
      // Überschriften der Prompt-KI („# Massenprompt") ignorieren.
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (activeKey == 'negativ') {
        negative = negative.isEmpty ? trimmed : '$negative $trimmed';
      } else if (activeKey == 'prompt' || promptParts.isEmpty) {
        if (trimmed.startsWith('#')) continue;
        promptParts.add(trimmed);
        activeKey = 'prompt';
      } else {
        promptParts.add(trimmed);
      }
    }

    final prompt = promptParts.join('\n').trim();
    if (prompt.isEmpty) {
      issues.add(BatchIssue(
          blockStart,
          'Dieser Block hat keine Bildbeschreibung. Erwartet wird eine '
          'Zeile „PROMPT: …".'));
      continue;
    }

    var finalName = (name ?? '').trim();
    if (finalName.isEmpty) {
      finalName = 'bild-${autoNumber.toString().padLeft(2, '0')}';
      warnings.add(BatchIssue(
          blockStart,
          'Kein Name angegeben – das Bild heißt „$finalName". Für '
          'wiederfindbare Ergebnisse besser „NAME: …" ergänzen.'));
    }
    final safeName = sanitizeBatchName(finalName);
    if (safeName != finalName) {
      warnings.add(BatchIssue(
          nameLine,
          'Der Name „$finalName" wird als „$safeName" gespeichert '
          '(Leer- und Sonderzeichen ersetzt).'));
    }
    final previous = usedNames[safeName.toLowerCase()];
    if (previous != null) {
      issues.add(BatchIssue(
          nameLine,
          'Der Name „$safeName" kommt schon in Zeile $previous vor – '
          'Namen müssen eindeutig sein, sonst überschreiben sich die '
          'Bilder.'));
    } else {
      usedNames[safeName.toLowerCase()] = nameLine;
    }

    final resolved = <String>[];
    for (final reference in references) {
      final hit = available[_refKey(reference)];
      if (hit == null) {
        issues.add(BatchIssue(
            blockStart,
            'Das Referenzbild „$reference" ist nicht geladen. Unter '
            '„Referenzbilder" hinzufügen oder die Zeile entfernen.'));
      } else {
        resolved.add(hit);
      }
    }
    if (resolved.isNotEmpty && !supportsReferences) {
      warnings.add(BatchIssue(
          blockStart,
          'Das gewählte KI-Modell wertet keine Referenzbilder aus – sie '
          'werden für dieses Bild ignoriert.'));
    }

    items.add(BatchItem(
      name: safeName,
      prompt: prompt,
      references: resolved,
      negativePrompt: negative,
      line: blockStart,
    ));
  }

  if (items.isEmpty && issues.isEmpty) {
    issues.add(const BatchIssue(
        0,
        'Es wurde kein Bild erkannt. Erwartet werden Blöcke aus „NAME:" '
        'und „PROMPT:", getrennt durch eine Zeile mit „---".'));
  }
  if (items.length > batchMaxItems) {
    issues.add(BatchIssue(
        0,
        '${items.length} Bilder sind mehr als die zulässigen '
        '$batchMaxItems pro Lauf. Bitte den Massenprompt aufteilen.'));
  }

  return BatchPlan(items: items, issues: issues, warnings: warnings);
}

/// Briefing für die Prompt-KI: beschreibt das Format so genau, dass
/// ein direkt verwendbarer Massenprompt herauskommt.
const String batchPromptBriefing =
    'Aufgabe: Erstelle einen „Massenprompt" für einen '
    'KI-Bildgenerator. Er enthält die Beschreibungen mehrerer Bilder, '
    'die nacheinander erzeugt werden. Halte dich exakt an dieses '
    'Format, sonst wird er abgelehnt:\n\n'
    '- Jedes Bild ist ein eigener Block.\n'
    '- Blöcke werden durch eine Zeile getrennt, die nur aus drei '
    'Bindestrichen besteht: ---\n'
    '- Jeder Block beginnt mit „NAME: " und einem kurzen, eindeutigen '
    'Namen (nur Buchstaben, Ziffern, Bindestrich; keine Leerzeichen, '
    'keine Umlaute). Unter diesem Namen wird das Bild gespeichert – '
    'jeder Name darf nur einmal vorkommen, am besten durchnummeriert '
    '(z. B. burg-01, burg-02).\n'
    '- Danach folgt „PROMPT: " mit der eigentlichen Bildbeschreibung '
    'auf Englisch. Sie darf über mehrere Zeilen gehen.\n'
    '- Optional „REF: " mit den Dateinamen der Referenzbilder, die '
    'dieses Bild als Vorlage nutzen soll (mehrere durch Komma '
    'getrennt). Nur nennen, wenn das Bild wirklich eine Vorlage '
    'braucht.\n'
    '- Optional „NEGATIV: " mit dem, was das Bild nicht enthalten '
    'soll.\n'
    '- Keine Nummerierung, keine Aufzählungszeichen, keine '
    'Erklärungen, keine Code-Blöcke – gib ausschließlich den '
    'Massenprompt aus.\n\n'
    'Beispiel für zwei Bilder:\n\n'
    'NAME: burg-01\n'
    'PROMPT: A medieval castle on a cliff at night, full moon, '
    'dramatic clouds, cinematic lighting\n'
    'NEGATIV: people, text, watermark\n'
    '---\n'
    'NAME: burg-02\n'
    'REF: burg.png\n'
    'PROMPT: The same castle at noon, clear blue sky, warm sunlight\n\n'
    'Meine Vorgaben:\n'
    '- Anzahl der Bilder: [HIER ANZAHL]\n'
    '- Thema/Serie: [HIER BESCHREIBEN]\n'
    '- Gemeinsamer Stil aller Bilder: [HIER STIL]\n'
    '- Was sich von Bild zu Bild ändern soll: [HIER VARIANTE]\n'
    '- Verfügbare Referenzbilder: [HIER DATEINAMEN ODER „keine"]';

/// Kleines, gültiges Beispiel zum Ausprobieren.
const String batchPromptExample = 'NAME: burg-01\n'
    'PROMPT: A medieval castle on a cliff at night, full moon, '
    'dramatic clouds, cinematic lighting\n'
    'NEGATIV: people, text, watermark\n'
    '---\n'
    'NAME: burg-02\n'
    'PROMPT: The same medieval castle at noon, clear blue sky, warm '
    'sunlight, birds in the distance\n'
    '---\n'
    'NAME: burg-03\n'
    'PROMPT: The same medieval castle in heavy fog at dawn, muted '
    'colors, mysterious atmosphere';
