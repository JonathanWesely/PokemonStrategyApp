#!/usr/bin/env python3
"""Switch top-edge camera mount for the XIAO ESP32S3 Sense (wide lens).

Design: C-clamp hooks over the console's top edge (fits all Switch models,
13.9 mm thick), a thin boom cantilevers FORWARD over the screen at 30 deg,
and the camera tray at its tip tilts 40 deg back-down so the lens looks at
the screen center from ~75 mm in front / ~45 mm above the top edge
(~117 mm optical distance, ~40 deg off the screen normal — readable, and
the exemplar matcher learns from exactly this viewpoint anyway).

Battery tray rides LOW on the back plate to counterweight the boom.
Slide the clamp anywhere along the edge — keep it off the vent slots.

Output: one binary STL of overlapping closed cuboid shells (every slicer
unions them). Print flat on the back plate, PETG, 3-4 perimeters.
"""
import math
import os
import numpy as np
from stl import mesh

OUT = "/home/claude/app/hardware/switch_cam_mount.stl"

# ------------------------------------------------------------------ mesh --
FACES = np.array([
    [0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
    [0, 1, 5], [0, 5, 4], [2, 3, 7], [2, 7, 6],
    [1, 2, 6], [1, 6, 5], [3, 0, 4], [3, 4, 7],
])
parts = []

def rot_x(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0],
                     [0, math.cos(a), -math.sin(a)],
                     [0, math.sin(a), math.cos(a)]])

def box(w, d, h, cx, cy, z0, rot=None, pivot=None):
    """Cuboid: width x (along edge), depth y, height z, base at z0,
    centered at (cx, cy). Optional rotation about pivot."""
    x, y = w / 2, d / 2
    v = np.array([
        [-x, -y, 0], [x, -y, 0], [x, y, 0], [-x, y, 0],
        [-x, -y, h], [x, -y, h], [x, y, h], [-x, y, h]], dtype=float)
    v[:, 0] += cx
    v[:, 1] += cy
    v[:, 2] += z0
    if rot is not None:
        p = np.asarray(pivot, dtype=float)
        v = (v - p) @ np.asarray(rot).T + p
    parts.append(v)
    return v

# ------------------------------------------------------------ parameters --
# Coordinates: x along the top edge, y front(-)/back(+), z up.
# Console top surface = z 0; console front (screen side) face at y = -GAP/2.
GAP = 14.4        # 13.9 mm console + foam allowance
LIP_T = 2.4       # front lip thickness
LIP_DROP = 6.0    # stays on the ~11 mm bezel, never over pixels
BACK_T = 3.0
BACK_DROP = 30.0
W = 40.0          # clamp width
BRIDGE_T = 3.2
PAD_W = 9.0       # bridge contact pads (vent-relief cutout between them)

BOOM_ANGLE = 30.0   # above horizontal, leaning forward over the screen
BOOM_LEN = 96.0
BOOM_W, BOOM_T = 14.0, 7.0

TILT = 40.0         # camera tray tilt: lens looks back-down at the screen
PL_W, PL_D, PL_T = 26.0, 30.0, 2.4   # tray plate
RIM = 2.0
BAY_W = 18.2        # XIAO ESP32S3 Sense: 17.8 wide, 21 long
WIN = 12.0          # lens window in the plate

SCREEN_CENTER = np.array([0.0, -GAP / 2, -45.0])   # ~45 mm below top edge

# ---------------------------------------------------------------- clamp ----
box(W, LIP_T, LIP_DROP, 0, -GAP / 2 - LIP_T / 2, -LIP_DROP)     # front lip
box(W, BACK_T, BACK_DROP, 0, GAP / 2 + BACK_T / 2, -BACK_DROP)  # back plate
span = GAP + LIP_T + BACK_T
span_cy = (-GAP / 2 - LIP_T + GAP / 2 + BACK_T) / 2
box(PAD_W, span, BRIDGE_T, -(W - PAD_W) / 2, span_cy, 0)        # bridge pad L
box(PAD_W, span, BRIDGE_T, (W - PAD_W) / 2, span_cy, 0)         # bridge pad R
box(W, LIP_T, BRIDGE_T, 0, -GAP / 2 - LIP_T / 2, 0)             # front spine
box(W, BACK_T, BRIDGE_T, 0, GAP / 2 + BACK_T / 2, 0)            # rear spine

# ----------------------------------------------------------------- boom ----
# Root at the front spine top, leaning forward BOOM_ANGLE above horizontal.
root = np.array([0.0, -GAP / 2 - LIP_T / 2, BRIDGE_T])
Rb = rot_x(90.0 - BOOM_ANGLE)   # tips the boom forward-UP over the screen
box(BOOM_W, BOOM_T, BOOM_LEN, root[0], root[1], root[2] - 0.0,
    rot=Rb, pivot=root)
# gusset at the root so the boom doesn't hinge at a layer line
box(BOOM_W, 10.0, BRIDGE_T + 4.0, 0, -GAP / 2 - LIP_T - 3.0, -2.0)

tip = root + Rb @ np.array([0, 0, BOOM_LEN])   # boom tip center

# ----------------------------------------------------------------- head ----
head = []
def hbox(w, d, h, cx, cy, z0):
    x, y = w / 2, d / 2
    v = np.array([
        [-x, -y, 0], [x, -y, 0], [x, y, 0], [-x, y, 0],
        [-x, -y, h], [x, -y, h], [x, y, h], [-x, y, h]], dtype=float)
    v[:, 0] += cx
    v[:, 1] += cy
    v[:, 2] += z0
    head.append(v)
    return v

# Pre-tilt: tray plate horizontal at the boom tip, board bay on top, the
# lens window centered at the tip; the XIAO sits lens-down over the window.
hy, hz = tip[1], tip[2]
strip = (PL_W - WIN) / 2
# plate strips around the lens window (window centered on the tip)
hbox(strip, PL_D, PL_T, -(WIN + strip) / 2, hy, hz)
hbox(strip, PL_D, PL_T, (WIN + strip) / 2, hy, hz)
edge = (PL_D - WIN) / 2
hbox(WIN, edge, PL_T, 0, hy - (WIN + edge) / 2, hz)
hbox(WIN, edge, PL_T, 0, hy + (WIN + edge) / 2, hz)
# rim walls (open toward the boom side to slide the board in)
hbox(RIM, PL_D, 6.0, -(BAY_W / 2 + RIM / 2), hy, hz + PL_T)
hbox(RIM, PL_D, 6.0, (BAY_W / 2 + RIM / 2), hy, hz + PL_T)
hbox(BAY_W + 2 * RIM, RIM, 6.0, 0, hy - PL_D / 2 + RIM / 2, hz + PL_T)
# zip-tie bars under the plate
hbox(PL_W, 4.0, 2.0, 0, hy - PL_D / 2 + 6.0, hz - 2.0)
hbox(PL_W, 4.0, 2.0, 0, hy + PL_D / 2 - 6.0, hz - 2.0)

# Tilt head about the boom tip so the lens looks back-down at the screen.
Rh = rot_x(TILT)
for v in head:
    parts.append((v - tip) @ Rh.T + tip)
# small wedge joining boom tip and head underside
box(BOOM_W, BOOM_T, 8.0, tip[0], tip[1], tip[2] - 6.0)

# ------------------------------------------------------------ battery tray --
BT_W, BT_D = 32.0, 7.5     # 502030 LiPo: 30 x 20 x ~5.5
bt_y = GAP / 2 + BACK_T
box(BT_W, BT_D, 2.0, 0, bt_y + BT_D / 2, -28.0)                  # floor
box(BT_W, 2.0, 22.0, 0, bt_y + BT_D - 1.0, -28.0)                # outer wall
box(2.0, BT_D, 22.0, -(BT_W / 2 - 1.0), bt_y + BT_D / 2, -28.0)  # side L
box(2.0, BT_D, 22.0, (BT_W / 2 - 1.0), bt_y + BT_D / 2, -28.0)   # side R

# ---------------------------------------------------------------- export ----
data = np.zeros(len(parts) * len(FACES), dtype=mesh.Mesh.dtype)
for i, v in enumerate(parts):
    for j, f in enumerate(FACES):
        data["vectors"][i * len(FACES) + j] = v[f]
m = mesh.Mesh(data)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
m.save(OUT)

# ------------------------------------------------------------- validation --
all_v = np.vstack(parts)
lens_pre = np.array([0.0, hy, hz])
lens = (lens_pre - tip) @ Rh.T + tip
axis = Rh @ np.array([0, 0, -1.0])          # lens optical axis
to_c = SCREEN_CENTER - lens
dist = np.linalg.norm(to_c)
off = math.degrees(math.acos(float(np.clip(np.dot(axis, to_c / dist), -1, 1))))
normal = np.array([0, -1.0, 0])             # screen normal
inc = math.degrees(math.acos(float(np.clip(np.dot(-to_c / dist, normal), -1, 1))))
# FOV needed for the 7" screen (155 x 87, top of glass ~11 mm below edge)
corners = [np.array([sx * 77.5, -GAP / 2, z])
           for sx in (-1, 1) for z in (-11.0, -98.0)]
angles = [math.degrees(math.acos(float(np.clip(
    np.dot(axis, (c - lens) / np.linalg.norm(c - lens)), -1, 1))))
    for c in corners]
def vol(msh):
    v0, v1, v2 = msh.vectors[:, 0], msh.vectors[:, 1], msh.vectors[:, 2]
    return abs(np.einsum('ij,ij->i', v0, np.cross(v1, v2)).sum()) / 6.0

print(f"parts {len(parts)}  triangles {len(data)}")
print(f"bbox x {all_v[:,0].min():.0f}..{all_v[:,0].max():.0f}  "
      f"y {all_v[:,1].min():.0f}..{all_v[:,1].max():.0f}  "
      f"z {all_v[:,2].min():.0f}..{all_v[:,2].max():.0f} (mm)")
print(f"volume {vol(m)/1000:.1f} cm3  (~printed weight w/ infill ≈ "
      f"{vol(m)/1000*1.27*0.5:.0f} g PETG)")
print(f"lens position y={lens[1]:.0f} z={lens[2]:.0f} "
      f"(={-lens[1]-GAP/2:.0f} mm in front of screen, {lens[2]:.0f} mm up)")
print(f"distance to screen center {dist:.0f} mm  "
      f"aim error {off:.1f} deg  incidence {inc:.0f} deg from screen normal")
print(f"max half-FOV to corners {max(angles):.1f} deg "
      f"-> need ≥{2*max(angles):.0f} deg lens (120 deg module: ok)")
