/// 18x18 type effectiveness with ability/item modifiers. Pure Dart.
library;

class TypeChart {
  final List<String> types;

  /// attacker -> defender -> multiplier (absent = 1.0).
  final Map<String, Map<String, double>> _attack;

  const TypeChart(this.types, this._attack);

  factory TypeChart.fromJson(Map<String, dynamic> json) {
    final attack = <String, Map<String, double>>{};
    (json['attack'] as Map<String, dynamic>).forEach((atk, row) {
      attack[atk] = (row as Map<String, dynamic>)
          .map((def, mult) => MapEntry(def, (mult as num).toDouble()));
    });
    return TypeChart((json['types'] as List).cast<String>(), attack);
  }

  /// Raw type-only multiplier of [attackType] into [defenderTypes].
  double typeEffectiveness(String attackType, List<String> defenderTypes) {
    var mult = 1.0;
    final row = _attack[attackType] ?? const {};
    for (final def in defenderTypes) {
      mult *= row[def] ?? 1.0;
    }
    return mult;
  }

  /// Effectiveness adjusted for the defender's ability and held item.
  /// Ability/item names are matched case-insensitively.
  double effectiveness(
    String attackType,
    List<String> defenderTypes, {
    String? ability,
    String? itemId,
  }) {
    var mult = typeEffectiveness(attackType, defenderTypes);
    final ab = ability?.toLowerCase() ?? '';

    // Full immunities granted by abilities.
    const immunities = {
      'levitate': 'Ground',
      'flash fire': 'Fire',
      'well-baked body': 'Fire',
      'water absorb': 'Water',
      'storm drain': 'Water',
      'dry skin': 'Water',
      'volt absorb': 'Electric',
      'lightning rod': 'Electric',
      'motor drive': 'Electric',
      'sap sipper': 'Grass',
      'earth eater': 'Ground',
    };
    if (immunities[ab] == attackType) return 0;

    // Halving / boosting abilities.
    if (ab == 'thick fat' && (attackType == 'Fire' || attackType == 'Ice')) {
      mult *= 0.5;
    }
    if ((ab == 'heatproof' || ab == 'water bubble') && attackType == 'Fire') {
      mult *= 0.5;
    }
    if (ab == 'purifying salt' && attackType == 'Ghost') mult *= 0.5;
    if (ab == 'dry skin' && attackType == 'Fire') mult *= 1.25;

    // Super-effective damage reducers.
    if ((ab == 'filter' || ab == 'solid rock' || ab == 'prism armor') &&
        mult > 1) {
      mult *= 0.75;
    }

    // Wonder Guard: only super-effective moves connect.
    if (ab == 'wonder guard' && mult <= 1) return 0;

    // Items.
    if (itemId == 'air-balloon' && attackType == 'Ground') return 0;

    return mult;
  }

  /// attackType -> multiplier for every attacking type into this defender.
  Map<String, double> defensiveProfile(
    List<String> defenderTypes, {
    String? ability,
    String? itemId,
  }) {
    return {
      for (final t in types)
        t: effectiveness(t, defenderTypes, ability: ability, itemId: itemId),
    };
  }
}
