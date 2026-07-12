/// The 25 natures. Fixed game data, so hardcoded rather than packed.
library;

class Nature {
  final String name;

  /// Stat key boosted 10% (null for neutral natures).
  final String? plus;

  /// Stat key reduced 10% (null for neutral natures).
  final String? minus;

  const Nature(this.name, [this.plus, this.minus]);

  bool get isNeutral => plus == null;

  /// 110, 100, or 90 — the multiplier numerator over 100. Integer math so
  /// stat formulas stay exact (see StatCalculator).
  int multiplierNumerator(String statKey) {
    if (plus == statKey) return 110;
    if (minus == statKey) return 90;
    return 100;
  }

  String get summary =>
      isNeutral ? 'neutral' : '+${plus!.toUpperCase()} / -${minus!.toUpperCase()}';
}

const List<Nature> natures = [
  Nature('Adamant', 'atk', 'spa'),
  Nature('Lonely', 'atk', 'def'),
  Nature('Brave', 'atk', 'spe'),
  Nature('Naughty', 'atk', 'spd'),
  Nature('Bold', 'def', 'atk'),
  Nature('Impish', 'def', 'spa'),
  Nature('Relaxed', 'def', 'spe'),
  Nature('Lax', 'def', 'spd'),
  Nature('Modest', 'spa', 'atk'),
  Nature('Mild', 'spa', 'def'),
  Nature('Quiet', 'spa', 'spe'),
  Nature('Rash', 'spa', 'spd'),
  Nature('Calm', 'spd', 'atk'),
  Nature('Gentle', 'spd', 'def'),
  Nature('Sassy', 'spd', 'spe'),
  Nature('Careful', 'spd', 'spa'),
  Nature('Timid', 'spe', 'atk'),
  Nature('Hasty', 'spe', 'def'),
  Nature('Jolly', 'spe', 'spa'),
  Nature('Naive', 'spe', 'spd'),
  Nature('Hardy'),
  Nature('Docile'),
  Nature('Serious'),
  Nature('Bashful'),
  Nature('Quirky'),
];

Nature natureByName(String name) => natures.firstWhere(
      (n) => n.name.toLowerCase() == name.toLowerCase(),
      orElse: () => const Nature('Serious'),
    );
