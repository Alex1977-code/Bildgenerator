import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/batch_prompt.dart';
import 'package:bildgenerator/services/item_prompt.dart';
import 'package:bildgenerator/services/prompt_briefing.dart';
import 'package:bildgenerator/services/roblox_prompt.dart';
import 'package:bildgenerator/services/tripo_service.dart';
import 'package:bildgenerator/services/view_direction.dart';
import 'package:bildgenerator/services/view_generator.dart';

/// Die Durchsicht der **Bild**-Prompts: alles, was an ein Bildmodell
/// geht, gegen sein Ziel gehalten.
///
/// Ein Bild, aus dem ein 3D-Modell gerechnet wird, braucht andere
/// Wörter als ein hübsches Bild. Und jedes Wort hat genau einen
/// Empfänger: Was Tripo versteht, versteht SDXL nicht, und umgekehrt.
/// Hier steht je Befund ein Test, damit keiner der Fälle
/// zurückkommt.
int woerter(String text) => text
    .replaceAll(',', ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .length;

void main() {
  final modelle = <(GenProvider, String)>[
    for (final provider in GenProvider.values)
      for (final option in staticModelOptions(provider))
        (provider, option.$1),
  ];

  group('Gegenstands-Prompt: zwei Empfänger, zwei Fassungen', () {
    final schwert = itemKindById('schwert')!;

    test('Innerhalb der App bringt der Prompt keine Inszenierung mit',
        () {
      final (prompt, _) = itemPromptParts(
          kind: schwert, figurePrompt: 'a stout dwarf knight',
          target: ItemPromptTarget.views);
      // Kamera, Licht und Hintergrund kommen entweder von der
      // Ansichten-Pipeline oder gar nicht – Text→3D kennt sie nicht.
      for (final wort in ['centered', 'lighting', 'background']) {
        expect(prompt, isNot(contains(wort)), reason: wort);
      }
      // Die Formworte bleiben: Sie vererben sich über das Bild in die
      // Rekonstruktion und gelten auch für Text→3D.
      expect(prompt, contains('single solid object shown alone'));
      expect(prompt, contains('visible wall thickness'));
    });

    test('Der kopierte Block für den Bild-Tab bringt sie mit', () {
      // Dort steht nichts anderes im Prompt – die Inszenierung muss
      // aus diesem Text kommen.
      final block = itemPrompt(
          kind: schwert, figurePrompt: 'a stout dwarf knight');
      expect(block, contains(itemStagingTail));
      expect(itemTail, startsWith(itemShapeTail));
    });

    test('Der Ansichts-Prompt widerspricht sich nicht mehr', () {
      // Vorher: „plain flat background" aus dem Gegenstands-Schwanz
      // gegen den Magenta-Screen der Ansicht – und genau der Screen
      // ist es, den die App hinterher per Chroma-Key entfernt.
      final (prompt, _) = itemPromptParts(
          kind: schwert, figurePrompt: 'a stout dwarf knight',
          target: ItemPromptTarget.views);
      final kette = viewFrontKeywords(prompt, null,
          background: ViewBackground.magenta);
      expect(kette, contains('chroma key magenta'));
      expect(kette, isNot(contains('plain flat background')));
      // „centered" und die Lichtangabe stehen je einmal.
      expect('centered'.allMatches(kette).length, 1);
      expect('lighting'.allMatches(kette).length, 1);
    });

    test('Die Kette wird deutlich kürzer als mit Inszenierung', () {
      final mit = itemPromptParts(
              kind: schwert, figurePrompt: 'a stout dwarf knight')
          .$1;
      final ohne = itemPromptParts(
              kind: schwert,
              figurePrompt: 'a stout dwarf knight',
              target: ItemPromptTarget.views)
          .$1;
      expect(woerter(ohne), lessThan(woerter(mit)));
    });

    test('Die Netz-Angaben gehen nur an Text→3D', () {
      // Die Begründung steht im Code selbst: Einem Bildmodell sagen
      // „closed watertight shell" und „single mesh" nichts. Der
      // Gegenstands-Dialog tauscht sie beim Roblox-Schwanz deshalb
      // aus – im allgemeinen Schwanz standen sie trotzdem weiter.
      String schwanz(ItemPromptTarget t) => itemPromptParts(
          kind: schwert, figurePrompt: 'a knight', target: t).$1;
      expect(schwanz(ItemPromptTarget.text3d), contains(itemMeshTail));
      for (final t in [ItemPromptTarget.image, ItemPromptTarget.views]) {
        expect(schwanz(t), isNot(contains('watertight')), reason: t.name);
        expect(schwanz(t), isNot(contains('single mesh')), reason: t.name);
      }
    });

    test('Der Roblox-Schalter wirkt nur mit Schwanz und NEGATIV', () {
      // Ohne beides änderte `roblox: true` gar nichts – genau so lief
      // der Lauf innerhalb der App.
      final ohne = itemPromptParts(
          kind: schwert, figurePrompt: 'a knight', roblox: true);
      final mit = itemPromptParts(
          kind: schwert,
          figurePrompt: 'a knight',
          roblox: true,
          accessoryTail: robloxAccessoryImageTail,
          accessoryNegative: robloxAccessoryNegative);
      expect(ohne.$1,
          itemPromptParts(kind: schwert, figurePrompt: 'a knight').$1);
      expect(mit.$1, contains(robloxAccessoryImageTail));
      expect(mit.$2, contains('noisy surface'));
    });

    test('Der Verweis aufs Referenzbild nennt „character" nicht', () {
      // Eine Verneinung in einer Stichwortkette nennt genau das
      // Substantiv, das nicht ins Bild soll – „no text" wirkt wie
      // „text". Ausgeschlossen wird über die NEGATIV-Zeile.
      final (prompt, negativ) = itemPromptParts(
          kind: schwert,
          figurePrompt: 'a stout dwarf knight',
          withReference: true);
      expect(prompt.toLowerCase(), isNot(contains('character in the')));
      expect(prompt, contains('the image shows the object on its own'));
      expect(negativ, startsWith('character'));
    });
  });

  group('Hintergrund: was das Modell überhaupt malen kann', () {
    test('Nur OpenAI wird nach Transparenz gefragt', () {
      final alpha = viewFrontKeywords('a small stone tower', null,
          background: ViewBackground.alpha);
      expect(alpha, contains('transparent'));
      // Ein Diffusions-Modell hat keinen Alphakanal. Auf der eigenen
      // GPU schneidet der Server frei (rembg), bei den übrigen die
      // App per Chroma-Key – beides braucht eine gleichmäßige Fläche,
      // kein unerfüllbares „transparent".
      for (final bg in [ViewBackground.magenta, ViewBackground.plain]) {
        final kette = viewFrontKeywords('a small stone tower', null,
            background: bg);
        expect(kette, isNot(contains('transparent')), reason: bg.name);
      }
      expect(
          viewFrontKeywords('x', null, background: ViewBackground.plain),
          contains('even unlit backdrop'));
    });

    test('Jede Fassung bleibt im Budget des sparsamsten Modells', () {
      final knappstes =
          promptProfileFor(GenProvider.selfhost, 'sdxl-turbo').maxWords;
      for (final bg in ViewBackground.values) {
        final kette =
            viewFrontKeywords('a small stone tower', null, background: bg);
        expect(woerter(kette), lessThanOrEqualTo(knappstes),
            reason: '${bg.name}: ${woerter(kette)} Wörter');
      }
    });
  });

  group('Spielgrafik: die Vorlage nennt das Budget des Modells', () {
    test('Keine zweite Zahl neben der Höchstlänge des Modells', () {
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model,
            direction: viewDirectionById('iso35'));
        if (profile.style != PromptStyle.keywords) continue;
        final block =
            profile.briefing.split('Spielgrafik (Gebäude-Asset):').last;
        // Vorher stand hier fest „Zusammen unter 60 Wörter" – bei
        // SDXL Turbo (40) und SD 1.5 (50) widersprach das der Zeile
        // darüber.
        expect(block, isNot(contains('unter 60 Wörter')),
            reason: '$provider/$model');
      }
    });

    test('Passt die feste Kette nicht ins Budget, steht es dort', () {
      final kette = gameAssetWordCount(gameAssetKeywords);
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model,
            direction: viewDirectionById('iso35'));
        if (profile.style != PromptStyle.keywords) continue;
        final block =
            profile.briefing.split('Spielgrafik (Gebäude-Asset):').last;
        final passt = profile.maxWords - kette >= gameAssetLeadWords;
        expect(block.contains('ACHTUNG'), !passt,
            reason: '$provider/$model: Budget ${profile.maxWords}, '
                'Kette $kette');
      }
    });

    test('Ohne Negativ-Feld verlangt sie keine NEGATIV-Zeile', () {
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model,
            direction: viewDirectionById('iso35'));
        if (profile.negativeHandling != NegativeHandling.ignored) continue;
        final block =
            profile.briefing.split('Spielgrafik (Gebäude-Asset):').last;
        expect(block, isNot(contains('immer genau diese Zeile')),
            reason: '$provider/$model');
        // Und der Boden darf dann nirgends stehen: Es gibt keinen
        // Block, in den er ausweichen könnte.
        expect(block, contains('Der Boden darf nirgends stehen'),
            reason: '$provider/$model');
      }
    });

    test('Die Zahlen am Beispiel sind gerechnet, nicht behauptet', () {
      final motiv = gameAssetWordCount(gameAssetExampleMotif);
      final gesamt = gameAssetWordCount(
          '$gameAssetExampleMotif $gameAssetKeywords');
      final block = promptProfileFor(GenProvider.selfhost, 'sdxl',
              direction: viewDirectionById('iso35'))
          .briefing;
      expect(block, contains('($motiv Wörter Motiv'));
      expect(block, contains('zusammen $gesamt Wörter'));
      // Der Stand am Tag der Prüfung – schlägt an, sobald jemand am
      // Beispiel oder an der Kette dreht.
      expect(motiv, 19);
      expect(gesamt, 53);
      expect(gameAssetWordCount(gameAssetKeywords), 34);
    });
  });

  group('Roblox-Regeln an einer Bild-Vorlage', () {
    test('Tripos Zeichengrenze steht nur im Text→3D-Fall', () {
      final text = robloxPromptRules(accessory: false);
      final bild = robloxPromptRules(accessory: false, image: true);
      expect(text, contains('Der PROMPT darf höchstens'));
      expect(text, contains('Zeichen haben'));
      expect(text, contains('${TripoService.maxNegativePromptChars}'));
      expect(bild, isNot(contains('Zeichen haben')));
      expect(bild, contains('gilt hier nicht'));
    });

    test('Die Pose gehört in ein Bild, nicht in einen Text→3D-Prompt',
        () {
      // Der Widerspruch, den es zu beheben galt: Die Vorlage „Figur
      // für Bild→3D" verlangt T- oder A-Pose, der angehängte
      // Roblox-Block verbot sie.
      final text = robloxPromptRules(accessory: false);
      final bild = robloxPromptRules(accessory: false, image: true);
      expect(text, contains('KEINE T-Pose in den Prompt schreiben'));
      expect(bild, isNot(contains('KEINE T-Pose in den Prompt')));
      expect(bild, contains('Die T-Pose gehört in den Bild-Prompt'));
      // Und die zweite Stelle, an der derselbe Block die Pose
      // erwähnt, sagt dasselbe – sonst stünden zwei Aussagen in einem
      // Text.
      expect(text, contains('über den Posen-Schalter selbst an'));
      expect(bild, isNot(contains('über den Posen-Schalter selbst an')));
      expect(bild, contains('die muss im Bild zu sehen sein'));
    });

    test('Der feste Schwanz sagt, was davon im Bild nichts bewirkt',
        () {
      final bild = robloxPromptRules(accessory: false, image: true);
      expect(bild, contains('„closed watertight shell" und „single '
          'mesh" nichts'));
      expect(robloxPromptRules(accessory: false),
          isNot(contains('nichts – sie stehen dort für den')));
    });

    test('Beim Accessoire bleibt alles andere unverändert', () {
      // Ein zugeschalteter Bild-Modus darf nur die drei Angaben
      // ändern, nicht den Bauplan.
      for (final markt in [false, true]) {
        final text = robloxPromptRules(accessory: false, marketplace: markt);
        final bild = robloxPromptRules(
            accessory: false, marketplace: markt, image: true);
        expect(bild, contains('AUFBAU des PROMPT'), reason: '$markt');
        expect(bild, contains('Die Hülle muss geschlossen sein'),
            reason: '$markt');
        expect(text.length, greaterThan(0));
      }
    });
  });

  group('Längengrenzen', () {
    test('Tripo kürzt selbst, und zwar an einer Kommastelle', () {
      final lang = List.filled(200, 'stone block').join(', ');
      final kurz =
          TripoService.clipToLimit(lang, TripoService.maxPromptChars);
      expect(kurz.length, lessThanOrEqualTo(TripoService.maxPromptChars));
      expect(kurz, isNot(endsWith(',')));
      expect(TripoService.maxPromptChars, 1024);
      expect(TripoService.maxNegativePromptChars, 255);
    });

    test('Die Bild-Modelle bekommen eine Wortgrenze genannt', () {
      // Die Grenze der Bild-Modelle ist keine Zeichenzahl, sondern die
      // Gewichtung: Ein CLIP-Block fasst 75 Tokens. Die App drückt das
      // als Wortzahl aus – und nur bei den Modellen, wo sie greift.
      for (final (provider, model) in modelle) {
        final profile = promptProfileFor(provider, model);
        if (profile.style == PromptStyle.keywords) {
          expect(profile.maxWords, greaterThan(0),
              reason: '$provider/$model');
          expect(profile.briefing, contains('${profile.maxWords} Wörter'),
              reason: '$provider/$model');
        } else {
          expect(profile.maxWords, 0, reason: '$provider/$model');
        }
      }
    });

    test('Der Massenprompt meldet, was über der Wortgrenze liegt', () {
      final profile = promptProfileFor(GenProvider.selfhost, 'sdxl-turbo');
      final lang = List.filled(profile.maxWords + 10, 'tower').join(' ');
      final plan = parseBatchPrompt('NAME: a\nPROMPT: $lang',
          profile: profile);
      expect(
          plan.warnings.map((w) => w.message).join(' '),
          contains('${profile.maxWords} Wörter'));
    });
  });
}
