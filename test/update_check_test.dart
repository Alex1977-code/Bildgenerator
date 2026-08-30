import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/fal_service.dart';
import 'package:bildgenerator/services/generators.dart';
import 'package:bildgenerator/services/model_catalog.dart';
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

  group('Anbieterübergreifende Modell-Liste', () {
    test('enthält jeden Anbieter mindestens einmal', () {
      final all = allImageModels((_) => const []);
      for (final provider in GenProvider.values) {
        expect(all.any((choice) => choice.provider == provider), isTrue,
            reason: 'Kein Modell für ${provider.name}');
      }
    });

    test('Schlüssel lässt sich wieder zerlegen', () {
      final choice = allImageModels((_) => const []).first;
      final parsed = ImageModelChoice.parseKey(choice.key);
      expect(parsed?.$1, choice.provider);
      expect(parsed?.$2, choice.id);
      expect(choice.fullLabel, startsWith(choice.provider.shortLabel));
    });

    test('Abgerufene Modelle kommen dazu, ohne zu doppeln', () {
      final all = allImageModels((p) =>
          p == GenProvider.openai ? const ['gpt-image-1', 'neu-99'] : const []);
      final openAi =
          all.where((c) => c.provider == GenProvider.openai).toList();
      expect(openAi.where((c) => c.id == 'gpt-image-1').length, 1);
      expect(openAi.any((c) => c.id == 'neu-99'), isTrue);
    });

    test('Kaputte Schlüssel liefern null', () {
      expect(ImageModelChoice.parseKey('ohne-schraegstrich'), isNull);
      expect(ImageModelChoice.parseKey('openai/'), isNull);
      expect(ImageModelChoice.parseKey('gibtsnicht/modell'), isNull);
    });
  });

  group('Eigener Bild-Server', () {
    test('Adresse wird vereinheitlicht', () {
      expect(SelfHostImageGenerator.normalizeBaseUrl('127.0.0.1:8766'),
          'http://127.0.0.1:8766');
      expect(SelfHostImageGenerator.normalizeBaseUrl(' http://pc:8766/ '),
          'http://pc:8766');
      expect(SelfHostImageGenerator.normalizeBaseUrl(''), '');
    });

    test('Der Bild-Server ist ein eigener Anbieter ohne Referenzbilder',
        () {
      expect(GenProvider.selfhost.isLocal, isTrue);
      expect(GenProvider.selfhost.supportsReferences, isFalse);
      expect(staticModelOptions(GenProvider.selfhost), isNotEmpty);
    });

    test('Der Eintrag kennt seine Art', () {
      const image =
          InstalledServer(backend: 'sd-image', dir: r'C:\KI\SD-Bilder');
      const mesh = InstalledServer(backend: 'sf3d', dir: r'C:\KI\SF3D');
      expect(image.kind, 'image');
      expect(mesh.kind, '3d');
      expect(backendsOfKind('image').single.id, 'sd-image');
      expect(defaultPort('image'), 8766);
      expect(defaultPort('3d'), 8765);
    });
  });

  group('Direkte Text→3D-Modelle', () {
    test('Der Katalog kennt mindestens ein Text→3D-Modell', () {
      expect(falModels.any((m) => m.textToModel), isTrue);
    });

    test('Bild→3D-Modelle bleiben Bild→3D', () {
      expect(falModelFor('fal-ai/trellis').textToModel, isFalse);
      expect(falModelFor('fal-ai/trellis').imageField, 'image_url');
      expect(falModelFor('fal-ai/hunyuan3d/v2').imageField,
          'input_image_url');
    });

    test('Eigene IDs mit text-to-3d gelten als Text→3D', () {
      expect(falModelFor('irgendwer/mein-text-to-3d').textToModel, isTrue);
      expect(falModelFor('irgendwer/mein-modell').textToModel, isFalse);
    });
  });
}
