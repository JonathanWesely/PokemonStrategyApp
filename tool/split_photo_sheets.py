#!/usr/bin/env python3
"""Cut NEW Champions sprites out of *photos of a phone screen* showing the
in-game Eligible Pokemon grid, and add them to `pokemon2Dsprites/`.

    python3 tool/split_photo_sheets.py "images/RegulationMC1 (2).jpeg" ... "(6).jpeg"

The Regulation M-B sprites came from clean screen captures and went through
`split_sprite_sheets.py`. The M-C additions arrived as five hand-held photos
(4032x3024, landscape, phone tilted a degree or two, a glare band across
the middle of every shot, LCD moire). This tool is that pipeline adapted:

 1. RECTIFY. Detect the navy tiles themselves (blue-dominant, darker than
    the page between them), fit a homography from lattice (col,row) to
    pixels, warp to a flat sheet with a fixed 121 px pitch and tile centres
    at cell centres (same scale as the M-B captures, so the v4 thresholds
    hold). Fit error is ~2 px at full resolution.
 2. CLASSIFY. A cell is a complete tile when its border is page-blue, its
    largest non-page component is a 62-95 % square that touches no edge, and
    the interior is navy. Bezel-cut rows and glare-merged tiles fail.
 3. ALIGN. Sheets overlap by scroll distance: the row offset between two
    sheets is the one that maximises NCC of 48x48 cell descriptors over
    >= 8 shared complete tiles (the true offset scores ~0.9, everything
    else ~0.5). Chain the sheets into one global grid.
 4. NAME. The grid is in National Dex order and the M-B manifest is the
    same order, so the new list is the old list with insertions; matching
    every cell against the 235 known sprites (NCC on navy composites)
    confirms each old cell in place and exposes the insertions. The
    insertion list is data below (`INSERTIONS`) - it was read off the
    contact sheets and verified against the game's own "24 new Pokemon"
    list; glare cells match wrongly by NCC so this step is not automatic.
 5. SEGMENT (v5 = v4 + photo fixes, see `segment_v5`). Cells under a glare
    *edge* get a per-pixel background field instead of one colour, and a
    fixed tile box when the tile edge is washed out. `dehaze` then removes
    the glare's additive brightness so the sprite colours sit with the
    M-B set.

Only the inserted cells are written; the old 235 PNGs are untouched. The
manifest is rewritten with the new order (262 entries).

Verification: `pokemon2Dsprites/_verification/mc_new.png` shows every new
sprite on magenta at 3x - look at it before trusting the output.
"""
import json, os, sys, warnings
import numpy as np
import cv2
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'pokemon2Dsprites')
PITCH = 121
COLS = 10
NAVY = np.array([44, 54, 184], np.float32)   # tile colour in a glare-free cell of these photos

# ---- naming data ------------------------------------------------------------
# (old display name, [new display names inserted right after it]) - M-C.
INSERTIONS = [
    ('Ninetales-Alola', ['Wigglytuff']),
    ('Vileplume', ['Persian', 'Alolan Persian']),
    ('Galarian Slowbro', ["Farfetch'd"]),
    ('Starmie', ['Mr. Mime']),
    ('Manectric', ['Swalot']),
    ('Glalie', ['Salamence']),
    ('Florges', ['Gogoat']),
    ('Passimian', ['Golisopod']),
    ('Kommo-o', ['Rillaboom', 'Cinderace', 'Inteleon']),
    ('Corviknight', ['Thievul']),
    ('Sandaconda', ['Toxtricity (Amped)', 'Toxtricity (Low Key)', 'Grapploct']),
    ('Grimmsnarl', ['Perrserker', "Sirfetch'd"]),
    ('Falinks', ['Pincurchin', 'Indeedee (Male)', 'Indeedee (Female)']),
    ('Quaquaval', ['Pawmot']),
    ('Maushold', ['Arboliva', 'Squawkabilly (Green Plumage)', 'Squawkabilly (Yellow Plumage)']),
    ('Bellibolt', ['Mabosstiff']),
    ('Kingambit', ['Baxcalibur']),
]
# PokeAPI form ids for the new display names (types come from the pack).
FORM_IDS = {
    'Wigglytuff': 'wigglytuff', 'Persian': 'persian', 'Alolan Persian': 'persian-alola',
    "Farfetch'd": 'farfetchd', 'Mr. Mime': 'mr-mime', 'Swalot': 'swalot', 'Salamence': 'salamence',
    'Gogoat': 'gogoat', 'Golisopod': 'golisopod', 'Rillaboom': 'rillaboom', 'Cinderace': 'cinderace',
    'Inteleon': 'inteleon', 'Thievul': 'thievul', 'Toxtricity (Amped)': 'toxtricity-amped',
    'Toxtricity (Low Key)': 'toxtricity-low-key', 'Grapploct': 'grapploct', 'Perrserker': 'perrserker',
    "Sirfetch'd": 'sirfetchd', 'Pincurchin': 'pincurchin', 'Indeedee (Male)': 'indeedee-male',
    'Indeedee (Female)': 'indeedee-female', 'Pawmot': 'pawmot', 'Arboliva': 'arboliva',
    'Squawkabilly (Green Plumage)': 'squawkabilly-green-plumage',
    'Squawkabilly (Yellow Plumage)': 'squawkabilly-yellow-plumage',
    'Mabosstiff': 'mabosstiff', 'Baxcalibur': 'baxcalibur',
}
# Per-sprite choices, all read off the review sheet. `sheet` picks which
# photo's instance to cut when several are complete (prefer uniform glare
# over a glare EDGE - a uniform haze subtracts cleanly, an edge does not);
# `fixed` uses the fixed tile box + background field (tile edge lost in
# glare); the rest are segment_v5 overrides.
CHOICES = {
    'Wigglytuff':     dict(fixed=True),
    'Persian':        dict(fixed=True),
    'Alolan Persian': dict(fixed=True, strip_bg=False),          # blue-grey fur ~ glare navy
    'Rillaboom':      dict(fixed=True, hole_max=400, dist_thr=30),  # dark belly ~ glare navy
    'Cinderace':      dict(fixed=True),
    'Inteleon':       dict(fixed=True, strip_bg=False, dist_thr=30, close_iter=3),  # body IS tile navy
    'Baxcalibur':     dict(sheet=1, bg_field=True, dist_thr=30, strip_bg=False),   # glare edge; dark body
    'Pawmot':         dict(sheet=1), 'Arboliva': dict(sheet=1),
    'Squawkabilly (Green Plumage)': dict(sheet=1), 'Squawkabilly (Yellow Plumage)': dict(sheet=1),
}
FIXED_BOX = (7, 7, 115, 115)   # median detected tile box over the rectified cells


# ---- 1. rectify -------------------------------------------------------------
def _tile_centroids(im, scale=0.5):
    small = cv2.resize(im, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA).astype(np.float32)
    B, G, R = small[..., 0], small[..., 1], small[..., 2]
    s = B - (R + G) / 2
    lum = small.mean(2)
    sb = s - cv2.GaussianBlur(s, (0, 0), 40)
    lb = lum - cv2.GaussianBlur(lum, (0, 0), 40)
    page = (s > 25) & (lb > 6) & (sb > 0)
    tilemask = ndi.binary_fill_holes(ndi.binary_opening((s > 15) & ~page, np.ones((5, 5))))
    lab, k = ndi.label(tilemask)
    cents = []
    for j, sl in enumerate(ndi.find_objects(lab), 1):
        h = sl[0].stop - sl[0].start; w = sl[1].stop - sl[1].start
        if not (40 <= h <= 200 and 40 <= w <= 200) or abs(h - w) > 0.3 * max(h, w): continue
        comp = lab[sl] == j
        if comp.sum() < 0.6 * h * w: continue
        cents.append(((sl[1].start + sl[1].stop) / 2 / scale, (sl[0].start + sl[0].stop) / 2 / scale))
    return np.array(cents, np.float32)


def _fit_lattice(xy):
    d = np.sqrt(((xy[:, None, :] - xy[None, :, :]) ** 2).sum(2)); np.fill_diagonal(d, 1e9)
    pitch = np.median(d.min(1))
    def cluster(v):
        idx = np.zeros(len(v), int); groups = []
        for i in np.argsort(v):
            if groups and abs(v[i] - np.mean(v[groups[-1]])) < 0.5 * pitch: groups[-1].append(i)
            else: groups.append([i])
        for g, members in enumerate(groups):
            for i in members: idx[i] = g
        return idx
    src = np.stack([cluster(xy[:, 0]), cluster(xy[:, 1])], 1).astype(np.float32)
    keep = np.ones(len(xy), bool)
    for _ in range(4):
        H, _ = cv2.findHomography(src[keep], xy[keep], 0)
        err = np.linalg.norm(cv2.perspectiveTransform(src.reshape(-1, 1, 2), H).reshape(-1, 2) - xy, axis=1)
        keep = err < 0.15 * pitch
    # re-derive indices from the fit (tilt can merge rows/cols in the clustering)
    src = np.round(cv2.perspectiveTransform(xy.reshape(-1, 1, 2), np.linalg.inv(H)).reshape(-1, 2)).astype(np.float32)
    for _ in range(3):
        H, _ = cv2.findHomography(src[keep], xy[keep], 0)
        err = np.linalg.norm(cv2.perspectiveTransform(src.reshape(-1, 1, 2), H).reshape(-1, 2) - xy, axis=1)
        keep = err < 0.06 * pitch
    return H, src[keep], err[keep], pitch


def rectify(path, extra=2):
    """Photo -> (rectified RGB ndarray, info). Landscape photos are rotated
    so the grid reads top-to-bottom (the phone was held sideways)."""
    im = cv2.imread(path)
    if im.shape[1] > im.shape[0]:
        im = cv2.rotate(im, cv2.ROTATE_90_COUNTERCLOCKWISE)
    cents = _tile_centroids(im)
    H, latt, err, pitch = _fit_lattice(cents)
    cmin, rmin = latt.min(0); cmax, rmax = latt.max(0)
    ncols, nrows = int(cmax - cmin) + 1, int(rmax - rmin) + 1
    S = np.array([[PITCH, 0, (0.5 - cmin + extra) * PITCH],
                  [0, PITCH, (0.5 - rmin + extra) * PITCH], [0, 0, 1]], np.float64)
    W, Hh = (ncols + 2 * extra) * PITCH, (nrows + 2 * extra) * PITCH
    rect = cv2.warpPerspective(im, S @ np.linalg.inv(H), (W, Hh), flags=cv2.INTER_AREA)
    print(f'  {os.path.basename(path)}: {len(cents)} tiles, pitch {pitch:.0f}px, fit err {np.median(err):.1f}px')
    return cv2.cvtColor(rect, cv2.COLOR_BGR2RGB)


# ---- 2. classify --------------------------------------------------------------
def classify(cell):
    a = cell.astype(np.float32); H, W, _ = a.shape
    border = np.zeros((H, W), bool); border[:3, :] = border[-3:, :] = True; border[:, :3] = border[:, -3:] = True
    page = np.median(a[border], 0)
    if page[2] - max(page[0], page[1]) < 15 or page.mean() < 40: return False
    notpage = ndi.binary_opening(np.sqrt(((a - page) ** 2).sum(2)) > 38, np.ones((3, 3)))
    lab, k = ndi.label(notpage)
    if k == 0: return False
    sizes = ndi.sum(notpage, lab, range(1, k + 1))
    tile = ndi.binary_fill_holes(lab == int(np.argmax(sizes)) + 1)
    ys, xs = np.where(tile)
    h = ys.max() - ys.min() + 1; w = xs.max() - xs.min() + 1
    if not (0.62 * W <= w <= 0.95 * W and 0.62 * H <= h <= 0.95 * H): return False
    if abs(w - h) > 0.12 * max(w, h) or tile.sum() < 0.8 * h * w: return False
    if ys.min() < 2 or xs.min() < 2 or ys.max() > H - 3 or xs.max() > W - 3: return False
    med = np.median(a[ndi.binary_erosion(tile, iterations=6)], 0)
    return med[2] - max(med[0], med[1]) >= 10


def grid_cells(rect):
    """-> dict (row, col) -> (cell ndarray, complete?) for the ten grid columns."""
    H, W, _ = rect.shape
    nr, nc = H // PITCH, W // PITCH
    # the ten grid columns are the run of columns with the most complete tiles
    ok = np.zeros((nr, nc), bool)
    cells = {}
    for r in range(nr):
        for c in range(nc):
            cell = rect[r * PITCH:(r + 1) * PITCH, c * PITCH:(c + 1) * PITCH]
            cells[(r, c)] = cell; ok[r, c] = classify(cell)
    colsum = ok.sum(0)
    c0 = max(range(nc - COLS + 1), key=lambda c: colsum[c:c + COLS].sum())
    return {(r, c - c0): (cells[(r, c)], bool(ok[r, c])) for r in range(nr) for c in range(c0, c0 + COLS)}


# ---- 3. align -----------------------------------------------------------------
def desc(cell, b=12):
    c = np.asarray(Image.fromarray(cell[b:-b, b:-b]).resize((48, 48), Image.LANCZOS)).astype(np.float32) / 255.
    return ((c - c.mean()) / (c.std() + 1e-6)).ravel()


def align(sheets):
    """sheets: list of grid dicts. -> list of global row offsets (sheet row r
    is global row r + off), chained from pairwise best offsets."""
    D = [{k: desc(cell) for k, (cell, ok) in g.items() if ok} for g in sheets]
    def best(a, b):
        top = None
        for off in range(-14, 15):
            sims = [float(np.dot(d, D[b][(r + off, c)])) / len(d) for (r, c), d in D[a].items() if (r + off, c) in D[b]]
            if len(sims) >= 8 and (top is None or np.mean(sims) > top[0]): top = (float(np.mean(sims)), off)
        return top
    n = len(sheets); off = {0: 0}; placed = {0}
    while len(placed) < n:
        cand = []
        for a in placed:
            for b in range(n):
                if b in placed: continue
                t = best(a, b)
                if t: cand.append((t[0], a, b, t[1]))
        cand.sort(reverse=True)
        s, a, b, o = cand[0]
        if s < 0.8: raise SystemExit(f'no confident overlap for sheet {b} (best {s:.2f})')
        off[b] = off[a] - o          # a row r == b row r+o  ->  G = r_a + off_a = r_b - o + off_a
        placed.add(b)
    return [off[i] for i in range(n)]


# ---- 5. segment -----------------------------------------------------------------
def _masked_median(a, mask, wins):
    out = np.full_like(a, np.nan)
    src = np.where(mask[..., None], a, np.nan)
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        for win in wins:
            for ch in range(3):
                est = ndi.generic_filter(src[..., ch], np.nanmedian, size=win, mode='nearest')
                fill = np.isnan(out[..., ch]); out[..., ch][fill] = est[fill]
    return out


def _find_tile(a, dpage, tile_box):
    H, W, _ = a.shape
    if tile_box is not None:
        x0, y0, x1, y1 = tile_box
        tile = np.zeros((H, W), bool); tile[y0:y1, x0:x1] = True
        return tile
    notpage = ndi.binary_opening(dpage > 38, np.ones((3, 3)))
    lab, k = ndi.label(notpage)
    if k == 0: return None
    sz = ndi.sum(notpage, lab, range(1, k + 1))
    cy, cx = H / 2, W / 2; best = None
    for j in range(1, k + 1):
        if sz[j - 1] < 0.15 * H * W: continue
        yy, xx = np.where(lab == j); dc = np.hypot(yy.mean() - cy, xx.mean() - cx)
        if best is None or dc < best[0]: best = (dc, j)
    if best is None: best = (0, int(np.argmax(sz)) + 1)
    return ndi.binary_fill_holes(lab == best[1])


def _core(a, tile, page, dpage, bg0, bg, dist_thr, dark_off, close_iter, edge_px, strip_bg, hole_max):
    """segment_v4's foreground logic against a background `bg` (1x1x3 or HxWx3)."""
    H, W, _ = a.shape
    ys, xs = np.where(tile); ty0, ty1, tx0, tx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    dom = a[..., 2] - np.maximum(a[..., 0], a[..., 1]); lum = a.mean(2)
    bgdom = bg[..., 2] - np.maximum(bg[..., 0], bg[..., 1]); bglum = bg.mean(2)
    d = np.sqrt(((a - bg) ** 2).sum(2) + (dom - bgdom) ** 2)
    inner = ndi.binary_erosion(tile, np.ones((3, 3)), iterations=1)
    edgezone = tile & ~ndi.binary_erosion(tile, np.ones((3, 3)), iterations=8)
    ringlike = (dpage < 0.75 * np.linalg.norm(bg0 - page)) & edgezone
    ringlike = ndi.binary_dilation(ringlike, np.ones((3, 3)), iterations=1) & edgezone
    # photographed edge highlight: lighter, still blue-dominant, hugging the
    # tile edge - in a photo it can be brighter than the page, which the v4
    # ring test ("between navy and page") lets through
    ez2 = tile & ~ndi.binary_erosion(tile, np.ones((3, 3)), iterations=edge_px)
    ringlike |= ez2 & (dom > 30) & (lum > bglum + 8)
    fg = ((d > dist_thr) | (lum < bglum - dark_off)) & inner & (dpage > 30) & ~ringlike
    for x in list(range(tx0, min(tx0 + 4, W))) + list(range(max(tx1 - 4, 0), tx1)):
        if fg[ty0:ty1, x].mean() > 0.75: fg[:, x] = False
    for y in list(range(ty0, min(ty0 + 4, H))) + list(range(max(ty1 - 4, 0), ty1)):
        if fg[y, tx0:tx1].mean() > 0.75: fg[y, :] = False
    fg = ndi.binary_fill_holes(ndi.binary_closing(fg, np.ones((3, 3)), iterations=close_iter)) & inner
    lab2, k2 = ndi.label(fg)
    if k2 == 0: return None
    objs = ndi.find_objects(lab2); sizes = ndi.sum(fg, lab2, range(1, k2 + 1)); biggest = float(sizes.max())
    IH, IW = ty1 - ty0, tx1 - tx0
    keep = np.zeros_like(fg)
    for j in range(1, k2 + 1):
        sl = objs[j - 1]; hh = sl[0].stop - sl[0].start; ww = sl[1].stop - sl[1].start
        touches = (sl[0].start <= ty0 + 2 or sl[0].stop >= ty1 - 2 or sl[1].start <= tx0 + 2 or sl[1].stop >= tx1 - 2)
        nearedge = (sl[0].start <= ty0 + edge_px or sl[0].stop >= ty1 - edge_px or sl[1].start <= tx0 + edge_px or sl[1].stop >= tx1 - edge_px)
        ar = max(hh, ww) / max(1, min(hh, ww))
        if sizes[j - 1] < 20: continue
        if touches and ar >= 5 and sizes[j - 1] < 0.08 * biggest: continue
        if touches and ((ww <= 6 and hh > 0.55 * IH) or (hh <= 6 and ww > 0.55 * IW)): continue
        if touches and min(hh, ww) <= 3: continue
        if nearedge and sizes[j - 1] < 0.08 * biggest and np.median(dom[lab2 == j]) > 25: continue
        keep |= (lab2 == j)
    if not keep.any(): keep = (lab2 == int(np.argmax(sizes)) + 1)
    keep = ndi.binary_fill_holes(keep)
    if strip_bg:
        keep &= ~((d < 24) & (lum > bglum - 12))
        holes = ndi.binary_fill_holes(keep) & ~keep
        hl, hk = ndi.label(holes)
        if hk:
            hs = ndi.sum(holes, hl, range(1, hk + 1))
            for j in range(1, hk + 1):
                if hs[j - 1] <= hole_max: keep |= (hl == j)
    soft = np.clip((d - 28) / 22, 0, 1)
    alpha = np.maximum(keep.astype(np.float32), soft * ndi.binary_dilation(keep, np.ones((3, 3)), iterations=1))
    alpha[~tile] = 0; alpha[dpage <= 30] = 0; alpha[ringlike & ~keep] = 0
    return alpha, (int(tx0), int(ty0), int(tx1), int(ty1))


def segment_v5(a, dist_thr=42, dark_off=30, close_iter=2, tile_box=None, bg_field=False,
               edge_px=6, field_win=9, strip_bg=True, hole_max=30):
    """v4 for photo cells. tile_box: fixed tile rectangle when the tile edge
    is lost in glare. bg_field: per-pixel background (masked median) so a
    glare band is subtracted, not segmented - two passes, the second field
    estimated only from pixels outside the first pass's sprite (the first
    lets blue-grey fur / dark purple hide in it). strip_bg/hole_max: v4's
    "strip tile-coloured pixels" can be switched off for a sprite that IS
    navy or is enclosed by its outline. Returns (RGBA, info) or None; info
    carries `bg` (scalar or per-pixel, over the bbox) for dehaze()."""
    a = np.asarray(a).astype(np.float32); H, W, _ = a.shape
    border = np.zeros((H, W), bool); border[:3, :] = border[-3:, :] = True; border[:, :3] = border[:, -3:] = True
    page = np.median(a[border], 0)
    dpage = np.sqrt(((a - page) ** 2).sum(2))
    tile = _find_tile(a, dpage, tile_box)
    if tile is None: return None
    if tile_box is not None: dpage = np.where(tile, 1e3, dpage)   # glare makes the page test meaningless
    band = ndi.binary_erosion(tile, np.ones((3, 3)), iterations=2) & ~ndi.binary_erosion(tile, np.ones((3, 3)), iterations=8)
    bg0 = np.median(a[band], 0) if band.sum() > 200 else np.median(a[tile], 0)
    args = (dist_thr, dark_off, close_iter, edge_px, strip_bg, hole_max)
    if not bg_field:
        res = _core(a, tile, page, dpage, bg0, bg0[None, None, :], *args); haze = bg0
    else:
        dom = a[..., 2] - np.maximum(a[..., 0], a[..., 1]); lum = a.mean(2)
        inner_t = ndi.binary_erosion(tile, np.ones((3, 3)), iterations=3)
        # absolute floors: under glare bg0 is the bright band, and the
        # un-glared navy elsewhere in the tile must stay in the mask
        mask = inner_t & (dom > 25) & (lum > NAVY.mean() - 25) & (a[..., 2] >= a[..., 0] + 20)
        mask &= ~ndi.binary_dilation(lum < NAVY.mean() - 25, np.ones((3, 3)), iterations=1)
        bgf = _masked_median(a, mask, (field_win, 3 * field_win))
        bgf[np.isnan(bgf)] = np.broadcast_to(bg0, a.shape)[np.isnan(bgf)]
        res = _core(a, tile, page, dpage, bg0, bgf, *args)
        if res is None: return None
        bgm = tile & ~ndi.binary_dilation(res[0] > 0, np.ones((3, 3)), iterations=3) & (lum > NAVY.mean() - 25)
        bgf2 = _masked_median(a, bgm, (11, 45))
        bgf2[np.isnan(bgf2)] = np.broadcast_to(bg0, a.shape)[np.isnan(bgf2)]
        res = _core(a, tile, page, dpage, bg0, bgf2, *args); haze = bgf2
    if res is None: return None
    alpha, tbox = res
    ys, xs = np.where(alpha > 0.35)
    if len(ys) == 0: return None
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    out = np.dstack([a.astype(np.uint8), (alpha * 255).astype(np.uint8)])[y0:y1, x0:x1]
    tx0, ty0, tx1, ty1 = tbox
    info = dict(tile=tbox, bbox=(int(x0), int(y0), int(x1), int(y1)),
                touch=(int(x0 <= tx0 + 1), int(x1 >= tx1 - 1), int(y0 <= ty0 + 1), int(y1 >= ty1 - 1)),
                bg=haze[y0:y1, x0:x1] if np.ndim(haze) == 3 else haze)
    return out, info


def dehaze(rgba, bg, navy=NAVY):
    """Undo screen glare, hue-preserving: treat it as an additive luminance
    haze h(x,y) = bg_lum - navy_lum and subtract it from every channel. (A
    per-channel affine fit needs a second colour anchor - "white" - that not
    every sprite has, and guessing one tints the sprite.)"""
    a = rgba.astype(np.float32); rgb = a[..., :3]; al = a[..., 3]
    bg = np.broadcast_to(np.asarray(bg, np.float32), rgb.shape) if np.ndim(bg) == 1 else bg
    h = bg.mean(2) - navy.mean()
    if np.abs(h).max() < 12: return rgba          # clean capture: leave alone
    true = rgb - np.clip(h, 0, None)[..., None]
    return np.dstack([np.clip(true, 0, 255).astype(np.uint8), al.astype(np.uint8)])


def usable(cell):
    """An incomplete cell we can still cut with the fixed box: page-blue
    border (not bezel/black) and a navy-ish tile interior band."""
    a = cell.astype(np.float32); H, W, _ = a.shape
    border = np.zeros((H, W), bool); border[:3, :] = border[-3:, :] = True; border[:, :3] = border[:, -3:] = True
    p = np.median(a[border], 0)
    x0, y0, x1, y1 = FIXED_BOX
    t = np.zeros((H, W), bool); t[y0:y1, x0:x1] = True
    band = ndi.binary_erosion(t, iterations=3) & ~ndi.binary_erosion(t, iterations=10)
    b = np.median(a[band], 0)
    return p.mean() > 40 and p[2] - max(p[0], p[1]) > 10 and b[2] - max(b[0], b[1]) > 10


def glare_spread(cell):
    """90-10 percentile luminance spread of the tile-edge band: high = a
    glare EDGE crosses the tile (uniform glare is fine, an edge is not)."""
    lum = cell.astype(np.float32).mean(2)
    t = np.zeros(lum.shape, bool); t[7:115, 7:115] = True
    band = ndi.binary_erosion(t, iterations=3) & ~ndi.binary_erosion(t, iterations=10)
    v = lum[band]; return float(np.percentile(v, 90) - np.percentile(v, 10))


# ---- main --------------------------------------------------------------------------
def main(paths):
    print('rectifying')
    sheets = [grid_cells(rectify(p)) for p in paths]
    offs = align(sheets)
    order = sorted(range(len(sheets)), key=lambda i: offs[i])
    print('sheet order (first to last):', [os.path.basename(paths[i]) for i in order], 'offsets', offs)
    # global grid: (G, c) -> [(sheet index, row, cell, complete)]
    inst = {}
    for i, g in enumerate(sheets):
        for (r, c), (cell, ok) in g.items():
            inst.setdefault((r + offs[i], c), []).append((i, r, cell, ok))
    gmin = min(G for (G, c), L in inst.items() if any(t[3] for t in L))
    gmax = max(G for (G, c), L in inst.items() if any(t[3] for t in L))
    lastrow = [c for c in range(COLS) if any(t[3] for t in inst.get((gmax, c), []))]
    total = (gmax - gmin) * COLS + len(lastrow)
    print(f'{gmax - gmin + 1} rows, last row has {len(lastrow)} tiles -> {total} cells')

    man = json.load(open(os.path.join(OUT, 'manifest.json')))
    old = [s['displayName'] for s in man['sprites']]
    ins = dict(INSERTIONS)
    seq = []
    for n in old:
        seq.append((n, False))
        for x in ins.get(n, []): seq.append((x, True))
    if len(seq) != total:
        raise SystemExit(f'expected {len(seq)} cells from manifest + INSERTIONS, grid has {total}')
    new_names = [n for n, new in seq if new]
    print(f'{len(old)} known + {len(new_names)} inserted = {len(seq)}')

    vdir = os.path.join(OUT, '_verification'); os.makedirs(vdir, exist_ok=True)
    scale = 3; P = PITCH * scale; cols = 6; rows = (len(new_names) + cols - 1) // cols
    review = Image.new('RGB', (cols * P, rows * (P + 16)), (255, 0, 255)); dr = ImageDraw.Draw(review)
    entries = []
    for i, (name, new) in enumerate(seq):
        if not new: continue
        G, c = divmod(i, COLS); G += gmin
        L = inst[(G, c)]
        ch = CHOICES.get(name, {})
        opts = {k: v for k, v in ch.items() if k not in ('sheet', 'fixed')}
        if ch.get('fixed'):
            # no complete instance anywhere: take the least-spread incomplete one
            cand = sorted([t for t in L if usable(t[2])], key=lambda t: glare_spread(t[2]))
            opts.update(tile_box=FIXED_BOX, bg_field=True)
        else:
            cand = sorted([t for t in L if t[3]], key=lambda t: glare_spread(t[2]))
        if 'sheet' in ch:
            # CHOICES['sheet'] indexes the chronological order (0 = first sheet)
            si = order[ch['sheet']]
            pick = [t for t in L if t[0] == si and (t[3] or (ch.get('fixed') and usable(t[2])))]
            if pick: cand = pick + cand
        if not cand: raise SystemExit(f'{name}: no usable cell')
        si, r, cell, ok = cand[0]
        res = segment_v5(cell, **opts)
        if res is None: raise SystemExit(f'{name}: segmentation failed')
        rgba, info = res
        rgba = dehaze(rgba, info['bg'])
        Image.fromarray(rgba, 'RGBA').save(os.path.join(OUT, f'{name}.png'))
        entries.append((name, rgba.shape[1], rgba.shape[0]))
        k = len(entries) - 1
        big = Image.fromarray(rgba, 'RGBA').resize((rgba.shape[1] * scale, rgba.shape[0] * scale), Image.NEAREST)
        x, y = (k % cols) * P, (k // cols) * (P + 16)
        review.paste(big, (x + (P - big.width) // 2, y + (P - big.height) // 2), big)
        dr.text((x + 4, y + P), f'{name}  sheet {order.index(si)+1} r{r} c{c}', fill=(0, 0, 0))
        print(f'  {name:32s} sheet {order.index(si)+1} row {r} col {c}  {rgba.shape[1]}x{rgba.shape[0]}  touch {info["touch"]}')
    review.save(os.path.join(vdir, 'mc_new.png'))

    # manifest: old entries keep their data, renumbered into the new order
    byname = {s['displayName']: s for s in man['sprites']}
    pack = {}
    try:
        pack = {p['id']: p for p in json.load(open(os.path.join(ROOT, 'assets', 'data', 'pokedex.json')))['species']}
    except Exception:
        pass
    sprites = []
    for i, (name, new) in enumerate(seq, 1):
        if not new:
            s = dict(byname[name]); s['order'] = i
        else:
            fid = FORM_IDS[name]; w, h = next((w, h) for n, w, h in entries if n == name)
            p = pack.get(fid)
            s = dict(order=i, file=f'{name}.png', displayName=name, formId=fid, packSpeciesId=fid,
                     inDataPack=bool(p), width=w, height=h, types=(p or {}).get('types', []))
        sprites.append(s)
    man.update(source=man['source'] + ' + RegulationMC1 (2)-(6).jpeg (M-C additions, photos of the screen)',
               count=len(sprites),
               segmentation=man['segmentation'] + '; v5 (2026-09-14) for the 27 M-C cells: photo rectification, '
                                                  'glare background field, dehaze - see tool/split_photo_sheets.py')
    man['sprites'] = sprites
    json.dump(man, open(os.path.join(OUT, 'manifest.json'), 'w'), indent=1)
    print(f'wrote {len(entries)} sprites, manifest now {len(sprites)} entries; review {vdir}/mc_new.png')


if __name__ == '__main__':
    main(sys.argv[1:] or sorted(__import__('glob').glob(os.path.join(ROOT, 'images', 'RegulationMC1 (*.jpeg'))))
