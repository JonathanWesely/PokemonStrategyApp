# Data update ritual (plan §5.1) — per regulation rollover, ~5 minutes

Champions rotates regulations every ~2–3 months (M-A → M-B → ...), each
adding Pokemon, moves, and Megas. Keeping the app current is data-only —
no app code changes.

## The ritual

1. `dart run tool/update_data.dart`
   - TODAY: validates the packs in `assets/data/` (missing base stats,
     unknown types/moves/items, illegal SP spreads, usage referencing
     species that aren't in the pokedex) and prints a coverage summary
     including which species have **no usage data** (the dashboard dims
     those).
   - PHASE 0 TODO — add the fetch stages to this same script:
     a. regulation roster + permitted Megas (Victory Road/Serebii style
        sources),
     b. base stats / types / abilities / learnsets for new species
        (PokeAPI),
     c. usage stats: moves/items/abilities/spreads/teammates
        (Pikalytics/QuickPika — no official API, so scrape gently and
        cache; the pack format is provider-agnostic on purpose).
     Then print a DIFF summary (species added/removed, new Megas, new
     moves) and rewrite the packs with a bumped `generatedAt`.
2. Read the diff/validation output. Anything unresolved is listed loudly.
3. `flutter test` — the pack-integrity suite is the same rules, enforced.
4. Rebuild the app (`flutter run` / release build). The Settings screen
   shows the active pack's regulation + generated date; the home banner
   disappears once `source` is no longer `starter-placeholder`.

## Day one of a new regulation

Usage stats barely exist yet. Ship the roster/pokedex update immediately —
matchups, stats, manual entry are all fully accurate. Prediction
percentages auto-dim (low-confidence) and sharpen as you re-run step 1
over the following days.

## The one exception: new mechanics

If the Omni Ring gains a new gimmick (Terastallization, Dynamax...), that
changes battle RULES, not data — plan one small dev session: add a forme/
state to the gimmick model (`megas` today generalizes), its stat/type
effects, and a dashboard toggle. Everything else stays data-driven.

## Pack files & schema

| File | Contents | Schema notes |
|---|---|---|
| `pokedex.json` | species: types, baseStats, abilities, learnset, megas | `source`, `generatedAt` at top |
| `moves.json` | id, name, type, category, power, accuracy, priority, note | `power: null` = status/varies; `accuracy: null` = never misses |
| `items.json` | id, name, desc | Mega Stones: desc starts "Mega Stone" |
| `type_chart.json` | 18 types + attack map | only non-1.0 multipliers stored |
| `usage_<reg>.json` | per species: usage%, moves/items/abilities pct, spreads (nature+SP), teammates | `regulation` + `source` at top |
| `regulations.json` | the format picker list | pickSize 3 (singles) / 4 (doubles) |
