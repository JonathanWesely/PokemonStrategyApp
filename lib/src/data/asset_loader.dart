/// Loads the DataPack from bundled Flutter assets. The only data-layer file
/// that imports Flutter.
library;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'data_pack.dart';

Future<DataPack> loadDataPackFromAssets({AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  return DataPack.fromJsonStrings(
    pokedexJson: await b.loadString('assets/data/pokedex.json'),
    movesJson: await b.loadString('assets/data/moves.json'),
    itemsJson: await b.loadString('assets/data/items.json'),
    typeChartJson: await b.loadString('assets/data/type_chart.json'),
    usageJson: await b.loadString('assets/data/usage_reg_mb.json'),
    regulationsJson: await b.loadString('assets/data/regulations.json'),
  );
}
