import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

W, H = 940, 300
s = Svg(W, H, "Build path: USB-C bring-up, then optional cordless conversion")
s.text(24, 34, "Build path — you are never blocked on a joint", size=17, weight="700")
s.text(24, 55, "Phase A works with zero electrical joints. Only convert to cordless when you want to; the gate decides whether glue is enough.",
       size=12, fill=MUTED)

BOXY, BOXH = 80, 96
def box(x, w, title, sub, color, badge_n, fill=CARD):
    s.rect(x, BOXY, w, BOXH, fill=fill, stroke=color, sw=2, rx=10)
    s.badge(x + 20, BOXY + 22, badge_n, color=color)
    s.text(x + 40, BOXY + 27, title, size=13.5, weight="700", fill=color)
    s.lines(x + 16, BOXY + 52, sub, size=11.5, lh=14)

box(24, 210, "Phase A — USB-C", [
    "Battery stays in the bag.", "Power the pod from a wall brick", "or power bank. Flash, stream,", "scan — everything works."], GREEN, 1)
s.text(24 + 105, BOXY + BOXH + 20, "0 joints · do this first", size=11, fill=GREEN, anchor="middle", weight="600")

s.line(244, BOXY + 48, 286, BOXY + 48, stroke=MUTED, sw=1.6, marker="arrowM")
s.text(265, BOXY + 40, "then", size=10.5, fill=MUTED, anchor="middle")

box(292, 230, "Phase B — cordless", [
    "Cut JST plug, switch inline on", "red, conductive glue on the two", "BAT pads, strain-relief tape,", "E6000 overcoat, full cure."], AMBER, 2)
s.text(292 + 115, BOXY + BOXH + 20, "2 glued joints · your golf-tracker supplies", size=11, fill=AMBER, anchor="middle", weight="600")

s.line(532, BOXY + 48, 574, BOXY + 48, stroke=MUTED, sw=1.6, marker="arrowM")

# Gate diamond
gx, gy = 660, BOXY + 48
s.path(f"M{gx},{gy-54} L{gx+102},{gy} L{gx},{gy+54} L{gx-102},{gy} Z", fill=PANEL, stroke=INK, sw=2)
s.text(gx, gy - 16, "THE GATE", size=11.5, weight="700", anchor="middle")
s.text(gx, gy + 2, "joint ≤ 0.2 Ω", size=11.5, anchor="middle", font=MONO)
s.text(gx, gy + 20, "+ 10 min stream, no reboot", size=11, anchor="middle", fill=MUTED)

# Pass
s.line(gx + 106, gy - 14, 762, gy - 40, stroke=GREEN, sw=1.8, marker="arrowG")
s.text(768, gy - 44, "PASS", size=12, weight="700", fill=GREEN)
s.text(768, gy - 28, "Done — cordless build.", size=11.5, fill=INK)
s.text(768, gy - 13, "USB-C still charges it.", size=11.5, fill=MUTED)

# Fail
s.line(gx + 106, gy + 14, 762, gy + 34, stroke=RED, sw=1.8, marker="arrowR")
s.text(768, gy + 30, "FAIL", size=12, weight="700", fill=RED)
s.text(768, gy + 45, "Re-glue once (more contact", size=11.5, fill=INK)
s.text(768, gy + 59, "area) → still failing? Solder", size=11.5, fill=INK)
s.text(768, gy + 73, "the 2 pads, ~5 min (§12.1).", size=11.5, fill=INK)

s.rect(24, 236, 498, 46, fill="#fef3c7", stroke=AMBER, sw=1.2, rx=8)
s.text(38, 254, "Why a gate at all?", size=12, weight="700", fill="#92400e")
s.text(38, 271, "Wi-Fi streaming pulls ~150–250 mA with bursts to ~500 mA — 100× the golf tracker's glued joint.",
       size=11.5, fill="#92400e")
s.save('/home/claude/diagrams/PokemonRig-BuildPath.svg')
