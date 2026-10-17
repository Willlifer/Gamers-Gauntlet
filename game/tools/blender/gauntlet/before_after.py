"""Before/after sheet for a Gauntlet kit gun (the reference-gauntlet finish):

    python game/tools/blender/gauntlet/before_after.py <id> <tag_before> <tag_after> [fps_before_dir] [fps_after_dir] [frame_name]

Reads design/shots/kit/<tag>_<id>_{ref,right,front}.png (kit_ref_shots FULL=1)
and the in-hand frame design/shots/fps/<dir>/<frame_name>.png (fps_shots.gd;
default "<n>_flash_<id>"), writes design/shots/kit/final_<id>_before_after.png:
  row 1  reference | before (ref angle) | after (ref angle)
  row 2  before right | after right
  row 3  before in hand | after in hand (the gun's half of the frame)
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
KIT = os.path.join(ROOT, "design", "shots", "kit")
FPS = os.path.join(ROOT, "design", "shots", "fps")
aid, t0, t1 = sys.argv[1:4]
d0 = sys.argv[4] if len(sys.argv) > 4 else "dust_mid_g0"
d1 = sys.argv[5] if len(sys.argv) > 5 else "dust_mid"
frame = sys.argv[6] if len(sys.argv) > 6 else None


def kit(tag, view):
    p = os.path.join(KIT, "%s_%s_%s.png" % (tag, aid, view))
    return Image.open(p).convert("RGB") if os.path.exists(p) else None


def hand(d):
    if frame:
        p = os.path.join(FPS, d, frame + ".png")
    else:
        c = sorted(glob.glob(os.path.join(FPS, d, "*_flash_%s.png" % aid)))
        if not c:
            c = sorted(glob.glob(os.path.join(FPS, d, "*_%s_*.png" % aid)))
        p = c[0] if c else ""
    if not os.path.exists(p):
        return None
    im = Image.open(p).convert("RGB")
    w, h = im.size
    return im.crop((w // 2, h // 3, w, h))          # the gun's quarter


def fit(im, w, h):
    if im is None:
        return Image.new("RGB", (w, h), (40, 40, 44))
    k = min(w / im.width, h / im.height)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    out = Image.new("RGB", (w, h), (32, 34, 38))
    out.paste(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


W, H1, H2, H3 = 2100, 400, 330, 470
sheet = Image.new("RGB", (W, H1 + H2 + H3 + 60), (24, 26, 30))
d = ImageDraw.Draw(sheet)
ref_p = os.path.join(ROOT, "design", "ref", "kit", aid + ".jpg")
ref = Image.open(ref_p).convert("RGB") if os.path.exists(ref_p) else None
cells = [("reference", ref, (0, 20, 700, H1)), ("before " + t0, kit(t0, "ref"), (700, 20, 700, H1)), ("after " + t1, kit(t1, "ref"), (1400, 20, 700, H1)),
         ("before right", kit(t0, "right"), (0, H1 + 40, 1050, H2)), ("after right", kit(t1, "right"), (1050, H1 + 40, 1050, H2)),
         ("before in hand", hand(d0), (0, H1 + H2 + 60, 1050, H3)), ("after in hand", hand(d1), (1050, H1 + H2 + 60, 1050, H3))]
for name, im, (x, y, w, h) in cells:
    sheet.paste(fit(im, w, h), (x, y))
    d.text((x + 8, y - 16), name, fill=(235, 235, 235))
out = os.path.join(KIT, "final_%s_before_after.png" % aid)
sheet.save(out)
print(out)
