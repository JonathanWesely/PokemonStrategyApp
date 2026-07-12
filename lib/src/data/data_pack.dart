/// The bundled data pack: pokedex, moves, items, type chart, usage stats,
/// and battle formats. Pure Dart — construction takes raw JSON strings so
/// tests can feed it files and the app can feed it rootBundle assets.
library;

import 'dart:convert';

import '../models/item.dart';
import '../models/move.dart';
import '../models/regulation.dart';
import '../models/species.dart';
import 'type_chart.dart';
import 'usage_stats.dart';

class DataPack {
  final Map<String, Species> species;
  final Map<String, MoveData> moves;
  final Map<String, ItemData> items;
  final TypeChart typeChart;
  final UsageStats usage;
  final List<FormatSpec> formats;
  final String pokedexSource;
  final String pokedexGeneratedAt;

  const DataPack({
    required this.species,
    required this.moves,
    required this.items,
    required this.typeChart,
    required this.usage,
    required this.formats,
    required this.pokedexSource,
    required this.pokedexGeneratedAt,
  });

  factory DataPack.fromJsonStrings({
    required String pokedexJson,
    required String movesJson,
    required String itemsJson,
    required String typeChartJson,
    required String usageJson,
    required String regulationsJson,
  }) {
    final pokedex = jsonDecode(pokedexJson) as Map<String, dynamic>;
    final movesDoc = jsonDecode(movesJson) as Map<String, dynamic>;
    final itemsDoc = jsonDecode(itemsJson) as Map<String, dynamic>;
    final regsDoc = jsonDecode(regulationsJson) as Map<String, dynamic>;

    return DataPack(
      species: {
        for (final s in pokedex['species'] as List)
          (s as Map<String, dynamic>)['id'] as String: Species.fromJson(s),
      },
      moves: {
        for (final m in movesDoc['moves'] as List)
          (m as Map<String, dynamic>)['id'] as String: MoveData.fromJson(m),
      },
      items: {
        for (final i in itemsDoc['items'] as List)
          (i as Map<String, dynamic>)['id'] as String: ItemData.fromJson(i),
      },
      typeChart:
          TypeChart.fromJson(jsonDecode(typeChartJson) as Map<String, dynamic>),
      usage: UsageStats.fromJson(jsonDecode(usageJson) as Map<String, dynamic>),
      formats: [
        for (final f in regsDoc['formats'] as List)
          FormatSpec.fromJson(f as Map<String, dynamic>),
      ],
      pokedexSource: (pokedex['source'] as String?) ?? 'unknown',
      pokedexGeneratedAt: (pokedex['generatedAt'] as String?) ?? '',
    );
  }

  Species? speciesById(String id) => species[id];

  MoveData? moveById(String id) => moves[id];

  ItemData? itemById(String? id) => id == null ? null : items[id];

  String moveName(String id) => moves[id]?.name ?? id;

  String itemName(String? id) =>
      id == null ? '—' : (items[id]?.name ?? id);

  String speciesName(String id) => species[id]?.name ?? id;

  FormatSpec? formatById(String id) {
    for (final f in formats) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Case-insensitive species search over names and ids.
  List<Species> searchSpecies(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return species.values.toList();
    return species.values
        .where((s) =>
            s.name.toLowerCase().contains(q) || s.id.toLowerCase().contains(q))
        .toList();
  }

  /// Resolve a free-form name (from a vision model or user typing) to a
  /// species id. Exact name/id match first, then prefix, then contains.
  String? resolveSpeciesName(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return null;
    if (species.containsKey(q)) return q;
    for (final s in species.values) {
      if (s.name.toLowerCase() == q) return s.id;
    }
    for (final s in species.values) {
      if (s.name.toLowerCase().startsWith(q) || s.id.startsWith(q)) return s.id;
    }
    for (final s in species.values) {
      if (s.name.toLowerCase().contains(q) || s.id.contains(q)) return s.id;
    }
    return null;
  }
}
