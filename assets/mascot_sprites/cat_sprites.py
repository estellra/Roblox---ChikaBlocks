"""Game-ready sprite set: the calico cat drawn for every piece shape in src/shared/Pieces.luau.
usage: python -I cat_sprites.py <Pieces.luau> <out_dir>
Each sprite: transparent PNG, cell size CELL_PX, with a transparent margin of MARGIN cells on every side
so the head, feet and tail can overflow the cells. manifest.json lists the size of each sprite."""
import json
import math
import os
import random
import re
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

CELL_PX = 128          # final pixels per cell
MARGIN_U = 160         # margin around the cells, in drawing units (a cell is 200 units)
K = 1.28               # drawing pixels per unit (2x supersampling of CELL_PX)
INK = (78, 58, 60)
CREAM = (255, 250, 241)
ORANGE = (244, 170, 96)
ORANGE_D = (222, 140, 70)
BLACK = (84, 72, 82)
PINK = (255, 170, 190)
EAR_IN = (255, 190, 196)

CW = CH = 0
canvas = None
DX = DY = 0.0


def sp(points, closed=True, n=12):
    pts = points
    m = len(pts)
    out = []
    for i in (range(m) if closed else range(m - 1)):
        p0 = pts[(i - 1) % m] if closed or i > 0 else pts[0]
        p1, p2 = pts[i], pts[(i + 1) % m]
        p3 = pts[(i + 2) % m] if closed or i + 2 < m else pts[-1]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append(((x + DX) * K, (y + DY) * K))
    if not closed:
        out.append(((pts[-1][0] + DX) * K, (pts[-1][1] + DY) * K))
    return out


def new_mask():
    return Image.new("L", (CW, CH), 0)


def poly_mask(points, closed=True):
    m = new_mask()
    ImageDraw.Draw(m).polygon(sp(points, closed), fill=255)
    return m


def ell_mask(cx, cy, rx, ry):
    m = new_mask()
    ImageDraw.Draw(m).ellipse(((cx - rx + DX) * K, (cy - ry + DY) * K, (cx + rx + DX) * K, (cy + ry + DY) * K), fill=255)
    return m


def union(*ms):
    r = ms[0]
    for m in ms[1:]:
        r = ImageChops.lighter(r, m)
    return r


def dilate(m, r):
    b = m.filter(ImageFilter.GaussianBlur(r * 0.62))
    return b.point(lambda v: 255 if v > 38 else 0).filter(ImageFilter.GaussianBlur(0.8)).point(lambda v: 255 if v > 128 else 0)


def fill_with(mask, color):
    canvas.paste(Image.new("RGBA", (CW, CH), color + (255,)), (0, 0), mask)


def paint(mask, color, outline=True, t=3.2):
    if outline:
        fill_with(dilate(mask, t * K), INK)
    fill_with(mask, color)


def clip_paint(mask, base, color):
    fill_with(ImageChops.multiply(mask, base), color)


def stroke(points, width):
    lay = new_mask()
    d = ImageDraw.Draw(lay)
    pts = sp(points, False) if len(points) > 2 else [((p[0] + DX) * K, (p[1] + DY) * K) for p in points]
    d.line(pts, fill=255, width=int(width * K), joint="curve")
    r = width * K / 2
    for q in (pts[0], pts[-1]):
        d.ellipse((q[0] - r, q[1] - r, q[0] + r, q[1] + r), fill=255)
    return lay


def mirror(points):
    return [(260 - x, y) for x, y in points]  # about the head's centre line x=130


def blob(cx, cy, r, rng):
    pts = []
    for i in range(9):
        a = i / 9 * math.tau
        rr = r * rng.uniform(0.72, 1.2)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return poly_mask(pts)


def parse_pieces(path):
    text = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r'\{ id = "(\w+)", color = COLORS\.\w+, rows = \{([^}]*)\} \}', text):
        out.append((m.group(1), re.findall(r'"([#.]+)"', m.group(2))))
    return out


def render(pid, rows):
    global CW, CH, canvas, DX, DY
    cells = {(x, y) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == "#"}
    w, h = max(x for x, _ in cells) + 1, len(rows)
    CW, CH = int((w * 200 + 2 * MARGIN_U) * K), int((h * 200 + 2 * MARGIN_U) * K)
    canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    DX = DY = 0.0
    rng = random.Random(pid)
    ox = lambda c: MARGIN_U + c[0] * 200
    oy = lambda c: MARGIN_U + c[1] * 200
    cxu = lambda c: ox(c) + 100
    cyu = lambda c: oy(c) + 100

    def degree(c):
        return sum((c[0] + dx, c[1] + dy) in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))

    def exposed(c):
        return [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (c[0] + dx, c[1] + dy) not in cells]

    top = min(c[1] for c in cells)
    hc = min((c for c in cells if c[1] == top), key=lambda c: (degree(c), c[0]))
    rear = max(cells, key=lambda c: (abs(c[0] - hc[0]) + abs(c[1] - hc[1]), c[1], c[0]))

    # ---- silhouette
    m = new_mask()
    d = ImageDraw.Draw(m)
    for c in cells:
        x0, y0 = ox(c), oy(c)
        d.rounded_rectangle(((x0 + 15) * K, (y0 + 15) * K, (x0 + 185) * K, (y0 + 185) * K), 78 * K, fill=255)
        if (c[0] + 1, c[1]) in cells:
            d.rectangle(((x0 + 100) * K, (y0 + 15) * K, (x0 + 300) * K, (y0 + 185) * K), fill=255)
        if (c[0], c[1] + 1) in cells:
            d.rectangle(((x0 + 15) * K, (y0 + 100) * K, (x0 + 185) * K, (y0 + 300) * K), fill=255)
    body = m.filter(ImageFilter.GaussianBlur(16 * K)).point(lambda v: 255 if v > 125 else 0).filter(ImageFilter.GaussianBlur(1.2))

    # ---- tail, behind the body
    ex = exposed(rear)
    if rear != hc:
        vx, vy = rear[0] - hc[0], rear[1] - hc[1]
        tdir = max(ex, key=lambda e: (e[0] * vx + e[1] * vy, e[0], e[1])) if ex else (1, 0)
    else:
        tdir = (1, 0) if (1, 0) in ex else (ex[0] if ex else (1, 0))
    u, v = tdir, (-tdir[1], tdir[0])
    tp = [(cxu(rear) + a * u[0] + b * v[0], cyu(rear) + a * u[1] + b * v[1]) for a, b in ((60, 0), (112, 26), (132, -14), (104, -62))]
    tail = stroke(tp, 30)
    paint(tail, ORANGE)
    path = sp(tp, False)
    for frac in (0.34, 0.5, 0.66, 0.82):
        i = int(frac * (len(path) - 1))
        (px, py), (qx, qy) = path[i], path[min(i + 2, len(path) - 1)]
        ang = math.atan2(qy - py, qx - px) + math.pi / 2
        dx_, dy_ = math.cos(ang) * 16 * K, math.sin(ang) * 16 * K
        ring = new_mask()
        ImageDraw.Draw(ring).line((px - dx_, py - dy_, px + dx_, py + dy_), fill=255, width=int(7 * K))
        clip_paint(ring, tail, ORANGE_D)
    tx, ty = tp[-1]
    clip_paint(ell_mask(tx, ty, 15, 15), tail, CREAM)

    # ---- back feet (bottom row, outer cells)
    bottom = max(c[1] for c in cells)
    row = sorted(c for c in cells if c[1] == bottom)
    spots = [(cxu(row[0]) - 38, row[0]), (cxu(row[-1]) + 38, row[-1])]
    for fx, c in spots:
        paint(ell_mask(fx, oy(c) + 186, 30, 19), CREAM)
        for dx_ in (-9, 9):
            fill_with(stroke([(fx + dx_, oy(c) + 190), (fx + dx_, oy(c) + 200)], 2.4), INK)

    # ---- body + calico patches
    paint(body, CREAM)
    cl = sorted(cells)
    palette = [ORANGE, BLACK, ORANGE, ORANGE, BLACK]
    rng.shuffle(cl)
    for i in range(max(2, int(len(cells) * 0.9))):
        c = cl[i % len(cl)]
        blobm = blob(cxu(c) + rng.uniform(-60, 60), cyu(c) + rng.uniform(-60, 60), rng.uniform(55, 95), rng)
        clip_paint(blobm, body, palette[i % len(palette)])

    bm = np.asarray(body, dtype=np.float32) / 255
    big = body.filter(ImageFilter.GaussianBlur(11 * K))
    sh = np.asarray(ImageChops.offset(body, int(-14 * K), int(-10 * K)).filter(ImageFilter.GaussianBlur(11 * K)), dtype=np.float32) / 255
    rim = np.clip((0.9 - sh) / 0.55, 0, 1)
    arr = np.asarray(canvas).astype(np.float32)
    arr[..., :3] *= 1 - 0.22 * (rim * bm)[..., None]
    hl = np.clip((sh - np.asarray(big, dtype=np.float32) / 255) * 4, 0, 1) * bm
    arr[..., :3] = arr[..., :3] * (1 - 0.35 * hl[..., None]) + 255 * 0.35 * hl[..., None]
    canvas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    # ---- head, drawn in the cat's own coordinates then moved onto the head cell
    DX, DY = cxu(hc) - 130, oy(hc) - 30 - 120
    ear_l = [(54, 108), (46, 56), (58, 26), (80, 36), (116, 68)]
    earL, earR = poly_mask(ear_l), poly_mask(mirror(ear_l))
    head_pts = [(44, 112), (58, 72), (98, 54), (130, 50), (162, 54), (202, 72), (216, 112), (210, 152), (180, 180), (130, 190), (80, 180), (50, 152)]
    head = poly_mask(head_pts)
    tuft = [(52, 120), (30, 130), (40, 138), (28, 150), (56, 154)]
    tl, tr = poly_mask(tuft, False), poly_mask(mirror(tuft), False)
    paint(union(earL, earR), CREAM)
    paint(union(head, tl, tr), CREAM)
    allhead = union(head, earL, earR, tl, tr)
    left, right = (ORANGE, BLACK) if rng.random() < 0.6 else (BLACK, ORANGE)
    clip_paint(poly_mask([(34, 20), (128, 34), (118, 96), (76, 120), (34, 118)]), allhead, left)
    clip_paint(poly_mask([(168, 30), (236, 50), (236, 126), (196, 104), (170, 72)]), allhead, right)
    clip_paint(poly_mask([(100, 40), (160, 40), (146, 74), (130, 90), (114, 74)]), allhead, CREAM)
    clip_paint(poly_mask([(64, 98), (60, 58), (68, 46), (84, 54), (102, 72)]), earL, EAR_IN)
    clip_paint(poly_mask(mirror([(64, 98), (60, 58), (68, 46), (84, 54), (102, 72)])), earR, EAR_IN)
    for exx in (96, 164):
        lay = new_mask()
        ImageDraw.Draw(lay).arc(((exx - 17 + DX) * K, (110 - 8 + DY) * K, (exx + 17 + DX) * K, (110 + 22 + DY) * K), 200, 340, fill=255, width=int(5 * K))
        fill_with(lay, INK)
    for bx in (74, 186):
        fill_with(ell_mask(bx, 140, 17, 10).filter(ImageFilter.GaussianBlur(2 * K)).point(lambda v: int(v * 0.7)), PINK)
    paint(poly_mask([(121, 133), (139, 133), (130, 146)]), PINK, t=1.6)
    mouth = new_mask()
    md = ImageDraw.Draw(mouth)
    md.arc(((112 + DX) * K, (140 + DY) * K, (130 + DX) * K, (158 + DY) * K), 10, 170, fill=255, width=int(3.2 * K))
    md.arc(((130 + DX) * K, (140 + DY) * K, (148 + DX) * K, (158 + DY) * K), 10, 170, fill=255, width=int(3.2 * K))
    fill_with(mouth, INK)
    wh = new_mask()
    wd = ImageDraw.Draw(wh)
    for a, b in ((0, -8), (10, 6), (20, 20)):
        wd.line(((52 + DX) * K, (134 + a + DY) * K, (12 + DX) * K, (132 + b + DY) * K), fill=255, width=int(2.2 * K))
        wd.line(((208 + DX) * K, (134 + a + DY) * K, (248 + DX) * K, (132 + b + DY) * K), fill=255, width=int(2.2 * K))
    fill_with(wh, INK)

    # ---- front paws resting under the head
    for px in (92, 168):
        paint(ell_mask(px, 222, 25, 30), CREAM)
        for dx_ in (-8, 8):
            fill_with(stroke([(px + dx_, 232), (px + dx_, 246)], 2.4), INK)
        fill_with(ell_mask(px, 238, 8, 6), PINK)
    DX = DY = 0.0

    out = canvas.resize((CW // 2, CH // 2), Image.LANCZOS)
    return out, w, h


if __name__ == "__main__":
    pieces = parse_pieces(sys.argv[1])
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    manifest = {"cellPx": CELL_PX, "marginCells": MARGIN_U / 200, "pieces": {}}
    sheet_ids = ["Dot", "I2_H", "I3_V", "L3_1", "O2", "T4_1", "S_H", "L4_1", "I4_H", "L5_1", "R2x3", "O3"]
    sheet = {}
    for pid, rows in pieces:
        img, w, h = render(pid, rows)
        img.save(os.path.join(out_dir, f"{pid}.png"))
        manifest["pieces"][pid] = {"cellsW": w, "cellsH": h, "width": img.width, "height": img.height}
        if pid in sheet_ids:
            sheet[pid] = img
        print(pid, img.size, flush=True)
    json.dump(manifest, open(os.path.join(out_dir, "manifest.json"), "w"), indent=1)

    cols, sc = 4, 0.6
    cellw = int(5 * CELL_PX * sc) + 40
    rows_n = (len(sheet_ids) + cols - 1) // cols
    sh = Image.new("RGBA", (cols * cellw, rows_n * (cellw + 10)), (255, 200, 214, 255))
    dd = ImageDraw.Draw(sh)
    for i, pid in enumerate(sheet_ids):
        if pid not in sheet:
            continue
        im = sheet[pid]
        im = im.resize((int(im.width * sc), int(im.height * sc)), Image.LANCZOS)
        x0, y0 = (i % cols) * cellw + 20, (i // cols) * (cellw + 10) + 10
        mg = int(MARGIN_U / 200 * CELL_PX * sc)
        rows = dict(pieces)[pid]
        for yy, r in enumerate(rows):
            for xx, ch in enumerate(r):
                if ch == "#":
                    s = int(CELL_PX * sc)
                    dd.rounded_rectangle((x0 + mg + xx * s + 2, y0 + mg + yy * s + 2, x0 + mg + (xx + 1) * s - 2, y0 + mg + (yy + 1) * s - 2), 8, fill=(234, 244, 251, 255))
        sh.alpha_composite(im, (x0, y0))
        dd.text((x0, y0 + cellw - 24), pid, fill=(78, 61, 74, 255))
    sh.convert("RGB").save(os.path.join(out_dir, "_sheet.png"))
    print("done", len(pieces))
