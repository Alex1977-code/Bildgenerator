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

  String? _openAiKey;
  String? _stabilityKey;

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
    } catch (_) {
      // Secure Storage nicht verfügbar – Schlüssel müssen erneut
      // eingegeben werden.
    }
    notifyListeners();
  }

  String? apiKeyFor(GenProvider p) =>
      p == GenProvider.openai ? _openAiKey : _stabilityKey;

  bool hasApiKeyFor(GenProvider p) {
    final key = apiKeyFor(p);
    return key != null && key.trim().isNotEmpty;
  }

  Future<void> setApiKey(GenProvider p, String value) async {
    final trimmed = value.trim();
    final storageKey =
        p == GenProvider.openai ? 'openai_api_key' : 'stability_api_key';
    if (p == GenProvider.openai) {
      _openAiKey = trimmed.isEmpty ? null : trimmed;
    } else {
      _stabilityKey = trimmed.isEmpty ? null : trimmed;
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

  void _persistString(String key, String value) {
    _prefs?.setString(key, value);
  }
}
