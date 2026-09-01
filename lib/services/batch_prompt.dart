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
import 'view_direction.dart';

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
  ViewDirection direction = freeDirection,
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
  var currentHasName = false;
  final namePattern = RegExp(r'^\s*name\s*:', caseSensitive: false);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (RegExp(r'^\s*-{3,}\s*$').hasMatch(line)) {
      blocks.add((start, current));
      current = [];
      start = i + 2;
      currentHasName = false;
      continue;
    }
    // Ein zweites „NAME:" beginnt einen neuen Block, auch ohne
    // Trennlinie. Vorher trennte nur „---": Zwei Blöcke mit bloß
    // einer Leerzeile dazwischen verschmolzen zu einem – der zweite
    // Name überschrieb den ersten, und beide Beschreibungen landeten
    // in einem einzigen Bild.
    if (namePattern.hasMatch(line)) {
      if (currentHasName) {
        blocks.add((start, current));
        current = [];
        start = i + 1;
      }
      currentHasName = true;
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
    warnings.addAll(_modelWarnings(items, profile, direction: direction));
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

/// Kamerawinkel für sprachverstehende Modelle: rund 35° von oben.
final _elevationPattern = RegExp(
    r'\b(3[0-9]|4[0-5])\s*(°|degrees?|grad)', caseSensitive: false);

/// Kameraangabe, die ein Diffusions-Modell tatsächlich versteht.
final _isometricPattern = RegExp(
    r'\b(high angle|isometric|top.?down|bird.?s.?eye|three.quarter '
    r'view from above)\b',
    caseSensitive: false);

/// Die Verstärkung des Blickwinkels. „high angle isometric view"
/// allein blieb zu flach – im Bild war fast die volle Fassade zu
/// sehen und vom Dach nur ein Streifen. Erst die Blickrichtung auf
/// das Dach („looking down onto the roof", „tilted top view",
/// „from high above") hat den Winkel gedreht.
final _roofViewPattern = RegExp(
    r'(looking down (onto|on|at) the roof|tilted top view|'
    r'from high above|roof surface|onto the roof)',
    caseSensitive: false);

/// Boden im **positiven** Teil. Der Renderer malt den Erdsaum selbst;
/// alles, was hier steht, malt das Modell zusätzlich – so kam nach
/// dem Teller der ausgefranste Gras- und Erdfleck zurück.
/// „centered on empty ground" war die Formulierung, die es ausgelöst
/// hat.
final _groundInPromptPattern = RegExp(
    r'\b(empty ground|bare ground|on the ground|standing on|grass|'
    r'grassy|dirt|soil|mud|moss|earth|lawn|meadow|terrain|island|'
    r'ground)\b',
    caseSensitive: false);

/// „diorama" und „miniature scene" bringen die Bodenplatte mit –
/// beide sind aus dem positiven Teil in den Negativ-Prompt gewandert.
final _dioramaPattern = RegExp(
    r'\b(diorama|miniature (scene|model|village)|tabletop scene)\b',
    caseSensitive: false);

/// Mengenangaben als Anweisung („at most 15 stone courses", „three
/// windows"). Diffusions-Modelle zählen nicht – sie sehen nur das
/// Substantiv und machen davon mehr.
final _countPattern = RegExp(
    r'\b(at most|no more than|exactly|up to|höchstens|genau)?\s*'
    r'(\d+|one|two|three|four|five|six|zwei|drei|vier|fünf)\s+'
    r'(\w+\s+){0,2}'
    r'(courses|layers|rows|stones|bricks|windows|doors|floors|storeys|'
    r'stories|planks|beams|steps|lagen|steinlagen|fenster|türen)\b',
    caseSensitive: false);

/// Formulierungen, die bei Diffusions-Modellen ins Gegenteil ziehen.
/// „coarse masonry of large softly rounded boulders" hat aus Gebäuden
/// runde Findlings-Kuppeln gemacht.
final _boulderPattern = RegExp(
    r'\b(boulders?|findlinge?|rundlinge?)\b', caseSensitive: false);

/// Streicht verneinte Wortgruppen aus dem Text. Der empfohlene Satz
/// „no terrace, no paving, no low wall …" nennt die Begriffe ja
/// gerade, um sie auszuschließen – ohne diesen Schritt würde die
/// Prüfung genau die richtigen Prompts bemängeln.
final _negatedGroup = RegExp(
    r'\b(no|not|without|ohne|keine?[rsnm]?)\s+([a-zA-Z-]+\s+){0,2}[a-zA-Z-]+',
    caseSensitive: false);

String _withoutNegations(String text) => text.replaceAll(_negatedGroup, ' ');

/// Stil-Angaben, die nicht am Anfang eines Prompts stehen sollten –
/// dort gehört das Motiv hin.
final _styleOpenerPattern = RegExp(
    r'\b(stylized|diorama|game asset|chunky|matte|isometric|high '
    r'angle|golden hour|plain grey|low poly|render|octane|unreal|'
    r'concept art)\b',
    caseSensitive: false);

/// Was die NEGATIV-Zeile bei Gebäude-Assets mindestens abdecken
/// muss. Jede Gruppe steht für einen Fehler, der schon im Bild war:
/// der Gras- und Erdfleck, der Teller darunter und der zu flache
/// Blickwinkel.
const Map<String, List<String>> _requiredNegativeGroups = {
  'den Bodenfleck (Gras, Erde, Moos)': ['grass', 'dirt', 'soil', 'moss'],
  'die Bodenplatte (Platte, Sockel, Podest)': [
    'plate',
    'platform',
    'pedestal',
    'platter',
    'disc',
  ],
  'den flachen Blickwinkel (Front-, Seitenansicht, Augenhöhe)': [
    'front view',
    'side view',
    'eye level',
    'low camera angle',
  ],
};

/// Die ersten [count] Wörter eines Textes.
String _firstWords(String text, int count) =>
    text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(count).join(' ');

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
  ViewDirection direction = freeDirection,
}) {
  final gameAssets = direction.extraRules == 'spielgrafik';
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
  // Der Boden gehört in den Negativ-Prompt, nie in den Prompt: Das
  // Modell malt, was dasteht.
  final ground = items
      .where((item) =>
          _groundInPromptPattern.hasMatch(_withoutNegations(item.prompt)))
      .toList();
  if (ground.isNotEmpty) {
    warnings.add(issue(
        ground,
        'Spielgrafik: ${_names(ground)} nennen im PROMPT den Boden '
        '(Gras, Erde, „empty ground" …). Genau daran ist das zweite '
        'Bild gescheitert: Der Renderer malt den Erdsaum selbst, das '
        'Modell malt zusätzlich einen ausgefransten Fleck, und beim '
        'Freistellen bleibt eine harte Kante stehen. Der Boden gehört '
        'ausschließlich in die NEGATIV-Zeile; die Vereinzelung trägt '
        '„single isolated 3d building model".'));
  }

  // Der Kamerawinkel muss unterschiedlich formuliert sein: GPT-Image
  // und Gemini verstehen „35 degrees", ein Diffusions-Modell nicht –
  // dort zählt „isometric view from high above".
  final keywordStyle = profile.style == PromptStyle.keywords;
  final flat = items
      .where((item) => keywordStyle
          ? !_isometricPattern.hasMatch(item.prompt)
          : !_elevationPattern.hasMatch(item.prompt))
      .toList();
  if (flat.isNotEmpty) {
    warnings.add(issue(
        flat,
        'Spielgrafik: ${flat.length} Beschreibung(en) nennen keine '
        'Aufsicht (${_names(flat)}). Das Spiel braucht rund 35° von '
        'oben – die Bodenebene ist auf 0,62 verkürzt (ROWH 32 auf '
        'TILE 52). '
        '${keywordStyle ? 'Bei diesem Modell gehört dafür „isometric '
            'view from high above" in den Prompt.' : 'Bei diesem Modell '
            'wirkt die Angabe „camera elevation 35 degrees above the '
            'horizon".'}'));
  }
  // Und die Aufsicht muss auf das Dach zeigen. Beim zweiten
  // Bäckerei-Bild stand „high angle isometric view" im Prompt – zu
  // sehen war trotzdem fast die volle Fassade. Der Fehler wiegt
  // schwer: Ein zu flach gesehenes Haus kippt neben dem Gelände und
  // lässt sich nachträglich nicht reparieren.
  final noRoof = items
      .where((item) =>
          !flat.contains(item) && !_roofViewPattern.hasMatch(item.prompt))
      .toList();
  if (noRoof.isNotEmpty) {
    warnings.add(issue(
        noRoof,
        'Spielgrafik: Bei ${_names(noRoof)} steht die Aufsicht nur '
        'als Schlagwort, ohne Blickrichtung. Das blieb zu flach: '
        'fast die volle Fassade, vom Dach nur ein Streifen. '
        '${keywordStyle ? 'Alle drei Angaben aus der Kette nehmen – '
            '„isometric view from high above, looking down onto the '
            'roof, tilted top view".' : 'Dazuschreiben, dass die '
            'Kamera auf das Dach herabsieht und die Dachfläche etwa '
            'ein Drittel des Bildes einnimmt.'}'));
  }

  if (keywordStyle) {
    // Die drei Formulierungen, die den Bäckerei-Block gekippt haben.
    final counts =
        items.where((item) => _countPattern.hasMatch(item.prompt)).toList();
    if (counts.isNotEmpty) {
      warnings.add(issue(
          counts,
          'Spielgrafik: ${_names(counts)} enthalten Mengenangaben '
          '(„at most 15 stone courses" o. Ä.). ${profile.modelLabel} '
          'zählt nicht – es sieht nur das Substantiv und macht davon '
          'mehr. Solche Vorgaben ersatzlos streichen.'));
    }
    final degrees = items
        .where((item) => _elevationPattern.hasMatch(item.prompt))
        .toList();
    if (degrees.isNotEmpty) {
      warnings.add(issue(
          degrees,
          'Spielgrafik: ${_names(degrees)} nennen eine Gradzahl. '
          '${profile.modelLabel} kennt keine Winkel; die Aufsicht '
          'bringt nur die Kette „isometric view from high above, '
          'looking down onto the roof, tilted top view".'));
    }
    final dioramas =
        items.where((item) => _dioramaPattern.hasMatch(item.prompt)).toList();
    if (dioramas.isNotEmpty) {
      warnings.add(issue(
          dioramas,
          'Spielgrafik: ${_names(dioramas)} nennen „diorama" oder '
          '„miniature scene" im PROMPT. Beide bringen die Bodenplatte '
          'mit – sie gehören in die NEGATIV-Zeile, im PROMPT steht '
          '„stylized game asset".'));
    }
    final boulders =
        items.where((item) => _boulderPattern.hasMatch(item.prompt)).toList();
    if (boulders.isNotEmpty) {
      warnings.add(issue(
          boulders,
          'Spielgrafik: ${_names(boulders)} sprechen von „boulders". '
          'Gemeint ist grobes Mauerwerk, an kommt „Gebäude aus '
          'Findlingen" – runde Lehmkuppeln ohne Dach. Besser „chunky '
          'rounded shapes" wie in der Vorlage.'));
    }
    // Motivanteil: Steht am Anfang schon der Stil, ist das Gebäude
    // verloren.
    final styleFirst = items
        .where((item) => _styleOpenerPattern
            .hasMatch(_firstWords(item.prompt, gameAssetLeadWords)))
        .toList();
    if (styleFirst.isNotEmpty) {
      warnings.add(issue(
          styleFirst,
          'Spielgrafik: Bei ${_names(styleFirst)} stehen schon in den '
          'ersten $gameAssetLeadWords Wörtern Stil-Angaben. Dorthin '
          'gehört das Motiv (Gebäudeart, auffälligstes Merkmal, Wände, '
          'Dach, ein bis zwei Requisiten); der Stil-Schwanz kommt '
          'danach.'));
    }
  }
  if (profile.negativeHandling == NegativeHandling.ignored) {
    // Ohne wirksamen Negativ-Prompt lässt sich weder der Bodenfleck
    // noch das zweite Gebäude verhindern – das muss dastehen, bevor
    // 43 Blöcke durchlaufen.
    warnings.add(issue(
        items,
        'Spielgrafik: ${profile.modelLabel} wertet den NEGATIV-Block '
        'nicht aus (Guidance ≤ 1). Bodenfleck, Bodenplatte und ein '
        'zweites Gebäude lassen sich damit nicht ausschließen – für '
        'Gebäude-Assets besser SDXL Base oder SD 3.5 wählen.'));
  } else {
    // Drei Gruppen, die alle drei schon einmal gefehlt haben.
    for (final group in _requiredNegativeGroups.entries) {
      final missing = items
          .where((item) => !group.value.any(
              (term) => item.negativePrompt.toLowerCase().contains(term)))
          .toList();
      if (missing.isEmpty) continue;
      warnings.add(issue(
          missing,
          'Spielgrafik: ${missing.length} NEGATIV-Zeile(n) schließen '
          '${group.key} nicht aus (${_names(missing)}). '
          'Empfohlen ist die vollständige Zeile: '
          '$gameAssetNegativeTerms'));
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
  ViewDirection direction = freeDirection,
}) {
  final names = references.join(', ');
  final keywords = profile.style == PromptStyle.keywords;
  // Auch im Massenprompt gehört die Kamera in jede Zeile – bei
  // vierzig Bildern in einem Lauf fällt eine verrutschte Ansicht erst
  // auf, wenn alle fertig sind.
  final kamera = '\n\n${viewDirectionBriefing(direction, profile.style, profile.negativeHandling, profile.modelLabel)}';
  final assets = direction.extraRules == 'spielgrafik'
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
      '$kamera$assets\n\n'
      'Beispiel:\n\n'
      '${batchPromptExample(profile, direction: direction)}\n\n'
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
String batchPromptExample(PromptProfile profile,
    {ViewDirection direction = freeDirection}) {
  final gameAssets = direction.extraRules == 'spielgrafik';
  // Bei Spielgrafiken ist der erprobte Block die beste Vorlage: Er
  // zeigt die Aufteilung 15 Wörter Motiv, dann der feste Stil-Schwanz.
  if (gameAssets && profile.style == PromptStyle.keywords) {
    return gameAssetExample;
  }
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
