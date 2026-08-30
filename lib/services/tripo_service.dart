import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'generators.dart' show GenerationException;

/// Anbindung an die Tripo3D-API (Text→3D, Bild→3D, Auto-Rigging).
///
/// Tripo arbeitet mit asynchronen Tasks: anlegen, Status pollen, fertige
/// Modelle über signierte URLs herunterladen. Antworten sind in
/// `{"code": 0, "data": {…}}` verpackt – das gilt in beiden Fassungen.
///
/// **API-Fassungen.** Tripo stellt V2 ab: Seit dem 1. Oktober 2026 gibt
/// es dort keine Neuerungen und keinen Support mehr, am 1. November
/// 2026 nehmen die V2-Endpunkte keine Anfragen mehr an. Deshalb spricht
/// die App standardmäßig V3; V2 bleibt bis dahin als Rückfallweg
/// wählbar, falls bei einem Konto etwas klemmt.
///
/// Der Unterschied ist nicht nur der Pfad:
///
/// * V2 legt jeden Task über ein einziges `POST /task` an und nennt die
///   Art im Feld `type`. V3 hat je Art einen eigenen Endpunkt
///   (`/generation/text-to-model`, `/animations/rig` …) und kein
///   `type` mehr.
/// * Aus `model_version` wird `model`, und es ist **Pflicht**.
/// * Der Upload wandert von `/upload` nach `/files`, der Task-Abruf von
///   `/task/{id}` nach `/tasks/{id}`, das Guthaben von `/user/balance`
///   nach `/account/balance`.
/// * Die Ergebnis-URLs heißen jetzt `model_url` und `rendered_image_url`
///   statt `pbr_model`/`model` und `rendered_image`.
enum TripoApiVersion {
  /// Abgekündigt – Endpunkte enden am 1. November 2026.
  v2,

  /// Aktuelle Fassung.
  v3;

  static TripoApiVersion fromName(String? name) =>
      name == 'v2' ? TripoApiVersion.v2 : TripoApiVersion.v3;

  String get label => switch (this) {
        TripoApiVersion.v2 => 'V2 (läuft am 01.11.2026 aus)',
        TripoApiVersion.v3 => 'V3 (aktuell)',
      };
}

/// Tag, an dem die V2-Endpunkte keine Anfragen mehr annehmen
/// (1. November 2026, 00:00 UTC+8 = 31. Oktober 2026, 16:00 UTC).
final DateTime tripoV2Shutdown = DateTime.utc(2026, 10, 31, 16);

/// Tag, ab dem V2 keine Neuerungen und keinen Support mehr bekommt.
final DateTime tripoV2FeatureFreeze = DateTime.utc(2026, 9, 30, 16);

class TripoService {
  TripoService(this.apiKey, {this.version = TripoApiVersion.v3});

  final String apiKey;
  final TripoApiVersion version;

  bool get _v3 => version == TripoApiVersion.v3;

  String get _base => _v3
      ? 'https://openapi.tripo3d.ai/v3'
      : 'https://api.tripo3d.ai/v2/openapi';

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  Never _throwNetworkError(Object e) {
    throw GenerationException(
      'Netzwerkfehler: $e\n'
      'Bitte Internetverbindung prüfen. Hinweis: Im Browser (Web-Version) '
      'können CORS-Beschränkungen Anfragen blockieren – die nativen Apps '
      'sind davon nicht betroffen.',
    );
  }

  GenerationException _error(int httpStatus, String body) {
    var detail = body;
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      detail = (json['message'] ?? json['suberror'] ?? body).toString();
      final suggestion = json['suggestion'];
      if (suggestion is String && suggestion.isNotEmpty) {
        detail = '$detail ($suggestion)';
      }
    } catch (_) {}
    var hint = '';
    if (httpStatus == 401 || httpStatus == 403) {
      hint = ' Bitte den Tripo3D-API-Schlüssel in den Einstellungen prüfen '
          '(erhältlich auf platform.tripo3d.ai).';
    } else if (httpStatus == 402 ||
        detail.toLowerCase().contains('balance') ||
        detail.toLowerCase().contains('credit')) {
      hint = '\n\nHinweis: Vermutlich ist das Tripo-Guthaben aufgebraucht – '
          'auf platform.tripo3d.ai Credits aufladen.';
    } else if (httpStatus == 404 && _v3) {
      hint = '\n\nHinweis: Der V3-Endpunkt wurde nicht gefunden. In den '
          'Einstellungen lässt sich vorübergehend auf die alte V2-API '
          'zurückschalten – die nimmt allerdings nur noch bis zum '
          '1. November 2026 Anfragen an.';
    } else if (_isVersionGone(httpStatus, detail)) {
      hint = '\n\nHinweis: Die Tripo-API V2 ist abgeschaltet '
          '(seit 1. November 2026). In den Einstellungen auf V3 '
          'umstellen.';
    }
    return GenerationException('Tripo3D-Fehler ($httpStatus): $detail$hint');
  }

  bool _isVersionGone(int status, String detail) =>
      !_v3 &&
      (status == 404 ||
          status == 410 ||
          detail.toLowerCase().contains('deprecated'));

  Map<String, dynamic> _unwrap(http.Response response) {
    if (response.statusCode != 200) {
      throw _error(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final code = (json['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw _error(response.statusCode, response.body);
    }
    return json['data'] as Map<String, dynamic>? ?? {};
  }

  /// Legt einen Task an. [v3Path] ist der eigene V3-Endpunkt, [v2Type]
  /// der Wert, den V2 im Feld `type` erwartet.
  /// Legt einen Auftrag an.
  ///
  /// [optional] nennt Felder, die nicht jede Modellfassung kennt.
  /// Weist Tripo eines davon zurück, wird der Auftrag ohne diese
  /// Felder wiederholt – die Alternative wäre ein Lauf, der gar nicht
  /// erst startet, nur weil eine Zusatzoption fehlt.
  Future<String> _createTask(
    String v3Path,
    String v2Type,
    Map<String, dynamic> body, {
    Set<String> optional = const {},
  }) async {
    final url = _v3 ? '$_base$v3Path' : '$_base/task';
    final payload = _v3 ? body : {'type': v2Type, ...body};
    Future<http.Response> post(Map<String, dynamic> data) async {
      try {
        return await http.post(
          Uri.parse(url),
          headers: _jsonHeaders,
          body: jsonEncode(data),
        );
      } catch (e) {
        _throwNetworkError(e);
      }
    }

    var response = await post(payload);
    final rejected = optional
        .where((key) => payload.containsKey(key))
        .where((key) => response.body.contains(key))
        .toList();
    if (response.statusCode >= 400 && rejected.isNotEmpty) {
      final retry = {...payload}
        ..removeWhere((key, _) => optional.contains(key));
      response = await post(retry);
    }
    final data = _unwrap(response);
    final id = data['task_id'] as String?;
    if (id == null || id.isEmpty) {
      throw GenerationException('Tripo3D hat keine Task-ID zurückgegeben.');
    }
    return id;
  }

  /// Lädt ein Ausgangsbild hoch und liefert das Datei-Token.
  Future<String> uploadImage(Uint8List bytes, String mimeType) async {
    final subtype = mimeType.split('/').last;
    Future<http.Response> tryUpload(String path) async {
      final request = http.MultipartRequest('POST', Uri.parse('$_base/$path'))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'vorlage.${subtype == 'jpeg' ? 'jpg' : subtype}',
          contentType: MediaType('image', subtype),
        ));
      return http.Response.fromStream(await request.send());
    }

    http.Response response;
    try {
      response = await tryUpload(_v3 ? 'files' : 'upload');
      if (!_v3 && response.statusCode == 404) {
        // Ältere Konten nutzen unter V2 einen anderen Pfad.
        response = await tryUpload('upload/sts');
      }
    } catch (e) {
      _throwNetworkError(e);
    }
    final data = _unwrap(response);
    final token =
        (data['file_token'] ?? data['image_token'] ?? data['token'])
            as String?;
    if (token == null || token.isEmpty) {
      throw GenerationException(
          'Tripo3D hat kein Datei-Token zurückgegeben.');
    }
    return token;
  }

  /// Modellfassung, die an die API geht. V3 verlangt das Feld
  /// zwingend – „Standard" bedeutet dort die bewährte 2.5er-Fassung.
  static const String defaultModelVersion = 'v2.5-20250123';

  /// Längengrenzen der Textfelder laut Tripo. Wird eine überschritten,
  /// lehnt die API die ganze Anfrage mit 400 ab – deshalb kürzt der
  /// Dienst selbst, statt den Lauf scheitern zu lassen.
  static const int maxPromptChars = 1024;
  static const int maxNegativePromptChars = 255;

  /// Kürzt einen Text auf [max] Zeichen, und zwar an der letzten
  /// Kommastelle davor. Bei einer Stichwortliste bleibt so eine
  /// vollständige Liste übrig statt eines abgeschnittenen Worts.
  static String clipToLimit(String text, int max) {
    final trimmed = text.trim();
    if (trimmed.length <= max) return trimmed;
    final cut = trimmed.substring(0, max);
    final comma = cut.lastIndexOf(',');
    // Nur an einem Komma trennen, wenn dabei nicht die halbe Liste
    // wegfällt.
    if (comma > max * 0.6) return cut.substring(0, comma).trim();
    final space = cut.lastIndexOf(' ');
    return (space > max * 0.6 ? cut.substring(0, space) : cut).trim();
  }

  /// Qualitäts-Optionen, die alle Modell-Endpunkte verstehen.
  ///
  /// Öffentlich, damit sich nachprüfen lässt, was tatsächlich an
  /// Tripo geht – die Frage „schicken wir eigentlich alles Nötige?"
  /// soll ein Test beantworten, nicht eine Vermutung.
  @visibleForTesting
  Map<String, dynamic> qualityFields({
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
    int faceLimit = 0,
    bool smartLowPoly = false,
    bool pbr = true,
    bool autoSize = false,
  }) {
    final model = (modelVersion == null || modelVersion.isEmpty)
        ? defaultModelVersion
        : modelVersion;
    return {
      // V2 nannte das Feld model_version, V3 nennt es model und
      // verlangt es zwingend.
      if (_v3) 'model': model else if (modelVersion != null &&
          modelVersion.isNotEmpty)
        'model_version': modelVersion,
      // Die API verlangt bei Quad-Netzen ausdrücklich FBX; ohne die
      // Angabe lehnt sie den Auftrag ab oder liefert stillschweigend
      // FBX. Siehe [quadForcesFbx].
      if (quad) ...{'quad': true, 'out_format': 'fbx'},
      // Obergrenze der Flächen bei der Generierung.
      //
      // Gemessen an einem Lauf: mit face_limit = 10.000 kamen 101.298
      // Dreiecke zurück. Woran das lag, steht in keiner Dokumentation,
      // die hier greifbar war – belegt ist nur die Beobachtung. Wer
      // die Zahl sicher braucht, nimmt deshalb [createConvertTask]:
      // Dort ist face_limit dokumentiert (Vorgabe 10.000) und Tripo
      // rechnet das fertige Modell neu, mit UVs und Textur.
      if (faceLimit > 0) 'face_limit': faceLimit,
      if (smartLowPoly) 'smart_low_poly': true,
      if (texture && detailedTexture) 'texture_quality': 'detailed',
      // Maßstab: Ohne das kommt das Modell in einer beliebigen Größe.
      // Der Roblox-Importer rechnet glTF-Einheiten als Meter – eine
      // Figur mit 0,98 Einheiten wird dort 3,5 Studs hoch statt der
      // üblichen 5.
      if (autoSize) 'auto_size': true,
    };
  }

  Future<String> createTextTask(
    String prompt, {
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
    int faceLimit = 0,
    bool smartLowPoly = false,
    bool pbr = true,
    bool autoSize = false,
    String? negativePrompt,
  }) =>
      _createTask(optional: _optionalQualityFields,
          '/generation/text-to-model', 'text_to_model', {
        'prompt': clipToLimit(prompt, maxPromptChars),
        'texture': texture,
        // PBR liefert drei Bilder (Basecolor, Normal,
        // Metallic-Roughness). Wer nur eine Textur will – Roblox etwa
        // nimmt je Mesh ein Material –, schaltet es aus.
        'pbr': texture && pbr,
        if (negativePrompt != null && negativePrompt.trim().isNotEmpty)
          'negative_prompt':
              clipToLimit(negativePrompt, maxNegativePromptChars),
        ...qualityFields(
          texture: texture,
          modelVersion: modelVersion,
          quad: quad,
          detailedTexture: detailedTexture,
          faceLimit: faceLimit,
          smartLowPoly: smartLowPoly,
          pbr: pbr,
          autoSize: autoSize,
        ),
      });

  Future<String> createImageTask(
    String fileToken,
    String mimeType, {
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
    int faceLimit = 0,
    bool smartLowPoly = false,
    bool pbr = true,
    bool autoSize = false,
    bool alignToImage = false,
  }) {
    final subtype = mimeType.split('/').last;
    return _createTask(optional: _optionalQualityFields,
        '/generation/image-to-model', 'image_to_model', {
      'file': {
        'type': subtype == 'jpeg' ? 'jpg' : subtype,
        'file_token': fileToken,
      },
      'texture': texture,
      'pbr': texture && pbr,
      // Ohne das dreht Tripo das Modell nach eigenem Gutdünken; mit
      // „align_image" steht es so, wie es auf dem Bild steht. Für
      // eine Figur, die anschließend geriggt wird, ist das der
      // Unterschied zwischen „schaut nach vorn" und „schaut schräg".
      if (alignToImage) 'orientation': 'align_image',
      ...qualityFields(
        texture: texture,
        modelVersion: modelVersion,
        quad: quad,
        detailedTexture: detailedTexture,
        faceLimit: faceLimit,
        smartLowPoly: smartLowPoly,
        pbr: pbr,
        autoSize: autoSize,
      ),
    });
  }

  /// Multiview→Modell: Ansichten in der Reihenfolge Vorn, Links, Hinten,
  /// Rechts; fehlende Ansichten als leere Einträge. V3 führt das Feld
  /// `files` in genau dieser Reihenfolge weiter.
  Future<String> createMultiviewTask(
    List<(String, String)?> views, {
    required bool texture,
    String? modelVersion,
    bool quad = false,
    bool detailedTexture = false,
    int faceLimit = 0,
    bool smartLowPoly = false,
    bool pbr = true,
    bool autoSize = false,
    bool alignToImage = false,
  }) {
    Map<String, dynamic> fileEntry((String, String)? view) {
      if (view == null) return <String, dynamic>{};
      final (token, mimeType) = view;
      final subtype = mimeType.split('/').last;
      return {
        'type': subtype == 'jpeg' ? 'jpg' : subtype,
        'file_token': token,
      };
    }

    return _createTask(optional: _optionalQualityFields,
        '/generation/multiview-to-model', 'multiview_to_model', {
      'files': [for (final view in views) fileEntry(view)],
      'texture': texture,
      'pbr': texture && pbr,
      // Ohne das dreht Tripo das Modell nach eigenem Gutdünken; mit
      // „align_image" steht es so, wie es auf dem Bild steht. Für
      // eine Figur, die anschließend geriggt wird, ist das der
      // Unterschied zwischen „schaut nach vorn" und „schaut schräg".
      if (alignToImage) 'orientation': 'align_image',
      ...qualityFields(
        texture: texture,
        modelVersion: modelVersion,
        quad: quad,
        detailedTexture: detailedTexture,
        faceLimit: faceLimit,
        smartLowPoly: smartLowPoly,
        pbr: pbr,
        autoSize: autoSize,
      ),
    });
  }

  /// **Quad-Netze kommen bei Tripo ausschließlich als FBX zurück.**
  ///
  /// glTF/GLB kennt nur Dreiecke; ein Viereck lässt sich darin nicht
  /// ablegen. Die API erzwingt deshalb bei `quad: true` das
  /// FBX-Format – unabhängig davon, was sonst angefragt wird. Für
  /// alles, was diese App danach rechnet (Anzeige, Roblox-Prüfung,
  /// Rigging, STL/OBJ), ist das eine Sackgasse: Die Datei ist dann
  /// keine GLB mehr.
  static const bool quadForcesFbx = true;

  /// Felder, die nicht jede Modellfassung kennt – siehe [_createTask].
  static const Set<String> _optionalQualityFields = {
    'smart_low_poly',
    'texture_quality',
  };

  /// Rechnet ein fertiges Modell bei Tripo neu.
  ///
  /// Das ist der Weg, ein Modell auf eine Dreiecks- und Texturgrenze
  /// zu bringen, **ohne** es lokal zu dezimieren: Tripo remesht auf
  /// [faceLimit] und backt die Texturen auf [textureSize] – UVs und
  /// Bilder bleiben dabei erhalten, weil derselbe Dienst rechnet, der
  /// das Modell gebaut hat. Ein lokaler Dezimierer könnte das nicht:
  /// Er müsste UV-Nähte auftrennen und die Textur neu packen.
  ///
  /// Kostet zusätzliche Credits (laut Preisliste 10 für eine reine
  /// Umwandlung, 20 sobald Geometrie-Optionen wie `face_limit` oder
  /// `texture_size` dabei sind).
  ///
  /// Der V3-Pfad ist nicht dokumentiert gewesen, als das hier
  /// entstand; bei 404 nennt die Fehlermeldung den Weg über V2, wo
  /// der Auftrag als `type: convert_model` sicher angenommen wird.
  Future<String> createConvertTask(
    String modelTaskId, {
    int faceLimit = 0,
    int textureSize = 0,
    bool quad = false,
    bool packUv = false,
    String format = 'GLTF',
  }) =>
      _createTask('/conversion/convert-model', 'convert_model', {
        'original_model_task_id': modelTaskId,
        'format': format,
        if (faceLimit > 0) 'face_limit': faceLimit,
        if (textureSize > 0) 'texture_size': textureSize,
        if (quad) 'quad': true,
        if (packUv) 'pack_uv': true,
      });

  /// Prüft, ob das Modell riggbar ist (Figur erkannt).
  Future<String> createPrerigCheck(String modelTaskId) =>
      _createTask('/animations/rig-check', 'animate_prerigcheck', {
        'original_model_task_id': modelTaskId,
      });

  /// Figurtypen, die Tripos Rigging kennt – Schlüssel ist der Typ
  /// aus der App.
  static const Map<String, String> rigTypes = {
    'biped': 'biped',
    'quadruped': 'quadruped',
    'insect': 'hexapod',
    'bird': 'avian',
    'snake': 'serpentine',
    'fish': 'aquatic',
  };

  Future<String> createRig(String modelTaskId, {String rigType = ''}) =>
      _createTask(
          optional: const {'rig_type', 'spec'},
          '/animations/rig',
          'animate_rig',
          {
            'original_model_task_id': modelTaskId,
            'out_format': 'glb',
            // Ohne Typangabe muss Tripo raten; bei einer Kapuzenfigur
            // ohne sichtbares Gesicht ist das eine unnötige Hürde.
            if (rigTypes[rigType] != null) 'rig_type': rigTypes[rigType],
            // Mixamo-Namensschema: Die R15-Umbenennung dieser App ist
            // genau darauf ausgelegt (sie schneidet „mixamorig:" ab
            // und kennt „LeftForeArm" & Co.). Ohne die Angabe kommen
            // Tripo-eigene Namen, die sie schlechter trifft.
            'spec': 'mixamo',
          });

  Future<Map<String, dynamic>> getTask(String id) async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse(_v3 ? '$_base/tasks/$id' : '$_base/task/$id'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    return _unwrap(response);
  }

  /// Pollt einen Task bis zum Abschluss (max. ca. 15 Minuten).
  Future<Map<String, dynamic>> waitForTask(
    String id, {
    required String stageLabel,
    required void Function(String stage) onProgress,
    required bool Function() isCancelled,
  }) async {
    for (var attempt = 0; attempt < 180; attempt++) {
      if (isCancelled()) {
        throw GenerationException('Abgebrochen.');
      }
      final data = await getTask(id);
      final status = (data['status'] as String? ?? 'queued').toLowerCase();
      final progress = (data['progress'] as num?)?.toInt() ?? 0;
      onProgress('$stageLabel … $progress %');
      if (status == 'success') return data;
      if (status == 'failed' ||
          status == 'cancelled' ||
          status == 'banned' ||
          status == 'expired') {
        throw GenerationException(_taskFailure(status, data));
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw GenerationException(
        'Zeitüberschreitung – der Tripo3D-Task wurde nicht rechtzeitig '
        'fertig.');
  }

  /// Fehlermeldung eines gescheiterten Tasks. V3 liefert dazu
  /// `error_code` und `error_message`; 2008 ist eine Ablehnung durch die
  /// Inhaltsprüfung, 2018 ein abgelaufener Warteschlangen-Eintrag.
  static String _taskFailure(String status, Map<String, dynamic> data) {
    final code = (data['error_code'] as num?)?.toInt();
    final message = data['error_message'] as String?;
    final reason = switch (code) {
      2008 => 'Die Inhaltsprüfung von Tripo hat den Auftrag abgelehnt.',
      2018 => 'Der Auftrag ist in der Warteschlange abgelaufen – bitte '
          'noch einmal starten.',
      _ => message ?? '',
    };
    return 'Tripo3D-Task fehlgeschlagen ($status)'
        '${reason.isEmpty ? '.' : ': $reason'}';
  }

  /// GLB-URL aus einer Task-Antwort lesen (PBR-Variante bevorzugt).
  ///
  /// V3 nennt das Feld `model_url` (bzw. `model_urls`), V2 nannte es
  /// `pbr_model`/`model`. Beide Namen werden gelesen, damit ein Wechsel
  /// der Fassung nichts kaputt macht.
  static String? findGlbUrl(Map<String, dynamic> data) {
    final output = data['output'];
    if (output is Map) {
      for (final key in [
        'model_url',
        'pbr_model',
        'model',
        'base_model',
      ]) {
        final value = output[key];
        if (value is String && value.startsWith('http')) return value;
      }
      final list = output['model_urls'];
      if (list is List) {
        for (final value in list) {
          if (value is String && value.startsWith('http')) return value;
        }
      }
    }
    String? found;
    void walk(dynamic node) {
      if (found != null) return;
      if (node is String &&
          node.startsWith('http') &&
          node.contains('.glb')) {
        found = node;
      } else if (node is Map) {
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(data);
    return found;
  }

  static String? findThumbnailUrl(Map<String, dynamic> data) {
    final output = data['output'];
    if (output is Map) {
      for (final key in ['rendered_image_url', 'rendered_image']) {
        final value = output[key];
        if (value is String && value.startsWith('http')) return value;
      }
    }
    return null;
  }

  /// Verbleibendes Guthaben (Credits) des Kontos.
  Future<double?> fetchBalance() async {
    http.Response response;
    try {
      response = await http.get(
        Uri.parse(
            _v3 ? '$_base/account/balance' : '$_base/user/balance'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
    } catch (e) {
      _throwNetworkError(e);
    }
    final data = _unwrap(response);
    return (data['balance'] as num?)?.toDouble();
  }

  /// Lädt eine Datei (z. B. das fertige GLB) herunter.
  Future<Uint8List> downloadFile(String url) async {
    http.Response response;
    try {
      response = await http.get(Uri.parse(url));
    } catch (e) {
      _throwNetworkError(e);
    }
    if (response.statusCode != 200) {
      throw GenerationException(
          'Download fehlgeschlagen (${response.statusCode}).');
    }
    return response.bodyBytes;
  }
}
