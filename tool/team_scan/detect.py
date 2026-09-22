"""Template DETECTION for the card-corner sprite icons: no segmentation.

For every reference tile, slide it (at a few display scales) over the icon
window and take the best template-masked NCC. The template's own alpha is
the mask, so nothing depends on separating a white sprite from cream or a
purple one from the card.
"""
import json
import sys
import numpy as np
from PIL import Image
from scipy.signal import fftconvolve
import os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import dart_twin as dt
import proto

MAN = {s['displayName']: (s['width'], s['height'])
       for s in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'pokemon2Dsprites', 'manifest.json')))['sprites']}


def prep_templates(refs, sides):
    """Resize each 32x32 tile to every candidate display SIZE (px of the
    sprite's larger dimension on screen). The game fits each icon into a
    box, so the right size varies per sprite — search them all. Returns a
    flat list of (ref, zero-mean template, mask, n, var)."""
    out = []
    for s, rr, ra in refs:
      for side in sides:
        side = max(6, int(round(side)))
        rgb = np.asarray(Image.fromarray((rr * 255).astype(np.uint8)).resize(
            (side, side), Image.BILINEAR)).astype(np.float32) / 255
        m = np.asarray(Image.fromarray((ra * 255).astype(np.uint8)).resize(
            (side, side), Image.BILINEAR)).astype(np.float32) / 255
        m = (m > 0.5).astype(np.float32)
        n = m.sum()
        if n < 20:
            continue
        mu = (rgb * m[..., None]).reshape(-1, 3).sum(0) / n
        tc = (rgb - mu) * m[..., None]          # zero-mean template under mask
        tvar = (tc ** 2).reshape(-1, 3).sum(0)  # per-channel
        out.append((s, tc, m, n, tvar))
    return out


def detect(window, templates):
    """Best (score, name, species) over all templates and placements."""
    win = window.astype(np.float32) / 255
    best = (-1.0, '?', '?')
    H, W, _ = win.shape
    for s, tc, m, n, tvar in templates:
        th, tw = m.shape
        if th > H or tw > W:
            continue
        num = np.zeros((H - th + 1, W - tw + 1))
        sp = np.zeros_like(num)
        sp2 = np.zeros_like(num)
        corr = np.zeros_like(num)
        ok = True
        for c in range(3):
            if tvar[c] < 1e-6:
                continue
            f = win[..., c]
            mm = m[::-1, ::-1]
            tt = tc[::-1, ::-1, c]
            s_p = fftconvolve(f, mm, mode='valid')
            s_p2 = fftconvolve(f * f, mm, mode='valid')
            s_pt = fftconvolve(f, tt, mode='valid')
            var_p = np.maximum(s_p2 - s_p * s_p / n, 1e-6)
            corr += s_pt / np.sqrt(var_p * tvar[c])
        corr /= 3.0
        j = np.argmax(corr)
        v = corr.flat[j]
        if v > best[0]:
            best = (float(v), s['name'], s['species'])
    return best


def rank(window, templates, top=4):
    # NOTE: templates may hold several scales per ref; keep each ref's best.
    win = window.astype(np.float32) / 255
    H, W, _ = win.shape
    scores = []
    for s, tc, m, n, tvar in templates:
        th, tw = m.shape
        if th > H or tw > W:
            scores.append((-1.0, s['name'], s['species']))
            continue
        corr = None
        for c in range(3):
            if tvar[c] < 1e-6:
                continue
            f = win[..., c]
            mm = m[::-1, ::-1]
            tt = tc[::-1, ::-1, c]
            s_p = fftconvolve(f, mm, mode='valid')
            s_p2 = fftconvolve(f * f, mm, mode='valid')
            s_pt = fftconvolve(f, tt, mode='valid')
            var_p = np.maximum(s_p2 - s_p * s_p / n, 1e-6)
            cc = s_pt / np.sqrt(var_p * tvar[c])
            corr = cc if corr is None else corr + cc
        scores.append((float(np.max(corr)) / 3.0, s['name'], s['species']))
    best = {}
    for v, n_, sp in scores:
        if n_ not in best or v > best[n_][0]:
            best[n_] = (v, n_, sp)
    scores = sorted(best.values(), reverse=True)
    return scores[:top]


def window_of(photo, card):
    x0, y0, x1, y1 = card
    ch, cw = y1 - y0, x1 - x0
    H, W, _ = photo.shape
    return photo[max(0, y0 - int(0.18 * ch)):min(H, y0 + int(0.33 * ch)),
                 max(0, x0 - int(0.005 * cw)):min(W, x0 + int(0.145 * cw))]


if __name__ == '__main__':
    meta, refs = dt.load_refs()
    truth = {'t1_moves': ['Chesnaught', 'Typhlosion', 'Rillaboom', 'Sableye', 'Scolipede', 'Armarouge'],
             't1_stats': ['Chesnaught', 'Typhlosion', 'Rillaboom', 'Sableye', 'Scolipede', 'Armarouge'],
             't2_moves': ['Heat Rotom', 'Charizard', 'Froslass', 'Garchomp', 'Whimsicott', 'Paldean Tauros (Blaze)'],
             't2_stats': ['Heat Rotom', 'Charizard', 'Froslass', 'Garchomp', 'Whimsicott', 'Paldean Tauros (Blaze)']}
    for kbase in [float(a) for a in (sys.argv[1:] or [1.10])]:
        tmpl_sets = None
        ok = 0
        details = []
        for key in truth:
            photo = proto.load(key + '.jpg')
            cards, _ = proto.find_cards(photo)
            # display scale is proportional to card height; calibrate per image
            ch = np.median([c[3] - c[1] for c in cards])
            sides = [f * ch * kbase for f in (0.24, 0.28, 0.32, 0.36, 0.41)]
            templates = prep_templates(refs, sides)
            for i, card in enumerate(cards):
                w = window_of(photo, card)
                r = rank(w, templates)
                got = r[0][1]
                ok += got == truth[key][i]
                margin = r[0][0] - r[1][0]
                details.append(
                    f'{key}#{i+1} {truth[key][i]:24s} -> {got:24s} {r[0][0]:.3f} (2nd {r[1][1]} {r[1][0]:.3f})'
                    + ('' if got == truth[key][i] else '  WRONG'))
        print(f'kbase={kbase}: {ok}/24')
        for d in details:
            if 'WRONG' in d:
                print('  ' + d)
