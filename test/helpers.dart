/// Test helpers: load the real bundled data packs straight from disk
/// (flutter test runs with the project root as CWD).
library;

import 'dart:io';

import 'package:pokemon_strategy_app/src/data/data_pack.dart';

DataPack? _cached;

DataPack loadRealDataPack() {
  return _cached ??= DataPack.fromJsonStrings(
    pokedexJson: File('assets/data/pokedex.json').readAsStringSync(),
    movesJson: File('assets/data/moves.json').readAsStringSync(),
    itemsJson: File('assets/data/items.json').readAsStringSync(),
    typeChartJson: File('assets/data/type_chart.json').readAsStringSync(),
    usageJson: File('assets/data/usage_reg_mb.json').readAsStringSync(),
    regulationsJson: File('assets/data/regulations.json').readAsStringSync(),
  );
}
