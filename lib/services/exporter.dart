import 'dart:typed_data';

import 'export/exporter_web.dart'
    if (dart.library.io) 'export/exporter_io.dart' as impl;

/// Exportiert ein Bild plattformgerecht (Teilen, Speichern oder Download).
/// Gibt eine Erfolgsmeldung zurück oder `null`, wenn abgebrochen wurde.
Future<String?> exportImageBytes(
        Uint8List bytes, String fileName, String mimeType) =>
    impl.exportImageBytes(bytes, fileName, mimeType);
