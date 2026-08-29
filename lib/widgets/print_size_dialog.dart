import 'package:flutter/material.dart';

import '../services/mesh_check.dart';

/// Fragt die Druckgröße (längste Seite in mm) ab und zeigt das
/// Ergebnis der Wasserdichtheits-Prüfung an – gemeinsam genutzt vom
/// Viewer und vom Export-Menü der Ergebnisliste.
Future<double?> askPrintSizeDialog(
  BuildContext context, {
  required String title,
  required String note,
  MeshCheckResult? check,
}) {
  final controller = TextEditingController(text: '100');
  final (checkIcon, checkColor, checkText) = check == null
      ? (Icons.help_outline, Colors.grey, 'Netz nicht geprüft.')
      : check.watertight
          ? (
              Icons.check_circle,
              Colors.green,
              'Geprüft: Das Modell ist geschlossen (wasserdicht) und '
                  'damit druckbar.'
                  '${check.nonManifoldEdges > 0 ? ' ${check.nonManifoldEdges} Berührungskanten – für Slicer unkritisch.' : ''}'
            )
          : (
              Icons.warning_amber,
              Colors.orange,
              '${check.openEdges} offene Kanten gefunden – meist '
                  'unkritisch: PrusaSlicer, Bambu Studio & Co. '
                  'reparieren das beim Import automatisch.'
            );
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Größe der längsten Seite (mm)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(checkIcon, color: checkColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child:
                    Text(checkText, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note, style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(double.tryParse(controller.text.replaceAll(',', '.'))),
          child: const Text('Exportieren'),
        ),
      ],
    ),
  );
}
