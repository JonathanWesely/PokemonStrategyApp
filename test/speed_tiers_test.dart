/// Speed strip: ordering, exact-vs-range entries, scarf flag.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/battle_state.dart';
import 'package:pokemon_strategy_app/src/models/pokemon_build.dart';
import 'package:pokemon_strategy_app/src/prediction/speed_tiers.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();

  PokemonBuild jollyMaxSpeChienPao() => PokemonBuild(
        speciesId: 'chien-pao',
        ability: 'Sword of Ruin',
        nature: 'Jolly',
        sp: {'spe': 32, 'atk': 32, 'def': 2},
      );

  test('your Pokemon get exact speeds, enemies get ranges', () {
    final tiers = buildSpeedTiers(
      pack,
      [jollyMaxSpeChienPao()],
      [EnemyPokemon(speciesId: 'incineroar')],
    );
    expect(tiers.length, 2);

    final yours = tiers.firstWhere((t) => t.yours);
    expect(yours.isExact, isTrue);
    expect(yours.likely, 205); // Jolly max-Spe Chien-Pao

    final enemy = tiers.firstWhere((t) => !t.yours);
    expect(enemy.isExact, isFalse);
    expect(enemy.min, 72);
    expect(enemy.max, 123);
  });

  test('entries sort fastest-likely first', () {
    final tiers = buildSpeedTiers(
      pack,
      [jollyMaxSpeChienPao()],
      [
        EnemyPokemon(speciesId: 'incineroar'),
        EnemyPokemon(speciesId: 'gengar'),
      ],
    );
    for (var i = 1; i < tiers.length; i++) {
      expect(tiers[i - 1].likely, greaterThanOrEqualTo(tiers[i].likely));
    }
    expect(tiers.first.likely, 205);
  });

  test('choice scarf: applied exactly to yours, flagged for enemies', () {
    final scarfed = jollyMaxSpeChienPao()..itemId = 'choice-scarf';
    final enemy = EnemyPokemon(speciesId: 'incineroar')
      ..revealedItem = 'choice-scarf';
    final tiers = buildSpeedTiers(pack, [scarfed], [enemy]);

    expect(tiers.firstWhere((t) => t.yours).likely, 307); // 205 * 1.5
    expect(tiers.firstWhere((t) => !t.yours).scarfLikely, isTrue);
  });

  test('nickname is used as the label when set', () {
    final build = jollyMaxSpeChienPao()..nickname = 'Snowball';
    final tiers = buildSpeedTiers(pack, [build], []);
    expect(tiers.single.label, 'Snowball');
  });
}
