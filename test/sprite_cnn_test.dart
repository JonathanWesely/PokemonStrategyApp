/// SpriteCnn: the Dart forward pass must reproduce the Python twin
/// (tool/sprite_cnn/export.py) exactly, and the classifier must read the
/// real frames — including the low-contrast RIG frame the template tier
/// failed (2/6 in the app, 2026-09-17).
///
/// Goldens: `python3 tool/sprite_cnn/make_goldens.py` after every retrain.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/recognition/sprite_cnn.dart';
import 'package:pokemon_strategy_app/src/recognition/sprite_matcher.dart';

import 'helpers.dart';

Future<Uint8List?> fileLoader(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

void main() {
  late SpriteCnn cnn;
  final golden = jsonDecode(
          File('test/fixtures/sprite_cnn_golden.json').readAsStringSync())
      as Map<String, dynamic>;

  setUpAll(() async {
    final loaded = await SpriteCnn.load(fileLoader);
    expect(loaded, isNotNull, reason: 'assets/models/sprite_cnn.* missing');
    cnn = loaded!;
  });

  test('model covers the whole roster, in atlas order', () {
    final meta = jsonDecode(
            File('pokemon2Dsprites/manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    final ids = [
      for (final s in meta['sprites'] as List)
        (s as Map<String, dynamic>)['packSpeciesId'] as String
    ];
    expect(cnn.species, ids);
    expect(cnn.input, 48);
  });

  test('area resize matches the Python twin', () {
    final r = golden['resize'] as Map<String, dynamic>;
    final src = Float64List.fromList(
        [for (final v in r['src'] as List) (v as num).toDouble()]);
    final out = SpriteCnn.areaResize(
        src, r['h'] as int, r['w'] as int, r['hOut'] as int, r['wOut'] as int);
    final want = [for (final v in r['out'] as List) (v as num).toDouble()];
    expect(out.length, want.length);
    for (var i = 0; i < want.length; i++) {
      expect(out[i], closeTo(want[i], 1e-5), reason: 'pixel $i');
    }
  });

  test('logits match the Python twin on real panel windows', () {
    for (final raw in golden['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      final win = Float32List.fromList(
          [for (final v in c['window'] as List) (v as num).toDouble()]);
      final z = cnn.logits(SpriteCnn.standardize(win));
      final want = [for (final v in c['logits'] as List) (v as num).toDouble()];
      var worst = 0.0;
      for (var i = 0; i < want.length; i++) {
        worst = (z[i] - want[i]).abs() > worst ? (z[i] - want[i]).abs() : worst;
      }
      expect(worst, lessThan(2e-3), reason: '${c['tag']}: max logit diff');
      var best = 0;
      for (var i = 1; i < z.length; i++) {
        if (z[i] > z[best]) best = i;
      }
      expect(cnn.names[best], c['truth'], reason: '${c['tag']}');
    }
  });

  group('end to end through SpriteMatcher', () {
    final pack = loadRealDataPack();
    SpriteMatcher matcher() => SpriteMatcher(pack,
        loadBytes: fileLoader,
        exemplars: ExemplarStore(loadBundled: (_) async => null));

    for (final (fixture, truth) in <(String, List<String>)>[
      // The Seeed XIAO rig, 1600x1200, 2026-09-17: blurred, ~45% contrast,
      // translucent cards. The template tier got Kleavor and Dragonite only.
      (
        'test/fixtures/rig2.jpeg',
        ['charizard', 'venusaur', 'kleavor', 'drampa', 'dragonite', 'ceruledge']
      ),
      (
        'test/fixtures/select1.jpeg',
        ['raichu', 'staraptor', 'pelipper', 'swampert', 'dragonite', 'bellibolt']
      ),
      (
        'test/fixtures/preview1.jpeg',
        ['sneasler', 'umbreon', 'decidueye', 'lycanroc-dusk', 'arcanine', 'sylveon']
      ),
    ]) {
      test('$fixture: 6/6 from a cold start', () async {
        final matches =
            await matcher().matchPreview(File(fixture).readAsBytesSync());
        expect(matches.length, 6, reason: 'panel detection');
        expect([for (final m in matches) m.assigned.speciesId], truth);
      },
          timeout: const Timeout(Duration(minutes: 3)),
          skip: File(fixture).existsSync() ? false : 'fixture missing');
    }
  });
}
