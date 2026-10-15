"""Review sheet: the reference beside our renders (system Python + PIL).

    python game/tools/blender/gauntlet/sheet.py <id> <tag> [ref_name]

Reads design/ref/kit/<ref_name or id>.jpg and design/shots/kit/<tag>_<id>_*.png,
writes design/shots/kit/<tag>_<id>_sheet.png (reference top-left, then each view).
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
aid, tag = sys.argv[1], sys.argv[2]
ref = sys.argv[3] if len(sys.argv) > 3 else aid
shots = os.path.join(ROOT, "design", "shots", "kit")
tiles = [("reference", os.path.join(ROOT, "design", "ref", "kit", ref + ".jpg"))]
for p in sorted(glob.glob(os.path.join(shots, "%s_%s_*.png" % (tag, aid)))):
    if p.endswith("_sheet.png"):
        continue
    tiles.append((os.path.basename(p)[len(tag) + len(aid) + 2:-4], p))
W, H = 900, 600
cols = 3
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (W * cols, H * rows), (30, 32, 36))
d = ImageDraw.Draw(sheet)
for i, (name, p) in enumerate(tiles):
    im = Image.open(p).convert("RGB")
    k = min(W / im.width, (H - 30) / im.height)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    x, y = (i % cols) * W, (i // cols) * H
    sheet.paste(im, (x + (W - im.width) // 2, y + 30 + (H - 30 - im.height) // 2))
    d.text((x + 10, y + 8), name, fill=(240, 240, 240))
out = os.path.join(shots, "%s_%s_sheet.png" % (tag, aid))
sheet.save(out)
print(out)
