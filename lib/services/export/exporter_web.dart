import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: Bild als Download anbieten.
Future<String?> exportImageBytes(
    Uint8List bytes, String fileName, String mimeType) async {
  _download(bytes, fileName, mimeType);
  return 'Download gestartet: $fileName';
}

/// Mehrere Dateien auf einmal.
///
/// Im Browser gibt es keinen Ordner-Dialog – die Seite darf nicht
/// wissen, wohin gespeichert wird. Der Browser fragt stattdessen
/// **einmal**, ob die Seite mehrere Dateien herunterladen darf, und
/// legt danach alles in den Download-Ordner. Das ist so nah an „einmal
/// fragen", wie es im Web geht.
///
/// Die kleine Pause zwischen den Downloads bleibt: Ein Schwall von
/// vierzig Anfragen auf einmal wird abgewiesen.
Future<({int written, String message})?> exportManyBytes(
    List<({Uint8List bytes, String fileName, String mimeType})> files,
    {String suggestedFolderName = ''}) async {
  if (files.isEmpty) return (written: 0, message: 'Nichts zu speichern.');
  for (final f in files) {
    _download(f.bytes, f.fileName, f.mimeType);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  return (
    written: files.length,
    message: '${files.length} Downloads gestartet – der Browser fragt '
        'einmal, ob die Seite mehrere Dateien speichern darf.'
  );
}

void _download(Uint8List bytes, String fileName, String mimeType) {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
