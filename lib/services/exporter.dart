import 'dart:typed_data';

import 'export/exporter_web.dart'
    if (dart.library.io) 'export/exporter_io.dart' as impl;

/// Exportiert ein Bild plattformgerecht (Teilen, Speichern oder Download).
/// Gibt eine Erfolgsmeldung zurück oder `null`, wenn abgebrochen wurde.
Future<String?> exportImageBytes(
        Uint8List bytes, String fileName, String mimeType) =>
    impl.exportImageBytes(bytes, fileName, mimeType);

/// Exportiert **mehrere** Dateien mit einem einzigen Dialog.
///
/// Der Unterschied zu [exportImageBytes] in einer Schleife: Dort geht
/// für jede Datei ein „Speichern unter" auf. Bei vierzig Bildern sind
/// das vierzig Dialoge, und niemand klickt die durch.
///
/// Desktop: einmal nach dem Ordner fragen, alles dort ablegen.
/// Handy: alles in einem Teilen-Vorgang. Web: der Browser fragt
/// einmal, ob die Seite mehrere Dateien speichern darf.
///
/// Gibt null zurück, wenn abgebrochen wurde – dann wurde nichts
/// geschrieben.
Future<({int written, String message})?> exportManyBytes(
        List<({Uint8List bytes, String fileName, String mimeType})> files,
        {String suggestedFolderName = ''}) =>
    impl.exportManyBytes(files, suggestedFolderName: suggestedFolderName);
