/// Data pack integrity — the same holes tool/update_data.dart guards
/// against. If these fail after a data refresh, the pack is bad, not the app.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/models/pokemon_build.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();

  group('pack integrity', () {
    test('has species, moves, items, formats', () {
      expect(pack.species, isNotEmpty);
      expect(pack.moves, isNotEmpty);
      expect(pack.items, isNotEmpty);
      expect(pack.formats, isNotEmpty);
    });

    test('every learnset move exists in the moves pack', () {
      for (final species in pack.species.values) {
        for (final moveId in species.learnset) {
          expect(pack.moves.containsKey(moveId), isTrue,
              reason: '${species.id} learns unknown move $moveId');
        }
      }
    });

    test('every species has valid types and at least one ability', () {
      for (final species in pack.species.values) {
        expect(species.types, isNotEmpty);
        expect(species.abilities, isNotEmpty);
        for (final t in species.types) {
          expect(pack.typeChart.types.contains(t), isTrue,
              reason: '${species.id} has unknown type $t');
        }
      }
    });

    test('every Mega forme references a real Mega Stone', () {
      for (final species in pack.species.values) {
        for (final mega in species.megas) {
          final stone = pack.items[mega.item];
          expect(stone, isNotNull,
              reason: '${mega.id} needs missing item ${mega.item}');
          expect(stone!.isMegaStone, isTrue);
        }
      }
    });

    test('usage stats reference only known species/moves/items/abilities', () {
      for (final usage in pack.usage.bySpecies.values) {
        final species = pack.species[usage.speciesId];
        expect(species, isNotNull,
            reason: 'usage for unknown species ${usage.speciesId}');
        for (final m in usage.moves) {
          expect(species!.learnset.contains(m.id), isTrue,
              reason: '${usage.speciesId} usage move ${m.id} not in learnset');
        }
        for (final i in usage.items) {
          expect(pack.items.containsKey(i.id), isTrue,
              reason: '${usage.speciesId} usage item ${i.id} unknown');
        }
        for (final a in usage.abilities) {
          expect(species!.abilities.contains(a.id), isTrue,
              reason: '${usage.speciesId} usage ability ${a.id} unknown');
        }
        for (final t in usage.teammates.keys) {
          expect(pack.species.containsKey(t), isTrue,
              reason: '${usage.speciesId} teammate $t unknown');
        }
      }
    });

    test('usage spreads respect the SP budget (66 total, 32 per stat)', () {
      for (final usage in pack.usage.bySpecies.values) {
        for (final spread in usage.spreads) {
          final total = spread.sp.values.fold<int>(0, (a, b) => a + b);
          expect(total, lessThanOrEqualTo(spTotalBudget),
              reason: '${usage.speciesId} spread exceeds budget');
          for (final v in spread.sp.values) {
            expect(v, lessThanOrEqualTo(spPerStatCap));
            expect(v, greaterThanOrEqualTo(0));
          }
        }
      }
    });

    test('formats define sensible sizes', () {
      for (final f in pack.formats) {
        expect(f.pickSize, lessThanOrEqualTo(f.teamSize));
        expect(f.fieldSlots, f.style == 'doubles' ? 2 : 1);
      }
      // The game's core formats exist.
      expect(pack.formats.any((f) => f.pickSize == 4 && f.isDoubles), isTrue);
      expect(pack.formats.any((f) => f.pickSize == 3 && !f.isDoubles), isTrue);
    });
  });

  group('name resolution (vision output -> species id)', () {
    test('exact, case-insensitive, and partial matches', () {
      expect(pack.resolveSpeciesName('Incineroar'), 'incineroar');
      expect(pack.resolveSpeciesName('incineroar'), 'incineroar');
      expect(pack.resolveSpeciesName('BASCULEGION-MALE'),
          'basculegion-male');
      expect(pack.resolveSpeciesName('Ninetales'), 'ninetales');
      expect(pack.resolveSpeciesName('SomeNicknameXYZ'), isNull);
      expect(pack.resolveSpeciesName(''), isNull);
    });
  });
}
