import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gg_common as gg
"""Gauntlet kit: `pistol`, a Beretta 92FS-style 9 mm service pistol, all black.

    blender -b --factory-startup --python game/tools/blender/gauntlet/gg_pistol.py -- --views --tag r0

Modelled in millimetres on a side profile: f = forward from the rearmost point
(grip heel / hammer), z = up from the magazine base. P() maps (x, f, z) into the
contract's weapon frame (muzzle -Y, up +Z, +X = the gun's LEFT, origin = fist
centre on the grip). Parts: `body` (frame, grips, barrel, hammer, trigger...)
and `slide` (the slide with its sights, serrations and decocker levers).
"""
import math

import bmesh
from mathutils import Vector

F0, Z0 = 18.5, 50.0             # fist centre on the grip, in profile mm
DARK_STEEL = "steel:#3a3d41"    # the 92FS is all black: small parts in dark steel
SLIDE_ROLE = "blued:#2c2f34"     # a hair lighter than the frame so the slide separates


FS = 217.0 / 236.3            # profile drawn ~231 mm heel-to-crown; squeezed along the bore to the real 217


def P(x, f, z):
    return Vector((x / 1000.0, -(f - F0) * FS / 1000.0, (z - Z0) / 1000.0))


# ------------------------------------------------------------------ 2D helpers

def area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                     for i in range(len(poly)))


def offset(poly, d):
    """Mitred outward offset (d < 0 insets) of a closed 2D polygon."""
    s = 1.0 if area(poly) > 0 else -1.0
    n = len(poly)
    out = []
    for i in range(n):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]

        def nrm(p, q):
            dx, dy = q[0] - p[0], q[1] - p[1]
            l = math.hypot(dx, dy) or 1.0
            return (s * dy / l, -s * dx / l)
        n1, n2 = nrm(a, b), nrm(b, c)
        mx, my = n1[0] + n2[0], n1[1] + n2[1]
        ml = math.hypot(mx, my)
        if ml < 1e-6:
            mx, my, ml = n1[0], n1[1], 1.0
        mx, my = mx / ml, my / ml
        cosh = max(mx * n1[0] + my * n1[1], 0.4)
        k = d / cosh
        out.append((b[0] + mx * k, b[1] + my * k))
    return out


def arc(cx, cz, r, a0, a1, n):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cz + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def strip(pts, t):
    """A closed outline around an open polyline, thickness t."""
    left, right = [], []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        l = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / l * t / 2, dx / l * t / 2
        left.append((p[0] + nx, p[1] + nz))
        right.append((p[0] - nx, p[1] - nz))
    return left + right[::-1]


# ------------------------------------------------------------------ 3D pieces

PIECES = {"body": [], "slide": [], "mag": []}


def add(part, bm, role):
    ob = gg.mesh_object("%s_%d" % (part, len(PIECES[part])), bm, [role])
    PIECES[part].append(ob)
    return ob


def _faces_between(bm, ring_a, ring_b):
    n = len(ring_a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ring_a[i], ring_a[j], ring_b[j], ring_b[i]))


def plate(part, role, outline, x0, x1, bev=1.0):
    """Side-profile prism: outline (f, z) extruded across x0..x1 with a chamfer band."""
    bm = bmesh.new()
    if area(outline) < 0:
        outline = outline[::-1]
    bev = min(bev, (x1 - x0) * 0.45)
    if bev > 0:
        inner = offset(outline, -bev)
        layers = [(x0, inner), (x0 + bev, outline), (x1 - bev, outline), (x1, inner)]
    else:
        layers = [(x0, outline), (x1, outline)]
    rings = [[bm.verts.new(P(x, f, z)) for f, z in poly] for x, poly in layers]
    bm.faces.new(rings[0][::-1])
    for a, b in zip(rings, rings[1:]):
        _faces_between(bm, a, b)
    bm.faces.new(rings[-1])
    return add(part, bm, role)


def loft(part, role, sections, cap=True):
    """Sections (f, [(x, z)...]) of equal length, lofted along the bore."""
    bm = bmesh.new()
    rings = [[bm.verts.new(P(x, f, z)) for x, z in sec] for f, sec in sections]
    for a, b in zip(rings, rings[1:]):
        _faces_between(bm, a, b)
    if cap:
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])
    return add(part, bm, role)


def bar(part, role, sec, f0, f1, ch=0.8):
    """A section lofted f0..f1 with chamfered ends."""
    if area(sec) < 0:
        sec = sec[::-1]
    ins = offset(sec, -ch)
    return loft(part, role, [(f0, ins), (f0 + ch, sec), (f1 - ch, sec), (f1, ins)])


def circle(cx, cz, r, n):
    return [(cx + r * math.cos(2 * math.pi * i / n), cz + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def disk_x(part, role, f, z, r, x0, x1, n=12, bev=0.4):
    """A round button/pin across x (axis along X)."""
    return plate(part, role, circle(f, z, r, n), x0, x1, bev)


def both(fn, *a, **k):
    """Build a side detail on the right (-X) and mirrored on the left (+X): fn(sign)."""
    fn(-1, *a, **k)
    fn(1, *a, **k)


def xr(sign, a, b):
    """x range a..b (positive mm, a < b) on side `sign`."""
    return (a, b) if sign > 0 else (-b, -a)


def torus_x(part, role, f, z, R, r, nu=10, nv=6, x=0.0):
    bm = bmesh.new()
    rings = []
    for i in range(nu):
        u = 2 * math.pi * i / nu
        cu, su = math.cos(u), math.sin(u)
        ring = []
        for j in range(nv):
            v = 2 * math.pi * j / nv
            rr = R + r * math.cos(v)
            ring.append(bm.verts.new(P(x + r * math.sin(v), f + rr * cu, z + rr * su)))
        rings.append(ring)
    for i in range(nu):
        _faces_between(bm, rings[i], rings[(i + 1) % nu])
    return add(part, bm, role)


# ------------------------------------------------------------------ the pistol

RAKE, RAKE_Z = 9.0, 78.0                 # the grip rakes back: f shifts -RAKE*(RAKE_Z - z)/66 below RAKE_Z


def rake(pts):
    return [(f - RAKE * max(0.0, RAKE_Z - z) / 66.0, z) for f, z in pts]


MAG_BODY = rake([(-4, 10), (34, 10), (47, 91), (34, 94), (11, 94), (9, 91)])   # side outline, top-front at (47, 91)
MAG_AXIS = (22.3 * FS, 81.0)                                                   # (df, dz) up the grip's rake
SLIDE_BOT, SLIDE_TOP = 99.0, 132.0
BORE_Z = 121.0


def slide_section(top, half=15.0, bot=SLIDE_BOT):
    return [(-half, bot), (half, bot), (half, top - 8), (half - 1.5, top - 3), (half - 5, top),
            (-(half - 5), top), (-(half - 1.5), top - 3), (-half, top - 8)]


def build_slide():
    # rear block (breech): closed, full height, f 12..98; front face sloped like the 92's
    rear = slide_section(SLIDE_TOP)
    ins = offset(rear[::-1] if area(rear) < 0 else rear, -0.8)
    low = slide_section(129.5)
    loft("slide", SLIDE_ROLE, [(12, ins), (12.8, rear), (80, rear), (90, slide_section(131.4)), (97, slide_section(130.3)),
                            (100, low), (100.6, offset(low, -0.6))])
    # open-top side walls, f 100..196: the barrel shows between them
    for s in (-1, 1):
        wall = [(9.5, SLIDE_BOT), (15.0, SLIDE_BOT), (15.0, 123.0), (13.5, 126.0), (9.5, 126.5)]
        wall = [(s * x, z) for x, z in wall]
        bar("slide", SLIDE_ROLE, wall, 99.5, 197, 0.5)
    # the nose bridge around the muzzle, f 196..212 (sweeps up from the walls)
    # the nose sweeps up out of the walls (a scoop, not a step) and rounds off at the crown
    nose = slide_section(130.5)
    nose_lo = slide_section(130.5, bot=104.0)
    loft("slide", SLIDE_ROLE, [(186, offset(slide_section(126.5), -0.8)), (187, slide_section(126.5)), (191, slide_section(128.8)),
                               (196, slide_section(130.2)), (201, nose), (206, nose), (210.6, nose_lo), (212, offset(nose_lo, -2.6))])
    # sights: rear notch (two posts on a base), front blade
    plate("slide", SLIDE_ROLE, [(14, 131), (23, 131), (23, 133.4), (14, 134.0)], -8, 8, 0.5)
    for s in (-1, 1):
        a, b = xr(s, 1.8, 7.5)
        plate("slide", SLIDE_ROLE, [(14, 132), (22, 132), (22, 135.5), (20, 138.2), (14, 138.2)], a, b, 0.4)
        disk_y("slide", "sign_white", 135.4, 1.0, 13.5, 14.2, 14, cx=s * 4.6)      # white dots, sight picture
    plate("slide", SLIDE_ROLE, [(203, 130), (209, 130), (208.5, 136), (206.5, 138.2), (203, 138.2)], -1.7, 1.7, 0.3)
    disk_y("slide", "sign_white", 135.6, 0.9, 202.5, 203.2, 14)
    # rear cocking serrations: proud ribs on both sides
    for s in (-1, 1):
        a, b = xr(s, 14.6, 15.8)
        for i in range(12):
            f = 32 + i * 1.8
            plate("slide", SLIDE_ROLE, [(f, 101.5), (f + 0.9, 101.5), (f + 0.9, 124.5), (f, 124.5)], a, b, 0.25)
    # ambidextrous safety/decocker levers on the slide's rear, red dot on each
    for s in (-1, 1):
        a, b = xr(s, 14.6, 16.9)
        # a round hub with a narrow paddle sweeping up and back to the slide's top line
        disk_x("slide", DARK_STEEL, 23.0, 119.5, 3.6, a, b, 14, 0.5)
        plate("slide", DARK_STEEL, strip([(23.0, 119.5), (18.0, 124.5), (13.5, 129.0)], 3.2), a, b, 0.5)
        a, b = xr(s, 14.6, 15.6)
        disk_x("slide", "sign_red", 30.5, 113.0, 1.3, a, b, 10, 0.2)        # the fire dot, under the lever


def build_body():
    # frame: one side profile from the beavertail tang over the dust cover to the grip
    frame = [(1, 98.9), (8, 98.9), (195, 98.9), (197.5, 96.5), (197, 92), (192, 88.5), (128, 88.5), (122, 89.5),
             (66, 92), (61, 87), (58, 80), (54.5, 68), (49.5, 52), (45, 34), (40.5, 22), (40.5, 16), (42, 12.5),
             (-10.5, 12), (-9, 17), (-7, 30), (-4.5, 55), (-2.5, 70), (0, 82), (2.5, 88), (1.5, 92), (1.5, 96.5)]
    # beavertail tang: a narrower hump under the hammer, not a full-width shelf
    plate("body", "gunmetal", [(-3.5, 92.8), (2, 90.5), (9, 95), (9, 98.6), (-1.5, 98.6), (-4.5, 96.2)], -8, 8, 1.4)
    # dust cover: as wide as it can sit under the slide, so it reads flush with it
    plate("body", "gunmetal", [(118, 98.8), (195, 98.8), (197.5, 96.5), (197, 92), (192, 88.5), (122, 88.5), (118, 92)], -13.5, 13.5, 1.2)
    frame = rake(frame)
    plate("body", "gunmetal", frame, -11, 11, 1.2)
    # round trigger guard: a loop from under the frame round to the grip's front
    guard = arc(106, 84, 18.5, 45, -90, 16) + [(80, 65.5), (70, 67), (62, 70.5), (55.5, 74)]
    plate("body", "gunmetal", strip(guard, 4.5), -6, 6, 0.9)
    # grip panels with checkering, a medallion and screws
    panel = rake([(3, 92), (55, 92), (56, 82), (46, 52), (37.5, 17), (-4.5, 17), (-2.5, 50), (0, 80)])
    feats = [(f, z, r) for (f, z), r in zip(rake([(14.0, 74.0), (19.0, 25.0), (36.0, 85.0)]), (5.0, 2.6, 2.6))]   # (f, z, r) medallion, screws
    inner = offset(panel, -3.5)
    for s in (-1, 1):
        a, b = xr(s, 10.0, 16.0)
        plate("body", "polymer_black", panel, a, b, 1.6)
        f, z, r = feats[0]
        a, b = xr(s, 15.5, 16.8)
        disk_x("body", DARK_STEEL, f, z, r, a, b, 16, 0.5)
        for f, z, r in feats[1:]:
            a, b = xr(s, 15.5, 16.9)
            disk_x("body", DARK_STEEL, f, z, r, a, b, 8, 0.5)
        checker(s, inner, feats)
    # magazine base, a touch proud of the grip; lanyard ring at the heel
    plate("mag", "polymer_black", rake([(-10.5, 1), (41, 1), (42.5, 6), (42, 12.5), (-10.5, 12.5), (-11.5, 6)]), -13.5, 13.5, 1.5)
    # lanyard ring: a swivel on the left of the heel, the ring lying flat along the backstrap
    (lf, lz), = rake([(-3.0, 19.0)])
    disk_x("body", DARK_STEEL, lf, lz, 2.2, 10.5, 12.4, 8, 0.3)
    torus_x("body", DARK_STEEL, lf - 1.0, lz - 4.0, 3.6, 1.0, x=12.6)
    # the magazine body inside the grip (hidden until it drops), raked with the grip
    plate("mag", "blued", MAG_BODY, -6.5, 6.5, 0.8)
    # barrel: chamber block, tube, and a dark bore at the crown
    barrel = [(98, circle(0, BORE_Z, 7.6, 16)), (118, circle(0, BORE_Z, 7.6, 16)), (122, circle(0, BORE_Z, 7.0, 16)),
              (214.2, circle(0, BORE_Z, 7.0, 16)), (215, circle(0, BORE_Z, 6.3, 16))]
    loft("body", "steel:#55595e", barrel)
    disk_y("body", "rubber", BORE_Z, 4.4, 214.6, 215.25, 16)
    # recoil-spring guide rod end under the barrel, in the nose
    disk_y("body", "rubber", 110.5, 3.4, 211.4, 212.3)
    disk_y("body", DARK_STEEL, 110.5, 2.2, 211.4, 212.7, 10)
    # external hammer (decocked, spur up at the rear)
    plate("body", DARK_STEEL, [(6, 94), (17, 95), (18, 102), (16, 112), (12.5, 120), (5, 120), (2.5, 116), (5, 106)],
          -4.2, 4.2, 0.8)
    # the spur: solid, top level with the slide, with a hole through it
    holed_plate("body", DARK_STEEL, [(2, 118), (12.5, 118), (13.5, 125), (11.5, 130.5), (7, 132.2), (2.5, 130.5), (0.5, 125)],
                (7.0, 125.5), 2.3, -3.0, 3.0)
    # trigger
    plate("body", DARK_STEEL, strip([(86, 95), (85, 89), (85.5, 83), (88, 77.5), (92.5, 74)], 6.5), -3.8, 3.8, 1.0)
    # controls: slide stop + takedown lever (left), takedown button (right), mag release (left)
    plate("body", DARK_STEEL, [(96, 94), (116, 94), (121, 96.5), (117, 98.6), (97, 98.6)], 10.5, 14.6, 0.5)
    disk_x("body", DARK_STEEL, 130.0, 94.5, 3.6, 12.5, 14.9, 14, 0.5)
    disk_x("body", DARK_STEEL, 130.0, 94.5, 2.6, -14.7, -12.5, 12, 0.4)
    disk_x("body", DARK_STEEL, 78.0, 95.5, 1.8, -11.8, -10.5, 8, 0.3)       # trigger pin, right
    disk_x("body", DARK_STEEL, 78.0, 95.5, 1.8, 10.5, 11.8, 8, 0.3)
    plate("body", DARK_STEEL, [(52, 80), (57.5, 80), (59, 88), (53.5, 88)], 10.5, 13.0, 0.6)


def holed_plate(part, role, outline, c, r, x0, x1, n=16):
    """A plate whose outline (star-shaped about c) has a round through-hole of radius r at c."""
    bm = bmesh.new()
    outer, inner = [], []
    for i in range(n):
        t = 2 * math.pi * i / n
        d = (math.cos(t), math.sin(t))
        best = None
        for j in range(len(outline)):
            (ax, az), (bx, bz) = outline[j], outline[(j + 1) % len(outline)]
            ex, ez = bx - ax, bz - az
            den = d[0] * ez - d[1] * ex
            if abs(den) < 1e-9:
                continue
            u = ((ax - c[0]) * ez - (az - c[1]) * ex) / den
            v = ((ax - c[0]) * d[1] - (az - c[1]) * d[0]) / den
            if u > 0 and -1e-6 <= v <= 1 + 1e-6 and (best is None or u < best):
                best = u
        outer.append((c[0] + d[0] * best, c[1] + d[1] * best))
        inner.append((c[0] + d[0] * r, c[1] + d[1] * r))
    rings = {}
    for x in (x0, x1):
        rings[x] = ([bm.verts.new(P(x, f, z)) for f, z in outer], [bm.verts.new(P(x, f, z)) for f, z in inner])
    for i in range(n):
        j = (i + 1) % n
        for x, flip in ((x0, True), (x1, False)):
            o, k = rings[x]
            q = (o[i], o[j], k[j], k[i])
            bm.faces.new(q[::-1] if flip else q)
        bm.faces.new((rings[x0][0][i], rings[x0][0][j], rings[x1][0][j], rings[x1][0][i]))
        bm.faces.new((rings[x0][1][j], rings[x0][1][i], rings[x1][1][i], rings[x1][1][j]))
    return add(part, bm, role)


def disk_y(part, role, z, r, f0, f1, n=12, cx=0.0):
    return loft(part, role, [(f0, circle(cx, z, r, n)), (f1, circle(cx, z, r, n))])


def inside(poly, f, z):
    c = False
    n = len(poly)
    for i in range(n):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
        if (y1 > z) != (y2 > z) and f < (x2 - x1) * (z - y1) / (y2 - y1) + x1:
            c = not c
    return c


def checker(s, region, feats, a=1.8, h=0.75, x=15.8):
    """Raised diamond pyramids (closed, 6 tris each) tiling the grip panel's face."""
    bm = bmesh.new()
    j = 0
    z = 15.0
    while z < 95:
        f = (a if j % 2 else 0.0) - 2 * a
        while f < 62:
            corners = [(f - a, z), (f, z - a), (f + a, z), (f, z + a)]
            ok = all(inside(region, cf, cz) for cf, cz in corners)
            ok = ok and all(math.hypot(f - ff, z - zz) > rr + 1.6 for ff, zz, rr in feats)
            if ok:
                base = [bm.verts.new(P(s * x, cf, cz)) for cf, cz in corners]
                apex = bm.verts.new(P(s * (x + h + 0.2), f, z))
                bm.faces.new(base)
                for i in range(4):
                    bm.faces.new((base[(i + 1) % 4], base[i], apex))
            f += 2 * a
        z += a
        j += 1
    add("body", bm, "polymer_black")


def main():
    gg.reset()
    build_slide()
    build_body()
    gg.join("body", PIECES["body"])
    gg.join("slide", PIECES["slide"])
    gg.join("mag", PIECES["mag"])
    gg.marker("grip", (0, 0, 0))
    gg.marker("muzzle", P(0, 215.3, BORE_Z))
    gg.marker("eye", P(0, -20, 138.2))     # on the line over the sight tops
    gg.marker("support", P(0, 44, 38))
    gg.marker("slide_pivot", P(0, 12, 118))
    gg.marker("mag_pivot", P(0, 47, 91), fwd=(0, -MAG_AXIS[0], MAG_AXIS[1]), up=(0, -1, 0))
    meta = {"hands": 1, "socket": "hand_r", "class": "pistol", "notes": "Beretta 92FS style"}
    gg.finish("pistol", "item", meta)
    if gg.arg("--close"):
        # my own close-ups (not in the sheet): right side, the first-person view, rear 3/4
        c = P(0, 100, 80)
        gg.render_views("pistolclose", "item", str(gg.arg("--tag", "r0")), views={
            "right": (c + Vector((-0.42, 0, 0)), c),
            "fp": (P(0, -70, 160), P(0, 150, 118)),
            "rear": (P(-90, -80, 150), P(0, 60, 100)),
            "under": (P(-120, 260, 20), P(0, 100, 80))})


main()
