/// Saved match history for the active profile.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/match_record.dart';
import 'widgets.dart';

class MatchHistoryScreen extends StatelessWidget {
  const MatchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final matches = state.matches;
    return Scaffold(
      appBar: AppBar(title: const Text('Match history')),
      body: matches.isEmpty
          ? const Center(
              child: Text('No matches yet.\nFinish a battle and save it.',
                  textAlign: TextAlign.center),
            )
          : ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, i) => _MatchTile(record: matches[i]),
            ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  final MatchRecord record;

  const _MatchTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pack = state.pack;
    final date = record.date.length >= 16
        ? record.date.substring(0, 16).replaceFirst('T', ' ')
        : record.date;
    final (icon, color) = switch (record.result) {
      'win' => (Icons.emoji_events, Colors.green),
      'loss' => (Icons.close, Colors.red),
      _ => (Icons.help_outline, Colors.grey),
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text('${record.formatName} — ${record.result.toUpperCase()}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text('$date · ${record.teamName}',
            style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (record.enemySpeciesIds.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Enemy Pokemon seen',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final id in record.enemySpeciesIds)
                  Chip(
                    avatar: SpeciesIcon(id, size: 18),
                    label: Text(pack.speciesName(id),
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
              onPressed: () => state.deleteMatch(record),
            ),
          ),
        ],
      ),
    );
  }
}
