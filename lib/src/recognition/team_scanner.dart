/// Scan Team: turn the two Champions team-display photos ("Moves & More" +
/// "Stats") into a ready-to-edit [Team]. Pure Dart (package:image) + the
/// injected [TextOcr] seam, so the whole pipeline runs in plain
/// `flutter test` against the fixture photos.
///
/// How each part reads (prototyped on the four 2026-09-21 fixture photos —
/// tool/team_scan/proto.py & detect.py):
///
///  * CARDS — the six lavender cards are found by a purple chromaticity
///    mask on a 1200 px detection copy (blue clearly above red and green),
///    filtered by height, ordered row-major = the on-screen 1..6 numbers.
///    The purple header band above them holds the TEAM NAME (left of the
///    avatar; the tab labels are filtered out).
///  * TEXT — one OCR pass per image; lines are assigned to cards by
///    position. Moves card: name in the strip, ability/item down the left,
///    up to four moves right of 55% width. Stats card: six labelled rows,
///    each "label … stat — sp".
///  * SPECIES — the printed name resolves against the roster first. A name
///    that maps to a form FAMILY (Rotom, Tauros, Indeedee…) is settled by
///    sprite DETECTION among just that family; a name that resolves to
///    nothing (nickname) runs detection against all 262 references and the
///    slot is flagged for review. Detection slides each reference tile
///    (masked NCC, template's own alpha as the mask, several display
///    scales) over the card-corner icon window — no segmentation, so white
///    sprites on cream and purple ones on the card don't fall apart
///    (20/24 alone on the fixture cards; names settle the rest).
///  * GENDER — no text: the ♂/♀ circle right after the name is classified
///    by color (royal blue / pink-red). Type badges sit right-aligned much
///    further along the strip, so a colored blob only counts as a gender
///    symbol close after the name box (a genderless Rotom's Electric badge
///    is not close). Unreadable -> left unset.
///  * NATURE — no text either, and the ▲/▼ arrows are tiny: the nature is
///    INFERRED FROM THE MATH. At level 50 each displayed stat equals
///    StatCalculator's formula under exactly one of x0.9 / x1.0 / x1.1, so
///    the boosted and hindered stats identify the nature — and every stat
///    double-checks the OCR (a stat that verifies under no multiplier, or
///    a missing SP number, is re-solved or flagged).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../data/data_pack.dart';
import '../data/stat_calculator.dart';
import '../models/nature.dart';
import '../models/pokemon_build.dart';
import '../models/species.dart';
import '../models/team.dart';
import 'battle_ocr.dart';
import 'champions_atlas.dart';
import 'sprite_matcher.dart' show ByteLoader;

/// One scanned slot: the build plus everything the review UI should show.
class ScannedSlot {
  final PokemonBuild build;

  /// True when the species came from the printed name (or a one-candidate
  /// family); false = sprite detection decided (nickname) — review it.
  final bool speciesFromName;

  /// Sprite-detection runners-up (display names), best first.
  final List<String> alternatives;

  final List<String> warnings;

  const ScannedSlot(this.build,
      {required this.speciesFromName,
      this.alternatives = const [],
      this.warnings = const []});
}

class ScannedTeam {
  final Team team;
  final List<ScannedSlot> slots;

  /// Image-level problems (missing cards, unreadable header, …).
  final List<String> warnings;

  const ScannedTeam(this.team, this.slots, this.warnings);

  List<String> get allWarnings => [
        ...warnings,
        for (final s in slots) ...s.warnings,
      ];
}

/// Everything a TEAM BUILD SCAN saw, for the diagnostics dump
/// (`documents/last_team_scan/`): both input photos, the card boxes and
/// OCR lines found in each, and the final result. Fired once per scan —
/// including failed ones, where cards/lines may be empty.
class TeamScanDebug {
  final Uint8List movesImage;
  final Uint8List statsImage;
  final List<List<int>> movesCards;
  final List<List<int>> statsCards;
  final List<OcrLine> movesLines;
  final List<OcrLine> statsLines;
  final ScannedTeam result;

  const TeamScanDebug({
    required this.movesImage,
    required this.statsImage,
    required this.movesCards,
    required this.statsCards,
    required this.movesLines,
    required this.statsLines,
    required this.result,
  });
}

class TeamScanner {
  TeamScanner(this.pack, {required this.loadBytes});

  final DataPack pack;
  final ByteLoader loadBytes;

  static const detectWidth = 1200;

  ChampionsReferenceSet? _refs;
  bool _refsTried = false;

  Future<ChampionsReferenceSet?> _loadRefs() async {
    if (_refsTried) return _refs;
    _refsTried = true;
    return _refs = await ChampionsReferenceSet.load(loadBytes);
  }

  Future<ScannedTeam> scan({
    required Uint8List movesImage,
    required Uint8List statsImage,
    required TextOcr ocr,
    void Function(TeamScanDebug)? onDebug,
  }) async {
    // Every exit goes through this, so failed scans get diagnosed too.
    ScannedTeam finish(
      ScannedTeam r, {
      List<List<int>> mc = const [],
      List<List<int>> sc = const [],
      List<OcrLine> ml = const [],
      List<OcrLine> sl = const [],
    }) {
      onDebug?.call(TeamScanDebug(
        movesImage: movesImage,
        statsImage: statsImage,
        movesCards: mc,
        statsCards: sc,
        movesLines: ml,
        statsLines: sl,
        result: r,
      ));
      return r;
    }

    final warnings = <String>[];
    final moves = _decode(movesImage);
    final stats = _decode(statsImage);
    if (moves == null || stats == null) {
      return finish(ScannedTeam(Team(name: 'Scanned team'), const [],
          ['Could not decode one of the images.']));
    }
    final movesCards = findTeamCards(moves);
    final statsCards = findTeamCards(stats);
    if (movesCards.isEmpty) {
      return finish(
          ScannedTeam(Team(name: 'Scanned team'), const [],
              ['No team cards found in the Moves & More image — make sure '
                  'the whole screen is in frame.']),
          mc: movesCards,
          sc: statsCards);
    }
    if (movesCards.length != statsCards.length) {
      warnings.add('Found ${movesCards.length} cards in the Moves & More '
          'image but ${statsCards.length} in the Stats image — slots were '
          'paired by position, double-check them.');
    }

    final movesLines = await ocr.readLines(movesImage);
    final statsLines = await ocr.readLines(statsImage);

    final teamName = _teamName(moves, movesCards, movesLines) ??
        _teamName(stats, statsCards, statsLines);
    if (teamName == null) {
      warnings.add('Could not read the team name from the header — '
          'name it yourself.');
    }

    final refs = await _loadRefs();
    if (refs == null) {
      warnings.add('Sprite references unavailable — nicknamed Pokemon '
          'cannot be identified.');
    }

    final slots = <ScannedSlot>[];
    for (var i = 0; i < movesCards.length && i < 6; i++) {
      slots.add(await _scanSlot(
        index: i,
        moves: moves,
        movesCard: movesCards[i],
        movesLines: movesLines,
        stats: stats,
        statsCard: i < statsCards.length ? statsCards[i] : null,
        statsLines: statsLines,
        refs: refs,
      ));
    }
    if (slots.length < 6) {
      warnings.add('Only ${slots.length} of 6 Pokemon were found.');
    }

    final team = Team(
      name: teamName ?? 'Scanned team',
      builds: [for (final s in slots) s.build],
    );
    return finish(ScannedTeam(team, slots, warnings),
        mc: movesCards, sc: statsCards, ml: movesLines, sl: statsLines);
  }

  img.Image? _decode(Uint8List bytes) {
    final raw = img.decodeImage(bytes);
    if (raw == null) return null;
    return img.bakeOrientation(raw); // phone photos carry EXIF rotation
  }

  // ------------------------------------------------------------- cards --

  /// The six card rects in ORIGINAL pixels, row-major (the 1..6 order).
  static List<List<int>> findTeamCards(img.Image photo) {
    final w = photo.width;
    final k = w > detectWidth ? w / detectWidth : 1.0;
    final small = k > 1.0
        ? img.copyResize(photo,
            width: detectWidth, interpolation: img.Interpolation.linear)
        : photo;
    final sw = small.width, sh = small.height;
    final mask = Uint8List(sw * sh);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        if (b > r + 30 && b > g + 45 && b > 130 && r > 60) {
          mask[y * sw + x] = 1;
        }
      }
    }
    // connected components (4-conn), keep card-shaped ones
    final label = Int32List(sw * sh);
    var next = 0;
    final boxes = <List<int>>[]; // x0,y0,x1,y1,area per component
    final stack = <int>[];
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0 || label[i] != 0) continue;
      next++;
      var x0 = sw, y0 = sh, x1 = 0, y1 = 0, area = 0;
      stack.add(i);
      label[i] = next;
      while (stack.isNotEmpty) {
        final j = stack.removeLast();
        final x = j % sw, y = j ~/ sw;
        area++;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        for (final n in [j - 1, j + 1, j - sw, j + sw]) {
          if (n < 0 || n >= mask.length) continue;
          if ((j % sw == 0 && n == j - 1) || (j % sw == sw - 1 && n == j + 1)) {
            continue;
          }
          if (mask[n] == 1 && label[n] == 0) {
            label[n] = next;
            stack.add(n);
          }
        }
      }
      if (area < 0.004 * sw * sh) continue;
      final bw = x1 - x0, bh = y1 - y0;
      if (bh >= 0.055 * sh && bw > 2.5 * bh) {
        boxes.add([x0, y0, x1, y1, area]);
      }
    }
    boxes.sort((a, b) => a[1].compareTo(b[1]));
    // group into rows, sort each row left-to-right
    final ordered = <List<int>>[];
    var row = <List<int>>[];
    for (final b in boxes) {
      if (row.isNotEmpty && b[1] - row.last[1] > 0.5 * (row.last[3] - row.last[1])) {
        row.sort((a, c) => a[0].compareTo(c[0]));
        ordered.addAll(row);
        row = [];
      }
      row.add(b);
    }
    row.sort((a, c) => a[0].compareTo(c[0]));
    ordered.addAll(row);
    return [
      for (final b in ordered)
        [
          (b[0] * k).round(),
          (b[1] * k).round(),
          (b[2] * k).round(),
          (b[3] * k).round(),
        ]
    ];
  }

  // --------------------------------------------------------- team name --

  String? _teamName(
      img.Image photo, List<List<int>> cards, List<OcrLine> lines) {
    if (cards.isEmpty) return null;
    final topY = cards.first[1] / photo.height;
    String? best;
    var bestCy = -1.0;
    for (final l in lines) {
      if (l.cy >= topY - 0.005 || l.cx > 0.48) continue;
      final t = l.text.trim();
      final c = _clean(t);
      if (t.length < 2 || c.isEmpty) continue;
      if (const {'movesmore', 'moves', 'stats', 'more', 'movesamore'}
          .contains(c)) {
        continue;
      }
      if (l.cy > bestCy) {
        bestCy = l.cy;
        best = t;
      }
    }
    return best;
  }

  // -------------------------------------------------------------- slot --

  Future<ScannedSlot> _scanSlot({
    required int index,
    required img.Image moves,
    required List<int> movesCard,
    required List<OcrLine> movesLines,
    required img.Image stats,
    required List<int>? statsCard,
    required List<OcrLine> statsLines,
    required ChampionsReferenceSet? refs,
  }) async {
    final warnings = <String>[];
    final card = movesCard;
    final inCard = _linesIn(movesLines, moves, card, padTop: 0.05);

    // name = the top-left line of the strip. Only the left 35% of the
    // strip can hold name text — the gender circle sits at fx ~0.42 and
    // the badges at 0.4575+, and on a TV photo their glyphs OCR into
    // short junk ("G3" for Charizard's ♂+Fire) that can land a few
    // PIXELS above the real name, which the topmost rule then loses to.
    // Two letters minimum: a stray glyph reads as "G3"/"O", a name
    // never does.
    OcrLine? nameLine;
    for (final l in inCard) {
      final fy = _fy(l, moves, card), fx = _fx(l, moves, card);
      final letters = RegExp('[a-zA-Z]').allMatches(l.text).length;
      if (fy < 0.32 && fx < 0.35 && letters >= 2) {
        if (nameLine == null || fy < _fy(nameLine, moves, card)) nameLine = l;
      }
    }
    final rawName = nameLine?.text.trim() ?? '';

    // ---- species: printed name first, sprite detection for families and
    // nicknames ----
    String? speciesId;
    var fromName = false;
    var alternatives = const <String>[];
    final resolved =
        rawName.isEmpty ? null : BattleTextMatcher(pack).resolveName(rawName);
    if (resolved != null) {
      final family = _formFamily(resolved);
      if (family.length <= 1 || refs == null) {
        speciesId = resolved;
        fromName = true;
        if (family.length > 1) {
          warnings.add('${_slotTag(index)}: "$rawName" has several forms and '
              'sprites were unavailable — took ${pack.speciesName(resolved)}.');
        }
      } else {
        // The card's own type badges settle a family whose members differ
        // in typing — Blaze vs Aqua Tauros is Fire vs Water, whole
        // colours, where the sprites differ by pixels at tile size.
        final byBadge = familyFromBadges(moves, card, family, refs);
        if (byBadge != null) {
          speciesId = byBadge;
          fromName = true;
        } else {
          // Same-type families (Indeedee, Lycanroc…) and unreadable
          // badges fall back to sprite detection at high working
          // resolution; a near-tie there is imported but flagged.
          final ranked =
              detectSprite(moves, card, refs, onlySpecies: family, chPx: 160);
          speciesId = ranked.isEmpty ? resolved : ranked.first.$2;
          fromName = true; // the family came from the name
          if (ranked.length > 1 && ranked[0].$1 - ranked[1].$1 < 0.05) {
            alternatives = [
              for (final r in ranked.skip(1).take(3)) pack.speciesName(r.$2)
            ];
            warnings.add('${_slotTag(index)}: the "$rawName" forms look '
                'almost identical here — took ${pack.speciesName(speciesId)}, '
                'check it.');
          }
        }
      }
    } else if (refs != null) {
      // Nickname: coarse full-roster pass, then re-rank the leaders at
      // high resolution.
      var ranked = detectSprite(moves, card, refs, chPx: 96);
      if (ranked.length > 1) {
        final leaders = {for (final r in ranked.take(12)) r.$2};
        final refined =
            detectSprite(moves, card, refs, onlySpecies: leaders, chPx: 160);
        if (refined.isNotEmpty) ranked = refined;
      }
      if (ranked.isNotEmpty) {
        speciesId = ranked.first.$2;
        // If the sprite's pick belongs to a family, let the card's type
        // badges correct the FORM (the sprite already chose the family;
        // Blaze vs Aqua is a coin flip at tile size but Fire vs Water on
        // the badges).
        var badgeCorrected = false;
        final fam = _formFamily(speciesId);
        if (fam.length > 1) {
          final byBadge = familyFromBadges(moves, card, fam, refs);
          if (byBadge != null && byBadge != speciesId) {
            speciesId = byBadge;
            badgeCorrected = true;
          }
        }
        alternatives = [
          for (final r in ranked.skip(1).take(3))
            if (r.$2 != speciesId) pack.speciesName(r.$2)
        ];
        warnings.add('${_slotTag(index)}: "$rawName" is not a species name — '
            'identified by '
            '${badgeCorrected ? 'sprite + type badges' : 'sprite'} as '
            '${pack.speciesName(speciesId)}. Double-check it.');
      }
    }
    if (speciesId == null) {
      warnings.add('${_slotTag(index)}: could not identify this Pokemon.');
      return ScannedSlot(PokemonBuild(speciesId: 'unknown'),
          speciesFromName: false, warnings: warnings);
    }
    final species = pack.speciesById(speciesId);

    // ---- ability + item (left column) and moves (right column) ----
    String ability = '';
    String? itemId;
    final moveIds = <String>[];
    final leftLines = <OcrLine>[];
    final rightLines = <OcrLine>[];
    for (final l in inCard) {
      if (identical(l, nameLine)) continue;
      final fx = _fx(l, moves, card);
      final fy = _fy(l, moves, card);
      if (_clean(l.text).isEmpty) continue;
      if (fx < 0.5 && fy > 0.25) leftLines.add(l);
      if (fx >= 0.52) rightLines.add(l);
    }
    leftLines.sort(
        (a, b) => _fy(a, moves, card).compareTo(_fy(b, moves, card)));
    if (leftLines.isNotEmpty) {
      final raw = leftLines.first.text.trim();
      ability = _matchAbility(raw) ?? raw;
      if (_matchAbility(raw) == null) {
        warnings.add('${_slotTag(index)}: ability "$raw" is not in the '
            'ability list — saved as written.');
      }
    }
    if (leftLines.length > 1) {
      final raw = leftLines[1].text.trim();
      itemId = _matchItem(raw);
      if (itemId == null && raw.isNotEmpty) {
        itemId = _slug(raw);
        warnings.add('${_slotTag(index)}: item "$raw" is not in the item '
            'list — saved by name.');
      }
    }
    rightLines.sort(
        (a, b) => _fy(a, moves, card).compareTo(_fy(b, moves, card)));
    for (final l in rightLines) {
      if (moveIds.length >= 4) break;
      final raw = l.text.trim();
      if (RegExp(r'^\d+$').hasMatch(_clean(raw))) continue; // card number
      final id = _matchMove(raw);
      if (id != null) {
        if (!moveIds.contains(id)) moveIds.add(id);
      } else if (_clean(raw).length >= 4) {
        warnings.add('${_slotTag(index)}: move "$raw" was not recognized.');
      }
    }

    // ---- gender (color of the circle right after the name) ----
    final gender = nameLine == null
        ? null
        : readGender(moves, card, nameLine);

    // ---- stats image: SP + nature via the level-50 math ----
    var sp = <String, int>{};
    var natureName = 'Serious';
    if (statsCard != null && species != null) {
      final rows = parseStatRows(
          _linesIn(statsLines, stats, statsCard, padTop: 0.02),
          stats,
          statsCard);
      final solved = solveSpAndNature(rows, species.baseStats);
      sp = solved.sp;
      natureName = solved.nature;
      warnings.addAll(solved.warnings.map((w) => '${_slotTag(index)}: $w'));
    } else if (statsCard == null) {
      warnings.add('${_slotTag(index)}: no matching card in the Stats image.');
    }

    // ---- mega forme from the held stone ----
    String? megaFormeId;
    if (species != null && itemId != null) {
      for (final m in species.megas) {
        if (m.item == itemId) megaFormeId = m.id;
      }
    }

    final isNickname = !fromName &&
        rawName.isNotEmpty &&
        species != null &&
        _clean(rawName) != _clean(species.name);
    final build = PokemonBuild(
      speciesId: speciesId,
      nickname: isNickname ? rawName : null,
      moveIds: moveIds,
      ability: ability,
      itemId: itemId,
      nature: natureName,
      sp: sp,
      megaFormeId: megaFormeId,
      gender: gender,
    );
    return ScannedSlot(build,
        speciesFromName: fromName,
        alternatives: alternatives,
        warnings: warnings);
  }

  static String _slotTag(int index) => 'Slot ${index + 1}';

  // ------------------------------------------------- stats-card parsing --

  /// label key -> (statValue, spValue or null) for the six rows.
  static Map<String, (int, int?)> parseStatRows(
      List<OcrLine> lines, img.Image photo, List<int> card) {
    const labels = {
      'hp': 'hp',
      'attack': 'atk',
      'defense': 'def',
      'spatk': 'spa',
      'spdef': 'spd',
      'speed': 'spe',
    };
    double fxOf(OcrLine o) =>
        (o.cx * photo.width - card[0]) / (card[2] - card[0]);
    final out = <String, (int, int?)>{};
    for (final l in lines) {
      final c = _clean(l.text);
      // On a TV photo the row icon and the ▲/▼ nature arrows OCR INTO
      // the label ("kAttack", "O Sp. Atk", "7 Speed A", "Atack &"), so
      // the key is matched anywhere inside the cleaned text, with one
      // edit allowed for keys long enough to stay unambiguous. Every
      // "row was unreadable" on the 2026-09-27 iPhone scan was this —
      // the numbers themselves were all present.
      String? key;
      var ambiguous = false;
      for (final e in labels.entries) {
        final hit = c.contains(e.key) ||
            (e.key.length >= 5 && _containsWithinOneEdit(c, e.key));
        if (hit) {
          if (key != null && key != e.value) ambiguous = true;
          key = e.value;
        }
      }
      if (key == null || ambiguous || out.containsKey(key)) continue;
      // numbers on the same row, right of the label, in the label's own
      // HALF of the card — OCR rows span both columns, and Whimsicott's
      // HP once took the Sp.Atk column's 32 as its SP.
      final labelLeft = fxOf(l) < 0.5;
      final nums = <(double, int)>[];
      for (final n in lines) {
        if ((n.cy - l.cy).abs() > 0.011) continue;
        if (n.cx <= l.cx) continue;
        if (labelLeft ? fxOf(n) >= 0.52 : fxOf(n) < 0.5) continue;
        for (final m in RegExp(r'\d{1,3}').allMatches(n.text)) {
          final v = int.parse(m.group(0)!);
          nums.add((n.cx + m.start * 0.0001, v));
        }
      }
      nums.sort((a, b) => a.$1.compareTo(b.$1));
      int? stat;
      int? spv;
      for (final (_, v) in nums) {
        if (stat == null && v >= 40 && v <= 300) {
          stat = v;
        } else if (stat != null && v <= 39) {
          spv = v;
          break;
        }
      }
      if (stat != null) out[key] = (stat, spv);
    }
    return out;
  }

  /// Infer SP + nature from displayed stats; verify with the exact level-50
  /// math (each stat matches exactly one of x0.9/x1.0/x1.1).
  static ({Map<String, int> sp, String nature, List<String> warnings})
      solveSpAndNature(Map<String, (int, int?)> rows, BaseStats base) {
    final sp = <String, int>{};
    final warnings = <String>[];
    final unsettled = <String>[]; // rows unread or failing the math
    String? plus;
    String? minus;
    for (final key in statKeys) {
      final row = rows[key];
      if (row == null) {
        warnings.add('the $key row was unreadable');
        if (key != 'hp') unsettled.add(key);
        continue;
      }
      final (shown, spShownRaw) = row;
      final b = base.byKey(key);
      bool verifies(int spv, int nat) => key == 'hp'
          ? StatCalculator.hpStat(b, spv) == shown
          : StatCalculator.otherStat(b, spv, nat) == shown;
      final natsToTry = key == 'hp' ? const [100] : const [110, 100, 90];
      int? goodSp;
      int? goodNat;
      final spShown = spShownRaw;
      if (spShown != null) {
        for (final nat in natsToTry) {
          if (verifies(spShown, nat)) {
            goodSp = spShown;
            goodNat = nat;
            break;
          }
        }
      }
      if (goodSp == null) {
        // OCR dropped or mangled the SP number: solve it from the stat.
        final solutions = <(int, int)>[];
        for (final nat in natsToTry) {
          for (var s = 0; s <= 32; s++) {
            if (verifies(s, nat)) solutions.add((s, nat));
          }
        }
        if (solutions.length == 1) {
          goodSp = solutions.single.$1;
          goodNat = solutions.single.$2;
          if (spShown != null) {
            warnings.add('the $key SP read as $spShown but only '
                '${solutions.single.$1} matches the shown stat $shown — '
                'used ${solutions.single.$1}');
          }
        } else if (solutions.isEmpty) {
          // The stat DIGITS may be the misread — TV blur turns 6/8/9
          // into 0 and so on (three Sp.Def rows failed exactly this way
          // on the 2026-10-01 scan). Try single-digit confusion variants
          // of the shown value and accept only a UNIQUE
          // (stat, SP, nature) explanation: the same math-does-the-
          // checking spirit as the SP re-solve above.
          final fixes = <(int, int, int)>[];
          for (final v in _digitConfusions(shown)) {
            for (final nat in natsToTry) {
              for (var s = 0; s <= 32; s++) {
                final ok = key == 'hp'
                    ? StatCalculator.hpStat(b, s) == v
                    : StatCalculator.otherStat(b, s, nat) == v;
                if (ok) fixes.add((v, s, nat));
              }
            }
          }
          if (fixes.length == 1) {
            goodSp = fixes.single.$2;
            goodNat = fixes.single.$3;
            warnings.add('the $key stat read as $shown but only '
                '${fixes.single.$1} verifies against the level-50 math — '
                'corrected');
          } else {
            warnings.add('the $key stat $shown did not verify against '
                'the level-50 math — check it');
            if (key != 'hp') unsettled.add(key);
            goodSp = spShown ?? 0;
          }
        } else {
          warnings.add('the $key stat $shown did not verify against the '
              'level-50 math — check it');
          if (key != 'hp') unsettled.add(key);
          goodSp = spShown ?? 0;
        }
      }
      sp[key] = goodSp;
      if (goodNat == 110) {
        if (plus != null && plus != key) {
          warnings.add('two stats look nature-boosted ($plus and $key)');
        }
        plus = key;
      } else if (goodNat == 90) {
        if (minus != null && minus != key) {
          warnings.add('two stats look nature-hindered ($minus and $key)');
        }
        minus = key;
      }
    }
    sp.removeWhere((_, v) => v == 0);
    // Half a nature is still a nature when exactly one row escaped the
    // math: every READABLE stat verified neutral, so the missing partner
    // must be the one row that didn't — a dead OCR row no longer costs
    // the nature (it cost four of six slots on the 2026-09-27 scan).
    if (plus != null && minus == null) {
      final cands = unsettled.where((k) => k != plus).toList();
      if (cands.length == 1 &&
          natures.any((n) => n.plus == plus && n.minus == cands.single)) {
        minus = cands.single;
        warnings.add('the ${cands.single} row could not be verified — the '
            'boosted $plus leaves only one nature, so it must be hindered');
      }
    } else if (minus != null && plus == null) {
      final cands = unsettled.where((k) => k != minus).toList();
      if (cands.length == 1 &&
          natures.any((n) => n.minus == minus && n.plus == cands.single)) {
        plus = cands.single;
        warnings.add('the ${cands.single} row could not be verified — the '
            'hindered $minus leaves only one nature, so it must be boosted');
      }
    }
    String natureName = 'Serious';
    if (plus != null || minus != null) {
      final match = natures.where((n) => n.plus == plus && n.minus == minus);
      if (match.isNotEmpty) {
        natureName = match.first.name;
      } else {
        warnings.add('the boosted/hindered stats (+$plus/-$minus) match no '
            'nature — set to Serious');
      }
    }
    return (sp: sp, nature: natureName, warnings: warnings);
  }

  // ------------------------------------------------------------ gender --

  /// Classify the small circle right after the name text: royal blue = ♂,
  /// pink-red = ♀. Type badges sit right-aligned much further along the
  /// strip, so only a blob CLOSE after the name box counts.
  static String? readGender(
      img.Image photo, List<int> card, OcrLine nameLine) {
    final x0 = card[0], y0 = card[1];
    final cw = card[2] - x0, ch = card[3] - y0;
    final stripH = (0.24 * ch).round();
    final nameRight = nameLine.w > 0
        ? ((nameLine.cx + nameLine.w / 2) * photo.width).round()
        : (x0 + 0.40 * cw).round();
    final zx0 = math.max(x0, nameRight);
    // The circle sits in a FIXED slot right before badge slot 1 (fx
    // ~0.42-0.455 of the card — the badge reader's own measurement), so
    // the zone runs to the badge zone regardless of the name's OCR box:
    // "Froslass" once OCR'd as "Froslas", and 3.1 strip-heights from that
    // undershot box stopped 5 px short of the ♀ circle.
    final zx1 = math.min(card[2], x0 + (0.45 * cw).round());
    final zy0 = y0 + (0.03 * ch).round();
    final zy1 = y0 + (0.26 * ch).round();
    if (zx1 - zx0 < 8 || zy1 - zy0 < 8) {
      return _washedFemale(photo, card, zy0, zy1, stripH);
    }
    // strip background = median-ish mean of the zone borders
    var sr = 0.0, sg = 0.0, sb = 0.0, n = 0;
    for (var x = zx0; x < zx1; x += 2) {
      for (final y in [zy0, zy1 - 1]) {
        final p = photo.getPixel(x, y);
        sr += p.r.toDouble();
        sg += p.g.toDouble();
        sb += p.b.toDouble();
        n++;
      }
    }
    if (n == 0) return null;
    sr /= n;
    sg /= n;
    sb /= n;
    // find the LEFTMOST colored blob and average only its own pixels —
    // a type badge later in the zone must not blend into the color.
    bool colored(int x, int y) {
      final p = photo.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final d = math.sqrt((r - sr) * (r - sr) +
          (g - sg) * (g - sg) +
          (b - sb) * (b - sb));
      final sat = [r, g, b].reduce(math.max) - [r, g, b].reduce(math.min);
      return d > 90 && sat > 45;
    }

    // Leftmost RUN of colored columns (>=3 columns with >=3 colored pixels
    // each) — a lone antialiased text pixel or a card-edge stray must not
    // hijack the blob position (it did, on the fixture photos).
    final counts = List<int>.filled(zx1 - zx0, 0);
    for (var y = zy0 + 1; y < zy1 - 1; y++) {
      for (var x = zx0; x < zx1; x++) {
        if (colored(x, y)) counts[x - zx0]++;
      }
    }
    var minX = -1;
    for (var x = 0; x + 2 < counts.length; x++) {
      if (counts[x] >= 3 && counts[x + 1] >= 3 && counts[x + 2] >= 3) {
        minX = zx0 + x;
        break;
      }
    }
    if (minX < 0) return _washedFemale(photo, card, zy0, zy1, stripH);
    final blobEnd = math.min(zx1, minX + (0.9 * stripH).round());
    var blobR = 0.0, blobG = 0.0, blobB = 0.0;
    var blobN = 0;
    for (var y = zy0; y < zy1; y++) {
      for (var x = minX; x < blobEnd; x++) {
        if (!colored(x, y)) continue;
        final p = photo.getPixel(x, y);
        blobR += p.r.toDouble();
        blobG += p.g.toDouble();
        blobB += p.b.toDouble();
        blobN++;
      }
    }
    if (blobN < 0.02 * stripH * stripH) {
      return _washedFemale(photo, card, zy0, zy1, stripH);
    }
    blobR /= blobN;
    blobG /= blobN;
    blobB /= blobN;
    if (blobB > blobR + 50 && blobB > blobG + 50) return 'male';
    if (blobR > blobB + 35 && blobR > blobG + 45 && blobR > 140) {
      return 'female';
    }
    return _washedFemale(photo, card, zy0, zy1, stripH);
  }

  /// Pass 2, ♀ only: on a warm TV photo the pink circle body measures
  /// d 55-90 against the strip — under the strict gates above — while the
  /// ♂ royal blue always clears them. The circle's slot is FIXED (right
  /// before badge slot 1) and nothing else plainly PINK ever sits there:
  /// measured 1700+ pink pixels on the washed 2026-09-27 TV photo's two
  /// ♀ cards vs 0 on every ♂ and genderless card (threshold ~130).
  static String? _washedFemale(
      img.Image photo, List<int> card, int zy0, int zy1, int stripH) {
    final x0 = card[0];
    final cw = card[2] - x0;
    final wx0 = x0 + (0.385 * cw).round();
    final wx1 = math.min(card[2], x0 + (0.4525 * cw).round());
    var pink = 0;
    for (var y = zy0; y < zy1; y++) {
      for (var x = wx0; x < wx1; x++) {
        final p = photo.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        if (r - (g + b) / 2 > 15 && r > 120) pink++;
      }
    }
    return pink >= 0.02 * stripH * stripH ? 'female' : null;
  }

  // ------------------------------------------------------- type badges --

  /// The name strip's two FIXED badge slots, in card-width fractions,
  /// measured on the four team fixtures (`tool/team_scan/badge.py`):
  /// badge 1 sits at fx 0.461-0.470, badge 2 at 0.518-0.528, and a single
  /// badge always occupies slot 1. The gender circle's tail pokes into the
  /// zone at ~0.44 and a card-edge artifact runs at 0.585+; keeping only
  /// runs whose CENTER lands inside a slot window excludes both while
  /// still catching the narrow run a near-strip-purple badge produces.
  static const _badgeZoneX0 = 0.44;
  static const _badgeZoneX1 = 0.578;
  static const _badgeSlots = [(0.4575, 0.5135), (0.5135, 0.5695)];

  /// A slot with no column run can still hold a badge whose body hides
  /// against the strip purple (Ghost, Poison, Dragon, Fairy) — but its
  /// white GLYPH is bright whatever the body colour. Measured: slots with
  /// a badge 0.063+, empty strip <= 0.010.
  static const _glyphPresence = 0.035;

  /// A restricted comparison between family candidates must win by this.
  static const _badgeCompareMargin = 0.04;

  /// Which member of [family] the card's own type badges name, or null
  /// when they cannot settle it (a same-type family, unreadable badges, no
  /// margin). The badge count picks the candidates with that many types;
  /// one survivor is verified against its own expected badges, several are
  /// scored slot-by-slot with [ChampionsReferenceSet.badgeTypeScore] — a
  /// comparison among the family's OWN types only, never an 18-way read,
  /// so Blaze vs Aqua Tauros is just "is this badge Fire or Water?".
  String? familyFromBadges(img.Image photo, List<int> card,
      Set<String> family, ChampionsReferenceSet refs) {
    if (!refs.hasBadges) return null;
    final x0 = card[0], y0 = card[1];
    final cw = card[2] - x0, ch = card[3] - y0;
    final by0 = y0 + (0.03 * ch).round();
    final by1 = y0 + (0.26 * ch).round();
    final h = by1 - by0;
    final zx0 = x0 + (_badgeZoneX0 * cw).round();
    final zx1 = x0 + (_badgeZoneX1 * cw).round();
    if (h < 10 ||
        zx1 - zx0 < 16 ||
        by0 < 0 ||
        by1 > photo.height ||
        zx0 < 0 ||
        zx1 > photo.width) {
      return null;
    }

    // strip background: per-channel median over the wider band (inside the
    // narrow badge zone the badges themselves dominate).
    final wx0 = math.max(0, x0 + (0.28 * cw).round());
    final wx1 = math.min(photo.width, x0 + (0.615 * cw).round());
    final rs = <double>[], gs = <double>[], bs = <double>[];
    for (var y = by0; y < by1; y += 2) {
      for (var x = wx0; x < wx1; x += 2) {
        final p = photo.getPixel(x, y);
        rs.add(p.r.toDouble());
        gs.add(p.g.toDouble());
        bs.add(p.b.toDouble());
      }
    }
    if (rs.length < 64) return null;
    rs.sort();
    gs.sort();
    bs.sort();
    final bgR = rs[rs.length ~/ 2];
    final bgG = gs[gs.length ~/ 2];
    final bgB = bs[bs.length ~/ 2];

    // column runs of off-strip pixels (same recipe as the battle panels)
    const bgDist2 = 45.0 * 45.0;
    final on = List<bool>.filled(zx1 - zx0, false);
    for (var x = zx0; x < zx1; x++) {
      var k = 0;
      for (var y = by0; y < by1; y++) {
        final p = photo.getPixel(x, y);
        final dr = p.r - bgR, dg = p.g - bgG, db = p.b - bgB;
        if (dr * dr + dg * dg + db * db > bgDist2) k++;
      }
      on[x - zx0] = k > 0.25 * h;
    }
    final runs = <List<int>>[];
    int? start;
    for (var i = 0; i < on.length; i++) {
      if (on[i] && start == null) {
        start = i;
      } else if (!on[i] && start != null) {
        runs.add([start, i]);
        start = null;
      }
    }
    if (start != null) runs.add([start, on.length]);
    final merged = <List<int>>[];
    for (final r in runs) {
      if (merged.isNotEmpty && r[0] - merged.last[1] < 3) {
        merged.last[1] = r[1];
      } else {
        merged.add([r[0], r[1]]);
      }
    }

    // assign runs to the two slots by center (splitting a fused double-
    // badge run), then fall back to glyph presence for a slot whose badge
    // body hid in the strip colour.
    final slotBox = List<List<int>?>.filled(2, null);
    for (final r in merged) {
      final rw = r[1] - r[0];
      if (rw < 0.3 * h) continue;
      final n = (rw / h).round().clamp(1, 2);
      final step = rw / n;
      for (var k = 0; k < n; k++) {
        final bx0 = zx0 + (r[0] + k * step).floor() - 2;
        final bx1 = zx0 + (r[0] + (k + 1) * step).floor() + 2;
        final cx = ((bx0 + bx1) / 2 - x0) / cw;
        for (var s = 0; s < 2; s++) {
          if (cx >= _badgeSlots[s].$1 && cx < _badgeSlots[s].$2) {
            final prev = slotBox[s];
            slotBox[s] = prev == null
                ? [bx0, bx1]
                : [math.min(prev[0], bx0), math.max(prev[1], bx1)];
          }
        }
      }
    }
    final whiteLum = math.max(120.0, (bgR + bgG + bgB) / 3 + 55);
    for (var s = 0; s < 2; s++) {
      if (slotBox[s] != null) continue;
      final sx0 = x0 + (_badgeSlots[s].$1 * cw).round();
      final sx1 = x0 + (_badgeSlots[s].$2 * cw).round();
      var white = 0, total = 0;
      for (var y = by0; y < by1; y++) {
        for (var x = sx0; x < sx1; x++, total++) {
          final p = photo.getPixel(x, y);
          final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
          final lum = (r + g + b) / 3;
          final sat =
              math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
          if (lum > whiteLum && sat < 80) white++;
        }
      }
      if (total > 0 && white / total > _glyphPresence) {
        slotBox[s] = [sx0, sx1];
      }
    }
    if (slotBox[0] == null) return null; // every card has >= 1 badge
    final boxes = [slotBox[0]!, if (slotBox[1] != null) slotBox[1]!];

    // candidates with as many types as the card shows badges
    final cands = <String>[
      for (final id in family)
        if ((pack.speciesById(id)?.types.length ?? -1) == boxes.length) id
    ];
    if (cands.isEmpty) return null;

    double slotScore(List<int> box, String type) => refs.badgeTypeScore(
        photo, box[0], by0, box[1], by1, bgR, bgG, bgB, type);

    if (cands.length == 1) {
      // decided by badge COUNT alone — verify each badge at least matches
      // the survivor's own typing, so a glare artifact cannot decide a
      // form. (The verify is against the EXPECTED type, so it holds even
      // for strip-coloured badges, which fail detection but match their
      // own signature.)
      final types = pack.speciesById(cands.first)!.types;
      for (var i = 0; i < boxes.length; i++) {
        if (slotScore(boxes[i], types[i]) < 0.30) return null;
      }
      return cands.first;
    }
    final scored = <(double, String)>[];
    for (final id in cands) {
      final types = pack.speciesById(id)!.types;
      var total = 0.0;
      for (var i = 0; i < boxes.length; i++) {
        total += slotScore(boxes[i], types[i]);
      }
      scored.add((total / boxes.length, id));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    if (scored[0].$1 - scored[1].$1 < _badgeCompareMargin) return null;
    return scored.first.$2;
  }

  // --------------------------------------------------- sprite detection --

  /// Rank species for the card-corner sprite icon by sliding each reference
  /// tile over the icon window (masked NCC, several display scales).
  /// Returns (score, speciesId) best-first.
  static List<(double, String)> detectSprite(
      img.Image photo, List<int> card, ChampionsReferenceSet refs,
      {Set<String>? onlySpecies, int chPx = 96}) {
    final x0 = card[0], y0 = card[1];
    final cw = card[2] - x0, ch = card[3] - y0;
    // icon window, downscaled so the card height maps to 96 px
    final wx0 = math.max(0, x0 - (0.005 * cw).round());
    final wx1 = math.min(photo.width, x0 + (0.145 * cw).round());
    final wy0 = math.max(0, y0 - (0.18 * ch).round());
    final wy1 = math.min(photo.height, y0 + (0.33 * ch).round());
    if (wx1 - wx0 < 12 || wy1 - wy0 < 12) return const [];
    final f = chPx / ch;
    final win = img.copyResize(
      img.copyCrop(photo,
          x: wx0, y: wy0, width: wx1 - wx0, height: wy1 - wy0),
      width: ((wx1 - wx0) * f).round().clamp(8, 4096),
      height: ((wy1 - wy0) * f).round().clamp(8, 4096),
      interpolation: img.Interpolation.average,
    );
    final ww = win.width, wh = win.height;
    final wr = Float64List(ww * wh);
    final wg = Float64List(ww * wh);
    final wb = Float64List(ww * wh);
    var i = 0;
    for (var y = 0; y < wh; y++) {
      for (var x = 0; x < ww; x++, i++) {
        final p = win.getPixel(x, y);
        wr[i] = p.r / 255.0;
        wg[i] = p.g / 255.0;
        wb[i] = p.b / 255.0;
      }
    }
    final sides = [
      for (final frac in const [0.24, 0.28, 0.32, 0.36, 0.41])
        (frac * chPx).round()
    ];
    final best = <String, double>{};
    for (final ref in refs.sprites) {
      if (onlySpecies != null && !onlySpecies.contains(ref.speciesId)) {
        continue;
      }
      var refBest = -1.0;
      for (final side in sides) {
        if (side > ww || side > wh) continue;
        final t = _scaledTemplate(ref, refs.tile, side);
        if (t == null) continue;
        final v = _bestPlacement(wr, wg, wb, ww, wh, t);
        if (v > refBest) refBest = v;
      }
      final prev = best[ref.speciesId];
      if (prev == null || refBest > prev) best[ref.speciesId] = refBest;
    }
    final ranked = [
      for (final e in best.entries) (e.value, e.key)
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return ranked;
  }

  /// tile resized to [side] px (bilinear — nearest leaves 32->65 px blocks
  /// that cost real score) with mask, zero-mean under the mask.
  static _Template? _scaledTemplate(ChampionsRef ref, int tile, int side) {
    final n = side * side;
    final m = Float64List(n);
    final tr = Float64List(n);
    final tg = Float64List(n);
    final tb = Float64List(n);
    var count = 0;
    double sample(Float64List ch, double sx, double sy) {
      final x0 = sx.floor().clamp(0, tile - 1);
      final y0 = sy.floor().clamp(0, tile - 1);
      final x1 = (x0 + 1).clamp(0, tile - 1);
      final y1 = (y0 + 1).clamp(0, tile - 1);
      final fx = (sx - x0).clamp(0.0, 1.0);
      final fy = (sy - y0).clamp(0.0, 1.0);
      final a = ch[y0 * tile + x0] * (1 - fx) + ch[y0 * tile + x1] * fx;
      final b = ch[y1 * tile + x0] * (1 - fx) + ch[y1 * tile + x1] * fx;
      return a * (1 - fy) + b * fy;
    }

    for (var y = 0; y < side; y++) {
      final sy = (y + 0.5) * tile / side - 0.5;
      for (var x = 0; x < side; x++) {
        final sx = (x + 0.5) * tile / side - 0.5;
        final i = y * side + x;
        if (sample(ref.a, sx, sy) > 0.5) {
          m[i] = 1;
          tr[i] = sample(ref.r, sx, sy);
          tg[i] = sample(ref.g, sx, sy);
          tb[i] = sample(ref.b, sx, sy);
          count++;
        }
      }
    }
    if (count < 20) return null;
    for (final ch in [tr, tg, tb]) {
      var mu = 0.0;
      for (var i = 0; i < n; i++) {
        if (m[i] > 0) mu += ch[i];
      }
      mu /= count;
      for (var i = 0; i < n; i++) {
        if (m[i] > 0) ch[i] -= mu;
      }
    }
    var vr = 0.0, vg = 0.0, vb = 0.0;
    for (var i = 0; i < n; i++) {
      if (m[i] > 0) {
        vr += tr[i] * tr[i];
        vg += tg[i] * tg[i];
        vb += tb[i] * tb[i];
      }
    }
    return _Template(side, m, tr, tg, tb, count, vr, vg, vb);
  }

  static double _bestPlacement(Float64List wr, Float64List wg, Float64List wb,
      int ww, int wh, _Template t) {
    final side = t.side;
    var best = -1.0;
    final channels = [(wr, t.r, t.vr), (wg, t.g, t.vg), (wb, t.b, t.vb)];
    for (var oy = 0; oy + side <= wh; oy += 2) {
      for (var ox = 0; ox + side <= ww; ox += 2) {
        var corr = 0.0;
        for (final (ch, tc, tvar) in channels) {
          if (tvar < 1e-6) continue;
          var sP = 0.0, sP2 = 0.0, sPT = 0.0;
          var i = 0;
          for (var y = 0; y < side; y++) {
            final wrow = (oy + y) * ww + ox;
            for (var x = 0; x < side; x++, i++) {
              if (t.m[i] == 0) continue;
              final v = ch[wrow + x];
              sP += v;
              sP2 += v * v;
              sPT += v * tc[i];
            }
          }
          final varP = math.max(sP2 - sP * sP / t.n, 1e-6);
          corr += sPT / math.sqrt(varP * tvar);
        }
        corr /= 3.0;
        if (corr > best) best = corr;
      }
    }
    return best;
  }

  // ------------------------------------------------------ fuzzy matching --

  static String _clean(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// All species ids sharing [id]'s family root (rotom -> the six Rotoms).
  /// A short root that is not itself a species ("mr" from mr-mime) is a
  /// name fragment, not a family — Mr. Mime must not be settled against
  /// Mr. Rime.
  Set<String> _formFamily(String id) {
    final root = id.split('-').first;
    if (root.length < 4 && !pack.species.containsKey(root)) return {id};
    return {
      for (final s in pack.species.keys)
        if (s == root || s.startsWith('$root-') || s == id) s
    };
  }

  /// OCR glues the little coloured icon before a name into the text
  /// ("S Charizardite Y", "3 Electroweb", "O Protect"): drop a leading
  /// 1-2 char token when a real word follows it.
  static String _dropLeadingGlyph(String raw) {
    final m = RegExp(r'^\S{1,2}\s+(?=\S{3,})').firstMatch(raw.trim());
    return m == null ? raw.trim() : raw.trim().substring(m.end);
  }

  /// Exact match on the raw text or on the text minus a leading glyph,
  /// else the UNIQUE best edit distance <= 2. "First match within 2"
  /// once turned "S Charizardite Y" (distance 1 from the real stone)
  /// into charizardite-X, distance 2 but earlier in the pack — and the
  /// Mega forme with it. A tie on the best distance is ambiguity.
  String? _matchName(String raw, Iterable<(String, String)> idNames) {
    final stripped = _clean(_dropLeadingGlyph(raw));
    for (final q in {_clean(raw), stripped}) {
      if (q.length < 3) continue;
      for (final (id, name) in idNames) {
        if (_clean(name) == q) return id;
      }
    }
    if (stripped.length < 5) return null;
    String? best;
    var bestD = 3;
    var tie = false;
    for (final (id, name) in idNames) {
      final c = _clean(name);
      if ((c.length - stripped.length).abs() > 2) continue;
      final d = _editDistance(stripped, c);
      if (d < bestD) {
        bestD = d;
        best = id;
        tie = false;
      } else if (d == bestD && d < 3 && id != best) {
        tie = true;
      }
    }
    return (bestD <= 2 && !tie) ? best : null;
  }

  String? _matchAbility(String raw) => _matchName(
      raw, [for (final name in pack.abilities.keys) (name, name)]);

  String? _matchItem(String raw) => _matchName(
      raw, [for (final item in pack.items.values) (item.id, item.name)]);

  String? _matchMove(String raw) => _matchName(
      raw, [for (final m in pack.moves.values) (m.id, m.name)]);

  /// OCR digit look-alikes on a blurred TV capture (kept symmetric).
  static const Map<String, List<String>> _confusableDigits = {
    '0': ['8', '6', '9'],
    '1': ['7'],
    '3': ['8'],
    '4': ['9'],
    '5': ['6'],
    '6': ['0', '5', '8'],
    '7': ['1'],
    '8': ['0', '3', '6', '9'],
    '9': ['0', '4', '8'],
  };

  /// Every value one digit-confusion away from [n], within stat range.
  static List<int> _digitConfusions(int n) {
    final s = n.toString();
    final out = <int>{};
    for (var i = 0; i < s.length; i++) {
      for (final c in _confusableDigits[s[i]] ?? const <String>[]) {
        final v = int.parse(s.replaceRange(i, i + 1, c));
        if (v != n && v >= 40 && v <= 300) out.add(v);
      }
    }
    return out.toList()..sort();
  }

  /// True when any substring of [text] sits within one edit of [key] —
  /// "atack" (the arrow ate a t) still names the Attack row. Only used
  /// for keys of 5+ characters, where one edit cannot cross labels.
  static bool _containsWithinOneEdit(String text, String key) {
    for (final len in [key.length - 1, key.length, key.length + 1]) {
      if (len < 1) continue;
      for (var i = 0; i + len <= text.length; i++) {
        if (_editDistance(text.substring(i, i + len), key) <= 1) return true;
      }
    }
    return false;
  }

  static int _editDistance(String a, String b) {
    final m = a.length, n = b.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1),
            prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[n];
  }

  // -------------------------------------------------------- geometry --

  List<OcrLine> _linesIn(
      List<OcrLine> lines, img.Image photo, List<int> card,
      {double padTop = 0.0}) {
    final x0 = card[0] / photo.width, x1 = card[2] / photo.width;
    final y0 = (card[1] - padTop * (card[3] - card[1])) / photo.height;
    final y1 = card[3] / photo.height;
    return [
      for (final l in lines)
        if (l.cx >= x0 && l.cx <= x1 && l.cy >= y0 && l.cy <= y1) l
    ];
  }

  double _fx(OcrLine l, img.Image photo, List<int> card) =>
      (l.cx * photo.width - card[0]) / (card[2] - card[0]);

  double _fy(OcrLine l, img.Image photo, List<int> card) =>
      (l.cy * photo.height - card[1]) / (card[3] - card[1]);
}

class _Template {
  final int side;
  final Float64List m, r, g, b;
  final int n;
  final double vr, vg, vb;
  _Template(this.side, this.m, this.r, this.g, this.b, this.n, this.vr,
      this.vg, this.vb);
}
