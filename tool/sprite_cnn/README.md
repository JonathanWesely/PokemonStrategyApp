# tool/sprite_cnn — the trained sprite classifier

Why it exists: the template tier needs a clean segmentation, and the rig's
low-contrast frames never give it one (CLAUDE.md: "six gate formulations
tried, all worse"). This classifier looks at a fixed window of each panel
instead and is trained on synthetic panels degraded the way a photo of the
screen degrades them.

```bash
pip install --break-system-packages tensorflow-cpu opencv-python-headless scipy pillow
python3 tool/sprite_cnn/gen.py val 12 7          # ~1 min  -> _data/val.npz
python3 tool/sprite_cnn/gen.py train 360 1       # ~25 min -> _data/train.npz (94k panels)
python3 tool/sprite_cnn/train.py                 # ~45 min on 2 CPUs; prints the 18 real panels each epoch
python3 tool/sprite_cnn/export.py tool/sprite_cnn/_data/m1.keras assets/models
python3 tool/sprite_cnn/eval_extra.py tool/sprite_cnn/_data/m1.keras   # confidence, finder jitter, synthetic screen
python3 tool/sprite_cnn/make_goldens.py          # test/fixtures/sprite_cnn_golden.json
```

- `render.py` — the synthetic panel renderer and the exact resample/window
  rules the Dart mirrors (`area_resize`, `WIN_X/WIN_Y`, per-channel
  standardisation). Calibration is in its docstring.
- `realeval.py` — the real held-out panels (rig2, select1, preview1), cut with
  the Dart panel finder's Python twin. NEVER train on these.
- `export.py` — folds BatchNorm, writes `assets/models/sprite_cnn.{bin,json}`,
  and holds `forward()`, the numpy twin of `lib/src/recognition/sprite_cnn.dart`.
- After a retrain, re-run `make_goldens.py` or `test/sprite_cnn_test.dart` fails.
- Add a real frame to the test set: `.\tool\pull_scan.ps1 -Truth "A,B,C,D,E,F"`
  archives it with its truth under `test\_scan_dump\archive\`.
