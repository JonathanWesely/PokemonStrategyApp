# Recognition contract — vision model ↔ app

The prompt lives in `lib/src/recognition/cloud_vision_recognizer.dart`
(`_requestBody`). This doc is the human-readable contract; keep the two in
sync when tuning.

## Request

One user message to the Anthropic Messages API containing:

1. an `image` content block — JPEG snapshot of the battle screen
   (camera photo of a TV, or a phone screenshot shared into the app), then
2. a `text` block with:
   - your own picks by name (the model never has to identify your side
     from pixels — the app already knows it),
   - the current pack's roster names to constrain matching,
   - the instruction to identify by **3D model first, name text second**
     (on-screen names can be nicknames — plan §7 risk),
   - the strict output shape below.

## Response (the model must reply with ONLY this JSON)

```json
{
  "pokemon": [
    {
      "name": "Incineroar",     // species name matched against the roster
      "side": "enemy",           // "yours" | "enemy"
      "hpPercent": 87,           // 0-100, or null if the bar isn't readable
      "mega": false,             // true if the forme looks Mega-Evolved
      "confidence": 0.97         // 0.0-1.0
    }
  ]
}
```

## Parsing rules (implemented + unit-tested)

- Tolerate prose/code-fence wrapping: the first `{...}` block is extracted.
- `name` resolves via `DataPack.resolveSpeciesName` (exact → prefix →
  contains, case-insensitive). Unknown names are **skipped, not fatal** —
  the confirm-and-correct UI covers misses.
- Engine failures throw `RecognitionException` with a human-readable
  message; the battle screen shows it in a snackbar and manual entry
  remains available.

## Tuning checklist (Phase 3)

- Build a fixture library: TV photos at angles, glare, phone screenshots,
  singles + doubles, Mega formes, low-HP bars.
- Track accuracy per fixture in a table here; tune the prompt, not the
  parser.
- Try `hpPercent` reading against known fixtures before trusting it in UI.
