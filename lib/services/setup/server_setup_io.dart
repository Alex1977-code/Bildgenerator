import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Der Assistent läuft nur auf dem Desktop – auf Android/iOS gibt es
/// weder Python noch eine passende GPU.
bool get setupSupported =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Vorschlag für den Zielordner: unter Windows ein eigener Ordner auf
/// C:, sonst im Benutzerverzeichnis.
String defaultTargetDir() {
  if (Platform.isWindows) return r'C:\KI\TripoSR';
  final home = Platform.environment['HOME'] ?? '';
  return home.isEmpty ? 'ki/TripoSR' : '$home/ki/TripoSR';
}

/// Kandidaten für eine Python-3.11-Installation, absteigend nach
/// Verlässlichkeit. Der erste Treffer, der sich wirklich als 3.11
/// meldet, wird verwendet.
Future<List<String>> pythonCandidates() async {
  if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    return [
      if (local.isNotEmpty)
        '$local\\Programs\\Python\\Python311\\python.exe',
      r'C:\Program Files\Python311\python.exe',
      r'C:\Python311\python.exe',
    ];
  }
  return ['python3.11', '/usr/bin/python3.11', '/usr/local/bin/python3.11'];
}

Future<String?> _versionOf(String exe) async {
  try {
    final result = await Process.run(exe, ['--version']);
    if (result.exitCode != 0) return null;
    final out = '${result.stdout}${result.stderr}'.trim();
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

/// Prüft die Voraussetzungen. Rückgabe je Schlüssel: Beschreibung des
/// Fundes oder null, wenn nichts gefunden wurde.
/// Schlüssel: 'python' (Pfad|Version), 'git', 'gpu'.
Future<Map<String, String?>> checkPrerequisites() async {
  String? python;
  for (final candidate in await pythonCandidates()) {
    final version = await _versionOf(candidate);
    if (version != null && version.contains('3.11')) {
      python = '$candidate|$version';
      break;
    }
  }
  String? git;
  try {
    final result = await Process.run('git', ['--version']);
    if (result.exitCode == 0) git = result.stdout.toString().trim();
  } catch (_) {}
  String? gpu;
  try {
    final result = await Process.run(
        'nvidia-smi', ['--query-gpu=name,memory.total', '--format=csv,noheader']);
    if (result.exitCode == 0) {
      final line = result.stdout.toString().trim().split('\n').first.trim();
      if (line.isNotEmpty) gpu = line;
    }
  } catch (_) {}
  return {'python': python, 'git': git, 'gpu': gpu};
}

String _venvPython(String targetDir) => Platform.isWindows
    ? '$targetDir\\.venv\\Scripts\\python.exe'
    : '$targetDir/.venv/bin/python';

/// Führt einen Schritt aus und gibt seine Ausgabe zeilenweise weiter.
Stream<String> _run(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String> environment = const {},
}) async* {
  yield '\$ $executable ${arguments.join(' ')}';
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment.isEmpty ? null : environment,
    runInShell: false,
  );
  final lines = StreamController<String>();
  var open = 2;
  void pipe(Stream<List<int>> source) {
    source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(lines.add, onDone: () {
      if (--open == 0) lines.close();
    }, onError: (Object e) => lines.add('$e'));
  }

  pipe(process.stdout);
  pipe(process.stderr);
  // Zwei Sammlungen für die Fehlermeldung: die auffälligen Zeilen
  // (Compiler, Linker, pip) und die letzten Zeilen überhaupt – sonst
  // geht die eigentliche Ursache im langen Protokoll unter.
  final flagged = <String>[];
  final lastLines = <String>[];
  final pattern = RegExp(
      r'\berror\b|\bERROR\b|Fehler|unresolved|nicht aufgel|LNK\d|'
      r'fatal|Traceback',
      caseSensitive: false);
  await for (final line in lines.stream) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && pattern.hasMatch(trimmed)) {
      flagged.add(trimmed);
      if (flagged.length > 8) flagged.removeAt(0);
    }
    if (trimmed.isNotEmpty) {
      lastLines.add(trimmed);
      if (lastLines.length > 12) lastLines.removeAt(0);
    }
    yield line;
  }
  final code = await process.exitCode;
  if (code != 0) {
    final reason = <String>[
      if (flagged.isNotEmpty) ...flagged,
      if (flagged.isEmpty && lastLines.isNotEmpty) ...lastLines,
    ];
    throw Exception('„${arguments.join(' ')}" endete mit Fehlercode '
        '$code.${reason.isEmpty ? '' : '\n${reason.join('\n')}'}');
  }
}

/// SF3D und SPAR3D bringen zwei C++-Erweiterungen mit
/// (`texture_baker`, `uv_unwrapper`). Unter Windows scheitert
/// `uv_unwrapper` daran, dass `bvh.cpp` `std::make_tuple` und
/// `std::exchange` nutzt, ohne die zugehörigen Header einzubinden –
/// GCC zieht sie nebenbei mit herein, MSVC nicht. Bekanntes Problem
/// im Projekt (Stability-AI/stable-fast-3d, Issue 45); wir ergänzen
/// die beiden Zeilen vor dem Bauen.
Iterable<String> _patchNativeSources(String targetDir) sync* {
  final sep = Platform.pathSeparator;
  final file = File('$targetDir${sep}uv_unwrapper$sep'
      'uv_unwrapper${sep}csrc${sep}bvh.cpp');
  if (!file.existsSync()) return;
  final code = file.readAsStringSync();
  final missing = <String>[
    if (!code.contains('#include <tuple>')) '#include <tuple>',
    if (!code.contains('#include <utility>')) '#include <utility>',
  ];
  if (missing.isEmpty) {
    yield 'bvh.cpp: Header sind bereits vorhanden.';
    return;
  }
  final lines = code.split('\n');
  var last = -1;
  for (var i = 0; i < lines.length && i < 60; i++) {
    if (lines[i].trimLeft().startsWith('#include')) last = i;
  }
  if (last < 0) return;
  lines.insertAll(last + 1, missing);
  file.writeAsStringSync(lines.join('\n'));
  yield 'bvh.cpp ergänzt um ${missing.join(' und ')} '
      '(MSVC braucht die Header ausdrücklich).';
}

/// Umgebung für das Bauen der C++-Erweiterungen. Unter Windows
/// übersetzt MSVC sonst nach C++14, während die PyTorch-Header C++17
/// verlangen – daraus werden unverständliche Vorlagen-Fehler. Über die
/// Variable CL hängt cl.exe den Schalter an jeden Aufruf an.
Map<String, String> _buildEnvironment() {
  if (!Platform.isWindows) return const {};
  final existing = Platform.environment['CL'] ?? '';
  // /openmp schaltet die parallelen Schleifen des Quellcodes scharf
  // (MSVC bindet dann vcomp selbst ein).
  const flags = '/std:c++17 /openmp';
  return {
    ...Platform.environment,
    'CL': existing.isEmpty ? flags : '$existing $flags',
  };
}

Future<void> _download(String url, File target) async {
  final client = HttpClient();
  try {
    var uri = Uri.parse(url);
    HttpClientResponse response;
    // Bis zu 5 Weiterleitungen selbst folgen (raw.githubusercontent
    // leitet je nach Region um).
    for (var hop = 0;; hop++) {
      final request = await client.getUrl(uri);
      response = await request.close();
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null &&
          hop < 5) {
        uri = uri.resolve(location);
        continue;
      }
      break;
    }
    if (response.statusCode != 200) {
      throw Exception('Download fehlgeschlagen (${response.statusCode}): '
          '$url');
    }
    await response.pipe(target.openWrite());
  } finally {
    client.close();
  }
}

/// Richtet TripoSR im Zielordner ein und meldet den Fortschritt
/// zeilenweise. Bricht mit einer Ausnahme ab, sobald ein Schritt
/// fehlschlägt.
Stream<String> installServer({
  required String targetDir,
  required String serverScriptUrl,
  required String shimUrl,
  required String requirementsUrl,
  required String pythonExe,
  String backend = 'sf3d',
  String repoUrl = 'https://github.com/Stability-AI/stable-fast-3d.git',
}) async* {
  final dir = Directory(targetDir);
  final parent = dir.parent;
  if (!parent.existsSync()) {
    yield '# Ordner wird angelegt: ${parent.path}';
    parent.createSync(recursive: true);
  }

  final isImage = backend == 'sd-image';
  // Paketordner des jeweiligen Modells – daran erkennen wir, ob das
  // Repository schon geholt wurde.
  final packageDir = switch (backend) {
    'triposr' => 'tsr',
    'spar3d' => 'spar3d',
    _ => 'sf3d',
  };
  if (isImage) {
    // Der Bild-Server braucht kein Repository: Alles kommt als
    // fertiges Paket von PyPI.
    if (!dir.existsSync()) dir.createSync(recursive: true);
    yield '# 1/6 Kein Quellcode nötig – die Bild-Modelle kommen als '
        'fertige Pakete.';
  } else if (Directory('$targetDir${Platform.pathSeparator}$packageDir')
      .existsSync()) {
    yield '# Das Modell ist bereits vorhanden – überspringe das Klonen.';
  } else {
    yield '# 1/6 Modell-Quellcode wird geladen';
    yield* _run('git', ['clone', repoUrl, targetDir]);
  }

  final venvPython = _venvPython(targetDir);
  if (File(venvPython).existsSync()) {
    yield '# Python-Umgebung ist bereits vorhanden.';
  } else {
    yield '# 2/6 Python-Umgebung wird angelegt';
    yield* _run(pythonExe, ['-m', 'venv', '.venv'],
        workingDirectory: targetDir);
  }

  yield '# 3/6 PyTorch mit CUDA wird installiert (~2,4 GB – dauert)';
  yield* _run(
    venvPython,
    [
      '-m',
      'pip',
      'install',
      'torch',
      '--index-url',
      'https://download.pytorch.org/whl/cu121',
    ],
    workingDirectory: targetDir,
  );

  yield '# 4/6 Hilfsdateien werden geladen';
  final sep = Platform.pathSeparator;
  const listName = 'requirements-server.txt';
  if (backend == 'triposr') {
    // Nur TripoSR baut torchmcubes und braucht deshalb den CPU-Ersatz.
    await _download(shimUrl, File('$targetDir${sep}torchmcubes.py'));
    yield 'torchmcubes.py (CPU-Ersatz, kein CUDA-Toolkit nötig)';
  }
  await _download(requirementsUrl, File('$targetDir$sep$listName'));
  yield listName;
  final scriptName =
      isImage ? 'local_image_server.py' : 'local3d_server.py';
  await _download(serverScriptUrl, File('$targetDir$sep$scriptName'));
  yield scriptName;

  yield '# 5/6 Restliche Pakete werden installiert (~1 GB)';
  if (backend != 'triposr' && !isImage) {
    // SF3D und SPAR3D bringen eine eigene Liste mit. Sie enthält zwei
    // eigene C++-Erweiterungen (texture_baker, uv_unwrapper), die
    // PyTorch bereits beim Bauen brauchen. pip kapselt den Bauvorgang
    // normalerweise ab – dort fehlt torch, und der Lauf bricht mit
    // „Getting requirements to build wheel did not run successfully"
    // ab. Deshalb: Bau-Werkzeuge sicherstellen und die Abkapselung
    // abschalten, damit das eben installierte torch sichtbar ist.
    if (File('$targetDir${sep}requirements.txt').existsSync()) {
      yield '# Bau-Werkzeuge werden vorbereitet';
      yield* _run(
        venvPython,
        ['-m', 'pip', 'install', '-U', 'pip', 'setuptools', 'wheel'],
        workingDirectory: targetDir,
      );
      yield '# Quellcode der C++-Erweiterungen wird geprüft';
      for (final line in _patchNativeSources(targetDir)) {
        yield line;
      }
      // Zwischenstände eines früheren Versuchs wegräumen: Sonst
      // verwendet setuptools die alten Objektdateien weiter, und
      // geänderte Compiler-Schalter bleiben wirkungslos.
      for (final name in const ['uv_unwrapper', 'texture_baker']) {
        final build =
            Directory('$targetDir$sep$name${sep}build');
        if (build.existsSync()) {
          build.deleteSync(recursive: true);
          yield 'Alten Bau-Zwischenstand entfernt: $name/build';
        }
      }
      yield '# Modell-Abhängigkeiten (ohne Bau-Abkapselung, damit die '
          'C++-Erweiterungen PyTorch finden)';
      yield* _run(
        venvPython,
        [
          '-m',
          'pip',
          'install',
          '-r',
          'requirements.txt',
          '--no-build-isolation',
        ],
        workingDirectory: targetDir,
        environment: _buildEnvironment(),
      );
    }
  }
  yield* _run(
    venvPython,
    ['-m', 'pip', 'install', '-r', listName],
    workingDirectory: targetDir,
  );

  yield '# 6/6 Installation wird geprüft';
  final needed = switch (backend) {
    'sd-image' =>
      "['torch','diffusers','transformers','PIL','safetensors','rembg']",
    'triposr' =>
      "['numpy','PIL','torch','torchmcubes','transformers','trimesh',"
          "'omegaconf','einops','rembg','skimage']",
    _ => "['numpy','PIL','torch','trimesh','rembg','$packageDir']",
  };
  yield* _run(
    venvPython,
    [
      '-c',
      'import importlib.util as u; miss=[m for m in $needed '
          'if not u.find_spec(m)]; '
          "print('FEHLT: '+', '.join(miss) if miss else "
          "'Alle Pakete vorhanden.')",
    ],
    workingDirectory: targetDir,
  );
  if (isImage) {
    yield '# Hinweis: SD 1.5, SDXL und SDXL Turbo laufen ohne Anmeldung. '
        'SD 3.5 und FLUX verlangen einmalig eine Lizenz-Zustimmung auf '
        'huggingface.co und ein "huggingface-cli login" in dieser '
        'Umgebung.';
  } else if (backend != 'triposr') {
    yield '# Hinweis: Die Modellgewichte sind auf Hugging Face '
        'freigabepflichtig. Einmalig die Lizenz auf der Modellseite '
        'bestätigen und in dieser Umgebung "huggingface-cli login" '
        'ausführen, sonst schlägt der erste Lauf fehl.';
  }
  yield '# Fertig. Der Server kann jetzt gestartet werden.';
}

/// Startet den Server als eigenständigen Prozess und liefert eine
/// kurze Bestätigung. Der Prozess läuft weiter, auch wenn die App
/// geschlossen wird.
Future<String> startServer({
  required String targetDir,
  required int port,
  String backend = 'sf3d',
}) async {
  final venvPython = _venvPython(targetDir);
  if (!File(venvPython).existsSync()) {
    throw Exception('Im Ordner „$targetDir" wurde keine eingerichtete '
        'Python-Umgebung gefunden. Bitte zuerst installieren.');
  }
  final isImage = backend == 'sd-image';
  await Process.start(
    venvPython,
    isImage
        ? ['local_image_server.py', '--port', '$port']
        : ['local3d_server.py', '--backend', backend, '--port', '$port'],
    workingDirectory: targetDir,
    mode: ProcessStartMode.detached,
  );
  return 'Server gestartet auf http://127.0.0.1:$port – der erste Lauf '
      'lädt einmalig die Modellgewichte '
      '${isImage ? '(je nach Modell 2–24 GB)' : '(~1,7 GB)'}.';
}

/// Übliche Ordnernamen je Backend – der Assistent legt sie so an.
const _folderNames = <String, List<String>>{
  'triposr': ['TripoSR', 'TRIPOSR', 'triposr'],
  'sf3d': ['SF3D', 'sf3d', 'stable-fast-3d'],
  'spar3d': ['SPAR3D', 'spar3d', 'stable-point-aware-3d'],
  'trellis': ['TRELLIS', 'trellis'],
  'sd-image': ['SD-Bilder', 'SD-BILDER', 'sd-image'],
};

/// Ein Ordner gilt als eingerichtet, wenn dort eine Python-Umgebung
/// und das passende Server-Skript liegen.
bool _looksInstalled(String dir, String script) =>
    File(_venvPython(dir)).existsSync() &&
    File('$dir${Platform.pathSeparator}$script').existsSync();

/// Sucht neben dem Standard-Zielordner nach fertigen Installationen.
Future<List<(String, String)>> detectInstalledServers(
    List<String> backends) async {
  final base = defaultTargetDir();
  final cut = base.lastIndexOf(RegExp(r'[\\/]'));
  if (cut < 0) return const [];
  final parent = base.substring(0, cut + 1);
  final found = <(String, String)>[];
  for (final id in backends) {
    for (final folder in _folderNames[id] ?? [id]) {
      final dir = '$parent$folder';
      final script = id == 'sd-image'
          ? 'local_image_server.py'
          : 'local3d_server.py';
      if (_looksInstalled(dir, script)) {
        found.add((id, dir));
        break;
      }
    }
  }
  return found;
}


/// Schreibt das Einrichtungs-Protokoll in den Zielordner, damit es sich
/// in Ruhe ansehen (und weitergeben) lässt. Liefert den Pfad.
Future<String?> saveSetupLog(String targetDir, List<String> lines) async {
  try {
    final dir = Directory(targetDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file =
        File('$targetDir${Platform.pathSeparator}einrichtung-protokoll.txt');
    await file.writeAsString(lines.join(Platform.lineTerminator));
    return file.path;
  } catch (_) {
    return null;
  }
}
