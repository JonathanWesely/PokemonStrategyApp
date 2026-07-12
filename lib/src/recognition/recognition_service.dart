/// The recognition abstraction — this app's equivalent of the golf app's
/// SensorLink/BleTransport split. UI and AppState only ever see this
/// interface; engines (mock, cloud vision, future OCR/on-device) swap freely.
library;

import 'dart:typed_data';

import '../models/recognition_result.dart';

/// What the engine is allowed to know about the battle when it looks at a
/// snapshot: your picks (so your side needs no recognition at all) and how
/// many enemy slots the format has.
class BattleSnapshotContext {
  final List<String> yourSpeciesIds;
  final int enemyFieldSlots;

  const BattleSnapshotContext({
    required this.yourSpeciesIds,
    required this.enemyFieldSlots,
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
