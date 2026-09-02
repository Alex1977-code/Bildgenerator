import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/pose_prompt.dart';
import 'package:bildgenerator/services/tripo_service.dart';

void main() {
  group('T-Pose-Zusatz', () {
    test('Ohne Rigging bleibt der Prompt unangetastet', () {
      expect(withTPose('a knight', wanted: false), 'a knight');
      expect(tPoseExtraChars('a knight', wanted: false), 0);
    });

    test('Mit Rigging wird angehängt', () {
      final out = withTPose('a knight', wanted: true);
      expect(out, startsWith('a knight, '));
      expect(out, contains(tPoseSuffix));
      expect(tPoseExtraChars('a knight', wanted: true),
          tPoseSuffix.length + 2);
    });

    test('Steht die Pose schon im Prompt, wird nichts angehängt', () {
      // Genau der Fall aus dem gemeldeten 400er: Der Prompt brachte die
      // T-Pose selbst mit, die App hängte sie trotzdem an.
      for (final variant in [
        'a knight standing in T-pose, sword',
        'a knight in t pose',
        'a knight, T_Pose, sword',
        'ROBOT IN T-POSE',
      ]) {
        expect(withTPose(variant, wanted: true), variant.trim(),
            reason: variant);
        expect(tPoseExtraChars(variant, wanted: true), 0, reason: variant);
      }
    });

    test('Ein leerer Prompt bekommt keinen Zusatz', () {
      expect(withTPose('   ', wanted: true), '');
    });

    test('Rand-Leerzeichen fallen weg', () {
      expect(withTPose('  a knight  ', wanted: false), 'a knight');
    });
  });

  group('Zusammenspiel mit Tripos Längengrenze', () {
    test('Der gemeldete Fall: 958 + Zusatz reißt die 1024', () {
      // 958 Zeichen im Eingabefeld, kein T-Pose-Wort darin.
      final prompt = 'x' * 958;
      expect(prompt.length, 958);
      final effective = withTPose(prompt, wanted: true);
      expect(effective.length, 958 + tPoseSuffix.length + 2);
      expect(effective.length, greaterThan(TripoService.maxPromptChars));
      // Genau deshalb muss die Länge nach dem Zusammenbauen zählen.
    });

    test('806 Zeichen lassen dem Zusatz Luft', () {
      final prompt = 'y' * 806;
      final effective = withTPose(prompt, wanted: true);
      expect(effective.length,
          lessThanOrEqualTo(TripoService.maxPromptChars));
    });

    test('Der Zusatz kostet knapp 121 Zeichen', () {
      // Die Zahl steht in den Hinweistexten – sie muss stimmen.
      expect(tPoseSuffix.length + 2, 121);
    });

    test('Der A-Pose-Baustein nennt alle drei Angaben', () {
      // Aus der Uebergabe: A-Pose, 45 Grad nach unten, Arme
      // gestreckt. Fehlt das letzte, laesst der Text angewinkelte
      // Arme zu, und die sind fuer den Segmentierer so unbrauchbar
      // wie waagerechte.
      final text = aPoseSuffix.toLowerCase();
      expect(text, contains('a-pose'));
      expect(text, contains('45 degrees'));
      expect(text, contains('down'));
      expect(text, contains('straight'));
      // Und er bleibt kurz: Tripo misst den fertigen String.
      expect(aPoseSuffix.length, lessThanOrEqualTo(120));
    });
  });
}
