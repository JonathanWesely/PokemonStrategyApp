/// Configure one Pokemon: species, moves, ability, item, nature, SP spread
/// (66-point allocator with live stat readout), and Mega forme.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/stat_calculator.dart';
import '../models/nature.dart';
import '../models/pokemon_build.dart';
import '../models/species.dart';
import 'widgets.dart';

class BuildEditorScreen extends StatefulWidget {
  final PokemonBuild? existing;

  const BuildEditorScreen({super.key, this.existing});

  @override
  State<BuildEditorScreen> createState() => _BuildEditorScreenState();
}

class _BuildEditorScreenState extends State<BuildEditorScreen> {
  PokemonBuild? _build;
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _build = widget.existing;
    _nicknameController =
        TextEditingController(text: widget.existing?.nickname ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final build = _build;
    final species =
        build == null ? null : state.pack.speciesById(build.speciesId);

    return Scaffold(
      appBar: AppBar(
        title: Text(species?.name ?? 'Choose Pokemon'),
        actions: [
          if (build != null)
            TextButton(
              onPressed: () {
                build.nickname = _nicknameController.text.trim().isEmpty
                    ? null
                    : _nicknameController.text.trim();
                Navigator.pop(context, build);
              },
              child: const Text('Done'),
            ),
        ],
      ),
      body: build == null || species == null
          ? _speciesPicker(state.pack.species.values.toList())
          : _editor(species, build),
    );
  }

  Widget _speciesPicker(List<Species> all) {
    all.sort((a, b) => a.name.compareTo(b.name));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Autocomplete<Species>(
          displayStringForOption: (s) => s.name,
          optionsBuilder: (value) => all.where((s) => s.name
              .toLowerCase()
              .contains(value.text.trim().toLowerCase())),
          onSelected: _selectSpecies,
          fieldViewBuilder: (context, controller, focus, onSubmit) =>
              TextField(
            controller: controller,
            focusNode: focus,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search Pokemon',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final s in all)
          ListTile(
            dense: true,
            title: Text(s.name),
            subtitle: Wrap(
                spacing: 4,
                children: [for (final t in s.types) TypeChip(t, small: true)]),
            onTap: () => _selectSpecies(s),
          ),
      ],
    );
  }

  void _selectSpecies(Species species) {
    setState(() {
      _build = PokemonBuild(
        speciesId: species.id,
        ability: species.abilities.first,
        nature: 'Adamant',
      );
    });
  }

  Widget _editor(Species species, PokemonBuild build) {
    final state = AppScope.of(context);
    final pack = state.pack;
    final mega = species.megaById(build.megaFormeId);
    final effectiveStats = StatCalculator.computeStats(
      species.baseStatsFor(build.megaFormeId),
      build.sp,
      build.nature,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 4, children: [
          for (final t in species.typesFor(build.megaFormeId)) TypeChip(t),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _nicknameController,
          decoration: const InputDecoration(
            labelText: 'Nickname (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        // Ability (fixed by forme while Mega).
        DropdownButtonFormField<String>(
          initialValue: mega?.ability ??
              (species.abilities.contains(build.ability)
                  ? build.ability
                  : species.abilities.first),
          decoration: const InputDecoration(
            labelText: 'Ability',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final a in mega == null ? species.abilities : [mega.ability])
              DropdownMenuItem(value: a, child: Text(a)),
          ],
          onChanged: mega != null
              ? null
              : (value) => setState(() => build.ability = value ?? ''),
        ),
        const SizedBox(height: 12),

        DropdownButtonFormField<String>(
          initialValue: build.nature,
          decoration: const InputDecoration(
            labelText: 'Nature',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final n in natures)
              DropdownMenuItem(
                  value: n.name, child: Text('${n.name} (${n.summary})')),
          ],
          onChanged: (value) =>
              setState(() => build.nature = value ?? 'Serious'),
        ),
        const SizedBox(height: 12),

        DropdownButtonFormField<String?>(
          initialValue: build.itemId,
          decoration: const InputDecoration(
            labelText: 'Held item',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('— none —')),
            for (final item in pack.items.values.toList()
              ..sort((a, b) => a.name.compareTo(b.name)))
              DropdownMenuItem(value: item.id, child: Text(item.name)),
          ],
          onChanged: (value) => setState(() => build.itemId = value),
        ),
        const SizedBox(height: 12),

        if (species.megas.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            initialValue: build.megaFormeId,
            decoration: const InputDecoration(
              labelText: 'Mega Evolution (Omni Ring)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('— none —')),
              for (final m in species.megas)
                DropdownMenuItem(value: m.id, child: Text(m.name)),
            ],
            onChanged: (value) => setState(() {
              build.megaFormeId = value;
              final selected = species.megaById(value);
              if (selected != null) {
                build.itemId = selected.item; // stone comes with the forme
                build.ability = selected.ability;
              }
            }),
          ),
          const SizedBox(height: 12),
        ],

        Text('Moves', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (var slot = 0; slot < 4; slot++) _moveSlot(species, build, slot),
        const SizedBox(height: 16),

        Row(
          children: [
            Text('Stat Points', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Chip(
              label: Text('${build.spRemaining} SP left'),
              backgroundColor: build.spRemaining < 0
                  ? Colors.red.shade100
                  : Colors.green.shade100,
            ),
          ],
        ),
        for (final key in statKeys)
          _spRow(species, build, key, effectiveStats[key] ?? 0),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _moveSlot(Species species, PokemonBuild build, int slot) {
    final pack = AppScope.of(context).pack;
    final current = slot < build.moveIds.length ? build.moveIds[slot] : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String?>(
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Move ${slot + 1}',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('— empty —')),
          for (final moveId in species.learnset)
            DropdownMenuItem(
              value: moveId,
              child: Text(
                '${pack.moveName(moveId)}  ·  ${pack.moveById(moveId)?.summary ?? ''}',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => setState(() {
          final moves = List<String?>.generate(
            4,
            (i) => i < build.moveIds.length ? build.moveIds[i] : null,
          );
          moves[slot] = value;
          build.moveIds = moves.whereType<String>().toList();
        }),
      ),
    );
  }

  Widget _spRow(Species species, PokemonBuild build, String key, int stat) {
    return Row(
      children: [
        SizedBox(
            width: 34,
            child: Text(statLabels[key] ?? key,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(
          child: Slider(
            value: build.spFor(key).toDouble(),
            min: 0,
            max: spPerStatCap.toDouble(),
            divisions: spPerStatCap,
            label: '${build.spFor(key)}',
            onChanged: (value) =>
                setState(() => build.sp[key] = value.round()),
          ),
        ),
        SizedBox(
            width: 30,
            child: Text('${build.spFor(key)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12))),
        SizedBox(
          width: 44,
          child: Text('→ $stat',
              textAlign: TextAlign.right,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
