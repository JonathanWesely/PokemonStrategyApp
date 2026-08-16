/// Tap-for-details bottom sheets: what a move, ability, or item actually
/// does. Reachable from every predicted/confirmed row and chip.
library;

import 'package:flutter/material.dart';

import '../data/data_pack.dart';
import 'widgets.dart';

void showMoveInfo(BuildContext context, DataPack pack, String moveId) {
  final move = pack.moveById(moveId);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _InfoSheet(
      title: pack.moveName(moveId),
      chips: move == null
          ? const []
          : [
              TypeChip(move.type),
              _pill(context, move.category),
              _pill(context, move.power == null ? 'Power —' : 'Power ${move.power}'),
              _pill(context,
                  move.accuracy == null ? 'Never misses' : 'Acc ${move.accuracy}%'),
              if (move.priority != 0)
                _pill(context,
                    'Priority ${move.priority > 0 ? '+' : ''}${move.priority}'),
            ],
      body: move == null
          ? 'Not in the current data pack.'
          : (move.desc.isNotEmpty ? move.desc : move.note),
      footnote: move?.note.isNotEmpty == true && move?.desc.isNotEmpty == true
          ? move!.note
          : null,
    ),
  );
}

void showAbilityInfo(BuildContext context, DataPack pack, String abilityName) {
  final desc = pack.abilityDesc(abilityName);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _InfoSheet(
      title: abilityName,
      chips: const [],
      body: desc.isNotEmpty ? desc : 'No description in the current data pack.',
    ),
  );
}

void showItemInfo(BuildContext context, DataPack pack, String itemId) {
  final item = pack.itemById(itemId);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _InfoSheet(
      title: pack.itemName(itemId),
      chips: const [],
      body: item == null
          ? 'Not in the current data pack.'
          : (item.desc.isNotEmpty ? item.desc : 'No description available.'),
    ),
  );
}

Widget _pill(BuildContext context, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );

class _InfoSheet extends StatelessWidget {
  final String title;
  final List<Widget> chips;
  final String body;
  final String? footnote;

  const _InfoSheet(
      {required this.title,
      required this.chips,
      required this.body,
      this.footnote});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: chips),
          ],
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(fontSize: 14, height: 1.35)),
          if (footnote != null) ...[
            const SizedBox(height: 8),
            Text(footnote!,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600)),
          ],
        ],
      ),
    );
  }
}
