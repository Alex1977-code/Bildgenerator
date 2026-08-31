/// Passt ein Bild-Modell in den Grafikspeicher?
///
/// Der Bild-Server nennt unter `/health`, wie viel VRAM die Karte hat
/// und wie viel jedes Modell braucht. Daraus entsteht hier ein Satz,
/// der **vor** dem ersten Lauf sagt, was passieren wird – statt dass
/// es sich erst nach zwei Minuten Wartezeit als „langsam" oder als
/// „CUDA out of memory" herausstellt.
///
/// **Warum ein Aufschlag.** Die Gewichte sind nicht alles: Beim
/// Rechnen kommen Aktivierungen, Latents und der VAE-Schritt dazu, bei
/// 1024×1024 grob anderthalb Gigabyte. Eine 10-GB-Karte und ein
/// 10-GB-Modell sind deshalb kein Treffer, sondern ein Engpass.
library;

/// Wie ein Modell auf diese Karte passt.
enum VramFit {
  /// Läuft vollständig auf der GPU – der schnelle Fall.
  ganz,

  /// Passt fast; einzelne Teile wandern zwischen GPU und Hauptspeicher.
  ausgelagert,

  /// Deutlich zu groß – läuft, aber spürbar langsam.
  knapp,

  /// Keine Angabe (kein CUDA, alte Server-Fassung).
  unbekannt,
}

/// Das Urteil samt Begründung.
class VramVerdict {
  const VramVerdict(this.fit, this.text);

  final VramFit fit;

  /// Ein Satz für die Oberfläche.
  final String text;

  bool get fast => fit == VramFit.ganz;
}

String _gb(double value) =>
    value.toStringAsFixed(1).replaceAll('.', ',');

/// Beurteilt ein Modell auf einer Karte.
///
/// [cardGb] ist der Grafikspeicher, [modelGb] der Bedarf der Gewichte,
/// [reserveGb] der Aufschlag fürs Rechnen (der Server meldet ihn mit).
VramVerdict vramVerdict({
  required double cardGb,
  required double modelGb,
  double reserveGb = 1.5,
}) {
  if (cardGb <= 0 || modelGb <= 0) {
    return const VramVerdict(
        VramFit.unbekannt, 'Kein Grafikspeicher gemeldet.');
  }
  if (cardGb >= modelGb + reserveGb) {
    return VramVerdict(
      VramFit.ganz,
      'Läuft vollständig auf der GPU: ${_gb(modelGb)} GB Modell plus '
          '${_gb(reserveGb)} GB fürs Rechnen passen in ${_gb(cardGb)} GB.',
    );
  }
  if (cardGb >= modelGb) {
    return VramVerdict(
      VramFit.ausgelagert,
      'Passt knapp nicht: ${_gb(modelGb)} GB Modell plus '
          '${_gb(reserveGb)} GB fürs Rechnen überschreiten '
          '${_gb(cardGb)} GB. Teile werden ausgelagert – langsamer, '
          'läuft aber.',
    );
  }
  return VramVerdict(
    VramFit.knapp,
    'Zu groß für diese Karte: ${_gb(modelGb)} GB gegen ${_gb(cardGb)} GB. '
        'Läuft mit Auslagerung, wird aber spürbar langsam.',
  );
}

/// Fasst zusammen, welche Modelle auf dieser Karte schnell laufen –
/// ein Satz für die Verbindungsmeldung.
///
/// [models] ist Modellname → Bedarf in GB. Leer, wenn nichts bekannt
/// ist; dann steht in der Meldung auch nichts.
///
/// [measured] sind auf dieser Karte **gemessene** Spitzenwerte, sobald
/// ein Modell einmal gelaufen ist. Die gewinnen gegen die Schätzung:
/// Eine Tabelle aus der Literatur kann um Gigabyte danebenliegen – bei
/// SD 3.5 war die Schätzung dieser App zunächst 10 GB, mit dem
/// T5-Encoder sind es aber rund 16. Ein gemessener Wert braucht auch
/// keinen Aufschlag mehr, er **ist** schon der Spitzenwert.
String vramSummary({
  required double cardGb,
  required Map<String, double> models,
  Map<String, double> measured = const {},
  double reserveGb = 1.5,
}) {
  if (cardGb <= 0 || models.isEmpty) return '';
  final ganz = <String>[];
  final rest = <String>[];
  final names = models.keys.toList()
    ..sort((a, b) => (measured[a] ?? models[a]!)
        .compareTo(measured[b] ?? models[b]!));
  for (final name in names) {
    final gemessen = measured[name];
    final verdict = gemessen != null
        ? vramVerdict(cardGb: cardGb, modelGb: gemessen, reserveGb: 0)
        : vramVerdict(
            cardGb: cardGb, modelGb: models[name]!, reserveGb: reserveGb);
    (verdict.fast ? ganz : rest).add(
        gemessen == null ? name : '$name (gemessen)');
  }
  final parts = <String>[];
  if (ganz.isNotEmpty) parts.add('ganz auf der GPU: ${ganz.join(', ')}');
  if (rest.isNotEmpty) {
    parts.add('ausgelagert (langsamer): ${rest.join(', ')}');
  }
  return '${_gb(cardGb)} GB VRAM – ${parts.join('; ')}';
}
