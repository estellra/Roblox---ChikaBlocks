"""Soft 3D calico cat sprites: the head is cut from the reference render, the body/paws/tail are drawn and shaded to match.
usage: python soft_sprites.py <Pieces.luau> <out_dir> <head.png> [all]"""
import math
import os
import random
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import cat_sprites as cs

K, M, CELL_PX = cs.K, cs.MARGIN_U, cs.CELL_PX
WHITE = (252, 250, 246)
BLACK = (58, 48, 48)
BROWN = (172, 108, 78)
YELLOW = (255, 206, 96)
RIM = (205, 198, 208)
COOL = (150, 158, 190)


def shade(mask, hgt_img=None, sigma=15, strength=0.2):
    """3D-ish lighting from the top left, applied to the canvas inside `mask`."""
    m = np.asarray(mask, dtype=np.float32) / 255
    g = np.asarray(hgt_img if hgt_img is not None else mask.filter(ImageFilter.GaussianBlur(sigma * K)), dtype=np.float32) / 255
    gy, gx = np.gradient(g)
    nl = 0.55 * gx + 0.75 * gy
    inside = m > 0.5
    if not inside.any():
        return
    scale = np.percentile(np.hypot(gx, gy)[inside], 98) + 1e-6
    t = np.clip(nl / scale, -1, 1)
    arr = np.asarray(cs.canvas).astype(np.float32)
    rgb = arr[..., :3]
    lit = rgb * (1 + strength * np.clip(t, 0, 1)[..., None])
    neg = np.clip(-t, 0, 1)[..., None]
    shadow = rgb * (1 - 0.10 * neg) * (1 - 0.0) * 0.96 + np.array(COOL, np.float32) * 0.07 * neg
    out = np.where(t[..., None] >= 0, lit, shadow)
    rgb[...] = rgb * (1 - m[..., None]) + np.clip(out, 0, 255) * m[..., None]
    cs.canvas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def soft_paint(mask, color, sigma=12, strength=0.2):
    cs.fill_with(cs.dilate(mask, 2.6 * K), RIM)
    cs.fill_with(mask, color)
    shade(mask, sigma=sigma, strength=strength)


def render(pid, rows, head_src):
    cells = {(x, y) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == "#"}
    w, h = max(x for x, _ in cells) + 1, len(rows)
    cs.CW, cs.CH = int((w * 200 + 2 * M) * K), int((h * 200 + 2 * M) * K)
    CW, CH = cs.CW, cs.CH
    cs.canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    cs.DX = cs.DY = 0.0
    rng = random.Random(pid)
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

    # silhouette and per-cell height map (puffy cubes, soft seams)
    sil = cs.new_mask()
    sd = ImageDraw.Draw(sil)
    hgt = np.zeros((CH, CW), np.float32)
    for c in cells:
        x0, y0 = ox(c), oy(c)
        sd.rounded_rectangle(((x0 + 10) * K, (y0 + 10) * K, (x0 + 190) * K, (y0 + 190) * K), 72 * K, fill=255)
        cm = cs.new_mask()
        ImageDraw.Draw(cm).rounded_rectangle(((x0 + 10) * K, (y0 + 10) * K, (x0 + 190) * K, (y0 + 190) * K), 72 * K, fill=255)
        hgt = np.maximum(hgt, np.asarray(cm.filter(ImageFilter.GaussianBlur(20 * K)), dtype=np.float32) / 255)
        if (c[0] + 1, c[1]) in cells:
            sd.rectangle(((x0 + 130) * K, (y0 + 36) * K, (x0 + 270) * K, (y0 + 164) * K), fill=255)
        if (c[0], c[1] + 1) in cells:
            sd.rectangle(((x0 + 36) * K, (y0 + 130) * K, (x0 + 164) * K, (y0 + 270) * K), fill=255)
    sil = sil.filter(ImageFilter.GaussianBlur(8 * K)).point(lambda v: 255 if v > 120 else 0).filter(ImageFilter.GaussianBlur(1.0))
    hgt_img = Image.fromarray((np.clip(hgt, 0, 1) * 255).astype(np.uint8), "L")

    # tail behind
    ex = exposed(rear)
    if rear != hc:
        vx, vy = rear[0] - hc[0], rear[1] - hc[1]
        tdir = max(ex, key=lambda e: (e[0] * vx + e[1] * vy, e[0], e[1])) if ex else (1, 0)
    else:
        tdir = (1, 0) if (1, 0) in ex else (ex[0] if ex else (1, 0))
    u, vv = tdir, (-tdir[1], tdir[0])
    tp = [(cxu(rear) + a * u[0] + b * vv[0], cyu(rear) + a * u[1] + b * vv[1]) for a, b in ((60, 0), (130, 34), (172, 0), (150, -54))]
    tail = cs.stroke(tp, 46)
    soft_paint(tail, WHITE, sigma=8)
    tip = cs.ell_mask(tp[-1][0], tp[-1][1], 28, 28)
    cs.clip_paint(tip, tail, YELLOW)
    shade(tail, sigma=8, strength=0.18)

    # hind feet
    bottom = max(c[1] for c in cells)
    row = sorted(c for c in cells if c[1] == bottom)
    for fx, c in ((cxu(row[0]) - 44, row[0]), (cxu(row[-1]) + 44, row[-1])):
        foot = cs.ell_mask(fx, oy(c) + 188, 34, 22)
        soft_paint(foot, WHITE, sigma=8)
        for dx_ in (-12, 0, 12):
            cs.fill_with(cs.stroke([(fx + dx_, oy(c) + 194), (fx + dx_, oy(c) + 204)], 2.6), BLACK)

    # body: white with calico patches, then the lighting
    cs.fill_with(cs.dilate(sil, 3 * K), RIM)
    cs.fill_with(sil, WHITE)
    cl = sorted(c for c in cells if c != hc) or [hc]
    rng.shuffle(cl)
    palette = [BLACK, BROWN, YELLOW, BLACK, YELLOW, BROWN]
    for i in range(max(2, int(len(cells) * 0.9))):
        c = cl[i % len(cl)]
        blobm = cs.blob(cxu(c) + rng.uniform(-55, 55), cyu(c) + rng.uniform(-55, 55), rng.uniform(48, 82), rng)
        cs.clip_paint(blobm.filter(ImageFilter.GaussianBlur(1.5)), sil, palette[i % len(palette)])
    shade(sil, hgt_img=hgt_img, strength=0.22)

    # head from the reference render, levelled and scaled to the head cell
    head = head_src.rotate(-12, expand=True, resample=Image.BICUBIC)
    sc = 330 * K / head.width
    hs = head.resize((int(head.width * sc), int(head.height * sc)), Image.LANCZOS)
    hx, hy = cxu(hc) * K, (oy(hc) + 92) * K       # the head's bottom edge rests on the cell's upper part
    # contact shadow on the body under the head
    sh = cs.ell_mask(cxu(hc), oy(hc) + 98, 100, 26).filter(ImageFilter.GaussianBlur(7 * K)).point(lambda v: int(v * 0.35))
    cs.fill_with(ImageChops.multiply(sh, sil), COOL)
    cs.canvas.alpha_composite(hs, (int(hx - hs.width / 2), int(hy - hs.height)))

    # front paws tucked under the chin
    for px in (-40, 40):
        pxc, pyc = cxu(hc) + px, oy(hc) + 132
        paw = cs.ell_mask(pxc, pyc, 24, 30)
        soft_paint(paw, WHITE, sigma=7)
        for dx_ in (-9, 0, 9):
            cs.fill_with(cs.stroke([(pxc + dx_, pyc + 14), (pxc + dx_, pyc + 24)], 2.4), BLACK)

    out = cs.canvas.resize((CW // 2, CH // 2), Image.LANCZOS)
    return out, w, h


if __name__ == "__main__":
    pieces = cs.parse_pieces(sys.argv[1])
    out_dir = sys.argv[2]
    head_src = Image.open(sys.argv[3]).convert("RGBA")
    os.makedirs(out_dir, exist_ok=True)
    lookup = dict(pieces)
    if len(sys.argv) > 4 and sys.argv[4] == "all":
        for pid, rows in pieces:
            img, w, h = render(pid, rows, head_src)
            img.save(os.path.join(out_dir, f"{pid}.png"))
            print(pid, flush=True)
    show = ["Dot", "I3_H", "I3_V", "L3_1", "O2", "T4_1", "S_H", "L4_1", "L5_1", "R2x3", "O3", "I5_V"]
    sc = 0.55
    slot = int(5 * CELL_PX * sc) + 30
    cols = 4
    sheet = Image.new("RGBA", (cols * slot, ((len(show) + cols - 1) // cols) * slot), (255, 200, 214, 255))
    dd = ImageDraw.Draw(sheet)
    for i, pid in enumerate(show):
        img, w, h = render(pid, lookup[pid], head_src)
        im = img.resize((int(img.width * sc), int(img.height * sc)), Image.LANCZOS)
        x0, y0 = (i % cols) * slot + 10, (i // cols) * slot + 5
        mg = int(M / 200 * CELL_PX * sc)
        s = int(CELL_PX * sc)
        for yy, r in enumerate(lookup[pid]):
            for xx, ch in enumerate(r):
                if ch == "#":
                    dd.rounded_rectangle((x0 + mg + xx * s + 2, y0 + mg + yy * s + 2, x0 + mg + (xx + 1) * s - 2, y0 + mg + (yy + 1) * s - 2), 8, fill=(234, 244, 251, 255))
        sheet.alpha_composite(im, (x0, y0))
    sheet.convert("RGB").save(os.path.join(out_dir, "_soft_sheet.png"))
    print("sheet saved")
