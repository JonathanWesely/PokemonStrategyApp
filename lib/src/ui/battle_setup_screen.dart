/// Pick a format (as the game presents them) and your 3-of-6 / 4-of-6.
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
  final Set<int> _pickedIndexes = {};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final format = _format ?? state.pack.formats.first;
    final pickSize = format.pickSize;

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
              _pickedIndexes.clear();
            }),
          ),
          const SizedBox(height: 8),
          Text(
            '${format.style == 'doubles' ? 'Doubles' : 'Singles'} · '
            'bring ${format.teamSize}, pick $pickSize · level ${format.level}'
            '${format.itemClause ? ' · item clause' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          Text('Select your $pickSize (team preview order matters — pick '
              'leads first):'),
          const SizedBox(height: 8),
          for (var i = 0; i < widget.team.builds.length; i++)
            CheckboxListTile(
              value: _pickedIndexes.contains(i),
              title: Text(widget.team.builds[i].nickname ??
                  state.pack.speciesName(widget.team.builds[i].speciesId)),
              subtitle: Text(
                widget.team.builds[i].moveIds
                    .map(state.pack.moveName)
                    .join(', '),
                style: const TextStyle(fontSize: 11),
              ),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  if (_pickedIndexes.length < pickSize) _pickedIndexes.add(i);
                } else {
                  _pickedIndexes.remove(i);
                }
              }),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text('Start battle (${_pickedIndexes.length}/$pickSize)'),
            onPressed: _pickedIndexes.length == pickSize
                ? () {
                    final picks = _pickedIndexes.toList()..sort();
                    state.startBattle(
                      format,
                      widget.team,
                      [for (final i in picks) widget.team.builds[i]],
                    );
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const BattleScreen()),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
