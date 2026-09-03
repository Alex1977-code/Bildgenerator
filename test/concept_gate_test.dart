import 'package:bildgenerator/services/concept_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Marktplatz-Ganzkörper braucht ein Gesicht', () {
    ConceptVerdict pruefe(String prompt) =>
        checkConcept(prompt, ConceptTarget.marketplaceFullBody);

    test('ein Kapuzenschatten ist der Ausschlussgrund', () {
      final v = pruefe('hooded creature with the face in shadow, '
          'glowing eyes, long cloak');
      expect(v.blocked, isTrue);
      final f = v.findings.first;
      expect(f.level, ConceptLevel.blocker);
      expect(f.title, contains('Gesicht im Schatten'));
      expect(f.detail, contains('Lider'));
      // Und der Ausweg steht dabei: das Verdeckende abtrennen.
      expect(f.detail, contains('Accessoire'));
      expect(f.detail, contains('Körperteile ohne Kopf'));
    });

    test('ein Hoodie allein ist keiner', () {
      // Die Falle: „hoodie" enthält „hood". Eine Kapuzenjacke mit
      // sichtbarem Gesicht ist völlig in Ordnung – ausgeschlossen ist
      // der leere Kopf, nicht das Kleidungsstück.
      final v = pruefe('a friendly character in a straight boxy hoodie, '
          'round face with big eyes and a small mouth');
      expect(v.blocked, isFalse);
      expect(v.hasWarning, isFalse);
      expect(v.findings.single.level, ConceptLevel.ok);
    });

    test('Helm, Maske und Visier ebenso', () {
      for (final wort in [
        'knight in a full plate helmet',
        'soldier with a gas mask',
        'pilot with a mirrored visor',
        'ein Ritter mit Helm',
        'gesichtslose Gestalt',
      ]) {
        expect(pruefe(wort).blocked, isTrue, reason: wort);
      }
    });

    test('ohne jedes Gesichtswort gibt es eine Warnung, keine Sperre',
        () {
      final v = pruefe('a stout robot with thick legs and mitten hands');
      expect(v.blocked, isFalse);
      expect(v.hasWarning, isTrue);
      expect(v.findings.single.detail, contains('FACS'));
    });

    test('Anbauten und nackte Haut sind Warnungen mit Ausweg', () {
      final drache = pruefe('friendly dragon character with big eyes, a '
          'wide mouth and a long tail');
      expect(drache.blocked, isFalse);
      expect(drache.hasWarning, isTrue);
      final anbau = drache.findings.firstWhere((f) => f.hit == 'tail');
      expect(anbau.title, contains('Schwanz'));
      expect(anbau.detail, contains('Accessoire'));

      final nackt = pruefe('naked troll with round eyes and a grin');
      expect(nackt.hasWarning, isTrue);
      expect(nackt.findings.any((f) => f.title == 'Nackte Haut'), isTrue);
    });

    test('der Befund nennt die Stelle im Text', () {
      final v = pruefe('a creature, empty hood, no eyes');
      expect(v.findings.first.hit, 'empty hood');
    });
  });

  group('Die anderen Ziele fragen nicht nach dem Gesicht', () {
    test('Körperteile, Accessoire und eigenes Erlebnis gehen durch', () {
      for (final ziel in [
        ConceptTarget.marketplaceBodyParts,
        ConceptTarget.accessory,
        ConceptTarget.ownExperience,
      ]) {
        // Selbst mit Helm: Für diese Ziele prüft Roblox kein
        // Gesichtsrig.
        final v = checkConcept('knight with a closed helmet', ziel);
        expect(v.blocked, isFalse, reason: ziel.label);
        expect(v.findings.single.level, ConceptLevel.ok);
        expect(v.findings.single.detail, contains(ziel.label));
      }
    });
  });

  test('der Bericht lässt sich lesen', () {
    final v = checkConcept('faceless figure', ConceptTarget.marketplaceFullBody);
    expect(v.text, contains('Konzept-Prüfung'));
    expect(v.text, contains('Marktplatz-Ganzkörper'));
  });
}
