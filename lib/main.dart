/// Pokemon Strategy App — battle companion for Pokemon Champions.
///
/// Boot sequence mirrors the golf app: open the database, load the data
/// pack, restore state, run. The recognition engine defaults to the mock
/// (no camera / API key needed); switch to cloud vision in Settings.
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'src/app_state.dart';
import 'src/data/asset_loader.dart';
import 'src/storage/app_database.dart';
import 'src/ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbDir = await getDatabasesPath();
  final db = await AppDatabase.open(
    databaseFactory,
    path: p.join(dbDir, 'pokemon_strategy.db'),
  );
  final pack = await loadDataPackFromAssets();

  final state = AppState(pack: pack, db: db);
  await state.restore();

  runApp(PokemonStrategyApp(state: state));
}

class PokemonStrategyApp extends StatelessWidget {
  final AppState state;

  const PokemonStrategyApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Pokemon Strategy',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
