/// The Champions reference tier: the packed atlas of the game's REAL 2D
/// sprites + type badges, and the end-to-end recognition it enables.
///
/// The fixture here (`select1.jpeg`) is a photo of the actual team-select
/// screen. Nothing about it is synthetic and nothing in it came from the
/// atlas, so a pass is real evidence rather than a round trip.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/recognition/champions_atlas.dart';
import 'package:pokemon_strategy_app/src/recognition/sprite_matcher.dart';

import 'helpers.dart';

Future<Uint8List?> fileLoader(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

void main() {
  final pack = loadRealDataPack();

  group('reference atlas', () {
    test('loads every packed sprite and badge', () async {
      final refs = await ChampionsReferenceSet.load(fileLoader);
      expect(refs, isNotNull, reason: 'assets/sprites/champions_atlas.png');
      // 235 Regulation M-B entries + 27 M-C additions (2026-09-14).
      expect(refs!.sprites.length, greaterThanOrEqualTo(262));
      expect(refs.hasBadges, isTrue);
      // Every reference tile is square, [tile] px, and carries a real mask.
      for (final r in refs.sprites.take(20)) {
        expect(r.size, refs.tile);
        expect(r.a.length, refs.tile * refs.tile);
        expect(r.a.any((v) => v > 0.5), isTrue,
            reason: '${r.formId} has an empty alpha mask');
      }
    });

    test('every reference reports a species the data pack knows', () async {
      final refs = (await ChampionsReferenceSet.load(fileLoader))!;
      final unknown = <String>{
        for (final r in refs.sprites)
          if (!pack.species.containsKey(r.speciesId)) r.speciesId,
      };
      expect(unknown, isEmpty,
          reason: 'atlas references a species missing from pokedex.json');
    });

    test('every pack species has at least one reference sprite', () async {
      final refs = (await ChampionsReferenceSet.load(fileLoader))!;
      final covered = {for (final r in refs.sprites) r.speciesId};
      final missing = pack.species.keys.where((s) => !covered.contains(s));
      expect(missing, isEmpty);
    });

    test('every form variant is its own species, with its own typing',
        () async {
      final refs = (await ChampionsReferenceSet.load(fileLoader))!;
      final byForm = {for (final r in refs.sprites) r.formId: r};
      // Champions fields these as distinct Pokemon with distinct stats and
      // movepools, so the pack carries them as distinct species and the
      // matcher must report the exact form — Wash Rotom, not "Rotom".
      for (final form in [
        'rotom-heat', 'rotom-wash', 'rotom-frost', 'rotom-fan', 'rotom-mow',
        'meowstic-female', 'gourgeist-small', 'gourgeist-large',
        'gourgeist-super', 'lycanroc-midday', 'lycanroc-midnight',
        'lycanroc-dusk', 'basculegion-female',
      ]) {
        expect(byForm[form]?.speciesId, form, reason: form);
        expect(pack.species.containsKey(form), isTrue, reason: form);
      }
      // The badge prior sees the form's real typing — the pack agrees.
      expect(byForm['rotom-heat']?.types, containsAll(['Electric', 'Fire']));
      expect(byForm['rotom-wash']?.types, containsAll(['Electric', 'Water']));
      expect(pack.species['rotom-wash']!.types, containsAll(['Electric', 'Water']));
      // M-C: forms the game lists separately are their own species.
      expect(pack.species['toxtricity-low-key']!.abilities, contains('Minus'));
      expect(pack.species['squawkabilly-yellow-plumage']!.abilities,
          contains('Sheer Force'));
      expect(pack.species['salamence']!.megas.map((m) => m.name),
          contains('Mega Salamence'));
      expect(pack.species['absol']!.megas.map((m) => m.name),
          contains('Mega Absol Z'));
    });

    test('references and pack are one-to-one', () async {
      final refs = (await ChampionsReferenceSet.load(fileLoader))!;
      // 262 eligible entries (Regulation M-C); one reference tile each.
      expect(refs.sprites.length, pack.species.length);
      expect(pack.species.length, 262);
      expect({for (final r in refs.sprites) r.speciesId}.length,
          refs.sprites.length,
          reason: 'no two tiles should report the same species');
    });

    test('the index and the atlas agree on tile count', () async {
      final meta = jsonDecode(
              utf8.decode((await fileLoader(ChampionsReferenceSet.indexAsset))!))
          as Map<String, dynamic>;
      final refs = (await ChampionsReferenceSet.load(fileLoader))!;
      expect(refs.sprites.length, (meta['sprites'] as List).length);
    });
  });

  group('team-select screen', () {
    const fixture = 'test/fixtures/select1.jpeg';
    final missing = !File(fixture).existsSync();

    // Michell's team, read off the screenshot by eye.
    const truth = [
      'raichu',
      'staraptor',
      'pelipper',
      'swampert',
      'dragonite',
      'bellibolt',
    ];

    test('identifies all six enemy Pokemon from a cold start', () async {
      final matcher = SpriteMatcher(
        pack,
        loadBytes: fileLoader,
        // No exemplar seeds: this is purely the template tier, which is the
        // whole point — day one, before the user has confirmed anything.
        // (The classifier has its own copy of this test in
        // sprite_cnn_test.dart; useCnn: false pins down the fallback.)
        exemplars: ExemplarStore(loadBundled: (_) async => null),
        useCnn: false,
      );
      final matches =
          await matcher.matchPreview(File(fixture).readAsBytesSync());
      expect(matches.length, 6, reason: 'panel detection');
      final assigned = [for (final m in matches) m.assigned.speciesId];
      expect(assigned, truth);
      // Uniqueness: the six enemies are always six different species.
      expect(assigned.toSet().length, 6);
    }, timeout: const Timeout(Duration(minutes: 3)),
        skip: missing ? 'fixture photo not present' : false);

    test('each winner clears its runner-up by a real margin', () async {
      final matcher = SpriteMatcher(
        pack,
        loadBytes: fileLoader,
        exemplars: ExemplarStore(loadBundled: (_) async => null),
      );
      final matches =
          await matcher.matchPreview(File(fixture).readAsBytesSync());
      for (var i = 0; i < matches.length; i++) {
        final ranked = matches[i].ranked;
        expect(ranked.first.score, greaterThan(0.35),
            reason: 'panel $i top score too weak to trust');
        expect(ranked.first.score - ranked[1].score, greaterThan(0.05),
            reason: 'panel $i is a coin flip between '
                '${ranked.first.speciesId} and ${ranked[1].speciesId}');
      }
    }, timeout: const Timeout(Duration(minutes: 3)),
        skip: missing ? 'fixture photo not present' : false);
  });
}
