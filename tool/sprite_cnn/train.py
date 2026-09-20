import os, sys, json, time
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
import numpy as np
import tensorflow as tf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render as R
import realeval

WIDTHS = [int(v) for v in os.environ.get('WIDTHS', '24,48,96,160').split(',')]
EPOCHS = int(os.environ.get('EPOCHS', '14'))
TAG = os.environ.get('TAG', 'm1')


def standardize_batch(X):
    div = 255.0 if X.dtype == np.uint8 else 1.0
    out = np.empty(X.shape, np.float32)
    for i in range(0, len(X), 4096):
        x = X[i:i + 4096].astype(np.float32) / div
        m = x.mean(axis=(1, 2), keepdims=True)
        s = x.std(axis=(1, 2), keepdims=True)
        out[i:i + 4096] = (x - m) / np.maximum(s, 0.02)
    return out


def build(n_classes):
    L = tf.keras.layers
    inp = tf.keras.Input((R.IN, R.IN, 3))
    x = L.RandomTranslation(0.04, 0.04, fill_mode='nearest')(inp)
    for k, w in enumerate(WIDTHS):
        x = L.Conv2D(w, 3, padding='same', use_bias=False, name=f'conv{k}')(x)
        x = L.BatchNormalization(name=f'bn{k}')(x)
        x = L.ReLU()(x)
        if k < len(WIDTHS) - 1:
            x = L.MaxPool2D(name=f'pool{k}')(x)
    x = L.GlobalAveragePooling2D()(x)
    x = L.Dropout(0.3)(x)
    out = L.Dense(n_classes, name='fc')(x)
    return tf.keras.Model(inp, out)


class RealEval(tf.keras.callbacks.Callback):
    def __init__(self, X, y, tags, names):
        self.X, self.y, self.tags, self.names = X, y, tags, names

    def on_epoch_end(self, epoch, logs=None):
        lg = self.model.predict(self.X, verbose=0)
        order = np.argsort(-lg, 1)
        ranks = [int(np.where(order[i] == self.y[i])[0][0]) + 1 for i in range(len(self.y))]
        rig = ranks[:6]
        print(f'  [real] epoch {epoch + 1}: top1 {sum(r == 1 for r in ranks)}/18 '
              f'(rig {sum(r == 1 for r in rig)}/6, phone {sum(r == 1 for r in ranks[6:])}/12)  '
              f'top5 {sum(r <= 5 for r in ranks)}/18  rig ranks {rig}', flush=True)


def main():
    meta, _ = R.load_sprites()
    names = [s['displayName'] for s in meta]
    tr = np.load(os.path.join(R.DATA, 'train.npz')); va = np.load(os.path.join(R.DATA, 'val.npz'))
    ytr = tr['y']
    nc = len(names)

    def prep(x, y):
        x = tf.cast(x, tf.float32) / 255.0
        m = tf.reduce_mean(x, axis=(0, 1), keepdims=True)
        s = tf.math.reduce_std(x, axis=(0, 1), keepdims=True)
        return (x - m) / tf.maximum(s, 0.02), tf.one_hot(y, nc)
    ds_tr = (tf.data.Dataset.from_tensor_slices((tr['X'], ytr)).shuffle(20000, seed=1)
             .map(prep, num_parallel_calls=2).batch(128).prefetch(2))
    ds_va = (tf.data.Dataset.from_tensor_slices((va['X'], va['y']))
             .map(prep).batch(256))
    Xre, yre, tags = realeval.load(names)
    Xre = standardize_batch(Xre)
    model = build(len(names))
    print('params', model.count_params(), 'widths', WIDTHS, flush=True)
    steps = EPOCHS * int(np.ceil(len(ytr) / 128))
    sched = tf.keras.optimizers.schedules.CosineDecay(2e-3, steps, warmup_target=None)
    model.compile(optimizer=tf.keras.optimizers.AdamW(sched, weight_decay=1e-4),
                  loss=tf.keras.losses.CategoricalCrossentropy(from_logits=True, label_smoothing=0.1),
                  metrics=['accuracy'])
    t = time.time()
    model.fit(ds_tr, epochs=EPOCHS, validation_data=ds_va,
              callbacks=[RealEval(Xre, yre, tags, names)], verbose=2)
    print(f'trained in {time.time() - t:.0f}s', flush=True)
    model.save(os.path.join(R.DATA, f'{TAG}.keras'))
    lg = model.predict(Xre, verbose=0)
    for i in range(len(yre)):
        o = np.argsort(-lg[i])
        r = int(np.where(o == yre[i])[0][0]) + 1
        top = '  '.join(f'{names[j]}' for j in o[:3])
        print(f'{tags[i]:11s} want {names[yre[i]]:16s} rank {r:3d}   top3: {top}')


if __name__ == '__main__':
    main()
