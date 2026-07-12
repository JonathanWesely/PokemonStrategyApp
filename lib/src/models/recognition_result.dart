/// Output contract of every RecognitionService implementation. Pure Dart.
library;

enum BattleSide { yours, enemy }

class RecognizedPokemon {
  final String speciesId;
  final BattleSide side;

  /// 0.0–1.0
  final double confidence;

  /// Visible HP percent (0–100) if the engine could read the bar.
  final int? hpPercent;

  /// Whether the on-screen forme looked Mega-Evolved.
  final bool isMega;

  const RecognizedPokemon({
    required this.speciesId,
    required this.side,
    this.confidence = 1.0,
    this.hpPercent,
    this.isMega = false,
  });

  factory RecognizedPokemon.fromJson(Map<String, dynamic> json) =>
      RecognizedPokemon(
        speciesId: json['speciesId'] as String,
        side: (json['side'] as String) == 'yours'
            ? BattleSide.yours
            : BattleSide.enemy,
        confidence: ((json['confidence'] as num?) ?? 1.0).toDouble(),
        hpPercent: json['hpPercent'] as int?,
        isMega: (json['isMega'] as bool?) ?? false,
      );
}

class RecognitionResult {
  final List<RecognizedPokemon> slots;

  /// Which engine produced this ('mock', 'cloud-vision', ...).
  final String engine;

  const RecognitionResult({required this.slots, required this.engine});

  List<RecognizedPokemon> get enemies =>
      slots.where((s) => s.side == BattleSide.enemy).toList();

  List<RecognizedPokemon> get yours =>
      slots.where((s) => s.side == BattleSide.yours).toList();
}

class RecognitionException implements Exception {
  final String message;
  const RecognitionException(this.message);

  @override
  String toString() => 'RecognitionException: $message';
}
