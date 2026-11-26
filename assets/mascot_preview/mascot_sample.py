"""Sample: build a stretchy mascot (round head from Figma + drawn tube body) on polyomino shapes.
usage: python -I mascot_sample.py <mascot.png> <out.png>"""
import sys
from collections import Counter
from PIL import Image, ImageDraw

SS = 4            # supersampling
CELL = 192        # px per cell in the final part image
BODY_W = 0.74     # tube width / cell
OUTLINE = 0.045   # outline thickness / cell
HEAD = 1.04       # head circle diameter / cell

SHAPES = {
    "Dot": ["#"], "I3": ["###"], "L3": ["##", "#."], "O2": ["##", "##"],
    "T4": ["###", ".#."], "S": [".##", "##."], "L5": ["#..", "#..", "###"],
    "I5V": ["#", "#", "#", "#", "#"], "O3": ["###", "###", "###"], "R2x3": ["##", "##", "##"],
}


def sample_colors(img):
    px = [p[:3] for p in img.getdata() if p[3] == 255]
    dark = Counter(p for p in px if sum(p) < 260)
    outline = dark.most_common(1)[0][0]
    fill = img.getpixel((180, 125))[:3]  # forehead, above the eyes
    return fill, outline


def head_geometry(img):
    a = img.getchannel("A")
    # the head circle is the big round body; measure it on the row through the eyes, minus hands
    row = [x for x in range(img.width) if a.getpixel((x, 160)) > 0]
    return (row[0] + row[-1]) / 2, 195, row[-1] - row[0]  # cx, cy, diameter


def cell_part(mask, fill, outline):
    """mask: dict with keys N,E,S,W (orthogonal) and NE,SE,SW,NW (diagonal) booleans."""
    n = CELL * SS
    c = n / 2
    half = BODY_W * n / 2
    t = OUTLINE * n
    prims = []  # rectangles/circles as ("r", x0, y0, x1, y1) / ("c", cx, cy, r)
    prims.append(("c", c, c, half))
    if mask["N"]: prims.append(("r", c - half, -n, c + half, c))
    if mask["S"]: prims.append(("r", c - half, c, c + half, 2 * n))
    if mask["W"]: prims.append(("r", -n, c - half, c, c + half))
    if mask["E"]: prims.append(("r", c, c - half, 2 * n, c + half))
    for d, (a, b, box) in {"NE": ("N", "E", (c, -n, 2 * n, c)), "SE": ("S", "E", (c, c, 2 * n, 2 * n)),
                           "SW": ("S", "W", (-n, c, c, 2 * n)), "NW": ("N", "W", (-n, -n, c, c))}.items():
        if mask[a] and mask[b] and mask[d]:
            prims.append(("r",) + box)

    def paint(d, inflate, color):
        for p in prims:
            if p[0] == "c":
                _, cx, cy, r = p
                d.ellipse((cx - r - inflate, cy - r - inflate, cx + r + inflate, cy + r + inflate), fill=color)
            else:
                _, x0, y0, x1, y1 = p
                # inflate only across the arm so it stays flush at the cell edge
                if x1 - x0 > y1 - y0 and not (x0 <= 0 and x1 >= n):
                    pass
                d.rectangle((x0 - inflate, y0 - inflate, x1 + inflate, y1 + inflate), fill=color)

    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    paint(d, t, outline + (255,))
    paint(d, 0, fill + (255,))
    return im.resize((CELL, CELL), Image.LANCZOS)


def build_piece(rows, head_img, fill, outline, cell):
    cells = {(x, y) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == "#"}
    w, h = max(x for x, _ in cells) + 1, len(rows)
    M = round(0.2 * cell)  # margin so the head and feet are not cut off
    canvas = Image.new("RGBA", (w * cell + 2 * M, h * cell + 2 * M), (0, 0, 0, 0))
    for (x, y) in cells:
        has = lambda dx, dy: (x + dx, y + dy) in cells
        m = {"N": has(0, -1), "S": has(0, 1), "W": has(-1, 0), "E": has(1, 0),
             "NE": has(1, -1), "SE": has(1, 1), "SW": has(-1, 1), "NW": has(-1, -1)}
        part = cell_part(m, fill, outline).resize((cell, cell), Image.LANCZOS)
        canvas.alpha_composite(part, (M + x * cell, M + y * cell))

    def degree(c):
        return sum((c[0] + dx, c[1] + dy) in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    ends = [c for c in cells if degree(c) <= 1]
    pool = ends or list(cells)
    hx, hy = min(pool, key=lambda c: (c[1], c[0]))
    cx, cy, dia = head_geometry_cache
    scale = HEAD * cell / dia
    hs = head_img.resize((round(head_img.width * scale), round(head_img.height * scale)), Image.LANCZOS)
    px = round(M + hx * cell + cell / 2 - cx * scale)
    py = round(M + hy * cell + cell / 2 - cy * scale)
    canvas.alpha_composite(hs, (px, py)) if px >= 0 and py >= 0 else canvas.paste(hs, (px, py), hs)
    return canvas, M


src, out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
fill, outline = sample_colors(img)
head_geometry_cache = head_geometry(img)
print("fill", fill, "outline", outline, "head", head_geometry_cache)

CELLP = 84
bg = (255, 200, 214, 255)
names = list(SHAPES)
pad = 24
cols = 5
tiles = []
for name in names:
    p, m = build_piece(SHAPES[name], img, fill, outline, CELLP)
    tiles.append((name, p, m))
slot = 5 * CELLP + pad
rows_n = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGBA", (cols * slot + pad, rows_n * slot + pad), bg)
d = ImageDraw.Draw(sheet)
for i, (name, p, m) in enumerate(tiles):
    ox, oy = pad + (i % cols) * slot, pad + (i // cols) * slot
    for gy in range(5):
        for gx in range(5):
            d.rounded_rectangle((ox + gx * CELLP + 3, oy + gy * CELLP + 3, ox + (gx + 1) * CELLP - 3,
                                 oy + (gy + 1) * CELLP - 3), 14, fill=(234, 244, 251, 255))
    sheet.alpha_composite(p, (ox - m, oy - m)) if False else sheet.paste(p, (ox - m, oy - m), p)
    d.text((ox + 4, oy + 5 * CELLP + 4), name, fill=(78, 61, 74, 255))
sheet.convert("RGB").save(out)
print("saved", out, sheet.size)
