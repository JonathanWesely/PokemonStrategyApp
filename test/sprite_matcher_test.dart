/// SpriteMatcher: panel detection + segmentation + matching, tested two ways:
///  1. A synthetic team-preview screen composed from bundled sprites
///     (deterministic, always runs).
///  2. The real fixture photo test/fixtures/preview1.jpeg (skipped when the
///     file is absent) — end-to-end proof on real camera conditions, using
///     the bundled exemplar seeds segmented from Champions photos.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokemon_strategy_app/src/recognition/sprite_matcher.dart';

import 'helpers.dart';

Future<Uint8List?> fileLoader(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

/// Compose a fake team-select screen: six crimson panels on the right half,
/// each with a sprite pasted at the panel's sprite position.
///
/// The sprites come from `test/fixtures/champions/` — the game's own 2D art,
/// the same domain the matcher's reference atlas holds. Composing from the
/// bundled HOME renders instead would test the matcher against artwork the
/// game never draws, which is what the old art-histogram tier existed to
/// cope with and what the atlas replaced.
Uint8List composePreview(List<String> speciesIds) {
  const w = 1200, h = 900;
  final canvas = img.Image(width: w, height: h);
  img.fill(canvas, color: img.ColorRgb8(40, 90, 60)); // arena-ish green
  const panelX = 780, panelW = 330;
  const panelH = 90, gap = 28, startY = 110;
  for (var i = 0; i < speciesIds.length; i++) {
    final y0 = startY + i * (panelH + gap);
    img.fillRect(canvas,
        x1: panelX,
        y1: y0,
        x2: panelX + panelW,
        y2: y0 + panelH,
        color: img.ColorRgb8(216, 44, 100)); // crimson panel
    final champions = File('test/fixtures/champions/${speciesIds[i]}.png');
    final spriteBytes = champions.existsSync()
        ? champions.readAsBytesSync()
        : File('assets/sprites/home/${speciesIds[i]}.png').readAsBytesSync();
    final sprite = img.decodeImage(spriteBytes)!;
    final scaled = img.copyResize(sprite, height: panelH - 10);
    img.compositeImage(canvas, scaled,
        dstX: panelX + (panelW * 0.22).round(), dstY: y0 + 5);
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
}

void main() {
  final pack = loadRealDataPack();

  SpriteMatcher freshMatcher({bool withSeeds = true, bool useCnn = true}) =>
      SpriteMatcher(
        pack,
        loadBytes: fileLoader,
        exemplars: ExemplarStore(
            loadBundled: withSeeds ? fileLoader : (_) async => null),
        useCnn: useCnn,
      );

  group('synthetic preview screen', () {
    const truth = [
      'garchomp',
      'dragonite',
      'gholdengo',
      'pelipper',
      'torkoal',
      'metagross'
    ];

    test('finds all six panels and ranks each sprite sensibly', () async {
      final matcher = freshMatcher(withSeeds: false);
      final matches = await matcher.matchPreview(composePreview(truth));
      expect(matches.length, 6);
      final assigned = [for (final m in matches) m.assigned.speciesId];
      // Runs through the trained classifier by default (6/6 top-1 in the
      // Python twin; Metagross weakest at ~0.35). The bar stays at top-3
      // containment plus a strong majority exact so the same test also holds
      // for the template fallback — the exemplar loop (next test) is what
      // makes a confirmed species exact.
      var exact = 0;
      for (var i = 0; i < matches.length; i++) {
        final top3 = [
          for (final c in matches[i].ranked.take(3)) c.speciesId
        ];
        expect(top3, contains(truth[i]),
            reason: 'panel $i: ${truth[i]} missing from top-3 $top3');
        if (assigned[i] == truth[i]) exact++;
      }
      expect(exact, greaterThanOrEqualTo(4));
      // Uniqueness: no species assigned twice.
      expect(assigned.toSet().length, 6);
      // Every panel carries a segmented crop for the exemplar loop.
      for (final m in matches) {
        expect(m.cropPng, isNotEmpty);
        expect(img.decodeImage(m.cropPng), isNotNull);
      }
    });

    test('confirmed crops become exemplars that then dominate matching',
        () async {
      final store = ExemplarStore(loadBundled: (_) async => null);
      final matcher =
          SpriteMatcher(pack, loadBytes: fileLoader, exemplars: store);
      final first = await matcher.matchPreview(composePreview(truth));
      // Simulate the user confirming panel 0.
      store.add(truth[0], first[0].cropPng);
      final again = await matcher.matchPreview(composePreview(truth));
      expect(again[0].assigned.speciesId, truth[0]);
      expect(again[0].assigned.score, greaterThan(0.8),
          reason: 'exemplar NCC on the same crop should be near-perfect');
    });
  });

  group('real fixture photo', () {
    const fixture = 'test/fixtures/preview1.jpeg';
    final fixtureMissing = !File(fixture).existsSync();
    // Read off the photo itself, badges included: panel 3 is the GREEN-hooded
    // owl with Grass+Ghost badges (base Decidueye — the Hisuian form is
    // red/white and Grass/Fighting), and panel 4's orange wolf is the Dusk
    // form. Both were mislabelled before the true-sprite matcher caught it.
    const truth = [
      'sneasler',
      'umbreon',
      'decidueye',
      'lycanroc-dusk',
      'arcanine',
      'sylveon'
    ];

    test('segments six panels and matches via bundled exemplar seeds',
        () async {
      final matcher = freshMatcher();
      final matches =
          await matcher.matchPreview(File(fixture).readAsBytesSync());
      expect(matches.length, 6, reason: 'panel detection');
      final assigned = [for (final m in matches) m.assigned.speciesId];
      expect(assigned, truth,
          reason: 'exemplar seeds come from this same screen setup');
    },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: fixtureMissing ? 'fixture photo not present' : false);

    // The template tier is now the fallback for when the classifier model is
    // absent; useCnn: false keeps it honest.
    test('without exemplars, the Champions template tier ranks the truth high',
        () async {
      final matcher = freshMatcher(withSeeds: false, useCnn: false);
      final matches =
          await matcher.matchPreview(File(fixture).readAsBytesSync());
      var topThree = 0, exact = 0;
      for (var i = 0; i < matches.length; i++) {
        final order = [for (final c in matches[i].ranked) c.speciesId];
        if (order.take(3).contains(truth[i])) topThree++;
        if (matches[i].assigned.speciesId == truth[i]) exact++;
      }
      // The old art-histogram tier managed the truth in the top EIGHT for
      // only 3 of 6 panels here. Matching the game's own artwork puts it at
      // rank 1 on all six in the Python reference run (including the exact
      // Lycanroc form); one panel of slack covers detector differences.
      expect(topThree, 6,
          reason: 'template tier should rank the truth in the top three');
      expect(exact, greaterThanOrEqualTo(5),
          reason: 'and get nearly all of them outright, with no exemplars');
    },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: fixtureMissing ? 'fixture photo not present' : false);
  });
}
