# Recognition contract — engines ↔ app

Every engine implements `RecognitionService.recognize(imageBytes, context)`
and returns the same `RecognitionResult`, so the UI never knows which one is
running. The `context` carries your picks (your side never needs
recognition), the format's field slots and team size, and — new — which
**screen** the snapshot shows:

| screen | what's visible | how each engine reads it |
|---|---|---|
| `preview` | Team-select: your 6 (named) left, enemy 6 as **2D sprites, no names** right | Local: sprite matcher · API: "identify each enemy from its 2D sprite art, top-to-bottom" prompt |
| `battle` | The field: names + HP banners (enemy top, yours bottom) | Local: on-device OCR + fuzzy roster match · API: "3D model first, name text second" prompt |

## Local engine (on-device, no network)

**Preview** — `sprite_matcher.dart`:

1. Downscale to 1200px; find the six enemy panels by their crimson color
   (row profile of a hue mask over the right half).
2. Per panel: crop the sprite region (x 14–62% of panel width, 6% vertical
   inset — the edge glow otherwise destabilizes segmentation), soft
   foreground weights from distance to the panel background color, keep the
   largest connected blob.
3. Score each species: **exemplar NCC** (masked, per-channel, against
   sprites segmented from previously confirmed photos + bundled seeds in
   `assets/exemplars/`) — the trusted signal; falling back to a
   **semantic color-class histogram** against bundled art
   (`assets/sprites/{home,icons,}/`) with confidence scaled to ≤0.5 so the
   UI treats it as a guess.
4. Unique assignment across panels (the six enemies are distinct), then the
   UI shows unconfirmed slots in amber with the runners-up one tap away.
   **Every confirmation saves the segmented crop as a new exemplar**, so
   accuracy climbs with every battle. Constants live at the top of
   `sprite_matcher.dart`; the fixture tests in `test/sprite_matcher_test.dart`
   pin the behavior against `test/fixtures/preview1.jpeg`.

**Battle** — `battle_ocr.dart` (+ `mlkit_ocr.dart` for the actual OCR):
name banners → fuzzy roster resolution (exact → forme-prefix → edit
distance ≤2), side from your-picks membership then vertical position, HP
from `NN%` or `cur/max` fragments near the name.

## API engine (`cloud_vision_recognizer.dart`)

One class, two wire formats:

* **Anthropic Messages** — `POST {base}/v1/messages`, image as base64
  block, `x-api-key` header.
* **OpenAI-compatible chat completions** — `POST {base}/chat/completions`,
  image as `data:` URL, `authorization: Bearer` header. Works with OpenAI,
  Gemini's compatibility endpoint, and local servers (Ollama, LM Studio) —
  set the base URL in Settings.

Both send the roster + your pick names + the screen-specific instruction,
and require this reply (prose/code-fence wrapping is tolerated):

```json
{"pokemon":[{"name":"<species name from the roster>",
             "side":"yours"|"enemy",
             "hpPercent":0-100|null,
             "mega":true|false,
             "confidence":0.0-1.0}]}
```

Unknown names are skipped (never crash); names resolve through
`DataPack.resolveSpeciesName`.

Keep this document in sync with `_prompt()` in
`cloud_vision_recognizer.dart` when tuning.
