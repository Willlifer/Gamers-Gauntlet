import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gg_common as gg
"""Campus paintball (Gauntlet kit env): a leafy college campus in autumn turned
into a paintball field. Reference: design/ref/kit/campus.jpg.

    blender -b --factory-startup --python game/tools/blender/gauntlet/gg_campus.py -- --views --tag r0

Layout (Blender axes, metres, ground z = 0):
  play area x -55..55 (long axis), y -40..40; spawn A at x = -51 (west), B at +51 (east).
  Gameplay mirrors about x = 0; dressing (colours, canopy styles, backdrop) does not.
  Centre: the stone chapel (nave along y, tower at its south end) splits the field.
  North flank: two brick halls (with a back alley behind them) and the north path.
  South: the curving road (the open danger lane) bowing north at the chapel's forecourt,
  then a strip of lawn and the brick gatehouse beyond it.
  Mid flanks: a small brick lodge each side. Lawns carry inflatable bunkers, bushes
  (walk-through, HIDE_) and trees (trunks are thin hard cover).
  Outside the stone wall + net: a ring of real trees, then a canopy "blanket" heightfield
  (one closed terrain mesh whose crowns are coloured per tree) with backdrop buildings.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

R = random.Random(1234)
PI = math.pi
HX, HY = 55.0, 40.0                        # play-area half extents
TERR = 240.0                               # terrain half size
STEP = 3.0                                 # terrain grid step

BLUE = "polymer_black:#2a7ad8"
YELLOW = "polymer_black:#f2c21a"
RED = "sign_red"
WHITE = "sign_white"
STONE = "stone_grey"
STONE_L = "stone_grey:#cdc8bb"
CH_STONE = "stone_grey:#aa9f8a"
CH_TRIM = "stone_grey:#c9bea6"
CH_JOINT = "stone_grey:#867c6a"
BRICK = "brick_red"
GRASS = "grass:#638a36"
GRASS_STRIPE = "grass:#7fa648"
GRASS_ROUGH = "grass:#6c8638"
FOLIAGE = [("foliage", 14), ("foliage:#3d6a25", 12), ("foliage:#6f8c2c", 10), ("foliage:#2f4f22", 6),
           ("foliage_gold", 12), ("foliage_gold:#e2bb34", 8), ("foliage_autumn", 10),
           ("foliage_autumn:#dc8f2c", 8), ("foliage_red", 6), ("foliage_red:#c2461f", 6)]


FOLIAGE_GREEN = [("foliage", 16), ("foliage:#3d6a25", 14), ("foliage:#6f8c2c", 10), ("foliage:#2f4f22", 6),
                 ("foliage_gold", 5), ("foliage_autumn", 4), ("foliage_red", 2)]
FOLIAGE_WARM = [("foliage", 4), ("foliage:#6f8c2c", 4), ("foliage_gold", 10), ("foliage_gold:#e2bb34", 7),
                ("foliage_autumn", 8), ("foliage_autumn:#dc8f2c", 6), ("foliage_red", 5), ("foliage_red:#c2461f", 4)]


def pick(rng, table):
    tot = sum(w for _, w in table)
    x = rng.uniform(0, tot)
    for v, w in table:
        x -= w
        if x <= 0:
            return v
    return table[-1][0]


# ------------------------------------------------------------------ mesh helpers

class Part:
    def __init__(s, name):
        s.name = name
        s.bm = bmesh.new()
        s.roles = []

    def mi(s, role):
        if role not in s.roles:
            s.roles.append(role)
        return s.roles.index(role)

    def add(s, verts, faces, role, M=None, smooth=False, face_roles=None):
        if M is not None:
            vs = [s.bm.verts.new(M @ Vector(v)) for v in verts]
        else:
            vs = [s.bm.verts.new(v) for v in verts]
        mi = s.mi(role)
        for k, f in enumerate(faces):
            try:
                face = s.bm.faces.new([vs[i] for i in f])
            except ValueError:
                continue
            face.material_index = s.mi(face_roles[k]) if face_roles else mi
            face.smooth = smooth[k] if isinstance(smooth, list) else smooth
        return vs

    def box(s, c, h, role, rz=0.0, M=None):
        v, f = box_geo(*h)
        m = T(*c, rz=rz)
        s.add(v, f, role, (M @ m) if M is not None else m)

    def boxM(s, M, c, h, role):
        v, f = box_geo(*h)
        s.add([(a + c[0], b + c[1], z + c[2]) for a, b, z in v], f, role, M)

    def tris(s):
        return sum(len(f.verts) - 2 for f in s.bm.faces)

    def done(s):
        return gg.mesh_object(s.name, s.bm, s.roles)


def T(x, y, z, rz=0.0, ry=0.0, rx=0.0, sc=None):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    if sc is not None:
        m = m @ Matrix.Diagonal((sc[0], sc[1], sc[2], 1.0))
    return m


def frame(o, t, n):
    """Local (u, d, w) -> world o + u*t + d*n + w*up (a wall face; d = outward)."""
    t = Vector(t).normalized()
    n = Vector(n).normalized()
    return Matrix(((t.x, n.x, 0, o[0]), (t.y, n.y, 0, o[1]), (t.z, n.z, 1, o[2]), (0, 0, 0, 1)))


def box_geo(hx, hy, hz):
    v = [(sx * hx, sy * hy, sz * hz) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    f = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return v, f


def lathe_geo(prof, n, phase=0.0):
    v, f, rings = [], [], []
    for r, z in prof:
        if r < 1e-6:
            rings.append([len(v)])
            v.append((0.0, 0.0, z))
        else:
            idx = []
            for i in range(n):
                a = 2 * PI * i / n + phase
                idx.append(len(v))
                v.append((r * math.cos(a), r * math.sin(a), z))
            rings.append(idx)
    for A, B in zip(rings, rings[1:]):
        if len(A) == 1 and len(B) == 1:
            continue
        if len(A) == 1:
            f += [(A[0], B[i], B[(i + 1) % n]) for i in range(n)]
        elif len(B) == 1:
            f += [(A[i], A[(i + 1) % n], B[0]) for i in range(n)]
        else:
            f += [(A[i], A[(i + 1) % n], B[(i + 1) % n], B[i]) for i in range(n)]
    if len(rings[0]) > 1:
        f.append(tuple(reversed(rings[0])))
    if len(rings[-1]) > 1:
        f.append(tuple(rings[-1]))
    return v, f


def prism_geo(poly, z0, z1, top_scale=1.0):
    """Extrude an XY polygon from z0 to z1 (top optionally scaled about the origin)."""
    n = len(poly)
    v = [(x, y, z0) for x, y in poly] + [(x * top_scale, y * top_scale, z1) for x, y in poly]
    f = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    f += [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    return v, f


def slab_geo(poly_uw, d0, d1):
    """A polygon in a wall plane (u along, w up) extruded outward d0..d1 -> local (u, d, w)."""
    n = len(poly_uw)
    v = [(u, d0, w) for u, w in poly_uw] + [(u, d1, w) for u, w in poly_uw]
    f = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    f += [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    return v, f


_ICO = {}


def ico_geo(sub):
    if sub not in _ICO:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        bm.verts.index_update()
        _ICO[sub] = ([tuple(x.co) for x in bm.verts], [tuple(x.index for x in fa.verts) for fa in bm.faces])
        bm.free()
    return _ICO[sub]


def blob(P, c, r, role, rng, sub=1, jit=0.13, rz=0.0, smooth=True):
    v, f = ico_geo(sub)
    vv = []
    for x, y, z in v:
        k = 1.0 + rng.uniform(-jit, jit)
        vv.append((x * r[0] * k, y * r[1] * k, z * r[2] * k))
    P.add(vv, f, role, T(c[0], c[1], c[2], rz=rz), smooth=smooth)


def spline(ctrl, step=1.5):
    P = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = (Vector(q) for q in (P[i - 1], P[i], P[i + 1], P[i + 2]))
        n = max(1, int((p2 - p1).length / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(Vector(ctrl[-1]))
    return out


def ribbon(P, pts, hw, z0, z1, role, off=0.0):
    """A closed slab following a 2D polyline (paths, road); `off` shifts it sideways."""
    n = len(pts)
    verts = []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = (b - a).normalized()
        nr = Vector((-t.y, t.x))
        L, Rr = p + nr * (off + hw), p + nr * (off - hw)
        verts += [(L.x, L.y, z1), (Rr.x, Rr.y, z1), (L.x, L.y, z0), (Rr.x, Rr.y, z0)]
    faces = []
    for i in range(n - 1):
        a, b = 4 * i, 4 * (i + 1)
        faces += [(a, a + 1, b + 1, b), (a + 2, b + 2, b + 3, a + 3), (a, b, b + 2, a + 2), (a + 1, a + 3, b + 3, b + 1)]
    e = 4 * (n - 1)
    faces += [(0, 2, 3, 1), (e, e + 1, e + 3, e + 2)]
    P.add(verts, faces, role)


def offset_pts(pts, off):
    out = []
    n = len(pts)
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = (b - a).normalized()
        out.append(p + Vector((-t.y, t.x)) * off)
    return out


def seg_dist(p, a, b):
    ab = b - a
    L2 = ab.length_squared
    t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / L2))
    return (p - (a + ab * t)).length


def poly_dist(p, pts):
    p = Vector(p[:2])
    return min(seg_dist(p, pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def rect_dist(p, rect):
    cx, cy, hx, hy = rect
    dx = max(abs(p[0] - cx) - hx, 0.0)
    dy = max(abs(p[1] - cy) - hy, 0.0)
    return math.hypot(dx, dy)


def COL(c, h, rz=0.0):
    gg.box_volume("COL", c, h, rz)


def HIDE(c, h, rz=0.0):
    gg.box_volume("HIDE", c, h, rz)


# ------------------------------------------------------------------ parts

G = Part("ground")
B = Part("buildings")
TR = Part("trees")
BU = Part("bushes")
BK = Part("bunkers")
PR = Part("props")

# ---------------------------------------------------------------- layout data

def road_y(x):
    return -15.0 - 13.0 * (x / 55.0) ** 2


ROAD_HW = 3.5
road_ctrl = ([(-240, -44), (-190, -52), (-140, -50), (-100, -44), (-75, -36.4)] +
             [(x, road_y(x)) for x in (-55, -40, -25, -12, 0, 12, 25, 40, 55)] +
             [(72, -35.5), (92, -48), (115, -72), (140, -108), (165, -150), (190, -200), (212, -240)])
ROAD = spline(road_ctrl, 2.0)
ROAD_IN = [p for p in ROAD if abs(p.x) <= 60]

# inner buildings (axis-aligned rects cx, cy, hx, hy) for placement checks
HALL_Y = 32.5
RECTS = [(-27, HALL_Y, 10, 5), (27, HALL_Y, 10, 5),            # north halls
         (-33, 12, 4, 3.2), (33, 12, 4, 3.2),                  # lodges
         (0, -31, 8, 4.5),                                     # gatehouse
         (0, 6, 8.2, 9.2), (0, 9, 11.3, 3.6), (0, 17.25, 4.6, 2.4), (0, -5.5, 4.0, 4.0)]  # chapel


def mirror_ctrl(c):
    return [(-x, y) for x, y in reversed(c)]


PATHS = []          # (pts, hw, role)


def add_path(ctrl, hw, role="path_concrete:#c3c3bf", mirror=True, step=1.2):
    PATHS.append((spline(ctrl, step), hw, role))
    if mirror:
        PATHS.append((spline(mirror_ctrl(ctrl), step), hw, role))


add_path([(-48, 4), (-40, 5.4), (-34, 6.4), (-26, 6.9), (-18, 7.8), (-11.4, 9.0)], 1.2)        # spawn -> transept door
add_path([(-52, 23.8), (-36, 23.8), (-18, 23.9), (0, 23.8), (18, 23.9), (36, 23.8), (52, 23.8)], 1.2, mirror=False)  # north path
add_path([(-46.5, 23.0), (-43.5, 16), (-41.5, 9.5), (-40.5, 5.6)], 1.0)                          # NW diagonal
add_path([(-11.3, 12.5), (-13.5, 18), (-17, 23.2)], 1.0)                                         # transept -> north path
add_path([(-8.0, -9.5), (-9.4, -2), (-10.2, 3), (-11.4, 7.0)], 1.0)                              # forecourt -> transept
add_path([(0, -18.6), (0, -26.2)], 1.4, mirror=False)                                            # road -> gatehouse
add_path([(-36.5, 12.0), (-41.2, 11.0)], 0.8)                                                    # lodge door -> diagonal
SIDEWALK = [p for p in offset_pts(ROAD, ROAD_HW + 1.7) if abs(p.x) <= 56]


def on_paths(p, extra):
    for pts, hw, _ in PATHS:
        if poly_dist(p, pts) < hw + extra:
            return True
    return poly_dist(p, SIDEWALK) < 1.0 + extra


SPAWNS_A = [(-51.0, -5.0), (-51.0, 0.0), (-51.0, 5.0)]
SPAWNS_B = [(51.0, -5.0), (51.0, 0.0), (51.0, 5.0)]

# bunkers: west half (mirrored to the east); x == 0 entries are not mirrored
BUNKERS = [
    ("temple", -44.0, 0.0, PI / 2), ("dorito", -44.0, 9.5, 0.0), ("dorito", -44.0, -9.5, PI),
    ("can", -39.0, 16.5, 0.0), ("can", -38.0, -12.5, 0.0), ("snake", -33.0, 20.5, 0.0),
    ("brick", -32.0, -4.5, PI / 2), ("dorito", -29.5, 2.0, 0.6), ("can", -25.0, -8.5, 0.0),
    ("temple", -22.0, 15.5, PI / 2), ("can", -19.0, -6.3, 0.0), ("dorito", -8.6, 21.1, 0.2),
    ("snake", -27.0, -25.0, 0.12), ("temple", -40.0, -31.0, 0.0), ("can", -13.0, -26.5, 0.0),
    ("can", -49.0, 31.0, 0.0), ("dorito", -42.5, 30.5, 0.4), ("brick", -12.0, 31.5, 0.0),
    ("can", -49.5, -35.5, 0.0), ("brick", -21.0, -33.0, 0.0), ("can", -5.0, -22.3, 0.0),
    ("dorito", 0.0, 21.35, 0.0), ("can", -9.5, 36.5, 0.0),
    ("can", -35.0, -9.0, 0.0), ("dorito", -24.0, 10.8, 0.3), ("can", -14.5, 3.0, 0.0), ("brick", -50.0, 15.5, PI / 2),
    ("can", -41.0, 36.2, 0.0), ("brick", -10.5, -24.9, 0.0),
    # r2: lane breakers (north path, road shoulders, south strip, back alley)
    ("brick", -12.5, 24.0, 0.0, "onpath"), ("can", -26.0, 25.6, 0.0, "onpath"), ("temple", 0.0, 27.0, 0.0, "onpath"),
    ("can", -19.5, 22.6, 0.0, "onpath"), ("snake", -44.0, -15.4, 0.2), ("dorito", -31.0, -13.2, 0.5, "onpath"),
    ("can", -36.0, -26.4, 0.0), ("can", -30.0, -37.6, 0.0), ("can", 0.0, 38.3, 0.0), ("can", -29.0, -11.0, 0.0),
    ("tower", -22.0, 20.0, 0.0), ("tower", -22.0, -11.0, 0.0, "onpath"), ("wall", -20.0, -24.0, 0.0),
    ("tower", -37.5, 19.6, 0.0), ("wall", -37.0, 0.5, PI / 2), ("tower", -14.0, -8.6, 0.0, "onpath"),
    ("tower", -44.6, 5.2, 0.0, "onpath"), ("tower", -44.6, -5.4, 0.0),
    ("brick", -49.0, -18.4, 0.45, "onpath"), ("temple", -46.5, -14.6, 0.3), ("can", -17.0, -21.2, 0.0),
]
BUNK_R = {"can": 0.8, "dorito": 1.1, "temple": 1.3, "snake": 3.7, "brick": 1.4, "tower": 1.0, "wall": 1.8}
BUNK_HALF = {"can": (0.76, 0.76, 0.8), "dorito": (0.85, 0.8, 0.75), "temple": (1.12, 0.74, 0.8),
             "snake": (3.3, 0.5, 0.5), "brick": (1.3, 0.55, 0.8), "tower": (0.92, 0.92, 1.3), "wall": (1.7, 0.55, 1.25)}


ONPATH = set()


def bunker_list():
    out = []
    for b in BUNKERS:
        kind, x, y, rz = b[:4]
        if len(b) > 4:
            ONPATH.add((kind, x, y))
            ONPATH.add((kind, -x, y))
        out.append((kind, x, y, rz, "W"))
        if abs(x) > 0.01:
            out.append((kind, -x, y, PI - rz if kind != "can" else rz, "E"))
    return out


ALL_BUNKERS = bunker_list()


def bunker_ok(kind, x, y, rz):
    r = BUNK_R[kind]
    hx, hy, _ = BUNK_HALF[kind]
    # sample the bunker's footprint ends for long ones
    pts = [(x, y)]
    if kind == "snake":
        pts += [(x + math.cos(rz) * hx, y + math.sin(rz) * hx), (x - math.cos(rz) * hx, y - math.sin(rz) * hx)]
    rr = 0.7 if kind == "snake" else r
    for p in pts:
        if poly_dist(p, ROAD_IN) < ROAD_HW + rr + 0.5:
            return "road"
        if any(rect_dist(p, q) < rr + 0.6 for q in RECTS):
            return "building"
        if on_paths(p, rr + 0.1) and (kind, x, y) not in ONPATH:
            return "path"
        if abs(p[0]) > HX - rr - 0.8 or abs(p[1]) > HY - rr - 0.8:
            return "wall"
    return None


# ------------------------------------------------------------------ ground

UNDER = (0, 0, 1, 1, "foliage:#3a5a2a")


def build_terrain(crowns):
    far = [270.0, 310.0, 360.0, 420.0, 500.0]              # coarse far-forest ring to the horizon
    xs = [-f for f in reversed(far)] + [-TERR + STEP * i for i in range(int(2 * TERR / STEP) + 1)] + far
    n = len(xs)
    cell = 12.0
    hsh = {}
    for c in crowns:
        hsh.setdefault((int(math.floor(c[0] / cell)), int(math.floor(c[1] / cell))), []).append(c)

    def dome(x, y):
        best, own, fill_h = 0.0, None, 0.0
        gx, gy = int(math.floor(x / cell)), int(math.floor(y / cell))
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for c in hsh.get((gx + i, gy + j), ()):
                    d2 = (x - c[0]) ** 2 + (y - c[1]) ** 2
                    if d2 < c[2] * c[2]:
                        h = c[3] * (1.0 - 0.38 * d2 / (c[2] * c[2]))
                        if h > best:
                            best, own = h, c
                    elif best == 0.0 and d2 < (c[2] + 4.5) ** 2:
                        fill = 8.2 + 1.2 * math.sin(x * 0.37 + c[0]) * math.cos(y * 0.29)
                        if fill > fill_h:
                            fill_h = fill
        if best == 0.0 and fill_h > 0:
            return fill_h, UNDER
        return best, own

    def height(x, y):
        if abs(x) > TERR + 1 or abs(y) > TERR + 1:
            return 11.5 + 1.6 * math.sin(x * 0.05) * math.cos(y * 0.043) + 1.0 * math.sin((x - y) * 0.031)
        return dome(x, y)[0]

    H = [[height(x, y) for x in xs] for y in xs]          # H[j][i]
    verts = []
    for j in range(n):
        for i in range(n):
            verts.append((xs[i], xs[j], H[j][i] if H[j][i] > 0 else 0.0))
    faces, roles = [], []
    for j in range(n - 1):
        for i in range(n - 1):
            a = j * n + i
            faces.append((a, a + 1, a + n + 1, a + n))
            cx, cy = (xs[i] + xs[i + 1]) / 2, (xs[j] + xs[j + 1]) / 2
            if abs(cx) > TERR or abs(cy) > TERR:
                nz = math.sin(cx * 0.009 + 0.7) * math.cos(cy * 0.011 - 0.2)
                roles.append("foliage:#5e6e30" if nz > 0.3 else "foliage:#4c6a2d")
                continue
            h, own = dome(cx, cy)
            if own is not None and max(H[j][i], H[j][i + 1], H[j + 1][i], H[j + 1][i + 1]) > 0:
                roles.append(own[4])
            elif abs(cx) < HX + 1 and abs(cy) < HY + 1:
                roles.append(GRASS)
            else:
                k = (int(cx // 24) * 7 + int(cy // 24) * 13) % 5
                roles.append(GRASS_ROUGH if k else GRASS)
    # skirt + bottom: a closed shell, so the outward-normal pass can't flip the top
    ring = [(0, j) for j in range(n)] + [(i, n - 1) for i in range(1, n)] + \
           [(n - 1, j) for j in range(n - 2, -1, -1)] + [(i, 0) for i in range(n - 2, 0, -1)]
    base = len(verts)
    for (j, i) in ring:
        verts.append((xs[i], xs[j], -4.0))
    m = len(ring)
    for k in range(m):
        j0, i0 = ring[k]
        j1, i1 = ring[(k + 1) % m]
        faces.append((j0 * n + i0, j1 * n + i1, base + (k + 1) % m, base + k))
        roles.append(GRASS_ROUGH)
    faces.append(tuple(range(base + m - 1, base - 1, -1)))
    roles.append(GRASS_ROUGH)
    sm = [r.startswith("foliage") for r in roles]
    G.add(verts, faces, GRASS, face_roles=roles, smooth=sm)


def build_ground_dressing():
    # mowed stripes across the play area
    k = 0
    y = -HY
    while y < HY - 0.1:
        if k % 2 == 0:
            G.box((0, y + 2.5, 0.01), (HX - 0.05, 2.49, 0.012), GRASS_STRIPE)
        y += 5.0
        k += 1
    # road, curbs, centre dashes, crossings
    ribbon(G, ROAD, ROAD_HW, -0.05, 0.05, "asphalt")
    for s in (1, -1):
        ribbon(G, ROAD, 0.15, -0.05, 0.14, "concrete_light", off=s * (ROAD_HW + 0.15))
    for i in range(0, len(ROAD) - 2, 3):
        a, b = ROAD[i], ROAD[i + 1]
        d = (b - a)
        if d.length < 1e-3:
            continue
        rz = math.atan2(d.y, d.x)
        G.box(((a.x + b.x) / 2, (a.y + b.y) / 2, 0.052), (0.9, 0.07, 0.006), "sign_white:#e8c84a", rz=rz)
    for cx in (-22.0, 0.0, 22.0):
        cy = road_y(cx)
        for k in range(-3, 4):
            G.box((cx + k * 0.9, cy, 0.053), (0.3, ROAD_HW - 0.3, 0.006), WHITE)
    ribbon(G, [p for p in offset_pts(ROAD, ROAD_HW + 1.7)], 1.0, -0.04, 0.06, "path_concrete")
    ribbon(G, [p for p in offset_pts(ROAD, -(ROAD_HW + 1.7)) if abs(p.x) > 60], 1.0, -0.04, 0.06, "path_concrete")
    for k, (pts, hw, role) in enumerate(PATHS):
        ribbon(G, pts, hw, -0.04, 0.045 + 0.003 * k, role)
    # chapel forecourt and spawn plazas
    G.box((0, -6.8, 0.0), (8.4, 4.9, 0.06), "path_concrete:#c6c1b6")
    for s in (-1, 1):
        G.box((s * 50.8, 0, 0.0), (3.6, 8.0, 0.065), "path_concrete:#c6c1b6")
        team = BLUE if s < 0 else YELLOW
        for e in (-1, 1):
            G.box((s * 50.8, e * 7.75, 0.0), (3.6, 0.25, 0.075), team)
        G.box((s * 47.45, 0, 0.0), (0.25, 7.5, 0.075), team)


# ------------------------------------------------------------------ buildings

def window(P, M, u, z, w, h, frame_role="window_frame", pane="window_dark", lintel=STONE_L, rich=True):
    P.boxM(M, (u, 0.04, z), (w / 2, 0.05, h / 2), pane)
    if not rich:
        P.boxM(M, (u, 0.02, z), (w / 2 + 0.12, 0.04, h / 2 + 0.12), frame_role)
        return
    b = 0.11
    P.boxM(M, (u - w / 2 - b / 2, 0.07, z), (b / 2, 0.07, h / 2 + b), frame_role)
    P.boxM(M, (u + w / 2 + b / 2, 0.07, z), (b / 2, 0.07, h / 2 + b), frame_role)
    P.boxM(M, (u, 0.07, z + h / 2 + b / 2), (w / 2, 0.07, b / 2), frame_role)
    P.boxM(M, (u, 0.07, z - h / 2 - b / 2), (w / 2, 0.07, b / 2), frame_role)
    P.boxM(M, (u, 0.06, z), (0.035, 0.06, h / 2), frame_role)
    P.boxM(M, (u, 0.06, z + h * 0.12), (w / 2, 0.06, 0.035), frame_role)
    P.boxM(M, (u, 0.11, z - h / 2 - b - 0.05), (w / 2 + 0.22, 0.11, 0.06), STONE_L)
    if lintel:
        P.boxM(M, (u, 0.05, z + h / 2 + b + 0.17), (w / 2 + 0.26, 0.05, 0.17), lintel)


def door(P, M, u, w=1.7, h=2.9, wood="wood_old:#3b2a1e", pediment=True):
    P.boxM(M, (u, 0.05, h / 2), (w / 2, 0.06, h / 2), wood)
    for s in (-1, 1):
        P.boxM(M, (u + s * (w / 2 + 0.12), 0.09, h / 2 + 0.06), (0.12, 0.09, h / 2 + 0.06), "window_frame")
    P.boxM(M, (u, 0.09, h + 0.2), (w / 2 + 0.24, 0.09, 0.14), "window_frame")
    P.boxM(M, (u, 0.05, h - 0.35), (w / 2 - 0.12, 0.08, 0.28), "window_dark")     # fanlight
    if pediment:
        v, f = slab_geo([(u - w / 2 - 0.5, h + 0.34), (u + w / 2 + 0.5, h + 0.34), (u, h + 1.05)], 0.0, 0.2)
        P.add(v, f, "window_frame", M)
    P.boxM(M, (u, 0.55, 0.09), (w / 2 + 0.5, 0.55, 0.09), STONE_L)


def facade(P, M, L, storeys, sh, skip_ground=(), rich=True, win_w=1.25, win_h=2.1, spacing=3.2):
    n = int((L - 2.0) // spacing)
    us = [(-(n - 1) / 2 + k) * spacing for k in range(n)]
    for s in range(storeys):
        for u in us:
            if s == 0 and any(abs(u - q) < 1.6 for q in skip_ground):
                continue
            window(P, M, u, s * sh + 0.4 + sh * 0.5, win_w, win_h, rich=rich)
    return us


def hip_geo(hx, hy, z0, rise, along_x=True):
    if along_x:
        inset = min(hy, hx * 0.9)
        v = [(-hx, -hy, z0), (hx, -hy, z0), (hx, hy, z0), (-hx, hy, z0), (-hx + inset, 0, z0 + rise), (hx - inset, 0, z0 + rise)]
        f = [(0, 1, 5, 4), (2, 3, 4, 5), (1, 2, 5), (3, 0, 4), (3, 2, 1, 0)]
    else:
        inset = min(hx, hy * 0.9)
        v = [(-hx, -hy, z0), (hx, -hy, z0), (hx, hy, z0), (-hx, hy, z0), (0, -hy + inset, z0 + rise), (0, hy - inset, z0 + rise)]
        f = [(1, 2, 5, 4), (3, 0, 4, 5), (0, 1, 4), (2, 3, 5), (3, 2, 1, 0)]
    return v, f


def gable_geo(hx, hy, z0, rise, along_x=True):
    if along_x:
        prof = [(-hy, z0), (hy, z0), (0, z0 + rise)]
        v = [(-hx, a, b) for a, b in prof] + [(hx, a, b) for a, b in prof]
    else:
        prof = [(-hx, z0), (hx, z0), (0, z0 + rise)]
        v = [(a, -hy, b) for a, b in prof] + [(a, hy, b) for a, b in prof]
    f = [(0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5), (2, 1, 0), (3, 4, 5)]
    return v, f


def hall(P, cx, cy, hx, hy, storeys=3, rz=0.0, brick=BRICK, roof="roof_slate", door_faces=("S",),
         cupola=False, rich=True, col=False, hip=True, splats=0):
    sh = 4.0
    H = storeys * sh + 0.4
    Mb = T(cx, cy, 0, rz=rz)
    P.boxM(Mb, (0, 0, 0.4), (hx + 0.12, hy + 0.12, 0.4), STONE)
    P.boxM(Mb, (0, 0, H / 2), (hx, hy, H / 2), brick)
    for s in range(1, storeys):
        P.boxM(Mb, (0, 0, s * sh + 0.4), (hx + 0.05, hy + 0.05, 0.1), STONE_L)
    P.boxM(Mb, (0, 0, H + 0.2), (hx + 0.32, hy + 0.32, 0.22), "window_frame")
    rise = min(hy, hx) * 0.75
    v, f = (hip_geo if hip else gable_geo)(hx + 0.45, hy + 0.45, H + 0.42, rise, along_x=hx >= hy)
    P.add(v, f, roof, Mb)
    for s in (-1, 1):                                   # chimneys
        if hx >= hy:
            P.boxM(Mb, (s * (hx - 1.6), 0, H + rise * 0.7), (0.5, 0.9, rise * 0.55 + 0.6), brick)
        else:
            P.boxM(Mb, (0, s * (hy - 1.6), H + rise * 0.7), (0.9, 0.5, rise * 0.55 + 0.6), brick)
    faces = {"S": ((0, -hy, 0), (1, 0, 0), (0, -1, 0), 2 * hx), "N": ((0, hy, 0), (-1, 0, 0), (0, 1, 0), 2 * hx),
             "E": ((hx, 0, 0), (0, 1, 0), (1, 0, 0), 2 * hy), "W": ((-hx, 0, 0), (0, -1, 0), (-1, 0, 0), 2 * hy)}
    for key, (o, t, n, L) in faces.items():
        M = Mb @ frame(o, t, n)
        if key in door_faces:
            facade(P, M, L, storeys, sh, skip_ground=(0.0,), rich=rich)
            door(P, M, 0.0)
        else:
            facade(P, M, L, storeys, sh, rich=rich)
    if rich:                                           # stone quoins at the corners
        for sx in (-1, 1):
            for sy in (-1, 1):
                for k in range(int((H - 0.8) / 0.62)):
                    z = 0.8 + 0.31 + k * 0.62
                    lx, ly = (0.55, 0.3) if k % 2 == 0 else (0.3, 0.55)
                    P.boxM(Mb, (sx * (hx - lx + 0.04), sy * (hy - 0.3 + 0.04), z), (lx, 0.3, 0.27), STONE_L)
                    P.boxM(Mb, (sx * (hx - 0.3 + 0.04), sy * (hy - ly + 0.04), z), (0.3, ly, 0.27), STONE_L)
    if cupola:
        top = H + 0.42 + rise
        lv, lf = lathe_geo([(1.3, top - 0.6), (1.3, top + 1.6), (1.55, top + 1.6), (1.55, top + 1.85), (0.0, top + 3.6)], 8, PI / 8)
        P.add(lv, lf, "window_frame", Mb)
        lv, lf = lathe_geo([(1.45, top + 1.85), (0.0, top + 3.7)], 8, PI / 8)
        P.add(lv, lf, "roof_copper", Mb)
    if col:
        COL((cx, cy, (H + rise) / 2), (hx + 0.15, hy + 0.15, (H + rise) / 2), rz)
    return H


def lancet_poly(w, h, k=4):
    """A pointed (equilateral Gothic) arch outline, base at 0, total height h."""
    hs = h - 0.866 * w
    pts = [(-w / 2, 0.0), (w / 2, 0.0)]
    for i in range(0, k):
        t = (PI / 3) * i / k
        pts.append((-w / 2 + w * math.cos(t), hs + w * math.sin(t)))
    pts.append((0.0, h))
    for i in range(k - 1, -1, -1):
        t = (PI / 3) * i / k
        pts.append((w / 2 - w * math.cos(t), hs + w * math.sin(t)))
    return pts


def lancet(P, M, u, z, w, h, surround=STONE_L):
    out = [(x * (w + 0.36) / w + u, y * (h + 0.3) / h + z - 0.15) for x, y in lancet_poly(w, h)]
    v, f = slab_geo(out, -0.02, 0.07, )
    P.add(v, f, surround, M)
    v, f = slab_geo([(x + u, y + z) for x, y in lancet_poly(w, h)], 0.0, 0.1)
    P.add(v, f, "window_dark", M)
    P.boxM(M, (u, 0.1, z + h * 0.45), (0.045, 0.06, h * 0.45), surround)
    P.boxM(M, (u, 0.1, z + h * 0.42), (w / 2, 0.06, 0.045), surround)
    P.boxM(M, (u, 0.13, z - 0.2), (w / 2 + 0.3, 0.13, 0.08), surround)


def chapel(P):
    S = CH_STONE
    # nave (along y), x half 6.5, y -3..15, walls 10
    P.box((0, 6, 0.5), (6.75, 9.25, 0.5), CH_TRIM)
    P.box((0, 6, 5.0), (6.5, 9.0, 5.0), S)
    P.box((0, 6, 10.1), (6.8, 9.3, 0.18), CH_TRIM)
    v, f = gable_geo(7.1, 9.6, 10.25, 9.0, along_x=False)
    P.add(v, f, "roof_slate", T(0, 6, 0))
    # transept (along x) at y = 9
    P.box((0, 9, 5.0), (11.0, 3.5, 5.0), S)
    P.box((0, 9, 10.1), (11.3, 3.8, 0.18), CH_TRIM)
    v, f = gable_geo(11.4, 3.9, 10.25, 6.4, along_x=True)
    P.add(v, f, "roof_slate", T(0, 9, 0))
    for s in (-1, 1):
        v, f = slab_geo([(-3.5, 10.25), (3.5, 10.25), (0, 16.4)], 0.0, 0.25)       # transept gable walls
        P.add(v, f, S, frame((s * 11.0, 9, 0), (0, -s, 0), (s, 0, 0)))
    # apse / chancel at the north end
    P.box((0, 17.25, 4.0), (4.5, 2.25, 4.0), S)
    v, f = gable_geo(4.8, 2.5, 8.1, 4.8, along_x=False)
    P.add(v, f, "roof_slate", T(0, 17.25, 0))
    v, f = slab_geo([(-6.5, 10.25), (6.5, 10.25), (0, 19.2)], 0.0, 0.25)            # nave north gable
    P.add(v, f, S, frame((0, 15.0, 0), (-1, 0, 0), (0, 1, 0)))
    # buttresses + lancets on the nave long faces
    for s in (-1, 1):
        Mf = frame((s * 6.5, 0, 0), (0, -s, 0), (s, 0, 0))
        for y in (-2.6, 1.0, 4.6, 13.4):
            u = -s * y
            P.boxM(Mf, (u, 0.8, 2.2), (0.5, 0.8, 2.2), CH_TRIM)
            P.boxM(Mf, (u, 0.5, 5.0), (0.42, 0.5, 5.0), CH_TRIM)
            v, f = slab_geo([(u - 0.4, 7.2), (u + 0.4, 7.2), (u + 0.4, 7.4), (u - 0.4, 8.6)], 0.0, 0.5)
            P.add(v, f, CH_TRIM, Mf)
        for y in (-0.8, 2.8, 14.3):
            if y > 14:
                continue
            lancet(P, Mf, -s * y, 2.4, 1.3, 5.2, CH_TRIM)
        Mt = frame((s * 11.0, 9, 0), (0, -s, 0), (s, 0, 0))
        lancet(P, Mt, 0.0, 2.6, 2.2, 6.4, CH_TRIM)
        v, f = lathe_geo([(0.0, 0.0), (0.9, 0.0), (0.9, 0.12), (0.0, 0.12)], 12)
        P.add(v, f, "window_dark", Mt @ T(0, 0.05, 13.0, rx=-PI / 2))
        v, f = lathe_geo([(0.0, 0.0), (1.15, 0.0), (1.15, 0.07), (0.0, 0.07)], 12)
        P.add(v, f, CH_TRIM, Mt @ T(0, 0.0, 13.0, rx=-PI / 2))
        door(P, Mt, -2.6 if s < 0 else 2.6, w=1.5, h=2.8, pediment=False)
        Ma = frame((s * 4.5, 17.25, 0), (0, -s, 0), (s, 0, 0))
        lancet(P, Ma, 0.0, 2.2, 1.1, 4.2, CH_TRIM)
    lancet(P, frame((0, 19.5, 0), (-1, 0, 0), (0, 1, 0)), 0.0, 2.4, 1.6, 4.6, CH_TRIM)
    # tower at the south end: (0, -5.5), half 3.6, body to 23
    tx, ty, th = 0.0, -5.5, 26.0
    P.box((tx, ty, 0.5), (3.9, 3.9, 0.5), CH_TRIM)
    P.box((tx, ty, th / 2), (3.6, 3.6, th / 2), S)
    for z in (8.0, 17.6, th):
        P.box((tx, ty, z), (3.75, 3.75, 0.16), CH_TRIM)
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.box((tx + sx * 3.55, ty + sy * 3.55, th / 2 - 0.5), (0.55, 0.55, th / 2 - 0.5), CH_TRIM)
    # belfry louvres on all four faces
    for (o, t, n) in (((tx, ty - 3.6, 0), (1, 0, 0), (0, -1, 0)), ((tx, ty + 3.6, 0), (-1, 0, 0), (0, 1, 0)),
                      ((tx + 3.6, ty, 0), (0, 1, 0), (1, 0, 0)), ((tx - 3.6, ty, 0), (0, -1, 0), (-1, 0, 0))):
        Mf = frame(o, t, n)
        for u in (-1.0, 1.0):
            lancet(P, Mf, u, 19.5, 1.0, 4.2, CH_TRIM)
        v, f = lathe_geo([(0.0, 0.0), (1.1, 0.0), (1.1, 0.12), (0.0, 0.12)], 16)
        P.add(v, f, "window_frame", Mf @ T(0, 0.02, 15.2, rx=-PI / 2))
        P.boxM(Mf, (0.0, 0.16, 15.45), (0.05, 0.03, 0.55), "iron_dark")
        P.boxM(Mf, (0.3, 0.17, 15.2), (0.38, 0.03, 0.05), "iron_dark")
        lancet(P, Mf, 0.0, 9.6, 1.0, 3.6, CH_TRIM)
    # crenellated parapet + corner pinnacles
    P.box((tx, ty, th + 0.45), (3.75, 3.75, 0.45), S)
    for side in range(4):
        for k in range(-2, 3):
            a = k * 1.45
            pos = [(tx + a, ty - 3.55), (tx + a, ty + 3.55), (tx - 3.55, ty + a), (tx + 3.55, ty + a)][side]
            if abs(k) == 2:
                continue
            P.box((pos[0], pos[1], th + 1.35), (0.42 if side < 2 else 0.22, 0.22 if side < 2 else 0.42, 0.45), S)
    for sx in (-1, 1):
        for sy in (-1, 1):
            px, py = tx + sx * 3.45, ty + sy * 3.45
            P.box((px, py, th + 1.3), (0.6, 0.6, 1.3), CH_TRIM)
            v, f = lathe_geo([(0.62, th + 2.6), (0.0, th + 6.2)], 4, PI / 4)
            P.add(v, f, S, T(px, py, 0))
    v, f = lathe_geo([(2.6, th + 0.9), (0.0, th + 7.6)], 4, PI / 4)          # low central spire
    P.add(v, f, "roof_slate", T(tx, ty, 0))
    # south door (pointed arch) with steps
    Ms = frame((tx, ty - 3.6, 0), (1, 0, 0), (0, -1, 0))
    v, f = slab_geo([(x * 1.25, y * 1.1 + 0.2) for x, y in lancet_poly(2.4, 3.8)], -0.02, 0.1)
    P.add(v, f, CH_TRIM, Ms)
    v, f = slab_geo([(x, y + 0.25) for x, y in lancet_poly(2.2, 3.7)], 0.0, 0.13)
    P.add(v, f, "wood_old:#3b2a1e", Ms)
    P.boxM(Ms, (0, 0.7, 0.12), (2.0, 0.7, 0.12), CH_TRIM)
    lancet(P, Ms, 0.0, 5.0, 1.4, 2.6, CH_TRIM)
    # stone coursing: thin joint bands that read as ashlar from eye level
    for z in (2.15, 7.7):
        P.box((0, 6, z), (6.53, 9.03, 0.025), CH_JOINT)
        P.box((0, 9, z), (11.03, 3.53, 0.025), CH_JOINT)
        P.box((0, 17.25, z), (4.53, 2.28, 0.025), CH_JOINT) if z < 7.8 else None
    for z in (4.0, 12.0, 17.5):
        P.box((tx, ty, z), (3.63, 3.63, 0.025), CH_JOINT)
    # colliders: nave+apse, transept, tower
    COL((0, 7.6, 7.0), (6.9, 11.0, 7.0))
    COL((0, 9, 6.5), (11.2, 3.6, 6.5))
    COL((tx, ty, 14.5), (4.1, 4.1, 14.5))


def round_building(P, cx, cy):
    M = T(cx, cy, 0)
    v, f = lathe_geo([(15.5, 0.0), (15.5, 0.6), (14.0, 0.6), (14.0, 0.0)], 32)
    P.add(v, f, "concrete_light", M)
    v, f = lathe_geo([(13.6, 0.0), (13.6, 3.6)], 32)
    P.add(v, f, "window_dark", M)
    for i in range(32):
        a = 2 * PI * i / 32
        P.box((cx + 13.75 * math.cos(a), cy + 13.75 * math.sin(a), 1.8), (0.08, 0.12, 1.8), "window_frame", rz=a)
    v, f = lathe_geo([(15.2, 3.6), (15.2, 4.3), (11.2, 4.3)], 32)
    P.add(v, f, "concrete_light", M)
    v, f = lathe_geo([(10.6, 4.2), (10.6, 7.2)], 24)
    P.add(v, f, "window_dark", M)
    for i in range(24):
        a = 2 * PI * i / 24
        P.box((cx + 10.72 * math.cos(a), cy + 10.72 * math.sin(a), 5.7), (0.07, 0.12, 1.5), "window_frame", rz=a)
    v, f = lathe_geo([(12.0, 7.2), (12.0, 7.6), (3.0, 9.4), (0.0, 9.6)], 24)
    P.add(v, f, "concrete_light:#d7d6d2", M)
    for i in range(12):
        a = 2 * PI * i / 12
        P.box((cx + 7.6 * math.cos(a), cy + 7.6 * math.sin(a), 8.55), (4.3, 0.14, 0.12), "window_frame", rz=a)
    v, f = lathe_geo([(2.6, 9.3), (2.6, 10.6), (0.0, 11.0)], 12)
    P.add(v, f, "window_dark", M)
    # a brick wing behind it
    hall(P, cx - 22, cy + 18, 12, 6, storeys=2, rz=0.4, rich=False, door_faces=())


def house(P, cx, cy, rz, rng):
    hx, hy = rng.uniform(5, 7), rng.uniform(4, 5.5)
    wall = rng.choice(["plaster_white", "brick_tan", "plaster_white:#e8e2d4", BRICK])
    Mb = T(cx, cy, 0, rz=rz)
    P.boxM(Mb, (0, 0, 3.2), (hx, hy, 3.2), wall)
    v, f = hip_geo(hx + 0.6, hy + 0.6, 6.4, 3.0, along_x=True)
    P.add(v, f, rng.choice(["roof_slate", "roof_slate:#4a4e55", "roof_slate:#6a5a4e"]), Mb)
    for key, (o, t, n, L) in {"S": ((0, -hy, 0), (1, 0, 0), (0, -1, 0), 2 * hx), "N": ((0, hy, 0), (-1, 0, 0), (0, 1, 0), 2 * hx)}.items():
        facade(P, Mb @ frame(o, t, n), L, 2, 3.0, rich=False, win_h=1.5, win_w=1.0, spacing=2.8)


# ------------------------------------------------------------------ trees and bushes

def canopy_style(rng):
    """A few blob clusters (offsets, radii) reused by many trees."""
    n = rng.randint(4, 6)
    out = []
    for k in range(n):
        a = rng.uniform(0, 2 * PI)
        d = rng.uniform(0.2, 1.0) if k else 0.0
        out.append((math.cos(a) * d, math.sin(a) * d, rng.uniform(-0.25, 0.35), rng.uniform(0.6, 0.9)))
    return out


FOLIAGE_IN = ["foliage", "foliage_gold", "foliage:#3d6a25", "foliage_autumn", "foliage:#6f8c2c", "foliage_red",
              "foliage", "foliage_gold:#e2bb34", "foliage:#3d6a25", "foliage_autumn:#dc8f2c"]
STYLES = [canopy_style(random.Random(1234 + 17 * i)) for i in range(6)]


def tree(P, x, y, rng, height=None, crown=None, role=None, blobs=None, sub=1, trunk_r=None, mx=1.0):
    h = height or rng.uniform(10.5, 15.0)
    cr = crown or rng.uniform(3.4, 4.8)
    tr = trunk_r or rng.uniform(0.24, 0.4)
    role = role or pick(rng, FOLIAGE)
    role2 = pick(rng, FOLIAGE) if rng.random() < 0.35 else role
    base = max(4.0, h - 2.0 * cr * 0.95)
    v, f = cyl_geo(tr * 1.25, tr * 0.6, base + cr * 0.8, 6)
    P.add(v, f, "bark", T(x, y, 0, rz=rng.uniform(0, PI)))
    # two branch stubs into the crown
    for k in range(2):
        a = rng.uniform(0, 2 * PI)
        v, f = cyl_geo(tr * 0.45, tr * 0.25, cr * 0.9, 5)
        P.add(v, f, "bark", T(x, y, base - 0.3, rz=a, ry=0.75))
    style = STYLES[rng.randrange(len(STYLES))]
    cz = base + cr * 0.95
    rz = rng.uniform(0, 2 * PI)
    for k, (ox, oy, oz, rr) in enumerate(style[:blobs] if blobs else style):
        ca, sa = math.cos(rz), math.sin(rz)
        px, py = x + mx * (ox * ca - oy * sa) * cr, y + (ox * sa + oy * ca) * cr
        r = rr * cr
        blob(P, (px, py, cz + oz * cr), (r, r, r * 0.82), role if k % 3 != 2 else role2, rng, sub=sub)
    return base, tr


def cyl_geo(r0, r1, h, n):
    return lathe_geo([(r0, 0.0), (r1, h)], n)


def conifer(P, x, y, rng):
    h = rng.uniform(9, 13)
    v, f = cyl_geo(0.3, 0.15, h * 0.4, 6)
    P.add(v, f, "bark", T(x, y, 0))
    for k in range(3):
        z = h * (0.25 + 0.22 * k)
        r = (3.0 - 0.75 * k) * rng.uniform(0.9, 1.1)
        v, f = lathe_geo([(r, z), (0.0, z + h * 0.42)], 8)
        P.add(v, f, "foliage:#2d4a26", T(x, y, 0, rz=rng.uniform(0, PI)))


BUSH_ROLES = [("hedge", 5), ("foliage", 4), ("foliage:#557a2c", 3), ("foliage_red", 2),
              ("foliage_autumn", 1), ("foliage_gold:#b9a23a", 1)]


def bush(P, x, y, rng, role=None, rz=None, length=None):
    """A walk-through bush clump (or a hedge run when `length` is given). Returns HIDE box."""
    role = role or pick(rng, [("hedge", 5), ("foliage", 4), ("foliage:#557a2c", 3), ("foliage_red", 2),
                              ("foliage_autumn", 1), ("foliage_gold:#b9a23a", 1)])
    h = rng.uniform(1.45, 1.8)
    rz = rng.uniform(0, PI) if rz is None else rz
    if length:
        n = max(2, int(length / 1.3))
        hw = 0.65
        for k in range(n):
            u = (-(n - 1) / 2 + k) * (length / n)
            r = (length / n) * 0.75
            blob(P, (x + math.cos(rz) * u, y + math.sin(rz) * u, h * 0.52), (r, hw, h * 0.5), role, rng, rz=rz, jit=0.1)
        HIDE((x, y, h / 2), (length / 2, hw * 0.95, h / 2), rz)
        return (x, y, length / 2 + 0.3)
    k = rng.randint(4, 5)                                  # loose puffs with gaps: reads as see-into
    rad = rng.uniform(1.2, 1.7)
    for i in range(k):
        a = rz + 2 * PI * i / k + rng.uniform(-0.3, 0.3)
        d = rad * rng.uniform(0.5, 0.68)
        r = rad * rng.uniform(0.36, 0.48)
        rzz = h - r * 0.9 - rng.uniform(0.0, 0.35)
        blob(P, (x + math.cos(a) * d, y + math.sin(a) * d, rzz), (r, r, r * 1.25), role, rng, jit=0.16)
    blob(P, (x, y, h * 0.42), (rad * 0.42, rad * 0.42, h * 0.42), role, rng, jit=0.16)
    HIDE((x, y, h / 2), (rad * 0.95, rad * 0.95, h / 2), rz)
    return (x, y, rad)


# ------------------------------------------------------------------ bunkers

def bevel_geo(v, f, off, segs=2):
    """Round every edge of a closed shape (the inflatable look)."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in v]
    for q in f:
        bm.faces.new([vs[k] for k in q])
    bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=off, segments=segs, affect="EDGES", profile=0.5)
    bm.verts.index_update()
    out = ([tuple(x.co) for x in bm.verts], [tuple(x.index for x in fa.verts) for fa in bm.faces])
    bm.free()
    return out


def bunker(P, kind, x, y, rz, col, accent):
    M = T(x, y, 0, rz=rz)
    if kind == "can":
        v, f = lathe_geo([(0.0, 0.0), (0.74, 0.0), (0.78, 0.15), (0.78, 1.3), (0.66, 1.5), (0.36, 1.58), (0.0, 1.6)], 16)
        P.add(v, f, col, M, smooth=True)
        v, f = lathe_geo([(0.79, 0.62), (0.80, 0.7), (0.79, 0.78)], 16)
        P.add(v, f, accent, M, smooth=True)
    elif kind == "dorito":
        tri = [(1.15 * math.cos(a), 1.15 * math.sin(a)) for a in (PI / 2, PI / 2 + 2 * PI / 3, PI / 2 + 4 * PI / 3)]
        v, f = bevel_geo(*prism_geo(tri, 0.0, 1.5, top_scale=0.38), 0.18)
        P.add(v, f, col, M, smooth=True)
        v, f = prism_geo(tri, 0.6, 0.76, top_scale=1.0)
        P.add([(a * 0.79, b * 0.79, c) for a, b, c in v], f, accent, M)
    elif kind == "temple":
        v, f = box_geo(1.15, 0.75, 0.8)
        v = [(a * (0.62 if c > 0 else 1.0), b * (0.75 if c > 0 else 1.0), c + 0.8) for a, b, c in v]
        v, f = bevel_geo(v, f, 0.22)
        P.add(v, f, col, M, smooth=True)
        P.boxM(M, (0, 0, 0.34), (1.1, 0.72, 0.07), accent)
    elif kind == "snake":
        L = 6.0
        v, f = lathe_geo([(0.0, -L / 2 - 0.4), (0.3, -L / 2 - 0.3), (0.48, -L / 2), (0.48, L / 2), (0.3, L / 2 + 0.3), (0.0, L / 2 + 0.4)], 14)
        P.add(v, f, col, M @ T(0, 0, 0.48, ry=PI / 2), smooth=True)
        for k in range(5):
            u = -L / 2 + 0.6 + k * (L - 1.2) / 4
            v, f = lathe_geo([(0.5, u - 0.12), (0.53, u), (0.5, u + 0.12)], 14)
            P.add(v, f, accent, M @ T(0, 0, 0.48, ry=PI / 2), smooth=True)
    elif kind == "tower":
        v, f = lathe_geo([(0.0, 0.0), (0.92, 0.0), (0.96, 0.2), (0.96, 2.2), (0.8, 2.5), (0.42, 2.6), (0.0, 2.62)], 16)
        P.add(v, f, col, M, smooth=True)
        for z in (0.8, 1.7):
            v, f = lathe_geo([(0.97, z - 0.09), (0.99, z), (0.97, z + 0.09)], 16)
            P.add(v, f, accent, M, smooth=True)
    elif kind == "wall":
        v, f = bevel_geo(*box_geo(1.7, 0.55, 1.25), 0.3)
        P.add([(a, b, c + 1.25) for a, b, c in v], f, col, M, smooth=True)
        P.boxM(M, (0, 0, 1.9), (1.62, 0.56, 0.09), accent)
    elif kind == "brick":
        v, f = bevel_geo(*box_geo(1.3, 0.55, 0.8), 0.25)
        P.add([(a, b, c + 0.8) for a, b, c in v], f, col, M, smooth=True)
        P.boxM(M, (0, 0, 1.15), (1.24, 0.56, 0.08), accent)
    hx, hy, hz = BUNK_HALF[kind]
    COL((x, y, hz), (hx, hy, hz), rz)


# ------------------------------------------------------------------ props

def splat(P, M, u, w, size, role, rng):
    pts = []
    n = 14
    for i in range(n):
        a = 2 * PI * i / n
        r = size * (rng.uniform(0.55, 0.8) if i % 2 else rng.uniform(0.9, 1.35))
        pts.append((u + math.cos(a) * r, w + math.sin(a) * r * 0.9))
    v, f = slab_geo(pts, 0.0, 0.03)
    P.add(v, f, role, M)
    for k in range(rng.randint(1, 3)):                     # drips
        du = rng.uniform(-size * 0.6, size * 0.6)
        ln = rng.uniform(0.3, 0.9) * size
        P.boxM(M, (u + du, 0.015, w - size * 0.5 - ln / 2), (0.05, 0.015, ln / 2), role)


def bench(P, x, y, rz):
    M = T(x, y, 0, rz=rz)
    for k in range(3):
        P.boxM(M, (0, -0.18 + k * 0.18, 0.46), (0.9, 0.07, 0.03), "wood_old")
    P.boxM(M, (0, 0.27, 0.78), (0.9, 0.04, 0.12), "wood_old")
    for s in (-1, 1):
        P.boxM(M, (s * 0.78, 0, 0.23), (0.04, 0.25, 0.23), "iron_dark")
        P.boxM(M, (s * 0.78, 0.27, 0.6), (0.04, 0.03, 0.3), "iron_dark")
    COL((x, y, 0.45), (0.92, 0.32, 0.45), rz)


def lamp(P, x, y):
    v, f = cyl_geo(0.09, 0.06, 4.2, 6)
    P.add(v, f, "iron_dark", T(x, y, 0))
    P.box((x, y, 0.25), (0.16, 0.16, 0.25), "iron_dark")
    v, f = lathe_geo([(0.14, 4.1), (0.26, 4.25), (0.26, 4.65), (0.32, 4.7), (0.0, 4.95)], 6)
    P.add(v, f, "window_frame:#f4e8c0", T(x, y, 0))
    COL((x, y, 2.2), (0.12, 0.12, 2.2))


def boundary(P):
    segs = [((-HX, -HY), (HX, -HY)), ((HX, -HY), (HX, HY)), ((HX, HY), (-HX, HY)), ((-HX, HY), (-HX, -HY))]
    for (x0, y0), (x1, y1) in segs:
        a, b = Vector((x0, y0)), Vector((x1, y1))
        d = b - a
        L = d.length
        t = d / L
        rz = math.atan2(t.y, t.x)
        mid = (a + b) / 2
        P.box((mid.x, mid.y, 0.5), (L / 2 + 0.3, 0.3, 0.5), STONE, rz=rz)
        P.box((mid.x, mid.y, 1.04), (L / 2 + 0.38, 0.38, 0.06), STONE_L, rz=rz)
        COL((mid.x, mid.y, 3.0), (L / 2 + 0.3, 0.35, 3.0), rz)
        # net posts + the net lattice (1.1 .. 4.4 m)
        np_ = int(L / 5.5)
        for k in range(np_ + 1):
            p = a + t * (L * k / np_)
            P.box((p.x, p.y, 2.75), (0.07, 0.07, 1.7), "wood_pole")
        for z in (1.15, 2.25, 3.35, 4.4):
            P.box((mid.x, mid.y, z), (L / 2, 0.02, 0.02), "net", rz=rz)
        nv = int(L / 0.9)
        for k in range(nv):
            p = a + t * (L * (k + 0.5) / nv)
            P.box((p.x, p.y, 2.77), (0.012, 0.012, 1.63), "net", rz=rz)
    # gate pillars where the road meets the wall
    for s in (-1, 1):
        yc = road_y(s * HX)
        for e in (-1, 1):
            P.box((s * HX, yc + e * (ROAD_HW + 0.8), 1.3), (0.5, 0.5, 1.3), STONE_L)
            v, f = lathe_geo([(0.4, 2.6), (0.0, 3.1)], 4, PI / 4)
            P.add(v, f, STONE, T(s * HX, yc + e * (ROAD_HW + 0.8), 0))


def flag(P, x, y, role):
    v, f = cyl_geo(0.06, 0.04, 7.0, 6)
    P.add(v, f, "steel", T(x, y, 0))
    P.box((x, y + 0.9, 6.3), (0.02, 0.85, 0.55), role)
    COL((x, y, 3.5), (0.08, 0.08, 3.5))


# ------------------------------------------------------------------ build

def main():
    gg.reset()
    rng = R
    stats = {}

    # ---- buildings (inner)
    hall(B, -27, HALL_Y, 10, 5, storeys=3, door_faces=("S",), col=True, brick="brick_red:#86432f")
    hall(B, 27, HALL_Y, 10, 5, storeys=3, door_faces=("S",), col=True, cupola=True, brick="brick_red:#93503b")
    for s in (-1, 1):
        hall(B, s * 33, 12, 4, 3.2, storeys=1, door_faces=("E" if s < 0 else "W",), col=True, hip=False)
    hall(B, 0, -31, 8, 4.5, storeys=2, door_faces=("N",), col=True, rz=0.0, brick="brick_red:#7a3d2e")
    chapel(B)

    # ---- bunkers
    bad = []
    for kind, x, y, rz, side in ALL_BUNKERS:
        why = bunker_ok(kind, x, y, rz)
        if why:
            bad.append((kind, x, y, why))
            continue
        if abs(x) < 0.01:
            col, acc = RED, WHITE
        else:
            k = (int(abs(x)) + int(abs(y))) % 3
            col = [BLUE, YELLOW, BLUE][k] if side == "W" else [YELLOW, BLUE, YELLOW][k]
            acc = WHITE if k != 1 else RED
        bunker(BK, kind, x, y, rz, col, acc)
    if bad:
        print("campus: REJECTED bunkers", bad)
    stats["bunkers"] = len(ALL_BUNKERS) - len(bad)

    # ---- inner trees (west half generated, mirrored)
    trees = []
    bunk_pts = [(x, y, BUNK_R[k]) for k, x, y, rz, s in ALL_BUNKERS]

    def tree_ok(x, y, mind=8.0):
        if abs(x) > HX - 2.5 or abs(y) > HY - 2.5 or x > -3.5:
            return False
        if poly_dist((x, y), ROAD_IN) < ROAD_HW + 1.6:
            return False
        if any(rect_dist((x, y), q) < 1.6 for q in RECTS):
            return False
        if on_paths((x, y), 0.8):
            return False
        if any(math.hypot(x - bx, y - by) < br + 2.2 for bx, by, br in bunk_pts):
            return False
        if any(math.hypot(x - sx, y - sy) < 8.5 for sx, sy in SPAWNS_A):
            return False
        if any(math.hypot(x - tx, y - ty) < mind for tx, ty in trees):
            return False
        return True

    for x in (-47.0, -36.0, -27.0, -15.0, -6.5):              # road avenue, north side
        y = road_y(x) + ROAD_HW + 3.6
        if tree_ok(x, y, 6.0):
            trees.append((x, y))
    for x in (-44.0, -31.0, -18.0):                            # south side
        y = road_y(x) - ROAD_HW - 3.4
        if tree_ok(x, y, 6.0):
            trees.append((x, y))
    tries = 0
    while len(trees) < 16 and tries < 4000:
        tries += 1
        x, y = rng.uniform(-HX + 2.5, -4.0), rng.uniform(-HY + 2.5, HY - 2.5)
        if tree_ok(x, y):
            trees.append((x, y))
    crng = random.Random(4321)
    for ti, (x, y) in enumerate(trees):
        con = False                                       # no pines in the field: their skirts block at eye level
        for sx in (1, -1):
            px = x * sx
            trng = random.Random(1000 + ti)
            if con:
                conifer(TR, px, y, trng)
                COL((px, y, 2.0), (0.3, 0.3, 2.0))
            else:
                base, tr = tree(TR, px, y, trng, role=FOLIAGE_IN[ti % len(FOLIAGE_IN)],
                                height=trng.uniform(10.0, 16.5), crown=trng.uniform(3.0, 5.2), mx=sx)
                COL((px, y, 2.0), (tr * 0.95, tr * 0.95, 2.0))
    stats["inner_trees"] = 2 * len(trees)

    # ---- bushes (west half generated, mirrored with a different look)
    bushes = []

    def bush_ok(x, y, r):
        if x > -2.4 - r or abs(x) > HX - 1.0 - r or abs(y) > HY - 1.0 - r:
            return False
        if poly_dist((x, y), ROAD_IN) < ROAD_HW + 0.8 + r:
            return False
        if any(rect_dist((x, y), q) < r + 0.7 for q in RECTS):
            return False
        if on_paths((x, y), r + 0.15):
            return False
        if any(math.hypot(x - bx, y - by) < br + r + 1.1 for bx, by, br in bunk_pts):
            return False
        if any(math.hypot(x - tx, y - ty) < r + 0.7 for tx, ty in trees):
            return False
        if any(math.hypot(x - sx, y - sy) < r + 6.5 for sx, sy in SPAWNS_A) or (x < -45 and abs(y) < 7.5):
            return False
        if any(math.hypot(x - bx, y - by) < r + br + 1.2 for bx, by, br in bushes):
            return False
        for cx, cy in EYE_CLEAR:
            if math.hypot(x - cx, y - cy) < r + 2.5:
                return False
        return True

    # hedges in front of the north halls (with gaps at the doors) and along the back wall
    hedges = []
    for x0 in (-34.5, -19.5):
        hedges.append((x0, HALL_Y - 5.0 - 1.15, 0.0, 6.0))
    for x0 in (-46.0, -6.5):
        hedges.append((x0, -37.5, 0.0, 6.0))
    brng_w, brng_e = random.Random(77), random.Random(78)
    for (x, y, rz, L) in hedges:
        bushes.append(bush(BU, x, y, brng_w, role="hedge", rz=rz, length=L))
        bush(BU, -x, y, brng_e, role="hedge:#46652e", rz=rz, length=L)
    tries = 0
    while len(bushes) < 50 and tries < 8000:
        tries += 1
        x, y = rng.uniform(-HX + 2, -3.0), rng.uniform(-HY + 2, HY - 2)
        r = 1.5
        if bush_ok(x, y, r):
            role = pick(brng_w, BUSH_ROLES)
            bushes.append(bush(BU, x, y, random.Random(3000 + len(bushes)), role=role))
            bush(BU, -x, y, random.Random(3000 + len(bushes) - 1), role=pick(brng_e, BUSH_ROLES))
    stats["bushes"] = 2 * len(bushes)

    # ---- props
    boundary(PR)
    for p in ((-40.0, 26.0, 0.0), (-24.0, 26.0, 0.0), (-6.0, -11.8, 0.0), (-14.0, -21.6, PI)):
        for s in (1, -1):
            x, y, rz = p
            bench(PR, s * x, y, rz)
    for x in (-50, -32, -20, -10):
        for s in (1, -1):
            lamp(PR, s * x, road_y(x) + ROAD_HW + 0.7)
    for x in (-50.0, -12.0):
        for s in (1, -1):
            lamp(PR, s * x, 22.2)
    flag(PR, -53.5, 9.0, BLUE)
    flag(PR, 53.5, -9.0, YELLOW)
    for s, role in ((-1, BLUE), (1, YELLOW)):
        for sx, sy in (SPAWNS_A if s < 0 else SPAWNS_B):
            v, f = lathe_geo([(0.0, 0.0), (0.85, 0.0), (0.85, 0.09), (0.0, 0.09)], 16)
            PR.add(v, f, role, T(sx, sy, 0))
    srng = random.Random(99)
    walls = [((-27, HALL_Y - 5, 0), (1, 0, 0), (0, -1, 0), 9), ((27, HALL_Y - 5, 0), (1, 0, 0), (0, -1, 0), 9),
             ((-29.0, 12, 0), (0, 1, 0), (1, 0, 0), 2.5), ((29.0, 12, 0), (0, -1, 0), (-1, 0, 0), 2.5),
             ((-6.5, 6, 0), (0, 1, 0), (-1, 0, 0), 8), ((6.5, 6, 0), (0, -1, 0), (1, 0, 0), 8),
             ((0, -26.5, 0), (-1, 0, 0), (0, 1, 0), 7), ((-3.6, -5.5, 0), (0, 1, 0), (-1, 0, 0), 3),
             ((3.6, -5.5, 0), (0, -1, 0), (1, 0, 0), 3)]
    splat_cols = ["paint_splat", "paint_splat:#2a8ae0", "paint_splat:#f0c020", "paint_splat:#ff6a1a", "paint_splat:#40d060"]
    for o, t, n, L in walls:
        M = frame(o, t, n) @ T(0, 0.12, 0)
        for k in range(srng.randint(2, 3)):
            splat(PR, M, srng.uniform(-L, L), srng.uniform(0.7, 2.6), srng.uniform(0.25, 0.5), srng.choice(splat_cols), srng)

    # ---- backdrop: outer buildings, clearings, near-ring trees, the canopy blanket
    clear = []      # rects (cx, cy, hx, hy) kept free of crowns / ring trees
    orng = random.Random(555)
    OUT = [(-100, 15, 7, 18, 3), (-38, 78, 22, 8, 3), (28, 84, 16, 7, 4), (96, 48, 7, 14, 3),
           (60, 140, 26, 9, 4), (-72, 128, 18, 8, 3), (-150, 95, 14, 7, 3), (150, 120, 8, 16, 3), (-20, -95, 16, 7, 3)]
    for cx, cy, hx, hy, st in OUT:
        hall(B, cx, cy, hx, hy, storeys=st, rich=False, door_faces=("S",), cupola=(st == 4 and cx < 40),
             brick=orng.choice(["brick_red", "brick_red:#7e3f30", "brick_red:#965540", "brick_red:#8c4a36"]),
             roof=orng.choice(["roof_slate", "roof_slate:#4c5158", "roof_slate:#666a70"]))
        clear.append((cx, cy, hx + 5, hy + 5))
    round_building(B, -88, -62)
    clear.append((-96, -55, 30, 26))
    for (x, y) in ((118, -8), (136, 30), (152, -56), (104, -112), (-160, 40), (176, 70), (60, -118), (-150, -120), (190, -20), (-200, 150)):
        house(B, x, y, orng.uniform(-0.4, 0.4), orng)
        clear.append((x, y, 16, 14))
    # sports field + dome to the north
    G.box((-20, 190, 0.0), (52, 33, 0.05), "grass:#4f9a3a")
    for k in range(-5, 6):
        G.box((-20 + k * 9.0, 190, 0.06), (0.12, 30, 0.01), WHITE)
    G.box((-20, 220, 0.06), (50, 0.12, 0.01), WHITE)
    G.box((-20, 160, 0.06), (50, 0.12, 0.01), WHITE)
    clear.append((-20, 190, 62, 43))
    v, f = lathe_geo([(26, 0.0), (26, 3.0), (20, 9.5), (11, 13.5), (0, 15)], 24)
    B.add(v, f, "concrete_light:#c9cbcf", T(70, 205, 0))
    clear.append((70, 205, 36, 36))
    # parking lots by the halls
    for (x, y, hx, hy) in ((-38, 58, 16, 6), (60, 115, 18, 7)):
        G.box((x, y, 0.0), (hx, hy, 0.05), "asphalt:#55585a")
        for k in range(int(hx)):
            G.box((x - hx + 1 + 2 * k * 1.25, y, 0.055), (0.05, hy * 0.7, 0.008), WHITE)
        clear.append((x, y, hx + 6, hy + 6))

    def outer_free(x, y, extra):
        if poly_dist((x, y), ROAD) < ROAD_HW + extra:
            return False
        return not any(rect_dist((x, y), q) < extra * 0.3 for q in clear)

    ring = []
    rr = random.Random(2024)
    for row, off in enumerate((4.5, 10.5)):
        L = 2 * (2 * (HX + off) + 2 * (HY + off))
        n = int(L / 7.0)
        for k in range(n):
            s = (k + 0.5 * row) / n * L
            w2, h2 = 2 * (HX + off), 2 * (HY + off)
            if s < w2:
                x, y = -HX - off + s, -HY - off
            elif s < w2 + h2:
                x, y = HX + off, -HY - off + (s - w2)
            elif s < 2 * w2 + h2:
                x, y = HX + off - (s - w2 - h2), HY + off
            else:
                x, y = -HX - off, HY + off - (s - 2 * w2 - h2)
            x += rr.uniform(-1.8, 1.8)
            y += rr.uniform(-1.8, 1.8)
            if outer_free(x, y, 6.0):
                ring.append((x, y))
    for (x, y) in ring:
        if rr.random() < 0.12:
            conifer(TR, x, y, rr)
        else:
            tree(TR, x, y, rr, blobs=3, height=rr.uniform(11, 16), crown=rr.uniform(3.8, 5.2))
    stats["ring_trees"] = len(ring)

    crowns = []
    cr = random.Random(31337)
    g = 8.4
    n = int(2 * TERR / g)
    for i in range(n):
        for j in range(n):
            x = -TERR + (i + 0.5) * g + cr.uniform(-3.2, 3.2)
            y = -TERR + (j + 0.5) * g + cr.uniform(-3.2, 3.2)
            r = cr.uniform(3.8, 8.6)
            top = cr.uniform(10.0, 15.5)
            nz = math.sin(x * 0.021 + 1.3) * math.cos(y * 0.017 - 0.4) + 0.5 * math.sin((x + y) * 0.033)
            role = pick(cr, FOLIAGE_WARM if nz > 0.35 else FOLIAGE_GREEN)
            if abs(x) < HX + 15 + r and abs(y) < HY + 15 + r:
                continue
            if poly_dist((x, y), ROAD) < ROAD_HW + 6.0 + r:
                continue
            if any(rect_dist((x, y), q) < r * 0.6 for q in clear):
                continue
            if cr.random() < 0.04:
                continue                                        # a few gaps in the canopy
            crowns.append((x, y, r, top, role))
    stats["crowns"] = len(crowns)
    build_terrain(crowns)
    build_ground_dressing()

    # ---- ground collider
    COL((0, 0, -1.0), (HX + 2, HY + 2, 1.0))

    # ---- markers
    for k, (x, y) in enumerate(SPAWNS_A):
        gg.marker("spawn_a%d" % k, (x, y, 0.0), fwd=(1.0, -y * 0.03, 0.0))
    for k, (x, y) in enumerate(SPAWNS_B):
        gg.marker("spawn_b%d" % k, (x, y, 0.0), fwd=(-1.0, -y * 0.03, 0.0))
    cam = Vector(REF_CAM[0])
    gg.marker("ref_cam", cam, fwd=tuple(Vector(REF_CAM[1]) - cam))

    # ---- review sun (not exported): autumn afternoon from the south-west
    ld = bpy.data.lights.new("Sun", "SUN")
    ld.energy = 4.2
    ld.color = (1.0, 0.86, 0.68)
    ld.angle = math.radians(1.5)
    lo = bpy.data.objects.new("Sun", ld)
    lo.rotation_euler = Vector(SUN_DIR).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(lo)
    ld2 = bpy.data.lights.new("Fill", "SUN")
    ld2.energy = 0.5
    ld2.color = (0.8, 0.86, 1.0)
    lo2 = bpy.data.objects.new("Fill", ld2)
    lo2.rotation_euler = Vector((-SUN_DIR[0], -SUN_DIR[1], SUN_DIR[2])).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(lo2)
    world_setup()
    ee = bpy.context.scene.eevee
    for k, v in (("taa_render_samples", 32), ("use_fast_gi", True), ("fast_gi_distance", 6.0), ("use_gtao", True)):
        try:
            setattr(ee, k, v)
        except (AttributeError, TypeError):
            pass

    for P in (G, B, TR, BU, BK, PR):
        stats["tris_" + P.name] = P.tris()
        P.done()
    print("campus stats:", stats)
    return stats


def world_setup():
    """Review sky: a pale gradient (warm ground bounce below the horizon) (in-game haze is the meta fog).
    render_views() only sets the Background node's default colour, which a link overrides."""
    sc = bpy.context.scene
    w = bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes.get("Background")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    el = ramp.color_ramp.elements
    el[0].position, el[0].color = 0.0, (*gg._lin(gg._hex("#b8b49a")), 1)
    el[1].position, el[1].color = 0.55, (*gg._lin(gg._hex("#86aad6")), 1)
    e = el.new(0.04)
    e.color = (*gg._lin(gg._hex("#e2e6e4")), 1)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])


EYE_CLEAR = [(-53.0, 0.0), (-24.0, -3.0)]
EYE_A = ((-53.0, 0.0, 1.6), (0.0, 3.0, 3.5))
EYE_MID = ((-24.0, -3.0, 1.6), (6.0, -12.0, 2.5))
REF_CAM = ((55.0, -205.0, 125.0), (-15.0, 45.0, 0.0))
_s = Vector((0.6, 0.66, -0.42)).normalized()          # Blender: the direction sunlight travels
SUN_DIR = tuple(_s)

stats = main()
gd = Vector((SUN_DIR[0], SUN_DIR[2], -SUN_DIR[1]))
meta = {
    "class": "map",
    "notes": "Campus paintball: spawn A (west, x=-51, blue) vs spawn B (east, x=+51, yellow); play area 110x80 m "
             "inside a stone wall + net. Chapel + tower at the centre blocks the long axis; brick halls on the "
             "north flank (back alley behind them); the curving road across the south is the open danger lane. "
             "Godot axes: north (halls) is -Z, the road is toward +Z. Gameplay mirrors about x=0; bushes are HIDE_ walk-through volumes, tree trunks thin COL_ cover.",
    "play_area": [-HX, -HY, HX, HY],
    "ref_cam_fov": 53.1,                   # Godot vertical fov of the Blender 24 mm review lens at 3:2
    "lights": {"sun_dir": [round(gd.x, 3), round(gd.y, 3), round(gd.z, 3)], "sun_col": "#ffe4c0", "sun_energy": 1.8,
               "sky_top": "#6a9ad0", "sky_horizon": "#dfe6ea", "ground": "#6a6a4a", "ambient": 0.7,
               "ambient_col": "#c8bfa8", "sky_share": 0.35, "ssao": 2.0, "fog_col": "#d8dfe4",
               "fog_density": 0.004, "saturation": 1.08, "contrast": 1.05, "shadow_dist": 120.0},
}


def lane_report():
    """Open long lanes at chest height (1.2 m): horizontal lines y = const from x=-50 to 50 not cut by any COL box."""
    boxes = []
    for o in bpy.data.objects:
        if o.name.startswith("COL_") and o.scale.x < 40:
            c, h, r = o.location, o.scale, o.rotation_euler.z
            if c.z - h.z < 1.2 < c.z + h.z:
                boxes.append((c.x, c.y, h.x, h.y, r))
    def hit(y, x0, x1):
        for cx, cy, hx, hy, r in boxes:
            for k in range(int((x1 - x0) / 0.25) + 1):
                x = x0 + k * 0.25
                dx, dy = x - cx, y - cy
                u = dx * math.cos(r) + dy * math.sin(r)
                v = -dx * math.sin(r) + dy * math.cos(r)
                if abs(u) <= hx and abs(v) <= hy:
                    return True
        return False
    open_ = [y / 2 for y in range(-76, 77) if not hit(y / 2, -50.0, 50.0)]
    print("campus lanes open end-to-end at y =", open_)
    for o in bpy.data.objects:
        if o.name.startswith("HIDE_"):
            boxes.append((o.location.x, o.location.y, o.scale.x, o.scale.y, o.rotation_euler.z))
    print("campus lanes not even screened by bushes:", [y for y in open_ if not hit(y, -50.0, 50.0)])


if os.environ.get("LANES"):
    lane_report()
side = gg.finish("campus", "env", meta)
print("campus: colliders %d, hide volumes %d" % (side["colliders"], side["hide_volumes"]))
if gg.arg("--views"):
    tag = str(gg.arg("--tag", "r0"))
    gg.render_views("campus", "env", tag, {"eye_a": EYE_A, "eye_mid": EYE_MID, "plan": ((0.0, 0.0, 108.0), (0.0, 0.01, 0.0))})
