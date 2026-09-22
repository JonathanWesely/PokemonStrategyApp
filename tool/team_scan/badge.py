"""Twin of ChampionsReferenceSet.readBadge/badgeBoxes applied to the TEAM
CARD name strip, to validate badge-type disambiguation of form families
(Blaze vs Aqua Tauros) before porting to team_scanner.dart.

The strip's right-aligned badge cluster is scanned with the SAME machinery
the battle panels use: column runs of off-background pixels -> boxes;
chromaticity + white-glyph IoU vs the 18 atlas badges, with the absolute
gates (_minBadgeScore 0.30, margin 0.06, glyph IoU 0.35).
"""
import json
import sys
import os
import numpy as np
from PIL import Image
import proto

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')

BG_DIST = 45.0
MIN_GLYPH_FRACTION = 0.045
MIN_SLOT_DISTANCE = 40.0
MIN_BADGE_SCORE = 0.30
MIN_BADGE_MARGIN = 0.06
MIN_GLYPH_IOU = 0.35


def load_badge_sigs():
    meta = json.load(open(os.path.join(ROOT, 'assets/data/champions_refs.json')))
    tile = meta['badgeTile']
    cols = meta['badgeCols']
    atlas = np.asarray(Image.open(
        os.path.join(ROOT, 'assets/sprites/type_badge_atlas.png')
    ).convert('RGB')).astype(np.float64)
    sigs = []
    for b in meta['badges']:
        i = b['i']
        x0, y0 = (i % cols) * tile, (i // cols) * tile
        cr, cg, glyph = feature_from(atlas[y0:y0 + tile, x0:x0 + tile], tile)
        sigs.append((b['type'], cr, cg, glyph))
    return sigs, tile


def feature_from(region, n):
    """Mirror of _featureFrom: area-average to n x n, then body chromaticity
    (median of non-glyph cells) + white-glyph mask (lum>p70 & sat<p45)."""
    h, w, _ = region.shape
    cr = np.zeros(n * n)
    cg = np.zeros(n * n)
    lum = np.zeros(n * n)
    sat = np.zeros(n * n)
    for ty in range(n):
        sy0 = int(ty * h / n)
        sy1 = max(sy0 + 1, int((ty + 1) * h / n))
        for tx in range(n):
            sx0 = int(tx * w / n)
            sx1 = max(sx0 + 1, int((tx + 1) * w / n))
            cell = region[sy0:sy1, sx0:sx1].reshape(-1, 3)
            r, g, b = cell.mean(0)
            i = ty * n + tx
            s = r + g + b + 1e-6
            cr[i] = r / s
            cg[i] = g / s
            lum[i] = (r + g + b) / 3
            sat[i] = cell.max(1).mean() - cell.min(1).mean()  # NOTE below
    # Dart takes max-min of the AVERAGED cell colour; redo it faithfully:
    for ty in range(n):
        sy0 = int(ty * h / n)
        sy1 = max(sy0 + 1, int((ty + 1) * h / n))
        for tx in range(n):
            sx0 = int(tx * w / n)
            sx1 = max(sx0 + 1, int((tx + 1) * w / n))
            cell = region[sy0:sy1, sx0:sx1].reshape(-1, 3)
            r, g, b = cell.mean(0)
            i = ty * n + tx
            sat[i] = max(r, g, b) - min(r, g, b)
    def pctl(v, f):
        s = np.sort(v)
        return s[min(int(len(s) * f), len(s) - 1)]
    lum_thr = pctl(lum, 0.70)
    sat_thr = pctl(sat, 0.45)
    glyph = ((lum > lum_thr) & (sat < sat_thr)).astype(np.float64)
    body = glyph == 0
    if body.sum() > 40:
        mr, mg = np.median(cr[body]), np.median(cg[body])
    else:
        mr, mg = np.median(cr), np.median(cg)
    return mr, mg, glyph


def slot_filled(region, bg):
    r, g, b = region[..., 0], region[..., 1], region[..., 2]
    lum = region.mean(2)
    mx = region.max(2)
    mn = region.min(2)
    bg_lum = bg.mean()
    white_lum = max(120.0, bg_lum + 55)
    white = ((lum > white_lum) & ((mx - mn) < 80)).mean()
    if white <= MIN_GLYPH_FRACTION:
        return False
    med = np.median(region.reshape(-1, 3), 0)
    return np.sqrt(((med - bg) ** 2).sum()) > MIN_SLOT_DISTANCE


def tight_box(region, bg):
    d2 = ((region - bg) ** 2).sum(2)
    ys, xs = np.where(d2 > BG_DIST * BG_DIST)
    if len(xs) < 30:
        return 0, 0, region.shape[1], region.shape[0]
    xs_s, ys_s = np.sort(xs.astype(float)), np.sort(ys.astype(float))
    def q(v, f):
        return int(round(v[min(int(len(v) * f), len(v) - 1)]))
    bx0, bx1 = q(xs_s, 0.02), q(xs_s, 0.98) + 1
    by0, by1 = q(ys_s, 0.02), q(ys_s, 0.98) + 1
    if bx1 - bx0 < 8 or by1 - by0 < 8:
        return 0, 0, region.shape[1], region.shape[0]
    return bx0, by0, bx1, by1


def read_badge(region, bg, sigs, tile):
    if region.shape[0] < 8 or region.shape[1] < 8:
        return None, {}
    if not slot_filled(region, bg):
        return None, {'why': 'unfilled'}
    bx0, by0, bx1, by1 = tight_box(region, bg)
    cr, cg, glyph = feature_from(region[by0:by1, bx0:bx1], tile)
    best, best_score, runner, best_iou = None, -1.0, -1.0, 0.0
    for t, scr, scg, sglyph in sigs:
        dc = np.sqrt((cr - scr) ** 2 + (cg - scg) ** 2)
        inter = float((glyph * sglyph).sum())
        union = float(np.maximum(glyph, sglyph).sum())
        iou = inter / union if union > 0 else 0.0
        score = 0.55 * (1 - min(dc / 0.22, 1.0)) + 0.45 * iou
        if score > best_score:
            runner = best_score
            best_score, best_iou, best = score, iou, t
        elif score > runner:
            runner = score
    dbg = {'best': best, 'score': round(best_score, 3),
           'margin': round(best_score - runner, 3), 'iou': round(best_iou, 3)}
    if best_score < MIN_BADGE_SCORE or \
       best_score - runner < MIN_BADGE_MARGIN or best_iou < MIN_GLYPH_IOU:
        return None, dbg
    return best, dbg


def badge_boxes(band, bg):
    """Mirror of badgeBoxes: column runs of off-bg pixels; a run ~2x as wide
    as tall splits in two. Returns boxes as (x0,x1) in band coords, ALL runs
    (the Dart caps at 2 — here we keep all to see the gender circle too)."""
    h, w, _ = band.shape
    d2 = ((band - bg) ** 2).sum(2)
    on = (d2 > BG_DIST * BG_DIST).sum(0) > 0.25 * h
    runs = []
    start = None
    for i in range(w):
        if on[i] and start is None:
            start = i
        elif not on[i] and start is not None:
            runs.append([start, i])
            start = None
    if start is not None:
        runs.append([start, w])
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < 3:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    boxes = []
    for r in merged:
        rw = r[1] - r[0]
        if rw < 0.3 * h:
            continue
        n = min(2, max(1, round(rw / h)))
        step = rw / n
        for k in range(n):
            boxes.append((int(r[0] + k * step) - 2, int(r[0] + (k + 1) * step) + 2))
    return boxes


def type_score(region, bg, sig, tile):
    """Raw score of ONE badge box against ONE type signature — no argmax,
    no absolute gates. This is the restricted comparison the scanner uses
    inside a form family."""
    if region.shape[0] < 8 or region.shape[1] < 8:
        return -1.0
    bx0, by0, bx1, by1 = tight_box(region, bg)
    cr, cg, glyph = feature_from(region[by0:by1, bx0:bx1], tile)
    t, scr, scg, sglyph = sig
    dc = np.sqrt((cr - scr) ** 2 + (cg - scg) ** 2)
    inter = float((glyph * sglyph).sum())
    union = float(np.maximum(glyph, sglyph).sum())
    iou = inter / union if union > 0 else 0.0
    return 0.55 * (1 - min(dc / 0.22, 1.0)) + 0.45 * iou


# The badge zone: the strip holds TWO fixed badge slots — badge 1 at fx
# 0.461-0.470, badge 2 at 0.518-0.528 (measured on all four fixtures), a
# single badge always in slot 1. The gender circle's tail pokes into the
# zone at ~0.44 and a card-edge artifact runs at 0.585+; a run is kept
# only if its CENTER lands inside a slot window, which excludes both and
# still catches the narrow runs a near-strip-purple badge (Dragon,
# Poison, Ghost) produces.
BZX0, BZX1 = 0.44, 0.578
BZY0, BZY1 = 0.03, 0.26
SLOT1 = (0.4575, 0.5135)   # fx window a run's center must fall into
SLOT2 = (0.5135, 0.5695)
MARGIN = 0.04


GLYPH_PRESENCE = 0.035


def slot_boxes(photo, card, bg):
    """Runs in the badge zone, assigned to the two slots by center; runs
    sharing a slot merge (a weak badge can fragment). A slot with no run
    can still hold a near-strip-purple badge (Ghost, Poison, Dragon) whose
    body vanishes into the bg gate — its white GLYPH is bright whatever
    the body colour, so white fraction in the slot's fixed window is the
    presence signal of last resort (duals 0.063+, empty strip <=0.010).
    Returns {1: (x0,x1), 2: (x0,x1)} in band coords, plus the band."""
    x0, y0, x1, y1 = card
    cw, ch = x1 - x0, y1 - y0
    by0, by1 = y0 + int(BZY0 * ch), y0 + int(BZY1 * ch)
    band = photo[by0:by1, x0 + int(BZX0 * cw):x0 + int(BZX1 * cw)]
    slots = {}
    for (rx0, rx1) in badge_boxes(band, bg):
        cx = (x0 + int(BZX0 * cw) + (rx0 + rx1) / 2 - x0) / cw
        for k, (s0, s1) in ((1, SLOT1), (2, SLOT2)):
            if s0 <= cx < s1:
                if k in slots:
                    slots[k] = (min(slots[k][0], rx0), max(slots[k][1], rx1))
                else:
                    slots[k] = (rx0, rx1)
    for k, (s0, s1) in ((1, SLOT1), (2, SLOT2)):
        if k in slots:
            continue
        wx0 = int(s0 * cw) - int(BZX0 * cw)
        wx1 = int(s1 * cw) - int(BZX0 * cw)
        reg = band[:, max(0, wx0):min(band.shape[1], wx1)]
        if reg.size == 0:
            continue
        lum = reg.mean(2)
        mx, mn = reg.max(2), reg.min(2)
        white_lum = max(120.0, bg.mean() + 55)
        if ((lum > white_lum) & ((mx - mn) < 80)).mean() > GLYPH_PRESENCE:
            slots[k] = (wx0, wx1)
    return slots, band


def family_badge_pick(photo, card, family, types_of, sigs, tile):
    """The scanner rule: slot count filters candidates by type count, then
    each candidate is scored per-slot against its own expected badges.
    Returns (winner or None, debug)."""
    x0, y0, x1, y1 = card
    cw, ch = x1 - x0, y1 - y0
    by0, by1 = y0 + int(BZY0 * ch), y0 + int(BZY1 * ch)
    # bg from the wider strip band (badges dominate the narrow zone)
    wide = photo[by0:by1, x0 + int(0.28 * cw):x0 + int(0.615 * cw)]
    bg = np.median(wide.reshape(-1, 3), 0)
    slots, band = slot_boxes(photo, card, bg)
    if not slots or (2 in slots and 1 not in slots):
        return None, f'slots={sorted(slots)}'
    boxes = [slots[k] for k in sorted(slots)]
    cands = [c for c in family if len(types_of[c]) == len(boxes)]
    if not cands:
        return None, f'no candidate has {len(boxes)} types'
    if len(cands) == 1:
        # decided by count alone — verify each box is at least badge-like
        # for the expected type, so a glare artifact can't decide a form
        sig_by = {s[0]: s for s in sigs}
        for (rx0, rx1), t in zip(boxes, types_of[cands[0]]):
            reg = band[:, max(0, rx0):min(band.shape[1], rx1)]
            sc = type_score(reg, bg, sig_by[t], tile)
            if sc < 0.30:
                return None, f'count-only pick failed verify ({t} {sc:.2f})'
        return cands[0], f'by count ({len(boxes)})'
    sig_by = {s[0]: s for s in sigs}
    scored = []
    for c in cands:
        tot = 0.0
        for (rx0, rx1), t in zip(boxes, types_of[c]):
            reg = band[:, max(0, rx0):min(band.shape[1], rx1)]
            tot += type_score(reg, bg, sig_by[t], tile)
        scored.append((tot / len(boxes), c))
    scored.sort(reverse=True)
    dbg = ' '.join(f'{c}:{s:.3f}' for s, c in scored)
    if len(scored) > 1 and scored[0][0] - scored[1][0] < MARGIN:
        return None, 'near-tie ' + dbg
    return scored[0][1], dbg


if __name__ == '__main__':
    sigs, tile = load_badge_sigs()
    pd = json.load(open(os.path.join(ROOT, 'assets/data/pokedex.json')))
    sp = pd['species'] if isinstance(pd, dict) and 'species' in pd else pd
    types_of = {s['id']: s['types'] for s in (sp.values() if isinstance(sp, dict) else sp)} \
        if not isinstance(sp, dict) else {k: v['types'] for k, v in sp.items()}
    truth = {
        't1': ['chesnaught', 'typhlosion', 'rillaboom', 'sableye',
               'scolipede', 'armarouge'],
        't2': ['rotom-heat', 'charizard', 'froslass', 'garchomp',
               'whimsicott', 'tauros-paldea-blaze-breed'],
    }
    families = {
        'typhlosion': ['typhlosion', 'typhlosion-hisui'],
        'rotom-heat': ['rotom', 'rotom-heat', 'rotom-wash', 'rotom-frost',
                       'rotom-fan', 'rotom-mow'],
        'tauros-paldea-blaze-breed': [
            'tauros', 'tauros-paldea-combat-breed',
            'tauros-paldea-blaze-breed', 'tauros-paldea-aqua-breed'],
    }
    count_ok = count_tot = fam_ok = fam_tot = 0
    for key in ['t1_moves', 't1_stats', 't2_moves', 't2_stats']:
        photo = proto.load(os.path.join(
            ROOT, 'test/fixtures/team' + key[1] + '_' +
            key.split('_')[1] + '.jpeg')).astype(np.float64)
        cards, _ = proto.find_cards(photo.astype(np.uint8))
        print(f'== {key}')
        for i, card in enumerate(cards):
            x0, y0, x1, y1 = card
            cw, ch = x1 - x0, y1 - y0
            by0, by1 = y0 + int(BZY0 * ch), y0 + int(BZY1 * ch)
            wide = photo[by0:by1, x0 + int(0.28 * cw):x0 + int(0.615 * cw)]
            bg = np.median(wide.reshape(-1, 3), 0)
            slots, band = slot_boxes(photo, card, bg)
            tid = truth[key[:2]][i]
            want = types_of[tid]
            count_tot += 1
            cok = len(slots) == len(want)
            count_ok += cok
            line = (f'  card{i+1} {tid:26s} types={len(want)} '
                    f'slots={sorted(slots)} {"OK" if cok else "COUNT WRONG"}')
            if tid in families:
                fam_tot += 1
                pick, dbg = family_badge_pick(
                    photo, card, families[tid], types_of, sigs, tile)
                good = pick == tid
                fam_ok += good
                line += f'  family -> {pick} ({dbg}) {"OK" if good else "WRONG"}'
            print(line)
    print(f'box counts {count_ok}/{count_tot}   family picks {fam_ok}/{fam_tot}')
