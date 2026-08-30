/// Findet eine vorhandene Roblox-Studio-Installation.
///
/// Nur auf dem Desktop sinnvoll: In der Web-Version gibt es keinen
/// Dateizugriff, dort meldet die Prüfung schlicht „nicht prüfbar".
library;

import 'roblox/roblox_install_web.dart'
    if (dart.library.io) 'roblox/roblox_install_io.dart' as impl;

/// Was über eine Roblox-Installation bekannt ist.
class RobloxInstall {
  const RobloxInstall({
    required this.found,
    this.studioPath = '',
    this.version = '',
    this.note = '',
  });

  /// Ob Roblox Studio gefunden wurde.
  final bool found;

  /// Pfad zur Studio-Anwendung.
  final String studioPath;

  /// Versionsordner, soweit erkennbar.
  final String version;

  /// Erklärung, wenn nichts gefunden wurde oder nicht gesucht werden
  /// konnte.
  final String note;
}

/// Sucht Roblox Studio an den üblichen Stellen.
Future<RobloxInstall> findRobloxStudio() => impl.findRobloxStudio();

/// Öffnet den Ordner der Installation im Dateimanager.
Future<bool> openRobloxFolder(String path) => impl.openRobloxFolder(path);
