/// Team list + entry points to battle and settings.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/team.dart';
import 'battle_setup_screen.dart';
import 'settings_screen.dart';
import 'team_editor_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pokemon Strategy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.pack.usage.isPlaceholder)
            MaterialBanner(
              padding: const EdgeInsets.all(10),
              leading: const Icon(Icons.science_outlined),
              content: const Text(
                'Starter data pack — usage percentages are placeholders. '
                'Run tool/update_data.dart for real stats.',
                style: TextStyle(fontSize: 12),
              ),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: state.teams.isEmpty
                ? const Center(
                    child: Text('No teams yet.\nTap + to build your first team.',
                        textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    itemCount: state.teams.length,
                    itemBuilder: (context, i) =>
                        _TeamCard(team: state.teams[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TeamEditorScreen(team: Team(name: 'New Team')),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New team'),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final Team team;

  const _TeamCard({required this.team});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final members = team.builds
        .map((b) => state.pack.speciesName(b.speciesId))
        .join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(team.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          members.isEmpty ? 'Empty team' : members,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TeamEditorScreen(team: team.copy())),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Battle with this team',
              icon: const Icon(Icons.sports_kabaddi),
              onPressed: team.builds.isEmpty
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => BattleSetupScreen(team: team)),
                      ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'duplicate') {
                  final copy = team.copy()
                    ..id = null
                    ..name = '${team.name} (copy)';
                  await state.saveTeam(copy);
                } else if (value == 'delete') {
                  await state.deleteTeam(team);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
