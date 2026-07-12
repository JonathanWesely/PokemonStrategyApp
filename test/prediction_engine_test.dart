/// Prediction engine v1: usage lookup, reveal promotion, stat ranges.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/battle_state.dart';
import 'package:pokemon_strategy_app/src/prediction/prediction_engine.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();
  final engine = PredictionEngine(pack);

  group('usage-based predictions', () {
    test('Incineroar intel comes from usage data, sorted by pct', () {
      final intel = engine.intelFor(EnemyPokemon(speciesId: 'incineroar'));
      expect(intel.fromUsageData, isTrue);
      expect(intel.usagePercent, greaterThan(0));
      expect(intel.moves.first.id, 'fake-out');
      for (var i = 1; i < intel.moves.length; i++) {
        expect(intel.moves[i - 1].pct, greaterThanOrEqualTo(intel.moves[i].pct));
      }
      expect(intel.items, isNotEmpty);
      expect(intel.abilities.first.id, 'Intimidate');
      expect(intel.teammates, isNotEmpty);
    });

    test('stat ranges are exact-formula min/max/likely', () {
      final intel = engine.intelFor(EnemyPokemon(speciesId: 'incineroar'));
      final spe = intel.statRanges['spe']!;
      // Incineroar base 60 Spe: hindered 0 SP = 72, boosted 32 SP = 123,
      // top spread (Careful, 4 Spe SP) = 84.
      expect(spe.min, 72);
      expect(spe.max, 123);
      expect(spe.likely, 84);
    });
  });

  group('reveal promotion (the confirm ledger)', () {
    test('a revealed predicted move becomes confirmed and moves first', () {
      final enemy = EnemyPokemon(speciesId: 'incineroar')
        ..revealedMoves.add('knock-off');
      final intel = engine.intelFor(enemy);
      expect(intel.moves.first.id, 'knock-off');
      expect(intel.moves.first.confirmed, isTrue);
      expect(intel.moves.first.pct, 100);
    });

    test('an UNPREDICTED revealed move slots in automatically', () {
      // close-combat is in Incineroar's learnset but not its usage list.
      final enemy = EnemyPokemon(speciesId: 'incineroar')
        ..revealedMoves.add('close-combat');
      final intel = engine.intelFor(enemy);
      final first = intel.moves.first;
      expect(first.id, 'close-combat');
      expect(first.confirmed, isTrue);
      expect(first.label, 'Close Combat');
    });

    test('revealed item and ability are promoted', () {
      final enemy = EnemyPokemon(speciesId: 'incineroar')
        ..revealedItem = 'assault-vest'
        ..revealedAbility = 'Intimidate';
      final intel = engine.intelFor(enemy);
      expect(intel.items.first.id, 'assault-vest');
      expect(intel.items.first.confirmed, isTrue);
      expect(intel.abilities.first.confirmed, isTrue);
    });
  });

  group('Mega handling', () {
    test('a Mega enemy has its forme ability locked in', () {
      final enemy = EnemyPokemon(speciesId: 'gengar', mega: true);
      final intel = engine.intelFor(enemy);
      expect(intel.abilities.single.id, 'Shadow Tag');
      expect(intel.abilities.single.confirmed, isTrue);
    });

    test('Mega stat ranges use the Mega base stats', () {
      final normal = engine.intelFor(EnemyPokemon(speciesId: 'gengar'));
      final mega = engine.intelFor(EnemyPokemon(speciesId: 'gengar', mega: true));
      // Mega Gengar is faster (130 vs 110 base Spe).
      expect(mega.statRanges['spe']!.max,
          greaterThan(normal.statRanges['spe']!.max));
    });
  });
}
