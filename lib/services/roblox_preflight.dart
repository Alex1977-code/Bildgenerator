/// Der Preflight: Was hindert dieses Modell daran, in Roblox zu
/// landen?
///
/// „Für Roblox prüfen" gab es schon – als Liste von Befunden. Diese
/// Datei macht daraus einen Bericht mit **zwei Stufen**: Ein Fehler
/// blockiert den Export, eine Warnung nicht. Und sie sortiert nach
/// dem, was in der Praxis wirklich zur Ablehnung führt: fehlende
/// Attachments und ein gerissenes Dreiecksbudget stehen oben, die
/// Feinheiten unten.
///
/// Jeder Punkt sagt **warum** – eine Prüfliste, die nur „Fehler"
/// meldet, verschiebt die Arbeit nur. Und wo die App den Fehler selbst
/// beheben kann, trägt der Punkt die passende Reparatur bei sich; die
/// Oberfläche macht daraus einen Knopf.
///
/// Die vorhandene Prüfung in `roblox_check.dart` bleibt unangetastet
/// und liefert weiterhin die Zahlen – hier kommt die Bewertung dazu.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'glb_preview.dart' show splitGlb, parseGlbForPreview;
import 'roblox_check.dart';
import 'roblox_marketplace.dart';
import 'roblox_specs_config.dart';

/// Wie schwer ein Befund wiegt.
enum PreflightSeverity {
  /// Blockiert den Export: So nimmt Roblox das Modell nicht an.
  fehler,

  /// Geht durch, kostet aber Qualität, Leistung oder Nacharbeit.
  warnung,

  /// Etwas, das die App aus der Datei nicht sehen kann – gehört
  /// trotzdem in den Bericht, sonst wirkt die Liste vollständiger,
  /// als sie ist.
  hinweis,

  /// Regel eingehalten.
  ok,
}

/// Was die App selbst reparieren kann.
enum PreflightFix {
  keine,

  /// Auf das Budget reduzieren (Modul „Dreiecksbudget").
  reduzieren,

  /// Löcher schließen und die Wicklung vereinheitlichen.
  huelleSchliessen,

  /// Texturen auf die Zielgröße verkleinern.
  texturVerkleinern,

  /// Maßstab, Nullpunkt, Knochen und Ausrichtung herrichten.
  rigHerrichten,

  /// Die Textur-Pipeline: ein UV-Satz, UVs in den 0–1-Raum, ein
  /// Material je Mesh.
  texturPipeline,
}

/// Ein Punkt des Berichts.
class PreflightIssue {
  const PreflightIssue({
    required this.id,
    required this.severity,
    required this.title,
    required this.reason,
    required this.rank,
    this.fix = PreflightFix.keine,
  });

  /// Kennung für Tests und für die Oberfläche.
  final String id;

  final PreflightSeverity severity;

  /// Die Kurzform, z. B. „Dreiecke: 8.400 von 4.000".
  final String title;

  /// Warum das zählt und was zu tun ist – im Klartext.
  final String reason;

  /// Kleiner heißt weiter oben. Attachments und Budget sind 0 und 1.
  final int rank;

  final PreflightFix fix;

  bool get blocks => severity == PreflightSeverity.fehler;
}

/// Der ganze Bericht.
class PreflightReport {
  const PreflightReport(this.issues, this.facts);

  final List<PreflightIssue> issues;

  /// Die gemessenen Zahlen – damit die Oberfläche sie zeigen kann,
  /// ohne noch einmal zu lesen.
  final RobloxFacts facts;

  List<PreflightIssue> get errors =>
      [for (final i in issues) if (i.severity == PreflightSeverity.fehler) i];

  List<PreflightIssue> get warnings => [
        for (final i in issues)
          if (i.severity == PreflightSeverity.warnung) i,
      ];

  /// Ob der Export blockiert ist.
  bool get blocked => errors.isNotEmpty;

  /// Ein Satz für die Kopfzeile.
  String get summary {
    if (blocked) {
      return '${errors.length} '
          '${errors.length == 1 ? 'Fehler blockiert' : 'Fehler blockieren'} '
          'den Export'
          '${warnings.isEmpty ? '.' : ', dazu ${warnings.length} '
              'Warnung(en).'}';
    }
    if (warnings.isNotEmpty) {
      return 'Kein Fehler, aber ${warnings.length} Warnung(en) – der '
          'Export ist frei.';
    }
    return 'Alles in Ordnung.';
  }
}

/// Zusätzliche Angaben, die `readRobloxFacts` nicht liest: die Namen
/// der Knoten. Daran hängen Attachments und Cages.
class GlbNodeNames {
  const GlbNodeNames({
    required this.attachments,
    required this.cages,
    required this.meshNodes,
    required this.transformedMeshNodes,
  });

  /// Knoten, die auf `_Att` enden oder wie ein Attachment heißen.
  final List<String> attachments;

  /// Knoten, die auf `_OuterCage` oder `_InnerCage` enden.
  final List<String> cages;

  /// Namen aller Knoten, an denen ein Mesh hängt.
  final List<String> meshNodes;

  /// Mesh-Knoten mit Drehung, Skalierung oder Matrix – die
  /// Transformation ist dann nicht eingefroren.
  final List<String> transformedMeshNodes;
}

/// Liest die Knotennamen aus einer GLB. Wirft nicht.
GlbNodeNames readGlbNodeNames(Uint8List glb) {
  final attachments = <String>[];
  final cages = <String>[];
  final meshNodes = <String>[];
  final transformed = <String>[];
  try {
    final json = splitGlb(glb).json;
    final nodes = json['nodes'] as List? ?? const [];
    for (final raw in nodes) {
      final node = raw as Map<String, dynamic>;
      final name = (node['name'] as String?) ?? '';
      if (name.endsWith('_Att') || name.endsWith('Attachment')) {
        attachments.add(name);
      }
      if (name.endsWith('_OuterCage') || name.endsWith('_InnerCage')) {
        cages.add(name);
      }
      if (node['mesh'] == null) continue;
      meshNodes.add(name);
      if (_hasTransform(node)) transformed.add(name.isEmpty ? '(ohne Namen)' : name);
    }
  } catch (_) {
    // Eine unlesbare Datei fällt an anderer Stelle auf.
  }
  return GlbNodeNames(
    attachments: attachments,
    cages: cages,
    meshNodes: meshNodes,
    transformedMeshNodes: transformed,
  );
}

bool _hasTransform(Map<String, dynamic> node) {
  final matrix = node['matrix'];
  if (matrix is List && matrix.length == 16) {
    const einheit = [
      1.0, 0.0, 0.0, 0.0, //
      0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0,
    ];
    for (var i = 0; i < 16; i++) {
      if (((matrix[i] as num).toDouble() - einheit[i]).abs() > 1e-6) {
        return true;
      }
    }
  }
  final rotation = node['rotation'];
  if (rotation is List && rotation.length == 4) {
    for (var i = 0; i < 3; i++) {
      if ((rotation[i] as num).abs() > 1e-6) return true;
    }
    if (((rotation[3] as num).abs() - 1).abs() > 1e-6) return true;
  }
  final scale = node['scale'];
  if (scale is List) {
    for (final s in scale) {
      if (((s as num).toDouble() - 1).abs() > 1e-6) return true;
    }
  }
  return false;
}

/// Der Preflight für ein Modell.
///
/// [spec] ist der gewählte Asset-Typ aus `roblox_specs.json`; daran
/// hängen Budget, Texturgrenze und die Frage, ob ein einziges Mesh
/// verlangt ist.
Future<PreflightReport> preflightGlb(
  Uint8List glb, {
  required AssetSpec spec,
  RobloxSpecs? specs,
}) async {
  final facts = await readRobloxFacts(glb);
  final names = readGlbNodeNames(glb);

  // Die Marktplatz-Regeln brauchen die Geometrie, nicht nur die
  // Kennzahlen – Tiefe, Hals und getrennte Beine liest man nur am
  // Querschnitt ab.
  var marktplatz = const <MarketplaceFinding>[];
  if (spec.marketplace) {
    try {
      final mesh = await parseGlbForPreview(glb);
      try {
        marktplatz = checkMarketplaceFigure(
            measureMarketplaceFigure(mesh.positions, mesh.indices));
      } finally {
        mesh.dispose();
      }
    } catch (_) {
      // Eine Datei, die sich nicht zeichnen lässt, scheitert schon an
      // den Regeln davor; hier still weiter statt abbrechen.
    }
  }

  return buildPreflightReport(
    facts: facts,
    names: names,
    spec: spec,
    specs: specs ?? robloxSpecs,
    marketplace: marktplatz,
  );
}

/// Die Bewertung – getrennt vom Lesen, damit sie sich mit erfundenen
/// Zahlen prüfen lässt, ohne jedes Mal eine GLB zu bauen.
PreflightReport buildPreflightReport({
  required RobloxFacts facts,
  required GlbNodeNames names,
  required AssetSpec spec,
  required RobloxSpecs specs,
  List<MarketplaceFinding> marketplace = const [],
}) {
  final issues = <PreflightIssue>[];

  void add(String id, PreflightSeverity severity, String title,
      String reason, int rank,
      {PreflightFix fix = PreflightFix.keine}) {
    issues.add(PreflightIssue(
        id: id,
        severity: severity,
        title: title,
        reason: reason,
        rank: rank,
        fix: fix));
  }

  // --- Marktplatz zuerst ----------------------------------------
  // Rang −1: Eine zu tiefe Figur ist für den Marktplatz verloren,
  // bevor Attachments oder Budget überhaupt zählen. Und anders als
  // alles andere lässt sich das hier **nicht reparieren** – es
  // entsteht beim Prompt.
  for (final f in marketplace) {
    if (f.level == MarketplaceLevel.ok) continue;
    add(
      'markt_${f.id}',
      f.level == MarketplaceLevel.fehler
          ? PreflightSeverity.fehler
          : PreflightSeverity.warnung,
      f.title,
      '${f.reason}\n\nGemessen am Marktplatz-Validator '
          '($marketplaceMeasuredOn); in Roblox\' Dokumentation steht '
          'diese Grenze nicht.',
      -1,
    );
  }

  // --- 0. Attachments -------------------------------------------
  // Der häufigste Ablehnungsgrund: Ohne Attachment weiß Roblox nicht,
  // wo das Teil sitzt.
  if (spec.attachments > 0) {
    final falschBenannt = [
      for (final n in names.attachments)
        if (!n.endsWith('_Att')) n,
    ];
    if (names.attachments.isEmpty) {
      add(
          'attachments',
          PreflightSeverity.warnung,
          'Kein Attachment in der Datei',
          'Ein starres Accessoire braucht genau ${spec.attachments} '
              'Attachment – daran hängt es am Körper. In dieser Datei '
              'steht keines. Das ist kein Fehler, solange du den Weg '
              'über „Für Roblox ausliefern" gehst: Das mitgelieferte '
              'Lua-Skript legt es in Studio an, mit dem Namen, der zum '
              'AccessoryType passt. Wer es schon in der Datei haben '
              'will, benennt den Knoten „<Name>_Att".',
          0);
    } else if (falschBenannt.isNotEmpty) {
      add(
          'attachments_namen',
          PreflightSeverity.fehler,
          'Attachment falsch benannt: ${falschBenannt.join(', ')}',
          'Roblox erkennt Attachments am Namen. Er muss auf „_Att" '
              'enden (Hat_Att, FaceFront_Att, Root_Att …). Ein anderer '
              'Name führt zu keiner Fehlermeldung – das Teil sitzt beim '
              'Anziehen irgendwo, meist im Boden.',
          0);
    } else if (names.attachments.length != spec.attachments) {
      add(
          'attachments_zahl',
          PreflightSeverity.fehler,
          '${names.attachments.length} Attachments statt '
              '${spec.attachments}',
          'Für „${spec.label}" ist genau ${spec.attachments} Attachment '
              'vorgesehen. Mehr als eines macht die Lage mehrdeutig.',
          0);
    } else {
      add('attachments', PreflightSeverity.ok,
          'Attachment: ${names.attachments.first}', 'Richtig benannt.', 0);
    }
  }

  // --- 1. Dreiecksbudget ----------------------------------------
  final budget = spec.triangles;
  final groestesMesh = facts.meshTriangles.isEmpty
      ? facts.triangles
      : facts.meshTriangles.reduce(math.max);
  if (budget > 0 && facts.triangles > budget) {
    add(
        'budget',
        PreflightSeverity.fehler,
        'Dreiecke: ${facts.triangles} von $budget',
        'Das Budget für „${spec.label}" ist gerissen – '
            '${facts.triangles - budget} Dreiecke zu viel. Roblox lehnt '
            'ab. Der Regler „Dreiecksbudget" reduziert das Netz; ein '
            'Skelett übersteht das allerdings nicht, also vorher '
            'reduzieren und danach riggen.',
        1,
        fix: PreflightFix.reduzieren);
  } else if (budget > 0 && facts.triangles > budget * 0.9) {
    add(
        'budget',
        PreflightSeverity.warnung,
        'Dreiecke: ${facts.triangles} von $budget – knapp',
        'Über 90 % des Budgets. Es passt, aber Löcher schließen, ein '
            'Cage und aufgetrennte Nähte bringen noch Dreiecke dazu.',
        1,
        fix: PreflightFix.reduzieren);
  } else {
    add('budget', PreflightSeverity.ok,
        'Dreiecke: ${facts.triangles} von $budget', 'Innerhalb des '
        'Budgets.', 1);
  }
  if (groestesMesh > specs.assetTypes['genericMesh']!.triangles) {
    add(
        'mesh_budget',
        PreflightSeverity.fehler,
        'Ein Mesh hat $groestesMesh Dreiecke',
        'Der Importer nimmt je Mesh höchstens '
            '${specs.assetTypes['genericMesh']!.triangles}, unabhängig '
            'vom Asset-Typ.',
        1,
        fix: PreflightFix.reduzieren);
  }

  // --- 2. Wasserdichtheit ---------------------------------------
  if (spec.watertight) {
    if (facts.openEdges > 0) {
      add(
          'wasserdicht',
          PreflightSeverity.fehler,
          '${facts.openEdges} offene Kante(n)',
          'Die Hülle muss geschlossen sein – keine Löcher, keine '
              'Rückseiten. Eine offene Kante gehört nur zu einem '
              'Dreieck; dort sieht man beim Drehen ins Innere. Die App '
              'kann Löcher schließen.',
          2,
          fix: PreflightFix.huelleSchliessen);
    } else {
      add('wasserdicht', PreflightSeverity.ok, 'Wasserdicht',
          'Keine offenen Kanten.', 2);
    }
  }

  // --- 3. Wicklung ----------------------------------------------
  if (facts.reversedEdges > 0) {
    add(
        'wicklung',
        PreflightSeverity.fehler,
        '${facts.reversedEdges} Kante(n) mit gegenläufiger Wicklung',
        'Benachbarte Dreiecke müssen ihre gemeinsame Kante gegenläufig '
            'durchlaufen. Wo das nicht stimmt, zeigt die Fläche nach '
            'innen und ist im Spiel unsichtbar. Die App dreht sie um.',
        3,
        fix: PreflightFix.huelleSchliessen);
  } else if (facts.signedVolume < 0) {
    add(
        'normalen',
        PreflightSeverity.fehler,
        'Normalen zeigen nach innen',
        'Das eingeschlossene Volumen ist negativ – das ganze Netz ist '
            'umgestülpt. Von außen sieht man dann nichts.',
        3,
        fix: PreflightFix.huelleSchliessen);
  }

  // --- 4. Volumen -----------------------------------------------
  if (facts.volumeRatio < 0.001) {
    add(
        'volumen',
        PreflightSeverity.fehler,
        'Kein Volumen',
        'Kein Teil darf null Dicke haben. Ein Blatt ohne Dicke wird '
            'in Roblox unsichtbar, sobald man von der falschen Seite '
            'schaut. In Blender mit „Solidify" eine Wandstärke geben.',
        4);
  }

  // --- 5. Füllung des Hüllquaders -------------------------------
  final size = facts.size;
  final boxVolumen = size.length >= 3 ? size[0] * size[1] * size[2] : 0.0;
  if (boxVolumen > 0) {
    final fuellung = facts.signedVolume.abs() / boxVolumen;
    if (fuellung < specs.minBoundingBoxFill) {
      add(
          'huellquader',
          PreflightSeverity.warnung,
          'Hüllquader nur zu ${(fuellung * 100).round()} % gefüllt',
          'Roblox verlangt, dass ein Asset einen erkennbaren Teil '
              'seines Hüllquaders einnimmt (Richtwert '
              '${(specs.minBoundingBoxFill * 100).round()} %). Ein '
              'dünnes, weit ausgestrecktes Teil wirkt im Katalog wie '
              'ein Fehler. Gemessen ist hier das Volumen; Roblox '
              'beurteilt es an der Ansicht von vorn, der Seite und '
              'hinten.',
          5);
    } else {
      add('huellquader', PreflightSeverity.ok,
          'Hüllquader zu ${(fuellung * 100).round()} % gefüllt', '', 5);
    }
  }

  // --- 6. Texturen ----------------------------------------------
  final zuGross = [
    for (final t in facts.textures)
      if (t.width > spec.texture.hardCap || t.height > spec.texture.hardCap)
        t,
  ];
  final ueberZiel = [
    for (final t in facts.textures)
      if (t.width > spec.texture.target || t.height > spec.texture.target) t,
  ];
  if (zuGross.isNotEmpty) {
    add(
        'textur',
        PreflightSeverity.fehler,
        '${zuGross.length} Textur(en) über ${spec.texture.hardCap} px',
        'Das ist die harte Grenze beim Hochladen. Die App kann die '
            'Bilder verkleinern.',
        6,
        fix: PreflightFix.texturVerkleinern);
  } else if (ueberZiel.isNotEmpty) {
    add(
        'textur',
        PreflightSeverity.warnung,
        '${ueberZiel.length} Textur(en) über ${spec.texture.target} px',
        'Die Zielgröße ist ${spec.texture.target} px; darüber lädt '
            'Roblox zwar hoch, rechnet aber selbst herunter – lieber '
            'selbst verkleinern und das Ergebnis sehen.',
        6,
        fix: PreflightFix.texturVerkleinern);
  } else if (facts.textures.isNotEmpty) {
    add('textur', PreflightSeverity.ok,
        '${facts.textures.length} Textur(en) innerhalb der Grenze', '', 6);
  }

  // --- 7. UVs ---------------------------------------------------
  if (facts.uvSets > 1) {
    add(
        'uv_saetze',
        PreflightSeverity.fehler,
        '${facts.uvSets} UV-Sätze',
        'Studio nimmt genau einen UV-Satz je Objekt. Weitere Sätze '
            'gehen verloren – und das Ergebnis sieht anders aus als im '
            'Modellierprogramm.',
        7,
        fix: PreflightFix.texturPipeline);
  }
  if (facts.uvMin < -0.001 || facts.uvMax > 1.001) {
    add(
        'uv_raum',
        PreflightSeverity.fehler,
        'UVs außerhalb von 0–1',
        'Alle UVs müssen im Bereich 0 bis 1 liegen (gemessen: '
            '${facts.uvMin.toStringAsFixed(2)} bis '
            '${facts.uvMax.toStringAsFixed(2)}). Außerhalb kachelt die '
            'Textur, und in Roblox sieht das anders aus als im '
            'Modellierprogramm. Liegt die ganze Insel um eine ganze '
            'Kachel daneben, schiebt die Textur-Pipeline sie bildgleich '
            'zurück; reicht sie über eine Kachelgrenze, muss das '
            'UV-Layout neu gelegt werden.',
        7,
        fix: PreflightFix.texturPipeline);
  }

  // --- 8. Material und Mesh-Zahl --------------------------------
  if (facts.maxPrimitivesPerMesh > 1) {
    add(
        'material',
        PreflightSeverity.fehler,
        '${facts.maxPrimitivesPerMesh} Materialien in einem Mesh',
        'Der Importer nimmt ein Material je Mesh. Mehrere Materialien '
            'zerlegen das Netz beim Import, und die Teile verlieren '
            'ihren Zusammenhang. Teilnetze mit demselben Material legt '
            'die Textur-Pipeline zusammen; verschiedene Materialien '
            'brauchen einen Textur-Atlas.',
        8,
        fix: PreflightFix.texturPipeline);
  }
  if (spec.singleMesh && facts.meshCount > 1) {
    add(
        'ein_mesh',
        PreflightSeverity.fehler,
        '${facts.meshCount} Meshes statt einem',
        'Für „${spec.label}" verlangt Roblox ein einziges Mesh. In '
            'Blender die Teile verbinden (Strg+J) und die Doppelpunkte '
            'zusammenlegen.',
        8);
  }

  // --- 9. Transformationen --------------------------------------
  if (names.transformedMeshNodes.isNotEmpty) {
    add(
        'transform',
        PreflightSeverity.warnung,
        'Nicht eingefrorene Transformation: '
            '${names.transformedMeshNodes.take(3).join(', ')}'
            '${names.transformedMeshNodes.length > 3 ? ' …' : ''}',
        'Der Mesh-Knoten trägt eine Drehung oder Skalierung, statt sie '
            'in die Punkte eingerechnet zu haben. Studio übernimmt das '
            'zwar, aber jede spätere Messung – Größe, Dreiecke, '
            'Attachment-Lage – rechnet dann an der falschen Stelle. '
            '„Für Roblox anpassen" backt sie ein.',
        9,
        fix: PreflightFix.rigHerrichten);
  }

  // --- 10. Maßstab ----------------------------------------------
  final hoehe = size.length >= 2 ? size[1] : 0.0;
  if (hoehe > 0 && spec.id == 'characterBody') {
    final ziel = specs.characterStuds;
    if ((hoehe - ziel).abs() > ziel * 0.4) {
      add(
          'massstab',
          PreflightSeverity.warnung,
          'Höhe ${hoehe.toStringAsFixed(2)} statt $ziel Studs',
          'Der Importer setzt eine glTF-Einheit gleich einem Stud. Ein '
              'Standard-Charakter ist $ziel Studs hoch; wer stark '
              'abweicht, bekommt eine Figur, die neben allen anderen '
              'falsch wirkt. „Für Roblox anpassen" skaliert.',
          10,
          fix: PreflightFix.rigHerrichten);
    }
  }

  // --- 11. Cages ------------------------------------------------
  if (names.cages.isEmpty) {
    add(
        'cages',
        PreflightSeverity.hinweis,
        'Keine Cages in der Datei',
        'Layered Accessories und Charakterkörper brauchen Cage-Meshes '
            '(<Name>_OuterCage). Starre Accessoires und Props brauchen '
            'keine. Roblox verlangt ausdrücklich, dass Cages aus den '
            'offiziellen Vorlagen übernommen und nicht selbst gebaut '
            'werden – solange die Vorlage nicht vorliegt, kann die App '
            'hier nichts erzeugen.',
        11);
  } else {
    add('cages', PreflightSeverity.ok,
        '${names.cages.length} Cage-Mesh(es)', names.cages.join(', '), 11);
  }

  // --- 12. Was aus der Datei nicht zu sehen ist ------------------
  add(
      'ngons',
      PreflightSeverity.hinweis,
      'N-Gons sind hier nicht messbar',
      'glTF speichert ausschließlich Dreiecke. Ob im Modellierprogramm '
          'N-Gons stehen, steht nicht in der Datei – die Dreieckszahl '
          'oben ist die nach der Triangulierung, also genau das, was '
          'Roblox zählt.',
      12);
  add(
      'studio_eigenschaften',
      PreflightSeverity.hinweis,
      'Material, Transparency und VertexColor setzt Studio',
      'Material „Plastic", Transparency 0 und VertexColor 1,1,1 sind '
          'Eigenschaften des Teils in Studio, nicht der Datei – sie '
          'lassen sich hier weder lesen noch setzen. Das mitgelieferte '
          'Lua-Skript („Für Roblox ausliefern") setzt sie beim Anlegen.',
      13);

  issues.sort((a, b) {
    final r = a.rank.compareTo(b.rank);
    if (r != 0) return r;
    return a.severity.index.compareTo(b.severity.index);
  });
  return PreflightReport(issues, facts);
}

/// Der Bericht als Text – für die Zwischenablage und für die
/// Sidecar-Datei.
String preflightAsText(PreflightReport report, AssetSpec spec) {
  final buffer = StringBuffer()
    ..writeln('Roblox-Preflight – ${spec.label}')
    ..writeln(report.summary)
    ..writeln();
  for (final issue in report.issues) {
    final marke = switch (issue.severity) {
      PreflightSeverity.fehler => 'FEHLER ',
      PreflightSeverity.warnung => 'WARNUNG',
      PreflightSeverity.hinweis => 'HINWEIS',
      PreflightSeverity.ok => 'OK     ',
    };
    buffer.writeln('$marke  ${issue.title}');
    if (issue.reason.isNotEmpty) buffer.writeln('         ${issue.reason}');
  }
  return buffer.toString();
}

/// Der Bericht als JSON – damit er sich neben dem Asset ablegen lässt.
String preflightAsJson(PreflightReport report, AssetSpec spec) =>
    const JsonEncoder.withIndent('  ').convert({
      'assetType': spec.id,
      'label': spec.label,
      'blocked': report.blocked,
      'summary': report.summary,
      'triangles': report.facts.triangles,
      'budget': spec.triangles,
      'issues': [
        for (final issue in report.issues)
          {
            'id': issue.id,
            'severity': issue.severity.name,
            'title': issue.title,
            'reason': issue.reason,
            if (issue.fix != PreflightFix.keine) 'fix': issue.fix.name,
          },
      ],
    });
