/// Team list + entry points to battle, match history, profile, settings.
/// First launch asks for an account name (local profile — no server).
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/team.dart';
import 'battle_setup_screen.dart';
import 'match_history_screen.dart';
import 'settings_screen.dart';
import 'team_editor_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _onboardingShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!state.onboarded && !_onboardingShown) {
      _onboardingShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askName(state));
    }
  }

  Future<void> _askName(AppState state) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Welcome, trainer!'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Your name',
            helperText: 'Creates your local account — teams and match '
                'history are saved under it, on this device only.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    await state.completeOnboarding(name ?? '');
  }

  Future<void> _profileMenu(AppState state) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in state.profiles)
              ListTile(
                leading: Icon(
                  p.id == state.activeProfileId
                      ? Icons.account_circle
                      : Icons.account_circle_outlined,
                  color: p.id == state.activeProfileId
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(p.name),
                trailing:
                    p.id == state.activeProfileId ? const Text('active') : null,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await state.switchProfile(p.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('New account'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _createProfile(state);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename this account'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _renameProfile(state);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createProfile(AppState state) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New account'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await state.createProfile(name.trim());
    }
  }

  Future<void> _renameProfile(AppState state) async {
    final controller =
        TextEditingController(text: state.activeProfile?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename account'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await state.renameActiveProfile(name.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pokemon Strategy'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.account_circle, size: 18),
            label: Text(state.activeProfile?.name ?? '…',
                style: const TextStyle(fontSize: 12)),
            onPressed: () => _profileMenu(state),
          ),
          IconButton(
            tooltip: 'Match history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MatchHistoryScreen()),
            ),
          ),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(team.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: team.builds.isEmpty
            ? const Text('Empty team', style: TextStyle(fontSize: 12))
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    for (final b in team.builds.take(6))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: SpeciesIcon(b.speciesId, size: 28),
                      ),
                  ],
                ),
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
