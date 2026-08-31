/// Gegenstände so ausliefern, dass Roblox sie erkennt.
///
/// Ein Mesh allein ist in Roblox kein Hut und kein Schwert. Es braucht
/// die richtige Hülle drumherum:
///
/// * Ein **getragener** Gegenstand wird ein `Accessory` mit einem Teil
///   namens `Handle` und **einem `Attachment` darin, dessen Name zur
///   `AccessoryType` passt** – `HatAttachment` beim Hut,
///   `BodyBackAttachment` beim Rucksack. Stimmt der Name nicht, sitzt
///   das Teil beim Anziehen irgendwo, meist im Boden.
/// * Ein **gehaltener** Gegenstand wird ein `Tool`, ebenfalls mit
///   einem Teil namens `Handle`. Ohne genau diesen Namen nimmt die
///   Figur das Werkzeug gar nicht erst in die Hand.
///
/// Dazu kommen Größengrenzen je Art. Die Zahlen unten stammen aus der
/// offiziellen Spezifikation für starre Accessoires (Body Scale
/// `Normal`, Mannequin rund 5,75–6,5 Studs hoch) und sind der Grund,
/// warum ein zu großer Hut beim Hochladen abgelehnt wird – nicht ein
/// Fehler im Modell.
library;

import 'dart:typed_data';

import 'item_prompt.dart';
import 'roblox_check.dart'
    show readRobloxFacts, robloxAccessoryTriangles;

/// Größte zulässige Ausdehnung eines starren Accessoires in Studs,
/// gemessen an der Ausrichtung des Attachments.
class AccessoryLimit {
  const AccessoryLimit(this.width, this.height, this.depth, {this.note = ''});

  /// x, y, z in Studs.
  final double width, height, depth;

  /// Besonderheit, etwa dass der Bereich nicht mittig liegt.
  final String note;
}

/// Die Grenzen je `AccessoryType` für den Body Scale `Normal`.
///
/// Quelle: die offizielle Spezifikation für starre Accessoires. Für
/// `Slender` und `Classic` gelten kleinere bzw. andere Werte; wer
/// darunter bleibt, ist überall auf der sicheren Seite – deshalb
/// prüft diese App gegen `Normal` und sagt dazu, worauf sich das
/// bezieht.
const robloxAccessoryLimits = <String, AccessoryLimit>{
  'Hat': AccessoryLimit(1.87, 2.5, 1.87),
  'Hair': AccessoryLimit(1.87, 3.12, 2.18,
      note: 'nicht mittig: 1,25 nach oben, 1,875 nach unten'),
  'Face': AccessoryLimit(1.87, 1.25, 1.25),
  'Neck': AccessoryLimit(2.95, 3.68, 2.16),
  'Shoulder': AccessoryLimit(2.67, 4.40, 3.09,
      note: 'gilt für RightShoulderAttachment/LeftShoulderAttachment; '
          'am NeckAttachment sind 6,90 Breite erlaubt'),
  'Front': AccessoryLimit(2.95, 3.68, 3.24),
  'Back': AccessoryLimit(9.86, 8.59, 4.87,
      note: 'nicht mittig: 1,623 nach vorn, 3,246 nach hinten'),
  'Waist': AccessoryLimit(3.94, 4.29, 7.57,
      note: 'nicht mittig: 1,842 nach oben, 2,457 nach unten'),
};

/// Wie das `Attachment` im `Handle` heißen muss – je `AccessoryType`.
///
/// Mehrere Namen bedeuten: Alle sind zulässig, der erste ist die
/// naheliegende Wahl. Die Namen stammen aus der offiziellen Tabelle;
/// ein selbst ausgedachter Name führt dazu, dass das Accessoire beim
/// Anziehen nicht sitzt.
const robloxAttachmentNames = <String, List<String>>{
  'Hat': ['HatAttachment'],
  'Hair': ['HairAttachment'],
  'Face': ['FaceFrontAttachment', 'FaceCenterAttachment'],
  'Neck': ['NeckAttachment'],
  'Shoulder': [
    'RightShoulderAttachment',
    'LeftShoulderAttachment',
    'RightCollarAttachment',
    'LeftCollarAttachment',
    'NeckAttachment',
  ],
  'Front': ['BodyFrontAttachment'],
  'Back': ['BodyBackAttachment'],
  'Waist': [
    'WaistCenterAttachment',
    'WaistFrontAttachment',
    'WaistBackAttachment',
  ],
};

/// Der Attachment-Name, den diese App vorschlägt.
String? robloxAttachmentFor(String? accessoryType) {
  if (accessoryType == null) return null;
  final names = robloxAttachmentNames[accessoryType];
  return names == null || names.isEmpty ? null : names.first;
}

String _n(double value) =>
    value.toStringAsFixed(2).replaceAll('.', ',');

/// Was die Größenprüfung eines Gegenstands ergeben hat.
class AccessoryFit {
  const AccessoryFit({
    required this.accessoryType,
    required this.width,
    required this.height,
    required this.depth,
    required this.limit,
    required this.exceeded,
  });

  /// Null = kein Accessoire, sondern ein Werkzeug in der Hand. Für
  /// die gibt es keine Größentabelle; da entscheidet, ob es zur Figur
  /// passt.
  final String? accessoryType;

  /// Gemessene Ausdehnung des Netzes in Studs.
  final double width, height, depth;

  final AccessoryLimit? limit;

  /// Achsen, die über der Grenze liegen ('Breite', 'Höhe', 'Tiefe').
  final List<String> exceeded;

  bool get ok => exceeded.isEmpty;

  /// Faktor, mit dem das Modell schrumpfen müsste, damit es passt.
  /// 1,0 = passt bereits.
  double get shrinkTo {
    final l = limit;
    if (l == null) return 1;
    var factor = 1.0;
    for (final (mass, grenze) in [
      (width, l.width),
      (height, l.height),
      (depth, l.depth),
    ]) {
      if (mass > grenze && grenze > 0) {
        final needed = grenze / mass;
        if (needed < factor) factor = needed;
      }
    }
    return factor;
  }

  /// Ein Satz für die Oberfläche.
  String get text {
    final l = limit;
    if (l == null) {
      return 'In die Hand: ${_n(width)} × ${_n(height)} × ${_n(depth)} '
          'Studs. Für Werkzeuge gibt es keine Größentabelle – hier '
          'zählt, dass es zur Figur passt.';
    }
    final gemessen =
        '${_n(width)} × ${_n(height)} × ${_n(depth)} Studs';
    final erlaubt =
        '${_n(l.width)} × ${_n(l.height)} × ${_n(l.depth)}';
    if (ok) {
      return '$accessoryType: $gemessen – erlaubt sind $erlaubt. Passt.'
          '${l.note.isEmpty ? '' : ' (${l.note})'}';
    }
    return '$accessoryType: $gemessen – erlaubt sind $erlaubt. Zu groß '
        'in ${exceeded.join(' und ')}. Auf '
        '${(shrinkTo * 100).round()} % verkleinern, dann passt es.'
        '${l.note.isEmpty ? '' : ' (${l.note})'}';
  }
}

/// Vergleicht die gemessene Größe eines Gegenstands mit der Grenze
/// seiner Art.
///
/// [size] ist die Ausdehnung in Modelleinheiten (x, y, z) – so, wie
/// sie [readRobloxFacts] liefert. [studsPerUnit] rechnet in Studs um;
/// der Roblox-Importer setzt eine Einheit gleich einem Stud, deshalb
/// ist 1,0 die Vorgabe.
AccessoryFit accessoryFitFromSize(List<double> size, ItemKind kind,
    {double studsPerUnit = 1.0}) {
  final width = (size.isNotEmpty ? size[0] : 0.0) * studsPerUnit;
  final height = (size.length > 1 ? size[1] : 0.0) * studsPerUnit;
  final depth = (size.length > 2 ? size[2] : 0.0) * studsPerUnit;
  final type = kind.robloxAccessoryType;
  final limit = type == null ? null : robloxAccessoryLimits[type];
  final exceeded = <String>[];
  if (limit != null) {
    if (width > limit.width) exceeded.add('Breite');
    if (height > limit.height) exceeded.add('Höhe');
    if (depth > limit.depth) exceeded.add('Tiefe');
  }
  return AccessoryFit(
    accessoryType: type,
    width: width,
    height: height,
    depth: depth,
    limit: limit,
    exceeded: exceeded,
  );
}

/// Dasselbe direkt aus einer GLB.
Future<AccessoryFit> checkAccessoryFit(Uint8List glb, ItemKind kind,
    {double studsPerUnit = 1.0}) async {
  final facts = await readRobloxFacts(glb);
  return accessoryFitFromSize(facts.size, kind,
      studsPerUnit: studsPerUnit);
}

/// Die Länge, ab der eine Bezeichnung kein Name mehr ist, sondern
/// eine Beschreibung.
const robloxMaxNameLength = 40;

/// Ein Name, mit dem Roblox etwas anfangen kann.
///
/// Die Bezeichnung eines Ergebnisses ist in dieser App der Prompt. Bei
/// einem Gegenstand sind das mehrere hundert Zeichen mit Kommas und
/// Anführungszeichen („one-handed sword with a straight blade, simple
/// crossguard …"). Ungeprüft landete das als `Tool.Name` im Rucksack
/// der Figur – und das Anführungszeichen darin beendete die
/// Lua-Zeichenkette mittendrin, das Skript ließ sich gar nicht mehr
/// ausführen.
///
/// Deshalb: Zeilenumbrüche und Steuerzeichen zu Leerzeichen,
/// Anführungszeichen und Backslashes raus, und alles, was nach einer
/// Aufzählung aussieht (ein Komma) oder länger als
/// [robloxMaxNameLength] ist, gilt als Beschreibung – dann greift
/// [fallback], in der Regel die Art des Gegenstands.
String robloxInstanceName(String raw, {required String fallback}) {
  final name = _flacherName(raw);
  final istBeschreibung =
      name.contains(',') || name.length > robloxMaxNameLength;
  if (name.isEmpty || istBeschreibung) {
    final ersatz = _flacherName(fallback);
    return ersatz.isEmpty ? 'Gegenstand' : ersatz;
  }
  return name;
}

/// Eine Zeile ohne Umbrüche, ohne Anführungszeichen, ohne Backslash –
/// damit lässt sie sich gefahrlos in eine Lua-Zeichenkette setzen.
String _flacherName(String raw) => raw
    .replaceAll(RegExp(r'[\x00-\x1f]'), ' ')
    .replaceAll(RegExp(r'["\\]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Lua-Skript, das aus einem importierten Mesh die richtige Hülle
/// baut – in Studio in die Befehlszeile einfügen und ausführen.
///
/// Warum überhaupt ein Skript: Der 3D-Importer legt eine `MeshPart` in
/// den Arbeitsbereich, mehr nicht. Ein Hut wird daraus erst, wenn ein
/// `Accessory` darum steht, das Teil `Handle` heißt und darin ein
/// `Attachment` mit dem passenden Namen sitzt. Von Hand sind das sechs
/// Schritte, bei denen jeder Tippfehler im Namen dazu führt, dass das
/// Teil beim Anziehen im Boden landet – ohne Fehlermeldung.
String robloxItemLua(ItemKind kind, {String meshName = ''}) {
  final name = robloxInstanceName(meshName, fallback: kind.label);
  final attachment = robloxAttachmentFor(kind.robloxAccessoryType);
  final kopf = '-- 3DGenerator: "${kind.label}" in Roblox anlegen\n'
      '-- Das importierte Mesh (MeshPart) im Arbeitsbereich auswaehlen\n'
      '-- und dieses Skript in der Befehlszeile ausfuehren.\n'
      'local Selection = game:GetService("Selection")\n'
      'local teil = Selection:Get()[1]\n'
      'if not teil or not teil:IsA("BasePart") then\n'
      '\twarn("Bitte zuerst das importierte Mesh auswaehlen.")\n'
      '\treturn\n'
      'end\n';

  if (kind.rideable) {
    final sitz = kind.animalMount ? 'Seat' : 'VehicleSeat';
    final wohin = kind.animalMount ? 'den Sattel' : 'den Sitzplatz';
    return '$kopf\n'
        '-- Kein Accessoire: Dieses Teil wird bestiegen, nicht angezogen.\n'
        'local modell = Instance.new("Model")\n'
        'modell.Name = "$name"\n'
        'modell.Parent = teil.Parent\n'
        'teil.Parent = modell\n'
        'modell.PrimaryPart = teil\n'
        '\n'
        'local sitz = Instance.new("$sitz")\n'
        'sitz.Name = "Sitz"\n'
        'sitz.Size = Vector3.new(2, 0.4, 2)\n'
        '-- Sitzflaeche auf die Oberseite legen; danach in Studio genau\n'
        '-- an $wohin schieben.\n'
        'sitz.CFrame = teil.CFrame * CFrame.new(0, teil.Size.Y / 2, 0)\n'
        'sitz.Parent = modell\n'
        '\n'
        'local schweissen = Instance.new("WeldConstraint")\n'
        'schweissen.Part0 = teil\n'
        'schweissen.Part1 = sitz\n'
        'schweissen.Parent = sitz\n'
        '\n'
        'print("Fertig: $name mit einem $sitz. Den Sitz noch genau auf "\n'
        '\t.. "$wohin schieben.")\n';
  }

  if (attachment == null) {
    return '$kopf\n'
        '-- In die Hand: ein Tool mit einem Teil namens "Handle".\n'
        '-- Der Name ist Pflicht - ohne ihn nimmt die Figur nichts in\n'
        '-- die Hand.\n'
        'local werkzeug = Instance.new("Tool")\n'
        'werkzeug.Name = "$name"\n'
        'werkzeug.RequiresHandle = true\n'
        'werkzeug.CanBeDropped = true\n'
        '\n'
        'teil.Name = "Handle"\n'
        'teil.Anchored = false\n'
        'teil.CanCollide = false\n'
        'teil.Massless = true\n'
        'teil.Parent = werkzeug\n'
        'werkzeug.Parent = game.StarterPack\n'
        '\n'
        'print("Fertig: Tool \\"$name\\" liegt in StarterPack. Griff "\n'
        '\t.. "bei Bedarf ueber werkzeug.Grip nachjustieren.")\n';
  }

  return '$kopf\n'
      '-- Getragen: ein Accessory mit einem Teil namens "Handle" und\n'
      '-- darin einem Attachment, dessen Name zur AccessoryType passt.\n'
      'local zubehoer = Instance.new("Accessory")\n'
      'zubehoer.Name = "$name"\n'
      'zubehoer.AccessoryType = Enum.AccessoryType.'
      '${kind.robloxAccessoryType}\n'
      '\n'
      'teil.Name = "Handle"\n'
      'teil.Anchored = false\n'
      'teil.CanCollide = false\n'
      'teil.Massless = true\n'
      'teil.Parent = zubehoer\n'
      '\n'
      '-- Der Name des Attachments entscheidet, wo das Teil sitzt. Er\n'
      '-- muss genau so heissen wie der Punkt am Koerper.\n'
      'local punkt = Instance.new("Attachment")\n'
      'punkt.Name = "$attachment"\n'
      'punkt.Parent = teil\n'
      '\n'
      'zubehoer.Parent = game.Workspace\n'
      '\n'
      'print("Fertig: Accessory \\"$name\\" '
      '(${kind.robloxAccessoryType}) mit "\n'
      '\t.. "$attachment. Lage im Accessory Fitting Tool feinjustieren.")\n';
}

/// Die Beilage zum Export: was das Skript tut und worauf zu achten ist.
String robloxItemReadme(ItemKind kind, {AccessoryFit? fit}) {
  final attachment = robloxAttachmentFor(kind.robloxAccessoryType);
  final zeilen = <String>[
    '# ${kind.label} in Roblox',
    '',
    robloxAttachNote(kind),
    '',
    '## Schritte',
    '',
    '1. GLB in Studio importieren (3D-Importer). Es entsteht eine '
        'MeshPart im Arbeitsbereich.',
    '2. Die MeshPart auswählen.',
    '3. Das beiliegende Lua-Skript in die Befehlszeile einfügen und '
        'ausführen.',
  ];
  if (attachment != null) {
    zeilen.addAll([
      '4. Lage und Drehung mit dem **Accessory Fitting Tool** '
          'feinjustieren.',
      '',
      '## Der Name entscheidet',
      '',
      'Das `Attachment` im `Handle` muss `$attachment` heißen. Ein '
          'anderer Name führt zu keiner Fehlermeldung – das Teil sitzt '
          'beim Anziehen einfach irgendwo, meist im Boden. Erlaubt sind '
          'für `${kind.robloxAccessoryType}`: '
          '${robloxAttachmentNames[kind.robloxAccessoryType]!.join(', ')}.',
    ]);
  } else if (kind.rideable) {
    zeilen.addAll([
      '4. Den Sitz genau an die Sitzposition schieben '
          '(${kind.animalMount ? 'Sattel' : 'Sitzplatz'}).',
      '',
      '## Kein Accessoire',
      '',
      'Etwas, das bestiegen wird, ist in Roblox kein Accessoire, '
          'sondern ein Modell mit einem Sitz.'
          '${kind.needsRig ? ' Das Skelett steckt bereits im Modell – '
              'darüber läuft die Bewegung.' : ''}',
    ]);
  } else {
    zeilen.addAll([
      '4. Den Griff über `Tool.Grip` nachjustieren, falls der '
          'Gegenstand schief in der Hand liegt.',
      '',
      '## Der Name entscheidet',
      '',
      'Das Teil im `Tool` muss `Handle` heißen. Ohne genau diesen '
          'Namen nimmt die Figur das Werkzeug gar nicht erst in die '
          'Hand.',
    ]);
  }
  if (fit != null) {
    zeilen.addAll(['', '## Größe', '', fit.text]);
  }
  zeilen.addAll([
    '',
    '## Grenzen',
    '',
    '- Starre Accessoires: höchstens $robloxAccessoryTriangles Dreiecke, '
        'ein Mesh, geschlossene Hülle.',
    '- Die Größenangaben gelten für den Body Scale `Normal`. Für '
        '`Slender` und `Classic` sind die Grenzen kleiner – wer darunter '
        'bleibt, ist überall auf der sicheren Seite.',
  ]);
  return zeilen.join('\n');
}
