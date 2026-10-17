import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gg_common as gg
"""marksman: a Ruger American (Predator / Gen II) style hunting bolt-action
after design/ref/kit/marksman.jpg: grey speckled synthetic stock with a black
comb insert, a straight comb and slim forend, stainless action, spiral-fluted
barrel with a radial brake, a 3-9x40 scope on low rings, an AI-style box mag.

    blender -b --factory-startup --python game/tools/blender/gauntlet/gg_marksman.py -- --views --tag r0

Frame (gg_common): muzzle -Y, up +Z, +X = the gun's LEFT; origin = the grip
fist. Helpers below work in (x, f, z) with f = metres forward (Blender -Y).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# material slots shared by every part (index -> kit role)
ROLES = ["polymer_speckle:#454b56", "gunmetal:#7c8086", "alloy_black", "glass_lens", "rubber",
         "steel", "polymer_black", "brass", "blued", "rubber:#4a4d52", "gunmetal:#686c72"]
STOCK, METAL, ALLOY, GLASS, RUBBER, STEEL, POLY, BRASS, BLUED, LATT, FLUTE = range(11)

BORE = 0.070          # bore axis height above the fist
ACT_R = 0.0175        # receiver radius
ACT0, ACT1 = -0.018, 0.205   # receiver rear / front (f)
MUZZLE = 0.770        # brake exit (f): barrel 0.205..0.770 = 0.565
BUTT = -0.300         # recoil pad rear (f): LOP from the trigger ~0.345
SC_Z = 0.114          # scope axis height
SC0, SC1 = -0.095, 0.215     # scope ocular end / objective end (f): 0.31 long


def P(x, f, z):
    return Vector((x, -f, z))


# ------------------------------------------------------------------ mesh helpers

def _ring_faces(bm, rings, mi, cap0=True, cap1=True):
    """Bridge rings (lists of BMVerts, equal length, or length 1 = a pole)."""
    for a, b in zip(rings, rings[1:]):
        n = max(len(a), len(b))
        for i in range(n):
            j = (i + 1) % n
            if len(a) == 1:
                vs = (a[0], b[i], b[j])
            elif len(b) == 1:
                vs = (a[i], b[0], a[j])
            else:
                vs = (a[i], b[i], b[j], a[j])
            try:
                f = bm.faces.new(vs)
                f.material_index = mi if isinstance(mi, int) else mi[rings.index(a)]
            except ValueError:
                pass
    for ok, r in ((cap0, rings[0]), (cap1, rings[-1])):
        if ok and len(r) > 2:
            f = bm.faces.new(r)
            f.material_index = mi if isinstance(mi, int) else (mi[0] if r is rings[0] else mi[-1])


def loft(bm, rings_pts, mi, cap0=True, cap1=True):
    rings = [[bm.verts.new(p) for p in r] for r in rings_pts]
    _ring_faces(bm, rings, mi, cap0, cap1)


def superellipse(n, e):
    """Unit superellipse points (u, v), CCW from +u."""
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        out.append((math.copysign(abs(c) ** (2 / e), c), math.copysign(abs(s) ** (2 / e), s)))
    return out


def stock_ring(f, top, bot, w, n=24, e=2.6, top_e=None):
    """A section of the stock across x at station f between z=bot and z=top."""
    zc, h = (top + bot) * 0.5, (top - bot) * 0.5
    pts = []
    for u, v in superellipse(n, e):
        pts.append(P(w * u, f, zc + h * v))
    return pts


def lathe(bm, f0, f1, prof, segs, x=0.0, z=BORE, rfun=None, axis_pts=None, mfun=None, spin=None):
    """Revolve prof [(t, r, mi)] about the axis from (x,f0,z) to (x,f1,z).
    t in metres along the axis, r = radius (0 = pole); mi = material of the band
    ending at that point. rfun(t, theta, r) -> r lets a surface be modulated."""
    a = P(x, f0, z) if axis_pts is None else axis_pts[0]
    b = P(x, f1, z) if axis_pts is None else axis_pts[1]
    d = (b - a).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(up).normalized()
    v = u.cross(d).normalized()
    rings, mis = [], []
    for t, r, mi in prof:
        c = a + d * t
        if r <= 0:
            rings.append([bm.verts.new(c)])
        else:
            ring = []
            for i in range(segs):
                th = 2 * math.pi * i / segs
                rr = rfun(t, th, r) if rfun else r
                ta = th + (spin(t) if spin else 0.0)     # the grid follows a helix
                ring.append(bm.verts.new(c + (u * math.cos(ta) + v * math.sin(ta)) * rr))
            rings.append(ring)
        mis.append(mi)
    for k, (ra, rb) in enumerate(zip(rings, rings[1:])):
        n = max(len(ra), len(rb))
        for i in range(n):
            j = (i + 1) % n
            if len(ra) == 1:
                vs = (ra[0], rb[j], rb[i])
            elif len(rb) == 1:
                vs = (ra[i], ra[j], rb[0])
            else:
                vs = (ra[i], ra[j], rb[j], rb[i])
            fc = bm.faces.new(vs)
            fc.material_index = mis[k + 1]
            if mfun and len(ra) > 1 and len(rb) > 1:
                mm = mfun((prof[k][0] + prof[k + 1][0]) * 0.5, 2 * math.pi * (i + 0.5) / n)
                if mm is not None:
                    fc.material_index = mm
    for ring, mi in ((rings[0], mis[0]), (rings[-1], mis[-1])):
        if len(ring) > 2:
            fc = bm.faces.new(ring)
            fc.material_index = mi


def box(bm, f0, f1, x0, x1, z0, z1, mi):
    vs = [bm.verts.new(P(x, f, z)) for f in (f0, f1) for x in (x0, x1) for z in (z0, z1)]
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        fc = bm.faces.new([vs[i] for i in q])
        fc.material_index = mi


def sweep(bm, pts, section, mi, cap=True):
    """Sweep a 2D section [(a, b)] along a polyline of Vectors; a along the
    path normal n, b along the binormal. Frames by parallel transport."""
    rings = []
    n_prev = None
    for k, p in enumerate(pts):
        if k == 0:
            t = (pts[1] - pts[0]).normalized()
        elif k == len(pts) - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = ((pts[k + 1] - pts[k]).normalized() + (p - pts[k - 1]).normalized()).normalized()
        if n_prev is None:
            ref = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 0, 1))
            n = (ref - t * ref.dot(t)).normalized()
        else:
            n = (n_prev - t * n_prev.dot(t)).normalized()
        n_prev = n
        bnm = t.cross(n)
        rings.append([bm.verts.new(p + n * a + bnm * b) for a, b in section])
    _ring_faces(bm, rings, mi, cap, cap)


def smooth_path(pts, k=4):
    """Catmull-Rom through pts, k samples per span."""
    out = []
    ext = [pts[0] * 2 - pts[1]] + list(pts) + [pts[-1] * 2 - pts[-2]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for j in range(k):
            t = j / k
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1].copy())
    return out


def circle2(r, n):
    return [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def sphere(bm, c, r, mi, seg=10, rings=6):
    prof = []
    for k in range(rings + 1):
        a = math.pi * k / rings
        prof.append((r - r * math.cos(a), r * math.sin(a), mi))
    lathe(bm, 0, 0, prof, seg, axis_pts=(c + Vector((0, r, 0)), c + Vector((0, -r, 0))))


def disc_on(bm, c, nrm, r, mi, n=6, th=0.0004):
    """A thin proud disc (a hole/port read) centred at c facing nrm."""
    lathe(bm, 0, 0, [(0, 0, mi), (0, r, mi), (th, r, mi), (th, 0, mi)], n,
          axis_pts=(c - nrm * 0.0002, c + nrm * (th - 0.0002) * 50))


# ------------------------------------------------------------------ the stock

def build_stock(bm):
    # (f, top, bottom, half width): butt -> wrist -> action -> forend tip
    st = [
        (BUTT + 0.022, 0.058, -0.088, 0.0200),
        (BUTT + 0.030, 0.060, -0.087, 0.0210),
        (-0.24, 0.060, -0.072, 0.0215),
        (-0.18, 0.060, -0.055, 0.0210),
        (-0.13, 0.058, -0.038, 0.0200),
        (-0.095, 0.056, -0.022, 0.0190),
        (-0.065, 0.054, -0.006, 0.0180),
        (-0.035, 0.052, -0.002, 0.0175),
        (-0.010, 0.056, 0.006, 0.0180),
        (0.020, 0.062, 0.010, 0.0215),
        (0.070, 0.062, 0.012, 0.0225),
        (0.180, 0.063, 0.014, 0.0225),
        (0.240, 0.062, 0.019, 0.0205),
        (0.330, 0.060, 0.030, 0.0182),
        (0.440, 0.059, 0.038, 0.0168),
        (0.495, 0.058, 0.042, 0.0156),
        (0.515, 0.057, 0.045, 0.0130),
        (0.524, 0.055, 0.048, 0.0080),
    ]
    loft(bm, [stock_ring(*s) for s in st], STOCK)
    # the pistol grip: a loft down a raked axis through the fist (the origin)
    top, bot = Vector((0.0, 0.008, 0.036)), Vector((0.0, -0.054, -0.078))  # (x, f, z)
    ax = (bot - top).normalized()
    side = Vector((1, 0, 0))
    vv = side.cross(ax).normalized()           # in the f-z plane, toward the front
    if vv.y < 0:
        vv = -vv
    rings = []
    # (t along axis, half width, half depth front/back, offset along vv)
    for t, w, dp, off in ((0.0, 0.0180, 0.025, 0.0), (0.03, 0.0190, 0.0275, -0.002), (0.065, 0.0192, 0.0280, -0.003),
                          (0.100, 0.0182, 0.0275, -0.005), (0.118, 0.0190, 0.0305, -0.008), (0.127, 0.0178, 0.0290, -0.010),
                          (0.131, 0.013, 0.022, -0.010)):
        c = top + ax * t + vv * off
        ring = []
        for u, v in superellipse(22, 2.3):
            q = c + side * (w * u) + vv * (dp * v)
            ring.append(P(q.x, q.y, q.z))
        rings.append(ring)
    loft(bm, rings, STOCK)
    # the black comb insert on the butt, proud of the stock's sides
    ci = [
        (BUTT + 0.024, 0.073, 0.036, 0.0222),
        (-0.24, 0.073, 0.038, 0.0230),
        (-0.16, 0.072, 0.044, 0.0226),
        (-0.115, 0.069, 0.052, 0.0212),
        (-0.088, 0.062, 0.056, 0.0180),
    ]
    loft(bm, [stock_ring(f, t, b, w, 20, 3.2) for f, t, b, w in ci], POLY)
    # recoil pad: rubber, the butt's outline, a little bigger
    pad = []
    for f, g in ((BUTT, 0.0), (BUTT + 0.004, 0.0012), (BUTT + 0.024, 0.0012)):
        pad.append(stock_ring(f, 0.074 + g, -0.088 - g, 0.0215 + g, 20, 3.0))
    loft(bm, pad, RUBBER)
    # the pad's lattice: dark grey ribs standing proud on both sides
    for sx in (-1, 1):
        for k in range(6):
            z0 = -0.080 + k * 0.025
            pts = [P(sx * 0.0230, BUTT + 0.005, z0), P(sx * 0.0230, BUTT + 0.019, z0 + 0.0125),
                   P(sx * 0.0230, BUTT + 0.005, z0 + 0.025)]
            sweep(bm, pts, [(-0.0009, -0.0007), (0.0009, -0.0007), (0.0009, 0.0007), (-0.0009, 0.0007)], LATT)
    # sling studs
    for f, z in ((-0.20, -0.062), (0.45, 0.037)):
        lathe(bm, 0, 0, [(0, 0, STEEL), (0, 0.0035, STEEL), (0.010, 0.0035, STEEL), (0.010, 0.0055, STEEL),
                         (0.014, 0.0055, STEEL), (0.014, 0, STEEL)], 8,
              axis_pts=(P(0, f, z + 0.004), P(0, f, z - 0.01)))


# ------------------------------------------------------------------ action, barrel

def build_action(bm):
    # receiver: a round stainless tube, tapering tang at the rear, barrel nut in front
    lathe(bm, ACT0 - 0.012, ACT1 + 0.016, [
        (0.0, 0.0, METAL), (0.0, 0.012, METAL), (0.012, ACT_R, METAL), (0.012 + ACT1 - ACT0, ACT_R, METAL),
        (0.012 + ACT1 - ACT0, 0.0195, METAL), (0.028 + ACT1 - ACT0, 0.0195, METAL),
        (0.028 + ACT1 - ACT0, 0.0, METAL)], 20)
    # flat scope bases on top
    box(bm, -0.016, 0.016, -0.0085, 0.0085, BORE + ACT_R - 0.004, BORE + ACT_R + 0.006, ALLOY)
    box(bm, 0.084, 0.116, -0.0085, 0.0085, BORE + ACT_R - 0.004, BORE + ACT_R + 0.006, ALLOY)
    # ejection port on the RIGHT (-x): a dark frame proud of the receiver
    # trigger guard: a steel strap loop
    g = [P(0, 0.074, 0.013), P(0, 0.072, 0.000), P(0, 0.064, -0.012), P(0, 0.048, -0.019), P(0, 0.030, -0.018),
         P(0, 0.016, -0.010), P(0, 0.010, 0.000), P(0, 0.012, 0.016)]
    sweep(bm, smooth_path(g, 3), [(-0.0045, -0.0016), (0.0045, -0.0016), (0.0045, 0.0016), (-0.0045, 0.0016)], STEEL)
    # trigger blade
    tb = [P(0, 0.044, 0.016), P(0, 0.045, 0.004), P(0, 0.041, -0.006), P(0, 0.035, -0.010)]
    sweep(bm, smooth_path(tb, 3), [(-0.0028, -0.0015), (0.0028, -0.0015), (0.0028, 0.0015), (-0.0028, 0.0015)], BLUED)
    # safety on the tang
    box(bm, -0.030, -0.018, -0.0035, 0.0035, 0.052, 0.060, BLUED)
    # mag latch ahead of the guard
    box(bm, 0.076, 0.084, -0.006, 0.006, 0.000, 0.013, STEEL)


def build_barrel(bm):
    f0, f1 = ACT1 + 0.010, MUZZLE - 0.058     # barrel (to the brake)
    L = f1 - f0
    fl0, fl1 = 0.075, L - 0.012               # fluted run (t from f0)
    twist = 2 * math.pi * 0.85
    flutes, depth = 6, 0.0031

    def r_of(t):
        return 0.0148 + (0.0118 - 0.0148) * min(1.0, max(0.0, (t - 0.04) / (L - 0.04)))

    def rfun(t, th, r):
        if t <= fl0 or t >= fl1:
            return r
        k = min(1.0, (t - fl0) / 0.03, (fl1 - t) / 0.03)
        return r - depth * k * groove(th)

    def groove(ph):           # a narrow, flat-bottomed flute: walls steep enough to hold a sharp edge
        c = math.cos(flutes * ph)
        return 1.0 if c > 0.55 else (max(0.0, (c + 0.05) / 0.6))

    def mfun(t, th):
        if t <= fl0 + 0.02 or t >= fl1 - 0.02:
            return None
        return FLUTE if groove(th) > 0.5 else None

    def spin(t):
        return twist * min(1.0, max(0.0, (t - fl0) / (fl1 - fl0)))

    prof = [(0.0, 0.0, METAL)]
    n = 52
    for i in range(n + 1):
        t = L * i / n
        prof.append((t, r_of(t), METAL))
    prof.append((L, 0.0, METAL))
    lathe(bm, f0, f1, prof, 48, rfun=rfun, mfun=mfun, spin=spin)
    # muzzle brake: a slightly fatter can, crowned, ports as proud dark dots
    b0, b1 = f1 - 0.004, MUZZLE
    lathe(bm, b0, b1, [(0, 0, METAL), (0, 0.0122, METAL), (0.004, 0.0128, METAL), (b1 - b0 - 0.003, 0.0128, METAL),
                       (b1 - b0, 0.0118, METAL), (b1 - b0, 0.0048, METAL), (b1 - b0 - 0.0015, 0.0042, BLUED),
                       (b1 - b0 - 0.0015, 0.0, BLUED)], 24)
    for row in range(4):
        f = b0 + 0.012 + row * 0.011
        for k in range(10):
            th = 2 * math.pi * (k + 0.5 * (row % 2)) / 10
            if abs(math.sin(th)) > 0.92 and math.sin(th) < 0:
                continue          # none underneath
            nrm = Vector((math.cos(th), 0, math.sin(th)))
            c = P(0, f, BORE) + nrm * 0.0127
            disc_on(bm, c, nrm, 0.0026, BLUED, 6, 0.0006)


# ------------------------------------------------------------------ scope

def build_scope(bm):
    z = SC_Z
    L = SC1 - SC0
    prof = [
        (0.000, 0.0, GLASS), (0.000, 0.0170, GLASS), (0.0015, 0.0170, ALLOY),   # ocular lens, recessed
        (0.0015, 0.0192, ALLOY), (0.004, 0.0198, ALLOY), (0.040, 0.0198, ALLOY),      # eyepiece
        (0.052, 0.0175, ALLOY), (0.058, 0.0172, ALLOY),                               # power ring
        (0.060, 0.0180, ALLOY), (0.072, 0.0180, ALLOY), (0.074, 0.0172, ALLOY),
        (0.084, 0.0128, ALLOY),                                                       # into the tube
        (0.215, 0.0128, ALLOY), (0.255, 0.0235, ALLOY),                               # objective bell
        (L - 0.002, 0.0238, ALLOY), (L, 0.0230, ALLOY), (L, 0.0200, ALLOY),
        (L - 0.003, 0.0200, GLASS), (L - 0.003, 0.0, GLASS),                         # objective lens
    ]
    lathe(bm, SC0, SC1, prof, 32, z=z)
    # the gold ring on the objective bell (stands proud)
    lathe(bm, SC1 - 0.022, SC1 - 0.016, [(0, 0, BRASS), (0, 0.0243, BRASS), (0.006, 0.0243, BRASS), (0.006, 0, BRASS)],
          24, z=z)
    # turret saddle + elevation (top) + windage (right, -x)
    tc = SC0 + 0.150
    lathe(bm, tc - 0.018, tc + 0.018, [(0, 0, ALLOY), (0, 0.0150, ALLOY), (0.036, 0.0150, ALLOY), (0.036, 0, ALLOY)],
          16, z=z)
    for d in (Vector((0, 0, 1)), Vector((-1, 0, 0))):
        base = P(0, tc, z) + d * 0.006       # start inside the saddle, clear of the other stubs
        lathe(bm, 0, 0, [(0, 0, ALLOY), (0, 0.0105, ALLOY), (0.017, 0.0105, ALLOY), (0.017, 0.0118, ALLOY),
                         (0.025, 0.0118, ALLOY), (0.027, 0.0105, ALLOY), (0.027, 0, ALLOY)], 14,
              axis_pts=(base, base + d))
    # side-focus/illum stub on the left (+x)
    base = P(0, tc, z) + Vector((0.006, 0, 0))
    lathe(bm, 0, 0, [(0, 0, ALLOY), (0, 0.009, ALLOY), (0.015, 0.009, ALLOY), (0.015, 0, ALLOY)], 12,
          axis_pts=(base, base + Vector((1, 0, 0))))
    # rings and their bases down to the receiver bases
    for f in (0.000, 0.100):
        lathe(bm, f - 0.0065, f + 0.0065, [(0, 0, ALLOY), (0, 0.0152, ALLOY), (0.013, 0.0152, ALLOY), (0.013, 0, ALLOY)],
              20, z=z)
        box(bm, f - 0.0065, f + 0.0065, -0.0095, 0.0095, BORE + ACT_R + 0.004, z - 0.006, ALLOY)
        # ring cap screws (top) and the base's crossbolt nut (right)
        for sx in (-1, 1):
            box(bm, f - 0.0025, f + 0.0025, sx * 0.0128 - 0.002, sx * 0.0128 + 0.002, z + 0.004, z + 0.0085, ALLOY)
        lathe(bm, 0, 0, [(0, 0, STEEL), (0, 0.0045, STEEL), (0.004, 0.0045, STEEL), (0.004, 0, STEEL)], 6,
              axis_pts=(P(-0.0105, f, BORE + ACT_R + 0.011), P(-0.02, f, BORE + ACT_R + 0.011)))


# ------------------------------------------------------------------ moving parts

def build_bolt(bm):
    # bolt shroud behind the receiver
    lathe(bm, ACT0 - 0.046, ACT0 - 0.008, [(0, 0, METAL), (0, 0.0085, METAL), (0.006, 0.0115, METAL),
                                           (0.032, 0.0140, METAL), (0.038, 0.0140, METAL), (0.038, 0, METAL)], 16)
    # the bolt body seen through the ejection port (proud of the dark frame)
    lathe(bm, 0.050, 0.104, [(0, 0, METAL), (0, 0.0062, METAL), (0.054, 0.0062, METAL), (0.054, 0, METAL)], 12,
          x=-ACT_R + 0.0048, z=BORE + 0.0062)
    # handle: root on the bolt's right side, swept out, down and back
    pts = [P(-0.010, 0.002, BORE - 0.001), P(-0.026, 0.000, BORE - 0.004), P(-0.040, -0.006, BORE - 0.012),
           P(-0.050, -0.012, BORE - 0.024), P(-0.055, -0.016, BORE - 0.032)]
    sweep(bm, smooth_path(pts, 3), circle2(0.0052, 10), METAL)
    sphere(bm, P(-0.057, -0.018, BORE - 0.038), 0.0122, ALLOY, 14, 8)


def build_mag(bm):
    # AI-style box: body inside the well, its floorplate proud below the stock
    f0, f1 = 0.092, 0.186
    lo = -0.011
    def rr(z, hw, hl, fc):
        return [P(hw * u, fc + hl * v, z) for u, v in superellipse(20, 3.2)]
    fc, hl = (f0 + f1) * 0.5, (f1 - f0) * 0.5
    loft(bm, [rr(lo + 0.004, 0.0135, hl - 0.001, fc), rr(lo + 0.006, 0.0135, hl, fc), rr(0.040, 0.0135, hl, fc)], POLY)
    loft(bm, [rr(lo, 0.0130, hl + 0.0015, fc + 0.001), rr(lo + 0.0015, 0.0145, hl + 0.003, fc + 0.001),
              rr(lo + 0.0065, 0.0145, hl + 0.003, fc + 0.001), rr(lo + 0.008, 0.0130, hl + 0.0015, fc + 0.001)], POLY)
    # ribs on the sides (proud)
    for sx in (-1, 1):
        box(bm, f0 + 0.012, f1 - 0.012, sx * 0.0135 - 0.0008, sx * 0.0135 + 0.0008, lo + 0.010, lo + 0.014, POLY)


# ------------------------------------------------------------------ build

def part(name, fn):
    bm = bmesh.new()
    fn(bm)
    return gg.mesh_object(name, bm, ROLES)


def drop_unused(ob):
    used = {p.material_index for p in ob.data.polygons}
    keep = sorted(used)
    remap = {old: new for new, old in enumerate(keep)}
    mats = [ob.data.materials[i] for i in keep]
    idx = [remap[p.material_index] for p in ob.data.polygons]
    ob.data.materials.clear()          # (this resets the face indices, so set them after)
    for m in mats:
        ob.data.materials.append(m)
    for p, i in zip(ob.data.polygons, idx):
        p.material_index = i


def smooth_by_angle(ob, deg):
    """Smooth faces, sharp edges where the faces meet steeper than `deg`."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    lim = math.radians(deg)
    for fc in bm.faces:
        fc.smooth = True
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) != 2 or e.calc_face_angle(0.0) > lim)
    bm.to_mesh(ob.data)
    bm.free()


gg.reset()
body = part("body", lambda bm: (build_stock(bm), build_action(bm), build_barrel(bm), build_scope(bm)))
bolt = part("bolt", build_bolt)
mag = part("mag", build_mag)
for ob in (body, bolt, mag):
    drop_unused(ob)
    smooth_by_angle(ob, 38.0)

gg.marker("grip", (0, 0, 0))
gg.marker("muzzle", P(0, MUZZLE, BORE))
gg.marker("eye", P(0, SC0 - 0.08, SC_Z))
gg.marker("support", P(0, 0.33, 0.026))
gg.marker("butt", P(0, BUTT, -0.007))
gg.marker("bolt_pivot", P(0, 0.002, BORE))

meta = {"hands": 2, "socket": "hand_r", "class": "rifle", "notes": "Ruger American style bolt rifle, scoped"}
gg.finish("marksman", "item", meta)


# ------------------------------------------------------------------ extra review views

def extra_views(tag):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("XCam")
    cam = bpy.data.objects.new("XCam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    lo, hi = gg._bounds()
    c = (lo + hi) * 0.5
    # "diag": the reference's pose, the RIGHT side with the muzzle to the upper right
    a = math.radians(30)
    r = Vector((0, -math.cos(a), -math.sin(a)))
    u = Vector((0, -math.sin(a), math.cos(a)))
    zc = Vector((-1, 0, 0))
    views = {
        "diag": (c + zc * 1.55, r, u, zc, 50.0),
    }
    # "action": a close-up of the action from the right, a touch above
    fwd = Vector((1, 0.15, -0.35)).normalized()
    zc2 = -fwd
    r2 = Vector((0, -1, 0))
    r2 = (r2 - fwd * r2.dot(fwd)).normalized()
    u2 = zc2.cross(r2)
    views["action"] = (P(0, 0.08, 0.06) - fwd * 0.55, r2, u2, zc2, 50.0)
    # "muzzle": the barrel and brake close
    views["muzzle"] = (P(0, 0.62, 0.07) - fwd * 0.45, r2, u2, zc2, 50.0)
    for name, (loc, rx, uy, zz, lens) in views.items():
        m = Matrix((rx, uy, zz)).transposed().to_4x4()
        m.translation = loc
        cam.matrix_world = m
        cd.lens = lens
        cd.clip_start = 0.01
        sc.render.filepath = os.path.join(gg.SHOTS, "%s_marksman_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


if gg.arg("--views"):
    extra_views(str(gg.arg("--tag", "r0")))
