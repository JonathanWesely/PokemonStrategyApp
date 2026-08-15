/// BattleSession: the enemy-preview roster and reserve derivation that back
/// the Local-engine tracking tabs. Pure Dart, real bundled pack.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/battle_state.dart';
import 'package:pokemon_strategy_app/src/models/pokemon_build.dart';
import 'package:pokemon_strategy_app/src/models/team.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();
  final doubles = pack.formats.firstWhere((f) => f.isDoubles && f.pickSize == 4);

  PokemonBuild build(String id) => PokemonBuild(speciesId: id);

  BattleSession session() => BattleSession(
        format: doubles,
        team: Team(name: 'T', builds: [
          build('incineroar'),
          build('chien-pao'),
          build('gengar'),
          build('amoonguss'),
        ]),
        picks: [
          build('incineroar'),
          build('chien-pao'),
          build('gengar'),
          build('amoonguss'),
        ],
      );

  group('reserve derivation (doubles)', () {
    test('two lead, two of your reserves', () {
      final s = session();
      expect(s.activeYours.length, 2);
      expect(s.yourReserves.length, 2);
    });

    test('enemy reserve slots come from the format (4 picked − 2 on field)', () {
      final s = session();
      expect(s.enemyReserveCount, 2);
      expect(s.enemyUnknownReserveCount, 2); // nothing revealed yet
    });

    test('revealing a benched enemy lowers the unknown reserve count', () {
      final s = session();
      s.addEnemy('incineroar'); // on field
      s.addEnemy('gengar'); // on field — both slots full
      s.addEnemy('amoonguss'); // benches the oldest
      expect(s.enemiesOnField.length, 2);
      expect(s.enemyBench.length, 1);
      expect(s.enemyUnknownReserveCount, 1);
    });
  });

  group('enemy preview roster', () {
    test('holds the scouted species in order', () {
      final s = session();
      s.enemyPreview.addAll(['incineroar', 'gengar']);
      expect(s.enemyPreview, ['incineroar', 'gengar']);
      expect(s.enemyPreview.length, lessThanOrEqualTo(s.format.teamSize));
    });
  });
}
