/// The packed Champions reference atlas — every species' **real** in-game 2D
/// sprite, plus the 18 type badges, as pre-computed descriptor tiles.
///
/// Why an atlas instead of 235 loose PNGs: each tile is already square-padded
/// and resized to [tile]x[tile] with its alpha mask baked in, so a match costs
/// no decode and no resample. One image decode on first use, then arithmetic.
///
/// Provenance: the four `RegulationMBPokemon*.png` captures of the in-game
/// "Eligible Pokemon" list (National Dex order), segmented off the tile
/// background. Regenerate with `tool/build_champions_atlas.py`.
///
/// This is the *cold-start* reference tier. It is same-domain — the identical
/// artwork the game draws — unlike the old bundled HOME renders, which are a
/// different artist's 3D model of the same creature and could only ever be
/// compared by colour histogram.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef AtlasByteLoader = Future<Uint8List?> Function(String path);

/// One reference sprite, already in descriptor form (square, [size] px,
/// alpha = foreground weight).
class ChampionsRef {
  /// Unique per form: `venusaur`, `rotom-heat`, `lycanroc-dusk`.
  final String formId;

  /// The data-pack species this reports as. Since 2026-09-06 every form the
  /// game lists separately is its own pack species too, so this equals
  /// [formId]; the two are kept distinct so a future collapse (or split)
  /// only has to touch the index.
  final String speciesId;

  final String displayName;

  /// The form's real types (Heat Rotom is Electric/Fire). Drives the
  /// type-badge prior.
  final List<String> types;

  final int size;
  final Float64List r, g, b, a;

  ChampionsRef({
    required this.formId,
    required this.speciesId,
    required this.displayName,
    required this.types,
    required this.size,
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });
}

/// A type badge reduced to what survives a phone camera: the body's
/// chromaticity (exposure-invariant) and the white glyph's silhouette.
class _BadgeSig {
  final String type;
  final double cr, cg;
  final Float64List glyph;
  const _BadgeSig(this.type, this.cr, this.cg, this.glyph);
}

class _BadgeFeat {
  final double cr, cg;
  final Float64List glyph;
  const _BadgeFeat(this.cr, this.cg, this.glyph);
}

class ChampionsReferenceSet {
  final int tile;
  final int badgeTile;
  final List<ChampionsRef> sprites;
  final List<_BadgeSig> _badges;

  ChampionsReferenceSet._(this.tile, this.badgeTile, this.sprites, this._badges);

  static const indexAsset = 'assets/data/champions_refs.json';

  /// Colour distance (0-255 space) at which a pixel counts as "not the panel".
  static const _bgDistance = 45.0;

  /// A slot only holds a badge if it has this much near-white glyph...
  static const _minGlyphFraction = 0.045;

  /// ...and its median colour is this far from the panel background.
  static const _minSlotDistance = 40.0;

  /// Below this the badge read is discarded rather than guessed.
  static const _minBadgeScore = 0.30;

  /// ...and the winner must beat the runner-up by this much. Grey Normal vs
  /// navy Dark, and yellow Electric vs orange Fighting, come down to a few
  /// hundredths at phone-camera resolution; a coin flip between them is worth
  /// less than no answer, because the caller treats an absent badge as "no
  /// prior" but a wrong one as evidence.
  static const _minBadgeMargin = 0.06;

  /// The white-glyph IoU is the EXPOSURE-INVARIANT half of the evidence, and
  /// a read that rests on hue alone is a guess: hue always names SOME type,
  /// and on a soft, colour-cast capture it names the wrong one confidently.
  /// The rig frame of 2026-09-17 read Water as Fire and Ghost as Normal at
  /// IoU 0.03 and 0.12 — its 25 px badges are below the blur limit and the
  /// glyph simply is not resolved — while every correct read on the phone
  /// fixtures scored 0.38+ (only a featureless Normal pill scored 0.19).
  /// Below this the badge is unread, which is worth far more than a wrong
  /// one: a wrong type docks the true species [SpriteMatcher.typePriorPenalty]
  /// AND hands [SpriteMatcher.typePriorBonus] to an impostor.
  static const _minGlyphIou = 0.35;

  /// Returns null when the atlas assets are absent (older builds, bare tests),
  /// which lets the matcher fall back to its legacy behaviour.
  static Future<ChampionsReferenceSet?> load(AtlasByteLoader loadBytes) async {
    final metaBytes = await loadBytes(indexAsset);
    if (metaBytes == null) return null;
    final Map<String, dynamic> meta;
    try {
      meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final tile = (meta['tile'] as num?)?.toInt() ?? 32;
    final cols = (meta['cols'] as num?)?.toInt() ?? 16;
    final atlasBytes = await loadBytes(meta['atlas'] as String? ?? '');
    if (atlasBytes == null) return null;
    final atlas = img.decodeImage(atlasBytes);
    if (atlas == null) return null;

    final sprites = <ChampionsRef>[];
    for (final raw in (meta['sprites'] as List? ?? const [])) {
      final s = raw as Map<String, dynamic>;
      final idx = (s['i'] as num).toInt();
      final tx = (idx % cols) * tile, ty = (idx ~/ cols) * tile;
      if (tx + tile > atlas.width || ty + tile > atlas.height) continue;
      final n = tile * tile;
      final r = Float64List(n), g = Float64List(n), b = Float64List(n);
      final a = Float64List(n);
      var i = 0;
      for (var y = 0; y < tile; y++) {
        for (var x = 0; x < tile; x++, i++) {
          final p = atlas.getPixel(tx + x, ty + y);
          r[i] = p.r / 255.0;
          g[i] = p.g / 255.0;
          b[i] = p.b / 255.0;
          a[i] = p.a / 255.0;
        }
      }
      sprites.add(ChampionsRef(
        formId: s['form'] as String,
        speciesId: s['species'] as String,
        displayName: s['name'] as String? ?? s['form'] as String,
        types: [for (final t in (s['types'] as List? ?? const [])) t as String],
        size: tile,
        r: r,
        g: g,
        b: b,
        a: a,
      ));
    }
    if (sprites.isEmpty) return null;

    final badgeTile = (meta['badgeTile'] as num?)?.toInt() ?? 28;
    final badgeCols = (meta['badgeCols'] as num?)?.toInt() ?? 6;
    final badges = <_BadgeSig>[];
    final badgeBytes = await loadBytes(meta['badgeAtlas'] as String? ?? '');
    final badgeAtlas =
        badgeBytes == null ? null : img.decodeImage(badgeBytes);
    if (badgeAtlas != null) {
      for (final raw in (meta['badges'] as List? ?? const [])) {
        final s = raw as Map<String, dynamic>;
        final idx = (s['i'] as num).toInt();
        final bx = (idx % badgeCols) * badgeTile;
        final by = (idx ~/ badgeCols) * badgeTile;
        if (bx + badgeTile > badgeAtlas.width ||
            by + badgeTile > badgeAtlas.height) {
          continue;
        }
        final f = _featureFrom(
            badgeAtlas, bx, by, bx + badgeTile, by + badgeTile, badgeTile);
        badges.add(_BadgeSig(s['type'] as String, f.cr, f.cg, f.glyph));
      }
    }
    return ChampionsReferenceSet._(tile, badgeTile, sprites, badges);
  }

  bool get hasBadges => _badges.isNotEmpty;

  // ------------------------------------------------------- badge reading --

  /// Read one type-badge slot of a panel. [bgR]/[bgG]/[bgB] are the panel's
  /// background colour in 0-255 space; an unfilled slot *is* that colour, so
  /// it is rejected rather than matched to the nearest same-hue badge (the
  /// crimson panel otherwise reads as Fire every time).
  String? readBadge(img.Image photo, int x0, int y0, int x1, int y1,
      double bgR, double bgG, double bgB) {
    if (_badges.isEmpty) return null;
    x0 = x0.clamp(0, photo.width - 1);
    x1 = x1.clamp(x0 + 1, photo.width);
    y0 = y0.clamp(0, photo.height - 1);
    y1 = y1.clamp(y0 + 1, photo.height);
    if (x1 - x0 < 8 || y1 - y0 < 8) return null;
    if (!_slotFilled(photo, x0, y0, x1, y1, bgR, bgG, bgB)) return null;

    final box = _tightBox(photo, x0, y0, x1, y1, bgR, bgG, bgB);
    final f =
        _featureFrom(photo, box[0], box[1], box[2], box[3], badgeTile);

    var bestScore = -1.0, runnerUp = -1.0, bestIou = 0.0;
    String? best;
    for (final sig in _badges) {
      final dc = math.sqrt((f.cr - sig.cr) * (f.cr - sig.cr) +
          (f.cg - sig.cg) * (f.cg - sig.cg));
      var inter = 0.0, union = 0.0;
      for (var i = 0; i < f.glyph.length && i < sig.glyph.length; i++) {
        final a = f.glyph[i], b = sig.glyph[i];
        inter += a * b;
        union += a > b ? a : b;
      }
      final iou = union > 0 ? inter / union : 0.0;
      final score = 0.55 * (1 - math.min(dc / 0.22, 1.0)) + 0.45 * iou;
      if (score > bestScore) {
        runnerUp = bestScore;
        bestScore = score;
        bestIou = iou;
        best = sig.type;
      } else if (score > runnerUp) {
        runnerUp = score;
      }
    }
    if (bestScore < _minBadgeScore) return null;
    if (bestScore - runnerUp < _minBadgeMargin) return null;
    if (bestIou < _minGlyphIou) return null;
    return best;
  }

  /// Raw match score of one badge region against ONE type's signature —
  /// no argmax over the 18 types and none of [readBadge]'s absolute gates.
  /// This is the *restricted* comparison the team scanner uses inside a
  /// form family, where the question is never "which of 18 types?" but
  /// "Fire or Water?": a Ghost badge whose purple body hides against the
  /// card strip fails every detection gate yet still scores higher against
  /// the Ghost signature than the Fire one. Returns -1 when the type is
  /// unknown, the badges are unloaded, or the region is degenerate.
  double badgeTypeScore(img.Image photo, int x0, int y0, int x1, int y1,
      double bgR, double bgG, double bgB, String type) {
    _BadgeSig? sig;
    for (final s in _badges) {
      if (s.type == type) sig = s;
    }
    if (sig == null) return -1.0;
    x0 = x0.clamp(0, photo.width - 1);
    x1 = x1.clamp(x0 + 1, photo.width);
    y0 = y0.clamp(0, photo.height - 1);
    y1 = y1.clamp(y0 + 1, photo.height);
    if (x1 - x0 < 8 || y1 - y0 < 8) return -1.0;
    final box = _tightBox(photo, x0, y0, x1, y1, bgR, bgG, bgB);
    final f = _featureFrom(photo, box[0], box[1], box[2], box[3], badgeTile);
    final dc = math.sqrt((f.cr - sig.cr) * (f.cr - sig.cr) +
        (f.cg - sig.cg) * (f.cg - sig.cg));
    var inter = 0.0, union = 0.0;
    for (var i = 0; i < f.glyph.length && i < sig.glyph.length; i++) {
      final a = f.glyph[i], b = sig.glyph[i];
      inter += a * b;
      union += a > b ? a : b;
    }
    final iou = union > 0 ? inter / union : 0.0;
    return 0.55 * (1 - math.min(dc / 0.22, 1.0)) + 0.45 * iou;
  }

  /// Badge squares inside a panel's badge area [x0,x1) x [y0,y1): column runs
  /// of off-card pixels, a run about twice as wide as it is tall split into
  /// two squares (badges are square and sit side by side). One run of about
  /// the area's height is the single badge the game centres between the two
  /// slots. Returns at most two boxes, left to right, each padded by 2 px.
  List<List<int>> badgeBoxes(img.Image photo, int x0, int y0, int x1, int y1,
      double bgR, double bgG, double bgB) {
    x0 = x0.clamp(0, photo.width - 1);
    x1 = x1.clamp(x0 + 1, photo.width);
    y0 = y0.clamp(0, photo.height - 1);
    y1 = y1.clamp(y0 + 1, photo.height);
    final h = y1 - y0, w = x1 - x0;
    if (h < 8 || w < 8) return const [];
    final on = List<bool>.filled(w, false);
    for (var x = x0; x < x1; x++) {
      var k = 0;
      for (var y = y0; y < y1; y++) {
        final p = photo.getPixel(x, y);
        final dr = p.r - bgR, dg = p.g - bgG, db = p.b - bgB;
        if (dr * dr + dg * dg + db * db > _bgDistance * _bgDistance) k++;
      }
      on[x - x0] = k > 0.25 * h;
    }
    final runs = <List<int>>[];
    int? start;
    for (var i = 0; i < w; i++) {
      if (on[i] && start == null) {
        start = i;
      } else if (!on[i] && start != null) {
        runs.add([start, i]);
        start = null;
      }
    }
    if (start != null) runs.add([start, w]);
    final merged = <List<int>>[];
    for (final r in runs) {
      if (merged.isNotEmpty && r[0] - merged.last[1] < 3) {
        merged.last[1] = r[1];
      } else {
        merged.add([r[0], r[1]]);
      }
    }
    final boxes = <List<int>>[];
    for (final r in merged) {
      final rw = r[1] - r[0];
      if (rw < 0.3 * h) continue;
      final n = (rw / h).round().clamp(1, 2);
      final step = rw / n;
      for (var k = 0; k < n; k++) {
        boxes.add([
          x0 + (r[0] + k * step).floor() - 2,
          y0,
          x0 + (r[0] + (k + 1) * step).floor() + 2,
          y1,
        ]);
      }
    }
    return boxes.length > 2 ? boxes.sublist(0, 2) : boxes;
  }

  static bool _slotFilled(img.Image photo, int x0, int y0, int x1, int y1,
      double bgR, double bgG, double bgB) {
    var white = 0, total = 0;
    final rs = <double>[], gs = <double>[], bs = <double>[];
    // "White glyph" is judged RELATIVE to the card: a rig frame exposed for
    // a bright screen (ae_level -2) never puts anything near 255, but the
    // glyph is still far brighter than the crimson it sits on.
    final bgLum = (bgR + bgG + bgB) / 3;
    final whiteLum = math.max(120.0, bgLum + 55);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++, total++) {
        final p = photo.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        rs.add(r);
        gs.add(g);
        bs.add(b);
        final lum = (r + g + b) / 3;
        final mx = math.max(r, math.max(g, b));
        final mn = math.min(r, math.min(g, b));
        if (lum > whiteLum && (mx - mn) < 80) white++;
      }
    }
    if (total == 0) return false;
    if (white / total <= _minGlyphFraction) return false;
    final dr = _median(rs) - bgR, dg = _median(gs) - bgG, db = _median(bs) - bgB;
    return math.sqrt(dr * dr + dg * dg + db * db) > _minSlotDistance;
  }

  /// Trim the panel-coloured margin off a slot. Uses 2nd/98th percentile of
  /// the off-background pixel coordinates, so a stray highlight can't blow the
  /// box open the way a raw min/max bounding box would.
  static List<int> _tightBox(img.Image photo, int x0, int y0, int x1, int y1,
      double bgR, double bgG, double bgB) {
    final xs = <double>[], ys = <double>[];
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final p = photo.getPixel(x, y);
        final dr = p.r - bgR, dg = p.g - bgG, db = p.b - bgB;
        if (dr * dr + dg * dg + db * db > _bgDistance * _bgDistance) {
          xs.add(x.toDouble());
          ys.add(y.toDouble());
        }
      }
    }
    if (xs.length < 30) return [x0, y0, x1, y1];
    xs.sort();
    ys.sort();
    int q(List<double> v, double f) => v[(v.length * f).floor().clamp(0, v.length - 1)].round();
    final bx0 = q(xs, 0.02), bx1 = q(xs, 0.98) + 1;
    final by0 = q(ys, 0.02), by1 = q(ys, 0.98) + 1;
    if (bx1 - bx0 < 8 || by1 - by0 < 8) return [x0, y0, x1, y1];
    return [bx0, by0, bx1, by1];
  }

  /// Area-average the region down to [n]x[n], then derive the exposure-
  /// invariant signature: body chromaticity + white-glyph mask.
  static _BadgeFeat _featureFrom(
      img.Image src, int x0, int y0, int x1, int y1, int n) {
    final w = x1 - x0, h = y1 - y0;
    final count = n * n;
    final cr = Float64List(count), cg = Float64List(count);
    final lum = Float64List(count), sat = Float64List(count);
    for (var ty = 0; ty < n; ty++) {
      final sy0 = y0 + (ty * h / n).floor();
      final sy1 = math.max(sy0 + 1, y0 + ((ty + 1) * h / n).floor());
      for (var tx = 0; tx < n; tx++) {
        final sx0 = x0 + (tx * w / n).floor();
        final sx1 = math.max(sx0 + 1, x0 + ((tx + 1) * w / n).floor());
        var sr = 0.0, sg = 0.0, sb = 0.0;
        var k = 0;
        for (var y = sy0; y < sy1 && y < src.height; y++) {
          for (var x = sx0; x < sx1 && x < src.width; x++, k++) {
            final p = src.getPixel(x, y);
            sr += p.r;
            sg += p.g;
            sb += p.b;
          }
        }
        if (k == 0) k = 1;
        final r = sr / k, g = sg / k, b = sb / k;
        final i = ty * n + tx;
        final s = r + g + b + 1e-6;
        cr[i] = r / s;
        cg[i] = g / s;
        lum[i] = (r + g + b) / 3;
        sat[i] = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      }
    }
    final lumThr = _percentile(lum, 0.70);
    final satThr = _percentile(sat, 0.45);
    final glyph = Float64List(count);
    final bodyR = <double>[], bodyG = <double>[];
    for (var i = 0; i < count; i++) {
      if (lum[i] > lumThr && sat[i] < satThr) {
        glyph[i] = 1.0;
      } else {
        bodyR.add(cr[i]);
        bodyG.add(cg[i]);
      }
    }
    double mr, mg;
    if (bodyR.length > 40) {
      mr = _median(bodyR);
      mg = _median(bodyG);
    } else {
      mr = _median(List<double>.from(cr));
      mg = _median(List<double>.from(cg));
    }
    return _BadgeFeat(mr, mg, glyph);
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
}
