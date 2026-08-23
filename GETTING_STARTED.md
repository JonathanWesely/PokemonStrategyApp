# Getting Started — running & testing the app

A click-by-click guide for Windows. If you already set up the
GolfSwingTrackerApp, **you have everything installed** — Flutter at
`C:\src\flutter`, Android Studio, the emulator, USB debugging. This app
uses the exact same toolchain and commands.

You do **not** need Pokemon Champions running, an API key, or even a
camera for most of this — the mock engine simulates recognition, and the
real (Local) engine can be tested with the photos in `test/fixtures/`.

---

## Part 1 — One-time project setup

```powershell
cd C:\GitProjects\GitHub\PokemonStrategyApp
flutter create . --platforms=android,ios --org com.jonwes --project-name pokemon_strategy_app
dart run tool/setup_platforms.dart   # CAMERA/INTERNET permissions
flutter pub get                      # NEW deps: camera, image_picker, image,
                                     # google_mlkit_text_recognition, path_provider
```

## Part 2 — Level 1: run the tests (no phone needed)

```powershell
flutter analyze
flutter test
```

You're looking for **"All tests passed!"** — stat math vs known level-50
numbers, the type chart, predictions (including the new bench prediction),
both API wire formats against a fake server, the **sprite matcher against
your real photos** in `test/fixtures/`, OCR name-matching, storage with the
v1→v2 migration, legality, and pack integrity.

Also run the data validator:

```powershell
dart run tool/update_data.dart
```

## Part 3 — Level 2: run the app on the emulator

1. Start an Android Studio emulator (or plug in a phone), then `flutter run`.
2. First launch asks your name → that's your local account (profiles live
   in the top-right of the home screen; teams & match history are saved
   per account).
3. Build a team: **New team** → add your 6 (try your real team: Froslass,
   Avalugg, Gengar, Grimmsnarl, Incineroar, Sinistcha — all in the pack
   now, with sprites).

### Testing recognition on the emulator — two ways

**A. With the fixture photos (most reliable, no camera):**

1. Get the photos into the emulator (adb is the reliable way; drag-drop
   works but the gallery may not index until a reboot):

   ```powershell
   adb push test\fixtures\preview1.jpeg /sdcard/Pictures/
   adb push test\fixtures\battle1.jpeg /sdcard/Pictures/
   adb push test\fixtures\battle2.jpeg /sdcard/Pictures/
   adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/preview1.jpeg
   ```

2. In the app: battle icon on your team card → pick the doubles format →
   **Start battle**. The battle opens on **Team Preview** — you scout
   BEFORE picking, like the real game.
3. Team Preview tab → **Scan preview** → tap the **gallery icon** →
   choose preview1 → the six enemy boxes fill in. Amber box = the
   matcher's guess: tap it to confirm or pick the runner-up (each
   confirmation teaches the matcher).
4. Battle tab → **lock in your 4** (tap in send-out order; first two
   lead — the ★ badges; ✎ next to "Your picks" changes them later) →
   then **Scan battle** → gallery icon → battle1 → Umbreon and Sneasler
   appear on-field with HP. (OCR runs on-device via ML Kit — it works on
   the emulator, no Play Services needed.)

**B. With your laptop webcam as the emulator's camera:**

1. Android Studio → Device Manager → your AVD → ✏ Edit → Show Advanced
   Settings → Camera **Back: Webcam0** → save, cold-boot the emulator.
2. Same flow as above, but point your laptop at the Switch and press
   **Snap** instead of using the gallery. Flip on **Auto** to re-scan
   every 5 s (the hands-free tracking mode).

**C. With the camera rig (or any MJPEG stream):**

1. On either scan screen, tap the **Wi-Fi icon** (top right) to switch
   the source from phone camera to **Rig**.
2. Enter the stream address — just the rig's IP is enough (it becomes
   `http://<ip>:81/stream`) — and hit **Connect**. The address is
   remembered. Snap and Auto work exactly like the camera.
3. No rig yet? Install the **IP Webcam** app on any Android phone, start
   its server, and connect to `http://<phone-ip>:8080/video` — same
   format, great for testing. Full rig assembly + firmware: vault note
   §12.

5. On each enemy card: amber rows are predictions — tap a move/item/
   ability when the battle reveals it (turns green, list re-ranks); the
   ⓘ icon explains what anything does; "Saw a move not listed?" handles
   surprises. The enemy bench shows amber predicted reserves from their
   scouted roster.
6. End battle (✕) → Save as Win/Loss → it appears under **Match history**.

### Engines (Settings ⚙)

- **Local** (default): everything above, fully offline. Recognition
  improves as you confirm photos.
- **AI API**: choose Anthropic or OpenAI-compatible, paste a key (for
  Ollama/LM Studio set the base URL, e.g. `http://<pc-ip>:11434/v1`).
  Most accurate day one.
- **Mock**: no photos needed — "Scan" invents plausible enemies. Good for
  UI demos.

## What's still fake / pending

- **Usage percentages** are hand-authored placeholders (home-screen banner
  reminds you) until the Phase 0 fetchers land in `tool/update_data.dart` —
  and only ~29 species have even placeholder usage; the rest show their
  learnset with the "no usage data" dimming.
- The roster itself is complete: **the full Champions dex** (208 species
  incl. regional forms, all 75 Megas with real stats — Mega Froslass
  included).

## iPhone

The Dart code is iOS-ready and `setup_platforms.dart` patches the iOS
permissions, but iOS builds require a Mac — the vault note
"how to make android app available for iPhone" has the full path
(Xcode + free Apple ID for your own phone, or Codemagic/TestFlight
without a Mac). New for this app: after cloning on the Mac, also run
`pod install` under `ios/` if Xcode asks (camera + ML Kit pods).

## Troubleshooting

- **`flutter pub get` fails on a plugin version**: run
  `flutter pub upgrade google_mlkit_text_recognition camera image_picker`.
- **"Could not find the enemy team panels"**: the whole team-select screen
  must be in frame and reasonably straight-on; glare over the pink panels
  hurts. Re-shoot or fill boxes manually — every manual fix still teaches
  the matcher.
- **Emulator camera shows a green field**: the AVD camera is set to
  "Emulated" — switch it to Webcam0 (see B above).
- **"No API key configured"**: you're on the API engine without a key —
  add one or switch engines.
