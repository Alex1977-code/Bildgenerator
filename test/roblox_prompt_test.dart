import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/concept_gate.dart';
import 'package:bildgenerator/services/pose_prompt.dart';
import 'package:bildgenerator/services/roblox_export.dart';
import 'package:bildgenerator/services/roblox_prompt.dart';
import 'package:bildgenerator/services/tripo_service.dart';

void main() {
  final figur = robloxPromptRules(accessory: false);
  final accessoire = robloxPromptRules(accessory: true);

  group('Die Vorlage gibt den Bauplan mit', () {
    test('Der feste Schwanz steht wörtlich drin', () {
      // Ohne ihn muss die Prompt-KI raten – genau daran sind die
      // ersten Läufe gescheitert.
      expect(figur, contains(robloxFigureTail));
      expect(accessoire, contains(robloxAccessoryTail));
    });

    test('Die vier tragenden Angaben stehen im Schwanz', () {
      for (final term in [
        'single connected body',
        'visible wall thickness',
        'closed watertight shell',
        'single mesh',
      ]) {
        expect(robloxFigureTail, contains(term), reason: term);
      }
      for (final term in [
        'single solid object',
        'visible wall thickness',
        'closed watertight shell',
        'single mesh',
      ]) {
        expect(robloxAccessoryTail, contains(term), reason: term);
      }
    });

    test('Die NEGATIV-Zeile steht wörtlich drin und passt in die '
        'Grenze', () {
      expect(figur, contains(robloxFigureNegative));
      expect(accessoire, contains(robloxAccessoryNegative));
      expect(robloxFigureNegative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
      expect(robloxAccessoryNegative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
    });

    test('Ein vollständiges Beispiel ist dabei', () {
      expect(figur, contains(robloxFigureExample));
      expect(accessoire, contains(robloxAccessoryExample));
      // Das Beispiel selbst hält die Längengrenze ein – mit dem
      // T-Pose-Zusatz, den die App anhängt.
      final prompt = robloxFigureExample
          .split('\n')
          .firstWhere((l) => l.startsWith('PROMPT: '))
          .substring('PROMPT: '.length);
      expect(prompt.length + tPoseSuffix.length + 2,
          lessThanOrEqualTo(TripoService.maxPromptChars));
    });

    test('Die Reihenfolge des Motivs wird vorgegeben', () {
      expect(figur, contains('AUFBAU des PROMPT'));
      expect(figur, contains('Proportionen'));
      expect(figur, contains('erkennende Merkmal'));
      expect(accessoire, contains('Grundform'));
    });
  });

  group('Die Vorlage nennt die Fallen', () {
    test('Keine T-Pose im Text, aber der Zusatz wird beziffert', () {
      expect(figur, contains('KEINE T-Pose'));
      expect(figur, contains('${tPoseSuffix.length + 2} Zeichen'));
      // Beim Accessoire gibt es keine Pose.
      expect(accessoire, contains('KEINE Pose'));
      expect(accessoire, isNot(contains('T-Pose')));
    });

    test('Verneinungen und dünne Kleinteile stehen als Falle drin', () {
      for (final text in [figur, accessoire]) {
        expect(text, contains('KEINE Verneinungen'));
        expect(text, contains('dünnen Kleinteile'));
        expect(text, contains('Moderation'));
      }
    });

    test('Verdeckende Kleidung nur bei der Figur', () {
      expect(figur, contains('Umhänge'));
      expect(figur, contains('kein Skelett andocken'));
      expect(accessoire, isNot(contains('Umhänge')));
    });
  });

  group('Die Vorlage nennt die Grenzen', () {
    test('Dreiecke, Textur und Zeichen', () {
      expect(figur, contains('10.000 Dreiecke'));
      expect(accessoire, contains('4.000 Dreiecke'));
      for (final text in [figur, accessoire]) {
        expect(text, contains('1024er-Textur'));
        expect(text, contains('1.024 Zeichen'));
        expect(text, contains('255'));
      }
    });

    test('Die Studs stehen nur bei der Figur', () {
      expect(figur, contains('5 Studs'));
      expect(accessoire, isNot(contains('Studs')));
    });
  });

  group('Marktplatz-Körper', () {
    final markt = robloxPromptRules(accessory: false, marketplace: true);

    test('nennt jede der fünf Formregeln', () {
      for (final baustein in [
        'body depth less than two fifths',
        'hip bone',
        'separate leg tubes',
        'mitten hands',
        'narrow visible neck',
      ]) {
        expect(robloxMarketplaceTail, contains(baustein), reason: baustein);
      }
    });

    test('„chunky" fliegt raus – genau das Wort hat die Tiefe bestellt',
        () {
      expect(robloxMarketplaceTail, isNot(contains('chunky')));
      // In der Vorlage für die Figur im eigenen Erlebnis bleibt es:
      // Dort gilt die Tiefengrenze nicht.
      expect(robloxFigureTail, contains('chunky'));
    });

    test('ganz vorn im Negativ steht, was das Gesicht verdeckt', () {
      // Der einzige Fehler, den weder Prompt noch Reparatur
      // nachträglich beheben – deshalb vor den Formfehlern.
      final teile = robloxMarketplaceNegative.split(', ');
      expect(teile.take(4),
          containsAll(<String>['hood', 'helmet', 'mask', 'visor']));
      // Und gleich danach die beiden, an denen die Figur abgelehnt
      // wurde.
      expect(teile.take(8), containsAll(<String>['deep body', 'long hem']));
    });

    test('der Schwanz bestellt Lider und Lippen im Kopf, keine '
        'eigenen Volumen', () {
      // Lauf 5: Augen und Zähne als eigene Netze reichen nicht. Der
      // Schwanz hatte genau das bestellt.
      expect(robloxMarketplaceTail, contains('eyelids'));
      expect(robloxMarketplaceTail, contains('lips'));
      expect(robloxMarketplaceTail, contains('face fully visible'));
      expect(robloxMarketplaceTail, isNot(contains('separate volumes')));
      expect(markt, contains('Lidern'));
      expect(markt, contains('Lippen'));
      expect(markt, isNot(contains('eigene Volumen sein')));
      // Und der Ausweg steht dabei.
      expect(markt, contains('Accessoire'));
    });

    test('das Beispiel ist keine Kapuzenfigur mehr', () {
      // Vorher stand hier das Konzept, das fünfmal gescheitert ist –
      // und das Gate hielt es nicht auf, weil „eyes" dastand.
      final promptZeile = robloxMarketplaceExample
          .split('\n')
          .first
          .replaceFirst('PROMPT: ', '')
          .toLowerCase();
      for (final wort in ['hood', 'helmet', 'mask', 'visor', 'shadow']) {
        expect(promptZeile, isNot(contains(wort)), reason: wort);
      }
      expect(promptZeile, contains('eyelids'));
      expect(promptZeile, contains('lips'));
      final urteil =
          checkConcept(promptZeile, ConceptTarget.marketplaceFullBody);
      expect(urteil.blocked, isFalse);
      expect(urteil.hasWarning, isFalse);
      // Die Pose steht im Schwanz, die App hängt keine zweite an.
      expect(promptHasPose(promptZeile), isTrue);
    });

    test('der Regeltext nennt das Motiv-Budget', () {
      // „höchstens 1.024" allein ließ die Prompt-KI ein langes Motiv
      // schreiben; Tripo kürzte hinten – und hinten stehen die Regeln.
      final budget =
          TripoService.maxPromptChars - robloxMarketplaceTail.length - 2;
      expect(markt, contains('rund $budget Zeichen'));
      expect(markt, contains('kürzt Tripo hinten'));
      // Für die Figur geht der Posen-Zusatz zusätzlich ab.
      final figurBudget = TripoService.maxPromptChars -
          robloxFigureTail.length -
          2 -
          (tPoseSuffix.length + 2);
      expect(robloxPromptRules(accessory: false),
          contains('rund $figurBudget Zeichen'));
    });

    test('das Figur-Negativ verträgt sich mit der A-Pose', () {
      // „arms down" gegen „angled 45 degrees down" – das gab es.
      expect(robloxFigureNegative, isNot(contains('arms down')));
      expect(robloxFigureNegative, contains('arms along the body'));
    });

    test('die Längen passen zu Tripos Grenzen', () {
      expect(robloxMarketplaceNegative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
      final promptZeile = robloxMarketplaceExample
          .split('\n')
          .first
          .replaceFirst('PROMPT: ', '');
      expect(promptZeile.length,
          lessThanOrEqualTo(TripoService.maxPromptChars));
    });

    test('verlangt die A-Pose und begründet sie', () {
      expect(robloxMarketplaceTail, contains('A-pose'));
      expect(markt, contains('KEINE T-Pose'));
      expect(markt, contains('Auto Setup'));
    });

    test('nennt die gemessenen Grenzen mit ihrer Herkunft', () {
      expect(markt, contains('gemessen'));
      expect(markt, contains('2,00'));
      expect(markt, contains('1,50'));
      expect(markt, contains('6,22'));
    });

    test('nennt das Gruppenbudget und face_limit 7.000', () {
      expect(markt, contains('1.248'));
      expect(markt, contains('7.000'));
    });

    test('ein Accessoire bleibt ein Accessoire', () {
      // marketplace wirkt nur zusammen mit accessory: false.
      expect(robloxPromptRules(accessory: true, marketplace: true),
          robloxPromptRules(accessory: true));
    });
  });

  group('Auto-Setup-Skript', () {
    final lua = autoSetupLua(modelName: 'kapuzzee');

    test('nennt das Modell und die drei Aufrufe', () {
      expect(lua, contains('kapuzzee'));
      expect(lua, contains('AutoSetupAvatarAsync'));
      expect(lua, contains('LoadGeneratedAvatarAsync'));
      expect(lua, contains('ValidateUGCFullBodyAsync'));
    });

    test('umgeht die drei Fallen aus dem echten Lauf', () {
      // Braucht einen echten Player, yieldet minutenlang, und das
      // Ergebnis darf nicht unverankert in die Welt.
      expect(lua, contains('GetPlayers()'));
      expect(lua, contains('task.spawn'));
      expect(lua, contains('Anchored = true'));
    });

    test('erzeugt gültiges Luau ohne kaputte Zeichenkette', () {
      // Der Lua-Generator ist an genau dieser Stelle schon einmal
      // gescheitert: ein Backslash zu viel, und das Skript
      // kompiliert nicht.
      expect(lua, isNot(contains(r'\"')));
      final anfuehrung = '"'.allMatches(lua).length;
      expect(anfuehrung.isEven, isTrue,
          reason: 'ungerade Zahl Anführungszeichen');
    });
  });

  group('Roblox-Paket', () {
    test('die Anleitung nennt beide Wege und den dynamischen Kopf', () {
      final text = robloxReadme(
        glbFile: 'figur.glb',
        fbxFile: 'figur.fbx',
        scriptFile: 'figur.py',
        luaFile: 'figur.lua',
        autoSetupFile: 'figur_auto_setup.lua',
        missingBones: const [],
      );
      expect(text, contains('STARTFIGUR'));
      expect(text, contains('MARKTPLATZ'));
      expect(text, contains('FACS'));
      expect(text, contains('figur_auto_setup.lua'));
      // Ohne das Skript darf die Anleitung es auch nicht erwähnen.
      final ohne = robloxReadme(
        glbFile: 'figur.glb',
        fbxFile: 'figur.fbx',
        scriptFile: 'figur.py',
        luaFile: 'figur.lua',
        missingBones: const [],
      );
      expect(ohne, isNot(contains('auto_setup')));
    });

    test('liegt die FBX dabei, entfällt der Umweg über Blender', () {
      // Die App schreibt FBX inzwischen selbst. Dann gehört das
      // Ergebnis ins Paket und nicht die Anleitung dorthin – das
      // Skript bleibt als Rückfallweg.
      final mit = robloxReadme(
        glbFile: 'figur.glb',
        fbxFile: 'figur.fbx',
        scriptFile: 'figur.py',
        luaFile: 'figur.lua',
        missingBones: const [],
        fbxIncluded: true,
        textureFile: 'figur.png',
      );
      expect(mit, contains('liegt schon dabei'));
      expect(mit, contains('Rueckfallweg'));
      expect(mit, contains('figur.png'));
      // Die Datei steht auch in der Liste oben.
      final liste = mit.split('Zwei Wege').first;
      expect(liste, contains('figur.fbx'));
      expect(liste, contains('figur.png'));

      // Ohne FBX bleibt es beim alten Weg, und nichts verspricht eine
      // Datei, die nicht im Paket liegt.
      final ohneFbx = robloxReadme(
        glbFile: 'figur.glb',
        fbxFile: 'figur.fbx',
        scriptFile: 'figur.py',
        luaFile: 'figur.lua',
        missingBones: const [],
      );
      expect(ohneFbx, isNot(contains('liegt schon dabei')));
      expect(ohneFbx, contains('blender --background'));
      expect(ohneFbx.split('Zwei Wege').first, isNot(contains('figur.fbx')));
    });
  });
}
