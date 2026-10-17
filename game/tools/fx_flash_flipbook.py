"""The muzzle flash flipbook (G61), after design/ref/kit/muzzle_flash.png:
a white-hot core just ahead of the muzzle, a few big ragged tongues thrown
forward and out, dozens of fine fibres between them, a warm glow round it.
Hand-built here (numpy + PIL, seeded: same file every run), not generated
in the game, so the tongues are drawn, not noise-thresholded.

    python game/tools/fx_flash_flipbook.py

Writes game/art/fx/muzzle_flash_side.png (4 frames side by side, 512x256
each: the plume seen from the side, u forward from the muzzle at U0, v
across) and game/art/fx/muzzle_flash_star.png (4 frames, 256x256 each: the
burst seen down the barrel). Light on black: FpsMuzzleFlash keys the
brightness to alpha, so black is see-through.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "art", "fx"))
U0 = 0.074                      # the muzzle, as FpsMuzzleFlash maps the plane
FRAMES = 4
SW, SH = 512, 256               # side frame
SS = 256                        # star frame
SUPER = 2                       # draw at 2x, then down-sample


def heat_to_rgb(h):
    """white-hot > pale gold > orange > deep red > nothing (FpsMuzzleFlash._heat)."""
    h = np.clip(h, 0.0, 1.6)
    out = np.zeros(h.shape + (3,), np.float32)
    # piecewise stops (heat, colour)
    stops = [(0.0, (0.55, 0.12, 0.02)), (0.22, (1.0, 0.42, 0.08)), (0.5, (1.0, 0.74, 0.36)),
             (0.8, (1.0, 0.94, 0.82)), (1.1, (1.0, 1.0, 0.98)), (1.6, (1.0, 1.0, 1.0))]
    for i in range(len(stops) - 1):
        h0, c0 = stops[i]
        h1, c1 = stops[i + 1]
        t = np.clip((h - h0) / (h1 - h0), 0.0, 1.0)[..., None]
        seg = ((h >= h0) & (h < h1))[..., None] if i < len(stops) - 2 else (h >= h0)[..., None]
        out = np.where(seg, np.array(c0) * (1 - t) + np.array(c1) * t, out)
    bright = np.clip(h * 1.6, 0.0, 1.0)[..., None]
    return out * bright


def blur(arr, r):
    im = Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), "L")
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0


def tongue(draw, ox, oy, ang, length, w0, rng, fill):
    """A tapered, ragged tongue from (ox, oy) along ang (radians), as a polygon."""
    n = 14
    left, right = [], []
    dx, dy = math.cos(ang), math.sin(ang)
    px, py = -dy, dx
    wob = rng.uniform(0.0, 6.28)
    bend = rng.uniform(-0.25, 0.25)
    for i in range(n + 1):
        t = i / n
        a2 = ang + bend * t * t
        cx = ox + math.cos(a2) * length * t
        cy = oy + math.sin(a2) * length * t
        # wide at the root, feathered to a point, with a ragged edge
        w = w0 * (1.0 - t) ** 0.8 * (0.75 + 0.5 * abs(math.sin(t * 9.0 + wob)))
        if t > 0.75:
            w *= (1.0 - t) / 0.25
        jl = rng.uniform(0.7, 1.3)
        jr = rng.uniform(0.7, 1.3)
        left.append((cx + px * w * jl, cy + py * w * jl))
        right.append((cx - px * w * jr, cy - py * w * jr))
    draw.polygon(left + right[::-1], fill=fill)


def fibre(draw, ox, oy, ang, length, rng, fill, width):
    """A thin curving filament."""
    pts = []
    bend = rng.uniform(-0.5, 0.5)
    for i in range(9):
        t = i / 8
        a2 = ang + bend * t
        pts.append((ox + math.cos(a2) * length * t, oy + math.sin(a2) * length * t))
    draw.line(pts, fill=fill, width=width)


def streaks(rng, xx, yy, ox, oy, span):
    """Fibres inside the cloud: noise fine round the origin, long along the radius."""
    ang = np.arctan2(yy - oy, xx - ox)
    rad = np.sqrt((xx - ox) ** 2 + (yy - oy) ** 2) / span
    na, nr = 720, 40
    tab = rng.uniform(0.0, 1.0, (na, nr)).astype(np.float32)
    tab = np.asarray(Image.fromarray((tab * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0
    ia = ((ang + math.pi) / (2 * math.pi) * (na - 1)).astype(np.int32) % na
    ir = np.clip((rad * (nr - 1)).astype(np.int32), 0, nr - 1)
    v = tab[ia, ir]
    return 0.55 + 0.9 * (v - 0.5)


def side_frame(seed):
    rng = np.random.default_rng(seed)
    W, H = SW * SUPER, SH * SUPER
    mx = U0 * W                                 # the muzzle's x
    my = H * 0.5
    layer_big = Image.new("L", (W, H), 0)
    layer_fine = Image.new("L", (W, H), 0)
    db = ImageDraw.Draw(layer_big)
    df = ImageDraw.Draw(layer_fine)
    ox, oy = mx + W * 0.10, my               # the tongues' root, just ahead of the muzzle
    # 4-6 big tongues, forward-biased, uneven
    nt = int(rng.integers(4, 7))
    angs = sorted(rng.uniform(-1.15, 1.15, nt))
    for k, a in enumerate(angs):
        a += rng.uniform(-0.12, 0.12)
        fwd = math.cos(a)
        length = W * rng.uniform(0.30, 0.62) * (0.45 + 0.55 * fwd)
        w0 = H * rng.uniform(0.07, 0.13)
        tongue(db, ox, oy, a, length, w0, rng, int(rng.integers(120, 190)))
    # one long central jet
    tongue(db, ox - W * 0.03, oy, rng.uniform(-0.1, 0.1), W * rng.uniform(0.55, 0.72), H * 0.09, rng, 200)
    # fibres: many soft filaments between and beyond the tongues
    for _ in range(int(rng.integers(90, 130))):
        a = rng.uniform(-1.5, 1.5)
        fwd = math.cos(a)
        length = W * rng.uniform(0.18, 0.55) * (0.4 + 0.6 * fwd)
        fibre(df, ox + rng.uniform(-W * 0.02, W * 0.04), oy + rng.uniform(-H * 0.06, H * 0.06), a, length, rng,
              int(rng.integers(60, 150)), int(rng.integers(2, 6)))
    big = np.asarray(layer_big, np.float32) / 255.0
    fine = np.asarray(layer_fine, np.float32) / 255.0
    big = blur(big, 4.0)
    fine = blur(fine, 2.2)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    big *= streaks(rng, xx, yy, ox, oy, W * 0.7)
    # the core: a hot ellipse ahead of the muzzle, plus the neck from the muzzle
    cx, cy = mx + W * 0.13, my
    core = np.exp(-(((xx - cx) / (W * 0.085)) ** 2 + ((yy - cy) / (H * 0.17)) ** 2))
    neck = np.exp(-((yy - my) / (H * 0.04 + (xx - mx) * 0.08)) ** 2) * ((xx > mx - W * 0.01) & (xx < cx)).astype(np.float32)
    heat = big * 1.0 + fine * 0.5 + core * 1.3 + neck * 0.8
    glow = blur(np.clip(heat, 0, 1), 28.0) * 0.4 + blur(np.clip(heat, 0, 1), 9.0) * 0.25
    heat = heat + glow
    # nothing behind the muzzle; a soft fade to the frame's edges
    behind = np.clip(1.0 + (xx - mx) / (W * 0.03), 0.0, 1.0)
    heat *= behind
    edge = np.clip(np.minimum(np.minimum(xx, W - xx) / (W * 0.04), np.minimum(yy, H - yy) / (H * 0.08)), 0.0, 1.0)
    heat *= edge
    rgb = heat_to_rgb(heat)
    im = Image.fromarray(np.clip(rgb * 255.0, 0, 255).astype(np.uint8), "RGB")
    return im.resize((SW, SH), Image.LANCZOS)


def star_frame(seed):
    rng = np.random.default_rng(seed)
    N = SS * SUPER
    c = N * 0.5
    layer_big = Image.new("L", (N, N), 0)
    layer_fine = Image.new("L", (N, N), 0)
    db = ImageDraw.Draw(layer_big)
    df = ImageDraw.Draw(layer_fine)
    nt = int(rng.integers(5, 8))
    base = rng.uniform(0, 6.28)
    for k in range(nt):
        a = base + k * 6.283 / nt + rng.uniform(-0.3, 0.3)
        tongue(db, c, c, a, N * rng.uniform(0.22, 0.42), N * rng.uniform(0.05, 0.09), rng, int(rng.integers(120, 190)))
    for _ in range(int(rng.integers(90, 130))):
        a = rng.uniform(0, 6.283)
        fibre(df, c + rng.uniform(-N * 0.03, N * 0.03), c + rng.uniform(-N * 0.03, N * 0.03), a,
              N * rng.uniform(0.15, 0.42), rng, int(rng.integers(60, 150)), int(rng.integers(2, 6)))
    big = blur(np.asarray(layer_big, np.float32) / 255.0, 4.0)
    fine = blur(np.asarray(layer_fine, np.float32) / 255.0, 2.2)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    big *= streaks(rng, xx, yy, c, c, N * 0.5)
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (N * 0.5)
    core = np.exp(-(r / 0.16) ** 2)
    heat = big * 1.0 + fine * 0.5 + core * 1.3
    glow = blur(np.clip(heat, 0, 1), 26.0) * 0.4 + blur(np.clip(heat, 0, 1), 8.0) * 0.25
    heat = (heat + glow) * np.clip((1.0 - r) * 4.0, 0.0, 1.0)
    rgb = heat_to_rgb(heat)
    im = Image.fromarray(np.clip(rgb * 255.0, 0, 255).astype(np.uint8), "RGB")
    return im.resize((SS, SS), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    side = Image.new("RGB", (SW * FRAMES, SH), (0, 0, 0))
    star = Image.new("RGB", (SS * FRAMES, SS), (0, 0, 0))
    for k in range(FRAMES):
        side.paste(side_frame(1001 + k * 17), (k * SW, 0))
        star.paste(star_frame(2002 + k * 29), (k * SS, 0))
    side.save(os.path.join(OUT, "muzzle_flash_side.png"), optimize=True)
    star.save(os.path.join(OUT, "muzzle_flash_star.png"), optimize=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
