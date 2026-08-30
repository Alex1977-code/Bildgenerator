/// Prüft, ob im GitHub-Release eine neuere Fassung liegt, und
/// installiert sie auf dem Desktop auf Knopfdruck.
///
/// Vergleichsgrundlage ist die Commit-Kennung: Die CI schreibt sie in
/// den Release-Text, die App kennt ihre eigene aus [buildInfo]. Damit
/// ist der Vergleich eindeutig – anders als ein Datum, das bei zwei
/// Builds am selben Tag nichts aussagt.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;

import '../build_info.dart';
import 'generators.dart' show GenerationException;
import 'update/update_installer_web.dart'
    if (dart.library.io) 'update/update_installer_io.dart' as impl;

const _releaseApi = 'https://api.github.com/repos/Alex1977-code/'
    'Bildgenerator/releases/latest';

/// Fester Link, unter dem GitHub immer die Datei des neuesten Releases
/// ausliefert – ohne API und damit ohne Abfragegrenze.
const _latestDownloadBase =
    'https://github.com/Alex1977-code/Bildgenerator/releases/latest/'
    'download';

/// Die Release-Seite zum Nachsehen von Hand.
const releasesPageUrl =
    'https://github.com/Alex1977-code/Bildgenerator/releases/latest';

/// GitHub weist Anfragen ohne Programmkennung ab; ohne diesen Kopf
/// antwortet die API mit 403.
const _apiHeaders = {
  'Accept': 'application/vnd.github+json',
  'User-Agent': '3DGenerator-App',
  'X-GitHub-Api-Version': '2022-11-28',
};

/// Eine im Release verfügbare Fassung.
class UpdateInfo {
  const UpdateInfo({
    required this.sha,
    required this.published,
    required this.downloadUrl,
    required this.assetName,
    required this.sizeBytes,
  });

  /// Vollständige Commit-Kennung des Releases.
  final String sha;
  final DateTime? published;
  final String downloadUrl;
  final String assetName;
  final int sizeBytes;

  String get shortSha => sha.length >= 7 ? sha.substring(0, 7) : sha;
  /// Größe der Datei; bei der Notfall-Variante ohne API ist sie
  /// unbekannt.
  String get sizeLabel => sizeBytes <= 0
      ? 'Größe unbekannt'
      : '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Commit-Kennung der laufenden App (die ersten Zeichen aus
/// [buildInfo], z. B. „acdb042 · 30.08.2026 UTC"). Leer bei einem
/// Entwicklungs-Build.
String get runningBuildSha {
  final match = RegExp(r'^[0-9a-f]{7,40}').firstMatch(buildInfo.trim());
  return match?.group(0) ?? '';
}

/// Name der Release-Datei für die laufende Plattform – null, wenn für
/// diese Plattform nichts veröffentlicht wird.
String? get platformAssetName {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'bildgenerator-windows.zip',
    TargetPlatform.android => 'bildgenerator-android.apk',
    _ => null,
  };
}

/// Fragt das neueste Release ab. Liefert null, wenn es für diese
/// Plattform keine Datei gibt.
Future<UpdateInfo?> fetchLatestRelease() async {
  http.Response response;
  try {
    response = await http
        .get(Uri.parse(_releaseApi), headers: _apiHeaders)
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    throw GenerationException('Update-Prüfung nicht möglich – '
        'Netzwerkfehler: $e');
  }
  if (response.statusCode != 200) {
    throw GenerationException(describeApiFailure(
        response.statusCode, response.headers));
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  // Die CI schreibt „Build-Kennung: `<sha>`" in den Release-Text.
  final body = json['body']?.toString() ?? '';
  final sha =
      RegExp(r'\b[0-9a-f]{40}\b').firstMatch(body)?.group(0) ?? '';
  final wanted = platformAssetName;
  if (wanted == null) return null;
  for (final asset in (json['assets'] as List?) ?? []) {
    final map = asset as Map<String, dynamic>;
    if (map['name'] == wanted) {
      return UpdateInfo(
        sha: sha,
        published: DateTime.tryParse(
            map['updated_at']?.toString() ?? ''),
        downloadUrl: map['browser_download_url'].toString(),
        assetName: wanted,
        sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
      );
    }
  }
  return null;
}

/// Verständlicher Text zu einem fehlgeschlagenen API-Aufruf.
///
/// 403 ist der häufigste Fall und heißt bei GitHub fast immer
/// „Abfragegrenze erreicht": Ohne Anmeldung sind 60 Abfragen je Stunde
/// und IP-Adresse erlaubt. Die Kopfzeilen sagen, ob es daran lag und
/// wann es wieder geht.
String describeApiFailure(int status, Map<String, String> headers) {
  if (status == 403 || status == 429) {
    final remaining =
        int.tryParse(headers['x-ratelimit-remaining'] ?? '') ?? -1;
    if (remaining == 0) {
      final reset = int.tryParse(headers['x-ratelimit-reset'] ?? '');
      var wait = '';
      if (reset != null) {
        final at = DateTime.fromMillisecondsSinceEpoch(reset * 1000);
        final minutes = at.difference(DateTime.now()).inMinutes;
        if (minutes > 0) wait = ' Wieder möglich in etwa $minutes Minuten.';
      }
      return 'GitHub erlaubt ohne Anmeldung nur 60 Abfragen je Stunde '
          'und Internet-Anschluss – die sind gerade aufgebraucht.$wait '
          'Die neueste Fassung lässt sich trotzdem direkt laden.';
    }
    return 'GitHub hat die Anfrage abgewiesen (403). Das passiert bei '
        'zu vielen Abfragen oder wenn ein Firmen-Netz bzw. ein '
        'Virenscanner dazwischenfunkt. Die neueste Fassung lässt sich '
        'trotzdem direkt laden.';
  }
  if (status == 404) {
    return 'Es ist noch keine Veröffentlichung vorhanden (404).';
  }
  return 'Update-Prüfung fehlgeschlagen ($status).';
}

/// Die neueste Fassung ohne API: GitHub liefert unter
/// `releases/latest/download/<Datei>` immer die Datei des neuesten
/// Releases aus. Damit kommt man auch dann an das Update, wenn die
/// Abfragegrenze erreicht ist – nur die Kennung bleibt unbekannt,
/// deshalb sagt die App nicht, ob es wirklich neuer ist.
UpdateInfo? latestReleaseWithoutApi() {
  final wanted = platformAssetName;
  if (wanted == null) return null;
  return UpdateInfo(
    sha: '',
    published: null,
    downloadUrl: '$_latestDownloadBase/$wanted',
    assetName: wanted,
    sizeBytes: 0,
  );
}

/// True, wenn sich das Release von der laufenden Fassung
/// unterscheidet. Bei einem Entwicklungs-Build (ohne Kennung) oder
/// unbekanntem Release-Stand: false, statt fälschlich ein Update zu
/// melden.
bool isNewer(UpdateInfo info) {
  final running = runningBuildSha;
  if (running.isEmpty || info.sha.isEmpty) return false;
  return !info.sha.startsWith(running);
}

/// Auf dem Desktop kann die App die neue Fassung selbst danebenlegen
/// und starten.
bool get canInstall => impl.canInstall;

/// Lädt die Release-Datei herunter.
Future<Uint8List> downloadUpdate(
    UpdateInfo info, void Function(String stage) onProgress) async {
  onProgress('Neue Fassung wird geladen (${info.sizeLabel}) …');
  http.Response response;
  try {
    response = await http
        .get(Uri.parse(info.downloadUrl))
        .timeout(const Duration(minutes: 10));
  } catch (e) {
    throw GenerationException('Download fehlgeschlagen: $e');
  }
  if (response.statusCode != 200) {
    throw GenerationException(
        'Download fehlgeschlagen (${response.statusCode}).');
  }
  return response.bodyBytes;
}

/// Entpackt die neue Fassung neben die laufende und liefert den Pfad
/// zum neuen Programm.
Future<String> installUpdate(Uint8List archiveBytes, UpdateInfo info,
        void Function(String stage) onProgress) =>
    impl.installUpdate(
        archiveBytes, info.assetName, info.shortSha, onProgress);

/// Startet die installierte Fassung.
Future<void> launchInstalled(String path) => impl.launchInstalled(path);

/// Beendet die alte Fassung, sobald die neue läuft.
Future<void> quitApp() => impl.quitApp();
