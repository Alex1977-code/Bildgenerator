import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/server_setup.dart';
import 'package:bildgenerator/services/update_check.dart';

void main() {
  group('Update-Prüfung', () {
    test('Ohne eigene Build-Kennung wird kein Update gemeldet', () {
      // Im Test läuft der Entwicklungs-Build ohne Commit-Kennung –
      // dann darf die App nicht fälschlich ein Update anbieten.
      expect(runningBuildSha, '');
      expect(
        isNewer(const UpdateInfo(
          sha: '0123456789abcdef0123456789abcdef01234567',
          published: null,
          downloadUrl: 'https://example.invalid/app.zip',
          assetName: 'bildgenerator-windows.zip',
          sizeBytes: 1,
        )),
        isFalse,
      );
    });

    test('Größe wird lesbar angezeigt', () {
      const info = UpdateInfo(
        sha: 'abc1234',
        published: null,
        downloadUrl: 'https://example.invalid/app.zip',
        assetName: 'bildgenerator-windows.zip',
        sizeBytes: 26 * 1024 * 1024,
      );
      expect(info.sizeLabel, '26.0 MB');
      expect(info.shortSha, 'abc1234');
    });
  });

  group('Eingerichtete Server', () {
    test('Eintrag lässt sich speichern und wieder lesen', () {
      const entry =
          InstalledServer(backend: 'sf3d', dir: r'C:\KI\SF3D', port: 8765);
      final again = InstalledServer.decode(entry.encode());
      expect(again, entry);
      expect(again!.url, 'http://127.0.0.1:8765');
      expect(again.label, 'SF3D');
    });

    test('Kaputte Einträge liefern null', () {
      expect(InstalledServer.decode(''), isNull);
      expect(InstalledServer.decode('sf3d|8765'), isNull);
      expect(InstalledServer.decode('|8765|C:\\KI'), isNull);
    });

    test('Unbekannter Port fällt auf den Standard zurück', () {
      final entry = InstalledServer.decode('triposr|xxx|/opt/ki/TripoSR');
      expect(entry!.port, 8765);
      expect(entry.backend, 'triposr');
      expect(entry.dir, '/opt/ki/TripoSR');
    });

    test('Backend-Kurzname ohne erklärenden Zusatz', () {
      expect(backendLabel('triposr'), 'TripoSR');
      expect(backendLabel('trellis'), 'TRELLIS');
      expect(backendLabel('unbekannt'), 'UNBEKANNT');
    });
  });
}
