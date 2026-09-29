/// The dashboard cards: everything the game hides, one card per Pokemon.
///
/// Color language: green = confirmed this battle (the reveal ledger),
/// amber = predicted from usage data, grey = unknown/no data. Tap a row to
/// confirm/unconfirm it; tap the info icon for what the move/ability/item
/// does; use the "+" rows for reveals the predictions didn't list.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/stat_calculator.dart';
import '../models/battle_state.dart';
import '../models/pokemon_build.dart';
import '../models/species.dart';
import '../prediction/prediction_engine.dart';
import 'info_sheets.dart';
import 'widgets.dart';

/// Card for one ENEMY Pokemon: predicted stats/moves/items/abilities with
/// tap-to-confirm (the reveal ledger).
class EnemyIntelCard extends StatelessWidget {
  final EnemyPokemon enemy;

  /// When set (the arena's detail overlay), the ↓ button asks which spot
  /// to swap with instead of plain benching.
  final VoidCallback? onSwapRequest;

  const EnemyIntelCard({super.key, required this.enemy, this.onSwapRequest});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pack = state.pack;
    final species = pack.speciesById(enemy.speciesId);
    if (species == null) return const SizedBox.shrink();

    final battle = state.battle!;
    final teammates = [
      for (final e in battle.enemiesOnField)
        if (e != enemy) e.speciesId
    ];
    final intel = PredictionEngine(pack)
        .intelFor(enemy, visibleTeammateIds: teammates);
    final megaForme =
        enemy.mega && species.megas.isNotEmpty ? species.megas.first : null;
    final types = megaForme?.types ?? species.types;
    final topAbility =
        intel.abilities.isEmpty ? null : intel.abilities.first.id;
    final profile = pack.typeChart.defensiveProfile(
      types,
      ability: enemy.revealedAbility ?? topAbility,
      itemId: enemy.revealedItem,
    );
    final dim = !intel.fromUsageData;
    final labelStyle = Theme.of(context).textTheme.labelLarge;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SpeciesIcon(enemy.speciesId, size: 30),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    megaForme?.name ?? species.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (enemy.hpPercent != null)
                  Text('${enemy.hpPercent}% HP',
                      style: const TextStyle(fontSize: 12)),
                if (species.megas.isNotEmpty)
                  IconButton(
                    tooltip: enemy.mega ? 'Revert forme' : 'Mark as Mega',
                    icon: Icon(Icons.flash_on,
                        size: 18,
                        color: enemy.mega ? Colors.purple : Colors.grey),
                    onPressed: () =>
                        state.mutateBattle(() => enemy.mega = !enemy.mega),
                  ),
                IconButton(
                  tooltip: onSwapRequest == null ? 'Bench' : 'Swap with…',
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: onSwapRequest ??
                      () => state.mutateBattle(() => enemy.onField = false),
                ),
                IconButton(
                  tooltip: 'Remove (misrecognized)',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => state.removeEnemy(enemy),
                ),
              ],
            ),
            Wrap(spacing: 4, children: [for (final t in types) TypeChip(t)]),
            if (dim)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No usage data for this Pokemon — showing learnset only',
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey),
                ),
              ),
            const Divider(),
            MatchupGroups(profile: profile),
            const Divider(),

            Text('Base stats (Champions)', style: labelStyle),
            const SizedBox(height: 4),
            BaseStatsRow(megaForme?.baseStats ?? species.baseStats),
            const SizedBox(height: 6),
            Text('Predicted stats (level 50)', style: labelStyle),
            const SizedBox(height: 4),
            _statRangesTable(intel.statRanges),
            const Divider(),

            Text('Moves — tap when revealed', style: labelStyle),
            for (final option in intel.moves.take(8))
              RatedOptionRow(
                option: option,
                dim: dim,
                subtitle: pack.moveById(option.id)?.summary,
                onInfo: () => showMoveInfo(context, pack, option.id),
                onConfirm: () => state.mutateBattle(() {
                  if (option.confirmed) {
                    enemy.revealedMoves.remove(option.id);
                  } else {
                    enemy.revealedMoves.add(option.id);
                  }
                }),
              ),
            _addUnlistedRow(
              context,
              label: 'Saw a move not listed?',
              onTap: () => _revealMove(context, state, species),
            ),
            const Divider(),

            Text('Item', style: labelStyle),
            for (final option in intel.items.take(4))
              RatedOptionRow(
                option: option,
                dim: dim,
                onInfo: () => showItemInfo(context, pack, option.id),
                onConfirm: () => state.mutateBattle(() {
                  enemy.revealedItem = option.confirmed ? null : option.id;
                }),
              ),
            _addUnlistedRow(
              context,
              label: 'Different item?',
              onTap: () => _revealItem(context, state),
            ),
            const Divider(),

            Text('Ability', style: labelStyle),
            for (final option in intel.abilities.take(3))
              RatedOptionRow(
                option: option,
                dim: dim,
                onInfo: () => showAbilityInfo(context, pack, option.id),
                onConfirm: megaForme != null
                    ? null // a Mega's ability is fixed by the forme
                    : () => state.mutateBattle(() {
                          enemy.revealedAbility =
                              option.confirmed ? null : option.id;
                        }),
              ),

            if (intel.teammates.isNotEmpty) ...[
              const Divider(),
              Text('Common partners', style: labelStyle),
              Wrap(
                spacing: 4,
                children: [
                  for (final entry in intel.teammates.entries.take(4))
                    Chip(
                      avatar: SpeciesIcon(entry.key, size: 18),
                      label: Text(
                        '${pack.speciesName(entry.key)} '
                        '${entry.value.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addUnlistedRow(BuildContext context,
      {required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline,
                size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _statRangesTable(Map<String, dynamic> ranges) {
    return Row(
      children: [
        for (final key in statKeys)
          Expanded(
            child: Column(
              children: [
                Text(statLabels[key] ?? key,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600)),
                Text(
                  '${ranges[key] ?? '?'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _revealMove(
      BuildContext context, AppState state, Species species) async {
    final pack = state.pack;
    final entries = <MapEntry<String, String>>[
      for (final id in species.learnset)
        if (!enemy.revealedMoves.contains(id)) MapEntry(id, pack.moveName(id)),
    ]..sort((a, b) => a.value.compareTo(b.value));
    if (entries.isEmpty) return;
    final chosen =
        await showPickerDialog(context, title: 'Reveal a move', entries: entries);
    if (chosen != null) {
      state.mutateBattle(() => enemy.revealedMoves.add(chosen));
    }
  }

  Future<void> _revealItem(BuildContext context, AppState state) async {
    final pack = state.pack;
    final entries = <MapEntry<String, String>>[
      for (final item in pack.items.values) MapEntry(item.id, item.name),
    ]..sort((a, b) => a.value.compareTo(b.value));
    final chosen =
        await showPickerDialog(context, title: 'Reveal item', entries: entries);
    if (chosen != null) {
      state.mutateBattle(() => enemy.revealedItem = chosen);
    }
  }
}

/// Card for one of YOUR Pokemon: exact stats, real moves, matchups.
class YourIntelCard extends StatelessWidget {
  final PokemonBuild pokemonBuild;

  /// When set (the arena's detail overlay), a ↓ button appears that asks
  /// which spot to swap this Pokemon with.
  final VoidCallback? onSwapRequest;

  const YourIntelCard(
      {super.key, required this.pokemonBuild, this.onSwapRequest});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pack = state.pack;
    final species = pack.speciesById(pokemonBuild.speciesId);
    if (species == null) return const SizedBox.shrink();

    final types = species.typesFor(pokemonBuild.megaFormeId);
    final stats = StatCalculator.computeStats(
      species.baseStatsFor(pokemonBuild.megaFormeId),
      pokemonBuild.sp,
      pokemonBuild.nature,
    );
    final profile = pack.typeChart.defensiveProfile(
      types,
      ability: pokemonBuild.ability,
      itemId: pokemonBuild.itemId,
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SpeciesIcon(pokemonBuild.speciesId, size: 30),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    pokemonBuild.nickname ?? species.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                InkWell(
                  onTap: pokemonBuild.ability.isEmpty
                      ? null
                      : () =>
                          showAbilityInfo(context, pack, pokemonBuild.ability),
                  child: Text(
                      '${pokemonBuild.ability} · ${pack.itemName(pokemonBuild.itemId)}',
                      style: const TextStyle(fontSize: 11)),
                ),
                if (onSwapRequest != null)
                  IconButton(
                    tooltip: 'Swap with…',
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: onSwapRequest,
                  ),
              ],
            ),
            Wrap(spacing: 4, children: [for (final t in types) TypeChip(t)]),
            const Divider(),
            MatchupGroups(profile: profile),
            const Divider(),
            Row(
              children: [
                for (final key in statKeys)
                  Expanded(
                    child: Column(
                      children: [
                        Text(statLabels[key] ?? key,
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600)),
                        Text('${stats[key]}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(),
            for (final moveId in pokemonBuild.moveIds)
              InkWell(
                onTap: () => showMoveInfo(context, pack, moveId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      TypeChip(pack.moveById(moveId)?.type ?? 'Normal',
                          small: true),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(pack.moveName(moveId),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                      Text(pack.moveById(moveId)?.summary ?? '',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
