import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

POD_W, POD_FRONT, POD_REAR = 34.6, -25.0, 23.0
FLOOR_T, RAIL_H = 2.4, 4.0
RAIL_C0, RAIL_C1 = -3.0, 23.0
WIN, WY = 12.0, -10.0
BAY_W, BAY_L, WALL_T = 18.2, 21.6, 2.0
ZF_B, ZF_T, Z_TOP = RAIL_H, RAIL_H + FLOOR_T, 13.0
BAY_Y0, BAY_Y1 = POD_FRONT + 2.0, POD_FRONT + 2.0 + BAY_L
REAR_Y0, REAR_Y1 = BAY_Y1 + 1.6, POD_REAR - WALL_T

W, H = 990, 704
s = Svg(W, H, "Pod loading — exploded side view and top view, to scale")
s.text(24, 32, "Pod loading — drawn to scale from the printed part", size=17, weight="700")
s.text(24, 52, "Board goes in lens-down over the window; battery lies across the pod in the rear bay; both wires cross through the divider gap.",
       size=12, fill=MUTED)

# ================================================== EXPLODED SIDE VIEW ====
K = 6.4
OX, OY = 220, 400
def sx(y): return OX + y * K
def sz(z): return OY - z * K

s.text(60, 104, "SIDE VIEW — exploded, cut lengthwise down the middle", size=13, weight="700")

# ---- floating parts, labels on fixed rows
FL = 244
s.text(sx(-12), 150, "XIAO + Sense board", size=10.5, weight="700", anchor="middle")
s.text(sx(-12), 163, "USB-C up · 160° module lens-down", size=9.5, fill=MUTED, anchor="middle")
s.text(sx(11), 150, "502030 LiPo", size=10.5, weight="700", anchor="middle")
s.text(sx(11), 163, "5 mm thick", size=9.5, fill=MUTED, anchor="middle")

s.rect(sx(BAY_Y0), FL - 20, BAY_L * K, 20, fill="#eef2ff", stroke=INK, sw=1.6, rx=2)
s.rect(sx(WY - 4), FL, 8 * K, 13, fill="#374151", stroke=INK, sw=1.3, rx=1)
s.rect(sx(-22.5), FL - 31, 5 * K, 11, fill="#9ca3af", stroke=INK, sw=1.2, rx=2)
s.rect(sx(REAR_Y0), FL - 22, (REAR_Y1 - REAR_Y0) * K, 22, fill=PANEL, stroke=INK, sw=1.6, rx=2)
s.text(sx(-7), FL + 27, "160° module, lens-down", size=9.5, fill="#374151", anchor="start", weight="700")

s.line(sx(-19), FL + 6, sx(-19), sz(Z_TOP) - 12, stroke=INK, sw=1.8, marker="arrow", dash="5 4")
s.line(sx(11), FL + 6, sx(11), sz(Z_TOP) - 12, stroke=INK, sw=1.8, marker="arrow", dash="5 4")

# ---- pod shell (cut plane = middle, so no side walls here)
s.line(sx(POD_FRONT), sz(Z_TOP), sx(POD_REAR), sz(Z_TOP), stroke=LIGHT, sw=1.2, dash="6 4")
s.text(sx(19), sz(Z_TOP) - 7, "side-wall top edge", size=9, fill=LIGHT, anchor="middle")
s.rect(sx(RAIL_C0), sz(RAIL_H), (RAIL_C1 - RAIL_C0) * K, RAIL_H * K, fill="#e5e7eb", stroke=INK, sw=1.4)
s.rect(sx(POD_FRONT), sz(ZF_T), (WY - 6 - POD_FRONT) * K, FLOOR_T * K, fill="#dbeafe", stroke=INK, sw=1.4)
s.rect(sx(WY + 6), sz(ZF_T), (POD_REAR - (WY + 6)) * K, FLOOR_T * K, fill="#dbeafe", stroke=INK, sw=1.4)
s.path(f"M{sx(WY-6)},{sz(ZF_T)} L{sx(WY-8)},{sz(ZF_B)}", stroke=INK, sw=1.3)
s.path(f"M{sx(WY+6)},{sz(ZF_T)} L{sx(WY+8)},{sz(ZF_B)}", stroke=INK, sw=1.3)
# end walls (in the cut plane) + divider
s.rect(sx(POD_FRONT), sz(Z_TOP), WALL_T * K, (Z_TOP - ZF_T) * K, fill="#f1f5f9", stroke=INK, sw=1.4)
s.rect(sx(POD_REAR - WALL_T), sz(Z_TOP), WALL_T * K, (Z_TOP - ZF_T) * K, fill="#f1f5f9", stroke=INK, sw=1.4)
s.rect(sx(BAY_Y1), sz(12.0), 1.6 * K, (12.0 - ZF_T) * K, fill="#d1d5db", stroke=INK, sw=1.3)

# bay callouts inside the shell
s.text(sx(-12), sz(9.6), "FRONT BAY", size=9.5, fill=MUTED, anchor="middle", weight="700")
s.text(sx(-12), sz(7.9), "board", size=9, fill=MUTED, anchor="middle")
s.text(sx(11), sz(9.6), "REAR BAY", size=9.5, fill=MUTED, anchor="middle", weight="700")
s.text(sx(11), sz(7.9), "battery", size=9, fill=MUTED, anchor="middle")

s.text(sx(POD_FRONT) - 6, sz(10.0), "FRONT", size=10, weight="700", anchor="end")
s.text(sx(POD_FRONT) - 6, sz(8.2), "(lens end)", size=9, fill=MUTED, anchor="end")
s.text(sx(POD_REAR) + 6, sz(10.0), "REAR", size=10, weight="700")
s.text(sx(BAY_Y1 + 5.5), sz(11.4), "divider", size=9.5, fill=MUTED)
s.path(f"M{sx(BAY_Y1+5)},{sz(11.0)} L{sx(BAY_Y1+2.2)},{sz(10.4)}", stroke=MUTED, sw=0.9)

# below-shell labels
s.path(f"M{sx(WY)},{sz(ZF_B)} L{sx(WY)},{sz(0)+16}", stroke=BLUE, sw=1, dash="3 2")
s.text(sx(WY), sz(0) + 28, "12 mm lens window", size=10, fill=BLUE, anchor="middle", weight="700")
s.text(sx(WY), sz(0) + 40, "(45° bevel)", size=9.5, fill=BLUE, anchor="middle")
s.text(sx(13), sz(0) + 28, "dovetail rail", size=10, fill=MUTED, anchor="middle")
s.line(sx(POD_FRONT), sz(0) + 56, sx(POD_REAR), sz(0) + 56, stroke=MUTED, sw=1, marker="arrowM")
s.line(sx(POD_REAR), sz(0) + 56, sx(POD_FRONT), sz(0) + 56, stroke=MUTED, sw=1, marker="arrowM")
s.text(sx(-1), sz(0) + 70, "48 mm", size=10, fill=MUTED, anchor="middle")

# ============================================================= TOP VIEW ====
KT = 5.6
TX, TY = 566, 186
def tx(y): return TX + (y - POD_FRONT) * KT
def ty(x): return TY + (x + POD_W / 2) * KT

s.text(TX, 104, "TOP VIEW — looking down into the open pod", size=13, weight="700")
s.text(TX, 122, "(pod is 48 × 34.6 mm; same scale both directions)", size=10, fill=MUTED)
s.rect(tx(POD_FRONT), ty(-POD_W / 2), (POD_REAR - POD_FRONT) * KT, POD_W * KT,
       fill="#f8fafc", stroke=INK, sw=1.8, rx=3)
for xoff in (-POD_W / 2, POD_W / 2 - WALL_T):
    s.rect(tx(POD_FRONT), ty(xoff), (POD_REAR - POD_FRONT) * KT, WALL_T * KT,
           fill="#e5e7eb", stroke=LIGHT, sw=1)
    s.rect(tx(-14), ty(xoff), 5 * KT, WALL_T * KT, fill="#fff", stroke=AMBER, sw=1.8)
s.text(tx(-11.5), ty(-POD_W / 2) - 10, "zip-tie notches (both sides)", size=9.5,
       fill="#92400e", anchor="middle", weight="700")

s.rect(tx(WY - 6), ty(-6), WIN * KT, WIN * KT, fill="#dbeafe", stroke=BLUE, sw=1.6, dash="4 3")
s.rect(tx(BAY_Y0), ty(-BAY_W / 2), BAY_L * KT, BAY_W * KT, fill="#eef2ff", stroke=INK, sw=1.5, rx=2, op="0.88")
s.text(tx((BAY_Y0 + BAY_Y1) / 2), ty(-2.4), "XIAO", size=11, weight="700", anchor="middle")
s.text(tx((BAY_Y0 + BAY_Y1) / 2), ty(2.6), "21 × 17.5 mm", size=9, fill=MUTED, anchor="middle")

for x0, x1 in [(-POD_W / 2 + 1.0, -3.4), (3.4, POD_W / 2 - 1.0)]:
    s.rect(tx(BAY_Y1), ty(x0), 1.6 * KT, (x1 - x0) * KT, fill="#d1d5db", stroke=INK, sw=1.2)
s.path(f"M{tx(BAY_Y1-3)},{ty(0)} L{tx(BAY_Y1+4.5)},{ty(0)}", stroke=RED, sw=2.6, marker="arrowR")

s.rect(tx(REAR_Y0), ty(-15), 20 * KT, 30 * KT, fill=PANEL, stroke=INK, sw=1.5, rx=2)
s.text(tx(REAR_Y0 + 10), ty(-2.4), "LiPo", size=11, weight="700", anchor="middle")
s.text(tx(REAR_Y0 + 10), ty(2.6), "30 mm across", size=9, fill=MUTED, anchor="middle")
s.text(tx(POD_REAR) + 8, ty(-1.4), "34.6 mm", size=10, fill=MUTED)
s.text(tx(POD_REAR) + 8, ty(2.0), "outer width", size=9.5, fill=MUTED)

# labels below the top view
s.text(tx(WY), ty(POD_W / 2) + 18, "window under the board", size=9.5, fill=BLUE, anchor="middle")
s.line(tx(WY), ty(POD_W / 2) + 6, tx(WY), ty(6.4), stroke=BLUE, sw=0.9, dash="3 2")
s.text(tx(BAY_Y1 + 2), ty(POD_W / 2) + 34, "wire gap in the divider", size=9.5, fill=RED, weight="700", anchor="middle")
s.line(tx(BAY_Y1 + 0.8), ty(POD_W / 2) + 26, tx(BAY_Y1 + 0.8), ty(2.2), stroke=RED, sw=0.9, dash="3 2")

# ------------------------------------------------------------- footnotes --
FY = 512
s.line(24, FY - 22, W - 24, FY - 22, stroke="#e5e7eb", sw=1)
s.text(24, FY, "Loading order", size=13, weight="700")
s.lines(24, FY + 22, [
    "1.  Board into the FRONT bay, camera pointing DOWN through the window — the bay rails and stop locate it; USB-C ends up facing up.",
    "2.  Battery flat in the REAR bay, lying across the pod (its 30 mm side spans the width, its 20 mm side runs along the length).",
    "3.  Both wires through the divider's centre gap — nothing pinched under the board, nothing lying over the window.",
    "4.  One zip tie over each bay, threaded through the side-wall notches; snug, not crushing. Trim the tails flush so the pod still slides in.",
    "5.  Fold the camera ribbon flat beside the board — never across the window, and never pinched under a zip tie.",
    "6.  Snap on the U.FL antenna (in the XIAO's box — it is required) and tape it OUTSIDE a side wall. Never on top of the battery: foil detunes it.",
], size=11.5, lh=17, fill=INK)
s.rect(24, FY + 120, W - 48, 46, fill="#dbeafe", stroke=BLUE, sw=1.2, rx=6)
s.text(38, FY + 138, "Dry-fit the 160° module first — its barrel is taller than the stock camera. The window is a 12 mm hole through 2.4 mm of floor, so the barrel",
       size=11.5, fill="#1e3a8a", weight="600")
s.text(38, FY + 156, "nests into it and buys back that height. Keep the opening otherwise clear: no tape, no glue, no wire, no ribbon across it.",
       size=11.5, fill="#1e3a8a", weight="600")
s.save('/home/claude/diagrams/PokemonRig-PodLoading.svg')
