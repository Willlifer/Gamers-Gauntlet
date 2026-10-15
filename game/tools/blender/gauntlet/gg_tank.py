import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gg_common as gg
"""Gauntlet kit: `tank`, a tracked IFV after design/ref/kit/tank.jpg (a Redback-class scale model).

Prop frame: origin on the ground under the hull centre, front -Y, up +Z, vehicle LEFT = +X.
Parts: hull (fixed), tracks (bands + wheels), turret (yaws about M_turret_pivot),
gun (mantlet + cannon, elevates about M_gun_pivot). The reference photo is the
vehicle's front-LEFT three-quarter, so the "ref" view looks from +X, -Y.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

RNG = random.Random(1307)

# ------------------------------------------------------------------ dimensions (m)
TY = 0.30            # turret centre (y) on the hull roof
ROOF = 2.0           # hull roof
T_BOT = 2.08         # turret underside
T_TOP = 2.86         # turret roof
GUN_Z = 2.45         # trunnion height
TRK_X = 1.33         # track centre |x|
TRK_W = 0.56
BAND = 0.075         # track band thickness
SK_OUT = 1.75        # skirt outer face |x|
Z_BELT = 2.44        # turret widest belt
TW_BOT, TW_BELT, TW_TOP = 1.28, 1.46, 1.2


# ------------------------------------------------------------------ mesh builder
class Part:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.roles = []

    def mi(self, role):
        if role not in self.roles:
            self.roles.append(role)
        return self.roles.index(role)

    def faces(self, verts, faces, role, smooth=False, smooth_mask=None):
        vs = [self.bm.verts.new(Vector(v)) for v in verts]
        m = self.mi(role)
        for i, f in enumerate(faces):
            nf = self.bm.faces.new([vs[k] for k in f])
            nf.material_index = m
            nf.smooth = smooth_mask[i] if smooth_mask else smooth

    def hull(self, pts, role, bevel=0.0):
        tmp = bmesh.new()
        vs = [tmp.verts.new(Vector(p)) for p in pts]
        r = bmesh.ops.convex_hull(tmp, input=vs)
        kill = list({g for g in r["geom_interior"] + r["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
        if kill:
            bmesh.ops.delete(tmp, geom=kill, context="VERTS")
        bmesh.ops.dissolve_limit(tmp, angle_limit=0.0005, verts=tmp.verts[:], edges=tmp.edges[:])
        if bevel > 0:
            bmesh.ops.bevel(tmp, geom=tmp.edges[:] + tmp.verts[:], offset=bevel, offset_type="OFFSET",
                            segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
        vmap = {}
        m = self.mi(role)
        for v in tmp.verts:
            vmap[v] = self.bm.verts.new(v.co)
        for f in tmp.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = m
        tmp.free()

    def box(self, c, size, role, rot=None):
        c = Vector(c)
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        R = rot or Matrix.Identity(3)
        pts = [c + R @ Vector((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        self.hull(pts, role)

    def cyl(self, p0, p1, r0, role, sides=12, r1=None, smooth=True, cap_role=None, cap0=True):
        p0, p1 = Vector(p0), Vector(p1)
        r1 = r0 if r1 is None else r1
        ax = (p1 - p0).normalized()
        u, v = frame(ax)
        ring0 = [p0 + (u * math.cos(2 * math.pi * i / sides) + v * math.sin(2 * math.pi * i / sides)) * r0 for i in range(sides)]
        ring1 = [p1 + (u * math.cos(2 * math.pi * i / sides) + v * math.sin(2 * math.pi * i / sides)) * r1 for i in range(sides)]
        vs = ring0 + ring1
        fs = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i) for i in range(sides)]
        mask = [smooth] * sides
        self.faces(vs, fs, role, smooth_mask=mask)
        # caps share no verts with the sides in this builder; finish() welds coincident verts
        self.faces(ring1, [tuple(range(sides))], cap_role or role)
        if cap0:
            self.faces(ring0, [tuple(reversed(range(sides)))], role)

    def lathe(self, p0, ax, prof, role, sides=16, end_role=None):
        """One closed surface of revolution: prof = [(t, r)...] along unit axis ax from p0."""
        p0, ax = Vector(p0), Vector(ax).normalized()
        u, v = frame(ax)
        vs = []
        for t, r in prof:
            for i in range(sides):
                a = 2 * math.pi * i / sides
                vs.append(p0 + ax * t + (u * math.cos(a) + v * math.sin(a)) * r)
        bm = self.bm
        bv = [bm.verts.new(c) for c in vs]
        m = self.mi(role)
        for k in range(len(prof) - 1):
            for i in range(sides):
                f = bm.faces.new([bv[k * sides + i], bv[k * sides + (i + 1) % sides],
                                  bv[(k + 1) * sides + (i + 1) % sides], bv[(k + 1) * sides + i]])
                f.material_index = m
                f.smooth = abs(prof[k][1] - prof[k + 1][1]) < 0.3 * abs(prof[k + 1][0] - prof[k][0]) + 1e-4
        f = bm.faces.new([bv[i] for i in reversed(range(sides))]); f.material_index = m
        last = (len(prof) - 1) * sides
        f = bm.faces.new([bv[last + i] for i in range(sides)]); f.material_index = self.mi(end_role or role)

    def bolt(self, p, n, r=0.04, h=0.03, sides=6, role="paint_army", sink=0.02):
        n = Vector(n).normalized()
        p = Vector(p)
        self.lathe(p - n * sink, n, [(0, r), (sink + h * 0.45, r), (sink + h, r * 0.62)], role, sides=sides)

    def torus(self, c, axis, R, r, role, seg=10, sides=6):
        c, axis = Vector(c), Vector(axis).normalized()
        u, v = frame(axis)
        vs = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            d = u * math.cos(a) + v * math.sin(a)
            for j in range(sides):
                b = 2 * math.pi * j / sides
                vs.append(c + d * (R + r * math.cos(b)) + axis * (r * math.sin(b)))
        fs = []
        for i in range(seg):
            for j in range(sides):
                a0 = i * sides + j
                a1 = i * sides + (j + 1) % sides
                b0 = ((i + 1) % seg) * sides + j
                b1 = ((i + 1) % seg) * sides + (j + 1) % sides
                fs.append((a0, b0, b1, a1))
        self.faces(vs, fs, role, smooth=True)

    def build(self):
        ob = gg.mesh_object(self.name, self.bm, self.roles)
        return ob


def frame(ax):
    ax = Vector(ax).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = ax.cross(ref).normalized()
    v = ax.cross(u).normalized()
    return u, v


def quad_panel(part, a, b, c, d, n, t, role="paint_army", bevel=0.0):
    """A slab whose outer face is the quad a-b-c-d, thickness t inward along -n."""
    n = Vector(n).normalized()
    outer = [Vector(p) for p in (a, b, c, d)]
    part.hull(outer + [p - n * t for p in outer], role, bevel)


def lerp(a, b, t):
    return Vector(a).lerp(Vector(b), t)


# ------------------------------------------------------------------ hull
def build_hull():
    H = Part("hull")
    A = "paint_army"
    # lower tub between the tracks
    tub = []
    for x in (-1.04, 1.04):
        for y, z in ((-3.02, 0.42), (3.38, 0.42), (3.68, 0.95), (3.68, 1.3), (-3.66, 1.3), (-3.66, 1.18)):
            tub.append((x, y, z))
    H.hull(tub, A, 0.03)
    # upper body over the tracks: nose face, long glacis, flat roof, chamfered roof edges
    up = []
    for s in (-1, 1):
        for y, z, x in ((-3.76, 1.22, 1.58), (3.72, 1.22, 1.58), (-3.76, 1.44, 1.58), (-3.70, 1.48, 1.48),
                        (-1.55, 1.86, 1.58), (-1.55, ROOF, 1.44), (3.72, ROOF, 1.44), (3.72, 1.86, 1.58)):
            up.append((s * x, y, z))
    H.hull(up, A, 0.06)
    # glacis plane helper: z on the glacis centre line at y
    def gl_z(y):
        return 1.48 + (ROOF - 1.48) * (y + 3.70) / (3.70 - 1.55)
    gl_n = Vector((0, -(ROOF - 1.48), (3.70 - 1.55))).normalized()

    # nose ledge (raised front beam) and lower front plate add-on
    H.box((0, -3.80, 1.36), (2.6, 0.14, 0.2), A)
    lf_n = Vector((0, -(1.18 - 0.42), -(3.66 - 3.02))).normalized()   # lower front plate faces down-forward
    quad_panel(H, (-0.95, -3.70, 1.12), (0.95, -3.70, 1.12), (0.95, -3.12, 0.52), (-0.95, -3.12, 0.52), lf_n, -0.05)
    for i in range(7):
        for t in (0.25, 0.75):
            p = lerp((-0.85 + i * 0.283, -3.70, 1.12), (-0.85 + i * 0.283, -3.12, 0.52), t) + lf_n * 0.05
            H.bolt(p, lf_n, r=0.028, h=0.02)
    # tow eyes on the nose corners, shackle plates on the lower front
    for s in (-1, 1):
        H.box((s * 1.38, -3.86, 1.33), (0.18, 0.12, 0.2), A)
        H.torus((s * 1.38, -3.95, 1.30), (1, 0, 0), 0.085, 0.03, A)
        H.box((s * 0.72, -3.5, 0.92), (0.06, 0.26, 0.3), A, rot=Matrix.Rotation(-0.85, 3, "X"))
        H.box((s * 0.88, -3.5, 0.92), (0.06, 0.26, 0.3), A, rot=Matrix.Rotation(-0.85, 3, "X"))
        H.torus((s * 0.80, -3.62, 0.78), (1, 0, 0), 0.09, 0.03, A)
        H.cyl((s * 0.66, -3.56, 0.86), (s * 0.94, -3.56, 0.86), 0.035, "gunmetal", sides=8)
        # headlight cluster: housing + 3 lenses on the front corner face
        H.box((s * 1.18, -3.78, 1.06), (0.42, 0.1, 0.14), A)
        for k in range(3):
            x = s * (1.03 + k * 0.14)
            H.cyl((x, -3.80, 1.06), (x, -3.86, 1.06), 0.045, "glass_lens", sides=10)
            H.torus((x, -3.835, 1.06), (0, -1, 0), 0.05, 0.012, A, seg=10, sides=4)
    # glacis: hatch hinges, fittings and rows of bolts (the bolted add-on armour)
    for row, y in enumerate((-3.45, -2.6)):
        n = 9 if row < 2 else 7
        for i in range(n):
            x = -1.25 + 2.5 * i / (n - 1)
            if abs(x) < 0.12 and row > 1:
                continue
            p = Vector((x, y, gl_z(y)))
            H.bolt(p, gl_n, r=0.045, h=0.03, sides=8)
    rot = Matrix.Rotation(math.atan2(-gl_n.y, gl_n.z), 3, "X")
    for (x, y) in ((-1.05, -3.25), (1.05, -3.25), (-0.45, -2.95), (0.45, -2.95), (-1.0, -2.05), (1.0, -2.05), (-0.3, -1.95), (0.3, -2.4)):
        p = Vector((x, y, gl_z(y))) + gl_n * 0.03
        H.box(p, (0.3, 0.1, 0.05), A, rot=rot)                           # low cleat: base + two lugs + bar
        for dx in (-0.1, 0.1):
            H.box(p + Vector((dx, 0, 0)) + gl_n * 0.05, (0.04, 0.08, 0.07), A, rot=rot)
        H.box(p + gl_n * 0.08, (0.24, 0.04, 0.03), A, rot=rot)
    # driver's hatch, periscope blocks
    H.cyl((0.62, -1.15, ROOF - 0.02), (0.62, -1.15, ROOF + 0.05), 0.33, A, sides=14, smooth=False)
    for k in range(3):
        H.box((0.32 + k * 0.3, -1.6, ROOF + 0.04), (0.2, 0.1, 0.1), A)
        H.box((0.32 + k * 0.3, -1.655, ROOF + 0.05), (0.16, 0.012, 0.05), "glass_lens")
    # turret ring collar on the roof
    H.cyl((0, TY, ROOF - 0.02), (0, TY, ROOF + 0.07), 1.1, A, sides=24, smooth=False)
    # rear deck: grilles and stowage boxes, rear door, tail lights
    for s in (-1, 1):
        H.box((s * 0.75, 3.15, ROOF + 0.06), (0.8, 0.8, 0.12), A)
        H.box((s * 0.75, 3.15, ROOF + 0.13), (0.6, 0.6, 0.03), A)
        H.box((s * 1.18, 3.86, 1.62), (0.56, 0.32, 0.5), A)               # rear stowage bins
        H.box((s * 1.18, 4.025, 1.62), (0.5, 0.02, 0.42), A)
        H.cyl((s * 1.42, 3.72, 1.92), (s * 1.42, 3.78, 1.92), 0.05, "glass_lens", sides=8)
    H.box((0, 3.74, 1.15), (1.5, 0.08, 1.0), A)                           # rear ramp door
    H.box((0, 3.8, 1.5), (1.2, 0.06, 0.06), A)
    H.box((0, 3.65, 2.02), (1.6, 0.4, 0.12), A)

    # side armour: upper bolted row (tilted) and lower hinged row (vertical)
    for s in (-1, 1):
        # upper row: tilted panels; the front one runs down the glacis side
        segs = [(-3.55, -2.35), (-2.33, -1.0), (-0.98, 0.35), (0.37, 1.7), (1.72, 3.0), (3.02, 3.72)]
        for i, (y0, y1) in enumerate(segs):
            zb = 1.36
            def ztop(y):
                return min(1.95, 1.47 + (1.95 - 1.47) * (y + 3.6) / (3.6 - 1.7)) if y < -1.7 else 1.95
            xb, xt = SK_OUT, SK_OUT - 0.24
            a = (s * xb, y0, zb)
            b = (s * xb, y1, zb)
            c = (s * xt, y1, ztop(y1))
            d = (s * xt, y0, ztop(y0))
            n = Vector((s * (ztop(y0) - zb), 0, xb - xt)).normalized()
            quad_panel(H, a, b, c, d, n, 0.2, bevel=0.025)
            # bolts: sparse big round heads, paired columns
            ncol = max(1, int((y1 - y0) / 0.36))
            for ci in range(ncol):
                y = y0 + (y1 - y0) * (ci + 0.5) / ncol
                zt = ztop(y)
                rows = (0.3, 0.7) if zt - zb > 0.35 else (0.5,)
                for rz in rows:
                    kind = RNG.random()
                    if kind < 0.12:
                        continue
                    zc = zb + (zt - zb) * rz
                    if kind < 0.45:
                        offs = [(-0.09, -0.085), (0.09, -0.085), (-0.09, 0.085), (0.09, 0.085)]   # 2x2 cluster
                    elif kind < 0.8:
                        offs = [(0.0, -0.085), (0.0, 0.085)]                                    # vertical pair
                    else:
                        offs = [(-0.09, 0.0), (0.09, 0.0)]
                    for dy, dz in offs:
                        zz = zc + dz
                        x = xb + (xt - xb) * (zz - zb) / (zt - zb)
                        H.bolt((s * x, y + dy, zz), n, r=0.066, h=0.04, sides=10)
        # lower row: vertical panels, front one with a raked leading edge
        lsegs = [(-3.3, -2.25), (-2.23, -1.0), (-0.98, 0.35), (0.37, 1.7), (1.72, 3.0), (3.02, 3.6)]
        for i, (y0, y1) in enumerate(lsegs):
            zt, zb = 1.36, 0.66
            yb0 = y0 + (0.8 if i == 0 else 0.0)
            quad_panel(H, (s * SK_OUT, yb0, zb), (s * SK_OUT, y1, zb), (s * SK_OUT, y1, zt), (s * SK_OUT, y0, zt),
                       (s, 0, 0), 0.06, bevel=0.012)
            for k in range(3 if (y1 - y0) > 1.0 else 2):
                y = y0 + 0.15 + k * 0.45
                if y < y1 - 0.08:
                    H.bolt((s * SK_OUT, y, zt - 0.08), (s, 0, 0), r=0.025, h=0.015)
            if i > 0:   # hinge knuckles on the seams
                for z in (0.86, 1.18):
                    H.cyl((s * (SK_OUT + 0.02), y0 - 0.01, z - 0.06), (s * (SK_OUT + 0.02), y0 - 0.01, z + 0.06), 0.025, A, sides=6)
                    H.box((s * (SK_OUT + 0.008), y0 + 0.04, z), (0.02, 0.1, 0.1), A)
        # skirt hangers along the bottom of the upper row
        H.box((s * 1.68, 0.12, 1.36), (0.24, 7.1, 0.06), A)      # the crease ledge between the rows
        # hull number plate "8": dark plate, raised light digit (seven segments)
        n = Vector((s * (1.95 - 1.36), 0, 0.24)).normalized()
        py = -0.4
        pz = 1.78
        px = SK_OUT - 0.24 * (pz - 1.36) / (1.95 - 1.36) + 0.02
        R = Matrix((frame_cols(n, s)))
        base = Vector((s * px, py, pz))
        H.box(base, (0.03, 0.17, 0.21), "polymer_black", rot=R)
        # segments in plate-local (y along hull, z up the tilted face)
        segs8 = [((0, 0.09), (0.11, 0.022)), ((0, 0.0), (0.11, 0.022)), ((0, -0.09), (0.11, 0.022)),
                 ((-0.055, 0.045), (0.022, 0.1)), ((0.055, 0.045), (0.022, 0.1)),
                 ((-0.055, -0.045), (0.022, 0.1)), ((0.055, -0.045), (0.022, 0.1))]
        for (sy, sz), (wy, wz) in segs8:
            p = base + R @ Vector((0.02, sy * 0.68, sz * 0.68))
            H.box(p, (0.016, max(0.024, wy * 0.68), max(0.024, wz * 0.68)), "sign_white", rot=R)
        # a rear fender flap, front mud flap
        H.box((s * 1.33, 3.66, 1.25), (0.6, 0.12, 0.08), A)
    return H.build()


def frame_cols(n, s):
    """Rotation whose X axis is the panel normal n (tilted plate), Y along the hull, Z up the face."""
    x = Vector(n).normalized()
    y = Vector((0, 1, 0))
    z = x.cross(y).normalized()
    if z.z < 0:
        z = -z
    return (x.to_tuple(), y.to_tuple(), z.to_tuple()) and Matrix((x, y, z)).transposed()


# ------------------------------------------------------------------ tracks + wheels
def convex_hull_2d(pts):
    pts = sorted(set(pts))
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]   # CCW


def resample(loop, step):
    out = []
    n = len(loop)
    segs = [(Vector(loop[i]), Vector(loop[(i + 1) % n])) for i in range(n)]
    total = sum((b - a).length for a, b in segs)
    count = int(total / step)
    step = total / count
    acc = 0.0
    i = 0
    a, b = segs[0]
    seg_len = (b - a).length
    for k in range(count):
        t = k * step
        while t > acc + seg_len:
            acc += seg_len
            i += 1
            a, b = segs[i]
            seg_len = (b - a).length
        out.append(a.lerp(b, (t - acc) / seg_len if seg_len > 0 else 0))
    return out


ROAD_Y = (-2.38, -1.45, -0.52, 0.41, 1.34, 2.27)
ROAD_R = 0.32
SPR = (-3.17, 0.85, 0.28)
IDL = (3.28, 0.68, 0.28)


def build_tracks():
    T = Part("tracks")
    A = "paint_army"
    circles = [SPR, IDL] + [(y, ROAD_R + BAND, ROAD_R) for y in ROAD_Y]
    pts = []
    for (cy, cz, r) in circles:
        for i in range(48):
            a = 2 * math.pi * i / 48
            pts.append((round(cy + r * math.cos(a), 5), round(cz + r * math.sin(a), 5)))
    loop = resample(convex_hull_2d(pts), 0.085)   # (y, z), CCW in the y-z plane
    n = len(loop)
    for s in (-1, 1):
        x0, x1 = s * (TRK_X - TRK_W / 2), s * (TRK_X + TRK_W / 2)
        vs = []
        for i, p in enumerate(loop):
            t = (loop[(i + 1) % n] - loop[i - 1]).normalized()
            nrm = Vector((t.y, -t.x))          # outward for a CCW loop
            off = BAND if (i % 3) != 0 else BAND * 0.3
            o = p + nrm * off
            for (y, z) in ((p.x, p.y), (o.x, o.y)):
                pass
            vs += [(x0, p.x, p.y), (x1, p.x, p.y), (x1, o.x, o.y), (x0, o.x, o.y)]
        fs = []
        for i in range(n):
            a, b = i * 4, ((i + 1) % n) * 4
            for k in range(4):
                fs.append((a + k, a + (k + 1) % 4, b + (k + 1) % 4, b + k))
        T.faces(vs, fs, "track_rubber")
        # inner guide horns on the band (read through the gaps)
        # wheels
        xo = s * (TRK_X + TRK_W / 2)      # outer face
        for y in ROAD_Y:
            z = ROAD_R + BAND
            T.cyl((s * (TRK_X + 0.06), y, z), (xo, y, z), ROAD_R, "track_rubber", sides=16)
            T.cyl((s * (TRK_X - TRK_W / 2), y, z), (s * (TRK_X - 0.06), y, z), ROAD_R, "track_rubber", sides=12)
            T.cyl((xo - s * 0.01, y, z), (xo + s * 0.035, y, z), ROAD_R * 0.7, A, sides=16, r1=ROAD_R * 0.66)
            T.cyl((xo + s * 0.02, y, z), (xo + s * 0.08, y, z), 0.12, A, sides=10, r1=0.09)
            for k in range(6):
                a = 2 * math.pi * k / 6
                p = Vector((xo + s * 0.035, y + 0.17 * math.cos(a), z + 0.17 * math.sin(a)))
                T.bolt(p, (s, 0, 0), r=0.022, h=0.015, sides=6, role="gunmetal")
        # drive sprocket (front): toothed ring + hub
        cy, cz, r = SPR
        teeth = 11
        ring = []
        for i in range(teeth * 2):
            a = math.pi * i / teeth
            rr = r + 0.02 if i % 2 == 0 else r - 0.05
            ring.append((cy + rr * math.cos(a), cz + rr * math.sin(a)))
        for (xa, xb) in ((TRK_X - 0.24, TRK_X - 0.12), (TRK_X + 0.12, TRK_X + 0.24)):
            pts3 = [(s * xa, y, z) for y, z in ring] + [(s * xb, y, z) for y, z in ring]
            m = len(ring)
            fs = [(i, (i + 1) % m, m + (i + 1) % m, m + i) for i in range(m)]
            fs += [tuple(range(m)), tuple(range(2 * m - 1, m - 1, -1))]
            T.faces(pts3, fs, A)
        T.cyl((s * (TRK_X - 0.12), cy, cz), (s * (TRK_X + 0.3), cy, cz), 0.16, A, sides=12)
        T.cyl((s * (TRK_X + 0.3), cy, cz), (s * (TRK_X + 0.36), cy, cz), 0.1, A, sides=10, r1=0.07)
        # idler (rear)
        cy, cz, r = IDL
        T.cyl((s * (TRK_X - TRK_W / 2), cy, cz), (s * (TRK_X + TRK_W / 2), cy, cz), r, "track_rubber", sides=16)
        T.cyl((xo - s * 0.01, cy, cz), (xo + s * 0.03, cy, cz), r * 0.8, A, sides=16)
        T.cyl((xo + s * 0.02, cy, cz), (xo + s * 0.08, cy, cz), 0.1, A, sides=10, r1=0.08)
        # return rollers (mostly hidden by the skirts)
        for y in (-1.9, 0.0, 1.9):
            T.cyl((s * (TRK_X - 0.1), y, 1.0), (s * (TRK_X + 0.1), y, 1.0), 0.09, "track_rubber", sides=10)
    return T.build()


# ------------------------------------------------------------------ turret
def turret_pts():
    pts = []
    for s in (-1, 1):
        # (x, y, z) relative: y from turret centre, front = -y; a long wedge nose, sloped cheeks
        pts += [
            (s * 0.42, -1.66, T_BOT + 0.02), (s * TW_BOT, -0.45, T_BOT), (s * TW_BOT, 1.72, T_BOT),
            (s * 0.44, -1.92, Z_BELT), (s * TW_BELT, -0.5, Z_BELT), (s * TW_BELT, 1.82, Z_BELT),
            (s * 0.4, -1.62, T_TOP), (s * TW_TOP, -0.58, T_TOP), (s * TW_TOP, 1.1, T_TOP), (s * (TW_TOP - 0.06), 1.72, T_TOP - 0.1),
        ]
    return [(x, y + TY, z) for x, y, z in pts]


def build_turret():
    T = Part("turret")
    A = "paint_army"
    T.hull(turret_pts(), A, 0.055)
    # turret basket collar
    T.cyl((0, TY, ROOF + 0.06), (0, TY, T_BOT + 0.02), 1.0, "gunmetal", sides=24, smooth=False)
    # side appliquÃ© plates (proud of the sloped sides), with seams between them
    for s in (-1, 1):
        for (y0, y1) in ((-0.44, 0.62), (0.66, 1.74)):
            for (za, zb, xa, xb) in ((Z_BELT + 0.02, T_TOP - 0.04, TW_BELT, TW_TOP), (T_BOT + 0.03, Z_BELT - 0.02, TW_BOT, TW_BELT)):
                xa2 = xa + (xb - xa) * 0.0
                n = Vector((s * (zb - za), 0, -(xb - xa))).normalized()
                a = (s * (xa + 0.03), y0 + TY, za)
                b = (s * (xa + 0.03), y1 + TY, za)
                c = (s * (xb + 0.03), y1 + TY, zb)
                d = (s * (xb + 0.03), y0 + TY, zb)
                quad_panel(T, a, b, c, d, n, 0.06, bevel=0.012)
        T.box((s * (TW_BELT + 0.03), TY + 0.95, Z_BELT + 0.12), (0.06, 0.18, 0.2), A)
    # bustle roof plate + rails
    T.hull([(sx * 1.0, TY + y, T_TOP + z) for sx in (-1, 1) for y in (0.3, 1.2) for z in (-0.02, 0.07)], A, 0.02)
    for s in (-1, 1):
        T.box((s * 0.95, TY + 0.78, T_TOP + 0.15), (0.04, 0.9, 0.04), A)
        for y in (0.38, 0.78, 1.18):
            T.box((s * 0.95, TY + y, T_TOP + 0.11), (0.04, 0.04, 0.08), A)
    # raised blocks on the front roof wedge
    for s in (-1, 1):
        T.box((s * 0.7, TY - 1.1, T_TOP + 0.03), (0.34, 0.45, 0.07), A)
    # smoke grenade launchers: two clusters (2x2 + 2x2) on each front cheek
    for s in (-1, 1):
        a = Vector((s * 0.44, TY - 1.92, Z_BELT))
        b = Vector((s * TW_BELT, TY - 0.5, Z_BELT))
        edge = (b - a).normalized()
        n = Vector((s * abs(edge.y), -abs(edge.x), 0)).normalized()     # outward-forward
        aim = (n + Vector((0, 0, 0.25))).normalized()
        for t in (0.2, 0.74):
            base = a.lerp(b, t)
            bracket_c = base + n * 0.06 + Vector((0, 0, 0.04))
            T.hull([bracket_c + edge * dx + Vector((0, 0, dz)) + n * dn
                    for dx in (-0.3, 0.3) for dz in (-0.16, 0.17) for dn in (-0.08, 0.04)], A, 0.015)
            for col in range(4):
                for row in range(2):
                    off = -0.2 + col * 0.12 + (0.03 if col >= 2 else 0.0) - 0.015
                    p = bracket_c + edge * off + Vector((0, 0, -0.07 + row * 0.135)) + n * 0.02
                    T.cyl(p, p + aim * 0.2, 0.056, A, sides=8, cap_role="gunmetal")
    # commander's panoramic sight on a short mast: base, mast, box head with two lenses, side drum
    sx, sy = 0.32, TY - 0.3
    T.cyl((sx, sy, T_TOP - 0.02), (sx, sy, T_TOP + 0.12), 0.26, A, sides=16, smooth=False)
    T.cyl((sx, sy, T_TOP + 0.12), (sx, sy, 3.2), 0.09, A, sides=10)
    T.cyl((sx, sy, 3.12), (sx, sy, 3.19), 0.17, A, sides=12, smooth=False)
    T.hull([(sx - 0.03 + dx, sy + dy, 3.35 + dz) for dx in (-0.19, 0.19) for dy in (-0.18, 0.18) for dz in (-0.16, 0.16)], A, 0.02)
    T.cyl((sx + 0.15, sy - 0.02, 3.35), (sx + 0.25, sy - 0.02, 3.35), 0.16, A, sides=14)
    T.box((sx - 0.03, sy, 3.53), (0.34, 0.32, 0.03), A)
    T.cyl((sx - 0.11, sy - 0.17, 3.38), (sx - 0.11, sy - 0.21, 3.38), 0.085, "glass_lens", sides=12)
    T.box((sx + 0.05, sy - 0.19, 3.38), (0.08, 0.04, 0.17), "glass_lens")
    # hatches
    for (hx, hy, r) in ((-0.5, TY + 0.25, 0.36), (0.55, TY + 0.55, 0.3)):
        T.cyl((hx, hy, T_TOP - 0.02), (hx, hy, T_TOP + 0.06), r, A, sides=16, smooth=False)
        T.cyl((hx, hy, T_TOP + 0.06), (hx, hy, T_TOP + 0.1), r * 0.25, A, sides=8, smooth=False)
        T.box((hx, hy + r * 0.85, T_TOP + 0.08), (0.2, 0.08, 0.06), A)
    # gunner's sight block, front left of the roof
    T.box((-0.45, TY - 1.25, T_TOP + 0.08), (0.34, 0.3, 0.16), A)
    T.box((-0.45, TY - 1.405, T_TOP + 0.09), (0.26, 0.012, 0.09), "glass_lens")
    return T.build()


# ------------------------------------------------------------------ gun
MANT_FRONT = TY - 2.08
PIVOT = Vector((0, TY - 1.6, GUN_Z))


def build_gun():
    G = Part("gun")
    A = "paint_army"
    z = GUN_Z
    # boxy mantlet block set into the turret's nose
    G.hull([(sx * w, y, z + sz * h) for sx in (-1, 1) for sz in (-1, 1)
            for (y, w, h) in ((MANT_FRONT, 0.26, 0.2), (MANT_FRONT + 0.08, 0.32, 0.25), (TY - 1.45, 0.34, 0.27))], A, 0.02)
    y0 = MANT_FRONT
    G.lathe((0, y0 + 0.02, z), (0, -1, 0), [(0, 0.2), (0.3, 0.17), (0.36, 0.13)], A, sides=8)   # faceted sleeve
    G.lathe((0, y0 + 0.02, z), (0, -1, 0), [(0, 0.15), (0.14, 0.135), (0.9, 0.128), (0.97, 0.085), (2.78, 0.08),
                                            (2.8, 0.106), (2.98, 0.106), (3.02, 0.094)], A, sides=16, end_role="gunmetal")
    G.cyl((0, y0 - 3.0, z), (0, y0 - 3.024, z), 0.05, "gunmetal", sides=10)    # bore, proud of the tip
    G.cyl((0.22, y0 + 0.02, z - 0.08), (0.22, y0 - 0.06, z - 0.08), 0.035, "gunmetal", sides=8)   # coax
    return G.build()


# ------------------------------------------------------------------ main
def main():
    gg.reset()
    build_hull()
    build_tracks()
    build_turret()
    build_gun()
    tip = Vector((0, MANT_FRONT - 3.02, GUN_Z))  # muzzle face
    gg.marker("muzzle", tip, (0, -1, 0))
    gg.marker("turret_pivot", (0, TY, ROOF), (0, -1, 0), (0, 0, 1))
    gg.marker("gun_pivot", PIVOT, (0, -1, 0), (0, 0, 1))
    gg.marker("sight", (0.29, TY - 0.3, 3.35), (0, -1, 0))
    gg.marker("hatch", (-0.5, TY + 0.25, T_TOP + 0.1), (0, -1, 0))
    cam = Vector((0, TY + 9.0, 5.2))
    look = Vector((0, TY - 1.0, 2.4))
    gg.marker("cam", cam, (look - cam).normalized(), (0, 0, 1))
    meta = {"hands": 0, "socket": "none", "class": "vehicle", "notes": "tracked IFV, Redback-like"}
    gg.finish("tank", "prop", meta)
    if gg.arg("--views"):
        tag = str(gg.arg("--tag", "r0"))
        gg.render_views("tank", "prop", tag, {"ref": REF_CAM})
        pivot_test(tag)


REF_CAM = ((8.9, -9.9, 3.3), (0.3, -0.5, 1.45))


def pivot_test(tag):
    """Throwaway: turret yawed 30 deg, gun raised 10 deg, rendered as <tag>pv (not in the sheet)."""
    tur, gun = bpy.data.objects["turret"], bpy.data.objects["gun"]
    piv = Vector((0, TY, ROOF))
    yaw = Matrix.Translation(piv) @ Matrix.Rotation(math.radians(30), 4, "Z") @ Matrix.Translation(-piv)
    ele = Matrix.Translation(PIVOT) @ Matrix.Rotation(math.radians(-10), 4, "X") @ Matrix.Translation(-PIVOT)
    tur.matrix_world = yaw @ tur.matrix_world
    gun.matrix_world = yaw @ ele @ gun.matrix_world
    gg.render_views("tank", "prop", tag + "pv", {"pivot": REF_CAM, "pivot_side": ((-14, 0.5, 3.0), (0, 0.0, 1.6))})


main()
