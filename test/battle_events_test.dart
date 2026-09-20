/// BattleEventTracker: scripted OCR lines -> reveal ledger entries, field
/// conditions, and speed-order evidence. The lines transcribe real
/// Champions message text ("Froslass used Blizzard!" — see the 2026-09-20
/// screenshots). Pure Dart, real bundled pack.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/battle_state.dart';
import 'package:pokemon_strategy_app/src/models/pokemon_build.dart';
import 'package:pokemon_strategy_app/src/models/team.dart';
import 'package:pokemon_strategy_app/src/prediction/speed_tiers.dart';
import 'package:pokemon_strategy_app/src/recognition/battle_events.dart';
import 'package:pokemon_strategy_app/src/recognition/battle_ocr.dart';

import 'helpers.dart';

OcrLine line(String text) => OcrLine(text, cx: 0.5, cy: 0.5);

void main() {
  final pack = loadRealDataPack();
  final doubles = pack.formats.firstWhere((f) => f.isDoubles && f.pickSize == 4);

  PokemonBuild build(String id) => PokemonBuild(speciesId: id);

  BattleSession session() => BattleSession(
        format: doubles,
        team: Team(name: 'T', builds: [
          build('froslass'),
          build('grimmsnarl'),
          build('gengar'),
          build('incineroar'),
        ]),
        picks: [
          build('froslass'),
          build('grimmsnarl'),
          build('gengar'),
          build('incineroar'),
        ],
      );

  final t0 = DateTime(2026, 9, 20, 20, 0, 0);

  test('"used" lines reveal enemy moves and yield speed evidence', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);

    final events = tracker.consume([
      line('Froslass used Blizzard!'),
      line('The opposing Umbreon used Foul Play!'),
    ], at: t0);

    expect(events.map((e) => e.kind), ['move', 'move']);
    final umbreon = s.enemies.singleWhere((e) => e.speciesId == 'umbreon');
    expect(umbreon.onField, isTrue);
    expect(umbreon.revealedMoves, contains('foul-play'));
    // Your own move never lands in an enemy ledger.
    expect(s.enemies.any((e) => e.speciesId == 'froslass'), isFalse);
    // Same turn, same priority (0), Froslass moved first -> confirmed faster.
    expect(s.speedEvidence, [
      ['y:froslass', 'e:umbreon']
    ]);
    expect(s.speedRelationKnown('y:froslass', 'e:umbreon'), isTrue);
  });

  test('a message that stays on screen across frames fires once', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    tracker.consume([line('The opposing Umbreon used Foul Play!')], at: t0);
    // 2 frames/second: the same text is still on screen…
    final again = tracker.consume(
        [line('The opposing Umbreon used Foul Play!')],
        at: t0.add(const Duration(milliseconds: 500)));
    expect(again, isEmpty);
    expect(s.speedEvidence, isEmpty); // one actor, no pair
    expect(
        s.enemies.single.revealedMoves.length, 1);
  });

  test('different priority brackets never pair', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    tracker.consume([
      line('The opposing Weavile used Fake Out!'), // priority 3
      line('Froslass used Blizzard!'), // priority 0
    ], at: t0);
    expect(s.speedEvidence, isEmpty);
  });

  test('a repeated actor starts a new turn', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    tracker.consume([line('Froslass used Blizzard!')], at: t0);
    // Next turn: Froslass again — the old turn's entry must not pair.
    tracker.consume([line('Froslass used Shadow Ball!')],
        at: t0.add(const Duration(seconds: 10)));
    tracker.consume([line('The opposing Umbreon used Foul Play!')],
        at: t0.add(const Duration(seconds: 12)));
    expect(s.speedEvidence, [
      ['y:froslass', 'e:umbreon']
    ]);
  });

  test('Trick Room flips the evidence and sets the flag', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    tracker.consume([
      line('The opposing Grimmsnarl used Trick Room!'),
      line('The opposing Grimmsnarl twisted the dimensions!'),
    ], at: t0);
    expect(s.trickRoom, isTrue);
    // Under Trick Room the FIRST mover is the slower one.
    tracker.consume([
      line('The opposing Umbreon used Foul Play!'),
      line('Froslass used Blizzard!'),
    ], at: t0.add(const Duration(seconds: 8)));
    expect(s.speedEvidence, [
      ['y:froslass', 'e:umbreon']
    ]);
    tracker.consume([line('The twisted dimensions returned to normal!')],
        at: t0.add(const Duration(seconds: 30)));
    expect(s.trickRoom, isFalse);
  });

  test('ability and item lines land in the reveal ledger', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    final events = tracker.consume([
      line("The opposing Umbreon's Inner Focus!"),
      line('The opposing Sneasler hung on using its Focus Sash!'),
    ], at: t0);
    expect(events.map((e) => e.kind).toSet(), {'ability', 'item'});
    expect(
        s.enemies.singleWhere((e) => e.speciesId == 'umbreon').revealedAbility,
        'Inner Focus');
    expect(
        s.enemies.singleWhere((e) => e.speciesId == 'sneasler').revealedItem,
        'focus-sash');
  });

  test('Tailwind messages set the right side', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    tracker.consume(
        [line('The Tailwind blew from behind the opposing team!')],
        at: t0);
    expect(s.enemyTailwind, isTrue);
    expect(s.yourTailwind, isFalse);
    tracker.consume([line('The Tailwind blew from behind your team!')],
        at: t0.add(const Duration(seconds: 1)));
    expect(s.yourTailwind, isTrue);
    tracker.consume(
        [line("The opposing team's Tailwind petered out!")],
        at: t0.add(const Duration(seconds: 2)));
    expect(s.enemyTailwind, isFalse);
  });

  test('tolerates OCR mangling in both names', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    tracker.consume([line('The opposing Umbre0n used Foul P1ay!')], at: t0);
    expect(
        s.enemies.singleWhere((e) => e.speciesId == 'umbreon').revealedMoves,
        contains('foul-play'));
  });

  test('UI noise produces nothing', () {
    final s = session();
    final tracker = BattleEventTracker(pack, s);
    final events = tracker.consume([
      line('Battle Info'),
      line('MOVE TIME 41'),
      line('Show Summary'),
      line('FIGHT'),
      line('POKEMON'),
      line('Blastoise 100%'),
    ], at: t0);
    expect(events, isEmpty);
    expect(s.speedEvidence, isEmpty);
  });

  test('speed evidence reorders the strip and marks entries confirmed', () {
    final s = session();
    // Weavile (base 125 speed) predicts faster than Froslass (110) — but
    // this match showed Froslass moving first.
    s.addEnemy('weavile');
    s.addSpeedEvidence(faster: 'y:froslass', slower: 'e:weavile');
    final tiers = buildSpeedTiers(
        pack, [s.picks.first], s.enemiesOnField,
        evidence: s.speedEvidence);
    final order = [for (final t in tiers) t.key];
    expect(order.indexOf('y:froslass'), lessThan(order.indexOf('e:weavile')));
    expect(tiers.singleWhere((t) => t.key == 'y:froslass').orderConfirmed,
        isTrue);
    expect(
        tiers.singleWhere((t) => t.key == 'e:weavile').orderConfirmed, isTrue);
  });

  test('latest observation replaces a contradicting pair', () {
    final s = session();
    s.addSpeedEvidence(faster: 'e:umbreon', slower: 'y:froslass');
    s.addSpeedEvidence(faster: 'y:froslass', slower: 'e:umbreon');
    expect(s.speedEvidence, [
      ['y:froslass', 'e:umbreon']
    ]);
  });
}
