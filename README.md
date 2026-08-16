# PokemonStrategyApp

Flutter battle companion for **Pokemon Champions**: create a local account,
build and save teams (SP system: 66 points, 32/stat, fixed 31 IVs), then
during a battle point your camera at the screen and get the intel the game
hides — on two live tabs:

* **Team vs. Team** — your 6 vs the enemy 6 as tappable boxes. The enemy
  side fills in from a photo of the team-select screen via **2D sprite
  recognition** (their sprites have no names in-game). Tap any of the 12
  boxes for that Pokemon's full page: base stats, typing,
  weakness/resistance chart, learnable moves, abilities, and the most
  common competitive build (moves / item / ability / SP spread).
* **Battle tracking** — after both sides pick 4: the on-field Pokemon
  (recognized by OCR of the name banners), your reserves (known), and the
  enemy's **predicted** bench. Every predicted fact renders amber; when the
  battle reveals it (a move used, an item shown), tap it and it flips to
  confirmed green and the predictions re-rank. Moves, abilities, and items
  are tappable for full descriptions.

Match results save to per-profile **match history**.

See `PokemonStrategyApp.md` in the Obsidian vault for the full project
plan; `CLAUDE.md` here for session-to-session conventions. Sibling project
of GolfSwingTrackerApp — same toolchain, same mock-first workflow.

**Status: two-tab battle companion with camera capture, three recognition
engines, profiles + match history. Pre-release; usage stats still
placeholder.**

## Recognition engines (Settings)

| engine | needs | how it works |
|---|---|---|
| **Local** (default) | nothing — offline, free | Pure-Dart sprite matcher for the preview screen (exemplar library that **learns from every photo you confirm** + bundled art fallback) and on-device ML Kit OCR for the battle screen |
| **API** | an API key | Any vision model: Anthropic, or OpenAI-compatible endpoints (OpenAI, Gemini, local Ollama/LM Studio) — most accurate from day one |
| **Mock** | nothing | Simulated enemies for emulator demos |

## Quick start

```bash
# 1. Same toolchain as GolfSwingTrackerApp (Flutter + Android Studio).
# 2. From this folder, one time:
flutter create . --platforms=android,ios --org com.jonwes --project-name pokemon_strategy_app
dart run tool/setup_platforms.dart
flutter pub get
# 3. Verify everything:
flutter analyze
flutter test
dart run tool/update_data.dart   # data-pack validator
# 4. Run it (Android emulator or phone):
flutter run
```

`GETTING_STARTED.md` has the click-by-click version, including how to test
recognition on the emulator with your laptop webcam or the fixture photos.

## Architecture

```
lib/
  main.dart                     opens DB, loads packs, wires exemplar store
  src/
    app_state.dart              profiles, teams, matches, settings, battle,
                                engine swap (local | api | mock)
    models/                     Species, MoveData, AbilityData, PokemonBuild,
                                Team, BattleSession (+PreviewSlot, reveal
                                ledger), MatchRecord/Profile, Recognition*
    data/                       data_pack, asset_loader, type_chart,
                                stat_calculator, usage_stats, legality
    prediction/
      prediction_engine.dart    usage lookup + reveal promotion + bench
                                prediction (scouted roster × co-usage)
      speed_tiers.dart          who-outspeeds-whom strip
    recognition/
      recognition_service.dart  engine seam (+ RecognitionScreen)
      sprite_matcher.dart       2D sprite recognition, pure Dart (preview)
      battle_ocr.dart           OCR-lines -> Pokemon (battle), pure Dart
      mlkit_ocr.dart            the ONLY file importing ML Kit
      local_recognizer.dart     wires the two local pipelines
      cloud_vision_recognizer.dart  ApiRecognizer — the ONLY networked file
      mock_recognizer.dart      simulated snapshots
    storage/app_database.dart   SQLite v2: profiles, teams, matches, settings
    ui/                         home (profiles/history), team/build editors,
                                battle setup, two-tab battle screen,
                                capture screen (ONLY camera import),
                                intel cards, species detail, info sheets
assets/
  data/                         pokedex, moves (+desc), items, abilities,
                                type chart, usage_reg_mb, regulations
  sprites/ + sprites/home + sprites/icons   2D art for UI + matcher
  exemplars/                    seed sprites segmented from real photos —
                                the local matcher's starting knowledge
test/                           ground-truth stat math, type chart,
                                predictions (+bench), recognition (both API
                                wire formats), sprite matcher (synthetic +
                                real fixture photos), OCR matching, storage
                                (+v1->v2 migration), legality, pack integrity
test/fixtures/                  real Champions photos (preview1/battle1/2)
tool/setup_platforms.dart       permissions patcher (run after flutter create)
tool/update_data.dart           data validator; Phase 0 adds the fetchers
docs/RECOGNITION_PROMPT.md      engine contracts (local pipeline + API)
docs/DATA_UPDATE.md             per-regulation update checklist
```

## The exemplar loop (why local recognition gets better)

The sprite matcher's trusted signal is comparing against sprites segmented
from **your own previous photos** — same console, same lighting, same art.
It ships with seeds from real photos (assets/exemplars/); every slot you
confirm in the app adds another. Cold start leans on bundled official art
with capped confidence, so early sessions ask for a tap or two of
confirmation per team and improve from there.

## Updating data when Champions adds new Pokemon

One command, no code changes: `dart run tool/update_data.dart` — see
docs/DATA_UPDATE.md. New species/moves/items/Megas are pure data; only
brand-new Omni Ring mechanics need a code session. (Known gap: Mega
Froslass — the stone item exists, the forme awaits documented stats.)
