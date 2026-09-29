/// Mutable state of one battle session. Pure Dart.
library;

import 'dart:typed_data';

import 'pokemon_build.dart';
import 'recognition_result.dart';
import 'regulation.dart';
import 'team.dart';

/// An enemy Pokemon revealed during the battle, plus everything confirmed
/// about it so far. Reveals feed the prediction engine (confirmed slots are
/// promoted; unpredicted reveals slot in automatically).
class EnemyPokemon {
  final String speciesId;
  bool onField;
  bool mega;
  int? hpPercent;

  final Set<String> revealedMoves = {};
  String? revealedItem;
  String? revealedAbility;

  EnemyPokemon({
    required this.speciesId,
    this.onField = true,
    this.mega = false,
    this.hpPercent,
  });

  Map<String, dynamic> toJson() => {
        'speciesId': speciesId,
        'onField': onField,
        'mega': mega,
        if (hpPercent != null) 'hpPercent': hpPercent,
        'revealedMoves': revealedMoves.toList(),
        if (revealedItem != null) 'revealedItem': revealedItem,
        if (revealedAbility != null) 'revealedAbility': revealedAbility,
      };

  factory EnemyPokemon.fromJson(Map<String, dynamic> json) {
    final e = EnemyPokemon(
      speciesId: json['speciesId'] as String,
      onField: (json['onField'] as bool?) ?? false,
      mega: (json['mega'] as bool?) ?? false,
      hpPercent: json['hpPercent'] as int?,
    );
    e.revealedMoves
        .addAll(((json['revealedMoves'] as List?) ?? const []).cast<String>());
    e.revealedItem = json['revealedItem'] as String?;
    e.revealedAbility = json['revealedAbility'] as String?;
    return e;
  }
}

/// One box of the enemy's roster on the Team Preview tab. Auto-recognized
/// slots start unconfirmed (shown in the "predicted" amber style); tapping
/// confirm — or correcting the species — makes them confirmed (green).
class PreviewSlot {
  String speciesId;

  /// Recognition confidence 0–1 (1.0 for manual entry).
  double confidence;

  /// True once the user has confirmed/corrected this slot.
  bool confirmed;

  /// Transient (not serialized): the local matcher's runner-up candidates
  /// for one-tap correction, and the segmented sprite this slot came from
  /// (saved as an exemplar when confirmed).
  List<RecognizedAlt> alternatives;
  Uint8List? spriteCrop;

  PreviewSlot(this.speciesId,
      {this.confidence = 1.0,
      this.confirmed = true,
      this.alternatives = const [],
      this.spriteCrop});

  Map<String, dynamic> toJson() => {
        'speciesId': speciesId,
        'confidence': confidence,
        'confirmed': confirmed,
      };

  factory PreviewSlot.fromJson(Map<String, dynamic> json) => PreviewSlot(
        json['speciesId'] as String,
        confidence: ((json['confidence'] as num?) ?? 1.0).toDouble(),
        confirmed: (json['confirmed'] as bool?) ?? true,
      );
}

/// A timed field condition shown above the arena ("Grassy Terrain —
/// 4 turns left?"). [turnsLeft] null = the count is unknown; [uncertain]
/// = an extending item could not be ruled out, or the count was guessed,
/// shown as a trailing "?".
class TimedCondition {
  /// terrain: grassy | misty | psychic | electric;
  /// weather: snow | rain | sun | sandstorm; also trickroom / tailwind.
  String kind;
  int? turnsLeft;
  bool uncertain;

  TimedCondition(this.kind, {this.turnsLeft, this.uncertain = true});

  /// One turn passed.
  void tick() {
    final t = turnsLeft;
    if (t != null && t > 0) turnsLeft = t - 1;
  }

  /// Countdown hit zero and no extender can save it — the caller clears
  /// the condition. An UNCERTAIN one holds at 0 ("0 turns left?"): the
  /// extender may buy three more, so only an end message (or the user)
  /// removes it.
  bool get expired => turnsLeft == 0 && !uncertain;
}

class BattleSession {
  final FormatSpec format;
  final Team team;

  /// The 3 (singles) or 4 (doubles) builds brought to this battle. EMPTY
  /// until the player locks their picks — the battle opens on Team Preview
  /// first (scout the enemy, THEN choose), mirroring the real game flow.
  final List<PokemonBuild> picks;

  /// Indexes into [picks] currently on the field.
  final Set<int> activePickIndexes = {};

  final List<EnemyPokemon> enemies = [];

  /// The enemy's full team as seen on the team-preview screen (species ids,
  /// no names in-game — identified by sprite). Up to [format.teamSize]
  /// entries; fills in as recognition lands / you tap the boxes. Drives the
  /// Team Preview tab and narrows which four they can have brought.
  final List<PreviewSlot> enemyPreview = [];

  // ---- field conditions + speed-order evidence (in-match text tracker,
  // ---- plus the arena's tap-to-edit sheet) ----

  /// Active terrain (kind grassy|misty|psychic|electric), or null.
  TimedCondition? terrain;

  /// Active weather (kind snow|rain|sun|sandstorm), or null.
  TimedCondition? weather;

  /// Trick Room (set/cleared by "twisted the dimensions" messages).
  TimedCondition? trickRoomCond;

  /// Tailwind per side (set/cleared by the Tailwind messages).
  TimedCondition? yourTailwindCond;
  TimedCondition? enemyTailwindCond;

  bool get trickRoom => trickRoomCond != null;
  bool get yourTailwind => yourTailwindCond != null;
  bool get enemyTailwind => enemyTailwindCond != null;

  /// A new turn started: count every timed condition down; conditions
  /// that certainly ended drop off.
  void tickFieldConditions() {
    terrain?.tick();
    weather?.tick();
    trickRoomCond?.tick();
    yourTailwindCond?.tick();
    enemyTailwindCond?.tick();
    if (terrain?.expired ?? false) terrain = null;
    if (weather?.expired ?? false) weather = null;
    if (trickRoomCond?.expired ?? false) trickRoomCond = null;
    if (yourTailwindCond?.expired ?? false) yourTailwindCond = null;
    if (enemyTailwindCond?.expired ?? false) enemyTailwindCond = null;
  }

  /// Confirmed raw-speed orderings observed this match, as
  /// `[fasterKey, slowerKey]` pairs with keys `y:<speciesId>` /
  /// `e:<speciesId>`. "Moved first at the same move priority" is the
  /// evidence (inverted while Trick Room is up — the tracker handles that);
  /// speed ties are deliberately not modelled.
  final List<List<String>> speedEvidence = [];

  /// Record that [faster] outsped [slower]. The latest observation wins:
  /// a contradicting earlier pair (a Tailwind or paralysis changed the
  /// order) is replaced.
  void addSpeedEvidence({required String faster, required String slower}) {
    speedEvidence.removeWhere((p) =>
        (p[0] == faster && p[1] == slower) ||
        (p[0] == slower && p[1] == faster));
    speedEvidence.add([faster, slower]);
  }

  /// True when the observed order of [aKey] vs [bKey] is known.
  bool speedRelationKnown(String aKey, String bKey) => speedEvidence.any(
      (p) =>
          (p[0] == aKey && p[1] == bKey) || (p[0] == bKey && p[1] == aKey));

  BattleSession(
      {required this.format, required this.team, List<PokemonBuild>? picks})
      : picks = picks ?? [] {
    // Lead slots default to the first 1 or 2 picks.
    for (var i = 0; i < format.fieldSlots && i < this.picks.length; i++) {
      activePickIndexes.add(i);
    }
  }

  /// True once the player has locked in their 3 (singles) / 4 (doubles).
  bool get picksChosen => picks.length >= format.pickSize;

  /// Lock in (or change) the picks; order matters — the first
  /// [FormatSpec.fieldSlots] lead.
  void setPicks(List<PokemonBuild> newPicks) {
    picks
      ..clear()
      ..addAll(newPicks.take(format.pickSize));
    activePickIndexes.clear();
    for (var i = 0; i < format.fieldSlots && i < picks.length; i++) {
      activePickIndexes.add(i);
    }
  }

  /// Swap two POSITIONS among your picks (the arena's swap flow): the
  /// builds trade places while the active flags stay with the positions,
  /// so swapping an on-field spot with a reserve spot switches who is on
  /// the field, and swapping two same-zone spots just reorders them.
  void swapPickPositions(int a, int b) {
    if (a < 0 || b < 0 || a >= picks.length || b >= picks.length || a == b) {
      return;
    }
    final t = picks[a];
    picks[a] = picks[b];
    picks[b] = t;
  }

  List<PokemonBuild> get activeYours =>
      [for (final i in activePickIndexes) picks[i]];

  /// Your chosen Pokemon that are not currently on the field (the reserve
  /// icons on the battle tab). All known — they're your own picks.
  List<PokemonBuild> get yourReserves => [
        for (var i = 0; i < picks.length; i++)
          if (!activePickIndexes.contains(i)) picks[i]
      ];

  List<EnemyPokemon> get enemiesOnField =>
      enemies.where((e) => e.onField).toList();

  List<EnemyPokemon> get enemyBench => enemies.where((e) => !e.onField).toList();

  /// How many enemy reserves exist for this format (chosen minus on-field);
  /// e.g. doubles = 4 picked − 2 on field = 2. The reserve icons show the
  /// revealed benched enemies first, then predictions for the rest.
  int get enemyReserveCount =>
      (format.pickSize - format.fieldSlots).clamp(0, format.pickSize);

  /// Number of enemy reserve slots still unknown (predicted / "?").
  int get enemyUnknownReserveCount =>
      (enemyReserveCount - enemyBench.length).clamp(0, enemyReserveCount);

  /// Preview slot for a species, if the enemy roster has been scouted.
  PreviewSlot? previewSlotFor(String speciesId) {
    for (final s in enemyPreview) {
      if (s.speciesId == speciesId) return s;
    }
    return null;
  }

  EnemyPokemon addEnemy(String speciesId,
      {bool onField = true, bool mega = false, int? hpPercent}) {
    final existing = enemies.where((e) => e.speciesId == speciesId).firstOrNull;
    if (existing != null) {
      existing.onField = onField;
      if (hpPercent != null) existing.hpPercent = hpPercent;
      if (mega) existing.mega = true;
      return existing;
    }
    // Field slots are limited; benching the oldest if full.
    if (onField) {
      final onFieldNow = enemiesOnField;
      if (onFieldNow.length >= format.fieldSlots) {
        onFieldNow.first.onField = false;
      }
    }
    final enemy = EnemyPokemon(
        speciesId: speciesId, onField: onField, mega: mega, hpPercent: hpPercent);
    enemies.add(enemy);
    // A revealed enemy is confirmed knowledge of their roster too.
    final slot = previewSlotFor(speciesId);
    if (slot == null) {
      if (enemyPreview.length < format.teamSize) {
        enemyPreview.add(PreviewSlot(speciesId));
      }
    } else {
      slot.confirmed = true;
      slot.confidence = 1.0;
    }
    return enemy;
  }

  void removeEnemy(EnemyPokemon enemy) => enemies.remove(enemy);

  /// Snapshot of everything worth keeping in match history.
  Map<String, dynamic> toSnapshotJson() => {
        'formatId': format.id,
        'formatName': format.name,
        'teamName': team.name,
        'picks': [for (final p in picks) p.toJson()],
        'enemyPreview': [for (final s in enemyPreview) s.toJson()],
        'enemies': [for (final e in enemies) e.toJson()],
        if (speedEvidence.isNotEmpty) 'speedEvidence': speedEvidence,
      };
}
