#!/usr/bin/env python3
"""Modular Champions camera rig v4.2 — THREE printed parts:

  camera_pod.stl        self-contained pod: XIAO ESP32S3 Sense (lens-down
                        over a beveled window) + 502030 LiPo + dovetail rail
  switch_cam_mount.stl  the proven v3 clamp + boom, head replaced by a
                        dovetail SOCKET (tilt re-solved for the seated pod)
  tv_stand.stl          desk stand: the pod stands ON END against a
                        back-leaning wall, camera looking out through its
                        floor window TV_TILT_UP deg above horizontal

The pod slides into either socket (insert from above/behind, gravity
seats it on the FRONT stop) — tool-free swap between handheld and TV
mode.

v4.2 fixes (found by the slide-sweep + frame tracing):
  * clip-on: the boom-tip wedge was world-axis-aligned under a 50-deg
    tilted plate and poked 1.6 mm up into the dovetail channel — replaced
    by a SOCKET-FRAME connector whose top stays 2 mm below the channel.
  * tv stand: complete redesign. The old 12-deg-from-horizontal socket
    pointed the pod's through-the-floor lens at the DESK. The wall now
    leans (90 + TV_TILT_UP) deg, the pod stands lens-end down, gravity
    runs almost straight down the slide axis onto the stop (pure
    compression), and two legs straddle the light path into the base.
  * socket walls: inner slant re-referenced so the rail keeps the full
    0.3 mm clearance down to its bottom corners (was pinched to 0.14).
  * verification: slide sweeps + light-path ray casts now run for BOTH
    docks, with the pod floated 0.06 mm / started 0.1 mm shy of the stop
    so designed sliding contact registers zero and anything left is real
    interference. All checks hard-fail the build.
"""
import math
import os
import numpy as np

# ---------------------------------------------------------------- meshkit --
FACES = np.array([
    [0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
    [0, 1, 5], [0, 5, 4], [2, 3, 7], [2, 7, 6],
    [1, 2, 6], [1, 6, 5], [3, 0, 4], [3, 4, 7],
])

def rot_x(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0],
                     [0, math.cos(a), -math.sin(a)],
                     [0, math.sin(a), math.cos(a)]])

_jit_n = [0]
def _jit():
    _jit_n[0] += 1
    k = _jit_n[0]
    return np.array([((k * 7) % 11 - 5) * 0.006,
                     ((k * 5) % 9 - 4) * 0.006,
                     ((k * 3) % 7 - 3) * 0.008])

class Part:
    def __init__(self, name):
        self.name = name
        self.verts = []  # list of (8,3)

    def hexa(self, vb, vt, rot=None, pivot=None):
        """Hexahedron from 4 bottom + 4 top corners (each (x, y, z)),
        ordered like the box corners: (-x,-y),(x,-y),(x,y),(-x,y)."""
        v = np.array(list(vb) + list(vt), dtype=float)
        if rot is not None:
            p = np.asarray(pivot, dtype=float)
            v = (v - p) @ np.asarray(rot).T + p
        v = v + _jit()
        self.verts.append(v)
        return v

    def box(self, w, d, h, cx, cy, z0, rot=None, pivot=None):
        x, y = w / 2, d / 2
        vb = [(-x + cx, -y + cy, z0), (x + cx, -y + cy, z0),
              (x + cx, y + cy, z0), (-x + cx, y + cy, z0)]
        vt = [(a, b, z0 + h) for (a, b, _) in vb]
        return self.hexa(vb, vt, rot=rot, pivot=pivot)

    def prism_x(self, xb0, xb1, xt0, xt1, y0, y1, z0, z1,
                rot=None, pivot=None):
        """Prism with a trapezoid X-Z cross-section extruded along Y:
        bottom edge x in [xb0,xb1] at z0, top edge x in [xt0,xt1] at z1."""
        vb = [(xb0, y0, z0), (xb1, y0, z0), (xb1, y1, z0), (xb0, y1, z0)]
        vt = [(xt0, y0, z1), (xt1, y0, z1), (xt1, y1, z1), (xt0, y1, z1)]
        return self.hexa(vb, vt, rot=rot, pivot=pivot)

def local_frame(p, R, origin):
    """Helpers that place geometry expressed in a socket-local frame:
    R maps local -> world, origin = world position of local (0,0,0)."""
    R = np.asarray(R)
    o = np.asarray(origin, dtype=float)
    def hexa_local(vb, vt):
        v = np.array(list(vb) + list(vt), dtype=float)
        p.verts.append((v @ R.T) + o + _jit())
    def box_local(w, d, h, cx, cy, z0):
        x, y = w / 2, d / 2
        vb = [(-x + cx, -y + cy, z0), (x + cx, -y + cy, z0),
              (x + cx, y + cy, z0), (-x + cx, y + cy, z0)]
        vt = [(a, b, z0 + h) for (a, b, _) in vb]
        hexa_local(vb, vt)
    return box_local, hexa_local

# ------------------------------------------------------------- parameters --
GAP = 14.4
LIP_T, LIP_DROP = 2.4, 6.0
BACK_T, BACK_DROP = 3.0, 30.0
W, BRIDGE_T, PAD_W = 40.0, 3.2, 9.0
BOOM_ANGLE, BOOM_LEN = 30.0, 96.0
BOOM_W, BOOM_T = 14.0, 7.0
SCREEN_CENTER = np.array([0.0, -GAP / 2, -45.0])

# Pod (local frame: x across, y along length, -y = front/lens end,
# z up from the dovetail rail bottom).
POD_W = 34.6          # outer width (battery 30 + walls)
POD_FRONT, POD_REAR = -25.0, 23.0
FLOOR_T = 2.4
RAIL_H, RAIL_HALF_B, RAIL_HALF_T = 4.0, 6.7, 4.7   # dovetail male
RAIL_C0, RAIL_C1 = -3.0, 23.0                       # rail span (rear half)
WIN, WY = 12.0, -10.0                               # lens window, center y
BAY_W, BAY_L = 18.2, 21.6                           # XIAO bay
WALL_H = 7.0
# Socket (local frame: same axes; plate z 0..2.4; -y = stop/front end).
SOCK_PLATE_W, SOCK_F, SOCK_R = 26.0, -13.0, 17.0    # plate y span
SOCK_WALL_R = 13.0                                  # walls y span (-13..13)
CLEAR = 0.3                                         # dovetail clearance/side
POD_SEAT_DY = 10.0    # socket_y = pod_y - POD_SEAT_DY (rail front on the stop)
TV_TILT_UP = 20.0     # stand: camera elevation above horizontal
TV_DIST, TV_HALF_W, TV_HALF_H = 1200.0, 610.0, 343.0   # 55" TV ray targets

OUTDIR = "/home/claude/app/hardware"

# ------------------------------------------------------------------- pod ---
def build_pod():
    p = Part("camera_pod")
    # dovetail rail (single segment; top welds 0.4 into the floor)
    p.prism_x(-RAIL_HALF_B, RAIL_HALF_B, -RAIL_HALF_T, RAIL_HALF_T,
              RAIL_C0, RAIL_C1, 0.0, RAIL_H + 0.4)
    z0 = RAIL_H                       # floor bottom
    z1 = RAIL_H + FLOOR_T             # floor top
    half = POD_W / 2
    # floor around the beveled lens window (window x +-6, y WY +-6)
    p.box(half - 6.0, POD_REAR - POD_FRONT, FLOOR_T,
          -(6.0 + half) / 2, (POD_FRONT + POD_REAR) / 2, z0)
    p.box(half - 6.0, POD_REAR - POD_FRONT, FLOOR_T,
          (6.0 + half) / 2, (POD_FRONT + POD_REAR) / 2, z0)
    front_d = (WY - 6.0) - POD_FRONT
    p.box(12.8, front_d + 0.4, FLOOR_T, 0,
          POD_FRONT + (front_d + 0.4) / 2, z0)
    rear_d = POD_REAR - (WY + 6.0)
    p.box(12.8, rear_d + 0.4, FLOOR_T, 0,
          POD_REAR - (rear_d + 0.4) / 2, z0)
    # window bevel: 45-deg flare downward so the 160-deg lens sees no tunnel
    p.prism_x(-8.0, -6.0, -6.4, -6.0, WY - 8, WY + 8, z0, z1)
    p.prism_x(6.0, 8.0, 6.0, 6.4, WY - 8, WY + 8, z0, z1)
    # XIAO bay at the front: side rails + front stop (open to the rear)
    p.box(2.0, BAY_L + 2.0, 5.6, -(BAY_W / 2 + 1.0), POD_FRONT + 1.0 +
          (BAY_L + 2.0) / 2, z1 - 0.4)
    p.box(2.0, BAY_L + 2.0, 5.6, (BAY_W / 2 + 1.0), POD_FRONT + 1.0 +
          (BAY_L + 2.0) / 2, z1 - 0.4)
    p.box(BAY_W + 4.0, 2.0, 5.6, 0, POD_FRONT + 2.0, z1 - 0.4)
    # divider between board and battery (wire gap in the middle)
    dv0 = POD_FRONT + 2.0 + BAY_L     # ~ -1.4
    for x0, x1 in [(-half + 1.0, -3.4), (3.4, half - 1.0)]:
        p.box(x1 - x0, 1.6, 5.6, (x0 + x1) / 2, dv0 + 0.8, z1 - 0.4)
    # outer side walls (segmented: zip-tie notches over both bays)
    for sx in (-1, 1):
        cx = sx * (half - 1.0)
        for y0, y1 in [(POD_FRONT, -14.0), (-9.0, POD_REAR)]:
            p.box(2.0, y1 - y0, WALL_H, cx, (y0 + y1) / 2, z1 - 0.4)
    # front + rear end walls
    p.box(POD_W, 2.0, WALL_H, 0, POD_FRONT + 1.0, z1 - 0.4)
    p.box(POD_W, 2.0, WALL_H, 0, POD_REAR - 1.0, z1 - 0.4)
    return p

# -------------------------------------------------- socket (shared shape) --
def add_socket(p, R, origin):
    """Dovetail socket in a frame: R maps socket-local -> world, origin =
    world position of socket-local (0,0,0). Local: plate z 0..2.4."""
    box_local, hexa_local = local_frame(p, R, origin)
    # plate (extends FORWARD to carry the front stop)
    box_local(SOCK_PLATE_W, SOCK_R - (SOCK_F - 4.0), 2.4, 0,
              ((SOCK_F - 4.0) + SOCK_R) / 2, 0.0)
    # dovetail walls: tops stop 0.4 BELOW the pod floor (z=6.0). The inner
    # slant matches the RAIL's slope exactly (+CLEAR normal offset): the
    # rail profile extrapolated to the wall's z, so clearance is a uniform
    # 0.3 mm from the rail's bottom corner to the wall top (v4.2 fix —
    # referencing the bottom at plate level pinched it to 0.14 mm).
    wall_top = 2.4 + RAIL_H - 0.4
    slope = (RAIL_HALF_B - RAIL_HALF_T) / (RAIL_H + 0.4)   # per mm of z
    wb = RAIL_HALF_B + slope * 0.4 + CLEAR                 # at z = 2.0
    wt = RAIL_HALF_B - slope * (wall_top - 2.4) + CLEAR    # at wall_top
    for sx in (-1, 1):
        if sx < 0:
            hexa_local(
                [(-11.0, -SOCK_WALL_R, 2.0), (-wb, -SOCK_WALL_R, 2.0),
                 (-wb, SOCK_WALL_R, 2.0), (-11.0, SOCK_WALL_R, 2.0)],
                [(-11.0, -SOCK_WALL_R, wall_top),
                 (-wt, -SOCK_WALL_R, wall_top),
                 (-wt, SOCK_WALL_R, wall_top),
                 (-11.0, SOCK_WALL_R, wall_top)])
        else:
            hexa_local(
                [(wb, -SOCK_WALL_R, 2.0), (11.0, -SOCK_WALL_R, 2.0),
                 (11.0, SOCK_WALL_R, 2.0), (wb, SOCK_WALL_R, 2.0)],
                [(wt, -SOCK_WALL_R, wall_top),
                 (11.0, -SOCK_WALL_R, wall_top),
                 (11.0, SOCK_WALL_R, wall_top),
                 (wt, SOCK_WALL_R, wall_top)])
    # FRONT stop bar: rail front face seats against it; gravity presses the
    # pod INTO it on both docks. Its top stays 0.4 below the pod floor and
    # it sits under the window's rear sill — the seated-pod ray-cast
    # verifies it never enters the light path.
    box_local(12.0, 3.0, wall_top - 2.0, 0, SOCK_F - 1.5, 2.0)

# ------------------------------------------------------- clip-on (mount) ---
def build_clipon():
    p = Part("switch_cam_mount")
    p.box(W, LIP_T, LIP_DROP + 0.6, 0, -GAP / 2 - LIP_T / 2, -LIP_DROP)
    p.box(W, BACK_T, BACK_DROP + 0.6, 0, GAP / 2 + BACK_T / 2, -BACK_DROP)
    span = GAP + LIP_T + BACK_T
    span_cy = (-GAP / 2 - LIP_T + GAP / 2 + BACK_T) / 2
    p.box(PAD_W, span, BRIDGE_T, -(W - PAD_W) / 2, span_cy, 0)
    p.box(PAD_W, span, BRIDGE_T, (W - PAD_W) / 2, span_cy, 0)
    p.box(W, LIP_T, BRIDGE_T, 0, -GAP / 2 - LIP_T / 2, 0)
    p.box(W, BACK_T, BRIDGE_T, 0, GAP / 2 + BACK_T / 2, 0)
    root = np.array([0.0, -GAP / 2 - LIP_T / 2, BRIDGE_T])
    Rb = rot_x(90.0 - BOOM_ANGLE)
    p.box(BOOM_W, BOOM_T, BOOM_LEN + 4.0, root[0], root[1], root[2] - 4.0,
          rot=Rb, pivot=root)
    p.box(BOOM_W, 10.0, BRIDGE_T + 4.0, 0, -GAP / 2 - LIP_T - 3.0, -2.0)
    tip = root + Rb @ np.array([0, 0, BOOM_LEN])

    # Solve the socket tilt so the SEATED POD's lens axis hits screen center.
    # Lens (window center) in socket-local coords: pod y=WY maps to socket
    # y = WY - POD_SEAT_DY; lens height = plate 2.4 + rail + floor top.
    lens_local = np.array([0.0, WY - POD_SEAT_DY, 2.4 + RAIL_H + FLOOR_T])
    def aim_error(tilt):
        R = rot_x(tilt)
        lens = R @ lens_local + tip
        ax = R @ np.array([0, 0, -1.0])
        to_c = SCREEN_CENTER - lens
        to_c = to_c / np.linalg.norm(to_c)
        return math.degrees(math.acos(float(np.clip(np.dot(ax, to_c), -1, 1))))
    tilt = min(np.arange(20.0, 75.0, 0.1), key=aim_error)
    R = rot_x(tilt)
    add_socket(p, R, tip)
    # connector tying boom tip to the plate UNDERSIDE — built in the
    # SOCKET frame (v4.2 fix: the old world-axis-aligned wedge poked
    # 1.6 mm through the tilted plate into the dovetail channel). Top
    # welds 0.4 into the plate and never crosses local z 0.4, so it
    # cannot reach the channel (z >= 2.4); its lower half buries into
    # the boom head (axes only ~10 deg apart).
    box_local, _ = local_frame(p, R, tip)
    box_local(BOOM_W, BOOM_T, 8.4, 0.0, 0.0, -8.0)
    return p, tip, tilt, R, lens_local

# ------------------------------------------------------------- tv stand ----
def build_stand():
    """The pod stands ON END against a wall leaning back
    (90 + TV_TILT_UP) deg from horizontal: lens end down, camera looking
    out through the floor window TV_TILT_UP deg above horizontal at the
    TV. Gravity runs almost straight down the slide axis onto the front
    stop (pure compression); the dovetail steadies the pod and resists
    the small prying component. Two legs straddle the light path and
    carry the wall into the base plate; a rib (fully shadowed by the
    plate edge) stiffens the wall's back."""
    p = Part("tv_stand")
    p.box(80.0, 70.0, 3.0, 0, 0, 0)                      # base plate
    Rz180 = np.array([[-1.0, 0, 0], [0, -1.0, 0], [0, 0, 1.0]])
    R = rot_x(-(90.0 + TV_TILT_UP)) @ Rz180   # stop end faces straight down
    # origin height sized so the pod's LOWEST point — the top-front wall
    # corner of the nose-down, back-leaning pod — keeps >2 mm off the base
    origin = np.array([0.0, 5.0, 43.5])
    add_socket(p, R, origin)
    box_local, _ = local_frame(p, R, origin)
    # legs: 0.8 mm y-overlap weld into the plate's bottom edge, far ends
    # embedded THROUGH the base top plane. Inner faces at x +-10.5 —
    # outside the widest ray the window aperture passes at this depth
    # (the stand ray-cast proves it).
    for sx in (-1, 1):
        box_local(5.5, 28.3, 3.2, sx * 13.25, -30.35, -0.8)
    # crossbar tying the leg ends together below the light path
    box_local(32.0, 10.0, 2.4, 0.0, -39.5, 0.0)
    # stiffening rib behind the wall (local z <= 0.4: welded into the
    # plate, never inside the dovetail channel or the light cone)
    box_local(26.0, 25.0, 4.4, 0.0, 2.5, -4.0)
    return p, R, origin

# ----------------------------------------------------------------- export --
import trimesh

def export(part):
    solids = [trimesh.Trimesh(vertices=v, faces=FACES, process=True)
              for v in part.verts]
    for i, s in enumerate(solids):
        if not s.is_volume:
            raise SystemExit(f"{part.name}: part {i} is not a closed volume")
    u = trimesh.boolean.union(solids, engine="manifold")
    if not u.is_watertight:
        raise SystemExit(f"{part.name}: union not watertight")
    if len(u.split(only_watertight=False)) != 1:
        raise SystemExit(f"{part.name}: disconnected bodies")
    path = os.path.join(OUTDIR, f"{part.name}.stl")
    u.export(path)
    print(f"{part.name}: OK  {len(u.faces)} tris  "
          f"{u.volume / 1000:.1f} cm3  bbox {np.round(u.extents, 1)}")
    return u

os.makedirs(OUTDIR, exist_ok=True)
pod = build_pod()
clipon, tip, TILT, Rt, lens_local = build_clipon()
stand, Rs, stand_origin = build_stand()
pod_m = export(pod)
clip_m = export(clipon)
stand_m = export(stand)
print(f"solved clip-on socket tilt: {TILT:.1f} deg; "
      f"stand camera elevation: {TV_TILT_UP:.0f} deg")

# ------------------------------------------------------------ validation ---
SEAT_LOCAL = np.array([0.0, -POD_SEAT_DY, 2.4])

def seat_pod(R, origin, off=0.0, lift=0.0):
    pm = pod_m.copy()
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = origin + R @ (SEAT_LOCAL + np.array([0.0, off, lift]))
    pm.apply_transform(T)
    return pm

def sweep(dock_m, R, origin, label):
    """Slide-path check with the pod floated 0.06 mm off the sliding
    surface and started 0.1 mm shy of the stop, so DESIGNED contact
    (rail bottom on plate top, rail front face on the stop) registers
    zero — anything left is real interference."""
    bad = False
    for off in (0.1, 6.0, 14.0, 26.0, 40.0):
        pm = seat_pod(R, origin, off=off, lift=0.06)
        inter = trimesh.boolean.intersection([pm, dock_m], engine="manifold")
        vol = 0.0 if inter.is_empty else inter.volume
        ok = vol < 0.5
        bad = bad or not ok
        print(f"  {label} slide {off:4.1f} mm: intersection {vol:6.2f} mm3  "
              f"{'OK' if ok else 'COLLISION'}")
    if bad:
        raise SystemExit(f"{label}: slide-path collision — DO NOT PRINT")

def ray_check(dock_m, R, origin, targets, label):
    pm = seat_pod(R, origin)
    assembly = trimesh.util.concatenate([dock_m, pm])
    lens = R @ lens_local + origin
    dirs = [(t - lens) / np.linalg.norm(t - lens) for t in targets]
    origins = np.array([lens + dd * 2.5 for dd in dirs])
    hits = assembly.ray.intersects_any(origins, np.array(dirs))
    print(f"  {label} rays blocked (must all be False): {hits.tolist()}")
    if any(hits):
        raise SystemExit(f"{label}: printed part blocks the light path")
    return lens

# --- clip-on: aim numbers + Switch-screen rays + sweep
lens = Rt @ lens_local + tip
axis = Rt @ np.array([0, 0, -1.0])
to_c = SCREEN_CENTER - lens
d = np.linalg.norm(to_c)
aim = math.degrees(math.acos(float(np.clip(np.dot(axis, to_c / d), -1, 1))))
inc = math.degrees(math.acos(float(
    np.clip(np.dot(-to_c / d, np.array([0, -1.0, 0])), -1, 1))))
corners = [np.array([sx * 77.5, -GAP / 2, z])
           for sx in (-1, 1) for z in (-11.0, -98.0)]
fovs = [math.degrees(math.acos(float(np.clip(
    np.dot(axis, (c - lens) / np.linalg.norm(c - lens)), -1, 1))))
    for c in corners]
print(f"clip-on: lens y={lens[1]:.0f} z={lens[2]:.0f}  dist {d:.0f} mm  "
      f"aim {aim:.1f} deg  incidence {inc:.0f} deg  "
      f"need >= {2 * max(fovs):.0f} deg lens")
ray_check(clip_m, Rt, tip, [lens + axis * d] + corners, "clip-on")
sweep(clip_m, Rt, tip, "clip-on")

# --- stand: aim numbers + virtual-TV rays + sweep
s_axis = Rs @ np.array([0, 0, -1.0])
elev = math.degrees(math.asin(float(s_axis[2])))
tv_c = (Rs @ lens_local + stand_origin) + s_axis * TV_DIST
tv_up = np.array([0.0, s_axis[2], -s_axis[1]])   # perp to axis, in Y-Z
tv_corners = [tv_c + sx * TV_HALF_W * np.array([1.0, 0, 0]) + sz * TV_HALF_H * tv_up
              for sx in (-1, 1) for sz in (-1, 1)]
s_fovs = [math.degrees(math.acos(float(np.clip(
    np.dot(s_axis, (c - (Rs @ lens_local + stand_origin)) /
           np.linalg.norm(c - (Rs @ lens_local + stand_origin))), -1, 1))))
    for c in tv_corners]
s_lens = Rs @ lens_local + stand_origin
print(f"stand: lens {s_lens[2]:.0f} mm above desk, elevation {elev:.1f} deg; "
      f"55\" TV at {TV_DIST:.0f} mm needs >= {2 * max(s_fovs):.0f} deg lens")
ray_check(stand_m, Rs, stand_origin, [tv_c] + tv_corners, "stand")
sweep(stand_m, Rs, stand_origin, "stand")

# --- dovetail numbers
print(f"dovetail: rail {2*RAIL_HALF_B:.1f}->{2*RAIL_HALF_T:.1f} mm, uniform "
      f"{CLEAR} mm/side clearance; wall tops 0.4 mm below the pod floor")
print("ALL CHECKS PASSED — safe to print")
