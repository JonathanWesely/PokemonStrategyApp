/// Team legality linting per format rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/data/legality.dart';
import 'package:pokemon_strategy_app/src/models/pokemon_build.dart';
import 'package:pokemon_strategy_app/src/models/team.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();
  final ranked = pack.formats.firstWhere((f) => f.legalityChecked);
  final casual = pack.formats.firstWhere((f) => !f.itemClause);

  PokemonBuild legalIncineroar() => PokemonBuild(
        speciesId: 'incineroar',
        ability: 'Intimidate',
        nature: 'Careful',
        moveIds: ['fake-out', 'knock-off', 'parting-shot', 'flare-blitz'],
        itemId: 'safety-goggles',
        sp: {'hp': 32, 'atk': 6, 'def': 8, 'spd': 16, 'spe': 4},
      );

  test('a legal team produces no issues', () {
    final team = Team(name: 't', builds: [legalIncineroar()]);
    expect(lintTeam(team, ranked, pack), isEmpty);
  });

  test('species clause catches duplicates', () {
    final team =
        Team(name: 't', builds: [legalIncineroar(), legalIncineroar()]);
    final issues = lintTeam(team, ranked, pack);
    expect(issues.any((i) => i.message.contains('Duplicate species')), isTrue);
  });

  test('item clause: ranked only', () {
    final a = legalIncineroar();
    final b = PokemonBuild(
      speciesId: 'rillaboom',
      ability: 'Grassy Surge',
      itemId: 'safety-goggles',
      moveIds: ['fake-out', 'grassy-glide'],
    );
    final team = Team(name: 't', builds: [a, b]);
    expect(
        lintTeam(team, ranked, pack)
            .any((i) => i.message.contains('Duplicate held item')),
        isTrue);
    expect(
        lintTeam(team, casual, pack)
            .any((i) => i.message.contains('Duplicate held item')),
        isFalse);
  });

  test('illegal SP spreads are flagged', () {
    final build = legalIncineroar()..sp = {'hp': 32, 'atk': 32, 'spe': 32};
    final issues =
        lintTeam(Team(name: 't', builds: [build]), ranked, pack);
    expect(issues.any((i) => i.message.contains('SP spread')), isTrue);
  });

  test('wrong ability and off-learnset moves are flagged', () {
    final build = legalIncineroar()
      ..ability = 'Drizzle'
      ..moveIds = ['surging-strikes'];
    final issues =
        lintTeam(Team(name: 't', builds: [build]), ranked, pack);
    expect(issues.any((i) => i.message.contains('cannot have the ability')),
        isTrue);
    expect(issues.any((i) => i.message.contains('not in its learnset')),
        isTrue);
  });

  test('Mega forme requires its stone', () {
    final build = PokemonBuild(
      speciesId: 'gengar',
      ability: 'Cursed Body',
      megaFormeId: 'gengar-mega',
      itemId: 'leftovers',
      moveIds: ['shadow-ball'],
    );
    final issues =
        lintTeam(Team(name: 't', builds: [build]), ranked, pack);
    expect(issues.any((i) => i.message.contains('requires Gengarite')), isTrue);
  });
}
