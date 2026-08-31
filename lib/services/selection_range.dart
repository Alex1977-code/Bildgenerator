/// Bereichsauswahl in einer Liste – „von hier bis dort".
///
/// In der Galerie liegen bei einem Massenlauf schnell vierzig Kacheln
/// nebeneinander. Sie einzeln anzutippen ist Fleißarbeit; üblich ist
/// deshalb: die erste anklicken, die letzte mit Umschalt – und alles
/// dazwischen ist markiert. Diese Funktion macht daraus reine Logik,
/// unabhängig von der Oberfläche und damit prüfbar.
library;

/// Die Kennungen von [anchor] bis [target] – beide eingeschlossen,
/// in der Reihenfolge von [ids].
///
/// Die Richtung spielt keine Rolle: Liegt der Anker hinter dem Ziel,
/// kommt derselbe Bereich heraus. Ist der Anker unbekannt oder nicht
/// (mehr) in der Liste – etwa weil die Kachel inzwischen einsortiert
/// wurde –, bleibt es beim Ziel allein. Ein Bereich ohne Anker wäre
/// geraten.
List<String> selectionRange(List<String> ids, String? anchor, String target) {
  final ziel = ids.indexOf(target);
  if (ziel < 0) return const [];
  final start = anchor == null ? -1 : ids.indexOf(anchor);
  if (start < 0) return [target];
  final von = start < ziel ? start : ziel;
  final bis = start < ziel ? ziel : start;
  return ids.sublist(von, bis + 1);
}
