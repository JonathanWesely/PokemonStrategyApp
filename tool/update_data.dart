/// The data update ritual (plan §5.1), one command:
///
///   dart run tool/update_data.dart
///
/// TODAY (scaffold): validates the bundled packs in assets/data/ against the
/// schema rules the test suite also enforces, and prints a summary — so a
/// hand-edited or freshly generated pack is checked before the app ships it.
///
/// PHASE 0 TODO (see docs/DATA_UPDATE.md): add the fetch stages —
///   1. regulation roster + permitted Megas   (Victory Road)
///   2. base stats/types/abilities/learnsets  (PokeAPI)
///   3. usage stats: moves/items/abilities/spreads/teammates (Pikalytics)
/// then diff against the current packs and rewrite them. Keep this file the
/// ONLY place that knows about those sources.
library;

import 'dart:convert';
import 'dart:io';

const dataDir = 'assets/data';

void main() {
  final problems = <String>[];
  final summary = <String>[];

  Map<String, dynamic> load(String name) {
    final file = File('$dataDir/$name');
    if (!file.existsSync()) {
      problems.add('MISSING FILE: $dataDir/$name');
      return const {};
    }
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      problems.add('BAD JSON in $name: $e');
      return const {};
    }
  }

  final pokedex = load('pokedex.json');
  final movesDoc = load('moves.json');
  final itemsDoc = load('items.json');
  final typeChart = load('type_chart.json');
  final usage = load('usage_reg_mb.json');
  final regulations = load('regulations.json');

  final types = ((typeChart['types'] as List?) ?? const []).cast<String>();
  final moveIds = {
    for (final m in (movesDoc['moves'] as List?) ?? const [])
      (m as Map<String, dynamic>)['id'] as String
  };
  final itemIds = {
    for (final i in (itemsDoc['items'] as List?) ?? const [])
      (i as Map<String, dynamic>)['id'] as String
  };

  // ---- pokedex checks ----
  final speciesList = ((pokedex['species'] as List?) ?? const [])
      .cast<Map<String, dynamic>>();
  final speciesIds = <String>{};
  var megaCount = 0;
  for (final s in speciesList) {
    final id = s['id'] as String;
    speciesIds.add(id);
    for (final t in (s['types'] as List).cast<String>()) {
      if (!types.contains(t)) problems.add('$id: unknown type $t');
    }
    if (((s['abilities'] as List?) ?? const []).isEmpty) {
      problems.add('$id: no abilities');
    }
    for (final m in ((s['learnset'] as List?) ?? const []).cast<String>()) {
      if (!moveIds.contains(m)) problems.add('$id: learnset move $m unknown');
    }
    for (final mega in ((s['megas'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()) {
      megaCount++;
      if (!itemIds.contains(mega['item'])) {
        problems.add('$id: mega stone ${mega['item']} unknown');
      }
    }
  }
  summary.add('pokedex: ${speciesIds.length} species, $megaCount megas '
      '(source: ${pokedex['source']}, generated ${pokedex['generatedAt']})');
  summary.add('moves: ${moveIds.length} · items: ${itemIds.length} · '
      'types: ${types.length}');

  // ---- usage checks ----
  final usageList =
      ((usage['pokemon'] as List?) ?? const []).cast<Map<String, dynamic>>();
  for (final u in usageList) {
    final id = u['speciesId'] as String;
    if (!speciesIds.contains(id)) {
      problems.add('usage: unknown species $id');
      continue;
    }
    for (final m in ((u['moves'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()) {
      if (!moveIds.contains(m['id'])) {
        problems.add('usage $id: unknown move ${m['id']}');
      }
    }
    for (final i in ((u['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()) {
      if (!itemIds.contains(i['id'])) {
        problems.add('usage $id: unknown item ${i['id']}');
      }
    }
    for (final t in ((u['teammates'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()) {
      if (!speciesIds.contains(t['speciesId'])) {
        problems.add('usage $id: unknown teammate ${t['speciesId']}');
      }
    }
    for (final spread in ((u['spreads'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()) {
      final sp = (spread['sp'] as Map).cast<String, int>();
      final total = sp.values.fold<int>(0, (a, b) => a + b);
      if (total > 66) problems.add('usage $id: spread total $total > 66');
      for (final v in sp.values) {
        if (v > 32) problems.add('usage $id: spread stat $v > 32');
      }
    }
  }
  summary.add('usage (${usage['regulation']}): ${usageList.length} species '
      '(source: ${usage['source']})');

  // ---- coverage: species without usage data ----
  final covered = {for (final u in usageList) u['speciesId'] as String};
  final uncovered = speciesIds.difference(covered);
  if (uncovered.isNotEmpty) {
    summary.add('NO USAGE DATA (dashboard will dim these): '
        '${(uncovered.toList()..sort()).join(', ')}');
  }

  final formats = ((regulations['formats'] as List?) ?? const []);
  summary.add('formats: ${formats.length}');

  // ---- report ----
  stdout.writeln('=== data pack validation ===');
  summary.forEach(stdout.writeln);
  if (problems.isEmpty) {
    stdout.writeln('\nAll checks passed.');
    if (usage['source'] == 'starter-placeholder') {
      stdout.writeln('\nNOTE: usage stats are still the hand-authored starter '
          'placeholder.\nPhase 0 wires the real fetchers into this script '
          '(docs/DATA_UPDATE.md).');
    }
  } else {
    stdout.writeln('\nPROBLEMS (${problems.length}):');
    for (final p in problems) {
      stdout.writeln('  ! $p');
    }
    exitCode = 1;
  }
}
