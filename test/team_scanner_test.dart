/// TeamScanner: the two Champions team-display photos -> a ready Team.
///
/// The four fixture photos are real hand-held shots of the two example
/// teams ("grasssun" and "earthquake", 2026-09-21). Vision (cards, sprite
/// detection, gender) runs on the real pixels; TEXT is scripted through the
/// TextOcr seam, placed inside the card boxes the scanner itself finds —
/// the same trick as every other OCR test here.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokemon_strategy_app/src/data/stat_calculator.dart';
import 'package:pokemon_strategy_app/src/recognition/battle_ocr.dart';
import 'package:pokemon_strategy_app/src/recognition/team_scanner.dart';

import 'helpers.dart';

Future<Uint8List?> fileLoader(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

/// Scripted OCR whose lines were laid out against the CARD BOXES the
/// scanner finds in the actual fixture image.
class FakeOcr implements TextOcr {
  final Map<Uint8List, List<OcrLine>> byImage;
  FakeOcr(this.byImage);

  @override
  Future<List<OcrLine>> readLines(Uint8List imageBytes) async =>
      byImage[imageBytes] ?? const [];
}

/// Text content of one moves-card: name, ability, item, moves.
class MovesCardText {
  final String name, ability, item;
  final List<String> moves;
  const MovesCardText(this.name, this.ability, this.item, this.moves);
}

/// (label, shown stat, shown SP) rows of one stats-card.
typedef StatsCardText = List<(String, int, int)>;

List<OcrLine> movesLinesFor(
    img.Image photo, List<List<int>> cards, List<MovesCardText> texts,
    {String header = 'grasssun'}) {
  final w = photo.width, h = photo.height;
  final lines = <OcrLine>[
    // header: team name left of the avatar, plus noise the scanner skips
    OcrLine(header,
        cx: 0.36, cy: (cards.first[1] / h) - 0.06, w: 0.05, h: 0.02),
    OcrLine('jonathan',
        cx: 0.65, cy: (cards.first[1] / h) - 0.06, w: 0.05, h: 0.02),
    OcrLine('Moves & More',
        cx: 0.42, cy: (cards.first[1] / h) - 0.02, w: 0.06, h: 0.015),
    OcrLine('Stats',
        cx: 0.58, cy: (cards.first[1] / h) - 0.02, w: 0.03, h: 0.015),
  ];
  for (var i = 0; i < texts.length; i++) {
    final c = cards[i];
    final cw = (c[2] - c[0]).toDouble(), chh = (c[3] - c[1]).toDouble();
    OcrLine at(String text, double fx, double fy) {
      final tw = 0.0205 * text.length * cw; // measured glyph width
      final startX = c[0] + 0.113 * cw;
      final cx = fx >= 0 ? c[0] + fx * cw : startX + tw / 2;
      return OcrLine(text,
          cx: cx / w, cy: (c[1] + fy * chh) / h, w: tw / w, h: 0.05 * chh / h);
    }

    final t = texts[i];
    lines.add(at(t.name, -1, 0.13)); // -1 = left-anchored like the real strip
    lines.add(at(t.ability, 0.24, 0.42));
    lines.add(at(t.item, 0.26, 0.68));
    for (var m = 0; m < t.moves.length; m++) {
      lines.add(at(t.moves[m], 0.76, 0.10 + 0.245 * m));
    }
  }
  return lines;
}

List<OcrLine> statsLinesFor(
    img.Image photo, List<List<int>> cards, List<StatsCardText> texts) {
  final w = photo.width, h = photo.height;
  final lines = <OcrLine>[];
  for (var i = 0; i < texts.length; i++) {
    final c = cards[i];
    final cw = (c[2] - c[0]).toDouble(), chh = (c[3] - c[1]).toDouble();
    for (var r = 0; r < texts[i].length; r++) {
      final (label, stat, sp) = texts[i][r];
      final left = r < 3;
      final fy = 0.42 + 0.24 * (r % 3);
      final lx = left ? 0.15 : 0.58;
      lines.add(OcrLine(label,
          cx: (c[0] + lx * cw) / w, cy: (c[1] + fy * chh) / h));
      lines.add(OcrLine('$stat',
          cx: (c[0] + (lx + 0.16) * cw) / w, cy: (c[1] + fy * chh) / h));
      lines.add(OcrLine('$sp',
          cx: (c[0] + (lx + 0.28) * cw) / w, cy: (c[1] + fy * chh) / h));
    }
  }
  return lines;
}

const team1Moves = [
  MovesCardText('Chesnaught', 'Bulletproof', 'Chesnaughtite',
      ['Spiky Shield', 'Body Press', 'Grassy Glide', 'Synthesis']),
  MovesCardText('Typhlosion', 'Flash Fire', 'Life Orb',
      ['Eruption', 'Solar Beam', 'Flamethrower', 'Protect']),
  MovesCardText('Rillaboom', 'Grassy Surge', 'Grassy Seed',
      ['Fake Out', 'Solar Blade', 'Grassy Glide', 'Sunny Day']),
  MovesCardText('Sableye', 'Prankster', 'Sablenite',
      ['Psych Up', 'Will-O-Wisp', 'Encore', 'Disable']),
  MovesCardText('Scolipede', 'Speed Boost', 'Scolipite',
      ['Iron Defense', 'Leech Life', 'Baton Pass', 'Protect']),
  MovesCardText('Armarouge', 'Flash Fire', 'Choice Scarf',
      ['Lava Plume', 'Psychic', 'Aura Sphere', 'Solar Beam']),
];

const List<StatsCardText> team1Stats = [
  [('HP', 195, 32), ('Attack', 127, 0), ('Defense', 191, 32),
   ('Sp. Atk', 84, 0), ('Sp. Def', 97, 2), ('Speed', 84, 0)],
  [('HP', 155, 2), ('Attack', 93, 0), ('Defense', 98, 0),
   ('Sp. Atk', 161, 32), ('Sp. Def', 105, 0), ('Speed', 167, 32)],
  [('HP', 207, 32), ('Attack', 194, 32), ('Defense', 110, 0),
   ('Sp. Atk', 72, 0), ('Sp. Def', 92, 2), ('Speed', 105, 0)],
  [('HP', 157, 32), ('Attack', 95, 0), ('Defense', 97, 2),
   ('Sp. Atk', 76, 0), ('Sp. Def', 128, 32), ('Speed', 70, 0)],
  [('HP', 137, 2), ('Attack', 167, 32), ('Defense', 109, 0),
   ('Sp. Atk', 67, 0), ('Sp. Def', 121, 32), ('Speed', 132, 0)],
  [('HP', 177, 17), ('Attack', 72, 0), ('Defense', 120, 0),
   ('Sp. Atk', 194, 32), ('Sp. Def', 100, 0), ('Speed', 112, 17)],
];

void main() {
  final pack = loadRealDataPack();
  final movesBytes =
      File('test/fixtures/team1_moves.jpeg').readAsBytesSync();
  final statsBytes =
      File('test/fixtures/team1_stats.jpeg').readAsBytesSync();
  final movesPhoto = img.bakeOrientation(img.decodeImage(movesBytes)!);
  final statsPhoto = img.bakeOrientation(img.decodeImage(statsBytes)!);
  final movesCards = TeamScanner.findTeamCards(movesPhoto);
  final statsCards = TeamScanner.findTeamCards(statsPhoto);

  test('finds six cards, row-major, in all four fixture photos', () {
    expect(movesCards.length, 6);
    expect(statsCards.length, 6);
    // row-major: 1 left of 2, 3 left of 4, 1 above 3
    expect(movesCards[0][0], lessThan(movesCards[1][0]));
    expect(movesCards[2][0], lessThan(movesCards[3][0]));
    expect(movesCards[0][1], lessThan(movesCards[2][1]));
    for (final f in ['team2_moves', 'team2_stats']) {
      final p = img.bakeOrientation(
          img.decodeImage(File('test/fixtures/$f.jpeg').readAsBytesSync())!);
      expect(TeamScanner.findTeamCards(p).length, 6, reason: f);
    }
  });

  test('scans the grasssun team end to end', () async {
    final scanner = TeamScanner(pack, loadBytes: fileLoader);
    final result = await scanner.scan(
      movesImage: movesBytes,
      statsImage: statsBytes,
      ocr: FakeOcr({
        movesBytes: movesLinesFor(movesPhoto, movesCards, team1Moves),
        statsBytes: statsLinesFor(statsPhoto, statsCards, team1Stats),
      }),
    );

    expect(result.team.name, 'grasssun');
    expect(result.slots.length, 6);
    expect([for (final s in result.slots) s.build.speciesId], [
      'chesnaught', 'typhlosion', 'rillaboom', 'sableye', 'scolipede',
      'armarouge',
    ]);
    expect(result.allWarnings, isEmpty,
        reason: 'a clean pair of images should read without complaints');

    final builds = [for (final s in result.slots) s.build];
    expect([for (final b in builds) b.ability], [
      'Bulletproof', 'Flash Fire', 'Grassy Surge', 'Prankster',
      'Speed Boost', 'Flash Fire',
    ]);
    expect([for (final b in builds) b.itemId], [
      'chesnaughtite', 'life-orb', 'grassy-seed', 'sablenite', 'scolipite',
      'choice-scarf',
    ]);
    expect(builds[0].moveIds,
        ['spiky-shield', 'body-press', 'grassy-glide', 'synthesis']);
    expect(builds[3].moveIds,
        ['psych-up', 'will-o-wisp', 'encore', 'disable']);
    // natures inferred purely from the stat math
    expect([for (final b in builds) b.nature],
        ['Impish', 'Timid', 'Adamant', 'Careful', 'Adamant', 'Modest']);
    expect(builds[0].sp, {'hp': 32, 'def': 32, 'spd': 2});
    expect(builds[5].sp, {'hp': 17, 'spa': 32, 'spe': 17});
    // the held Mega Stones select the Mega formes
    expect(builds[0].megaFormeId, 'chesnaught-mega');
    expect(builds[3].megaFormeId, 'sableye-mega');
    expect(builds[4].megaFormeId, 'scolipede-mega');
    // genders come off the ♂/♀ circle pixels
    expect(builds[3].gender, 'female', reason: 'Sableye is ♀');
    expect(builds[0].gender, 'male');
    // real names are not nicknames
    expect(builds.every((b) => b.nickname == null), isTrue);
    expect(result.slots.every((s) => s.speciesFromName), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a nicknamed Pokemon is identified by its sprite and flagged',
      () async {
    final texts = [
      for (var i = 0; i < team1Moves.length; i++)
        i == 3
            ? const MovesCardText('Gemboi', 'Prankster', 'Sablenite',
                ['Psych Up', 'Will-O-Wisp', 'Encore', 'Disable'])
            : team1Moves[i]
    ];
    final scanner = TeamScanner(pack, loadBytes: fileLoader);
    final result = await scanner.scan(
      movesImage: movesBytes,
      statsImage: statsBytes,
      ocr: FakeOcr({
        movesBytes: movesLinesFor(movesPhoto, movesCards, texts),
        statsBytes: statsLinesFor(statsPhoto, statsCards, team1Stats),
      }),
    );
    final slot = result.slots[3];
    expect(slot.build.speciesId, 'sableye',
        reason: 'sprite detection must recover the species');
    expect(slot.speciesFromName, isFalse);
    expect(slot.build.nickname, 'Gemboi');
    expect(slot.warnings, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('form families are settled by the type badges', () async {
    final p = img.bakeOrientation(img.decodeImage(
        File('test/fixtures/team2_moves.jpeg').readAsBytesSync())!);
    final cards = TeamScanner.findTeamCards(p);
    final refs = await loadRefsForTest();
    final scanner = TeamScanner(pack, loadBytes: fileLoader);
    // Blaze vs Aqua Tauros differ by pixels at sprite-tile size (an honest
    // near-tie the scanner used to flag) but by whole colours on the
    // badges: Fighting+Fire vs Fighting+Water. The badges must call it
    // decisively — no flag, no coin flip.
    expect(
        scanner.familyFromBadges(
            p,
            cards[5],
            {
              'tauros',
              'tauros-paldea-combat-breed',
              'tauros-paldea-blaze-breed',
              'tauros-paldea-aqua-breed',
            },
            refs),
        'tauros-paldea-blaze-breed');
    // Six Rotoms differ only in the second type; card 1 is Heat.
    expect(
        scanner.familyFromBadges(
            p,
            cards[0],
            {
              'rotom', 'rotom-heat', 'rotom-wash', 'rotom-frost',
              'rotom-fan', 'rotom-mow',
            },
            refs),
        'rotom-heat');
    // A family whose members share a typing gets NOTHING from badges —
    // that must come back null so the sprite keeps deciding those.
    expect(
        scanner.familyFromBadges(
            p, cards[5], {'toxtricity-amped', 'toxtricity-low-key'}, refs),
        isNull);
    // The count path: base Typhlosion shows ONE badge, Hisuian shows two.
    expect(
        scanner.familyFromBadges(
            movesPhoto, movesCards[1], {'typhlosion', 'typhlosion-hisui'},
            refs),
        'typhlosion');
    // The sprite fallback still recovers the family member on its own
    // (this is what an unreadable badge strip degrades to).
    final rotom = TeamScanner.detectSprite(p, cards[0], refs,
        onlySpecies: {
          'rotom', 'rotom-heat', 'rotom-wash', 'rotom-frost', 'rotom-fan',
          'rotom-mow',
        },
        chPx: 160);
    expect(rotom.first.$2, 'rotom-heat');
  }, timeout: const Timeout(Duration(minutes: 3)));

  group('stat math', () {
    test('solves nature and verifies every stat', () {
      // Typhlosion: base 78/84/78/109/85/100, Timid, 2/0/0/32/0/32.
      final base = pack.speciesById('typhlosion')!.baseStats;
      final rows = {
        'hp': (155, 2), 'atk': (93, 0), 'def': (98, 0),
        'spa': (161, 32), 'spd': (105, 0), 'spe': (167, 32),
      }.map((k, v) => MapEntry(k, (v.$1, v.$2 as int?)));
      final solved = TeamScanner.solveSpAndNature(rows, base);
      expect(solved.nature, 'Timid');
      expect(solved.sp, {'hp': 2, 'spa': 32, 'spe': 32});
      expect(solved.warnings, isEmpty);
    });

    test('recovers a missing SP number from the shown stat', () {
      final base = pack.speciesById('typhlosion')!.baseStats;
      final rows = {
        'hp': (155, 2), 'atk': (93, 0), 'def': (98, 0),
        'spa': (161, 32), 'spd': (105, 0), 'spe': (167, null),
      }.map((k, v) => MapEntry(k, (v.$1, v.$2)));
      final solved = TeamScanner.solveSpAndNature(rows, base);
      expect(solved.nature, 'Timid');
      expect(solved.sp['spe'], 32);
    });

    test('flags a stat that matches no multiplier', () {
      final base = pack.speciesById('typhlosion')!.baseStats;
      final rows = {
        'hp': (155, 2), 'atk': (93, 0), 'def': (98, 0),
        'spa': (161, 32), 'spd': (105, 0), 'spe': (166, 32), // off by one
      }.map((k, v) => MapEntry(k, (v.$1, v.$2 as int?)));
      final solved = TeamScanner.solveSpAndNature(rows, base);
      expect(solved.warnings, isNotEmpty);
    });

    test('the level-50 formula reproduces every number on both fixture '
        'stat screens', () {
      const ids = [
        'chesnaught', 'typhlosion', 'rillaboom', 'sableye', 'scolipede',
        'armarouge',
      ];
      const natures = [
        'Impish', 'Timid', 'Adamant', 'Careful', 'Adamant', 'Modest',
      ];
      const spMaps = [
        {'hp': 32, 'def': 32, 'spd': 2},
        {'hp': 2, 'spa': 32, 'spe': 32},
        {'hp': 32, 'atk': 32, 'spd': 2},
        {'hp': 32, 'def': 2, 'spd': 32},
        {'hp': 2, 'atk': 32, 'spd': 32},
        {'hp': 17, 'spa': 32, 'spe': 17},
      ];
      for (var i = 0; i < ids.length; i++) {
        final stats = StatCalculator.computeStats(
            pack.speciesById(ids[i])!.baseStats, spMaps[i], natures[i]);
        final shown = team1Stats[i];
        final byKey = {
          'hp': shown[0].$2, 'atk': shown[1].$2, 'def': shown[2].$2,
          'spa': shown[3].$2, 'spd': shown[4].$2, 'spe': shown[5].$2,
        };
        expect(stats, byKey, reason: ids[i]);
      }
    });
  });
}
