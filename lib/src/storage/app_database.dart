/// SQLite persistence: profiles (accounts), teams, match history, and
/// settings. Written against sqflite_common's pure-Dart types so tests run
/// on real SQLite with no device (sqflite_common_ffi) — same pattern as the
/// golf app's SwingDatabase.
///
/// Schema v2 (2026-08): adds profiles + matches, scopes teams to a profile.
/// v1 databases migrate in place; existing teams land on the default profile.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../models/match_record.dart';
import '../models/team.dart';

class AppDatabase {
  final Database _db;

  AppDatabase._(this._db);

  static Future<AppDatabase> open(
    DatabaseFactory factory, {
    String path = 'pokemon_strategy.db',
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await _createV2(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL
              )
            ''');
            await db.insert('profiles',
                {'name': 'Player 1', 'created_at': _now()});
            await db.execute(
                'ALTER TABLE teams ADD COLUMN profile_id INTEGER NOT NULL DEFAULT 1');
            await db.execute('''
              CREATE TABLE matches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id INTEGER NOT NULL,
                date TEXT NOT NULL,
                format_id TEXT NOT NULL,
                format_name TEXT NOT NULL,
                team_name TEXT NOT NULL,
                result TEXT NOT NULL,
                json TEXT NOT NULL
              )
            ''');
          }
        },
      ),
    );
    final app = AppDatabase._(db);
    await app._ensureDefaultProfile();
    return app;
  }

  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE teams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        profile_id INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE matches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        format_id TEXT NOT NULL,
        format_name TEXT NOT NULL,
        team_name TEXT NOT NULL,
        result TEXT NOT NULL,
        json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static String _now() => DateTime.now().toIso8601String();

  Future<void> _ensureDefaultProfile() async {
    final rows = await _db.query('profiles', limit: 1);
    if (rows.isEmpty) {
      await _db.insert('profiles', {'name': 'Player 1', 'created_at': _now()});
    }
  }

  Future<void> close() => _db.close();

  // ----------------------------------------------------------- profiles --

  Future<List<Profile>> loadProfiles() async {
    final rows = await _db.query('profiles', orderBy: 'id ASC');
    return [
      for (final r in rows)
        Profile(id: r['id'] as int, name: r['name'] as String),
    ];
  }

  Future<Profile> createProfile(String name) async {
    final id =
        await _db.insert('profiles', {'name': name, 'created_at': _now()});
    return Profile(id: id, name: name);
  }

  Future<void> renameProfile(int id, String name) async {
    await _db.update('profiles', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------- teams --

  Future<List<Team>> loadTeams({int profileId = 1}) async {
    final rows = await _db.query('teams',
        where: 'profile_id = ?',
        whereArgs: [profileId],
        orderBy: 'updated_at DESC');
    return [
      for (final row in rows)
        Team.decode(row['json'] as String, id: row['id'] as int),
    ];
  }

  /// Insert or update; returns the team with its id set.
  Future<Team> saveTeam(Team team, {int profileId = 1}) async {
    final now = _now();
    if (team.id == null) {
      final id = await _db.insert('teams', {
        'name': team.name,
        'json': team.encode(),
        'updated_at': now,
        'profile_id': profileId,
      });
      team.id = id;
    } else {
      await _db.update(
        'teams',
        {'name': team.name, 'json': team.encode(), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [team.id],
      );
    }
    return team;
  }

  Future<void> deleteTeam(int id) async {
    await _db.delete('teams', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------ matches --

  Future<MatchRecord> saveMatch(MatchRecord match) async {
    final id = await _db.insert('matches', {
      'profile_id': match.profileId,
      'date': match.date,
      'format_id': match.formatId,
      'format_name': match.formatName,
      'team_name': match.teamName,
      'result': match.result,
      'json': match.encodeSnapshot(),
    });
    return MatchRecord(
      id: id,
      profileId: match.profileId,
      date: match.date,
      formatId: match.formatId,
      formatName: match.formatName,
      teamName: match.teamName,
      result: match.result,
      snapshot: match.snapshot,
    );
  }

  Future<List<MatchRecord>> loadMatches({int profileId = 1}) async {
    final rows = await _db.query('matches',
        where: 'profile_id = ?', whereArgs: [profileId], orderBy: 'date DESC');
    return [for (final r in rows) MatchRecord.fromRow(r)];
  }

  Future<void> deleteMatch(int id) async {
    await _db.delete('matches', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------- settings --

  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
