import 'dart:io';

import '../roblox_install.dart';

/// Sucht Roblox Studio an den Stellen, an denen der Installer es
/// ablegt. Windows nutzt einen Versionsordner je Installation,
/// deshalb wird der neueste genommen.
Future<RobloxInstall> findRobloxStudio() async {
  try {
    if (Platform.isWindows) return _windows();
    if (Platform.isMacOS) return _macOs();
    return const RobloxInstall(
      found: false,
      note: 'Roblox Studio gibt es nur für Windows und macOS. Die '
          'hier erzeugten Dateien lassen sich auf einem solchen '
          'Rechner weiterverwenden.',
    );
  } catch (e) {
    return RobloxInstall(
        found: false, note: 'Die Suche schlug fehl: $e');
  }
}

RobloxInstall _windows() {
  final local = Platform.environment['LOCALAPPDATA'];
  final candidates = <Directory>[
    if (local != null) Directory('$local\\Roblox\\Versions'),
    Directory('C:\\Program Files (x86)\\Roblox\\Versions'),
    Directory('C:\\Program Files\\Roblox\\Versions'),
  ];
  final hits = <FileSystemEntity>[];
  for (final base in candidates) {
    if (!base.existsSync()) continue;
    for (final entry in base.listSync()) {
      if (entry is! Directory) continue;
      final exe = File('${entry.path}\\RobloxStudioBeta.exe');
      if (exe.existsSync()) hits.add(exe);
    }
  }
  if (hits.isEmpty) {
    return const RobloxInstall(
      found: false,
      note: 'Roblox Studio wurde nicht gefunden. Es ist kostenlos: '
          'create.roblox.com → „Studio herunterladen". Die Dateien '
          'des Pakets bleiben davon unberührt.',
    );
  }
  // Der neueste Versionsordner ist der, der zuletzt geändert wurde.
  hits.sort((a, b) => b.statSync().modified.compareTo(
      a.statSync().modified));
  final exe = hits.first.path;
  final parts = exe.split('\\');
  return RobloxInstall(
    found: true,
    studioPath: exe,
    version: parts.length > 1 ? parts[parts.length - 2] : '',
    note: hits.length > 1
        ? '${hits.length} Fassungen gefunden – die neueste ist '
            'eingetragen.'
        : '',
  );
}

RobloxInstall _macOs() {
  const path = '/Applications/RobloxStudio.app';
  if (Directory(path).existsSync()) {
    return const RobloxInstall(found: true, studioPath: path);
  }
  return const RobloxInstall(
    found: false,
    note: 'Roblox Studio wurde nicht in /Applications gefunden. Es ist '
        'kostenlos: create.roblox.com → „Studio herunterladen".',
  );
}

Future<bool> openRobloxFolder(String path) async {
  try {
    final folder = File(path).parent.path;
    if (Platform.isWindows) {
      await Process.run('explorer', [folder]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [folder]);
    } else {
      await Process.run('xdg-open', [folder]);
    }
    return true;
  } catch (_) {
    return false;
  }
}
