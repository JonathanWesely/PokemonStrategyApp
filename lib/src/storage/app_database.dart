/// SQLite persistence: teams and settings. Written against sqflite_common's
/// pure-Dart types so tests run on real SQLite with no device
/// (sqflite_common_ffi) — same pattern as the golf app's SwingDatabase.
library;

import 'package:sqflite_common/sqlite_api.dart';

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
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE teams (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              json TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => _db.close();

  // ------------------------------------------------------------- teams --

  Future<List<Team>> loadTeams() async {
    final rows = await _db.query('teams', orderBy: 'updated_at DESC');
    return [
      for (final row in rows)
        Team.decode(row['json'] as String, id: row['id'] as int),
    ];
  }

  /// Insert or update; returns the team with its id set.
  Future<Team> saveTeam(Team team) async {
    final now = DateTime.now().toIso8601String();
    if (team.id == null) {
      final id = await _db.insert('teams', {
        'name': team.name,
        'json': team.encode(),
        'updated_at': now,
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
