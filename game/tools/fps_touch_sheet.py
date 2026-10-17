"""G67: contact sheets of the touch-control frames (tools/fps_touch_shots.gd).
python game/tools/fps_touch_sheet.py  -> design/shots/fps/touch/sheet_<size>.png, sheet_extras.png"""
import os
from PIL import Image

D = os.path.join(os.path.dirname(__file__), "..", "..", "design", "shots", "fps", "touch")


def sheet(names, out, cols=2, w=1200):
    ims = [Image.open(os.path.join(D, n + ".png")).convert("RGB") for n in names if os.path.exists(os.path.join(D, n + ".png"))]
    if not ims:
        return
    ims = [im.resize((w, int(im.height * w / im.width))) for im in ims]
    h = max(im.height for im in ims)
    rows = (len(ims) + cols - 1) // cols
    s = Image.new("RGB", (cols * w + (cols + 1) * 8, rows * h + (rows + 1) * 8), (20, 20, 24))
    for i, im in enumerate(ims):
        s.paste(im, (8 + (i % cols) * (w + 8), 8 + (i // cols) * (h + 8)))
    s.save(os.path.join(D, out))
    print(out, s.size)


for size in ("1280x720", "2400x1080"):
    sheet([f"{size}_{g}" for g in ("rooftop", "dust_mid", "campus", "extract")], f"sheet_{size}.png")
sheet(["extra_pause", "extra_radial", "extra_extract_use"], "sheet_extras.png", cols=2)
