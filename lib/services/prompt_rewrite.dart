import 'batch_prompt.dart';
import 'prompt_briefing.dart';

/// Ergebnis einer Umschreibung.
class PromptRewrite {
  const PromptRewrite({
    required this.prompt,
    required this.negativePrompt,
    required this.notes,
    required this.changed,
  });

  final String prompt;
  final String negativePrompt;

  /// Was dabei passiert ist – wird in der Oberfläche aufgezählt,
  /// damit die Umschreibung nachvollziehbar bleibt.
  final List<String> notes;

  /// Ob überhaupt etwas geändert wurde.
  final bool changed;
}

/// Schreibt ein Briefing in eine Stichwortkette um.
///
/// Der Anlass: Ein Massenprompt mit 351 Wörtern lief auf SDXL Base.
/// Er war für ein sprachverstehendes Modell geschrieben – ganze Sätze,
/// Verneinungen, Gradzahlen, Erklärungen zum Spiel. SDXL liest davon
/// nichts als Anweisung: Es zerlegt den Text in Blöcke zu 75 Tokens
/// (hier waren es sieben), gewichtet den Anfang am stärksten und
/// nimmt jedes Substantiv als Wunsch. Herausgekommen ist ein Gebäude
/// in Frontalansicht auf einem Erdboden – also genau das, was der
/// Text ausschließen wollte.
///
/// Die Umschreibung macht daraus, was das Modell lesen kann:
///
/// * **Motiv voran**, in den ersten Wörtern, ohne Artikel und
///   Füllwörter.
/// * **Verneinungssätze fliegen raus** – ihre Begriffe wandern in den
///   Negativ-Prompt, wo sie wirken.
/// * **Erklärungen zum Spiel fliegen raus** („the image is downscaled
///   about 13 times") – das Modell kann damit nichts anfangen, aber
///   es sieht die Substantive.
/// * **Gradzahlen und Mengenangaben fliegen raus** – dafür kommt die
///   erprobte Kamera-Kette.
/// * Am Ende der feste Stil-Schwanz, und alles zusammen unter der
///   Wortgrenze des Modells.
PromptRewrite rewriteForKeywordModel(
  String prompt, {
  required String negativePrompt,
  required PromptProfile profile,
  required bool gameAssets,
}) {
  final notes = <String>[];
  final harvested = <String>[];

  final sentences = prompt
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  var droppedNegations = 0;
  var droppedMeta = 0;
  var droppedNumbers = 0;

  final kept = <String>[];
  for (var i = 0; i < sentences.length; i++) {
    final sentence = sentences[i];
    if (_negationPattern.hasMatch(sentence)) {
      harvested.addAll(_harvestNegatives(sentence));
      droppedNegations++;
      continue;
    }
    if (_metaPattern.hasMatch(sentence)) {
      droppedMeta++;
      continue;
    }
    if (_numberPattern.hasMatch(sentence)) {
      droppedNumbers++;
      continue;
    }
    kept.add(sentence);
  }

  if (droppedNegations > 0) {
    notes.add('$droppedNegations Satz/Sätze mit Verneinungen entfernt – '
        'ihre Begriffe stehen jetzt im Negativ-Prompt, wo sie wirken.');
  }
  if (droppedMeta > 0) {
    notes.add('$droppedMeta Erklärung(en) zum Spiel entfernt (Maßstab, '
        'Pixelgröße): Das Modell kann sie nicht befolgen, sieht aber '
        'die Substantive darin.');
  }
  if (droppedNumbers > 0) {
    notes.add('$droppedNumbers Satz/Sätze mit Grad- oder Mengenangaben '
        'entfernt – Zahlen versteht das Modell nicht als Vorgabe.');
  }

  // Stichworte aus dem, was übrig bleibt.
  final fragments = <String>[];
  for (final sentence in kept) {
    for (final raw in sentence.split(',')) {
      for (final piece in _toKeywords(raw)) {
        if (fragments.contains(piece)) continue;
        fragments.add(piece);
      }
    }
  }

  final lead = gameAssets ? gameAssetLeadWords : profile.maxWords ~/ 2;
  final motif = <String>[];
  var words = 0;
  for (final fragment in fragments) {
    final count = _wordCount(fragment);
    if (words + count > lead && motif.isNotEmpty) break;
    motif.add(fragment);
    words += count;
  }

  final tail = gameAssets ? gameAssetKeywords : _neutralTail;
  var out = '${motif.join(', ')}, $tail';
  final total = _wordCount(out);
  if (total > profile.maxWords) {
    // Zur Not vorne kürzen: Der Stil-Schwanz muss vollständig
    // bleiben, sonst fehlt die Kamera.
    final tailWords = _wordCount(tail);
    final budget = profile.maxWords - tailWords;
    final trimmed = <String>[];
    var used = 0;
    for (final fragment in motif) {
      final count = _wordCount(fragment);
      if (used + count > budget) break;
      trimmed.add(fragment);
      used += count;
    }
    out = '${trimmed.join(', ')}, $tail';
    notes.add('Auf ${profile.maxWords} Wörter gekürzt – das ist die '
        'Grenze, ab der ${profile.modelLabel} den Rest kaum noch '
        'gewichtet.');
  }

  // Negativ-Prompt: vorhandene Begriffe, geerntete und die
  // empfohlenen – ohne Dubletten.
  final negatives = <String>[];
  void addNegative(String term) {
    final clean = term.trim().toLowerCase();
    if (clean.isEmpty || clean.length < 3) return;
    if (negatives.contains(clean)) return;
    negatives.add(clean);
  }

  for (final term in negativePrompt.split(',')) {
    addNegative(term);
  }
  for (final term in harvested) {
    addNegative(term);
  }
  if (gameAssets) {
    for (final term in gameAssetNegativeTerms.split(',')) {
      addNegative(term);
    }
  }

  final newNegative = negatives.join(', ');
  final changed = out.trim() != prompt.trim() ||
      newNegative.trim() != negativePrompt.trim();
  if (changed && notes.isEmpty) {
    notes.add('Aus ganzen Sätzen wurde eine Stichwortkette.');
  }
  return PromptRewrite(
    prompt: out,
    negativePrompt: newNegative,
    notes: notes,
    changed: changed,
  );
}

/// Stil-Schwanz, wenn es nicht um Gebäude-Assets geht: nur das
/// Nötigste, damit nichts Erfundenes dazukommt.
const String _neutralTail = 'clean composition, plain background';

/// Sätze, die etwas ausschließen wollen.
final _negationPattern = RegExp(
    r'\b(no|not|never|without|nothing)\b',
    caseSensitive: false);

/// Sätze, die dem Modell etwas erklären, statt ein Bild zu
/// beschreiben.
final _metaPattern = RegExp(
    r'\b(in the game|downscaled|pixels? tall|keep every|the image is|'
    r'because|so keep|readable at that size|exactly one)\b',
    caseSensitive: false);

/// Grad- und Mengenangaben.
final _numberPattern = RegExp(
    r'\b(\d+\s*(degrees?|courses|times)|at most|no more than)\b',
    caseSensitive: false);

/// Füllwörter, die eine Stichwortkette nur verlängern.
final _fillerPattern = RegExp(
    r'^(a|an|the|and|with|there is|there are|it is|its|and the|'
    r'and a|and an)\s+',
    caseSensitive: false);

/// Satzteile, die als Anweisung gemeint sind und als Stichwort
/// nichts taugen.
final _instructionPattern = RegExp(
    r'^(camera|sharp focus|all materials|one warm|every edge|'
    r'plain neutral|never)\b',
    caseSensitive: false);

/// Wörter, an denen ein Satzteil in einen Nebensatz übergeht.
///
/// „a smith's workshop with an open forge and anvil under a wide
/// timber-framed front" zerfällt daran in drei Stichworte. Wichtig:
/// Der Nebensatz wird **nicht** weggeworfen. Beim ersten Anlauf tat
/// er das – und damit war bei einer Waffenschmiede ausgerechnet die
/// Esse weg, also das Merkmal, an dem man sie erkennt. Dieselbe
/// Lehre wie beim Kuppelofen der Bäckerei.
final _splitPattern = RegExp(
    r'\s+\b(with|under|against|over|from|rather than|than|between|'
    r'inside|above|below|around|throughout)\b\s+',
    caseSensitive: false);

/// Macht aus einem Satzteil ein oder zwei Stichworte.
///
/// Ein Doppelpunkt trennt meist Oberbegriff und Ausführung („A
/// medieval armory: a smith's workshop …") – beide Seiten sind
/// brauchbar, deshalb kommt aus einem Fragment auch mal mehr als ein
/// Stichwort.
List<String> _toKeywords(String raw) {
  final base = raw.trim().replaceAll(RegExp(r'[.;]+$'), '').trim();
  if (base.isEmpty) return const [];
  final out = <String>[];
  for (var text in base.split(':')) {
    text = text.trim();
    while (_fillerPattern.hasMatch(text)) {
      text = text.replaceFirst(_fillerPattern, '').trim();
    }
    if (text.isEmpty || _instructionPattern.hasMatch(text)) continue;
    // In Kopf und Nebensätze zerlegen – jeder Teil wird ein eigenes
    // Stichwort, keiner geht verloren.
    for (var chunk in text.split(_splitPattern)) {
      chunk = chunk.trim();
      while (_fillerPattern.hasMatch(chunk)) {
        chunk = chunk.replaceFirst(_fillerPattern, '').trim();
      }
      if (chunk.isEmpty || _instructionPattern.hasMatch(chunk)) continue;
      // Was danach immer noch ein Satz ist, taugt nicht als Stichwort.
      final words =
          chunk.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      if (words.length > 8) continue;
      out.add(chunk.toLowerCase());
    }
  }
  return out;
}

/// Die Begriffe aus einem Verneinungssatz, die in den Negativ-Prompt
/// gehören: „no floor, no terrace, no paving" → floor, terrace,
/// paving.
List<String> _harvestNegatives(String sentence) {
  final out = <String>[];
  for (final match in RegExp(
    r'\b(?:no|not|never|without)\s+([a-zA-Z][a-zA-Z\- ]{2,30}?)'
    r'(?=[,.;]|\s+(?:and|or|under|in|on|at|with|because)\b|$)',
    caseSensitive: false,
  ).allMatches(sentence)) {
    var term = match.group(1)!.trim().toLowerCase();
    // Nachlaufende Füllwörter abschneiden: „ground anywhere" →
    // „ground", „shadow falls anywhere" → „shadow".
    term = term.replaceFirst(_negativeTailPattern, '').trim();
    if (term.isEmpty || term.length < 3) continue;
    // Zu allgemeine Begriffe würden im Negativ-Prompt mehr kaputt
    // machen als sie verhindern.
    if (_tooGeneric.contains(term)) continue;
    out.add(term);
  }
  return out;
}

/// Was am Ende eines geernteten Begriffs nur Füllwort ist.
final _negativeTailPattern = RegExp(
    r'\s+\b(anywhere|at all|else|falls anywhere|in the image|'
    r'under it|beside it|of any kind)\b.*$',
    caseSensitive: false);

/// Begriffe, die im Negativ-Prompt mehr schaden als nützen: Sie
/// kommen in fast jedem Bild vor.
const Set<String> _tooGeneric = {
  'surface',
  'one',
  'it',
  'thing',
  'shape',
  'colour',
  'color',
  'light',
  'image',
};

int _wordCount(String text) => text
    .replaceAll(',', ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .length;


/// Schreibt einen ganzen Massenprompt um und gibt den fertigen Text
/// zurück – so, wie er wieder ins Eingabefeld gehört.
///
/// Referenzbilder bleiben erhalten; sie stehen unabhängig vom
/// Prompt-Stil in ihrer eigenen Zeile.
({String text, List<String> notes, int changedItems}) rewriteBatchText(
  BatchPlan plan, {
  required PromptProfile profile,
  required bool gameAssets,
}) {
  final blocks = <String>[];
  final notes = <String>[];
  var changed = 0;
  for (final item in plan.items) {
    final rewrite = rewriteForKeywordModel(
      item.prompt,
      negativePrompt: item.negativePrompt,
      profile: profile,
      gameAssets: gameAssets,
    );
    if (rewrite.changed) {
      changed++;
      for (final note in rewrite.notes) {
        if (!notes.contains(note)) notes.add(note);
      }
    }
    final lines = <String>[
      'NAME: ${item.name}',
      'PROMPT: ${rewrite.prompt}',
      if (rewrite.negativePrompt.isNotEmpty)
        'NEGATIV: ${rewrite.negativePrompt}',
      if (item.references.isNotEmpty)
        'REFERENZ: ${item.references.join(', ')}',
    ];
    blocks.add(lines.join('\n'));
  }
  return (
    text: blocks.join('\n\n'),
    notes: notes,
    changedItems: changed,
  );
}
