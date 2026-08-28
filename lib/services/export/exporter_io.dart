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
