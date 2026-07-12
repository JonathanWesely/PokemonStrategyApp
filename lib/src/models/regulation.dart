/// Battle format specs from the regulations pack. Pure Dart.
library;

class FormatSpec {
  final String id;
  final String name;
  final String regulation;
  final String? regulationName;
  final String? start;
  final String? end;

  /// 'singles' | 'doubles'
  final String style;
  final int teamSize;
  final int pickSize;
  final int level;
  final bool itemClause;
  final bool speciesClause;

  /// Whether ranked-roster legality should be linted for this format.
  final bool legalityChecked;

  const FormatSpec({
    required this.id,
    required this.name,
    required this.regulation,
    this.regulationName,
    this.start,
    this.end,
    required this.style,
    required this.teamSize,
    required this.pickSize,
    required this.level,
    required this.itemClause,
    required this.speciesClause,
    required this.legalityChecked,
  });

  factory FormatSpec.fromJson(Map<String, dynamic> json) => FormatSpec(
        id: json['id'] as String,
        name: json['name'] as String,
        regulation: json['regulation'] as String,
        regulationName: json['regulationName'] as String?,
        start: json['start'] as String?,
        end: json['end'] as String?,
        style: json['style'] as String,
        teamSize: json['teamSize'] as int,
        pickSize: json['pickSize'] as int,
        level: json['level'] as int,
        itemClause: json['itemClause'] as bool,
        speciesClause: json['speciesClause'] as bool,
        legalityChecked: json['legalityChecked'] as bool,
      );

  bool get isDoubles => style == 'doubles';

  /// Pokemon per side on the field at once.
  int get fieldSlots => isDoubles ? 2 : 1;
}
