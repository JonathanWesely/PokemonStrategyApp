/// Per-regulation usage statistics pack. Pure Dart.
library;

import '../models/prediction.dart';

class SpeciesUsage {
  final String speciesId;
  final double usagePercent;
  final List<RatedOption> moves;
  final List<RatedOption> items;
  final List<RatedOption> abilities;
  final List<SpreadUsage> spreads;

  /// teammate speciesId -> co-usage pct.
  final Map<String, double> teammates;

  const SpeciesUsage({
    required this.speciesId,
    required this.usagePercent,
    required this.moves,
    required this.items,
    required this.abilities,
    required this.spreads,
    required this.teammates,
  });

  factory SpeciesUsage.fromJson(Map<String, dynamic> json) {
    List<RatedOption> rated(String field, String idKey, String labelKey) =>
        ((json[field] as List?) ?? const [])
            .map((e) => e as Map<String, dynamic>)
            .map((e) => RatedOption(
                  id: (e[idKey] ?? e[labelKey]) as String,
                  label: (e[labelKey] ?? e[idKey]) as String,
                  pct: ((e['pct'] as num?) ?? 0).toDouble(),
                ))
            .toList();
    return SpeciesUsage(
      speciesId: json['speciesId'] as String,
      usagePercent: ((json['usagePercent'] as num?) ?? 0).toDouble(),
      moves: rated('moves', 'id', 'id'),
      items: rated('items', 'id', 'id'),
      abilities: rated('abilities', 'name', 'name'),
      spreads: ((json['spreads'] as List?) ?? const [])
          .map((e) => SpreadUsage.fromJson(e as Map<String, dynamic>))
          .toList(),
      teammates: {
        for (final t in ((json['teammates'] as List?) ?? const []))
          (t as Map<String, dynamic>)['speciesId'] as String:
              ((t['pct'] as num?) ?? 0).toDouble(),
      },
    );
  }
}

class UsageStats {
  final String regulation;
  final String generatedAt;
  final String source;
  final String note;
  final Map<String, SpeciesUsage> bySpecies;

  const UsageStats({
    required this.regulation,
    required this.generatedAt,
    required this.source,
    required this.note,
    required this.bySpecies,
  });

  factory UsageStats.fromJson(Map<String, dynamic> json) => UsageStats(
        regulation: (json['regulation'] as String?) ?? 'unknown',
        generatedAt: (json['generatedAt'] as String?) ?? '',
        source: (json['source'] as String?) ?? 'unknown',
        note: (json['note'] as String?) ?? '',
        bySpecies: {
          for (final p in ((json['pokemon'] as List?) ?? const []))
            (p as Map<String, dynamic>)['speciesId'] as String:
                SpeciesUsage.fromJson(p),
        },
      );

  bool get isPlaceholder => source == 'starter-placeholder';

  SpeciesUsage? forSpecies(String speciesId) => bySpecies[speciesId];
}
