import 'dart:typed_data';

import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/roblox_export.dart';
import 'package:bildgenerator/services/roblox_face_parts.dart';
import 'package:bildgenerator/services/roblox_marketplace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ein Name für Datei, Netz und Knoten.
///
/// Studio übernimmt beim Import den Namen aus der Datei. Tripo liefert
/// die Netze namenlos, und Studio nennt sie dann „Mesh" – bei drei
/// Modellen im Arbeitsbereich weiß danach niemand mehr, welches
/// welches ist.
void main() {
  Uint8List figur() {
    final m = LocalMesh();
    void quader(double x0, double y0, double z0, double x1, double y1,
        double z1) {
      final p = [
        m.addVertex(x0, y0, z0, 0, 0),
        m.addVertex(x1, y0, z0, 1, 0),
        m.addVertex(x1, y1, z0, 1, 1),
        m.addVertex(x0, y1, z0, 0, 1),
        m.addVertex(x0, y0, z1, 0, 0),
        m.addVertex(x1, y0, z1, 1, 0),
        m.addVertex(x1, y1, z1, 1, 1),
        m.addVertex(x0, y1, z1, 0, 1),
      ];
      m.addQuad(p[0], p[3], p[2], p[1]);
      m.addQuad(p[4], p[5], p[6], p[7]);
      m.addQuad(p[0], p[1], p[5], p[4]);
      m.addQuad(p[2], p[3], p[7], p[6]);
      m.addQuad(p[1], p[2], p[6], p[5]);
      m.addQuad(p[0], p[4], p[7], p[3]);
    }

    quader(-1.3, 2.25, -0.6, 1.3, 3.9, 0.6);
    quader(-0.75, 3.9, -0.7, 0.75, 5.0, 0.7);
    quader(-0.95, 0.0, -0.45, -0.25, 2.25, 0.45);
    quader(0.25, 0.0, -0.45, 0.95, 2.25, 0.45);
    return buildGlb(m);
  }

  group('Bezeichner aus einem Prompt', () {
    test('aus einer Beschreibung wird ein Dateiname', () {
      expect(exportBaseNameFrom('Kapuzzeee, hooded creature'),
          'kapuzzeee_hooded_creature');
      expect(exportBaseNameFrom('Rüstung für Zwerge'),
          'ruestung_fuer_zwerge');
      expect(exportBaseNameFrom('  ---  '), 'modell');
      expect(exportBaseNameFrom('', fallback: 'roblox_figur'),
          'roblox_figur');
    });

    test('nie länger als 40 Zeichen und nie mit Unterstrich am Ende', () {
      final lang = exportBaseNameFrom(
          'ein sehr langer prompt mit vielen woertern der niemals '
          'als dateiname taugen wuerde');
      expect(lang.length, lessThanOrEqualTo(40));
      expect(lang.endsWith('_'), isFalse);
      expect(lang.startsWith('_'), isFalse);
    });

    test('nichts, was ein Dateisystem stört', () {
      final name = exportBaseNameFrom(r'a/b\c:d*e?f"g<h>i|j.k');
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(name), isTrue,
          reason: name);
    });
  });

  group('Der Name steht in der Datei', () {
    test('Netz, Knoten und Szene tragen ihn', () {
      final json = splitGlb(applyExportName(figur(), 'kapuzzeee')).json;
      final meshes = (json['meshes'] as List).cast<Map>();
      expect(meshes.first['name'], 'kapuzzeee');
      final nodes = (json['nodes'] as List).cast<Map>();
      final mitNetz = nodes.where((n) => n.containsKey('mesh'));
      expect(mitNetz.map((n) => n['name']), contains('kapuzzeee'));
      expect(((json['scenes'] as List)[0] as Map)['name'], 'kapuzzeee');
    });

    test('die Gesichtsteile behalten ihre Namen', () {
      // Auto Setup erkennt sie daran. Sie umzubenennen kostet den
      // dynamischen Kopf – und damit den Marktplatz.
      final vorbereitet = prepareForAutoSetup(figur(), targetStuds: 5.0);
      final mitGesicht = addFaceParts(vorbereitet.glb);
      final json =
          splitGlb(applyExportName(mitGesicht.glb, 'kapuzzeee')).json;
      final namen = [
        for (final mesh in (json['meshes'] as List).cast<Map>())
          mesh['name'] as String?,
      ];
      for (final teil in faceMeshNames) {
        expect(namen, contains(teil), reason: teil);
      }
      expect(namen, contains('kapuzzeee'));
      expect(namen.length, faceMeshNames.length + 1);
    });

    test('die Geometrie bleibt unangetastet', () async {
      // Ein Name ist ein Name – er darf keinen Punkt verschieben.
      final vorher = await parseGlbForPreview(figur());
      final a = vorher.positions.toList();
      vorher.dispose();
      final nachher =
          await parseGlbForPreview(applyExportName(figur(), 'egal'));
      final b = nachher.positions.toList();
      nachher.dispose();
      expect(b, a);
    });
  });
}
