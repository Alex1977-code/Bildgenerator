import 'package:flutter/foundation.dart';

/// Reicht ein fertiges 3D-Modell aus der Galerie in den 3D-Tab
/// zurück – und wechselt dabei dorthin.
///
/// **Warum das nötig ist.** Die Gegenstände zu einer Figur hingen bis
/// hierher an der Ergebnisliste des 3D-Tabs, und die lebt nur im
/// Arbeitsspeicher. Nach einem Neustart war die Figur zwar noch in
/// der Galerie, aber der Weg zu „Passende Gegenstände" war weg: Man
/// hätte sie neu erzeugen müssen, um Zubehör dazu zu bekommen. Genau
/// dort sucht man die Funktion aber – am fertigen Modell.
///
/// Gebaut wie [PromptRelay], nur mit den Daten eines Modells statt
/// eines Prompts.
class ModelRelay extends ChangeNotifier {
  _PendingModel? _pending;

  /// Holt das wartende Modell ab (und leert die Ablage).
  ({Uint8List glb, String label, String prompt})? takePending() {
    final value = _pending;
    _pending = null;
    return value == null
        ? null
        : (glb: value.glb, label: value.label, prompt: value.prompt);
  }

  /// Ob gerade eines wartet – für die Anzeige, bevor es abgeholt wird.
  bool get hasPending => _pending != null;

  void send({
    required Uint8List glb,
    required String label,
    String prompt = '',
  }) {
    _pending = _PendingModel(glb, label, prompt);
    notifyListeners();
  }
}

class _PendingModel {
  const _PendingModel(this.glb, this.label, this.prompt);
  final Uint8List glb;
  final String label;
  final String prompt;
}
