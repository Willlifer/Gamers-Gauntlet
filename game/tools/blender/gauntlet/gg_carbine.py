import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gg_common as gg
"""carbine: a compact 9 mm PDW (Stribog / Scorpion class) for the Gauntlet kit.

    blender -b --factory-startup --python game/tools/blender/gauntlet/gg_carbine.py -- --views --tag r0

Reference: design/ref/kit/carbine.jpg is the gun's RIGHT side (muzzle to the
image's right, so it matches the "right" review view): the ejection port, the
charging-handle knob and the bolt catch are modelled on the right (-X); the
charging slot, safety, mag release and pins are on both sides.

Most shapes are side profiles traced off the reference in its own pixels and
extruded across X: px(x, y) maps a reference pixel to Blender (Y, Z), with the
grip's fist centre (258, 150) at the origin and 0.62 m over the 586 px gun.
Recesses (charging slot, M-LOK slots) are real: the receiver is a core with
side cladding built around the openings, so they read in any light.
"""

import math

import bmesh
import bpy
from mathutils import Vector

K = 0.00106                 # metres per reference pixel
GX, GY = 258.0, 150.0       # reference pixel of the grip's fist centre (origin)


def P(x, y):
    """Reference pixel -> Blender (Y, Z)."""
    return (-(x - GX) * K, -(y - GY) * K)


def V(x, y, X=0.0):
    yy, zz = P(x, y)
    return Vector((X, yy, zz))


class Part:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.roles = []

    def mi(self, role):
        if role not in self.roles:
            self.roles.append(role)
        return self.roles.index(role)

    def build(self):
        return gg.mesh_object(self.name, self.bm, self.roles)


def _clean_pts(pts):
    out = []
    for p in pts:
        if not out or (abs(out[-1][0] - p[0]) > 1e-7 or abs(out[-1][1] - p[1]) > 1e-7):
            out.append(p)
    if len(out) > 2 and abs(out[0][0] - out[-1][0]) < 1e-7 and abs(out[0][1] - out[-1][1]) < 1e-7:
        out.pop()
    return out


def prism(part, pts, a0, a1, role, bevel=0.0, axis="x", segs=1):
    """Extrude a 2D polygon (metres) between a0 and a1 along `axis`.
    axis x: pts are (Y, Z); y: (X, Z); z: (X, Y)."""
    pts = _clean_pts(pts)

    def mk(u, v, a):
        if axis == "x":
            return (a, u, v)
        if axis == "y":
            return (u, a, v)
        return (u, v, a)

    bm = part.bm
    lo = [bm.verts.new(mk(u, v, a0)) for u, v in pts]
    hi = [bm.verts.new(mk(u, v, a1)) for u, v in pts]
    n = len(pts)
    faces = [bm.faces.new(hi), bm.faces.new(list(reversed(lo)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((lo[i], lo[j], hi[j], hi[i])))
    m = part.mi(role)
    for f in faces:
        f.material_index = m
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    if bevel > 0:
        edges = list({e for f in faces[:2] for e in f.edges})
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=segs,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    return faces


def prism_px(part, pts_px, x0, x1, role, bevel=0.0, segs=1):
    return prism(part, [P(x, y) for x, y in pts_px], x0, x1, role, bevel, segs=segs)


def both(part, pts_px, inner, outer, role, bevel=0.0):
    """The same profile on both sides: X in [inner, outer] and [-outer, -inner]."""
    prism_px(part, pts_px, inner, outer, role, bevel)
    prism_px(part, pts_px, -outer, -inner, role, bevel)


def lathe(part, prof, origin, axis, role, seg=12, smooth=True, closed=False):
    """Revolve (s, r) pairs about `axis` through `origin`; r == 0 makes an apex.
    Open profiles are capped at ends with r > 0; closed ones join last to first."""
    bm = part.bm
    origin = Vector(origin)
    axis = Vector(axis).normalized()
    ref = Vector((1, 0, 0)) if abs(axis.x) < 0.9 else Vector((0, 0, 1))
    u = axis.cross(ref).normalized()
    v = axis.cross(u).normalized()
    rings = []
    for s, r in prof:
        c = origin + axis * s
        if r <= 1e-9:
            rings.append([bm.verts.new(c)])
        else:
            rings.append([bm.verts.new(c + (u * math.cos(2 * math.pi * k / seg) + v * math.sin(2 * math.pi * k / seg)) * r)
                          for k in range(seg)])
    faces = []
    pairs = list(zip(rings[:-1], rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(seg):
            k2 = (k + 1) % seg
            if len(a) == 1:
                faces.append(bm.faces.new((a[0], b[k], b[k2])))
            elif len(b) == 1:
                faces.append(bm.faces.new((a[k], a[k2], b[0])))
            else:
                faces.append(bm.faces.new((a[k], a[k2], b[k2], b[k])))
    for f in faces:
        f.smooth = smooth
    if not closed:
        if len(rings[0]) > 1:
            faces.append(bm.faces.new(list(reversed(rings[0]))))
        if len(rings[-1]) > 1:
            faces.append(bm.faces.new(rings[-1]))
    m = part.mi(role)
    for f in faces:
        f.material_index = m
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def loft(part, rings, role, smooth=True, caps=True):
    bm = part.bm
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    faces = []
    for a, b in zip(vr[:-1], vr[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            f.smooth = smooth
            faces.append(f)
    if caps:
        faces.append(bm.faces.new(list(reversed(vr[0]))))
        faces.append(bm.faces.new(vr[-1]))
    m = part.mi(role)
    for f in faces:
        f.material_index = m
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def disc_x(part, x, y, r_px, X0, X1, role, seg=10):
    """A round pin/button head on a side face: axis X, centre at reference pixel (x, y)."""
    yy, zz = P(x, y)
    lathe(part, [(0.0, r_px * K), (X1 - X0, r_px * K)], (X0, yy, zz), (1, 0, 0), role, seg, smooth=True)


def stadium(x0, x1, y0, y1, n=4):
    """A horizontal stadium (rounded slot) outline in reference pixels."""
    r = (y1 - y0) / 2.0
    yc = (y0 + y1) / 2.0
    pts = []
    for k in range(n + 1):                      # right end, top -> bottom
        t = math.pi / 2 - math.pi * k / n
        pts.append((x1 - r + r * math.cos(t), yc - r * math.sin(t)))
    for k in range(n + 1):                      # left end, bottom -> top
        t = -math.pi / 2 - math.pi * k / n
        pts.append((x0 + r + r * math.cos(t), yc - r * math.sin(t)))
    return pts


def band_pieces(xa, xb, y0, y1, slots, n=4):
    """Profiles (reference px) covering the band [xa, xb] x [y0, y1] except
    stadium-shaped slots [(sx0, sx1)...] spanning the band's full height."""
    r = (y1 - y0) / 2.0
    yc = (y0 + y1) / 2.0
    out = []
    edges = [(None, xa)] + [(s0, s1) for s0, s1 in sorted(slots)] + [(xb, None)]
    for (pa0, pa1), (pb0, pb1) in zip(edges[:-1], edges[1:]):
        pts = []
        if pa0 is None:                         # straight left edge
            pts += [(pa1, y0), (pa1, y1)]
        else:                                   # concave: the right end of slot a, top -> bottom
            cx = pa1 - r
            for k in range(n + 1):
                t = math.pi / 2 - math.pi * k / n
                pts.append((cx + r * math.cos(t), yc - r * math.sin(t)))
        if pb1 is None:                         # straight right edge, bottom -> top
            pts += [(pb0, y1), (pb0, y0)]
        else:                                   # concave: the left end of slot b, bottom -> top
            cx = pb0 + r
            for k in range(n + 1):
                t = -math.pi / 2 + math.pi * k / n
                pts.append((cx - r * math.cos(t), yc - r * math.sin(t)))
        out.append(pts)
    return out


def rrect(w, h, r, nc=3):
    """Rounded rectangle (centre origin) as (a, b) points, a across w, b across h."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(nc + 1):
            t = math.radians(a0 + 90.0 * k / nc)
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return pts


# The upper is alloy, a shade lighter than the polymer lower (the photo's two tones).
ALLOY = "alloy_black:#3b3e43"
# The magazine: smoke-amber, as in the photo (the role recoloured, per the contract).
CLEAR = "polymer_clear:#6e4c2c"

# ------------------------------------------------------------------ body

def build_body():
    b = Part("body")
    AL, PO, ST = ALLOY, "polymer_black", "steel"
    DS = "steel:#3c3f43"                        # dark steel: the flash hider and controls, as in the photo

    # Upper receiver: a core with side cladding (the recesses are the gaps).
    upper = [(212, 40), (218, 33), (512, 33), (531, 57), (531, 80), (523, 90.5), (212, 90.5)]
    prism_px(b, upper, -0.021, 0.021, AL, bevel=0.0024, segs=2)
    CI = 0.0205                                 # cladding starts inside the core (never coincident)
    TOP_O, BAND_O = 0.0245, 0.0255
    chamfer = lambda y: 512 + (y - 33) * (19.0 / 24.0)
    # top section (y 33..57.5): the charging-handle slot runs x 385..508, y 42..55, both sides
    for side in (1, -1):
        def clad(pts, outer, bev=0.0006):
            prism_px(b, pts, side * CI, side * outer, AL, bev)
        clad([(212, 42.3), (212, 40), (218, 33), (512, 33), (chamfer(42.3), 42.3)], TOP_O)
        pieces = band_pieces(212.5, 0, 42, 55, [(385, 508)])
        # the last piece's right edge follows the front chamfer
        left, right = pieces[0], pieces[1]
        clad(left, TOP_O)
        right = [p for p in right if p[0] < 600]
        right = right[:5] + [(chamfer(55), 55), (chamfer(42), 42)]
        clad(right, TOP_O)
        clad([(212, 54.7), (chamfer(54.7), 54.7), (531, 57.5), (212, 57.5)], TOP_O)
        # band (y 60..88): M-LOK slots x 457..488 and 495..526, y 72..79
        clad([(212.5, 60), (531, 60), (531, 72.3), (212.5, 72.3)], BAND_O)
        clad([(212.5, 78.7), (531, 78.7), (531, 80), (523.5, 90), (212.5, 90)], BAND_O)
        for pts in band_pieces(212.5, 531, 72, 79, [(457, 488), (495, 526)]):
            clad(pts, BAND_O, 0.0)
    # dark plates at the slot bottoms (read as openings)
    for side in (1, -1):
        prism_px(b, stadium(386, 507, 43, 54), side * 0.0195, side * 0.0213, PO)
        for s0, s1 in ((457, 488), (495, 526)):
            prism_px(b, stadium(s0 + 0.8, s1 - 0.8, 72.8, 78.2), side * 0.0195, side * 0.0215, PO)
    # ejection port (right side): a raised port frame with the bolt face showing
    prism_px(b, [(360, 61.5), (418, 61.5), (418, 75), (360, 75)], -0.0250, -0.0272, AL, 0.0006)
    prism_px(b, [(392, 65.5), (412, 65.5), (412, 72), (392, 72)], -0.0268, -0.0279, PO)
    prism_px(b, [(395, 66.5), (409, 66.5), (409, 71), (395, 71)], -0.0272, -0.0283, ST)
    # rear button and takedown pins
    disc_x(b, 235, 45, 4, -0.0250, -0.0262, DS)
    disc_x(b, 235, 45, 4, 0.0250, 0.0262, DS)

    # Picatinny rail: low spine plus teeth on a 10 mm pitch
    zb = P(0, 33.3)[1]
    spine = [(-0.0085, zb), (0.0085, zb), (0.0085, zb + 0.0022), (-0.0085, zb + 0.0022)]
    ya, yb = P(233, 0)[0], P(505, 0)[0]
    prism(b, spine, yb, ya, AL, axis="y")
    tooth = [(-0.0080, zb + 0.0010), (0.0080, zb + 0.0010), (0.0106, zb + 0.0030), (0.0106, zb + 0.0038),
             (0.0078, zb + 0.0050), (-0.0078, zb + 0.0050), (-0.0106, zb + 0.0038), (-0.0106, zb + 0.0030)]
    y = ya - 0.004
    while y - 0.0053 > yb + 0.001:
        prism(b, tooth, y - 0.0053, y, AL, axis="y")
        y -= 0.010

    # Flip-up sights (both up). Sight line at reference y 9.5.
    zs = P(0, 9.5)[1]
    ztop_rail = zb + 0.0050
    # rear: clamp, a tapered leaf, an aperture ring
    prism_px(b, [(241, 25), (262, 25), (262, 32.5), (241, 32.5)], -0.0112, 0.0112, AL, 0.0008)
    yr = P(250.5, 0)[0]
    prism(b, [(-0.0085, P(0, 25.5)[1]), (0.0085, P(0, 25.5)[1]), (0.0052, zs - 0.0040), (-0.0052, zs - 0.0040)],
          yr - 0.0018, yr + 0.0018, AL, axis="y")
    lathe(b, [(0.0, 0.0016), (0.0, 0.0050), (0.0034, 0.0050), (0.0034, 0.0016)], (0, yr + 0.0017, zs),
          (0, -1, 0), AL, seg=12, smooth=True, closed=True)
    prism(b, [(-0.0007, zs + 0.0049), (0.0007, zs + 0.0049), (0.0007, zs + 0.0068), (-0.0007, zs + 0.0068)],
          yr - 0.0012, yr + 0.0012, AL, axis="y")
    # front: clamp, two ears, the post between them
    prism_px(b, [(482, 24), (501, 24), (501, 32.5), (482, 32.5)], -0.0112, 0.0112, AL, 0.0008)
    yf = P(491.5, 0)[0]
    zc = P(0, 24.5)[1]
    for s in (1, -1):
        prism(b, [(s * 0.0047, zc + 0.0003), (s * 0.0085, zc + 0.0003), (s * 0.0072, P(0, 1.5)[1]), (s * 0.0047, P(0, 2.5)[1])],
              yf - 0.0019, yf + 0.0019, AL, axis="y")
    prism(b, [(-0.0050, zc), (0.0050, zc), (0.0050, zc + 0.0045), (-0.0050, zc + 0.0045)],
          yf - 0.0019, yf + 0.0019, AL, axis="y")
    prism(b, [(-0.0011, zc), (0.0011, zc), (0.0009, zs), (-0.0009, zs)], yf - 0.0012, yf + 0.0012, AL, axis="y")

    # Barrel and flash hider (axis at reference y 71)
    yb0, zbar = P(525, 71)
    lathe(b, [(0.0, 0.0056), ((552 - 525) * K, 0.0056)], (0, yb0, zbar), (0, -1, 0), DS, seg=12)
    lathe(b, [(0.0, 0.0095), (0.0060, 0.0095), (0.0068, 0.0080)], (0, P(529, 0)[0], zbar), (0, -1, 0), DS, seg=8, smooth=False)
    hp = [(0.0, 0.0062), (0.0045, 0.0062), (0.0045, 0.0076)]
    s = 0.0045
    for k in range(5):
        hp += [(s + 0.0010, 0.0081), (s + 0.0028, 0.0081), (s + 0.0034, 0.0068), (s + 0.0044, 0.0068)]
        s += 0.0044
    hp += [(s + 0.0006, 0.0088), (s + 0.0120, 0.0088), (s + 0.0130, 0.0080),
           (s + 0.0130, 0.0047), (s + 0.0040, 0.0047)]
    y_h = P(548, 0)[0]
    lathe(b, hp, (0, y_h, zbar), (0, -1, 0), DS, seg=12)
    muzzle_y = y_h - (s + 0.0130)
    # crown slots: four dark notches round the crown
    for ang in (45, 135, 225, 315):
        a = math.radians(ang)
        fs = prism(b, [(-0.0015, -0.0016), (0.0015, -0.0016), (0.0015, 0.0016), (-0.0015, 0.0016)],
                   muzzle_y - 0.0002, muzzle_y + 0.0060, PO, axis="y")
        for vtx in {v for f in fs for v in f.verts}:
            x, z = vtx.co.x, vtx.co.z + 0.0084
            vtx.co.x = x * math.cos(a) - z * math.sin(a)
            vtx.co.z = zbar + x * math.sin(a) + z * math.cos(a)

    # Lower receiver (polymer), magwell flare, trigger guard
    # the lower runs on down into the trigger guard's front post (one polymer moulding, as in the photo)
    lower = [(220, 87), (441, 87), (442, 98), (424, 106), (421, 137), (372, 140), (346, 147), (339, 147),
             (336.5, 140), (336.5, 120), (333, 114.5), (327, 113), (296, 112), (288, 108), (250, 104), (232, 100), (222, 94)]
    prism_px(b, lower, -0.0215, 0.0215, PO, bevel=0.0015)
    prism_px(b, [(370, 126), (421, 126), (425, 139.5), (366, 140)], -0.0255, 0.0255, PO, bevel=0.0018)  # flared mouth
    prism_px(b, [(378, 104), (421, 106), (419, 127), (376, 127)], -0.0232, 0.0232, PO, bevel=0.001)  # grip panel on the magwell
    prism_px(b, [(281, 141.5), (341, 141.5), (344, 144.5), (341, 149.5), (291, 150.5), (281, 147.5)],
             -0.0170, 0.0170, PO, bevel=0.0022, segs=2)                              # guard bow
    prism_px(b, [(305, 112), (313, 112), (313.5, 122), (318, 133), (321, 140), (316, 141), (310, 129), (306, 119)],
             -0.003, 0.003, DS)
    # the lower's raised side panel line (where the lower meets the upper)
    for side in (1, -1):
        prism_px(b, [(240, 87.2), (370, 87.2), (384, 95), (443, 95), (444, 100), (428, 106), (380, 104),
                     (296, 104), (250, 100), (238, 95)], side * 0.021, side * 0.0228, PO, 0.0007)

    # Pistol grip with raised textured side panels
    grip = [(241, 101), (293, 108), (292, 125), (291, 140), (284, 148), (280, 160), (278, 172), (276, 182),
            (273, 195), (272, 201), (277, 206), (278, 213), (273, 217), (230, 217), (222, 209), (224, 200),
            (228, 180), (235, 160), (240, 150), (245.5, 140), (247, 125), (246, 110)]
    prism_px(b, grip, -0.0155, 0.0155, PO, bevel=0.0040, segs=3)
    prism_px(b, [(223, 206), (277, 206), (279, 213), (274, 218.5), (229, 218.5), (221, 211)], -0.0172, 0.0172, PO, bevel=0.0025, segs=2)  # flared toe
    both(b, [(250, 124), (285, 130), (279, 160), (272, 195), (231, 195), (241, 152)], 0.014, 0.0168, PO, 0.0009)

    # Controls: ambidextrous safety, bolt catch (right), mag release, pins
    for side in (1, -1):
        disc_x(b, 289, 95, 6, side * 0.0225, side * 0.0250, DS)
        disc_x(b, 284, 92, 1.6, side * 0.0249, side * 0.0256, "sign_red", seg=8)   # the fire dot
        prism_px(b, [(286, 92), (306, 99), (305, 104), (286, 98)], side * 0.0240, side * 0.0262, DS)
        disc_x(b, 366, 106, 3.5, side * 0.0215, side * 0.0245, DS)
        disc_x(b, 437, 97, 3.5, side * 0.0210, side * 0.0240, DS)
        disc_x(b, 232, 84, 3.5, side * 0.0250, side * 0.0270, DS)
    for side in (1, -1):
        prism_px(b, [(341, 83), (349, 83), (350, 99), (343, 101)], side * 0.0225, side * 0.0258, DS, 0.0004)
    # left side: the maker's plate on the upper rear and the bolt-release paddle
    prism_px(b, [(238, 41), (290, 41), (290, 51), (238, 51)], 0.0240, 0.0252, PO, 0.0004)
    prism_px(b, [(322, 64), (352, 64), (352, 72), (322, 72)], 0.0250, 0.0266, AL, 0.0005)

    # Folding brace, extended: hinge, two bars with triangular webs, the arm-brace end
    prism_px(b, [(186, 58), (214, 58), (214, 91), (188, 89)], -0.020, 0.020, PO, bevel=0.0015)
    prism_px(b, [(195, 63), (206, 63), (206, 75), (195, 75)], -0.0228, -0.0198, PO, 0.0005)
    for side in (1, -1):
        disc_x(b, 209, 72, 4.5, side * 0.0195, side * 0.0222, ST)
    prism_px(b, [(56, 60), (188, 60), (188, 66.5), (56, 66.5)], -0.0065, 0.0065, PO, bevel=0.0012)
    prism_px(b, [(56, 75.5), (188, 75.5), (188, 81), (56, 81)], -0.0065, 0.0065, PO, bevel=0.0012)
    for web in ([(56, 64), (64, 64), (64, 78), (56, 78)],
                [(76, 78), (83, 78), (95, 64), (88, 64)],
                [(144, 64), (151, 64), (163, 78), (156, 78)],
                [(180, 64), (188, 64), (188, 78), (180, 78)]):
        prism_px(b, web, -0.0055, 0.0055, PO, bevel=0.0008)
    # the cuff (top) and the cheek frame below it, open in the middle
    prism_px(b, [(8, 52), (20, 47), (48, 47), (56, 52), (59, 62), (59, 86), (4, 86), (2, 64)],
             -0.024, 0.024, PO, bevel=0.0035, segs=2)
    prism_px(b, [(6, 85), (56, 85), (52, 101), (9, 101)], -0.018, 0.018, PO, bevel=0.0015)
    prism_px(b, [(7, 99), (27, 99), (28, 160), (16, 166), (9, 128)], -0.018, 0.018, PO, bevel=0.0015)
    prism_px(b, [(40, 99), (52, 99), (47, 160), (37, 160)], -0.018, 0.018, PO, bevel=0.0015)
    prism_px(b, [(15, 157), (54, 157), (56, 168), (54, 177), (20, 179), (13, 170)], -0.020, 0.020, PO, bevel=0.0025, segs=2)
    yk, zk = P(4, 70)
    lathe(b, [(0.0, 0.0075), (0.008, 0.0075)], (0, yk + 0.002, zk), (0, 1, 0), PO, seg=12)
    return b.build()


# ------------------------------------------------------------------ magazine

def mag_curve(t):
    """Magazine centreline: quadratic Bezier in reference px, top (seated) to bottom."""
    p0, p1, p2 = (391.0, 106.0), (399.0, 186.0), (429.0, 255.0)
    x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
    y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
    dx = 2 * (1 - t) * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0])
    dy = 2 * (1 - t) * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1])
    c = V(x, y)
    tan = Vector((0.0, -dx, -dy)).normalized()          # px -> Blender: Y = -x, Z = -y
    fwd = tan.cross(Vector((1, 0, 0)))
    if fwd.y > 0:
        fwd = -fwd
    return c, tan, fwd.normalized()


MAG_D, MAG_W = 0.0390, 0.0236


def build_mag():
    m = Part("mag")
    X = Vector((1, 0, 0))
    sec = rrect(MAG_D, MAG_W, 0.0065, 3)
    rings = []
    N = 10
    for i in range(N + 1):
        c, tan, fwd = mag_curve(i / N)
        rings.append([c + fwd * a + X * bb for a, bb in sec])
    loft(m, rings, CLEAR, smooth=True)
    # floor plate: a little bigger, with the front lip
    c, tan, fwd = mag_curve(1.0)
    base = rrect(MAG_D + 0.0070, MAG_W + 0.0045, 0.005, 2)
    r0 = [c - tan * 0.0015 + fwd * (a + 0.0015) + X * bb for a, bb in base]
    r1 = [c + tan * 0.0080 + fwd * (a + 0.0040) + X * bb for a, bb in base]
    loft(m, [r0, r1], "polymer_black", smooth=False)
    # internal ribs (dark spines inside the clear body) and witness-window ticks
    for side in (1, -1):
        for off in (-0.0135, -0.0030, 0.0115):
            rings = []
            for i in range(N + 1):
                t = 0.22 + 0.74 * i / N
                c, tan, fwd = mag_curve(t)
                cc = c + fwd * off + X * side * 0.0103
                rings.append([cc + fwd * a + X * bb for a, bb in ((-0.0008, -0.0007), (0.0008, -0.0007), (0.0008, 0.0007), (-0.0008, 0.0007))])
            loft(m, rings, "polymer_black", smooth=False)
        for t in (0.42, 0.62, 0.82):
            c, tan, fwd = mag_curve(t)
            cc = c + fwd * 0.004 + X * side * 0.0103
            ring_a = [cc + fwd * a + X * bb - tan * 0.0006 for a, bb in ((-0.007, -0.0007), (0.007, -0.0007), (0.007, 0.0007), (-0.007, 0.0007))]
            ring_b = [p + tan * 0.0012 for p in ring_a]
            loft(m, [ring_a, ring_b], "polymer_black", smooth=False)
    # the rounds: a staggered double stack, noses forward
    rp = [(0.0, 0.0048), (0.0010, 0.0049), (0.0190, 0.0048), (0.0190, 0.0045), (0.0235, 0.0040), (0.0270, 0.0022), (0.0285, 0.0)]
    n_r = 0
    t = 0.24
    while t < 0.56:                             # a part-loaded mag: the lower half shows smoke and ribs
        c, tan, fwd = mag_curve(t)
        x = 0.0034 if n_r % 2 == 0 else -0.0034
        lathe(m, rp, c - fwd * 0.0150 + X * x, fwd, "brass", seg=7, smooth=True)
        n_r += 1
        t += 0.0072 / 0.162
    return m.build()


def mag_top_front():
    c, tan, fwd = mag_curve(0.0)
    return c + fwd * MAG_D / 2


# ------------------------------------------------------------------ charging handle

def build_charging():
    ch = Part("charging")
    prism_px(ch, stadium(437, 462, 43.5, 54.5), -0.0200, -0.0300, "alloy_black", 0.0006)
    prism_px(ch, stadium(435, 464, 42.5, 55.5), -0.0298, -0.0326, "alloy_black", 0.0008)
    for k in range(4):                          # grip grooves on the knob's face
        x0 = 441 + k * 5
        prism_px(ch, [(x0, 44.5), (x0 + 1.6, 44.5), (x0 + 1.6, 53.5), (x0, 53.5)], -0.0324, -0.0332, "alloy_black")
    return ch.build()


# ------------------------------------------------------------------ main

gg.reset()
build_body()
build_mag()
build_charging()

# Review-only: let the clear mag show its insides (the game swaps its own shader by name).
mc = gg.mat(CLEAR)
bsdf = mc.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Alpha"].default_value = 0.68
for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
    try:
        setattr(mc, attr, val)
    except (AttributeError, TypeError):
        pass
mc.use_backface_culling = False

# Markers
gg.marker("grip", (0, 0, 0))
yb0, zbar = P(525, 71)
yh = P(548, 0)[0]
y_mz = yh - (0.0045 + 5 * 0.0044 + 0.0130)
gg.marker("muzzle", (0, y_mz, zbar))
zs = P(0, 9.5)[1]
yr = P(250.5, 0)[0]
gg.marker("eye", (0, yr + 0.06, zs))
gg.marker("support", (0, P(478, 0)[0], P(0, 80)[1]))
yk, zk = P(2, 68)
gg.marker("butt", (0, yk, zk))
gg.marker("mag_pivot", tuple(mag_top_front()))
gg.marker("charging_pivot", (-0.021, P(449.5, 0)[0], P(0, 49)[1]))

meta = {"hands": 2, "socket": "hand_r", "class": "smg", "notes": "9 mm PDW-style personal carbine"}
gg.finish("carbine", "item", meta)
