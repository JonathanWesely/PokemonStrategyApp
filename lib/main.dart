/// Pokemon Strategy App — battle companion for Pokemon Champions.
///
/// Boot sequence mirrors the golf app: open the database, load the data
/// pack, restore state, run. The recognition engine defaults to Local
/// (on-device sprite matching + OCR, no cloud); switch to an AI API or the
/// mock in Settings.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'src/app_state.dart';
import 'src/data/asset_loader.dart';
import 'src/recognition/mlkit_ocr.dart';
import 'src/recognition/sprite_matcher.dart';
import 'src/storage/app_database.dart';
import 'src/ui/home_screen.dart';

Future<Uint8List?> _bundleLoader(String path) async {
  try {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null; // asset not bundled (e.g. species without an exemplar seed)
  }
}

/// Exemplar persistence: PNGs under `documents/exemplars/speciesId/`.
Future<ExemplarStore> _buildExemplarStore() async {
  final store = ExemplarStore(loadBundled: _bundleLoader);
  final docs = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(docs.path, 'exemplars'));
  if (root.existsSync()) {
    for (final dir in root.listSync().whereType<Directory>()) {
      final speciesId = p.basename(dir.path);
      final pngs = <Uint8List>[
        for (final f in dir.listSync().whereType<File>())
          if (f.path.endsWith('.png')) f.readAsBytesSync(),
      ];
      if (pngs.isNotEmpty) store.seedRuntime(speciesId, pngs);
    }
  }
  store.onAdded = (speciesId, png) {
    final dir = Directory(p.join(root.path, speciesId));
    dir.createSync(recursive: true);
    File(p.join(dir.path,
            'ex_${DateTime.now().millisecondsSinceEpoch}.png'))
        .writeAsBytesSync(png);
  };
  return store;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbDir = await getDatabasesPath();
  final db = await AppDatabase.open(
    databaseFactory,
    path: p.join(dbDir, 'pokemon_strategy.db'),
  );
  final pack = await loadDataPackFromAssets();
  final exemplars = await _buildExemplarStore();

  final state = AppState(
    pack: pack,
    db: db,
    assetLoader: _bundleLoader,
    exemplars: exemplars,
    ocr: MlkitTextOcr(),
  );
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
