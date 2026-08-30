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
  final bvh = File('$targetDir${sep}uv_unwrapper$sep'
      'uv_unwrapper${sep}csrc${sep}bvh.cpp');
  if (bvh.existsSync()) {
    final code = bvh.readAsStringSync();
    final missing = <String>[
      if (!code.contains('#include <tuple>')) '#include <tuple>',
      if (!code.contains('#include <utility>')) '#include <utility>',
    ];
    if (missing.isEmpty) {
      yield 'bvh.cpp: Header sind bereits vorhanden.';
    } else {
      final lines = code.split('\n');
      var last = -1;
      for (var i = 0; i < lines.length && i < 60; i++) {
        if (lines[i].trimLeft().startsWith('#include')) last = i;
      }
      if (last >= 0) {
        lines.insertAll(last + 1, missing);
        bvh.writeAsStringSync(lines.join('\n'));
        yield 'bvh.cpp ergänzt um ${missing.join(' und ')} '
            '(MSVC braucht die Header ausdrücklich).';
      }
    }
  }
  if (!Platform.isWindows) return;
  // Jede Python-Erweiterung braucht unter Windows eine Init-Funktion
  // PyInit_<Modul>; der Linker verlangt sie ausdrücklich
  // (/EXPORT:PyInit__C). SF3D und SPAR3D bringen dafür
  // PYBIND11_MODULE(TORCH_EXTENSION_NAME, m) mit – das genügt, solange
  // PyTorch beim Übersetzen -DTORCH_EXTENSION_NAME=_C mitgibt (siehe
  // _buildEnvironment). Fehlt die Zeile in einem anderen Projekt ganz,
  // hängen wir die vom PyTorch-Handbuch vorgesehene Minimal-Fassung an.
  for (final (package, file) in const [
    ('uv_unwrapper', 'unwrapper.cpp'),
    ('texture_baker', 'baker.cpp'),
  ]) {
    final dir = Directory('$targetDir$sep$package$sep$package${sep}csrc');
    if (!dir.existsSync()) continue;
    // Schon eine Init-Funktion vorhanden (eigene oder über pybind11)?
    String? found;
    for (final entry in dir.listSync()) {
      if (entry is! File) continue;
      final name = entry.path.toLowerCase();
      if (!name.endsWith('.cpp') && !name.endsWith('.cu')) continue;
      final text = entry.readAsStringSync();
      final marker = text.contains('PYBIND11_MODULE')
          ? 'PYBIND11_MODULE'
          : (text.contains('PyInit_') ? 'PyInit_' : null);
      if (marker != null) {
        found = '${entry.uri.pathSegments.last}: $marker';
        break;
      }
    }
    if (found != null) {
      yield '$package: Modul-Init ist vorhanden ($found).';
      continue;
    }
    final target = File('${dir.path}$sep$file');
    if (!target.existsSync()) continue;
    target.writeAsStringSync(
      '\n\n// Vom 3DGenerator ergänzt: Windows verlangt eine\n'
      '// Modul-Init-Funktion, sonst bricht der Linker ab.\n'
      '#ifdef _WIN32\n'
      '#include <Python.h>\n'
      'extern "C" {\n'
      'PyObject *PyInit__C(void) {\n'
      '  static struct PyModuleDef module_def = {\n'
      '      PyModuleDef_HEAD_INIT, "_C", NULL, -1, NULL,\n'
      '      NULL, NULL, NULL, NULL,\n'
      '  };\n'
      '  return PyModule_Create(&module_def);\n'
      '}\n'
      '}\n'
      '#endif\n',
      mode: FileMode.append,
    );
    yield '$package/$file um die Windows-Modul-Init ergänzt '
        '(behebt „LNK2001: PyInit__C").';
  }
}

/// Umgebung für das Bauen der C++-Erweiterungen.
///
/// Wir rufen `python` aus der virtuellen Umgebung direkt auf, statt sie
/// vorher zu aktivieren. Dadurch fehlt der Umgebung dreierlei – der
/// PATH-Eintrag auf allen Systemen, die beiden Compiler-Schalter nur
/// unter Windows:
///
/// 1. **PATH**: `ninja` liegt in `.venv\Scripts` (Windows) bzw.
///    `.venv/bin`. Ohne diesen Eintrag findet PyTorch das Werkzeug
///    nicht, fällt auf den alten distutils-Weg zurück – und der
///    schickt `.cu`-Dateien an cl.exe
///    („blockIdx: nicht deklarierter Bezeichner") und verliert dabei
///    auch `-DTORCH_EXTENSION_NAME=_C`, worauf der Linker mit
///    „LNK2001: PyInit__C" abbricht. Mit ninja stimmt beides.
/// 2. **CL**: MSVC übersetzt sonst nach C++14, die PyTorch-Header
///    verlangen C++17.
/// 3. **NVCC_PREPEND_FLAGS**: CUDA 12.x lehnt neuere MSVC-Fassungen
///    sonst rundheraus ab.
///
/// Dazu kommt unter Windows die Umgebung der Build-Tools (siehe
/// [_msvcEnvironment]), damit ninja `cl.exe` findet.
Future<Map<String, String>> _buildEnvironment(String targetDir) async {
  final sep = Platform.pathSeparator;
  // Platform.environment ist unter Windows unabhängig von Groß- und
  // Kleinschreibung, die Kopie ist es nicht. Deshalb ersetzen wir
  // Einträge immer über [_replace], sonst stehen am Ende „Path" und
  // „PATH" nebeneinander und Windows nimmt den falschen.
  final env = <String, String>{...Platform.environment};
  for (final entry in (await _msvcEnvironment()).entries) {
    _replace(env, entry.key, entry.value);
  }
  final scripts = Platform.isWindows
      ? '$targetDir$sep.venv${sep}Scripts'
      : '$targetDir$sep.venv${sep}bin';
  final listSep = Platform.isWindows ? ';' : ':';
  final oldPath = _lookup(env, 'PATH') ?? '';
  _replace(env, 'PATH',
      oldPath.isEmpty ? scripts : '$scripts$listSep$oldPath');
  if (!Platform.isWindows) return env;

  // /openmp schaltet die parallelen Schleifen des Quellcodes scharf
  // (MSVC bindet dann vcomp selbst ein). Die Modulkennung ist ein
  // Sicherheitsnetz: Setzt PyTorch sie selbst (ninja-Weg), gewinnt der
  // Wert von der Befehlszeile, weil CL davor eingefügt wird.
  // PyTorch bricht den Bau ab, sobald es die Build-Tools-Umgebung
  // sieht (VSCMD_ARG_TGT_ARCH), ohne dass DISTUTILS_USE_SDK gesetzt
  // ist: „It seems that the VC environment is activated but
  // DISTUTILS_USE_SDK is not set." Gemeint ist damit, dass setuptools
  // den Compiler **nicht** noch einmal selbst suchen soll – sonst
  // liefe vcvars zweimal übereinander. Genau das wollen wir hier:
  // Die Umgebung steht schon, cl.exe und die Bibliothekspfade
  // stimmen. MSSdk gehört als zweiter Schalter dazu.
  _replace(env, 'DISTUTILS_USE_SDK', '1');
  _replace(env, 'MSSdk', '1');

  const flags = '/std:c++17 /openmp /DTORCH_EXTENSION_NAME=_C';
  final existing = _lookup(env, 'CL') ?? '';
  _replace(env, 'CL', existing.isEmpty ? flags : '$existing $flags');
  _replace(
      env,
      'NVCC_PREPEND_FLAGS',
      '${_lookup(env, 'NVCC_PREPEND_FLAGS') ?? ''} '
              '-allow-unsupported-compiler'
          .trim());
  return env;
}

/// Wert einer Umgebungsvariablen, unabhängig von Groß- und
/// Kleinschreibung.
String? _lookup(Map<String, String> env, String name) {
  final wanted = name.toLowerCase();
  for (final entry in env.entries) {
    if (entry.key.toLowerCase() == wanted) return entry.value;
  }
  return null;
}

/// Setzt eine Umgebungsvariable und entfernt vorher alle Schreibweisen
/// desselben Namens.
void _replace(Map<String, String> env, String name, String value) {
  final wanted = name.toLowerCase();
  env.removeWhere((key, _) => key.toLowerCase() == wanted);
  env[name] = value;
}

/// Die Umgebung der Visual-Studio-Build-Tools (cl.exe, link.exe sowie
/// INCLUDE und LIB). distutils sucht sich den Compiler selbst über
/// vswhere; ninja dagegen ruft schlicht `cl` auf und braucht ihn
/// deshalb im Suchpfad. Wir holen die Werte so, wie es die
/// „Entwickler-Eingabeaufforderung" tut: vcvars64.bat aufrufen und
/// anschließend `set` auslesen.
///
/// Findet sich nichts, bleibt die Umgebung unverändert – der Bau kann
/// dann immer noch klappen, weil PyTorch dasselbe notfalls selbst
/// versucht.
Future<Map<String, String>> _msvcEnvironment() async {
  if (!Platform.isWindows) return const {};
  final programFiles = Platform.environment['ProgramFiles(x86)'] ??
      r'C:\Program Files (x86)';
  final vswhere = File('$programFiles\\Microsoft Visual Studio\\Installer'
      '\\vswhere.exe');
  if (!vswhere.existsSync()) return const {};
  String install;
  try {
    final found = await Process.run(vswhere.path, const [
      '-latest',
      '-products',
      '*',
      '-requires',
      'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
      '-property',
      'installationPath',
    ]);
    install = (found.stdout as String).trim().split('\n').first.trim();
  } catch (_) {
    return const {};
  }
  if (install.isEmpty) return const {};
  final vcvars = File('$install\\VC\\Auxiliary\\Build\\vcvars64.bat');
  if (!vcvars.existsSync()) return const {};

  // Umweg über eine Stapeldatei: „call … && set" direkt an cmd.exe zu
  // übergeben scheitert sonst an den Anführungszeichen im Pfad.
  final helper = File('${Directory.systemTemp.path}\\'
      'kigenerator-vcvars-${pid.toString()}.bat');
  try {
    helper.writeAsStringSync(
        '@echo off\r\ncall "${vcvars.path}" x64 >nul\r\nset\r\n');
    final dump = await Process.run('cmd.exe', ['/c', helper.path]);
    final text = dump.stdout is String ? dump.stdout as String : '';
    final env = <String, String>{};
    for (final line in text.split('\n')) {
      final at = line.indexOf('=');
      if (at <= 0) continue;
      env[line.substring(0, at).trim()] = line.substring(at + 1).trimRight();
    }
    // Nur übernehmen, wenn die Ausgabe wirklich nach Build-Umgebung
    // aussieht – sonst lieber gar nichts ändern.
    final hasInclude = env.keys.any((k) => k.toLowerCase() == 'include');
    final hasPath = env.keys.any((k) => k.toLowerCase() == 'path');
    if (!hasInclude || !hasPath) return const {};
    return env;
  } catch (_) {
    return const {};
  } finally {
    if (helper.existsSync()) {
      try {
        helper.deleteSync();
      } catch (_) {}
    }
  }
}

/// Prüft, ob PyTorch in dieser Umgebung `ninja` findet. PyTorch sucht
/// es genau so – über den PATH des Kindprozesses.
Future<bool> _ninjaVisible(
    String python, String targetDir, Map<String, String> environment) async {
  try {
    final result = await Process.run(
      python,
      [
        '-c',
        'import shutil, sys; sys.exit(0 if shutil.which("ninja") else 1)',
      ],
      workingDirectory: targetDir,
      environment: environment.isEmpty ? null : environment,
    );
    return result.exitCode == 0;
  } catch (_) {
    return false;
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

/// Holt nur die Server-Dateien neu (Skript, Paketliste, ggf. den
/// CPU-Ersatz) – ohne Python-Umgebung, ohne pip. Damit passt ein schon
/// eingerichteter Server wieder zur aktuellen App, wenn deren
/// Server-Skript weiterentwickelt wurde. Liefert die Dateinamen.
Future<List<String>> refreshServerFiles({
  required String targetDir,
  required String serverScriptUrl,
  required String requirementsUrl,
  String? shimUrl,
  String backend = 'sf3d',
}) async {
  final dir = Directory(targetDir);
  if (!dir.existsSync()) {
    throw Exception('Der Ordner $targetDir existiert nicht mehr. Der '
        'Server wurde wohl verschoben oder gelöscht – bitte den '
        'Einrichtungs-Assistenten erneut starten.');
  }
  final sep = Platform.pathSeparator;
  final written = <String>[];
  final scriptName =
      backend == 'sd-image' ? 'local_image_server.py' : 'local3d_server.py';
  await _download(serverScriptUrl, File('$targetDir$sep$scriptName'));
  written.add(scriptName);
  const listName = 'requirements-server.txt';
  await _download(requirementsUrl, File('$targetDir$sep$listName'));
  written.add(listName);
  if (backend == 'triposr' && shimUrl != null) {
    await _download(shimUrl, File('$targetDir${sep}torchmcubes.py'));
    written.add('torchmcubes.py');
  }
  return written;
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
      // torchvision gehört aus derselben Quelle: Wird es später aus
      // requirements.txt nachgezogen, verlangt die dortige Fassung ein
      // neueres torch – und pip tauscht das eben installierte
      // CUDA-Paket gegen eine CPU-Fassung aus. Die GPU wäre danach
      // stumm, ohne dass eine Fehlermeldung darauf hinweist.
      'torchvision',
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
      yield '# Bau-Werkzeuge werden vorbereitet (mit ninja – ohne das '
          'schickt PyTorch die CUDA-Dateien an den falschen Compiler)';
      yield* _run(
        venvPython,
        ['-m', 'pip', 'install', '-U', 'pip', 'setuptools', 'wheel', 'ninja'],
        workingDirectory: targetDir,
      );
      // NumPy vor dem Bauen: Ohne es meldet torch beim ersten Import
      // „Failed to initialize NumPy" und die Erweiterungen werden
      // ohne NumPy-Anbindung übersetzt. Unter 2, weil torch 2.5.1
      // gegen die NumPy-1-Schnittstelle gebaut ist.
      yield '# NumPy vorab (torch braucht es schon beim Bauen)';
      yield* _run(
        venvPython,
        ['-m', 'pip', 'install', 'numpy<2'],
        workingDirectory: targetDir,
      );
      // ninja liegt danach in .venv\Scripts. Wir rufen python.exe von
      // dort direkt auf, ohne die Umgebung zu aktivieren – deshalb muss
      // das Verzeichnis ausdrücklich in den PATH, sonst sucht PyTorch
      // vergeblich. Diese Prüfung sagt vor dem langen Bauen Bescheid.
      final buildEnv = await _buildEnvironment(targetDir);
      if (Platform.isWindows) {
        yield _lookup(buildEnv, 'VSCMD_ARG_TGT_ARCH') != null
            ? 'Build-Tools-Umgebung geladen – ninja findet cl.exe, '
                'DISTUTILS_USE_SDK ist gesetzt.'
            : 'Hinweis: Die Build-Tools-Umgebung ließ sich nicht laden; '
                'PyTorch versucht es notfalls selbst.';
      }
      if (await _ninjaVisible(venvPython, targetDir, buildEnv)) {
        yield 'ninja ist für PyTorch sichtbar – CUDA-Dateien gehen an '
            'nvcc, und die Modulkennung stimmt.';
      } else {
        yield 'Warnung: ninja ist trotz Installation nicht auffindbar. '
            'Der Bau läuft weiter, kann aber an „blockIdx" oder '
            '„LNK2001: PyInit__C" scheitern.';
      }
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
        environment: buildEnv,
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
  String imageModel = '',
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
        ? [
            'local_image_server.py',
            '--port',
            '$port',
            // Das im Bild-Tab gewählte Modell gleich vorwählen. Sonst
            // startet der Server mit seiner Vorgabe (sdxl-turbo) und
            // lädt beim ersten Bild ein zweites Mal.
            if (imageModel.isNotEmpty) ...['--model', imageModel],
          ]
        : ['local3d_server.py', '--backend', backend, '--port', '$port'],
    workingDirectory: targetDir,
    mode: ProcessStartMode.detached,
  );
  return 'Server gestartet auf http://127.0.0.1:$port'
      '${isImage && imageModel.isNotEmpty ? ' mit $imageModel' : ''} – '
      'der erste Lauf lädt einmalig die Modellgewichte '
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
