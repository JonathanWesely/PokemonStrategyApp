# Handheld + TV camera rig (v4.2, modular)

One camera, two homes. The **camera pod** is self-contained — XIAO ESP32S3
Sense (lens-down over a beveled window), 502030 LiPo, and a dovetail foot —
and slides tool-free into either of two docks:

* **`switch_cam_mount.stl`** — the clip-on: C-clamp over the Switch's top
  edge + forward boom, with a dovetail **socket** at the tip (handheld play).
* **`tv_stand.stl`** — a desk base with a back-leaning wall carrying the
  same socket: the pod stands **on end**, lens end down, camera looking
  out 20° above horizontal at the TV (docked play).
* **`camera_pod.stl`** — the pod both of them accept.

Swap = slide the pod up/back out of one socket, slide it into the other
until the rail seats on the **front stop**. On both docks gravity presses
the pod *into* the stop (no detent needed — v4.1 deleted it after the
kinematic audit showed it would jam). Electronics never leave the pod;
the battery travels with it.

**Why not Bluetooth / a GoPro?** BT can't carry video; action cams can't
focus at 13 cm and don't expose streams to third-party apps. Full
reasoning + shopping list: vault note §11/§11.1. **No extra electronics
for TV mode** — same board, same battery, just one more printed part.

(For TV play you can also skip the rig entirely and point your phone at
the TV on any stand — the app's normal camera mode. The pod route is for
keeping the phone free.)

## Verified geometry (v4.2)

Every check below is run by the generator and **hard-fails the build** if
violated — the STLs in this folder only exist because all of them passed.

- **Clip-on**: socket tilt solved at **50.2°** for the seated pod: 135 mm
  to screen center, **0.0° aim error, 40° incidence**, worst corner needs
  ≥72° FOV (the 160° module has >2× margin).
- **TV stand**: pod stands against a wall leaning 20° past vertical —
  lens 22 mm above the desk, elevation exactly 20°. A 55″ TV at 1.2 m
  needs ≥61° FOV; two legs straddle the light path (inner faces ±10.5 mm,
  outside the widest ray the window aperture passes).
- **Ray-cast proof on BOTH docks**: five rays from the seated pod's lens
  (screen/TV center + 4 corners) clear the pod and the dock — nothing
  printed blocks the view (the lesson from v3's user-caught window bug).
- **Slide-path sweep on BOTH docks**: the pod is swept along the
  insertion axis (floated 0.06 mm, started 0.1 mm shy of the stop so
  designed sliding contact registers zero) — 0.00 mm³ interference at
  every offset. This sweep is what caught v4's two real flaws: the
  boom-tip wedge poking 1.6 mm into the clip-on's dovetail channel, and
  the old TV stand's riser doing the same (that stand's socket also
  pointed the lens at the *desk* — it was redesigned outright).
- Every part exports as a **single watertight manifold** (trimesh +
  manifold3d union, micro-jitter against coplanar T-vertices), and
  re-verifies watertight/single-body on reload: pod 7.6 cm³, clip-on
  19.1 cm³, stand 23.9 cm³. Walls ≥1.6 mm.
- Dovetail: rail 13.4→9.4 mm trapezoid, slot with a **uniform 0.3 mm/side
  clearance** (v4.2 re-referenced the wall slant — v4 pinched the rail's
  bottom corners to 0.14 mm). If a vendor prints tight, a few file
  strokes on the rail's flanks free it; if loose, a strip of tape on the
  rail bottom.
- Clamp torque with the battery riding in the pod: ~29 g at the boom
  head → ~1.2 N at the jaw pads — far below what foam friction holds.

## Printing (Craftcloud)

Upload **all three STLs in one order** at [craftcloud3d.com](https://craftcloud3d.com):
PETG, 0.2 mm / standard, supports ON (boom + socket overhangs; the pod's
rail prints with a little support; the stand's leaning wall needs support
too). ~51 cm³ total ≈ $15–25 shipped depending on vendor.

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

## TV-mode placement

Put the stand on the media console roughly centered under the TV, front
edge (the leg side) toward the screen. The camera's usable cone reaches
~38° above horizontal and far below — a TV whose center sits up to
~80 cm above the console at 1.2 m is fully covered; for a high
wall-mounted TV, just set the stand farther back.

## Files

- `switch_cam_rig.py` — the CURRENT parametric generator (all 3 parts,
  runs the full verification battery; needs `pip install trimesh manifold3d numpy-stl`).
- `switch_cam_mount.py` — superseded v3 single-piece generator, kept for
  reference.
- `mount_preview.png` — the three parts and both assembled modes.
