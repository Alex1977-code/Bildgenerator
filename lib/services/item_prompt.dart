/// Passende Gegenstände zu einer erzeugten Figur.
///
/// Eine Figur allein ist noch kein Spielinhalt: Es fehlen Schwert,
/// Schild, Helm, Laterne – Dinge, die zur Figur gehören und **zu ihr
/// passen müssen**, in Stil und vor allem in Größe. Genau daran
/// scheitern einzeln erzeugte Gegenstände: Das Schwert wird so lang
/// wie die Figur, der Helm passt auf einen Kürbis.
///
/// Diese Datei liefert dafür drei Dinge:
///
/// * eine Liste von Gegenstandsarten mit **Größenverhältnis** und
///   Bezugsgröße (Figur, Kopf oder Hand),
/// * einen **Vorschlag**, welche davon zu einer Figurbeschreibung
///   passen (ein Ritter braucht Schwert und Schild, kein Zauberbuch),
/// * eine **Prompt-Vorlage**, die Stil und Maßstab der Figur mitgibt –
///   wahlweise mit den Roblox-Regeln.
///
/// **Warum die Maßangabe in den Prompt gehört.** Ein Bildmodell kennt
/// keinen Maßstab: „Schwert" allein ergibt ein Schwert, das das ganze
/// Bild füllt. Erst „blade length about half the character's height"
/// bringt die Proportion ins Bild – und aus dem Bild ins 3D-Modell.
library;

/// Woran sich die Größe eines Gegenstands bemisst.
enum ItemScaleRef {
  /// Am Ganzen: Waffen, Stäbe, Rucksäcke.
  figur,

  /// Am Kopf: Helme, Hüte, Masken, Brillen.
  kopf,

  /// An der Hand: Tränke, Schlüssel, Bücher, Laternen.
  hand,
}

/// Kopf- und Handgröße im Verhältnis zur Gesamthöhe – gemessen an den
/// gedrungenen Spielfiguren, für die diese App gebaut ist (großer
/// Kopf, kurze Glieder), nicht an realen Menschenproportionen.
const headShareOfFigure = 0.25;
const handShareOfFigure = 0.11;

/// Eine Gegenstandsart.
class ItemKind {
  const ItemKind({
    required this.id,
    required this.label,
    required this.group,
    required this.core,
    required this.share,
    required this.scaleRef,
    required this.carry,
    this.robloxAccessoryType,
    this.words = const [],
    this.rigType,
    this.rideable = false,
    this.scaleClause,
    this.extraNegative = '',
  });

  /// Kennung, wie sie in Dateinamen und Verlauf landet.
  final String id;

  /// Deutsche Beschriftung.
  final String label;

  /// Gruppe in der Auswahl: „Waffe", „Am Körper", „Ausrüstung",
  /// „Umgebung".
  final String group;

  /// Der englische Kern des Prompts.
  final String core;

  /// Größe im Verhältnis zu [scaleRef].
  final double share;

  final ItemScaleRef scaleRef;

  /// Wie der Gegenstand getragen wird – steht als Hinweis in der
  /// Oberfläche und erklärt, warum die Größe so gewählt ist.
  final String carry;

  /// Passender Wert der Roblox-Aufzählung `AccessoryType`, wenn es
  /// einen gibt. Null = wird als Werkzeug (`Tool` mit einem Teil
  /// namens `Handle`) in die Hand gegeben, nicht als Accessoire
  /// angezogen.
  ///
  /// Die Namen stammen aus der offiziellen Aufzählung: Hat, Hair,
  /// Face, Neck, Shoulder, Front, Back, Waist (dazu die Werte für
  /// Layered Clothing, die diese App nicht erzeugt).
  final String? robloxAccessoryType;

  /// Wörter in der Figurbeschreibung, die diesen Gegenstand
  /// nahelegen – deutsch und englisch, weil beides vorkommt.
  final List<String> words;

  /// Figurtyp für das Auto-Rigging – null heißt: starres Teil ohne
  /// Skelett.
  ///
  /// Ein Reittier ist kein Gegenstand, sondern eine Figur für sich:
  /// Ein Strauß, auf dem man reiten soll, muss laufen können, und
  /// dafür braucht er ein Skelett. Ein Fahrzeug ebenso, damit sich
  /// die Räder drehen.
  final String? rigType;

  /// Eigener Größensatz für den Prompt statt des gerechneten.
  ///
  /// Bei einem Reittier sagt „1,5-mal so hoch wie die Figur" nichts
  /// Brauchbares – entscheidend ist, dass der **Rücken auf Hüfthöhe**
  /// sitzt und die Figur daraufpasst.
  final String? scaleClause;

  /// Zusätzliche Wörter für den Negativ-Prompt. Bei Reittieren steht
  /// dort „rider" – sonst kommt das Pferd mit Reiter, und der Reiter
  /// steckt danach im Netz.
  final String extraNegative;

  /// Etwas, auf dem die Figur sitzt oder fährt.
  ///
  /// Nicht dasselbe wie [needsRig]: Ein Ruderboot wird bestiegen,
  /// braucht aber kein Skelett – da bewegt sich nichts. Ein Strauß
  /// braucht eines, sonst kann er nicht laufen.
  final bool rideable;

  /// Braucht ein Skelett (Reittier, Fahrzeug mit Rädern)?
  bool get needsRig => rigType != null;

  /// Ein Lebewesen zum Reiten – dafür ist der Sitz in Roblox ein
  /// `Seat`, bei allem Fahrbaren ein `VehicleSeat` (der bringt die
  /// Steuerung mit).
  bool get animalMount => rigType == 'quadruped' || rigType == 'bird';

  /// Wird in die Hand genommen statt angezogen? Reittiere und
  /// Fahrzeuge sind weder das eine noch das andere.
  bool get handHeld => robloxAccessoryType == null && !rideable;
}

/// Alle Gegenstandsarten.
const itemKinds = <ItemKind>[
  // ---- Waffen und Werkzeug in der Hand -------------------------
  ItemKind(
    id: 'schwert',
    label: 'Schwert',
    group: 'Waffe',
    core: 'one-handed sword with a straight blade, simple crossguard '
        'and wrapped grip, pommel at the end',
    share: 0.55,
    scaleRef: ItemScaleRef.figur,
    carry: 'in der Hand; Klinge etwa halb so lang wie die Figur',
    words: ['ritter', 'knight', 'krieger', 'warrior', 'soldat',
        'schwert', 'sword', 'held', 'hero', 'samurai', 'paladin'],
  ),
  ItemKind(
    id: 'axt',
    label: 'Axt',
    group: 'Waffe',
    core: 'battle axe with a broad curved blade on a straight wooden '
        'haft',
    share: 0.45,
    scaleRef: ItemScaleRef.figur,
    carry: 'in der Hand',
    words: ['axt', 'axe', 'barbar', 'barbarian', 'zwerg', 'dwarf',
        'holzfäller', 'lumberjack', 'wikinger', 'viking'],
  ),
  ItemKind(
    id: 'schild',
    label: 'Schild',
    group: 'Waffe',
    core: 'round shield with a raised rim, a central boss and a broad '
        'painted emblem',
    share: 0.32,
    scaleRef: ItemScaleRef.figur,
    carry: 'am Arm oder auf dem Rücken',
    robloxAccessoryType: 'Back',
    words: ['ritter', 'knight', 'krieger', 'warrior', 'schild',
        'shield', 'wikinger', 'viking', 'wache', 'guard'],
  ),
  ItemKind(
    id: 'bogen',
    label: 'Bogen',
    group: 'Waffe',
    core: 'recurve bow with a thick grip and a taut string',
    share: 0.7,
    scaleRef: ItemScaleRef.figur,
    carry: 'in der Hand oder auf dem Rücken',
    words: ['bogen', 'bow', 'jäger', 'hunter', 'elf', 'ranger',
        'schütze', 'archer'],
  ),
  ItemKind(
    id: 'stab',
    label: 'Zauberstab (lang)',
    group: 'Waffe',
    core: 'long wooden wizard staff, gnarled shaft, a glowing crystal '
        'held in claw-like prongs at the top',
    share: 0.95,
    scaleRef: ItemScaleRef.figur,
    carry: 'in der Hand, etwa so hoch wie die Figur',
    words: ['zauberer', 'wizard', 'magier', 'mage', 'hexe', 'witch',
        'druide', 'druid', 'stab', 'staff', 'zauber', 'magic'],
  ),
  ItemKind(
    id: 'speer',
    label: 'Speer',
    group: 'Waffe',
    core: 'spear with a leaf-shaped metal head on a long straight '
        'shaft, leather binding below the head',
    share: 1.2,
    scaleRef: ItemScaleRef.figur,
    carry: 'in der Hand, länger als die Figur hoch ist',
    words: ['speer', 'spear', 'jäger', 'hunter', 'wache', 'guard',
        'lanze', 'lance'],
  ),
  ItemKind(
    id: 'hammer',
    label: 'Hammer / Werkzeug',
    group: 'Waffe',
    core: 'heavy work hammer with a blocky steel head and a wooden '
        'handle',
    share: 0.35,
    scaleRef: ItemScaleRef.figur,
    carry: 'in der Hand',
    words: ['schmied', 'blacksmith', 'bauarbeiter', 'builder',
        'handwerker', 'hammer', 'zwerg', 'dwarf', 'werkzeug', 'tool'],
  ),

  // ---- Am Körper getragen --------------------------------------
  ItemKind(
    id: 'helm',
    label: 'Helm',
    group: 'Am Körper',
    core: 'closed metal helmet with a narrow eye slit, a raised comb '
        'on top and a rolled rim',
    share: 1.25,
    scaleRef: ItemScaleRef.kopf,
    carry: 'auf dem Kopf – etwas größer als der Kopf, damit er darüber passt',
    robloxAccessoryType: 'Hat',
    words: ['ritter', 'knight', 'krieger', 'warrior', 'soldat',
        'helm', 'helmet', 'wache', 'guard'],
  ),
  ItemKind(
    id: 'hut',
    label: 'Hut',
    group: 'Am Körper',
    core: 'wide-brimmed pointed hat, thick rounded brim, tall '
        'soft-cornered cone, a single band around the base',
    share: 1.8,
    scaleRef: ItemScaleRef.kopf,
    carry: 'auf dem Kopf; die Krempe ragt deutlich über den Kopf hinaus',
    robloxAccessoryType: 'Hat',
    words: ['zauberer', 'wizard', 'hexe', 'witch', 'hut', 'hat',
        'cowboy', 'pirat', 'pirate', 'abenteurer', 'adventurer'],
  ),
  ItemKind(
    id: 'krone',
    label: 'Krone',
    group: 'Am Körper',
    core: 'simple crown, a thick band with broad rounded points and '
        'set gemstones',
    share: 1.1,
    scaleRef: ItemScaleRef.kopf,
    carry: 'auf dem Kopf, knapp über der Stirn',
    robloxAccessoryType: 'Hat',
    words: ['könig', 'king', 'königin', 'queen', 'prinz', 'prince',
        'krone', 'crown', 'herrscher', 'royal'],
  ),
  ItemKind(
    id: 'maske',
    label: 'Maske',
    group: 'Am Körper',
    core: 'face mask covering the front of the head, bold carved '
        'features, flat separated colour areas',
    share: 0.9,
    scaleRef: ItemScaleRef.kopf,
    carry: 'vor dem Gesicht',
    robloxAccessoryType: 'Face',
    words: ['maske', 'mask', 'schamane', 'shaman', 'dieb', 'thief',
        'ninja', 'geist', 'spirit'],
  ),
  ItemKind(
    id: 'rucksack',
    label: 'Rucksack',
    group: 'Am Körper',
    core: 'travel backpack with a rolled bedroll on top, two thick '
        'straps and buckled side pockets',
    share: 0.3,
    scaleRef: ItemScaleRef.figur,
    carry: 'auf dem Rücken',
    robloxAccessoryType: 'Back',
    words: ['abenteurer', 'adventurer', 'reisender', 'traveller',
        'entdecker', 'explorer', 'rucksack', 'backpack', 'wanderer'],
  ),
  ItemKind(
    id: 'umhang',
    label: 'Umhang',
    group: 'Am Körper',
    core: 'short shoulder cape with a thick rolled collar and a '
        'clasp at the throat, hanging in a few broad folds',
    share: 0.4,
    scaleRef: ItemScaleRef.figur,
    carry: 'über den Schultern',
    robloxAccessoryType: 'Shoulder',
    words: ['umhang', 'cape', 'cloak', 'held', 'hero', 'königlich',
        'royal', 'vampir', 'vampire', 'magier', 'mage'],
  ),
  ItemKind(
    id: 'amulett',
    label: 'Amulett',
    group: 'Am Körper',
    core: 'pendant amulet on a chain, a single large faceted stone in '
        'a thick metal setting',
    share: 0.5,
    scaleRef: ItemScaleRef.kopf,
    carry: 'um den Hals',
    robloxAccessoryType: 'Neck',
    words: ['magier', 'mage', 'priester', 'priest', 'amulett',
        'amulet', 'schamane', 'shaman', 'zauber', 'magic'],
  ),
  ItemKind(
    id: 'guerteltasche',
    label: 'Gürteltasche',
    group: 'Am Körper',
    core: 'belt pouch with a flap and a buckle, hanging from a thick '
        'leather belt',
    share: 0.6,
    scaleRef: ItemScaleRef.hand,
    carry: 'am Gürtel',
    robloxAccessoryType: 'Waist',
    words: ['dieb', 'thief', 'händler', 'merchant', 'abenteurer',
        'adventurer', 'tasche', 'pouch', 'schurke', 'rogue'],
  ),

  // ---- Ausrüstung in der Hand ----------------------------------
  ItemKind(
    id: 'laterne',
    label: 'Laterne',
    group: 'Ausrüstung',
    core: 'hand lantern, a glass housing in a metal frame with a ring '
        'handle on top and a warm glow inside',
    share: 1.6,
    scaleRef: ItemScaleRef.hand,
    carry: 'in der Hand am Bügel',
    words: ['bergarbeiter', 'miner', 'wächter', 'watchman', 'nacht',
        'night', 'laterne', 'lantern', 'entdecker', 'explorer'],
  ),
  ItemKind(
    id: 'trank',
    label: 'Trank',
    group: 'Ausrüstung',
    core: 'potion bottle, round body with a narrow neck, a cork '
        'stopper and a small paper label',
    share: 1.1,
    scaleRef: ItemScaleRef.hand,
    carry: 'in der Hand oder am Gürtel',
    words: ['alchemist', 'zauberer', 'wizard', 'heiler', 'healer',
        'trank', 'potion', 'hexe', 'witch', 'apotheker'],
  ),
  ItemKind(
    id: 'buch',
    label: 'Buch',
    group: 'Ausrüstung',
    core: 'thick closed spellbook, worn leather cover with a metal '
        'clasp and a bookmark ribbon',
    share: 1.3,
    scaleRef: ItemScaleRef.hand,
    carry: 'in der Hand',
    words: ['magier', 'mage', 'zauberer', 'wizard', 'gelehrter',
        'scholar', 'buch', 'book', 'bibliothekar', 'schreiber'],
  ),
  ItemKind(
    id: 'schluessel',
    label: 'Schlüssel',
    group: 'Ausrüstung',
    core: 'large ornate key with a round bow, a thick shaft and a '
        'blocky bit',
    share: 0.9,
    scaleRef: ItemScaleRef.hand,
    carry: 'in der Hand oder am Gürtel',
    words: ['wächter', 'keeper', 'kerkermeister', 'jailer',
        'schlüssel', 'key', 'dieb', 'thief'],
  ),

  // ---- Umgebung ------------------------------------------------
  ItemKind(
    id: 'truhe',
    label: 'Truhe',
    group: 'Umgebung',
    core: 'wooden treasure chest with a domed lid, iron bands and a '
        'heavy lock plate',
    share: 0.45,
    scaleRef: ItemScaleRef.figur,
    carry: 'steht auf dem Boden, reicht der Figur etwa bis zur Hüfte',
    words: ['pirat', 'pirate', 'schatz', 'treasure', 'truhe', 'chest',
        'dieb', 'thief', 'händler', 'merchant'],
  ),
  ItemKind(
    id: 'fass',
    label: 'Fass',
    group: 'Umgebung',
    core: 'wooden barrel with broad staves and three iron hoops, flat '
        'top',
    share: 0.5,
    scaleRef: ItemScaleRef.figur,
    carry: 'steht auf dem Boden',
    words: ['wirt', 'innkeeper', 'händler', 'merchant', 'fass',
        'barrel', 'pirat', 'pirate', 'brauer', 'lager'],
  ),
  // ---- Fortbewegung: Reittiere und Fahrzeuge -------------------
  // Diese sind keine Gegenstände, sondern Figuren für sich: Sie
  // brauchen ein Skelett (sonst kann der Strauß nicht laufen und die
  // Räder drehen sich nicht) und einen Sitzplatz statt eines
  // Attachments.
  ItemKind(
    id: 'reitpferd',
    rideable: true,
    label: 'Reitpferd',
    group: 'Fortbewegung',
    core: 'saddled riding horse standing on all four legs, sturdy '
        'body, a saddle with stirrups on its back, reins on the head, '
        'no rider',
    share: 1.5,
    scaleRef: ItemScaleRef.figur,
    scaleClause: "large enough for the character to ride: the back "
        "with the saddle at about hip height of the character, the "
        "body about one and a half times the character's height long",
    carry: 'zum Aufsitzen – Sattel etwa auf Hüfthöhe der Figur',
    rigType: 'quadruped',
    extraNegative: 'rider, person on top, saddled person, human',
    words: ['ritter', 'knight', 'reiter', 'rider', 'pferd', 'horse',
        'cowboy', 'nomade', 'bote', 'messenger'],
  ),
  ItemKind(
    id: 'reitvogel',
    rideable: true,
    label: 'Reitvogel (Strauß)',
    group: 'Fortbewegung',
    core: 'large flightless riding bird like an ostrich, long strong '
        'legs, round feathered body, small head on a long neck, a '
        'saddle strapped to its back, no rider',
    share: 1.4,
    scaleRef: ItemScaleRef.figur,
    scaleClause: "large enough for the character to ride: the saddle "
        "on its back at about hip height of the character",
    carry: 'zum Aufsitzen – braucht ein Vogel-Skelett (zwei Beine)',
    rigType: 'bird',
    extraNegative: 'rider, person on top, human, flying, wings spread '
        'wide',
    words: ['reiten', 'ride', 'wüste', 'desert', 'strauß', 'ostrich',
        'vogel', 'bird', 'abenteurer', 'adventurer', 'bote'],
  ),
  ItemKind(
    id: 'reitechse',
    rideable: true,
    label: 'Reitechse',
    group: 'Fortbewegung',
    core: 'large riding lizard on four legs, broad scaly back with a '
        'saddle, thick tail, no rider',
    share: 1.6,
    scaleRef: ItemScaleRef.figur,
    scaleClause: "large enough for the character to ride: the saddled "
        "back at about hip height of the character",
    carry: 'zum Aufsitzen',
    rigType: 'quadruped',
    extraNegative: 'rider, person on top, human',
    words: ['echse', 'lizard', 'drache', 'dragon', 'ork', 'orc',
        'dschungel', 'jungle', 'reiten', 'ride'],
  ),
  ItemKind(
    id: 'karren',
    rideable: true,
    label: 'Karren / Kutsche',
    group: 'Fortbewegung',
    core: 'wooden cart with two large spoked wheels, an open loading '
        'bed and two draft poles at the front',
    share: 1.8,
    scaleRef: ItemScaleRef.figur,
    carry: 'zum Ziehen oder Fahren – Räder als eigene runde Volumen',
    rigType: 'vehicle',
    extraNegative: 'rider, person, horse, animal',
    words: ['händler', 'merchant', 'bauer', 'farmer', 'karren',
        'cart', 'kutsche', 'wagen', 'wagon', 'markt'],
  ),
  ItemKind(
    id: 'auto',
    rideable: true,
    label: 'Fahrzeug (4 Räder)',
    group: 'Fortbewegung',
    core: 'small blocky vehicle with four round wheels, an open '
        'driver seat, a simple steering wheel and a short hood',
    share: 2.0,
    scaleRef: ItemScaleRef.figur,
    carry: 'zum Einsteigen – der Sitz etwa auf Kniehöhe der Figur',
    rigType: 'vehicle',
    extraNegative: 'driver, person, passenger',
    words: ['fahrer', 'driver', 'auto', 'car', 'rennfahrer', 'racer',
        'mechaniker', 'mechanic', 'stadt', 'city'],
  ),
  ItemKind(
    id: 'boot',
    rideable: true,
    label: 'Boot',
    group: 'Fortbewegung',
    core: 'small wooden rowing boat with a raised bow, plank benches '
        'and two oarlocks',
    share: 2.2,
    scaleRef: ItemScaleRef.figur,
    scaleClause: "large enough for the character to sit inside: about "
        "twice the character's height long",
    carry: 'zum Einsteigen – ohne Skelett, ein starres Teil',
    extraNegative: 'rower, person, passenger, water, waves',
    words: ['fischer', 'fisher', 'pirat', 'pirate', 'boot', 'boat',
        'see', 'lake', 'segler', 'sailor', 'insel', 'island'],
  ),
  ItemKind(
    id: 'gleiter',
    rideable: true,
    label: 'Gleiter / Flugzeug',
    group: 'Fortbewegung',
    core: 'small single-seat glider aircraft with broad straight '
        'wings, an open cockpit and a tail fin',
    share: 2.4,
    scaleRef: ItemScaleRef.figur,
    scaleClause: "large enough for the character to sit in: wingspan "
        "about two and a half times the character's height",
    carry: 'zum Einsteigen – Flügel als eigene Volumen',
    extraNegative: 'pilot, person, sky, clouds',
    words: ['pilot', 'flieger', 'flugzeug', 'plane', 'gleiter',
        'glider', 'erfinder', 'inventor', 'himmel', 'sky'],
  ),

  ItemKind(
    id: 'fahne',
    label: 'Banner',
    group: 'Umgebung',
    core: 'banner on a pole, rectangular cloth with a broad emblem '
        'and a weighted hem',
    share: 1.3,
    scaleRef: ItemScaleRef.figur,
    carry: 'in der Hand oder im Boden steckend',
    words: ['ritter', 'knight', 'armee', 'army', 'fahne', 'banner',
        'flagge', 'flag', 'herold', 'wache', 'guard'],
  ),
];

/// Eine Art nach Kennung.
ItemKind? itemKindById(String id) {
  for (final kind in itemKinds) {
    if (kind.id == id) return kind;
  }
  return null;
}

/// Gruppen in der Reihenfolge, in der sie in der Auswahl stehen.
List<String> get itemGroups {
  final out = <String>[];
  for (final kind in itemKinds) {
    if (!out.contains(kind.group)) out.add(kind.group);
  }
  return out;
}

/// Schlägt Gegenstände vor, die zur Figurbeschreibung passen.
///
/// Gezählt werden Treffer der Stichwörter; bestes zuerst. Findet sich
/// nichts (ein Tier, ein Fantasiewesen ohne Rolle), kommt eine
/// allgemein brauchbare Grundausstattung zurück – besser als eine
/// leere Liste, weil die Auswahl sonst wie kaputt aussieht.
List<ItemKind> suggestedItems(String figurePrompt, {int limit = 6}) {
  final text = figurePrompt.toLowerCase();
  final scored = <(ItemKind, int)>[];
  for (final kind in itemKinds) {
    var hits = 0;
    for (final word in kind.words) {
      if (text.contains(word)) hits++;
    }
    if (hits > 0) scored.add((kind, hits));
  }
  if (scored.isEmpty) {
    return [
      for (final id in ['schwert', 'schild', 'helm', 'rucksack'])
        itemKindById(id)!,
    ];
  }
  // Bei Gleichstand die Reihenfolge der Liste behalten, damit die
  // Vorschläge nicht bei jedem Aufruf springen.
  final order = {for (var i = 0; i < itemKinds.length; i++) itemKinds[i].id: i};
  scored.sort((a, b) {
    final byHits = b.$2.compareTo(a.$2);
    return byHits != 0 ? byHits : order[a.$1.id]!.compareTo(order[b.$1.id]!);
  });
  return [for (final entry in scored.take(limit)) entry.$1];
}

String _n(double value) {
  final rounded = (value * 100).round() / 100;
  var text = rounded.toStringAsFixed(2);
  if (text.endsWith('0')) text = text.substring(0, text.length - 1);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return text.replaceAll('.', ',');
}

/// Die absolute Größe eines Gegenstands bei einer Figur von
/// [figureHeight] Einheiten (bei Roblox: Studs).
double itemSize(ItemKind kind, double figureHeight) => switch (kind.scaleRef) {
      ItemScaleRef.figur => figureHeight * kind.share,
      ItemScaleRef.kopf => figureHeight * headShareOfFigure * kind.share,
      ItemScaleRef.hand => figureHeight * handShareOfFigure * kind.share,
    };

/// Der Maßstab-Satz für die Oberfläche, z. B. „etwa 2,8 Studs lang –
/// 0,55 × Figurenhöhe".
String itemScaleNote(ItemKind kind, double figureHeight,
    {String unit = 'Studs'}) {
  final size = itemSize(kind, figureHeight);
  final bezug = switch (kind.scaleRef) {
    ItemScaleRef.figur => 'Figurenhöhe',
    ItemScaleRef.kopf => 'Kopfhöhe',
    ItemScaleRef.hand => 'Handlänge',
  };
  return 'etwa ${_n(size)} $unit – ${_n(kind.share)} × $bezug';
}

/// Derselbe Maßstab als englischer Satz für den Prompt.
///
/// Ein Bildmodell kennt keinen Maßstab und keine Studs; es versteht
/// aber Verhältnisse („about half the character's height"). Deshalb
/// steht hier das Verhältnis, nicht die Zahl in Studs.
String itemScaleClause(ItemKind kind) {
  final share = kind.share;
  final bezug = switch (kind.scaleRef) {
    ItemScaleRef.figur => "the character's full height",
    ItemScaleRef.kopf => "the character's head",
    ItemScaleRef.hand => "the character's hand",
  };
  if (share >= 0.9 && share < 1.15) {
    return 'sized about as large as $bezug';
  }
  if (share >= 1.15) {
    return 'sized about ${share.toStringAsFixed(1)} times $bezug';
  }
  return 'sized about ${_englishFraction(share)} of $bezug';
}

/// Der Größensatz, der wirklich in den Prompt geht: der eigene, wenn
/// die Art einen hat, sonst der gerechnete.
String itemScaleSentence(ItemKind kind) =>
    kind.scaleClause ?? itemScaleClause(kind);

String _englishFraction(double share) {
  if (share >= 1.15) return share.toStringAsFixed(1);
  if ((share - 0.5).abs() < 0.06) return 'half';
  if ((share - 0.33).abs() < 0.05) return 'a third';
  if ((share - 0.25).abs() < 0.05) return 'a quarter';
  return '${(share * 100).round()} percent';
}

/// Der feste Schwanz für einen Gegenstand außerhalb von Roblox –
/// dieselben vier Angaben, die auch eine Figur brauchbar machen:
/// ein zusammenhängendes Volumen, sichtbare Wandstärke, geschlossene
/// Hülle, ein Netz.
const String itemTail =
    'single solid object shown alone, centered, thick rounded shapes '
    'with visible wall thickness, closed watertight shell, single '
    'mesh, clean readable silhouette, even neutral lighting, plain '
    'flat background';

/// Die NEGATIV-Zeile für einen Gegenstand. „character", „hand" und
/// „person" stehen ganz vorn: Der häufigste Fehlschlag ist, dass das
/// Bildmodell die Figur gleich mitmalt, weil sie im Referenzbild
/// steht – und das 3D-Modell dann Schwert **samt Hand** enthält.
const String itemNegative =
    'character, person, hand, arm, mannequin, second object, set of '
    'objects, base, pedestal, stand, thin parts, open mesh, holes, '
    'floating parts, text, logo, watermark, cluttered background, '
    'blurry, low quality';

/// Kürzt die Figurbeschreibung auf den Teil, der den Stil trägt.
///
/// Der volle Figur-Prompt kann mehrere hundert Zeichen haben; hinten
/// stehen meist die Bau-Anweisungen („single connected body,
/// watertight …"), die für einen Gegenstand nichts beitragen und den
/// Prompt nur verdünnen. Genommen wird deshalb der Anfang bis
/// [maxChars], an einer Kommagrenze abgeschnitten.
String figureStyleHint(String figurePrompt, {int maxChars = 180}) {
  var text = figurePrompt.trim();
  // Eine „PROMPT:"-Zeile aus der Vorlage enthält den eigentlichen Text.
  final marker = RegExp(r'^PROMPT:\s*', caseSensitive: false);
  final firstLine = text.split('\n').first;
  if (marker.hasMatch(firstLine)) text = firstLine.replaceFirst(marker, '');
  text = text.trim();
  if (text.length <= maxChars) return text;
  final cut = text.substring(0, maxChars);
  final comma = cut.lastIndexOf(',');
  return (comma > maxChars ~/ 2 ? cut.substring(0, comma) : cut).trim();
}

/// Baut den Prompt für einen Gegenstand, der zu einer Figur passt.
///
/// [withReference] sagt, ob ein gerendertes Bild der Figur als
/// Referenz mitgeht. Dann verweist der Prompt auf das Bild statt die
/// Figur zu beschreiben – das trifft den Stil deutlich besser, weil
/// Farben und Formensprache direkt zu sehen sind. Ohne Referenz
/// wandert die gekürzte Figurbeschreibung in den Text.
///
/// [roblox] hängt statt des allgemeinen Schwanzes die Roblox-Regeln
/// an, die die Plattformprüfung verlangt.
(String, String) itemPromptParts({
  required ItemKind kind,
  required String figurePrompt,
  bool roblox = false,
  bool withReference = false,
  String accessoryTail = '',
  String accessoryNegative = '',
}) {
  final tail = roblox && accessoryTail.isNotEmpty ? accessoryTail : itemTail;
  final negative =
      roblox && accessoryNegative.isNotEmpty ? accessoryNegative : itemNegative;
  final stil = withReference
      // „no character in the image" doppelt zum Negativ-Prompt: Bei
      // einem Referenzbild mit Figur ist der Zug, sie mitzumalen, am
      // stärksten – ein Modell, das den Negativ-Prompt gar nicht
      // auswertet (SDXL Turbo, FLUX), hört sonst nichts davon.
      ? 'in exactly the same art style, colour palette and level of '
          'detail as the reference image, but showing only the object '
          'itself, no character in the image'
      : 'in the same art style and colour palette as this character: '
          '${figureStyleHint(figurePrompt)}';
  final full = kind.extraNegative.isEmpty
      ? negative
      : '${kind.extraNegative}, $negative';
  return (
    '${kind.core}, ${itemScaleSentence(kind)}, $stil, $tail',
    full,
  );
}

/// Derselbe Prompt im Format der kopierbaren Vorlagen
/// (`PROMPT:` / `NEGATIV:`) – für den Massenprompt und zum Weitergeben
/// an eine Prompt-KI.
String itemPrompt({
  required ItemKind kind,
  required String figurePrompt,
  bool roblox = false,
  bool withReference = false,
  String accessoryTail = '',
  String accessoryNegative = '',
}) {
  final (prompt, negative) = itemPromptParts(
    kind: kind,
    figurePrompt: figurePrompt,
    roblox: roblox,
    withReference: withReference,
    accessoryTail: accessoryTail,
    accessoryNegative: accessoryNegative,
  );
  return 'PROMPT: $prompt\nNEGATIV: $negative';
}

/// Alle gewählten Gegenstände als ein Block – eine Zeile je
/// Gegenstand im Format des Massenprompts (`Name: Beschreibung`), so
/// dass sich daraus in einem Lauf alle Bilder erzeugen lassen.
String itemBatchPrompt({
  required List<ItemKind> kinds,
  required String figurePrompt,
  required String figureName,
  bool roblox = false,
  bool withReference = false,
  String accessoryTail = '',
  String accessoryNegative = '',
}) {
  final base = figureName.trim().isEmpty
      ? 'item'
      : figureName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final blocks = <String>[];
  for (final kind in kinds) {
    final prompt = itemPrompt(
      kind: kind,
      figurePrompt: figurePrompt,
      roblox: roblox,
      withReference: withReference,
      accessoryTail: accessoryTail,
      accessoryNegative: accessoryNegative,
    );
    blocks.add('NAME: $base-${kind.id}\n$prompt');
  }
  return blocks.join('\n\n');
}

/// Wie der Gegenstand in Roblox an die Figur kommt – ein Satz für die
/// Oberfläche und die Beilage zum Export.
///
/// Die Werte stammen aus der offiziellen Aufzählung `AccessoryType`
/// (Hat, Hair, Face, Neck, Shoulder, Front, Back, Waist …). Was dort
/// nicht hineinpasst, ist kein Accessoire, sondern ein Werkzeug:
/// ein `Tool` mit einem Teil namens `Handle`, das die Figur in die
/// Hand nimmt.
String robloxAttachNote(ItemKind kind) {
  if (kind.rideable) {
    // Ein Reittier oder Fahrzeug ist kein Accessoire: Es wird nicht
    // angezogen, sondern bestiegen. In Roblox ist das ein Modell mit
    // einem Sitz – `VehicleSeat` für Fahrbares (er bringt die
    // Steuerung mit), `Seat` für ein Reittier, dessen Bewegung ein
    // Skript macht.
    final sitz = kind.animalMount ? 'Seat' : 'VehicleSeat';
    final skelett = kind.needsRig
        ? ' Das Skelett (${kind.rigType}) steckt schon im Modell – '
            'darüber laufen Lauf- bzw. Radanimation.'
        : ' Ein starres Teil – hier bewegt sich nichts.';
    return 'Kein Accessoire: als eigenes Modell anlegen und einen '
        '`$sitz` an der Sitzposition einschweißen.$skelett';
  }
  final type = kind.robloxAccessoryType;
  if (type == null) {
    return 'In die Hand: als `Tool` mit einem Teil namens `Handle` '
        'anlegen und das Mesh dort einsetzen – kein Accessoire.';
  }
  return 'Als Accessoire anlegen, `AccessoryType` = `$type` '
      '(${kind.carry}).';
}
