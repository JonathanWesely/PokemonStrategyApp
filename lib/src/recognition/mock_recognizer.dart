/// Scripted/simulated recognition — the app's stand-in for the camera + AI
/// pipeline, exactly like the golf app's simulated sensor. Lets the whole
/// battle flow run on an emulator with no camera, no API key, no game.
library;

import 'dart:math';
import 'dart:typed_data';

import '../data/data_pack.dart';
import '../models/recognition_result.dart';
import 'recognition_service.dart';

class MockRecognizer implements RecognitionService {
  final DataPack pack;

  /// If set, these enemy species ids are returned in order; otherwise the
  /// engine samples plausible enemies weighted by usage.
  final List<String>? scriptedEnemies;
  final Random _random;

  MockRecognizer(this.pack, {this.scriptedEnemies, int? seed})
      : _random = Random(seed);

  @override
  String get name => 'mock';

  @override
  Future<RecognitionResult> recognize(
    Uint8List imageBytes, {
    required BattleSnapshotContext context,
  }) async {
    // Simulate camera + API latency so the UI's loading state is exercised.
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final slots = <RecognizedPokemon>[];

    // Your side is "recognized" perfectly from the picks.
    for (final id in context.yourSpeciesIds.take(context.enemyFieldSlots)) {
      slots.add(RecognizedPokemon(
        speciesId: id,
        side: BattleSide.yours,
        confidence: 1.0,
        hpPercent: 100,
      ));
    }

    final enemyIds = scriptedEnemies ?? _sampleEnemies(context.enemyFieldSlots);
    for (final id in enemyIds.take(context.enemyFieldSlots)) {
      slots.add(RecognizedPokemon(
        speciesId: id,
        side: BattleSide.enemy,
        confidence: 0.75 + _random.nextDouble() * 0.25,
        hpPercent: 100,
      ));
    }

    return RecognitionResult(slots: slots, engine: name);
  }

  /// Sample distinct species, weighted by usage percent.
  List<String> _sampleEnemies(int count) {
    final candidates = pack.usage.bySpecies.values.toList();
    if (candidates.isEmpty) {
      return pack.species.keys.take(count).toList();
    }
    final picked = <String>[];
    final pool = [...candidates];
    while (picked.length < count && pool.isNotEmpty) {
      final totalWeight =
          pool.fold<double>(0, (sum, u) => sum + u.usagePercent + 1);
      var roll = _random.nextDouble() * totalWeight;
      var chosen = pool.first;
      for (final u in pool) {
        roll -= u.usagePercent + 1;
        if (roll <= 0) {
          chosen = u;
          break;
        }
      }
      picked.add(chosen.speciesId);
      pool.remove(chosen);
    }
    return picked;
  }
}
