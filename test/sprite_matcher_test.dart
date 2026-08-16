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
    final spriteBytes =
        File('assets/sprites/home/${speciesIds[i]}.png').readAsBytesSync();
    final sprite = img.decodeImage(spriteBytes)!;
    final scaled = img.copyResize(sprite, height: panelH - 10);
    img.compositeImage(canvas, scaled,
        dstX: panelX + (panelW * 0.22).round(), dstY: y0 + 5);
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
}

void main() {
  final pack = loadRealDataPack();

  SpriteMatcher freshMatcher({bool withSeeds = true}) => SpriteMatcher(
        pack,
        loadBytes: fileLoader,
        exemplars: ExemplarStore(
            loadBundled: withSeeds ? fileLoader : (_) async => null),
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

    test('finds all six panels and identifies each sprite', () async {
      final matcher = freshMatcher(withSeeds: false);
      final matches = await matcher.matchPreview(composePreview(truth));
      expect(matches.length, 6);
      final assigned = [for (final m in matches) m.assigned.speciesId];
      expect(assigned, truth,
          reason: 'clean same-art sprites should match exactly');
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
    const truth = [
      'sneasler',
      'umbreon',
      'decidueye-hisui',
      'lycanroc',
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

    test('without exemplars, art fallback still ranks the truth sensibly',
        () async {
      final matcher = freshMatcher(withSeeds: false);
      final matches =
          await matcher.matchPreview(File(fixture).readAsBytesSync());
      var topEight = 0;
      for (var i = 0; i < matches.length; i++) {
        final order = [for (final c in matches[i].ranked) c.speciesId];
        if (order.take(8).contains(truth[i])) topEight++;
      }
      expect(topEight, greaterThanOrEqualTo(4),
          reason: 'cold-start art matching is a fallback, not the main path');
    },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: fixtureMissing ? 'fixture photo not present' : false);
  });
}
