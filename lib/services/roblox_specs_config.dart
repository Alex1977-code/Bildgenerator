/// Die Roblox-Vorgaben aus `assets/roblox_specs.json`.
///
/// Warum als Datei und nicht im Code: Roblox ändert seine Grenzen.
/// Eine Zahl, die im Code steht, altert still – auffallen tut das erst
/// beim abgelehnten Upload. Als Datei lässt sie sich nachziehen, ohne
/// die App neu zu bauen, und jeder Wert trägt seine Quelle und das
/// Datum, an dem zuletzt nachgesehen wurde. Sind die Daten älter als
/// `maxAgeDays`, sagt die App das beim Start.
///
/// Die Konstanten in `roblox_spec.dart` bleiben als **Rückfall**: Ist
/// die Datei kaputt oder fehlt sie, läuft die App mit ihnen weiter –
/// mit einem Hinweis, nicht mit einem Absturz.
library;

import 'dart:convert';

import 'roblox_spec.dart';

/// Was für eine Textur gilt.
class TextureBudget {
  const TextureBudget({
    required this.target,
    required this.hardCap,
    required this.nonAlbedo,
  });

  /// Zielgröße – darauf verkleinert die App von sich aus.
  final int target;

  /// Harte Obergrenze beim Hochladen.
  final int hardCap;

  /// Für Nicht-Albedo-Karten (Normal, Roughness, Metalness).
  final int nonAlbedo;

  Map<String, dynamic> toJson() =>
      {'target': target, 'hardCap': hardCap, 'nonAlbedo': nonAlbedo};

  static TextureBudget from(Map<String, dynamic>? json, TextureBudget fallback) {
    if (json == null) return fallback;
    return TextureBudget(
      target: _int(json['target'], fallback.target),
      hardCap: _int(json['hardCap'], fallback.hardCap),
      nonAlbedo: _int(json['nonAlbedo'], fallback.nonAlbedo),
    );
  }
}

/// Ein Asset-Typ mit seinem Budget.
class AssetSpec {
  const AssetSpec({
    required this.id,
    required this.label,
    required this.triangles,
    required this.texture,
    this.singleMesh = false,
    this.attachments = 0,
    this.watertight = true,
    this.parts = const {},
    this.meshNames = const [],
    this.source = '',
    this.checked,
  });

  final String id;
  final String label;

  /// Das Dreiecksbudget des ganzen Assets.
  final int triangles;

  final TextureBudget texture;

  /// Muss alles in einem einzigen Mesh liegen?
  final bool singleMesh;

  /// Wie viele Attachment-Punkte verlangt werden (0 = keine Vorgabe).
  final int attachments;

  final bool watertight;

  /// Einzelbudgets, wenn das Asset beim Hochladen zerlegt wird.
  final Map<String, int> parts;

  /// Die Namen der Teil-Meshes, wenn es welche gibt.
  final List<String> meshNames;

  /// Woher die Zahlen stammen.
  final String source;

  /// Wann zuletzt nachgesehen wurde.
  final DateTime? checked;

  /// Die Summe der Einzelbudgets – bei einem Körper muss sie zur
  /// Gesamtzahl passen, sonst stimmt die Datei nicht.
  int get partSum => parts.values.fold(0, (a, b) => a + b);
}

/// Alles, was in der Datei steht.
class RobloxSpecs {
  const RobloxSpecs({
    required this.version,
    required this.maxAgeDays,
    required this.assetTypes,
    required this.maxInfluences,
    required this.minBoundingBoxFill,
    required this.rootBone,
    required this.rootNode,
    required this.hierarchy,
    required this.allowedPoses,
    required this.characterStuds,
    required this.problems,
    this.fromFile = true,
  });

  final int version;

  /// Ab wie vielen Tagen ein Prüfdatum als veraltet gilt.
  final int maxAgeDays;

  final Map<String, AssetSpec> assetTypes;
  final int maxInfluences;

  /// Wie viel seines Hüllquaders ein Asset mindestens füllen muss.
  final double minBoundingBoxFill;

  final String rootBone;
  final String rootNode;
  final Map<String, List<String>> hierarchy;
  final List<String> allowedPoses;
  final double characterStuds;

  /// Was beim Lesen aufgefallen ist – leere Liste heißt: alles in
  /// Ordnung. Steht in den Einstellungen, statt still verschluckt zu
  /// werden.
  final List<String> problems;

  /// Ob die Werte wirklich aus der Datei kommen oder der Rückfall
  /// greift.
  final bool fromFile;

  AssetSpec? operator [](String id) => assetTypes[id];

  /// Das älteste Prüfdatum – daran hängt die Warnung.
  DateTime? get oldestChecked {
    DateTime? aeltestes;
    for (final spec in assetTypes.values) {
      final d = spec.checked;
      if (d == null) continue;
      if (aeltestes == null || d.isBefore(aeltestes)) aeltestes = d;
    }
    return aeltestes;
  }

  /// Wie alt die Angaben sind, in Tagen. Null, wenn kein Datum
  /// dasteht – das ist selbst ein Befund.
  int? ageInDays({DateTime? now}) {
    final aeltestes = oldestChecked;
    if (aeltestes == null) return null;
    return (now ?? DateTime.now()).difference(aeltestes).inDays;
  }

  bool isStale({DateTime? now}) {
    final alter = ageInDays(now: now);
    return alter == null || alter > maxAgeDays;
  }

  /// Der Satz, der beim Start erscheint – leer, wenn alles frisch ist.
  String staleWarning({DateTime? now}) {
    if (!isStale(now: now)) return '';
    final alter = ageInDays(now: now);
    if (alter == null) {
      return 'In roblox_specs.json steht kein Prüfdatum. Ohne Datum '
          'lässt sich nicht sagen, ob die Grenzen noch gelten.';
    }
    return 'Die Roblox-Vorgaben in roblox_specs.json sind $alter Tage '
        'alt (Grenze: $maxAgeDays). Roblox ändert seine Budgets – bitte '
        'gegen die Dokumentation prüfen und das Feld „checked" '
        'nachziehen.';
  }
}

/// Der Rückfall aus den Konstanten – identisch mit dem, was die
/// mitgelieferte Datei enthält.
RobloxSpecs fallbackSpecs({List<String> problems = const []}) => RobloxSpecs(
      version: 1,
      maxAgeDays: 90,
      fromFile: false,
      problems: problems,
      maxInfluences: specMaxInfluences,
      minBoundingBoxFill: 0.5,
      rootBone: specRootBone,
      rootNode: specRootNode,
      hierarchy: specR15Hierarchy,
      allowedPoses: specAllowedPoses,
      characterStuds: 5.0,
      assetTypes: {
        'rigidAccessory': AssetSpec(
          id: 'rigidAccessory',
          label: 'Starres Accessoire (UGC)',
          triangles: specAccessoryTriangles,
          singleMesh: true,
          attachments: 1,
          texture: const TextureBudget(
              target: specMaxTexture,
              hardCap: specMarketplaceTexture,
              nonAlbedo: 256),
        ),
        'genericMesh': AssetSpec(
          id: 'genericMesh',
          label: 'Generisches Mesh (Prop)',
          triangles: specMaxMeshTriangles,
          texture: const TextureBudget(
              target: specMaxTexture,
              hardCap: specMarketplaceTexture,
              nonAlbedo: specMaxTexture),
        ),
        'characterBody': AssetSpec(
          id: 'characterBody',
          label: 'Charakterkörper (R15)',
          triangles: specBodyTotalTriangles,
          parts: specBodyPartTriangles,
          meshNames: specBodyMeshNames,
          texture: const TextureBudget(
              target: specMaxTexture,
              hardCap: specMarketplaceTexture,
              nonAlbedo: specMaxTexture),
        ),
      },
    );

/// Liest die Datei. Wirft nicht: Was nicht lesbar ist, wird durch den
/// Rückfall ersetzt und steht in [RobloxSpecs.problems].
RobloxSpecs parseRobloxSpecs(String source) {
  final fallback = fallbackSpecs();
  final problems = <String>[];
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      return fallbackSpecs(problems: [
        'roblox_specs.json enthält kein Objekt – es gelten die '
            'eingebauten Werte.'
      ]);
    }
    json = decoded;
  } catch (e) {
    return fallbackSpecs(problems: [
      'roblox_specs.json ließ sich nicht lesen ($e) – es gelten die '
          'eingebauten Werte.'
    ]);
  }

  final typen = <String, AssetSpec>{};
  final rohTypen = json['assetTypes'];
  if (rohTypen is Map<String, dynamic>) {
    for (final entry in rohTypen.entries) {
      final wert = entry.value;
      if (wert is! Map<String, dynamic>) continue;
      final rueckfall = fallback[entry.key];
      final parts = <String, int>{};
      final rohParts = wert['parts'];
      if (rohParts is Map<String, dynamic>) {
        for (final p in rohParts.entries) {
          final zahl = _int(p.value, -1);
          if (zahl >= 0) parts[p.key] = zahl;
        }
      }
      final spec = AssetSpec(
        id: entry.key,
        label: (wert['label'] as String?) ?? rueckfall?.label ?? entry.key,
        triangles: _int(wert['triangles'], rueckfall?.triangles ?? 0),
        singleMesh: wert['singleMesh'] == true,
        attachments: _int(wert['attachments'], 0),
        watertight: wert['watertight'] != false,
        parts: parts,
        meshNames: [
          for (final n in (wert['meshNames'] as List? ?? const []))
            if (n is String) n,
        ],
        texture: TextureBudget.from(
            wert['texture'] as Map<String, dynamic>?,
            rueckfall?.texture ??
                const TextureBudget(
                    target: 1024, hardCap: 2048, nonAlbedo: 1024)),
        source: (wert['quelle'] as String?) ?? '',
        checked: _date(wert['checked']),
      );
      if (spec.triangles <= 0) {
        problems.add('„${spec.id}": Dreiecksbudget fehlt oder ist 0.');
      }
      if (spec.parts.isNotEmpty && spec.partSum != spec.triangles) {
        problems.add('„${spec.id}": Die Einzelbudgets ergeben '
            '${spec.partSum}, angegeben sind ${spec.triangles}.');
      }
      if (spec.texture.target > spec.texture.hardCap) {
        problems.add('„${spec.id}": Die Zielgröße der Textur liegt über '
            'der harten Grenze.');
      }
      if (spec.checked == null) {
        problems.add('„${spec.id}": kein Prüfdatum („checked").');
      }
      typen[entry.key] = spec;
    }
  }
  if (typen.isEmpty) {
    return fallbackSpecs(problems: [
      'roblox_specs.json nennt keine Asset-Typen – es gelten die '
          'eingebauten Werte.',
      ...problems,
    ]);
  }
  // Fehlt ein Typ, den die App braucht, kommt er aus dem Rückfall.
  for (final id in fallback.assetTypes.keys) {
    if (typen.containsKey(id)) continue;
    typen[id] = fallback[id]!;
    problems.add('„$id" fehlt in der Datei – dafür gelten die '
        'eingebauten Werte.');
  }

  final geometry = json['geometry'] as Map<String, dynamic>? ?? const {};
  final rig = json['rig'] as Map<String, dynamic>? ?? const {};
  final scale = json['scale'] as Map<String, dynamic>? ?? const {};

  final hierarchy = <String, List<String>>{};
  final rohHierarchie = rig['hierarchy'];
  if (rohHierarchie is Map<String, dynamic>) {
    for (final entry in rohHierarchie.entries) {
      hierarchy[entry.key] = [
        for (final k in (entry.value as List? ?? const []))
          if (k is String) k,
      ];
    }
  }

  return RobloxSpecs(
    version: _int(json['version'], 1),
    maxAgeDays: _int(json['maxAgeDays'], 90),
    assetTypes: typen,
    maxInfluences: _int(geometry['maxInfluences'], fallback.maxInfluences),
    minBoundingBoxFill:
        _double(geometry['minBoundingBoxFill'], fallback.minBoundingBoxFill),
    rootBone: (rig['rootBone'] as String?) ?? fallback.rootBone,
    rootNode: (rig['rootNode'] as String?) ?? fallback.rootNode,
    hierarchy: hierarchy.isEmpty ? fallback.hierarchy : hierarchy,
    allowedPoses: [
      for (final p in (rig['allowedPoses'] as List? ?? const []))
        if (p is String) p,
    ].isEmpty
        ? fallback.allowedPoses
        : [
            for (final p in (rig['allowedPoses'] as List? ?? const []))
              if (p is String) p,
          ],
    characterStuds:
        _double(scale['characterStuds'], fallback.characterStuds),
    problems: problems,
  );
}

int _int(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _double(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value.trim());
}

// ----------------------------------------------------------------
// Laden
// ----------------------------------------------------------------

/// Die geltenden Vorgaben. Bis [loadRobloxSpecs] gelaufen ist, sind es
/// die eingebauten – so ist der Wert nie null und kein Aufrufer muss
/// auf das Laden warten.
RobloxSpecs robloxSpecs = fallbackSpecs();

/// Lädt `assets/roblox_specs.json`. Schlägt das fehl, bleibt es beim
/// Rückfall; der Grund steht danach in [RobloxSpecs.problems].
///
/// [override] ist eine vom Benutzer geladene Fassung – sie gewinnt.
Future<RobloxSpecs> loadRobloxSpecs(
    Future<String> Function(String key) readAsset,
    {String? override}) async {
  if (override != null && override.trim().isNotEmpty) {
    robloxSpecs = parseRobloxSpecs(override);
    return robloxSpecs;
  }
  try {
    robloxSpecs = parseRobloxSpecs(await readAsset('assets/roblox_specs.json'));
  } catch (e) {
    robloxSpecs = fallbackSpecs(problems: [
      'assets/roblox_specs.json ließ sich nicht öffnen ($e) – es '
          'gelten die eingebauten Werte.'
    ]);
  }
  return robloxSpecs;
}
