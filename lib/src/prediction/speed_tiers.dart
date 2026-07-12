/// The speed-check strip: who moves before whom. Your Pokemon have exact
/// speeds; enemies get predicted ranges. Pure Dart.
library;

import '../data/data_pack.dart';
import '../data/stat_calculator.dart';
import '../models/battle_state.dart';
import '../models/nature.dart';
import '../models/pokemon_build.dart';
import '../models/prediction.dart';
import 'prediction_engine.dart';

class SpeedTierEntry {
  final String speciesId;
  final String label;
  final bool yours;
  final int min;
  final int max;
  final int likely;

  /// Set when the enemy's top predicted item is Choice Scarf — its real
  /// ceiling is 1.5x what the range shows.
  final bool scarfLikely;

  const SpeedTierEntry({
    required this.speciesId,
    required this.label,
    required this.yours,
    required this.min,
    required this.max,
    required this.likely,
    this.scarfLikely = false,
  });

  bool get isExact => min == max;
}

/// Entries for everything on the field, sorted fastest-likely first.
List<SpeedTierEntry> buildSpeedTiers(
  DataPack pack,
  List<PokemonBuild> yourActive,
  List<EnemyPokemon> enemiesOnField,
) {
  final engine = PredictionEngine(pack);
  final entries = <SpeedTierEntry>[];

  for (final build in yourActive) {
    final species = pack.speciesById(build.speciesId);
    if (species == null) continue;
    final base = species.baseStatsFor(build.megaFormeId).spe;
    final nature = natureByName(build.nature);
    var speed = StatCalculator.otherStat(
        base, build.spFor('spe'), nature.multiplierNumerator('spe'));
    if (build.itemId == 'choice-scarf') speed = speed * 3 ~/ 2;
    if (build.itemId == 'iron-ball') speed = speed ~/ 2;
    entries.add(SpeedTierEntry(
      speciesId: build.speciesId,
      label: build.nickname ?? species.name,
      yours: true,
      min: speed,
      max: speed,
      likely: speed,
    ));
  }

  for (final enemy in enemiesOnField) {
    final species = pack.speciesById(enemy.speciesId);
    if (species == null) continue;
    final intel = engine.intelFor(enemy);
    final range = intel.statRanges['spe'] ??
        StatRange(
          min: StatCalculator.minStat(species.baseStats.spe, 'spe'),
          max: StatCalculator.maxStat(species.baseStats.spe, 'spe'),
          likely: StatCalculator.otherStat(species.baseStats.spe, 0, 100),
        );
    final topItem = intel.items.isEmpty ? null : intel.items.first.id;
    entries.add(SpeedTierEntry(
      speciesId: enemy.speciesId,
      label: species.name,
      yours: false,
      min: range.min,
      max: range.max,
      likely: range.likely,
      scarfLikely: topItem == 'choice-scarf' ||
          enemy.revealedItem == 'choice-scarf',
    ));
  }

  entries.sort((a, b) => b.likely.compareTo(a.likely));
  return entries;
}
