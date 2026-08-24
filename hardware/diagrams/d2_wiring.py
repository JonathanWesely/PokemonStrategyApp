import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

W, H = 960, 596
s = Svg(W, H, "Cordless wiring: battery, inline switch, XIAO BAT pads")
s.text(24, 32, "Cordless wiring — battery → switch → BAT pads", size=17, weight="700")
s.text(24, 52, "Four glue joints total: two BAT pads + two switch pins. The kit's switches have solid PCB pins (no holes), so each wire gets", size=12, fill=MUTED)
s.text(24, 68, "4–5 tight turns wrapped around the pin with pliers, then glue over the coil. Use an SS12D00G5 — smallest body, 0.5 A / 50 V.", size=12, fill=MUTED)

REDBUS, BLKBUS = 268, 306

# ------------------------------------------------------------------ XIAO --
xx, xy, xw, xh = 560, 108, 300, 130
s.text(xx + xw/2, 96, "③ XIAO ESP32S3 — underside", size=13, weight="700", anchor="middle")
s.rect(xx, xy, xw, xh, fill="#eef2ff", stroke=INK, sw=1.8, rx=8)
for i in range(7):
    s.rect(xx + 12 + i * 38, xy - 8, 14, 9, fill="#d1d5db", stroke=LIGHT, sw=0.8, rx=1)
# USB-C at the RIGHT end — the compass for polarity
s.rect(xx + xw - 4, xy + 44, 26, 44, fill="#9ca3af", stroke=INK, sw=1.6, rx=6)
s.text(xx + xw + 9, xy + 106, "USB-C", size=11.5, weight="700", anchor="middle")
s.text(xx + 22, xy + 34, "(component side faces DOWN", size=10, fill=LIGHT)
s.text(xx + 22, xy + 47, "once it's seated in the pod)", size=10, fill=LIGHT)

# pads straddle the board's bottom edge so the wires never cross the board
padP_x, padN_x = xx + 70, xx + 172
pad_y, pad_h = xy + xh - 11, 22
s.rect(padP_x, pad_y, 38, pad_h, fill=RED, stroke=RED, sw=1, rx=2)
s.rect(padN_x, pad_y, 38, pad_h, fill=BLK, stroke=BLK, sw=1, rx=2)
s.text(padP_x + 19, pad_y - 20, "BAT +", size=12, weight="700", fill=RED, anchor="middle")
s.text(padN_x + 19, pad_y - 20, "BAT −", size=12, weight="700", fill=BLK, anchor="middle")
s.text(padP_x + 19, pad_y - 7, "farther from USB-C", size=9.5, fill=MUTED, anchor="middle")
s.text(padN_x + 19, pad_y - 7, "nearer USB-C", size=9.5, fill=INK, anchor="middle", weight="700")
# ~2 mm gap marker
gapc = (padP_x + 38 + padN_x) / 2
s.line(padP_x + 38, pad_y + 5, padN_x, pad_y + 5, stroke="#fff", sw=1.2, dash="3 2")
s.path(f"M{gapc},{pad_y-40} L{gapc},{pad_y+3}", stroke=MUTED, sw=1, dash="3 2")
s.text(gapc, pad_y - 52, "~2 mm apart —", size=10, fill=MUTED, anchor="middle")
s.text(gapc, pad_y - 41, "never bridge them", size=10, fill=MUTED, anchor="middle", weight="700")

# ---------------------------------------------------------------- battery --
bx, by, bw, bh = 28, 246, 130, 96
s.text(bx + bw/2, 236, "① Battery", size=13, weight="700", anchor="middle")
s.rect(bx, by, bw, bh, fill=PANEL, stroke=INK, sw=1.8, rx=6)
s.rect(bx + 9, by + 9, bw - 18, bh - 18, fill="#e5e7eb", stroke=LIGHT, sw=1, rx=3)
s.text(bx + bw/2, by + 44, "EEMB 502030", size=12, weight="700", anchor="middle")
s.text(bx + bw/2, by + 61, "3.7 V · 250 mAh", size=11, fill=MUTED, anchor="middle")
s.line(bx + bw, REDBUS, bx + bw + 38, REDBUS, stroke=RED, sw=3.2)
s.line(bx + bw, BLKBUS, bx + bw + 38, BLKBUS, stroke=BLK, sw=3.2)
s.text(bx + bw + 2, REDBUS - 9, "red +", size=11, fill=RED, weight="700")
s.text(bx + bw + 2, BLKBUS + 19, "black −", size=11, fill=BLK, weight="700")

# JST plug removed
jx = bx + bw + 38
s.rect(jx, REDBUS - 14, 24, BLKBUS - REDBUS + 28, fill="#fff", stroke=LIGHT, sw=1.3, rx=3, dash="4 3")
s.text(jx + 12, BLKBUS + 32, "JST plug", size=10, fill=LIGHT, anchor="middle")
s.text(jx + 12, BLKBUS + 44, "cut off", size=10, fill=LIGHT, anchor="middle")
for yy in (REDBUS, BLKBUS):
    s.line(jx - 13, yy - 9, jx - 3, yy + 9, stroke=RED, sw=2.2)
    s.line(jx - 13, yy + 9, jx - 3, yy - 9, stroke=RED, sw=2.2)

# ----------------------------------------------------------------- switch --
sx = 262
s.text(sx + 70, 176, "② Slide switch (SPDT)", size=13, weight="700", anchor="middle")
s.rect(sx, 192, 140, 44, fill=PANEL, stroke=INK, sw=1.8, rx=5)
s.rect(sx + 44, 176, 52, 18, fill="#d1d5db", stroke=INK, sw=1.4, rx=3)
s.text(sx + 70, 219, "slide", size=10.5, fill=MUTED, anchor="middle")
for lx in (sx + 26, sx + 70, sx + 114):
    s.line(lx, 236, lx, REDBUS + 4, stroke=INK, sw=3.4)
# wire wraps (coils) on the two pins we actually use
for lx in (sx + 70, sx + 114):
    for k in range(4):
        s.path(f"M{lx-5},{248+k*4} Q{lx},{245+k*4} {lx+5},{248+k*4}", stroke=RED, sw=1.6)
# unused pin gets clipped off
s.line(sx + 20, 244, sx + 32, 256, stroke=RED, sw=2.2)
s.line(sx + 20, 256, sx + 32, 244, stroke=RED, sw=2.2)
s.text(sx + 12, 254, "clip", size=9.5, fill=RED, anchor="end", weight="700")
s.text(sx + 96, REDBUS + 62, "centre pin = COMMON (in from battery)", size=10.5, weight="700", anchor="middle")
s.text(sx + 96, REDBUS + 76, "one outer pin = OUT to BAT+ · clip the third", size=10.5, fill=MUTED, anchor="middle")

# red: battery -> centre lug; outer lug -> under the board -> up into BAT+
s.path(f"M{jx+24},{REDBUS} L{sx+70},{REDBUS}", stroke=RED, sw=3.2)
s.path(f"M{sx+114},{REDBUS} L{padP_x+19},{REDBUS} L{padP_x+19},{pad_y+pad_h}", stroke=RED, sw=3.2)
# black: straight through, further right, up into BAT-
s.path(f"M{jx+24},{BLKBUS} L{padN_x+19},{BLKBUS} L{padN_x+19},{pad_y+pad_h}", stroke=BLK, sw=3.2)

# ------------------------------------------------------------- callouts ---
CY = 360
s.rect(28, CY, 268, 62, fill="#fee2e2", stroke=RED, sw=1.3, rx=8)
s.text(42, CY + 22, "⚠  Cut ONE lead at a time", size=12.5, weight="700", fill="#991b1b")
s.text(42, CY + 41, "Snipping both at once shorts the cell", size=11.5, fill="#991b1b")
s.text(42, CY + 55, "across the blades — sparks.", size=11.5, fill="#991b1b")

s.rect(312, CY, 250, 62, fill="#fef3c7", stroke=AMBER, sw=1.3, rx=8)
s.text(326, CY + 22, "Clip the unused third pin", size=12.5, weight="700", fill="#92400e")
s.text(326, CY + 41, "In the OFF position it sits at battery +", size=11.5, fill="#92400e")
s.text(326, CY + 55, "potential — a bare pin waiting to short.", size=11.5, fill="#92400e")

s.rect(578, CY, 354, 84, fill="#dcfce7", stroke=GREEN, sw=1.6, rx=8)
s.text(594, CY + 22, "Polarity rule — from Seeed's wiki:", size=12.5, weight="700", fill="#14532d")
s.text(594, CY + 42, "NEGATIVE is the pad closest to USB-C.", size=12.5, weight="700", fill="#14532d")
s.text(594, CY + 60, "Positive is the pad farther away. Confirm against", size=11.5, fill="#14532d")
s.text(594, CY + 75, "your own board first — reversing it kills the XIAO.", size=11.5, fill="#14532d")

s.line(24, 470, W - 24, 470, stroke="#e5e7eb", sw=1)
s.text(24, 492, "Also true of this wiring", size=12.5, weight="700")
s.lines(24, 512, [
    "•  USB-C still charges the cell once it's attached — built-in charger at 100 mA, empty-to-full ≈ 3 h, and streaming while charging is fine.",
    "•  The switch earns its place: this firmware never sleeps (~60–100 mA idle), so a hardwired cell would drain in a few hours on the shelf.",
    "•  Route both wires toward the pod's divider gap before the board goes in — never trapped under the Sense expansion board.",
    "•  The printed pod has no switch pocket: glue the switch flat on the OUTSIDE of the pod's rear end wall, handle up. Both docks stay clear of it.",
], size=11.5, lh=17)
s.save('/home/claude/diagrams/PokemonRig-Wiring.svg')
