/// Export-Presets: drei Wege aus dem Viewer heraus, jeder mit einem
/// Grund.
///
/// Bisher stand im Export-Menü eine Liste von Formaten. Was in welchem
/// Fall das richtige ist, musste man wissen. Diese Datei macht daraus
/// **Presets**: Format, Beiwerk und Vorbereitung in einem, mit einem
/// Satz dazu, wofür es gedacht ist.
///
/// Dazu die Vorbereitung, die Roblox erwartet und die sonst niemand
/// macht: Transformationen eingefroren, Nullpunkt unter der Figur,
/// +Y oben, +Z nach vorn, eine Einheit gleich ein Stud – und ein
/// Dateiname, der sich nicht erst ausdenken lässt.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'auto_rig.dart' show estimateFrontSign;
import 'glb_preview.dart' show splitGlb, joinGlb, readGltfFloats;

/// Das Dateiformat hinter einem Preset.
enum ExportFormat { fbx, glb, obj }

/// Ein Preset: Format plus der Grund, warum man es nimmt.
class ExportPreset {
  const ExportPreset({
    required this.id,
    required this.format,
    required this.label,
    required this.purpose,
    required this.extension,
    required this.mimeType,
    required this.carriesRig,
    required this.textureInFile,
    this.textureSidecar = false,
  });

  final String id;
  final ExportFormat format;

  /// Kurzname für das Menü.
  final String label;

  /// Wofür dieses Preset gedacht ist – ein Satz, der die Wahl abnimmt.
  final String purpose;

  final String extension;
  final String mimeType;

  /// Ob ein Skelett samt Gewichten mitgeht.
  final bool carriesRig;

  /// Ob die Textur **in** der Datei steckt.
  final bool textureInFile;

  /// Ob die Textur als eigene Datei danebengelegt wird.
  final bool textureSidecar;
}

/// FBX für gerigte Figuren – der Regelfall für Roblox.
const ExportPreset presetFbxRigged = ExportPreset(
  id: 'fbx_rig',
  format: ExportFormat.fbx,
  label: 'FBX für Roblox Studio',
  purpose: 'Gerigte Figuren und Accessoires. Skelett, Gewichte und '
      'Bindepose gehen mit; die Textur liegt als PNG daneben, weil FBX '
      'Bilder nicht einbettet und Roblox sie ohnehin getrennt hochlädt.',
  extension: 'fbx',
  mimeType: 'application/octet-stream',
  carriesRig: true,
  textureInFile: false,
  textureSidecar: true,
);

/// GLB mit allem drin – eine Datei, die überall aufgeht.
const ExportPreset presetGlbTextured = ExportPreset(
  id: 'glb_tex',
  format: ExportFormat.glb,
  label: 'GLB mit eingebetteten Texturen',
  purpose: 'Eine einzige Datei mit Netz, Textur und Skelett – für die '
      'eigene Ablage, für Blender und für jedes Werkzeug, das glTF '
      'liest. Studio nimmt sie auch, hat dabei aber schwächere '
      'Rig-Unterstützung als bei FBX.',
  extension: 'glb',
  mimeType: 'model/gltf-binary',
  carriesRig: true,
  textureInFile: true,
);

/// OBJ für statische Requisiten.
const ExportPreset presetObjStatic = ExportPreset(
  id: 'obj_prop',
  format: ExportFormat.obj,
  label: 'OBJ für statische Props',
  purpose: 'Kisten, Möbel, Deko – alles ohne Skelett. OBJ kennt weder '
      'Knochen noch Animation und trägt Farben nur als Vertexfarben; '
      'genau deshalb ist es für unbewegte Teile das schlankeste '
      'Format.',
  extension: 'obj',
  mimeType: 'model/obj',
  carriesRig: false,
  textureInFile: false,
);

/// Alle Presets in der Reihenfolge, in der sie im Menü stehen.
const List<ExportPreset> exportPresets = [
  presetFbxRigged,
  presetGlbTextured,
  presetObjStatic,
];

/// Das Preset zu einer Kennung – unbekannt heißt GLB, weil das am
/// wenigsten wegwirft.
ExportPreset exportPresetById(String? id) {
  for (final preset in exportPresets) {
    if (preset.id == id) return preset;
  }
  return presetGlbTextured;
}

/// Der Vorschlag zu einem Modell.
///
/// Ein Skelett entscheidet: Es geht nur durch FBX oder GLB, und für
/// Roblox ist FBX der Weg mit der besseren Rig-Unterstützung. Ohne
/// Skelett ist OBJ das ehrlichste Format – es verspricht nichts, was
/// nicht da ist.
ExportPreset recommendedPreset({
  required bool hasRig,
  required bool forRoblox,
}) {
  if (hasRig) return forRoblox ? presetFbxRigged : presetGlbTextured;
  return forRoblox ? presetObjStatic : presetGlbTextured;
}

// --- Namensgebung ----------------------------------------------------

/// Macht aus einem beliebigen Titel einen Dateinamen-Stamm.
///
/// Warum überhaupt: Der Titel eines Laufs ist oft der ganze Prompt –
/// mit Kommas, Anführungszeichen und Zeilenumbrüchen. Als Dateiname
/// ist das unbrauchbar, und unter Windows scheitert das Speichern
/// daran ganz. Umlaute werden ausgeschrieben statt entfernt, damit aus
/// „Kapuze" nicht „Kapze" wird.
String exportBaseName(String raw, {String fallback = 'modell'}) {
  const ersatz = {
    'ä': 'ae', 'ö': 'oe', 'ü': 'ue',
    'Ä': 'Ae', 'Ö': 'Oe', 'Ü': 'Ue',
    'ß': 'ss', 'é': 'e', 'è': 'e', 'ê': 'e', 'á': 'a', 'à': 'a',
    'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ç': 'c',
  };
  final buffer = StringBuffer();
  for (final zeichen in raw.trim().split('')) {
    final gemappt = ersatz[zeichen];
    if (gemappt != null) {
      buffer.write(gemappt);
    } else if (RegExp(r'[A-Za-z0-9]').hasMatch(zeichen)) {
      buffer.write(zeichen);
    } else {
      buffer.write('_');
    }
  }
  var name = buffer
      .toString()
      .replaceAll(RegExp('_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (name.isEmpty) return fallback;
  // Lang genug, um etwas zu sagen, kurz genug für jeden Dateidialog.
  if (name.length > 40) {
    name = name.substring(0, 40).replaceAll(RegExp(r'_+$'), '');
  }
  return name;
}

/// Der vollständige Dateiname für einen Export.
///
/// Aufbau: `stamm_JJJJMMTT-HHMM.endung`. Der Zeitstempel steht hinten,
/// weil dann die alphabetische Sortierung im Ordner auch die
/// zeitliche ist – bei mehreren Anläufen am selben Modell ist genau
/// das, was man sucht.
String exportFileName(ExportPreset preset, String title,
    {DateTime? now, String? suffix}) {
  final zeit = now ?? DateTime.now();
  String zwei(int v) => v.toString().padLeft(2, '0');
  final stempel = '${zeit.year}${zwei(zeit.month)}${zwei(zeit.day)}'
      '-${zwei(zeit.hour)}${zwei(zeit.minute)}';
  final stamm = exportBaseName(title);
  final anhang = suffix == null ? '' : '_$suffix';
  return '$stamm$anhang' '_$stempel.${preset.extension}';
}

// --- Vorbereitung ----------------------------------------------------

/// Wohin der Nullpunkt soll.
enum PivotMode {
  /// Mittig unter das Modell – die Figur steht auf y = 0. Das ist die
  /// Roblox-Erwartung: Ein Charakter wird an den Füßen platziert.
  fuesse,

  /// In die Mitte des umschließenden Quaders – richtig für Teile, die
  /// um sich selbst drehen (Räder, Deckel).
  mitte,

  /// Nichts anfassen.
  unveraendert,
}

/// Ein Schritt der Vorbereitung.
class ExportStep {
  const ExportStep(this.title, this.detail, {this.changed = false});
  final String title;
  final String detail;
  final bool changed;
}

class ExportPrepReport {
  const ExportPrepReport(this.steps);
  final List<ExportStep> steps;

  bool get changed => steps.any((s) => s.changed);

  String get text => [
        'Export-Vorbereitung',
        for (final s in steps) '${s.changed ? '✔' : '–'} ${s.title}: ${s.detail}',
      ].join('\n');
}

class ExportPrepResult {
  const ExportPrepResult(this.glb, this.report);
  final Uint8List glb;
  final ExportPrepReport report;
}

/// Bringt eine GLB in die Lage, die Roblox erwartet.
///
/// Vier Dinge, und für jedes gibt es einen Grund:
///
/// * **Transformationen einfrieren.** Eine Skalierung am Wurzelknoten
///   ist glTF-korrekt, aber jeder Importer geht anders damit um. Steht
///   sie in den Punkten, kann sich niemand mehr vertun.
/// * **Nullpunkt.** Roblox setzt ein Modell an seinem Ursprung ab.
///   Liegt der irgendwo neben der Figur, schwebt sie oder steckt im
///   Boden.
/// * **Achsen.** +Y oben ist in glTF Gesetz und wird nur nachgeprüft.
///   Die Blickrichtung dagegen kommt aus der Geometrie und stimmt bei
///   Bild→3D-Modellen oft nicht – das steht dann im Bericht.
/// * **Maßstab.** Der Roblox-Importer setzt einen Meter gleich einem
///   Stud. Die Höhe in glTF-Einheiten ist damit die Höhe in Studs, und
///   der Bericht nennt sie.
///
/// Bei einem Modell **mit Skelett** wird bewusst weniger angefasst:
/// Die Punkte liegen dort in Bindestellung, und die Gelenke rechnen
/// über die inversen Bindematrizen darauf. Verschiebt man nur eine der
/// beiden Seiten, reißt die Haut. Deshalb wird eine gleichmäßige
/// Skalierung in **alle drei** Seiten gerechnet (Punkte, Gelenke,
/// Bindematrizen) – und alles andere bleibt stehen, mit Begründung im
/// Bericht.
ExportPrepResult prepareForExport(
  Uint8List glb, {
  PivotMode pivot = PivotMode.fuesse,
  bool freezeTransforms = true,
}) {
  final parts = splitGlb(glb);
  final json = parts.json;
  var bin = Uint8List.fromList(parts.bin);
  final steps = <ExportStep>[];
  final hatSkelett = ((json['skins'] as List?) ?? const []).isNotEmpty;
  var veraendert = false;

  // --- 1. Einfrieren -------------------------------------------------
  if (freezeTransforms) {
    final skala = _rootUniformScale(json);
    if (skala == null) {
      steps.add(const ExportStep(
          'Transformationen',
          'Über der Szene steht mehr als eine gleichmäßige Skalierung '
          '(Drehung, Verschiebung oder ungleiche Achsen). Das wird '
          'nicht eingerechnet – bei einem Skelett verschöbe es die '
          'Bindepose, und ohne Skelett ließe es sich nicht sauber '
          'zurückrechnen.'));
    } else if ((skala - 1).abs() < 1e-6) {
      steps.add(const ExportStep('Transformationen',
          'Keine Skalierung über der Szene – schon eingefroren.'));
    } else {
      _bakeUniformScale(json, bin, skala);
      steps.add(ExportStep(
          'Transformationen',
          'Skalierung ${skala.toStringAsFixed(3)} in die Punkte '
          '${hatSkelett ? ', Gelenke und Bindematrizen ' : ''}gerechnet '
          'und vom Wurzelknoten genommen.',
          changed: true));
      veraendert = true;
    }
  }

  // --- 2. Nullpunkt ---------------------------------------------------
  final bounds = _bounds(json, bin);
  if (pivot == PivotMode.unveraendert || bounds == null) {
    steps.add(ExportStep(
        'Nullpunkt',
        bounds == null
            ? 'Keine Geometrie gefunden.'
            : 'Auf Wunsch unverändert gelassen.'));
  } else {
    final ziel = switch (pivot) {
      PivotMode.fuesse => [
          (bounds.minX + bounds.maxX) / 2,
          bounds.minY,
          (bounds.minZ + bounds.maxZ) / 2,
        ],
      _ => [
          (bounds.minX + bounds.maxX) / 2,
          (bounds.minY + bounds.maxY) / 2,
          (bounds.minZ + bounds.maxZ) / 2,
        ],
    };
    final weit = ziel.fold<double>(0, (m, v) => math.max(m, v.abs()));
    if (weit < 1e-4) {
      steps.add(ExportStep('Nullpunkt',
          'Liegt schon ${pivot == PivotMode.fuesse ? 'unter' : 'in'} '
          'der Mitte des Modells.'));
    } else {
      _translate(json, bin, -ziel[0], -ziel[1], -ziel[2]);
      steps.add(ExportStep(
          'Nullpunkt',
          '${pivot == PivotMode.fuesse ? 'Mittig unter das Modell' : 'In die '
              'Mitte des Modells'} gelegt (verschoben um '
          '${ziel.map((v) => v.toStringAsFixed(3)).join(' / ')}).',
          changed: true));
      veraendert = true;
    }
  }

  // --- 3. Achsen ------------------------------------------------------
  steps.add(const ExportStep('Hochachse',
      '+Y oben – das schreibt die glTF-Spezifikation vor, und der '
      'Roblox-Importer erwartet genau das.'));
  final positionen = _allPositions(json, bin);
  if (positionen.isEmpty) {
    steps.add(const ExportStep(
        'Blickrichtung', 'Keine Geometrie zum Messen.'));
  } else if (estimateFrontSign(positionen) >= 0) {
    steps.add(const ExportStep('Blickrichtung',
        'Das Modell schaut nach +Z – so will es Roblox.'));
  } else {
    steps.add(const ExportStep(
        'Blickrichtung',
        'Das Modell schaut nach −Z, Roblox erwartet +Z. Gedreht wird '
        'hier nichts: Bei einem Skelett müssten Gelenke und Netz '
        'gemeinsam gedreht werden. Im Viewer gibt es dafür die '
        '90°-Knöpfe – zweimal um die Y-Achse.'));
  }

  // --- 4. Maßstab -----------------------------------------------------
  if (bounds != null) {
    final hoehe = bounds.maxY - bounds.minY;
    steps.add(ExportStep(
        'Maßstab',
        'Eine Einheit ist ein Stud: Der Importer setzt einen Meter '
        'gleich einem Stud. Das Modell misst '
        '${hoehe.toStringAsFixed(2)} Studs in der Höhe '
        '(ein Standard-Charakter misst 5).'));
  }

  return ExportPrepResult(
    veraendert ? joinGlb(json, bin) : glb,
    ExportPrepReport(steps),
  );
}

// --- Kleinarbeit -----------------------------------------------------

typedef _Bounds = ({
  double minX,
  double maxX,
  double minY,
  double maxY,
  double minZ,
  double maxZ,
});

/// Die gleichmäßige Skalierung über der Szene – oder null, wenn dort
/// etwas anderes steht.
double? _rootUniformScale(Map<String, dynamic> json) {
  final nodes = (json['nodes'] as List?) ?? const [];
  final scenes = (json['scenes'] as List?) ?? const [];
  if (nodes.isEmpty || scenes.isEmpty) return 1;
  final sceneIndex = (json['scene'] as num?)?.toInt() ?? 0;
  if (sceneIndex >= scenes.length) return 1;
  final roots =
      ((scenes[sceneIndex] as Map)['nodes'] as List?)?.cast<num>() ??
          const [];
  if (roots.length != 1) return roots.isEmpty ? 1 : null;
  final root = nodes[roots.first.toInt()] as Map<String, dynamic>;
  if (root.containsKey('matrix')) return null;
  if (root.containsKey('rotation')) {
    final r = (root['rotation'] as List).cast<num>();
    // Einheitsquaternion heißt: keine Drehung.
    if (r.length == 4 && (r[3].abs() - 1).abs() > 1e-6) return null;
  }
  if (root.containsKey('translation')) {
    final t = (root['translation'] as List).cast<num>();
    if (t.any((v) => v.abs() > 1e-9)) return null;
  }
  final s = (root['scale'] as List?)?.cast<num>();
  if (s == null) return 1;
  if ((s[0] - s[1]).abs() > 1e-6 || (s[1] - s[2]).abs() > 1e-6) return null;
  return s[0].toDouble();
}

/// Rechnet eine gleichmäßige Skalierung in Punkte, Gelenke und
/// Bindematrizen und nimmt sie vom Wurzelknoten.
///
/// Warum das aufgeht: Skaliert man die ganze Szene mit S, wird aus
/// jeder Gelenk-Weltmatrix M die Matrix S·M und aus jeder inversen
/// Bindematrix IBM die Matrix S·IBM·S⁻¹. Für [R|t] ist das [R|S·t] –
/// nur die Verschiebungsspalte ändert sich, die Drehung bleibt. Genau
/// deshalb reicht es, Punkte und Verschiebungen zu skalieren.
void _bakeUniformScale(
    Map<String, dynamic> json, Uint8List bin, double scale) {
  for (final index in _positionAccessors(json)) {
    _mapFloats(json, bin, index, (values) {
      for (var i = 0; i < values.length; i++) {
        values[i] *= scale;
      }
    });
    final accessor = (json['accessors'] as List)[index] as Map;
    for (final key in ['min', 'max']) {
      final werte = (accessor[key] as List?)?.cast<num>();
      if (werte != null) accessor[key] = [for (final v in werte) v * scale];
    }
  }

  // Gelenke: nur die Verschiebung, nicht die Drehung.
  final joints = _jointNodes(json);
  for (final index in joints) {
    final node = (json['nodes'] as List)[index] as Map<String, dynamic>;
    final t = (node['translation'] as List?)?.cast<num>();
    if (t != null) node['translation'] = [for (final v in t) v * scale];
  }

  // Inverse Bindematrizen: die vierte Spalte, also die Elemente 12..14.
  for (final skin in (json['skins'] as List?) ?? const []) {
    final index = ((skin as Map)['inverseBindMatrices'] as num?)?.toInt();
    if (index == null) continue;
    _mapFloats(json, bin, index, (values) {
      for (var m = 0; m + 15 < values.length; m += 16) {
        values[m + 12] *= scale;
        values[m + 13] *= scale;
        values[m + 14] *= scale;
      }
    });
  }

  final scenes = (json['scenes'] as List?) ?? const [];
  final sceneIndex = (json['scene'] as num?)?.toInt() ?? 0;
  if (scenes.isEmpty || sceneIndex >= scenes.length) return;
  final roots =
      ((scenes[sceneIndex] as Map)['nodes'] as List?)?.cast<num>() ??
          const [];
  if (roots.length != 1) return;
  ((json['nodes'] as List)[roots.first.toInt()] as Map).remove('scale');
}

/// Verschiebt Punkte und – falls vorhanden – Gelenke und
/// Bindematrizen um denselben Betrag.
///
/// Für die Bindematrix gilt: Wandert die Welt um T, wird aus IBM die
/// Matrix IBM·Translate(−T); die Verschiebungsspalte wird also
/// t − R·T. Die Drehung R steht in den Elementen 0..10.
void _translate(Map<String, dynamic> json, Uint8List bin, double dx,
    double dy, double dz) {
  for (final index in _positionAccessors(json)) {
    _mapFloats(json, bin, index, (values) {
      for (var i = 0; i + 2 < values.length; i += 3) {
        values[i] += dx;
        values[i + 1] += dy;
        values[i + 2] += dz;
      }
    });
    final accessor = (json['accessors'] as List)[index] as Map;
    for (final key in ['min', 'max']) {
      final werte = (accessor[key] as List?)?.cast<num>();
      if (werte != null && werte.length == 3) {
        accessor[key] = [werte[0] + dx, werte[1] + dy, werte[2] + dz];
      }
    }
  }

  // Ohne Skelett ist die Arbeit hier zu Ende.
  final skins = (json['skins'] as List?) ?? const [];
  if (skins.isEmpty) return;

  // Die Wurzelgelenke wandern mit; ihre Kinder hängen daran und
  // bewegen sich von allein.
  for (final index in _rootJointNodes(json)) {
    final node = (json['nodes'] as List)[index] as Map<String, dynamic>;
    final t = (node['translation'] as List?)?.cast<num>() ??
        const <num>[0, 0, 0];
    node['translation'] = [t[0] + dx, t[1] + dy, t[2] + dz];
  }

  for (final skin in skins) {
    final index = ((skin as Map)['inverseBindMatrices'] as num?)?.toInt();
    if (index == null) continue;
    _mapFloats(json, bin, index, (values) {
      for (var m = 0; m + 15 < values.length; m += 16) {
        // Spaltenweise abgelegt: R steht in 0,1,2 / 4,5,6 / 8,9,10.
        values[m + 12] -= values[m] * dx + values[m + 4] * dy +
            values[m + 8] * dz;
        values[m + 13] -= values[m + 1] * dx + values[m + 5] * dy +
            values[m + 9] * dz;
        values[m + 14] -= values[m + 2] * dx + values[m + 6] * dy +
            values[m + 10] * dz;
      }
    });
  }
}

/// Alle POSITION-Accessoren, jeder nur einmal.
List<int> _positionAccessors(Map<String, dynamic> json) {
  final out = <int>{};
  for (final mesh in (json['meshes'] as List?) ?? const []) {
    for (final prim in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final index =
          ((prim as Map)['attributes'] as Map?)?['POSITION'] as num?;
      if (index != null) out.add(index.toInt());
    }
  }
  return out.toList();
}

/// Alle Knoten, die als Gelenk in einem Skin vorkommen.
Set<int> _jointNodes(Map<String, dynamic> json) {
  final out = <int>{};
  for (final skin in (json['skins'] as List?) ?? const []) {
    for (final joint in ((skin as Map)['joints'] as List?) ?? const []) {
      out.add((joint as num).toInt());
    }
  }
  return out;
}

/// Die Gelenke ohne Gelenk-Elternteil – dort setzt eine Verschiebung an.
List<int> _rootJointNodes(Map<String, dynamic> json) {
  final joints = _jointNodes(json);
  final kind = <int>{};
  for (final index in joints) {
    final node = (json['nodes'] as List)[index] as Map;
    for (final child in (node['children'] as List?) ?? const []) {
      kind.add((child as num).toInt());
    }
  }
  return [for (final j in joints) if (!kind.contains(j)) j];
}

/// Liest einen Kommazahlen-Accessor, lässt ihn ändern und schreibt ihn
/// an derselben Stelle zurück.
///
/// An derselben Stelle heißt: Die Datei wird nicht länger, und kein
/// anderer Accessor verrutscht. Das geht nur, weil sich hier nur Werte
/// ändern, nie ihre Zahl.
void _mapFloats(Map<String, dynamic> json, Uint8List bin, int index,
    void Function(Float32List) aendern) {
  final accessor = (json['accessors'] as List)[index] as Map<String, dynamic>;
  if (accessor['componentType'] != 5126) return;
  final viewIndex = (accessor['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return;
  final view =
      (json['bufferViews'] as List)[viewIndex] as Map<String, dynamic>;
  final count = (accessor['count'] as num).toInt();
  final teile = switch (accessor['type']) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    'MAT4' => 16,
    _ => 0,
  };
  if (teile == 0) return;
  final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final stride = (view['byteStride'] as num?)?.toInt() ?? teile * 4;
  final data = ByteData.sublistView(bin);
  final werte = Float32List(count * teile);
  for (var i = 0; i < count; i++) {
    for (var k = 0; k < teile; k++) {
      werte[i * teile + k] =
          data.getFloat32(start + i * stride + k * 4, Endian.little);
    }
  }
  aendern(werte);
  for (var i = 0; i < count; i++) {
    for (var k = 0; k < teile; k++) {
      data.setFloat32(start + i * stride + k * 4, werte[i * teile + k],
          Endian.little);
    }
  }
}

List<Float32List> _allPositions(Map<String, dynamic> json, Uint8List bin) => [
      for (final index in _positionAccessors(json))
        readGltfFloats(json, bin, index),
    ];

_Bounds? _bounds(Map<String, dynamic> json, Uint8List bin) {
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  var gesehen = false;
  for (final positions in _allPositions(json, bin)) {
    for (var i = 0; i + 2 < positions.length; i += 3) {
      gesehen = true;
      minX = math.min(minX, positions[i]);
      maxX = math.max(maxX, positions[i]);
      minY = math.min(minY, positions[i + 1]);
      maxY = math.max(maxY, positions[i + 1]);
      minZ = math.min(minZ, positions[i + 2]);
      maxZ = math.max(maxZ, positions[i + 2]);
    }
  }
  if (!gesehen) return null;
  return (
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
    minZ: minZ,
    maxZ: maxZ
  );
}
