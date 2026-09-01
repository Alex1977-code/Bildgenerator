/// FBX schreiben – binär, Fassung 7.4.
///
/// Warum überhaupt: Der Roblox-Importer bevorzugt FBX für gerigte
/// Figuren, und bisher führte der Weg dorthin über Blender und das
/// mitgelieferte Skript. Für einen Knopf „als FBX speichern" ist das
/// ein Umweg über ein zweites Programm.
///
/// Was geschrieben wird: die Geometrie (Punkte, Polygone, Normalen,
/// Texturkoordinaten), das Skelett als LimbNode-Kette, die
/// Hautgewichte als Cluster und die Bindepose. Damit importiert
/// Studio eine gerigte Figur.
///
/// Was **nicht** geschrieben wird, und das steht auch in der
/// Oberfläche: Material und Textur. FBX legt Bilder entweder als
/// externe Datei daneben oder eingebettet als Video-Objekt ab; beides
/// ist eigene Arbeit, und die App liefert die Textur ohnehin schon als
/// PNG im Roblox-Paket mit. Ein FBX ohne Material importiert sauber,
/// es kommt nur grau herein.
///
/// Der Aufbau folgt der binären FBX-Struktur, die `fbx_reader.dart`
/// liest: Datensätze mit Endposition, Eigenschaften und Kindern.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'glb_preview.dart';

/// Das Trennzeichen zwischen Name und Klasse in FBX-Objektnamen:
/// zwei Steuerzeichen (0 und 1). Als Konstante statt als rohes Byte im
/// Quelltext – so bleibt die Datei lesbar und lässt sich mit
/// gewöhnlichen Werkzeugen bearbeiten.
final String fbxNameSeparator =
    String.fromCharCodes(const [0, 1]);

/// Eine Objektkennung.
///
/// FBX verlangt sie als **64-Bit-Zahl**, auch wenn sie klein ist. Die
/// erste Fassung schrieb kleine Zahlen platzsparend als int32 – und
/// Blenders Importer brach mit einer Zusicherung ab
/// (`props_type[:3] == b'LSS'`): Er prüft die Typenfolge jedes
/// Objekts, und die muss int64, String, String sein.
class _Id {
  const _Id(this.value);
  final int value;
}

/// Ein Knochen für den Export.
class FbxBone {
  const FbxBone({
    required this.name,
    required this.parent,
    required this.translation,
    required this.bindMatrix,
  });

  final String name;

  /// Index des Elternknochens, -1 für die Wurzel.
  final int parent;

  /// Lage gegenüber dem Elternknochen.
  final List<double> translation;

  /// Die Weltmatrix des Knochens in Bindestellung, spaltenweise wie
  /// in glTF.
  final List<double> bindMatrix;
}

/// Alles, was in die Datei soll.
class FbxScene {
  const FbxScene({
    required this.name,
    required this.positions,
    required this.indices,
    this.normals,
    this.uvs,
    this.bones = const [],
    this.jointsPerVertex = const [],
    this.weightsPerVertex = const [],
    this.unitScaleFactor = 100.0,
  });

  final String name;

  /// x, y, z je Punkt.
  final Float32List positions;

  /// Dreiecke, je drei Indizes.
  final Uint32List indices;

  final Float32List? normals;
  final Float32List? uvs;

  final List<FbxBone> bones;

  /// Vier Knochenindizes je Punkt (wie glTF JOINTS_0).
  final List<int> jointsPerVertex;

  /// Vier Gewichte je Punkt (wie glTF WEIGHTS_0).
  final List<double> weightsPerVertex;

  /// Wie viele Zentimeter eine Einheit der Datei sind. 100 heißt: die
  /// Zahlen in der Datei sind Meter – so schreibt es Blender, und der
  /// Roblox-Importer rechnet damit eine Einheit auf einen Stud.
  final double unitScaleFactor;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
  bool get hasSkin =>
      bones.isNotEmpty &&
      jointsPerVertex.length == vertexCount * 4 &&
      weightsPerVertex.length == vertexCount * 4;
}

/// Baut die FBX-Datei.
Uint8List writeFbx(FbxScene scene) {
  final w = _Writer();
  w.header();

  // Kennungen: FBX verlangt eindeutige 64-Bit-Zahlen. Fortlaufend ab
  // einer beliebigen Basis – nichts daran muss zufällig sein.
  var nextId = 1000000;
  int id() => nextId++;
  final geometryId = id();
  final modelId = id();
  final boneIds = [for (var i = 0; i < scene.bones.length; i++) id()];
  final skinId = id();
  final clusterIds = [for (var i = 0; i < scene.bones.length; i++) id()];
  final poseId = id();

  w.node('FBXHeaderExtension', [], (n) {
    n.node('FBXHeaderVersion', [1003]);
    n.node('FBXVersion', [7400]);
    n.node('Creator', ['3DGenerator']);
  });
  w.node('Creator', ['3DGenerator']);

  w.node('GlobalSettings', [], (n) {
    n.node('Version', [1000]);
    n.node('Properties70', [], (p) {
      // Y nach oben, Z nach vorn – so erwartet es Roblox, und so
      // liegen die Daten in glTF ohnehin schon.
      p.property70int('UpAxis', 1);
      p.property70int('UpAxisSign', 1);
      p.property70int('FrontAxis', 2);
      p.property70int('FrontAxisSign', 1);
      p.property70int('CoordAxis', 0);
      p.property70int('CoordAxisSign', 1);
      p.property70double('UnitScaleFactor', scene.unitScaleFactor);
      p.property70double('OriginalUnitScaleFactor', scene.unitScaleFactor);
    });
  });

  w.node('Documents', [], (n) {
    n.node('Count', [1]);
    n.node('Document', [_Id(id()), 'Scene', 'Scene'], (d) {
      d.node('Properties70', []);
      d.node('RootNode', [0]);
    });
  });
  w.node('References', []);

  w.node('Definitions', [], (n) {
    n.node('Version', [100]);
    n.node('Count', [3 + scene.bones.length * 2 + (scene.hasSkin ? 2 : 0)]);
    void typ(String name, int count) {
      n.node('ObjectType', [name], (o) => o.node('Count', [count]));
    }

    typ('GlobalSettings', 1);
    typ('Geometry', 1);
    typ('Model', 1 + scene.bones.length);
    if (scene.hasSkin) {
      typ('Deformer', 1 + scene.bones.length);
      typ('Pose', 1);
    }
  });

  w.node('Objects', [], (objects) {
    _writeGeometry(objects, geometryId, scene);
    _writeMeshModel(objects, modelId, scene);
    for (var i = 0; i < scene.bones.length; i++) {
      _writeBoneModel(objects, boneIds[i], scene.bones[i]);
    }
    if (scene.hasSkin) {
      objects.node('Deformer', [_Id(skinId), '${fbxNameSeparator}Deformer', 'Skin'], (d) {
        d.node('Version', [101]);
        d.node('Link_DeformAcuracy', [50.0]);
      });
      final zuordnung = _clusterData(scene);
      for (var i = 0; i < scene.bones.length; i++) {
        _writeCluster(objects, clusterIds[i], scene.bones[i], zuordnung[i]);
      }
      _writePose(objects, poseId, scene, modelId, boneIds);
    }
  });

  w.node('Connections', [], (c) {
    // Geometrie hängt am Modell, das Modell an der Wurzel.
    c.node('C', ['OO', _Id(geometryId), _Id(modelId)]);
    c.node('C', ['OO', _Id(modelId), const _Id(0)]);
    for (var i = 0; i < scene.bones.length; i++) {
      final parent = scene.bones[i].parent;
      c.node('C', [
        'OO',
        _Id(boneIds[i]),
        _Id(parent < 0 ? 0 : boneIds[parent]),
      ]);
    }
    if (scene.hasSkin) {
      c.node('C', ['OO', _Id(skinId), _Id(geometryId)]);
      for (var i = 0; i < scene.bones.length; i++) {
        c.node('C', ['OO', _Id(clusterIds[i]), _Id(skinId)]);
        c.node('C', ['OO', _Id(boneIds[i]), _Id(clusterIds[i])]);
      }
    }
  });

  w.node('Takes', [], (t) => t.node('Current', ['']));
  return w.finish();
}

void _writeGeometry(_Node objects, int id, FbxScene scene) {
  objects.node('Geometry', [_Id(id), '${scene.name}${fbxNameSeparator}Geometry', 'Mesh'],
      (g) {
    g.node('GeometryVersion', [124]);
    g.nodeDoubles('Vertices', Float64List.fromList(
            [for (final v in scene.positions) v.toDouble()]));

    // FBX schreibt die Ecken hintereinander und markiert die letzte
    // eines Polygons mit negativem Vorzeichen.
    final polygon = Int32List(scene.indices.length);
    for (var i = 0; i < scene.indices.length; i += 3) {
      polygon[i] = scene.indices[i];
      polygon[i + 1] = scene.indices[i + 1];
      polygon[i + 2] = -scene.indices[i + 2] - 1;
    }
    g.nodeInts('PolygonVertexIndex', polygon);

    final normals = scene.normals;
    if (normals != null && normals.length == scene.positions.length) {
      // ByPolygonVertex: je Ecke eines Polygons eine Normale. Die
      // Punktnormalen werden dafür je Ecke wiederholt – so verlangt es
      // das Format, und so schreiben es auch Blender und Maya.
      final out = Float64List(scene.indices.length * 3);
      for (var i = 0; i < scene.indices.length; i++) {
        final v = scene.indices[i];
        out[i * 3] = normals[v * 3];
        out[i * 3 + 1] = normals[v * 3 + 1];
        out[i * 3 + 2] = normals[v * 3 + 2];
      }
      g.node('LayerElementNormal', [0], (n) {
        n.node('Version', [101]);
        n.node('Name', ['']);
        n.node('MappingInformationType', ['ByPolygonVertex']);
        n.node('ReferenceInformationType', ['Direct']);
        n.nodeDoubles('Normals', out);
      });
    }

    final uvs = scene.uvs;
    if (uvs != null && uvs.length == scene.vertexCount * 2) {
      g.node('LayerElementUV', [0], (n) {
        n.node('Version', [101]);
        n.node('Name', ['UVMap']);
        n.node('MappingInformationType', ['ByPolygonVertex']);
        n.node('ReferenceInformationType', ['IndexToDirect']);
        // FBX zählt V von unten, glTF von oben.
        final werte = Float64List(uvs.length);
        for (var i = 0; i < scene.vertexCount; i++) {
          werte[i * 2] = uvs[i * 2];
          werte[i * 2 + 1] = 1.0 - uvs[i * 2 + 1];
        }
        n.nodeDoubles('UV', werte);
        n.nodeInts('UVIndex', Int32List.fromList(
                [for (final i in scene.indices) i]));
      });
    }

    g.node('Layer', [0], (l) {
      l.node('Version', [100]);
      if (normals != null) {
        l.node('LayerElement', [], (e) {
          e.node('Type', ['LayerElementNormal']);
          e.node('TypedIndex', [0]);
        });
      }
      if (uvs != null) {
        l.node('LayerElement', [], (e) {
          e.node('Type', ['LayerElementUV']);
          e.node('TypedIndex', [0]);
        });
      }
    });
  });
}

void _writeMeshModel(_Node objects, int id, FbxScene scene) {
  objects.node('Model', [_Id(id), '${scene.name}${fbxNameSeparator}Model', 'Mesh'], (m) {
    m.node('Version', [232]);
    m.node('Properties70', [], (p) {
      p.property70int('DefaultAttributeIndex', 0);
      p.property70vector('Lcl Translation', 0, 0, 0);
      p.property70vector('Lcl Rotation', 0, 0, 0);
      p.property70vector('Lcl Scaling', 1, 1, 1);
    });
    m.node('MultiLayer', [0]);
    m.node('MultiTake', [0]);
    m.node('Shading', [true]);
    m.node('Culling', ['CullingOff']);
  });
}

void _writeBoneModel(_Node objects, int id, FbxBone bone) {
  objects.node('Model', [_Id(id), '${bone.name}${fbxNameSeparator}Model', 'LimbNode'],
      (m) {
    m.node('Version', [232]);
    m.node('Properties70', [], (p) {
      p.property70vector('Lcl Translation', bone.translation[0],
          bone.translation[1], bone.translation[2]);
      p.property70vector('Lcl Rotation', 0, 0, 0);
      p.property70vector('Lcl Scaling', 1, 1, 1);
    });
    m.node('MultiLayer', [0]);
    m.node('MultiTake', [0]);
    m.node('Shading', [true]);
    m.node('Culling', ['CullingOff']);
  });
}

/// Punkte und Gewichte je Knochen – FBX legt sie andersherum ab als
/// glTF: dort vier Knochen je Punkt, hier alle Punkte je Knochen.
///
/// Nennt eine GLB denselben Knochen für einen Punkt zweimal (0,55 +
/// 0,45 auf „Hips"), werden die Anteile hier **addiert**. In glTF ist
/// das harmlos, weil beim Häuten summiert wird; in FBX steht je
/// Cluster eine Punktnummer mit einem Gewicht, und Blender überschreibt
/// beim Import den ersten Eintrag mit dem zweiten – der Punkt verlöre
/// dann fast die Hälfte seines Gewichts. Genau das war an einer
/// Testfigur zu sehen: Gewichtssumme 0,453 statt 1,0.
List<(List<int>, List<double>)> _clusterData(FbxScene scene) {
  final out = [
    for (var i = 0; i < scene.bones.length; i++) (<int>[], <double>[]),
  ];
  final proPunkt = <int, double>{};
  for (var v = 0; v < scene.vertexCount; v++) {
    proPunkt.clear();
    for (var k = 0; k < 4; k++) {
      final joint = scene.jointsPerVertex[v * 4 + k];
      final weight = scene.weightsPerVertex[v * 4 + k];
      if (weight <= 0 || joint < 0 || joint >= out.length) continue;
      proPunkt[joint] = (proPunkt[joint] ?? 0) + weight;
    }
    proPunkt.forEach((joint, weight) {
      out[joint].$1.add(v);
      out[joint].$2.add(weight);
    });
  }
  return out;
}

void _writeCluster(_Node objects, int id, FbxBone bone,
    (List<int>, List<double>) data) {
  objects.node(
      'Deformer', [_Id(id), '${bone.name}${fbxNameSeparator}SubDeformer', 'Cluster'],
      (c) {
    c.node('Version', [100]);
    c.node('UserData', ['', '']);
    c.nodeInts('Indexes', Int32List.fromList(data.$1));
    c.nodeDoubles('Weights', Float64List.fromList(data.$2));
    // Transform: die Weltmatrix des Netzes zur Bindezeit (Einheit,
    // weil die Punkte schon in Weltlage stehen).
    c.nodeDoubles('Transform', _identity16());
    // TransformLink: die Weltmatrix des Knochens zur Bindezeit.
    c.nodeDoubles('TransformLink', Float64List.fromList(bone.bindMatrix));
  });
}

void _writePose(_Node objects, int id, FbxScene scene, int modelId,
    List<int> boneIds) {
  objects.node('Pose', [_Id(id), 'BindPose${fbxNameSeparator}Pose', 'BindPose'], (p) {
    p.node('Type', ['BindPose']);
    p.node('Version', [100]);
    p.node('NbPoseNodes', [1 + scene.bones.length]);
    p.node('PoseNode', [], (n) {
      n.node('Node', [_Id(modelId)]);
      n.nodeDoubles('Matrix', _identity16());
    });
    for (var i = 0; i < scene.bones.length; i++) {
      p.node('PoseNode', [], (n) {
        n.node('Node', [_Id(boneIds[i])]);
        n.nodeDoubles('Matrix', Float64List.fromList(scene.bones[i].bindMatrix));
      });
    }
  });
}

Float64List _identity16() => Float64List.fromList(
    [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

// ----------------------------------------------------------------
// Aus einer GLB
// ----------------------------------------------------------------

/// Liest eine GLB und schreibt sie als FBX.
///
/// Nimmt das Skelett mit, wenn eines drin ist. Das Netz wird dabei
/// **nicht** verändert – Maßstab und Lage bleiben, wie sie sind.
Future<Uint8List> glbToFbx(Uint8List glb, {String name = 'Model'}) async {
  final mesh = await parseGlbForPreview(glb);
  try {
    final rig = mesh.rig;
    final bones = <FbxBone>[];
    if (rig != null && rig.joints.isNotEmpty) {
      // Die Weltlage eines Knochens steckt in der inversen
      // Bindematrix: Sie rechnet von der Welt in den Knochen, gesucht
      // ist die Gegenrichtung. Bei einer starren Matrix ist das die
      // transponierte Drehung und die zurückgerechnete Verschiebung.
      List<double> weltPosition(int j) {
        final m = rig.inverseBindMatrices;
        final o = j * 16;
        if (o + 15 >= m.length) return [0, 0, 0];
        final tx = m[o + 12], ty = m[o + 13], tz = m[o + 14];
        // Spaltenweise: Spalte k liegt bei o + k*4.
        final r00 = m[o], r01 = m[o + 4], r02 = m[o + 8];
        final r10 = m[o + 1], r11 = m[o + 5], r12 = m[o + 9];
        final r20 = m[o + 2], r21 = m[o + 6], r22 = m[o + 10];
        return [
          -(r00 * tx + r10 * ty + r20 * tz),
          -(r01 * tx + r11 * ty + r21 * tz),
          -(r02 * tx + r12 * ty + r22 * tz),
        ];
      }

      final welt = [
        for (var j = 0; j < rig.joints.length; j++) weltPosition(j),
      ];
      for (var i = 0; i < rig.joints.length; i++) {
        final parent = rig.jointParents[i];
        final lokal = parent < 0
            ? welt[i]
            : [
                welt[i][0] - welt[parent][0],
                welt[i][1] - welt[parent][1],
                welt[i][2] - welt[parent][2],
              ];
        bones.add(FbxBone(
          name: rig.nodes[rig.joints[i]].name,
          parent: parent,
          translation: lokal,
          // Bindepose: verschoben, nicht gedreht – so baut die App
          // ihre Rigs, und so liest sie sie auch wieder.
          bindMatrix: [
            1, 0, 0, 0, //
            0, 1, 0, 0,
            0, 0, 1, 0,
            welt[i][0], welt[i][1], welt[i][2], 1,
          ],
        ));
      }
    }
    return writeFbx(FbxScene(
      name: _cleanName(name),
      positions: mesh.positions,
      indices: Uint32List.fromList(mesh.indices),
      normals: mesh.normals,
      uvs: mesh.uvs,
      bones: bones,
      jointsPerVertex: [for (final j in rig?.vertexJoints ?? const <int>[]) j],
      weightsPerVertex: [
        for (final w in rig?.vertexWeights ?? const <double>[]) w.toDouble(),
      ],
    ));
  } finally {
    mesh.dispose();
  }
}

/// FBX trennt Name und Klasse durch zwei Steuerzeichen – im Namen
/// selbst haben sie nichts zu suchen.
String _cleanName(String raw) {
  final clean = raw
      .replaceAll(RegExp(r'[\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean.isEmpty ? 'Model' : clean;
}

// ----------------------------------------------------------------
// Der Schreiber
// ----------------------------------------------------------------

/// Eine Stelle, an die Datensaetze geschrieben werden.
///
/// FBX nennt in jedem Datensatz die Position dahinter. Die steht erst
/// fest, wenn die Kinder geschrieben sind – deshalb bleibt die Stelle
/// zunaechst leer und wird nachgetragen.
class _Node {
  _Node(this.out);

  final List<int> out;

  /// Schreibt einen Datensatz. [children] baut die Kinder, [doubles]
  /// und [ints] sind Zahlenfelder als Eigenschaft.
  void node(
    String name,
    List<Object> properties, [
    void Function(_Node)? children,
  ]) =>
      _write(name, properties, children, null, null);

  /// Ein Datensatz, dessen einzige Eigenschaft ein Feld aus
  /// Kommazahlen ist (Vertices, Normals, Weights …).
  void nodeDoubles(String name, Float64List values) =>
      _write(name, const [], null, values, null);

  /// Dasselbe mit ganzen Zahlen (PolygonVertexIndex, Indexes …).
  void nodeInts(String name, Int32List values) =>
      _write(name, const [], null, null, values);

  void _write(
    String name,
    List<Object> properties,
    void Function(_Node)? children,
    Float64List? doubles,
    Int32List? ints,
  ) {
    final start = out.length;
    // Platzhalter fuer EndOffset, NumProperties, PropertyListLen.
    out.addAll(List.filled(12, 0));
    final nameBytes = latin1.encode(name);
    out.add(nameBytes.length);
    out.addAll(nameBytes);

    final propStart = out.length;
    var count = 0;
    for (final value in properties) {
      _writeProperty(out, value);
      count++;
    }
    if (doubles != null) {
      _writeDoubleArray(out, doubles);
      count++;
    }
    if (ints != null) {
      _writeIntArray(out, ints);
      count++;
    }
    final propLen = out.length - propStart;

    if (children != null) {
      children(this);
      // Eine Kinderliste wird durch einen Null-Datensatz beendet.
      out.addAll(List.filled(13, 0));
    }

    _setUint32(out, start, out.length);
    _setUint32(out, start + 4, count);
    _setUint32(out, start + 8, propLen);
  }

  /// Eine Zeile in Properties70. Der Aufbau ist immer derselbe: Name,
  /// Typ, Untertyp, Kennzeichen, dann die Werte.
  void property70int(String name, int value) =>
      node('P', [name, 'int', 'Integer', '', value]);

  void property70double(String name, double value) =>
      node('P', [name, 'double', 'Number', '', value]);

  void property70vector(String name, double x, double y, double z) =>
      node('P', [name, name, '', 'A', x, y, z]);
}

/// Der Schreiber der ganzen Datei.
class _Writer extends _Node {
  _Writer() : super(<int>[]);

  void header() {
    out.addAll(latin1.encode('Kaydara FBX Binary  '));
    out.add(0x00);
    out.addAll([0x1A, 0x00]);
    _addUint32(out, 7400);
  }

  Uint8List finish() {
    // Null-Datensatz schliesst die oberste Liste.
    out.addAll(List.filled(13, 0));
    // Fusszeile. Die Importer lesen bis zur letzten Liste; die
    // Fusszeile steht der Vollstaendigkeit halber da, mit der festen
    // Endmarke, an der sich eine FBX-Datei erkennen laesst.
    out.addAll(List.filled(16, 0));
    while (out.length % 16 != 0) {
      out.add(0);
    }
    _addUint32(out, 0);
    _addUint32(out, 7400);
    out.addAll(List.filled(120, 0));
    out.addAll(const [
      0xF8, 0x5A, 0x8C, 0x6A, 0xDE, 0xF5, 0xD9, 0x7E, //
      0xEC, 0xE9, 0x0C, 0xE3, 0x75, 0xE8, 0x1A, 0x30,
    ]);
    return Uint8List.fromList(out);
  }
}

void _writeProperty(List<int> out, Object value) {
  if (value is bool) {
    out.add(0x43);
    out.add(value ? 1 : 0);
  } else if (value is _Id) {
    // Kennungen immer als int64 – daran erkennt der Importer ein
    // Objekt.
    out.add(0x4C);
    _addInt64(out, value.value);
  } else if (value is int) {
    out.add(0x49);
    _addInt32(out, value);
  } else if (value is double) {
    out.add(0x44);
    _addFloat64(out, value);
  } else if (value is String) {
    out.add(0x53);
    // FBX legt Zeichenketten als Bytes ab; was nicht in Latin-1 passt,
    // wird zum Fragezeichen statt zum Absturz.
    final bytes = Uint8List.fromList(
        [for (final c in value.codeUnits) c < 256 ? c : 0x3F]);
    _addUint32(out, bytes.length);
    out.addAll(bytes);
  } else {
    throw ArgumentError('Unbekannte Eigenschaft: $value');
  }
}

void _writeDoubleArray(List<int> out, Float64List values) {
  out.add(0x64); // d
  _addUint32(out, values.length);
  _addUint32(out, 0); // unkomprimiert
  _addUint32(out, values.length * 8);
  final data = ByteData(values.length * 8);
  for (var i = 0; i < values.length; i++) {
    data.setFloat64(i * 8, values[i], Endian.little);
  }
  out.addAll(data.buffer.asUint8List());
}

void _writeIntArray(List<int> out, Int32List values) {
  out.add(0x69); // i
  _addUint32(out, values.length);
  _addUint32(out, 0);
  _addUint32(out, values.length * 4);
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    data.setInt32(i * 4, values[i], Endian.little);
  }
  out.addAll(data.buffer.asUint8List());
}

void _addUint32(List<int> out, int value) {
  out.add(value & 0xFF);
  out.add((value >> 8) & 0xFF);
  out.add((value >> 16) & 0xFF);
  out.add((value >> 24) & 0xFF);
}

void _addInt32(List<int> out, int value) => _addUint32(out, value & 0xFFFFFFFF);

void _addInt64(List<int> out, int value) {
  final data = ByteData(8)..setInt64(0, value, Endian.little);
  out.addAll(data.buffer.asUint8List());
}

void _addFloat64(List<int> out, double value) {
  final data = ByteData(8)..setFloat64(0, value, Endian.little);
  out.addAll(data.buffer.asUint8List());
}

void _setUint32(List<int> out, int offset, int value) {
  out[offset] = value & 0xFF;
  out[offset + 1] = (value >> 8) & 0xFF;
  out[offset + 2] = (value >> 16) & 0xFF;
  out[offset + 3] = (value >> 24) & 0xFF;
}
