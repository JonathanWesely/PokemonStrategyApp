/// On-device / local recognition engine — no network, no cloud AI, no
/// per-call cost.
///
/// Team-preview screen (no names in-game): the pure-Dart [SpriteMatcher]
/// segments the six enemy sprite panels and matches them against the
/// exemplar library (sprites saved from your own confirmed photos, plus
/// bundled seeds) with bundled official art as the cold-start fallback.
/// Low-confidence slots surface their runners-up so the UI can offer
/// one-tap correction — and every confirmation feeds the exemplar library,
/// so this engine sharpens with every battle.
///
/// Battle screen (names shown): on-device OCR (ML Kit, injected behind the
/// [TextOcr] seam) reads the name banners; [BattleTextMatcher] resolves them
/// against the roster with fuzzy matching and reads HP where visible.
library;

import 'dart:typed_data';

import '../data/data_pack.dart';
import '../models/recognition_result.dart';
import 'battle_ocr.dart';
import 'recognition_service.dart';
import 'sprite_matcher.dart';

class LocalRecognizer implements RecognitionService {
  final DataPack pack;
  final SpriteMatcher matcher;
  final TextOcr? ocr;

  const LocalRecognizer(this.pack, {required this.matcher, this.ocr});

  @override
  String get name => 'local';

  @override
  Future<RecognitionResult> recognize(
    Uint8List imageBytes, {
    required BattleSnapshotContext context,
  }) async {
    if (imageBytes.isEmpty) {
      throw const RecognitionException(
          'No image — take a photo or import a screenshot.');
    }
    return switch (context.screen) {
      RecognitionScreen.preview => _recognizePreview(imageBytes, context),
      RecognitionScreen.battle => _recognizeBattle(imageBytes, context),
    };
  }

  Future<RecognitionResult> _recognizePreview(
      Uint8List imageBytes, BattleSnapshotContext context) async {
    final matches = await matcher.matchPreview(imageBytes,
        expectedPanels: context.enemyTeamSize);
    if (matches.isEmpty) {
      throw const RecognitionException(
          'Could not find the enemy team panels in this photo. Make sure the '
          'whole team-select screen is in frame, or fill the boxes in '
          'manually.');
    }
    final slots = <RecognizedPokemon>[
      for (final m in matches)
        RecognizedPokemon(
          speciesId: m.assigned.speciesId,
          side: BattleSide.enemy,
          confidence: m.assigned.score.clamp(0.0, 1.0),
          alternatives: [
            for (final c in m.ranked.take(4))
              if (c.speciesId != m.assigned.speciesId)
                RecognizedAlt(speciesId: c.speciesId, confidence: c.score),
          ],
          spriteCrop: m.cropPng,
        ),
      // Your side needs no recognition — the app knows your team.
      for (final id in context.yourSpeciesIds)
        RecognizedPokemon(speciesId: id, side: BattleSide.yours),
    ];
    return RecognitionResult(slots: slots, engine: name);
  }

  Future<RecognitionResult> _recognizeBattle(
      Uint8List imageBytes, BattleSnapshotContext context) async {
    final engine = ocr;
    if (engine == null) {
      throw const RecognitionException(
          'On-device OCR is not available here — add the enemy manually.');
    }
    final lines = await engine.readLines(imageBytes);
    final slots = BattleTextMatcher(pack).match(lines, context);
    if (slots.isEmpty) {
      throw const RecognitionException(
          'No Pokemon names found in this photo — make sure the name banners '
          'are visible, or add the enemy manually.');
    }
    return RecognitionResult(slots: slots, engine: name);
  }
}
