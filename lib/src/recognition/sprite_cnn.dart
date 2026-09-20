/// Trained sprite classifier for the team-preview screen — pure Dart, no
/// native ML runtime, so it runs in plain `flutter test` like the rest of the
/// recognition pipeline.
///
/// WHY: the template tier (masked NCC against the game's own sprites) needs a
/// clean segmentation, and a clean segmentation needs contrast. The rig
/// compresses sprite-vs-card contrast to ~45%, the absolute foreground gate
/// then cuts fragments, and NCC of a fragment is noise — 1/6, 1/6 and 2/6 on
/// real rig scans. Six adaptive gates were tried and all lost (CLAUDE.md).
/// This model never segments: it looks at a FIXED window of the panel and was
/// trained on the 262 Champions sprites rendered onto synthetic cards and
/// degraded the way the rig degrades them (blur, contrast compression, colour
/// cast, translucent card, glare, scanlines, JPEG, finder error). Per-channel
/// standardisation of the window removes exposure/contrast/cast outright.
///
/// Mirrors `tool/sprite_cnn/export.py:forward` exactly (the Python twin);
/// `test/sprite_cnn_test.dart` checks the logits against goldens from it.
///
/// Model files (written by `tool/sprite_cnn/export.py`):
///   assets/models/sprite_cnn.json  window, input size, layer shapes, classes
///   assets/models/sprite_cnn.bin   float32 LE: per conv W[out][ky][kx][in]
///                                  then bias[out]; then dense W[out][in], b
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef CnnByteLoader = Future<Uint8List?> Function(String path);

class _Conv {
  final int cin, cout;
  final bool pool;

  /// Re-laid out as [ky][kx][cin][cout] so the innermost loop runs over
  /// output channels contiguously in both weights and accumulator.
  final Float32List w;
  final Float32List b;
  _Conv(this.cin, this.cout, this.pool, this.w, this.b);
}

class SpriteCnn {
  static const metaAsset = 'assets/models/sprite_cnn.json';
  static const binAsset = 'assets/models/sprite_cnn.bin';

  /// Floor on the per-channel std (0-1 units) — a flat window must not be
  /// amplified into noise. Same constant as the training pipeline.
  static const stdFloor = 0.02;

  final int input;
  final double wx0, wx1, wy0, wy1;
  final List<_Conv> _convs;
  final int _fcIn, _fcOut;
  final Float32List _fcW, _fcB;

  /// Class index -> pack species id / display name.
  final List<String> species;
  final List<String> names;

  SpriteCnn._(this.input, this.wx0, this.wx1, this.wy0, this.wy1, this._convs,
      this._fcIn, this._fcOut, this._fcW, this._fcB, this.species, this.names);

  /// Null when the model files are absent or malformed — the matcher then
  /// falls back to the template tier.
  static Future<SpriteCnn?> load(CnnByteLoader loadBytes) async {
    final metaBytes = await loadBytes(metaAsset);
    final binBytes = await loadBytes(binAsset);
    if (metaBytes == null || binBytes == null) return null;
    try {
      final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
      final bd = ByteData.sublistView(binBytes);
      final nFloats = binBytes.lengthInBytes ~/ 4;
      if (nFloats != (meta['floats'] as num).toInt()) return null;
      var off = 0;
      Float32List take(int n) {
        final out = Float32List(n);
        for (var i = 0; i < n; i++) {
          out[i] = bd.getFloat32((off + i) * 4, Endian.little);
        }
        off += n;
        return out;
      }

      final convs = <_Conv>[];
      int? fcIn, fcOut;
      Float32List? fcW, fcB;
      for (final raw in meta['layers'] as List) {
        final l = raw as Map<String, dynamic>;
        final cout = (l['out'] as num).toInt();
        final cin = (l['inp'] as num).toInt();
        if (l['kind'] == 'conv3x3') {
          final src = take(cout * 9 * cin); // [out][ky][kx][in]
          final w = Float32List(9 * cin * cout); // [ky][kx][in][out]
          for (var o = 0; o < cout; o++) {
            for (var k = 0; k < 9; k++) {
              for (var c = 0; c < cin; c++) {
                w[(k * cin + c) * cout + o] = src[(o * 9 + k) * cin + c];
              }
            }
          }
          convs.add(_Conv(cin, cout, l['pool'] == true, w, take(cout)));
        } else if (l['kind'] == 'dense') {
          fcIn = cin;
          fcOut = cout;
          fcW = take(cout * cin);
          fcB = take(cout);
        } else {
          return null;
        }
      }
      if (fcW == null || off != nFloats) return null;
      final wx = (meta['windowX'] as List).cast<num>();
      final wy = (meta['windowY'] as List).cast<num>();
      return SpriteCnn._(
        (meta['input'] as num).toInt(),
        wx[0].toDouble(),
        wx[1].toDouble(),
        wy[0].toDouble(),
        wy[1].toDouble(),
        convs,
        fcIn!,
        fcOut!,
        fcW,
        fcB!,
        (meta['species'] as List).cast<String>(),
        (meta['classes'] as List).cast<String>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Round half up, the same rule the Python twin uses (floor(v + 0.5)) —
  /// NOT Python's banker's round.
  static int _r(double v) => (v + 0.5).floor();

  /// The fixed sprite window of [panel] ([x0, y0, x1, y1] in [photo] pixels),
  /// area-resampled to [input] x [input] and standardised per channel.
  /// Layout: HWC, float32.
  Float32List inputFor(img.Image photo, List<int> panel) {
    final pw = panel[2] - panel[0], ph = panel[3] - panel[1];
    var x0 = panel[0] + _r(pw * wx0), x1 = panel[0] + _r(pw * wx1);
    var y0 = panel[1] + _r(ph * wy0), y1 = panel[1] + _r(ph * wy1);
    x0 = x0.clamp(0, photo.width - 1);
    y0 = y0.clamp(0, photo.height - 1);
    x1 = x1.clamp(x0 + 1, photo.width);
    y1 = y1.clamp(y0 + 1, photo.height);
    final w = x1 - x0, h = y1 - y0;
    final src = Float64List(w * h * 3);
    var i = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final p = photo.getPixel(x, y);
        src[i++] = p.r / 255.0;
        src[i++] = p.g / 255.0;
        src[i++] = p.b / 255.0;
      }
    }
    return standardize(areaResize(src, h, w, input, input));
  }

  /// Exact area-weighted resample (each output pixel = mean of its source
  /// footprint, fractional edges weighted). HWC in, HWC out.
  static Float32List areaResize(
      Float64List src, int h, int w, int hOut, int wOut) {
    final my = _areaWeights(h, hOut), mx = _areaWeights(w, wOut);
    // vertical pass: (hOut, w, 3)
    final tmp = Float64List(hOut * w * 3);
    for (var o = 0; o < hOut; o++) {
      for (final (i, wt) in my[o]) {
        final s = i * w * 3, d = o * w * 3;
        for (var k = 0; k < w * 3; k++) {
          tmp[d + k] += wt * src[s + k];
        }
      }
    }
    // horizontal pass: (hOut, wOut, 3)
    final out = Float32List(hOut * wOut * 3);
    for (var y = 0; y < hOut; y++) {
      for (var p = 0; p < wOut; p++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (final (j, wt) in mx[p]) {
          final s = (y * w + j) * 3;
          r += wt * tmp[s];
          g += wt * tmp[s + 1];
          b += wt * tmp[s + 2];
        }
        final d = (y * wOut + p) * 3;
        out[d] = r;
        out[d + 1] = g;
        out[d + 2] = b;
      }
    }
    return out;
  }

  /// Per output index: (source index, normalised weight) pairs.
  static List<List<(int, double)>> _areaWeights(int nIn, int nOut) {
    final scale = nIn / nOut;
    final rows = <List<(int, double)>>[];
    for (var o = 0; o < nOut; o++) {
      final a = o * scale, b = (o + 1) * scale;
      final i0 = a.floor(), i1 = math.min(b.ceil(), nIn);
      final row = <(int, double)>[];
      var sum = 0.0;
      for (var i = i0; i < i1; i++) {
        final wt = math.min(b, i + 1.0) - math.max(a, i.toDouble());
        if (wt > 0) {
          row.add((i, wt));
          sum += wt;
        }
      }
      rows.add([for (final (i, wt) in row) (i, wt / sum)]);
    }
    return rows;
  }

  /// Per-channel (x - mean) / max(std, stdFloor) over the whole window.
  static Float32List standardize(Float32List x) {
    final n = x.length ~/ 3;
    final out = Float32List(x.length);
    for (var c = 0; c < 3; c++) {
      var m = 0.0;
      for (var i = 0; i < n; i++) {
        m += x[i * 3 + c];
      }
      m /= n;
      var v = 0.0;
      for (var i = 0; i < n; i++) {
        final d = x[i * 3 + c] - m;
        v += d * d;
      }
      final s = math.max(math.sqrt(v / n), stdFloor);
      for (var i = 0; i < n; i++) {
        out[i * 3 + c] = (x[i * 3 + c] - m) / s;
      }
    }
    return out;
  }

  /// Raw class scores for a standardised [input] x [input] x 3 window.
  Float32List logits(Float32List x) {
    var a = x;
    var h = input, w = input, c = 3;
    for (final conv in _convs) {
      final co = conv.cout;
      final out = Float32List(h * w * co);
      final acc = Float64List(co);
      for (var y = 0; y < h; y++) {
        for (var xx = 0; xx < w; xx++) {
          for (var o = 0; o < co; o++) {
            acc[o] = conv.b[o];
          }
          for (var ky = 0; ky < 3; ky++) {
            final sy = y + ky - 1;
            if (sy < 0 || sy >= h) continue;
            for (var kx = 0; kx < 3; kx++) {
              final sx = xx + kx - 1;
              if (sx < 0 || sx >= w) continue;
              final ib = (sy * w + sx) * c;
              final wb = (ky * 3 + kx) * c * co;
              for (var ci = 0; ci < c; ci++) {
                final v = a[ib + ci];
                if (v == 0) continue; // post-ReLU activations are mostly 0
                final wr = wb + ci * co;
                for (var o = 0; o < co; o++) {
                  acc[o] += v * conv.w[wr + o];
                }
              }
            }
          }
          final ob = (y * w + xx) * co;
          for (var o = 0; o < co; o++) {
            out[ob + o] = acc[o] > 0 ? acc[o] : 0.0; // ReLU
          }
        }
      }
      a = out;
      c = co;
      if (conv.pool) {
        final h2 = h ~/ 2, w2 = w ~/ 2;
        final pooled = Float32List(h2 * w2 * c);
        for (var y = 0; y < h2; y++) {
          for (var xx = 0; xx < w2; xx++) {
            for (var ci = 0; ci < c; ci++) {
              var m = a[((2 * y) * w + 2 * xx) * c + ci];
              m = math.max(m, a[((2 * y) * w + 2 * xx + 1) * c + ci]);
              m = math.max(m, a[((2 * y + 1) * w + 2 * xx) * c + ci]);
              m = math.max(m, a[((2 * y + 1) * w + 2 * xx + 1) * c + ci]);
              pooled[(y * w2 + xx) * c + ci] = m;
            }
          }
        }
        a = pooled;
        h = h2;
        w = w2;
      }
    }
    // global average pool + dense
    final g = Float64List(c);
    for (var i = 0; i < h * w; i++) {
      for (var ci = 0; ci < c; ci++) {
        g[ci] += a[i * c + ci];
      }
    }
    for (var ci = 0; ci < c; ci++) {
      g[ci] /= h * w;
    }
    assert(c == _fcIn);
    final z = Float32List(_fcOut);
    for (var o = 0; o < _fcOut; o++) {
      var s = _fcB[o].toDouble();
      final base = o * _fcIn;
      for (var ci = 0; ci < _fcIn; ci++) {
        s += _fcW[base + ci] * g[ci];
      }
      z[o] = s;
    }
    return z;
  }

  /// Softmax probabilities, one per class (see [species]).
  List<double> probabilities(Float32List x) {
    final z = logits(x);
    var m = z[0];
    for (final v in z) {
      if (v > m) m = v;
    }
    final e = [for (final v in z) math.exp(v - m)];
    final s = e.fold(0.0, (p, v) => p + v);
    return [for (final v in e) v / s];
  }
}
