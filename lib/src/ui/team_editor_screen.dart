/// Edit a team: name, six slots, legality lint against the ranked format.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/legality.dart';
import '../models/team.dart';
import '../recognition/team_scanner.dart';
import 'build_editor_screen.dart';
import 'scan_team_screen.dart';
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

  /// Fill this team from the two Champions team-display images. The result
  /// REPLACES the current slots; anything uncertain arrives as a warning
  /// dialog plus per-slot notes.
  Future<void> _scanTeam() async {
    final scanned = await Navigator.push<ScannedTeam>(
      context,
      MaterialPageRoute(builder: (_) => const ScanTeamScreen()),
    );
    if (scanned == null || !mounted) return;
    setState(() {
      if (scanned.team.name != 'Scanned team') {
        _nameController.text = scanned.team.name;
      }
      widget.team.builds
        ..clear()
        ..addAll(scanned.team.builds);
    });
    final warnings = scanned.allWarnings;
    if (warnings.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Check these before saving'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $w', style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Got it')),
          ],
        ),
      );
    }
  }

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
          OutlinedButton.icon(
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan team from Champions (2 photos)'),
            onPressed: _scanTeam,
          ),
          const SizedBox(height: 8),
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
                    '${build.gender == 'male' ? '♂ ' : build.gender == 'female' ? '♀ ' : ''}'
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
