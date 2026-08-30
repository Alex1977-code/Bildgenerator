import 'dart:typed_data';

/// Woran sich eine 3D-Datei erkennen lässt – am Inhalt, nicht am Namen.
///
/// Der Anlass war ein Lauf, der als `modell.glb` in der Galerie lag und
/// sich weder anzeigen noch prüfen noch riggen ließ: Drin war ein
/// binäres FBX. Tripo liefert **Quad-Netze ausschließlich als FBX** –
/// glTF/GLB kennt keine Vierecke, nur Dreiecke. Die App hatte die
/// Antwort ungesehen als GLB abgelegt, und jeder folgende Schritt
/// scheiterte an einer Datei, die nie eine GLB war.
enum ModelFormat {
  glb,
  gltfJson,
  fbxBinary,
  fbxAscii,
  obj,
  ply,
  stl,
  zip,
  unknown,
}

/// Liest die Dateiart aus den ersten Bytes.
ModelFormat detectModelFormat(Uint8List bytes) {
  if (bytes.length < 12) return ModelFormat.unknown;
  bool startsWith(List<int> magic) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  // 'glTF' – der Container von GLB.
  if (startsWith([0x67, 0x6C, 0x54, 0x46])) return ModelFormat.glb;
  // 'Kaydara FBX Binary  \x00'
  if (startsWith('Kaydara FBX Binary'.codeUnits)) {
    return ModelFormat.fbxBinary;
  }
  if (startsWith([0x50, 0x4B, 0x03, 0x04])) return ModelFormat.zip;
  if (startsWith('ply'.codeUnits)) return ModelFormat.ply;
  if (startsWith('solid'.codeUnits)) return ModelFormat.stl;

  // Textformate: die ersten paar hundert Zeichen reichen.
  final head = String.fromCharCodes(
      bytes.take(512).where((b) => b < 0x80).toList());
  final trimmed = head.trimLeft();
  if (trimmed.startsWith('{')) {
    if (trimmed.contains('"asset"') || trimmed.contains('"meshes"')) {
      return ModelFormat.gltfJson;
    }
  }
  if (trimmed.contains('FBXHeaderExtension')) return ModelFormat.fbxAscii;
  for (final line in trimmed.split('\n')) {
    final l = line.trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    if (l.startsWith('v ') ||
        l.startsWith('vt ') ||
        l.startsWith('vn ') ||
        l.startsWith('f ') ||
        l.startsWith('mtllib ') ||
        l.startsWith('o ')) {
      return ModelFormat.obj;
    }
    break;
  }
  return ModelFormat.unknown;
}

/// Dateiendung mit Punkt.
String modelExtension(ModelFormat format) => switch (format) {
      ModelFormat.glb => '.glb',
      ModelFormat.gltfJson => '.gltf',
      ModelFormat.fbxBinary || ModelFormat.fbxAscii => '.fbx',
      ModelFormat.obj => '.obj',
      ModelFormat.ply => '.ply',
      ModelFormat.stl => '.stl',
      ModelFormat.zip => '.zip',
      ModelFormat.unknown => '.bin',
    };

/// MIME-Typ für den Export.
String modelMimeType(ModelFormat format) => switch (format) {
      ModelFormat.glb => 'model/gltf-binary',
      ModelFormat.gltfJson => 'model/gltf+json',
      ModelFormat.fbxBinary || ModelFormat.fbxAscii => 'application/octet-stream',
      ModelFormat.obj => 'model/obj',
      ModelFormat.ply => 'application/octet-stream',
      ModelFormat.stl => 'model/stl',
      ModelFormat.zip => 'application/zip',
      ModelFormat.unknown => 'application/octet-stream',
    };

/// Kurzname für die Oberfläche.
String modelFormatLabel(ModelFormat format) => switch (format) {
      ModelFormat.glb => 'GLB',
      ModelFormat.gltfJson => 'glTF',
      ModelFormat.fbxBinary => 'FBX',
      ModelFormat.fbxAscii => 'FBX (Text)',
      ModelFormat.obj => 'OBJ',
      ModelFormat.ply => 'PLY',
      ModelFormat.stl => 'STL',
      ModelFormat.zip => 'ZIP-Archiv',
      ModelFormat.unknown => 'unbekanntes Format',
    };

/// Was die App mit dieser Datei kann – und was nicht.
///
/// Alles, was die App selbst rechnet (Ansicht, Roblox-Prüfung,
/// Auto-Rigging, R15-Umbenennung, STL/OBJ/3MF-Export), liest GLB.
bool modelIsUsableInApp(ModelFormat format) => format == ModelFormat.glb;

/// Klartext, warum eine Datei hier nur zum Herunterladen taugt.
String modelFormatLimitation(ModelFormat format) {
  if (modelIsUsableInApp(format)) return '';
  return 'Die Datei ist ${modelFormatLabel(format)}, keine GLB. '
      'Anzeigen, prüfen, riggen und die Formatwandlungen laufen in '
      'dieser App über GLB – bei dieser Datei geht deshalb nur der '
      'Download. In Blender lässt sie sich öffnen und als GLB '
      'speichern.';
}
