"""Tiny SVG builder shared by the rig assembly diagrams."""

INK = "#1f2933"; MUTED = "#6b7280"; LIGHT = "#9ca3af"
RED = "#c0392b"; BLK = "#111827"; AMBER = "#d97706"
BLUE = "#2563eb"; GREEN = "#15803d"; PANEL = "#f3f4f6"; CARD = "#ffffff"
FONT = "ui-sans-serif, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
MONO = "ui-monospace, 'Cascadia Code', Consolas, monospace"


class Svg:
    def __init__(self, w, h, title=""):
        self.w, self.h, self.title = w, h, title
        self.parts = []

    def add(self, s):
        self.parts.append(s)
        return self

    def rect(self, x, y, w, h, fill="none", stroke=INK, sw=1.4, rx=0, dash=None, op=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        o = f' opacity="{op}"' if op else ""
        return self.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
                        f'rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}{o}/>')

    def circle(self, cx, cy, r, fill="none", stroke=INK, sw=1.4):
        return self.add(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fill}" '
                        f'stroke="{stroke}" stroke-width="{sw}"/>')

    def line(self, x1, y1, x2, y2, stroke=INK, sw=1.4, dash=None, cap="round", marker=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        m = f' marker-end="url(#{marker})"' if marker else ""
        return self.add(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
                        f'stroke="{stroke}" stroke-width="{sw}" stroke-linecap="{cap}"{d}{m}/>')

    def path(self, d, stroke=INK, sw=1.4, fill="none", dash=None, marker=None, cap="round"):
        da = f' stroke-dasharray="{dash}"' if dash else ""
        m = f' marker-end="url(#{marker})"' if marker else ""
        return self.add(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" '
                        f'stroke-linecap="{cap}" stroke-linejoin="round"{da}{m}/>')

    def text(self, x, y, s, size=12, fill=INK, anchor="start", weight="400", font=None, italic=False):
        st = ' font-style="italic"' if italic else ""
        s = (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        return self.add(f'<text x="{x:.1f}" y="{y:.1f}" font-family="{font or FONT}" '
                        f'font-size="{size}" fill="{fill}" text-anchor="{anchor}" '
                        f'font-weight="{weight}"{st}>{s}</text>')

    def lines(self, x, y, rows, size=11.5, fill=MUTED, anchor="start", lh=14, weight="400"):
        for i, r in enumerate(rows):
            self.text(x, y + i * lh, r, size=size, fill=fill, anchor=anchor, weight=weight)
        return self

    def badge(self, x, y, n, color=INK, r=11):
        self.circle(x, y, r, fill=color, stroke="none")
        return self.text(x, y + 4.2, str(n), size=12.5, fill="#ffffff", anchor="middle", weight="700")

    def render(self):
        defs = f'''<defs>
  <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7"
          orient="auto-start-reverse"><path d="M0,1 L9,5 L0,9 z" fill="{INK}"/></marker>
  <marker id="arrowR" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7"
          orient="auto-start-reverse"><path d="M0,1 L9,5 L0,9 z" fill="{RED}"/></marker>
  <marker id="arrowM" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6"
          orient="auto-start-reverse"><path d="M0,1 L9,5 L0,9 z" fill="{MUTED}"/></marker>
  <marker id="arrowG" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7"
          orient="auto-start-reverse"><path d="M0,1 L9,5 L0,9 z" fill="{GREEN}"/></marker>
  <pattern id="hatch" width="6" height="6" patternTransform="rotate(45)" patternUnits="userSpaceOnUse">
    <line x1="0" y1="0" x2="0" y2="6" stroke="{LIGHT}" stroke-width="2.5"/></pattern>
</defs>'''
        body = "\n".join(self.parts)
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}" role="img" aria-label="{self.title}">\n'
                f'{defs}\n<rect width="{self.w}" height="{self.h}" fill="{CARD}"/>\n{body}\n</svg>\n')

    def save(self, path):
        with open(path, "w", encoding="utf-8") as f:
            f.write(self.render())
        print("wrote", path)
