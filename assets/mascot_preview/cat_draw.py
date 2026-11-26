"""Redraw a long calico cat (1 cell wide, 3 cells tall) in a flat cute style, original artwork.
usage: python -I cat_draw.py <out_sprite.png> <out_preview.png>"""
import math
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SS = 3
W, H = 290, 700          # 1x units; the cat body is 3 cells tall
CW, CH = W * SS, H * SS
INK = (78, 58, 60)
CREAM = (255, 250, 241)
ORANGE = (244, 170, 96)
ORANGE_D = (222, 140, 70)
BLACK = (84, 72, 82)
PINK = (255, 170, 190)
EAR_IN = (255, 190, 196)


def sp(points, closed=True, n=14):
    """Catmull-Rom through points, in 1x units, returned scaled by SS."""
    pts = points
    out = []
    m = len(pts)
    rng = range(m) if closed else range(m - 1)
    for i in rng:
        p0 = pts[(i - 1) % m] if closed or i > 0 else pts[0]
        p1 = pts[i]
        p2 = pts[(i + 1) % m]
        p3 = pts[(i + 2) % m] if closed or i + 2 < m else pts[-1]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x * SS, y * SS))
    if not closed:
        out.append((pts[-1][0] * SS, pts[-1][1] * SS))
    return out


def poly_mask(points, closed=True):
    m = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(m).polygon(sp(points, closed), fill=255)
    return m


def ell_mask(cx, cy, rx, ry):
    m = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(m).ellipse(((cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS), fill=255)
    return m


def union(*ms):
    r = ms[0]
    for m in ms[1:]:
        r = ImageChops.lighter(r, m)
    return r


def grow(m, px):
    return ImageChops.lighter(m, ImageChops.invert(ImageChops.invert(m).filter(ImageFilter.MinFilter(1))))  # placeholder, replaced below


def dilate(m, r):
    b = m.filter(ImageFilter.GaussianBlur(r * 0.62))
    return b.point(lambda v: 255 if v > 38 else 0).filter(ImageFilter.GaussianBlur(0.8)).point(lambda v: 255 if v > 128 else 0)


canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))


def paint(mask, color, outline=True, t=3.2):
    if outline:
        g = dilate(mask, t * SS)
        canvas.paste(Image.new("RGBA", (CW, CH), INK + (255,)), (0, 0), g)
    canvas.paste(Image.new("RGBA", (CW, CH), color + (255,)), (0, 0), mask)


def clip_paint(mask, base, color):
    canvas.paste(Image.new("RGBA", (CW, CH), color + (255,)), (0, 0), ImageChops.multiply(mask, base))


def stroke(points, width, color, closed=False, cap=True, dash=None):
    lay = Image.new("L", (CW, CH), 0)
    d = ImageDraw.Draw(lay)
    pts = sp(points, closed) if len(points) > 2 else [(p[0] * SS, p[1] * SS) for p in points]
    d.line(pts, fill=255, width=int(width * SS), joint="curve")
    if cap:
        for q in (pts[0], pts[-1]):
            r = width * SS / 2
            d.ellipse((q[0] - r, q[1] - r, q[0] + r, q[1] + r), fill=255)
    return lay


def mirror(points):
    return [(W - x, y) for x, y in points]


# ---------------------------------------------------------------- tail (behind the body)
tail_path = [(160, 600), (214, 612), (246, 570), (240, 500), (216, 462)]
tail = stroke(tail_path, 30, ORANGE)
paint(tail, ORANGE)
for u in (0.30, 0.46, 0.62, 0.78):
    # dark rings across the tail
    i = int(u * (len(sp(tail_path, False)) - 1))
    px, py = sp(tail_path, False)[i]
    px2, py2 = sp(tail_path, False)[min(i + 2, len(sp(tail_path, False)) - 1)]
    ang = math.atan2(py2 - py, px2 - px) + math.pi / 2
    dx, dy = math.cos(ang) * 15 * SS, math.sin(ang) * 15 * SS
    ring = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(ring).line((px - dx, py - dy, px + dx, py + dy), fill=255, width=int(7 * SS))
    clip_paint(ring, tail, ORANGE_D)
tip = ell_mask(216, 462, 15, 15)
clip_paint(tip, tail, CREAM)

# ---------------------------------------------------------------- back feet
for fx in (92, 168):
    foot = ell_mask(fx, 636, 30, 19)
    paint(foot, CREAM)
    for dx in (-9, 9):
        canvas.paste(Image.new("RGBA", (CW, CH), INK + (255,)), (0, 0), stroke([(fx + dx, 640), (fx + dx, 650)], 2.4, INK))

# ---------------------------------------------------------------- body
body_pts = [(58, 150), (130, 140), (202, 150), (216, 220), (212, 330), (208, 440), (214, 530),
            (198, 604), (130, 626), (62, 604), (46, 530), (52, 440), (46, 330), (44, 220)]
body = poly_mask(body_pts)
paint(body, CREAM)

# calico patches, clipped to the body
clip_paint(poly_mask([(150, 150), (236, 150), (238, 330), (196, 372), (160, 320), (142, 240)]), body, BLACK)
clip_paint(poly_mask([(16, 262), (112, 248), (126, 330), (104, 430), (24, 440)]), body, ORANGE)
clip_paint(poly_mask([(122, 520), (236, 500), (236, 620), (130, 630)]), body, ORANGE)
clip_paint(ell_mask(82, 520, 26, 20), body, BLACK)
clip_paint(ell_mask(178, 436, 22, 16), body, ORANGE)

# soft shading: darker towards the lower right, a lighter rim on the upper left
bm = np.asarray(body, dtype=np.float32) / 255
sh = np.asarray(ImageChops.offset(body, -14 * SS, -10 * SS).filter(ImageFilter.GaussianBlur(11 * SS)), dtype=np.float32) / 255
rim = np.clip((0.9 - sh) / 0.55, 0, 1)
arr = np.asarray(canvas).astype(np.float32)
tone = 1 - 0.22 * rim[..., None] * bm[..., None]
arr[..., :3] = arr[..., :3] * tone
hl = np.clip((sh - np.asarray(body.filter(ImageFilter.GaussianBlur(11 * SS)), dtype=np.float32) / 255) * 4, 0, 1) * bm
arr[..., :3] = arr[..., :3] * (1 - 0.35 * hl[..., None]) + 255 * 0.35 * hl[..., None]
canvas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

# fur ticks
rng = np.random.default_rng(3)
tk = Image.new("L", (CW, CH), 0)
td = ImageDraw.Draw(tk)
for _ in range(45):
    x, y = rng.uniform(56, 204), rng.uniform(170, 600)
    a = rng.uniform(-0.5, 0.5) + math.pi / 2
    td.line((x * SS, y * SS, (x + 6 * math.cos(a)) * SS, (y + 9 * math.sin(a)) * SS), fill=110, width=int(1.4 * SS))
inner = body.filter(ImageFilter.MinFilter(15))
canvas.paste(Image.new("RGBA", (CW, CH), (150, 110, 100, 255)), (0, 0), ImageChops.multiply(tk, inner).filter(ImageFilter.GaussianBlur(0.6)))

# ---------------------------------------------------------------- ears + head
ear_l = [(54, 108), (46, 56), (58, 26), (80, 36), (116, 68)]
ear_r = mirror(ear_l)
earL, earR = poly_mask(ear_l), poly_mask(ear_r)
head_pts = [(44, 112), (58, 72), (98, 54), (130, 50), (162, 54), (202, 72), (216, 112), (210, 152), (180, 180), (130, 190), (80, 180), (50, 152)]
head = poly_mask(head_pts)
tuft_l = poly_mask([(52, 120), (30, 130), (40, 138), (28, 150), (56, 154)], closed=False)
tuft_r = poly_mask(mirror([(52, 120), (30, 130), (40, 138), (28, 150), (56, 154)]), closed=False)
tufts = union(ImageChops.multiply(tuft_l, tuft_l), tuft_r)
headfull = union(head, earL, earR)
paint(union(earL, earR), CREAM)
paint(union(head, tuft_l, tuft_r), CREAM)
# inner ears
clip_paint(poly_mask([(64, 98), (60, 58), (68, 46), (84, 54), (102, 72)]), earL, EAR_IN)
clip_paint(poly_mask(mirror([(64, 98), (60, 58), (68, 46), (84, 54), (102, 72)])), earR, EAR_IN)
# head patches
allhead = union(head, earL, earR, tuft_l, tuft_r)
clip_paint(poly_mask([(34, 20), (128, 34), (118, 96), (76, 120), (34, 118)]), allhead, ORANGE)
clip_paint(poly_mask([(168, 30), (236, 50), (236, 126), (196, 104), (170, 72)]), allhead, BLACK)
clip_paint(poly_mask([(100, 40), (160, 40), (146, 74), (130, 90), (114, 74)]), allhead, CREAM)
# the ears keep the patch colors but the pink inside shows on top again
clip_paint(poly_mask([(70, 90), (68, 62), (74, 54), (88, 60), (98, 72)]), earL, EAR_IN)
clip_paint(poly_mask(mirror([(70, 90), (68, 62), (74, 54), (88, 60), (98, 72)])), earR, EAR_IN)

# face: sleepy happy eyes, nose, mouth, blush, whiskers
for ex in (96, 164):
    lay = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(lay).arc(((ex - 17) * SS, (110 - 8) * SS, (ex + 17) * SS, (110 + 22) * SS), 200, 340, fill=255, width=int(5 * SS))
    canvas.paste(Image.new("RGBA", (CW, CH), INK + (255,)), (0, 0), lay)
for bx in (74, 186):
    blush = ell_mask(bx, 140, 17, 10).filter(ImageFilter.GaussianBlur(2 * SS))
    canvas.paste(Image.new("RGBA", (CW, CH), PINK + (255,)), (0, 0), blush.point(lambda v: int(v * 0.7)))
nose = poly_mask([(121, 133), (139, 133), (130, 146)])
paint(nose, PINK, t=1.6)
mouth = Image.new("L", (CW, CH), 0)
md = ImageDraw.Draw(mouth)
md.arc((112 * SS, 140 * SS, 130 * SS, 158 * SS), 10, 170, fill=255, width=int(3.2 * SS))
md.arc((130 * SS, 140 * SS, 148 * SS, 158 * SS), 10, 170, fill=255, width=int(3.2 * SS))
canvas.paste(Image.new("RGBA", (CW, CH), INK + (255,)), (0, 0), mouth)
wh = Image.new("L", (CW, CH), 0)
wd = ImageDraw.Draw(wh)
for dy, dy2 in ((0, -8), (10, 6), (20, 20)):
    wd.line((52 * SS, (134 + dy) * SS, 12 * SS, (132 + dy2) * SS), fill=255, width=int(2.2 * SS))
    wd.line((208 * SS, (134 + dy) * SS, 248 * SS, (132 + dy2) * SS), fill=255, width=int(2.2 * SS))
canvas.paste(Image.new("RGBA", (CW, CH), INK + (255,)), (0, 0), wh)

# ---------------------------------------------------------------- front paws resting on the chest
for px in (92, 168):
    paw = ell_mask(px, 222, 25, 30)
    paint(paw, CREAM)
    for dx in (-8, 8):
        canvas.paste(Image.new("RGBA", (CW, CH), INK + (255,)), (0, 0), stroke([(px + dx, 232), (px + dx, 246)], 2.4, INK))
    canvas.paste(Image.new("RGBA", (CW, CH), PINK + (255,)), (0, 0), ell_mask(px, 238, 8, 6))

out = canvas.resize((W * 2, H * 2), Image.LANCZOS)
out.save(sys.argv[1])

# preview on the game's board colours: three cells tall
prev = Image.new("RGBA", (700, 1500), (255, 200, 214, 255))
d = ImageDraw.Draw(prev)
cell = 200
ox, oy = 60, 60
for gy in range(7):
    for gx in range(3):
        d.rounded_rectangle((ox + gx * cell + 130 - 100 + 2, oy + gy * cell + 4, ox + gx * cell + 130 + 100 - 4, oy + gy * cell + cell - 4), 20, fill=(234, 244, 251, 255)) if False else None
for gy in range(3):
    d.rounded_rectangle((ox + 130 - 98 + 30, oy + gy * 410 / 1.0 * 0, 0, 0), 0) if False else None
sprite = canvas.resize((W * 2, H * 2), Image.LANCZOS)
# board cells behind (one column, 3 cells: each 200 px, sprite scaled 2x so a cell is 400/… keep simple)
for gy in range(3):
    d.rounded_rectangle((90, 80 + gy * 400, 90 + 380, 80 + gy * 400 + 380), 40, fill=(234, 244, 251, 255))
prev.alpha_composite(sprite, (60, 40))
prev.convert("RGB").save(sys.argv[2])
print("ok", out.size)
