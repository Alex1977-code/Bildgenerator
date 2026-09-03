import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/services/concept_gate.dart';
import 'package:bildgenerator/services/pose_prompt.dart';
import 'package:bildgenerator/services/roblox_export.dart';
import 'package:bildgenerator/services/roblox_marketplace.dart' show RobloxBodyScale;
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

    test('nennt jede der Formregeln – nach der Doku-Prüfung', () {
      for (final baustein in [
        'body depth less than two fifths of body height',
        'head about one quarter of body height',
        'tight opaque shorts',
        'hips at mid body height',
        'clear gap between the thighs',
        'eyes sunk into sockets with eyelids',
        'mitten hands',
        'narrow visible neck',
        'sturdy arms and legs filling their outlines',
      ]) {
        expect(robloxMarketplaceTail, contains(baustein), reason: baustein);
      }
      // Was raus musste: nackte Haut, dünne Beine – und „less than
      // half", das bei 5 Studs 2,5 bestellt, mehr als jede Skala erlaubt.
      for (final falsch in ['less than half', 'thighs uncovered', 'slim',
          'hip bone', 'narrower than one third']) {
        expect(robloxMarketplaceTail, isNot(contains(falsch)), reason: falsch);
      }
    });

    test('das Tiefenwort bestellt nie mehr, als die Skala erlaubt', () {
      // Der Fehler der Zwischenfassung: 0,45 wurde „less than half",
      // und das sind 2,5 bei 5 Studs – über Normals 2,25.
      for (final scale in RobloxBodyScale.values) {
        for (var zehntel = 36; zehntel <= 95; zehntel++) {
          final studs = zehntel / 10;
          final wort = robloxDepthWords(scale.maxDepth, studs);
          final bestellt = robloxDepthFraction(wort) * studs;
          expect(bestellt, lessThanOrEqualTo(scale.maxDepth + 1e-6),
              reason: '${scale.label} bei $studs: $wort');
        }
      }
      // Bei 5 Studs heißt es für alle drei Skalen „two fifths" – 2,0:
      // unter Normals 2,25, gerade an Classics und Slenders 2,0.
      for (final scale in RobloxBodyScale.values) {
        expect(robloxDepthWords(scale.maxDepth, 5),
            'less than two fifths of body height',
            reason: scale.label);
      }
    });

    test('die Tiefe wird aus Höhe und Skala gerechnet, nicht angenommen',
        () {
      // Die Grenze ist absolut: 2,00 bei Classic, 2,25 bei Normal. Und
      // 0,45 ist nicht „less than half" (das wären 2,5), sondern das
      // nächste Wort darunter.
      expect(robloxDepthWords(2.25, 5), 'less than two fifths of body height');
      expect(robloxDepthWords(2.0, 5), 'less than two fifths of body height');
      expect(robloxDepthWords(2.0, 6), 'less than one third of body height');
      expect(robloxDepthWords(2.0, 8), 'less than a quarter of body height');
      final classic6 = robloxMarketplaceTailFor(
          studs: 6, scale: RobloxBodyScale.classic);
      expect(classic6, contains('less than one third of body height'));
      expect(classic6, isNot(contains('less than half')));
      // Standard ist wörtlich die Konstante.
      expect(robloxMarketplaceTailFor(), robloxMarketplaceTail);
      // Und der Regeltext nennt Skala und Rig Scale.
      final text = robloxPromptRules(
          accessory: false,
          marketplace: true,
          studs: 6,
          scale: RobloxBodyScale.classic);
      expect(text, contains('Classic'));
      expect(text, contains('Rig Scale: R15'));
      expect(text, contains('2,00'));
    });

    test('das Negativ nennt Anbauten und keine „thick legs" mehr', () {
      final teile = robloxMarketplaceNegative.split(', ');
      expect(teile, containsAll(<String>['tail', 'wings', 'horns',
          'spindly limbs']));
      expect(teile, isNot(contains('thick legs')));
      // Nach der ersten Figur mit dem Schwanz: Stummelbeine und
      // Kugelaugen sind die zwei Fehler, die keine Reparatur behebt.
      expect(teile, containsAll(<String>['short legs', 'bulging eyes']));
      expect(robloxMarketplaceNegative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
    });

    test('der Regeltext nennt Modesty, Anbauten, Deckung und FACS', () {
      for (final wort in ['Modesty', 'Anbauten', 'humanoid', '50 %',
          '17. August 2026', '17 FACS', 'Augenbrauen', 'Outer Cage',
          'Sicherheitsaufschlag', 'Character body specifications']) {
        expect(markt, contains(wort), reason: wort);
      }
      expect(markt, isNot(contains('nicht dokumentiert')));
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
      // Dann die Anbauten, dann die beiden, an denen die Figur
      // abgelehnt wurde.
      expect(teile.take(12), containsAll(<String>['deep body', 'long hem']));
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

    test('das Beispielmotiv passt ins Motiv-Budget', () {
      // Das alte Beispiel hatte 329 Zeichen bei einem Budget von 285:
      // Mit dem Schwanz waren es 1.068, und Tripo hätte hinten „few
      // flat separated color areas, uniform material" abgeschnitten –
      // beim Beispiel, das die Vorlage selbst vormacht.
      final motiv = robloxMarketplaceExample
          .split('\n')
          .first
          .replaceFirst('PROMPT: ', '')
          .replaceFirst(', $robloxMarketplaceTail', '');
      expect(motiv, isNot(contains(robloxMarketplaceTailMarker)));
      final budget = marketplacePrompt(motiv).motifBudget;
      expect(motiv.length, lessThanOrEqualTo(budget),
          reason: 'Motiv ${motiv.length}, Budget $budget');
      expect(marketplacePrompt(motiv).motifTooLong, isFalse);
      // Und es bestellt die zwei Dinge, die die erste Figur nicht
      // hatte: Beine von einem Drittel und Augen im Kopf.
      expect(motiv, contains('hips at mid body height'));
      expect(motiv, contains('sunk into the head'));
      expect(motiv, isNot(contains('small stocky')));
    });

    test('verlangt die A-Pose und begründet sie', () {
      expect(robloxMarketplaceTail, contains('A-pose'));
      expect(markt, contains('KEINE T-Pose'));
      expect(markt, contains('Auto Setup'));
    });

    test('nennt die Grenzen mit ihrer Herkunft – Doku und Reserve', () {
      expect(markt, contains('2,25'));
      expect(markt, contains('1,50'));
      expect(markt, contains('6,22'));
      expect(markt, contains('Rig Scale: Rthro'));
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

  group('Der Marktplatz-Prompt, wie er wirklich geht', () {
    test('das Motiv bekommt den festen Schwanz und das feste Negativ',
        () {
      final m = marketplacePrompt('small stocky creature, big round eyes');
      expect(m.tailAppended, isTrue);
      expect(m.prompt, startsWith('small stocky creature, big round eyes, '));
      expect(m.prompt, endsWith(robloxMarketplaceTail));
      expect(m.negative, robloxMarketplaceNegative);
      // Die A-Pose steht im Schwanz – die App hängt keine zweite an.
      expect(promptHasPose(m.prompt), isTrue);
      expect(m.prompt.length, lessThanOrEqualTo(TripoService.maxPromptChars));
      expect(m.notes, isEmpty);
    });

    test('steht der Schwanz schon drin, bleibt es bei einem', () {
      final zurueck = robloxMarketplaceExample
          .split('\n')
          .first
          .replaceFirst('PROMPT: ', '');
      final m = marketplacePrompt(zurueck);
      expect(m.tailAppended, isFalse);
      expect(m.prompt, zurueck);
      expect(robloxMarketplaceTailMarker.allMatches(m.prompt).length, 1);
      expect(m.notes.join(' '), contains('nicht ein zweites Mal'));
    });

    test('eigene Negativ-Begriffe stehen vorn, ohne Doppelte, in der '
        'Grenze', () {
      final m = marketplacePrompt('x', negative: 'cape, purple, hood');
      expect(m.negative, startsWith('cape, purple, hood, '));
      expect('cape, '.allMatches('${m.negative}, ').length, 1);
      expect('hood, '.allMatches('${m.negative}, ').length, 1);
      expect(m.negative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
      // Zu viel Eigenes: hinten gekürzt, und der Bericht sagt es.
      final lang = marketplacePrompt('x',
          negative: List.generate(30, (i) => 'term$i').join(', '));
      expect(lang.negative.length,
          lessThanOrEqualTo(TripoService.maxNegativePromptChars));
      expect(lang.negative, startsWith('term0, term1'));
      expect(lang.notes.join(' '), contains('gekürzt'));
    });

    test('ein zu langes Motiv wird angesagt, nicht stillschweigend '
        'gekürzt', () {
      final m = marketplacePrompt('y' * 400);
      expect(m.motifTooLong, isTrue);
      expect(m.motifBudget,
          TripoService.maxPromptChars - robloxMarketplaceTail.length - 2);
      expect(m.notes.join(' '), contains('Tripo kürzt hinten'));
      // Der Prompt selbst bleibt ungekürzt – kürzen tut die
      // Anfrage, und das Feld zeigt es vorher an.
      expect(m.prompt.length, greaterThan(TripoService.maxPromptChars));
    });

    test('ein leeres Motiv bekommt keinen Schwanz', () {
      final m = marketplacePrompt('   ');
      expect(m.prompt, '');
      expect(m.tailAppended, isFalse);
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
