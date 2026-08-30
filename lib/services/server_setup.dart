/// Grafische Einrichtung des eigenen 3D-Servers (nur Desktop):
/// prüft die Voraussetzungen, installiert TripoSR samt Umgebung und
/// startet den Server. Auf der Web-Version ist alles abgeschaltet.
library;

import 'server_ports.dart';
import 'setup/server_setup_web.dart'
    if (dart.library.io) 'setup/server_setup_io.dart' as impl;

/// Basis-Adresse der Dateien im Projekt-Repository.
const _rawBase = 'https://raw.githubusercontent.com/Alex1977-code/'
    'Bildgenerator/claude/image-generator-text-descriptions-hxsqas/server';

const serverScriptUrl = '$_rawBase/local3d_server.py';
const imageServerScriptUrl = '$_rawBase/local_image_server.py';
const imageRequirementsUrl = '$_rawBase/requirements-image.txt';
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
    this.kind = '3d',
  });

  final String id;
  final String name;

  /// Leer, wenn kein Repository geklont werden muss (Bild-Server).
  final String repoUrl;
  final String description;
  final String vramLabel;
  final double minVramGb;
  final bool nativeOnWindows;

  /// '3d' = Bild→3D, 'image' = Text→Bild.
  final String kind;
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
  SetupBackend(
    id: 'sd-image',
    kind: 'image',
    name: 'Stable Diffusion – Text→Bild',
    repoUrl: '',
    description: 'Bilder aus Text auf der eigenen GPU – kostenlos und '
        'ohne Cloud. Das Modell wird später in der App gewählt: '
        'SD 1.5 (~4 GB), SDXL Turbo (~7 GB), SDXL (~8 GB), '
        'SD 3.5 Medium (~10 GB) oder FLUX.1 schnell (~16 GB). '
        'Zusammen mit einem 3D-Server läuft damit die ganze Kette '
        'Text→Bild→3D lokal. Nichts wird selbst übersetzt – die '
        'Installation braucht keinen C++-Compiler.',
    vramLabel: 'ab ca. 4 GB',
    minVramGb: 4,
  ),
];

/// Backends einer Art ('3d' oder 'image').
List<SetupBackend> backendsOfKind(String kind) =>
    [for (final b in setupBackends) if (b.kind == kind) b];

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

/// Schritte des Bild-Servers – ohne Repository und ohne C++-Bauteile.
const imageSetupSteps = <(String, String, String)>[
  (
    'Python-Umgebung anlegen',
    'Eigene Umgebung im Zielordner – dein System-Python bleibt '
        'unberührt',
    '—'
  ),
  ('PyTorch mit CUDA', 'Rechen-Bibliothek für die NVIDIA-GPU', '2,4 GB'),
  (
    'Hilfsdateien',
    'Server-Skript und Paketliste',
    '< 1 MB'
  ),
  (
    'Bild-Bibliotheken',
    'diffusers, transformers, accelerate, rembg – alles als fertige '
        'Pakete, kein Compiler nötig',
    '≈ 1 GB'
  ),
  ('Prüfen', 'Kontrolle, dass wirklich alles installiert ist', '—'),
];

/// Schrittliste je Art.
List<(String, String, String)> setupStepsFor(String kind) =>
    kind == 'image' ? imageSetupSteps : setupSteps;

/// Ein auf diesem Rechner eingerichteter 3D-Server. Die App merkt
/// sich die Einträge, damit man den Server später oben in der
/// Auswahlliste anklicken und mit einem Knopfdruck starten kann.
class InstalledServer {
  const InstalledServer({
    required this.backend,
    required this.dir,
    // 0 heißt „der übliche Port dieser Art" – siehe [port].
    int port = 0,
    // ignore: prefer_initializing_formals
  }) : _port = port;

  /// Backend-Kennung: triposr, sf3d, spar3d, trellis.
  final String backend;

  /// Ordner der Installation (enthält .venv und local3d_server.py).
  final String dir;

  final int _port;

  /// Port, auf dem der Server läuft.
  ///
  /// 0 in der Ablage heißt „der übliche Port dieser Art". Vorher stand
  /// dort fest 8765 – ein gefundener Bild-Server bekam damit den Port
  /// des 3D-Servers, und weil die Anzeige den Port verschwieg, standen
  /// zwei scheinbar gleiche Einträge in der Liste, von denen nur einer
  /// funktionierte.
  int get port => _port > 0 ? _port : defaultPort(kind);

  /// Kurzer Anzeigename, z. B. „SF3D".
  String get label => backendLabel(backend);

  /// '3d' = Bild→3D-Server, 'image' = Text→Bild-Server.
  String get kind => backend == 'sd-image' ? 'image' : '3d';

  /// Dieselbe Installation auf einem anderen Port – die getippte
  /// Adresse hat Vorrang vor dem gemerkten Eintrag.
  InstalledServer withPort(int port) =>
      InstalledServer(backend: backend, dir: dir, port: port);

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
      port: int.tryParse(parts[1]) ?? 0,
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

/// Vorschlag für den Zielordner eines bestimmten Backends – jedes
/// Modell bekommt seinen eigenen Ordner.
String targetDirFor(String backend) {
  final base = defaultTargetDir();
  final cut = base.lastIndexOf(RegExp(r'[\\/]'));
  final folder = backend == 'sd-image' ? 'SD-Bilder' : backend.toUpperCase();
  return cut < 0 ? folder : '${base.substring(0, cut + 1)}$folder';
}

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
}) {
  final entry = setupBackends.firstWhere((b) => b.id == backend,
      orElse: () => setupBackends.first);
  final isImage = entry.kind == 'image';
  return impl.installServer(
    targetDir: targetDir,
    serverScriptUrl: isImage ? imageServerScriptUrl : serverScriptUrl,
    shimUrl: shimUrl,
    requirementsUrl: switch (backend) {
      'sd-image' => imageRequirementsUrl,
      'triposr' => requirementsUrl,
      _ => sf3dRequirementsUrl,
    },
    pythonExe: pythonExe,
    backend: backend,
    repoUrl: entry.repoUrl,
  );
}

/// Frischt die Server-Dateien einer bestehenden Installation auf –
/// nur das Server-Skript und die Paketliste, keine Neuinstallation.
/// Nötig, wenn die App aktualisiert wurde und ihr Server-Skript
/// inzwischen weiter ist als das im Installationsordner.
Future<List<String>> refreshServerFiles({
  required String targetDir,
  required String backend,
}) {
  final entry = setupBackends.firstWhere((b) => b.id == backend,
      orElse: () => setupBackends.first);
  final isImage = entry.kind == 'image';
  return impl.refreshServerFiles(
    targetDir: targetDir,
    serverScriptUrl: isImage ? imageServerScriptUrl : serverScriptUrl,
    requirementsUrl: switch (backend) {
      'sd-image' => imageRequirementsUrl,
      'triposr' => requirementsUrl,
      _ => sf3dRequirementsUrl,
    },
    shimUrl: shimUrl,
    backend: backend,
  );
}

/// Übliche Portnummer je Art: 8765 für Bild→3D, 8766 für Text→Bild.
int defaultPort(String kind) =>
    kind == 'image' ? imageDefaultPort : threeDDefaultPort;

/// Schreibt das Protokoll der Einrichtung in den Zielordner (Desktop)
/// und liefert den Pfad – null, wenn das nicht ging.
Future<String?> saveSetupLog(String targetDir, List<String> lines) =>
    impl.saveSetupLog(targetDir, lines);

/// Der Befehl, mit dem sich der Server von Hand starten lässt.
///
/// Gebraucht wird er, wenn der Start aus der App nichts meldet: Der
/// Prozess wird abgekoppelt gestartet, ein sofortiger Absturz sieht
/// deshalb genauso aus wie ein langsam ladendes Modell. Im Terminal
/// steht stattdessen der wirkliche Grund.
///
/// Die Schreibweise richtet sich nach dem Ordner, nicht nach dem
/// laufenden System – so lässt sie sich auch prüfen.
String manualStartCommand({
  required String targetDir,
  required String backend,
  required int port,
  String imageModel = '',
}) {
  final windows = RegExp(r'^[A-Za-z]:|\\').hasMatch(targetDir);
  final python =
      windows ? r'.venv\Scripts\python.exe' : './.venv/bin/python';
  final args = backend == 'sd-image'
      ? [
          'local_image_server.py',
          '--port',
          '$port',
          if (imageModel.isNotEmpty) ...['--model', imageModel],
        ]
      : ['local3d_server.py', '--backend', backend, '--port', '$port'];
  final cd = windows ? 'cd /d "$targetDir"' : 'cd "$targetDir"';
  return '$cd\n$python ${args.join(' ')}';
}

Future<String> startServer({
  required String targetDir,
  int port = 8765,
  String backend = 'sf3d',
  String imageModel = '',
}) =>
    impl.startServer(
        targetDir: targetDir,
        port: port,
        backend: backend,
        imageModel: imageModel);
