import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gg_common as gg
"""Gauntlet kit: `deagle`, a Desert Eagle Mark XIX .50 AE in polished stainless.

    blender -b --factory-startup --python game/tools/blender/gauntlet/gg_deagle.py -- --views --tag r0

Modelled by tracing the reference photo (design/ref/kit/deagle.jpg, the gun's
LEFT side, 447 px long = 0.270 m). Outlines are written in that photo's pixel
coordinates (px right = toward the rear, py down) and mapped to Blender:
    Y = (px - 350) * K   (muzzle toward -Y)
    Z = (255 - py) * K   (up +Z), origin = the fist centre on the grip
    X = across the gun, +X = the gun's left side.
Parts: `body` (frame, barrel, brake, rails, grips, trigger, hammer) and
`slide` (the rear upper section, cycles back along +Y from M_slide_pivot).
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

K = 0.270 / 447.0
OX, OY = 350.0, 255.0

STEEL = "steel_bright"
DARK = "gunmetal"
SMALL = "steel"
GRIPR = "rubber"


def P(px, py):
    return ((px - OX) * K, (OY - py) * K)


def Yp(px):
    return (px - OX) * K


def Zp(py):
    return (OY - py) * K


# ------------------------------------------------------------------ 2D helpers

def _area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                     for i in range(len(poly)))


def inset(poly, d_side, d_top=None, d_bot=None):
    """Offset a closed 2D polygon (a, b) inward. Edges whose outward normal points
    up (+b) move by d_top, down by d_bot, the rest by d_side (mitred corners)."""
    if d_top is None:
        d_top = d_side
    if d_bot is None:
        d_bot = d_side
    n = len(poly)
    ccw = _area(poly) > 0
    lines = []
    for i in range(n):
        a = Vector(poly[i])
        b = Vector(poly[(i + 1) % n])
        t = (b - a)
        if t.length < 1e-9:
            t = Vector((1e-6, 0))
        t.normalize()
        out = Vector((t.y, -t.x)) if ccw else Vector((-t.y, t.x))
        d = d_top if out.y > 0.6 else (d_bot if out.y < -0.6 else d_side)
        lines.append((a - out * d, t))
    res = []
    for i in range(n):
        p0, t0 = lines[i - 1]
        p1, t1 = lines[i]
        den = t0.x * t1.y - t0.y * t1.x
        if abs(den) < 1e-6:
            q = p1
        else:
            w = p1 - p0
            s = (w.x * t1.y - w.y * t1.x) / den
            q = p0 + t0 * s
        orig = Vector(poly[i])
        lim = 2.5 * max(d_side, d_top, d_bot)
        if (q - orig).length > lim:
            q = orig + (q - orig).normalized() * lim
        res.append((q.x, q.y))
    return res


# ------------------------------------------------------------------ mesh builders

PIECES = {"body": [], "slide": []}


def loft(layers, role, part="body", axis="x"):
    """Skin rings of equal vertex count. axis 'x': layer = (x, [(Y, Z)...]);
    axis 'y': layer = (y, [(X, Z)...]). Caps both ends: a closed shell."""
    bm = bmesh.new()
    rings = []
    for t, poly in layers:
        if axis == "x":
            rings.append([bm.verts.new((t, a, b)) for a, b in poly])
        else:
            rings.append([bm.verts.new((a, t, b)) for a, b in poly])
    n = len(rings[0])
    for ra, rb in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = gg.mesh_object("piece", bm, [role])
    PIECES[part].append(ob)
    return ob


def prism(px_poly, x0, x1, role, part="body", c=0.0007, c_top=None, round_=False):
    """Side-view outline (photo px) extruded across X from x0 to x1, edges chamfered.
    c_top: a bigger chamfer on upward-facing edges (sloped tops)."""
    poly = [P(*p) for p in px_poly]
    if c <= 0:
        return loft([(x0, poly), (x1, poly)], role, part)
    ct = c if c_top is None else c_top
    if round_:
        lay = [(x0, inset(poly, c * 1.6, ct * 1.6)), (x0 + c * 0.45, inset(poly, c * 0.55, ct * 0.55)),
               (x0 + c * 1.6, poly), (x1 - c * 1.6, poly),
               (x1 - c * 0.45, inset(poly, c * 0.55, ct * 0.55)), (x1, inset(poly, c * 1.6, ct * 1.6))]
    else:
        cx = min(c, ct)
        lay = [(x0, inset(poly, c, ct)), (x0 + cx, poly), (x1 - cx, poly), (x1, inset(poly, c, ct))]
    return loft(lay, role, part)


def sym(px_poly, half, role, part="body", **kw):
    return prism(px_poly, -half, half, role, part, **kw)


def both_sides(px_poly, x_in, x_out, role, part="body", **kw):
    prism(px_poly, x_in, x_out, role, part, **kw)
    prism(px_poly, -x_out, -x_in, role, part, **kw)


def sweep_y(sec, y0, y1, role, part="body", c=0.0006):
    """A cross-section (X, Z) swept along Y from y0 to y1 (y0 < y1), ends chamfered."""
    if c > 0:
        lay = [(y0, inset(sec, c)), (y0 + c, sec), (y1 - c, sec), (y1, inset(sec, c))]
    else:
        lay = [(y0, sec), (y1, sec)]
    return loft(lay, role, part, axis="y")


def disk(px, py, r_px, x_in, x_out, role, part="body", segs=12):
    """A round boss on the side of the gun (axis X) at photo point (px, py)."""
    y, z = P(px, py)
    r = r_px * K
    poly = [(y + r * math.cos(2 * math.pi * i / segs), z + r * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
    c = min(r * 0.25, 0.0004)
    return loft([(x_in, poly), (x_out - c, poly), (x_out, inset(poly, c))], role, part)


def cyl_y(y0, y1, z, r, role, part="body", segs=16):
    poly = [(r * math.cos(2 * math.pi * i / segs), z + r * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
    return loft([(y0, poly), (y1, poly)], role, part, axis="y")


# ------------------------------------------------------------------ the gun

W_BAR = 0.0135     # barrel half width
W_SLIDE = 0.0150
W_FRAME = 0.0128
W_GRIPF = 0.0112
W_GRIP = 0.0160    # rubber wrap: 32 mm overall


def build_barrel():
    zb, zf1, zf2, zt = Zp(178), Zp(150), Zp(141), Zp(120)
    w, g, tw, cb = W_BAR, 0.0028, 0.0076, 0.0016
    half = [(w - cb, zb), (w, zb + cb), (w, zf1), (w - g, zf1), (w - g, zf2), (w, zf2), (tw, zt)]
    sec = half + [(-x, z) for x, z in reversed(half)]
    sec = [p for p in sec]
    # the rings must be counter-clockwise in (X, Z) for consistent winding; loft recalcs anyway
    sweep_y(sec, Yp(47), Yp(209), STEEL)
    for sx in (1, -1):
        a, b = sorted((sx * (W_BAR - 0.0029), sx * (W_BAR - 0.0022)))
        prism([(50, 141.6), (209, 141.6), (209, 149.4), (50, 149.4)], a, b, SMALL, c=0.0002)
    # rail base on the triangular top + Picatinny teeth
    sweep_y([(-0.0076, Zp(120.5)), (0.0076, Zp(120.5)), (0.0076, Zp(116.5)), (-0.0076, Zp(116.5))], Yp(47), Yp(205), DARK, c=0.0003)
    tooth = [(-0.0078, Zp(117)), (0.0078, Zp(117)), (0.0105, Zp(115.2)), (0.0105, Zp(114)), (0.0090, Zp(112.6)),
             (-0.0090, Zp(112.6)), (-0.0105, Zp(114)), (-0.0105, Zp(115.2))]
    x = 52.0
    while x + 10 <= 206:
        sweep_y(tooth, Yp(x), Yp(x + 10), STEEL, c=0.0003)
        x += 17.4
    # under-barrel accessory rail (dark)
    sweep_y([(-0.0095, Zp(185)), (0.0095, Zp(185)), (0.0095, Zp(177)), (-0.0095, Zp(177))], Yp(31), Yp(203), DARK, c=0.0004)
    tooth_u = [(-0.0090, Zp(192)), (0.0090, Zp(192)), (0.0105, Zp(190.6)), (0.0105, Zp(189.2)), (0.0080, Zp(184.5)),
               (-0.0080, Zp(184.5)), (-0.0105, Zp(189.2)), (-0.0105, Zp(190.6))]
    x = 33.0
    while x + 10 <= 204:
        sweep_y(tooth_u, Yp(x), Yp(x + 10), DARK, c=0.0003)
        x += 17.2


def build_brake():
    # lower solid block of the brake section
    sym([(0, 133), (48, 133), (48, 178), (1.5, 178), (0, 176)], W_BAR, STEEL, c=0.0012)
    # top skin over the ports, rounded off on top
    sym([(0.5, 116), (0.5, 112), (2, 110.5), (48, 110.5), (48, 116)], W_BAR - 0.0005, STEEL, c=0.0008, c_top=0.0014)
    # recessed dark core seen through the ports
    sym([(1, 115), (47, 115), (47, 134), (1, 134)], W_BAR - 0.0032, DARK, c=0)
    # fins between the four port slots (slots ~5 px wide, a slight forward lean)
    fins = [(0, 3.5), (8.5, 14.0), (19.0, 24.5), (29.5, 35.0), (40.0, 48.0)]
    for a, b in fins:
        lean = 1.6
        sym([(a, 134), (b, 134), (b - lean if b < 48 else b, 115), (a - lean if a > 0 else a, 115)], W_BAR, STEEL, c=0.0005)
    # front sight blade on the brake
    sym([(8, 111.5), (12, 102.5), (17, 98.5), (26, 98.5), (29, 111.5)], 0.0024, DARK, c=0.0004)
    # bore: a dark disc proud of the muzzle face
    cyl_y(Yp(0) - 0.0006, Yp(0) + 0.002, Zp(150), 0.0066, "polymer_black")
    # "50AE" stamping panel (left side): a thin flat plate, proud so it catches light
    prism([(13, 158), (46, 158), (46, 172), (13, 172)], W_BAR - 0.0002, W_BAR + 0.0005, STEEL, c=0.0003)


def build_slide():
    s = "slide"
    out = [(205, 173), (205, 113), (209, 108), (330, 106.5), (392, 112.5), (401, 118), (402, 168), (399, 173)]
    sym(out, W_SLIDE, STEEL, s, c=0.0012, c_top=0.0048)
    # rear serrations: raised slanted ridges on both sides
    for i in range(12):
        x0 = 272 + i * 9.2
        ridge = [(x0, 129), (x0 + 3.8, 129), (x0 + 12.5, 171), (x0 + 8.7, 171)]
        both_sides(ridge, W_SLIDE - 0.0004, W_SLIDE + 0.0010, STEEL, s, c=0.0004)
    # ambidextrous safety lever (slide-mounted) + its pivot boss
    lever = [(330, 130), (338, 124), (352, 121), (366, 120), (375, 124), (378, 133), (374, 142), (363, 146),
             (348, 143), (336, 138)]
    both_sides(lever, W_SLIDE - 0.0005, W_SLIDE + 0.0030, DARK, s, c=0.0006, round_=True)
    for sx in (1, -1):
        a, b = sorted((sx * (W_SLIDE + 0.0028), sx * (W_SLIDE + 0.0042)))
        disk(366, 132, 5.5, a, b, SMALL, s)
    # large fixed rear sight: base + two ears with a square notch
    sym([(342, 112), (346, 104.5), (371, 104.5), (373, 112)], 0.0090, DARK, s, c=0.0005)
    for sx in (1, -1):
        a, b = sorted((sx * 0.0026, sx * 0.0090))
        prism([(350, 105), (356, 99.0), (367, 98.5), (371.5, 99.0), (372, 105)], a, b, DARK, s, c=0.0005)


def build_frame():
    # upper frame: rails under the slide, dust cover, beavertail
    upper = [(199, 173), (404, 173), (414, 172.5), (434, 175), (446, 179), (448, 184), (445, 190.5), (432, 192.5), (415, 196),
             (401, 202), (392, 210), (386, 204), (290, 198), (228, 196.5), (206, 197.5), (200, 193)]
    sym(upper, W_FRAME, STEEL, c=0.0008)
    # grip frame (front strap and back strap show steel around the rubber)
    gripf = [(281, 192), (386, 195), (392, 205), (386, 212), (393, 250), (402, 270), (409, 290), (413, 310),
             (415, 326), (412, 336), (304, 337), (300, 329), (291, 252), (282, 234), (278, 210)]
    sym(gripf, W_GRIPF, STEEL, c=0.0012)
    # trigger guard (measured off the photo): the front hooks forward into the dust cover,
    # a squared vertical front bar, a flat bottom, the rear sweeping down into the front strap
    guard = [(206, 189), (213, 198), (215.5, 205), (215.5, 237), (218.5, 240.5), (283, 240.5), (290, 247), (296, 258),
             (298, 240), (286, 236), (282, 234), (226, 234), (223, 231), (223, 205), (221, 197), (219, 190)]
    sym(guard, 0.0058, STEEL, c=0.0010)
    # trigger
    sym([(271, 192), (282, 194), (283, 207), (281, 218), (277, 227), (270, 234), (263, 234.5), (262, 231), (266, 225),
         (269, 215), (270, 204)], 0.0050, DARK, c=0.0008)
    # exposed hammer, spur to the rear
    sym([(395, 146), (396, 128), (401, 119), (409, 114), (417, 113), (424, 117), (422, 124), (416, 121), (410, 122),
         (407, 127), (412, 131), (409, 146)],
        0.0052, DARK, c=0.0006)
    # takedown/barrel latch discs, slide stop, mag release (left), grip screws
    for py in (178.5, 193):
        disk(218, py, 5.5, -W_FRAME - 0.0006, W_FRAME + 0.0006, DARK)
    prism([(296, 181), (328, 179), (346, 177), (349, 183), (347, 195), (332, 196), (326, 189), (298, 188)],
          W_FRAME - 0.001, W_FRAME + 0.0016, DARK, c=0.0005)
    disk(300, 184.5, 3.5, W_FRAME, W_FRAME + 0.0024, SMALL)
    # dark split line where the slide meets the frame
    sym([(206, 172.2), (404, 172.2), (404, 175), (206, 175)], W_FRAME + 0.0005, DARK, c=0.0002)
    disk(290, 227, 5.0, W_GRIPF - 0.001, W_GRIPF + 0.0018, DARK)
    # magazine floorplate
    sym([(304, 336), (395, 336), (393, 349), (307, 349)], 0.0118, DARK, c=0.0010)


def build_grips():
    # wrap-around rubber grips, rounded, with a finger-groove hint on the front edge
    front = []
    y0, y1 = 182.0, 330.0
    for i in range(13):
        t = i / 12.0
        py = y0 + (y1 - y0) * t
        px = 300 - 4.0 * (py - 182) / 68 if py <= 250 else 296 + 0.157 * (py - 250)   # rake as the photo
        if 0.2 < t < 0.95:
            px -= 2.4 * abs(math.sin((t - 0.2) / 0.75 * 3 * math.pi))   # three soft finger bulges
        front.append((px, py))
    back = [(398, 334), (406, 329), (409.5, 314), (406, 292), (398, 268), (389, 245), (380, 215), (375, 194), (369, 179)]
    poly = [(300, 181)] + front[1:] + [(314, 334)] + back
    poly = list(reversed(poly))
    sym(poly, W_GRIP, GRIPR, c=0.0030, round_=True)
    # crown: a raised, rounded centre field on each panel so the wrap reads bulged
    # (an explicit, nearly convex outline: insetting the scalloped wrap outline folded it over itself)
    crown = [(310, 188), (360, 188), (367, 195), (373, 215), (382, 245), (391, 268), (398, 292), (401, 312),
             (399, 321), (392, 326), (320, 326), (313, 322), (303, 250), (306, 192)]
    both_sides(crown, W_GRIP - 0.002, W_GRIP + 0.0013, GRIPR, c=0.0012, round_=True)
    for sx in (1, -1):
        a, b = sorted((sx * (W_GRIP - 0.0008), sx * (W_GRIP + 0.0006)))
        disk(393, 292, 3.2, a, b, SMALL)


def review_world():
    """Review-only lighting. Polished steel shows only what it reflects, and the
    stock world is one flat grey, so the stainless rendered as dull paint. The
    camera still sees the stock flat grey (render_views sets that colour); only
    reflections and lighting see a studio sphere: dark floor, a bright horizon
    softbox band, a dim mid-sky and a bright ceiling. Not exported."""
    sc = bpy.context.scene
    wd = bpy.data.worlds.new("World")
    sc.world = wd
    wd.use_nodes = True
    nt = wd.node_tree
    bg = nt.nodes.get("Background")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    el = ramp.color_ramp.elements
    el[0].position, el[0].color = 0.0, (0.5, 0.5, 0.51, 1)
    try:
        wd.probe_resolution = "2048"
    except (AttributeError, TypeError):
        pass
    el[1].position, el[1].color = 1.0, (2.2, 2.2, 2.25, 1)
    for pos, v in ((0.36, 0.5), (0.43, 0.015), (0.49, 0.015), (0.53, 3.0), (0.65, 2.6), (0.72, 0.3), (0.84, 0.3), (0.93, 2.6)):
        e = el.new(pos)
        e.color = (v, v, v * 1.02, 1)
    # Generated runs -1..1 in Z for a world; remap to 0..1
    mp = nt.nodes.new("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = -1.0
    nt.links.remove(sep.outputs["Z"].links[0])
    nt.links.new(sep.outputs["Z"], mp.inputs["Value"])
    nt.links.new(mp.outputs["Result"], ramp.inputs["Fac"])
    mix.inputs["B"].default_value = (0.72, 0.74, 0.78, 1.0)
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["A"])
    nt.links.new(mix.outputs["Result"], bg.inputs["Color"])


def build():
    gg.reset()
    build_barrel()
    build_brake()
    build_slide()
    build_frame()
    build_grips()
    gg.join("body", PIECES["body"])
    gg.join("slide", PIECES["slide"])
    gg.marker("grip", (0, 0, 0))
    gg.marker("muzzle", (0, Yp(0) - 0.0008, Zp(150)))
    gg.marker("eye", (0, Yp(425), Zp(98.5)))
    gg.marker("support", (0, Yp(318), Zp(306)))
    gg.marker("slide_pivot", (0, Yp(402), Zp(140)))


build()
review_world()
meta = {"hands": 1, "socket": "hand_r", "class": "pistol", "notes": "Desert Eagle .50 AE style"}
gg.finish("deagle", "item", meta)
if gg.arg("--views"):
    # review-only: a first-person look down the sights, from just behind and above M_eye
    eye = Vector((0.0, Yp(425), Zp(98.5)))
    gg.render_views("deagle", "item", str(gg.arg("--tag", "r0")),
                    views={"fp": (eye + Vector((0.0, 0.05, 0.0)), Vector((0.0, Yp(18), Zp(98.5))))})
