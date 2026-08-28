import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

W, H = 1000, 660
s = Svg(W, H, "Which wire is positive, and which pad it goes to")
s.text(24, 32, "Polarity — which wire, which pad", size=18, weight="700")
s.text(24, 53, "Two independent facts settle this: the meter tells you which WIRE is positive, and the silkscreen on your own board tells you which PAD", size=12, fill=MUTED)
s.text(24, 69, "is positive. Never infer either one from wire colour.", size=12, fill=MUTED)

# ============================================ LEFT: find the + wire ======
s.rect(24, 88, 470, 552, fill=CARD, stroke="#e5e7eb", sw=1.5, rx=10)
s.text(46, 118, "A · Which WIRE is positive", size=14, weight="700")
s.text(46, 140, "Battery plugged into the cable, switch ON.", size=11.5, fill=MUTED)

s.badge(62, 168, "1", color=INK, r=10)
s.text(82, 173, "Meter to DC volts", size=12, weight="700")
s.text(82, 190, "The V with a straight line (V⎓), 20 V range or auto — not AC, not ohms.", size=11, fill=MUTED)

s.badge(62, 216, "2", color=INK, r=10)
s.text(82, 221, "Touch one probe to each bare end", size=12, weight="700")
s.text(82, 238, "Red probe on one wire, black on the other. Keep the bare ends apart", size=11, fill=MUTED)
s.text(82, 252, "from each other — touching them together shorts the cell.", size=11, fill=MUTED)

s.badge(62, 278, "3", color=INK, r=10)
s.text(82, 283, "Read the SIGN, not the colour", size=12, weight="700")

# the reading table
ty = 304
def read_row(yy, disp, verdict, col, bold=True):
    s.rect(58, yy, 128, 34, fill="#0f172a", stroke=INK, sw=1.2, rx=4)
    s.text(122, yy + 23, disp, size=15, fill="#4ade80", anchor="middle", font=MONO, weight="700")
    s.text(200, yy + 15, verdict, size=11.5, fill=col, weight="700" if bold else "400")
    s.text(200, yy + 29, "", size=11)

read_row(ty, "3.94", "No minus sign → the wire under the RED", RED)
s.text(200, ty + 29, "probe is POSITIVE.", size=11.5, fill=RED, weight="700")

read_row(ty + 48, "-3.94", "Minus sign → swap your answer: the wire", BLK)
s.text(200, ty + 77, "under the BLACK probe is POSITIVE.", size=11.5, fill=BLK, weight="700")

read_row(ty + 96, "0.00", "Switch is OFF, or the plug isn't seated.", MUTED, False)
s.text(200, ty + 125, "Toggle the switch, re-seat, retry.", size=11.5, fill=MUTED)

read_row(ty + 144, "2.9", "Under 3.3 V — charge the cell over USB-C", MUTED, False)
s.text(200, ty + 173, "before you build anything.", size=11.5, fill=MUTED)

s.rect(46, ty + 194, 426, 74, fill="#dcfce7", stroke=GREEN, sw=1.5, rx=8)
s.badge(72, ty + 220, "4", color=GREEN, r=10)
s.text(92, ty + 225, "Mark the positive wire the moment you know", size=12, weight="700", fill="#14532d")
s.text(92, ty + 245, "A flag of tape, a Sharpie band, a knot — anything you cannot", size=11, fill="#14532d")
s.text(92, ty + 259, "misread an hour later. Then meter once more before gluing.", size=11, fill="#14532d")

# ============================================ RIGHT: which pad ==========
s.rect(510, 88, 466, 552, fill=CARD, stroke="#e5e7eb", sw=1.5, rx=10)
s.text(532, 118, "B · Which PAD is positive", size=14, weight="700")
s.text(532, 140, "Board face-down, silkscreen up, USB-C at the top.", size=11.5, fill=MUTED)

# board schematic
BX, BY, BW, BH = 566, 168, 250, 250
s.rect(BX + 96, BY - 22, 58, 24, fill="#9ca3af", stroke=INK, sw=1.4, rx=4)
s.text(BX + 172, BY - 6, "USB-C", size=10, anchor="start", weight="700")
s.rect(BX, BY, BW, BH, fill="#111827", stroke=INK, sw=1.6, rx=8)

left_lbl = ["VUSB", "GND", "3V3", "D10", "D9", "D8", "D7"]
right_lbl = ["D0", "D1", "D2", "D3", "D4", "D5", "D6"]
for i in range(7):
    yy = BY + 22 + i * 34
    s.circle(BX + 9, yy, 6, fill="#d4a017", stroke="#f5deb3", sw=1.2)
    s.text(BX + 22, yy + 4, left_lbl[i], size=8.5, fill="#e5e7eb")
    s.circle(BX + BW - 9, yy, 6, fill="#d4a017", stroke="#f5deb3", sw=1.2)
    s.text(BX + BW - 22, yy + 4, right_lbl[i], size=8.5, fill="#e5e7eb", anchor="end")

inner = [("MTDO", "MTDI"), ("GND", "EN"), ("MTCK", "MTMS"), ("D+", "D−")]
for r, (a, b) in enumerate(inner):
    yy = BY + 56 + r * 34
    s.circle(BX + 60, yy, 7, fill="#e5e7eb", stroke="none")
    s.text(BX + 72, yy + 4, a, size=8, fill="#e5e7eb")
    s.circle(BX + 116, yy, 7, fill="#e5e7eb", stroke="none")
    s.text(BX + 128, yy + 4, b, size=8, fill="#e5e7eb")

# the two BAT ovals (rows 3 and 4 -> level with D2 and D3)
oy1, oy2 = BY + 22 + 2 * 34, BY + 22 + 3 * 34
s.rect(BX + 176, oy1 - 9, 34, 18, fill="#e5e7eb", stroke=BLK, sw=2.6, rx=8)
s.text(BX + 170, oy1 + 4, "−", size=13, fill="#e5e7eb", anchor="end", weight="700")
s.rect(BX + 176, oy2 - 9, 34, 18, fill="#fecaca", stroke=RED, sw=2.6, rx=8)
s.text(BX + 170, oy2 + 4, "+", size=13, fill="#fecaca", anchor="end", weight="700")
s.text(BX + 193, oy2 + 26, "BAT", size=9.5, fill="#e5e7eb", anchor="middle", weight="700")
s.text(BX + 125, BY + BH - 14, "seeed studio  XIAO ESP32S3", size=8.5, fill="#9ca3af", anchor="middle")

# callouts
s.line(BX + 210, oy1, 872, oy1 - 26, stroke=BLK, sw=1.6)
s.text(878, oy1 - 34, "BAT −", size=13, weight="700", fill=BLK)
s.text(878, oy1 - 18, "upper oval", size=10.5, fill=MUTED)
s.text(878, oy1 - 4, "level with D2", size=10.5, fill=MUTED)

s.line(BX + 210, oy2, 872, oy2 + 30, stroke=RED, sw=1.6)
s.text(878, oy2 + 22, "BAT +", size=13, weight="700", fill=RED)
s.text(878, oy2 + 38, "lower oval", size=10.5, fill=MUTED)
s.text(878, oy2 + 52, "level with D3", size=10.5, fill=MUTED)

s.rect(532, 452, 422, 78, fill="#dcfce7", stroke=GREEN, sw=1.5, rx=8)
s.text(548, 474, "Your board says so itself", size=12.5, weight="700", fill="#14532d")
s.text(548, 494, "A tiny − is etched beside the upper oval and a tiny + beside", size=11, fill="#14532d")
s.text(548, 509, "the lower one, with BAT underneath. Read the PCB — it beats", size=11, fill="#14532d")
s.text(548, 524, "every rule of thumb, including mine.", size=11, fill="#14532d")

s.rect(532, 544, 422, 78, fill="#fee2e2", stroke=RED, sw=1.6, rx=8)
s.text(548, 566, "⚠  This is the one irreversible mistake", size=12.5, weight="700", fill="#991b1b")
s.text(548, 586, "Reverse polarity kills the XIAO's charge chip. The two ovals sit", size=11, fill="#991b1b")
s.text(548, 601, "~2 mm apart, so a glue smear across both is just as fatal.", size=11, fill="#991b1b")
s.text(548, 616, "Check twice; you only get to do this once.", size=11, weight="700", fill="#991b1b")
s.save('/home/claude/diagrams/PokemonRig-Pads.svg')
