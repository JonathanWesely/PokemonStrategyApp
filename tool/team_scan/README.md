# tool/team_scan — Scan Team prototypes

Python twins of `lib/src/recognition/team_scanner.dart`, run against the
four fixture photos in `test/fixtures/team{1,2}_{moves,stats}.jpeg`.

- `proto.py` — card finder (purple mask), segmentation experiments, gender
  blobs. Segmentation topped out at 18/24 sprites (white bodies on cream,
  purple on the card), which is why the Dart uses DETECTION instead.
- `detect.py` — the detection approach the Dart mirrors: slide every 32px
  reference tile over the icon window at 5 display scales, masked NCC with
  the template's own alpha. 20/24 alone; names + form families settle the
  rest. The two stubborn misses (Scolipede, Paldean Tauros) are attractor
  ties — and the Paldean bulls are a genuine near-tie even at full
  resolution (they differ by pixels at tile size), which is why
  type-differing families are settled by the BADGES instead (below); the
  sprite only decides same-type families, and a close call there is
  flagged.
- `badge.py` — the type-badge disambiguation the Dart's
  `familyFromBadges` mirrors. The name strip holds two FIXED badge slots
  (fx 0.461–0.470 and 0.518–0.528 of card width; a single badge always in
  slot 1); runs of off-strip columns are kept only if their center lands
  in a slot window (excludes the gender circle's tail at ~0.44 and a
  card-edge artifact at 0.585+), and a slot with no run still counts as
  present when its white-GLYPH fraction clears 0.035 (a Ghost/Poison/
  Dragon badge body hides in the strip purple; the glyph never does —
  duals measured 0.063+, empty strips ≤0.010). Candidates are filtered by
  badge COUNT, then scored per-slot against their OWN expected badge
  signatures only (never an 18-way read — Blaze vs Aqua is just "Fire or
  Water?"). 24/24 slot counts, 6/6 family picks on the fixtures, all
  decisive: Tauros Blaze 0.756/0.711 vs Aqua 0.472/0.454, Heat Rotom
  0.692/0.734 vs 0.470 next, Typhlosion by count. An 18-way exact read
  was tried first and fails on these photos (Ghost/Dragon/Fairy sit near
  the strip purple, Ice near-ties Water) — restriction to the family's
  own types is what makes it decisive.
- `fusion.py` — score-fusion experiment (detection + segmentation); did NOT
  fix the misses (correlated failures), kept for the record.

Nature/stat verification needs no vision: every number on both fixture
stat screens reproduces exactly from StatCalculator's level-50 formula, so
natures come from which multiplier (x0.9/x1.0/x1.1) makes each displayed
stat check out — see test/team_scanner_test.dart.
