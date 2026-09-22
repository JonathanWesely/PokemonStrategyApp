/// Battle-screen text recognition support for the Local engine. Pure Dart:
/// the actual OCR runs behind [TextOcr] (ML Kit on device, fakes in tests);
/// everything here — name resolution, side assignment, HP parsing — is
/// deterministic and unit-tested against transcribed fixture text.
library;

import 'dart:typed_data';

import '../data/data_pack.dart';
import '../models/recognition_result.dart';
import 'recognition_service.dart';

/// One line of recognized text with its normalized center (0–1 in both axes,
/// y grows downward) and, when the engine provides it, its normalized box
/// size ([w]/[h] are 0 when unknown — the team scanner degrades gracefully).
class OcrLine {
  final String text;
  final double cx;
  final double cy;
  final double w;
  final double h;

  const OcrLine(this.text,
      {required this.cx, required this.cy, this.w = 0, this.h = 0});
}

/// The seam to the platform OCR engine. mlkit_ocr.dart implements this with
/// google_mlkit_text_recognition; tests hand in scripted lines.
abstract class TextOcr {
  Future<List<OcrLine>> readLines(Uint8List imageBytes);
}

/// Turns OCR lines from the battle screen into recognized Pokemon.
///
/// The Champions battle screen shows enemy name banners in the TOP part of
/// the frame and your own in the BOTTOM part. Names are matched fuzzily
/// against the pack roster (OCR mangles letters); your picks are used to
/// force side assignment when a name matches one of them.
class BattleTextMatcher {
  final DataPack pack;

  const BattleTextMatcher(this.pack);

  List<RecognizedPokemon> match(
      List<OcrLine> lines, BattleSnapshotContext context) {
    final found = <String, RecognizedPokemon>{};
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final speciesId = resolveName(line.text);
      if (speciesId == null || found.containsKey(speciesId)) continue;
      final inYourPicks = context.yourSpeciesIds.contains(speciesId);
      final side = inYourPicks
          ? BattleSide.yours
          : (line.cy < 0.5 ? BattleSide.enemy : BattleSide.yours);
      // Only report enemies we're confident about: an unknown name in the
      // bottom half is more likely your nicknamed Pokemon than an enemy.
      if (side == BattleSide.yours && !inYourPicks) continue;
      found[speciesId] = RecognizedPokemon(
        speciesId: speciesId,
        side: side,
        confidence: 0.9,
        hpPercent: _hpNear(lines, i),
      );
    }
    return found.values.toList();
  }

  /// Fuzzy roster lookup: exact (case/punctuation-insensitive), then
  /// edit-distance <= 2 for names of length >= 5. Public because the
  /// battle-event tracker resolves "`<Name>` used `<Move>`!" lines with the
  /// same rules.
  String? resolveName(String raw) {
    final q = _clean(raw);
    if (q.length < 3) return null;
    // Reject obvious UI words fast.
    const uiWords = {
      'fight', 'pokemon', 'battleinfo', 'movetime', 'snow', 'rain', 'sun',
      'sandstorm', 'run', 'showsummary', 'standingby', 'cancel',
    };
    if (uiWords.contains(q)) return null;
    for (final s in pack.species.values) {
      if (_clean(s.name) == q || s.id.replaceAll('-', '') == q) return s.id;
    }
    // Formes: the game shows "Floette", the pack id is floette-eternal —
    // accept a prefix match on the display name or the id either way.
    for (final s in pack.species.values) {
      final name = _clean(s.name);
      final id = s.id.replaceAll('-', '');
      if (q.length >= 5 &&
          (name.startsWith(q) ||
              q.startsWith(name) ||
              id.startsWith(q) ||
              q.startsWith(id))) {
        return s.id;
      }
    }
    for (final s in pack.species.values) {
      final name = _clean(s.name);
      if (q.length >= 5 &&
          (name.length - q.length).abs() <= 2 &&
          _editDistance(q, name, max: 2) <= 2) {
        return s.id;
      }
    }
    return null;
  }

  static String _clean(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  /// HP percent from the NEAREST matching line: "44%", "44 %", "177/202".
  /// Nearest matters — the two enemy banners sit side by side, so a
  /// first-match scan can grab the neighbor's HP.
  int? _hpNear(List<OcrLine> lines, int i) {
    final anchor = lines[i];
    int? best;
    var bestDist = double.infinity;
    for (final line in lines) {
      final dy = (line.cy - anchor.cy).abs();
      final dx = (line.cx - anchor.cx).abs();
      if (dy > 0.08 || dx > 0.25) continue;
      int? value;
      final pct = RegExp(r'(\d{1,3})\s*%').firstMatch(line.text);
      if (pct != null) {
        final v = int.parse(pct.group(1)!);
        if (v >= 0 && v <= 100) value = v;
      }
      if (value == null) {
        final frac =
            RegExp(r'(\d{1,3})\s*/\s*(\d{1,3})').firstMatch(line.text);
        if (frac != null) {
          final cur = int.parse(frac.group(1)!);
          final max = int.parse(frac.group(2)!);
          if (max > 0 && cur <= max) value = (cur * 100 / max).round();
        }
      }
      if (value == null) continue;
      final dist = dx * dx + dy * dy;
      if (dist < bestDist) {
        bestDist = dist;
        best = value;
      }
    }
    return best;
  }

  static int _editDistance(String a, String b, {int max = 2}) {
    if ((a.length - b.length).abs() > max) return max + 1;
    final m = a.length, n = b.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0);
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (cur[j] < rowMin) rowMin = cur[j];
      }
      if (rowMin > max) return max + 1;
      prev = cur;
    }
    return prev[n];
  }
}
