# PokemonStrategyApp

Flutter battle companion for **Pokemon Champions**: build and save teams
(SP system: 66 points, 32/stat, fixed 31 IVs), then during a battle,
snapshot the screen and get the intel the game hides — ability-aware type
matchups, exact stats for your side, and predicted stats / moves / items /
abilities for the enemy side from competitive usage data, with a speed-tier
strip and a tap-to-confirm reveal ledger that sharpens predictions as the
battle progresses.

See `PokemonStrategyApp.md` in the Obsidian vault for the full project
plan (architecture, phases, data-update ritual). Sibling project of
GolfSwingTrackerApp — same toolchain, same mock-first workflow.

**Status: scaffold (plan Phases 0–2 in starter form), pre-camera.**
Everything runs against a mock recognition engine and a bundled starter
data pack: team builder with legality linting, battle setup for all four
Champions formats, the full intel dashboard, prediction engine v1 with
reveal promotion, cloud-vision recognizer (implemented + tested against a
fake API; camera wiring is Phase 3), SQLite persistence.

## Quick start

```bash
# 1. Same toolchain as GolfSwingTrackerApp (Flutter + Android Studio).
# 2. From this folder, one time:
flutter create . --platforms=android,ios --org com.jonwes --project-name pokemon_strategy_app
dart run tool/setup_platforms.dart
flutter pub get
# 3. Verify everything:
flutter test
dart run tool/update_data.dart   # data-pack validator (update ritual step 3)
# 4. Run it (Android emulator or phone):
flutter run
```

`GETTING_STARTED.md` has the click-by-click version.

## Architecture

```
lib/
  main.dart                     opens DB, loads data pack, restores state
  src/
    app_state.dart              teams + settings + active battle + engine swap
    models/                     Species, MoveData, PokemonBuild, Team,
                                BattleSession/EnemyPokemon (reveal ledger),
                                RecognitionResult, EnemyIntel, FormatSpec
    data/
      data_pack.dart            bundled JSON -> typed lookups (pure Dart)
      asset_loader.dart         the only data file that imports Flutter
      type_chart.dart           18x18 + ability/item modifiers (Levitate...)
      stat_calculator.dart      level-50 SP math (ground-truth tested)
      usage_stats.dart          per-regulation usage pack
      legality.dart             team linting per format clauses
    prediction/
      prediction_engine.dart    usage lookup + reveal promotion (v1)
      speed_tiers.dart          who-outspeeds-whom strip
    recognition/
      recognition_service.dart  abstract engine interface
      mock_recognizer.dart      simulated snapshots (no camera/key needed)
      cloud_vision_recognizer.dart  the ONLY file that touches the network
    storage/app_database.dart   SQLite: teams + settings
    ui/                         home, team/build editors (SP sliders),
                                battle setup, battle screen, intel cards
assets/data/                    pokedex, moves, items, type chart,
                                usage_reg_mb, regulations (all versioned)
test/                           ground-truth stat math, type chart,
                                predictions, recognition vs fake API,
                                legality, storage (ffi), pack integrity
tool/setup_platforms.dart       permissions patcher (run after flutter create)
tool/update_data.dart           data validator; Phase 0 adds the fetchers
docs/RECOGNITION_PROMPT.md      vision prompt + JSON contract
docs/DATA_UPDATE.md             per-regulation update checklist
```

## How the mock enables pre-camera development

`MockRecognizer` plays the role the simulated swing sensor played in the
golf app: it returns plausible usage-weighted enemies behind the same
`RecognitionService` interface the cloud engine implements, so the entire
battle flow — dashboard, predictions, reveal ledger, speed strip — runs on
an emulator with no camera, no API key, and no game. The cloud engine is
exercised in tests against a fake HTTP transport (`http`'s MockClient)
that replays canned Anthropic API responses, including messy ones
(code-fence-wrapped JSON, unknown species, API errors).

## Updating data when Champions adds new Pokemon

One command, no code changes: `dart run tool/update_data.dart` — see
docs/DATA_UPDATE.md for the per-regulation ritual and what's still TODO
(the Phase 0 fetchers). New species/moves/items/Megas are pure data;
only brand-new Omni Ring mechanics (a new gimmick) need a code session.
