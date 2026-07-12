/// Mutable state of one battle session. Pure Dart.
library;

import 'pokemon_build.dart';
import 'regulation.dart';
import 'team.dart';

/// An enemy Pokemon revealed during the battle, plus everything confirmed
/// about it so far. Reveals feed the prediction engine (confirmed slots are
/// promoted; unpredicted reveals slot in automatically).
class EnemyPokemon {
  final String speciesId;
  bool onField;
  bool mega;
  int? hpPercent;

  final Set<String> revealedMoves = {};
  String? revealedItem;
  String? revealedAbility;

  EnemyPokemon({
    required this.speciesId,
    this.onField = true,
    this.mega = false,
    this.hpPercent,
  });
}

class BattleSession {
  final FormatSpec format;
  final Team team;

  /// The 3 (singles) or 4 (doubles) builds brought to this battle.
  final List<PokemonBuild> picks;

  /// Indexes into [picks] currently on the field.
  final Set<int> activePickIndexes = {};

  final List<EnemyPokemon> enemies = [];

  BattleSession({required this.format, required this.team, required this.picks}) {
    // Lead slots default to the first 1 or 2 picks.
    for (var i = 0; i < format.fieldSlots && i < picks.length; i++) {
      activePickIndexes.add(i);
    }
  }

  List<PokemonBuild> get activeYours =>
      [for (final i in activePickIndexes) picks[i]];

  List<EnemyPokemon> get enemiesOnField =>
      enemies.where((e) => e.onField).toList();

  List<EnemyPokemon> get enemyBench => enemies.where((e) => !e.onField).toList();

  EnemyPokemon addEnemy(String speciesId, {bool onField = true, bool mega = false, int? hpPercent}) {
    final existing = enemies.where((e) => e.speciesId == speciesId).firstOrNull;
    if (existing != null) {
      existing.onField = onField;
      if (hpPercent != null) existing.hpPercent = hpPercent;
      if (mega) existing.mega = true;
      return existing;
    }
    // Field slots are limited; benching the oldest if full.
    if (onField) {
      final onFieldNow = enemiesOnField;
      if (onFieldNow.length >= format.fieldSlots) {
        onFieldNow.first.onField = false;
      }
    }
    final enemy = EnemyPokemon(
        speciesId: speciesId, onField: onField, mega: mega, hpPercent: hpPercent);
    enemies.add(enemy);
    return enemy;
  }

  void removeEnemy(EnemyPokemon enemy) => enemies.remove(enemy);
}
