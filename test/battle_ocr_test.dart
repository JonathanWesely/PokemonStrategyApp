/// BattleTextMatcher: OCR lines from the battle screen -> recognized
/// Pokemon with sides and HP. The lines below transcribe the real fixture
/// photos (test/fixtures/battle1.jpeg): enemy banners top-right, your
/// Pokemon bottom-left, UI noise everywhere.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/recognition_result.dart';
import 'package:pokemon_strategy_app/src/recognition/battle_ocr.dart';
import 'package:pokemon_strategy_app/src/recognition/recognition_service.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();
  final matcher = BattleTextMatcher(pack);
  const context = BattleSnapshotContext(
    yourSpeciesIds: ['froslass', 'avalugg', 'grimmsnarl', 'sinistcha'],
    enemyFieldSlots: 2,
  );

  test('reads the battle1 fixture layout: two enemies up top, yours below',
      () {
    final lines = [
      // UI noise
      const OcrLine('Snow', cx: 0.22, cy: 0.05),
      const OcrLine('4/5', cx: 0.45, cy: 0.05),
      const OcrLine('MOVE TIME', cx: 0.78, cy: 0.28),
      const OcrLine('45', cx: 0.90, cy: 0.28),
      const OcrLine('Battle Info', cx: 0.82, cy: 0.34),
      const OcrLine('FIGHT', cx: 0.88, cy: 0.62),
      const OcrLine('POKEMON', cx: 0.88, cy: 0.78),
      // enemy banners (top right)
      const OcrLine('Umbreon', cx: 0.62, cy: 0.06),
      const OcrLine('100%', cx: 0.66, cy: 0.09),
      const OcrLine('Sneasler', cx: 0.83, cy: 0.06),
      const OcrLine('44%', cx: 0.86, cy: 0.09),
      // your banners (bottom left)
      const OcrLine('Froslass', cx: 0.18, cy: 0.85),
      const OcrLine('177/177', cx: 0.20, cy: 0.88),
      const OcrLine('Grimmsnarl', cx: 0.36, cy: 0.85),
      const OcrLine('175/202', cx: 0.38, cy: 0.88),
    ];
    final result = matcher.match(lines, context);

    final enemies = result.where((r) => r.side == BattleSide.enemy).toList();
    final yours = result.where((r) => r.side == BattleSide.yours).toList();
    expect(enemies.map((e) => e.speciesId).toSet(), {'umbreon', 'sneasler'});
    expect(yours.map((e) => e.speciesId).toSet(), {'froslass', 'grimmsnarl'});

    final sneasler = enemies.singleWhere((e) => e.speciesId == 'sneasler');
    expect(sneasler.hpPercent, 44);
    final umbreon = enemies.singleWhere((e) => e.speciesId == 'umbreon');
    expect(umbreon.hpPercent, 100);
    final grimmsnarl = yours.singleWhere((e) => e.speciesId == 'grimmsnarl');
    expect(grimmsnarl.hpPercent, (175 * 100 / 202).round());
  });

  test('tolerates OCR mangling via fuzzy matching', () {
    final lines = [
      const OcrLine('Umbre0n', cx: 0.6, cy: 0.06), // zero for o
      const OcrLine('Sneas1er', cx: 0.8, cy: 0.06), // one for l
    ];
    final result = matcher.match(lines, context);
    expect(result.map((e) => e.speciesId).toSet(), {'umbreon', 'sneasler'});
  });

  test('regional formes resolve from the base name the game displays', () {
    final lines = [
      const OcrLine('Decidueye', cx: 0.6, cy: 0.06), // pack id decidueye-hisui
      const OcrLine('Ninetales', cx: 0.8, cy: 0.06), // pack id ninetales-alola
    ];
    final result = matcher.match(lines, context);
    expect(result.map((e) => e.speciesId).toSet(),
        {'decidueye-hisui', 'ninetales-alola'});
  });

  test('ignores UI words and unknown names', () {
    final lines = [
      const OcrLine('FIGHT', cx: 0.9, cy: 0.6),
      const OcrLine('Totally Fake Mon', cx: 0.5, cy: 0.3),
      const OcrLine('Show Summary', cx: 0.8, cy: 0.9),
    ];
    expect(matcher.match(lines, context), isEmpty);
  });

  test('a roster name in the bottom half that is not yours is not forced '
      'to the enemy side', () {
    // e.g. OCR catching your nicknamed Pokemon's real species elsewhere.
    final lines = [
      const OcrLine('Gengar', cx: 0.3, cy: 0.9), // bottom half, not in picks
    ];
    expect(matcher.match(lines, context), isEmpty);
  });
}
