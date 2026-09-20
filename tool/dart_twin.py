"""A FAITHFUL port of SpriteMatcher's crop + score path, so the Python side
can predict what the app will actually do.

`recognition_prototype.py` is the design sandbox — its segmentation constants
drifted from the Dart over time (d>80 vs Dart's ~31, its own blob rules), so
it disagreed with the app by 2-3 panels on a rig frame and was no longer
usable as evidence about a shipped scan. Everything here mirrors the Dart
line for line, including the workWidth downscale for detection and the crop
from the ORIGINAL pixels.

    python3 tool/dart_twin.py <frame.jpg> "Truth One,Truth Two,..."
"""
import json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recognition_prototype as rp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK_W = 1200                 # SpriteMatcher.workWidth
FG_LOW, FG_SPAN, FG_HARD = 0.12, 0.25, 0.35     # fgThresholdLow/Span/fgHardMask
V_INSET = 0.06                                   # panelVerticalInset
SPRITE_X = (0.14, 0.62)
TYPE_BONUS, TYPE_PENALTY = 0.22, 0.10
TILE = 32                                        # champions_refs tile size


def is_card(r, g, b):
    s = r + g + b + 1e-6
    return (r / s >= 0.36) & (g / s <= 0.27) & (r / s >= g / s + 0.15) & (np.maximum(np.maximum(r, g), b) >= 55)


def segment_sprite(photo, panel):
    """SpriteMatcher._segmentSprite, in 0-1 RGB like the Dart."""
    px0, px1 = panel[0], panel[2]
    ph = panel[3] - panel[1]
    dy = round(ph * V_INSET)
    py0, py1 = panel[1] + dy, panel[3] - dy
    pw = px1 - px0
    x0 = px0 + round(pw * SPRITE_X[0])
    x1 = px0 + round(pw * SPRITE_X[1])
    crop = photo[py0:py1, x0:x1].astype(np.float32) / 255.0
    ch, cw, _ = crop.shape
    border = np.zeros((ch, cw), bool)
    border[:2, :] = border[-2:, :] = True
    border[:, :2] = border[:, -2:] = True
    b255 = crop * 255
    cardpx = border & is_card(b255[..., 0], b255[..., 1], b255[..., 2])
    src = crop[cardpx] if cardpx.sum() >= 16 else crop[border]
    bg = np.median(src, 0) if len(src) else np.zeros(3)
    dist = np.sqrt(((crop - bg) ** 2).sum(2))
    alpha = np.clip((dist - FG_LOW) / FG_SPAN, 0, 1)
    return keep_main_blob(crop, alpha)


def keep_main_blob(crop, alpha):
    from scipy import ndimage as ndi
    hard = alpha >= FG_HARD
    lab, k = ndi.label(hard)                      # 4-connectivity like the Dart
    if k == 0:
        return crop, alpha
    sizes = ndi.sum(hard, lab, range(1, k + 1))
    big = int(np.argmax(sizes)) + 1
    ys, xs = np.where(lab == big)
    by0, by1, bx0, bx1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = hard.shape
    padX, padY = w * 0.10, h * 0.10
    keep = {big}
    objs = ndi.find_objects(lab)
    for l in range(1, k + 1):
        if l == big:
            continue
        if sizes[l - 1] < max(12, sizes[big - 1] * 0.06):
            continue
        sl = objs[l - 1]
        y0, y1 = sl[0].start, sl[0].stop - 1
        x0, x1 = sl[1].start, sl[1].stop - 1
        far = y0 > by1 + padY or y1 < by0 - padY or x0 > bx1 + padX or x1 < bx0 - padX
        if not far:
            keep.add(l)
    drop = hard & ~np.isin(lab, list(keep))
    alpha = alpha.copy()
    alpha[drop] = 0.0
    # tighten to the hard-mask bbox
    ys, xs = np.where(alpha > FG_HARD)
    if len(ys) == 0 or ys.max() - ys.min() < 3 or xs.max() - xs.min() < 3:
        return crop, alpha
    sl = (slice(ys.min(), ys.max() + 1), slice(xs.min(), xs.max() + 1))
    return crop[sl], alpha[sl]


def square_resize(rgb, a, n):
    """_resizeSquare: pad to a square on the sprite's own bbox, then resize."""
    h, w = a.shape
    s = max(h, w)
    R = np.zeros((s, s, 3), np.float32); A = np.zeros((s, s), np.float32)
    oy, ox = (s - h) // 2, (s - w) // 2
    R[oy:oy + h, ox:ox + w] = rgb; A[oy:oy + h, ox:ox + w] = a
    ri = np.asarray(Image.fromarray((R * 255).astype(np.uint8)).resize((n, n), Image.BILINEAR)).astype(np.float32) / 255
    ai = np.asarray(Image.fromarray((A * 255).astype(np.uint8)).resize((n, n), Image.BILINEAR)).astype(np.float32) / 255
    return ri, ai


def template_score(cr, ca, rr, ra, corr_w=0.75):
    """_templateScore: masked per-channel NCC blended with mask agreement."""
    w = (ca * ra).ravel()
    wsum = w.sum()
    if wsum < 4:
        return -1.0
    union = np.maximum(ca, ra).sum()
    tot = 0.0
    for ch in range(3):
        A = cr[..., ch].ravel(); B = rr[..., ch].ravel()
        ma = (A * w).sum() / wsum; mb = (B * w).sum() / wsum
        xa, xb = A - ma, B - mb
        den = np.sqrt((w * xa * xa).sum() * (w * xb * xb).sum())
        if den > 1e-9:
            tot += (w * xa * xb).sum() / den
    shape = wsum / union if union > 0 else 0.0
    return corr_w * (tot / 3) + (1 - corr_w) * shape


def load_refs():
    meta = json.load(open(f'{ROOT}/assets/data/champions_refs.json'))
    atlas = np.asarray(Image.open(f'{ROOT}/assets/sprites/champions_atlas.png').convert('RGBA')).astype(np.float32) / 255
    tile, cols = meta.get('tile', TILE), meta.get('cols', 16)
    out = []
    for s in meta['sprites']:
        i = s['i']; tx, ty = (i % cols) * tile, (i // cols) * tile
        t = atlas[ty:ty + tile, tx:tx + tile]
        out.append((s, t[..., :3], t[..., 3]))
    return meta, out


def analyse(path, truth=None, corr_w=0.75):
    photo = np.asarray(Image.open(path).convert('RGB'))
    panels = rp.panels_of(photo.astype(np.float32))
    meta, refs = load_refs()
    tile = meta.get('tile', TILE)
    print(f'{os.path.basename(path)}  {photo.shape[1]}x{photo.shape[0]}  {len(panels)} panels')
    hits = 0
    for i, p in enumerate(panels):
        rgb, a = segment_sprite(photo, p)
        cr, ca = square_resize(rgb, a, tile)
        scored = [(template_score(cr, ca, rr, ra, corr_w), s['name'], s['species']) for s, rr, ra in refs]
        scored.sort(reverse=True)
        top = '  '.join(f'{n}:{v:.3f}' for v, n, _ in scored[:4])
        mark = ''
        if truth:
            ok = scored[0][1] == truth[i]; hits += ok
            rank = 1 + sum(1 for v, n, _ in scored if n != truth[i] and v > dict((n, v) for v, n, _ in scored)[truth[i]])
            mark = ' OK' if ok else f'  WRONG (want {truth[i]}, rank {rank})'
        print(f'  panel{i+1} {p[2]-p[0]}x{p[3]-p[1]} crop {a.shape[1]}x{a.shape[0]} -> {top}{mark}')
    if truth:
        print(f'  = {hits}/{len(truth)}')
    return hits


if __name__ == '__main__':
    path = sys.argv[1]
    truth = sys.argv[2].split(',') if len(sys.argv) > 2 else None
    analyse(path, truth)
