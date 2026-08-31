/// Projekte und Ordner in der Galerie.
///
/// Ein Projektpfad ist ein Text mit Schrägstrichen: „Burgenspiel",
/// „Burgenspiel/Gebäude", „Burgenspiel/Gebäude/Türme". Daraus baut
/// diese Datei den Baum, den die Galerie zeigt.
///
/// **Warum kein echter Ordner auf der Platte.** Die Dateien liegen
/// weiter dort, wo sie die App abgelegt hat; nur der Pfad im Eintrag
/// ändert sich. Ein Bild lässt sich damit umsortieren, ohne dass eine
/// Datei bewegt wird – und ein misslungenes Umsortieren kann nichts
/// verlieren. Beim Herunterladen entsteht der Ordner ohnehin nicht:
/// Browser und Teilen-Menü nehmen nur einen Dateinamen.
library;

/// Ein Ordner im Projektbaum samt allem, was darin liegt.
class ProjectNode {
  ProjectNode({
    required this.name,
    required this.path,
    required this.children,
    required this.directCount,
    required this.totalCount,
  });

  /// Name dieser Ebene, etwa „Gebäude".
  final String name;

  /// Voller Pfad bis hierher, etwa „Burgenspiel/Gebäude".
  final String path;

  /// Unterordner, alphabetisch.
  final List<ProjectNode> children;

  /// Einträge unmittelbar in diesem Ordner …
  final int directCount;

  /// … und zusammen mit allen Unterordnern.
  final int totalCount;

  bool get hasChildren => children.isNotEmpty;
}

/// Zerlegt einen Pfad in seine Ebenen und räumt ihn dabei auf:
/// doppelte Schrägstriche, Leerzeichen am Rand, leere Ebenen.
List<String> projectParts(String path) => [
      for (final part in path.split('/'))
        if (part.trim().isNotEmpty) part.trim(),
    ];

/// Ein Pfad in seiner aufgeräumten Form. Leer = nicht einsortiert.
String normalizeProject(String path) => projectParts(path).join('/');

/// Der übergeordnete Ordner. Leer, wenn der Pfad schon oberste Ebene
/// ist oder leer war.
String parentProject(String path) {
  final parts = projectParts(path);
  if (parts.length < 2) return '';
  return parts.sublist(0, parts.length - 1).join('/');
}

/// Name der letzten Ebene – das, was in der Kachel steht.
String projectName(String path) {
  final parts = projectParts(path);
  return parts.isEmpty ? '' : parts.last;
}

/// Alle Ebenen eines Pfades als Krümelpfad: „a", „a/b", „a/b/c".
List<String> projectTrail(String path) {
  final parts = projectParts(path);
  return [
    for (var i = 1; i <= parts.length; i++) parts.sublist(0, i).join('/'),
  ];
}

/// Ob [path] in [folder] liegt – der Ordner selbst zählt mit.
///
/// Verglichen wird ebenenweise, nicht als Textanfang: „Burg" darf
/// nicht „Burgenspiel" einschließen.
bool projectIsInside(String path, String folder) {
  if (folder.isEmpty) return true;
  final a = projectParts(path);
  final b = projectParts(folder);
  if (a.length < b.length) return false;
  for (var i = 0; i < b.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Baut den Ordnerbaum aus den Pfaden aller Einträge.
///
/// [paths] ist ein Pfad je Eintrag (mehrfach vorkommende Pfade zählen
/// mit). Ordner, die es nur als Zwischenebene gibt, entstehen dabei
/// von selbst.
///
/// [empty] sind Ordner, die es geben soll, **ohne** dass etwas darin
/// liegt. Ohne sie wäre ein frisch angelegtes Projekt unsichtbar, bis
/// das erste Bild darin landet – man legt einen Ordner an und nichts
/// passiert. Sie zählen nicht mit: Ein leerer Ordner enthält null
/// Einträge, nicht einen.
List<ProjectNode> buildProjectTree(Iterable<String> paths,
    {Iterable<String> empty = const []}) {
  // Erst jede Ebene zählen, dann daraus den Baum falten.
  final direct = <String, int>{};
  final known = <String>{};
  for (final raw in paths) {
    final path = normalizeProject(raw);
    if (path.isEmpty) continue;
    direct[path] = (direct[path] ?? 0) + 1;
    for (final level in projectTrail(path)) {
      known.add(level);
    }
  }
  for (final raw in empty) {
    for (final level in projectTrail(normalizeProject(raw))) {
      known.add(level);
    }
  }

  List<ProjectNode> childrenOf(String parent) {
    final names = <String>{};
    for (final path in known) {
      if (parentProject(path) == parent && path != parent) {
        names.add(path);
      }
    }
    final sorted = names.toList()
      ..sort((a, b) =>
          projectName(a).toLowerCase().compareTo(projectName(b).toLowerCase()));
    return [
      for (final path in sorted)
        () {
          final kids = childrenOf(path);
          final own = direct[path] ?? 0;
          return ProjectNode(
            name: projectName(path),
            path: path,
            children: kids,
            directCount: own,
            totalCount:
                own + kids.fold<int>(0, (sum, k) => sum + k.totalCount),
          );
        }(),
    ];
  }

  return childrenOf('');
}

/// Ein Pfad, der es noch nicht gibt: hängt „ (2)" an, bis er frei ist.
/// Verhindert, dass zwei Ordner gleichen Namens verschmelzen, wenn
/// jemand denselben Namen zweimal anlegt.
String uniqueProject(String wanted, Set<String> existing) {
  final base = normalizeProject(wanted);
  if (base.isEmpty || !existing.contains(base)) return base;
  for (var n = 2; n < 1000; n++) {
    final candidate = '$base ($n)';
    if (!existing.contains(candidate)) return candidate;
  }
  return base;
}

/// Benennt einen Ordner um bzw. verschiebt ihn: liefert den neuen Pfad
/// für einen Eintrag, der bisher unter [old] lag.
///
/// Unterordner wandern mit, weil nur der vordere Teil ersetzt wird.
String reparentProject(String path, String old, String replacement) {
  if (!projectIsInside(path, old)) return path;
  final rest = projectParts(path).sublist(projectParts(old).length);
  final target = normalizeProject(replacement);
  return [if (target.isNotEmpty) target, ...rest].join('/');
}
