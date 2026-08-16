/// AppDatabase against real SQLite (sqflite_common_ffi) — no device needed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/match_record.dart';
import 'package:pokemon_strategy_app/src/models/pokemon_build.dart';
import 'package:pokemon_strategy_app/src/models/team.dart';
import 'package:pokemon_strategy_app/src/storage/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<AppDatabase> openTestDb() =>
      AppDatabase.open(databaseFactoryFfi, path: inMemoryDatabasePath);

  Team sampleTeam() => Team(
        name: 'Rain team',
        builds: [
          PokemonBuild(
            speciesId: 'pelipper',
            ability: 'Drizzle',
            nature: 'Modest',
            moveIds: ['hurricane', 'muddy-water', 'tailwind', 'protect'],
            itemId: 'focus-sash',
            sp: {'hp': 12, 'def': 6, 'spa': 32, 'spd': 4, 'spe': 12},
          ),
          PokemonBuild(
            speciesId: 'archaludon',
            ability: 'Stamina',
            nature: 'Modest',
            moveIds: ['electro-shot', 'draco-meteor', 'body-press', 'protect'],
            itemId: 'power-herb',
            sp: {'hp': 16, 'def': 8, 'spa': 32, 'spd': 6, 'spe': 4},
          ),
        ],
      );

  test('save assigns an id and loadTeams round-trips everything', () async {
    final db = await openTestDb();
    final saved = await db.saveTeam(sampleTeam());
    expect(saved.id, isNotNull);

    final loaded = await db.loadTeams();
    expect(loaded.length, 1);
    final team = loaded.single;
    expect(team.name, 'Rain team');
    expect(team.builds.length, 2);
    expect(team.builds[0].speciesId, 'pelipper');
    expect(team.builds[0].moveIds, contains('hurricane'));
    expect(team.builds[0].sp['spa'], 32);
    expect(team.builds[1].itemId, 'power-herb');
    await db.close();
  });

  test('updating an existing team keeps one row', () async {
    final db = await openTestDb();
    final team = await db.saveTeam(sampleTeam());
    team.name = 'Rain team v2';
    team.builds.removeLast();
    await db.saveTeam(team);

    final loaded = await db.loadTeams();
    expect(loaded.length, 1);
    expect(loaded.single.name, 'Rain team v2');
    expect(loaded.single.builds.length, 1);
    await db.close();
  });

  test('deleteTeam removes the row', () async {
    final db = await openTestDb();
    final team = await db.saveTeam(sampleTeam());
    await db.deleteTeam(team.id!);
    expect(await db.loadTeams(), isEmpty);
    await db.close();
  });

  test('settings round-trip and overwrite', () async {
    final db = await openTestDb();
    expect(await db.getSetting('anthropic_api_key'), isNull);
    await db.setSetting('anthropic_api_key', 'sk-test-1');
    await db.setSetting('anthropic_api_key', 'sk-test-2');
    expect(await db.getSetting('anthropic_api_key'), 'sk-test-2');
    await db.close();
  });

  test('a default profile always exists; profiles CRUD works', () async {
    final db = await openTestDb();
    final profiles = await db.loadProfiles();
    expect(profiles, isNotEmpty);
    final created = await db.createProfile('Jonathan');
    expect(created.id, greaterThan(profiles.last.id));
    await db.renameProfile(created.id, 'Jon');
    final renamed = (await db.loadProfiles())
        .singleWhere((p) => p.id == created.id);
    expect(renamed.name, 'Jon');
    await db.close();
  });

  test('teams are scoped to their profile', () async {
    final db = await openTestDb();
    final second = await db.createProfile('Alt');
    await db.saveTeam(sampleTeam()); // default profile 1
    await db.saveTeam(sampleTeam(), profileId: second.id);
    expect((await db.loadTeams()).length, 1);
    expect((await db.loadTeams(profileId: second.id)).length, 1);
    expect((await db.loadTeams(profileId: 9999)), isEmpty);
    await db.close();
  });

  test('matches round-trip with their snapshot', () async {
    final db = await openTestDb();
    final saved = await db.saveMatch(MatchRecord(
      profileId: 1,
      date: '2026-08-16T10:00:00',
      formatId: 'ranked-doubles',
      formatName: 'Ranked Battle (Reg M-B Doubles)',
      teamName: 'Rain team',
      result: 'win',
      snapshot: {
        'enemies': [
          {'speciesId': 'umbreon', 'revealedMoves': ['foul-play']},
          {'speciesId': 'sneasler'},
        ],
      },
    ));
    expect(saved.id, isNotNull);
    final loaded = await db.loadMatches();
    expect(loaded.length, 1);
    expect(loaded.single.result, 'win');
    expect(loaded.single.enemySpeciesIds, ['umbreon', 'sneasler']);
    await db.deleteMatch(saved.id!);
    expect(await db.loadMatches(), isEmpty);
    await db.close();
  });

  test('v1 database migrates in place, keeping teams', () async {
    // Build a v1 schema by hand in a temp file, then reopen through
    // AppDatabase so onUpgrade runs.
    final dir = Directory.systemTemp.createTempSync('psa_migration');
    final path = '${dir.path}${Platform.pathSeparator}v1.db';
    final raw = await databaseFactoryFfi.openDatabase(path,
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
        ));
    await raw.insert('teams', {
      'name': 'Old team',
      'json': sampleTeam().encode(),
      'updated_at': '2026-07-11T00:00:00',
    });
    await raw.close();

    final db = await AppDatabase.open(databaseFactoryFfi, path: path);
    final teams = await db.loadTeams(); // default profile 1
    expect(teams.length, 1);
    expect(teams.single.name, 'Rain team');
    expect(await db.loadProfiles(), isNotEmpty);
    expect(await db.loadMatches(), isEmpty); // table exists post-migration
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
}
