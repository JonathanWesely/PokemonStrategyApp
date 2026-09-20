"""Stress tests for a trained model (numpy forward = what the Dart runs).

  1. the 18 real panels, with softmax confidence and margin
  2. the same panels with the panel box jittered (finder error) - 40 draws each
  3. sprite_matcher_test.dart's synthetic composePreview screen
"""
import os, sys, json
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import render as R, realeval, export, train
import recognition_prototype as rp

model_path = sys.argv[1]
import tensorflow as tf
model = tf.keras.models.load_model(model_path)
layers = export.fold(model)
meta, _ = R.load_sprites()
names = [s['displayName'] for s in meta]


def softmax(z):
    z = z - z.max()
    e = np.exp(z)
    return e / e.sum()


def predict(win01):
    x = R.area_resize(win01, R.IN, R.IN)
    x = train.standardize_batch(x[None])[0]
    return softmax(export.forward(layers, x))


print('--- 1. real panels')
for key, (path, truth) in realeval.FRAMES.items():
    photo = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    panels = rp.panels_of(photo)
    for i, p in enumerate(panels):
        pr = predict(realeval.panel_window(photo / 255.0, p))
        o = np.argsort(-pr)
        want = names.index(truth[i])
        r = int(np.where(o == want)[0][0]) + 1
        print(f'{key:8s}#{i+1} {truth[i]:16s} rank {r:3d} p={pr[want]:.3f}  '
              f'top: {names[o[0]]} {pr[o[0]]:.3f} | {names[o[1]]} {pr[o[1]]:.3f}')

print('--- 2. finder jitter (+-6% x, +-8% y per edge), 40 draws per panel')
rng = np.random.default_rng(5)
for key, (path, truth) in realeval.FRAMES.items():
    photo = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    panels = rp.panels_of(photo)
    ok = 0; n = 0
    for i, p in enumerate(panels):
        x0, y0, x1, y1 = p; W, H = x1 - x0, y1 - y0
        want = names.index(truth[i])
        for _ in range(40):
            q = (int(x0 + rng.uniform(-.06, .06) * W), int(y0 + rng.uniform(-.08, .08) * H),
                 int(x1 + rng.uniform(-.06, .06) * W), int(y1 + rng.uniform(-.08, .08) * H))
            ok += int(np.argmax(predict(realeval.panel_window(photo / 255.0, q))) == want); n += 1
    print(f'{key:8s} {ok}/{n} = {ok/n:.1%}')

print('--- 3. synthetic composePreview (sprite_matcher_test.dart)')
from PIL import Image as I
canvas = I.new('RGB', (1200, 900), (40, 90, 60))
ids = ['garchomp', 'dragonite', 'gholdengo', 'pelipper', 'torkoal', 'metagross']
disp = {s['packSpeciesId']: s['displayName'] for s in meta}
panelX, panelW, panelH, gap, startY = 780, 330, 90, 28, 110
for i, sid in enumerate(ids):
    y0 = startY + i * (panelH + gap)
    canvas.paste((216, 44, 100), (panelX, y0, panelX + panelW + 1, y0 + panelH + 1))
    fx = f'{R.ROOT}/test/fixtures/champions/{sid}.png'   # copies of pokemon2Dsprites
    sp = I.open(fx if os.path.exists(fx) else f'{R.ROOT}/pokemon2Dsprites/{disp[sid]}.png').convert('RGBA')
    h = panelH - 10; w = round(sp.width * h / sp.height)
    sp = sp.resize((w, h), I.NEAREST)   # image 4.x copyResize default = nearest
    canvas.paste(sp, (panelX + round(panelW * 0.22), y0 + 5), sp)
import io
buf = io.BytesIO(); canvas.save(buf, 'JPEG', quality=90)
photo = np.asarray(I.open(io.BytesIO(buf.getvalue())).convert('RGB')).astype(np.float32)
panels = rp.panels_of(photo)
print('panels', len(panels))
for i, p in enumerate(panels):
    pr = predict(realeval.panel_window(photo / 255.0, p))
    o = np.argsort(-pr); want = names.index(disp[ids[i]])
    r = int(np.where(o == want)[0][0]) + 1
    print(f'synthetic#{i+1} {disp[ids[i]]:12s} rank {r:3d} p={pr[want]:.3f} top: {names[o[0]]} {pr[o[0]]:.3f}')
