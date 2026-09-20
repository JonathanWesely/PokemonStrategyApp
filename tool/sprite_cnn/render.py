"""Synthetic enemy-panel renderer for training the sprite classifier.

Every sample is a whole team-preview PANEL at capture resolution — card,
translucent background bleed, sprite, badge/gender distractors — degraded the
way a photo of a screen degrades it, then cut to the CNN window and area-
resized to IN x IN exactly as the app will do it. Calibration comes from the
three real frames (rig2, select1, preview1):

  * scale:     panel_h / (115 * U(0.90, 1.12)) screen px per sprite px
               (preview1: window_h/scale = 98..106, select1 93..114)
  * placement: sprite centre x ~0.40 of the panel, feet near the bottom
  * card:      hue 292..10 deg, sat 0.55..0.97, val 0.36..0.80 (measured)
  * rig:       blur ~1.6 px, contrast ~45 %, blue -45 %, translucent card
"""
import json, os
import numpy as np
import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_data')   # gitignored
IN = 48
WIN_X = (0.10, 0.63)          # CNN window, fraction of panel width
WIN_Y = (0.04, 0.96)          # fraction of panel height


def load_sprites():
    man = json.load(open(f'{ROOT}/pokemon2Dsprites/manifest.json'))
    out = []
    for s in man['sprites']:
        im = cv2.imread(f"{ROOT}/pokemon2Dsprites/{s['file']}", cv2.IMREAD_UNCHANGED)
        rgba = cv2.cvtColor(im, cv2.COLOR_BGRA2RGBA).astype(np.float32) / 255.0
        out.append(rgba)
    return man['sprites'], out


# ---------------------------------------------------------------- resample
_AM = {}


def area_matrix(n_in, n_out):
    if (n_in, n_out) in _AM:
        return _AM[(n_in, n_out)]
    _AM[(n_in, n_out)] = M = _area_matrix(n_in, n_out)
    return M


def _area_matrix(n_in, n_out):
    """Row-stochastic matrix M (n_out x n_in): exact area-weighted average of
    the source footprint of each output pixel. The Dart side builds the same
    matrix, so train-time and app-time inputs are bit-comparable."""
    M = np.zeros((n_out, n_in), np.float64)
    scale = n_in / n_out
    for o in range(n_out):
        a, b = o * scale, (o + 1) * scale
        i0, i1 = int(np.floor(a)), int(np.ceil(b))
        for i in range(i0, min(i1, n_in)):
            w = min(b, i + 1) - max(a, i)
            if w > 0:
                M[o, i] = w
        M[o] /= M[o].sum()
    return M


def area_resize(img, h_out, w_out):
    my = area_matrix(img.shape[0], h_out)
    mx = area_matrix(img.shape[1], w_out)
    t = np.tensordot(my, img.astype(np.float64), axes=(1, 0))        # (h_out, W, 3)
    return np.tensordot(t, mx, axes=(1, 1)).transpose(0, 2, 1).astype(np.float32)


def window_of(panel_img, box=None):
    """Cut the CNN window out of a panel image (H,W,3 float 0..1)."""
    H, W = panel_img.shape[:2]
    x0, x1 = int(round(W * WIN_X[0])), int(round(W * WIN_X[1]))
    y0, y1 = int(round(H * WIN_Y[0])), int(round(H * WIN_Y[1]))
    return panel_img[y0:y1, x0:x1]


def standardize(x):
    """Per-channel standardisation over the window: removes any per-channel
    affine distortion (exposure, contrast compression, colour cast) exactly."""
    m = x.reshape(-1, 3).mean(0)
    s = x.reshape(-1, 3).std(0)
    return (x - m) / np.maximum(s, 0.02)


# ---------------------------------------------------------------- render
def hsv2rgb(h, s, v):
    c = v * s; hp = (h % 360) / 60.0; x = c * (1 - abs(hp % 2 - 1))
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][int(hp) % 6]
    m = v - c
    return np.array([r + m, g + m, b + m], np.float32)


def rand_background(rng, H, W):
    """What shows through the translucent card: bands of stage colour."""
    kind = rng.integers(0, 4)
    cols = [np.array(c, np.float32) / 255 for c in
            [(230, 210, 40), (40, 90, 220), (240, 240, 240), (60, 60, 60), (40, 170, 90), (200, 60, 40)]]
    bg = np.zeros((H, W, 3), np.float32)
    if kind == 0:                                  # horizontal bands
        y = 0
        while y < H:
            h = int(rng.integers(max(2, H // 8), max(3, H // 2)))
            bg[y:y + h] = cols[rng.integers(len(cols))]
            y += h
    elif kind == 1:                                # vertical split
        x = int(rng.integers(0, W))
        bg[:, :x] = cols[rng.integers(len(cols))]
        bg[:, x:] = cols[rng.integers(len(cols))]
    else:                                          # smooth gradient
        a, b = cols[rng.integers(len(cols))], cols[rng.integers(len(cols))]
        t = np.linspace(0, 1, H if kind == 2 else W, dtype=np.float32)
        g = a + (b - a) * t[:, None]
        bg[:] = g[:, None, :] if kind == 2 else g[None, :, :]
    return cv2.GaussianBlur(bg, (0, 0), max(1.0, H / 20))


def paste(dst, rgba, cx, by):
    """Alpha-composite rgba with its bottom-centre at (cx, by); clips."""
    h, w = rgba.shape[:2]
    x0, y0 = int(round(cx - w / 2)), int(round(by - h))
    H, W = dst.shape[:2]
    sx0, sy0 = max(0, -x0), max(0, -y0)
    dx0, dy0 = max(0, x0), max(0, y0)
    dx1, dy1 = min(W, x0 + w), min(H, y0 + h)
    if dx1 <= dx0 or dy1 <= dy0:
        return
    src = rgba[sy0:sy0 + dy1 - dy0, sx0:sx0 + dx1 - dx0]
    a = src[..., 3:4]
    dst[dy0:dy1, dx0:dx1] = dst[dy0:dy1, dx0:dx1] * (1 - a) + src[..., :3] * a


def distractors(rng, img):
    """Type badges + gender circle on the right of the card."""
    H, W = img.shape[:2]
    bs = int(H * rng.uniform(0.26, 0.34))
    y = int(H * rng.uniform(0.10, 0.18))
    x = int(W * rng.uniform(0.66, 0.72))
    for k in range(rng.integers(1, 3)):
        c = rng.uniform(0.2, 1.0, 3).astype(np.float32)
        img[y:y + bs, x:x + bs] = c
        g = int(bs * 0.3)
        img[y + g:y + bs - g, x + g:x + bs - g] = 0.95
        x += int(bs * 1.15)
    r = max(2, int(H * 0.09))
    cv2.circle(img, (int(W * rng.uniform(0.66, 0.72)), int(H * rng.uniform(0.70, 0.80))), r,
               (0.2, 0.3, 0.9) if rng.random() < 0.5 else (0.9, 0.2, 0.3), -1)


def render(rng, sprite, strength=1.0):
    """One degraded panel -> CNN window (float32 0..1, un-resized)."""
    Hp = int(rng.uniform(56, 190))
    Wp = int(Hp * rng.uniform(1.95, 2.75))
    card = hsv2rgb(rng.uniform(290, 372), rng.uniform(0.50, 0.98), rng.uniform(0.32, 0.88))
    img = np.empty((Hp, Wp, 3), np.float32)
    img[:] = card
    # subtle card shading (the game's card has a soft diagonal sheen)
    yy, xx = np.mgrid[0:Hp, 0:Wp].astype(np.float32)
    ang = rng.uniform(0, 2 * np.pi)
    ramp = (np.cos(ang) * xx / Wp + np.sin(ang) * yy / Hp)
    img *= (1 + rng.uniform(-0.12, 0.12) * ramp)[..., None]
    # translucent card: stage shows through
    if rng.random() < 0.6 * strength:
        t = rng.uniform(0.05, 0.38) * strength
        img = img * (1 - t) + rand_background(rng, Hp, Wp) * t
    if rng.random() < 0.7:
        distractors(rng, img)
    # sprite
    scale = Hp / (115.0 * rng.uniform(0.88, 1.28))
    h, w = sprite.shape[:2]
    nh, nw = max(4, int(round(h * scale))), max(4, int(round(w * scale)))
    interp = cv2.INTER_AREA if scale < 1 else cv2.INTER_LINEAR
    sp = cv2.resize(sprite, (nw, nh), interpolation=interp)
    sp[..., 3] = np.clip(sp[..., 3], 0, 1)
    cx = Wp * rng.uniform(0.33, 0.47)
    if rng.random() < 0.6:
        by = Hp * rng.uniform(0.86, 1.0)
    else:
        by = Hp * rng.uniform(0.45, 0.60) + nh / 2
    paste(img, sp, cx, by)
    img = np.clip(img, 0, 1)

    # ------------------------------------------------ photo-of-screen chain
    s = strength
    if rng.random() < 0.8:
        sig = rng.uniform(0.3, 2.6 * s) * (Hp / 97.0) ** 0.5
        img = cv2.GaussianBlur(img, (0, 0), sig)
    if rng.random() < 0.5 * s:                    # scanlines / moire
        per = rng.uniform(2.0, 7.0)
        amp = rng.uniform(0.0, 0.07)
        ph = rng.uniform(0, 2 * np.pi)
        img = img * (1 + amp * np.sin(2 * np.pi * yy / per + ph))[..., None]
    if rng.random() < 0.85:                       # contrast compression
        c = rng.uniform(0.32, 1.05) if rng.random() < s else rng.uniform(0.8, 1.05)
        m = img.reshape(-1, 3).mean(0)
        img = m + (img - m) * c
    if rng.random() < 0.8:                        # colour cast + exposure
        gains = rng.uniform(1 - 0.35 * s, 1 + 0.25 * s, 3).astype(np.float32)
        img = img * gains + rng.uniform(-0.08, 0.10, 3).astype(np.float32) * s
    if rng.random() < 0.5:                        # gamma
        img = np.clip(img, 0, 1) ** rng.uniform(0.75, 1.35)
    if rng.random() < 0.4 * s:                    # glare: additive white ramp
        ang = rng.uniform(0, 2 * np.pi)
        ramp = (np.cos(ang) * (xx / Wp - 0.5) + np.sin(ang) * (yy / Hp - 0.5)) + 0.5
        img = img + rng.uniform(0.05, 0.40) * np.clip(ramp, 0, 1)[..., None] ** rng.uniform(1, 3)
    if rng.random() < 0.7:
        img = img + rng.normal(0, rng.uniform(0.005, 0.04), img.shape).astype(np.float32)
    img = np.clip(img, 0, 1)
    if rng.random() < 0.85:                       # JPEG
        q = int(rng.uniform(25, 92))
        ok, enc = cv2.imencode('.jpg', (img[..., ::-1] * 255).astype(np.uint8), [cv2.IMWRITE_JPEG_QUALITY, q])
        img = cv2.imdecode(enc, cv2.IMREAD_COLOR)[..., ::-1].astype(np.float32) / 255
    # panel finder error: jitter the box a few percent before cutting the window
    jx0 = int(rng.uniform(-0.07, 0.07) * Wp); jx1 = int(rng.uniform(-0.09, 0.05) * Wp)
    jy0 = int(rng.uniform(-0.06, 0.06) * Hp); jy1 = int(rng.uniform(-0.06, 0.06) * Hp)
    pad = np.pad(img, ((Hp, Hp), (Wp, Wp), (0, 0)), mode='edge')
    box = pad[Hp + jy0:2 * Hp + jy1, Wp + jx0:2 * Wp + jx1]
    return window_of(box)


def sample(rng, sprite, strength=1.0):
    w = render(rng, sprite, strength)
    return area_resize(w, IN, IN)


if __name__ == '__main__':
    import sys, time
    meta, sprites = load_sprites()
    rng = np.random.default_rng(0)
    t = time.time()
    tiles = []
    names = ['Charizard', 'Venusaur', 'Kleavor', 'Drampa', 'Dragonite', 'Ceruledge', 'Sableye', 'Raichu']
    idx = [next(i for i, s in enumerate(meta) if s['displayName'] == n) for n in names]
    for i in idx:
        row = [sample(rng, sprites[i]) for _ in range(10)]
        tiles.append(np.concatenate([np.pad(r, ((1, 1), (1, 1), (0, 0))) for r in row], 1))
    print('per sample ms', (time.time() - t) / 80 * 1000)
    sheet = np.concatenate(tiles, 0)
    cv2.imwrite('aug_sheet.png', cv2.resize((sheet[..., ::-1] * 255).astype(np.uint8), None, fx=3, fy=3,
                                            interpolation=cv2.INTER_NEAREST))
