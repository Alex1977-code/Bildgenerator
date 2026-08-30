import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Minimale Schnittstelle für die sichere Schlüsselablage (testbar).
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Verschlüsselte Ablage über [FlutterSecureStorage]
/// (Keychain auf iOS, Keystore auf Android, DPAPI auf Windows).
class SecureKeyStore implements KeyStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Unverschlüsselte In-Memory-Ablage für Tests.
class InMemoryKeyStore implements KeyStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Einstellungen der App: Provider, API-Schlüssel, zuletzt genutzte Optionen.
class SettingsService extends ChangeNotifier {
  SettingsService({KeyStore? keyStore})
      : _secure = keyStore ?? SecureKeyStore();

  final KeyStore _secure;
  SharedPreferences? _prefs;

  GenProvider provider = GenProvider.openai;
  ThemeMode themeMode = ThemeMode.system;

  // Zuletzt genutzte Generierungs-Optionen (werden gespeichert).
  String openAiSize = 'auto';
  String stabilityAspect = '1:1';
  String quality = 'auto';
  bool transparent = false;
  String outputFormat = 'png';
  int compression = 90;
  int count = 1;
  String stylePreset = '';
  String geminiAspect = '1:1';
  String geminiImageSize = '1K';

  // Gewähltes Modell je Provider (auch freie IDs für neue Modelle möglich).
  String openAiModel = 'gpt-image-1';
  String stabilityModel = 'core';
  String geminiModel = 'gemini-2.5-flash-image';

  // Wasserzeichen mit eigenem Logo.
  bool watermarkEnabled = false;
  String watermarkPosition = 'br';
  int watermarkSizePercent = 18;
  int watermarkOpacity = 70;
  Uint8List? watermarkLogo;

  String? _openAiKey;
  String? _stabilityKey;
  String? _geminiKey;
  String? _meshyKey;
  String? _tripoKey;
  String? _falKey;
  String? _rodinKey;
  String? _replicateKey;

  /// Gewählter 3D-Provider: 'local', 'stability', 'meshy', 'tripo',
  /// 'fal', 'rodin', 'replicate' oder 'selfhost' (eigener 3D-Server,
  /// siehe server/README.md).
  String threeDProvider = 'local';

  /// Adresse des eigenen 3D-Servers (server/local3d_server.py),
  /// z. B. http://127.0.0.1:8765 – leer = nicht eingerichtet.
  String selfHostUrl = '';

  void setSelfHostUrl(String v) {
    selfHostUrl = v.trim();
    _persistString('selfHostUrl', selfHostUrl);
    notifyListeners();
  }

  /// Eingerichtete lokale 3D-Server, je Eintrag „backend|port|Ordner"
  /// (siehe InstalledServer in services/server_setup.dart). Damit
  /// lässt sich der Server in den Einstellungen auswählen und starten.
  List<String> localServers = const [];

  void rememberLocalServer(String entry) {
    if (entry.trim().isEmpty || localServers.contains(entry)) return;
    localServers = [...localServers, entry];
    _prefs?.setStringList('localServers', localServers);
    notifyListeners();
  }

  void forgetLocalServer(String entry) {
    if (!localServers.contains(entry)) return;
    localServers = [
      for (final e in localServers)
        if (e != entry) e,
    ];
    _prefs?.setStringList('localServers', localServers);
    notifyListeners();
  }

  /// Ersteller-Name für Erstellungsnachweise (PDF).
  String creatorName = '';

  void setCreatorName(String v) {
    creatorName = v.trim();
    _persistString('creatorName', creatorName);
    notifyListeners();
  }

  /// API-Schlüssel für den 3D-Provider Meshy.
  String? get meshyApiKey => _meshyKey;

  /// API-Schlüssel für den 3D-Provider Tripo3D.
  String? get tripoApiKey => _tripoKey;

  /// API-Schlüssel für den 3D-Marktplatz fal.ai.
  String? get falApiKey => _falKey;

  /// API-Schlüssel für Rodin (Hyper3D von Deemos).
  String? get rodinApiKey => _rodinKey;

  /// API-Token für Replicate.
  String? get replicateApiKey => _replicateKey;

  Future<void> setMeshyApiKey(String value) async {
    final trimmed = value.trim();
    _meshyKey = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await _secure.delete('meshy_api_key');
    } else {
      await _secure.write('meshy_api_key', trimmed);
    }
    notifyListeners();
  }

  Future<void> setTripoApiKey(String value) async {
    final trimmed = value.trim();
    _tripoKey = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await _secure.delete('tripo_api_key');
    } else {
      await _secure.write('tripo_api_key', trimmed);
    }
    notifyListeners();
  }

  Future<void> setFalApiKey(String value) async {
    final trimmed = value.trim();
    _falKey = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await _secure.delete('fal_api_key');
    } else {
      await _secure.write('fal_api_key', trimmed);
    }
    notifyListeners();
  }

  Future<void> setRodinApiKey(String value) async {
    final trimmed = value.trim();
    _rodinKey = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await _secure.delete('rodin_api_key');
    } else {
      await _secure.write('rodin_api_key', trimmed);
    }
    notifyListeners();
  }

  Future<void> setReplicateApiKey(String value) async {
    final trimmed = value.trim();
    _replicateKey = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await _secure.delete('replicate_api_key');
    } else {
      await _secure.write('replicate_api_key', trimmed);
    }
    notifyListeners();
  }

  /// Bis zu 5 eigene 3D-Vorlagen als JSON-Text (leerer Text = freier
  /// Platz). Inhalt und Aufbau bestimmt der 3D-Tab.
  List<String> customPresets = List<String>.filled(5, '');

  /// Anzahl der Plätze für eigene Vorlagen.
  static const customPresetSlots = 5;

  void setCustomPreset(int index, String json) {
    if (index < 0 || index >= customPresetSlots) return;
    final list = [...customPresets];
    list[index] = json;
    customPresets = list;
    _prefs?.setStringList('customPresets', list);
    notifyListeners();
  }

  void setThreeDProvider(String v) {
    threeDProvider = v;
    _persistString('threeDProvider', v);
    notifyListeners();
  }

  Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      provider = GenProvider.fromName(prefs.getString('provider'));
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString('themeMode'),
        orElse: () => ThemeMode.system,
      );
      openAiSize = prefs.getString('openAiSize') ?? openAiSize;
      stabilityAspect = prefs.getString('stabilityAspect') ?? stabilityAspect;
      quality = prefs.getString('quality') ?? quality;
      transparent = prefs.getBool('transparent') ?? transparent;
      outputFormat = prefs.getString('outputFormat') ?? outputFormat;
      compression = prefs.getInt('compression') ?? compression;
      count = prefs.getInt('count') ?? count;
      stylePreset = prefs.getString('stylePreset') ?? stylePreset;
      geminiAspect = prefs.getString('geminiAspect') ?? geminiAspect;
      geminiImageSize = prefs.getString('geminiImageSize') ?? geminiImageSize;
      openAiModel = prefs.getString('openAiModel') ?? openAiModel;
      stabilityModel = prefs.getString('stabilityModel') ?? stabilityModel;
      geminiModel = prefs.getString('geminiModel') ?? geminiModel;
      watermarkEnabled = prefs.getBool('watermarkEnabled') ?? watermarkEnabled;
      watermarkPosition =
          prefs.getString('watermarkPosition') ?? watermarkPosition;
      watermarkSizePercent =
          prefs.getInt('watermarkSizePercent') ?? watermarkSizePercent;
      watermarkOpacity = prefs.getInt('watermarkOpacity') ?? watermarkOpacity;
      threeDProvider = prefs.getString('threeDProvider') ?? threeDProvider;
      selfHostUrl = prefs.getString('selfHostUrl') ?? selfHostUrl;
      localServers = prefs.getStringList('localServers') ?? localServers;
      final storedPresets = prefs.getStringList('customPresets');
      if (storedPresets != null) {
        customPresets = [
          for (var i = 0; i < customPresetSlots; i++)
            i < storedPresets.length ? storedPresets[i] : '',
        ];
      }
      creatorName = prefs.getString('creatorName') ?? creatorName;
      for (final provider in GenProvider.values) {
        _fetchedModels[provider] =
            prefs.getStringList('fetchedModels_${provider.name}') ??
                const [];
      }
      final logoBase64 = prefs.getString('watermarkLogo');
      if (logoBase64 != null && logoBase64.isNotEmpty) {
        try {
          watermarkLogo = base64Decode(logoBase64);
        } catch (_) {}
      }
    } catch (_) {
      // Ohne Persistenz weiterlaufen (z. B. in Tests).
    }
    try {
      // Timeout, damit ein hängender Storage-Kanal den App-Start nie blockiert.
      _openAiKey = await _secure
          .read('openai_api_key')
          .timeout(const Duration(seconds: 5));
      _stabilityKey = await _secure
          .read('stability_api_key')
          .timeout(const Duration(seconds: 5));
      _geminiKey = await _secure
          .read('gemini_api_key')
          .timeout(const Duration(seconds: 5));
      _meshyKey = await _secure
          .read('meshy_api_key')
          .timeout(const Duration(seconds: 5));
      _tripoKey = await _secure
          .read('tripo_api_key')
          .timeout(const Duration(seconds: 5));
      _falKey = await _secure
          .read('fal_api_key')
          .timeout(const Duration(seconds: 5));
      _rodinKey = await _secure
          .read('rodin_api_key')
          .timeout(const Duration(seconds: 5));
      _replicateKey = await _secure
          .read('replicate_api_key')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Secure Storage nicht verfügbar – Schlüssel müssen erneut
      // eingegeben werden.
    }
    notifyListeners();
  }

  String? apiKeyFor(GenProvider p) => switch (p) {
        GenProvider.openai => _openAiKey,
        GenProvider.stability => _stabilityKey,
        GenProvider.gemini => _geminiKey,
      };

  bool hasApiKeyFor(GenProvider p) {
    final key = apiKeyFor(p);
    return key != null && key.trim().isNotEmpty;
  }

  /// Vom Anbieter abgerufene, aktuell verfügbare Modell-IDs.
  final Map<GenProvider, List<String>> _fetchedModels = {};

  List<String> fetchedModelsFor(GenProvider p) =>
      _fetchedModels[p] ?? const [];

  Future<void> setFetchedModels(GenProvider p, List<String> models) async {
    _fetchedModels[p] = models;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('fetchedModels_${p.name}', models);
    } catch (_) {}
    notifyListeners();
  }

  /// Gewähltes Modell des Providers.
  String modelFor(GenProvider p) => switch (p) {
        GenProvider.openai => openAiModel,
        GenProvider.stability => stabilityModel,
        GenProvider.gemini => geminiModel,
      };

  void setModelFor(GenProvider p, String value) {
    final model = value.trim();
    if (model.isEmpty) return;
    switch (p) {
      case GenProvider.openai:
        openAiModel = model;
        _persistString('openAiModel', model);
      case GenProvider.stability:
        stabilityModel = model;
        _persistString('stabilityModel', model);
      case GenProvider.gemini:
        geminiModel = model;
        _persistString('geminiModel', model);
    }
    notifyListeners();
  }

  Future<void> setApiKey(GenProvider p, String value) async {
    final trimmed = value.trim();
    final storageKey = switch (p) {
      GenProvider.openai => 'openai_api_key',
      GenProvider.stability => 'stability_api_key',
      GenProvider.gemini => 'gemini_api_key',
    };
    switch (p) {
      case GenProvider.openai:
        _openAiKey = trimmed.isEmpty ? null : trimmed;
      case GenProvider.stability:
        _stabilityKey = trimmed.isEmpty ? null : trimmed;
      case GenProvider.gemini:
        _geminiKey = trimmed.isEmpty ? null : trimmed;
    }
    if (trimmed.isEmpty) {
      await _secure.delete(storageKey);
    } else {
      await _secure.write(storageKey, trimmed);
    }
    notifyListeners();
  }

  void setProvider(GenProvider p) {
    provider = p;
    _persistString('provider', p.name);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _persistString('themeMode', mode.name);
    notifyListeners();
  }

  void setOpenAiSize(String v) {
    openAiSize = v;
    _persistString('openAiSize', v);
    notifyListeners();
  }

  void setStabilityAspect(String v) {
    stabilityAspect = v;
    _persistString('stabilityAspect', v);
    notifyListeners();
  }

  void setQuality(String v) {
    quality = v;
    _persistString('quality', v);
    notifyListeners();
  }

  void setTransparent(bool v) {
    transparent = v;
    // Transparenz benötigt PNG oder WebP.
    if (v && outputFormat == 'jpeg') {
      outputFormat = 'png';
      _persistString('outputFormat', outputFormat);
    }
    _prefs?.setBool('transparent', v);
    notifyListeners();
  }

  void setOutputFormat(String v) {
    outputFormat = v;
    if (v == 'jpeg' && transparent) {
      transparent = false;
      _prefs?.setBool('transparent', false);
    }
    _persistString('outputFormat', v);
    notifyListeners();
  }

  void setCompression(int v) {
    compression = v;
    _prefs?.setInt('compression', v);
    notifyListeners();
  }

  void setCount(int v) {
    count = v;
    _prefs?.setInt('count', v);
    notifyListeners();
  }

  void setStylePreset(String v) {
    stylePreset = v;
    _persistString('stylePreset', v);
    notifyListeners();
  }

  void setGeminiAspect(String v) {
    geminiAspect = v;
    _persistString('geminiAspect', v);
    notifyListeners();
  }

  void setGeminiImageSize(String v) {
    geminiImageSize = v;
    _persistString('geminiImageSize', v);
    notifyListeners();
  }

  void setWatermarkEnabled(bool v) {
    watermarkEnabled = v;
    _prefs?.setBool('watermarkEnabled', v);
    notifyListeners();
  }

  void setWatermarkPosition(String v) {
    watermarkPosition = v;
    _persistString('watermarkPosition', v);
    notifyListeners();
  }

  void setWatermarkSizePercent(int v) {
    watermarkSizePercent = v;
    _prefs?.setInt('watermarkSizePercent', v);
    notifyListeners();
  }

  void setWatermarkOpacity(int v) {
    watermarkOpacity = v;
    _prefs?.setInt('watermarkOpacity', v);
    notifyListeners();
  }

  void setWatermarkLogo(Uint8List? bytes) {
    watermarkLogo = bytes;
    if (bytes == null) {
      watermarkEnabled = false;
      _prefs?.setBool('watermarkEnabled', false);
      _prefs?.remove('watermarkLogo');
    } else {
      _persistString('watermarkLogo', base64Encode(bytes));
    }
    notifyListeners();
  }

  void _persistString(String key, String value) {
    _prefs?.setString(key, value);
  }
}
