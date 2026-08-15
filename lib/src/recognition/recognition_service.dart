/// The recognition abstraction — this app's equivalent of the golf app's
/// SensorLink/BleTransport split. UI and AppState only ever see this
/// interface; engines (mock, cloud vision, future OCR/on-device) swap freely.
library;

import 'dart:typed_data';

import '../models/recognition_result.dart';

/// Which game screen a snapshot is looking at. The team-preview screen shows
/// all six per side as sprites with no names (identify by sprite); the battle
/// screen shows the active Pokemon with their names (identify by text/OCR).
/// Engines that don't care (mock, cloud-vision) can ignore it.
enum RecognitionScreen { preview, battle }

/// What the engine is allowed to know about the battle when it looks at a
/// snapshot: your picks (so your side needs no recognition at all), how many
/// enemy slots the format has, and which screen is being read.
class BattleSnapshotContext {
  final List<String> yourSpeciesIds;
  final int enemyFieldSlots;
  final RecognitionScreen screen;

  const BattleSnapshotContext({
    required this.yourSpeciesIds,
    required this.enemyFieldSlots,
    this.screen = RecognitionScreen.battle,
  });
}

abstract class RecognitionService {
  /// Short id used in logs and the results UI ('mock', 'cloud-vision', ...).
  String get name;

  /// Identify the Pokemon in a battle-screen photo/screenshot.
  ///
  /// Throws [RecognitionException] on engine failure (offline, bad key,
  /// unparseable screen) — callers fall back to manual entry.
  Future<RecognitionResult> recognize(
    Uint8List imageBytes, {
    required BattleSnapshotContext context,
  });
}
