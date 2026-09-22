"""Team-display parsing prototype: cards, sprite ID, gender, name strip.

Validates the vision half of the Dart TeamScanner on the four real photos.
"""
import sys
import numpy as np
from PIL import Image, ImageOps
from scipy import ndimage as ndi
import os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import dart_twin as dt

DETECT_W = 1400


def load(path):
    im = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
    return np.asarray(im)


def find_cards(photo):
    """-> (cards, header) in ORIGINAL pixels; cards sorted row-major (1..6)."""
    H, W, _ = photo.shape
    k = W / DETECT_W
    small = np.asarray(Image.fromarray(photo).resize(
        (DETECT_W, round(H / k)))).astype(np.float32)
    r, g, b = small[..., 0], small[..., 1], small[..., 2]
    mask = (b > r + 30) & (b > g + 45) & (b > 130) & (r > 60)
    lab, n = ndi.label(ndi.binary_opening(mask, np.ones((3, 3))))
    sizes = ndi.sum(mask, lab, range(1, n + 1))
    cards, headers = [], []
    for j in range(1, n + 1):
        if sizes[j - 1] < 8000:
            continue
        ys, xs = np.where(lab == j)
        bw, bh = xs.max() - xs.min(), ys.max() - ys.min()
        box = (int(xs.min() * k), int(ys.min() * k),
               int(xs.max() * k), int(ys.max() * k))
        if bh >= 0.055 * small.shape[0] and bw > 2.5 * bh:
            cards.append(box)
        elif bw > 4 * bh:
            headers.append(box)
    cards.sort(key=lambda c: (c[1], c[0]))
    # group into rows by y proximity, sort each row by x
    rows, cur = [], [cards[0]]
    for c in cards[1:]:
        if c[1] - cur[-1][1] < 0.5 * (cur[-1][3] - cur[-1][1]):
            cur.append(c)
        else:
            rows.append(sorted(cur, key=lambda c: c[0]))
            cur = [c]
    rows.append(sorted(cur, key=lambda c: c[0]))
    ordered = [c for row in rows for c in row]
    headers.sort(key=lambda c: c[0])
    return ordered, headers


def segment_banded(crop):
    """Foreground vs per-row backgrounds from BOTH edges (cream / rounded
    corner / strip / body all covered), PLUS an edge channel: a white sprite
    on cream or a purple one on the card loses its body to the color
    distance, but its dark outline always has strong gradients — mask the
    outline by gradient, then fill enclosed holes so the body counts."""
    c = crop.astype(np.float32) / 255.0
    h, w, _ = c.shape
    m = max(5, w // 12)
    k5 = np.ones(5) / 5
    bgs = []
    for sl in (c[:, -m:], c[:, :m]):
        bg = np.median(sl, axis=1)
        for ch_ in range(3):
            bg[:, ch_] = np.convolve(bg[:, ch_], k5, mode='same')
        bgs.append(bg)
    d = np.minimum(*[np.sqrt(((c - bg[:, None, :]) ** 2).sum(2)) for bg in bgs])
    gray = c.mean(2)
    gx = np.zeros_like(gray)
    gy = np.zeros_like(gray)
    gx[:, 1:-1] = np.abs(gray[:, 2:] - gray[:, :-2])
    gy[1:-1, :] = np.abs(gray[2:, :] - gray[:-2, :])
    grad = np.maximum(gx, gy)
    noise = np.median(grad) + 1e-6
    edge = grad > max(0.10, 4.0 * noise)
    hard = (d > 0.30) | ndi.binary_opening(edge, np.ones((2, 2)))
    hard = ndi.binary_opening(hard, np.ones((2, 2)))
    lab, n = ndi.label(hard)
    if n == 0:
        return c, np.zeros((h, w), np.float32)
    sizes = ndi.sum(hard, lab, range(1, n + 1))
    main = int(np.argmax(sizes)) + 1
    keep = lab == main
    near = ndi.binary_dilation(keep, np.ones((3, 3)), iterations=3)
    for j in range(1, n + 1):
        if j != main and sizes[j - 1] >= 12 and (near & (lab == j)).any():
            keep |= lab == j
    filled = ndi.binary_fill_holes(keep)
    holes = filled & ~keep
    hl, hk = ndi.label(holes)
    cap = 1.5 * keep.sum()
    for j in range(1, hk + 1):
        mm = hl == j
        if mm.sum() <= cap:
            keep |= mm
    alpha = np.clip((d - 0.16) / 0.25, 0, 1)
    alpha = np.maximum(alpha, np.where(keep, 0.9, 0.0).astype(np.float32))
    alpha[~ndi.binary_dilation(keep, np.ones((3, 3)))] = 0
    ys, xs = np.where(alpha > 0.35)
    if len(ys) == 0:
        return c, np.zeros((h, w), np.float32)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return c[y0:y1, x0:x1], alpha[y0:y1, x0:x1]


def identify_sprite(photo, card, refs, tile):
    x0, y0, x1, y1 = card
    ch = y1 - y0
    cw = x1 - x0
    H, W, _ = photo.shape
    wx0 = max(0, x0 - int(0.005 * cw))
    wx1 = min(W, x0 + int(0.140 * cw))
    wy0 = max(0, y0 - int(0.18 * ch))
    wy1 = min(H, y0 + int(0.33 * ch))
    crop = photo[wy0:wy1, wx0:wx1]
    rgb, a = segment_banded(crop)
    if a.size < 16:
        return []
    cr, ca = dt.square_resize(rgb, a, tile)
    scored = sorted(((dt.template_score(cr, ca, rr, ra), s['name'], s['species'])
                     for s, rr, ra in refs), reverse=True)
    return scored[:4]


def read_gender(photo, card, n_types):
    """Colored blobs in the name strip right of the name: len(types) badges,
    plus optionally one gender circle FIRST. -> 'male' | 'female' | None."""
    x0, y0, x1, y1 = card
    ch, cw = y1 - y0, x1 - x0
    band = photo[y0 + int(0.03 * ch):y0 + int(0.27 * ch),
                 x0 + int(0.10 * cw):x0 + int(0.62 * cw)].astype(np.float32)
    strip = np.median(band.reshape(-1, 3), 0)
    d = np.sqrt(((band - strip) ** 2).sum(2))
    mx = band.max(2)
    mn = band.min(2)
    sat = mx - mn
    blobs_mask = (d > 70) & (sat > 55) & (mn < 200)
    lab, n = ndi.label(ndi.binary_opening(blobs_mask, np.ones((2, 2))))
    if n == 0:
        return None, []
    min_area = 0.002 * band.shape[0] * band.shape[1]
    comps = []
    for j in range(1, n + 1):
        ys, xs = np.where(lab == j)
        if len(ys) < min_area:
            continue
        col = band[lab == j].mean(0)
        comps.append((xs.mean(), col, len(ys)))
    comps.sort(key=lambda t: t[0])
    # merge fragments that overlap in x (a badge glyph can split its body)
    merged = []
    for x, col, area in comps:
        if merged and x - merged[-1][0] < 0.045 * band.shape[1] * 1.2:
            px, pcol, parea = merged[-1]
            merged[-1] = ((px * parea + x * area) / (parea + area),
                          (pcol * parea + col * area) / (parea + area),
                          parea + area)
        else:
            merged.append((x, col, area))
    dbg = [(round(x), col.astype(int).tolist()) for x, col, _ in merged]
    if len(merged) <= n_types:
        return None, dbg
    first = merged[0][1]
    r, g, b = first
    if b > r + 25 and b > g + 25:
        return 'male', dbg
    if r > b + 25 and r > g + 25:
        return 'female', dbg
    return None, dbg


if __name__ == '__main__':
    meta, refs = dt.load_refs()
    tile = meta.get('tile', 32)
    truth = {
        't1_moves': ['Chesnaught', 'Typhlosion', 'Rillaboom', 'Sableye',
                     'Scolipede', 'Armarouge'],
        't1_stats': ['Chesnaught', 'Typhlosion', 'Rillaboom', 'Sableye',
                     'Scolipede', 'Armarouge'],
        't2_moves': ['Heat Rotom', 'Charizard', 'Froslass', 'Garchomp',
                     'Whimsicott', 'Paldean Tauros (Blaze)'],
        't2_stats': ['Heat Rotom', 'Charizard', 'Froslass', 'Garchomp',
                     'Whimsicott', 'Paldean Tauros (Blaze)'],
    }
    genders = {
        't1_moves': ['male', 'male', 'male', 'female', 'male', 'male'],
        't2_moves': [None, 'male', 'female', 'male', 'female', 'male'],
    }
    types_of = {s['name']: len(s.get('types', []) or [1, 1]) for s, _, _ in refs}
    ok = gok = 0
    tot = gtot = 0
    for key in ['t1_moves', 't1_stats', 't2_moves', 't2_stats']:
        photo = load(key + '.jpg')
        cards, headers = find_cards(photo)
        print(f'{key}: {len(cards)} cards, {len(headers)} header pieces')
        for i, card in enumerate(cards):
            top = identify_sprite(photo, card, refs, tile)
            name = top[0][1] if top else '??'
            want = truth[key][i]
            tot += 1
            ok += name == want
            mark = 'OK' if name == want else f'WRONG want {want}'
            extra = ''
            if key in genders:
                nt = types_of.get(want, 2)
                gender, dbg = read_gender(photo, card, nt)
                gtot += 1
                gw = genders[key][i]
                gok += gender == gw
                extra = f'  gender {gender} ({"OK" if gender == gw else f"want {gw} dbg={dbg}"})'
            print(f'  card{i+1}: {name} {top[0][0]:.3f} (2nd {top[1][1]} {top[1][0]:.3f}) {mark}{extra}')
    print(f'sprites {ok}/{tot}   genders {gok}/{gtot}')
