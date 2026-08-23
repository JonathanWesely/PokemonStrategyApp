import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

W, H = 960, 420
s = Svg(W, H, "The glued BAT-pad joint, step by step in cross-section")
s.text(24, 32, "The glued joint, in cross-section — four layers, in this order", size=17, weight="700")
s.text(24, 52, "Do both pads the same way. The tape goes on BEFORE the glue: it carries every tug so the conductive glue only ever does the electrical job.",
       size=12, fill=MUTED)

PW, PH, PY = 216, 176, 84          # panel size
GAP = 20
BOARD_Y = PY + 118                 # board top surface within a panel

def panel(i, title, sub):
    x = 24 + i * (PW + GAP)
    s.rect(x, PY, PW, PH, fill=CARD, stroke="#e5e7eb", sw=1.4, rx=10)
    s.badge(x + 26, PY + 26, i + 1, color=INK)
    s.text(x + 46, PY + 31, title, size=12.5, weight="700")
    s.text(x + 16, PY + 60, sub, size=11, fill=MUTED)
    # the board slab + pad, common to every panel
    s.rect(x + 16, BOARD_Y, PW - 32, 26, fill="#eef2ff", stroke=INK, sw=1.5, rx=3)
    s.text(x + 24, BOARD_Y + 17, "XIAO", size=9.5, fill=LIGHT)
    s.rect(x + 96, BOARD_Y - 5, 62, 6, fill=BLK, stroke="none")     # the pad
    s.text(x + 127, BOARD_Y + 32, "BAT pad", size=9.5, fill=MUTED, anchor="middle")
    return x

# --- 1 clean
x = panel(0, "Clean the pad", "91% IPA on a swab. Let it flash off —")
s.text(x + 16, PY + 74, "glue will not bite through finger oil.", size=11, fill=MUTED)
s.path(f"M{x+104},{BOARD_Y-26} L{x+124},{BOARD_Y-8}", stroke=BLUE, sw=2.4)
s.circle(x + 100, BOARD_Y - 30, 9, fill="#dbeafe", stroke=BLUE, sw=1.6)
s.text(x + 122, BOARD_Y - 32, "IPA swab", size=10, fill=BLUE, weight="700")

# --- 2 tape
x = panel(1, "Tape the wire down", "Strain relief FIRST — tape the wire")
s.text(x + 16, PY + 74, "body to the board edge, not the joint.", size=11, fill=MUTED)
s.path(f"M{x+20},{BOARD_Y-14} L{x+86},{BOARD_Y-14} L{x+124},{BOARD_Y-8}", stroke=RED, sw=3.4)
s.rect(x + 22, BOARD_Y - 22, 46, 16, fill="#bfdbfe", stroke=BLUE, sw=1.4, rx=2, op="0.85")
s.text(x + 45, BOARD_Y - 30, "tape", size=10, fill=BLUE, anchor="middle", weight="700")
s.text(x + 150, BOARD_Y - 22, "bare end", size=10, fill=MUTED)
s.text(x + 150, BOARD_Y - 10, "rests on pad", size=10, fill=MUTED)

# --- 3 glue
x = panel(2, "Conductive glue", "A small dab bridging bare wire →")
s.text(x + 16, PY + 74, "pad. Cure 12–24 h, room temp.", size=11, fill=MUTED)
s.path(f"M{x+20},{BOARD_Y-14} L{x+86},{BOARD_Y-14} L{x+124},{BOARD_Y-8}", stroke=RED, sw=3.4)
s.rect(x + 22, BOARD_Y - 22, 46, 16, fill="#bfdbfe", stroke=BLUE, sw=1.4, rx=2, op="0.85")
s.path(f"M{x+100},{BOARD_Y-5} Q{x+124},{BOARD_Y-26} {x+152},{BOARD_Y-5} Z", fill="#fcd34d", stroke=AMBER, sw=1.6)
s.text(x + 126, BOARD_Y - 30, "wire glue", size=10, fill="#92400e", anchor="middle", weight="700")
s.text(x + 16, PY + PH - 14, "Never heat-cure with the LiPo attached.", size=10, fill="#92400e")

# --- 4 overcoat
x = panel(3, "Overcoat, then test", "E6000 or hot glue over the cured")
s.text(x + 16, PY + 74, "joint — it takes the mechanical load.", size=11, fill=MUTED)
s.path(f"M{x+20},{BOARD_Y-14} L{x+86},{BOARD_Y-14} L{x+124},{BOARD_Y-8}", stroke=RED, sw=3.4)
s.rect(x + 22, BOARD_Y - 22, 46, 16, fill="#bfdbfe", stroke=BLUE, sw=1.4, rx=2, op="0.85")
s.path(f"M{x+100},{BOARD_Y-5} Q{x+124},{BOARD_Y-26} {x+152},{BOARD_Y-5} Z", fill="#fcd34d", stroke=AMBER, sw=1.6)
s.path(f"M{x+88},{BOARD_Y-5} Q{x+126},{BOARD_Y-38} {x+164},{BOARD_Y-5} Z", fill="#c7d2fe", stroke="#4f46e5", sw=1.6, dash="4 3")
s.text(x + 126, BOARD_Y - 32, "E6000 cap", size=10, fill="#3730a3", anchor="middle", weight="700")

# ------------------------------------------------------------------ gate --
GY = 292
s.rect(24, GY, 596, 96, fill="#f8fafc", stroke=INK, sw=1.5, rx=10)
s.text(42, GY + 24, "Then the gate — two measurements decide whether glue was enough", size=13, weight="700")
s.circle(56, GY + 50, 9, fill=GREEN, stroke="none")
s.text(56, GY + 54, "Ω", size=12, fill="#fff", anchor="middle", weight="700")
s.text(74, GY + 48, "Meter battery lead → pad: ≤ ~0.2 Ω", size=12, weight="600")
s.text(74, GY + 65, "(subtract your probe-lead resistance — short the probes first and note the reading)", size=10.5, fill=MUTED)
s.circle(56, GY + 82, 9, fill=GREEN, stroke="none")
s.text(56, GY + 86, "▶", size=9, fill="#fff", anchor="middle")
s.text(74, GY + 80, "Stream for 10 minutes on battery alone — zero reboots", size=12, weight="600")

s.rect(636, GY, 296, 96, fill="#fef2f2", stroke=RED, sw=1.5, rx=10)
s.text(654, GY + 24, "If it fails", size=13, weight="700", fill="#991b1b")
s.lines(654, GY + 46, [
    "Reboots mid-stream = joint resistance.",
    "Re-glue once with more contact area;",
    "still failing → solder the two pads",
    "(~5 min, §12.1). Nothing is wasted.",
], size=11.5, fill="#991b1b", lh=15)
s.save('/home/claude/diagrams/PokemonRig-GlueJoint.svg')
