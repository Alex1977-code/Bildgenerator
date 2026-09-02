/// Der Pack-Modus: mehrere Assets in einem Zug, mit gesperrtem Stil.
///
/// **Wofür.** Ein Spiel braucht selten ein Modell, sondern einen Satz:
/// Fass, Kiste, Sack, Laterne. Einzeln erzeugt sehen die vier aus wie
/// von vier verschiedenen Leuten – eines glänzend, eines matt, eines
/// mit Kantenrundung, eines ohne. Nicht weil der Prompt schlecht war,
/// sondern weil er jedes Mal ein bisschen anders lautete.
///
/// **Die Stil-Sperre.** Der Stilblock wird **einmal** geschrieben und
/// danach für jeden Gegenstand **wörtlich und unverändert**
/// wiederverwendet. Nicht sinngemäß, nicht umformuliert – Text→3D- und
/// Text→Bild-Modelle reagieren auf jede Umstellung, und schon eine
/// andere Reihenfolge derselben Wörter ergibt ein anderes Ergebnis.
///
/// Dazu kommt: derselbe **Seed** für den ganzen Satz, wo der Anbieter
/// einen nimmt, und dieselben Einstellungen. Was sich ändern darf, ist
/// allein das Motiv.
///
/// **Was der Modus nicht kann.** Er macht aus vier Läufen keinen
/// einen. Jeder Gegenstand kostet, was er kostet – die Sperre spart
/// keine Kosten, sie spart Nacharbeit.
library;

import 'batch_prompt.dart' show sanitizeBatchName;

/// Ein Gegenstand im Satz.
class PackItem {
  const PackItem({
    required this.name,
    required this.subject,
    this.note = '',
  });

  /// Der Name – wird Dateiname und Titel.
  final String name;

  /// Das Motiv, und **nur** das Motiv: „ein Holzfass mit drei
  /// Eisenreifen". Kein Stil, keine Kamera, keine Qualitätswörter –
  /// die kommen aus dem gesperrten Block.
  final String subject;

  /// Eine Bemerkung für den Menschen, geht nicht in den Prompt.
  final String note;

  String get fileName => sanitizeBatchName(name);
}

/// Der gesperrte Stil eines Satzes.
class PackStyle {
  const PackStyle({
    required this.block,
    this.negative = '',
    this.seed,
    this.lockSeed = true,
  });

  /// Der Stilblock, wörtlich. Alles, was für jeden Gegenstand gleich
  /// sein soll: Material, Beleuchtung, Kamera, Detailgrad, Farbwelt.
  final String block;

  /// Der Negativ-Prompt, ebenfalls für alle gleich.
  final String negative;

  /// Der Seed. Null heißt: Der Anbieter würfelt – dann ist der Satz
  /// weniger einheitlich, und die App sagt das.
  final int? seed;

  /// Ob derselbe Seed für alle gilt.
  ///
  /// Bei manchen Motiven ist das Gegenteil richtig: Vier Fässer mit
  /// demselben Seed werden sich zu ähnlich. Deshalb abschaltbar – die
  /// Sperre gilt dann nur für den Text.
  final bool lockSeed;

  bool get hasSeed => seed != null;
}

/// Ein fertiger Auftrag für einen Gegenstand.
class PackJob {
  const PackJob({
    required this.item,
    required this.prompt,
    required this.negative,
    required this.seed,
    required this.index,
  });

  final PackItem item;

  /// Motiv plus gesperrter Stilblock – in dieser Reihenfolge.
  final String prompt;

  final String negative;

  /// Der Seed für diesen Auftrag, oder null.
  final int? seed;

  /// Die Position im Satz, ab 1.
  final int index;
}

/// Was beim Bauen des Satzes aufgefallen ist.
class PackIssue {
  const PackIssue(this.message, {this.blocking = false, this.item = ''});

  final String message;

  /// Ob der Lauf daran scheitert.
  final bool blocking;

  /// Auf welchen Gegenstand es sich bezieht – leer heißt: den Satz.
  final String item;

  @override
  String toString() => item.isEmpty ? message : '$item: $message';
}

/// Der fertige Satz.
class PackPlan {
  const PackPlan({
    required this.jobs,
    required this.issues,
    required this.style,
  });

  final List<PackJob> jobs;
  final List<PackIssue> issues;
  final PackStyle style;

  List<PackIssue> get blockers =>
      [for (final i in issues) if (i.blocking) i];

  bool get isValid => blockers.isEmpty && jobs.isNotEmpty;

  /// Ob alle Aufträge denselben Stilblock tragen – der Beweis, dass
  /// die Sperre gehalten hat.
  bool get styleLocked =>
      jobs.every((j) => j.prompt.endsWith(style.block));
}

/// Wörter, die im Motiv nichts verloren haben, weil sie in den
/// Stilblock gehören.
///
/// Sie im Motiv stehen zu lassen ist kein Fehler, den man verbieten
/// müsste – aber es ist fast immer ein Versehen, und es hebt genau die
/// Sperre auf, für die der Modus da ist: Steht „glossy" in einem von
/// vier Motiven, sieht dieses eine anders aus.
const List<String> packStyleWords = [
  'style',
  'stil',
  'lighting',
  'beleuchtung',
  'matte',
  'matt',
  'glossy',
  'glänzend',
  'realistic',
  'realistisch',
  'cartoon',
  'low-poly',
  'low poly',
  'render',
  'camera',
  'kamera',
  'background',
  'hintergrund',
  '4k',
  '8k',
  'photorealistic',
];

/// Höchstzahl der Gegenstände in einem Satz.
///
/// Dieselbe Grenze wie beim Massenprompt, aus demselben Grund: Ein
/// versehentlich riesiger Satz ist vor allem eine Rechnung.
const int packMaxItems = 50;

/// Baut die Aufträge und prüft, was dagegenspricht.
PackPlan buildPack(List<PackItem> items, PackStyle style) {
  final issues = <PackIssue>[];
  final jobs = <PackJob>[];

  if (items.isEmpty) {
    issues.add(const PackIssue(
        'Der Satz ist leer – ohne Gegenstände gibt es nichts zu '
        'erzeugen.',
        blocking: true));
  }
  if (items.length > packMaxItems) {
    issues.add(PackIssue(
        '${items.length} Gegenstände: mehr als $packMaxItems in einem '
        'Satz. Das ist selten Absicht und immer eine Rechnung.',
        blocking: true));
  }
  if (style.block.trim().isEmpty) {
    issues.add(const PackIssue(
        'Kein Stilblock. Ohne ihn ist der Pack-Modus nur eine Liste – '
        'die Gegenstände sehen aus wie einzeln erzeugt.',
        blocking: true));
  }

  final namen = <String>{};
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.name.trim().isEmpty) {
      issues.add(PackIssue('Gegenstand ${i + 1} hat keinen Namen.',
          blocking: true));
      continue;
    }
    if (!namen.add(item.fileName.toLowerCase())) {
      issues.add(PackIssue(
          'Der Name kommt zweimal vor – die zweite Datei würde die '
          'erste überschreiben.',
          blocking: true,
          item: item.name));
    }
    if (item.subject.trim().isEmpty) {
      issues.add(PackIssue('Kein Motiv angegeben.',
          blocking: true, item: item.name));
      continue;
    }

    // Stilwörter im Motiv heben die Sperre auf.
    final klein = item.subject.toLowerCase();
    final gefunden = [
      for (final wort in packStyleWords)
        if (klein.contains(wort)) wort,
    ];
    if (gefunden.isNotEmpty) {
      issues.add(PackIssue(
          'Das Motiv nennt „${gefunden.join('", „')}" – das gehört in '
          'den Stilblock. Steht es nur bei einem Gegenstand, sieht '
          'genau dieser anders aus als der Rest.',
          item: item.name));
    }

    jobs.add(PackJob(
      item: item,
      prompt: '${item.subject.trim()}, ${style.block.trim()}',
      negative: style.negative.trim(),
      seed: style.lockSeed ? style.seed : null,
      index: i + 1,
    ));
  }

  if (style.lockSeed && !style.hasSeed && jobs.length > 1) {
    issues.add(const PackIssue(
        'Kein Seed gesetzt: Der Anbieter würfelt für jeden Gegenstand '
        'neu. Der Text ist gesperrt, das Ergebnis wird trotzdem '
        'ungleichmäßiger. Für einen wirklich geschlossenen Satz einen '
        'Seed eintragen.'));
  }
  if (!style.lockSeed && jobs.length > 1) {
    issues.add(const PackIssue(
        'Seed nicht gesperrt – Absicht bei gleichartigen Motiven '
        '(vier Fässer würden sich mit demselben Seed zu ähnlich).'));
  }

  return PackPlan(jobs: jobs, issues: issues, style: style);
}

/// Liest einen Satz aus Text.
///
/// Ein Format, das man auch von Hand tippt: eine Zeile je Gegenstand,
/// `Name: Motiv`. Alles ab einer Zeile `STIL:` ist der Stilblock, alles
/// ab `NEGATIV:` der Negativ-Prompt.
///
/// Warum kein JSON: Der Satz entsteht beim Nachdenken, nicht beim
/// Programmieren. Wer eine Klammer vergisst, soll trotzdem ein
/// Ergebnis bekommen.
({List<PackItem> items, PackStyle style}) parsePackText(String text,
    {int? seed, bool lockSeed = true}) {
  final items = <PackItem>[];
  final stil = StringBuffer();
  final negativ = StringBuffer();
  var modus = 0; // 0 = Gegenstände, 1 = Stil, 2 = Negativ

  for (final roh in text.split('\n')) {
    final zeile = roh.trim();
    if (zeile.isEmpty) continue;
    final gross = zeile.toUpperCase();
    if (gross.startsWith('STIL:')) {
      modus = 1;
      final rest = zeile.substring(5).trim();
      if (rest.isNotEmpty) stil.write(rest);
      continue;
    }
    if (gross.startsWith('NEGATIV:')) {
      modus = 2;
      final rest = zeile.substring(8).trim();
      if (rest.isNotEmpty) negativ.write(rest);
      continue;
    }
    if (zeile.startsWith('#')) continue;

    switch (modus) {
      case 1:
        if (stil.isNotEmpty) stil.write(' ');
        stil.write(zeile);
      case 2:
        if (negativ.isNotEmpty) negativ.write(' ');
        negativ.write(zeile);
      default:
        final trenner = zeile.indexOf(':');
        if (trenner <= 0) {
          // Ohne Doppelpunkt ist die ganze Zeile das Motiv, und der
          // Name wird daraus gemacht. Besser als die Zeile
          // wegzuwerfen.
          items.add(PackItem(
            name: _nameAus(zeile),
            subject: zeile,
            note: 'Name aus dem Motiv abgeleitet.',
          ));
        } else {
          items.add(PackItem(
            name: zeile.substring(0, trenner).trim(),
            subject: zeile.substring(trenner + 1).trim(),
          ));
        }
    }
  }

  return (
    items: items,
    style: PackStyle(
      block: stil.toString(),
      negative: negativ.toString(),
      seed: seed,
      lockSeed: lockSeed,
    ),
  );
}

/// Ein Name aus den ersten Wörtern eines Motivs.
String _nameAus(String motiv) {
  final woerter = motiv
      .split(RegExp(r'[\s,]+'))
      .where((w) => w.isNotEmpty)
      .take(3)
      .toList();
  return woerter.isEmpty ? 'gegenstand' : woerter.join(' ');
}

/// Die Anleitung für die Prompt-KI, wenn jemand sich einen Satz
/// schreiben lassen will.
String packBriefing() => '''
Aufgabe: Schreibe einen Satz zusammengehöriger Gegenstände für einen
3D-Generator. Der Satz soll wie aus einer Hand wirken.

FORMAT, genau so:

  Name: Motiv
  Name: Motiv
  ...
  STIL: <der Stilblock, einmal für alle>
  NEGATIV: <der Negativ-Prompt, einmal für alle>

REGELN:

- Das MOTIV nennt nur, was der Gegenstand ist und woraus er besteht.
  Beispiel: „ein Holzfass mit drei Eisenreifen".
- Der STIL nennt alles, was für jeden Gegenstand gleich sein muss:
  Material-Anmutung, Detailgrad, Kantenrundung, Farbwelt, Beleuchtung,
  Kameraabstand. Er wird für jeden Gegenstand WÖRTLICH wiederverwendet.
- KEINE Stilwörter im Motiv. Steht „glossy" bei einem von vier
  Gegenständen, sieht genau dieser anders aus – und dafür ist der
  Pack-Modus da.
- Die Gegenstände sollen zueinander passen, sich aber unterscheiden:
  vier Behälter sind ein Satz, vier Fässer sind eine Wiederholung.
- Englisch, weil die Modelle darauf besser reagieren.

Mein Satz: [HIER BESCHREIBEN, z. B. „Requisiten für eine Taverne"]
''';
