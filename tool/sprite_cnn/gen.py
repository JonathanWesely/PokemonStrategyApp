import sys, numpy as np, time
from multiprocessing import Pool
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render as R

SPR = None

def init():
    global SPR
    import cv2
    cv2.setNumThreads(1)          # 2 workers on 2 cores; cv2's own pool oversubscribes
    SPR = R.load_sprites()[1]

def work(args):
    seed, idxs = args
    sprites = SPR
    rng = np.random.default_rng(seed)
    X = np.empty((len(idxs), R.IN, R.IN, 3), np.uint8)
    for n, k in enumerate(idxs):
        X[n] = np.clip(np.round(R.sample(rng, sprites[k]) * 255), 0, 255).astype(np.uint8)
    return X

if __name__ == '__main__':
    name, per_class, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    meta, _ = R.load_sprites()
    y = np.repeat(np.arange(len(meta)), per_class)
    np.random.default_rng(seed).shuffle(y)
    chunks = np.array_split(y, 64)
    t = time.time()
    with Pool(2, initializer=init) as p:
        parts = p.map(work, [(seed * 1000 + i, c) for i, c in enumerate(chunks)])
    X = np.concatenate(parts)
    os.makedirs(R.DATA, exist_ok=True)
    np.savez(os.path.join(R.DATA, f'{name}.npz'), X=X, y=y)
    print(name, X.shape, f'{time.time()-t:.0f}s')
