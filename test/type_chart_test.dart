/// Type chart correctness, including ability and item modifiers.
library;

import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final chart = loadRealDataPack().typeChart;

  group('raw type matchups', () {
    test('classic multipliers', () {
      expect(chart.typeEffectiveness('Water', ['Fire']), 2);
      expect(chart.typeEffectiveness('Fire', ['Water']), 0.5);
      expect(chart.typeEffectiveness('Electric', ['Ground']), 0);
      expect(chart.typeEffectiveness('Normal', ['Ghost']), 0);
      expect(chart.typeEffectiveness('Dragon', ['Fairy']), 0);
      expect(chart.typeEffectiveness('Poison', ['Steel']), 0);
    });

    test('dual-type stacking', () {
      // Rock into Charizard (Fire/Flying): 2 x 2
      expect(chart.typeEffectiveness('Rock', ['Fire', 'Flying']), 4);
      // Ice into Garchomp (Dragon/Ground): 2 x 2
      expect(chart.typeEffectiveness('Ice', ['Dragon', 'Ground']), 4);
      // Electric into Landorus (Ground/Flying): 0 x 2 = 0
      expect(chart.typeEffectiveness('Electric', ['Ground', 'Flying']), 0);
      // Fighting into Gholdengo (Steel/Ghost): 2 x 0 = 0
      expect(chart.typeEffectiveness('Fighting', ['Steel', 'Ghost']), 0);
      // Grass into Amoonguss (Grass/Poison): 0.5 x 0.5
      expect(chart.typeEffectiveness('Grass', ['Grass', 'Poison']), 0.25);
    });

    test('every type has an 18-entry defensive profile', () {
      final profile = chart.defensiveProfile(['Dragon']);
      expect(profile.length, 18);
      expect(profile['Ice'], 2);
      expect(profile['Fairy'], 2);
      expect(profile['Water'], 0.5);
    });
  });

  group('ability modifiers', () {
    test('Levitate blocks Ground', () {
      expect(chart.effectiveness('Ground', ['Ghost', 'Poison'],
              ability: 'Levitate'), 0);
    });

    test('Flash Fire blocks Fire', () {
      expect(chart.effectiveness('Fire', ['Fire'], ability: 'Flash Fire'), 0);
    });

    test('Water Absorb / Volt Absorb / Sap Sipper immunities', () {
      expect(chart.effectiveness('Water', ['Ground'], ability: 'Water Absorb'), 0);
      expect(chart.effectiveness('Electric', ['Water'], ability: 'Volt Absorb'), 0);
      expect(chart.effectiveness('Grass', ['Normal'], ability: 'Sap Sipper'), 0);
    });

    test('Thick Fat halves Fire and Ice only', () {
      expect(chart.effectiveness('Fire', ['Normal'], ability: 'Thick Fat'), 0.5);
      expect(chart.effectiveness('Ice', ['Normal'], ability: 'Thick Fat'), 0.5);
      expect(chart.effectiveness('Fighting', ['Normal'], ability: 'Thick Fat'), 2);
    });

    test('Filter softens super-effective hits', () {
      expect(chart.effectiveness('Rock', ['Fire', 'Flying'], ability: 'Filter'),
          3); // 4 * 0.75
      expect(chart.effectiveness('Water', ['Fire'], ability: 'Filter'),
          1.5); // 2 * 0.75
      expect(chart.effectiveness('Grass', ['Fire'], ability: 'Filter'),
          0.5); // not super effective: untouched
    });

    test('Wonder Guard: only super-effective connects', () {
      expect(chart.effectiveness('Water', ['Bug', 'Ghost'],
              ability: 'Wonder Guard'), 0);
      expect(chart.effectiveness('Rock', ['Bug', 'Ghost'],
              ability: 'Wonder Guard'), 2);
    });

    test('ability names match case-insensitively', () {
      expect(chart.effectiveness('Ground', ['Poison'], ability: 'levitate'), 0);
      expect(chart.effectiveness('Ground', ['Poison'], ability: 'LEVITATE'), 0);
    });
  });

  group('item modifiers', () {
    test('Air Balloon blocks Ground until popped', () {
      expect(chart.effectiveness('Ground', ['Steel'], itemId: 'air-balloon'), 0);
      expect(chart.effectiveness('Fire', ['Steel'], itemId: 'air-balloon'), 2);
    });
  });
}
