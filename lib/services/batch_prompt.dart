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
///
/// Wie ein Block geschrieben sein muss, hängt am gewählten
/// Bild-Modell: GPT-Image und Gemini wollen ganze Sätze, Stable
/// Diffusion eine Stichwortkette. Deshalb bekommen sowohl die Vorlage
/// für die Prompt-KI als auch die Prüfung das [PromptProfile] des
/// Modells mit.
library;

import 'prompt_briefing.dart';

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

  /// Wie viele Wörter die Bildbeschreibung hat – Maßstab für die
  /// Höchstlänge des gewählten Modells.
  int get wordCount =>
      prompt.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
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
  PromptProfile? profile,
  bool gameAssets = false,
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

  if (profile != null && items.isNotEmpty) {
    warnings.addAll(_modelWarnings(items, profile, gameAssets: gameAssets));
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

/// Verneinungen im Prompt („no text", „ohne Schrift"). Diffusions-
/// Modelle lesen nur die Stichworte und holen das Gemeinte eher ins
/// Bild – solche Angaben gehören in die Zeile „NEGATIV:".
final _negationPattern = RegExp(
    r'(^|[\s,;.(-])(no|not|without|avoid|keine?|kein|ohne)\s+[a-zA-Z\u00e4\u00f6\u00fc\u00c4\u00d6\u00dc]',
    caseSensitive: false);

/// Überschriften eines gegliederten Briefings – die gehören zu
/// GPT-Image und Gemini, nicht in eine Stichwortkette.
final _headingPattern = RegExp(
    r'(^|\n)\s*(motiv|subject|aufbau|composition|stil|style|kamera|'
    r'camera|licht|light(ing)?|hintergrund|background|ausgabe|output)\s*:',
    caseSensitive: false);

/// Bodenplatte, Terrasse und Verwandte – bei Spielgrafiken tabu.
final _basePlatePattern = RegExp(
    r'\b(terrace|patio|paving|paved|cobbled|cobblestone|plinth|pedestal|'
    r'base ?plate|platform|low wall|fence|steps|staircase|stairs)\b',
    caseSensitive: false);

/// Ein zweites Gebäude im selben Bild.
final _secondBuildingPattern = RegExp(
    r'\b(and|with|next to|beside|plus)\s+(a|an|another|two|second)?\s*'
    r'\w*\s?(tower|barn|shed|stable|chapel|windmill|hut|cottage|house|'
    r'building|silo)\b',
    caseSensitive: false);

/// Kamerawinkel: die Spielgrafik braucht rund 35° von oben.
final _elevationPattern = RegExp(
    r'\b(3[0-9]|4[0-5])\s*(°|degrees?|grad)', caseSensitive: false);

/// Streicht verneinte Wortgruppen aus dem Text. Der empfohlene Satz
/// „no terrace, no paving, no low wall …" nennt die Begriffe ja
/// gerade, um sie auszuschließen – ohne diesen Schritt würde die
/// Prüfung genau die richtigen Prompts bemängeln.
final _negatedGroup = RegExp(
    r'\b(no|not|without|ohne|keine?[rsnm]?)\s+([a-zA-Z-]+\s+){0,2}[a-zA-Z-]+',
    caseSensitive: false);

String _withoutNegations(String text) => text.replaceAll(_negatedGroup, ' ');

/// Namen der ersten drei Treffer, danach nur noch die Anzahl.
String _names(List<BatchItem> hits) {
  final shown = hits.take(3).map((item) => '\u201e${item.name}"').join(', ');
  return hits.length > 3 ? '$shown … (+${hits.length - 3})' : shown;
}

/// Alles, was am gewählten Bild-Modell hängt: Höchstlänge, Prompt-Art
/// und der Umgang mit dem Negativ-Prompt. Nichts davon blockiert den
/// Lauf – es sind Hinweise, die die Ergebnisse deutlich verbessern.
List<BatchIssue> _modelWarnings(
  List<BatchItem> items,
  PromptProfile profile, {
  bool gameAssets = false,
}) {
  final warnings = <BatchIssue>[];
  BatchIssue issue(List<BatchItem> hits, String message) =>
      BatchIssue(hits.first.line, message);

  if (profile.maxWords > 0) {
    final tooLong =
        items.where((item) => item.wordCount > profile.maxWords).toList();
    if (tooLong.isNotEmpty) {
      final longest = tooLong
          .map((item) => item.wordCount)
          .reduce((a, b) => a > b ? a : b);
      warnings.add(issue(
          tooLong,
          '${tooLong.length} Beschreibung(en) sind länger als die für '
          '${profile.modelLabel} sinnvollen ${profile.maxWords} Wörter '
          '(längste: $longest). Betroffen: ${_names(tooLong)}. Was '
          'darüber steht, gewichtet das Modell kaum noch.'));
    }
  }

  final withNegative =
      items.where((item) => item.negativePrompt.trim().isNotEmpty).toList();
  switch (profile.negativeHandling) {
    case NegativeHandling.ignored:
      if (withNegative.isNotEmpty) {
        warnings.add(issue(
            withNegative,
            '${profile.modelLabel} arbeitet ohne Guidance und wertet '
            'den Negativ-Prompt nicht aus – die NEGATIV-Zeilen von '
            '${_names(withNegative)} bleiben wirkungslos. Das '
            'Unerwünschte muss positiv im PROMPT stehen (\u201eleerer '
            'grauer Hintergrund" statt \u201ekeine Requisiten").'));
      }
    case NegativeHandling.inPrompt:
      if (withNegative.isNotEmpty) {
        warnings.add(issue(
            withNegative,
            '${profile.modelLabel} kennt kein Negativ-Feld. Die '
            'NEGATIV-Zeilen werden als Satz \u201eDo not include in the '
            'image: …" an den jeweiligen Prompt gehängt und wirken '
            'dadurch (${withNegative.length} von ${items.length} '
            'Bildern).'));
      }
    case NegativeHandling.separateField:
      if (withNegative.isEmpty) {
        warnings.add(BatchIssue(
            items.first.line,
            '${profile.modelLabel} wertet einen Negativ-Prompt aus, es '
            'hat aber kein Block eine Zeile \u201eNEGATIV:". Ohne sie '
            'gilt für alle Bilder nur der Negativ-Prompt aus dem '
            'Formular.'));
      }
  }

  if (profile.style == PromptStyle.keywords) {
    final negations = items
        .where((item) => _negationPattern.hasMatch(item.prompt))
        .toList();
    if (negations.isNotEmpty) {
      warnings.add(issue(
          negations,
          '${negations.length} Beschreibung(en) enthalten Verneinungen '
          '(${_names(negations)}). ${profile.modelLabel} liest nur die '
          'Stichworte: \u201eno text" wirkt wie \u201etext". '
          '${profile.negativeHandling == NegativeHandling.separateField
              ? 'Solche Angaben gehören in die Zeile \u201eNEGATIV:".'
              : 'Solche Angaben müssen positiv umformuliert werden.'}'));
    }
    final briefings =
        items.where((item) => _headingPattern.hasMatch(item.prompt)).toList();
    if (briefings.isNotEmpty) {
      warnings.add(issue(
          briefings,
          '${briefings.length} Beschreibung(en) sind als gegliedertes '
          'Briefing mit Überschriften geschrieben (${_names(briefings)}). '
          'Das ist für GPT-Image und Gemini gedacht; '
          '${profile.modelLabel} braucht eine durchgehende, dichte '
          'Stichwortkette.'));
    }
  }

  if (!gameAssets) return warnings;

  final plates = items
      .where((item) =>
          _basePlatePattern.hasMatch(_withoutNegations(item.prompt)))
      .toList();
  if (plates.isNotEmpty) {
    warnings.add(issue(
        plates,
        'Spielgrafik: ${_names(plates)} beschreiben eine Bodenplatte '
        '(Terrasse, Pflaster, Mäuerchen, Treppe …). Das Gebäude muss '
        'direkt auf flachem Boden stehen – der Renderer malt den '
        'Erdsaum selbst, eine mitgemalte Platte läge darüber.'));
  }
  final pairs = items
      .where((item) =>
          _secondBuildingPattern.hasMatch(_withoutNegations(item.prompt)))
      .toList();
  if (pairs.isNotEmpty) {
    warnings.add(issue(
        pairs,
        'Spielgrafik: ${_names(pairs)} nennen möglicherweise ein '
        'zweites Gebäude. Jedes Asset ist genau ein Gebäude, sonst '
        'lässt es sich nicht auf einen Knoten setzen.'));
  }
  final flat = items
      .where((item) => !_elevationPattern.hasMatch(item.prompt))
      .toList();
  if (flat.isNotEmpty) {
    warnings.add(issue(
        flat,
        'Spielgrafik: ${flat.length} Beschreibung(en) nennen keinen '
        'Kamerawinkel (${_names(flat)}). Das Spiel braucht rund 35° von '
        'oben – die Bodenebene ist auf 0,62 verkürzt (ROWH 32 auf '
        'TILE 52); flach gesehene Gebäude kippen neben dem Gelände.'));
  }
  if (profile.negativeHandling == NegativeHandling.separateField) {
    final withoutTerms = items
        .where((item) => !item.negativePrompt
            .toLowerCase()
            .contains('platform'))
        .toList();
    if (withoutTerms.isNotEmpty) {
      warnings.add(issue(
          withoutTerms,
          'Spielgrafik: ${withoutTerms.length} NEGATIV-Zeile(n) führen '
          'die Bodenplatten-Begriffe nicht (${_names(withoutTerms)}). '
          'Empfohlen: $gameAssetNegativeTerms'));
    }
  }
  return warnings;
}

/// Vorlage für die Prompt-KI: beschreibt das Format so genau, dass ein
/// direkt verwendbarer Massenprompt herauskommt – und dazu die
/// Schreibregeln des gewählten Bild-Modells.
///
/// [references] sind die Dateinamen der geladenen Referenzbilder,
/// [gameAssets] hängt die Regeln für Gebäude-Assets an.
String batchPromptBriefing(
  PromptProfile profile, {
  List<String> references = const [],
  bool gameAssets = false,
}) {
  final names = references.join(', ');
  final keywords = profile.style == PromptStyle.keywords;
  final assets = gameAssets
      ? '\n\n${gameAssetBriefing(profile.style)}'
      : '';
  return 'Aufgabe: Erstelle einen „Massenprompt" für einen '
      'KI-Bildgenerator. Er enthält die Beschreibungen mehrerer Bilder, '
      'die nacheinander erzeugt werden. Die Bilder werden mit '
      '${profile.modelLabel} erzeugt – die Beschreibungen müssen genau '
      'zu diesem Modell passen.\n\n'
      'Format (wird sonst abgelehnt):\n'
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
      '${_negativeFormatRule(profile)}'
      '- Keine Nummerierung, keine Aufzählungszeichen, keine '
      'Erklärungen, keine Code-Blöcke – gib ausschließlich den '
      'Massenprompt aus.\n\n'
      'So muss jede PROMPT-Zeile für ${profile.modelLabel} geschrieben '
      'sein:\n'
      '${keywords ? _keywordPromptRules(profile) : _briefingPromptRules(profile)}'
      '$assets\n\n'
      'Beispiel für zwei Bilder:\n\n'
      '${batchPromptExample(profile)}\n\n'
      'Meine Vorgaben:\n'
      '- Anzahl der Bilder: [HIER ANZAHL]\n'
      '- Thema/Serie: [HIER BESCHREIBEN]\n'
      '- Gemeinsamer Stil aller Bilder: [HIER STIL]\n'
      '- Was sich von Bild zu Bild ändern soll: [HIER VARIANTE]\n'
      '- Verfügbare Referenzbilder: ${names.isEmpty ? 'keine' : names}';
}

/// Was in der Formatbeschreibung über „NEGATIV:" stehen muss – das
/// hängt daran, was das Modell damit anfängt.
String _negativeFormatRule(PromptProfile profile) =>
    switch (profile.negativeHandling) {
      NegativeHandling.separateField =>
        '- „NEGATIV: " mit dem, was dieses eine Bild nicht enthalten '
            'soll. Gib die Zeile in jedem Block an – sie wird für genau '
            'dieses Bild ausgewertet.\n',
      NegativeHandling.inPrompt =>
        '- „NEGATIV: " mit dem, was dieses eine Bild nicht enthalten '
            'soll. ${profile.modelLabel} hat kein Negativ-Feld; die App '
            'hängt die Zeile als Satz „Do not include in the image: …" '
            'an genau diesen Prompt an, sie wirkt also.\n',
      NegativeHandling.ignored =>
        '- Eine Zeile „NEGATIV: " brauchst du nicht: '
            '${profile.modelLabel} wertet sie nicht aus. Schreibe '
            'Unerwünschtes stattdessen positiv in den PROMPT („empty '
            'grey background" statt „no props").\n',
    };

String _keywordPromptRules(PromptProfile profile) =>
    '- Der Text hinter „PROMPT:" ist eine dichte Stichwortkette auf '
    'Englisch, durch Kommas getrennt – keine Sätze, keine '
    'Überschriften, keine Anweisungen.\n'
    '- Reihenfolge ist Gewichtung: Motiv und Bauform zuerst, dann '
    'Material und Farben, dann Stil und Technik, zuletzt Kamera, Licht '
    'und Hintergrund.\n'
    '- Keine Verneinungen im PROMPT („no text" wirkt wie „text"). '
    '${profile.negativeHandling == NegativeHandling.separateField
        ? 'Unerwünschtes gehört in die Zeile „NEGATIV:".'
        : 'Unerwünschtes durch positive Formulierungen ersetzen.'}\n'
    '- Höchstens etwa ${profile.maxWords} Wörter je PROMPT.';

String _briefingPromptRules(PromptProfile profile) =>
    '- Der Text hinter „PROMPT:" ist ein zusammenhängender Auftrag in '
    'ganzen Sätzen; das Modell versteht Sprache und befolgt '
    'Anweisungen.\n'
    '- Verneinungen sind erlaubt und wirken („kein Text im Bild", '
    '„keine zweite Figur").\n'
    '- Maße, Proportionen und Farben so genau wie möglich nennen.\n'
    '- Englisch bringt meist etwas bessere Ergebnisse.\n'
    '- ${profile.negativeNote}';

/// Kleines, gültiges Beispiel zum Ausprobieren – in der Schreibweise
/// des gewählten Modells.
String batchPromptExample(PromptProfile profile) {
  if (profile.style == PromptStyle.keywords) {
    final negative = profile.negativeHandling == NegativeHandling.ignored
        ? ''
        : 'NEGATIV: people, text, watermark, blurry, low quality\n';
    return 'NAME: burg-01\n'
        'PROMPT: medieval stone castle on a cliff, tall keep, warm '
        'sandstone walls, night scene, full moon, dramatic clouds, '
        'cinematic rim light\n'
        '$negative'
        '---\n'
        'NAME: burg-02\n'
        'PROMPT: the same medieval stone castle, noon, clear blue sky, '
        'warm sunlight, soft shadows, distant birds\n'
        '${negative.isEmpty ? '' : 'NEGATIV: people, text, watermark, blurry, low quality'}';
  }
  return 'NAME: burg-01\n'
      'PROMPT: A medieval stone castle on a cliff at night. The full '
      'moon stands behind the keep, dramatic clouds, cinematic '
      'lighting. No people, no text in the image.\n'
      'NEGATIV: people, text, watermark\n'
      '---\n'
      'NAME: burg-02\n'
      'PROMPT: The same castle at noon under a clear blue sky, warm '
      'sunlight, soft shadows on the walls.\n'
      'NEGATIV: people, text, watermark';
}
