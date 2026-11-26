"""v2: plush body silhouette (smooth, shaded, belly, feather texture) + separate head, feet, wings, tail.
usage: python -I mascot_v2.py <mascot.png> <out.png>"""
import math
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

C = 100            # px per cell in the final preview
S = 2              # supersampling
C2 = C * S
M2 = int(0.55 * C2)  # margin around the piece for head, feet and tail

FILL = (255, 229, 154)
OUTLINE = (61, 46, 36)
SHADOW = (226, 184, 96)
BELLY = (255, 247, 218)
WING = (255, 214, 112)
TEXTURE = (232, 192, 104)

SHAPES = {
    "Dot": ["#"], "I3": ["###"], "L3": ["##", "#."], "O2": ["##", "##"],
    "T4": ["###", ".#."], "L5": ["#..", "#..", "###"], "O3": ["###", "###", "###"], "I5V": ["#", "#", "#", "#", "#"],
}


def blur(im, r):
    return im.filter(ImageFilter.GaussianBlur(r))


def arr(im):
    return np.asarray(im, dtype=np.float32) / 255.0


def to_l(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")


def shift(im, dx, dy):
    return ImageChops.offset(im, int(dx), int(dy))


def outlined(mask, fill, t):
    """RGBA of `mask` filled with `fill` and an outline of t px around it."""
    grown = mask.filter(ImageFilter.MaxFilter(2 * t + 1))
    grown = blur(grown, 1).point(lambda v: 255 if v > 110 else 0)
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", mask.size, OUTLINE + (255,)), (0, 0), grown)
    out.paste(Image.new("RGBA", mask.size, fill + (255,)), (0, 0), mask)
    return out


def load_parts(img):
    a = np.asarray(img.getchannel("A"))
    yy, xx = np.mgrid[0:img.height, 0:img.width]
    d = np.hypot(xx - 179.5, yy - 195)
    head_m = (d <= 126) | ((yy < 90) & (xx > 140) & (xx < 240) & (a > 0))
    head = img.copy()
    head.putalpha(Image.fromarray(np.where(head_m, a, 0).astype(np.uint8)))
    bb = head.getbbox()
    head = head.crop(bb)
    head.center = (179.5 - bb[0], 195 - bb[1])
    feet_m = (d > 130) & (yy > 300) & (a > 0)
    feet = []
    for lo, hi in ((0, 180), (180, 360)):
        sub = img.copy()
        m = np.where(feet_m & (xx >= lo) & (xx < hi), a, 0).astype(np.uint8)
        sub.putalpha(Image.fromarray(m))
        feet.append(sub.crop(sub.getbbox()))
    hands = []
    for lo, hi in ((0, 66), (294, 360)):
        sub = img.copy()
        m = np.where((d > 128) & (xx >= lo) & (xx < hi) & (yy > 205) & (yy < 265) & (a > 0), a, 0).astype(np.uint8)
        sub.putalpha(Image.fromarray(m))
        hands.append(sub.crop(sub.getbbox()))
    return head, feet, hands


def build_piece(rows, head, feet, hands):
    cells = {(x, y) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == "#"}
    w, h = max(x for x, _ in cells) + 1, len(rows)
    CW, CH = w * C2 + 2 * M2, h * C2 + 2 * M2
    cx = lambda c: M2 + c[0] * C2 + C2 / 2
    cy = lambda c: M2 + c[1] * C2 + C2 / 2

    # ---- silhouette
    m = Image.new("L", (CW, CH), 0)
    d = ImageDraw.Draw(m)
    pad = 0.015 * C2
    for c in cells:
        x0, y0 = M2 + c[0] * C2, M2 + c[1] * C2
        d.rounded_rectangle((x0 + pad, y0 + pad, x0 + C2 - pad, y0 + C2 - pad), 0.47 * C2, fill=255)
        for dx, dy in ((1, 0), (0, 1)):
            if (c[0] + dx, c[1] + dy) in cells:
                if dx:
                    d.rectangle((x0 + C2 / 2, y0 + 0.09 * C2, x0 + C2 * 1.5, y0 + 0.91 * C2), fill=255)
                else:
                    d.rectangle((x0 + 0.09 * C2, y0 + C2 / 2, x0 + 0.91 * C2, y0 + C2 * 1.5), fill=255)
    rng = np.random.default_rng(len(cells) * 7 + w)
    noise = Image.fromarray((rng.random((CH // 30 + 3, CW // 30 + 3)) * 255).astype(np.uint8), "L").resize((CW, CH), Image.BICUBIC)
    nz = arr(blur(noise, 0.06 * C2))
    nz = (nz - nz.mean()) / (nz.std() + 1e-6)
    bf = arr(blur(m, 0.11 * C2)) + 0.045 * nz
    body = to_l((bf > 0.5).astype(np.float32))
    body = blur(body, 1.5).point(lambda v: 255 if v > 128 else 0)
    body = blur(body, 1.2)  # soft edge, no jaggies

    # ---- head cell: a free end, top-left first; rear: the cell farthest from it
    def degree(c):
        return sum((c[0] + dx, c[1] + dy) in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    pool = [c for c in cells if degree(c) <= 1] or list(cells)
    hc = min(pool, key=lambda c: (c[1], c[0]))
    rear = max(cells, key=lambda c: (abs(c[0] - hc[0]) + abs(c[1] - hc[1]), c[1], c[0]))
    if rear == hc:
        rear = hc

    def exposed(c):
        return [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (c[0] + dx, c[1] + dy) not in cells]

    canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    t = int(0.042 * C2)

    # ---- behind the body: tail tufts and feet
    tail_dir = (1, 0)
    ex = exposed(rear)
    if rear != hc:
        vx, vy = rear[0] - hc[0], rear[1] - hc[1]
        tail_dir = max(ex, key=lambda e: e[0] * vx + e[1] * vy) if ex else (1, 0)
    elif ex:
        tail_dir = (1, 0) if (1, 0) in ex else ex[0]
    ang0 = math.atan2(tail_dir[1], tail_dir[0])
    bx = cx(rear) + tail_dir[0] * 0.40 * C2
    by = cy(rear) + tail_dir[1] * 0.40 * C2
    for off in (-0.55, 0.0, 0.55):
        a = ang0 + off
        ca, sa = math.cos(a), math.sin(a)
        pts = []
        for k in range(0, 13):
            u = k / 12
            px, py = u * 0.5 * C2, 0.1 * C2 * math.sin(u * math.pi) * (1 if off >= 0 else -1) * (0.6 if off else 0.0)
            pts.append((bx + px * ca - py * sa, by + px * sa + py * ca))
        tm = Image.new("L", (CW, CH), 0)
        ImageDraw.Draw(tm).line(pts, fill=255, width=int(0.06 * C2), joint="curve")
        for q in (pts[0], pts[-1]):
            ImageDraw.Draw(tm).ellipse((q[0] - 0.03 * C2, q[1] - 0.03 * C2, q[0] + 0.03 * C2, q[1] + 0.03 * C2), fill=255)
        canvas.alpha_composite(outlined(tm, FILL, int(0.025 * C2)))

    bottom_y = max(c[1] for c in cells)
    bottom = sorted(c for c in cells if c[1] == bottom_y)
    spots = [bottom[0], bottom[-1]] if len(bottom) > 1 else [bottom[0], bottom[0]]
    for i, (c, f) in enumerate(zip(spots, feet)):
        k = 0.50 * C2 / 70
        fs = f.resize((int(f.width * k * 1.35), int(f.height * k * 1.35)), Image.LANCZOS)
        off = (-0.2 if i == 0 else 0.2) if spots[0] == spots[1] else (-0.12 if i == 0 else 0.12)
        px = int(cx(c) + off * C2 - fs.width / 2)
        py = int(M2 + (c[1] + 1) * C2 - fs.height * 0.55)
        canvas.alpha_composite(fs, (px, py))

    # ---- outline + body
    grown = body.filter(ImageFilter.MaxFilter(2 * t + 1))
    grown = blur(grown, 1.2).point(lambda v: 255 if v > 100 else 0)
    canvas.paste(Image.new("RGBA", (CW, CH), OUTLINE + (255,)), (0, 0), grown)

    mf = arr(body)
    b = arr(blur(body, 0.17 * C2))
    bs = arr(blur(shift(body, -0.07 * C2, -0.09 * C2), 0.17 * C2))
    shade = np.clip((0.92 - bs) / 0.5, 0, 1) ** 1.2
    base = np.zeros((CH, CW, 3), np.float32) + np.array(FILL, np.float32)
    base = base * (1 - 0.8 * shade[..., None]) + np.array(SHADOW, np.float32) * 0.8 * shade[..., None]

    belly_in = arr(blur(shift(body, 0, 0.05 * C2), 0.15 * C2))
    belly = np.clip((belly_in - 0.80) / 0.14, 0, 1) * 0.95
    base = base * (1 - belly[..., None]) + np.array(BELLY, np.float32) * belly[..., None]

    # feather scallops, clipped to the inside of the body
    tex = Image.new("L", (CW, CH), 0)
    td = ImageDraw.Draw(tex)
    sp = 0.30 * C2
    j = 0
    y = M2 - sp
    while y < CH:
        x = M2 - sp + (sp / 2 if j % 2 else 0)
        while x < CW:
            td.arc((x, y, x + 0.19 * C2, y + 0.13 * C2), 15, 165, fill=255, width=max(2, int(0.02 * C2)))
            x += sp
        y += sp * 0.62
        j += 1
    tex = arr(tex) * np.clip((b - 0.85) / 0.1, 0, 1) * (1 - belly * 0.6)
    base = base * (1 - 0.55 * tex[..., None]) + np.array(TEXTURE, np.float32) * 0.55 * tex[..., None]

    light = np.clip((bs - b) * 5.0, 0, 1) * np.clip((b - 0.55) / 0.2, 0, 1)
    base = base * (1 - 0.5 * light[..., None]) + 255 * 0.5 * light[..., None]

    # a soft white shine on the top-left of every cell, like the game's blocks
    shine = Image.new("L", (CW, CH), 0)
    sd = ImageDraw.Draw(shine)
    for c in cells:
        sd.ellipse((M2 + c[0] * C2 + 0.16 * C2, M2 + c[1] * C2 + 0.12 * C2, M2 + c[0] * C2 + 0.42 * C2, M2 + c[1] * C2 + 0.24 * C2), fill=255)
    shine = arr(blur(shine, 0.02 * C2)) * 0.55 * mf
    base = base * (1 - shine[..., None]) + 255 * shine[..., None]

    rgb = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    canvas.paste(rgb, (0, 0), body)

    # ---- front paws beside the head (the little hands from the Figma mascot, enlarged)
    kh = 1.14 * C2 / 252
    for i, hd in enumerate(hands):
        hs2 = hd.resize((int(hd.width * kh * 1.9), int(hd.height * kh * 1.9)), Image.LANCZOS)
        side = -1 if i == 0 else 1
        px = int(cx(hc) + side * 0.40 * C2 - hs2.width / 2)
        py = int(cy(hc) + 0.16 * C2 - hs2.height / 2)
        canvas.alpha_composite(hs2, (px, py))

    # ---- head: a soft shadow on the body, then the head cut from the Figma mascot
    hx, hy = cx(hc) - 0.02 * C2, cy(hc) - 0.10 * C2
    sh = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(sh).ellipse((hx - 0.5 * C2, hy + 0.06 * C2, hx + 0.5 * C2, hy + 0.6 * C2), fill=120)
    sh = ImageChops.multiply(blur(sh, 0.07 * C2), body)
    canvas.paste(Image.new("RGBA", (CW, CH), (150, 100, 40, 255)), (0, 0), sh)
    k = 1.14 * C2 / 252
    hs = head.resize((int(head.width * k), int(head.height * k)), Image.LANCZOS)
    ccx, ccy = head.center
    canvas.alpha_composite(hs, (int(hx - ccx * k), int(hy - ccy * k)))
    return canvas.resize((CW // S, CH // S), Image.LANCZOS), M2 // S


src, out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
head, feet, hands = load_parts(img)
head.save(out.replace(".png", "_head.png"))
print("head", head.size, "feet", [f.size for f in feet], "hands", [h.size for h in hands])

tiles = [(n, *build_piece(r, head, feet, hands)) for n, r in SHAPES.items()]
pad = 24
cols = 4
slot = 5 * C + pad
sheet = Image.new("RGBA", (cols * slot + pad, 2 * slot + pad), (255, 200, 214, 255))
d = ImageDraw.Draw(sheet)
for i, (name, p, m) in enumerate(tiles):
    ox, oy = pad + (i % cols) * slot, pad + (i // cols) * slot
    for gy in range(5):
        for gx in range(5):
            d.rounded_rectangle((ox + gx * C + 3, oy + gy * C + 3, ox + (gx + 1) * C - 3, oy + (gy + 1) * C - 3), 12, fill=(234, 244, 251, 255))
    sheet.paste(p, (ox - m, oy - m), p)
    d.text((ox + 4, oy + 5 * C + 4), name, fill=(78, 61, 74, 255))
sheet.convert("RGB").save(out)
print("saved", out, sheet.size)
