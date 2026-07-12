/// Prediction engine v1: usage-frequency lookup with reveal promotion and
/// a learnset fallback when a species has no usage data. Pure Dart.
///
/// v2 (plan §2.5 / Phase 4) upgrades this to Bayesian re-weighting on
/// observed teammates, leads, and reveals — the reveal ledger built here
/// (EnemyPokemon.revealedMoves/Item/Ability) is already its event source.
library;

import '../data/data_pack.dart';
import '../data/stat_calculator.dart';
import '../models/battle_state.dart';
import '../models/nature.dart';
import '../models/prediction.dart';

class PredictionEngine {
  final DataPack pack;

  const PredictionEngine(this.pack);

  /// Full intel for one enemy. [visibleTeammateIds] are the other enemy
  /// species currently on the field (doubles pairing awareness).
  EnemyIntel intelFor(EnemyPokemon enemy,
      {List<String> visibleTeammateIds = const []}) {
    final species = pack.speciesById(enemy.speciesId);
    final usage = pack.usage.forSpecies(enemy.speciesId);
    final baseStats = species?.baseStatsFor(enemy.mega ? _megaIdFor(enemy) : null);

    // ---- moves ----
    var moves = usage?.moves ?? _learnsetFallback(enemy.speciesId);
    moves = _promoteConfirmed(
      moves,
      confirmedIds: enemy.revealedMoves,
      labelFor: pack.moveName,
    );

    // ---- items ----
    var items = usage?.items ?? const <RatedOption>[];
    items = _promoteConfirmed(
      items,
      confirmedIds: {if (enemy.revealedItem != null) enemy.revealedItem!},
      labelFor: (id) => pack.itemName(id),
    );

    // ---- abilities ----
    var abilities = usage?.abilities ??
        [
          for (final a in species?.abilities ?? const <String>[])
            RatedOption(
                id: a,
                label: a,
                pct: species!.abilities.isEmpty
                    ? 0
                    : 100 / species.abilities.length),
        ];
    abilities = _promoteConfirmed(
      abilities,
      confirmedIds: {if (enemy.revealedAbility != null) enemy.revealedAbility!},
      labelFor: (id) => id,
    );
    // A Mega's ability is fixed by the forme.
    if (enemy.mega && species != null) {
      final mega = species.megaById(_megaIdFor(enemy));
      if (mega != null) {
        abilities = [
          RatedOption(
              id: mega.ability, label: mega.ability, pct: 100, confirmed: true)
        ];
      }
    }

    // ---- stat ranges ----
    final spreads = usage?.spreads ?? const <SpreadUsage>[];
    final ranges = <String, StatRange>{};
    if (baseStats != null) {
      for (final key in ['hp', 'atk', 'def', 'spa', 'spd', 'spe']) {
        ranges[key] = _rangeFor(baseStats.byKey(key), key, spreads);
      }
    }

    return EnemyIntel(
      speciesId: enemy.speciesId,
      usagePercent: usage?.usagePercent ?? 0,
      fromUsageData: usage != null,
      moves: moves,
      items: items,
      abilities: abilities,
      spreads: spreads,
      statRanges: ranges,
      teammates: usage?.teammates ?? const {},
    );
  }

  String? _megaIdFor(EnemyPokemon enemy) {
    final species = pack.speciesById(enemy.speciesId);
    if (species == null || species.megas.isEmpty) return null;
    // If several Megas exist (Charizard), assume the more common one; the
    // confirm-and-correct UI can override by toggling the forme.
    return species.megas.first.id;
  }

  /// Mark confirmed options, re-sort them first, and append confirmed
  /// options that were never predicted (the "unpredicted reveal" case).
  List<RatedOption> _promoteConfirmed(
    List<RatedOption> options, {
    required Set<String> confirmedIds,
    required String Function(String id) labelFor,
  }) {
    final byId = {for (final o in options) o.id: o};
    final out = <RatedOption>[];
    for (final id in confirmedIds) {
      final existing = byId.remove(id);
      out.add(existing?.asConfirmed() ??
          RatedOption(id: id, label: labelFor(id), pct: 100, confirmed: true));
    }
    final rest = byId.values.toList()..sort((a, b) => b.pct.compareTo(a.pct));
    return [...out, ...rest];
  }

  List<RatedOption> _learnsetFallback(String speciesId) {
    final species = pack.speciesById(speciesId);
    if (species == null) return const [];
    return [
      for (final m in species.learnset)
        RatedOption(id: m, label: pack.moveName(m), pct: 0),
    ];
  }

  StatRange _rangeFor(int base, String statKey, List<SpreadUsage> spreads) {
    final min = StatCalculator.minStat(base, statKey);
    final max = StatCalculator.maxStat(base, statKey);
    if (spreads.isEmpty) {
      final neutral = statKey == 'hp'
          ? StatCalculator.hpStat(base, 0)
          : StatCalculator.otherStat(base, 0, 100);
      return StatRange(min: min, max: max, likely: neutral);
    }
    final top = spreads.first;
    final nature = natureByName(top.nature);
    final spValue = top.sp[statKey] ?? 0;
    final likely = statKey == 'hp'
        ? StatCalculator.hpStat(base, spValue)
        : StatCalculator.otherStat(
            base, spValue, nature.multiplierNumerator(statKey));
    return StatRange(min: min, max: max, likely: likely);
  }
}
