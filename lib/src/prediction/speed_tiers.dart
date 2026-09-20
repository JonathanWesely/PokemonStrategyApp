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

  /// True when this Pokemon's place relative to at least one other entry
  /// was CONFIRMED by the match itself (it moved first/last at the same
  /// move priority) — the strip shows ✓ instead of ?.
  final bool orderConfirmed;

  const SpeedTierEntry({
    required this.speciesId,
    required this.label,
    required this.yours,
    required this.min,
    required this.max,
    required this.likely,
    this.scarfLikely = false,
    this.orderConfirmed = false,
  });

  /// Evidence key, matching BattleSession.speedEvidence.
  String get key => '${yours ? 'y' : 'e'}:$speciesId';

  bool get isExact => min == max;

  SpeedTierEntry withOrderConfirmed() => SpeedTierEntry(
        speciesId: speciesId,
        label: label,
        yours: yours,
        min: min,
        max: max,
        likely: likely,
        scarfLikely: scarfLikely,
        orderConfirmed: true,
      );
}

/// Entries for everything on the field, sorted fastest-likely first.
///
/// [evidence] (BattleSession.speedEvidence) reorders the prediction where
/// the match has revealed the real order and marks those entries confirmed.
List<SpeedTierEntry> buildSpeedTiers(
  DataPack pack,
  List<PokemonBuild> yourActive,
  List<EnemyPokemon> enemiesOnField, {
  List<List<String>> evidence = const [],
}) {
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
  return applySpeedEvidence(entries, evidence);
}

/// Reorder [entries] so every observed `[faster, slower]` pair holds, and
/// mark the entries those pairs pin down. Bubble passes: cheap and stable
/// for the 4 Pokemon a doubles field holds.
List<SpeedTierEntry> applySpeedEvidence(
    List<SpeedTierEntry> entries, List<List<String>> evidence) {
  if (evidence.isEmpty || entries.length < 2) return entries;
  final out = [...entries];
  final keys = {for (final e in out) e.key};
  final pairs = [
    for (final p in evidence)
      if (p.length >= 2 && keys.contains(p[0]) && keys.contains(p[1])) p
  ];
  if (pairs.isEmpty) return out;
  int indexOf(String key) => out.indexWhere((e) => e.key == key);
  for (var pass = 0; pass < out.length * pairs.length; pass++) {
    var moved = false;
    for (final p in pairs) {
      final fi = indexOf(p[0]), si = indexOf(p[1]);
      if (fi > si) {
        final e = out.removeAt(fi);
        out.insert(si, e);
        moved = true;
      }
    }
    if (!moved) break;
  }
  final confirmedKeys = {for (final p in pairs) p[0], for (final p in pairs) p[1]};
  for (var i = 0; i < out.length; i++) {
    if (confirmedKeys.contains(out[i].key)) {
      out[i] = out[i].withOrderConfirmed();
    }
  }
  return out;
}
