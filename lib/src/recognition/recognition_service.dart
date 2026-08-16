/// The pluggable recognition seam (the SensorLink of this app): every engine
/// — mock, local on-device, API — implements the same interface, so the UI
/// and battle flow never know which one is running.
library;

import 'dart:typed_data';

import '../models/recognition_result.dart';

/// Which game screen a snapshot is looking at. The team-preview screen shows
/// all six per side — the enemy six as 2D sprites with no names (identify by
/// sprite); the battle screen shows the active Pokemon with their names
/// (identify by text/OCR). Engines that don't care (mock) can ignore it.
enum RecognitionScreen { preview, battle }

/// What the engine is allowed to know about the battle when it looks at a
/// snapshot: your picks (so your side needs no recognition at all), how many
/// enemy slots the format has, the enemy team size (preview screen), and
/// which screen is being read.
class BattleSnapshotContext {
  final List<String> yourSpeciesIds;
  final int enemyFieldSlots;

  /// Enemy Pokemon on the team-preview screen (format.teamSize; 6 in ranked).
  final int enemyTeamSize;
  final RecognitionScreen screen;

  const BattleSnapshotContext({
    required this.yourSpeciesIds,
    required this.enemyFieldSlots,
    this.enemyTeamSize = 6,
    this.screen = RecognitionScreen.battle,
  });
}

abstract class RecognitionService {
  /// Short engine id ('mock' | 'local' | 'api').
  String get name;

  Future<RecognitionResult> recognize(
    Uint8List imageBytes, {
    required BattleSnapshotContext context,
  });
}
