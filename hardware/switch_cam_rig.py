#!/usr/bin/env python3
"""Modular Champions camera rig v4 — THREE printed parts:

  camera_pod.stl        self-contained pod: XIAO ESP32S3 Sense (lens-down
                        over a beveled window) + 502030 LiPo + dovetail rail
  switch_cam_mount.stl  the proven v3 clamp + boom, head replaced by a
                        dovetail SOCKET (tilt re-solved for the seated pod)
  tv_stand.stl          desk base with the same socket, tilted 12 deg up,
                        for docked/TV play

The pod slides into either socket (insert from the front, click over a
detent, seat against the rear stop) — tool-free swap between handheld and
TV mode. Same verification discipline as v3: every part boolean-unioned
into a single watertight manifold, micro-jitter against coplanar
T-vertices, and a ray-cast from the lens of the SEATED pod proving the
light path clears both the pod and the mount.
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
DET_G0, DET_G1 = 0.3, 3.7                           # detent gap in the rail
WIN, WY = 12.0, -10.0                               # lens window, center y
BAY_W, BAY_L = 18.2, 21.6                           # XIAO bay
WALL_H = 7.0
# Socket (local frame: same axes; plate z 0..2.4; -y = insert/front).
SOCK_PLATE_W, SOCK_F, SOCK_R = 26.0, -13.0, 17.0    # plate y span
SOCK_WALL_R = 13.0                                  # walls y span (-13..13)
CLEAR = 0.3                                         # dovetail clearance/side
STOP_Y0, STOP_Y1 = 13.0, 16.0                       # rear stop bar
POD_SEAT_DY = 10.0    # socket_y = pod_y - POD_SEAT_DY (rail rear hits the stop)
TV_TILT_UP = 12.0

OUTDIR = "/home/claude/app/hardware"

# ------------------------------------------------------------------- pod ---
def build_pod():
    p = Part("camera_pod")
    # dovetail rail (two segments, detent gap between); tops weld 0.4 into
    # the floor so the union is one body
    for y0, y1 in [(RAIL_C0, DET_G0), (DET_G1, RAIL_C1)]:
        p.prism_x(-RAIL_HALF_B, RAIL_HALF_B, -RAIL_HALF_T, RAIL_HALF_T,
                  y0, y1, 0.0, RAIL_H + 0.4)
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
        for y0, y1 in [(POD_FRONT, -14.0), (-9.0, 8.0), (13.0, POD_REAR)]:
            p.box(2.0, y1 - y0, WALL_H, cx, (y0 + y1) / 2, z1 - 0.4)
    # front + rear end walls
    p.box(POD_W, 2.0, WALL_H, 0, POD_FRONT + 1.0, z1 - 0.4)
    p.box(POD_W, 2.0, WALL_H, 0, POD_REAR - 1.0, z1 - 0.4)
    return p

# -------------------------------------------------- socket (shared shape) --
def add_socket(p, R, origin):
    """Dovetail socket in a frame: R maps socket-local -> world, origin =
    world position of socket-local (0,0,0). Local: plate z 0..2.4."""
    def tf(part_verts):
        return (np.asarray(part_verts) @ R.T) + origin
    def hexa_local(vb, vt):
        v = np.array(list(vb) + list(vt), dtype=float)
        p.verts.append(tf(v) + _jit())
    def box_local(w, d, h, cx, cy, z0):
        x, y = w / 2, d / 2
        vb = [(-x + cx, -y + cy, z0), (x + cx, -y + cy, z0),
              (x + cx, y + cy, z0), (-x + cx, y + cy, z0)]
        vt = [(a, b, z0 + h) for (a, b, _) in vb]
        hexa_local(vb, vt)
    # plate (extends rear to carry the stop)
    box_local(SOCK_PLATE_W, SOCK_R - SOCK_F, 2.4, 0,
              (SOCK_F + SOCK_R) / 2, 0.0)
    # dovetail walls: inner faces slant matching the rail + clearance
    wb, wt = RAIL_HALF_B + CLEAR, RAIL_HALF_T + CLEAR
    for sx in (-1, 1):
        if sx < 0:
            hexa_local(
                [(-11.0, -SOCK_WALL_R, 2.0), (-wb, -SOCK_WALL_R, 2.0),
                 (-wb, SOCK_WALL_R, 2.0), (-11.0, SOCK_WALL_R, 2.0)],
                [(-11.0, -SOCK_WALL_R, 2.4 + RAIL_H + 0.3),
                 (-wt, -SOCK_WALL_R, 2.4 + RAIL_H + 0.3),
                 (-wt, SOCK_WALL_R, 2.4 + RAIL_H + 0.3),
                 (-11.0, SOCK_WALL_R, 2.4 + RAIL_H + 0.3)])
        else:
            hexa_local(
                [(wb, -SOCK_WALL_R, 2.0), (11.0, -SOCK_WALL_R, 2.0),
                 (11.0, SOCK_WALL_R, 2.0), (wb, SOCK_WALL_R, 2.0)],
                [(wt, -SOCK_WALL_R, 2.4 + RAIL_H + 0.3),
                 (11.0, -SOCK_WALL_R, 2.4 + RAIL_H + 0.3),
                 (11.0, SOCK_WALL_R, 2.4 + RAIL_H + 0.3),
                 (wt, SOCK_WALL_R, 2.4 + RAIL_H + 0.3)])
    # rear stop bar
    box_local(2 * RAIL_HALF_B, STOP_Y1 - STOP_Y0, RAIL_H + 0.3, 0,
              (STOP_Y0 + STOP_Y1) / 2, 2.0)
    # detent bump on the plate (lands in the rail's gap when seated)
    box_local(6.0, 2.6, 0.8, 0, -8.0, 2.4 - 0.2)

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
    # wedge tying boom tip to socket underside
    p.box(BOOM_W, BOOM_T, 8.0, tip[0], tip[1], tip[2] - 6.0)
    # battery no longer lives on the clamp — back plate stays as the jaw.
    return p, tip, tilt, R, lens_local

# ------------------------------------------------------------- tv stand ----
def build_stand():
    p = Part("tv_stand")
    p.box(80.0, 70.0, 3.0, 0, 0, 0)                      # base plate
    R = rot_x(-TV_TILT_UP)                               # tilt socket UP
    origin = np.array([0.0, 5.0, 6.0])
    # riser wedge under the socket plate
    p.prism_x(-13.0, 13.0, -13.0, 13.0, -14.0, 22.0, 2.6, 6.5)
    add_socket(p, R, origin)
    return p

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
stand = build_stand()
pod_m = export(pod)
clip_m = export(clipon)
stand_m = export(stand)
print(f"solved socket tilt: {TILT:.1f} deg")

# ------------------------------------------------------------ validation ---
# Seat the pod in the clip-on socket and ray-check the light path.
pod_seated = pod_m.copy()
T = np.eye(4)
T[:3, :3] = Rt
seat_local = np.array([0.0, -POD_SEAT_DY, 2.4])   # pod origin in socket frame
T[:3, 3] = tip + Rt @ seat_local
pod_seated.apply_transform(T)
assembly = trimesh.util.concatenate([clip_m, pod_seated])

lens = Rt @ lens_local + tip
axis = Rt @ np.array([0, 0, -1.0])
to_c = SCREEN_CENTER - lens
d = np.linalg.norm(to_c)
aim = math.degrees(math.acos(float(np.clip(np.dot(axis, to_c / d), -1, 1))))
inc = math.degrees(math.acos(float(
    np.clip(np.dot(-to_c / d, np.array([0, -1.0, 0])), -1, 1))))
corners = [np.array([sx * 77.5, -GAP / 2, z])
           for sx in (-1, 1) for z in (-11.0, -98.0)]
dirs = [axis / np.linalg.norm(axis)] + \
       [(c - lens) / np.linalg.norm(c - lens) for c in corners]
origins = np.array([lens + dd * 2.5 for dd in dirs])
hits = assembly.ray.intersects_any(origins, np.array(dirs))
fovs = [math.degrees(math.acos(float(np.clip(
    np.dot(axis, (c - lens) / np.linalg.norm(c - lens)), -1, 1))))
    for c in corners]
print(f"lens y={lens[1]:.0f} z={lens[2]:.0f}  dist {d:.0f} mm  "
      f"aim {aim:.1f} deg  incidence {inc:.0f} deg  "
      f"need >= {2 * max(fovs):.0f} deg lens")
print(f"rays blocked (must all be False): {hits.tolist()}")
# Dovetail sanity: clearance both sides
print(f"dovetail: rail {2*RAIL_HALF_B:.1f}->{2*RAIL_HALF_T:.1f} mm, "
      f"slot {2*(RAIL_HALF_B+CLEAR):.1f}->{2*(RAIL_HALF_T+CLEAR):.1f} mm "
      f"({CLEAR} mm/side clearance)")
