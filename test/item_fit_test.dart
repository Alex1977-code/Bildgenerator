import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/item_fit.dart';
import 'package:bildgenerator/services/item_prompt.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:bildgenerator/services/glb_preview.dart';

/// Ein kleiner Quader als Testgegenstand.
Uint8List _boxGlb({double size = 1.0}) {
  final mesh = LocalMesh();
  final v = <int>[];
  for (final x in [0.0, size]) {
    for (final y in [0.0, size]) {
      for (final z in [0.0, size]) {
        v.add(mesh.addVertex(x, y, z, 0.5, 0.5));
      }
    }
  }
  for (var i = 0; i + 2 < v.length; i++) {
    mesh.addTriangle(v[i], v[i + 1], v[i + 2]);
  }
  return buildGlb(mesh);
}

Map<String, dynamic> _json(Uint8List glb) {
  final header = ByteData.sublistView(glb);
  final length = header.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(glb.sublist(20, 20 + length)))
      as Map<String, dynamic>;
}

void main() {
  group('Anbaupunkt je Art', () {
    test('Getragenes geht an sein Körperteil', () {
      expect(itemSlotFor(itemKindById('helm')!), 'kopf');
      expect(itemSlotFor(itemKindById('rucksack')!), 'ruecken');
      expect(itemSlotFor(itemKindById('amulett')!), 'hals');
      expect(itemSlotFor(itemKindById('guerteltasche')!), 'huefte');
      expect(itemSlotFor(itemKindById('maske')!), 'gesicht');
    });

    test('Handgehaltenes an die Hand, Umgebung auf den Boden', () {
      expect(itemSlotFor(itemKindById('schwert')!), 'hand');
      expect(itemSlotFor(itemKindById('laterne')!), 'hand');
      expect(itemSlotFor(itemKindById('fass')!), 'boden');
    });

    test('Reittiere und Fahrzeuge stehen auf dem Boden', () {
      // Sie werden nicht getragen, sondern bestiegen.
      expect(itemSlotFor(itemKindById('reitvogel')!), 'boden');
      expect(itemSlotFor(itemKindById('auto')!), 'boden');
    });

    test('Zu jedem Anbaupunkt gibt es Gelenke', () {
      for (final kind in itemKinds) {
        final slot = itemSlotFor(kind);
        expect(itemAttachJoints, contains(slot), reason: kind.id);
        expect(itemAttachJoints[slot], isNotEmpty, reason: kind.id);
      }
    });
  });

  group('Anbaupunkt bestimmen', () {
    final anchors = figureAnchors(
        minY: 0, maxY: 2, minZ: -0.3, maxZ: 0.3, halfWidth: 0.5);

    test('Ohne Skelett kommt die Schätzung aus der Box', () {
      final (punkt, quelle) = attachPointFor(
        kind: itemKindById('helm')!,
        joints: const {},
        anchors: anchors,
      );
      expect(quelle, contains('geschätzt'));
      // Der Kopf liegt oben, nicht im Ursprung – ohne diesen Rückfall
      // stünde jedes ungeriggte Modell im Boden.
      expect(punkt.$2, closeTo(1.8, 1e-9));
    });

    test('Mit Skelett gewinnt das Gelenk', () {
      final (punkt, quelle) = attachPointFor(
        kind: itemKindById('helm')!,
        joints: const {'Head': (0.0, 1.75, 0.05)},
        anchors: anchors,
      );
      expect(quelle, 'Head');
      expect(punkt.$2, 1.75);
    });

    test('Fehlt das erste Wunschgelenk, greift das nächste', () {
      // Ein Rig ohne Hand_R, aber mit Hand_L.
      final (_, quelle) = attachPointFor(
        kind: itemKindById('schwert')!,
        joints: const {'Hand_L': (-0.4, 1.1, 0.0)},
        anchors: anchors,
      );
      expect(quelle, 'Hand_L');
    });

    test('Ein Reittier landet auf dem Boden, nicht am Kopf', () {
      final (punkt, _) = attachPointFor(
        kind: itemKindById('reitpferd')!,
        joints: const {'Head': (0.0, 1.75, 0.0)},
        anchors: anchors,
      );
      expect(punkt.$2, 0);
    });

    test('Jede Art findet einen Punkt', () {
      for (final kind in itemKinds) {
        final (_, quelle) = attachPointFor(
            kind: kind, joints: const {}, anchors: anchors);
        expect(quelle, isNot('Ursprung'), reason: kind.id);
      }
    });
  });

  group('Erster Vorschlag für die Größe', () {
    test('Ein zu groß geratenes Schwert wird zurechtgerückt', () {
      // Figur 2 Einheiten hoch, Schwert 3 Einheiten lang – viel zu
      // lang. Gewollt sind 0,55 × 2 = 1,1.
      final p = autoPlacement(
        kind: itemKindById('schwert')!,
        figureHeight: 2,
        itemLongest: 3,
      );
      expect(p.scale, closeTo(1.1 / 3, 1e-9));
    });

    test('Trifft das Modell die Proportion, ändert sich fast nichts', () {
      final kind = itemKindById('schwert')!;
      final p = autoPlacement(
        kind: kind,
        figureHeight: 2,
        itemLongest: itemSize(kind, 2),
      );
      expect(p.scale, closeTo(1.0, 1e-9));
    });

    test('Ohne Maße kein Unsinn', () {
      expect(
          autoPlacement(
                  kind: itemKindById('helm')!,
                  figureHeight: 0,
                  itemLongest: 1)
              .scale,
          1);
      expect(
          autoPlacement(
                  kind: itemKindById('helm')!,
                  figureHeight: 2,
                  itemLongest: 0)
              .scale,
          1);
    });
  });

  group('Die Transformation', () {
    test('Skalieren, drehen, verschieben in dieser Reihenfolge', () {
      const p = ItemPlacement(scale: 2, offsetX: 1, offsetY: 5);
      final (x, y, z) = applyPlacement(p, 1, 0, 0);
      expect(x, closeTo(3, 1e-9)); // 1*2 + 1
      expect(y, closeTo(5, 1e-9));
      expect(z, closeTo(0, 1e-9));
    });

    test('Eine Vierteldrehung um y bringt +x nach -z', () {
      final p = ItemPlacement(rotY: math.pi / 2);
      final (x, y, z) = applyPlacement(p, 1, 0, 0);
      expect(x, closeTo(0, 1e-9));
      expect(y, closeTo(0, 1e-9));
      expect(z, closeTo(-1, 1e-9));
    });

    test('Ohne Angaben ändert sich nichts', () {
      final (x, y, z) = applyPlacement(const ItemPlacement(), 3, -2, 7);
      expect([x, y, z], [3, -2, 7]);
    });
  });

  group('In die GLB schreiben', () {
    test('Ein Wurzelknoten mit Matrix kommt dazu, das Netz bleibt',
        () async {
      final glb = _boxGlb(size: 2);
      final vorher = await parseGlbForPreview(glb);
      final out = applyPlacementToGlb(
          glb, const ItemPlacement(scale: 0.5, offsetY: 1));
      final json = _json(out);
      final scene = (json['scenes'] as List).first as Map;
      final roots = (scene['nodes'] as List).cast<int>();
      expect(roots.length, 1);
      final root = (json['nodes'] as List)[roots.first] as Map;
      expect(root['matrix'], isNotNull);
      expect(root['children'], isNotEmpty);

      // Das Netz ist unangetastet – nur anders aufgehängt.
      final nachher = await parseGlbForPreview(out);
      expect(nachher.vertexCount, vorher.vertexCount);
    });

    test('Zweimal anwenden stapelt nicht, es ersetzt', () async {
      // Sonst würde jede Korrektur am Regler die vorige multiplizieren
      // und das Teil verschwände.
      final glb = _boxGlb();
      final einmal =
          applyPlacementToGlb(glb, const ItemPlacement(scale: 0.5));
      final zweimal =
          applyPlacementToGlb(einmal, const ItemPlacement(scale: 0.25));
      final json = _json(zweimal);
      final scene = (json['scenes'] as List).first as Map;
      expect((scene['nodes'] as List).length, 1);
      final root =
          (json['nodes'] as List)[(scene['nodes'] as List).first as int]
              as Map;
      final matrix = (root['matrix'] as List).cast<num>();
      expect(matrix[0], closeTo(0.25, 1e-9));
      // Und es ist genau ein Platzierungsknoten, kein zweiter darüber.
      final marker = (json['nodes'] as List)
          .where((n) => (n as Map)['name'] == 'DreiDGeneratorPlatzierung');
      expect(marker.length, 1);
    });

    test('Die Datei bleibt eine gültige GLB', () async {
      final out = applyPlacementToGlb(
          _boxGlb(), const ItemPlacement(scale: 2, rotY: 0.4));
      final header = ByteData.sublistView(out);
      expect(header.getUint32(0, Endian.little), 0x46546C67);
      expect(header.getUint32(4, Endian.little), 2);
      expect(header.getUint32(8, Endian.little), out.length);
      // Und sie lässt sich wieder öffnen.
      expect((await parseGlbForPreview(out)).vertexCount, greaterThan(0));
    });

    test('Kaputte Eingaben werfen verständlich', () {
      expect(() => applyPlacementToGlb(Uint8List(4), const ItemPlacement()),
          throwsException);
      expect(
          () => applyPlacementToGlb(
              Uint8List.fromList(List.filled(64, 0)),
              const ItemPlacement()),
          throwsException);
    });
  });
}
