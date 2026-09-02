import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' hide XFile;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobil: System-Teilen-Dialog (dort lässt sich das Bild auch in der
/// Foto-Galerie speichern). Desktop: "Speichern unter"-Dialog.
Future<String?> exportImageBytes(
    Uint8List bytes, String fileName, String mimeType) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );
    if (result.status == ShareResultStatus.dismissed) return null;
    return 'Bild geteilt bzw. gespeichert.';
  }

  final extension = fileName.split('.').last;
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [
      XTypeGroup(label: 'Bilder', extensions: [extension]),
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes);
  return 'Gespeichert: ${location.path}';
}

/// Mehrere Dateien auf einmal – **ein** Dialog für alle.
///
/// Vorher lief der Sammel-Download über [exportImageBytes] je Datei,
/// und damit ging für jedes Bild ein „Speichern unter" auf. Bei vierzig
/// Bildern sind das vierzig Dialoge; niemand klickt die durch.
///
/// Auf dem Desktop wird deshalb **einmal nach dem Ordner** gefragt und
/// alles dort abgelegt. Auf dem Handy geht alles in **einem**
/// Teilen-Vorgang heraus – auch dort ist der Dialog je Datei die
/// eigentliche Zumutung.
///
/// Gibt zurück, wie viele Dateien geschrieben wurden, und wohin. Null
/// heißt: abgebrochen, es wurde nichts geschrieben.
Future<({int written, String message})?> exportManyBytes(
    List<({Uint8List bytes, String fileName, String mimeType})> files,
    {String suggestedFolderName = ''}) async {
  if (files.isEmpty) return (written: 0, message: 'Nichts zu speichern.');

  if (Platform.isAndroid || Platform.isIOS) {
    final tmp = await getTemporaryDirectory();
    final xfiles = <XFile>[];
    for (final f in files) {
      final file =
          File('${tmp.path}${Platform.pathSeparator}${f.fileName}');
      await file.writeAsBytes(f.bytes);
      xfiles.add(XFile(file.path, mimeType: f.mimeType));
    }
    final result =
        await SharePlus.instance.share(ShareParams(files: xfiles));
    if (result.status == ShareResultStatus.dismissed) return null;
    return (
      written: xfiles.length,
      message: '${xfiles.length} Dateien geteilt bzw. gespeichert.'
    );
  }

  final ordner = await getDirectoryPath(
    confirmButtonText: 'Hier speichern',
  );
  if (ordner == null) return null;

  var geschrieben = 0;
  for (final f in files) {
    // Doppelte Namen nicht stillschweigend überschreiben: Wer zwei
    // gleich benannte Bilder in der Galerie hat, will beide.
    var ziel = File('$ordner${Platform.pathSeparator}${f.fileName}');
    if (await ziel.exists()) {
      final punkt = f.fileName.lastIndexOf('.');
      final stamm =
          punkt <= 0 ? f.fileName : f.fileName.substring(0, punkt);
      final endung = punkt <= 0 ? '' : f.fileName.substring(punkt);
      for (var n = 2; n < 1000; n++) {
        final kandidat =
            File('$ordner${Platform.pathSeparator}$stamm-$n$endung');
        if (!await kandidat.exists()) {
          ziel = kandidat;
          break;
        }
      }
    }
    await ziel.writeAsBytes(f.bytes);
    geschrieben++;
  }
  return (
    written: geschrieben,
    message: '$geschrieben ${geschrieben == 1 ? 'Datei' : 'Dateien'} '
        'gespeichert in $ordner'
  );
}
