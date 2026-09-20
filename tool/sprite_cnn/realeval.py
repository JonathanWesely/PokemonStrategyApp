"""The real held-out panels, cut exactly as the app will cut them."""
import sys, json, numpy as np
from PIL import Image
import os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
import recognition_prototype as rp
import render as R

FRAMES = {
    'rig2': (os.path.join(R.ROOT, 'test/fixtures/rig2.jpeg'),
             ['Charizard', 'Venusaur', 'Kleavor', 'Drampa', 'Dragonite', 'Ceruledge']),
    'select1': (os.path.join(R.ROOT, 'test/fixtures/select1.jpeg'),
                ['Raichu', 'Staraptor', 'Pelipper', 'Swampert', 'Dragonite', 'Bellibolt']),
    'preview1': (os.path.join(R.ROOT, 'test/fixtures/preview1.jpeg'),
                 ['Sneasler', 'Umbreon', 'Decidueye', 'Lycanroc (Dusk)', 'Arcanine', 'Sylveon']),
}


def rnd(v):
    # round half UP, as the Dart does - not Python's banker's round()
    return int(np.floor(v + 0.5))


def panel_window(photo01, p):
    x0, y0, x1, y1 = p
    W, H = x1 - x0, y1 - y0
    return photo01[y0 + rnd(H * R.WIN_Y[0]):y0 + rnd(H * R.WIN_Y[1]),
                   x0 + rnd(W * R.WIN_X[0]):x0 + rnd(W * R.WIN_X[1])]


def load(names):
    """-> X (N,48,48,3) float 0..1, y (N,), tags"""
    idx = {n: i for i, n in enumerate(names)}
    X, y, tags = [], [], []
    for key, (path, truth) in FRAMES.items():
        photo = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
        panels = rp.panels_of(photo)
        assert len(panels) == 6, key
        for i, p in enumerate(panels):
            w = panel_window(photo / 255.0, p)
            X.append(R.area_resize(w, R.IN, R.IN))
            y.append(idx[truth[i]])
            tags.append(f'{key}#{i + 1}')
    return np.stack(X), np.array(y), tags
