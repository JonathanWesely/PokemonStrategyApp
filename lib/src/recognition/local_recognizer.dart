/// On-device / local recognition engine — no network, no cloud AI, no
/// per-call cost. The honest "data-only" floor.
///
/// Track 1 (today): performs NO fabrication. It reports your side (already
/// known from your picks) and identifies no enemies — the Team Preview boxes
/// and manual entry let you fill the enemy side in yourself, so nothing is
/// ever guessed. This is the seam the Track 2 on-device pipeline plugs into:
///   - team-preview screen (no names): a bundled TFLite sprite classifier over
///     the six detected sprite boxes;
///   - battle screen (names shown): on-device OCR of the name labels resolved
///     via DataPack.resolveSpeciesName.
/// Both are camera + on-device only; see docs/RECOGNITION_PROMPT.md and the
/// project plan. Until then this engine keeps the whole flow usable offline.
library;

import 'dart:typed_data';

import '../data/data_pack.dart';
import '../models/recognition_result.dart';
import 'recognition_service.dart';

class LocalRecognizer implements RecognitionService {
  // Retained for the Track 2 pipeline (sprite classifier + OCR name lookup).
  final DataPack pack;

  const LocalRecognizer(this.pack);

  @override
  String get name => 'local';

  @override
  Future<RecognitionResult> recognize(
    Uint8List imageBytes, {
    required BattleSnapshotContext context,
  }) async {
    // No camera pipeline is wired yet (Track 2). Report your side from the
    // known picks and identify zero enemies, so the app never invents an
    // opponent — you confirm every enemy by hand. Returning your side keeps
    // the result shape identical to the other engines.
    final slots = <RecognizedPokemon>[
      for (final id in context.yourSpeciesIds.take(context.enemyFieldSlots))
        RecognizedPokemon(
          speciesId: id,
          side: BattleSide.yours,
          confidence: 1.0,
          hpPercent: 100,
        ),
    ];
    return RecognitionResult(slots: slots, engine: name);
  }
}
