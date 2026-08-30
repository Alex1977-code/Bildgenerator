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
const sf3dRequirementsUrl = '$_rawBase/requirements-sf3d.txt';

/// Wählbare Backends für den Assistenten. [minVramGb] ist der grob
/// nötige Grafikspeicher – der Assistent gleicht ihn mit der erkannten
/// Karte ab. [nativeOnWindows] ist false, wenn das Projekt nur unter
/// Linux/WSL2 sauber baut.
class SetupBackend {
  const SetupBackend({
    required this.id,
    required this.name,
    required this.repoUrl,
    required this.description,
    required this.vramLabel,
    required this.minVramGb,
    this.nativeOnWindows = true,
  });

  final String id;
  final String name;
  final String repoUrl;
  final String description;
  final String vramLabel;
  final double minVramGb;
  final bool nativeOnWindows;
}

/// Von sparsam nach anspruchsvoll sortiert – so findet jeder Rechner
/// sein passendes Modell.
const setupBackends = <SetupBackend>[
  SetupBackend(
    id: 'triposr',
    name: 'TripoSR – am schnellsten',
    repoUrl: 'https://github.com/VAST-AI-Research/TripoSR.git',
    description: 'Ergebnisse in Sekunden, gröber und mit Vertex-Farben. '
        'Gut zum schnellen Prüfen von Silhouette und Ansicht. '
        'MIT-Lizenz.',
    vramLabel: 'ca. 4–6 GB',
    minVramGb: 4,
  ),
  SetupBackend(
    id: 'sf3d',
    name: 'SF3D – Stable Fast 3D (empfohlen)',
    repoUrl: 'https://github.com/Stability-AI/stable-fast-3d.git',
    description: 'Echte UV-Textur statt Vertex-Farben – dasselbe '
        'Modell, das Stability über die API kostenpflichtig anbietet. '
        'Deutlich schärfer als TripoSR. Community-Lizenz: frei bis '
        '1 Mio. US-\$ Jahresumsatz; die Gewichte brauchen einmalig '
        'eine Freigabe auf Hugging Face.',
    vramLabel: 'ca. 6 GB',
    minVramGb: 6,
  ),
  SetupBackend(
    id: 'spar3d',
    name: 'SPAR3D – Stable Point Aware 3D',
    repoUrl: 'https://github.com/Stability-AI/stable-point-aware-3d.git',
    description: 'Die stärkste Stability-Variante: rekonstruiert '
        'Rückseite und Hohlräume am besten, mit UV-Textur. Gleiche '
        'Community-Lizenz und Hugging-Face-Freigabe wie SF3D.',
    vramLabel: 'ca. 7–10,5 GB',
    minVramGb: 7,
  ),
  SetupBackend(
    id: 'trellis',
    name: 'TRELLIS – beste Qualität, mit Multiview',
    repoUrl: 'https://github.com/microsoft/TRELLIS.git',
    description: 'Microsofts Spitzenmodell (MIT): die schärfsten '
        'Texturen und als einziges hier fähig, mehrere Ansichten '
        'desselben Objekts gemeinsam auszuwerten. Aufwendige '
        'Installation – unter Windows nur über WSL2 (Ubuntu), weil '
        'das Projekt ein Bash-Setup mit CUDA-Bausteinen nutzt.',
    vramLabel: 'ca. 12–16 GB',
    minVramGb: 12,
    nativeOnWindows: false,
  ),
];

/// Die Schritte, die der Assistent ausführt – für die Übersicht vor
/// dem Start: (Titel, Beschreibung, ungefähre Größe).
const setupSteps = <(String, String, String)>[
  (
    'Modell-Quellcode laden',
    'Repository des gewählten Modells von GitHub',
    '~40 MB'
  ),
  (
    'Python-Umgebung anlegen',
    'Eigene Umgebung im Zielordner – dein System-Python bleibt '
        'unberührt',
    '—'
  ),
  ('PyTorch mit CUDA', 'Rechen-Bibliothek für die NVIDIA-GPU', '2,4 GB'),
  (
    'Hilfsdateien',
    'Server-Skript, Paketliste und (bei TripoSR) der CPU-Ersatz für '
        'torchmcubes, der das CUDA-Toolkit erspart',
    '< 1 MB'
  ),
  (
    'Restliche Pakete',
    'Abhängigkeiten des Modells (transformers, trimesh, rembg …)',
    '≈ 1 GB'
  ),
  ('Prüfen', 'Kontrolle, dass wirklich alles installiert ist', '—'),
];

/// Ein auf diesem Rechner eingerichteter 3D-Server. Die App merkt
/// sich die Einträge, damit man den Server später oben in der
/// Auswahlliste anklicken und mit einem Knopfdruck starten kann.
class InstalledServer {
  const InstalledServer({
    required this.backend,
    required this.dir,
    this.port = 8765,
  });

  /// Backend-Kennung: triposr, sf3d, spar3d, trellis.
  final String backend;

  /// Ordner der Installation (enthält .venv und local3d_server.py).
  final String dir;

  final int port;

  /// Kurzer Anzeigename, z. B. „SF3D".
  String get label => backendLabel(backend);

  String get url => 'http://127.0.0.1:$port';

  /// Ablageform in den Einstellungen: „backend|port|Ordner".
  String encode() => '$backend|$port|$dir';

  /// Gegenstück zu [encode]; null bei kaputten Einträgen.
  static InstalledServer? decode(String raw) {
    final parts = raw.split('|');
    if (parts.length < 3) return null;
    final backend = parts[0].trim();
    // Der Ordner darf theoretisch selbst ein | enthalten.
    final dir = parts.sublist(2).join('|').trim();
    if (backend.isEmpty || dir.isEmpty) return null;
    return InstalledServer(
      backend: backend,
      dir: dir,
      port: int.tryParse(parts[1]) ?? 8765,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InstalledServer &&
      other.backend == backend &&
      other.dir == dir &&
      other.port == port;

  @override
  int get hashCode => Object.hash(backend, dir, port);
}

/// Kurzname eines Backends ohne den erklärenden Zusatz.
String backendLabel(String id) {
  for (final backend in setupBackends) {
    if (backend.id == id) return backend.name.split(' – ').first;
  }
  return id.toUpperCase();
}

/// Sucht neben dem Standard-Zielordner nach fertigen Installationen –
/// so taucht auch ein von Hand eingerichteter Server in der Liste auf.
Future<List<InstalledServer>> detectInstalledServers() async {
  final found = await impl.detectInstalledServers(
      [for (final backend in setupBackends) backend.id]);
  return [
    for (final (backend, dir) in found)
      InstalledServer(backend: backend, dir: dir),
  ];
}

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
  String backend = 'sf3d',
}) =>
    impl.installServer(
      targetDir: targetDir,
      serverScriptUrl: serverScriptUrl,
      shimUrl: shimUrl,
      requirementsUrl:
          backend == 'triposr' ? requirementsUrl : sf3dRequirementsUrl,
      pythonExe: pythonExe,
      backend: backend,
      repoUrl: setupBackends
          .firstWhere((b) => b.id == backend,
              orElse: () => setupBackends.first)
          .repoUrl,
    );

Future<String> startServer({
  required String targetDir,
  int port = 8765,
  String backend = 'sf3d',
}) =>
    impl.startServer(
        targetDir: targetDir, port: port, backend: backend);
