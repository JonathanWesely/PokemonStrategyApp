/// BattleSession: the enemy-preview roster, reserve derivation, and the
/// match-history snapshot round trip. Pure Dart, real bundled pack.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/battle_state.dart';
import 'package:pokemon_strategy_app/src/models/pokemon_build.dart';
import 'package:pokemon_strategy_app/src/models/team.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();
  final doubles = pack.formats.firstWhere((f) => f.isDoubles && f.pickSize == 4);

  PokemonBuild build(String id) => PokemonBuild(speciesId: id);

  BattleSession session() => BattleSession(
        format: doubles,
        team: Team(name: 'T', builds: [
          build('incineroar'),
          build('weavile'),
          build('gengar'),
          build('whimsicott'),
        ]),
        picks: [
          build('incineroar'),
          build('weavile'),
          build('gengar'),
          build('whimsicott'),
        ],
      );

  group('pick-later flow (scout first, then lock picks)', () {
    test('battle starts unpicked; Team Preview still fully usable', () {
      final s = BattleSession(
        format: doubles,
        team: Team(name: 'T', builds: [
          build('incineroar'),
          build('weavile'),
          build('gengar'),
          build('whimsicott'),
          build('torkoal'),
          build('pelipper'),
        ]),
      );
      expect(s.picksChosen, isFalse);
      expect(s.picks, isEmpty);
      expect(s.activeYours, isEmpty);
      // Scouting works before any picks exist.
      s.enemyPreview.add(PreviewSlot('umbreon'));
      expect(s.enemyPreview, isNotEmpty);
    });

    test('setPicks locks the order and defaults the leads', () {
      final s = BattleSession(
        format: doubles,
        team: Team(name: 'T', builds: [
          build('incineroar'),
          build('weavile'),
          build('gengar'),
          build('whimsicott'),
          build('torkoal'),
          build('pelipper'),
        ]),
      );
      s.setPicks([
        build('gengar'),
        build('torkoal'),
        build('weavile'),
        build('whimsicott'),
      ]);
      expect(s.picksChosen, isTrue);
      expect(s.picks.length, 4);
      expect([for (final p in s.activeYours) p.speciesId],
          ['gengar', 'torkoal']); // first two lead
      // Re-picking replaces cleanly.
      s.setPicks([
        build('incineroar'),
        build('pelipper'),
        build('gengar'),
        build('torkoal'),
      ]);
      expect(s.activeYours.first.speciesId, 'incineroar');
      expect(s.picks.length, 4);
    });
  });

  group('reserve derivation (doubles)', () {
    test('two lead, two of your reserves', () {
      final s = session();
      expect(s.activeYours.length, 2);
      expect(s.yourReserves.length, 2);
    });

    test('enemy reserve slots come from the format (4 picked − 2 on field)', () {
      final s = session();
      expect(s.enemyReserveCount, 2);
      expect(s.enemyUnknownReserveCount, 2); // nothing revealed yet
    });

    test('revealing a benched enemy lowers the unknown reserve count', () {
      final s = session();
      s.addEnemy('incineroar'); // on field
      s.addEnemy('gengar'); // on field — both slots full
      s.addEnemy('talonflame'); // benches the oldest
      expect(s.enemiesOnField.length, 2);
      expect(s.enemyBench.length, 1);
      expect(s.enemyUnknownReserveCount, 1);
    });
  });

  group('enemy preview roster', () {
    test('holds the scouted species in order', () {
      final s = session();
      s.enemyPreview
          .addAll([PreviewSlot('incineroar'), PreviewSlot('gengar')]);
      expect([for (final p in s.enemyPreview) p.speciesId],
          ['incineroar', 'gengar']);
      expect(s.enemyPreview.length, lessThanOrEqualTo(s.format.teamSize));
    });

    test('auto-recognized slots start predicted; confirm flips them', () {
      final slot = PreviewSlot('umbreon', confidence: 0.6, confirmed: false);
      expect(slot.confirmed, isFalse);
      final round = PreviewSlot.fromJson(slot.toJson());
      expect(round.speciesId, 'umbreon');
      expect(round.confirmed, isFalse);
      expect(round.confidence, closeTo(0.6, 1e-9));
    });

    test('revealing an enemy in battle confirms its preview slot', () {
      final s = session();
      s.enemyPreview
          .add(PreviewSlot('umbreon', confidence: 0.5, confirmed: false));
      s.addEnemy('umbreon');
      expect(s.previewSlotFor('umbreon')!.confirmed, isTrue);
      // And a brand-new species lands in the preview roster too.
      s.addEnemy('sneasler');
      expect(s.previewSlotFor('sneasler'), isNotNull);
    });
  });

  group('match snapshot', () {
    test('round-trips picks, roster, and reveals', () {
      final s = session();
      s.enemyPreview.add(PreviewSlot('umbreon'));
      final e = s.addEnemy('sneasler', hpPercent: 44);
      e.revealedMoves.add('dire-claw');
      e.revealedItem = 'focus-sash';

      final snap = s.toSnapshotJson();
      expect(snap['formatId'], doubles.id);
      expect((snap['picks'] as List).length, 4);
      final enemies = (snap['enemies'] as List).cast<Map<String, dynamic>>();
      final sneasler =
          enemies.singleWhere((m) => m['speciesId'] == 'sneasler');
      expect(sneasler['hpPercent'], 44);
      expect(sneasler['revealedMoves'], contains('dire-claw'));

      final back = EnemyPokemon.fromJson(sneasler);
      expect(back.revealedItem, 'focus-sash');
      expect(back.revealedMoves, contains('dire-claw'));
    });
  });
}
