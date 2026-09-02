import 'package:flutter/foundation.dart';

/// Reicht ein fertiges Bild aus dem Bild-Tab in den 3D-Tab – als
/// Vorderansicht, und wechselt dabei dorthin.
///
/// Das ist der Knopf „→ 3D" an jedem Ergebnis. Bisher war der Weg:
/// Bild herunterladen, in den 3D-Tab, „Aus Bild", Datei suchen. Der
/// Hauptweg der App ist aber genau dieser Schritt – Bild, dann 3D –,
/// und ein Hauptweg braucht keinen Umweg über die Platte.
///
/// Gebaut wie [PromptRelay] und [ModelRelay].
class ImageRelay extends ChangeNotifier {
  _PendingImage? _pending;

  ({Uint8List bytes, String name, String prompt})? takePending() {
    final value = _pending;
    _pending = null;
    return value == null
        ? null
        : (bytes: value.bytes, name: value.name, prompt: value.prompt);
  }

  bool get hasPending => _pending != null;

  void send({
    required Uint8List bytes,
    required String name,
    String prompt = '',
  }) {
    _pending = _PendingImage(bytes, name, prompt);
    notifyListeners();
  }
}

class _PendingImage {
  const _PendingImage(this.bytes, this.name, this.prompt);
  final Uint8List bytes;
  final String name;
  final String prompt;
}
