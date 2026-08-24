import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

W, H = 980, 716
s = Svg(W, H, "Cordless wiring: keep the battery's JST plug, switch on the cable")
s.text(24, 32, "Cordless wiring — keep the battery's white JST plug", size=17, weight="700")
s.text(24, 52, "Golf-tracker doctrine: never cut the battery — a replaceable LiPo is a feature. A JST switch cable does the same job with HALF the", size=12, fill=MUTED)
s.text(24, 68, "glue joints, because the switch is already wired inline: nothing to wrap, nothing to clip. You cut the CABLE's far end, not the cell.", size=12, fill=MUTED)

# ============================================== ROW A — recommended =======
s.rect(20, 88, W - 40, 250, fill="#f0fdf4", stroke=GREEN, sw=1.6, rx=10)
s.badge(46, 114, "A", color=GREEN)
s.text(66, 119, "RECOMMENDED — JST switch cable (≈$5)", size=13.5, weight="700", fill="#14532d")
s.text(500, 119, "2 glue joints · battery stays stock and swappable", size=11.5, fill="#14532d")

BUS_R, BUS_K = 214, 252

# battery, plug intact
bx, by, bw, bh = 44, 176, 118, 100
s.rect(bx, by, bw, bh, fill=PANEL, stroke=INK, sw=1.8, rx=6)
s.rect(bx + 9, by + 9, bw - 18, bh - 18, fill="#e5e7eb", stroke=LIGHT, sw=1, rx=3)
s.text(bx + bw / 2, by + 44, "EEMB 502030", size=11.5, weight="700", anchor="middle")
s.text(bx + bw / 2, by + 60, "3.7 V · 250 mAh", size=10.5, fill=MUTED, anchor="middle")
s.text(bx + bw / 2, by - 10, "battery — untouched", size=11, weight="700", anchor="middle", fill=GREEN)
s.line(bx + bw, BUS_R, bx + bw + 26, BUS_R, stroke=RED, sw=3)
s.line(bx + bw, BUS_K, bx + bw + 26, BUS_K, stroke=BLK, sw=3)

# JST junction: battery plug into the cable's socket
jx = bx + bw + 26
s.rect(jx, BUS_R - 14, 26, 66, fill="#fffbeb", stroke=INK, sw=1.6, rx=3)
s.rect(jx + 26, BUS_R - 14, 26, 66, fill="#fef9c3", stroke=INK, sw=1.6, rx=3)
s.line(jx + 26, BUS_R - 14, jx + 26, BUS_R + 52, stroke=INK, sw=1.6)
s.text(jx + 26, BUS_R - 24, "the white clip", size=10.5, weight="700", anchor="middle")
s.text(jx + 26, BUS_R + 68, "stays plugged in", size=10, fill=MUTED, anchor="middle")
s.text(jx + 26, BUS_R + 82, "(unplug to swap cells)", size=9.5, fill=MUTED, anchor="middle")

# cable run + inline switch
cx0 = jx + 52
s.line(cx0, BUS_R, cx0 + 78, BUS_R, stroke=RED, sw=3)
s.line(cx0, BUS_K, cx0 + 190, BUS_K, stroke=BLK, sw=3)
swx = cx0 + 78
s.rect(swx, BUS_R - 20, 74, 40, fill="#e2e8f0", stroke=INK, sw=1.8, rx=6)
s.rect(swx + 34, BUS_R - 32, 26, 13, fill="#94a3b8", stroke=INK, sw=1.3, rx=2)
s.text(swx + 37, BUS_R + 5, "SWITCH", size=10, weight="700", anchor="middle")
s.text(swx + 37, BUS_R - 50, "already wired inline", size=10, fill=MUTED, anchor="middle")
s.line(swx + 74, BUS_R, swx + 112, BUS_R, stroke=RED, sw=3)

# cut mark on the CABLE
cutx = swx + 118
for yy in (BUS_R, BUS_K):
    s.line(cutx - 7, yy - 9, cutx + 7, yy + 9, stroke=RED, sw=2.2)
    s.line(cutx - 7, yy + 9, cutx + 7, yy - 9, stroke=RED, sw=2.2)
s.text(cutx + 26, BUS_R - 26, "cut the CABLE here", size=10.5, weight="700", anchor="middle", fill=RED)
s.text(cutx, BUS_K + 30, "(this end is scrap — the battery never gets cut)", size=9.5, fill=MUTED, anchor="middle")
s.line(cutx + 10, BUS_R, cutx + 60, BUS_R, stroke=RED, sw=3)
s.line(cutx + 10, BUS_K, cutx + 60, BUS_K, stroke=BLK, sw=3)

# XIAO with pads
xx, xy, xw, xh = 700, 150, 236, 116
s.text(xx + xw / 2, by - 10, "XIAO ESP32S3 — underside", size=11.5, weight="700", anchor="middle")
s.rect(xx, xy, xw, xh, fill="#eef2ff", stroke=INK, sw=1.8, rx=8)
s.rect(xx + xw - 4, xy + 40, 22, 38, fill="#9ca3af", stroke=INK, sw=1.5, rx=5)
s.text(xx + xw + 6, xy + 92, "USB-C", size=10.5, weight="700", anchor="middle")
padP_x, padN_x = xx + 44, xx + 132
pad_y, pad_h = xy + xh - 10, 20
s.rect(padP_x, pad_y, 34, pad_h, fill=RED, stroke=RED, sw=1, rx=2)
s.rect(padN_x, pad_y, 34, pad_h, fill=BLK, stroke=BLK, sw=1, rx=2)
s.text(padP_x + 17, pad_y - 8, "BAT +", size=11, weight="700", fill=RED, anchor="middle")
s.text(padN_x + 17, pad_y - 8, "BAT −", size=11, weight="700", fill=BLK, anchor="middle")
s.text(xx + xw / 2, xy + 34, "the only two glue joints", size=10.5, weight="700", anchor="middle", fill=GREEN)
s.text(xx + xw / 2, xy + 50, "in the whole build", size=10.5, weight="700", anchor="middle", fill=GREEN)
s.path(f"M{cutx+60},{BUS_R} L{cutx+96},{BUS_R} L{cutx+96},{300} L{padP_x+17},{300} L{padP_x+17},{pad_y+pad_h}", stroke=RED, sw=3)
s.path(f"M{cutx+60},{BUS_K} L{cutx+120},{BUS_K} L{cutx+120},{320} L{padN_x+17},{320} L{padN_x+17},{pad_y+pad_h}", stroke=BLK, sw=3)

# ============================================== ROW B — fallback ==========
s.rect(20, 352, W - 40, 140, fill="#fffbeb", stroke=AMBER, sw=1.4, rx=10)
s.badge(46, 378, "B", color=AMBER)
s.text(66, 383, "FALLBACK — nothing to order: cut the plug, use a kit switch", size=13.5, weight="700", fill="#92400e")
s.text(560, 383, "4 glue joints · battery permanently attached", size=11.5, fill="#92400e")

y0 = 428
def chip(x, w, label, sub, fill="#fff"):
    s.rect(x, y0 - 22, w, 44, fill=fill, stroke=INK, sw=1.4, rx=5)
    s.text(x + w / 2, y0 - 4, label, size=10.5, weight="700", anchor="middle")
    s.text(x + w / 2, y0 + 11, sub, size=9.5, fill=MUTED, anchor="middle")
    return x + w

e = chip(52, 116, "battery", "plug cut off")
s.line(e, y0, e + 30, y0, stroke=RED, sw=2.6, marker="arrowR")
e = chip(e + 30, 150, "SS12D00G5", "wrap + glue 2 pins")
s.line(e, y0, e + 30, y0, stroke=RED, sw=2.6, marker="arrowR")
e = chip(e + 30, 150, "clip 3rd pin", "it sits at battery +")
s.line(e, y0, e + 30, y0, stroke=RED, sw=2.6, marker="arrowR")
chip(e + 30, 190, "glue to BAT + / BAT −", "same pads as above")
s.text(52, y0 + 44, "Works fine — it is simply more joints to get right, and the cell is committed to this build once it's glued on.", size=11.5, fill="#92400e")

# ================================================= shared callouts ========
CY = 520
s.rect(24, CY, 452, 92, fill="#dcfce7", stroke=GREEN, sw=1.6, rx=8)
s.text(40, CY + 22, "Polarity rule — from Seeed's wiki:", size=12.5, weight="700", fill="#14532d")
s.text(40, CY + 42, "NEGATIVE is the pad closest to USB-C.", size=12.5, weight="700", fill="#14532d")
s.text(40, CY + 60, "Positive is the pad farther away. Confirm on your own board", size=11.5, fill="#14532d")
s.text(40, CY + 75, "before gluing — reversing it kills the XIAO.", size=11.5, fill="#14532d")

s.rect(492, CY, 464, 92, fill="#fee2e2", stroke=RED, sw=1.6, rx=8)
s.text(508, CY + 22, "⚠  Meter the cut end — don't trust wire colours", size=12.5, weight="700", fill="#991b1b")
s.text(508, CY + 42, "JST housings are not wired to a universal convention, so the red", size=11.5, fill="#991b1b")
s.text(508, CY + 57, "wire at the cut end is not proof of anything. Plug the battery in,", size=11.5, fill="#991b1b")
s.text(508, CY + 72, "switch ON, and meter the two bare ends before either one touches a pad.", size=11.5, fill="#991b1b")

s.line(24, 634, W - 24, 634, stroke="#e5e7eb", sw=1)
s.lines(24, 656, [
    "•  Cable: Adafruit #3064 \"JST 2-pin Extension Cable with On/Off Switch\" (JST-PH 2.0, 22 AWG, ~20 in) — battery plugs into its socket end; trim the rest to length.",
    "•  Mount the switch and the plug junction on the OUTSIDE of the pod's rear end wall (the pod is an open tray, so the wires just cross the wall top).",
    "•  USB-C still charges the cell through the cable; leave the switch ON to charge. The firmware never sleeps (~60–100 mA idle) — that's what the switch is for.",
], size=11.5, lh=17)
s.save('/home/claude/diagrams/PokemonRig-Wiring.svg')
