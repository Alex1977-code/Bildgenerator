/// Web-Fassung: Auf der Web-Version lässt sich kein lokaler Server
/// einrichten – die Oberfläche blendet den Assistenten dort aus.
const bool setupSupported = false;

String defaultTargetDir() => '';

Future<Map<String, String?>> checkPrerequisites() async => const {};

Stream<String> installServer({
  required String targetDir,
  required String serverScriptUrl,
  required String shimUrl,
  required String requirementsUrl,
  required String pythonExe,
  String backend = 'sf3d',
  String repoUrl = '',
  String hfToken = '',
  String modelPage = '',
}) async* {
  throw UnsupportedError('Nur in der Desktop-App verfügbar.');
}

Future<List<String>> refreshServerFiles({
  required String targetDir,
  required String serverScriptUrl,
  required String requirementsUrl,
  String? shimUrl,
  String backend = 'sf3d',
}) async =>
    throw UnsupportedError('Nur in der Desktop-App verfügbar.');

Future<String> startServer({
  required String targetDir,
  required int port,
  String backend = 'sf3d',
  String imageModel = '',
  String hfToken = '',
}) async =>
    throw UnsupportedError('Nur in der Desktop-App verfügbar.');

Future<List<String>> pythonCandidates() async => const [];

Future<List<(String, String)>> detectInstalledServers(
        List<String> backends) async =>
    const [];

Future<String?> saveSetupLog(String targetDir, List<String> lines) async =>
    null;

/// Web-Fassung: Ohne lokalen Server gibt es auch nichts zu prüfen.
Future<String> checkHuggingFaceAccess({
  required String modelPage,
  required String token,
}) async =>
    throw UnsupportedError('Nur in der Desktop-App verfügbar.');
