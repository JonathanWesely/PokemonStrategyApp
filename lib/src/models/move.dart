/// Move data from the moves pack. Pure Dart.
library;

class MoveData {
  final String id;
  final String name;
  final String type;

  /// 'Physical' | 'Special' | 'Status'
  final String category;

  /// Base power; null for status moves and variable-power moves.
  final int? power;

  /// Accuracy percent; null means the move never misses.
  final int? accuracy;

  final int priority;
  final String note;

  /// Longer effect description (from the data pack; may be empty).
  final String desc;

  const MoveData({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    this.power,
    this.accuracy,
    this.priority = 0,
    this.note = '',
    this.desc = '',
  });

  factory MoveData.fromJson(Map<String, dynamic> json) => MoveData(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        category: json['category'] as String,
        power: json['power'] as int?,
        accuracy: json['accuracy'] as int?,
        priority: (json['priority'] as int?) ?? 0,
        note: (json['note'] as String?) ?? '',
        desc: (json['desc'] as String?) ?? '',
      );

  bool get isStatus => category == 'Status';

  /// Short display like "Fire · Phys 120 · 100%".
  String get summary {
    final p = power == null ? '—' : '$power';
    final a = accuracy == null ? '—' : '$accuracy%';
    final cat = switch (category) {
      'Physical' => 'Phys',
      'Special' => 'Spec',
      _ => 'Status',
    };
    return '$type · $cat $p · $a';
  }
}
