/// Erstellungsnachweis: dokumentiert nachvollziehbar, dass ein Bild
/// oder 3D-Modell selbst mit 3DGenerator erstellt wurde. Das PDF
/// enthält Datum/Uhrzeit, Ersteller, KI-Dienst/Modell, die Eingabe und
/// die SHA-256-Prüfsumme der Werkdatei – die Prüfsumme verknüpft
/// Nachweis und Datei eindeutig (jede Änderung an der Datei ergibt
/// eine andere Prüfsumme). Das Dokument lässt sich herunterladen und
/// ausdrucken (mit Unterschriftszeile).
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'settings_service.dart';

/// Metadaten des Werks für den Erstellungsnachweis.
class ProvenanceInfo {
  const ProvenanceInfo({
    required this.kind,
    required this.description,
    required this.providerLabel,
    this.model,
    this.details = const {},
    this.previewBytes,
  });

  /// 'Bild' oder '3D-Modell'.
  final String kind;

  /// Eingabe/Beschreibung (Prompt) bzw. Herkunft ('Aus Bild').
  final String description;

  /// Verwendeter Dienst (z. B. 'OpenAI (GPT Image)', 'Lokal').
  final String providerLabel;

  /// Verwendetes KI-Modell (optional).
  final String? model;

  /// Weitere Angaben (Einstellungen, Optionen).
  final Map<String, String> details;

  /// Optionales Vorschaubild (PNG/JPEG) fürs Dokument.
  final Uint8List? previewBytes;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime t) => '${_two(t.day)}.${_two(t.month)}.${t.year}, '
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)} Uhr';

bool _isPngOrJpeg(Uint8List b) =>
    (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) ||
    (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8);

/// Baut das Nachweis-PDF (A4, druckbar, mit Unterschriftszeile).
/// [createdAt] ist der Erstellungszeitpunkt des Werks (z. B. aus der
/// Galerie) – ohne Angabe gilt der aktuelle Zeitpunkt. Liegt die
/// Erstellung zurück, weist das PDF zusätzlich den Ausstellungs-
/// zeitpunkt des Nachweises aus.
Future<Uint8List> buildProvenancePdf({
  required ProvenanceInfo info,
  required String fileType,
  required Uint8List fileBytes,
  required String creatorName,
  DateTime? createdAt,
}) async {
  final hash = sha256.convert(fileBytes).toString();
  final now = DateTime.now();
  final created = createdAt ?? now;
  final utc = created.toUtc();
  final issuedLater = now.difference(created).inMinutes >= 1;

  // Gebündelte Roboto-Schriften (volle Umlaut-/Sonderzeichen-Abdeckung).
  final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final italic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'));
  final theme =
      pw.ThemeData.withFont(base: regular, bold: bold, italic: italic);

  pw.Widget row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Expanded(
                child:
                    pw.Text(value, style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
      );

  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(text,
            style:
                pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget bullet(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('•  ', style: const pw.TextStyle(fontSize: 10)),
            pw.Expanded(
                child:
                    pw.Text(text, style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
      );

  pw.Widget signatureField(String label) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 0.8))),
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ),
      );

  final previewBytes = info.previewBytes;
  final preview = previewBytes != null && _isPngOrJpeg(previewBytes)
      ? pw.MemoryImage(previewBytes)
      : null;

  final doc = pw.Document(
    theme: theme,
    title: 'Erstellungsnachweis',
    producer: '3DGenerator',
  );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(48),
    build: (context) => [
      pw.Text('Erstellungsnachweis',
          style:
              pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text('Dokumentation der Eigenerstellung – erstellt mit 3DGenerator',
          style: const pw.TextStyle(
              fontSize: 10, color: PdfColors.grey700)),
      pw.Divider(color: PdfColors.grey500),
      heading('Werk'),
      row('Art', info.kind),
      row('Dateityp', fileType),
      row('Dateigröße', '${fileBytes.length} Bytes'),
      row('SHA-256-Prüfsumme', hash),
      heading('Erstellung'),
      row('Datum/Uhrzeit', '${_stamp(created)} (Ortszeit)'),
      row('Datum/Uhrzeit (UTC)', _stamp(utc)),
      if (issuedLater)
        row('Nachweis ausgestellt', '${_stamp(now)} (Ortszeit)'),
      row('Software', '3DGenerator'),
      row('Dienst', info.providerLabel),
      if (info.model != null && info.model!.isNotEmpty)
        row('KI-Modell', info.model!),
      if (info.description.trim().isNotEmpty)
        row('Eingabe', info.description.trim()),
      for (final entry in info.details.entries)
        row(entry.key, entry.value),
      if (preview != null) ...[
        heading('Vorschau'),
        pw.Container(
          height: 150,
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(preview, fit: pw.BoxFit.contain),
        ),
      ],
      heading('Erklärung'),
      pw.Text(
        'Ich, $creatorName, versichere, das oben bezeichnete Werk zum '
        'genannten Zeitpunkt selbst mit der Anwendung 3DGenerator '
        'erstellt zu haben. Die Eingaben (Beschreibung bzw. '
        'Referenzbilder) stammen von mir.',
        style: const pw.TextStyle(fontSize: 10),
      ),
      pw.SizedBox(height: 40),
      pw.Row(children: [
        signatureField('Ort, Datum'),
        pw.SizedBox(width: 40),
        signatureField('Unterschrift'),
      ]),
      heading('Hinweise zur Beweiskraft'),
      bullet('Die SHA-256-Prüfsumme verknüpft diesen Nachweis eindeutig '
          'mit der Werkdatei. Datei und Nachweis gemeinsam und '
          'unverändert aufbewahren – jede Änderung an der Datei ergibt '
          'eine andere Prüfsumme.'),
      bullet('Zusätzliche Absicherung: PDF und Werkdatei direkt nach der '
          'Erstellung an die eigene E-Mail-Adresse senden (unabhängiger '
          'Zeitstempel des Anbieters) oder einen Zeitstempeldienst '
          'nutzen.'),
      bullet('Dieses Dokument ist eine Eigendokumentation zur '
          'Beweissicherung des Erstellungsvorgangs. Es ist keine '
          'amtliche oder notarielle Beglaubigung.'),
      bullet('Die Nutzungsrechte an KI-generierten Inhalten richten sich '
          'nach den Bedingungen des jeweiligen Dienstes; die in der App '
          'angebotenen Dienste räumen die kommerzielle Nutzung ein '
          '(Details im App-Bereich „Kosten & Qualität im Vergleich“).'),
    ],
  ));
  return doc.save();
}

/// Fragt den Ersteller-Namen ab (vorbelegt aus den Einstellungen, wird
/// gemerkt). Liefert null bei Abbruch.
Future<String?> askCreatorName(
    BuildContext context, SettingsService settings) async {
  final controller = TextEditingController(text: settings.creatorName);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Erstellungsnachweis (PDF)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Erzeugt ein druckbares PDF, das Zeitpunkt, Eingabe, '
            'KI-Dienst und die SHA-256-Prüfsumme der Datei dokumentiert '
            '– als Nachweis, dass das Werk selbst erstellt wurde.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Name des Erstellers / der Erstellerin',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text.trim()),
          child: const Text('PDF erstellen'),
        ),
      ],
    ),
  );
  if (name == null) return null;
  if (name.isNotEmpty) {
    settings.setCreatorName(name);
  }
  return name.isEmpty ? 'Name nicht angegeben' : name;
}
