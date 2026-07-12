/// Ground-truth validation of the level-50 SP stat model against numbers
/// every VGC player knows by heart. If Champions' in-game screen ever
/// disagrees with these (plan Phase 0 validation), fix StatCalculator and
/// these expectations together.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/data/stat_calculator.dart';
import 'package:pokemon_strategy_app/src/models/species.dart';

void main() {
  group('StatCalculator ground truth (level 50, IV 31)', () {
    test('max Speed Jolly Garchomp hits the famous 169', () {
      // base 102 Spe, 32 SP (=252 EVs), +Spe nature
      expect(StatCalculator.otherStat(102, 32, 110), 169);
    });

    test('max Speed Jolly Chien-Pao hits 205', () {
      expect(StatCalculator.otherStat(135, 32, 110), 205);
    });

    test('max Speed Jolly Landorus-Therian hits 157', () {
      expect(StatCalculator.otherStat(91, 32, 110), 157);
    });

    test('max HP Incineroar hits 202', () {
      expect(StatCalculator.hpStat(95, 32), 202);
    });

    test('0 SP Incineroar HP is 170', () {
      expect(StatCalculator.hpStat(95, 0), 170);
    });

    test('max HP Amoonguss hits 221', () {
      expect(StatCalculator.hpStat(114, 32), 221);
    });

    test('neutral 0 SP Incineroar Attack is 135, Adamant is 148', () {
      expect(StatCalculator.otherStat(115, 0, 100), 135);
      expect(StatCalculator.otherStat(115, 0, 110), 148);
    });

    test('hindered 0 SP Incineroar SpA is 90', () {
      expect(StatCalculator.otherStat(80, 0, 90), 90);
    });

    test('min Speed Torkoal is 36', () {
      expect(StatCalculator.minStat(20, 'spe'), 36);
    });

    test('each SP adds exactly +1 before nature', () {
      for (var sp = 0; sp <= 32; sp++) {
        expect(StatCalculator.otherStat(100, sp, 100),
            StatCalculator.otherStat(100, 0, 100) + sp);
        expect(StatCalculator.hpStat(100, sp),
            StatCalculator.hpStat(100, 0) + sp);
      }
    });

    test('nature multiplier uses exact integer math (no float drift)', () {
      // 154 * 1.1 must be 169, never 168 via floating point error.
      expect(StatCalculator.otherStat(102, 32, 110), 169);
      // raw 100 * 0.9 must be exactly 90.
      expect(StatCalculator.otherStat(80, 0, 90), 90);
    });

    test('computeStats produces a full six-stat map', () {
      const base = BaseStats(hp: 100, atk: 125, def: 90, spa: 60, spd: 70, spe: 85);
      final stats = StatCalculator.computeStats(
          base, {'hp': 32, 'atk': 32, 'spe': 2}, 'Adamant');
      expect(stats.keys.toSet(), statKeys.toSet());
      expect(stats['hp'], 207); // Rillaboom 32 HP SP
      expect(stats['atk'], 194); // 32 SP Adamant
      expect(stats['spa'], 72); // Adamant hinders SpA: 80 * 90 ~/ 100
      expect(stats['spe'], 107);
    });

    test('minStat <= neutral <= maxStat for every base value', () {
      for (final base in [20, 60, 100, 135, 200]) {
        for (final key in statKeys) {
          final min = StatCalculator.minStat(base, key);
          final max = StatCalculator.maxStat(base, key);
          final neutral = key == 'hp'
              ? StatCalculator.hpStat(base, 0)
              : StatCalculator.otherStat(base, 0, 100);
          expect(min, lessThanOrEqualTo(neutral));
          expect(neutral, lessThanOrEqualTo(max));
        }
      }
    });
  });
}
