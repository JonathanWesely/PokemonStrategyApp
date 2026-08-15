/// Full detail for one Pokemon, shown when you tap a Team Preview box.
///
/// Deterministic facts (types, base stats, learnable moves, abilities,
/// weakness/resistance chart) for any Pokemon, plus — on the preview screen —
/// meta-build predictions (popular moves/item/ability/spread) from the usage
/// pack. For your own Pokemon it also shows your exact level-50 stats and the
/// four moves you built.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/data_pack.dart';
import '../data/stat_calculator.dart';
import '../models/battle_state.dart';
import '../models/pokemon_build.dart';
import '../models/prediction.dart';
import '../models/species.dart';
import '../prediction/prediction_engine.dart';
import 'widgets.dart';

/// Open the detail sheet as a scrollable modal.
void showSpeciesDetail(
  BuildContext context, {
  required String speciesId,
  PokemonBuild? build,
  bool showPredictions = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SpeciesDetailSheet(
      speciesId: speciesId,
      build: build,
      showPredictions: showPredictions,
    ),
  );
}

class SpeciesDetailSheet extends StatelessWidget {
  final String speciesId;

  /// Non-null when this is one of YOUR Pokemon (adds exact stats + your moves).
  final PokemonBuild? build;

  /// Show usage-based meta predictions (preview screen); off for pure facts.
  final bool showPredictions;

  const SpeciesDetailSheet({
    super.key,
    required this.speciesId,
    this.build,
    this.showPredictions = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pack = state.pack;
    final species = pack.speciesById(speciesId);
    if (species == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Unknown Pokemon.'),
      );
    }

    final megaId = build?.megaFormeId;
    final types = species.typesFor(megaId);
    final baseStats = species.baseStatsFor(megaId);

    // Weakness/resistance from confirmed facts: your ability/item, or (for a
    // previewed enemy) the most common ability when predictions are on.
    String? profileAbility = build?.ability;
    String? profileItem = build?.itemId;
    EnemyIntel? intel;
    if (showPredictions || build == null) {
      intel = PredictionEngine(pack).intelFor(EnemyPokemon(speciesId: speciesId));
      profileAbility ??= intel.abilities.isEmpty ? null : intel.abilities.first.id;
    }
    final profile = pack.typeChart
        .defensiveProfile(types, ability: profileAbility, itemId: profileItem);

    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              Icon(build != null ? Icons.person : Icons.catching_pokemon,
                  size: 18,
                  color: build != null ? Colors.blue : Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(species.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: [for (final t in types) TypeChip(t)]),

          if (build != null) ...[
            const SizedBox(height: 6),
            Text(
              '${build!.ability.isEmpty ? '—' : build!.ability} · '
              '${pack.itemName(build!.itemId)} · ${build!.nature}',
              style: const TextStyle(fontSize: 12),
            ),
          ],

          const Divider(height: 20),
          Text('Base stats (Champions)', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          BaseStatsRow(baseStats),

          if (build != null) ...[
            const SizedBox(height: 10),
            Text('Your stats (level 50)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            _exactStatsRow(StatCalculator.computeStats(
                baseStats, build!.sp, build!.nature)),
          ],

          const Divider(height: 20),
          Text('Weakness / resistance', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          MatchupGroups(profile: profile),

          const Divider(height: 20),
          Text('Abilities', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final a in species.abilities)
                Chip(
                  label: Text(a, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),

          if (build != null) ...[
            const Divider(height: 20),
            Text('Your moves', style: theme.textTheme.labelLarge),
            for (final moveId in build!.moveIds) _moveLine(pack, moveId),
          ],

          const Divider(height: 20),
          Text('Can learn (starter pack — abbreviated)',
              style: theme.textTheme.labelLarge),
          for (final moveId in species.learnset) _moveLine(pack, moveId),

          if (showPredictions && intel != null) ...[
            const Divider(height: 20),
            Text('Popular meta build', style: theme.textTheme.labelLarge),
            if (!intel.fromUsageData)
              const Text('No usage data — learnset only',
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey)),
            const SizedBox(height: 4),
            if (intel.spreads.isNotEmpty)
              Text('Spread: ${_spreadText(intel.spreads.first)}',
                  style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            for (final option in intel.moves.take(6))
              RatedOptionRow(
                  option: option,
                  dim: !intel.fromUsageData,
                  subtitle: pack.moveById(option.id)?.summary),
            if (intel.items.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Item: ${intel.items.first.label} '
                  '(${intel.items.first.pct.toStringAsFixed(0)}%)',
                  style: const TextStyle(fontSize: 12)),
            ],
            if (intel.teammates.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Common partners', style: theme.textTheme.labelLarge),
              Wrap(
                spacing: 4,
                children: [
                  for (final e in intel.teammates.entries.take(4))
                    Chip(
                      label: Text(
                          '${pack.speciesName(e.key)} ${e.value.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _exactStatsRow(Map<String, int> stats) {
    return Row(
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
    );
  }

  Widget _moveLine(DataPack pack, String moveId) {
    final move = pack.moveById(moveId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          TypeChip(move?.type ?? 'Normal', small: true),
          const SizedBox(width: 6),
          Expanded(
            child: Text(pack.moveName(moveId),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Text(move?.summary ?? '',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  String _spreadText(SpreadUsage spread) {
    final parts = [
      for (final key in statKeys)
        if ((spread.sp[key] ?? 0) > 0) '${spread.sp[key]} ${statLabels[key]}',
    ];
    final sp = parts.isEmpty ? 'no SP' : parts.join(' / ');
    return '${spread.nature} · $sp';
  }
}
