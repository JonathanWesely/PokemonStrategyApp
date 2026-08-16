/// A finished battle saved to match history. Pure Dart.
library;

import 'dart:convert';

class MatchRecord {
  final int? id;
  final int profileId;
  final String date; // ISO-8601
  final String formatId;
  final String formatName;
  final String teamName;

  /// 'win' | 'loss' | 'unknown'
  final String result;

  /// BattleSession.toSnapshotJson(): picks, enemy roster, reveals.
  final Map<String, dynamic> snapshot;

  const MatchRecord({
    this.id,
    required this.profileId,
    required this.date,
    required this.formatId,
    required this.formatName,
    required this.teamName,
    required this.result,
    required this.snapshot,
  });

  String encodeSnapshot() => jsonEncode(snapshot);

  factory MatchRecord.fromRow(Map<String, Object?> row) => MatchRecord(
        id: row['id'] as int?,
        profileId: row['profile_id'] as int,
        date: row['date'] as String,
        formatId: row['format_id'] as String,
        formatName: row['format_name'] as String,
        teamName: row['team_name'] as String,
        result: row['result'] as String,
        snapshot: jsonDecode(row['json'] as String) as Map<String, dynamic>,
      );

  List<String> get enemySpeciesIds => [
        for (final e in (snapshot['enemies'] as List?) ?? const [])
          (e as Map<String, dynamic>)['speciesId'] as String,
      ];
}

class Profile {
  final int id;
  final String name;

  const Profile({required this.id, required this.name});
}
