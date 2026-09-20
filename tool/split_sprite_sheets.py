#!/usr/bin/env python3
"""Turn photos of the in-game "Eligible Pokemon" grid into one named,
background-removed PNG per Pokemon.

    python3 tool/split_sprite_sheets.py images/RegulationMBPokemon*.png

What it does, and why each step exists:

 1. FIT THE GRID. The captures are photos of a screen, so they carry a
    lighting gradient and a little keystone. Tiles are a darker navy than the
    page behind them, so the *gaps* are the bright lines: fit a comb to the
    blue-dominance profile, forcing the row pitch to equal the column pitch
    (the tiles are square). Fitting rows independently drifts half a tile by
    the bottom of the sheet.

 2. DE-DUPLICATE. Consecutive captures overlap by however far the list was
    scrolled. Compare the tail rows of sheet N against the head rows of N+1
    and drop the repeat.

 3. SEGMENT (v4). Per cell, FIND THE TILE (the navy rounded square; the gap
    around it is a brighter blue) instead of assuming a fixed margin — the
    tiles are not centred in their cells, and a fixed margin clipped Slowbro,
    Skeledirge, Snorlax and thirty others. Background colour = median of a
    band just inside the tile edge (a whole-tile median drifts toward a big
    sprite). Distance adds a blue-dominance channel so a dark teal (Snorlax's
    back) separates from navy. Interiors are filled, then anything that IS
    the tile colour is stripped back out (a sprite touching the edge twice
    otherwise gets tile background painted in between).

 4. NAME. The list is in National Dex order, so align it against the data
    pack sorted the same way. Champions lists some forms separately that the
    pack collapses (the appliance Rotoms, Gourgeist sizes, Lycanroc forms,
    Meowstic and Basculegion females) — those show up as insertions, and the
    alignment only closes one way. Verify with `_verification/` contact sheets
    before trusting the output.

Writes `pokemon2Dsprites/<Display Name>.png` plus a manifest.json.
Then run `tool/build_champions_atlas.py`.
"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'pokemon2Dsprites')
COLS = 10                      # the grid is ten wide
PITCH_RANGE = (112, 132)       # px, at the capture sizes seen so far
MARGIN = 0.135                 # fraction of a cell that is tile border


def blue_dominance(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    s = a[..., 2] - a[..., :2].mean(2)          # page ~147, tile ~124
    from PIL import ImageFilter
    blur = np.asarray(Image.fromarray(s.astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(25))).astype(np.float32)
    return s - blur, a


def fit_comb(profile, lo, hi, step=0.05):
    """Pitch + phase whose sample points sit on the *brightest* lines."""
    best = None
    n = len(profile)
    for p in np.arange(lo, hi, step):
        for o in np.arange(0, p, 0.5):
            idx = np.arange(o, n - 1, p)
            if len(idx) < 4:
                continue
            v = np.interp(idx, np.arange(n), profile).mean()
            if best is None or v > best[0]:
                best = (v, p, o)
    return best


def grid_of(path):
    s, _ = blue_dominance(path)
    h, w = s.shape
    _, pitch, phase = fit_comb(np.median(s, 0), *PITCH_RANGE)
    xs = []
    x = phase % pitch
    while x - pitch > -2:
        x -= pitch
    while x < w:
        xs.append(x)
        x += pitch
    # Rows: same pitch (square tiles), phase fitted in the tile side margins
    # where sprites almost never reach.
    cols = []
    for i in range(len(xs) - 1):
        l, r = int(xs[i]), int(xs[i + 1])
        cols += [j for j in range(l + int(.10 * pitch), l + int(.22 * pitch)) if 0 <= j < w]
        cols += [j for j in range(l + int(.78 * pitch), l + int(.90 * pitch)) if 0 <= j < w]
    row_prof = np.median(s[:, cols], 1)
    best = None
    for pr in np.arange(pitch - 3, pitch + 3, 0.05):
        for o in np.arange(0, pr, 0.5):
            idx = np.arange(o, h - 1, pr)
            if len(idx) < 3:
                continue
            v = np.interp(idx, np.arange(h), row_prof).mean()
            if best is None or v > best[0]:
                best = (v, pr, o)
    return pitch, phase, best[1], best[2]


def cells(path):
    cp, co, rp, ro = grid_of(path)
    im = Image.open(path).convert('RGB')
    w, h = im.size
    def lines(pitch, phase, limit):
        v, out = phase % pitch, []
        while v - pitch > -2:
            v -= pitch
        while v < limit:
            out.append(v)
            v += pitch
        return out
    xs, ys = lines(cp, co, w), lines(rp, ro, h)
    out = []
    for ri in range(len(ys) - 1):
        if ys[ri] < -1 or ys[ri + 1] > h + 1:
            continue
        row = []
        for ci in range(len(xs) - 1):
            if xs[ci] < -1 or xs[ci + 1] > w + 1:
                continue
            row.append(im.crop((int(round(xs[ci])), int(round(ys[ri])),
                                int(round(xs[ci + 1])), int(round(ys[ri + 1])))))
        if len(row) == COLS:
            out.append(row)
    return out


def desc(cell):
    a = np.asarray(cell.convert('RGB')).astype(np.float32)
    b = int(.10 * a.shape[0])
    c = np.asarray(Image.fromarray(a[b:-b, b:-b].astype(np.uint8))
                   .resize((48, 48), Image.LANCZOS)).astype(np.float32) / 255.
    return ((c - c.mean()) / (c.std() + 1e-6)).ravel()


def segment(cell):
    """v4: see segment_v4 below. Returns an RGBA PIL image or None."""
    a = np.asarray(cell.convert('RGB'))
    res = segment_v4(a)
    if res is None:
        return None
    out, _ = res
    return Image.fromarray(out, 'RGBA')


def segment_v4(a, dist_thr=42, dark_off=30, close_iter=2, debug=False):
    a=np.asarray(a).astype(np.float32); H,W,_=a.shape
    # 1. page (gap) colour from the cell's outer border
    border=np.zeros((H,W),bool); border[:3,:]=border[-3:,:]=True; border[:,:3]=border[:,-3:]=True
    page=np.median(a[border],0)
    dpage=np.sqrt(((a-page)**2).sum(2))
    notpage=dpage>38
    notpage=ndi.binary_opening(notpage,np.ones((3,3)))
    lab,k=ndi.label(notpage)
    if k==0: return None
    sz=ndi.sum(notpage,lab,range(1,k+1))
    # the tile is the large component nearest the cell centre
    cy,cx=H/2,W/2; best=None
    for j in range(1,k+1):
        if sz[j-1]<0.15*H*W: continue
        yy,xx=np.where(lab==j); dc=np.hypot(yy.mean()-cy,xx.mean()-cx)
        if best is None or dc<best[0]: best=(dc,j)
    if best is None: best=(0,int(np.argmax(sz))+1)
    tile=ndi.binary_fill_holes(lab==best[1])
    ys,xs=np.where(tile); ty0,ty1,tx0,tx1=ys.min(),ys.max()+1,xs.min(),xs.max()+1
    # 2. tile background = median of a 6px band just inside the tile edge
    #    (skipping the outer 2px highlight). Whole-tile medians drift toward
    #    the sprite when it is large — Camerupt pulled R from 44 to 70.
    band=ndi.binary_erosion(tile,np.ones((3,3)),iterations=2)&~ndi.binary_erosion(tile,np.ones((3,3)),iterations=8)
    bg=np.median(a[band],0) if band.sum()>200 else np.median(a[tile],0)
    dom=a[...,2]-np.maximum(a[...,0],a[...,1]); bgdom=bg[2]-max(bg[0],bg[1])
    d=np.sqrt(((a-bg)**2).sum(2)+(dom-bgdom)**2)
    lum=a.mean(2); bglum=bg.mean()
    inner=ndi.binary_erosion(tile,np.ones((3,3)),iterations=1)
    # The tile's edge highlight is a *lighter, equally blue-dominant* navy.
    # Sprite blues carry far more green (Vaporeon, Azumarill, even Metagross),
    # so "as blue-dominant as the tile but brighter" is ring/page, never sprite.
    # Adaptive: anything within 8px of the tile boundary whose colour is at
    # least a quarter of the way from tile-navy toward page-blue. Every
    # sprite blue in the roster (Azumarill, Vaporeon, Glaceon, Metagross) is
    # far further from the page colour than that.
    edgezone=tile&~ndi.binary_erosion(tile,np.ones((3,3)),iterations=8)
    ringlike=(dpage<0.75*np.linalg.norm(bg-page))&edgezone
    ringlike=ndi.binary_dilation(ringlike,np.ones((3,3)),iterations=1)&edgezone
    fg=((d>dist_thr)|(lum<bglum-dark_off))&inner&(dpage>30)&~ringlike
    # tile-edge highlight bars: a full-length line hugging the tile border
    band=4
    for x in list(range(tx0,min(tx0+band,W)))+list(range(max(tx1-band,0),tx1)):
        col=fg[ty0:ty1,x]
        if col.mean()>0.75: fg[:,x]=False
    for y in list(range(ty0,min(ty0+band,H)))+list(range(max(ty1-band,0),ty1)):
        row=fg[y,tx0:tx1]
        if row.mean()>0.75: fg[y,:]=False
    fg=ndi.binary_fill_holes(ndi.binary_closing(fg,np.ones((3,3)),iterations=close_iter))&inner
    lab2,k2=ndi.label(fg)
    if k2==0: return None
    objs=ndi.find_objects(lab2); sizes=ndi.sum(fg,lab2,range(1,k2+1)); biggest=float(sizes.max())
    IH,IW=ty1-ty0,tx1-tx0
    keep=np.zeros_like(fg)
    for j in range(1,k2+1):
        sl=objs[j-1]; hh=sl[0].stop-sl[0].start; ww=sl[1].stop-sl[1].start
        touches=(sl[0].start<=ty0+2 or sl[0].stop>=ty1-2 or sl[1].start<=tx0+2 or sl[1].stop>=tx1-2)
        ar=max(hh,ww)/max(1,min(hh,ww))
        if sizes[j-1]<20: continue
        if touches and ar>=5 and sizes[j-1]<0.08*biggest: continue
        if touches and ((ww<=6 and hh>0.55*IH) or (hh<=6 and ww>0.55*IW)): continue
        if touches and min(hh,ww)<=3: continue
        keep|=(lab2==j)
    if not keep.any(): keep=(lab2==int(np.argmax(sizes))+1)
    keep=ndi.binary_fill_holes(keep)
    # A sprite touching the tile edge in two places turns the tile background
    # between those contacts into an enclosed "hole" that fill_holes paints
    # in. Pixels that ARE the tile colour are never sprite (nothing in the
    # roster is that exact navy — Metagross and Garchomp both sit >90 away),
    # so strip them and re-fill only tiny specks (anti-aliasing, scanlines).
    bgpix=(d<24)&(lum>bglum-12)
    keep&=~bgpix
    holes=ndi.binary_fill_holes(keep)&~keep
    hl,hk=ndi.label(holes)
    if hk:
        hs=ndi.sum(holes,hl,range(1,hk+1))
        for j in range(1,hk+1):
            if hs[j-1]<=30: keep|=(hl==j)
    soft=np.clip((d-28)/22,0,1)
    alpha=np.maximum(keep.astype(np.float32), soft*ndi.binary_dilation(keep,np.ones((3,3)),iterations=1))
    alpha[~tile]=0; alpha[dpage<=30]=0; alpha[ringlike&~keep]=0
    ys,xs=np.where(alpha>0.35)
    if len(ys)==0: return None
    y0,y1,x0,x1=ys.min(),ys.max()+1,xs.min(),xs.max()+1
    out=np.dstack([a.astype(np.uint8),(alpha*255).astype(np.uint8)])[y0:y1,x0:x1]
    info=dict(tile=(int(tx0),int(ty0),int(tx1),int(ty1)),bbox=(int(x0),int(y0),int(x1),int(y1)),
              touch_l=int(x0<=tx0+1),touch_r=int(x1>=tx1-1),touch_t=int(y0<=ty0+1),touch_b=int(y1>=ty1-1))
    return out,info


# ---------------------------------------------------------------------------
# Per-sprite re-cuts. segment_v4 is tuned for sprites that stand clear of the
# navy tile. A few are close enough to the tile OR to the lighter page blue
# that v4 punches holes through them: v4 zeroes alpha wherever a pixel is
# within 30 of the PAGE colour (that gate exists to drop the gap around the
# tile), and Sableye's lit purple head (~R80 G59 B231) sits inside it, so the
# 2026-09-06 cut came out as 14 separate holes. Re-cut such sprites here:
#
#     python3 tool/split_sprite_sheets.py --recut Sableye
#
# then rebuild the atlas. `cell` = (sheet number as in the file name, row,
# column) as returned by cells() for that sheet.
RECUTS = {
    'Sableye': dict(cell=(1, 6, 1), method='lowcontrast', thr=18, dark=12),
}


def segment_lowcontrast(a, thr=18, dark=12, soft_lo=6, soft_span=14,
                        hole_max=40, erode_tile=5):
    """For sprites whose colours overlap the tile/page blues (Sableye).

    The tile is flat to +-3 per channel, so instead of v4's coarse
    distance + page-colour gate this keeps anything a modest distance from
    the TILE colour (or darker than it — the outline), restricted to the
    tile interior, then keeps the main blob plus nearby pieces, fills only
    small holes, and never gates on the page colour inside the tile."""
    a = np.asarray(a).astype(np.float32)
    H, W, _ = a.shape
    border = np.zeros((H, W), bool)
    border[:3, :] = border[-3:, :] = True
    border[:, :3] = border[:, -3:] = True
    page = np.median(a[border], 0)
    dpage = np.sqrt(((a - page) ** 2).sum(2))
    notpage = ndi.binary_opening(dpage > 38, np.ones((3, 3)))
    lab, k = ndi.label(notpage)
    if k == 0:
        return None
    sz = ndi.sum(notpage, lab, range(1, k + 1))
    tile = ndi.binary_fill_holes(lab == int(np.argmax(sz)) + 1)
    band = (ndi.binary_erosion(tile, np.ones((3, 3)), iterations=2)
            & ~ndi.binary_erosion(tile, np.ones((3, 3)), iterations=8))
    bg = np.median(a[band], 0)
    d = np.sqrt(((a - bg) ** 2).sum(2))
    lum = a.mean(2)
    inner = ndi.binary_erosion(tile, np.ones((3, 3)), iterations=erode_tile)
    fg = ((d > thr) | (lum < bg.mean() - dark)) & inner
    fg = ndi.binary_opening(fg, np.ones((2, 2)))
    fg = ndi.binary_closing(fg, np.ones((3, 3)), iterations=1) & inner
    lab, k = ndi.label(fg)
    if k == 0:
        return None
    sz = ndi.sum(fg, lab, range(1, k + 1))
    main = int(np.argmax(sz)) + 1
    keep = lab == main
    near = ndi.binary_dilation(keep, np.ones((3, 3)), iterations=4)
    for j in range(1, k + 1):
        if j != main and sz[j - 1] >= 12 and (near & (lab == j)).any():
            keep |= lab == j
    holes = ndi.binary_fill_holes(keep) & ~keep
    hl, hk = ndi.label(holes)
    for j in range(1, hk + 1):
        if (hl == j).sum() <= hole_max:
            keep |= hl == j
    soft = np.clip((d - soft_lo) / soft_span, 0, 1)
    alpha = np.maximum(keep.astype(np.float32),
                       soft * ndi.binary_dilation(keep, np.ones((3, 3)), iterations=1))
    alpha[~inner] = 0
    ys, xs = np.where(alpha > 0.35)
    if len(ys) == 0:
        return None
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    out = np.dstack([a.astype(np.uint8), (alpha * 255).astype(np.uint8)])[y0:y1, x0:x1]
    return out, dict(bbox=(int(x0), int(y0), int(x1), int(y1)))


def recut(name):
    spec = dict(RECUTS[name])
    sheet, row, col = spec.pop('cell')
    method = spec.pop('method')
    path = os.path.join(ROOT, 'images', f'RegulationMBPokemon{sheet}.png')
    a = np.asarray(cells(path)[row][col].convert('RGB'))
    res = (segment_lowcontrast(a, **spec) if method == 'lowcontrast'
           else segment_v4(a, **spec))
    if res is None:
        sys.exit(f'{name}: segmentation failed')
    out, _ = res
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, f'{name}.png'))
    mpath = os.path.join(OUT, 'manifest.json')
    man = json.load(open(mpath))
    for s in man['sprites']:
        if s['displayName'] == name:
            s['height'], s['width'] = int(out.shape[0]), int(out.shape[1])
    json.dump(man, open(mpath, 'w'), indent=1, ensure_ascii=False)
    print(f'{name}: {out.shape[1]}x{out.shape[0]} -> pokemon2Dsprites/{name}.png')


def main(paths):
    sheets = [cells(p) for p in paths]
    seq = list(sheets[0])
    for nxt in sheets[1:]:
        # how many trailing rows of what we have repeat at the head of `nxt`
        best, bestk = -1, 0
        for k in range(1, min(6, len(seq), len(nxt)) + 1):
            sims = [float(np.dot(desc(seq[-k + i][c]), desc(nxt[i][c])) / 6912)
                    for i in range(k) for c in range(COLS)]
            v = float(np.mean(sims))
            if v > best:
                best, bestk = v, k
        print(f'  overlap {bestk} rows (similarity {best:.3f})')
        seq += nxt[bestk:]
    flat = [c for row in seq for c in row]
    print(f'{len(flat)} cells before dropping empties')
    print('Now name them: the list is in National Dex order — align against '
          'assets/data/pokedex.json sorted by dex number and check the '
          'insertions. See the module docstring.')
    os.makedirs(OUT, exist_ok=True)
    for i, c in enumerate(flat, 1):
        s = segment(c)
        if s is not None:
            s.save(os.path.join(OUT, f'_unnamed_{i:03d}.png'))


if __name__ == '__main__':
    if sys.argv[1:2] == ['--recut']:
        for n in sys.argv[2:] or sorted(RECUTS):
            recut(n)
        sys.exit(0)
    main(sys.argv[1:] or sorted(
        __import__('glob').glob(os.path.join(ROOT, 'images', 'RegulationMB*.png'))))
