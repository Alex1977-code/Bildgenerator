/// Grafische Einrichtung des eigenen 3D-Servers (nur Desktop):
/// prüft die Voraussetzungen, installiert TripoSR samt Umgebung und
/// startet den Server. Auf der Web-Version ist alles abgeschaltet.
library;

import 'setup/server_setup_web.dart'
    if (dart.library.io) 'setup/server_setup_io.dart' as impl;

/// Basis-Adresse der Dateien im Projekt-Repository.
const _rawBase = 'https://raw.githubusercontent.com/Alex1977-code/'
    'Bildgenerator/claude/image-generator-text-descriptions-hxsqas/server';

const serverScriptUrl = '$_rawBase/local3d_server.py';
const shimUrl = '$_rawBase/shim/torchmcubes.py';
const requirementsUrl = '$_rawBase/requirements-triposr.txt';

/// Die Schritte, die der Assistent ausführt – für die Übersicht vor
/// dem Start: (Titel, Beschreibung, ungefähre Größe).
const setupSteps = <(String, String, String)>[
  (
    'TripoSR laden',
    'Quellcode des Open-Source-Modells von GitHub (MIT-Lizenz)',
    '37 MB'
  ),
  (
    'Python-Umgebung anlegen',
    'Eigene Umgebung im Zielordner – dein System-Python bleibt '
        'unberührt',
    '—'
  ),
  (
    'PyTorch mit CUDA',
    'Rechen-Bibliothek für die NVIDIA-GPU',
    '2,4 GB'
  ),
  (
    'Hilfsdateien',
    'Server-Skript und CPU-Ersatz für torchmcubes (spart das '
        'CUDA-Toolkit)',
    '< 1 MB'
  ),
  (
    'Restliche Pakete',
    'transformers, trimesh, rembg, scikit-image …',
    '≈ 1 GB'
  ),
  (
    'Prüfen',
    'Kontrolle, dass wirklich alles installiert ist',
    '—'
  ),
];

bool get setupSupported => impl.setupSupported;

/// Vorschlag für den Zielordner der Installation.
String defaultTargetDir() => impl.defaultTargetDir();

/// Voraussetzungen prüfen: 'python' (Pfad|Version), 'git', 'gpu' –
/// jeweils null, wenn nichts gefunden wurde.
Future<Map<String, String?>> checkPrerequisites() =>
    impl.checkPrerequisites();

Future<List<String>> pythonCandidates() => impl.pythonCandidates();

/// Installiert alles im Zielordner und meldet den Fortschritt
/// zeilenweise.
Stream<String> installServer({
  required String targetDir,
  required String pythonExe,
}) =>
    impl.installServer(
      targetDir: targetDir,
      serverScriptUrl: serverScriptUrl,
      shimUrl: shimUrl,
      requirementsUrl: requirementsUrl,
      pythonExe: pythonExe,
    );

Future<String> startServer({required String targetDir, int port = 8765}) =>
    impl.startServer(targetDir: targetDir, port: port);
