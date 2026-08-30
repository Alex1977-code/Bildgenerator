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
}) async* {
  yield '\$ $executable ${arguments.join(' ')}';
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
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
  yield* lines.stream;
  final code = await process.exitCode;
  if (code != 0) {
    throw Exception('„$executable ${arguments.join(' ')}" endete mit '
        'Fehlercode $code.');
  }
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
}) async* {
  final dir = Directory(targetDir);
  final parent = dir.parent;
  if (!parent.existsSync()) {
    yield '# Ordner wird angelegt: ${parent.path}';
    parent.createSync(recursive: true);
  }

  if (Directory('$targetDir${Platform.pathSeparator}tsr').existsSync()) {
    yield '# TripoSR ist bereits vorhanden – überspringe das Klonen.';
  } else {
    yield '# 1/6 TripoSR wird geladen (~37 MB)';
    yield* _run(
      'git',
      [
        'clone',
        'https://github.com/VAST-AI-Research/TripoSR.git',
        targetDir,
      ],
    );
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
  await _download(shimUrl, File('$targetDir${sep}torchmcubes.py'));
  yield 'torchmcubes.py (CPU-Ersatz, kein CUDA-Toolkit nötig)';
  await _download(
      requirementsUrl, File('$targetDir${sep}requirements-triposr.txt'));
  yield 'requirements-triposr.txt';
  await _download(serverScriptUrl, File('$targetDir${sep}local3d_server.py'));
  yield 'local3d_server.py';

  yield '# 5/6 Restliche Pakete werden installiert (~1 GB)';
  yield* _run(
    venvPython,
    ['-m', 'pip', 'install', '-r', 'requirements-triposr.txt'],
    workingDirectory: targetDir,
  );

  yield '# 6/6 Installation wird geprüft';
  yield* _run(
    venvPython,
    [
      '-c',
      "import importlib.util as u; miss=[m for m in "
          "['numpy','PIL','torch','torchmcubes','transformers','trimesh',"
          "'omegaconf','einops','rembg','skimage'] if not u.find_spec(m)]; "
          "print('FEHLT: '+', '.join(miss) if miss else "
          "'Alle Pakete vorhanden.')",
    ],
    workingDirectory: targetDir,
  );
  yield '# Fertig. Der Server kann jetzt gestartet werden.';
}

/// Startet den Server als eigenständigen Prozess und liefert eine
/// kurze Bestätigung. Der Prozess läuft weiter, auch wenn die App
/// geschlossen wird.
Future<String> startServer({
  required String targetDir,
  required int port,
}) async {
  final venvPython = _venvPython(targetDir);
  if (!File(venvPython).existsSync()) {
    throw Exception('Im Ordner „$targetDir" wurde keine eingerichtete '
        'Python-Umgebung gefunden. Bitte zuerst installieren.');
  }
  await Process.start(
    venvPython,
    ['local3d_server.py', '--backend', 'triposr', '--port', '$port'],
    workingDirectory: targetDir,
    mode: ProcessStartMode.detached,
  );
  return 'Server gestartet auf http://127.0.0.1:$port – der erste Lauf '
      'lädt einmalig die Modellgewichte (~1,7 GB).';
}
