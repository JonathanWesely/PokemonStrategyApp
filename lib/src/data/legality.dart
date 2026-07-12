/// Team legality linting per format. Warnings, not hard blocks — casual and
/// private battles are looser than ranked. Pure Dart.
library;

import '../models/pokemon_build.dart';
import '../models/regulation.dart';
import '../models/team.dart';
import 'data_pack.dart';

class LegalityIssue {
  final String message;

  /// Index of the offending build in the team, or null for team-wide issues.
  final int? buildIndex;

  const LegalityIssue(this.message, [this.buildIndex]);

  @override
  String toString() => message;
}

List<LegalityIssue> lintTeam(Team team, FormatSpec format, DataPack pack) {
  final issues = <LegalityIssue>[];

  if (team.builds.length > format.teamSize) {
    issues.add(LegalityIssue(
        'Team has ${team.builds.length} Pokemon; the format allows ${format.teamSize}.'));
  }

  // Species clause.
  if (format.speciesClause) {
    final seen = <String>{};
    for (var i = 0; i < team.builds.length; i++) {
      final id = team.builds[i].speciesId;
      if (!seen.add(id)) {
        issues.add(
            LegalityIssue('Duplicate species: ${pack.speciesName(id)}.', i));
      }
    }
  }

  // Item clause.
  if (format.itemClause) {
    final seen = <String>{};
    for (var i = 0; i < team.builds.length; i++) {
      final item = team.builds[i].itemId;
      if (item != null && !seen.add(item)) {
        issues.add(LegalityIssue(
            'Duplicate held item: ${pack.itemName(item)} (item clause).', i));
      }
    }
  }

  for (var i = 0; i < team.builds.length; i++) {
    issues.addAll(_lintBuild(team.builds[i], i, pack));
  }
  return issues;
}

List<LegalityIssue> _lintBuild(PokemonBuild build, int index, DataPack pack) {
  final issues = <LegalityIssue>[];
  final species = pack.speciesById(build.speciesId);
  if (species == null) {
    issues.add(LegalityIssue(
        'Unknown species "${build.speciesId}" — not in the current data pack.',
        index));
    return issues;
  }

  if (!build.spLegal) {
    issues.add(LegalityIssue(
        '${species.name}: SP spread is illegal (max $spTotalBudget total, '
        '$spPerStatCap per stat).',
        index));
  }

  if (build.ability.isNotEmpty && !species.abilities.contains(build.ability)) {
    issues.add(LegalityIssue(
        '${species.name} cannot have the ability ${build.ability}.', index));
  }

  final seenMoves = <String>{};
  for (final moveId in build.moveIds) {
    if (!species.learnset.contains(moveId)) {
      issues.add(LegalityIssue(
          '${species.name}: ${pack.moveName(moveId)} is not in its learnset '
          '(starter pack learnsets are abbreviated — refresh data if this '
          'looks wrong).',
          index));
    }
    if (!seenMoves.add(moveId)) {
      issues.add(LegalityIssue(
          '${species.name}: duplicate move ${pack.moveName(moveId)}.', index));
    }
  }
  if (build.moveIds.length > 4) {
    issues.add(LegalityIssue('${species.name}: more than 4 moves.', index));
  }

  // Mega forme needs its stone.
  final mega = species.megaById(build.megaFormeId);
  if (build.megaFormeId != null && mega == null) {
    issues.add(LegalityIssue(
        '${species.name}: unknown Mega forme ${build.megaFormeId}.', index));
  }
  if (mega != null && build.itemId != mega.item) {
    issues.add(LegalityIssue(
        '${species.name}: ${mega.name} requires ${pack.itemName(mega.item)} '
        'as the held item.',
        index));
  }

  return issues;
}
