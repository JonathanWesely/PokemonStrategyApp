# Assembly diagrams (vault §12.2)

Regenerate with `python3 dN_*.py` (needs nothing but the stdlib; render
checks used `cairosvg`). Each script writes its `PokemonRig-*.svg` here —
copy the SVGs to the Obsidian vault root, where `PokemonStrategyApp.md`
embeds them as `![[PokemonRig-*.svg]]`.

| Script | Diagram | Notes |
|---|---|---|
| `d1_buildpath.py` | BuildPath | Phase A (USB-C) → Phase B (glue) → the gate → pass/fail |
| `d2_wiring.py` | Wiring | battery → SPDT switch → BAT pads. **Polarity per Seeed's wiki: negative is the pad closest to USB-C.** |
| `d3_gluejoint.py` | GlueJoint | 4-step cross-section: clean → tape → glue → overcoat, then the gate |
| `d4_podloading.py` | PodLoading | exploded side view + top view, **to scale** |

`d4_podloading.py` hard-codes the same constants as `../switch_cam_rig.py`
(POD_W, POD_FRONT/REAR, WIN, WY, BAY_W/L, RAIL_*). If the pod geometry
changes there, update them here and re-render.
