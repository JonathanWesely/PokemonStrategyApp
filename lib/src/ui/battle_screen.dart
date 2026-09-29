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
import '../recognition/auto_scan.dart';
import '../models/recognition_result.dart';
import '../prediction/speed_tiers.dart';
import '../recognition/recognition_service.dart';
import 'arena_view.dart';
import 'capture_screen.dart';
import 'species_detail_sheet.dart';
import 'widgets.dart';

class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  bool _recognizing = false;

  /// Pick-selection state (Battle tab): team-build indexes in chosen order —
  /// the first [FormatSpec.fieldSlots] lead.
  final List<int> _pickOrder = [];
  bool _editingPicks = false;

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

  /// The Battle tab's "+ Enemy" button. Choices are the enemy team from
  /// the Team Preview tab — six knowns beat scrolling the whole roster
  /// once the preview has named them.
  Future<void> _addEnemyManually() async {
    final state = AppScope.of(context);
    final preview = state.battle?.enemyPreview ?? const [];
    final seen = <String>{};
    final entries = <MapEntry<String, String>>[
      for (final slot in preview)
        if (seen.add(slot.speciesId))
          MapEntry(slot.speciesId, state.pack.speciesName(slot.speciesId)),
    ];
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No enemy team yet — scan or fill the Team Preview '
              'tab first.')));
      return;
    }
    final chosen = await showPickerDialog(context,
        title: 'Enemy Pokemon (from team preview)', entries: entries);
    if (chosen == null || !mounted) return;
    final st = AppScope.of(context);
    final battle = st.battle!;
    final existing =
        battle.enemies.where((e) => e.speciesId == chosen).firstOrNull;
    if (existing?.onField ?? false) return; // already out there
    final onField = battle.enemiesOnField;
    if (onField.length >= battle.format.fieldSlots) {
      // The field is full, so one of the shown two must be wrong — ask
      // which, then swap it out for the one just confirmed.
      final wrong = await showPickerDialog(context,
          title: 'Which one is NOT actually in battle?',
          entries: [
            for (final e in onField)
              MapEntry(e.speciesId, st.pack.speciesName(e.speciesId)),
          ]);
      if (wrong == null || !mounted) return;
      AppScope.of(context).mutateBattle(() {
        for (final e in battle.enemies) {
          if (e.speciesId == wrong) e.onField = false;
        }
        battle.addEnemy(chosen, onField: true);
      });
    } else {
      st.addEnemyManually(chosen);
    }
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
        const _AutoScanChip(),
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
                label: const Text('Manually scan'),
                onPressed:
                    _recognizing ? null : () => _scan(RecognitionScreen.preview),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The rig fills these boxes by itself while auto-scan is on; '
          'Manually scan opens the camera view (phone / gallery / rig) if '
          'you need to line something up. Tap any Pokemon for its full '
          'page. Amber boxes are guesses — tap to confirm or fix.',
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
        if (!battle.picksChosen)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'When you\'ve seen enough, head to the Battle tab to lock '
                  'in your ${battle.format.pickSize}.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  // -------------------------------------------------------- pick selection --

  /// Shown on the Battle tab until picks are locked (and when editing them):
  /// choose your 3/4 in send-out order, exactly like the game's selection
  /// step — but with the Team Preview scout one tab away.
  Widget _buildPickSelector(BuildContext context, AppState state) {
    final battle = state.battle!;
    final pickSize = battle.format.pickSize;
    final leads = battle.format.fieldSlots;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Select your $pickSize',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Tap in the order you\'d send them out — the first '
          '$leads lead${leads > 1 ? '' : 's'}. Check the Team Preview tab '
          'for their six before you commit.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < battle.team.builds.length; i++)
          _pickTile(context, state, i),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: Text('Lock in picks (${_pickOrder.length}/$pickSize)'),
          onPressed: _pickOrder.length == pickSize
              ? () {
                  state.setPicks(
                      [for (final i in _pickOrder) battle.team.builds[i]]);
                  setState(() => _editingPicks = false);
                }
              : null,
        ),
        if (battle.picksChosen)
          TextButton(
            onPressed: () => setState(() => _editingPicks = false),
            child: const Text('Cancel — keep current picks'),
          ),
      ],
    );
  }

  Widget _pickTile(BuildContext context, AppState state, int i) {
    final pack = state.pack;
    final battle = state.battle!;
    final build = battle.team.builds[i];
    final order = _pickOrder.indexOf(i);
    final selected = order >= 0;
    final isLead = selected && order < battle.format.fieldSlots;
    return Card(
      color: selected
          ? (isLead ? Colors.blue.shade50 : Colors.blue.shade50.withAlpha(120))
          : null,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: SpeciesIcon(build.speciesId, size: 36),
        title: Text(build.nickname ?? pack.speciesName(build.speciesId),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          build.moveIds.map(pack.moveName).join(', '),
          style: const TextStyle(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: selected
            ? CircleAvatar(
                radius: 14,
                backgroundColor:
                    isLead ? Colors.blue : Colors.blueGrey.shade300,
                child: Text(
                  isLead ? '${order + 1}★' : '${order + 1}',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              )
            : const Icon(Icons.radio_button_unchecked, size: 20),
        onTap: () => setState(() {
          if (selected) {
            _pickOrder.remove(i);
          } else if (_pickOrder.length < battle.format.pickSize) {
            _pickOrder.add(i);
          }
        }),
      ),
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
    // Picks are chosen HERE, after scouting Team Preview — game order.
    if (!battle.picksChosen || _editingPicks) {
      return _buildPickSelector(context, state);
    }
    final tiers = buildSpeedTiers(
        pack, battle.activeYours, battle.enemiesOnField,
        evidence: battle.speedEvidence);

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        const _AutoScanChip(),
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
                label: Text(_recognizing ? 'Recognizing…' : 'Manually scan'),
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

        if (tiers.isNotEmpty)
          _SpeedStrip(
            tiers: tiers,
            trickRoom: battle.trickRoom,
            yourTailwind: battle.yourTailwind,
            enemyTailwind: battle.enemyTailwind,
          ),
        const SizedBox(height: 10),

        // The arena: your four on the left (inside the box = on the
        // field), theirs on the right, back two predicted with "?" until
        // a swap-in proves them. Terrain/weather/Trick Room/Tailwind draw
        // straight onto the floor with their turns-left above.
        ArenaView(onAddEnemy: _addEnemyManually),

        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'Tap a Pokemon for its full card — its ↓ swaps it with '
                'another spot. Tap the line above the arena to fix field '
                'conditions.',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ),
            IconButton(
              tooltip: 'Change picks',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => setState(() {
                _pickOrder
                  ..clear()
                  ..addAll([
                    for (final p in battle.picks)
                      battle.team.builds.indexOf(p)
                  ].where((i) => i >= 0));
                _editingPicks = true;
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
  final bool trickRoom;
  final bool yourTailwind;
  final bool enemyTailwind;

  const _SpeedStrip({
    required this.tiers,
    this.trickRoom = false,
    this.yourTailwind = false,
    this.enemyTailwind = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Speed check (fastest first)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (trickRoom)
                  const _ConditionBadge('Trick Room', Colors.purple),
                if (yourTailwind)
                  const _ConditionBadge('Your Tailwind', Colors.blue),
                if (enemyTailwind)
                  const _ConditionBadge('Enemy Tailwind', Colors.red),
              ],
            ),
            if (trickRoom)
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text('Trick Room is up — the SLOWER Pokemon act first.',
                    style: TextStyle(fontSize: 10, color: Colors.purple)),
              ),
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
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: entry.orderConfirmed
                            ? 'Order confirmed this match (moved first/last '
                                'at the same move priority)'
                            : 'Predicted from stats and usage — not yet '
                                'seen in this match',
                        child: entry.orderConfirmed
                            ? const Icon(Icons.check_circle,
                                size: 14, color: confirmedColor)
                            : Text('?',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: predictedColor)),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '✓ = order confirmed by this match · ? = prediction',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConditionBadge extends StatelessWidget {
  final String label;
  final MaterialColor color;

  const _ConditionBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade300),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color.shade800)),
    );
  }
}

/// Status chip for the hands-free rig scanning: what it is doing, when it
/// last scanned, and a pause/resume toggle. Shows the reason when auto-scan
/// cannot run (engine, address, setting).
class _AutoScanChip extends StatelessWidget {
  const _AutoScanChip();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final controller = state.autoScan;
    if (controller == null) {
      final reason = state.autoScanUnavailableReason;
      if (reason == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.motion_photos_off,
                size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(reason,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ),
          ],
        ),
      );
    }
    return ValueListenableBuilder<AutoScanStatus>(
      valueListenable: controller.status,
      builder: (context, status, _) {
        final IconData icon;
        final Color color;
        final String text;
        if (status.paused) {
          icon = Icons.pause_circle_outline;
          color = Colors.grey;
          text = 'Auto-scan paused';
        } else if (!status.connected) {
          icon = Icons.wifi_tethering_error;
          color = Colors.orange;
          text = status.message.isEmpty
              ? 'Connecting to the rig…'
              : status.message;
        } else if (status.phase == AutoScanPhase.battle) {
          icon = Icons.radio_button_checked;
          color = confirmedColor;
          text = 'Tracking the match from the rig (2 scans/s) — names, '
              'moves, items, speed order';
        } else {
          icon = Icons.radio_button_checked;
          color = confirmedColor;
          text = 'Auto-scanning the rig every 5 s — the enemy boxes fill '
              'by themselves';
        }
        final last = status.lastScanAt;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: const TextStyle(fontSize: 11)),
                      if (last != null && !status.paused)
                        Text(
                          'scans: ${status.scans} · last '
                          '${last.hour.toString().padLeft(2, '0')}:'
                          '${last.minute.toString().padLeft(2, '0')}:'
                          '${last.second.toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: status.paused ? 'Resume auto-scan' : 'Pause auto-scan',
                  icon: Icon(
                      status.paused ? Icons.play_arrow : Icons.pause,
                      size: 18),
                  onPressed: () {
                    if (status.paused) {
                      controller.resume();
                    } else {
                      controller.pause('paused by you');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
