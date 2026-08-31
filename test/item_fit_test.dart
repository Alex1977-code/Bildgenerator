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

/// Längste Kante einer Punktwolke.
double _longest(Float32List positions) {
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  var minZ = double.infinity, maxZ = double.negativeInfinity;
  for (var i = 0; i + 2 < positions.length; i += 3) {
    minX = math.min(minX, positions[i]);
    maxX = math.max(maxX, positions[i]);
    minY = math.min(minY, positions[i + 1]);
    maxY = math.max(maxY, positions[i + 1]);
    minZ = math.min(minZ, positions[i + 2]);
    maxZ = math.max(maxZ, positions[i + 2]);
  }
  return [maxX - minX, maxY - minY, maxZ - minZ]
      .reduce((a, b) => a > b ? a : b);
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
    test('Größe und Drehung landen im Netz, nicht in einer Matrix',
        () async {
      // Der entscheidende Punkt: Die Roblox-Größenprüfung liest die
      // Positionen roh. Läge die Größe nur in einer Wurzel-Matrix,
      // würde sie nach dem Verkleinern weiter „zu groß" melden.
      final glb = _boxGlb(size: 2);
      final vorher = await parseGlbForPreview(glb);
      final out =
          applyPlacementToGlb(glb, const ItemPlacement(scale: 0.5));
      final nachher = await parseGlbForPreview(out);
      expect(nachher.vertexCount, vorher.vertexCount);
      // Die halbierte Ausdehnung steht wirklich in den Punkten.
      expect(_longest(nachher.positions),
          closeTo(_longest(vorher.positions) / 2, 1e-5));
      // Und es gibt keinen zusätzlichen Wurzelknoten.
      final json = _json(out);
      expect(
          (json['nodes'] as List)
              .where((n) => (n as Map)['name'] ==
                  'DreiDGeneratorPlatzierung'),
          isEmpty);
    });

    test('Eine Drehung dreht die Punkte mit', () async {
      final glb = _boxGlb(size: 2);
      final out = applyPlacementToGlb(
          glb, ItemPlacement(rotY: math.pi / 2));
      final mesh = await parseGlbForPreview(out);
      // Der Quader lief von 0 bis 2 in x und z; nach einer
      // Vierteldrehung um y liegt die x-Ausdehnung im negativen z.
      var minZ = double.infinity, maxZ = double.negativeInfinity;
      for (var i = 2; i < mesh.positions.length; i += 3) {
        minZ = math.min(minZ, mesh.positions[i]);
        maxZ = math.max(maxZ, mesh.positions[i]);
      }
      expect(maxZ, closeTo(0, 1e-5));
      expect(minZ, closeTo(-2, 1e-5));
    });

    test('Nacheinander angewendet rechnet es sich zusammen', () async {
      // Anders als beim Matrix-Weg: Der Editor lädt jedes Mal die
      // aktuelle Datei und misst sie neu, deshalb ist Zusammenrechnen
      // hier das richtige Verhalten.
      final glb = _boxGlb(size: 2);
      final einmal =
          applyPlacementToGlb(glb, const ItemPlacement(scale: 0.5));
      final zweimal =
          applyPlacementToGlb(einmal, const ItemPlacement(scale: 0.5));
      final mesh = await parseGlbForPreview(zweimal);
      expect(_longest(mesh.positions), closeTo(0.5, 1e-5));
    });

    test('Ohne Änderung bleibt die Datei, wie sie war', () {
      final glb = _boxGlb();
      expect(applyPlacementToGlb(glb, const ItemPlacement()), same(glb));
    });

    test('Der Versatz wandert mit in die Datei', () async {
      // Er war zuerst ausgenommen – aus der Überlegung, das
      // Accessoire schwebte sonst um die Anbauhöhe daneben. Falsch
      // herum gedacht: In Roblox fällt das Attachment im Handle mit
      // dem Punkt am Körper zusammen, der Abstand des Netzes zu
      // seinem Ursprung IST der Abstand zum Körperpunkt. Ohne ihn
      // wäre die Anprobe Zierde gewesen.
      final glb = _boxGlb(size: 1);
      final out = applyPlacementToGlb(
          glb, const ItemPlacement(offsetY: 3, offsetX: -1));
      final mesh = await parseGlbForPreview(out);
      var minY = double.infinity, minX = double.infinity;
      for (var i = 0; i + 2 < mesh.positions.length; i += 3) {
        minX = math.min(minX, mesh.positions[i]);
        minY = math.min(minY, mesh.positions[i + 1]);
      }
      expect(minY, closeTo(3, 1e-5));
      expect(minX, closeTo(-1, 1e-5));
    });

    test('Erst skalieren, dann drehen, dann verschieben', () async {
      // Dieselbe Reihenfolge wie in der Vorschau – sonst sitzt das
      // Teil in der Datei anders als auf dem Bildschirm.
      final glb = _boxGlb(size: 2);
      const p = ItemPlacement(scale: 0.5, offsetY: 10);
      final out = applyPlacementToGlb(glb, p);
      final mesh = await parseGlbForPreview(out);
      var minY = double.infinity, maxY = double.negativeInfinity;
      for (var i = 1; i < mesh.positions.length; i += 3) {
        minY = math.min(minY, mesh.positions[i]);
        maxY = math.max(maxY, mesh.positions[i]);
      }
      // Erst halbiert (0..1), dann um 10 verschoben.
      expect(minY, closeTo(10, 1e-5));
      expect(maxY, closeTo(11, 1e-5));
      // Und die Vorschau rechnet dasselbe.
      final (_, vy, _) = applyPlacement(p, 0, 2, 0);
      expect(vy, closeTo(11, 1e-9));
    });

    test('Die Datei bleibt eine gültige GLB', () async {
      final out = applyPlacementToGlb(
          _boxGlb(), const ItemPlacement(scale: 2, rotY: 0.4));
      final header = ByteData.sublistView(out);
      expect(header.getUint32(0, Endian.little), 0x46546C67);
      expect(header.getUint32(4, Endian.little), 2);
      expect(header.getUint32(8, Endian.little), out.length);
      expect((await parseGlbForPreview(out)).vertexCount, greaterThan(0));
    });

    test('Kaputte Eingaben werfen verständlich', () {
      expect(
          () => applyPlacementToGlb(
              Uint8List(4), const ItemPlacement(scale: 2)),
          throwsException);
    });
  });
}
