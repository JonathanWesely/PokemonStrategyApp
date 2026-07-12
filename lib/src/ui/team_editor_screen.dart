/// Edit a team: name, six slots, legality lint against the ranked format.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/legality.dart';
import '../models/team.dart';
import 'build_editor_screen.dart';
import 'widgets.dart';

class TeamEditorScreen extends StatefulWidget {
  final Team team;

  const TeamEditorScreen({super.key, required this.team});

  @override
  State<TeamEditorScreen> createState() => _TeamEditorScreenState();
}

class _TeamEditorScreenState extends State<TeamEditorScreen> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.team.name);

  Future<void> _save() async {
    final state = AppScope.of(context);
    widget.team.name = _nameController.text.trim().isEmpty
        ? 'Unnamed team'
        : _nameController.text.trim();
    await state.saveTeam(widget.team);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final ranked = state.pack.formats.firstWhere(
      (f) => f.legalityChecked,
      orElse: () => state.pack.formats.first,
    );
    final issues = lintTeam(widget.team, ranked, state.pack);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit team'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Team name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (issues.isNotEmpty)
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Legality check (${ranked.name})',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 4),
                    for (final issue in issues)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• ${issue.message}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          for (var i = 0; i < teamSize; i++) _slotTile(context, i),
        ],
      ),
    );
  }

  Widget _slotTile(BuildContext context, int index) {
    final state = AppScope.of(context);
    final build =
        index < widget.team.builds.length ? widget.team.builds[index] : null;
    final species =
        build == null ? null : state.pack.speciesById(build.speciesId);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: build == null
            ? const Text('Empty slot',
                style: TextStyle(fontStyle: FontStyle.italic))
            : Text(build.nickname ?? species?.name ?? build.speciesId,
                style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: build == null || species == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 4, children: [
                    for (final t in species.typesFor(build.megaFormeId))
                      TypeChip(t, small: true),
                  ]),
                  Text(
                    '${build.nature} · ${state.pack.itemName(build.itemId)} · '
                    '${build.moveIds.map(state.pack.moveName).join(", ")}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
        trailing: build == null
            ? const Icon(Icons.add)
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    setState(() => widget.team.builds.removeAt(index)),
              ),
        onTap: () async {
          final edited = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BuildEditorScreen(existing: build?.copy()),
            ),
          );
          if (edited != null) {
            setState(() {
              if (build == null) {
                widget.team.builds.add(edited);
              } else {
                widget.team.builds[index] = edited;
              }
            });
          }
        },
      ),
    );
  }
}
