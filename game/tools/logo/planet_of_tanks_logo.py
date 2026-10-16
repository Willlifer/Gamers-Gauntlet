"""Planet of Tanks logo generator.

Renders the "PLANET OF TANKS" wordmark (Bahnschrift Bold Condensed, brushed
silver bevel, navy outline, soft shadow) under an original emblem: a metal
planet wearing a tank-tread ring.

Usage (from the game/ folder):  python tools/logo/planet_of_tanks_logo.py
Outputs:
  art/ui/planet_of_tanks_logo.png         (~1200 px wide, transparent)
  art/ui/planet_of_tanks_logo_small.png   (~480 px wide, transparent)
  ../design/shots/mmo/logo_preview.png    (both sizes on a dark smoky bg)
Only the rendered PNGs ship; the font is read from the system at build time.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_BIG = os.path.join(GAME, "art", "ui", "planet_of_tanks_logo.png")
OUT_SMALL = os.path.join(GAME, "art", "ui", "planet_of_tanks_logo_small.png")
OUT_PREVIEW = os.path.normpath(os.path.join(GAME, "..", "design", "shots", "mmo", "logo_preview.png"))

S = 4                      # supersample factor
W, H = 1400 * S, 700 * S   # working canvas (cropped later)
OUTLINE = (10, 14, 24)     # dark navy-black
FINAL_W = 1200
SMALL_W = 480

rng = np.random.default_rng(7)


# ----------------------------------------------------------------- helpers
def load_font(px, style="Bold Condensed"):
    try:
        f = ImageFont.truetype(r"C:\Windows\Fonts\bahnschrift.ttf", px)
        f.set_variation_by_name(style)
        return f
    except Exception:
        return ImageFont.truetype(r"C:\Windows\Fonts\impact.ttf", px)


def arr(m):
    return np.asarray(m, dtype=np.float32) / 255.0


def to_img(a):
    return Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8), "L")


def dilate(a, r):
    """Anti-aliased dilation of a float mask by r (big-canvas) pixels."""
    inside = a > 0.5
    d = ndimage.distance_transform_edt(~inside)
    return np.maximum(a, np.clip(r - d + 0.5, 0, 1))


def blur(a, r):
    return arr(to_img(a).filter(ImageFilter.GaussianBlur(r)))


def bbox_rows(a):
    ys = np.where(a.max(axis=1) > 0.05)[0]
    return ys.min(), ys.max()


def brushed(h, w, strength):
    """Horizontal brushed-metal streaks in [-strength, strength]."""
    small = rng.random((h, max(4, w // 90))).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8), "L").resize((w, h), Image.BILINEAR)
    n = arr(img) - 0.5
    n = n + (blur(rng.random((h, w)).astype(np.float32), 0.6) - 0.5) * 0.6
    return n * 2 * strength


def chrome_ramp(t):
    """Silver ramp: bright top -> darker mid band -> bright again."""
    pts = [(0.00, 1.00), (0.18, 0.93), (0.44, 0.72), (0.50, 0.42),
           (0.56, 0.54), (0.80, 0.80), (1.00, 0.93)]
    xs, ys = zip(*pts)
    return np.interp(t, xs, ys).astype(np.float32)


def bevel(a, r):
    """Edge light: + on upper/left edges, - on lower/right edges."""
    b = blur(a, r)
    gy = np.zeros_like(b)
    gx = np.zeros_like(b)
    gy[1:-1] = b[2:] - b[:-2]
    gx[:, 1:-1] = b[:, 2:] - b[:, :-2]
    k = 0.5 * r
    return np.clip((gy * 0.85 + gx * 0.35) * k, -1, 1)


def top_highlight(a, px):
    """Thin bright line along the top edge of each shape."""
    shifted = np.zeros_like(a)
    shifted[px:] = a[:-px]
    return np.clip(a - shifted, 0, 1)


def tint(v, cool=0.0):
    rgb = np.stack([v * (1.0 - 0.05 * cool), v * (1.0 - 0.01 * cool), v * (1.0 + 0.04 * cool)], -1)
    return np.clip(rgb, 0, 1)


def compose(dst, rgb, alpha):
    """Alpha-over a float RGB layer onto dst (H,W,4 float premult-free)."""
    a = alpha[..., None]
    out_a = a + dst[..., 3:4] * (1 - a)
    safe = np.where(out_a > 1e-6, out_a, 1)
    dst[..., :3] = (rgb * a + dst[..., :3] * dst[..., 3:4] * (1 - a)) / safe
    dst[..., 3:4] = out_a


# ----------------------------------------------------------------- wordmark
def text_mask(text, font, track):
    """Draw text char by char with tracking; return (mask, width)."""
    widths = [font.getbbox(c)[2] - font.getbbox(c)[0] for c in text]
    total = sum(widths) + track * (len(text) - 1)
    im = Image.new("L", (int(total + 40 * S), int(font.size * 1.4)), 0)
    d = ImageDraw.Draw(im)
    x = 20 * S
    for c, w in zip(text, widths):
        d.text((x - font.getbbox(c)[0], 0), c, font=font, fill=255)
        x += w + track
    m = arr(im)
    cols = np.where(m.max(axis=0) > 0.05)[0]
    # crop rows on the font's cap box (shared baseline), keeping overshoot
    _, top, _, bot = font.getbbox("H")
    pad = max(1, int(font.size * 0.012))
    return m[top - pad:bot + pad, cols.min():cols.max() + 1]


def build_wordmark():
    big = load_font(250 * S)
    small = load_font(116 * S, "Bold SemiCondensed")
    planet = text_mask("PLANET", big, 6 * S)
    tanks = text_mask("TANKS", big, 6 * S)
    o = text_mask("O", small, 0)
    f = text_mask("F", small, 0)
    cap_h = planet.shape[0]
    gap = 20 * S
    of_w = max(o.shape[1], f.shape[1])
    of_gap = int(cap_h - o.shape[0] - f.shape[0])
    w = planet.shape[1] + gap + of_w + gap + tanks.shape[1]
    m = np.zeros((cap_h, w), np.float32)
    x = 0
    m[:, x:x + planet.shape[1]] = planet
    x += planet.shape[1] + gap
    ox = x + (of_w - o.shape[1]) // 2
    m[0:o.shape[0], ox:ox + o.shape[1]] = np.maximum(m[0:o.shape[0], ox:ox + o.shape[1]], o)
    fx = x + (of_w - f.shape[1]) // 2
    m[cap_h - f.shape[0]:, fx:fx + f.shape[1]] = np.maximum(m[cap_h - f.shape[0]:, fx:fx + f.shape[1]], f)
    x += of_w + gap
    m[:, x:x + tanks.shape[1]] = tanks
    return m, of_gap


def metal_text(m):
    h, w = m.shape
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    v = np.broadcast_to(chrome_ramp(t), (h, w)).copy()
    v += brushed(h, w, 0.035)
    v += bevel(m, 3.0 * S) * 0.45
    v = np.where(top_highlight(m, int(2.2 * S)) > 0.3, 1.0, v)
    return tint(v, cool=1.0)


# ----------------------------------------------------------------- emblem
def ellipse_mask(shape, cx, cy, a, b):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]].astype(np.float32)
    r = np.sqrt(((xx - cx) / a) ** 2 + ((yy - cy) / b) ** 2)
    # ~1px AA edge measured along the minor axis
    return np.clip((1 - r) * b + 0.5, 0, 1), xx, yy


def build_emblem():
    """Returns layers (back_ring, planet, front_ring) as (mask, rgb) plus size."""
    E = 560 * S
    cx = cy = E / 2
    R = 120 * S                      # planet radius
    A, B = 262 * S, 70 * S           # ring outer semi-axes
    band = 30 * S                    # tread band thickness
    tilt = -16.0                     # degrees

    # -- planet ------------------------------------------------------------
    pm, xx, yy = ellipse_mask((E, E), cx, cy, R, R)
    nx = (xx - cx) / R
    ny = (yy - cy) / R
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    L = np.array([-0.45, -0.62, 0.64]); L /= np.linalg.norm(L)
    diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    hv = np.array([L[0], L[1], L[2] + 1]); hv /= np.linalg.norm(hv)
    spec = np.clip(nx * hv[0] + ny * hv[1] + nz * hv[2], 0, 1) ** 40
    # chrome horizon: reflected ramp by normal's vertical component
    ramp = chrome_ramp(np.clip((ny * 0.9 + 1) / 2, 0, 1))
    v = 0.10 + 0.66 * diff * ramp + 0.22 * ramp + 0.45 * spec
    # latitude grooves running parallel to the ring
    ang = math.radians(tilt)
    ry = -(xx - cx) * math.sin(ang) + (yy - cy) * math.cos(ang)
    for off, wdt in ((-0.52, 3.2), (0.10, 3.6), (0.62, 3.0)):
        gy = off * R
        curve = gy + 0.10 * R * (1 - nx * nx)  # slight bow, sells the sphere
        d = np.abs(ry - curve)
        v -= np.clip(1 - d / (wdt * S), 0, 1) * 0.28 * pm
        v += np.clip(1 - np.abs(ry - curve - 3.5 * S) / (2 * S), 0, 1) * 0.12 * pm
    v += brushed(E, E, 0.02)
    v += bevel(pm, 4 * S) * 0.35
    # rim light opposite the key light
    rim = np.clip((nx * 0.6 + ny * 0.8), 0, 1) ** 3 * (1 - nz) ** 0.5
    v += rim * 0.25
    planet_rgb = tint(v, cool=2.0)

    # -- tread ring (built horizontal, then rotated) -----------------------
    outer, xx0, yy0 = ellipse_mask((E, E), cx, cy, A, B)
    inner, _, _ = ellipse_mask((E, E), cx, cy, A - band, B - band * 0.42)
    ring = np.clip(outer - inner, 0, 1)
    # tread lugs: blocks sticking out of the outer rim, plus grooves across band
    lug_img = Image.new("L", (E, E), 0)
    groove_img = Image.new("L", (E, E), 0)
    dl = ImageDraw.Draw(lug_img)
    dg = ImageDraw.Draw(groove_img)
    n_links = 30
    for i in range(n_links):
        t = (i + 0.5) / n_links * 2 * math.pi
        ex, ey = A * math.cos(t), B * math.sin(t)
        # outward normal on ellipse
        nxe, nye = math.cos(t) / A, math.sin(t) / B
        nl = math.hypot(nxe, nye); nxe /= nl; nye /= nl
        txe, tye = -nye, nxe
        hw = 11 * S
        lo, hi = -2 * S, 11 * S
        pts = [(cx + ex + txe * s * hw + nxe * d, cy + ey + tye * s * hw + nye * d)
               for s, d in ((-1, lo), (1, lo), (0.75, hi), (-0.75, hi))]
        dl.polygon(pts, fill=255)
        # groove between links, across the band
        t2 = (i + 1.0) / n_links * 2 * math.pi
        ox_, oy_ = A * math.cos(t2), B * math.sin(t2)
        ix_, iy_ = (A - band) * math.cos(t2), (B - band * 0.42) * math.sin(t2)
        dg.line([(cx + ox_, cy + oy_), (cx + ix_, cy + iy_)], fill=255, width=int(3.2 * S))
    lugs = arr(lug_img.filter(ImageFilter.GaussianBlur(0.6 * S)))
    grooves = arr(groove_img.filter(ImageFilter.GaussianBlur(0.8 * S))) * ring
    ring_full = np.maximum(ring, lugs)

    # ring metal: ramp across the band (outer -> inner) for a rounded tread
    rr = np.sqrt(((xx0 - cx) / A) ** 2 + ((yy0 - cy) / B) ** 2)
    rr_in = np.sqrt(((xx0 - cx) / (A - band)) ** 2 + ((yy0 - cy) / (B - band * 0.42)) ** 2)
    across = np.clip((rr_in - 1) / np.maximum(rr_in - rr, 1e-3), 0, 1)  # 0 inner .. 1 outer
    vr = 0.42 + 0.5 * chrome_ramp(1 - across)
    # front half catches more light than the back half
    vr *= np.where(yy0 > cy, 1.0, 0.72)
    vr -= grooves * 0.45
    vr = np.where(lugs > 0.5, np.where(rr > 1.0, 0.86 - (rr - 1) * 1.2, vr), vr)
    vr += brushed(E, E, 0.02)
    vr += bevel(ring_full, 2.5 * S) * 0.4
    ring_rgb = tint(vr, cool=1.0)
    front = (yy0 >= cy).astype(np.float32)
    front = blur(front, 1.0 * S)

    def rot(a, mode=Image.BILINEAR):
        return arr(to_img(a).rotate(tilt, resample=mode, center=(cx, cy)))

    def rot_rgb(rgb):
        chans = [rot(rgb[..., k]) for k in range(3)]
        return np.stack(chans, -1)

    ring_full_r = rot(ring_full)
    ring_rgb_r = rot_rgb(ring_rgb)
    front_r = rot(front)
    back_mask = ring_full_r * (1 - front_r)
    front_mask = ring_full_r * front_r
    return (back_mask, ring_rgb_r), (pm, planet_rgb), (front_mask, ring_rgb_r), E


# ----------------------------------------------------------------- compose
def outlined_layer(canvas, mask, rgb, ow):
    """Paint mask's dark outline then its metal fill onto canvas."""
    ol = dilate(mask, ow)
    compose(canvas, np.broadcast_to(np.array(OUTLINE, np.float32) / 255, ol.shape + (3,)), ol)
    compose(canvas, rgb, mask)


def place(full, sub, x, y):
    h, w = sub.shape[:2]
    full[y:y + h, x:x + w] = sub


def main():
    word, _ = build_wordmark()
    back, planet, front, E = build_emblem()

    wh, ww = word.shape
    emb_y = 20 * S
    word_y = emb_y + E - 108 * S
    word_x = (W - ww) // 2
    emb_x = (W - E) // 2

    canvas = np.zeros((H, W, 4), np.float32)

    def full_mask(sub, x, y):
        m = np.zeros((H, W), np.float32)
        place(m, sub, x, y)
        return m

    def full_rgb(sub, x, y):
        m = np.zeros((H, W, 3), np.float32)
        place(m, sub, x, y)
        return m

    word_full = full_mask(word, word_x, word_y)
    word_rgb = full_rgb(metal_text(word), word_x, word_y)
    layers = [
        (full_mask(back[0], emb_x, emb_y), full_rgb(back[1], emb_x, emb_y), 4.5 * S),
        (full_mask(planet[0], emb_x, emb_y), full_rgb(planet[1], emb_x, emb_y), 4.5 * S),
        (full_mask(front[0], emb_x, emb_y), full_rgb(front[1], emb_x, emb_y), 4.5 * S),
        (word_full, word_rgb, 4.0 * S),
    ]

    # soft drop shadow + a thicker outer outline from the union silhouette
    union = np.zeros((H, W), np.float32)
    for m, _, _ in layers:
        union = np.maximum(union, m)
    outer = dilate(union, 7 * S)
    shadow = np.zeros_like(outer)
    sh = 9 * S
    shadow[sh:] = outer[:-sh]
    shadow = blur(shadow, 9 * S) * 0.9
    compose(canvas, np.zeros((H, W, 3), np.float32), shadow)
    compose(canvas, np.broadcast_to(np.array((26, 32, 46), np.float32) / 255, (H, W, 3)), outer)

    for m, rgb, ow in layers:
        outlined_layer(canvas, m, rgb, ow)

    img = Image.fromarray(np.clip(canvas * 255, 0, 255).astype(np.uint8), "RGBA")
    bb = img.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
    margin = 14 * S
    bb = (max(0, bb[0] - margin), max(0, bb[1] - margin), min(W, bb[2] + margin), min(H, bb[3] + margin))
    img = img.crop(bb)

    # premultiplied downsample to avoid dark fringes
    def downsample(im, w):
        h = round(im.height * w / im.width)
        a = np.asarray(im, np.float32) / 255
        pm_ = np.concatenate([a[..., :3] * a[..., 3:4], a[..., 3:4]], -1)
        chans = [Image.fromarray(pm_[..., k], "F").resize((w, h), Image.LANCZOS) for k in range(4)]
        out = np.stack([np.asarray(c) for c in chans], -1)
        al = np.clip(out[..., 3:4], 0, 1)
        rgb = np.where(al > 1e-4, out[..., :3] / np.maximum(al, 1e-4), 0)
        res = np.concatenate([np.clip(rgb, 0, 1), al], -1)
        return Image.fromarray((res * 255 + 0.5).astype(np.uint8), "RGBA")

    big = downsample(img, FINAL_W)
    small = downsample(img, SMALL_W)
    os.makedirs(os.path.dirname(OUT_BIG), exist_ok=True)
    big.save(OUT_BIG, optimize=True)
    small.save(OUT_SMALL, optimize=True)

    # preview on a dark smoky background
    pw, ph = 1400, big.height + small.height + 140
    yy, xx = np.mgrid[0:ph, 0:pw].astype(np.float32)
    smoke = blur(rng.random((ph // 8, pw // 8)).astype(np.float32), 2)
    smoke = arr(to_img(smoke).resize((pw, ph), Image.BICUBIC))
    vign = 1 - 0.6 * (((xx - pw / 2) / pw) ** 2 + ((yy - ph / 2) / ph) ** 2) * 2.5
    base = (0.10 + 0.12 * smoke) * vign
    bg = np.stack([base * 0.85, base * 0.95, base * 1.1], -1)
    prev = Image.fromarray(np.clip(bg * 255, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    prev.alpha_composite(big, ((pw - big.width) // 2, 40))
    prev.alpha_composite(small, ((pw - small.width) // 2, 40 + big.height + 60))
    os.makedirs(os.path.dirname(OUT_PREVIEW), exist_ok=True)
    prev.convert("RGB").save(OUT_PREVIEW)
    print("big", big.size, "small", small.size)
    print(OUT_BIG, OUT_SMALL, OUT_PREVIEW, sep="\n")


if __name__ == "__main__":
    main()
