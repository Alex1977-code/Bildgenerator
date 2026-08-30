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
}) async* {
  throw UnsupportedError('Nur in der Desktop-App verfügbar.');
}

Future<String> startServer({
  required String targetDir,
  required int port,
  String backend = 'sf3d',
}) async =>
    throw UnsupportedError('Nur in der Desktop-App verfügbar.');

Future<List<String>> pythonCandidates() async => const [];

Future<List<(String, String)>> detectInstalledServers(
        List<String> backends) async =>
    const [];
