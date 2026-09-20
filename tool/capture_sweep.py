#!/usr/bin/env python3
"""How much capture quality does the template tier actually need?

Renders each reference sprite back onto a card, degrades it the way a capture
does - optical blur, contrast compression toward the card colour, a channel
cast - and runs the real matcher (tool/dart_twin.py) over the whole 262-sprite
roster. Answers "is it blur, resolution, colour or contrast?" without needing
another scan on the device.

    python3 tool/capture_sweep.py [n_samples]

Result on the 2026-09-17 rig frames (n=70):

    phone-like  (sharp, full contrast)              top-1  98.6%
    rig-like    (blur 1.6, contrast 45%, blue -45%) top-1  25.7%
    rig + sharper optics (blur 0.8)                 top-1  24.3%   <- no help
    rig + full contrast (blur and cast unchanged)   top-1  94.3%   <- the fix

CONTRAST is the whole story. The foreground gate in _segmentSprite is an
ABSOLUTE distance from the card colour (fgThresholdLow 0.12, span 0.25), so
when a capture compresses sprite-vs-card separation to ~45% - which the rig
does, measured max distance 0.29-0.92 against the phone fixtures' 0.81-1.06 -
most of the sprite falls under the gate, the crop becomes a fragment, and NCC
between a fragment and a whole reference tile is noise. 25.7% over six panels
is ~1.5 correct, which is exactly what the rig scans returned (1/6, 1/6, 2/6).
Blur and colour cast cost almost nothing by comparison.
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dart_twin as dt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARD_PHONE = np.array([175, 56, 93], np.float32)   # median card, select1
CARD_RIG = np.array([120, 26, 35], np.float32)     # median card, rig frames

CONDITIONS = [
    ('phone-like  (sharp, full contrast)',            CARD_PHONE, 70, 0.6, 1.00, (1.00, 1.00, 1.00)),
    ('rig-like    (blur 1.6, contrast 45%, blue -45%)', CARD_RIG, 55, 1.6, 0.45, (1.05, 0.95, 0.55)),
    ('rig + sharper optics (blur 0.8)',               CARD_RIG, 55, 0.8, 0.45, (1.05, 0.95, 0.55)),
    ('rig + full contrast (blur and cast unchanged)', CARD_RIG, 55, 1.6, 1.00, (1.05, 0.95, 0.55)),
]


def render(png, card, px, blur, contrast, cast):
    im = Image.open(os.path.join(ROOT, 'pokemon2Dsprites', png)).convert('RGBA')
    s = px / max(im.size)
    im = im.resize((max(8, round(im.width * s)), max(8, round(im.height * s))), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255
    comp = a[..., :3] * a[..., 3:4] + (card / 255) * (1 - a[..., 3:4])
    pad = 12
    box = np.ones((comp.shape[0] + 2 * pad, comp.shape[1] + 2 * pad, 3), np.float32) * card / 255
    box[pad:pad + comp.shape[0], pad:pad + comp.shape[1]] = comp
    if blur > 0:
        box = np.asarray(Image.fromarray((box * 255).astype(np.uint8))
                         .filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255
    box = card / 255 + (box - card / 255) * contrast
    return np.clip(box * np.array(cast, np.float32), 0, 1)


def main(n=70):
    meta, refs = dt.load_refs()
    tile = meta.get('tile', 32)
    man = json.load(open(os.path.join(ROOT, 'pokemon2Dsprites', 'manifest.json')))['sprites']
    sample = [man[i] for i in np.random.default_rng(7).choice(len(man), min(n, len(man)), replace=False)]
    for label, card, px, blur, con, cast in CONDITIONS:
        t1 = t3 = k = 0
        for sp in sample:
            box = render(sp['file'], card, px, blur, con, cast)
            d = np.sqrt(((box - card / 255) ** 2).sum(2))
            alpha = np.clip((d - dt.FG_LOW) / dt.FG_SPAN, 0, 1)
            rgb, a = dt.keep_main_blob(box, alpha)
            if a.size < 16:
                continue
            cr, ca = dt.square_resize(rgb, a, tile)
            sc = sorted(((dt.template_score(cr, ca, rr, ra), s['name']) for s, rr, ra in refs), reverse=True)
            top = [x[1] for x in sc[:3]]
            k += 1
            t1 += top[0] == sp['displayName']
            t3 += sp['displayName'] in top
        print(f'{label:50s} top-1 {100*t1/k:5.1f}%   top-3 {100*t3/k:5.1f}%   (n={k})')


if __name__ == '__main__':
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 70)
