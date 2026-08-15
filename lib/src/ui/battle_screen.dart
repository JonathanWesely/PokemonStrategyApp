/// The live battle screen — two tabs, switchable at any time during a match:
///
///   • Team Preview: your 6 vs the enemy 6 as clickable boxes (facts + meta
///     predictions). Mirrors the in-game preview screen (no names there — you
///     identify the enemy by sprite; on-device recognition lands in Track 2).
///   • Battle: the Pokemon on the field (doubles = 2 per side) with the speed
///     strip and intel cards, plus reserve icons for the chosen-but-benched
///     Pokemon. Under the Local engine the enemy cards are facts + "?".
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/recognition_result.dart';
import '../prediction/speed_tiers.dart';
import 'intel_card.dart';
import 'species_detail_sheet.dart';
import 'widgets.dart';

class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  bool _recognizing = false;

  Future<void> _snapshot() async {
    final state = AppScope.of(context);
    setState(() => _recognizing = true);
    try {
      // Track 2 wires the camera/share-sheet here; until then the active
      // engine decides what to do with an empty image (mock samples enemies,
      // local reports only your side).
      final result = await state.runSnapshot(Uint8List(0));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${result.engine}: found ${result.enemies.length} enemy Pokemon '
              '— tap any wrong one to fix it'),
        ));
      }
    } on RecognitionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  /// Scrollable species picker over the whole roster.
  Future<String?> _pickSpecies(String title) {
    final state = AppScope.of(context);
    final all = state.pack.species.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return showPickerDialog(context,
        title: title, entries: [for (final s in all) MapEntry(s.id, s.name)]);
  }

  Future<void> _addEnemyManually() async {
    final chosen = await _pickSpecies('Enemy Pokemon');
    if (chosen != null && mounted) AppScope.of(context).addEnemyManually(chosen);
  }

  Future<void> _appendEnemyPreview() async {
    final chosen = await _pickSpecies('Identify an enemy Pokemon');
    if (chosen == null || !mounted) return;
    final state = AppScope.of(context);
    state.mutateBattle(() => state.battle!.enemyPreview.add(chosen));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final battle = state.battle;
    if (battle == null) {
      return const Scaffold(body: Center(child: Text('No battle in progress')));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(battle.format.name, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              tooltip: 'End battle',
              icon: const Icon(Icons.close),
              onPressed: () {
                state.endBattle();
                Navigator.pop(context);
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.grid_view), text: 'Team Preview'),
              Tab(icon: Icon(Icons.sports_kabaddi), text: 'Battle'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPreviewTab(context, state),
            _buildBattleTab(context, state),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- team preview tab --

  Widget _buildPreviewTab(BuildContext context, AppState state) {
    final pack = state.pack;
    final battle = state.battle!;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Tap any Pokemon for its types, base stats, learnset, abilities '
            'and matchups.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 12),
        Text('Your team', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in battle.team.builds)
              _PreviewBox(
                label: b.nickname ?? pack.speciesName(b.speciesId),
                types: pack.speciesById(b.speciesId)?.typesFor(b.megaFormeId) ??
                    const [],
                yours: true,
                onTap: () => showSpeciesDetail(context,
                    speciesId: b.speciesId, build: b),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Enemy team', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            Text('(${battle.enemyPreview.length}/${battle.format.teamSize})',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < battle.enemyPreview.length; i++)
              _PreviewBox(
                label: pack.speciesName(battle.enemyPreview[i]),
                types: pack.speciesById(battle.enemyPreview[i])?.types ??
                    const [],
                yours: false,
                onTap: () => showSpeciesDetail(context,
                    speciesId: battle.enemyPreview[i], showPredictions: true),
                onLongPress: () => state.mutateBattle(
                    () => battle.enemyPreview.removeAt(i)),
              ),
            if (battle.enemyPreview.length < battle.format.teamSize)
              _PreviewBox(
                label: null,
                types: const [],
                yours: false,
                onTap: _appendEnemyPreview,
              ),
          ],
        ),
        if (battle.enemyPreview.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Add the enemy Pokemon shown on the preview screen. '
              '(Long-press a box to remove it.)',
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ------------------------------------------------------------- battle tab --

  Widget _buildBattleTab(BuildContext context, AppState state) {
    final pack = state.pack;
    final battle = state.battle!;
    final factsOnly = state.engineName == 'local';
    final tiers =
        buildSpeedTiers(pack, battle.activeYours, battle.enemiesOnField);

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: _recognizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_camera),
                label: Text(_recognizing
                    ? 'Recognizing…'
                    : 'Snapshot (${state.engineName})'),
                onPressed: _recognizing ? null : _snapshot,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Enemy'),
              onPressed: _addEnemyManually,
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (tiers.isNotEmpty) _SpeedStrip(tiers: tiers),
        const SizedBox(height: 10),

        if (battle.enemiesOnField.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No enemies on the field yet.\nAdd the active enemy Pokemon '
                'with "Enemy" (or take a snapshot), and use the Team Preview '
                'tab for their full roster.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        for (final enemy in battle.enemiesOnField)
          EnemyIntelCard(enemy: enemy, factsOnly: factsOnly),
        for (final build in battle.activeYours)
          YourIntelCard(pokemonBuild: build),

        // Enemy reserves: revealed benched enemies + "?" for the rest.
        if (battle.enemyBench.isNotEmpty ||
            battle.enemyUnknownReserveCount > 0) ...[
          const SizedBox(height: 8),
          Text('Enemy reserves', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final enemy in battle.enemyBench)
                ActionChip(
                  avatar: const Icon(Icons.smart_toy, size: 14),
                  label: Text(pack.speciesName(enemy.speciesId)),
                  onPressed: () =>
                      state.mutateBattle(() => enemy.onField = true),
                ),
              for (var i = 0; i < battle.enemyUnknownReserveCount; i++)
                const Chip(
                  avatar: Icon(Icons.help_outline, size: 14),
                  label: Text('?'),
                ),
            ],
          ),
        ],

        const SizedBox(height: 8),
        Text('Your picks (tap to set who is on the field)',
            style: Theme.of(context).textTheme.titleSmall),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < battle.picks.length; i++)
              FilterChip(
                selected: battle.activePickIndexes.contains(i),
                label: Text(battle.picks[i].nickname ??
                    pack.speciesName(battle.picks[i].speciesId)),
                onSelected: (selected) => state.mutateBattle(() {
                  if (selected) {
                    battle.activePickIndexes.add(i);
                  } else {
                    battle.activePickIndexes.remove(i);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One clickable box in the Team Preview grid. [label] null = empty add slot.
class _PreviewBox extends StatelessWidget {
  final String? label;
  final List<String> types;
  final bool yours;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PreviewBox({
    required this.label,
    required this.types,
    required this.yours,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final empty = label == null;
    final color = empty
        ? Colors.grey.shade100
        : yours
            ? Colors.blue.shade50
            : Colors.red.shade50;
    return SizedBox(
      width: 106,
      height: 68,
      child: Card(
        color: color,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: empty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 18, color: Colors.grey),
                        Text('Add', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: [for (final t in types) TypeChip(t, small: true)],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SpeedStrip extends StatelessWidget {
  final List<SpeedTierEntry> tiers;

  const _SpeedStrip({required this.tiers});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Speed check (fastest first)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final entry in tiers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      entry.yours ? Icons.person : Icons.smart_toy,
                      size: 14,
                      color: entry.yours ? Colors.blue : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(entry.label,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(
                      entry.isExact
                          ? '${entry.likely}'
                          : '${entry.min}–${entry.max} (~${entry.likely})',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (entry.scarfLikely)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Tooltip(
                          message: 'Choice Scarf likely — real ceiling is 1.5x',
                          child: Icon(Icons.warning_amber,
                              size: 14, color: Colors.orange),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
