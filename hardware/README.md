# Handheld + TV camera rig (v4, modular)

One camera, two homes. The **camera pod** is self-contained — XIAO ESP32S3
Sense (lens-down over a beveled window), 502030 LiPo, and a dovetail foot —
and slides tool-free into either of two docks:

* **`switch_cam_mount.stl`** — the clip-on: C-clamp over the Switch's top
  edge + forward boom, with a dovetail **socket** at the tip (handheld play).
* **`tv_stand.stl`** — a flat desk base with the same socket tilted 12° up:
  set it on the media console pointed at the TV (docked play).
* **`camera_pod.stl`** — the pod both of them accept.

Swap = pinch the pod, slide it forward out of one socket, slide it into
the other until it clicks over the detent and seats on the rear stop.
Electronics never leave the pod; the battery travels with it.

**Why not Bluetooth / a GoPro?** BT can't carry video; action cams can't
focus at 13 cm and don't expose streams to third-party apps. Full
reasoning + shopping list: vault note §11/§11.1. **No extra electronics
for TV mode** — same board, same battery, just one more printed part.

(For TV play you can also skip the rig entirely and point your phone at
the TV on any stand — the app's normal camera mode. The pod route is for
keeping the phone free.)

## Verified geometry (v4)

- Socket tilt solved at **50.2°** for the seated pod: 135 mm to screen
  center, **0.0° aim error, 40° incidence**, worst corner needs ≥72° FOV
  (the 160° module has >2× margin).
- **Ray-cast proof**: five rays from the seated pod's lens (screen center
  + 4 corners) clear both the pod and the mount — nothing printed blocks
  the view (the lesson from v3's user-caught window bug, now a permanent
  check in the generator).
- Every part exports as a **single watertight manifold** (trimesh +
  manifold3d union, micro-jitter against coplanar T-vertices): pod
  7.3 cm³, clip-on 19.2 cm³, stand 22.3 cm³. Walls ≥1.6 mm.
- Dovetail: rail 13.4→9.4 mm trapezoid, slot +0.3 mm/side clearance,
  0.8 mm detent bump. If a vendor prints tight, a few file strokes on the
  rail's flanks free it; if loose, a strip of tape on the rail bottom.
- Clamp torque with the battery now riding in the pod: ~29 g at the boom
  head → ~1.2 N at the jaw pads — still far below what foam friction holds.

## Printing (Craftcloud)

Upload **all three STLs in one order** at [craftcloud3d.com](https://craftcloud3d.com):
PETG, 0.2 mm / standard, supports ON (boom + socket overhangs; the pod's
rail prints with a little support; the stand needs almost none).
~49 cm³ total ≈ $15–25 shipped depending on vendor.

## Assembly (once)

1. Foam-line the clamp jaws (0.5 mm strips; dry-fit first).
2. Swap the 160° camera module onto the XIAO (lift the socket latch).
3. Solder battery leads to the BAT pads (optional inline micro switch).
4. Board into the pod's front bay lens-down over the window; battery into
   the rear bay; wires through the divider gap; one zip tie over each bay
   through the side-wall notches.
5. Flash the Seeed webcam example; join the phone hotspot; stream at
   `http://<ip>:81/stream`. Unscrew the lens ~¼ turn for 13 cm focus
   (the TV stand works at room distance with the same focus — depth of
   field at these apertures covers both).

## Files

- `switch_cam_rig.py` — the CURRENT parametric generator (all 3 parts,
  runs the full verification battery; needs `pip install trimesh manifold3d numpy-stl`).
- `switch_cam_mount.py` — superseded v3 single-piece generator, kept for
  reference.
- `mount_preview.png` — the three parts and both assembled modes.
