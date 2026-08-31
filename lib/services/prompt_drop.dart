/// Text- und Markdown-Dateien in ein Prompt-Feld ziehen.
///
/// Prompts entstehen selten in der App: Sie kommen aus einer
/// Prompt-KI, einem Notizzettel, einer Markdown-Datei mit den
/// Beschreibungen eines ganzen Spiel-Sets. Bisher blieb nur
/// Kopieren-und-Einfügen – bei einem Massenprompt mit 43 Blöcken über
/// mehrere Bildschirmseiten fehleranfällig.
///
/// **Was hier passiert und was nicht.** Der Inhalt wird gelesen und
/// aufgeräumt, aber nicht gedeutet: Kein Erraten von Feldern, kein
/// Umschreiben. Was in der Datei steht, steht danach im Feld.
library;

/// Endungen, die als Text gelten.
const promptTextExtensions = {'.txt', '.md', '.markdown', '.text', '.prompt'};

/// Ob dieser Dateiname als Prompt-Text infrage kommt.
bool isPromptTextFile(String name) {
  final lower = name.toLowerCase();
  return promptTextExtensions.any(lower.endsWith);
}

/// Räumt den Inhalt einer abgelegten Datei auf.
///
/// * Eine **BOM** am Anfang fliegt raus – sonst steht ein unsichtbares
///   Zeichen vor dem ersten Wort und wandert in den Prompt.
/// * **Windows-Zeilenenden** werden zu einfachen: Der Massenprompt
///   trennt Blöcke an Leerzeilen, und ein „\r" macht eine Leerzeile
///   zu einer Zeile mit Inhalt.
/// * Ein **Codeblock-Rahmen** aus Markdown (```) fällt weg, wenn er
///   den ganzen Text umschließt: Prompt-KIs geben ihre Ergebnisse
///   gern so aus, und die Backticks gehören nicht in den Prompt.
/// * Am Rand wird getrimmt.
String cleanPromptText(String raw) {
  var text = raw;
  if (text.startsWith('﻿')) text = text.substring(1);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = text.trim().split('\n');
  if (lines.length >= 2 &&
      lines.first.trimRight().startsWith('```') &&
      lines.last.trim() == '```') {
    text = lines.sublist(1, lines.length - 1).join('\n');
  }
  return text.trim();
}

/// Fügt neuen Text an einen vorhandenen an.
///
/// Angehängt statt ersetzt: Wer schon etwas getippt hat, soll es durch
/// eine abgelegte Datei nicht verlieren. Getrennt wird mit einer
/// Leerzeile – im Massenprompt ist das die Blockgrenze, sonst schadet
/// sie nicht.
String appendPromptText(String existing, String added) {
  final vorhanden = existing.trimRight();
  final neu = cleanPromptText(added);
  if (neu.isEmpty) return existing;
  if (vorhanden.isEmpty) return neu;
  return '$vorhanden\n\n$neu';
}

/// Kurzer Bericht für die Meldung nach dem Ablegen.
String promptDropSummary(List<String> accepted, List<String> rejected) {
  final parts = <String>[];
  if (accepted.isNotEmpty) {
    parts.add('${accepted.length} '
        '${accepted.length == 1 ? 'Datei' : 'Dateien'} übernommen '
        '(${accepted.join(', ')})');
  }
  if (rejected.isNotEmpty) {
    parts.add('übergangen: ${rejected.join(', ')} – nur '
        '${promptTextExtensions.join(', ')}');
  }
  return parts.join('; ');
}
