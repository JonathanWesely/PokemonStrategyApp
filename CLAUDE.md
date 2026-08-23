# PokemonStrategyApp — session notes for Claude

Flutter battle companion for Pokemon Champions. The authoritative project
plan lives in the Obsidian vault: `JonWesOBVault/PokemonStrategyApp.md`
(architecture, phases, data ritual, decision log). Keep its Decision Log
updated when direction changes — Jonathan relies on it between sessions.

## Current architecture (2026-08-16)

- **Accounts**: local profiles (SQLite `profiles`), teams + match history
  scoped per profile. No server anywhere.
- **Battle mode = two tabs** (`ui/battle_screen.dart`):
  *Team Preview* — your 6 vs enemy 6 boxes; tap for the full per-species
  page. *Battle* — on-field intel cards + predicted enemy bench.
  **Picks are chosen INSIDE the battle** (Battle tab shows the selector
  until locked; ✎ to change) — scout preview first, then commit, same
  order the game forces. BattleSession starts with empty picks.
- **Color language everywhere**: green = confirmed this battle, amber =
  predicted (usage data), grey = unknown. Applies to preview boxes, move/
  item/ability rows, bench chips.
- **Recognition engines** behind `RecognitionService` (+ `RecognitionScreen
  {preview, battle}` context): `local` (default — pure-Dart sprite matcher
  + ML Kit OCR; **learns via the exemplar store**, see
  `docs/RECOGNITION_PROMPT.md`), `api` (Anthropic or any OpenAI-compatible
  endpoint), `mock` (emulator demo).
- **Plugin isolation rule**: camera/image_picker only in
  `ui/capture_screen.dart`; ML Kit only in `recognition/mlkit_ocr.dart`;
  network only in `recognition/cloud_vision_recognizer.dart` +
  `recognition/network_camera.dart`.
- **Capture sources (2026-08-23)**: phone camera, gallery, and **Rig**
  (network MJPEG stream from the camera pod at `http://<ip>:81/stream`;
  `network_camera.dart` holds the client + SOI/EOI frame parser, URL
  persisted as setting `net_cam_url`). Any MJPEG source works (IP Webcam
  at `:8080/video` for rig-free testing).
- **Data packs** in `assets/data/` (now incl. `abilities.json` + move
  `desc` fields); sprites in `assets/sprites{,/home,/icons}`; exemplar
  seeds in `assets/exemplars/`. `dart run tool/update_data.dart` validates
  everything; real fetchers are still the Phase 0 TODO.

## Verify before shipping

```powershell
flutter pub get
flutter analyze
flutter test          # includes fixture tests against test/fixtures/*.jpeg
dart run tool/update_data.dart
```

Tests are pure Dart (sqflite_common_ffi, fake HTTP, scripted OCR lines,
fixture photos) — no device needed. The sprite-matcher fixture tests skip
when `test/fixtures/preview1.jpeg` is absent.

## Gotchas

- The pack holds the FULL Champions roster (2026-08-16 import): 223
  pokedex entries (208 species + regional forms, Bulbapedia list) and all
  75 Megas with real stats from the updated PokeAPI dump (incl. Champions
  originals like Mega Froslass). Six VGC staples the July scaffold guessed
  are NOT in Champions and were removed (rillaboom, amoonguss,
  landorus-therian, chien-pao, salamence, urshifu-rapid-strike) — don't
  reference them in tests. Importer: full_roster.py (session workspace;
  fetches PokeAPI's GitHub dump).
- Usage percentages are hand-authored placeholders for ~29 species only
  (`source: starter-placeholder`); everything else falls back to learnset
  with dimmed confidence. The home-screen banner says so.
- The sprite matcher's constants were tuned against
  `test/fixtures/preview1.jpeg` via a Python parity prototype; if you touch
  segmentation, re-run the fixture tests and expect to regenerate
  `assets/exemplars/*.png` (they must come from the same pipeline).
