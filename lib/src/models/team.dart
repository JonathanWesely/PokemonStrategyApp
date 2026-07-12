/// A saved team of up to 6 builds. Pure Dart.
library;

import 'dart:convert';

import 'pokemon_build.dart';

const teamSize = 6;

class Team {
  /// Database row id; null until first save.
  int? id;
  String name;
  List<PokemonBuild> builds;

  Team({this.id, required this.name, List<PokemonBuild>? builds})
      : builds = builds ?? [];

  factory Team.fromJson(Map<String, dynamic> json, {int? id}) => Team(
        id: id,
        name: json['name'] as String,
        builds: ((json['builds'] as List?) ?? const [])
            .map((b) => PokemonBuild.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'builds': builds.map((b) => b.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static Team decode(String json, {int? id}) =>
      Team.fromJson(jsonDecode(json) as Map<String, dynamic>, id: id);

  Team copy() => Team.decode(encode(), id: id);
}
