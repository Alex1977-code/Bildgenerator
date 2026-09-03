/// Das Konzept-Gate: Passt das Motiv überhaupt zum Ziel?
///
/// **Warum es das gibt.** Fünf Läufe, drei Kapuzenfiguren, und keine
/// davon konnte als Ganzkörper-Avatar bestehen – das Konzept „Gesicht
/// im Schatten" scheitert nicht am Prompt und nicht am Export, sondern
/// an Roblox' Auto Setup: Für den dynamischen Kopf braucht es
/// **Augenhöhlen mit Lidern und eine Mundhöhle mit Lippen im
/// Kopfnetz**. Tripo liefert eine geschlossene Hülle ohne beides.
/// Lauf 5 hat das entschieden: Augen und Zähne als eigene Netze
/// reichen nicht, egal wo sie sitzen – „Cannot detect mouth open /
/// left eye close expression".
///
/// Das kostet Credits, bevor irgendetwas messbar ist. Also fragt die
/// App vorher.
///
/// **Was das Gate nicht ist.** Es liest Wörter, keine Bilder. Es kann
/// nicht wissen, ob eine Figur ein Gesicht hat – es sieht nur, ob der
/// Text eines beschreibt oder eines ausschließt. Deshalb ist der
/// härteste Befund eine Rückfrage, keine Sperre: Wer weiß, was er tut,
/// klickt weiter.
///
/// **Die Falle, die dabei zuerst zuschlägt.** „hoodie" enthält „hood",
/// und eine Kapuzenjacke ist völlig in Ordnung, solange das Gesicht
/// darunter zu sehen ist. Ausgeschlossen ist nicht das Kleidungsstück,
/// sondern der **leere** Kopf: „empty hood", „face in shadow",
/// „faceless", Helm, Maske, Visier.
library;

/// Wofür die Figur gedacht ist.
enum ConceptTarget {
  /// Ganzkörper-Avatar für den Marktplatz – braucht ein Gesicht.
  marketplaceFullBody,

  /// Einzelne Körperteile (Torso, Arme, Beine) für den Marktplatz.
  ///
  /// Roblox verkauft Körper auch in Teilen, und Torso, Arme und Beine
  /// der Kapuzenfigur haben `ValidateUGCBodyPartAsync` ohne eine
  /// einzige Meldung bestanden. Nur der Kopf fehlt.
  marketplaceBodyParts,

  /// Accessoire – ein Netz, kein Gesicht nötig.
  accessory,

  /// Figur fürs eigene Erlebnis – keine Marktplatz-Regeln.
  ownExperience,
}

extension ConceptTargetLabel on ConceptTarget {
  String get label => switch (this) {
        ConceptTarget.marketplaceFullBody => 'Marktplatz-Ganzkörper',
        ConceptTarget.marketplaceBodyParts => 'Marktplatz-Körperteile',
        ConceptTarget.accessory => 'Accessoire',
        ConceptTarget.ownExperience => 'Figur fürs eigene Erlebnis',
      };
}

enum ConceptLevel {
  /// Das Konzept kann das Ziel nicht erreichen.
  blocker,

  /// Es fehlt etwas, das es braucht – vielleicht steht es nur nicht im
  /// Text.
  warnung,

  /// Nichts dagegen.
  ok,
}

class ConceptFinding {
  const ConceptFinding(this.level, this.title, this.detail, {this.hit = ''});

  final ConceptLevel level;
  final String title;
  final String detail;

  /// Die Stelle im Text, an der es hängt – damit man sie findet.
  final String hit;
}

class ConceptVerdict {
  const ConceptVerdict(this.target, this.findings);

  final ConceptTarget target;
  final List<ConceptFinding> findings;

  bool get blocked =>
      findings.any((f) => f.level == ConceptLevel.blocker);
  bool get hasWarning =>
      findings.any((f) => f.level == ConceptLevel.warnung);

  /// Die Alternativen, die bleiben – nur beim Ganzkörper-Ziel nötig.
  ///
  /// Die erste ist die interessanteste: Was das Gesicht verdeckt, ist
  /// fast immer **abtrennbar**. Eine Kapuze ist ein starres
  /// Hut-Accessoire – ein Netz, höchstens 4.000 Dreiecke, kein Cage,
  /// kein Rig, kein Gesicht. Darunter steht dann eine Figur mit
  /// sichtbarem Gesicht, und die besteht Auto Setup. Aus einer
  /// unmöglichen Aufgabe werden so zwei lösbare.
  static const String alternatives =
      'Möglich bleibt: (1) Das Verdeckende abtrennen – die Kapuze (oder '
      'Helm, Maske) als eigenes Accessoire erzeugen und darunter eine '
      'Figur mit sichtbarem Gesicht; beides besteht für sich. '
      '(2) Die Figur als Marktplatz-Körperteile ohne Kopf – Torso, Arme '
      'und Beine haben die Prüfung schon einmal ohne eine einzige '
      'Meldung bestanden. (3) Als Figur fürs eigene Erlebnis, dort '
      'gelten die Marktplatz-Regeln nicht.';

  String get text => [
        'Konzept-Prüfung: ${target.label}',
        for (final f in findings) '  ${f.title}: ${f.detail}',
      ].join('\n');
}

/// Wörter, die einen Kopf **ohne** animierbares Gesicht beschreiben.
///
/// Bewusst als ganze Wendungen, nicht als einzelne Wörter: „hood"
/// allein steckt in „hoodie", und eine Kapuzenjacke mit sichtbarem
/// Gesicht ist erlaubt. Was hier steht, schließt das Gesicht aus.
const List<(String, String)> conceptBlockers = [
  ('faceless', 'kein Gesicht'),
  ('no face', 'kein Gesicht'),
  ('without a face', 'kein Gesicht'),
  ('without face', 'kein Gesicht'),
  ('featureless', 'kein Gesicht'),
  ('blank face', 'kein Gesicht'),
  ('empty hood', 'leere Kapuze'),
  ('hollow hood', 'leere Kapuze'),
  ('dark void', 'leerer Kopf'),
  ('shadowed face', 'Gesicht im Schatten'),
  ('face in shadow', 'Gesicht im Schatten'),
  ('face hidden', 'Gesicht verdeckt'),
  ('hidden face', 'Gesicht verdeckt'),
  ('obscured face', 'Gesicht verdeckt'),
  ('hood shadow', 'Kapuzenschatten'),
  ('shadow inside the hood', 'Kapuzenschatten'),
  ('helmet', 'Helm'),
  ('full-face mask', 'Maske'),
  ('face mask', 'Maske'),
  ('gas mask', 'Maske'),
  ('balaclava', 'Maske'),
  ('visor', 'Visier'),
  ('skull head', 'Schädel ohne Lider und Lippen'),
  ('gesichtslos', 'kein Gesicht'),
  ('kein gesicht', 'kein Gesicht'),
  ('ohne gesicht', 'kein Gesicht'),
  ('leere kapuze', 'leere Kapuze'),
  ('kapuzenschatten', 'Kapuzenschatten'),
  ('gesicht im schatten', 'Gesicht im Schatten'),
  ('helm', 'Helm'),
  ('maske', 'Maske'),
  ('visier', 'Visier'),
];

/// Wörter, an denen ein beschriebenes Gesicht erkennbar ist.
const List<String> conceptFaceWords = [
  'face',
  'eyes',
  'eye ',
  'eyelids',
  'eyelid',
  'mouth',
  'lips',
  'teeth',
  'smile',
  'grin',
  'expression',
  'gesicht',
  'augen',
  'lider',
  'mund',
  'lippen',
  'zähne',
];

/// Wörter für Anbauten, die nicht ins Körpernetz dürfen.
///
/// Erlaubt sind genau ein Kopf, ein Rumpf, zwei Arme, zwei Beine.
/// Schwanz, Flügel, Hörner und Haarsträhnen werden eigene Accessoires
/// – als Warnung, nicht als Sperre: Das Motiv darf sie nennen, die
/// Figur muss ohne sie erzeugt werden.
const List<(String, String)> conceptAppendageWords = [
  ('tail', 'Schwanz'),
  ('wings', 'Flügel'),
  ('horns', 'Hörner'),
  ('antlers', 'Geweih'),
  ('pointed ears', 'abstehende Ohren'),
  ('hair strands', 'Haarsträhnen'),
  ('schwanz', 'Schwanz'),
  ('flügel', 'Flügel'),
  ('hörner', 'Hörner'),
  ('geweih', 'Geweih'),
];

/// Wörter, die nackte Haut bestellen, wo der Marktplatz Bedeckung
/// verlangt (Hüfte bis unter Schritt und Gesäß).
const List<String> conceptBareSkinWords = [
  'naked',
  'nude',
  'bare skin',
  'bare legs',
  'nackt',
  'nackte haut',
];

/// Prüft ein Motiv gegen das Ziel – bevor Credits fließen.
///
/// [prompt] ist das Motiv, so wie es der Nutzer eingegeben hat, ohne
/// die Textbausteine der Vorlage: Die Vorlage nennt „two hemisphere
/// eyes and a mouth" selbst, und dann fände das Gate immer ein Gesicht.
ConceptVerdict checkConcept(String prompt, ConceptTarget target) {
  final findings = <ConceptFinding>[];
  final text = prompt.toLowerCase();

  if (target != ConceptTarget.marketplaceFullBody) {
    findings.add(ConceptFinding(
        ConceptLevel.ok,
        'Kein Gesicht nötig',
        'Für „${target.label}" prüft Roblox kein Gesichtsrig. Die '
            'Proportionsregeln gelten weiter, wo sie gelten.'));
    return ConceptVerdict(target, findings);
  }

  for (final (wort, grund) in conceptBlockers) {
    if (!text.contains(wort)) continue;
    findings.add(ConceptFinding(
        ConceptLevel.blocker,
        'Als Ganzkörper nicht möglich: $grund',
        'Im Motiv steht „$wort". Roblox\' Auto Setup braucht für den '
            'dynamischen Kopf Augenhöhlen mit Lidern und eine Mundhöhle '
            'mit Lippen **im Kopfnetz**. Fünf Läufe haben das gezeigt: '
            'Augen und Zähne als eigene Netze reichen nicht, egal wo '
            'sie sitzen. Kein Prompt und keine Reparatur ändern das. '
            '${ConceptVerdict.alternatives}',
        hit: wort));
    break;
  }

  if (findings.isEmpty &&
      !conceptFaceWords.any((w) => text.contains(w))) {
    findings.add(ConceptFinding(
        ConceptLevel.warnung,
        'Kein Gesicht beschrieben',
        'Das Motiv nennt weder Gesicht noch Augen oder Mund. Für einen '
            'Ganzkörper-Avatar muss das Kopfnetz Lider und Lippen '
            'haben – sonst findet Auto Setup keine FACS-Posen. Ins '
            'Motiv gehört ein sichtbares Gesicht, mit Augen und Mund '
            'als Teil des Kopfes.'));
  }

  if (findings.isEmpty) {
    for (final (wort, grund) in conceptAppendageWords) {
      if (!text.contains(wort)) continue;
      findings.add(ConceptFinding(
          ConceptLevel.warnung,
          'Anbau am Körper: $grund',
          'Im Motiv steht „$wort". Der Marktplatz erlaubt am Körper '
              'genau einen Kopf, einen Rumpf, zwei Arme, zwei Beine – '
              '„tails, wings, extra limbs … must be uploaded '
              'separately". Die Figur ohne $grund erzeugen und den '
              'Anbau als eigenes Accessoire dazugeben.',
          hit: wort));
      break;
    }
    for (final wort in conceptBareSkinWords) {
      if (!text.contains(wort)) continue;
      findings.add(ConceptFinding(
          ConceptLevel.warnung,
          'Nackte Haut',
          'Im Motiv steht „$wort". Der Marktplatz verlangt von der '
              'Hüfte bis unter Schritt und Gesäß volle, undurchsichtige '
              'Bedeckung in einer anderen Farbe als die Haut. Der feste '
              'Schwanz bestellt eng anliegende Shorts; das Motiv sollte '
              'dem nicht widersprechen.',
          hit: wort));
      break;
    }
  }

  if (findings.isEmpty) {
    findings.add(const ConceptFinding(
        ConceptLevel.ok,
        'Gesicht beschrieben',
        'Das Motiv nennt ein Gesicht. Ob das Kopfnetz am Ende Lider '
            'und Lippen hat, zeigt erst der Lauf – aber der Weg ist '
            'offen.'));
  }
  return ConceptVerdict(target, findings);
}
