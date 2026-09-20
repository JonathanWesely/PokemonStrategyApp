#!/usr/bin/env python3
"""Pack `pokemon2Dsprites/` + `pokemontypeimages/badges/` into the two assets
the Flutter matcher loads:

    assets/sprites/champions_atlas.png    32x32 RGBA tile per sprite
    assets/sprites/type_badge_atlas.png   28x28 RGB tile per type
    assets/data/champions_refs.json       index: form -> species, name, types

Tiles are already square-padded and resized, so at runtime a match costs one
image decode and then pure arithmetic — no per-sprite PNG decode, no resample.

    python3 tool/build_champions_atlas.py

Regenerate whenever `pokemon2Dsprites/` changes (a new regulation, new
species). Keep TILE in sync with nothing — the Dart side reads it from the
index — but do re-run `flutter test` afterwards.
"""
import json, math, os, sys, glob
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, 'pokemon2Dsprites')
BADGES = os.path.join(ROOT, 'pokemontypeimages', 'badges')
TILE, COLS = 32, 16
BADGE_TILE, BADGE_COLS = 28, 6

# Every form the game lists separately is its own pack species (since
# 2026-09-06), so a tile's species id is just its form id. Types come from
# the pack — one source of truth for the badge prior.
BASE = {}


def descriptor(rgb, alpha, n):
    """Square-pad to the sprite's own bounding box, then resize to n x n."""
    ys, xs = np.where(alpha > 0.35)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    r = rgb[y0:y1, x0:x1].astype(np.float32)
    w = alpha[y0:y1, x0:x1].astype(np.float32)
    h, wd = w.shape
    s = max(h, wd)
    R = np.zeros((s, s, 3), np.float32)
    A = np.zeros((s, s), np.float32)
    oy, ox = (s - h) // 2, (s - wd) // 2
    R[oy:oy + h, ox:ox + wd] = r
    A[oy:oy + h, ox:ox + wd] = w
    R = np.asarray(Image.fromarray(R.astype(np.uint8)).resize((n, n), Image.LANCZOS))
    A = np.asarray(Image.fromarray((A * 255).astype(np.uint8)).resize((n, n), Image.LANCZOS))
    return np.dstack([R, A]).astype(np.uint8)


def tight(c):
    """Trim a badge pill down to the coloured square icon."""
    c = c.astype(np.float32)
    H, W, _ = c.shape
    ring = np.zeros((H, W), bool)
    ring[:2, :] = ring[-2:, :] = True
    ring[:, :2] = ring[:, -2:] = True
    m = ndi.binary_opening(
        np.sqrt(((c - np.median(c[ring], 0)) ** 2).sum(2)) > 45, np.ones((3, 3)))
    if m.sum() < 30:
        return c
    lab, k = ndi.label(m)
    sz = ndi.sum(m, lab, range(1, k + 1))
    return c[ndi.find_objects(lab)[int(np.argmax(sz))]]


def main():
    manifest_path = os.path.join(SPRITES, 'manifest.json')
    if not os.path.exists(manifest_path):
        sys.exit(f'missing {manifest_path} — run tool/split_sprite_sheets.py first')
    man = json.load(open(manifest_path))['sprites']
    pack_types = {s['id']: s['types'] for s in json.load(
        open(os.path.join(ROOT, 'assets/data/pokedex.json')))['species']}
    pack = set(pack_types)

    rows = math.ceil(len(man) / COLS)
    atlas = np.zeros((rows * TILE, COLS * TILE, 4), np.uint8)
    index, bad = [], []
    for i, m in enumerate(man):
        a = np.asarray(Image.open(os.path.join(SPRITES, m['file'])).convert('RGBA'))
        r, c = divmod(i, COLS)
        atlas[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE] = \
            descriptor(a[..., :3], a[..., 3] / 255., TILE)
        form = m['formId']
        species = BASE.get(form, form)
        if species not in pack:
            bad.append((form, species))
        index.append({'i': i, 'form': form, 'species': species,
                      'name': m['displayName'],
                      'types': pack_types.get(species) or m['types'] or []})
    if bad:
        sys.exit(f'these forms map to species the pack does not have: {bad}')
    uncovered = pack - {e['species'] for e in index}
    if uncovered:
        sys.exit(f'no reference sprite for: {sorted(uncovered)}')

    files = sorted(glob.glob(os.path.join(BADGES, '*.png')))
    brows = math.ceil(len(files) / BADGE_COLS)
    batlas = np.zeros((brows * BADGE_TILE, BADGE_COLS * BADGE_TILE, 3), np.uint8)
    bindex = []
    for i, f in enumerate(files):
        t = os.path.basename(f)[:-4]
        c = tight(np.asarray(Image.open(f).convert('RGB')).astype(float))
        c = np.asarray(Image.fromarray(np.clip(c, 0, 255).astype(np.uint8))
                       .resize((BADGE_TILE, BADGE_TILE), Image.LANCZOS))
        r, cc = divmod(i, BADGE_COLS)
        batlas[r * BADGE_TILE:(r + 1) * BADGE_TILE,
               cc * BADGE_TILE:(cc + 1) * BADGE_TILE] = c
        bindex.append({'i': i, 'type': t[0].upper() + t[1:]})

    os.makedirs(os.path.join(ROOT, 'assets/sprites'), exist_ok=True)
    Image.fromarray(atlas, 'RGBA').save(
        os.path.join(ROOT, 'assets/sprites/champions_atlas.png'), optimize=True)
    Image.fromarray(batlas, 'RGB').save(
        os.path.join(ROOT, 'assets/sprites/type_badge_atlas.png'), optimize=True)
    json.dump({'version': 1, 'tile': TILE, 'cols': COLS,
               'atlas': 'assets/sprites/champions_atlas.png',
               'badgeTile': BADGE_TILE, 'badgeCols': BADGE_COLS,
               'badgeAtlas': 'assets/sprites/type_badge_atlas.png',
               'sprites': index, 'badges': bindex},
              open(os.path.join(ROOT, 'assets/data/champions_refs.json'), 'w'),
              separators=(',', ':'))
    print(f'{len(index)} sprites -> {atlas.shape[1]}x{atlas.shape[0]} atlas, '
          f'{len(bindex)} type badges, {len(pack)} species covered')


if __name__ == '__main__':
    main()
