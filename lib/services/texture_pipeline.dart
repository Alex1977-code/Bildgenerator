/// Die Textur-Pipeline: was zwischen einem Netz aus der KI und einem
/// Modell liegt, das Roblox annimmt.
///
/// Der Preflight nennt diese Punkte schon lange – Texturen zu groß,
/// mehr als ein UV-Satz, UVs außerhalb von 0–1, mehrere Materialien
/// in einem Mesh. Bisher stand dort nur, was falsch ist. Diese Datei
/// bringt es in Ordnung, so weit sich das **ohne Ratespiel** rechnen
/// lässt; wo das nicht geht, sagt der Bericht warum, statt etwas
/// kaputtzumachen.
///
/// Vier Schritte, jeder einzeln abschaltbar:
///
/// * **Verkleinern** – über `shrinkGlbTextures`, unverändert.
/// * **Ein UV-Satz** – `TEXCOORD_1` und höher fliegen aus den
///   Teilnetzen. Studio liest ohnehin nur den ersten.
/// * **UVs in den 0–1-Raum** – aber nur durch Verschieben um **ganze
///   Zahlen**. Unter der Wiederholung (`REPEAT`, der glTF-Standard)
///   ist das bildgleich: u = 1,3 und u = 0,3 treffen dasselbe Pixel.
///   Jede andere Verschiebung oder gar eine Skalierung würde die
///   Textur verrutschen lassen – das passiert hier nicht.
/// * **Ein Material je Mesh** – Teilnetze mit demselben Material
///   werden zusammengelegt. Verschiedene Materialien lassen sich nur
///   über einen Textur-Atlas vereinen; das sagt der Bericht, statt es
///   heimlich zu versuchen.
///
/// Dazu die **Hautton-Option**: siehe [makeSkinToneReady].
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'glb_preview.dart' show splitGlb, joinGlb, gltfBufferViewBytes;
import 'glb_textures.dart';

/// Ein Schritt der Pipeline im Bericht.
class TextureStep {
  const TextureStep(this.title, this.detail, {this.changed = false});

  final String title;

  /// Was genau passiert ist – oder warum nichts passiert ist.
  final String detail;

  /// Ob dieser Schritt die Datei verändert hat.
  final bool changed;
}

/// Was die Pipeline getan hat.
class TexturePipelineReport {
  const TexturePipelineReport({
    required this.steps,
    required this.bytesBefore,
    required this.bytesAfter,
  });

  final List<TextureStep> steps;
  final int bytesBefore;
  final int bytesAfter;

  bool get changed => steps.any((s) => s.changed);

  /// Der Bericht als Klartext – für den Nachweis und die Zwischenablage.
  String get text {
    final zeilen = <String>['Textur-Pipeline'];
    for (final s in steps) {
      zeilen.add('${s.changed ? '✔' : '–'} ${s.title}: ${s.detail}');
    }
    zeilen.add('Dateigröße: $bytesBefore → $bytesAfter Bytes');
    return zeilen.join('\n');
  }
}

class TexturePipelineResult {
  const TexturePipelineResult(this.glb, this.report);
  final Uint8List glb;
  final TexturePipelineReport report;
}

/// Führt die Pipeline aus.
Future<TexturePipelineResult> runTexturePipeline(
  Uint8List glb, {
  int maxTextureSize = 1024,
  bool shrinkTextures = true,
  bool singleUvSet = true,
  bool uvIntoUnitSquare = true,
  bool mergePrimitives = true,
}) async {
  final bytesBefore = glb.length;
  final steps = <TextureStep>[];
  var aktuell = glb;

  if (shrinkTextures) {
    final result = await shrinkGlbTextures(aktuell, maxSize: maxTextureSize);
    aktuell = result.glb;
    if (result.changed.isEmpty) {
      steps.add(TextureStep(
          'Texturgröße',
          result.untouched == 0
              ? 'Keine eingebettete Textur gefunden.'
              : '${result.untouched} Bild(er) waren schon '
                  'höchstens ${maxTextureSize}px groß.'));
    } else {
      final erstes = result.changed.first;
      steps.add(TextureStep(
          'Texturgröße',
          '${result.changed.length} Bild(er) verkleinert, z. B. '
              '${erstes.fromWidth}×${erstes.fromHeight} auf '
              '${erstes.toWidth}×${erstes.toHeight}.',
          changed: true));
    }
  }

  if (singleUvSet) {
    final entfernt = _dropExtraUvSets(aktuell);
    aktuell = entfernt.$1;
    steps.add(TextureStep(
        'UV-Sätze',
        entfernt.$2 == 0
            ? 'Genau ein Satz – so will es Studio.'
            : '${entfernt.$2} zusätzliche(r) Satz/Sätze aus den '
                'Teilnetzen genommen. Die Zahlen bleiben im Puffer '
                'liegen; der Importer liest sie nicht mehr.',
        changed: entfernt.$2 > 0));
  }

  if (uvIntoUnitSquare) {
    final verschoben = _shiftUvsIntoUnitSquare(aktuell);
    aktuell = verschoben.glb;
    steps.add(TextureStep(
        'UV-Raum',
        verschoben.detail,
        changed: verschoben.shifted > 0));
  }

  if (mergePrimitives) {
    final zusammen = _mergeSameMaterialPrimitives(aktuell);
    aktuell = zusammen.glb;
    steps.add(TextureStep(
        'Material je Mesh', zusammen.detail,
        changed: zusammen.merged > 0));
  }

  return TexturePipelineResult(
    aktuell,
    TexturePipelineReport(
      steps: steps,
      bytesBefore: bytesBefore,
      bytesAfter: aktuell.length,
    ),
  );
}

// --- Ein UV-Satz -----------------------------------------------------

/// Entfernt `TEXCOORD_1` und höher. Gibt die neue Datei und die Zahl
/// der entfernten Verweise zurück.
(Uint8List, int) _dropExtraUvSets(Uint8List glb) {
  final parts = splitGlb(glb);
  final json = parts.json;
  var entfernt = 0;
  for (final mesh in (json['meshes'] as List?) ?? const []) {
    for (final prim in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final attributes = (prim as Map)['attributes'] as Map<String, dynamic>?;
      if (attributes == null) continue;
      final weg = [
        for (final key in attributes.keys)
          if (key.startsWith('TEXCOORD_') && key != 'TEXCOORD_0') key,
      ];
      for (final key in weg) {
        attributes.remove(key);
        entfernt++;
      }
    }
  }
  if (entfernt == 0) return (glb, 0);
  return (joinGlb(json, parts.bin), entfernt);
}

// --- UVs in den 0–1-Raum ---------------------------------------------

/// Das Ergebnis der UV-Verschiebung.
typedef _UvShift = ({Uint8List glb, int shifted, String detail});

/// Verschiebt UV-Sätze um ganze Zahlen in den 0–1-Raum.
///
/// Möglich ist das genau dann, wenn die Spanne höchstens 1 breit ist
/// **und** eine ganze Zahl k existiert mit `max - 1 ≤ k ≤ min`. Sonst
/// liegt die Insel über einer Kachelgrenze, und nur ein neues Auslegen
/// der UVs würde helfen – das ist Handarbeit im 3D-Programm.
_UvShift _shiftUvsIntoUnitSquare(Uint8List glb) {
  final parts = splitGlb(glb);
  final json = parts.json;
  final bin = Uint8List.fromList(parts.bin);
  final accessors = (json['accessors'] as List?) ?? const [];

  final betroffen = <int>{};
  for (final mesh in (json['meshes'] as List?) ?? const []) {
    for (final prim in ((mesh as Map)['primitives'] as List?) ?? const []) {
      final index =
          ((prim as Map)['attributes'] as Map?)?['TEXCOORD_0'] as num?;
      if (index != null) betroffen.add(index.toInt());
    }
  }
  if (betroffen.isEmpty) {
    return (glb: glb, shifted: 0, detail: 'Keine UVs im Modell.');
  }

  var verschoben = 0;
  var schonDrin = 0;
  final unmoeglich = <String>[];
  for (final index in betroffen) {
    if (index < 0 || index >= accessors.length) continue;
    final accessor = accessors[index] as Map<String, dynamic>;
    if (accessor['type'] != 'VEC2' || accessor['componentType'] != 5126) {
      unmoeglich.add('ein UV-Satz liegt nicht als Kommazahlenpaar vor');
      continue;
    }
    final werte = _readVec2(json, bin, index);
    if (werte.isEmpty) continue;
    var uMin = double.infinity, uMax = -double.infinity;
    var vMin = double.infinity, vMax = -double.infinity;
    for (var i = 0; i < werte.length; i += 2) {
      uMin = math.min(uMin, werte[i]);
      uMax = math.max(uMax, werte[i]);
      vMin = math.min(vMin, werte[i + 1]);
      vMax = math.max(vMax, werte[i + 1]);
    }
    if (uMin >= -0.001 &&
        uMax <= 1.001 &&
        vMin >= -0.001 &&
        vMax <= 1.001) {
      schonDrin++;
      continue;
    }
    final ku = _wholeShift(uMin, uMax);
    final kv = _wholeShift(vMin, vMax);
    if (ku == null || kv == null) {
      unmoeglich.add('ein UV-Satz reicht über eine Kachelgrenze '
          '(u ${uMin.toStringAsFixed(2)}–${uMax.toStringAsFixed(2)}, '
          'v ${vMin.toStringAsFixed(2)}–${vMax.toStringAsFixed(2)})');
      continue;
    }
    for (var i = 0; i < werte.length; i += 2) {
      werte[i] -= ku;
      werte[i + 1] -= kv;
    }
    _writeVec2(json, bin, index, werte);
    verschoben++;
  }

  final teile = <String>[];
  if (verschoben > 0) {
    teile.add('$verschoben UV-Satz/Sätze um ganze Zahlen in 0–1 '
        'geschoben – bildgleich, weil die Textur sich wiederholt');
  }
  if (schonDrin > 0) teile.add('$schonDrin Satz/Sätze lagen schon in 0–1');
  if (unmoeglich.isNotEmpty) {
    teile.add('nicht zu retten: ${unmoeglich.join('; ')} – das UV-Layout '
        'muss im 3D-Programm neu gelegt werden');
  }

  return (
    glb: verschoben == 0 ? glb : joinGlb(json, bin),
    shifted: verschoben,
    detail: teile.isEmpty ? 'Nichts zu tun.' : '${teile.join('. ')}.',
  );
}

/// Die ganze Zahl, um die sich die Spanne [lo]–[hi] nach 0–1 schieben
/// lässt – oder null, wenn es keine gibt.
int? _wholeShift(double lo, double hi) {
  // Gesucht: k ganz mit k ≤ lo und hi − k ≤ 1, also hi − 1 ≤ k ≤ lo.
  final k = lo.floor();
  if (k >= hi - 1 - 1e-6) return k;
  return null;
}

// --- Ein Material je Mesh --------------------------------------------

typedef _MergeResult = ({Uint8List glb, int merged, String detail});

/// Legt Teilnetze eines Meshes zusammen, wenn sie dasselbe Material
/// tragen und dieselben Attribute führen.
///
/// Warum nur dann: Beim Zusammenlegen werden die Punktlisten
/// aneinandergehängt und die Indizes verschoben. Das geht nur, wenn
/// beide Seiten dieselben Attribute in derselben Form haben – sonst
/// wüsste das Ergebnis nicht, welche Normale zu welchem Punkt gehört.
/// Und ein gemeinsames Material braucht es, weil Roblox genau eines je
/// Mesh nimmt: zwei verschiedene ließen sich nur über einen
/// Textur-Atlas vereinen, und der gehört ins 3D-Programm.
_MergeResult _mergeSameMaterialPrimitives(Uint8List glb) {
  final parts = splitGlb(glb);
  final json = parts.json;
  final bin = parts.bin;
  final meshes = (json['meshes'] as List?) ?? const [];

  var merged = 0;
  var verschieden = 0;
  final anhang = _Anhaenger(bin.length);

  for (final meshRaw in meshes) {
    final mesh = meshRaw as Map<String, dynamic>;
    final primitives = (mesh['primitives'] as List?) ?? const [];
    if (primitives.length < 2) continue;

    // Nach Material gruppieren, Reihenfolge beibehalten.
    final gruppen = <Object?, List<Map<String, dynamic>>>{};
    for (final p in primitives) {
      final prim = p as Map<String, dynamic>;
      gruppen.putIfAbsent(prim['material'], () => []).add(prim);
    }
    if (gruppen.length > 1) verschieden++;

    final neu = <Map<String, dynamic>>[];
    for (final gruppe in gruppen.values) {
      if (gruppe.length < 2) {
        neu.add(gruppe.first);
        continue;
      }
      final zusammen = _mergeGroup(json, bin, gruppe, anhang);
      if (zusammen == null) {
        neu.addAll(gruppe);
      } else {
        neu.add(zusammen);
        merged += gruppe.length - 1;
      }
    }
    mesh['primitives'] = neu;
  }

  final teile = <String>[];
  if (merged > 0) {
    teile.add('$merged Teilnetz(e) mit gleichem Material zusammengelegt');
  }
  if (verschieden > 0) {
    teile.add('$verschieden Mesh(es) tragen verschiedene Materialien – '
        'die lassen sich nur über einen Textur-Atlas vereinen, und der '
        'gehört ins 3D-Programm');
  }
  if (teile.isEmpty) teile.add('Jedes Mesh hat genau ein Material');

  if (merged == 0) {
    return (glb: glb, merged: 0, detail: '${teile.join('. ')}.');
  }

  final neuerBin = Uint8List(anhang.length)..setRange(0, bin.length, bin);
  var pos = bin.length;
  for (final block in anhang.blocks) {
    neuerBin.setRange(pos, pos + block.length, block);
    pos += block.length;
  }
  (json['buffers'] as List)[0]['byteLength'] = neuerBin.length;
  return (
    glb: joinGlb(json, neuerBin),
    merged: merged,
    detail: '${teile.join('. ')}.',
  );
}

/// Legt eine Gruppe von Teilnetzen zu einem zusammen – oder gibt null
/// zurück, wenn sich das nicht sauber rechnen lässt.
Map<String, dynamic>? _mergeGroup(
  Map<String, dynamic> json,
  Uint8List bin,
  List<Map<String, dynamic>> gruppe,
  _Anhaenger anhang,
) {
  final ersteAttribute = gruppe.first['attributes'] as Map<String, dynamic>?;
  if (ersteAttribute == null) return null;
  final schluessel = ersteAttribute.keys.toList()..sort();
  for (final prim in gruppe) {
    // Nur Dreiecksnetze: Bei Linien oder Streifen hieße das
    // Aneinanderhängen der Indizes etwas anderes.
    if (((prim['mode'] as num?)?.toInt() ?? 4) != 4) return null;
    if (prim['indices'] == null) return null;
    final attribute = prim['attributes'] as Map<String, dynamic>?;
    if (attribute == null) return null;
    final eigene = attribute.keys.toList()..sort();
    if (eigene.join(',') != schluessel.join(',')) return null;
    for (final key in schluessel) {
      final a = _accessor(json, (ersteAttribute[key] as num).toInt());
      final b = _accessor(json, (attribute[key] as num).toInt());
      if (a['type'] != b['type'] ||
          a['componentType'] != b['componentType']) {
        return null;
      }
    }
  }

  final neueAttribute = <String, dynamic>{};
  for (final key in schluessel) {
    final quellen = [
      for (final prim in gruppe)
        ((prim['attributes'] as Map)[key] as num).toInt(),
    ];
    final index = _concatAccessors(json, bin, quellen, anhang);
    if (index == null) return null;
    neueAttribute[key] = index;
  }

  // Indizes: jede Liste um die Zahl der vorher liegenden Punkte
  // verschieben.
  final alleIndizes = <int>[];
  var versatz = 0;
  for (final prim in gruppe) {
    final indices = _readIndices(json, bin, (prim['indices'] as num).toInt());
    for (final i in indices) {
      alleIndizes.add(i + versatz);
    }
    final positionIndex =
        ((prim['attributes'] as Map)['POSITION'] as num).toInt();
    versatz += (_accessor(json, positionIndex)['count'] as num).toInt();
  }
  final indexAccessor =
      _appendIndices(json, alleIndizes, versatz, anhang);

  return <String, dynamic>{
    'attributes': neueAttribute,
    'indices': indexAccessor,
    if (gruppe.first['material'] != null)
      'material': gruppe.first['material'],
    'mode': 4,
  };
}

// --- Hautton ---------------------------------------------------------

/// Was die Hautton-Aufbereitung getan hat.
class SkinToneResult {
  const SkinToneResult(this.glb, this.detail, {this.changed = false});
  final Uint8List glb;
  final String detail;
  final bool changed;
}

/// Macht das Modell **hauttonfähig**.
///
/// Roblox multipliziert die Textur mit der Farbe des Teils – und die
/// Hautfarbe kommt aus dem Avatar-Editor genau über diese Farbe.
/// Steckt der Hautton schon in der Textur, wird er ein zweites Mal
/// eingefärbt: Aus einem hellen Braun und einem dunklen Hautton wird
/// ein sehr dunkles Braun, und der Regler im Editor tut scheinbar
/// nichts Richtiges.
///
/// Deshalb wird die Basisfarbtextur auf **Helligkeit** reduziert und
/// so aufgehellt, dass ihr Mittelwert bei [targetMean] liegt. Multipliziert
/// Roblox dann den gewählten Hautton darauf, kommt genau dieser Ton
/// heraus – mit den Schatten und Falten der Vorlage.
///
/// Der Preis steht im Bericht und ist nicht klein: **die Farben der
/// Textur gehen verloren.** Für eine Figur, deren Farbigkeit aus
/// Kleidung besteht, ist das der falsche Knopf. Deshalb ist es eine
/// Option und keine Stufe der Pipeline.
Future<SkinToneResult> makeSkinToneReady(
  Uint8List glb, {
  double targetMean = 0.78,
}) async {
  final parts = splitGlb(glb);
  final json = parts.json;
  final bin = parts.bin;
  final images = (json['images'] as List?) ?? const [];
  if (images.isEmpty) {
    return SkinToneResult(glb,
        'Das Modell hat keine eingebettete Textur – Roblox färbt das '
        'Mesh dann ohnehin allein über die Hautfarbe ein.');
  }

  final ersetzt = <int, Uint8List>{};
  for (var i = 0; i < images.length; i++) {
    final image = images[i] as Map<String, dynamic>;
    final view = image['bufferView'];
    if (view is! num) continue;
    final bytes = gltfBufferViewBytes(json, bin, view.toInt());
    final grau = await _toNeutralGrey(bytes, targetMean);
    if (grau == null) continue;
    ersetzt[view.toInt()] = grau;
    image['mimeType'] = 'image/png';
  }
  if (ersetzt.isEmpty) {
    return SkinToneResult(glb,
        'Keine der eingebetteten Texturen ließ sich lesen – nichts '
        'geändert.');
  }

  // Basisfarbfaktor auf Weiß: Sonst käme der Hautton doppelt getönt
  // heraus, diesmal über das Material statt über die Textur.
  for (final material in (json['materials'] as List?) ?? const []) {
    final pbr = (material as Map<String, dynamic>)['pbrMetallicRoughness'];
    if (pbr is Map<String, dynamic>) {
      pbr['baseColorFactor'] = [1.0, 1.0, 1.0, 1.0];
    }
  }

  final neu = _repackWithReplacements(json, bin, ersetzt);
  return SkinToneResult(
    neu,
    '${ersetzt.length} Textur(en) auf Helligkeit reduziert und auf '
    'einen Mittelwert von ${(targetMean * 100).round()} % aufgehellt. '
    'Roblox multipliziert den gewählten Hautton darauf – Schatten und '
    'Falten bleiben, die Farben der Vorlage sind weg.',
    changed: true,
  );
}

/// Wandelt ein kodiertes Bild in ein neutrales Graubild um.
Future<Uint8List?> _toNeutralGrey(Uint8List bytes, double targetMean) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width, height = image.height;
    image.dispose();
    codec.dispose();
    if (data == null) return null;
    final pixel = data.buffer.asUint8List();

    // Erst die Helligkeit, dann den Mittelwert messen.
    var summe = 0.0;
    var gezaehlt = 0;
    final grau = Uint8List(pixel.length);
    for (var i = 0; i < pixel.length; i += 4) {
      // Rec. 709 – dieselben Gewichte, mit denen ein Bildschirm
      // Helligkeit empfindet.
      final l = 0.2126 * pixel[i] +
          0.7152 * pixel[i + 1] +
          0.0722 * pixel[i + 2];
      grau[i] = grau[i + 1] = grau[i + 2] = l.round().clamp(0, 255);
      grau[i + 3] = pixel[i + 3];
      if (pixel[i + 3] > 8) {
        summe += l / 255;
        gezaehlt++;
      }
    }
    if (gezaehlt > 0) {
      final mittel = summe / gezaehlt;
      // Aufhellen über eine Gammakurve statt über einen Faktor: Ein
      // Faktor würde helle Stellen abschneiden, die Kurve nicht.
      if (mittel > 0.004 && mittel < 0.996) {
        final gamma = math.log(targetMean) / math.log(mittel);
        final tabelle = Uint8List(256);
        for (var v = 0; v < 256; v++) {
          tabelle[v] =
              (math.pow(v / 255, gamma) * 255).round().clamp(0, 255);
        }
        for (var i = 0; i < grau.length; i += 4) {
          final v = tabelle[grau[i]];
          grau[i] = grau[i + 1] = grau[i + 2] = v;
        }
      }
    }

    final fertig = await _encodePng(grau, width, height);
    return fertig;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _encodePng(Uint8List rgba, int width, int height) async {
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, width, height, ui.PixelFormat.rgba8888, fertig.complete);
  final image = await fertig.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

// --- Puffer-Kleinarbeit ----------------------------------------------

/// Sammelt neue Datenblöcke, die hinten an den Binärteil kommen, und
/// führt Buch über den nächsten freien Versatz.
class _Anhaenger {
  _Anhaenger(this.length);

  /// Länge des Puffers einschließlich aller angehängten Blöcke.
  int length;

  final List<Uint8List> blocks = [];

  /// Hängt einen Block an und gibt seinen Versatz im fertigen Puffer
  /// zurück. Aufgefüllt wird auf 4 Byte – die glTF-Spezifikation
  /// verlangt das für Accessoren, und manche Leser stürzen sonst ab.
  int add(Uint8List block) {
    final offset = length;
    blocks.add(block);
    length += block.length;
    final fuellung = (4 - (block.length % 4)) % 4;
    if (fuellung > 0) {
      blocks.add(Uint8List(fuellung));
      length += fuellung;
    }
    return offset;
  }
}

Map<String, dynamic> _accessor(Map<String, dynamic> json, int index) =>
    (json['accessors'] as List)[index] as Map<String, dynamic>;

int _componentSize(int componentType) => switch (componentType) {
      5120 || 5121 => 1,
      5122 || 5123 => 2,
      _ => 4,
    };

int _componentCount(String type) => switch (type) {
      'SCALAR' => 1,
      'VEC2' => 2,
      'VEC3' => 3,
      'VEC4' => 4,
      'MAT4' => 16,
      _ => 1,
    };

/// Liest einen VEC2-Kommazahlen-Accessor.
Float32List _readVec2(
    Map<String, dynamic> json, Uint8List bin, int index) {
  final accessor = _accessor(json, index);
  final count = (accessor['count'] as num).toInt();
  final viewIndex = (accessor['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return Float32List(0);
  final view = (json['bufferViews'] as List)[viewIndex]
      as Map<String, dynamic>;
  final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final stride = (view['byteStride'] as num?)?.toInt() ?? 8;
  final data = ByteData.sublistView(bin);
  final out = Float32List(count * 2);
  for (var i = 0; i < count; i++) {
    out[i * 2] = data.getFloat32(start + i * stride, Endian.little);
    out[i * 2 + 1] = data.getFloat32(start + i * stride + 4, Endian.little);
  }
  return out;
}

/// Schreibt einen VEC2-Accessor an derselben Stelle zurück.
void _writeVec2(Map<String, dynamic> json, Uint8List bin, int index,
    Float32List werte) {
  final accessor = _accessor(json, index);
  final count = (accessor['count'] as num).toInt();
  final viewIndex = (accessor['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return;
  final view = (json['bufferViews'] as List)[viewIndex]
      as Map<String, dynamic>;
  final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final stride = (view['byteStride'] as num?)?.toInt() ?? 8;
  final data = ByteData.sublistView(bin);
  for (var i = 0; i < count; i++) {
    data.setFloat32(start + i * stride, werte[i * 2], Endian.little);
    data.setFloat32(
        start + i * stride + 4, werte[i * 2 + 1], Endian.little);
  }
  // Der Accessor darf min/max führen; die stimmen jetzt nicht mehr.
  if (accessor.containsKey('min') || accessor.containsKey('max')) {
    var uMin = double.infinity, uMax = -double.infinity;
    var vMin = double.infinity, vMax = -double.infinity;
    for (var i = 0; i < werte.length; i += 2) {
      uMin = math.min(uMin, werte[i]);
      uMax = math.max(uMax, werte[i]);
      vMin = math.min(vMin, werte[i + 1]);
      vMax = math.max(vMax, werte[i + 1]);
    }
    accessor['min'] = [uMin, vMin];
    accessor['max'] = [uMax, vMax];
  }
}

List<int> _readIndices(
    Map<String, dynamic> json, Uint8List bin, int index) {
  final accessor = _accessor(json, index);
  final count = (accessor['count'] as num).toInt();
  final componentType = (accessor['componentType'] as num).toInt();
  final viewIndex = (accessor['bufferView'] as num?)?.toInt();
  if (viewIndex == null) return const [];
  final view = (json['bufferViews'] as List)[viewIndex]
      as Map<String, dynamic>;
  final size = _componentSize(componentType);
  final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
      ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
  final stride = (view['byteStride'] as num?)?.toInt() ?? size;
  final data = ByteData.sublistView(bin);
  return [
    for (var i = 0; i < count; i++)
      switch (componentType) {
        5121 => bin[start + i * stride],
        5123 => data.getUint16(start + i * stride, Endian.little),
        _ => data.getUint32(start + i * stride, Endian.little),
      },
  ];
}

/// Hängt mehrere gleichartige Accessoren hintereinander an den Puffer
/// und legt einen neuen Accessor dafür an.
int? _concatAccessors(
  Map<String, dynamic> json,
  Uint8List bin,
  List<int> quellen,
  _Anhaenger anhang,
) {
  final erste = _accessor(json, quellen.first);
  final type = erste['type'] as String;
  final componentType = (erste['componentType'] as num).toInt();
  final elementSize = _componentSize(componentType) * _componentCount(type);

  var gesamt = 0;
  for (final index in quellen) {
    gesamt += (_accessor(json, index)['count'] as num).toInt();
  }
  final block = Uint8List(gesamt * elementSize);
  var ziel = 0;
  for (final index in quellen) {
    final accessor = _accessor(json, index);
    final count = (accessor['count'] as num).toInt();
    final viewIndex = (accessor['bufferView'] as num?)?.toInt();
    if (viewIndex == null) return null;
    final view = (json['bufferViews'] as List)[viewIndex]
        as Map<String, dynamic>;
    final start = ((view['byteOffset'] as num?)?.toInt() ?? 0) +
        ((accessor['byteOffset'] as num?)?.toInt() ?? 0);
    final stride = (view['byteStride'] as num?)?.toInt() ?? elementSize;
    for (var i = 0; i < count; i++) {
      block.setRange(ziel, ziel + elementSize, bin, start + i * stride);
      ziel += elementSize;
    }
  }

  final offset = _appendBlock(json, block, anhang);
  (json['accessors'] as List).add(<String, dynamic>{
    'bufferView': offset,
    'componentType': componentType,
    'count': gesamt,
    'type': type,
  });
  return (json['accessors'] as List).length - 1;
}

/// Schreibt eine Indexliste in den Puffer und legt den Accessor an.
int _appendIndices(
  Map<String, dynamic> json,
  List<int> indizes,
  int vertexCount,
  _Anhaenger anhang,
) {
  // Über 65.535 Punkte reicht uint16 nicht mehr.
  final breit = vertexCount > 65535;
  final block = Uint8List(indizes.length * (breit ? 4 : 2));
  final data = ByteData.sublistView(block);
  for (var i = 0; i < indizes.length; i++) {
    if (breit) {
      data.setUint32(i * 4, indizes[i], Endian.little);
    } else {
      data.setUint16(i * 2, indizes[i], Endian.little);
    }
  }
  final view = _appendBlock(json, block, anhang);
  (json['accessors'] as List).add(<String, dynamic>{
    'bufferView': view,
    'componentType': breit ? 5125 : 5123,
    'count': indizes.length,
    'type': 'SCALAR',
  });
  return (json['accessors'] as List).length - 1;
}

/// Legt einen bufferView für einen neuen Datenblock an und gibt seinen
/// Index zurück.
int _appendBlock(
    Map<String, dynamic> json, Uint8List block, _Anhaenger anhang) {
  final offset = anhang.add(block);
  (json['bufferViews'] as List).add(<String, dynamic>{
    'buffer': 0,
    'byteOffset': offset,
    'byteLength': block.length,
  });
  return (json['bufferViews'] as List).length - 1;
}

/// Packt den Binärteil neu und ersetzt dabei einzelne bufferViews.
Uint8List _repackWithReplacements(Map<String, dynamic> json,
    Uint8List bin, Map<int, Uint8List> ersetzt) {
  final views = (json['bufferViews'] as List?) ?? const [];
  final blocks = <Uint8List>[];
  var offset = 0;
  for (var i = 0; i < views.length; i++) {
    final view = views[i] as Map<String, dynamic>;
    final daten = ersetzt[i] ?? gltfBufferViewBytes(json, bin, i);
    view['byteOffset'] = offset;
    view['byteLength'] = daten.length;
    blocks.add(daten);
    offset += daten.length;
    final fuellung = (4 - (daten.length % 4)) % 4;
    if (fuellung > 0) {
      blocks.add(Uint8List(fuellung));
      offset += fuellung;
    }
  }
  final neu = Uint8List(offset);
  var pos = 0;
  for (final block in blocks) {
    neu.setRange(pos, pos + block.length, block);
    pos += block.length;
  }
  if ((json['buffers'] as List?)?.isNotEmpty ?? false) {
    (json['buffers'] as List)[0]['byteLength'] = neu.length;
  }
  return joinGlb(json, neu);
}
