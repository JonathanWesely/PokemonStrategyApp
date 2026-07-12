/// The live battle screen: snapshot / manual entry, speed strip, intel cards.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/recognition_result.dart';
import '../prediction/speed_tiers.dart';
import 'intel_card.dart';

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
      // Phase 3 wires the camera/share-sheet here; until then the active
      // engine decides what to do with an empty image (mock ignores it).
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

  Future<void> _addEnemyManually() async {
    final state = AppScope.of(context);
    final all = state.pack.species.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Enemy Pokemon'),
        children: [
          for (final s in all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s.id),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (chosen != null) state.addEnemyManually(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final battle = state.battle;
    if (battle == null) {
      return const Scaffold(body: Center(child: Text('No battle in progress')));
    }

    final tiers =
        buildSpeedTiers(state.pack, battle.activeYours, battle.enemiesOnField);

    return Scaffold(
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
      ),
      body: ListView(
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
                  'No enemies identified yet.\nTake a snapshot of the battle '
                  'screen, or add the enemy Pokemon manually.',
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          for (final enemy in battle.enemiesOnField)
            EnemyIntelCard(enemy: enemy),
          for (final build in battle.activeYours)
            YourIntelCard(pokemonBuild: build),

          if (battle.enemyBench.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Enemy bench (revealed)',
                style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 6,
              children: [
                for (final enemy in battle.enemyBench)
                  ActionChip(
                    label: Text(state.pack.speciesName(enemy.speciesId)),
                    onPressed: () =>
                        state.mutateBattle(() => enemy.onField = true),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 8),
          Text('Your picks', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < battle.picks.length; i++)
                FilterChip(
                  selected: battle.activePickIndexes.contains(i),
                  label: Text(battle.picks[i].nickname ??
                      state.pack.speciesName(battle.picks[i].speciesId)),
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
