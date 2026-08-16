/// Pick a format (as the game presents them) and jump in. Your 3-of-6 /
/// 4-of-6 selection happens INSIDE the battle, on the Battle tab, after
/// you've scouted the enemy on Team Preview — same order as the real game.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/regulation.dart';
import '../models/team.dart';
import 'battle_screen.dart';

class BattleSetupScreen extends StatefulWidget {
  final Team team;

  const BattleSetupScreen({super.key, required this.team});

  @override
  State<BattleSetupScreen> createState() => _BattleSetupScreenState();
}

class _BattleSetupScreenState extends State<BattleSetupScreen> {
  FormatSpec? _format;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final format = _format ?? state.pack.formats.first;

    return Scaffold(
      appBar: AppBar(title: Text('Battle · ${widget.team.name}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          DropdownButtonFormField<String>(
            initialValue: format.id,
            decoration: const InputDecoration(
              labelText: 'Format',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final f in state.pack.formats)
                DropdownMenuItem(value: f.id, child: Text(f.name)),
            ],
            onChanged: (id) => setState(() {
              _format = state.pack.formatById(id ?? '');
            }),
          ),
          const SizedBox(height: 8),
          Text(
            '${format.style == 'doubles' ? 'Doubles' : 'Singles'} · '
            'bring ${format.teamSize}, pick ${format.pickSize} · '
            'level ${format.level}'
            '${format.itemClause ? ' · item clause' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'The battle opens on Team Preview — scout the enemy six '
                'first, then lock in your ${format.pickSize} on the Battle '
                'tab. Exactly like at the real team-preview screen.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start battle'),
            onPressed: () {
              state.startBattle(format, widget.team);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const BattleScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
