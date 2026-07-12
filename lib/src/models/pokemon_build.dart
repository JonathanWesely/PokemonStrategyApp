/// One configured Pokemon in a team. Pure Dart.
library;

import 'species.dart';

/// Champions SP budget: 66 points total, at most 32 in any one stat.
const spTotalBudget = 66;
const spPerStatCap = 32;

class PokemonBuild {
  String speciesId;
  String? nickname;

  /// Up to 4 move ids.
  List<String> moveIds;
  String ability;
  String? itemId;
  String nature;

  /// SP allocation per stat key ('hp'..'spe'). Missing keys mean 0.
  Map<String, int> sp;

  /// Selected Mega forme id (must be one of the species' megas), or null.
  String? megaFormeId;

  PokemonBuild({
    required this.speciesId,
    this.nickname,
    List<String>? moveIds,
    this.ability = '',
    this.itemId,
    this.nature = 'Serious',
    Map<String, int>? sp,
    this.megaFormeId,
  })  : moveIds = moveIds ?? [],
        sp = sp ?? {};

  int spFor(String statKey) => sp[statKey] ?? 0;

  int get spTotal => statKeys.fold(0, (sum, k) => sum + spFor(k));

  int get spRemaining => spTotalBudget - spTotal;

  bool get spLegal =>
      spTotal <= spTotalBudget &&
      statKeys.every((k) => spFor(k) >= 0 && spFor(k) <= spPerStatCap);

  factory PokemonBuild.fromJson(Map<String, dynamic> json) => PokemonBuild(
        speciesId: json['speciesId'] as String,
        nickname: json['nickname'] as String?,
        moveIds: ((json['moveIds'] as List?) ?? const []).cast<String>(),
        ability: (json['ability'] as String?) ?? '',
        itemId: json['itemId'] as String?,
        nature: (json['nature'] as String?) ?? 'Serious',
        sp: ((json['sp'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as int)),
        megaFormeId: json['megaFormeId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'speciesId': speciesId,
        if (nickname != null) 'nickname': nickname,
        'moveIds': moveIds,
        'ability': ability,
        if (itemId != null) 'itemId': itemId,
        'nature': nature,
        'sp': sp,
        if (megaFormeId != null) 'megaFormeId': megaFormeId,
      };

  PokemonBuild copy() => PokemonBuild.fromJson(toJson());
}
