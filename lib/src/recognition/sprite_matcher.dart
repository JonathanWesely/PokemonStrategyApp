/// On-device 2D sprite recognition for the team-preview screen. Pure Dart
/// (package:image only) so the whole pipeline runs in plain unit tests
/// against the fixture photos in test/fixtures/.
///
/// Pipeline (tuned against test/fixtures/preview1.jpeg):
///  1. Downscale the photo, find the six enemy panels by their pink/crimson
///     color (row-profile of a hue mask over the right half of the frame).
///  2. Inside each panel, segment the sprite: soft foreground weights from
///     distance to the panel background color, then keep the largest
///     connected blob (plus adjacent fragments).
///  3. Score each pack species. When the trained classifier is bundled
///     (`assets/models/sprite_cnn.*`, see sprite_cnn.dart) it DECIDES: it
///     reads a fixed window of the panel with no segmentation, which is what
///     survives the rig's low-contrast frames (6/6 on the 2026-09-17 rig
///     frame where the template tier managed 2/6). Exemplars can still
///     override it on a near-duplicate crop (NCC >= [cnnExemplarOverride]).
///     Without the model, the older tiers run:
///       a. EXEMPLAR match — masked per-channel NCC against sprites the app
///          previously segmented from the user's own confirmed photos (plus
///          bundled seeds). Same-domain, so this is the reliable signal.
///       b. TEMPLATE match — masked NCC against the REAL Champions 2D sprites
///          in `assets/sprites/champions_atlas.png`. Same artwork the game
///          draws, so this is same-domain too and works from a cold start.
///       c. ART match (last resort, only when the atlas asset is missing) —
///          color-class histogram against bundled HOME/icon renders. Those are
///          a different artist's 3D model of the same creature, so only a
///          histogram comparison is meaningful; confidence is capped.
///  3b. Read the panel's TYPE BADGES and fold them in as a soft prior. Badges
///      are flat, fixed-palette pills — far more robust through a phone camera
///      than a 40px creature sprite — and 26% of the roster is uniquely
///      identified by its typing alone, 72% down to four candidates. Soft, not
///      a hard filter: one misread badge must not be able to sink a panel.
///  4. Assign species to panels greedily with a uniqueness constraint (the
///     six enemy Pokemon are all different).
///
/// Every confirmed slot feeds its segmented crop back into the exemplar
/// store, so recognition sharpens with every battle you play.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../data/data_pack.dart';
import 'champions_atlas.dart';
import 'sprite_cnn.dart';

/// Loads an asset/file as bytes; returns null when missing. Injected so the
/// matcher stays testable without Flutter (tests pass a File-based loader,
/// the app passes rootBundle.load).
typedef ByteLoader = Future<Uint8List?> Function(String path);

class SpriteCandidate {
  final String speciesId;
  final double score;
  final bool fromExemplar;

  const SpriteCandidate(this.speciesId, this.score, this.fromExemplar);
}

class PanelMatch {
  /// All species ranked best-first.
  final List<SpriteCandidate> ranked;

  /// Species chosen for this panel after the uniqueness pass.
  final SpriteCandidate assigned;

  /// The segmented sprite (RGBA PNG, alpha = foreground weight) — saved as a
  /// personal exemplar when the user confirms this slot.
  final Uint8List cropPng;

  const PanelMatch(
      {required this.ranked, required this.assigned, required this.cropPng});
}

/// Everything a failed scan needs explaining: what the matcher saw, where it
/// looked, what it read, and which tier produced each answer. Emitted through
/// [SpriteMatcher.onDebug] once per [SpriteMatcher.matchPreview] call; the
/// app writes it to `documents/last_scan/` and the console.
class SpriteMatchDebug {
  final int frameWidth, frameHeight;

  /// Width the panel finder ran at (frames wider than [SpriteMatcher.workWidth]
  /// are downscaled for detection only; crops come from the original).
  final int workWidth;
  final double scale;

  /// Panel rects in ORIGINAL-frame pixels, top to bottom.
  final List<List<int>> panels;

  /// Type badges read per panel (empty = nothing legible / margin gate).
  final List<Set<String>> panelTypes;

  /// Top candidates per panel: (speciesId, score, tier) with tier one of
  /// `cnn` (trained classifier, a probability), `exemplar`, `template`, `art`.
  final List<List<(String, double, String)>> ranked;

  /// Segmented crops per panel (RGBA PNG) — the thing that was actually scored.
  final List<Uint8List> crops;

  /// Runtime (user-confirmed) exemplars per species — the learning store. A
  /// species listed here can outrank the bundled template on NCC alone, so
  /// this is the first place to look when answers are confidently wrong.
  final Map<String, int> runtimeExemplars;

  /// The bytes that were scored, re-encoded as JPEG for the overlay.
  final Uint8List frameJpeg;

  /// Per panel, every badge box the reader actually looked at, as
  /// `[x0, y0, x1, y1, read]` where `read` is 1 when that box produced a type.
  /// The fixed slots and the single-badge fallback pick different boxes, so
  /// "no type" is only diagnosable with the boxes in hand.
  final List<List<List<int>>> badgeBoxes;

  /// Species finally assigned per panel, after the greedy uniqueness pass —
  /// NOT always `ranked[i].first` (a higher-scoring panel can take a species
  /// this one wanted). The uniqueness pass is the suspect whenever a panel's
  /// top candidate is right but its answer is wrong.
  final List<String> assigned;

  const SpriteMatchDebug({
    required this.frameWidth,
    required this.frameHeight,
    required this.workWidth,
    required this.scale,
    required this.panels,
    required this.panelTypes,
    required this.ranked,
    required this.crops,
    required this.runtimeExemplars,
    required this.frameJpeg,
    this.badgeBoxes = const [],
    this.assigned = const [],
  });
}

/// A small float RGB(+weight) raster.
class _Patch {
  final int w, h;
  final Float64List r, g, b, a;
  _Patch(this.w, this.h)
      : r = Float64List(w * h),
        g = Float64List(w * h),
        b = Float64List(w * h),
        a = Float64List(w * h);

  static _Patch fromImage(img.Image im, {bool alphaWeights = false}) {
    final p = _Patch(im.width, im.height);
    var i = 0;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++, i++) {
        final px = im.getPixel(x, y);
        p.r[i] = px.r / 255.0;
        p.g[i] = px.g / 255.0;
        p.b[i] = px.b / 255.0;
        p.a[i] = alphaWeights ? px.a / 255.0 : 1.0;
      }
    }
    return p;
  }
}

class SpriteMatcher {
  final DataPack pack;
  final ByteLoader loadBytes;
  final ExemplarStore exemplars;

  /// Tunables (prototype-derived; see docs/RECOGNITION_PROMPT.md).
  static const workWidth = 1200;
  static const fgThresholdLow = 0.12;
  static const fgThresholdSpan = 0.25;
  static const fgHardMask = 0.35;

  /// Vertical inset (fraction of panel height) cropped off before
  /// segmentation — the panel's top/bottom edge glow otherwise attaches
  /// noise blobs that destabilize the sprite bounding box (verified against
  /// the fixture photo: cross-scale exemplar NCC 0.2 -> 0.9 with this on).
  static const panelVerticalInset = 0.06;
  static const exemplarTrust = 0.45; // NCC below this -> fall back to art
  /// Art-histogram similarity maps to confidence * this scale, keeping the
  /// cold-start path below exemplar confidence and free of tie plateaus.
  static const artConfidenceScale = 0.5;
  static const descriptorSize = 24;

  /// Split of the template score between colour correlation and mask
  /// agreement — the rest is shape. Tuned in the Python reference
  /// implementation against PokemonSelectionScreen.png.
  static const templateCorrWeight = 0.75;

  /// A candidate whose typing matches the badges gains this; one that
  /// contradicts them loses [typePriorPenalty]. Deliberately small next to a
  /// good NCC (~0.6-1.0) so the sprite always has the final say.
  static const typePriorBonus = 0.22;
  static const typePriorPenalty = 0.10;

  /// Type-badge slots as fractions of the panel rect. Two right-aligned
  /// squares; a single-typed Pokemon fills only the right-hand one.
  static const List<List<double>> badgeSlots = [
    [0.635, 0.812],
    [0.812, 0.985],
  ];
  static const badgeTopFrac = 0.06;
  static const badgeBottomFrac = 0.56;

  /// Badge prior for the classifier, as a likelihood ratio: a candidate whose
  /// typing matches every badge read is weighted x(1 + boost), one that
  /// contradicts them all x(1 - cut); then the panel is renormalised. The
  /// classifier never sees the badges (its window stops short of them), so
  /// this is independent evidence — it separates Raichu from Alolan Raichu.
  static const cnnTypeBoost = 0.5;
  static const cnnTypeCut = 0.5;

  /// A user/bundled exemplar only overrides the classifier on a near-duplicate
  /// crop. Below this, a blurred blob correlates with too many things (the
  /// Lycanroc-Dusk seed scored 0.40 on the rig's Ceruledge panel).
  static const cnnExemplarOverride = 0.85;

  SpriteMatcher(this.pack,
      {required this.loadBytes,
      required this.exemplars,
      this.onDebug,
      this.useCnn = true});

  /// False forces the pre-classifier tiers (template/art) — kept so tests can
  /// still pin down the fallback path.
  final bool useCnn;

  SpriteCnn? _cnn;
  bool _cnnTried = false;

  Future<SpriteCnn?> _loadCnn() async {
    if (!useCnn) return null;
    if (_cnnTried) return _cnn;
    _cnnTried = true;
    return _cnn = await SpriteCnn.load(loadBytes);
  }

  /// Optional diagnostics sink; see [SpriteMatchDebug].
  final void Function(SpriteMatchDebug report)? onDebug;

  // Cache of art-reference class signatures per species.
  Map<String, List<_ClassSig>>? _artSigs;

  // Packed Champions sprite + type-badge atlas; null when the asset is absent.
  ChampionsReferenceSet? _refs;
  bool _refsTried = false;

  Future<ChampionsReferenceSet?> _loadRefs() async {
    if (_refsTried) return _refs;
    _refsTried = true;
    return _refs = await ChampionsReferenceSet.load(loadBytes);
  }

  Future<List<PanelMatch>> matchPreview(Uint8List jpegBytes,
      {int expectedPanels = 6}) async {
    _descCache.clear(); // crop descriptors from prior calls
    _tmplCache.clear();
    final raw = img.decodeImage(jpegBytes);
    if (raw == null) return const [];
    // Camera JPEGs carry their rotation in EXIF; the panel finder assumes the
    // enemy column is on the RIGHT, so the pixels must actually be upright.
    final decoded = img.bakeOrientation(raw);
    final photo = decoded.width > workWidth
        ? img.copyResize(decoded,
            width: workWidth, interpolation: img.Interpolation.linear)
        : decoded;
    final panels = _findPanels(photo, expected: expectedPanels);
    if (panels.isEmpty) return const [];
    // Panels are FOUND on the work-sized copy (cheap, and the pink mask needs
    // no detail) but sprites and badges are CROPPED from the original. Working
    // off the downscaled copy costs ~40% of the template score on a small
    // sprite and flips marginal badge reads.
    final scale = decoded.width / photo.width;

    final refs = await _loadRefs();
    final cnn = await _loadCnn();
    final artSigs =
        refs == null && cnn == null ? await _loadArtSigs() : null;
    final crops = <_Patch>[];
    final pngs = <Uint8List>[];
    final panelTypes = <Set<String>>[];
    final rects = <List<int>>[];
    final badgeBoxes = <List<List<int>>>[];
    for (final panel in panels.take(expectedPanels)) {
      final rect = _scaleRect(panel, scale, decoded.width, decoded.height);
      rects.add(rect);
      final crop = _segmentSprite(decoded, rect);
      crops.add(crop);
      pngs.add(_encodeCrop(crop));
      final boxes = <List<int>>[];
      panelTypes.add(refs == null
          ? const <String>{}
          : _readTypes(decoded, rect, refs, boxes));
      badgeBoxes.add(boxes);
    }

    // Score matrix: per panel, per species.
    final speciesIds = pack.species.keys.toList();
    final scores = <List<SpriteCandidate>>[];
    final tiers = <Map<String, String>>[]; // per panel: speciesId -> tier
    final typesOf = <String, List<String>>{
      if (refs != null)
        for (final ref in refs.sprites) ref.speciesId: ref.types,
    };
    for (var pi = 0; pi < crops.length; pi++) {
      final crop = crops[pi];
      final wantTypes = panelTypes[pi];
      final tierOf = <String, String>{};

      if (cnn != null) {
        final row = await _cnnRow(cnn, decoded, rects[pi], crop, wantTypes,
            typesOf, speciesIds, tierOf);
        scores.add(row);
        tiers.add(tierOf);
        continue;
      }

      // b) template tier: best true-sprite score per species, type-adjusted.
      final template = <String, double>{};
      if (refs != null) {
        final desc = _templateDescriptor(crop, refs.tile);
        for (final ref in refs.sprites) {
          var s = _templateScore(desc, ref, refs.tile);
          if (s <= -1) continue;
          if (wantTypes.isNotEmpty && ref.types.isNotEmpty) {
            var hit = 0;
            for (final t in wantTypes) {
              if (ref.types.contains(t)) hit++;
            }
            final agree = hit / wantTypes.length;
            s += typePriorBonus * agree - typePriorPenalty * (1 - agree);
          }
          final prev = template[ref.speciesId];
          if (prev == null || s > prev) template[ref.speciesId] = s;
        }
      }

      final classSig = artSigs == null
          ? null
          : _ClassSig.fromPatch(crop, exposureNormalize: true);
      final row = <SpriteCandidate>[];
      for (final sid in speciesIds) {
        var best = const SpriteCandidate('', -1, false);
        // a) exemplars (same-domain NCC, sharpened by the user's own photos)
        for (final ex in await exemplars._patchesFor(sid)) {
          final ncc = _maskedNcc(crop, ex);
          if (ncc > best.score) {
            best = SpriteCandidate(sid, ncc, true);
            tierOf[sid] = 'exemplar';
          }
        }
        final tmpl = template[sid];
        if (tmpl != null && tmpl > best.score) {
          best = SpriteCandidate(sid, tmpl, false);
          tierOf[sid] = 'template';
        }
        if (best.score < exemplarTrust && classSig != null) {
          // c) bundled art last resort (scaled-down confidence)
          var art = -1.0;
          for (final sig in artSigs![sid] ?? const <_ClassSig>[]) {
            art = math.max(art, classSig.similarity(sig));
          }
          final scaled = art * artConfidenceScale;
          if (scaled > best.score) {
            best = SpriteCandidate(sid, scaled, false);
            tierOf[sid] = 'art';
          }
        }
        row.add(SpriteCandidate(sid, best.score, best.fromExemplar));
      }
      row.sort((a, b) => b.score.compareTo(a.score));
      scores.add(row);
      tiers.add(tierOf);
    }

    // Unique assignment, greedy by score.
    final assigned = List<SpriteCandidate?>.filled(scores.length, null);
    final usedSpecies = <String>{};
    final all = <(int, SpriteCandidate)>[
      for (var i = 0; i < scores.length; i++)
        for (final c in scores[i]) (i, c),
    ]..sort((a, b) => b.$2.score.compareTo(a.$2.score));
    for (final (i, c) in all) {
      if (assigned[i] != null || usedSpecies.contains(c.speciesId)) continue;
      assigned[i] = c;
      usedSpecies.add(c.speciesId);
    }

    final sink = onDebug;
    if (sink != null) {
      sink(SpriteMatchDebug(
        frameWidth: decoded.width,
        frameHeight: decoded.height,
        workWidth: photo.width,
        scale: scale,
        panels: rects,
        panelTypes: panelTypes,
        ranked: [
          for (var i = 0; i < scores.length; i++)
            [
              for (final c in scores[i].take(8))
                (c.speciesId, c.score, tiers[i][c.speciesId] ?? 'none'),
            ],
        ],
        crops: pngs,
        runtimeExemplars: exemplars.runtimeCounts,
        frameJpeg: Uint8List.fromList(img.encodeJpg(decoded, quality: 85)),
        badgeBoxes: badgeBoxes,
        assigned: [
          for (var i = 0; i < scores.length; i++)
            (assigned[i] ?? scores[i].first).speciesId,
        ],
      ));
    }

    return [
      for (var i = 0; i < scores.length; i++)
        PanelMatch(
          ranked: scores[i],
          assigned: assigned[i] ?? scores[i].first,
          cropPng: pngs[i],
        ),
    ];
  }

  /// One panel scored by the classifier: softmax, badge prior as a likelihood
  /// ratio, renormalised; exemplars override only on a near-duplicate crop.
  Future<List<SpriteCandidate>> _cnnRow(
      SpriteCnn cnn,
      img.Image photo,
      List<int> rect,
      _Patch crop,
      Set<String> wantTypes,
      Map<String, List<String>> typesOf,
      List<String> speciesIds,
      Map<String, String> tierOf) async {
    final probs = cnn.probabilities(cnn.inputFor(photo, rect));
    final p = <String, double>{};
    var total = 0.0;
    for (var k = 0; k < probs.length; k++) {
      final sid = cnn.species[k];
      var s = probs[k];
      final types = typesOf[sid];
      if (wantTypes.isNotEmpty && types != null && types.isNotEmpty) {
        var hit = 0;
        for (final t in wantTypes) {
          if (types.contains(t)) hit++;
        }
        final agree = hit / wantTypes.length;
        s *= (1 + cnnTypeBoost * agree) * (1 - cnnTypeCut * (1 - agree));
      }
      p[sid] = (p[sid] ?? 0.0) + s;
      total += s;
    }
    final row = <SpriteCandidate>[];
    for (final sid in speciesIds) {
      var best = SpriteCandidate(
          sid, total > 0 ? (p[sid] ?? 0.0) / total : 0.0, false);
      tierOf[sid] = 'cnn';
      for (final ex in await exemplars._patchesFor(sid)) {
        final ncc = _maskedNcc(crop, ex);
        if (ncc >= cnnExemplarOverride && ncc > best.score) {
          best = SpriteCandidate(sid, ncc, true);
          tierOf[sid] = 'exemplar';
        }
      }
      row.add(best);
    }
    row.sort((a, b) => b.score.compareTo(a.score));
    return row;
  }

  /// Map a panel rect from the work-sized image back onto the original.
  static List<int> _scaleRect(List<int> r, double scale, int w, int h) {
    if (scale == 1.0) return r;
    final x0 = (r[0] * scale).round().clamp(0, w - 1);
    final y0 = (r[1] * scale).round().clamp(0, h - 1);
    final x1 = (r[2] * scale).round().clamp(x0 + 1, w);
    final y1 = (r[3] * scale).round().clamp(y0 + 1, h);
    return [x0, y0, x1, y1];
  }

  // ------------------------------------------------------ panel detection --

  /// Enemy-card colour test, exposure-invariant: chromaticity red-dominant
  /// with little green. Accepts the crimson-to-magenta gradient of the cards
  /// as a phone sees them AND the dark pure red the rig's OV2640 makes of
  /// them; rejects the trainer-name pill (too much green), yellow walls, the
  /// blue court, white glare and the orange Joy-Con.
  static bool _isCard(num r, num g, num b) {
    final sum = r + g + b + 1e-6;
    final rf = r / sum, gf = g / sum;
    final v = math.max(r, math.max(g, b));
    return rf >= 0.36 && gf <= 0.27 && rf >= gf + 0.15 && v >= 55;
  }

  /// Panel rects (x0, y0, x1, y1) for the enemy column, top to bottom.
  ///
  /// Rewritten 2026-09-06 after the first rig frame: the old row-profile over
  /// the old pink test found ONE band — the trainer-name pill — because the rig's
  /// OV2640 renders the crimson cards as dark pure red (R≈0.4, B≈0.05) that
  /// failed the brightness test, and a glare band wiped out the top card.
  ///
  /// Now: an exposure-invariant red/magenta chromaticity mask, row bands over
  /// the stack's own x-range, a height-consistency filter (drops the pill),
  /// then an evenly-spaced-slots model whose phase is chosen by total red
  /// mass — so a card drowned in glare is still placed, because even washed
  /// out it carries more red than the blank strip below the stack. Card
  /// height comes from the pitch, not the band: sprites, badges and glare eat
  /// rows, so bands are a card's red core, not its extent.
  List<List<int>> _findPanels(img.Image photo, {int expected = 6}) {
    final w = photo.width, h = photo.height;
    final half = w ~/ 2;
    if (w < 40 || h < 40) return const [];

    // 1. mask (right half only), then a 3x3 opening to drop speckle.
    final raw = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = half; x < w; x++) {
        final px = photo.getPixel(x, y);
        final r = px.r.toDouble(), g = px.g.toDouble(), b = px.b.toDouble();
        if (_isCard(r, g, b)) raw[y * w + x] = 1;
      }
    }
    final mask = _open3x3(raw, w, h);

    // 2. stack x-range: run of the column profile containing its peak.
    final colp = Float64List(w);
    for (var x = half; x < w; x++) {
      var c = 0;
      for (var y = 0; y < h; y++) {
        c += mask[y * w + x];
      }
      colp[x] = c / h;
    }
    final colS = _boxSmooth(colp, 9);
    var peakX = half, peak = 0.0;
    for (var x = half; x < w; x++) {
      if (colS[x] > peak) {
        peak = colS[x];
        peakX = x;
      }
    }
    if (peak <= 0) return const [];
    final xr = _runContaining(_runs(colS, 0.15 * peak), peakX);
    if (xr == null) return const [];
    final sx0 = xr[0], sx1 = xr[1];
    if (sx1 - sx0 < w * 0.04) return const [];

    // 3. row bands over the stack.
    final rowp = Float64List(h);
    for (var y = 0; y < h; y++) {
      var c = 0;
      for (var x = sx0; x < sx1; x++) {
        c += mask[y * w + x];
      }
      rowp[y] = c / (sx1 - sx0);
    }
    final rowS = _boxSmooth(rowp, 5);
    final hi = _percentile(rowS, 0.90), lo = _percentile(rowS, 0.20);
    var bands = _runs(rowS, lo + 0.40 * (hi - lo))
        .where((b) => b[1] - b[0] >= 0.02 * h)
        .toList();
    if (bands.isEmpty) return const [];

    // 4. consistent heights only (the trainer-name pill is half a card).
    final heights = [for (final b in bands) (b[1] - b[0]).toDouble()];
    final medH = _median(heights);
    bands = [
      for (final b in bands)
        if (b[1] - b[0] >= 0.6 * medH && b[1] - b[0] <= 1.5 * medH) b,
    ];
    if (bands.isEmpty) return const [];
    if (bands.length < 2) {
      return [
        for (final b in bands) [sx0, b[0], sx1, b[1]],
      ];
    }

    // 5. evenly spaced slots. A sprite bright enough to break the card mask
    //    splits that card into FRAGMENTS, and a fragment that survives the
    //    height filter must set neither the pitch, the card height, nor the
    //    phase: the whole model hangs off one anchor centre, so a half-card
    //    anchor slides all six slots at once (rig frame 2026-09-17 — every
    //    panel 28 px off its card, and one card cropped to 74 px of its 110).
    //    Take all three from FULL bands only, the phase as a median residual
    //    so no single band can move it.
    final keptH = [for (final b in bands) (b[1] - b[0]).toDouble()];
    final cardH = _median(keptH);
    // TWO-sided: a band merged with its neighbour is as misleading an anchor
    // as a fragment, and the 1.5x arm of the height filter above lets one
    // through — at the 1200 px detect scale the trainer-name pill fuses with
    // card 1, and snapping to that merged band put panel 1 twenty-four px
    // above its card on the 2026-09-17 rig frames.
    var full = [
      for (final b in bands)
        if (b[1] - b[0] >= 0.8 * cardH && b[1] - b[0] <= 1.15 * cardH) b,
    ];
    if (full.length < 2) full = bands;
    final centers = [for (final b in full) (b[0] + b[1]) / 2.0];
    final gaps = [
      for (var i = 1; i < centers.length; i++) centers[i] - centers[i - 1],
    ];
    final minGap = gaps.reduce(math.min);
    final pitch = _median([for (final g in gaps) if (g < 1.6 * minGap) g]);
    if (pitch <= 0) return const [];
    // Card height: the median FULL band, not a fixed fraction of the pitch —
    // 0.90 x pitch over-crops a short card with wide gaps (the synthetic test
    // screen) and under-crops nothing.
    final ph = math.min(0.95 * pitch,
        _median([for (final b in full) (b[1] - b[0]).toDouble()]));
    final phase = _median([
      for (final c in centers)
        c - ((c - centers[0]) / pitch).roundToDouble() * pitch,
    ]);
    var maxIdx = 0;
    for (final c in centers) {
      maxIdx = math.max(maxIdx, ((c - phase) / pitch).round());
    }
    double mass(double c) {
      final y0 = math.max(0, (c - ph / 2).floor());
      final y1 = math.min(h, (c + ph / 2).floor());
      var m = 0.0;
      for (var y = y0; y < y1; y++) {
        m += rowS[y];
      }
      return m;
    }

    final loS = math.min(0, maxIdx - expected + 1) - 1;
    final hiS = math.max(0, maxIdx - expected + 1) + 1;
    List<double>? bestSlots;
    var bestMass = -1.0;
    for (var start = loS; start <= hiS; start++) {
      final slots = [
        for (var k = 0; k < expected; k++) phase + pitch * (start + k),
      ];
      if (slots.first < 0.35 * pitch || slots.last > h - 0.35 * pitch) {
        continue;
      }
      var m = 0.0;
      for (final c in slots) {
        m += mass(c);
      }
      if (m > bestMass) {
        bestMass = m;
        bestSlots = slots;
      }
    }
    if (bestSlots == null) return const [];

    // 6. rows per slot, then one
    //    x-range for the stack from the median of per-card extents — glare
    //    or a dark sprite can shrink a single card's extent, and the fisheye
    //    tilt across the stack is a few percent of the card width.
    final cx = (sx0 + sx1) ~/ 2;
    final rows = <List<int>>[];
    final xs0 = <double>[], xs1 = <double>[];
    for (final c in bestSlots) {
      // No snapping onto bands. The phase is already a median fit over whole
      // cards and lands within ~2 px; every misplaced panel across both rig
      // frames came from a slot snapping onto a band that was not a card —
      // a sprite-broken fragment, or a card fused with the trainer pill.
      final y0 = math.max(0, (c - ph / 2).round());
      final y1 = math.min(h, (c + ph / 2).round());
      if (y1 - y0 < 0.5 * ph) continue;
      final cp = Float64List(w);
      for (var x = half; x < w; x++) {
        var k = 0;
        for (var y = y0; y < y1; y++) {
          k += mask[y * w + x];
        }
        cp[x] = k / (y1 - y0);
      }
      final xr2 = _runContaining(_runs(cp, 0.12), cx);
      if (xr2 != null && xr2[1] - xr2[0] >= 0.6 * (sx1 - sx0)) {
        xs0.add(xr2[0].toDouble());
        xs1.add(xr2[1].toDouble());
      }
      rows.add([y0, y1]);
    }
    final x0 = xs0.isEmpty ? sx0 : _median(xs0).round();
    final x1 = xs1.isEmpty ? sx1 : _median(xs1).round();
    return [
      for (final r in rows) [x0, r[0], x1, r[1]],
    ];
  }

  /// 3x3 morphological opening on a 0/1 byte grid.
  static Uint8List _open3x3(Uint8List m, int w, int h) {
    final er = Uint8List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        if (m[y * w + x] == 0) continue;
        var all = true;
        for (var dy = -1; dy <= 1 && all; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (m[(y + dy) * w + x + dx] == 0) {
              all = false;
              break;
            }
          }
        }
        if (all) er[y * w + x] = 1;
      }
    }
    final out = Uint8List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        if (er[y * w + x] == 0) continue;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            out[(y + dy) * w + x + dx] = 1;
          }
        }
      }
    }
    return out;
  }

  static Float64List _boxSmooth(Float64List v, int k) {
    final n = v.length, half = k ~/ 2;
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      var s = 0.0, c = 0;
      for (var j = i - half; j <= i + half; j++) {
        if (j < 0 || j >= n) continue;
        s += v[j];
        c++;
      }
      out[i] = c == 0 ? 0 : s / c;
    }
    return out;
  }

  /// Contiguous index ranges [start, end) where v > thr.
  static List<List<int>> _runs(Float64List v, double thr) {
    final out = <List<int>>[];
    var s = -1;
    for (var i = 0; i < v.length; i++) {
      if (v[i] > thr) {
        if (s < 0) s = i;
      } else if (s >= 0) {
        out.add([s, i]);
        s = -1;
      }
    }
    if (s >= 0) out.add([s, v.length]);
    return out;
  }

  static List<int>? _runContaining(List<List<int>> rs, int i) {
    for (final r in rs) {
      if (r[0] <= i && i < r[1]) return r;
    }
    if (rs.isEmpty) return null;
    var best = rs.first;
    for (final r in rs) {
      if (r[1] - r[0] > best[1] - best[0]) best = r;
    }
    return best;
  }

  static double _percentile(Float64List v, double f) {
    final s = Float64List.fromList(v)..sort();
    return s[(s.length * f).floor().clamp(0, s.length - 1)];
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = List<double>.from(v)..sort();
    return s[s.length ~/ 2];
  }

  // -------------------------------------------------------- segmentation --

  /// Sprite sub-region of a panel: x in [0.14, 0.62] of panel width, with a
  /// [panelVerticalInset] slice dropped top and bottom (edge-glow noise).
  _Patch _segmentSprite(img.Image photo, List<int> panel) {
    final px0 = panel[0], px1 = panel[2];
    final ph = panel[3] - panel[1];
    final dy = (ph * panelVerticalInset).round();
    final py0 = panel[1] + dy, py1 = panel[3] - dy;
    final pw = px1 - px0;
    final x0 = px0 + (pw * 0.14).round();
    final x1 = px0 + (pw * 0.62).round();
    final cw = x1 - x0, ch = py1 - py0;
    final crop = _Patch(cw, ch);
    var i = 0;
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++, i++) {
        final px = photo.getPixel(x0 + x, py0 + y);
        crop.r[i] = px.r / 255.0;
        crop.g[i] = px.g / 255.0;
        crop.b[i] = px.b / 255.0;
      }
    }
    // Background color = median of the 2px border, preferring border pixels
    // that are card-coloured: if the rect overshoots the card, arena pixels
    // otherwise win the median and the whole card becomes "foreground".
    final borderR = <double>[], borderG = <double>[], borderB = <double>[];
    final cardR = <double>[], cardG = <double>[], cardB = <double>[];
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        if (y < 2 || y >= ch - 2 || x < 2 || x >= cw - 2) {
          final j = y * cw + x;
          borderR.add(crop.r[j]);
          borderG.add(crop.g[j]);
          borderB.add(crop.b[j]);
          if (_isCard(crop.r[j] * 255, crop.g[j] * 255, crop.b[j] * 255)) {
            cardR.add(crop.r[j]);
            cardG.add(crop.g[j]);
            cardB.add(crop.b[j]);
          }
        }
      }
    }
    double median(List<double> v) {
      v.sort();
      return v.isEmpty ? 0 : v[v.length ~/ 2];
    }

    final useCard = cardR.length >= 16;
    final bgR = median(useCard ? cardR : borderR);
    final bgG = median(useCard ? cardG : borderG);
    final bgB = median(useCard ? cardB : borderB);
    // Soft foreground weights.
    for (var j = 0; j < cw * ch; j++) {
      final dr = crop.r[j] - bgR, dg = crop.g[j] - bgG, db = crop.b[j] - bgB;
      final dist = math.sqrt(dr * dr + dg * dg + db * db);
      crop.a[j] = ((dist - fgThresholdLow) / fgThresholdSpan).clamp(0.0, 1.0);
    }
    _keepMainBlob(crop);
    return _tighten(crop);
  }

  /// Zero out weights not connected (or adjacent) to the largest blob.
  void _keepMainBlob(_Patch p) {
    final n = p.w * p.h;
    final labels = Int32List(n); // 0 = unlabeled
    var next = 0;
    final sizes = <int, int>{};
    final stack = <int>[];
    for (var start = 0; start < n; start++) {
      if (labels[start] != 0 || p.a[start] < fgHardMask) continue;
      next++;
      labels[start] = next;
      stack.add(start);
      var size = 0;
      while (stack.isNotEmpty) {
        final j = stack.removeLast();
        size++;
        final x = j % p.w, y = j ~/ p.w;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= p.w || ny >= p.h) continue;
          final k = ny * p.w + nx;
          if (labels[k] == 0 && p.a[k] >= fgHardMask) {
            labels[k] = next;
            stack.add(k);
          }
        }
      }
      sizes[next] = size;
    }
    if (sizes.isEmpty) return;
    final biggest =
        sizes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    // Blob bbox
    var by0 = p.h, by1 = 0, bx0 = p.w, bx1 = 0;
    for (var j = 0; j < n; j++) {
      if (labels[j] == biggest) {
        final x = j % p.w, y = j ~/ p.w;
        by0 = math.min(by0, y);
        by1 = math.max(by1, y);
        bx0 = math.min(bx0, x);
        bx1 = math.max(bx1, x);
      }
    }
    final padX = p.w * 0.10, padY = p.h * 0.10;
    // Per-label bbox for adjacency test.
    final keep = <int>{biggest};
    final lb = <int, List<int>>{};
    for (var j = 0; j < n; j++) {
      final l = labels[j];
      if (l == 0 || l == biggest) continue;
      final x = j % p.w, y = j ~/ p.w;
      final box = lb.putIfAbsent(l, () => [x, y, x, y]);
      box[0] = math.min(box[0], x);
      box[1] = math.min(box[1], y);
      box[2] = math.max(box[2], x);
      box[3] = math.max(box[3], y);
    }
    lb.forEach((l, box) {
      final sz = sizes[l] ?? 0;
      if (sz < math.max(12, (sizes[biggest] ?? 0) * 0.06)) return;
      final farAway = box[1] > by1 + padY ||
          box[3] < by0 - padY ||
          box[0] > bx1 + padX ||
          box[2] < bx0 - padX;
      if (!farAway) keep.add(l);
    });
    for (var j = 0; j < n; j++) {
      if (p.a[j] >= fgHardMask && !keep.contains(labels[j])) p.a[j] = 0.0;
      if (labels[j] == 0 && p.a[j] >= fgHardMask) p.a[j] = 0.0;
    }
  }

  /// Crop to the weighted bounding box.
  _Patch _tighten(_Patch p) {
    var y0 = p.h, y1 = -1, x0 = p.w, x1 = -1;
    for (var j = 0; j < p.w * p.h; j++) {
      if (p.a[j] > fgHardMask) {
        final x = j % p.w, y = j ~/ p.w;
        y0 = math.min(y0, y);
        y1 = math.max(y1, y);
        x0 = math.min(x0, x);
        x1 = math.max(x1, x);
      }
    }
    if (y1 < 0 || y1 - y0 < 3 || x1 - x0 < 3) return p;
    final out = _Patch(x1 - x0 + 1, y1 - y0 + 1);
    var i = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++, i++) {
        final j = y * p.w + x;
        out.r[i] = p.r[j];
        out.g[i] = p.g[j];
        out.b[i] = p.b[j];
        out.a[i] = p.a[j];
      }
    }
    return out;
  }

  Uint8List _encodeCrop(_Patch p) {
    final im = img.Image(width: p.w, height: p.h, numChannels: 4);
    var i = 0;
    for (var y = 0; y < p.h; y++) {
      for (var x = 0; x < p.w; x++, i++) {
        im.setPixelRgba(x, y, (p.r[i] * 255).round(), (p.g[i] * 255).round(),
            (p.b[i] * 255).round(), (p.a[i] * 255).round());
      }
    }
    return Uint8List.fromList(img.encodePng(im));
  }

  // ------------------------------------------------------- exemplar match --

  /// Pad-to-square + resize both patches to [descriptorSize], then masked
  /// per-channel NCC with the joint weight mask.
  double _maskedNcc(_Patch a, _Patch b) {
    final da = _descriptor(a), db = _descriptor(b);
    final n = descriptorSize * descriptorSize;
    final w = Float64List(n);
    var wsum = 0.0;
    for (var j = 0; j < n; j++) {
      w[j] = da.a[j] * db.a[j];
      wsum += w[j];
    }
    if (wsum < 4) return -1;
    var totalCorr = 0.0;
    for (final (ca, cb) in [(da.r, db.r), (da.g, db.g), (da.b, db.b)]) {
      var ma = 0.0, mb = 0.0;
      for (var j = 0; j < n; j++) {
        ma += ca[j] * w[j];
        mb += cb[j] * w[j];
      }
      ma /= wsum;
      mb /= wsum;
      var num = 0.0, da2 = 0.0, db2 = 0.0;
      for (var j = 0; j < n; j++) {
        final xa = (ca[j] - ma) * math.sqrt(w[j]);
        final xb = (cb[j] - mb) * math.sqrt(w[j]);
        num += xa * xb;
        da2 += xa * xa;
        db2 += xb * xb;
      }
      final den = math.sqrt(da2 * db2);
      if (den > 1e-9) totalCorr += num / den;
    }
    return totalCorr / 3;
  }

  final Map<_Patch, _Patch> _descCache = {};
  final Map<_Patch, _Patch> _tmplCache = {};

  _Patch _descriptor(_Patch p) =>
      _descCache[p] ??= _resizeSquare(p, descriptorSize);

  /// Crop descriptor at the atlas tile size, so a segmented panel crop and a
  /// packed reference tile are directly comparable. Cached separately from
  /// [_descriptor] so the exemplar tier keeps its own tuned resolution.
  _Patch _templateDescriptor(_Patch p, int n) =>
      _tmplCache[p] ??= _resizeSquare(p, n);

  _Patch _resizeSquare(_Patch p, int n) {
    final s = math.max(p.w, p.h);
    final sq = img.Image(width: s, height: s, numChannels: 4);
    final ox = (s - p.w) ~/ 2, oy = (s - p.h) ~/ 2;
    var i = 0;
    for (var y = 0; y < p.h; y++) {
      for (var x = 0; x < p.w; x++, i++) {
        sq.setPixelRgba(ox + x, oy + y, (p.r[i] * 255).round(),
            (p.g[i] * 255).round(), (p.b[i] * 255).round(),
            (p.a[i] * 255).round());
      }
    }
    final small = img.copyResize(sq,
        width: n, height: n, interpolation: img.Interpolation.linear);
    return _Patch.fromImage(small, alphaWeights: true);
  }

  // ------------------------------------------------------- template match --

  /// Masked per-channel NCC between a crop descriptor and a packed reference
  /// tile, blended with mask agreement (how much of the union of the two
  /// silhouettes they share). Mirrors `_verification/recognition_prototype.py`.
  double _templateScore(_Patch cropDesc, ChampionsRef ref, int n) {
    if (cropDesc.w != n || cropDesc.h != n || ref.size != n) return -1;
    final count = n * n;
    final w = Float64List(count);
    var wsum = 0.0, union = 0.0;
    for (var j = 0; j < count; j++) {
      final aa = cropDesc.a[j], ab = ref.a[j];
      w[j] = aa * ab;
      wsum += w[j];
      union += aa > ab ? aa : ab;
    }
    if (wsum < 4) return -1;
    var totalCorr = 0.0;
    final pairs = <(Float64List, Float64List)>[
      (cropDesc.r, ref.r),
      (cropDesc.g, ref.g),
      (cropDesc.b, ref.b),
    ];
    for (final (ca, cb) in pairs) {
      var ma = 0.0, mb = 0.0;
      for (var j = 0; j < count; j++) {
        ma += ca[j] * w[j];
        mb += cb[j] * w[j];
      }
      ma /= wsum;
      mb /= wsum;
      // Weighted covariance directly: sum(w*dx*dy) == sum((sqrt(w)*dx) *
      // (sqrt(w)*dy)), so the per-pixel sqrt the exemplar path uses is pure
      // overhead here — and this loop runs 235 x 6 times per scan.
      var acc = 0.0, va = 0.0, vb = 0.0;
      for (var j = 0; j < count; j++) {
        final wj = w[j];
        if (wj == 0) continue;
        final xa = ca[j] - ma;
        final xb = cb[j] - mb;
        acc += wj * xa * xb;
        va += wj * xa * xa;
        vb += wj * xb * xb;
      }
      final den = math.sqrt(va * vb);
      if (den > 1e-9) totalCorr += acc / den;
    }
    final shape = union > 0 ? wsum / union : 0.0;
    return templateCorrWeight * (totalCorr / 3) +
        (1 - templateCorrWeight) * shape;
  }

  // ---------------------------------------------------------- type badges --

  /// Panel background colour in 0-255 space: the median of the pixels that
  /// pass the pink test. Sampled on a 2px lattice — the panel carries a
  /// top-to-bottom gradient but is flat enough within one card.
  List<double> _panelBackground(img.Image photo, List<int> panel) {
    final rs = <double>[], gs = <double>[], bs = <double>[];
    for (var y = panel[1]; y < panel[3]; y += 2) {
      for (var x = panel[0]; x < panel[2]; x += 2) {
        final px = photo.getPixel(x, y);
        if (_isCard(px.r, px.g, px.b)) {
          rs.add(px.r.toDouble());
          gs.add(px.g.toDouble());
          bs.add(px.b.toDouble());
        }
      }
    }
    if (rs.isEmpty) return const [150.0, 50.0, 80.0];
    double med(List<double> v) {
      v.sort();
      return v[v.length ~/ 2];
    }

    return [med(rs), med(gs), med(bs)];
  }

  /// The 1-2 types shown as badges in a panel's top-right corner. Empty when
  /// nothing legible is there — callers treat that as "no prior", never as
  /// "typeless".
  Set<String> _readTypes(img.Image photo, List<int> panel,
      ChampionsReferenceSet refs, [List<List<int>>? boxesOut]) {
    if (!refs.hasBadges) return const <String>{};
    final pw = panel[2] - panel[0], ph = panel[3] - panel[1];
    if (pw < 40 || ph < 20) return const <String>{};
    final bg = _panelBackground(photo, panel);
    final y0 = panel[1] + (ph * badgeTopFrac).round();
    final y1 = panel[1] + (ph * badgeBottomFrac).round();
    final out = <String>{};
    for (final slot in badgeSlots) {
      final x0 = panel[0] + (pw * slot[0]).round();
      final x1 = panel[0] + (pw * slot[1]).round();
      final t = refs.readBadge(photo, x0, y0, x1, y1, bg[0], bg[1], bg[2]);
      if (t != null) out.add(t);
      boxesOut?.add([x0, y0, x1, y1, t != null ? 1 : 0]);
    }
    if (out.isEmpty) {
      // The game centres a SINGLE badge between the two slots, so each fixed
      // slot sees half of it and neither half survives the margin gate (a
      // Raichu card read no type at all, 2026-09-14). Find the badge squares
      // themselves across the whole badge area instead.
      final ax0 = panel[0] + (pw * badgeSlots.first[0]).round();
      final ax1 = panel[0] + (pw * badgeSlots.last[1]).round();
      boxesOut?.clear();
      for (final b
          in refs.badgeBoxes(photo, ax0, y0, ax1, y1, bg[0], bg[1], bg[2])) {
        final t =
            refs.readBadge(photo, b[0], b[1], b[2], b[3], bg[0], bg[1], bg[2]);
        if (t != null) out.add(t);
        boxesOut?.add([b[0], b[1], b[2], b[3], t != null ? 1 : 0]);
      }
    }
    return out;
  }

  // ------------------------------------------------------------ art refs --

  Future<Map<String, List<_ClassSig>>> _loadArtSigs() async {
    if (_artSigs != null) return _artSigs!;
    final sigs = <String, List<_ClassSig>>{};
    for (final sid in pack.species.keys) {
      final list = <_ClassSig>[];
      for (final path in [
        'assets/sprites/home/$sid.png',
        'assets/sprites/icons/$sid.png',
        'assets/sprites/$sid.png',
      ]) {
        final bytes = await loadBytes(path);
        if (bytes == null) continue;
        final im = img.decodeImage(bytes);
        if (im == null) continue;
        final p = _Patch.fromImage(im, alphaWeights: true);
        list.add(_ClassSig.fromPatch(_tightenStatic(p),
            exposureNormalize: false));
      }
      sigs[sid] = list;
    }
    return _artSigs = sigs;
  }

  static _Patch _tightenStatic(_Patch p) {
    var y0 = p.h, y1 = -1, x0 = p.w, x1 = -1;
    for (var j = 0; j < p.w * p.h; j++) {
      if (p.a[j] > 0.3) {
        final x = j % p.w, y = j ~/ p.w;
        y0 = math.min(y0, y);
        y1 = math.max(y1, y);
        x0 = math.min(x0, x);
        x1 = math.max(x1, x);
      }
    }
    if (y1 < 0 || y1 - y0 < 3 || x1 - x0 < 3) return p;
    final out = _Patch(x1 - x0 + 1, y1 - y0 + 1);
    var i = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++, i++) {
        final j = y * p.w + x;
        out.r[i] = p.r[j];
        out.g[i] = p.g[j];
        out.b[i] = p.b[j];
        out.a[i] = p.a[j];
      }
    }
    return out;
  }

  /// Decode a saved exemplar PNG into a patch (alpha channel = weights).
  static _Patch? _decodeExemplar(Uint8List png) {
    final im = img.decodeImage(png);
    if (im == null) return null;
    return _Patch.fromImage(im, alphaWeights: true);
  }
}

/// Exemplar library: bundled seed sprites (assets/exemplars/{id}.png,
/// segmented from real Champions photos) plus everything the user's own
/// confirmations have added at runtime via [add].
class ExemplarStore {
  final ByteLoader loadBundled;

  /// Persisted user exemplars: speciesId -> list of PNG bytes. The app wires
  /// this to files under its documents directory; tests use a map.
  final Map<String, List<Uint8List>> _runtime = {};
  final Map<String, List<_Patch>> _cache = {};

  /// Called after [add] so the host can persist the new exemplar.
  void Function(String speciesId, Uint8List png)? onAdded;

  /// Called after [clearRuntime] so the host can delete the persisted copies.
  void Function()? onCleared;

  /// Number of user-confirmed exemplars per species (bundled seeds excluded).
  Map<String, int> get runtimeCounts => {
        for (final e in _runtime.entries)
          if (e.value.isNotEmpty) e.key: e.value.length,
      };

  int get runtimeTotal =>
      _runtime.values.fold(0, (sum, list) => sum + list.length);

  /// Forget everything the user has confirmed. The bundled seeds and the
  /// Champions template atlas are untouched, so recognition falls back to its
  /// cold-start behaviour — which is the point when a run of wrong
  /// confirmations has taught it nonsense.
  void clearRuntime() {
    _runtime.clear();
    _cache.clear();
    onCleared?.call();
  }

  static const maxPerSpecies = 4;

  ExemplarStore({required this.loadBundled});

  /// Preload previously persisted exemplars (call at startup).
  void seedRuntime(String speciesId, List<Uint8List> pngs) {
    _runtime[speciesId] = List.of(pngs.take(maxPerSpecies));
    _cache.remove(speciesId);
  }

  /// Store the segmented crop of a user-confirmed slot.
  void add(String speciesId, Uint8List png) {
    final list = _runtime.putIfAbsent(speciesId, () => []);
    list.add(png);
    while (list.length > maxPerSpecies) {
      list.removeAt(0);
    }
    _cache.remove(speciesId);
    onAdded?.call(speciesId, png);
  }

  Future<List<_Patch>> _patchesFor(String speciesId) async {
    final cached = _cache[speciesId];
    if (cached != null) return cached;
    final out = <_Patch>[];
    final bundled = await loadBundled('assets/exemplars/$speciesId.png');
    if (bundled != null) {
      final p = SpriteMatcher._decodeExemplar(bundled);
      if (p != null) out.add(p);
    }
    for (final png in _runtime[speciesId] ?? const <Uint8List>[]) {
      final p = SpriteMatcher._decodeExemplar(png);
      if (p != null) out.add(p);
    }
    return _cache[speciesId] = out;
  }
}

// ---------------------------------------------------------------------------
// Semantic color-class signature (cast-tolerant art matching).
// ---------------------------------------------------------------------------

class _ClassSig {
  static const numClasses = 11;
  // black, dkgray, white, red, orange, yellow, green, cyan, blue, purple, pink
  final Float64List full;
  final List<Float64List> bands; // top/middle/bottom thirds

  _ClassSig(this.full, this.bands);

  static int _classify(double r, double g, double b) {
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    final d = mx - mn;
    final v = mx;
    final s = mx > 0 ? d / mx : 0.0;
    if (v < 0.24) return 0; // black
    if (s < 0.26) return v < 0.62 ? 1 : 2; // dkgray / white
    double h;
    if (d <= 0) {
      h = 0;
    } else if (mx == r) {
      h = (60 * ((g - b) / d)) % 360;
    } else if (mx == g) {
      h = 60 * ((b - r) / d) + 120;
    } else {
      h = 60 * ((r - g) / d) + 240;
    }
    if (h < 0) h += 360;
    if (h < 15 || h >= 345) return 3; // red
    if (h < 45) return 4; // orange
    if (h < 70) return 5; // yellow
    if (h < 165) return 6; // green
    if (h < 200) return 7; // cyan
    if (h < 255) return 8; // blue
    if (h < 290) return 9; // purple
    return 10; // pink/magenta
  }

  static _ClassSig fromPatch(_Patch p, {required bool exposureNormalize}) {
    var scale = 1.0;
    if (exposureNormalize) {
      // 95th percentile of foreground brightness -> 0.92
      final vs = <double>[];
      for (var j = 0; j < p.w * p.h; j++) {
        if (p.a[j] > 0.35) {
          vs.add(math.max(p.r[j], math.max(p.g[j], p.b[j])));
        }
      }
      if (vs.length > 10) {
        vs.sort();
        final hi = vs[(vs.length * 0.95).floor().clamp(0, vs.length - 1)];
        scale = 0.92 / math.max(hi, 0.15);
      }
    }
    final full = Float64List(numClasses);
    final bands = [
      Float64List(numClasses),
      Float64List(numClasses),
      Float64List(numClasses)
    ];
    for (var j = 0; j < p.w * p.h; j++) {
      final w = p.a[j];
      if (w <= 0) continue;
      final c = _classify((p.r[j] * scale).clamp(0.0, 1.0),
          (p.g[j] * scale).clamp(0.0, 1.0), (p.b[j] * scale).clamp(0.0, 1.0));
      full[c] += w;
      final y = j ~/ p.w;
      bands[math.min(2, y * 3 ~/ math.max(1, p.h))][c] += w;
    }
    void norm(Float64List h) {
      var s = 0.0;
      for (final v in h) {
        s += v;
      }
      if (s > 0) {
        for (var i = 0; i < h.length; i++) {
          h[i] /= s;
        }
      }
    }

    norm(full);
    bands.forEach(norm);
    return _ClassSig(full, bands);
  }

  /// Histogram-intersection similarity; band-weighted (wb = 0.7 from the
  /// prototype sweep).
  double similarity(_ClassSig other, {double wb = 0.7}) {
    double inter(Float64List a, Float64List b) {
      var s = 0.0;
      for (var i = 0; i < a.length; i++) {
        s += math.min(a[i], b[i]);
      }
      return s;
    }

    final f = inter(full, other.full);
    var b = 0.0;
    for (var i = 0; i < 3; i++) {
      b += inter(bands[i], other.bands[i]);
    }
    b /= 3;
    return (1 - wb) * f + wb * b;
  }
}
