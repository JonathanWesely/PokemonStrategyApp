/// Turns the battle screen's TEXT into intel. Pure Dart, unit-tested with
/// scripted OCR lines — the same seam as BattleTextMatcher.
///
/// The game prints everything that matters: "Froslass used Blizzard!",
/// "The opposing Umbreon's Inner Focus", "The opposing Sneasler hung on
/// using its Focus Sash!", "Grimmsnarl twisted the dimensions!". Reading
/// those lines every half second is the easiest reliable way to track a
/// match, so this class parses each frame's lines and writes what it learns
/// straight onto the BattleSession:
///
///   * "`<Name>` used `<Move>`!" -> enemy reveal ledger (revealedMoves) and a
///     speed-order observation: within one turn, whoever acts first in the
///     same priority bracket is the faster one — CONFIRMED, not predicted
///     (inverted while Trick Room is up). Speed ties are deliberately
///     ignored (per the v1 convention).
///   * "`<Name>`'s `<Ability>`" -> revealedAbility.
///   * a line naming a Pokemon and an item -> revealedItem.
///   * "twisted the dimensions" / "returned to normal" -> trickRoom flag.
///   * "Tailwind blew from behind ..." -> per-side tailwind flags.
///
/// The rig scans ~2x per second while a message stays on screen for
/// seconds, so every event is de-duplicated within [repeatWindow].
library;

import '../data/data_pack.dart';
import '../models/battle_state.dart';
import 'battle_ocr.dart';

/// One parsed, de-duplicated event — returned so the UI/status chip (and
/// the tests) can see what a frame taught us.
class BattleEvent {
  final String kind; // move | ability | item | trickroom | tailwind | speed
  final String description;

  const BattleEvent(this.kind, this.description);

  @override
  String toString() => '$kind: $description';
}

class BattleEventTracker {
  BattleEventTracker(this.pack, this.session,
      {this.repeatWindow = const Duration(seconds: 6),
      this.turnGap = const Duration(seconds: 25)})
      : _names = BattleTextMatcher(pack) {
    _moveByClean = {
      for (final m in pack.moves.values) _clean(m.name): m.id,
    };
    _abilityByClean = {
      for (final name in pack.abilities.keys) _clean(name): name,
    };
  }

  final DataPack pack;
  final BattleSession session;
  final Duration repeatWindow;

  /// A gap this long between move messages starts a new turn.
  final Duration turnGap;

  final BattleTextMatcher _names;
  late final Map<String, String> _moveByClean;
  late final Map<String, String> _abilityByClean;

  /// clean(line) -> last time it was seen (sliding: refreshed every frame,
  /// so a message that stays on screen never re-fires).
  final Map<String, DateTime> _seen = {};

  /// Moves seen this turn: actor key -> priority bracket.
  final List<(String key, int priority)> _turnMoves = [];
  DateTime? _lastMoveAt;

  static final _usedRe = RegExp(
      r'^(the\s+opposing\s+)?(.+?)\s+used\s+(.+?)\s*[.!]*$',
      caseSensitive: false);
  static final _possessiveRe =
      RegExp(r"^(the\s+opposing\s+)?(.+?)(?:['’]s|s)\s+(.+?)\s*[.!]*$",
          caseSensitive: false);

  static String _clean(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Feed one frame's OCR lines. Returns the NEW events (empty for a frame
  /// that only repeats what's already known).
  List<BattleEvent> consume(List<OcrLine> lines, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final events = <BattleEvent>[];
    for (final line in lines) {
      final raw = line.text.trim();
      if (raw.length < 6) continue;
      final key = _clean(raw);
      if (key.length < 6) continue;
      final last = _seen[key];
      _seen[key] = now;
      if (last != null && now.difference(last) < repeatWindow) continue;

      final e = _parseLine(raw, now);
      if (e != null) events.add(e);
    }
    _pruneSeen(now);
    return events;
  }

  BattleEvent? _parseLine(String raw, DateTime now) {
    return _parseUsedMove(raw, now) ??
        _parseFieldCondition(raw) ??
        _parseAbility(raw) ??
        _parseItem(raw);
  }

  // -------------------------------------------------------------- moves --

  BattleEvent? _parseUsedMove(String raw, DateTime now) {
    final m = _usedRe.firstMatch(raw);
    if (m == null) return null;
    final opposing = m.group(1) != null;
    final speciesId = _names.resolveName(m.group(2)!);
    if (speciesId == null) return null;
    final moveId = _resolveMove(m.group(3)!);
    if (moveId == null) return null;

    final enemySide = _isEnemy(speciesId, opposingPrefix: opposing);
    if (enemySide == null) return null; // same species both sides, no prefix
    if (enemySide) {
      final enemy = session.addEnemy(speciesId); // using a move = on field
      enemy.revealedMoves.add(moveId);
    }

    // Speed-order evidence: same turn + same priority bracket => the one
    // that moved first is faster (slower under Trick Room). One move per
    // Pokemon per turn, so a repeated actor (or a long silence) means a new
    // turn started.
    final actorKey = '${enemySide ? 'e' : 'y'}:$speciesId';
    final priority = pack.moveById(moveId)?.priority ?? 0;
    final gapped = _lastMoveAt != null && now.difference(_lastMoveAt!) > turnGap;
    if (gapped || _turnMoves.any((t) => t.$1 == actorKey)) {
      _turnMoves.clear();
    }
    for (final (earlierKey, earlierPriority) in _turnMoves) {
      if (earlierPriority != priority || earlierKey == actorKey) continue;
      if (session.trickRoom) {
        session.addSpeedEvidence(faster: actorKey, slower: earlierKey);
      } else {
        session.addSpeedEvidence(faster: earlierKey, slower: actorKey);
      }
    }
    _turnMoves.add((actorKey, priority));
    _lastMoveAt = now;

    return BattleEvent('move',
        '${enemySide ? 'enemy ' : ''}${pack.speciesName(speciesId)} used ${pack.moveName(moveId)}');
  }

  String? _resolveMove(String raw) {
    final q = _clean(raw);
    if (q.length < 3) return null;
    final exact = _moveByClean[q];
    if (exact != null) return exact;
    if (q.length < 6) return null;
    // OCR mangles a letter now and then: allow edit distance 1.
    String? best;
    for (final entry in _moveByClean.entries) {
      if ((entry.key.length - q.length).abs() > 1) continue;
      if (_editDistanceAtMost1(entry.key, q)) {
        if (best != null) return null; // ambiguous — don't guess
        best = entry.value;
      }
    }
    return best;
  }

  // ---------------------------------------------------- field conditions --

  BattleEvent? _parseFieldCondition(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('twisted the dimensions')) {
      session.trickRoom = true;
      return const BattleEvent('trickroom', 'Trick Room is up');
    }
    if (lower.contains('dimensions returned to normal') ||
        (lower.contains('twisted dimensions') && lower.contains('normal'))) {
      session.trickRoom = false;
      return const BattleEvent('trickroom', 'Trick Room ended');
    }
    if (lower.contains('tailwind blew')) {
      final enemy = lower.contains('opposing');
      if (enemy) {
        session.enemyTailwind = true;
      } else {
        session.yourTailwind = true;
      }
      return BattleEvent(
          'tailwind', enemy ? 'enemy Tailwind is up' : 'your Tailwind is up');
    }
    if (lower.contains('tailwind petered out')) {
      final enemy = lower.contains('opposing');
      if (enemy) {
        session.enemyTailwind = false;
      } else {
        session.yourTailwind = false;
      }
      return BattleEvent(
          'tailwind', enemy ? 'enemy Tailwind ended' : 'your Tailwind ended');
    }
    return null;
  }

  // ----------------------------------------------------------- abilities --

  BattleEvent? _parseAbility(String raw) {
    final m = _possessiveRe.firstMatch(raw);
    if (m == null) return null;
    final ability = _abilityByClean[_clean(m.group(3)!)];
    if (ability == null) return null;
    final speciesId = _names.resolveName(m.group(2)!);
    if (speciesId == null) return null;
    final enemySide = _isEnemy(speciesId, opposingPrefix: m.group(1) != null);
    if (enemySide != true) return null; // only the enemy ledger needs this
    final enemy = session.addEnemy(speciesId);
    enemy.revealedAbility = ability;
    return BattleEvent(
        'ability', 'enemy ${pack.speciesName(speciesId)} has $ability');
  }

  // --------------------------------------------------------------- items --

  BattleEvent? _parseItem(String raw) {
    final lower = ' ${raw.toLowerCase()} ';
    String? itemId;
    var itemLen = 0;
    for (final item in pack.items.values) {
      final name = item.name.toLowerCase();
      if (name.length < 4) continue;
      if (_containsWord(lower, name) && name.length > itemLen) {
        itemId = item.id;
        itemLen = name.length;
      }
    }
    if (itemId == null) return null;
    // Which Pokemon? Prefer one already named in the line.
    String? speciesId;
    var speciesLen = 0;
    for (final s in pack.species.values) {
      final name = s.name.toLowerCase();
      if (name.length < 4) continue;
      if (_containsWord(lower, name) && name.length > speciesLen) {
        speciesId = s.id;
        speciesLen = name.length;
      }
    }
    if (speciesId == null) return null;
    final enemySide = _isEnemy(speciesId,
        opposingPrefix: lower.contains(' opposing '));
    if (enemySide != true) return null;
    final enemy = session.addEnemy(speciesId);
    enemy.revealedItem = itemId;
    return BattleEvent('item',
        'enemy ${pack.speciesName(speciesId)} holds ${pack.itemName(itemId)}');
  }

  static bool _containsWord(String haystackPadded, String needle) {
    var from = 0;
    while (true) {
      final i = haystackPadded.indexOf(needle, from);
      if (i < 0) return false;
      final before = haystackPadded.codeUnitAt(i - 1);
      final afterIndex = i + needle.length;
      final after = afterIndex < haystackPadded.length
          ? haystackPadded.codeUnitAt(afterIndex)
          : 32;
      final beforeOk = !_isAlnum(before);
      final afterOk = !_isAlnum(after);
      if (beforeOk && afterOk) return true;
      from = i + 1;
    }
  }

  static bool _isAlnum(int c) =>
      (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122);

  /// True when [a] and [b] differ by at most one substitution, insertion or
  /// deletion. Cheap special case — no DP table needed.
  static bool _editDistanceAtMost1(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    final (long, short) = a.length >= b.length ? (a, b) : (b, a);
    var i = 0, j = 0, edits = 0;
    while (i < long.length && j < short.length) {
      if (long.codeUnitAt(i) == short.codeUnitAt(j)) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (long.length == short.length) {
        i++;
        j++; // substitution
      } else {
        i++; // deletion from the longer string
      }
    }
    edits += (long.length - i) + (short.length - j);
    return edits <= 1;
  }

  // --------------------------------------------------------------- sides --

  /// true = enemy, false = yours, null = can't tell (skip).
  bool? _isEnemy(String speciesId, {required bool opposingPrefix}) {
    if (opposingPrefix) return true;
    final yours = session.picks.any((p) => p.speciesId == speciesId) ||
        session.team.builds.any((b) => b.speciesId == speciesId);
    final theirs = session.enemies.any((e) => e.speciesId == speciesId) ||
        session.enemyPreview.any((s) => s.speciesId == speciesId);
    if (yours && theirs) return null; // mirror match, no prefix — ambiguous
    if (yours) return false;
    // Not yours: it's the enemy (their names print without "opposing" too
    // once context is unambiguous, and an unknown species using a move can
    // only be theirs).
    return true;
  }

  void _pruneSeen(DateTime now) {
    if (_seen.length < 200) return;
    _seen.removeWhere(
        (_, t) => now.difference(t) > repeatWindow * 4);
  }
}
