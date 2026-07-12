/// Species data from the pokedex pack. Pure Dart — no Flutter imports.
library;

/// The six stat keys, in canonical order.
const statKeys = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];

const statLabels = {
  'hp': 'HP',
  'atk': 'Atk',
  'def': 'Def',
  'spa': 'SpA',
  'spd': 'SpD',
  'spe': 'Spe',
};

class BaseStats {
  final int hp, atk, def, spa, spd, spe;

  const BaseStats({
    required this.hp,
    required this.atk,
    required this.def,
    required this.spa,
    required this.spd,
    required this.spe,
  });

  factory BaseStats.fromJson(Map<String, dynamic> json) => BaseStats(
        hp: json['hp'] as int,
        atk: json['atk'] as int,
        def: json['def'] as int,
        spa: json['spa'] as int,
        spd: json['spd'] as int,
        spe: json['spe'] as int,
      );

  Map<String, dynamic> toJson() =>
      {'hp': hp, 'atk': atk, 'def': def, 'spa': spa, 'spd': spd, 'spe': spe};

  int byKey(String key) => switch (key) {
        'hp' => hp,
        'atk' => atk,
        'def' => def,
        'spa' => spa,
        'spd' => spd,
        'spe' => spe,
        _ => throw ArgumentError('unknown stat key: $key'),
      };
}

/// A Mega Evolution forme reachable from a base species via its Mega Stone
/// (the Omni Ring gimmick model: other gimmicks can be added alongside).
class MegaForme {
  final String id;
  final String name;
  final List<String> types;
  final BaseStats baseStats;
  final String ability;

  /// Item id of the required Mega Stone.
  final String item;

  const MegaForme({
    required this.id,
    required this.name,
    required this.types,
    required this.baseStats,
    required this.ability,
    required this.item,
  });

  factory MegaForme.fromJson(Map<String, dynamic> json) => MegaForme(
        id: json['id'] as String,
        name: json['name'] as String,
        types: (json['types'] as List).cast<String>(),
        baseStats: BaseStats.fromJson(json['baseStats'] as Map<String, dynamic>),
        ability: json['ability'] as String,
        item: json['item'] as String,
      );
}

class Species {
  final String id;
  final String name;
  final List<String> types;
  final BaseStats baseStats;
  final List<String> abilities;
  final List<String> learnset;
  final List<MegaForme> megas;

  const Species({
    required this.id,
    required this.name,
    required this.types,
    required this.baseStats,
    required this.abilities,
    required this.learnset,
    this.megas = const [],
  });

  factory Species.fromJson(Map<String, dynamic> json) => Species(
        id: json['id'] as String,
        name: json['name'] as String,
        types: (json['types'] as List).cast<String>(),
        baseStats: BaseStats.fromJson(json['baseStats'] as Map<String, dynamic>),
        abilities: (json['abilities'] as List).cast<String>(),
        learnset: (json['learnset'] as List).cast<String>(),
        megas: ((json['megas'] as List?) ?? const [])
            .map((m) => MegaForme.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  MegaForme? megaById(String? megaId) {
    if (megaId == null) return null;
    for (final m in megas) {
      if (m.id == megaId) return m;
    }
    return null;
  }

  /// Effective types/stats/ability for a given (possibly mega) state.
  List<String> typesFor(String? megaId) => megaById(megaId)?.types ?? types;
  BaseStats baseStatsFor(String? megaId) => megaById(megaId)?.baseStats ?? baseStats;
}
