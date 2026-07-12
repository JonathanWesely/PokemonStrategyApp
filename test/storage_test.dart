/// AppDatabase against real SQLite (sqflite_common_ffi) — no device needed.
library;

import 'package:flutter_test/flutter_test.dart';
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
}
