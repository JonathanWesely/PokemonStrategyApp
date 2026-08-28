import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

W, H = 1020, 1044
s = Svg(W, H, "Battery wiring, step by step, using the Adafruit JST-PH switch cable")
s.text(24, 34, "Battery wiring — step by step", size=18, weight="700")
s.text(24, 55, "The battery is never cut and stays swappable. The switch is already wired into the cable, so the whole build has exactly TWO glue joints:", size=12, fill=MUTED)
s.text(24, 71, "the two BAT pads on the XIAO. Everything else is a plug or a factory joint.", size=12, fill=MUTED)

# ------------------------------------------------------------- the part --
s.rect(24, 88, W - 48, 96, fill="#f8fafc", stroke="#e5e7eb", sw=1.4, rx=10)
s.text(44, 112, "THE PART:", size=11.5, weight="700")
s.text(126, 112, "Adafruit \"JST 2-pin Extension Cable with On/Off Switch — JST PH2\"  ·  ~20 in / 508 mm  ·  22 AWG  ·  $7.25  ·  qty 1 is plenty", size=11.5)
# cable sketch
cy = 152
s.rect(60, cy - 11, 26, 22, fill="#fffbeb", stroke=INK, sw=1.5, rx=3)
s.text(73, cy + 30, "socket end", size=9.5, anchor="middle", fill=MUTED)
s.text(73, cy + 42, "(battery goes here)", size=9, anchor="middle", fill=MUTED)
s.line(86, cy - 4, 300, cy - 4, stroke=RED, sw=2.6)
s.line(86, cy + 4, 300, cy + 4, stroke=BLK, sw=2.6)
s.rect(300, cy - 15, 74, 30, fill="#334155", stroke=INK, sw=1.5, rx=7)
s.circle(337, cy, 7, fill="#94a3b8", stroke=INK, sw=1.3)
s.text(337, cy + 34, "in-line switch", size=9.5, anchor="middle", fill=MUTED, weight="700")
s.text(337, cy + 46, "click on / click off", size=9, anchor="middle", fill=MUTED)
s.line(374, cy - 4, 640, cy - 4, stroke=RED, sw=2.6)
s.line(374, cy + 4, 640, cy + 4, stroke=BLK, sw=2.6)
s.rect(640, cy - 11, 26, 22, fill="#fef9c3", stroke=INK, sw=1.5, rx=3)
s.text(653, cy + 30, "plug end", size=9.5, anchor="middle", fill=MUTED)
s.text(653, cy + 42, "CUT THIS OFF", size=9.5, anchor="middle", fill=RED, weight="700")
s.text(700, cy - 8, "Only one end fits the battery —", size=11, fill=INK)
s.text(700, cy + 6, "it is keyed and cannot go in wrong.", size=11, fill=INK)
s.text(700, cy + 24, "The end that does NOT fit is", size=11, weight="700", fill=INK)
s.text(700, cy + 38, "the end you cut off.", size=11, weight="700", fill=INK)

# ------------------------------------------------------------- 6 steps ---
PW_, PH_, GAP_ = 314, 244, 14
def step(i, title):
    col, row = i % 3, i // 3
    x = 24 + col * (PW_ + GAP_)
    y = 208 + row * (PH_ + 16)
    s.rect(x, y, PW_, PH_, fill=CARD, stroke="#e5e7eb", sw=1.4, rx=10)
    s.badge(x + 26, y + 26, i + 1, color=INK)
    s.text(x + 46, y + 31, title, size=12.5, weight="700")
    return x, y

# 1 — plug the battery in
x, y = step(0, "Plug the battery in")
s.lines(x + 18, y + 56, [
    "Leave the battery exactly as it came.",
    "Push its white plug into the cable end",
    "that accepts it — it clicks and only",
    "goes one way.",
], size=10.5, lh=13)
s.rect(x + 30, y + 138, 96, 58, fill=PANEL, stroke=INK, sw=1.5, rx=4)
s.text(x + 78, y + 172, "battery", size=10.5, anchor="middle", weight="700")
s.line(x + 126, y + 160, x + 150, y + 160, stroke=RED, sw=2.6)
s.line(x + 126, y + 170, x + 150, y + 170, stroke=BLK, sw=2.6)
s.rect(x + 150, y + 150, 20, 30, fill="#fffbeb", stroke=INK, sw=1.5, rx=3)
s.rect(x + 170, y + 150, 20, 30, fill="#fef9c3", stroke=INK, sw=1.5, rx=3)
s.text(x + 200, y + 162, "click", size=10, fill=GREEN, weight="700")
s.text(x + 200, y + 176, "no tools", size=9.5, fill=MUTED)
s.text(x + 18, y + 222, "Nothing about the cell is modified.", size=10.5, weight="700", fill=GREEN)

# 2 — lay it out, then cut
x, y = step(1, "Lay it out, then cut")
s.lines(x + 18, y + 56, [
    "Hold the pod where it will sit and the",
    "switch where you want it — flat on the",
    "OUTSIDE of the pod's rear end wall.",
    "Cut the far (plug) end leaving ~80 mm",
    "of cable past the switch.",
], size=10.5, lh=13)
s.line(x + 24, y + 168, x + 150, y + 168, stroke=RED, sw=2.6)
s.rect(x + 150, y + 156, 52, 24, fill="#334155", stroke=INK, sw=1.4, rx=6)
s.line(x + 202, y + 168, x + 268, y + 168, stroke=RED, sw=2.6)
for d in (-8, 8):
    s.line(x + 262, y + 168 + d, x + 276, y + 168 - d, stroke=RED, sw=2.2)
s.text(x + 235, y + 150, "~80 mm", size=9.5, anchor="middle", fill=MUTED, weight="700")
s.text(x + 18, y + 208, "Spare cable on the battery side: coil it,", size=10, fill="#92400e")
s.text(x + 18, y + 222, "zip-tie it to the pod. Don't splice it out.", size=10, fill="#92400e")

# 3 — strip and fan
x, y = step(2, "Strip 6 mm, fan the strands")
s.lines(x + 18, y + 56, [
    "22 AWG is thick for a 1 mm pad, so",
    "splay the strands into a flat fan with",
    "your fingernail. More contact area,",
    "less bulk, a flatter joint.",
], size=10.5, lh=13)
s.line(x + 40, y + 160, x + 150, y + 160, stroke=RED, sw=6)
for k, dy in enumerate((-9, -4.5, 0, 4.5, 9)):
    s.line(x + 150, y + 160, x + 196, y + 160 + dy, stroke="#b45309", sw=1.5)
s.text(x + 172, y + 186, "6 mm", size=9.5, anchor="middle", fill=MUTED)
s.line(x + 150, y + 176, x + 196, y + 176, stroke=MUTED, sw=1)
s.text(x + 18, y + 216, "Do both wires. Keep the two ends apart —", size=10, fill=RED)
s.text(x + 18, y + 230, "the cell is live even with the switch OFF.", size=10, fill=RED)

# 4 — meter
x, y = step(3, "METER before anything touches")
s.lines(x + 18, y + 56, [
    "Switch ON. Put the meter on DC volts",
    "and touch the two bare ends. A reading",
    "of +3.5 to +4.2 V means the RED probe",
    "is on the positive wire. Mark it.",
], size=10.5, lh=13)
s.rect(x + 24, y + 138, 74, 56, fill=PANEL, stroke=INK, sw=1.5, rx=6)
s.rect(x + 32, y + 146, 58, 22, fill="#e2e8f0", stroke=LIGHT, sw=1, rx=2)
s.text(x + 61, y + 162, "3.94 V", size=11, anchor="middle", weight="700", font=MONO)
s.path(f"M{x+98},{y+180} L{x+150},{y+164} L{x+196},{y+164}", stroke=RED, sw=2.2)
s.path(f"M{x+98},{y+190} L{x+150},{y+186} L{x+196},{y+186}", stroke=BLK, sw=2.2)
s.text(x + 204, y + 168, "+", size=13, weight="700", fill=RED)
s.text(x + 204, y + 190, "−", size=13, weight="700", fill=BLK)
s.text(x + 18, y + 218, "Wire colour is NOT proof — housings", size=10, weight="700", fill=RED)
s.text(x + 18, y + 232, "aren't wired to one convention.", size=10, weight="700", fill=RED)

# 5 — tape then glue
x, y = step(4, "Tape first, then glue")
s.lines(x + 18, y + 56, [
    "Clean both pads with 91% IPA. Tape the",
    "wire body to the board edge so the tape",
    "takes every tug. Then a small dab of",
    "wire glue bridging fan → pad. Cure",
    "12–24 h, then E6000 over the top.",
], size=10.5, lh=13)
s.rect(x + 30, y + 176, 200, 22, fill="#eef2ff", stroke=INK, sw=1.4, rx=3)
s.rect(x + 120, y + 170, 54, 6, fill=BLK, stroke="none")
s.line(x + 34, y + 164, x + 112, y + 164, stroke=RED, sw=3.4)
s.rect(x + 40, y + 156, 40, 14, fill="#bfdbfe", stroke=BLUE, sw=1.3, rx=2, op="0.9")
s.text(x + 60, y + 150, "tape", size=9, anchor="middle", fill=BLUE, weight="700")
s.path(f"M{x+112},{y+171} Q{x+140},{y+152} {x+172},{y+171} Z", fill="#fcd34d", stroke=AMBER, sw=1.4)
s.text(x + 196, y + 158, "glue", size=9.5, fill="#92400e", weight="700")
s.text(x + 18, y + 222, "+ → pad FARTHER from USB-C.", size=10.5, weight="700", fill=RED)

# 6 — mount
x, y = step(5, "Mount it on the rear wall")
s.lines(x + 18, y + 56, [
    "Switch and plug junction live OUTSIDE,",
    "flat on the pod's rear end wall (34.6 ×",
    "6.6 mm of free face). Wires cross the",
    "wall top — the pod is an open tray.",
], size=10.5, lh=13)
s.rect(x + 46, y + 150, 170, 46, fill="#f8fafc", stroke=INK, sw=1.6, rx=3)
s.text(x + 131, y + 178, "pod, rear face", size=10, anchor="middle", fill=MUTED)
s.rect(x + 70, y + 128, 56, 20, fill="#334155", stroke=INK, sw=1.4, rx=5)
s.circle(x + 98, y + 138, 5, fill="#94a3b8", stroke=INK, sw=1)
s.rect(x + 136, y + 128, 34, 20, fill="#fef9c3", stroke=INK, sw=1.4, rx=3)
s.text(x + 98, y + 120, "switch", size=9, anchor="middle", weight="700")
s.text(x + 153, y + 120, "junction", size=9, anchor="middle", weight="700")
s.text(x + 18, y + 216, "Clear of the dovetail on both docks, and", size=10, fill=MUTED)
s.text(x + 18, y + 230, "on TOP when the TV stand is in use.", size=10, fill=MUTED)

# ----------------------------------------------------------- callouts ----
CY = 744
s.rect(24, CY, 486, 92, fill="#dcfce7", stroke=GREEN, sw=1.6, rx=8)
s.text(42, CY + 24, "Which pad is which — from Seeed's wiki:", size=12.5, weight="700", fill="#14532d")
s.text(42, CY + 45, "NEGATIVE is the pad CLOSEST to the USB-C port.", size=13, weight="700", fill="#14532d")
s.text(42, CY + 64, "Positive is the pad farther away. The two sit ~2 mm apart — never let", size=11.5, fill="#14532d")
s.text(42, CY + 80, "glue bridge them, and confirm on your own board before you commit.", size=11.5, fill="#14532d")

s.rect(524, CY, 472, 92, fill="#f8fafc", stroke=INK, sw=1.5, rx=8)
s.text(542, CY + 24, "Then the gate — before you trust it in a match", size=12.5, weight="700")
s.text(542, CY + 45, "Meter battery → pad through the switch: ≤ ~0.3 Ω (subtract your", size=11.5, fill=MUTED)
s.text(542, CY + 61, "probe leads). Then stream 10 minutes on battery alone with zero", size=11.5, fill=MUTED)
s.text(542, CY + 77, "reboots. Reboots = joint resistance → re-glue, or solder those 2 pads.", size=11.5, fill=MUTED)

# ------------------------------------------- battery state timeline -----
TY = 858
s.text(24, TY, "Battery state through the build — glue and cure with the circuit DEAD", size=13.5, weight="700")
s.text(24, TY + 18, "The cell is plugged in for exactly two moments: the voltage check, and the final soak test. Everything else happens with nothing live.", size=11, fill=MUTED)

segs = [
    ("Cut + strip", "battery OUT", GREEN, 176),
    ("Volt check", "battery IN", AMBER, 132),
    ("Fan · clean · tape · glue · cure · overcoat", "battery OUT — and no USB either", GREEN, 350),
    ("Ω gate", "battery OUT", GREEN, 132),
    ("10-min soak", "battery IN", AMBER, 182),
]
bx = 24
for label, state, col, w in segs:
    fill = "#dcfce7" if col == GREEN else "#fef3c7"
    s.rect(bx, TY + 34, w, 54, fill=fill, stroke=col, sw=1.6, rx=6)
    s.text(bx + w / 2, TY + 55, label, size=10.5, weight="700", anchor="middle",
           fill="#14532d" if col == GREEN else "#92400e")
    s.text(bx + w / 2, TY + 74, state, size=9.5, anchor="middle",
           fill="#14532d" if col == GREEN else "#92400e")
    bx += w + 6

s.text(24, TY + 114, "Why it matters", size=11.5, weight="700")
s.text(24, TY + 132, "Wet conductive glue bridging the ~2 mm pad gap is just a smear you wipe off when nothing is powered — with a cell or USB live, it is a dead", size=11, fill=MUTED)
s.text(24, TY + 148, "short across the battery. Cutting the cable is the same story: strippers across both conductors only matter if the cell is plugged in.", size=11, fill=MUTED)
s.text(24, TY + 170, "Keeping the plug pays off again here — an unplugged cell sits safely in its own housing, where a cut-off one would be two bare live wires.", size=11, fill=INK, weight="600")
s.save('/home/claude/diagrams/PokemonRig-Wiring.svg')
