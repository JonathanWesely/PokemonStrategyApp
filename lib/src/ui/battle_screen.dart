/// The live battle screen — two tabs, switchable at any time during a match:
///
///   • Team Preview: your 6 vs the enemy 6 as clickable sprite boxes.
///     Enemy boxes fill from the preview scan (2D sprite recognition) or
///     manual taps; auto-recognized boxes show in the amber "predicted"
///     style until confirmed. Tap any box for the full per-Pokemon menu
///     (base stats, typing, matchups, learnset, abilities, meta builds).
///   • Battle: the Pokemon on the field (doubles = 2 per side) with the
///     speed strip and intel cards, plus reserve icons — yours known,
///     enemy bench predicted (amber) until revealed (green/confirmed).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/battle_state.dart';
import '../models/recognition_result.dart';
import '../prediction/prediction_engine.dart';
import '../prediction/speed_tiers.dart';
import '../recognition/recognition_service.dart';
import 'capture_screen.dart';
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

  /// Mock engine: no camera needed, recognize an empty image directly.
  /// Local / API engines: open the camera capture screen.
  Future<void> _scan(RecognitionScreen mode) async {
    final state = AppScope.of(context);
    if (state.engineName == 'mock') {
      setState(() => _recognizing = true);
      try {
        final result = await state.runSnapshot(Uint8List(0), screen: mode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('mock: found ${result.enemies.length} enemy Pokemon '
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
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CaptureScreen(mode: mode)),
    );
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
    state.mutateBattle(
        () => state.battle!.enemyPreview.add(PreviewSlot(chosen)));
  }

  Future<void> _endBattle() async {
    final state = AppScope.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End battle'),
        content: const Text('Save this match to your history?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'loss'),
              child: const Text('Save — Loss')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'win'),
              child: const Text('Save — Win')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'discard') {
      await state.endBattle(save: false);
    } else {
      await state.endBattle(result: choice);
    }
    if (mounted) Navigator.pop(context);
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
              onPressed: _endBattle,
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
                label: Text('Scan preview (${state.engineName})'),
                onPressed:
                    _recognizing ? null : () => _scan(RecognitionScreen.preview),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Tap any Pokemon for its full page: base stats, typing, matchups, '
          'learnset, abilities and common builds. Amber boxes are '
          'auto-recognized guesses — tap to confirm or fix.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        Text('Your team', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in battle.team.builds)
              _PreviewBox(
                speciesId: b.speciesId,
                label: b.nickname ?? pack.speciesName(b.speciesId),
                types: pack.speciesById(b.speciesId)?.typesFor(b.megaFormeId) ??
                    const [],
                style: _BoxStyle.yours,
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
              _enemyPreviewBox(context, state, battle.enemyPreview[i], i),
            if (battle.enemyPreview.length < battle.format.teamSize)
              _PreviewBox(
                speciesId: null,
                label: null,
                types: const [],
                style: _BoxStyle.enemy,
                onTap: _appendEnemyPreview,
              ),
          ],
        ),
        if (battle.enemyPreview.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Scan the team-select screen, or tap + to add the enemy '
              'Pokemon by hand. (Long-press a box to remove it.)',
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

  Widget _enemyPreviewBox(
      BuildContext context, AppState state, PreviewSlot slot, int index) {
    final pack = state.pack;
    final battle = state.battle!;
    return _PreviewBox(
      speciesId: slot.speciesId,
      label: pack.speciesName(slot.speciesId),
      types: pack.speciesById(slot.speciesId)?.types ?? const [],
      style: slot.confirmed ? _BoxStyle.enemy : _BoxStyle.predicted,
      confidence: slot.confirmed ? null : slot.confidence,
      onTap: () {
        if (slot.confirmed) {
          showSpeciesDetail(context,
              speciesId: slot.speciesId, showPredictions: true);
        } else {
          _confirmSlotSheet(context, state, slot);
        }
      },
      onLongPress: () =>
          state.mutateBattle(() => battle.enemyPreview.removeAt(index)),
    );
  }

  /// Unconfirmed slot: confirm the guess, pick a runner-up, or choose any.
  void _confirmSlotSheet(BuildContext context, AppState state, PreviewSlot slot) {
    final pack = state.pack;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Which Pokemon is this?',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: SpeciesIcon(slot.speciesId, size: 34),
              title: Text(pack.speciesName(slot.speciesId),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  'best match · ${(slot.confidence * 100).toStringAsFixed(0)}%'),
              trailing: const Icon(Icons.check_circle, color: confirmedColor),
              onTap: () {
                state.confirmPreviewSlot(slot, slot.speciesId);
                Navigator.pop(sheetContext);
              },
            ),
            for (final alt in slot.alternatives.take(3))
              ListTile(
                leading: SpeciesIcon(alt.speciesId, size: 34),
                title: Text(pack.speciesName(alt.speciesId)),
                subtitle: Text(
                    'runner-up · ${(alt.confidence * 100).toStringAsFixed(0)}%'),
                onTap: () {
                  state.confirmPreviewSlot(slot, alt.speciesId);
                  Navigator.pop(sheetContext);
                },
              ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Something else…'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final chosen = await _pickSpecies('Enemy Pokemon');
                if (chosen != null) state.confirmPreviewSlot(slot, chosen);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- battle tab --

  Widget _buildBattleTab(BuildContext context, AppState state) {
    final pack = state.pack;
    final battle = state.battle!;
    final tiers =
        buildSpeedTiers(pack, battle.activeYours, battle.enemiesOnField);
    final benchPredictions = PredictionEngine(pack).predictBench(battle);

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
                    : 'Scan battle (${state.engineName})'),
                onPressed:
                    _recognizing ? null : () => _scan(RecognitionScreen.battle),
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
                'No enemies on the field yet.\nScan the battle screen, or add '
                'the active enemy Pokemon with "Enemy". The Team Preview tab '
                'holds their full roster.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        for (final enemy in battle.enemiesOnField)
          EnemyIntelCard(enemy: enemy),
        for (final build in battle.activeYours)
          YourIntelCard(pokemonBuild: build),

        // Enemy reserves: revealed benched enemies (confirmed) + predicted.
        if (battle.enemyBench.isNotEmpty ||
            battle.enemyUnknownReserveCount > 0) ...[
          const SizedBox(height: 8),
          Text('Enemy reserves', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final enemy in battle.enemyBench)
                ActionChip(
                  avatar: SpeciesIcon(enemy.speciesId, size: 20),
                  label: Text(pack.speciesName(enemy.speciesId)),
                  side: const BorderSide(color: confirmedColor),
                  onPressed: () =>
                      state.mutateBattle(() => enemy.onField = true),
                ),
              for (final option in benchPredictions)
                ActionChip(
                  avatar: SpeciesIcon(option.id, size: 20),
                  label: Text('${option.label}?',
                      style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: predictedColor)),
                  side: BorderSide(color: predictedColor),
                  onPressed: () => state.mutateBattle(
                      () => battle.addEnemy(option.id, onField: false)),
                ),
              for (var i = benchPredictions.length;
                  i < battle.enemyUnknownReserveCount;
                  i++)
                const Chip(
                  avatar: Icon(Icons.help_outline, size: 14),
                  label: Text('?'),
                ),
            ],
          ),
          Text(
            'Amber = predicted from usage + their scouted roster; tap when '
            'revealed to confirm.',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
                avatar: battle.activePickIndexes.contains(i)
                    ? null
                    : SpeciesIcon(battle.picks[i].speciesId, size: 20),
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

enum _BoxStyle { yours, enemy, predicted }

/// One clickable box in the Team Preview grid. [label] null = empty add slot.
class _PreviewBox extends StatelessWidget {
  final String? speciesId;
  final String? label;
  final List<String> types;
  final _BoxStyle style;
  final double? confidence;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PreviewBox({
    required this.speciesId,
    required this.label,
    required this.types,
    required this.style,
    this.confidence,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final empty = label == null;
    final color = empty
        ? Colors.grey.shade100
        : switch (style) {
            _BoxStyle.yours => Colors.blue.shade50,
            _BoxStyle.enemy => Colors.red.shade50,
            _BoxStyle.predicted => Colors.amber.shade50,
          };
    final border = style == _BoxStyle.predicted
        ? BorderSide(color: predictedColor, width: 1.4)
        : BorderSide.none;
    return SizedBox(
      width: 112,
      height: 74,
      child: Card(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: border,
        ),
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
                        Text('Add',
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      SpeciesIcon(speciesId!, size: 34),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(label!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 3,
                              runSpacing: 2,
                              children: [
                                for (final t in types) TypeChip(t, small: true)
                              ],
                            ),
                            if (confidence != null)
                              Text(
                                  '${(confidence! * 100).toStringAsFixed(0)}%'
                                  ' guess',
                                  style: TextStyle(
                                      fontSize: 9, color: predictedColor)),
                          ],
                        ),
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
