/// The Battle tab's arena: a small drawn battlefield instead of a card
/// list. Your four picks sit on the left (two inside the arena = on the
/// field, two outside = reserves), the enemy's four mirror them on the
/// right — revealed enemies confirmed, the back two predicted with "?"
/// until a swap-in proves them. The arena box itself carries the field
/// state: terrain squiggles run bottom-left to top-right in the terrain's
/// colour, weather squiggles bottom-right to top-left, Trick Room draws a
/// second outline, Tailwind lays white wind lines over its side. Above
/// the box every active condition shows its turns left, with a "?" when
/// an extender item can't be ruled out.
///
/// Tap any Pokemon for its full intel card (the same card as before) —
/// tap anywhere blank on the card to come back, or its ↓ to swap it with
/// another spot on its side. Tap the condition labels to correct or set
/// conditions by hand (the text tracker fills them in automatically when
/// a scan catches the message).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/battle_state.dart';
import '../models/prediction.dart';
import '../prediction/prediction_engine.dart';
import '../prediction/speed_tiers.dart';
import 'intel_card.dart';
import 'species_detail_sheet.dart';
import 'widgets.dart';

class ArenaView extends StatelessWidget {
  /// The Battle tab's "+ Enemy" flow — reused when an empty enemy field
  /// slot is tapped.
  final VoidCallback onAddEnemy;

  const ArenaView({super.key, required this.onAddEnemy});

  // ------------------------------------------------------------- labels --

  static String conditionName(String kind) => switch (kind) {
        'grassy' => 'Grassy Terrain',
        'misty' => 'Misty Terrain',
        'psychic' => 'Psychic Terrain',
        'electric' => 'Electric Terrain',
        'snow' => 'Snow',
        'rain' => 'Rain',
        'sun' => 'Harsh Sunlight',
        'sandstorm' => 'Sandstorm',
        'trickroom' => 'Trick Room',
        _ => kind,
      };

  static Color? terrainColor(String? kind) => switch (kind) {
        'grassy' => Colors.green.shade600,
        'misty' => Colors.blue.shade400,
        'psychic' => Colors.purple.shade400,
        'electric' => Colors.amber.shade700,
        _ => null,
      };

  static Color? weatherColor(String? kind) => switch (kind) {
        'snow' => Colors.lightBlue.shade200,
        'rain' => Colors.blue.shade900,
        'sun' => Colors.red.shade400,
        'sandstorm' => Colors.brown.shade400,
        _ => null,
      };

  static String _turnsLabel(TimedCondition c) {
    final q = c.uncertain ? '?' : '';
    final t = c.turnsLeft;
    if (t == null) return '${conditionName(c.kind)} — up$q';
    return '${conditionName(c.kind)} — $t turn${t == 1 ? '' : 's'} left$q';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pack = state.pack;
    final battle = state.battle!;

    // ---- spots ----
    final activePos = [
      for (var i = 0; i < battle.picks.length; i++)
        if (battle.activePickIndexes.contains(i)) i
    ];
    final reservePos = [
      for (var i = 0; i < battle.picks.length; i++)
        if (!battle.activePickIndexes.contains(i)) i
    ];
    final activeEnemies = battle.enemiesOnField;
    final benchEnemies = battle.enemyBench;
    final knownIds = {for (final e in battle.enemies) e.speciesId};
    final predicted = PredictionEngine(pack)
        .predictBench(battle)
        .where((o) => !knownIds.contains(o.id))
        .take((battle.enemyReserveCount - benchEnemies.length)
            .clamp(0, battle.enemyReserveCount))
        .toList();

    // ---- turn-order ranks over all eight (acting order: under Trick
    // Room the slowest acts first, so the list flips) ----
    final phantoms = [
      for (final o in predicted) EnemyPokemon(speciesId: o.id, onField: false)
    ];
    final tiers = buildSpeedTiers(
        pack, battle.picks, [...battle.enemies, ...phantoms],
        evidence: battle.speedEvidence);
    final ordered = battle.trickRoom ? tiers.reversed.toList() : tiers;
    final rankOf = <String, String>{};
    for (var i = 0; i < ordered.length; i++) {
      rankOf.putIfAbsent(ordered[i].key,
          () => '${i + 1}${ordered[i].orderConfirmed ? '' : '?'}');
    }

    Widget tileFor({
      String? speciesId,
      required String label,
      bool predictedStyle = false,
      String? rankKey,
      VoidCallback? onTap,
    }) {
      return _ArenaTile(
        speciesId: speciesId,
        label: label,
        predicted: predictedStyle,
        rankText: rankKey == null ? null : rankOf[rankKey],
        onTap: onTap,
      );
    }

    final yourActiveTiles = <Widget>[
      for (final pos in activePos)
        tileFor(
          speciesId: battle.picks[pos].speciesId,
          label: battle.picks[pos].nickname ??
              pack.speciesName(battle.picks[pos].speciesId),
          rankKey: 'y:${battle.picks[pos].speciesId}',
          onTap: () => _openYourCard(context, state, pos),
        ),
      for (var i = activePos.length; i < battle.format.fieldSlots; i++)
        tileFor(label: 'empty'),
    ];
    final yourReserveTiles = <Widget>[
      for (final pos in reservePos)
        tileFor(
          speciesId: battle.picks[pos].speciesId,
          label: battle.picks[pos].nickname ??
              pack.speciesName(battle.picks[pos].speciesId),
          rankKey: 'y:${battle.picks[pos].speciesId}',
          onTap: () => _openYourCard(context, state, pos),
        ),
    ];
    final enemyActiveTiles = <Widget>[
      for (final e in activeEnemies)
        tileFor(
          speciesId: e.speciesId,
          label: pack.speciesName(e.speciesId),
          rankKey: 'e:${e.speciesId}',
          onTap: () => _openEnemyCard(context, state, e),
        ),
      for (var i = activeEnemies.length; i < battle.format.fieldSlots; i++)
        tileFor(label: 'add…', onTap: onAddEnemy),
    ];
    final enemyReserveTiles = <Widget>[
      for (final e in benchEnemies)
        tileFor(
          speciesId: e.speciesId,
          label: pack.speciesName(e.speciesId),
          rankKey: 'e:${e.speciesId}',
          onTap: () => _openEnemyCard(context, state, e),
        ),
      for (final o in predicted)
        tileFor(
          speciesId: o.id,
          label: '${o.label}?',
          predictedStyle: true,
          rankKey: 'e:${o.id}',
          onTap: () => showSpeciesDetail(context,
              speciesId: o.id, showPredictions: true),
        ),
      for (var i = benchEnemies.length + predicted.length;
          i < battle.enemyReserveCount;
          i++)
        tileFor(label: '?'),
    ];

    // ---- active conditions above the arena ----
    final conditions = <(TimedCondition, Color)>[
      if (battle.terrain != null)
        (battle.terrain!, terrainColor(battle.terrain!.kind) ?? Colors.green),
      if (battle.weather != null)
        (battle.weather!, weatherColor(battle.weather!.kind) ?? Colors.blue),
      if (battle.trickRoomCond != null)
        (battle.trickRoomCond!, Colors.purple),
    ];
    final tailwinds = <(String, TimedCondition)>[
      if (battle.yourTailwindCond != null)
        ('Your Tailwind', battle.yourTailwindCond!),
      if (battle.enemyTailwindCond != null)
        ('Enemy Tailwind', battle.enemyTailwindCond!),
    ];

    const arenaHeight = 212.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _editConditions(context, state),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: (conditions.isEmpty && tailwinds.isEmpty)
                ? Text('No field conditions — tap to set',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500))
                : Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      for (final (c, color) in conditions)
                        Text(_turnsLabel(c),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: color)),
                      for (final (label, c) in tailwinds)
                        Text(
                            '$label — ${c.turnsLeft ?? "?"} '
                            'turn${c.turnsLeft == 1 ? '' : 's'} left'
                            '${c.uncertain ? '?' : ''}',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey.shade600)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: arenaHeight,
          child: Row(
            children: [
              SizedBox(
                width: 66,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: yourReserveTiles,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _ArenaPainter(
                        terrain: terrainColor(battle.terrain?.kind),
                        weather: weatherColor(battle.weather?.kind),
                        trickRoom: battle.trickRoom,
                        yourTailwind: battle.yourTailwind,
                        enemyTailwind: battle.enemyTailwind,
                        borderColor: Colors.grey.shade600,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: yourActiveTiles,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: enemyActiveTiles,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 66,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: enemyReserveTiles,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ overlays --

  void _openYourCard(BuildContext context, AppState state, int pos) {
    final battle = state.battle!;
    final build = battle.picks[pos];
    _showCardSheet(
      context,
      (sheetContext) => YourIntelCard(
        pokemonBuild: build,
        onSwapRequest: () {
          Navigator.pop(sheetContext);
          _swapYourDialog(context, state, pos);
        },
      ),
    );
  }

  void _openEnemyCard(BuildContext context, AppState state, EnemyPokemon e) {
    _showCardSheet(
      context,
      (sheetContext) => EnemyIntelCard(
        enemy: e,
        onSwapRequest: () {
          Navigator.pop(sheetContext);
          _swapEnemyDialog(context, state, e);
        },
      ),
    );
  }

  /// The detail overlay: the full intel card in a tall sheet. A tap on
  /// anything non-interactive (or the barrier, or a swipe down) returns
  /// to the arena; taps on rows/buttons inside still do their jobs.
  void _showCardSheet(
      BuildContext context, Widget Function(BuildContext) cardBuilder) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => Navigator.pop(sheetContext),
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
            child: cardBuilder(sheetContext),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- swaps --

  Future<void> _swapYourDialog(
      BuildContext context, AppState state, int pos) async {
    final battle = state.battle!;
    final pack = state.pack;
    final name = battle.picks[pos].nickname ??
        pack.speciesName(battle.picks[pos].speciesId);
    String spotLabel(int i) {
      final n = battle.picks[i].nickname ??
          pack.speciesName(battle.picks[i].speciesId);
      final zone =
          battle.activePickIndexes.contains(i) ? 'on the field' : 'reserve';
      return '$n — $zone';
    }

    final entries = <MapEntry<String, String>>[
      for (var i = 0; i < battle.picks.length; i++)
        if (i != pos) MapEntry('$i', spotLabel(i)),
    ];
    final chosen = await showPickerDialog(context,
        title: 'Swap $name with…', entries: entries);
    if (chosen == null) return;
    state.mutateBattle(
        () => battle.swapPickPositions(pos, int.parse(chosen)));
  }

  Future<void> _swapEnemyDialog(
      BuildContext context, AppState state, EnemyPokemon e) async {
    final battle = state.battle!;
    final pack = state.pack;
    final knownIds = {for (final en in battle.enemies) en.speciesId};
    final predicted = e.onField
        ? PredictionEngine(pack)
            .predictBench(battle)
            .where((o) => !knownIds.contains(o.id))
            .take(2)
            .toList()
        : const <RatedOption>[];
    final entries = <MapEntry<String, String>>[
      for (var i = 0; i < battle.enemies.length; i++)
        if (battle.enemies[i] != e)
          MapEntry(
              'e$i',
              '${pack.speciesName(battle.enemies[i].speciesId)} — '
              '${battle.enemies[i].onField ? 'on the field' : 'reserve'}'),
      for (final o in predicted)
        MapEntry('p${o.id}', '${o.label}? — predicted reserve'),
    ];
    if (entries.isEmpty) return;
    final chosen = await showPickerDialog(context,
        title: 'Swap ${pack.speciesName(e.speciesId)} with…',
        entries: entries);
    if (chosen == null) return;
    state.mutateBattle(() {
      if (chosen.startsWith('e')) {
        final other = battle.enemies[int.parse(chosen.substring(1))];
        if (other.onField != e.onField) {
          final t = other.onField;
          other.onField = e.onField;
          e.onField = t;
        } else {
          // Same zone: just trade display positions.
          final i = battle.enemies.indexOf(e);
          final j = battle.enemies.indexOf(other);
          battle.enemies[i] = other;
          battle.enemies[j] = e;
        }
      } else {
        // A predicted reserve turned out to be on the field instead.
        e.onField = false;
        battle.addEnemy(chosen.substring(1), onField: true);
      }
    });
  }

  // -------------------------------------------------- condition editing --

  void _editConditions(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          final battle = state.battle!;
          void mut(void Function() fn) {
            state.mutateBattle(fn);
            setSheet(() {});
          }

          Widget turnsRow(TimedCondition c) {
            return Row(
              children: [
                const SizedBox(width: 12),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  onPressed: () => mut(() => c.turnsLeft =
                      ((c.turnsLeft ?? 5) - 1).clamp(0, 8)),
                ),
                Text('${c.turnsLeft ?? "?"} turns left',
                    style: const TextStyle(fontSize: 12)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  onPressed: () => mut(() => c.turnsLeft =
                      ((c.turnsLeft ?? 5) + 1).clamp(0, 8)),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('? uncertain',
                      style: TextStyle(fontSize: 11)),
                  selected: c.uncertain,
                  onSelected: (v) => mut(() => c.uncertain = v),
                ),
              ],
            );
          }

          Widget kindPicker({
            required String title,
            required List<String> kinds,
            required TimedCondition? current,
            required void Function(TimedCondition?) assign,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label:
                          const Text('None', style: TextStyle(fontSize: 11)),
                      selected: current == null,
                      onSelected: (_) => mut(() => assign(null)),
                    ),
                    for (final k in kinds)
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(conditionName(k),
                            style: const TextStyle(fontSize: 11)),
                        selected: current?.kind == k,
                        onSelected: (_) => mut(() =>
                            assign(TimedCondition(k, turnsLeft: 5))),
                      ),
                  ],
                ),
                if (current != null) turnsRow(current),
                const SizedBox(height: 8),
              ],
            );
          }

          Widget toggle({
            required String title,
            required TimedCondition? current,
            required void Function(TimedCondition?) assign,
            required int defaultTurns,
          }) {
            return Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(title, style: const TextStyle(fontSize: 13)),
                  value: current != null,
                  onChanged: (v) => mut(() => assign(v
                      ? TimedCondition('tailwind',
                          turnsLeft: defaultTurns, uncertain: false)
                      : null)),
                ),
                if (current != null) turnsRow(current),
              ],
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Field conditions',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'The tracker sets these itself when a scan catches the '
                    'message — fix or add anything it missed here. "?" '
                    'means an extender item can\'t be ruled out.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  kindPicker(
                    title: 'Terrain',
                    kinds: const ['grassy', 'misty', 'psychic', 'electric'],
                    current: battle.terrain,
                    assign: (c) => battle.terrain = c,
                  ),
                  kindPicker(
                    title: 'Weather',
                    kinds: const ['snow', 'rain', 'sun', 'sandstorm'],
                    current: battle.weather,
                    assign: (c) => battle.weather = c,
                  ),
                  Column(
                    children: [
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Trick Room',
                            style: TextStyle(fontSize: 13)),
                        value: battle.trickRoomCond != null,
                        onChanged: (v) => mut(() => battle.trickRoomCond = v
                            ? TimedCondition('trickroom',
                                turnsLeft: 5, uncertain: false)
                            : null),
                      ),
                      if (battle.trickRoomCond != null)
                        turnsRow(battle.trickRoomCond!),
                    ],
                  ),
                  toggle(
                    title: 'Your Tailwind',
                    current: battle.yourTailwindCond,
                    assign: (c) => battle.yourTailwindCond = c,
                    defaultTurns: 4,
                  ),
                  toggle(
                    title: 'Enemy Tailwind',
                    current: battle.enemyTailwindCond,
                    assign: (c) => battle.enemyTailwindCond = c,
                    defaultTurns: 4,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One Pokemon spot: sprite, name under it, predicted turn-order badge in
/// the top-right corner ("2" = second to act at equal move priority,
/// "2?" = predicted rather than confirmed). Amber italic + "?" label =
/// a predicted enemy reserve.
class _ArenaTile extends StatelessWidget {
  final String? speciesId;
  final String label;
  final bool predicted;
  final String? rankText;
  final VoidCallback? onTap;

  const _ArenaTile({
    required this.speciesId,
    required this.label,
    required this.predicted,
    required this.rankText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final confirmedRank = rankText != null && !rankText!.endsWith('?');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                speciesId == null
                    ? Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Icon(
                            onTap == null ? Icons.help_outline : Icons.add,
                            size: 18,
                            color: Colors.grey.shade500),
                      )
                    : SpeciesIcon(speciesId!, size: 42),
                if (rankText != null)
                  Positioned(
                    top: -5,
                    right: -9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: confirmedRank
                                ? confirmedColor
                                : predictedColor),
                      ),
                      child: Text(rankText!,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: confirmedRank
                                  ? confirmedColor
                                  : predictedColor)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: 62,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  fontStyle: predicted ? FontStyle.italic : FontStyle.normal,
                  color: predicted ? predictedColor : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the arena floor: border, centre line and circle; terrain
/// squiggles bottom-left→top-right, weather squiggles bottom-right→
/// top-left, a second outline for Trick Room, white wind lines over the
/// half that has Tailwind.
class _ArenaPainter extends CustomPainter {
  final Color? terrain;
  final Color? weather;
  final bool trickRoom;
  final bool yourTailwind;
  final bool enemyTailwind;
  final Color borderColor;

  const _ArenaPainter({
    required this.terrain,
    required this.weather,
    required this.trickRoom,
    required this.yourTailwind,
    required this.enemyTailwind,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    if (terrain != null) _squiggles(canvas, size, terrain!, upRight: true);
    if (weather != null) _squiggles(canvas, size, weather!, upRight: false);
    if (yourTailwind) {
      _windLines(
          canvas, Rect.fromLTWH(0, 0, size.width / 2, size.height));
    }
    if (enemyTailwind) {
      _windLines(canvas,
          Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height));
    }
    canvas.restore();

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = borderColor;
    canvas.drawRect(rect.deflate(1), border);
    canvas.drawLine(Offset(size.width / 2, 1),
        Offset(size.width / 2, size.height - 1), border);
    canvas.drawOval(
        Rect.fromCenter(center: rect.center, width: 42, height: 26), border);
    if (trickRoom) {
      final tr = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.purple;
      canvas.drawRect(rect.deflate(5), tr);
    }
  }

  /// Diagonal wavy lines covering the whole box. [upRight] = from the
  /// bottom-left toward the top-right (terrain); false = from the
  /// bottom-right toward the top-left (weather).
  void _squiggles(Canvas canvas, Size size, Color color,
      {required bool upRight}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withAlpha(150);
    final w = size.width, h = size.height;
    const spacing = 15.0;
    for (var c = -h; c < w + h; c += spacing) {
      final path = Path();
      var started = false;
      for (var t = 0.0; t <= h; t += 5) {
        final wob = math.sin(t / 6.5) * 2.6;
        final double x, y;
        if (upRight) {
          x = c + t + wob * 0.707;
          y = (h - t) + wob * 0.707;
        } else {
          x = (w - c) - t + wob * 0.707;
          y = (h - t) - wob * 0.707;
        }
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  /// Horizontal white wind lines (with a soft grey halo so they read on
  /// the light background) over one side's half of the arena.
  void _windLines(Canvas canvas, Rect r) {
    final halo = Paint()
      ..strokeWidth = 3.2
      ..color = Colors.grey.withAlpha(110);
    final line = Paint()
      ..strokeWidth = 1.6
      ..color = Colors.white;
    for (var y = r.top + 16.0; y < r.bottom - 8; y += 22) {
      canvas.drawLine(Offset(r.left + 10, y), Offset(r.right - 10, y), halo);
      canvas.drawLine(Offset(r.left + 10, y), Offset(r.right - 10, y), line);
    }
  }

  @override
  bool shouldRepaint(_ArenaPainter old) =>
      old.terrain != terrain ||
      old.weather != weather ||
      old.trickRoom != trickRoom ||
      old.yourTailwind != yourTailwind ||
      old.enemyTailwind != enemyTailwind;
}
