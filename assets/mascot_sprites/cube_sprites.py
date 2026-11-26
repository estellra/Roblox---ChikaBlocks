"""Cube-plush cat sprites: every cell is a puffy cube, the head cell carries the face and ears.
usage: python -I cube_sprites.py <Pieces.luau> <out_dir> [all]"""
import json
import math
import os
import random
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import cat_sprites as cs

K, M, CELL_PX = cs.K, cs.MARGIN_U, cs.CELL_PX

VARIANTS = {
    "black": dict(fur=(52, 48, 60), ink=(22, 20, 28), ear_in=(232, 176, 188), stripes=None, mask=None,
                  ring=(255, 205, 70), iris=None, pupil=(20, 18, 26), pale=(80, 76, 90)),
    "siamese": dict(fur=(247, 237, 214), ink=(112, 80, 62), ear=(122, 76, 56), ear_in=(210, 160, 140), stripes=None,
                    mask=(124, 78, 58), ring=(240, 246, 252), iris=(120, 182, 232), pupil=(30, 40, 62), pale=(255, 250, 238)),
    "ginger": dict(fur=(230, 178, 104), ink=(142, 92, 44), ear_in=(255, 240, 230), stripes=(242, 140, 58), mask=None,
                   ring=(255, 255, 255), iris=None, pupil=(40, 30, 30), pale=(250, 226, 186)),
    "gray": dict(fur=(176, 172, 186), ink=(84, 80, 96), ear_in=(232, 184, 194), stripes=(62, 58, 70), mask=None,
                 ring=(255, 255, 255), iris=None, pupil=(34, 30, 38), pale=(208, 204, 216)),
}


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def render(pid, rows, vname):
    v = VARIANTS[vname]
    cs.INK = v["ink"]
    cells = {(x, y) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == "#"}
    w, h = max(x for x, _ in cells) + 1, len(rows)
    cs.CW, cs.CH = int((w * 200 + 2 * M) * K), int((h * 200 + 2 * M) * K)
    CW, CH = cs.CW, cs.CH
    cs.canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    cs.DX = cs.DY = 0.0
    rng = random.Random(pid + vname)
    ox = lambda c: M + c[0] * 200
    oy = lambda c: M + c[1] * 200
    cxu = lambda c: ox(c) + 100
    cyu = lambda c: oy(c) + 100

    def degree(c):
        return sum((c[0] + dx, c[1] + dy) in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))

    def exposed(c):
        return [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (c[0] + dx, c[1] + dy) not in cells]

    top = min(c[1] for c in cells)
    hc = min((c for c in cells if c[1] == top), key=lambda c: (degree(c), c[0]))
    rear = max(cells, key=lambda c: (abs(c[0] - hc[0]) + abs(c[1] - hc[1]), c[1], c[0]))

    # silhouette: puffy cubes that touch, with a small pinch at the corners where they join
    sil = cs.new_mask()
    sd = ImageDraw.Draw(sil)
    cellmask = {}
    for c in cells:
        x0, y0 = ox(c), oy(c)
        sd.rounded_rectangle(((x0 + 3) * K, (y0 + 3) * K, (x0 + 197) * K, (y0 + 197) * K), 56 * K, fill=255)
        cm = cs.new_mask()
        ImageDraw.Draw(cm).rounded_rectangle(((x0 + 3) * K, (y0 + 3) * K, (x0 + 197) * K, (y0 + 197) * K), 56 * K, fill=255)
        cellmask[c] = cm
        if (c[0] + 1, c[1]) in cells:
            sd.rectangle(((x0 + 150) * K, (y0 + 40) * K, (x0 + 250) * K, (y0 + 160) * K), fill=255)
        if (c[0], c[1] + 1) in cells:
            sd.rectangle(((x0 + 40) * K, (y0 + 150) * K, (x0 + 160) * K, (y0 + 250) * K), fill=255)
    sil = sil.filter(ImageFilter.GaussianBlur(1.0))

    fur, pale = v["fur"], v["pale"]
    dark_stripe = v["stripes"]

    # tail stub (behind)
    ex = exposed(rear)
    if rear != hc:
        vx, vy = rear[0] - hc[0], rear[1] - hc[1]
        tdir = max(ex, key=lambda e: (e[0] * vx + e[1] * vy, e[0], e[1])) if ex else (1, 0)
    else:
        tdir = (1, 0) if (1, 0) in ex else (ex[0] if ex else (1, 0))
    u, vv = tdir, (-tdir[1], tdir[0])
    tp = [(cxu(rear) + a * u[0] + b * vv[0], cyu(rear) + a * u[1] + b * vv[1]) for a, b in ((70, 0), (118, 22), (138, -8), (118, -46))]
    tail = cs.stroke(tp, 34)
    cs.paint(tail, fur)
    if dark_stripe:
        path = cs.sp(tp, False)
        for frac in (0.4, 0.62, 0.84):
            i = int(frac * (len(path) - 1))
            (px, py), (qx, qy) = path[i], path[min(i + 2, len(path) - 1)]
            ang = math.atan2(qy - py, qx - px) + math.pi / 2
            dx_, dy_ = math.cos(ang) * 18 * K, math.sin(ang) * 18 * K
            ring = cs.new_mask()
            ImageDraw.Draw(ring).line((px - dx_, py - dy_, px + dx_, py + dy_), fill=255, width=int(8 * K))
            cs.clip_paint(ring, tail, dark_stripe)

    # paws under the bottom row
    bottom = max(c[1] for c in cells)
    row = sorted(c for c in cells if c[1] == bottom)
    for px, c in ((cxu(row[0]) - 46, row[0]), (cxu(row[-1]) + 46, row[-1])):
        cs.paint(cs.ell_mask(px, oy(c) + 190, 27, 17), pale)

    # ears behind the head cell
    hx, hy = cxu(hc), cyu(hc)
    ear_col = v.get("ear", fur)
    for sgn in (-1, 1):
        pts = [(hx + sgn * 92, hy - 70), (hx + sgn * 82, hy - 124), (hx + sgn * 64, hy - 142), (hx + sgn * 40, hy - 118), (hx + sgn * 24, hy - 80)]
        ear = cs.poly_mask(pts)
        cs.paint(ear, ear_col)
        inner = [(hx + sgn * 78, hy - 82), (hx + sgn * 70, hy - 118), (hx + sgn * 60, hy - 126), (hx + sgn * 46, hy - 108), (hx + sgn * 38, hy - 84)]
        cs.clip_paint(cs.poly_mask(inner), ear, v["ear_in"])

    # body
    cs.paint(sil, fur)

    # fur strokes, clipped to the silhouette
    lay = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    for c in cells:
        for _ in range(170):
            x, y = ox(c) + rng.uniform(8, 192), oy(c) + rng.uniform(8, 192)
            ang = math.pi / 2 + rng.uniform(-0.6, 0.6)
            ln = rng.uniform(9, 17)
            f = rng.choice((0.9, 0.94, 1.07, 1.12))
            col = shade(fur, f) + (150,)
            ld.line((x * K, y * K, (x + math.cos(ang) * ln) * K, (y + math.sin(ang) * ln) * K), fill=col, width=int(1.7 * K))
    lay.putalpha(ImageChops.multiply(lay.getchannel("A"), sil.filter(ImageFilter.MinFilter(9))))
    cs.canvas.alpha_composite(lay)

    # siamese mask and tabby stripes
    face_cell = cellmask[hc]
    if v["mask"]:
        cs.clip_paint(cs.ell_mask(hx, hy - 4, 84, 56).filter(ImageFilter.GaussianBlur(3)), face_cell, v["mask"])
    if dark_stripe:
        for dx_ in (-24, 0, 24):
            st = cs.stroke([(hx + dx_, hy - 92 + abs(dx_) * 0.3), (hx + dx_ * 0.9, hy - 66 + abs(dx_) * 0.3)], 9)
            cs.clip_paint(st, face_cell, dark_stripe)
        for c in cells:
            if c != hc and rng.random() < 0.8:
                sx = ox(c) + (190 if rng.random() < 0.5 else 10)
                for k in range(2):
                    st = cs.stroke([(sx - 30 * (1 if sx > ox(c) + 100 else -1), oy(c) + 60 + k * 22), (sx, oy(c) + 66 + k * 22)], 8)
                    cs.clip_paint(st, cellmask[c], dark_stripe)

    # puffy shading per cube: darker towards its edges (lower right most), soft shine top left
    arr = np.asarray(cs.canvas).astype(np.float32)
    for c, cm in cellmask.items():
        m = np.asarray(cm, dtype=np.float32) / 255
        sh = np.asarray(ImageChops.offset(cm, int(-12 * K), int(-9 * K)).filter(ImageFilter.GaussianBlur(14 * K)), dtype=np.float32) / 255
        rim = np.clip((0.92 - sh) / 0.55, 0, 1)
        arr[..., :3] *= 1 - 0.20 * (rim * m)[..., None]
    sil_np = np.asarray(sil, dtype=np.float32) / 255
    shine = cs.new_mask()
    shd = ImageDraw.Draw(shine)
    for c in cells:
        shd.ellipse(((ox(c) + 26) * K, (oy(c) + 22) * K, (ox(c) + 92) * K, (oy(c) + 52) * K), fill=255)
    shn = np.asarray(shine.filter(ImageFilter.GaussianBlur(6 * K)), dtype=np.float32) / 255 * 0.28 * sil_np
    arr[..., :3] = arr[..., :3] * (1 - shn[..., None]) + 255 * shn[..., None]
    cs.canvas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    # face on the head cell
    for sgn in (-1, 1):
        ex_, ey_ = hx + sgn * 46, hy - 8
        cs.paint(cs.ell_mask(ex_, ey_, 29, 29), v["ring"], t=2.0)
        if v["iris"]:
            cs.fill_with(cs.ell_mask(ex_, ey_, 20, 20), v["iris"])
            cs.fill_with(cs.ell_mask(ex_, ey_, 11, 11), v["pupil"])
        else:
            cs.fill_with(cs.ell_mask(ex_ + 1, ey_ + 1, 19, 19), v["pupil"])
        cs.fill_with(cs.ell_mask(ex_ - 7, ey_ - 8, 6, 6), (255, 255, 255))
        cs.fill_with(cs.ell_mask(ex_ + 8, ey_ + 8, 3, 3), (255, 255, 255))
        for k in range(3):
            tick = cs.stroke([(hx + sgn * 84 - sgn * k * 5, hy + 22 + k * 2), (hx + sgn * 88 - sgn * k * 5 + sgn * 3, hy + 32 + k * 2)], 2.6)
            cs.fill_with(tick, (232, 128, 150))
    cs.paint(cs.poly_mask([(hx - 7, hy + 22), (hx + 7, hy + 22), (hx, hy + 31)]), (255, 160, 180), t=1.4)
    mouth = cs.new_mask()
    md = ImageDraw.Draw(mouth)
    md.arc(((hx - 13) * K, (hy + 26) * K, (hx) * K, (hy + 42) * K), 10, 170, fill=255, width=int(2.6 * K))
    md.arc(((hx) * K, (hy + 26) * K, (hx + 13) * K, (hy + 42) * K), 10, 170, fill=255, width=int(2.6 * K))
    cs.fill_with(mouth, v["ink"])

    out = cs.canvas.resize((CW // 2, CH // 2), Image.LANCZOS)
    return out, w, h


if __name__ == "__main__":
    pieces = cs.parse_pieces(sys.argv[1])
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    if len(sys.argv) > 3 and sys.argv[3] == "all":
        for vname in VARIANTS:
            d = os.path.join(out_dir, vname)
            os.makedirs(d, exist_ok=True)
            for pid, rows in pieces:
                img, w, h = render(pid, rows, vname)
                img.save(os.path.join(d, f"{pid}.png"))
            print(vname, "done", flush=True)
    show = ["I3_H", "L4_1", "O2", "T4_1"]
    lookup = dict(pieces)
    sc = 0.55
    slot = int(5 * CELL_PX * sc) + 30
    sheet = Image.new("RGBA", (len(show) * slot, len(VARIANTS) * slot), (255, 200, 214, 255))
    dd = ImageDraw.Draw(sheet)
    for j, vname in enumerate(VARIANTS):
        for i, pid in enumerate(show):
            img, w, h = render(pid, lookup[pid], vname)
            im = img.resize((int(img.width * sc), int(img.height * sc)), Image.LANCZOS)
            x0, y0 = i * slot + 10, j * slot + 5
            mg = int(M / 200 * CELL_PX * sc)
            s = int(CELL_PX * sc)
            for yy, r in enumerate(lookup[pid]):
                for xx, ch in enumerate(r):
                    if ch == "#":
                        dd.rounded_rectangle((x0 + mg + xx * s + 2, y0 + mg + yy * s + 2, x0 + mg + (xx + 1) * s - 2, y0 + mg + (yy + 1) * s - 2), 8, fill=(234, 244, 251, 255))
            sheet.alpha_composite(im, (x0, y0))
    sheet.convert("RGB").save(os.path.join(out_dir, "_cube_sheet.png"))
    print("sheet saved")
