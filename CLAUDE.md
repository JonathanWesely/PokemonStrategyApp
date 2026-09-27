# PokemonStrategyApp — session notes for Claude

Flutter battle companion for Pokemon Champions. The authoritative project
plan lives in the Obsidian vault: `JonWesOBVault/PokemonStrategyApp.md`
(architecture, phases, data ritual, decision log). Keep its Decision Log
updated when direction changes — Jonathan relies on it between sessions.

## Current architecture (2026-09-06)

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
- **Sprite matching (2026-09-06 rewrite)**: three tiers, best score wins per
  species — (a) user exemplars, (b) the **Champions template tier**, (c) the
  legacy art histogram, which now only runs if the atlas asset is missing.
  Tier (b) is masked NCC against the game's OWN 2D sprites, packed as 32x32
  RGBA tiles in `assets/sprites/champions_atlas.png` with an index at
  `assets/data/champions_refs.json` (`champions_atlas.dart` loads both). It is
  same-domain, so it works from a cold start — the old tier compared against
  PokeAPI HOME renders, a different artist's 3D model, and could only manage a
  colour histogram.
- **Trained classifier DECIDES when bundled (2026-09-19)** —
  `lib/src/recognition/sprite_cnn.dart` + `assets/models/sprite_cnn.{bin,json}`,
  trained by `tool/sprite_cnn/` (README there). Pure Dart, no native ML
  runtime, so it runs under plain `flutter test`. It reads a FIXED window of
  each panel (x 0.10-0.63, y 0.04-0.96 of the panel rect), area-resamples it
  to 48x48 and standardises each channel — no segmentation, which is exactly
  what the rig's low contrast breaks. 4 conv3x3 stages (24/48/96/160, BN
  folded) + global average pool + dense over the 262 tiles; 233k floats,
  ~18M MACs per panel. Trained ONLY on synthetic panels (the 262 sprites on
  randomised cards with blur, contrast compression, colour cast, translucent
  card bleed, glare, scanlines, JPEG and finder jitter — calibration in
  `render.py`); the real frames are held out and scored every epoch: rig2 6/6
  (the template tier: 2/6 in the app), select1 6/6, preview1 6/6, softmax
  0.66-0.97 with the runner-up <= 0.02, 100% under +-6-8% finder jitter.
  All-262 rig-like render: 99.6% vs the template tier's 36% (the one miss is
  Gourgeist sizes, which differ only in scale). Badges enter as a likelihood
  ratio (x1.5 agree / x0.5 contradict, renormalised); exemplars override only
  on a near-duplicate crop (NCC >= 0.85 — the Lycanroc-Dusk seed scored 0.40
  on the rig's Ceruledge). `useCnn: false` forces the old tiers, which remain
  the fallback when the model files are absent. `export.py:forward` is the
  numpy twin; `test/sprite_cnn_test.dart` checks the Dart against goldens
  (`make_goldens.py` — REGENERATE after every retrain) and runs all three
  fixtures end to end. Only ONE rig frame exists as a test (the first was
  overwritten by the next pull): `.\tool\pull_scan.ps1 -Truth "A,B,C,D,E,F"`
  now archives every pull with its truth — collect more before trusting the
  rig number, and retrain with any frame it gets wrong held OUT.
- **Type badges as a soft prior**: each enemy panel's 1-2 badges are read from
  `assets/sprites/type_badge_atlas.png` by body chromaticity (exposure
  invariant) + white-glyph IoU. A read that doesn't beat its runner-up by
  `_minBadgeMargin` is discarded — an absent badge means "no prior", a wrong
  one is evidence, so a coin flip is worth less than silence. Matching types
  add `typePriorBonus`, contradicting ones subtract `typePriorPenalty`; both
  are small next to a good NCC so the sprite always decides. **A single-type
  card centres its one badge between the two slots** (each slot sees half,
  neither half clears the margin gate — Raichu on select1 read nothing and
  lost its +0.22 to a Froslass coin flip, 2026-09-14): when the slots read
  nothing, `badgeBoxes` finds the badge squares themselves from column runs
  of off-card pixels and reads those.
- **A badge read must clear `_minGlyphIou` (0.35) on the white-glyph IoU**, not
  just the hue score. Hue always names SOME type; on a soft, colour-cast
  capture it names the wrong one *confidently*. The rig's 25 px badges are
  below its blur limit — the 2026-09-17 frame read Water as Fire and Ghost as
  Normal at IoU 0.03/0.12 — while correct reads on the phone fixtures score
  0.38+. An unread badge costs nothing (it means "no prior"); a wrong one is a
  ~0.32 swing the wrong way, and it cost that scan two panels it would
  otherwise have won.
- **Panel finder (2026-09-06, after the first rig frame)**: exposure-
  invariant red/magenta chromaticity mask (`_isCard`), row bands over the
  stack's own x-range, height-consistency filter, then six evenly spaced
  slots whose phase is chosen by total red mass — a card lost to glare is
  still placed. The rig's OV2640 renders the crimson cards as dark pure red
  (R≈0.4, B≈0.05) that the old brightness-gated pink test rejected, leaving
  only the trainer-name pill. Verified 6/6 panels on the rig frame and both
  fixtures. **Pitch, card height and phase all come from FULL bands only**
  (0.8x to 1.15x the median kept band), the phase a median residual rather
  than `centers[0]`, and **slots are never snapped onto a band**. A sprite
  bright enough to break the card mask splits its card into fragments; the
  trainer-name pill fuses with card 1 at the 1200 px DETECT scale. Both
  survive the height filter, and both slid the whole six-slot layout when used
  as the anchor or snapped to — 28 px on the first 2026-09-17 rig frame, 24 px
  on the second. Unsnapped, the model lands within ~2 px of every card on
  both. Card height is the median full band, not 0.90 x pitch, which
  over-cropped the short cards of the synthetic test screen. The sprite
  segmenter also takes its background from card-coloured border pixels only.
- **`tool/dart_twin.py` is the faithful twin** — crop geometry, segmentation
  constants, square-pad/resize and the masked-NCC-plus-shape score all mirror
  `sprite_matcher.dart` line for line, including the workWidth downscale for
  DETECTION and the crop from ORIGINAL pixels. Use it, not
  `recognition_prototype.py`, to predict what a scan will do:
  `python3 tool/dart_twin.py <frame.jpg> "Truth One,Truth Two,..."`. It scores
  6/6 on both phone fixtures from the template tier alone. The prototype is
  the design sandbox and its constants had drifted (alpha at d>80 against the
  Dart's ~31) until it disagreed with the app by 2-3 panels on a rig frame.
  Neither models the exemplar tier, so the app can still differ where a
  bundled seed wins.
- **`flutter test test/scan_dump_test.dart`** writes `test/_scan_dump/
  {select1,preview1,synthetic}/` (frame, overlay, crops, top-8 per panel) —
  the first thing to look at when a fixture test fails. Keep `test/_scan_dump/`
  out of git.
- **CONTRAST, not blur, is what the template tier needs** (`tool/capture_sweep.py`,
  2026-09-18). Rendering the roster back onto a card and degrading it:
  phone-like 98.6% top-1; rig-like (blur 1.6, contrast 45%, blue -45%) 25.7%;
  halving the blur 24.3% (no help); restoring contrast with blur and cast
  UNCHANGED 94.3%. The cause is that `_segmentSprite`'s foreground gate is an
  ABSOLUTE distance from the card colour (`fgThresholdLow` 0.12, span 0.25):
  the rig's sprite-vs-card separation maxes at 0.29-0.92 against the phone
  fixtures' 0.81-1.06, so most of each sprite falls under the gate, the crop
  becomes a fragment, and NCC of a fragment against a whole tile is noise.
  25.7% over six panels is ~1.5 correct — exactly the 1/6, 1/6, 2/6 the rig
  scans returned. A naive per-panel contrast gain fixes the worst panels
  (Ceruledge rank 14 -> rank 1) and breaks the best (Charizard rank 1 -> 111),
  so the gate needs to be relative WITHOUT amplifying background.
- **That gate is not fixable by tuning — six formulations tried, all worse**
  (2026-09-18, scored on the rig frame + both fixtures, 18 panels total;
  today's absolute gate = 16/18). Do not re-try these:
  normalise d by its own p99.5 (13/18) · Otsu split on d (8/18) · gate at 28%
  of the crop's peak (9/18) · signal-to-noise gate off the card's own noise
  (no-op: the rig's noise did not compress, only its signal) · a generous
  threshold for the EXTENT with the strict one for the weights (7/18 — the box
  grows to the whole window) · matching against extra RIG-DEGRADED copies of
  every template (15/18 — a blurred template correlates with every blurred
  blob, so it lifts the wrong species more than the right one).
  Each adaptive gate trades panels rather than winning them: p99.5 normalising
  takes Ceruledge from rank 14 to rank 1 (0.151 -> 0.695) and simultaneously
  takes Charizard from rank 1 to rank 111. The descriptor is square-padded on
  the SEGMENTED bbox, so a lost tail changes the aspect ratio and the match
  dies — Drampa is 2:1 wide, its crop came out 1:1, rank 65. The conclusion is
  that the fault is the design's dependence on a clean segmentation, not a
  constant that wants another pass.
- **Rig focus**: the first rig frame's enemy column scored ~30 on Laplacian
  variance vs 430–890 for the phone-photo fixtures at the same scale — out
  of focus by more than an order of magnitude, and no matcher survives that.
  The Rig preview now shows a live "Focus NNN" chip (centre-crop Laplacian
  variance, 1 Hz, off-isolate); turn the lens barrel until it peaks. Then
  worry about recognition accuracy.
- **Panels are found on a workWidth copy but cropped from the ORIGINAL**
  image. Segmenting off the downscaled copy costs ~40% of the template score
  on a small sprite.
- **Plugin isolation rule**: camera/image_picker only in
  `ui/capture_screen.dart`; ML Kit only in `recognition/mlkit_ocr.dart`;
  network only in `recognition/cloud_vision_recognizer.dart` +
  `recognition/network_camera.dart`.
- **Auto-scan is the default capture path (2026-09-20)**: starting a battle
  connects to the saved rig stream (`net_cam_url`) by itself —
  `recognition/auto_scan.dart` (`AutoScanController`, injected frames/URL/
  phase so it unit-tests without a network). Team preview scans every 5 s
  until picks are locked (confirmed boxes never overwritten), then the
  0.5 s in-match TEXT tracker takes over regardless of tab. The battle
  buttons are now just "Manually scan" (opens the old capture screen, which
  PAUSES auto-scan while open — the ESP32 serves ONE stream client).
  Local engine only; toggle in Settings (`auto_scan`), status chip with
  pause/resume on both battle tabs. Restarting auto-scan (settings change)
  preserves the paused state or it would steal the capture screen's stream.
- **In-match tracking reads the printed TEXT, not sprites**
  (`recognition/battle_events.dart`, `BattleEventTracker`): local-engine
  battle scans OCR once and feed the same lines to BattleTextMatcher (who
  is on field + HP; also syncs YOUR active chips) and the tracker —
  "`<Name>` used `<Move>`!" -> revealedMoves + speed evidence, "`<Name>`'s
  `<Ability>`" -> revealedAbility, item lines -> revealedItem, "twisted the
  dimensions"/"Tailwind blew" -> field flags on BattleSession. Events
  de-dup within 6 s (a message stays on screen across ~12 frames at 2/s);
  a repeated actor or a 25 s gap starts a new turn.
- **✓/? is the certainty convention everywhere**: ✓ = confirmed this match,
  ? = predicted. RatedOptionRow prints "seen ✓" / "~45% ?", the speed strip
  marks each row. Speed-order evidence = "moved first at the same move
  priority" (inverted under Trick Room, ties ignored); pairs live in
  `BattleSession.speedEvidence` as [fasterKey, slowerKey] with keys
  `y:<id>`/`e:<id>`, latest observation wins, and
  `applySpeedEvidence` reorders the strip over the stat-based prediction.
- **Scan Team (2026-09-21)** imports a whole team from the game's two
  team-display pages — `recognition/team_scanner.dart`, button inside the
  team editor, flow in `ui/scan_team_screen.dart` (upload or take a picture;
  the camera view defaults to the rig). Cards = purple chromaticity mask;
  species = printed name first (nicknames fall back to sprite DETECTION:
  slide each 32 px reference tile over the icon window, masked NCC with the
  template's own alpha, coarse 96 px pass then a 160 px re-rank — no
  segmentation, because white sprites on cream and purple on the card broke
  every gate, 18/24 vs detection's 20/24; `tool/team_scan/`). Form families
  whose members DIFFER IN TYPING (Tauros breeds, Rotoms, base-vs-regional)
  are settled by the card's own TYPE BADGES (`familyFromBadges` +
  `ChampionsReferenceSet.badgeTypeScore`, twin `tool/team_scan/badge.py`):
  two fixed slots in the name strip (fx 0.461/0.518 of card width, single
  badge always slot 1; runs kept only when centered in a slot — the gender
  circle and a card-edge artifact sit outside), white-GLYPH fraction >0.035
  marks a slot whose badge body hides in the strip purple (Ghost/Poison/
  Dragon), candidates filtered by badge COUNT then scored against their
  OWN types only — never an 18-way read, which genuinely fails here. 24/24
  counts, 6/6 picks on the fixtures, Blaze vs Aqua 0.75 vs 0.47. The
  sprite still settles SAME-type families (Indeedee, Lycanroc…) and is the
  fallback when badges can't call it; a near-tie there (<0.05 — the
  Paldean bulls differ by pixels at tile size) is imported but FLAGGED.
  Gender = the ♂/♀ circle right after the name box
  (royal blue / pink-red; badges sit further right). NATURE IS MATH, not
  arrows: every displayed stat must reproduce from StatCalculator under
  exactly one of x0.9/x1.0/x1.1 given base+SP, which identifies the nature
  AND self-checks the OCR (a missing SP number is re-solved from the shown
  stat; anything that verifies under no multiplier is flagged). The held
  stone sets megaFormeId; PokemonBuild gained `gender`. The scanned team
  opens PRE-FILLED in the editor with a warnings dialog — review, then
  save. Fixtures: `test/fixtures/team{1,2}_{moves,stats}.jpeg` +
  `test/team_scanner_test.dart` (scripted OCR laid out against the card
  boxes the scanner itself finds).
- **The pack's Champions-original stone names were guesses** until the
  2026-09-21 team photos showed the real ones: `sableyeite`->`sablenite`,
  `scolipedeite`->`scolipite` (ids AND names), Grassy Seed added. If another
  guessed name shows up on screen, fix the pack, don't fuzzy around it.
- **iOS via Codemagic + TestFlight (2026-09-22)**: no Mac anywhere —
  `codemagic.yaml` (repo root) builds the ipa on a cloud Mac with
  automatic signing through the App Store Connect API key (integration
  name `AppStoreConnect`) and uploads to TestFlight; build number =
  `$PROJECT_BUILD_NUMBER`, builds started MANUALLY on codemagic.io.
  Codemagic FETCHES signing files, it does not create them: the Apple
  Distribution cert lives in Codemagic Code signing identities and the
  App Store profile was made on the developer portal + fetched
  (2026-09-23) — a build failing pre-step with “No matching profiles
  found” means those are missing, not that the yaml is wrong.
  Deployment target is **15.5** (ML Kit floor) in project.pbxproj AND the
  new ios/Podfile; Info.plist carries the usage strings + the
  `NSAllowsLocalNetworking` ATS exception + `ITSAppUsesNonExemptEncryption
  = false`. The step-by-step (accounts, first install, updates,
  distributing) lives in the vault:
  `JonWesOBVault/how to make android app available for iPhone.md`.
- **Capture sources (2026-08-23)**: phone camera, gallery, and **Rig**
  (network MJPEG stream from the camera pod at `http://<ip>:81/stream`;
  `network_camera.dart` holds the client + SOI/EOI frame parser, URL
  persisted as setting `net_cam_url`). Any MJPEG source works (IP Webcam
  at `:8080/video` for rig-free testing).
- **Reference assets**: `pokemon2Dsprites/` (262 named, alpha-cut Champions
  sprites) and `pokemontypeimages/` are the *sources*, kept in the repo root,
  not shipped. `tool/split_sprite_sheets.py` rebuilt the M-B set from screen
  captures of the in-game Eligible Pokemon grid; `tool/split_photo_sheets.py`
  added the M-C set from hand-held *photos* of that grid (rectifies the
  photo, aligns the overlapping shots, cuts only the inserted cells, with a
  glare-tolerant segmenter); `tool/build_champions_atlas.py` packs them into
  the two shipped atlases. `tool/recognition_prototype.py` is the Python
  reference implementation the Dart mirrors — tune constants there first, it
  iterates in seconds.
- **Data packs** in `assets/data/` (now incl. `abilities.json` + move
  `desc` fields); sprites in `assets/sprites{,/home,/icons}`; exemplar
  seeds in `assets/exemplars/`. `dart run tool/update_data.dart` validates
  everything; real fetchers are still the Phase 0 TODO.

## Diagnosing a bad scan

Debug builds write every local team-preview scan to `documents/last_scan/`
(`frame.jpg`, `overlay.jpg`, `panel_N.png` crops, `report.txt`) and print the
report to the `flutter run` console. Each scan OVERWRITES it — scan once, pull,
then scan again. Pull it with

```powershell
.\tool\pull_scan.ps1          # -> test\_scan_dump\live\, prints report.txt
```

**On iPhone (2026-09-26)**: no adb — instead the dump is gated on the
`scan_diagnostics` setting (debug builds default ON, release OFF; toggle
in Settings → “Save scan diagnostics”), and Info.plist now sets
`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`, so the
app's documents folder shows in the Files app: On My iPhone → Pokemon
Strategy → last_scan. Share frame.jpg + overlay.jpg + report.txt (and
panel crops) straight into a Claude session — the twin runs on the exact
scanner input.

**Naming (Jonathan's convention, 2026-09-27)**: the in-match enemy scan
is the **match preview scan** (dump: `last_scan/`); the two-photo team
import is the **team build scan** (dump: `last_team_scan/` — moves.jpg,
stats.jpg, an overlay per photo with card boxes green + OCR lines
yellow, and report.txt with every OCR line and the per-slot result;
written by `_teamScanDebugWriter` in main.dart via `TeamScanner.scan`'s
`onDebug`, fired on failed scans too). SEPARATE folders on purpose —
the two dumps get analyzed in parallel. One Settings toggle gates both.
Also 2026-09-27: the Battle tab's "+ Enemy" picker offers only the
enemy team from the Team Preview tab, not the whole roster.

(`run-as ... cp /sdcard/Download` is denied on this emulator image; the script
uses the base64 tar pipe, the one route that works without root.) Every pull is
also copied to `test\_scan_dump\archive\<timestamp>\`; add
`-Truth "Charizard,Venusaur,..."` (top to bottom) and a `truth.txt` goes with
it — that archive is the rig test set. For the
fixtures instead of a device, `flutter test test/scan_dump_test.dart` writes
the same thing for select1/preview1/synthetic. Keep `test/_scan_dump/` out of
git.

`frame.jpg` is the point: it is the exact input the Dart matcher scored, so
`tool/recognition_prototype.py <frame>` re-runs the Python twin on the same
pixels — twin right + Dart wrong means the PORT drifted, both wrong means the
ALGORITHM or the references are at fault. That split is worth more than any
amount of squinting at scores.

The report's first two lines answer the usual questions: frame size (are the
sprites even 25 px?) and `runtime exemplars` (has a run of wrong confirmations
poisoned the learning store? Settings → Reset learned sprites). Each panel line
gives the badge types read, `-> ` the species finally ASSIGNED (not always the
top candidate — the greedy uniqueness pass can hand a species to a
higher-scoring panel), then the top-5 with tier tags `[c]nn` (a probability),
`[e]xemplar`, `[t]emplate`, `[a]rt`. The overlay draws the panel rect green, the sprite region cyan, the
classifier's window orange, and
every badge box the reader looked at — yellow if it produced a type, magenta
if it read nothing.

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

- The pack holds the FULL Champions roster (2026-08-16 import, extended
  2026-09-14 for Regulation M-C): real stats from the PokeAPI GitHub dump
  for every entry, 81 Megas (incl. Champions originals like Mega Froslass
  and the M-C "Z" Megas). Four VGC staples the July scaffold guessed are
  NOT in Champions (amoonguss, landorus-therian, chien-pao,
  urshifu-rapid-strike) — don't reference them in tests. Rillaboom and
  Salamence were on that list until M-C added them for real. Importers:
  full_roster.py (session workspace), `tool/add_form_species.py`,
  `tool/add_reg_mc.py`.
- Usage percentages are hand-authored placeholders for ~29 species only
  (`source: starter-placeholder`); everything else falls back to learnset
  with dimmed confidence. The home-screen banner says so.
- The sprite matcher's constants were tuned against
  `test/fixtures/preview1.jpeg` and `test/fixtures/select1.jpeg` via
  `tool/recognition_prototype.py`; if you touch segmentation, re-run the
  fixture tests and expect to regenerate `assets/exemplars/*.png` (they must
  come from the same pipeline).
- **The pack has 262 species = the 262 tiles of the Regulation M-C
  Eligible Pokemon grid** (235 from M-B + 27 added 2026-09-14), in the
  grid's National Dex order — the atlas index, `pokemon2Dsprites/manifest.json`
  and `pokedex.json` are all in that same order and the tools rely on it.
  Every form the game lists separately is its own species with real PokeAPI
  stats/learnsets: five appliance Rotoms (each with only its own signature
  move), Meowstic-Female, Gourgeist small/large/super, Lycanroc
  midday/midnight/dusk, Basculegion-Female (2026-09-06); Alolan Persian,
  Toxtricity Amped/Low Key, Indeedee Male/Female, Squawkabilly Green/Yellow
  (2026-09-14). `lycanroc` was RENAMED `lycanroc-midday` (it always carried
  Midday's stats); the usage placeholder moved to `lycanroc-dusk`. Adding
  more: `tool/add_form_species.py` / `tool/add_reg_mc.py` show the recipe.
- **M-C counted 24 "new Pokemon" but the grid gained 27 tiles**: the game's
  own list names 29 (four Squawkabilly plumages) yet the grid shows only
  Green and Yellow Squawkabilly, so 24 names -> 27 tiles. Blue/White plumage
  would match Green/Yellow's silhouette at a different hue if they ever
  appear in a preview. The six M-C Megas (Salamence, Golisopod, Baxcalibur,
  Absol Z, Garchomp Z, Lucario Z) sit on their species' `megas` lists —
  Absol/Garchomp/Lucario now have TWO Megas each, like Charizard.
- `regulations.json` is on Reg M-C (2026-09-09 → 2026-12-02). The usage
  placeholder file is still `usage_reg_mb.json` (loaded by fixed path in
  `asset_loader.dart`); its `regulation` field is only a label.
- **Fixture truth was mislabelled** until the true-sprite matcher caught it:
  preview1.jpeg panel 3 is base Decidueye (green hood, Grass+Ghost badges),
  not Hisuian; panel 4 is Lycanroc-Dusk. Exemplar seeds are named
  `decidueye.png` / `lycanroc-dusk.png` accordingly. When labelling a photo,
  read the type badges — they settle regional forms instantly.
- `test/fixtures/champions/*.png` (the six sprites the synthetic preview
  test pastes onto its fake screen) are COPIES of `pokemon2Dsprites/` and
  must be refreshed whenever those are re-cut — the 2026-09-06 re-audit
  un-clipped Gholdengo's feet in the atlas but not in the fixture, and the
  clipped fixture then scored 0.32 against its own unclipped tile.
- **v4 can punch holes through sprites whose colours overlap the page blue.**
  It zeroes alpha wherever a pixel is within 30 of the gap/page colour, and
  Sableye's lit purple head sits inside that radius, so its first cut had 14
  holes (fixed 2026-09-19 via `RECUTS` + `segment_lowcontrast` in
  `tool/split_sprite_sheets.py`; `--recut Sableye` redoes it and patches the
  manifest). Quaquaval shows the same speckled holes and Glimmora/Milotic
  may too — check any blue/purple sprite on magenta before trusting it.
- **Never run index-writing git commands through the Cowork sandbox**
  (`git status`/`add`/`commit` via device_bash): git creates `.git/index.lock`
  while it works, and the sandbox is not allowed to DELETE files, so the lock
  is left behind and every later git operation — including GitHub Desktop —
  fails with "A lock file already exists". That is exactly where the stale
  Aug 28 `HEAD.lock` and Sep 6 `index.lock` came from (cleared 2026-09-20
  into `_to_delete/`). Read-only inspection (`git log`, `cat .git/HEAD`) is
  fine; anything that touches the index belongs in Jonathan's own shell.
- The four `images/RegulationMBPokemon*.png` captures OVERLAP — the list was
  scrolled between shots. The splitter de-duplicates by matching tail rows
  against head rows; don't assume 4 x 80 cells.
