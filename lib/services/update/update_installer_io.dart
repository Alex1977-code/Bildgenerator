import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Nur auf dem Desktop lässt sich eine neue Fassung danebenlegen und
/// starten. Auf Android übernimmt das der System-Installer, dorthin
/// führt der Download-Link.
bool get canInstall =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Entpackt die heruntergeladene ZIP-Datei in einen **neuen** Ordner
/// neben der laufenden App und liefert den Pfad zum neuen Programm.
///
/// Bewusst kein Überschreiben: Die laufende Programmdatei lässt sich
/// unter Windows nicht ersetzen, und ein halb überschriebener Ordner
/// wäre schlimmer als zwei nebeneinander. Einstellungen, Schlüssel und
/// Galerie liegen im Benutzerprofil und gelten damit für beide.
Future<String> installUpdate(
  Uint8List archiveBytes,
  String assetName,
  String version,
  void Function(String stage) onProgress,
) async {
  final currentExe = File(Platform.resolvedExecutable);
  final currentDir = currentExe.parent;
  final target =
      Directory('${currentDir.parent.path}${Platform.pathSeparator}'
          '3DGenerator-$version');
  if (target.existsSync()) {
    onProgress('Vorhandener Ordner ${target.path} wird ersetzt …');
    target.deleteSync(recursive: true);
  }
  target.createSync(recursive: true);

  onProgress('Archiv wird entpackt …');
  final archive = ZipDecoder().decodeBytes(archiveBytes);
  var written = 0;
  for (final entry in archive) {
    final path = '${target.path}${Platform.pathSeparator}'
        '${entry.name.replaceAll('/', Platform.pathSeparator)}';
    if (entry.isFile) {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.content as List<int>);
      written++;
      if (written % 50 == 0) onProgress('$written Dateien entpackt …');
    } else {
      Directory(path).createSync(recursive: true);
    }
  }
  onProgress('$written Dateien entpackt.');

  // Die neue Programmdatei suchen – im Wurzelverzeichnis des Archivs
  // oder eine Ebene tiefer, je nachdem wie es gepackt wurde.
  final exeName = currentExe.uri.pathSegments.last;
  final candidates = <String>[
    '${target.path}${Platform.pathSeparator}$exeName',
    for (final dir in target.listSync().whereType<Directory>())
      '${dir.path}${Platform.pathSeparator}$exeName',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  throw Exception('Im entpackten Ordner wurde „$exeName" nicht '
      'gefunden. Die Dateien liegen unter ${target.path} und lassen '
      'sich von Hand starten.');
}

/// Startet die neue Fassung losgelöst; die alte darf sich danach
/// beenden.
Future<void> launchInstalled(String path) async {
  await Process.start(path, const [],
      workingDirectory: File(path).parent.path,
      mode: ProcessStartMode.detached);
}

/// Beendet die laufende (alte) Fassung, nachdem die neue gestartet
/// wurde.
Future<void> quitApp() async {
  exit(0);
}
