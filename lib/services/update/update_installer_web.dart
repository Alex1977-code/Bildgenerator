import 'dart:typed_data';

/// Web: Es gibt nichts zu installieren – ein Neuladen der Seite
/// (Strg+F5) holt die neue Fassung.
const bool canInstall = false;

Future<String> installUpdate(
  Uint8List archiveBytes,
  String assetName,
  String version,
  void Function(String stage) onProgress,
) async =>
    throw UnsupportedError('Nur in der Desktop-App verfügbar.');

Future<void> launchInstalled(String path) async =>
    throw UnsupportedError('Nur in der Desktop-App verfügbar.');

Future<void> quitApp() async {}
