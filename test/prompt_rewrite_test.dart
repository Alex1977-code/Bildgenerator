import 'package:flutter_test/flutter_test.dart';

import 'package:bildgenerator/models/models.dart';
import 'package:bildgenerator/services/batch_prompt.dart';
import 'package:bildgenerator/services/prompt_briefing.dart';
import 'package:bildgenerator/services/prompt_rewrite.dart';

/// Genau der Prompt, der auf SDXL Base ein Gebäude in Frontalansicht
/// auf einem Erdboden ergeben hat – 351 Wörter, für ein
/// sprachverstehendes Modell geschrieben.
const _realPrompt =
    'A medieval armory: a smith\'s workshop with an open forge and '
    'anvil under a wide timber-framed front, a rack of swords and '
    'spears against the wall, and a tall stone chimney with a warm '
    'glow inside. Exactly one single building in the image, nothing '
    'else beside it. There is no ground anywhere in the image - the '
    'building is a free-standing cut-out on an empty background with '
    'nothing at all under it: no floor, no terrace, no paving, no '
    'cobblestones, no low wall, no fence, no steps, no platform, and '
    'no bare floor under an open front or a lean-to either. Camera '
    'elevation 35 degrees above the horizon, clearly looking down '
    'onto the roof, not at the facade. Coarse masonry: at most about '
    '15 courses of rounded boulders over the height of a wall, each '
    'stone large and softly rounded - no fine stone mosaic, the image '
    'is downscaled about 13 times in the game. In the game this '
    'building is drawn only about 77 pixels tall, so keep every shape '
    'bold and readable at that size. Every edge is softly rounded and '
    'chamfered, the roof planes slightly convex, the ridge a soft '
    'round rather than a crease, the eaves thick and rounded, timber '
    'beams with rounded arrises. Warm, slightly desaturated palette: '
    'warm sandstone and plaster walls, timber in warm brown, roofs in '
    'warm grey slate with warm beige highlights, or warm brown '
    'shingle, or straw thatch. All materials matte, no gloss, no '
    'metallic sheen. One warm low sun from the upper left at 35 '
    'degrees elevation, golden hour light, very soft shadows, strong '
    'ambient occlusion in every recess, no hard highlights. Plain '
    'neutral warm-grey background, the same flat grey behind the '
    'building and below it, the building centred and cropped tight to '
    'its own outline. Sharp focus throughout, no depth of field, no '
    'text and no watermark in the image.';

int words(String text) => text
    .replaceAll(',', ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .length;

void main() {
  final sdxl = promptProfileFor(GenProvider.selfhost, 'sdxl');

  group('Briefing zu Stichwortkette', () {
    late PromptRewrite result;

    setUp(() {
      result = rewriteForKeywordModel(
        _realPrompt,
        negativePrompt: 'ground plate, base, cast shadow',
        profile: sdxl,
        gameAssets: true,
      );
    });

    test('Aus 351 Wörtern wird ein Prompt im Budget', () {
      expect(words(_realPrompt), greaterThan(300));
      expect(words(result.prompt), lessThanOrEqualTo(sdxl.maxWords));
      expect(result.changed, isTrue);
    });

    test('Das Motiv steht vorn', () {
      expect(result.prompt, startsWith('medieval armory'));
      expect(result.prompt, contains('forge'));
    });

    test('Die Kamera-Kette steht drin, die Gradzahl nicht', () {
      expect(result.prompt, contains('isometric view from high above'));
      expect(result.prompt, contains('looking down onto the roof'));
      expect(result.prompt, isNot(contains('35 degrees')));
      expect(result.prompt, isNot(contains('elevation')));
    });

    test('Keine Verneinung mehr im Prompt', () {
      // „no floor", „nothing at all", „not at the facade" – jedes
      // davon liest SDXL als Wunsch.
      expect(result.prompt, isNot(matches(RegExp(r'\bno\b'))));
      expect(result.prompt, isNot(matches(RegExp(r'\bnothing\b'))));
      expect(result.prompt, isNot(matches(RegExp(r'\bnever\b'))));
    });

    test('Die ausgeschlossenen Begriffe stehen im Negativ-Prompt', () {
      for (final term in ['floor', 'terrace', 'paving', 'cobblestones']) {
        expect(result.negativePrompt, contains(term), reason: term);
      }
      // Der alte Negativ-Prompt bleibt erhalten …
      expect(result.negativePrompt, contains('ground plate'));
      // … und die empfohlene Liste kommt dazu.
      expect(result.negativePrompt, contains('grass patch'));
    });

    test('Erklärungen zum Spiel sind raus', () {
      expect(result.prompt, isNot(contains('downscaled')));
      expect(result.prompt, isNot(contains('pixels')));
      expect(result.prompt, isNot(contains('in the game')));
    });

    test('Die Umschreibung sagt, was sie getan hat', () {
      expect(result.notes, isNotEmpty);
      expect(result.notes.join(' '), contains('Verneinungen'));
    });
  });

  test('Ein schon passender Prompt bleibt im Budget', () {
    final good = rewriteForKeywordModel(
      'medieval bakery, large domed bread oven attached to the side '
      'wall, timber framed plaster walls, thatched roof, stone '
      'chimney',
      negativePrompt: gameAssetNegativeTerms,
      profile: sdxl,
      gameAssets: true,
    );
    expect(words(good.prompt), lessThanOrEqualTo(sdxl.maxWords));
    expect(good.prompt, startsWith('medieval bakery'));
    expect(good.prompt, contains(gameAssetKeywords));
  });

  test('Ohne Spielgrafik-Regeln kommt kein Gebäude-Schwanz dazu', () {
    final plain = rewriteForKeywordModel(
      'A red sports car on a road. There is no rain.',
      negativePrompt: '',
      profile: sdxl,
      gameAssets: false,
    );
    expect(plain.prompt, isNot(contains('building')));
    expect(plain.negativePrompt, contains('rain'));
  });

  test('Der ganze Massenprompt wird umgeschrieben, Namen bleiben', () {
    final plan = parseBatchPrompt(
      'NAME: bld-01-armory\nPROMPT: $_realPrompt\n'
      'NEGATIV: ground plate, base\n\n'
      'NAME: bld-02-bakery\nPROMPT: A bakery. There is no fence.\n',
      profile: sdxl,
      gameAssets: true,
    );
    expect(plan.items.length, 2);
    final out = rewriteBatchText(plan, profile: sdxl, gameAssets: true);
    expect(out.changedItems, 2);
    expect(out.text, contains('NAME: bld-01-armory'));
    expect(out.text, contains('NAME: bld-02-bakery'));
    expect(out.text, contains('PROMPT: medieval armory'));

    // Und das Wichtigste: Der umgeschriebene Text besteht die
    // Prüfung, die den ursprünglichen bemängelt hat.
    final before = parseBatchPrompt(
      'NAME: bld-01-armory\nPROMPT: $_realPrompt\n'
      'NEGATIV: ground plate, base\n',
      profile: sdxl,
      gameAssets: true,
    );
    expect(before.warnings, isNotEmpty);
    final after =
        parseBatchPrompt(out.text, profile: sdxl, gameAssets: true);
    expect(after.isValid, isTrue);
    expect(
        after.warnings.map((w) => w.message).join(' '),
        isNot(contains('länger als')));
    expect(after.warnings.map((w) => w.message).join(' '),
        isNot(contains('Verneinungen')));
    expect(after.warnings.map((w) => w.message).join(' '),
        isNot(contains('Gradzahl')));
  });
}
