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
  network only in `recognition/cloud_vision_recognizer.dart`.
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

- Mega Froslass exists in Champions (Jonathan runs Froslassite) but has no
  documented stats yet — the item exists in `items.json`, the forme is
  deliberately NOT in `pokedex.json`. Add it via a data update when the
  community documents the stats; don't invent numbers.
- Usage percentages are hand-authored placeholders
  (`source: starter-placeholder`); the home-screen banner says so.
- The sprite matcher's constants were tuned against
  `test/fixtures/preview1.jpeg` via a Python parity prototype; if you touch
  segmentation, re-run the fixture tests and expect to regenerate
  `assets/exemplars/*.png` (they must come from the same pipeline).
