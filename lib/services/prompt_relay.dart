import 'package:flutter/foundation.dart';

/// Überträgt einen Prompt aus der Galerie zurück in den Generator
/// und wechselt dabei zum Generator-Tab.
class PromptRelay extends ChangeNotifier {
  String? _pending;

  String? takePending() {
    final value = _pending;
    _pending = null;
    return value;
  }

  void send(String prompt) {
    _pending = prompt;
    notifyListeners();
  }
}
