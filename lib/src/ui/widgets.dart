/// Small shared UI pieces: type chips, usage bars, matchup groups.
library;

import 'package:flutter/material.dart';

import '../models/prediction.dart';
import '../models/species.dart';

const typeColors = <String, Color>{
  'Normal': Color(0xFFA8A77A),
  'Fire': Color(0xFFEE8130),
  'Water': Color(0xFF6390F0),
  'Electric': Color(0xFFF7D02C),
  'Grass': Color(0xFF7AC74C),
  'Ice': Color(0xFF96D9D6),
  'Fighting': Color(0xFFC22E28),
  'Poison': Color(0xFFA33EA1),
  'Ground': Color(0xFFE2BF65),
  'Flying': Color(0xFFA98FF3),
  'Psychic': Color(0xFFF95587),
  'Bug': Color(0xFFA6B91A),
  'Rock': Color(0xFFB6A136),
  'Ghost': Color(0xFF735797),
  'Dragon': Color(0xFF6F35FC),
  'Dark': Color(0xFF705746),
  'Steel': Color(0xFFB7B7CE),
  'Fairy': Color(0xFFD685AD),
};

class TypeChip extends StatelessWidget {
  final String type;
  final bool small;

  const TypeChip(this.type, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = typeColors[type] ?? Colors.grey;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// "x4 / x2 / x1/2 / x1/4 / immune" groups of a defensive profile.
class MatchupGroups extends StatelessWidget {
  /// attackType -> multiplier.
  final Map<String, double> profile;

  const MatchupGroups({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<String>>{};
    profile.forEach((type, mult) {
      final key = switch (mult) {
        >= 3.9 => 'Weak x4',
        > 1.0 => 'Weak x2',
        0.0 => 'Immune',
        < 0.26 => 'Resist x1/4',
        < 1.0 => 'Resist x1/2',
        _ => '',
      };
      if (key.isNotEmpty) groups.putIfAbsent(key, () => []).add(type);
    });

    const order = ['Weak x4', 'Weak x2', 'Resist x1/2', 'Resist x1/4', 'Immune'];
    final rows = [
      for (final label in order)
        if (groups.containsKey(label))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 78,
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: label.startsWith('Weak')
                            ? Colors.red.shade700
                            : label == 'Immune'
                                ? Colors.blueGrey
                                : Colors.green.shade700,
                      )),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: [
                      for (final t in groups[label]!) TypeChip(t, small: true)
                    ],
                  ),
                ),
              ],
            ),
          ),
    ];

    if (rows.isEmpty) {
      return const Text('No weaknesses or resistances',
          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic));
    }
    return Column(children: rows);
  }
}

/// Color language shared across the app:
///   green = confirmed (seen in this battle) · amber = predicted (usage data)
///   grey = unknown / no data.
const confirmedColor = Colors.green;
final predictedColor = Colors.amber.shade800;

/// A predicted-or-confirmed option row: label, usage bar, percent, confirm
/// state, and an info tap for what the move/ability/item does.
class RatedOptionRow extends StatelessWidget {
  final RatedOption option;
  final String? subtitle;
  final VoidCallback? onConfirm;

  /// Opens the detail sheet for this option.
  final VoidCallback? onInfo;
  final bool dim;

  const RatedOptionRow({
    super.key,
    required this.option,
    this.subtitle,
    this.onConfirm,
    this.onInfo,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    // The ✓ / ? convention: ✓ = confirmed in this match, ? = prediction.
    final pctText =
        option.confirmed ? 'seen ✓' : '~${option.pct.toStringAsFixed(0)}% ?';
    final barColor = option.confirmed
        ? confirmedColor
        : dim
            ? Colors.grey.shade400
            : predictedColor;
    return InkWell(
      onTap: onConfirm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(
              option.confirmed
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 16,
              color: option.confirmed ? confirmedColor : Colors.grey.shade400,
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: option.confirmed
                            ? FontWeight.w700
                            : FontWeight.w400,
                        fontStyle:
                            option.confirmed ? null : FontStyle.italic,
                        color: dim
                            ? Colors.grey
                            : option.confirmed
                                ? null
                                : predictedColor,
                      )),
                  if (subtitle != null)
                    Text(subtitle!,
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (option.confirmed ? 100 : option.pct) / 100,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: barColor,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(pctText,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11)),
            ),
            if (onInfo != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(Icons.info_outline,
                    size: 15, color: Colors.grey.shade500),
                onPressed: onInfo,
              ),
          ],
        ),
      ),
    );
  }
}

/// Bundled 2D sprite for a species, with a graceful fallback icon.
class SpeciesIcon extends StatelessWidget {
  final String speciesId;
  final double size;

  const SpeciesIcon(this.speciesId, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/sprites/home/$speciesId.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Icon(Icons.catching_pokemon,
          size: size * 0.8, color: Colors.grey.shade400),
    );
  }
}

/// Raw base-stat readout (the species line, before SP/nature). Pure fact —
/// safe to show for any Pokemon, no prediction involved.
class BaseStatsRow extends StatelessWidget {
  final BaseStats base;

  const BaseStatsRow(this.base, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final key in statKeys)
          Expanded(
            child: Column(
              children: [
                Text(statLabels[key] ?? key,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600)),
                Text('${base.byKey(key)}',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }
}

/// One "fill in the blank" slot for the facts-only enemy card: shows a
/// revealed fact (green check) or a "?" you tap to reveal / correct.
class RevealSlotRow extends StatelessWidget {
  /// The revealed label, or null while still unknown.
  final String? label;
  final String? subtitle;

  /// Hint shown on the right while unknown (e.g. 'tap to set move').
  final String hint;
  final VoidCallback onTap;
  final Widget? leadingChip;

  const RevealSlotRow({
    super.key,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.hint = 'tap to reveal',
    this.leadingChip,
  });

  @override
  Widget build(BuildContext context) {
    final known = label != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(known ? Icons.check_circle : Icons.help_outline,
                size: 16, color: known ? Colors.green : Colors.grey.shade400),
            const SizedBox(width: 6),
            if (known && leadingChip != null) ...[
              leadingChip!,
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(known ? label! : '?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: known ? FontWeight.w700 : FontWeight.w400,
                        color: known ? null : Colors.grey,
                      )),
                  if (known && subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Text(known ? 'seen' : hint,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

/// A simple scrollable single-choice picker. Returns the chosen id, or null if
/// dismissed. Shared by enemy-species entry and the reveal-slot pickers.
Future<String?> showPickerDialog(
  BuildContext context, {
  required String title,
  required List<MapEntry<String, String>> entries,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final e in entries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, e.key),
            child: Text(e.value),
          ),
      ],
    ),
  );
}
