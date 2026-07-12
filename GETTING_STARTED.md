# Getting Started — running & testing the app

A click-by-click guide for Windows. If you already set up the
GolfSwingTrackerApp, **you have everything installed** — Flutter at
`C:\src\flutter`, Android Studio, the emulator, USB debugging. This app
uses the exact same toolchain and commands. (If you're starting fresh,
follow Parts 1–3 of `GolfSwingTrackerApp/GETTING_STARTED.md` first — the
installs are identical.)

You do **not** need a camera, an API key, or Pokemon Champions running for
any of this — the app ships with a **mock recognizer** that simulates the
snapshot step with plausible enemies, the same way the golf app shipped
with a simulated swing sensor.

---

## The big picture

1. **Run the automated tests** — one command, no phone or emulator.
   Proves the stat math (validated against known level-50 numbers), the
   type chart, the prediction engine, recognition parsing, and storage.
2. **Run the app on a screen** — Android phone or emulator. Build teams,
   start a mock battle, watch the intel dashboard fill in.
3. **Real snapshots** — later (Phase 3 wires up the camera). The cloud
   vision engine is already implemented and tested against a fake API;
   you can try it today by adding an Anthropic API key in Settings.

---

## Part 1 — One-time project setup

```powershell
cd C:\GitProjects\GitHub\PokemonStrategyApp
flutter create . --platforms=android,ios --org com.jonwes --project-name pokemon_strategy_app
dart run tool/setup_platforms.dart   # CAMERA/INTERNET permissions, removes stock template test
flutter pub get
```

`flutter create .` only generates the missing `android/` and `ios/`
platform folders — it does not touch the app code. `setup_platforms.dart`
is idempotent (safe to run again anytime).

## Part 2 — Level 1: run the tests (no phone needed)

```powershell
flutter test
```

You're looking for **"All tests passed!"** — that's the stat calculator
vs known VGC ground truth (Jolly Garchomp = 169 Speed, max-HP Incineroar
= 202, ...), the full 18x18 type chart with ability modifiers, prediction
reveal-promotion, the cloud recognizer against a fake API, legality
linting, and SQLite storage.

Also try the data validator (the §5.1 update ritual, step 3):

```powershell
dart run tool/update_data.dart
```

## Part 3 — Level 2: run the app

Same as the golf app: plug in your phone (USB debugging on) or start an
Android Studio emulator, then:

```powershell
flutter run
```

> Run on **Android** — like the golf app, the desktop/Chrome targets
> aren't wired up for the on-device database yet.

## Part 4 — Playing with the app

1. **New team** → tap slot 1 → search a Pokemon (try Incineroar) → set
   ability/nature/item, pick 4 moves, drag the SP sliders and watch the
   live stats update (66-point budget, 32 per stat — the Champions
   system). The amber card flags legality problems (duplicate items,
   off-learnset moves, missing Mega Stones) as you build.
2. Fill a few more slots, **Save**.
3. Tap the **battle icon** on the team card → pick a format (Ranked
   Doubles Reg M-B = pick 4 of 6) → check your 4 picks → **Start battle**.
4. Tap **Snapshot (mock)** — the mock recognizer "identifies" two enemy
   Pokemon, weighted by usage. Each enemy card shows: type matchups
   (ability-aware), predicted stat ranges, predicted moves/item/ability
   with usage bars, and common partners. The **Speed check** strip at the
   top shows exactly who outspeeds whom.
5. **Tap a predicted move** when the "enemy" uses it — it flips to
   confirmed (green) and the list re-sorts. This is the reveal ledger the
   live-tracking phase will drive automatically.
6. **Add enemy** lets you skip recognition entirely and pick from a list —
   this manual path makes the app usable in real battles TODAY.
7. Settings (gear icon): switch the engine to **Cloud vision** and paste
   an Anthropic API key to try real recognition (Phase 3 adds the camera
   flow; the engine itself already works).

While `flutter run` is active: `r` = hot reload, `R` = full restart,
`q` = quit.

---

## What's obviously fake right now

- **Usage percentages** are hand-authored placeholders (the banner on the
  home screen reminds you). Real Pikalytics-based stats arrive when the
  Phase 0 fetchers land in `tool/update_data.dart`.
- **The roster is 26 starter species** — enough to exercise every feature.
  The pack format already supports the full Champions roster.
- **Snapshot uses the mock engine** by default — the camera arrives in
  Phase 3.

## Troubleshooting

Same fixes as the golf app's GETTING_STARTED (PATH, licenses, USB
debugging). One new one:

- **"No API key configured"** when using Snapshot — you switched the
  engine to Cloud vision without a key. Add one in Settings or switch
  back to Mock.
