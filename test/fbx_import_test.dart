import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/fbx_import.dart';
import 'package:bildgenerator/services/glb_preview.dart';
import 'package:bildgenerator/services/model_import.dart';

void main() {
  // Eine echte FBX aus Blender 4.0: ein Würfel und eine UV-Kugel,
  // zusammen 490 Punkte, 518 Polygone, 972 Dreiecke nach der
  // Fächer-Triangulierung. Selbst geschriebene Testdateien würden nur
  // die eigenen Annahmen bestätigen.
  final datei = File('test/assets/wuerfel_kugel.fbx');
  final bytes = Uint8List.fromList(datei.readAsBytesSync());

  group('Binäre FBX aus Blender', () {
    test('Wird als FBX erkannt', () {
      expect(isBinaryFbx(bytes), isTrue);
      expect(looksLikeFbx(bytes), isTrue);
      expect(isBinaryFbx(Uint8List.fromList([1, 2, 3])), isFalse);
    });

    test('Punkte und Polygone stimmen mit Blender überein', () {
      final mesh = readFbxMesh(bytes);
      expect(mesh.positions.length ~/ 3, 490);
      expect(mesh.polygons.length, 518);
      expect(mesh.triangleCount, 972);
    });

    test('Einheiten und Achse stehen drin', () {
      final mesh = readFbxMesh(bytes);
      // Blender schreibt „eine Einheit ist ein Zentimeter" und legt
      // den Maßstab als Lcl Scaling 100 an die Objekte.
      expect(mesh.unitScale, 1.0);
      expect(mesh.upAxis, 1);
      // Zwei Netze: Würfel und Kugel.
      expect(mesh.objects, 2);
    });

    test('Daraus wird eine lesbare GLB', () async {
      final glb = fbxToGlb(bytes);
      final preview = await parseGlbForPreview(glb);
      expect(preview.positions.length ~/ 3, 490);
      expect(preview.indices.length ~/ 3, 972);
    });

    test('Der Maßstab wird auf Meter gebracht', () async {
      final glb = fbxToGlb(bytes);
      final preview = await parseGlbForPreview(glb);
      var minY = double.infinity, maxY = -double.infinity;
      var minX = double.infinity, maxX = -double.infinity;
      for (var i = 0; i + 2 < preview.positions.length; i += 3) {
        minX = preview.positions[i] < minX ? preview.positions[i] : minX;
        maxX = preview.positions[i] > maxX ? preview.positions[i] : maxX;
        minY = preview.positions[i + 1] < minY
            ? preview.positions[i + 1]
            : minY;
        maxY = preview.positions[i + 1] > maxY
            ? preview.positions[i + 1]
            : maxY;
      }
      // Der Würfel hat in Blender 2 Einheiten Kantenlänge, die Kugel
      // Durchmesser 2. In der FBX stehen sie mit Lcl Scaling 100 in
      // Zentimetern; hier müssen 2 Meter herauskommen.
      expect(maxY - minY, closeTo(2.0, 0.05));
      // Und die Kugel steht 4 Meter neben dem Würfel: Ohne die
      // Objekt-Transformation fielen beide in den Ursprung, und die
      // Breite wäre 2 statt 6.
      expect(maxX - minX, closeTo(6.0, 0.05));
    });

    test('Der allgemeine Import nimmt FBX jetzt an', () async {
      final glb = importModelToGlb(bytes, 'figur.fbx');
      expect((await parseGlbForPreview(glb)).indices.length ~/ 3, 972);
      // Auch ohne passenden Dateinamen, am Inhalt erkannt.
      expect(() => importModelToGlb(bytes, 'ohne-endung'),
          returnsNormally);
    });
  });

  group('Text-FBX', () {
    // Blender schreibt nur binär; die Textfassung stammt aus älteren
    // Werkzeugen und aus Maya. Zwei Dreiecke, ein Quadrat.
    const text = '''
; FBX 7.3.0 project file
FBXHeaderExtension:  {
	FBXHeaderVersion: 1003
}
GlobalSettings:  {
	Properties70:  {
		P: "UpAxis", "int", "Integer", "",1
		P: "UnitScaleFactor", "double", "Number", "",1
	}
}
Objects:  {
	Geometry: 123, "Geometry::Flaeche", "Mesh" {
		Vertices: *12 {
			a: 0,0,0,1,0,0,1,0,1,0,0,1
		}
		PolygonVertexIndex: *4 {
			a: 0,1,2,-4
		}
	}
}
''';

    final bytes = Uint8List.fromList(text.codeUnits);

    test('Wird erkannt und gelesen', () {
      expect(isAsciiFbx(bytes), isTrue);
      expect(isBinaryFbx(bytes), isFalse);
      final mesh = readFbxMesh(bytes);
      expect(mesh.positions.length ~/ 3, 4);
      expect(mesh.polygons, [
        [0, 1, 2, 3]
      ]);
      expect(mesh.triangleCount, 2);
    });

    test('Daraus wird ein Quadrat aus zwei Dreiecken', () async {
      final preview = await parseGlbForPreview(fbxToGlb(bytes));
      expect(preview.positions.length ~/ 3, 4);
      expect(preview.indices.length ~/ 3, 2);
    });
  });

  group('Was schiefgehen kann', () {
    test('Eine Datei ohne Netz wird verständlich abgelehnt', () {
      const leer = '''
FBXHeaderExtension:  {
	FBXHeaderVersion: 1003
}
Objects:  {
	Geometry: 1, "Geometry::Leer", "Mesh" {
	}
}
''';
      expect(
          () => fbxToGlb(Uint8List.fromList(leer.codeUnits)),
          throwsA(predicate(
              (e) => e.toString().contains('kein lesbares Netz'))));
    });

    test('Etwas anderes ist keine FBX', () {
      expect(() => readFbxMesh(Uint8List.fromList('hallo'.codeUnits)),
          throwsA(anything));
    });

    test('Ein Polygon ohne Abschlussmarke wird verworfen', () {
      // Die letzte Ecke eines Polygons trägt ein negatives Vorzeichen.
      // Fehlt es, ist die Liste abgeschnitten.
      const kaputt = '''
FBXHeaderExtension:  { FBXHeaderVersion: 1003 }
Objects:  {
	Geometry: 1, "Geometry::X", "Mesh" {
		Vertices: *9 { a: 0,0,0,1,0,0,1,0,1 }
		PolygonVertexIndex: *3 { a: 0,1,2 }
	}
}
''';
      final mesh = readFbxMesh(Uint8List.fromList(kaputt.codeUnits));
      expect(mesh.polygons, isEmpty);
    });
  });
}
