/// Level-50 stat math for the Champions SP system. Pure Dart.
///
/// Working model (validated by test/stat_calculator_test.dart against known
/// level-50 numbers, and to be re-validated against the in-game stat screen —
/// plan §1): IVs are fixed at 31, and each SP adds exactly +1 to the stat at
/// level 50 (the equivalent of 8 EVs in the classic formula).
///
///   HP    = floor((2*base + 31) / 2) + 60 + SP
///   other = (floor((2*base + 31) / 2) + 5 + SP) * nature   (nature in exact
///           integer math: *110 ~/ 100 or *90 ~/ 100)
library;

import '../models/nature.dart';
import '../models/species.dart';

class StatCalculator {
  static const int level = 50;
  static const int fixedIv = 31;

  static int hpStat(int base, int spPoints, {int iv = fixedIv}) =>
      ((2 * base + iv) * level ~/ 100) + level + 10 + spPoints;

  static int otherStat(int base, int spPoints, int natureNumerator,
          {int iv = fixedIv}) =>
      (((2 * base + iv) * level ~/ 100) + 5 + spPoints) * natureNumerator ~/ 100;

  /// All six stats for a base-stat line + SP allocation + nature.
  static Map<String, int> computeStats(
    BaseStats base,
    Map<String, int> sp,
    String natureName,
  ) {
    final nature = natureByName(natureName);
    return {
      for (final key in statKeys)
        key: key == 'hp'
            ? hpStat(base.byKey(key), sp[key] ?? 0)
            : otherStat(
                base.byKey(key), sp[key] ?? 0, nature.multiplierNumerator(key)),
    };
  }

  /// Absolute floor for a stat: hindering nature, 0 SP.
  static int minStat(int base, String statKey) => statKey == 'hp'
      ? hpStat(base, 0)
      : otherStat(base, 0, 90);

  /// Absolute ceiling for a stat: boosting nature, max SP.
  static int maxStat(int base, String statKey) => statKey == 'hp'
      ? hpStat(base, 32)
      : otherStat(base, 32, 110);
}
