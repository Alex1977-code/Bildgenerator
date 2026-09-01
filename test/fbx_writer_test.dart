import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bildgenerator/services/auto_rig.dart';
import 'package:bildgenerator/services/fbx_import.dart';
import 'package:bildgenerator/services/fbx_reader.dart';
import 'package:bildgenerator/services/fbx_writer.dart';
import 'package:bildgenerator/services/local_3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eine Figur, an der sich alles messen lässt: 285 Punkte, 504
/// Dreiecke, 1,0 × 5,0 × 0,69 Einheiten groß.
LocalMesh _figur() {
  final m = LocalMesh();
  final ids = <List<int>>[];
  const rings = 14, sectors = 18;
  for (var i = 0; i <= rings; i++) {
    final phi = (i / rings) * math.pi;
    final row = <int>[];
    for (var j = 0; j <= sectors; j++) {
      final th = (j / sectors) * 2 * math.pi;
      row.add(m.addVertex(
        0.5 * math.sin(phi) * math.cos(th),
        2.5 * math.cos(phi) * -1,
        0.35 * math.sin(phi) * math.sin(th),
        j / sectors,
        i / rings,
        r: 0.7,
        g: 0.5,
        b: 0.4,
      ));
    }
    ids.add(row);
  }
  for (var i = 0; i < rings; i++) {
    for (var j = 0; j < sectors; j++) {
      m.addQuad(ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]);
    }
  }
  return m;
}

/// Alle Knoten eines Namens im ganzen Baum – die Objekte liegen unter
/// `Objects`, aber die Suche soll sich nicht darauf verlassen.
Iterable<FbxNode> _alle(List<FbxNode> roots, String name) sync* {
  for (final root in roots) {
    if (root.name == name) yield root;
    yield* _alle(root.children, name);
  }
}

void main() {
  group('FBX schreiben', () {
    test('Kopf und Fassung stimmen', () async {
      final fbx = await glbToFbx(buildGlb(_figur()), name: 'Testfigur');
      expect(isBinaryFbx(fbx), isTrue);
      expect(looksLikeFbx(fbx), isTrue);
      final version = ByteData.sublistView(fbx).getUint32(23, Endian.little);
      expect(version, 7400);
    });

    test('Punkte und Dreiecke überstehen den Weg zurück', () async {
      final fbx = await glbToFbx(buildGlb(_figur()), name: 'Testfigur');
      final mesh = readFbxMesh(fbx);
      expect(mesh.positions.length ~/ 3, 285);
      expect(mesh.triangleCount, 504);
      expect(mesh.objects, 1);
    });

    test('Maße bleiben erhalten', () async {
      final fbx = await glbToFbx(buildGlb(_figur()), name: 'Testfigur');
      final mesh = readFbxMesh(fbx);
      double spanne(int achse) {
        var lo = double.infinity, hi = -double.infinity;
        for (var i = achse; i < mesh.positions.length; i += 3) {
          lo = math.min(lo, mesh.positions[i]);
          hi = math.max(hi, mesh.positions[i]);
        }
        return hi - lo;
      }

      expect(spanne(0), closeTo(1.0, 0.01));
      expect(spanne(1), closeTo(5.0, 0.01));
      expect(spanne(2), closeTo(0.689, 0.01));
    });

    test('eine Einheit ist ein Meter', () async {
      final fbx = await glbToFbx(buildGlb(_figur()), name: 'Testfigur');
      final roots = readFbxTree(fbx);
      final global = _alle(roots, 'GlobalSettings').first;
      // 100 Zentimeter je Einheit: So schreibt es Blender, und der
      // Roblox-Importer rechnet damit eine Einheit auf einen Stud.
      expect(global.property70Single('UnitScaleFactor', 0), 100);
      // Y oben, Z nach vorn – die Roblox-Konvention.
      expect(global.property70Single('UpAxis', -1), 1);
      expect(global.property70Single('FrontAxis', -1), 2);
    });

    test('Objektkennungen stehen als 64-Bit-Zahl in der Datei', () async {
      // Blenders Importer prüft die Typenfolge (int64, String,
      // String) und bricht sonst ab. Als int32 geschriebene Kennungen
      // waren der erste Fehlschlag.
      final fbx = await glbToFbx(buildGlb(_figur()), name: 'Testfigur');
      final typen = <int>[];
      for (var i = 0; i + 1 < fbx.length; i++) {
        if (fbx[i] == 0x47 &&
            fbx[i + 1] == 0x65 &&
            String.fromCharCodes(fbx.sublist(i, i + 8)) == 'Geometry') {
          typen.add(fbx[i + 8]);
        }
      }
      // 0x4C = 'L' (int64) steht direkt hinter dem Knotennamen.
      expect(typen, contains(0x4C));
    });
  });

  group('FBX mit Skelett', () {
    Future<List<FbxNode>> baum() async {
      final glb = injectAutoRig(buildGlb(_figur()), rigType: 'biped');
      return readFbxTree(await glbToFbx(glb, name: 'Testfigur'));
    }

    test('jeder Knochen wird zum LimbNode', () async {
      final roots = await baum();
      final limbs = [
        for (final m in _alle(roots, 'Model'))
          if (m.properties.length > 2 && m.properties[2] == 'LimbNode')
            m.properties[1] as String,
      ];
      expect(limbs.length, 17);
      expect(limbs.any((n) => n.startsWith('Hips')), isTrue);
      expect(limbs.any((n) => n.startsWith('Head')), isTrue);
    });

    test('Bindepose führt Netz und alle Knochen', () async {
      final roots = await baum();
      final pose = _alle(roots, 'Pose').first;
      expect(pose.first('Type')!.properties.first, 'BindPose');
      expect(pose.first('NbPoseNodes')!.properties.first, 18);
      expect(pose.named('PoseNode').length, 18);
    });

    test('kein Punkt steht zweimal im selben Cluster', () async {
      // Eine GLB darf denselben Knochen für einen Punkt zweimal
      // nennen (0,55 + 0,45 auf „Hips") – in glTF wird summiert. In
      // FBX steht je Cluster eine Punktnummer mit einem Gewicht, und
      // Blender überschreibt beim Import den ersten Eintrag mit dem
      // zweiten. Der Punkt verlöre fast die Hälfte seines Gewichts.
      final roots = await baum();
      final cluster = [
        for (final d in _alle(roots, 'Deformer'))
          if (d.properties.length > 2 && d.properties[2] == 'Cluster') d,
      ];
      expect(cluster, isNotEmpty);
      for (final c in cluster) {
        final indexes = c.first('Indexes')?.ints() ?? const <int>[];
        expect(indexes.toSet().length, indexes.length,
            reason: 'Cluster ${c.properties[1]} nennt einen Punkt zweimal');
      }
    });

    test('die Gewichte je Punkt summieren sich auf 1', () async {
      final roots = await baum();
      final summen = <int, double>{};
      for (final d in _alle(roots, 'Deformer')) {
        if (d.properties.length <= 2 || d.properties[2] != 'Cluster') continue;
        final indexes = d.first('Indexes')?.ints() ?? const <int>[];
        final weights = d.first('Weights')?.doubles() ?? const <double>[];
        expect(indexes.length, weights.length);
        for (var i = 0; i < indexes.length; i++) {
          summen[indexes[i]] = (summen[indexes[i]] ?? 0) + weights[i];
        }
      }
      expect(summen.length, 285);
      for (final entry in summen.entries) {
        expect(entry.value, closeTo(1.0, 0.001),
            reason: 'Punkt ${entry.key}');
      }
    });

    test('höchstens vier Knochen je Punkt – Roblox lässt nicht mehr zu',
        () async {
      final roots = await baum();
      final zahl = <int, int>{};
      for (final d in _alle(roots, 'Deformer')) {
        if (d.properties.length <= 2 || d.properties[2] != 'Cluster') continue;
        for (final i in d.first('Indexes')?.ints() ?? const <int>[]) {
          zahl[i] = (zahl[i] ?? 0) + 1;
        }
      }
      expect(zahl.values.fold<int>(0, math.max), lessThanOrEqualTo(4));
    });

    test('Geometrie und Knochen hängen am selben Skin', () async {
      final roots = await baum();
      final skins = [
        for (final d in _alle(roots, 'Deformer'))
          if (d.properties.length > 2 && d.properties[2] == 'Skin') d,
      ];
      expect(skins.length, 1);
      final verbindungen = _alle(roots, 'Connections').first;
      final paare = [
        for (final c in verbindungen.named('C'))
          if (c.properties.length >= 3 &&
              c.properties[1] is num &&
              c.properties[2] is num)
            ((c.properties[1] as num).toInt(), (c.properties[2] as num).toInt()),
      ];
      final skinId = skins.first.id!;
      // Der Skin hängt an der Geometrie, jeder Cluster am Skin.
      expect(paare.where((p) => p.$1 == skinId).length, 1);
      final clusterIds = [
        for (final d in _alle(roots, 'Deformer'))
          if (d.properties.length > 2 && d.properties[2] == 'Cluster') d.id!,
      ];
      for (final id in clusterIds) {
        expect(paare.any((p) => p.$1 == id && p.$2 == skinId), isTrue,
            reason: 'Cluster $id hängt nicht am Skin');
      }
    });
  });

  test('geschriebenes FBX lässt sich wieder in eine GLB wandeln', () async {
    // Der ganze Kreis: GLB → FBX → GLB. Das ist der Weg, den ein
    // Nutzer geht, der die Datei speichert und später wieder ablegt.
    final fbx = await glbToFbx(buildGlb(_figur()), name: 'Testfigur');
    final glb = fbxToGlb(fbx);
    expect(String.fromCharCodes(glb.sublist(0, 4)), 'glTF');
    expect(glb.length, greaterThan(1000));
  });
}
