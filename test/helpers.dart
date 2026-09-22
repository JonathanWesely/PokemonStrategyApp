/// Test helpers: load the real bundled data packs straight from disk
/// (flutter test runs with the project root as CWD).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:pokemon_strategy_app/src/data/data_pack.dart';
import 'package:pokemon_strategy_app/src/recognition/champions_atlas.dart';

DataPack? _cached;

DataPack loadRealDataPack() {
  return _cached ??= DataPack.fromJsonStrings(
    pokedexJson: File('assets/data/pokedex.json').readAsStringSync(),
    movesJson: File('assets/data/moves.json').readAsStringSync(),
    itemsJson: File('assets/data/items.json').readAsStringSync(),
    typeChartJson: File('assets/data/type_chart.json').readAsStringSync(),
    usageJson: File('assets/data/usage_reg_mb.json').readAsStringSync(),
    regulationsJson: File('assets/data/regulations.json').readAsStringSync(),
    abilitiesJson: File('assets/data/abilities.json').readAsStringSync(),
  );
}


Future<Uint8List?> helperFileLoader(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

ChampionsReferenceSet? _refs;

/// The bundled sprite/badge reference set, loaded once per test run.
Future<ChampionsReferenceSet> loadRefsForTest() async =>
    _refs ??= (await ChampionsReferenceSet.load(helperFileLoader))!;
