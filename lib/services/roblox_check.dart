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

/// Wofür das Modell gedacht ist – davon hängt die Dreiecksgrenze ab.
enum RobloxTarget {
  /// Figur oder Prop im Erlebnis: hart 20.000 Dreiecke je Mesh,
  /// Arbeitsziel unter 10.000.
  character,

  /// UGC-Accessoire (Hut, Rucksack, Haare …): hart 4.000 Dreiecke.
  accessory,
}

extension RobloxTargetLabel on RobloxTarget {
  String get label => switch (this) {
        RobloxTarget.character => 'Figur oder Prop',
        RobloxTarget.accessory => 'UGC-Accessoire',
      };

  /// Grenze, ab der der Importer ablehnt.
  int get hardTriangles => switch (this) {
        RobloxTarget.character => robloxMaxTriangles,
        RobloxTarget.accessory => robloxAccessoryTriangles,
      };

  /// Arbeitsziel – darunter läuft das Modell im Spiel flüssig.
  int get goalTriangles => switch (this) {
        RobloxTarget.character => robloxGoalTriangles,
        RobloxTarget.accessory => robloxAccessoryTriangles,
      };
}

/// Harte Obergrenze des Importers je Mesh.
const int robloxMaxTriangles = 20000;

/// Arbeitsziel für Figuren und Props.
const int robloxGoalTriangles = 10000;

/// Obergrenze für UGC-Accessoires.
const int robloxAccessoryTriangles = 4000;

/// Größte zulässige Texturkante.
const int robloxMaxTexture = 1024;

/// Höchstzahl der Bones, die einen Vertex beeinflussen dürfen.
const int robloxMaxInfluences = 4;

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

  bool get tooLarge =>
      width > robloxMaxTexture || height > robloxMaxTexture;
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
    required this.textures,
    this.jointSets = 0,
    this.boneCount = 0,
    this.maxInfluences = 0,
    this.scaledBones = 0,
    this.rotatedBones = 0,
    this.rootAtOrigin = true,
    this.rootWeighted = false,
    this.rootName = '',
  });

  final int triangles;
  final int meshCount;

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

  /// Hat der Wurzelknochen Einflüsse auf Vertices? (Roblox will keine.)
  final bool rootWeighted;

  final String rootName;

  bool get hasRig => boneCount > 0;
  bool get hasUvs => uvSets > 0;
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
  final hard = target.hardTriangles;
  final goal = target.goalTriangles;
  if (facts.triangles > hard) {
    findings.add(RobloxFinding(
        RobloxLevel.blocker,
        'Dreiecke: ${_n(facts.triangles)}',
        'Über der Grenze von ${_n(hard)} je Mesh – der Importer weist '
            'das Modell ab. Am besten schon bei der Generierung '
            'begrenzen (Meshy „target_polycount", Rodin-Polygonzahl, '
            'Tripo-Face-Limit); nur wenn das nicht reicht, hinterher in '
            'Blender mit „Decimate" nacharbeiten.'));
  } else if (facts.triangles > goal) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Dreiecke: ${_n(facts.triangles)}',
        'Der Import geht durch (Grenze ${_n(hard)}), das Arbeitsziel '
            'liegt aber unter ${_n(goal)}. Darüber kostet jede Instanz '
            'im Erlebnis spürbar Leistung.'));
  } else {
    findings.add(RobloxFinding(
        RobloxLevel.ok,
        'Dreiecke: ${_n(facts.triangles)}',
        'Innerhalb des Arbeitsziels von ${_n(goal)} für '
            '${target.label}.'));
  }

  // 2. Ein Material je Mesh.
  if (facts.materialCount > 1 || facts.primitiveCount > facts.meshCount) {
    findings.add(RobloxFinding(
        RobloxLevel.blocker,
        'Materialien: ${facts.materialCount} in '
            '${facts.primitiveCount} Teilnetzen',
        'Roblox erlaubt genau ein Material je Mesh. Mehrere '
            'Oberflächen müssen in einem Texture-Atlas '
            'zusammengefasst werden (in Blender: Materialien '
            'zusammenlegen, UVs neu packen, eine Textur backen).'));
  } else {
    findings.add(const RobloxFinding(RobloxLevel.ok, 'Ein Material',
        'Genau ein Material je Mesh – so verlangt es der Importer.'));
  }

  // 3. Geschlossene Form.
  if (facts.openEdges > 0) {
    findings.add(RobloxFinding(
        RobloxLevel.warning,
        'Offene Kanten: ${_n(facts.openEdges)}',
        'Das Netz ist nicht wasserdicht. Löcher und einseitige '
            'Flächen werden im Spiel von hinten durchsichtig; '
            'Nullstärke-Flächen flackern. In Blender schließen '
            '(Mesh → Clean Up) oder das Modell dicker generieren.'));
  } else {
    findings.add(const RobloxFinding(RobloxLevel.ok, 'Wasserdicht',
        'Keine offenen Kanten – keine Löcher, keine Rückseiten.'));
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
    if (tooLarge.isNotEmpty) {
      findings.add(RobloxFinding(
          RobloxLevel.blocker,
          'Textur zu groß: $biggest px',
          'Roblox nimmt höchstens $robloxMaxTexture×$robloxMaxTexture. '
              '${tooLarge.length} von ${facts.textures.length} Bildern '
              'liegen darüber – vor dem Hochladen verkleinern (in der '
              'App den Textur-Modus „Atlas 1024" wählen).'));
    } else {
      findings.add(RobloxFinding(
          RobloxLevel.ok,
          'Textur: $biggest px',
          '${facts.textures.length} Bild(er), alle innerhalb von '
              '$robloxMaxTexture×$robloxMaxTexture. Roblox nimmt PNG, '
              'JPG, TGA und BMP – im GLB stecken PNG oder JPEG.'));
    }
  }

  // 6. Skelett.
  if (!facts.hasRig) {
    findings.add(const RobloxFinding(
        RobloxLevel.hint,
        'Ohne Skelett',
        'Beim Import „No Rig" wählen. Für Props und Accessoires ist '
            'das richtig; eine animierbare Figur braucht ein Skelett.'));
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
    } else {
      findings.add(const RobloxFinding(
          RobloxLevel.ok,
          'Wurzelknochen im Ursprung, ohne Gewichte',
          'So erwartet es der Importer.'));
    }
    findings.add(const RobloxFinding(
        RobloxLevel.hint,
        'T-Pose und Rig-Typ von Hand prüfen',
        'Das Modell muss in T-Pose stehen (Arme waagerecht) – das '
            'kann die App nicht messen. Beim Import wählt man R15, '
            'Custom oder No Rig; ein vollwertiger R15-Avatar braucht '
            '15 einzeln benannte Körperteil-Meshes, ein einteiliges '
            'Modell importiert man als „Custom".'));
  }

  // 7. Dateiformat.
  findings.add(const RobloxFinding(
      RobloxLevel.hint,
      'Format: GLB',
      'Roblox nimmt .fbx, .gltf/.glb und .obj. GLB liest Studio '
          'direkt und bringt die Texturen mit, hat aber eingeschränkte '
          'Rig-Unterstützung. Für gerigte Figuren ist FBX der '
          'Standardfall – dafür die GLB in Blender öffnen und als FBX '
          'ausgeben. OBJ passt nur für einfache statische Props.'));

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
  var primitiveCount = 0;
  var uvSets = 0;
  var jointSets = 0;
  final uvAccessors = <int>{};
  for (final mesh in meshes) {
    final primitives =
        (mesh as Map<String, dynamic>)['primitives'] as List? ?? const [];
    for (final raw in primitives) {
      final primitive = raw as Map<String, dynamic>;
      final mode = (primitive['mode'] as num?)?.toInt() ?? 4;
      if (mode != 4) continue;
      primitiveCount++;
      final material = (primitive['material'] as num?)?.toInt();
      if (material != null) materials.add(material);
      final attributes =
          primitive['attributes'] as Map<String, dynamic>? ?? const {};
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
    final rig = mesh.rig;
    var maxInfluences = 0;
    var scaled = 0, rotated = 0;
    var rootAtOrigin = true, rootWeighted = false;
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
      meshCount: meshes.length,
      primitiveCount: primitiveCount,
      materialCount: materials.length,
      uvSets: uvSets,
      uvMin: uvMin,
      uvMax: uvMax,
      openEdges: check.openEdges,
      textures: textures,
      jointSets: jointSets,
      boneCount: boneCount,
      maxInfluences: maxInfluences,
      scaledBones: scaled,
      rotatedBones: rotated,
      rootAtOrigin: rootAtOrigin,
      rootWeighted: rootWeighted,
      rootName: rootName,
    );
  } finally {
    mesh.dispose();
  }
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
