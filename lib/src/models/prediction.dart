/// Prediction output types consumed by the intel dashboard. Pure Dart.
library;

/// One predicted option (a move, item, or ability) with its usage rate.
class RatedOption {
  final String id;
  final String label;

  /// Usage percent 0–100 among this species' competitive sets.
  final double pct;

  /// True once the battle has revealed this option for certain.
  final bool confirmed;

  const RatedOption({
    required this.id,
    required this.label,
    required this.pct,
    this.confirmed = false,
  });

  RatedOption asConfirmed() =>
      RatedOption(id: id, label: label, pct: 100, confirmed: true);
}

/// Inclusive stat range across plausible competitive spreads.
class StatRange {
  final int min;
  final int max;

  /// Value from the most common spread.
  final int likely;

  const StatRange({required this.min, required this.max, required this.likely});

  bool get isExact => min == max;

  @override
  String toString() => isExact ? '$likely' : '$min–$max ($likely)';
}

/// A usage-pack spread: nature + SP allocation + how common it is.
class SpreadUsage {
  final String nature;
  final Map<String, int> sp;
  final double pct;

  const SpreadUsage({required this.nature, required this.sp, required this.pct});

  factory SpreadUsage.fromJson(Map<String, dynamic> json) => SpreadUsage(
        nature: json['nature'] as String,
        sp: ((json['sp'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as int)),
        pct: ((json['pct'] as num?) ?? 0).toDouble(),
      );
}

/// Everything the dashboard shows for one enemy Pokemon.
class EnemyIntel {
  final String speciesId;

  /// Usage percent of this species in the current regulation (0 if unknown).
  final double usagePercent;

  /// Whether real usage data existed (false = learnset fallback, dim the UI).
  final bool fromUsageData;

  final List<RatedOption> moves;
  final List<RatedOption> items;
  final List<RatedOption> abilities;
  final List<SpreadUsage> spreads;

  /// statKey -> predicted range at level 50.
  final Map<String, StatRange> statRanges;

  /// speciesId -> co-usage pct, most common partners first.
  final Map<String, double> teammates;

  const EnemyIntel({
    required this.speciesId,
    required this.usagePercent,
    required this.fromUsageData,
    required this.moves,
    required this.items,
    required this.abilities,
    required this.spreads,
    required this.statRanges,
    required this.teammates,
  });
}
