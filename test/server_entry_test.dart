import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/server_setup.dart';

void main() {
  group('Server-Eintrag: Port je Art', () {
    test('Ohne Portangabe zählt der übliche Port der Art', () {
      // Vorher stand hier fest 8765 – ein gefundener Bild-Server
      // bekam damit den Port des 3D-Servers.
      const image =
          InstalledServer(backend: 'sd-image', dir: r'C:\KI\SD-Bilder');
      const mesh = InstalledServer(backend: 'triposr', dir: r'C:\KI\TripoSR');
      expect(image.port, 8766);
      expect(mesh.port, 8765);
      expect(image.url, 'http://127.0.0.1:8766');
      expect(mesh.url, 'http://127.0.0.1:8765');
    });

    test('Ein gesetzter Port gewinnt', () {
      const entry = InstalledServer(
          backend: 'sd-image', dir: r'C:\KI\SD-Bilder', port: 9000);
      expect(entry.port, 9000);
      expect(entry.url, 'http://127.0.0.1:9000');
    });

    test('withPort ändert nur den Port', () {
      const entry =
          InstalledServer(backend: 'sd-image', dir: r'C:\KI\SD-Bilder');
      final moved = entry.withPort(8770);
      expect(moved.port, 8770);
      expect(moved.backend, entry.backend);
      expect(moved.dir, entry.dir);
      expect(moved, isNot(entry));
    });

    test('Ablegen und Zurücklesen', () {
      const entry = InstalledServer(
          backend: 'sd-image', dir: r'C:\KI\SD-Bilder', port: 8766);
      final back = InstalledServer.decode(entry.encode());
      expect(back, entry);
      // Ein alter Eintrag ohne brauchbare Portangabe fällt auf den
      // üblichen Port der Art zurück, nicht auf 8765.
      expect(InstalledServer.decode(r'sd-image|x|C:\KI\SD-Bilder')?.port,
          8766);
      expect(InstalledServer.decode('kaputt'), isNull);
    });
  });

  group('Start von Hand', () {
    test('Windows-Pfad ergibt Windows-Befehl', () {
      final cmd = manualStartCommand(
        targetDir: r'C:\KI\SD-Bilder',
        backend: 'sd-image',
        port: 8766,
        imageModel: 'sdxl',
      );
      expect(cmd, contains(r'cd /d "C:\KI\SD-Bilder"'));
      expect(cmd, contains(r'.venv\Scripts\python.exe'));
      expect(cmd, contains('local_image_server.py --port 8766'));
      expect(cmd, contains('--model sdxl'));
    });

    test('Ohne Modellangabe fehlt der Schalter', () {
      final cmd = manualStartCommand(
          targetDir: r'C:\KI\SD-Bilder', backend: 'sd-image', port: 8766);
      expect(cmd, isNot(contains('--model')));
    });

    test('Unix-Pfad ergibt Unix-Befehl, 3D nennt sein Backend', () {
      final cmd = manualStartCommand(
        targetDir: '/home/max/TripoSR',
        backend: 'triposr',
        port: 8765,
      );
      expect(cmd, contains('cd "/home/max/TripoSR"'));
      expect(cmd, contains('./.venv/bin/python'));
      expect(cmd,
          contains('local3d_server.py --backend triposr --port 8765'));
    });
  });
}
