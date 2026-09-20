"""Goldens for test/sprite_cnn_test.dart: the Dart classifier must reproduce
the Python twin (export.forward) on the same inputs.

    python3 tool/sprite_cnn/make_goldens.py

Writes test/fixtures/sprite_cnn_golden.json with
  resize: a small random image and its area-resampled output
  cases:  real panel windows (area-resized, NOT yet standardised) and the
          logits export.forward produces for them
"""
import os, sys, json
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import render as R, realeval, export
sys.path.insert(0, os.path.join(R.ROOT, 'tool'))
import recognition_prototype as rp


def load_layers():
    meta = json.load(open(os.path.join(R.ROOT, 'assets/models/sprite_cnn.json')))
    data = np.fromfile(os.path.join(R.ROOT, 'assets/models/sprite_cnn.bin'), '<f4')
    layers, off = [], 0
    for L in meta['layers']:
        o, i = L['out'], L['inp']
        if L['kind'] == 'conv3x3':
            W = data[off:off + o * 9 * i].reshape(o, 3, 3, i); off += o * 9 * i
            b = data[off:off + o]; off += o
            layers.append(dict(kind='conv3x3', W=W, b=b, pool=L['pool']))
        else:
            W = data[off:off + o * i].reshape(o, i); off += o * i
            b = data[off:off + o]; off += o
            layers.append(dict(kind='dense', W=W, b=b))
    assert off == data.size
    return meta, layers


def standardize(x):
    m = x.reshape(-1, 3).mean(0)
    s = x.reshape(-1, 3).std(0)
    return ((x - m) / np.maximum(s, 0.02)).astype(np.float32)


if __name__ == '__main__':
    meta, layers = load_layers()
    rng = np.random.default_rng(3)
    src = rng.random((7, 9, 3))
    out = R.area_resize(src, 4, 5)
    cases = []
    for key, (path, truth) in realeval.FRAMES.items():
        photo = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
        panels = rp.panels_of(photo)
        for i in ([0, 3] if key == 'rig2' else [2]):
            win = R.area_resize(realeval.panel_window(photo / 255.0, panels[i]), R.IN, R.IN)
            z = export.forward(layers, standardize(win))
            cases.append(dict(tag=f'{key}#{i + 1}', truth=truth[i],
                              window=[float(f'{v:.7g}') for v in win.ravel()],
                              logits=[float(f'{v:.7g}') for v in z]))
            print(cases[-1]['tag'], truth[i], '->', meta['classes'][int(np.argmax(z))])
    g = dict(resize=dict(h=7, w=9, hOut=4, wOut=5,
                         src=[float(f'{v:.9g}') for v in src.ravel()],
                         out=[float(f'{v:.9g}') for v in out.ravel()]),
             cases=cases)
    dst = os.path.join(R.ROOT, 'test/fixtures/sprite_cnn_golden.json')
    json.dump(g, open(dst, 'w'))
    print('wrote', dst, os.path.getsize(dst), 'bytes')
