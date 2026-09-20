"""Fold BatchNorm into the convs and write the model as
  sprite_cnn.bin  - little-endian float32, layers in order: for each conv
                    weights[out][ky][kx][in] then bias[out]; then fc
                    weights[out][in] then bias[out]
  sprite_cnn.json - input size, window fractions, layer shapes, class list
and check a pure-numpy forward pass (the layout the Dart reads) against Keras.

    python3 tool/sprite_cnn/export.py tool/sprite_cnn/_data/m1.keras assets/models
"""
import os, sys, json
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render as R


def fold(model):
    layers, k = [], 0
    while True:
        try:
            conv = model.get_layer(f'conv{k}')
        except ValueError:
            break
        bn = model.get_layer(f'bn{k}')
        W = conv.get_weights()[0].astype(np.float64)            # kh,kw,in,out
        g, b, m, v = [x.astype(np.float64) for x in bn.get_weights()]
        sc = g / np.sqrt(v + bn.epsilon)
        Wf = (W * sc).transpose(3, 0, 1, 2)                      # out,kh,kw,in
        bf = b - m * sc
        pool = True
        try:
            model.get_layer(f'pool{k}')
        except ValueError:
            pool = False
        layers.append(dict(kind='conv3x3', W=Wf.astype(np.float32), b=bf.astype(np.float32), pool=pool))
        k += 1
    fc = model.get_layer('fc')
    W, b = fc.get_weights()
    layers.append(dict(kind='dense', W=W.T.astype(np.float32).copy(), b=b.astype(np.float32)))
    return layers


def forward(layers, x):
    """x: (IN,IN,3) standardised. Mirrors sprite_cnn.dart exactly."""
    a = x.astype(np.float32)
    for L in layers:
        if L['kind'] == 'conv3x3':
            H, Wd, C = a.shape
            p = np.pad(a, ((1, 1), (1, 1), (0, 0)))
            cols = np.stack([p[ky:ky + H, kx:kx + Wd] for ky in range(3) for kx in range(3)], 2)  # H,W,9,C
            Wm = L['W'].reshape(L['W'].shape[0], 9, C)                                         # out,9,C
            a = np.einsum('hwkc,okc->hwo', cols, Wm, optimize=True) + L['b']
            a = np.maximum(a, 0)
            if L['pool']:
                H2, W2 = a.shape[0] // 2, a.shape[1] // 2
                a = a[:H2 * 2, :W2 * 2].reshape(H2, 2, W2, 2, -1).max((1, 3))
        else:
            g = a.reshape(-1, a.shape[-1]).mean(0)
            return L['W'] @ g + L['b']


def write(layers, names, species, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    blob, spec = [], []
    for L in layers:
        blob += [L['W'].ravel(), L['b'].ravel()]
        if L['kind'] == 'conv3x3':
            spec.append(dict(kind='conv3x3', out=int(L['W'].shape[0]), inp=int(L['W'].shape[3]),
                             pool=bool(L['pool'])))
        else:
            spec.append(dict(kind='dense', out=int(L['W'].shape[0]), inp=int(L['W'].shape[1])))
    data = np.concatenate(blob).astype('<f4')
    data.tofile(os.path.join(out_dir, 'sprite_cnn.bin'))
    meta = dict(version=1, input=R.IN, windowX=list(R.WIN_X), windowY=list(R.WIN_Y),
                resize='area', normalize='per-channel standardise, std floor 0.02 (0-1 units)',
                layers=spec, floats=int(data.size), classes=names, species=species)
    json.dump(meta, open(os.path.join(out_dir, 'sprite_cnn.json'), 'w'), indent=1)
    return data.size


if __name__ == '__main__':
    import tensorflow as tf
    model = tf.keras.models.load_model(sys.argv[1])
    out_dir = sys.argv[2]
    meta, _ = R.load_sprites()
    names = [s['displayName'] for s in meta]
    species = [s['packSpeciesId'] for s in meta]
    layers = fold(model)
    n = write(layers, names, species, out_dir)
    print('floats', n, 'bytes', n * 4)
    # parity: numpy forward vs keras on random + real inputs
    import realeval, train
    Xre, yre, tags = realeval.load(names)
    Xs = train.standardize_batch(Xre)
    kl = model.predict(Xs, verbose=0)
    nl = np.stack([forward(layers, x) for x in Xs])
    print('max |keras - numpy| logit diff', float(np.abs(kl - nl).max()))
