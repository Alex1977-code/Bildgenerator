/// Roblox-Prüfung: Hält ein erzeugtes Modell die Regeln des
/// Roblox-Importers ein?
///
/// Roblox Studio weist Modelle hart zurück, die über 20.000 Dreiecke
/// je Mesh liegen, mehr als ein Material tragen, größere Texturen als
/// 1024×1024 mitbringen oder deren Skelett nicht der Konvention folgt
/// (Bones ohne Skalierung und Rotation, Wurzel im Ursprung, höchstens
/// vier Einflüsse je Vertex). KI-Modelle aus Meshy, Tripo & Co.
/// starten oft bei mehreren hunderttausend Dreiecken – deshalb
/// scheitert der Import zuverlässig, wenn niemand vorher nachsieht.
///
/// Diese Datei trennt zwei Dinge: [readRobloxFacts] liest die Zahlen
/// aus einer GLB-Datei, [checkRobloxFacts] beurteilt sie. Die
/// Beurteilung ist damit ohne Datei und ohne Flutter-Bindings prüfbar.
library;

import 'dart:typed_data';

import 'glb_preview.dart';
import 'mesh_check.dart';
import 'roblox_rig.dart';
import 'roblox_face_parts.dart' show faceMeshNames;
import 'roblox_spec.dart';

/// Wofür das Modell gedacht ist – davon hängt die Dreiecksgrenze ab.
enum RobloxTarget {
  /// Figur oder Prop im Erlebnis: hart 20.000 Dreiecke je Mesh,
  /// Arbeitsziel unter 10.000.
  character,

  /// UGC-Accessoire (Hut, Rucksack, Haare …): hart 4.000 Dreiecke.
  accessory,

  /// Marktplatz-Avatar über Roblox' Auto Setup.
  ///
  /// Ein eigenes Ziel, weil hier drei Dinge **anders** gelten als im
  /// eigenen Erlebnis: Es soll **kein** Skelett in der Datei sein
  /// (Auto Setup baut sein eigenes und verwirft ein mitgebrachtes),
  /// das Budget wird je Körpergruppe gerechnet statt je Mesh, und ein
  /// erkennbarer Hals ist Pflicht, weil Auto Setup sonst die Grenze
  /// zwischen Kopf und Rumpf nicht findet.
  marketplaceAvatar,
}

extension RobloxTargetLabel on RobloxTarget {
  String get label => switch (this) {
        RobloxTarget.character => 'Figur im Erlebnis',
        RobloxTarget.accessory => 'UGC-Accessoire',
        RobloxTarget.marketplaceAvatar => 'Marktplatz-Avatar',
      };

  /// Grenze, ab der der Importer ablehnt.
  int get hardTriangles => switch (this) {
        RobloxTarget.character => robloxMaxTriangles,
        RobloxTarget.accessory => robloxAccessoryTriangles,
        // Der Importer deckelt auch hier je Mesh; die schärfere
        // Marktplatz-Grenze steht als eigene Zeile im Bericht.
        RobloxTarget.marketplaceAvatar => robloxMaxTriangles,
      };

  /// Arbeitsziel – darunter läuft das Modell im Spiel flüssig.
  int get goalTriangles => switch (this) {
        RobloxTarget.character => robloxGoalTriangles,
        RobloxTarget.accessory => robloxAccessoryTriangles,
        RobloxTarget.marketplaceAvatar => specBodyTotalTriangles,
      };
}

/// Harte Obergrenze des Importers je Mesh. Aus der Spezifikation:
/// „Individual meshes can not exceed 20,000 triangles."
const int robloxMaxTriangles = specMaxMeshTriangles;

/// Arbeitsziel für Figuren und Props.
///
/// Eine runde Zahl unterhalb dessen, was ein Marktplatz-Körper
/// zusammen ausgibt: Die sechs Teile eines R15-Körpers dürfen laut
/// Tabelle zusammen [specBodyTotalTriangles] Dreiecke haben. Wer
/// darunter bleibt, kann das Modell auch zerlegt hochladen.
const int robloxGoalTriangles = 10000;

/// Obergrenze für UGC-Accessoires: „Rigid accessories can't exceed 4k
/// triangles."
const int robloxAccessoryTriangles = specAccessoryTriangles;

/// Größte zulässige Texturkante: „Roblox supports up to 1024×1024
/// pixel spaces for texture maps."
const int robloxMaxTexture = specMaxTexture;

/// Höchstzahl der Bones, die einen Vertex beeinflussen dürfen: „A
/// vertex can not be influenced by more than 4 bones or joints."
const int robloxMaxInfluences = specMaxInfluences;

/// Ein Stud in Metern – das physikalische Maß, mit dem Roblox seine
/// Welt beschreibt. Achtung: Der 3D-Importer rechnet **nicht** damit
/// um, er setzt schlicht einen Meter gleich einem Stud.
const double robloxStudMeters = 0.28;

/// Die Dreieckszahl, mit der ein Modell in Roblox' Auto Setup gehen
/// soll.
///
/// **Nicht dokumentiert, sondern aus einem Lauf.** `AutoSetupParams`
/// kennt keine Reduktion: Was hineingeht, wird verteilt. Bei 9.627
/// Dreiecken bekam jede Gliedmaße 2.304 – bei einem Gruppenbudget von
/// 1.248. Die Eingabe muss also schon darunter liegen, und 7.000 hält
/// nach der Verteilung Luft.
const int robloxAutoSetupTriangles = 7000;

/// Höhe eines Standard-Charakters in Studs (Vergleichsmaßstab).
const double robloxCharacterStuds = 5.0;

/// Rechnet ein Dreiecks-Budget in die Polygonzahl um, die ein Anbieter
/// als Ziel bekommt.
///
/// Roblox zählt **Dreiecke**. Ein Viereck wird beim Export zu zwei
/// Dreiecken – bei Quad-Topologie darf der Anbieter also nur die
/// halbe Zahl liefern, sonst landet ein „10.000er"-Netz bei 20.000
/// Dreiecken und damit genau auf der harten Grenze.
int robloxPolygonBudget(int triangles, {required bool quad}) =>
    quad ? triangles ~/ 2 : triangles;

/// Wie schwer ein Fund wiegt.
enum RobloxLevel {
  /// Der Importer lehnt ab oder das Modell ist unbrauchbar.
  blocker,

  /// Geht durch, kostet aber Leistung oder Qualität.
  warning,

  /// Nichts zu tun, nur zur Kenntnis.
  hint,

  /// Regel eingehalten.
  ok,
}

/// Ein einzelner Punkt der Prüfliste.
class RobloxFinding {
  const RobloxFinding(this.level, this.title, this.detail);

  final RobloxLevel level;

  /// Kurzform für die Liste, z. B. „Dreiecke: 8.400".
  final String title;

  /// Was das bedeutet und was zu tun ist.
  final String detail;

  @override
  String toString() => '$title – $detail';
}

/// Ein Texturbild aus der Datei.
class RobloxTexture {
  const RobloxTexture(this.width, this.height, this.mimeType);

  final int width;
  final int height;
  final String mimeType;

  /// Über der **harten** Grenze: Darüber nimmt der Marktplatz das
  /// Bild nicht an.
  ///
  /// Hier stand [robloxMaxTexture] (1024) – und damit meldete die
  /// Prüfung ein 2048er-Bild als Blocker, obwohl der Importer bis
  /// 4096 nimmt und der Marktplatz bis 2048. Ein 2048er-Bild ist also
  /// nicht falsch, nur nicht optimal.
  bool get tooLarge =>
      width > specMarketplaceTexture || height > specMarketplaceTexture;

  /// Über der Zielgröße für den UV-Raum, aber noch zulässig.
  bool get overTarget =>
      !tooLarge && (width > robloxMaxTexture || height > robloxMaxTexture);
}

/// Die aus der Datei abgelesenen Zahlen.
class RobloxFacts {
  const RobloxFacts({
    required this.triangles,
    required this.meshCount,
    required this.primitiveCount,
    required this.materialCount,
    required this.uvSets,
    required this.uvMin,
    required this.uvMax,
    required this.openEdges,
    required this.rawOpenEdges,
    required this.partVolumes,
    required this.textures,
    this.meshTriangles = const [],
    this.meshNames = const [],
    this.maxPrimitivesPerMesh = 1,
    this.size = const [0.0, 0.0, 0.0],
    this.reversedEdges = 0,
    this.signedVolume = 0.0,
    this.volumeRatio = 0.0,
    this.degenerateTriangles = 0,
    this.jointSets = 0,
    this.boneCount = 0,
    this.maxInfluences = 0,
    this.scaledBones = 0,
    this.rotatedBones = 0,
    this.rootAtOrigin = true,
    this.lowerTorsoAtOrigin = true,
    this.rootWeighted = false,
    this.rootName = '',
    this.boneNames = const [],
  });

  /// Dreiecke über alle Meshes zusammen.
  final int triangles;
  final int meshCount;

  /// Dreiecke je einzelnem Mesh. Roblox deckelt **je Mesh**, nicht das
  /// ganze Modell – ein Modell aus fünf Teilen à 6.000 geht durch.
  final List<int> meshTriangles;

  /// Die Namen der Netze, in derselben Reihenfolge wie
  /// [meshTriangles]. Daran hängt die Frage, ob die fünf
  /// Gesichtsteile in der Datei stehen – ohne sie baut Auto Setup
  /// keinen dynamischen Kopf.
  final List<String> meshNames;

  /// Meiste Primitive in einem einzelnen Mesh – mehr als eines heißt
  /// mehr als ein Material in diesem Mesh.
  final int maxPrimitivesPerMesh;

  /// Ausdehnung in x, y, z in glTF-Einheiten (laut Spezifikation
  /// Meter).
  final List<double> size;

  /// Kanten mit gegenläufig gewickelten Nachbardreiecken (Backfaces).
  final int reversedEdges;

  /// Eingeschlossenes Volumen mit Vorzeichen; negativ = Normalen nach
  /// innen.
  final double signedVolume;

  /// Volumen im Verhältnis zum Würfel der größten Kante – nahe null
  /// bei einer Fläche ohne Dicke.
  final double volumeRatio;

  /// Dreiecke ohne Fläche.
  final int degenerateTriangles;

  /// Zeichenaufrufe – mehr als einer je Mesh heißt mehr als ein
  /// Material.
  final int primitiveCount;
  final int materialCount;

  /// Wie viele UV-Sätze (TEXCOORD_n) vorkommen; 0 = gar keine UVs.
  final int uvSets;

  /// Kleinster und größter UV-Wert; Roblox will alles in 0–1.
  final double uvMin;
  final double uvMax;

  /// Kanten, die nur zu einem Dreieck gehören (Löcher im Netz).
  final int openEdges;

  /// Dieselbe Zählung ohne Verschweißen – so, wie die Datei
  /// geschrieben wird. Roblox verschweißt nicht.
  final int rawOpenEdges;

  /// Vorzeichenbehaftetes Volumen je zusammenhängendem Teil, größtes
  /// zuerst. Negativ heißt: nach innen gewickelt.
  final List<double> partVolumes;

  /// Wie viele Teile nach innen zeigen.
  int get invertedParts => partVolumes.where((v) => v < 0).length;

  final List<RobloxTexture> textures;

  /// JOINTS_n-Sätze; mehr als einer heißt mehr als vier Einflüsse.
  final int jointSets;
  final int boneCount;

  /// Größte Zahl von Bones, die auf einen Vertex wirken.
  final int maxInfluences;

  /// Bones mit einer Skalierung ungleich 1,1,1.
  final int scaledBones;

  /// Bones mit einer Rotation ungleich 0,0,0.
  final int rotatedBones;

  /// Sitzt der Wurzelknochen im Ursprung?
  final bool rootAtOrigin;

  /// Sitzt der LowerTorso im Ursprung? Roblox verlangt das für R15
  /// ausdrücklich – der Nullpunkt einer Figur liegt an der Hüfte,
  /// nicht am Boden.
  final bool lowerTorsoAtOrigin;

  /// Hat der Wurzelknochen Einflüsse auf Vertices? (Roblox will keine.)
  final bool rootWeighted;

  final String rootName;

  /// Namen der Skelett-Gelenke – daran hängt der R15-Import.
  final List<String> boneNames;

  /// Welche der 15 R15-Gelenke fehlen.
  List<String> get missingR15 => missingR15Bones(boneNames);

  bool get hasRig => boneCount > 0;
  bool get hasUvs => uvSets > 0;

  /// Das größte einzelne Mesh – daran misst der Importer.
  int get largestMesh => meshTriangles.isEmpty
      ? triangles
      : meshTriangles.reduce((a, b) => a > b ? a : b);

  /// Höhe in glTF-Einheiten (y-Achse).
  double get height => size.length > 1 ? size[1] : 0;

  /// Höhe in Studs. Der Importer rechnet die Datei über die
  /// Scale-Unit-Einstellung in Meter um und setzt dann einen Meter
  /// gleich einem Stud – die Höhe in Einheiten ist also die Höhe in
  /// Studs. (Physikalisch misst ein Stud 0,28 m, siehe
  /// [robloxStudMeters]; danach richtet sich der Importer aber nicht.)
  double get studs => height;
}

String _n(int value) {
  final text = '$value';
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// Beurteilt die abgelesenen Zahlen. Die Liste ist die Prüfliste, die
/// die Oberfläche anzeigt – erledigte Punkte inbegriffen, damit man
/// sieht, was schon stimmt.
List<RobloxFinding> checkRobloxFacts(RobloxFacts facts, RobloxTarget target) {
  final findings = <RobloxFinding>[];

  // 1. Dreiecke – der Grund, an dem KI-Modelle fast immer scheitern.
  // Die Grenze gilt je Mesh: Ein Modell aus fünf Teilen à 6.000 geht
  // durch, ein einzelnes Teil mit 21.000 nicht.
  final hard = target.hardTriangles;
  final goal = target.goalTriangles;
  final largest = facts.largestMesh;
  final sum = facts.meshCount > 1
      ? ' Zusammen sind es ${_n(facts.triangles)} in '
          '${facts.meshCount} Meshes; die Grenze gilt je Mesh, die '
          'Summe zählt für die Leistung im Erlebnis.'
      : '';
  final label = facts.meshCount > 1
      ? 'Größtes Mesh: ${_n(largest)} Dreiecke'
      : 'Dreiecke: ${_n(largest)}';
  if (largest > hard) {
    findings.add(RobloxFinding(
        RobloxLevel.blocker,
        label,
        'Über der Grenze von ${_n(hard)} je Mesh – der Importer weist '
            'es ab. Am besten schon bei der Generierung begrenzen '
            '(Meshy „target_polycount", Tripo „face_limit", Rodin '
            '„quality_override"); bei Tripo zusätzlich „Smart '
            'Low-Poly" einschalten – mit „face_limit" = 10.000 allein '
            'kamen in einem Lauf 101.298 Dreiecke zurück. Ist es '
            'trotzdem zu viel, das Modell beim Anbieter neu rechnen '
            'lassen: Der Knopf „Bei Tripo3D nachrechnen" schickt es '
            'zurück und holt es mit Dreiecks- und Texturgrenze wieder '
            '– UVs und Textur bleiben erhalten, weil derselbe Dienst '
            'rechnet. Oder gleich hier: Der Dreiecksbudget-Regler im '
            'Viewer (Tacho-Symbol) reduziert jede GLB und nimmt die '
            'UVs mit – ein Skelett übersteht das allerdings nicht, '
            'also vorher reduzieren und danach riggen. Achtung bei '
            'Quad-Netzen: Jedes Viereck wird zu zwei Dreiecken.$sum'));
  } else if (largest > goal) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        label,
        'Der Import geht durch (Grenze ${_n(hard)} je Mesh), das '
            'Arbeitsziel liegt aber unter ${_n(goal)}. Darüber kostet '
            'jede Instanz im Erlebnis spürbar Leistung.$sum'));
  } else {
    findings.add(RobloxFinding(
        RobloxLevel.ok,
        label,
        'Innerhalb des Arbeitsziels von ${_n(goal)} je Mesh für '
            '${target.label}.$sum'));
  }

  // 1b. Für den Marktplatz zählt eine zweite Rechnung: nicht je Mesh,
  // sondern je Körpergruppe. Eine Hand mit 1.374 Dreiecken sprengt
  // das Budget des ganzen Arms (1.248), ohne dass irgendeine
  // Mesh-Grenze reißt.
  if (target == RobloxTarget.marketplaceAvatar) {
    final gesamt = facts.triangles;
    final teile = [
      for (final e in specBodyPartTriangles.entries) '${e.key} ${_n(e.value)}',
    ].join(', ');
    findings.add(RobloxFinding(
        gesamt > specBodyTotalTriangles
            ? RobloxLevel.blocker
            : RobloxLevel.ok,
        'Marktplatz-Budget: ${_n(gesamt)} von '
            '${_n(specBodyTotalTriangles)}',
        'Der Marktplatz rechnet je Körpergruppe: $teile. Solange die '
            'Figur ein einziges Netz ist, lässt sich nur die Summe '
            'prüfen; nach der Zerlegung in 15 Meshes nennt der Bericht '
            'jede Gruppe einzeln. Erfahrungswert: Ausmodellierte '
            'Finger sprengen den Arm zuerst – „rounded mitten stumps '
            'without separate fingers" in den Prompt.'));
  }

  // 2. Ein Material je Mesh – auch das zählt je Mesh, nicht im Modell.
  if (facts.maxPrimitivesPerMesh > 1) {
    findings.add(RobloxFinding(
        RobloxLevel.blocker,
        'Bis zu ${facts.maxPrimitivesPerMesh} Materialien in einem Mesh',
        'Roblox erlaubt genau ein Material je Mesh (insgesamt '
            '${facts.materialCount} in ${facts.primitiveCount} '
            'Teilnetzen). Mehrere Oberflächen müssen in einem '
            'Texture-Atlas zusammengefasst werden (in Blender: '
            'Materialien zusammenlegen, UVs neu packen, eine Textur '
            'backen).'));
  } else {
    findings.add(RobloxFinding(
        RobloxLevel.ok,
        'Ein Material je Mesh',
        facts.meshCount > 1
            ? '${facts.materialCount} Material(ien) auf '
                '${facts.meshCount} Meshes verteilt – je Mesh genau '
                'eines, so verlangt es der Importer.'
            : 'Genau ein Material – so verlangt es der Importer.'));
  }

  // 3. Geschlossene Form.
  if (facts.openEdges > 0) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Offene Kanten: ${_n(facts.openEdges)}',
        'Das Netz ist nicht wasserdicht. Löcher werden im Spiel von '
            'hinten durchsichtig. **Das macht die App selbst**: „In '
            'Ordnung bringen" schließt die Löcher, ohne neue Punkte '
            'anzulegen – UVs und Gewichte bleiben. Nur was danach '
            'übrig ist, gehört nach Blender (Mesh → Clean Up).'));
  } else {
    findings.add(const RobloxFinding(RobloxLevel.ok, 'Wasserdicht',
        'Keine offenen Kanten – keine Löcher im Netz.'));
  }

  // 3a. Und dieselbe Zählung ohne Verschweißen: Die App rechnet sonst
  // an einer Arbeitskopie, die es in der Datei nicht gibt.
  if (facts.rawOpenEdges > facts.openEdges) {
    findings.add(RobloxFinding(
        RobloxLevel.hint,
        'Doppelte Punkte: ${_n(facts.rawOpenEdges - facts.openEdges)} '
            'Randkanten mehr',
        'Die Zahl darüber gilt nach dem Verschweißen nach Position – '
            'eine Textur-Naht verdoppelt Punkte, ist aber kein Loch. '
            'Ungeschweißt zählt die Datei ${_n(facts.rawOpenEdges)} '
            'Randkanten, und so sieht Blender sie, so sieht Roblox '
            'sie. Wo eine Naht in der Textur sitzt, ist das richtig '
            'so; an einem Teil ohne UVs sind doppelte Punkte ein '
            'Modellierfehler.'));
  }

  // 3b. Backfaces: nach innen zeigende oder uneinheitliche Normalen.
  if (facts.reversedEdges > 0) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Uneinheitliche Wicklung: ${_n(facts.reversedEdges)} Kanten',
        'An diesen Kanten stoßen gegenläufig gewickelte Dreiecke '
            'aneinander – solche Flächen sind im Spiel von außen '
            'unsichtbar (Backfaces). **Das macht die App selbst**: '
            '„Für Roblox anpassen" vereinheitlicht die Wicklung und '
            'rechnet die Normalen neu. Blender braucht es dafür nicht '
            'mehr.'));
  } else if (facts.invertedParts > 0) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Nach innen gewickelt: ${_n(facts.invertedParts)} von '
            '${_n(facts.partVolumes.length)} zusammenhängenden Stücken',
        'Die Wicklung ist einheitlich, aber verkehrt herum – diese '
            'Stücke sind im Spiel von außen unsichtbar. Gemessen wird '
            'das Volumen mit Vorzeichen **je zusammenhängendem Stück**: '
            'positiv heißt außen. Die Summe allein genügt nicht, ein '
            'großer richtiger Körper überdeckt darin eine falsch '
            'gewickelte Kugel. „In Ordnung bringen" dreht jedes Teil '
            'einzeln.'));
  } else {
    findings.add(RobloxFinding(
        RobloxLevel.ok,
        'Normalen nach außen',
        facts.partVolumes.length > 1
            ? 'Einheitliche Wicklung, und alle '
                '${_n(facts.partVolumes.length)} zusammenhängenden '
                'Stücke haben ein positives Volumen – keine Backfaces. '
                'Gezählt sind Inseln aus zusammenhängenden Dreiecken, '
                'nicht Netze: Ein Körper, dessen Arme frei stehen, '
                'bringt allein schon mehrere mit.'
            : 'Einheitliche Wicklung, positives Volumen – keine '
                'Backfaces.'));
  }

  // 3b2. Die fünf Gesichtsteile – nur beim Marktplatz-Ziel.
  //
  // Ob sie in der Datei stehen, ließ sich bisher nur durch Öffnen der
  // GLB beantworten. Das ist genau die Frage, die vor dem Hochladen
  // ansteht: Ohne Augen und Mund als eigene Netze baut Auto Setup
  // keinen dynamischen Kopf, und ohne den lehnt der Marktplatz das
  // Ganzkörper-Bundle ab („FACS controls for at least 17 poses").
  if (target == RobloxTarget.marketplaceAvatar) {
    final vorhanden = [
      for (final name in faceMeshNames)
        if (facts.meshNames.contains(name)) name,
    ];
    final fehlend = [
      for (final name in faceMeshNames)
        if (!facts.meshNames.contains(name)) name,
    ];
    if (fehlend.isEmpty) {
      findings.add(RobloxFinding(
          RobloxLevel.ok,
          'Gesichtsteile: alle fünf da',
          'LeftEye, RightEye, UpperTeeth, LowerTeeth und Tongue stehen '
              'als eigene Netze in der Datei – zusammen mit dem Körper '
              'also ${_n(facts.meshCount)} Netze. Daran erkennt Auto '
              'Setup, was es für die FACS-Posen bewegen kann.'));
    } else {
      findings.add(RobloxFinding(
          RobloxLevel.warning,
          'Gesichtsteile: ${_n(fehlend.length)} von 5 fehlen',
          '${fehlend.join(', ')} ${fehlend.length == 1 ? 'fehlt' : 'fehlen'} '
              'in der Datei${vorhanden.isEmpty ? '' : ' (da sind: '
                  '${vorhanden.join(', ')})'}. Ohne Augen und Mund als '
              'eigene Netze baut Auto Setup keinen dynamischen Kopf, '
              'und der Marktplatz lehnt das Ganzkörper-Bundle ab. „Für '
              'Roblox vorbereiten" ergänzt sie, solange der Schalter '
              '„Gesichtsteile ergänzen" an ist.'));
    }
  }

  // 3c. Nullstärke – genau der Fehler, vor dem der Prompt bei
  // Umhängen, Schleiern und Netzen warnt.
  final thinnest = facts.size.isEmpty
      ? 0.0
      : facts.size.reduce((a, b) => a < b ? a : b);
  final widest = facts.size.isEmpty
      ? 0.0
      : facts.size.reduce((a, b) => a > b ? a : b);
  final flat = widest > 0 && thinnest / widest < 0.01;
  if (flat || facts.volumeRatio < 0.0005) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        flat ? 'Fläche ohne Dicke' : 'Kaum Volumen',
        flat
            ? 'Die dünnste Ausdehnung ist weniger als ein Hundertstel '
                'der größten – das ist eine Platte, kein Körper. '
                'Roblox verlangt Volumen; Nullstärke flackert im '
                'Spiel. In Blender mit „Solidify" Dicke geben.'
            : 'Das eingeschlossene Volumen ist verschwindend klein '
                'gegenüber der Ausdehnung. Meist sind das offene '
                'Schalen oder hauchdünne Teile (Umhänge, Schleier, '
                'Netze) – in Blender mit „Solidify" Dicke geben.'));
  } else {
    findings.add(const RobloxFinding(RobloxLevel.ok, 'Hat Volumen',
        'Keine Nullstärke, kein flaches Blatt.'));
  }

  // 3d. Degenerierte Dreiecke.
  if (facts.degenerateTriangles > 0) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Dreiecke ohne Fläche: ${_n(facts.degenerateTriangles)}',
        'Flächen mit zusammenfallenden Ecken. Sie kosten nichts, '
            'können aber Schatten- und Kollisionsfehler auslösen. In '
            'Blender: Mesh → Clean Up → Degenerate Dissolve.'));
  }

  // 4. UVs.
  if (!facts.hasUvs) {
    findings.add(const RobloxFinding(
        RobloxLevel.blocker,
        'Keine UV-Koordinaten',
        'Ohne UVs kann Roblox keine Textur auf das Modell legen. Bei '
            'der Generierung die Textur einschalten oder in Blender '
            'auspacken (UV → Smart UV Project).'));
  } else if (facts.uvSets > 1) {
    findings.add(RobloxFinding(
        RobloxLevel.blocker,
        'UV-Sätze: ${facts.uvSets}',
        'Roblox liest genau einen UV-Satz. Die zusätzlichen Sätze in '
            'Blender löschen.'));
  } else if (facts.uvMin < -0.001 || facts.uvMax > 1.001) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'UVs außerhalb 0–1',
        'Die Koordinaten reichen von ${facts.uvMin.toStringAsFixed(2)} '
            'bis ${facts.uvMax.toStringAsFixed(2)}. Roblox erwartet '
            'alles im 0–1-Raum; was darüber hinausgeht, kachelt oder '
            'wird abgeschnitten.'));
  } else {
    findings.add(const RobloxFinding(RobloxLevel.ok, 'UVs in 0–1',
        'Ein einzelner UV-Satz, vollständig im 0–1-Raum.'));
  }

  // 5. Texturen.
  if (facts.textures.isEmpty) {
    findings.add(const RobloxFinding(
        RobloxLevel.hint,
        'Keine Textur eingebettet',
        'Das Modell kommt ohne Bild. Für Figuren ist eine Textur die '
            'Regel – in Studio lässt sich sonst nur eine Farbe '
            'zuweisen.'));
  } else {
    final tooLarge = facts.textures.where((t) => t.tooLarge).toList();
    final biggest = facts.textures
        .map((t) => t.width > t.height ? t.width : t.height)
        .reduce((a, b) => a > b ? a : b);
    final ueberZiel = facts.textures.where((t) => t.overTarget).toList();
    if (tooLarge.isNotEmpty) {
      findings.add(RobloxFinding(
          RobloxLevel.blocker,
          'Textur zu groß: $biggest px',
          'Über $specMarketplaceTexture×$specMarketplaceTexture nimmt '
              'der Marktplatz das Bild nicht an. '
              '${tooLarge.length} von ${facts.textures.length} Bildern '
              'liegen darüber. Das lässt sich hier beheben: Der Knopf '
              '„Texturen auf $robloxMaxTexture verkleinern" unten '
              'rechnet sie herunter und packt die GLB neu. Beim '
              'lokalen Generator gleich den Textur-Modus '
              '„Atlas $robloxMaxTexture" wählen.'));
    } else if (ueberZiel.isNotEmpty) {
      // Hier stand ein Blocker ab 1024. Das war falsch: Der Importer
      // nimmt bis 4096, der Marktplatz bis 2048. Die 1024 sind die
      // empfohlene UV-Fläche, kein Ablehnungsgrund.
      findings.add(RobloxFinding(
          RobloxLevel.hint,
          'Textur: $biggest px – größer als nötig',
          'Zulässig bis $specMarketplaceTexture; empfohlen sind '
              '$robloxMaxTexture für den UV-Raum. Es geht also durch, '
              'kostet aber Speicher und Ladezeit, ohne sichtbar besser '
              'auszusehen. Der Knopf „Texturen auf $robloxMaxTexture '
              'verkleinern" nimmt es herunter.'));
    } else {
      findings.add(RobloxFinding(
          RobloxLevel.ok,
          'Textur: $biggest px',
          '${facts.textures.length} Bild(er), alle innerhalb von '
              '$robloxMaxTexture×$robloxMaxTexture. Roblox nimmt PNG, '
              'JPG, TGA und BMP – im GLB stecken PNG oder JPEG.'));
    }
  }

  // 5b. Skalierung – die häufigste Importpanne. glTF rechnet in
  // Metern, der Importer steht aber auf Studs.
  final height = facts.height;
  if (height <= 0) {
    findings.add(const RobloxFinding(RobloxLevel.hint, 'Größe unbekannt',
        'Die Höhe ließ sich nicht bestimmen.'));
  } else {
    // Gemessen an einem echten Import: Der Importer rechnet die Datei
    // über die Scale-Unit-Einstellung in Meter um und setzt dann einen
    // Meter gleich einem Stud. Die Höhe in Einheiten ist damit die
    // Höhe in Studs – eine 1,20-Einheiten-Figur kam kniehoch an.
    final studs = height;
    final ziel = target == RobloxTarget.accessory
        ? 'Ein Accessoire richtet sich nach dem Körperteil, an dem es '
            'sitzt – ein Hut misst etwa einen Stud.'
        : 'Ein Standard-Charakter ist etwa '
            '${robloxCharacterStuds.toStringAsFixed(0)} Studs hoch.';
    final detail = 'Das Modell ist ${height.toStringAsFixed(2)} '
        'glTF-Einheiten hoch, und genau so viele Studs werden daraus: '
        'Der Importer setzt eine Datei-Einheit gleich einem Stud. '
        '$ziel Der Knopf „Für Roblox anpassen" bringt eine Figur von '
        'sich aus auf ${robloxCharacterStuds.toStringAsFixed(0)} '
        'Studs. Tripos Schalter „auto_size" tut das **nicht** – ein '
        'Lauf damit kam mit 1,00 Einheiten zurück; er sorgt nur für '
        'eine Größenordnung, nicht für das Maß.';
    final plausible = target == RobloxTarget.accessory
        ? studs > 0.2 && studs < 8
        : studs > robloxCharacterStuds * 0.5 &&
            studs < robloxCharacterStuds * 2;
    findings.add(RobloxFinding(
        plausible ? RobloxLevel.ok : RobloxLevel.warning,
        'Größe: ${studs.toStringAsFixed(2)} Studs',
        plausible
            ? detail
            : '$detail So wie sie ist, kommt sie in der falschen Größe '
                'an.'));
  }

  // 6. Skelett. Ein Accessoire ist ein starres Teil – dort ist ein
  // Skelett nicht nur unnötig, sondern falsch.
  if (!facts.hasRig) {
    findings.add(RobloxFinding(
        RobloxLevel.ok,
        'Ohne Skelett',
        switch (target) {
          RobloxTarget.accessory =>
            'Richtig so: Ein Accessoire wie Hut, Frisur oder Rucksack '
                'ist ein starres Netz. Beim Import „No Rig" wählen.',
          // Hier stand für jedes Ziel „eine animierbare Figur braucht
          // ein Skelett". Für den Marktplatz-Weg ist das falsch: Auto
          // Setup baut sein eigenes Rig und verwirft ein
          // mitgebrachtes – das rohe Netz ist dort das saubere.
          RobloxTarget.marketplaceAvatar =>
            'Richtig so für den Marktplatz-Weg: Roblox\' Auto Setup '
                'zerlegt das Netz selbst in 15 Teile, baut das '
                'R15-Rig, häutet, setzt Cages und Attachments und '
                'erzeugt den Gesichtsrig. Ein mitgebrachtes Skelett '
                'würde dabei ohnehin verworfen. Bei Tripo also **ohne** '
                'Rigging erzeugen.',
          RobloxTarget.character =>
            'Beim Import „No Rig" wählen. Für Props ist das richtig; '
                'eine animierbare Figur im eigenen Erlebnis braucht '
                'ein Skelett.',
        }));
  } else if (target == RobloxTarget.marketplaceAvatar) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Skelett für den Marktplatz-Weg',
        'Das Modell trägt ${facts.boneCount} Bones. Auto Setup baut '
            'sein eigenes R15-Rig und verwirft dieses – das rohe Netz '
            'wäre sauberer. Für die Startfigur im eigenen Erlebnis ist '
            'das Skelett dagegen genau richtig; dann ist hier das Ziel '
            '„Figur im Erlebnis" das passende.'));
  } else if (target == RobloxTarget.accessory) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Skelett in einem Accessoire',
        'Das Modell trägt ${facts.boneCount} Bones. Ein klassisches '
            'Accessoire (Hut, Frisur, Rucksack, Brille) ist ein '
            'starres Netz und wird über einen Attachment-Punkt am '
            'Avatar befestigt – das Skelett kann weg. Nur Layered '
            'Clothing, das sich mitverformt, braucht eines, und dafür '
            'gehören zusätzlich Innen- und Außen-Cage-Meshes in die '
            'Datei; die erzeugt diese App nicht.'));
  } else {
    if (facts.jointSets > 1 || facts.maxInfluences > robloxMaxInfluences) {
      findings.add(RobloxFinding(
          RobloxLevel.blocker,
          'Bis zu ${facts.maxInfluences} Bones je Vertex',
          'Roblox erlaubt höchstens $robloxMaxInfluences. In Blender '
              'die Gewichte begrenzen (Weight Paint → Limit Total = '
              '$robloxMaxInfluences) und normalisieren.'));
    } else {
      findings.add(RobloxFinding(
          RobloxLevel.ok,
          'Höchstens ${facts.maxInfluences} Bones je Vertex',
          'Innerhalb der Grenze von $robloxMaxInfluences.'));
    }
    if (facts.scaledBones > 0 || facts.rotatedBones > 0) {
      findings.add(RobloxFinding(
          RobloxLevel.blocker,
          'Bone-Transformationen: ${facts.scaledBones} skaliert, '
              '${facts.rotatedBones} gedreht',
          'Roblox verlangt für jeden Bone Scale 1,1,1 und Rotation '
              '0,0,0. In Blender alle Transformationen anwenden '
              '(Object → Apply → All Transforms), dann neu '
              'exportieren.'));
    } else {
      findings.add(RobloxFinding(
          RobloxLevel.ok,
          'Bones ohne Skalierung und Rotation',
          'Alle ${facts.boneCount} Bones stehen auf Scale 1,1,1 und '
              'Rotation 0,0,0.'));
    }
    if (!facts.rootAtOrigin) {
      findings.add(RobloxFinding(
          RobloxLevel.blocker,
          'Wurzelknochen nicht im Ursprung',
          'Der Wurzelknochen '
              '${facts.rootName.isEmpty ? '' : '„${facts.rootName}" '}'
              'muss bei 0,0,0 sitzen. In Blender an den Ursprung '
              'setzen und die Figur darüber aufbauen.'));
    } else if (facts.rootWeighted) {
      findings.add(const RobloxFinding(
          RobloxLevel.blocker,
          'Wurzelknochen trägt Gewichte',
          'Der Wurzelknochen darf keine Vertices beeinflussen – er ist '
              'nur der Aufhängepunkt. Die Gewichte auf den ersten '
              'echten Bone (Hüfte/Torso) übertragen.'));
    } else if (!facts.lowerTorsoAtOrigin &&
        target != RobloxTarget.accessory) {
      findings.add(const RobloxFinding(
          RobloxLevel.blocker,
          'LowerTorso nicht im Ursprung',
          'Roblox schreibt für Charakterkörper beides zugleich vor: '
              'Wurzelknochen **und** LowerTorso bei 0,0,0. Der '
              'Nullpunkt einer Figur liegt damit an der Hüfte, nicht '
              'am Boden – die Füße stehen im Minus. Liegt er auf '
              'Fußhöhe, landet der HumanoidRootPart zwischen den '
              'Füßen: Die Figur schwebt um die Hip Height nach oben '
              'oder kippt beim ersten Schritt um. Der Knopf „Für '
              'Roblox vorbereiten" legt den Nullpunkt richtig.'));
    } else {
      findings.add(const RobloxFinding(
          RobloxLevel.ok,
          'Nullpunkt an der Hüfte, Wurzelknochen ohne Gewichte',
          'Wurzelknochen und LowerTorso sitzen bei 0,0,0, und der '
              'Wurzelknochen bewegt keinen Vertex. So erwartet es der '
              'Importer.'));
    }
    // Die R15-Benennung ist der Schritt, an dem der Rig-Weg steht
    // oder fällt – und sie ist aus der Datei ablesbar.
    final missing = facts.missingR15;
    if (missing.isEmpty) {
      findings.add(const RobloxFinding(
          RobloxLevel.ok,
          'Knochen nach R15 benannt',
          'Alle 15 Gelenke tragen die Namen, die der Importer '
              'erwartet – die Figur taugt als StarterCharacter.'));
    } else if (missing.length >= robloxR15Bones.length - 1) {
      findings.add(RobloxFinding(
          RobloxLevel.warning,
          'Knochen nicht nach R15 benannt',
          'Kein einziges der 15 R15-Gelenke ist zu finden (die Datei '
              'nennt z. B. ${facts.boneNames.take(3).join(', ')}). Für '
              'eine Spielfigur müssen die Knochen umbenannt werden – '
              'das macht „Für Roblox vorbereiten" im Export-Menü. Ohne '
              'Umbenennen bleibt nur der Import-Weg „Custom".'));
    } else {
      findings.add(RobloxFinding(
          RobloxLevel.warning,
          'R15: ${robloxR15Bones.length - missing.length} von '
              '${robloxR15Bones.length} Gelenken',
          'Es fehlen: ${missing.join(', ')}. Ohne sie lässt sich das '
              'Modell nur mit der Import-Einstellung „Custom" nutzen; '
              'als StarterCharacter braucht es alle 15.'));
    }

    findings.add(const RobloxFinding(
        RobloxLevel.hint,
        'T-Pose und Rig-Typ von Hand prüfen',
        'Das Modell muss in T-Pose stehen (Arme waagerecht) – das '
            'kann die App nicht messen. Beim Import wählt man R15, '
            'Rthro oder Custom: „Custom" ergibt ein Modell auf einem '
            'einzelnen Mesh, das die Katalog-R15-Animationen abspielt; '
            '„R15"/„Rthro" ergibt einen Humanoid-Rig, der als '
            'StarterCharacter taugt. In 15 einzelne MeshParts '
            'zerschneiden muss man nichts – es reicht, die Knochen '
            'nach R15 zu benennen und auf ein Mesh zu skinnen.'));
  }

  // 7. Was nur für Accessoires gilt.
  if (target == RobloxTarget.accessory) {
    findings.add(const RobloxFinding(
        RobloxLevel.hint,
        'Befestigung kommt aus Studio',
        'Das Mesh allein ist noch kein Accessoire: In Studio wird '
            'daraus ein Accessory mit einem Handle und einem '
            'Attachment (z. B. HatAttachment), das die Lage am Avatar '
            'festlegt – dabei hilft das Accessory Fitting Tool. Der '
            'Verkauf im Marketplace hängt zusätzlich an den '
            'Kontovoraussetzungen von Roblox.'));
  }

  // 8. Dateiformat.
  findings.add(const RobloxFinding(
      RobloxLevel.hint,
      'Format: GLB',
      'Roblox nimmt .fbx, .gltf/.glb und .obj. GLB liest Studio '
          'direkt und bringt die Texturen mit, hat aber eingeschränkte '
          'Rig-Unterstützung. Für gerigte Figuren ist FBX der '
          'Standardfall – dafür die GLB in Blender öffnen und als FBX '
          'ausgeben. OBJ passt nur für einfache statische Props.'));

  // 9. Was diese Prüfung grundsätzlich nicht sehen kann.
  findings.add(const RobloxFinding(
      RobloxLevel.hint,
      'Quad-Topologie ist hier nicht messbar',
      'glTF speichert ausschließlich Dreiecke – ob der Generator ein '
          'Viereck-Netz geliefert hat, steht nicht in der Datei. Die '
          'Zahl oben ist die Dreieckszahl nach der Triangulierung, '
          'also genau das, was Roblox zählt.'));
  findings.add(const RobloxFinding(
      RobloxLevel.hint,
      'Diese Prüfung gilt für die GLB',
      'Geht das Modell für ein Rig über Blender nach FBX, ändern sich '
          'genau dort Dreieckszahl und Bone-Transforms. Nach dem '
          'Export in Blender gegenprüfen: Statistik-Overlay für die '
          'Dreiecke, N-Panel → Item → Transform für Scale 1,1,1 und '
          'Rotation 0,0,0 der Bones, notfalls Object → Apply → All '
          'Transforms.'));

  return findings;
}

/// Liest die Prüfzahlen aus einer GLB-Datei.
Future<RobloxFacts> readRobloxFacts(Uint8List glb) async {
  final parts = splitGlb(glb);
  final json = parts.json;
  final bin = parts.bin;

  // Netz- und Materialzahlen direkt aus dem JSON – dafür muss die
  // Geometrie nicht gelesen werden.
  final meshes = json['meshes'] as List? ?? const [];
  final materials = <int>{};
  final meshTriangles = <int>[];
  final meshNames = <String>[];
  var primitiveCount = 0;
  var maxPrimitivesPerMesh = 0;
  var uvSets = 0;
  var jointSets = 0;
  final uvAccessors = <int>{};
  for (final mesh in meshes) {
    final primitives =
        (mesh as Map<String, dynamic>)['primitives'] as List? ?? const [];
    var trianglesInMesh = 0;
    var primitivesInMesh = 0;
    for (final raw in primitives) {
      final primitive = raw as Map<String, dynamic>;
      final mode = (primitive['mode'] as num?)?.toInt() ?? 4;
      if (mode != 4) continue;
      primitiveCount++;
      primitivesInMesh++;
      // Dreiecke je Mesh – daran misst der Roblox-Importer, nicht am
      // ganzen Modell.
      final indices = (primitive['indices'] as num?)?.toInt();
      final attributesRaw =
          primitive['attributes'] as Map<String, dynamic>? ?? const {};
      final counted = indices != null
          ? _accessorCount(json, indices)
          : _accessorCount(json, (attributesRaw['POSITION'] as num?)
              ?.toInt());
      trianglesInMesh += counted ~/ 3;
      final material = (primitive['material'] as num?)?.toInt();
      if (material != null) materials.add(material);
      final attributes = attributesRaw;
      for (final key in attributes.keys) {
        if (key.startsWith('TEXCOORD_')) {
          final index = int.tryParse(key.substring(9)) ?? 0;
          if (index + 1 > uvSets) uvSets = index + 1;
          if (index == 0) uvAccessors.add(attributes[key] as int);
        }
        if (key.startsWith('JOINTS_')) {
          final index = int.tryParse(key.substring(7)) ?? 0;
          if (index + 1 > jointSets) jointSets = index + 1;
        }
      }
    }
    if (primitivesInMesh == 0) continue;
    meshTriangles.add(trianglesInMesh);
    meshNames.add((mesh['name'] as String?) ?? '');
    if (primitivesInMesh > maxPrimitivesPerMesh) {
      maxPrimitivesPerMesh = primitivesInMesh;
    }
  }

  // UV-Spanne aus den tatsächlichen Werten – nur so fällt eine
  // kachelnde Textur auf.
  var uvMin = 0.0, uvMax = 0.0;
  var first = true;
  for (final accessor in uvAccessors) {
    final values = readGltfFloats(json, bin, accessor);
    for (final value in values) {
      if (first) {
        uvMin = value;
        uvMax = value;
        first = false;
      } else if (value < uvMin) {
        uvMin = value;
      } else if (value > uvMax) {
        uvMax = value;
      }
    }
  }

  final textures = <RobloxTexture>[];
  for (final raw in json['images'] as List? ?? const []) {
    final image = raw as Map<String, dynamic>;
    final view = (image['bufferView'] as num?)?.toInt();
    if (view == null) continue;
    final bytes = gltfBufferViewBytes(json, bin, view);
    final size = imageDimensions(bytes);
    if (size == null) continue;
    textures.add(RobloxTexture(size.width, size.height,
        (image['mimeType'] as String?) ?? size.mimeType));
  }

  // Geometrie und Skelett über den Vorschau-Parser – der kennt alle
  // Accessor-Spielarten schon.
  final mesh = await parseGlbForPreview(glb);
  try {
    final check = checkMeshWatertight(mesh.positions, mesh.indices);
    final orientation =
        checkMeshOrientation(mesh.positions, mesh.indices);
    final rig = mesh.rig;
    var maxInfluences = 0;
    var scaled = 0, rotated = 0;
    var rootAtOrigin = true, rootWeighted = false;
    var lowerTorsoAtOrigin = true;
    var rootName = '';
    var boneCount = 0;
    if (rig != null) {
      boneCount = rig.joints.length;
      final weights = rig.vertexWeights;
      for (var v = 0; v * 4 + 3 < weights.length; v++) {
        var count = 0;
        for (var k = 0; k < 4; k++) {
          if (weights[v * 4 + k] > 0.0001) count++;
        }
        if (count > maxInfluences) maxInfluences = count;
      }
      for (final joint in rig.joints) {
        final node = rig.nodes[joint];
        if ((node.scale[0] - 1).abs() > 0.001 ||
            (node.scale[1] - 1).abs() > 0.001 ||
            (node.scale[2] - 1).abs() > 0.001) {
          scaled++;
        }
        if (node.rotation[0].abs() > 0.001 ||
            node.rotation[1].abs() > 0.001 ||
            node.rotation[2].abs() > 0.001 ||
            (node.rotation[3].abs() - 1).abs() > 0.001) {
          rotated++;
        }
      }
      // LowerTorso: Weltlage über die Elternkette aufsummiert. Das
      // stimmt, solange keine Drehungen im Baum stehen – und die
      // meldet die Prüfung ohnehin gesondert.
      final torso = rig.jointNames.indexOf('LowerTorso');
      if (torso >= 0) {
        var x = 0.0, y = 0.0, z = 0.0;
        var slot = torso;
        for (var guard = 0; slot >= 0 && guard <= rig.joints.length; guard++) {
          final node = rig.nodes[rig.joints[slot]];
          x += node.translation[0];
          y += node.translation[1];
          z += node.translation[2];
          slot = rig.jointParents[slot];
        }
        lowerTorsoAtOrigin =
            x.abs() < 0.05 && y.abs() < 0.05 && z.abs() < 0.05;
      }
      final rootSlot = rig.jointParents.indexOf(-1);
      if (rootSlot >= 0) {
        final node = rig.nodes[rig.joints[rootSlot]];
        rootName = node.name;
        rootAtOrigin = node.translation[0].abs() < 0.001 &&
            node.translation[1].abs() < 0.001 &&
            node.translation[2].abs() < 0.001;
        final joints = rig.vertexJoints;
        for (var i = 0; i < joints.length && !rootWeighted; i++) {
          if (joints[i] == rootSlot && weights[i] > 0.0001) {
            rootWeighted = true;
          }
        }
      }
    }
    return RobloxFacts(
      triangles: mesh.triangleCount,
      meshCount: meshTriangles.length,
      meshTriangles: meshTriangles,
      meshNames: meshNames,
      maxPrimitivesPerMesh:
          maxPrimitivesPerMesh == 0 ? 1 : maxPrimitivesPerMesh,
      size: orientation.size,
      reversedEdges: orientation.reversedEdges,
      signedVolume: orientation.signedVolume,
      volumeRatio: orientation.volumeRatio,
      degenerateTriangles: orientation.degenerateTriangles,
      primitiveCount: primitiveCount,
      materialCount: materials.length,
      uvSets: uvSets,
      uvMin: uvMin,
      uvMax: uvMax,
      openEdges: check.openEdges,
      rawOpenEdges: check.rawOpenEdges,
      partVolumes: orientation.partVolumes,
      textures: textures,
      jointSets: jointSets,
      boneCount: boneCount,
      maxInfluences: maxInfluences,
      scaledBones: scaled,
      rotatedBones: rotated,
      rootAtOrigin: rootAtOrigin,
      lowerTorsoAtOrigin: lowerTorsoAtOrigin,
      rootWeighted: rootWeighted,
      rootName: rootName,
      boneNames: rig == null ? const [] : rig.jointNames,
    );
  } finally {
    mesh.dispose();
  }
}

/// Anzahl der Elemente eines Accessors – für die Dreieckszahl reicht
/// der Kopf, die Daten müssen dafür nicht gelesen werden.
int _accessorCount(Map<String, dynamic> json, int? accessor) {
  if (accessor == null) return 0;
  final list = json['accessors'] as List?;
  if (list == null || accessor >= list.length) return 0;
  return ((list[accessor] as Map<String, dynamic>)['count'] as num?)
          ?.toInt() ??
      0;
}

/// Liest Breite, Höhe und Typ aus den ersten Bytes eines PNG- oder
/// JPEG-Bildes. Reicht für die Größenprüfung – das Bild muss dafür
/// nicht dekodiert werden (und die Prüfung läuft dadurch auch ohne
/// Grafik-Backend).
({int width, int height, String mimeType})? imageDimensions(
    Uint8List bytes) {
  if (bytes.length > 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final data = ByteData.sublistView(bytes);
    return (
      width: data.getUint32(16),
      height: data.getUint32(20),
      mimeType: 'image/png',
    );
  }
  if (bytes.length > 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      // SOF0…SOF15 tragen die Bildmaße; DHT/DAC/RST/SOS nicht.
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      final data = ByteData.sublistView(bytes);
      if (isSof) {
        return (
          width: data.getUint16(offset + 7),
          height: data.getUint16(offset + 5),
          mimeType: 'image/jpeg',
        );
      }
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD9)) {
        offset += 2;
        continue;
      }
      offset += 2 + data.getUint16(offset + 2);
    }
  }
  return null;
}

/// Kurzfassung der Plattformregeln für die Oberfläche.
String robloxRulesSummary(RobloxTarget target) =>
    'Die Grenzen des Importers: höchstens ${_n(target.hardTriangles)} '
    'Dreiecke je Mesh (Arbeitsziel unter ${_n(target.goalTriangles)}), '
    'genau ein Material je Mesh, ein UV-Satz im 0–1-Raum, Texturen bis '
    '$robloxMaxTexture×$robloxMaxTexture (PNG, JPG, TGA, BMP), '
    'wasserdicht ohne Löcher, Rückseiten und Nullstärke. Bei gerigten '
    'Figuren zusätzlich: T-Pose, Bones mit Scale 1,1,1 und Rotation '
    '0,0,0, Wurzelknochen bei 0,0,0 ohne Einflüsse und höchstens '
    '$robloxMaxInfluences Bones je Vertex. Formate: .fbx (Standard für '
    'Rigs), .gltf/.glb, .obj (nur einfache statische Props).';
