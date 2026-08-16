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
///  3. Score each pack species against the segmented sprite:
///       a. EXEMPLAR match — masked per-channel NCC against sprites the app
///          previously segmented from the user's own confirmed photos (plus
///          bundled seeds). Same-domain, so this is the reliable signal.
///       b. ART match (cold-start fallback) — semantic color-class histogram
///          (cast-tolerant) against bundled HOME/icon/front sprites. Weaker;
///          its confidence is capped so the UI asks for confirmation.
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

  SpriteMatcher(this.pack, {required this.loadBytes, required this.exemplars});

  // Cache of art-reference class signatures per species.
  Map<String, List<_ClassSig>>? _artSigs;

  Future<List<PanelMatch>> matchPreview(Uint8List jpegBytes,
      {int expectedPanels = 6}) async {
    _descCache.clear(); // crop descriptors from prior calls
    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) return const [];
    final photo = decoded.width > workWidth
        ? img.copyResize(decoded,
            width: workWidth, interpolation: img.Interpolation.linear)
        : decoded;
    final panels = _findPanels(photo);
    if (panels.isEmpty) return const [];

    final artSigs = await _loadArtSigs();
    final crops = <_Patch>[];
    final pngs = <Uint8List>[];
    for (final panel in panels.take(expectedPanels)) {
      final crop = _segmentSprite(photo, panel);
      crops.add(crop);
      pngs.add(_encodeCrop(crop));
    }

    // Score matrix: per panel, per species.
    final speciesIds = pack.species.keys.toList();
    final scores = <List<SpriteCandidate>>[];
    for (final crop in crops) {
      final classSig = _ClassSig.fromPatch(crop, exposureNormalize: true);
      final row = <SpriteCandidate>[];
      for (final sid in speciesIds) {
        var best = const SpriteCandidate('', -1, false);
        // a) exemplars (same-domain NCC)
        for (final ex in await exemplars._patchesFor(sid)) {
          final ncc = _maskedNcc(crop, ex);
          if (ncc > best.score) best = SpriteCandidate(sid, ncc, true);
        }
        if (best.score < exemplarTrust) {
          // b) bundled art fallback (scaled-down confidence)
          var art = -1.0;
          for (final sig in artSigs[sid] ?? const <_ClassSig>[]) {
            art = math.max(art, classSig.similarity(sig));
          }
          final scaled = art * artConfidenceScale;
          if (scaled > best.score) best = SpriteCandidate(sid, scaled, false);
        }
        row.add(SpriteCandidate(sid, best.score, best.fromExemplar));
      }
      row.sort((a, b) => b.score.compareTo(a.score));
      scores.add(row);
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

    return [
      for (var i = 0; i < scores.length; i++)
        PanelMatch(
          ranked: scores[i],
          assigned: assigned[i] ?? scores[i].first,
          cropPng: pngs[i],
        ),
    ];
  }

  // ------------------------------------------------------ panel detection --

  static bool _isPink(num r, num g, num b) {
    final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final mx = math.max(rf, math.max(gf, bf));
    final mn = math.min(rf, math.min(gf, bf));
    final sat = mx > 0 ? (mx - mn) / mx : 0.0;
    return rf > 0.45 && sat > 0.30 && (rf - gf) > 0.18 && bf > gf - 0.05;
  }

  /// Panel rects (x0, y0, x1, y1) for the enemy column, top to bottom.
  List<List<int>> _findPanels(img.Image photo) {
    final w = photo.width, h = photo.height;
    final half = w ~/ 2;
    final mask = List.generate(h, (_) => List.filled(w, false));
    var total = 0;
    for (var y = 0; y < h; y++) {
      for (var x = half; x < w; x++) {
        final px = photo.getPixel(x, y);
        if (_isPink(px.r, px.g, px.b)) {
          mask[y][x] = true;
          total++;
        }
      }
    }
    if (total == 0) return const [];
    final rows = [for (var y = 0; y < h; y++) mask[y].where((v) => v).length];
    final threshold = (total / h) * 0.6;
    final bands = <List<int>>[];
    var y = 0;
    while (y < h) {
      if (rows[y] > threshold) {
        final y0 = y;
        while (y < h && rows[y] > threshold) {
          y++;
        }
        bands.add([y0, y]);
      } else {
        y++;
      }
    }
    final panels = <List<int>>[];
    for (final band in bands) {
      final y0 = band[0], y1 = band[1];
      if (y1 - y0 < h * 0.02) continue;
      // column extent
      var x0 = -1, x1 = -1;
      for (var x = half; x < w; x++) {
        var count = 0;
        for (var yy = y0; yy < y1; yy++) {
          if (mask[yy][x]) count++;
        }
        if (count > (y1 - y0) * 0.5) {
          if (x0 < 0) x0 = x;
          x1 = x;
        }
      }
      if (x0 < 0 || (x1 - x0) < w * 0.05) continue;
      panels.add([x0, y0, x1, y1]);
    }
    panels.sort((a, b) => (b[3] - b[1]).compareTo(a[3] - a[1]));
    final top = panels.take(6).toList()..sort((a, b) => a[1].compareTo(b[1]));
    return top;
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
    // Background color = median of 2px border.
    final borderR = <double>[], borderG = <double>[], borderB = <double>[];
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        if (y < 2 || y >= ch - 2 || x < 2 || x >= cw - 2) {
          final j = y * cw + x;
          borderR.add(crop.r[j]);
          borderG.add(crop.g[j]);
          borderB.add(crop.b[j]);
        }
      }
    }
    double median(List<double> v) {
      v.sort();
      return v.isEmpty ? 0 : v[v.length ~/ 2];
    }

    final bgR = median(borderR), bgG = median(borderG), bgB = median(borderB);
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

  _Patch _descriptor(_Patch p) {
    final cached = _descCache[p];
    if (cached != null) return cached;
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
        width: descriptorSize,
        height: descriptorSize,
        interpolation: img.Interpolation.linear);
    final d = _Patch.fromImage(small, alphaWeights: true);
    _descCache[p] = d;
    return d;
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
