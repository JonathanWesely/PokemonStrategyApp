import sys; sys.path.insert(0, '/home/claude/diagrams')
from svgkit import *

W, H = 980, 636
s = Svg(W, H, "Camera swap and why the stream resolution changes")
s.text(24, 32, "The 160° camera — swap it in, then raise the resolution", size=17, weight="700")
s.text(24, 52, "A 160° lens puts the whole room in frame, so the Switch screen lands on a much smaller slice of the sensor. That is fine — we scan", size=12, fill=MUTED)
s.text(24, 68, "every 5 s, so frame rate is irrelevant and we simply take the pixels back by streaming at the sensor's full 1600 × 1200.", size=12, fill=MUTED)

# ============================================================ swap row ====
PY, PH_, PW_ = 92, 190, 300
def panel(i, title):
    x = 24 + i * (PW_ + 16)
    s.rect(x, PY, PW_, PH_, fill=CARD, stroke="#e5e7eb", sw=1.4, rx=10)
    s.badge(x + 24, PY + 24, i + 1, color=INK)
    s.text(x + 42, PY + 29, title, size=12.5, weight="700")
    return x

def board(x):
    s.rect(x + 40, PY + 118, 120, 26, fill="#eef2ff", stroke=INK, sw=1.4, rx=3)
    s.text(x + 52, PY + 135, "Sense", size=9.5, fill=LIGHT)
    s.rect(x + 150, PY + 114, 38, 34, fill="#cbd5e1", stroke=INK, sw=1.4, rx=2)
    s.text(x + 169, PY + 162, "FPC socket", size=9, fill=MUTED, anchor="middle")

# 1 — record the orientation
x = panel(0, "Photograph it first")
s.lines(x + 18, PY + 52, [
    "Seeed doesn't document which way the",
    "contacts face — so photograph the stock",
    "ribbon while it's still seated.",
], size=10.5, lh=13)
board(x)
s.path(f"M{x+188},{PY+124} L{x+248},{PY+110}", stroke=AMBER, sw=3.2)
s.text(x + 286, PY + 106, "ribbon", size=9.5, fill="#92400e", weight="700", anchor="end")
s.text(x + 18, PY + 180, "The new one goes back in the same way.", size=10.5, weight="700")

# 2 — lift the latch
x = panel(1, "Lift the latch, don't force it")
s.lines(x + 18, PY + 52, [
    "The dark flap on the socket rotates up",
    "~90°; the old ribbon then slides straight",
    "out with zero force. If it resists, the",
    "latch isn't fully open.",
], size=10.5, lh=13)
board(x)
s.path(f"M{x+168},{PY+114} A 18 18 0 0 1 {x+186},{PY+100}", stroke=GREEN, sw=2.6, marker="arrowG")
s.text(x + 194, PY + 106, "flip up", size=10, fill=GREEN, weight="700")
s.text(x + 18, PY + 180, "A torn latch ends the board.", size=10.5, weight="700", fill=RED)

# 3 — seat + close
x = panel(2, "Seat fully, close, verify")
s.lines(x + 18, PY + 52, [
    "Push the new ribbon in square and all",
    "the way, then close the flap. Tug gently",
    "— a half-seated ribbon shows up as",
    "\"Camera init failed\" or a green frame.",
], size=10.5, lh=13)
board(x)
s.line(x + 258, PY + 131, x + 196, PY + 131, stroke=AMBER, sw=3.2)
s.path(f"M{x+232},{PY+131} L{x+206},{PY+131}", stroke=GREEN, sw=2.2, marker="arrowG")
s.text(x + 18, PY + 180, "Keep the stock camera as a spare.", size=10.5, weight="700")

# ====================================================== coverage + table ==
CY = 300
s.line(24, CY, W - 24, CY, stroke="#e5e7eb", sw=1)
s.text(24, CY + 26, "Why the resolution has to go up", size=14, weight="700")

fx, fy, fw, fh = 40, CY + 44, 230, 173
s.text(fx + fw / 2, fy - 8, "what the 160° lens sees at 13 cm", size=10.5, fill=MUTED, anchor="middle")
s.rect(fx, fy, fw, fh, fill="#f1f5f9", stroke=INK, sw=1.6, rx=4)
sw_, sh_ = fw * 0.45, fh * 0.45
sxx, syy = fx + (fw - sw_) / 2, fy + (fh - sh_) / 2
s.rect(sxx, syy, sw_, sh_, fill="#dbeafe", stroke=BLUE, sw=1.8)
s.text(sxx + sw_ / 2, syy + sh_ / 2 - 3, "Switch screen", size=10, weight="700", anchor="middle", fill="#1e3a8a")
s.text(sxx + sw_ / 2, syy + sh_ / 2 + 11, "≈45% of frame", size=9, anchor="middle", fill="#1e3a8a")
s.text(fx + 8, fy + fh - 9, "the rest is your lap, the table, the wall", size=9, fill=LIGHT)
s.text(fx, fy + fh + 20, "The screen's diagonal subtends 72° of the lens's 160°.", size=10.5, fill=MUTED)

tx0 = 312
s.rect(tx0, CY + 44, 632, 92, fill="#fef2f2", stroke=RED, sw=1.4, rx=8)
s.text(tx0 + 16, CY + 66, "SVGA 800 × 600 — the old recommendation, wrong for this lens", size=12.5, weight="700", fill="#991b1b")
s.text(tx0 + 16, CY + 86, "Screen lands on ≈360 × 270 px · a name banner ≈54 px wide · glyphs ≈7 px tall.", size=11.5, fill="#991b1b")
s.text(tx0 + 16, CY + 104, "ML Kit needs roughly double that to read a name reliably — OCR would be guessing.", size=11.5, fill="#991b1b")
s.text(tx0 + 16, CY + 124, "SVGA was fine for a PHONE camera, where the screen fills most of the frame.", size=10.5, fill="#991b1b", italic=True)

s.rect(tx0, CY + 148, 632, 78, fill="#dcfce7", stroke=GREEN, sw=1.6, rx=8)
s.text(tx0 + 16, CY + 170, "UXGA 1600 × 1200 — use this", size=12.5, weight="700", fill="#14532d")
s.text(tx0 + 16, CY + 190, "Screen lands on ≈720 × 540 px · banner ≈108 px · glyphs ≈15 px. Preview sprites ≈90 px", size=11.5, fill="#14532d")
s.text(tx0 + 16, CY + 208, "each, far above the matcher's 24 px descriptor. It costs frame rate — which we never use.", size=11.5, fill="#14532d")

s.rect(24, 552, W - 48, 68, fill="#fffbeb", stroke=AMBER, sw=1.3, rx=8)
s.text(40, 574, "Swap BEFORE you collect any exemplars.", size=12, weight="700", fill="#92400e")
s.text(40, 592, "The local matcher learns from crops of your own confirmed photos, so teaching it through the stock lens stores the wrong distortion", size=11.5, fill="#92400e")
s.text(40, 608, "and scale. Flash with the stock camera to prove the toolchain, then swap the module, then start scanning.", size=11.5, fill="#92400e")
s.save('/home/claude/diagrams/PokemonRig-Camera.svg')
