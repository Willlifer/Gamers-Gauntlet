import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gg_common as gg

"""auto_rifle: AR-15-pattern carbine in FDE with a red dot (Gauntlet kit).

    blender -b --factory-startup --python game/tools/blender/gauntlet/gg_auto_rifle.py -- --views --tag r0

Local coordinates used below: f = metres forward of the grip fist (Blender -Y),
x = Blender X (+ = the gun's LEFT, - = RIGHT), z = up. Ref: design/ref/kit/auto_rifle.jpg.
"""

import math

import bmesh
import bpy
from mathutils import Vector

PARTS = {"body": [], "mag": [], "charging": []}

BORE = 0.091          # bore axis height above the fist
RAIL = 0.118          # top of the receiver / handguard (rail base)
RAIL_TOP = 0.127
MUZZLE = 0.607


def V(f, x, z):
    return Vector((x, -f, z))


# ------------------------------------------------------------------ mesh helpers

def _finish_bm(bm, bevel=0.0, angle=30.0, seg=1):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        lim = math.radians(angle)
        edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=seg, affect="EDGES",
                            profile=0.5, clamp_overlap=True)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def emit(bm, role, part="body", bevel=0.0, smooth_tag=None, angle=30.0, seg=1):
    _finish_bm(bm, bevel, angle, seg)
    if smooth_tag is not None:
        for fc in bm.faces:
            fc.smooth = len(fc.verts) == 4 and smooth_tag
    me = bpy.data.meshes.new("p")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(gg.mat(role))
    ob = bpy.data.objects.new("p", me)
    bpy.context.scene.collection.objects.link(ob)
    PARTS[part].append(ob)
    return ob


def _loop_faces(bm, a, b, closed=True):
    n = len(a)
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))


def side_prism(pts_fz, x0, x1, role, part="body", bevel=0.0, angle=30.0):
    """Side profile (f, z) extruded across x0..x1."""
    bm = bmesh.new()
    a = [bm.verts.new(V(f, x0, z)) for f, z in pts_fz]
    b = [bm.verts.new(V(f, x1, z)) for f, z in pts_fz]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    _loop_faces(bm, a, b)
    return emit(bm, role, part, bevel, angle=angle)


def long_prism(pts_xz, f0, f1, role, part="body", bevel=0.0, taper=None):
    """Cross-section (x, z) extruded along f0..f1 (taper=(sx, sz, cz) scales the f1 end)."""
    bm = bmesh.new()
    a = [bm.verts.new(V(f0, x, z)) for x, z in pts_xz]
    if taper:
        sx, sz, cz = taper
        b = [bm.verts.new(V(f1, x * sx, cz + (z - cz) * sz)) for x, z in pts_xz]
    else:
        b = [bm.verts.new(V(f1, x, z)) for x, z in pts_xz]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    _loop_faces(bm, a, b)
    return emit(bm, role, part, bevel)


def vert_prism(pts_fx, z0, z1, role, part="body", bevel=0.0, shift=(0.0, 0.0)):
    """Plan (f, x) extruded up z0..z1; `shift` = (df, dx) of the z0 end (lean)."""
    bm = bmesh.new()
    a = [bm.verts.new(V(f + shift[0], x + shift[1], z0)) for f, x in pts_fx]
    b = [bm.verts.new(V(f, x, z1)) for f, x in pts_fx]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    _loop_faces(bm, a, b)
    return emit(bm, role, part, bevel)


def box(f0, f1, x0, x1, z0, z1, role, part="body", bevel=0.0):
    return long_prism([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], f0, f1, role, part, bevel)


def cyl(p0, p1, r0, role, part="body", r1=None, segs=16, smooth=True, phase=0.0):
    """A closed cylinder / cone between two Blender points."""
    p0, p1 = Vector(p0), Vector(p1)
    r1 = r0 if r1 is None else r1
    ax = (p1 - p0).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = ax.cross(ref).normalized()
    w = ax.cross(u).normalized()
    bm = bmesh.new()
    a, b = [], []
    for i in range(segs):
        t = 2 * math.pi * (i + phase) / segs
        d = u * math.cos(t) + w * math.sin(t)
        a.append(bm.verts.new(p0 + d * r0))
        b.append(bm.verts.new(p1 + d * r1))
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    _loop_faces(bm, a, b)
    return emit(bm, role, part, smooth_tag=smooth)


def cyl_f(f0, f1, x, z, r, role, part="body", r1=None, segs=16, phase=0.0):
    return cyl(V(f0, x, z), V(f1, x, z), r, role, part, r1, segs, phase=phase)


def cyl_x(x0, x1, f, z, r, role, part="body", segs=12):
    return cyl(V(f, x0, z), V(f, x1, z), r, role, part, segs=segs)


def cyl_z(z0, z1, f, x, r, role, part="body", r1=None, segs=12):
    return cyl(V(f, x, z0), V(f, x, z1), r, role, part, r1, segs)


# ------------------------------------------------------------------ the rifle

def receivers():
    FDE = "anodized_fde"
    # upper receiver: flat sides, chamfered top shoulders under the rail
    up = [(-0.0200, 0.0695), (0.0200, 0.0695), (0.0222, 0.0725), (0.0222, 0.104), (0.0135, RAIL), (-0.0135, RAIL), (-0.0222, 0.104), (-0.0222, 0.0725)]
    long_prism(up, 0.0, 0.192, FDE, bevel=0.0012)
    # front of the upper: barrel nut collar
    cyl_f(0.186, 0.198, 0, BORE, 0.019, "gunmetal", segs=16)
    # forward assist housing (RIGHT side, -x) + its button
    cyl(V(0.068, -0.0205, 0.094), V(0.028, -0.0285, 0.099), 0.0098, FDE, segs=14)
    side_prism([(0.040, 0.086), (0.070, 0.086), (0.070, 0.104), (0.048, 0.104)], -0.0222, -0.0236, FDE)
    cyl(V(0.032, -0.0278, 0.0985), V(0.012, -0.0318, 0.101), 0.0076, "gunmetal", segs=12)
    for k in range(2):   # button grip rings
        t0, t1 = 0.2 + k * 0.35, 0.35 + k * 0.35
        a, b = V(0.032, -0.0278, 0.0985), V(0.012, -0.0318, 0.101)
        cyl(a.lerp(b, t0), a.lerp(b, t1), 0.0082, "gunmetal", segs=12)
    # brass deflector bump behind the port (right)
    side_prism([(0.068, 0.082), (0.086, 0.082), (0.086, 0.106), (0.072, 0.106)], -0.0222, -0.0290, FDE, bevel=0.0012)
    # ejection port cover (right): black plate standing proud, with a hinge rod and a spring latch bump
    box(0.090, 0.160, -0.0237, -0.0222, 0.080, 0.104, "alloy_black")              # port opening
    box(0.092, 0.158, -0.0249, -0.0236, 0.081, 0.099, "alloy_black", bevel=0.0006)  # dust cover (black, as in the photo)
    box(0.098, 0.108, -0.0257, -0.0248, 0.086, 0.093, "steel")              # cover latch bump
    cyl_f(0.088, 0.162, -0.0230, 0.0790, 0.0019, "steel", segs=8)                  # hinge rod

    # lower receiver: side profile (buffer tower at the rear, mag well at the front)
    lower = [(-0.020, 0.108), (-0.020, 0.082), (-0.012, 0.060), (0.000, 0.042), (0.026, 0.036), (0.098, 0.036),
             (0.102, 0.024), (0.098, 0.014), (0.208, 0.012), (0.202, 0.026), (0.188, 0.048),
             (0.192, 0.0705), (0.0, 0.0705), (0.0, 0.108)]
    side_prism(lower, -0.0198, 0.0198, FDE, bevel=0.0012)
    # mag well flare lip
    side_prism([(0.097, 0.008), (0.207, 0.006), (0.204, 0.018), (0.098, 0.020)], -0.0222, 0.0222, FDE, bevel=0.0012)
    # front pivot-pin boss
    side_prism([(0.176, 0.054), (0.194, 0.054), (0.196, 0.073), (0.172, 0.073)], -0.0226, 0.0226, FDE, bevel=0.0015)
    # trigger guard (black, integrated style): loop under the trigger
    side_prism([(0.026, 0.036), (0.036, 0.036), (0.038, 0.020), (0.090, 0.020), (0.092, 0.036),
                (0.103, 0.036), (0.103, 0.010), (0.036, 0.010), (0.026, 0.022)], -0.0095, 0.0095, FDE, bevel=0.002)
    # trigger blade
    side_prism([(0.060, 0.037), (0.066, 0.037), (0.068, 0.030), (0.066, 0.022), (0.062, 0.020),
                (0.063, 0.027), (0.060, 0.032)], -0.0035, 0.0035, "gunmetal")
    # pins across the lower (stand proud on both sides)
    for f, z in ((-0.008, 0.077), (0.183, 0.064), (0.040, 0.050), (0.064, 0.050)):
        cyl_x(-0.0232, 0.0232, f, z, 0.0034, "steel", segs=10)
    # selector levers, both sides
    for s in (-1, 1):
        side_prism([(0.004, 0.058), (0.024, 0.060), (0.026, 0.066), (0.006, 0.066)],
                   s * 0.0212, s * 0.0262, "alloy_black", bevel=0.001)
    # mag release button (RIGHT)
    box(0.092, 0.104, -0.0262, -0.0205, 0.046, 0.058, "alloy_black", bevel=0.001)
    # bolt catch paddle (LEFT)
    side_prism([(0.094, 0.064), (0.110, 0.066), (0.112, 0.080), (0.100, 0.082)], 0.0212, 0.0252, "alloy_black", bevel=0.001)


def rail(f0, f1):
    FDE = "anodized_fde"
    long_prism([(-0.0105, RAIL - 0.002), (0.0105, RAIL - 0.002), (0.0105, 0.1225), (0.0080, 0.1235),
                (-0.0080, 0.1235), (-0.0105, 0.1225)], f0, f1, FDE)
    n = int((f1 - f0 - 0.003) / 0.01)
    for i in range(n):
        a = f0 + 0.003 + i * 0.01
        long_prism([(-0.0108, 0.1225), (0.0108, 0.1225), (0.0108, 0.1250), (0.0085, RAIL_TOP),
                    (-0.0085, RAIL_TOP), (-0.0108, 0.1250)], a, a + 0.0052, FDE)


def handguard():
    FDE = "anodized_fde"
    f0, f1 = 0.192, 0.478
    sec = [(-0.0225, 0.078), (-0.0135, 0.069), (0.0135, 0.069), (0.0225, 0.078),
           (0.0225, 0.106), (0.018, RAIL - 0.001), (-0.018, RAIL - 0.001), (-0.0225, 0.106)]
    long_prism(sec, f0, f1, FDE, bevel=0.0012)
    # end cap: a slight step down at the muzzle end
    long_prism([(x * 0.93, BORE + (z - BORE) * 0.93) for x, z in sec], f1, f1 + 0.006, FDE, bevel=0.001)
    rail(-0.002, f1)
    # M-LOK slots: dark plates standing proud of each side and the bottom
    slot_l, gap = 0.036, 0.007
    starts = [0.209 + i * (slot_l + gap) for i in range(6)]
    for a in starts:
        for s in (-1, 1):
            # side slot (mid height) with a raised FDE frame around it
            box(a, a + slot_l, s * 0.0223, s * 0.0237, 0.0870, 0.0965, "alloy_black")
        box(a, a + slot_l, -0.0062, 0.0062, 0.0678, 0.0693, "alloy_black")
    # upper row of short lightening slots on the side chamfer line
    # QD sling cup at the rear of the handguard, both sides
    for s in (-1, 1):
        cyl_x(s * 0.0220, s * 0.0260, 0.200, 0.087, 0.0050, "alloy_black", segs=12)


def barrel():
    cyl_f(0.19, 0.566, 0, BORE, 0.0092, "gunmetal", r1=0.0085, segs=16)
    # muzzle brake: rings with port grooves (stand out in silhouette)
    segs = [(0.560, 0.571, 0.0118, "gunmetal"), (0.571, 0.577, 0.0096, "alloy_black"),
            (0.577, 0.585, 0.0118, "gunmetal"), (0.585, 0.591, 0.0096, "alloy_black"),
            (0.591, MUZZLE, 0.0118, "gunmetal")]
    for a, b, r, role in segs:
        cyl_f(a, b, 0, BORE, r, role, segs=16)
    # top ports (black slots on the top of the brake)
    for a in (0.5635, 0.594):
        box(a, a + 0.009, -0.0045, 0.0045, BORE + 0.0108, BORE + 0.0124, "alloy_black")


def stock():
    PB = "polymer_black"
    TUBE_Z = 0.103
    cyl_f(-0.200, -0.004, 0, TUBE_Z, 0.0158, "alloy_black", segs=16)
    cyl_f(-0.022, -0.008, 0, TUBE_Z, 0.0195, "alloy_black", segs=12, phase=0.5)   # castle nut
    cyl_f(-0.008, 0.0, 0, TUBE_Z - 0.001, 0.021, "alloy_black", segs=16)          # end plate
    # Magpul-style stock: side profile, tall butt, slanted underside, toe step
    prof = [(-0.248, 0.120), (-0.118, 0.120), (-0.104, 0.117), (-0.100, 0.110), (-0.100, 0.086),
            (-0.134, 0.084), (-0.168, 0.066), (-0.196, 0.044), (-0.206, 0.040), (-0.222, 0.040),
            (-0.228, 0.026), (-0.248, 0.026)]
    side_prism(prof, -0.0205, 0.0205, PB, bevel=0.003, angle=25)
    # cheek riser ramp on top
    side_prism([(-0.248, 0.119), (-0.150, 0.119), (-0.168, 0.1255), (-0.248, 0.1255)], -0.0175, 0.0175, PB, bevel=0.002)
    # sling cut on the side: dark inset standing proud
    for s in (-1, 1):   # QD sling cup at the rear of the stock
        cyl_x(s * 0.0220, s * 0.0255, -0.232, 0.060, 0.0055, "alloy_black", segs=12)
    # thick butt pad
    side_prism([(-0.262, 0.127), (-0.247, 0.127), (-0.247, 0.025), (-0.262, 0.025)], -0.0225, 0.0225, "rubber", bevel=0.004)
    # adjustment lever under the front of the stock
    for s in (-1, 1):   # raised side panel (stepped sides like the photo)
        side_prism([(-0.240, 0.040), (-0.212, 0.044), (-0.180, 0.064), (-0.150, 0.082), (-0.118, 0.090),
                    (-0.118, 0.110), (-0.240, 0.110)], s * 0.0203, s * 0.0222, PB, bevel=0.0012)


def pistol_grip():
    # MOE-style grip, angled back; origin (the fist) sits inside it
    # raked ~22 degrees back like the photo (bottom toward the butt)
    g = [(-0.034, 0.040), (0.031, 0.040), (0.030, 0.026), (0.021, 0.012), (0.022, 0.000),
         (0.014, -0.014), (0.014, -0.030), (0.005, -0.044), (-0.002, -0.058), (-0.010, -0.064),
         (-0.032, -0.064), (-0.036, -0.055), (-0.026, -0.020), (-0.020, 0.010), (-0.024, 0.022),
         (-0.034, 0.033)]
    # slim it fore-aft toward the front edge (photo: ~45% of its length at the top)
    g = [(f + (0.026 - 0.4 * z - f) * 0.18 if f < 0 else f, z) for f, z in g]
    side_prism(g, -0.0128, 0.0128, "polymer_black", bevel=0.004, angle=25)
    # bottom cap
    side_prism([(-0.009, -0.060), (-0.002, -0.060), (-0.008, -0.069), (-0.026, -0.069), (-0.030, -0.060)],
               -0.012, 0.012, "polymer_black", bevel=0.002)


def foregrip():
    """Magpul RVG-style: short, squarish, a flared hand stop at the bottom."""
    fc = 0.405

    def sq(hf, hx, c=0.005):
        return [(fc - hf + c, -hx), (fc + hf - c, -hx), (fc + hf, -hx + c), (fc + hf, hx - c),
                (fc + hf - c, hx), (fc - hf + c, hx), (fc - hf, hx - c), (fc - hf, -hx + c)]
    vert_prism(sq(0.0158, 0.0128), -0.010, 0.064, "polymer_black", bevel=0.0015)
    # clamp base on the handguard bottom
    box(fc - 0.024, fc + 0.024, -0.013, 0.013, 0.062, 0.0695, "polymer_black", bevel=0.0015)
    # finger ridges
    for z in (0.008, 0.023, 0.038):
        vert_prism(sq(0.0171, 0.0140), z, z + 0.006, "polymer_black")
    # flared hand stop
    vert_prism(sq(0.0188, 0.0151, 0.006), -0.018, -0.008, "polymer_black", bevel=0.002)


def optic():
    AB = "alloy_black"
    zc = 0.171
    r = 0.0158
    f0, f1 = 0.100, 0.160
    # riser mount
    side_prism([(0.100, RAIL_TOP), (0.160, RAIL_TOP), (0.150, 0.158), (0.110, 0.158)], -0.0095, 0.0095, AB, bevel=0.002)
    box(0.100, 0.160, -0.0135, 0.0135, RAIL_TOP - 0.004, RAIL_TOP + 0.006, AB, bevel=0.0012)   # rail clamp
    cyl_x(-0.0135, -0.0215, 0.130, 0.128, 0.0062, AB, segs=12)      # clamp knob (right)
    cyl_x(0.0135, 0.0165, 0.130, 0.128, 0.004, AB, segs=8)          # bolt head (left)
    # tube body with front/rear bells
    cyl_f(f0, f1, 0, zc, r, AB, segs=20)
    cyl_f(f1 - 0.010, f1 + 0.002, 0, zc, r + 0.0018, AB, segs=20)
    cyl_f(f0 - 0.002, f0 + 0.008, 0, zc, r + 0.0012, AB, segs=20)
    # lenses (stand proud of the end faces)
    cyl_f(f1 + 0.002, f1 + 0.0032, 0, zc, r - 0.003, "glass_lens", segs=20)
    cyl_f(f0 - 0.0032, f0 - 0.002, 0, zc, r - 0.003, "glass_lens", segs=20)
    # turrets: elevation on top, windage on the RIGHT, battery/brightness on the LEFT
    cyl_z(zc + r - 0.002, zc + r + 0.0085, 0.131, 0, 0.0075, AB, segs=12)
    cyl_x(-(r - 0.002), -(r + 0.0085), 0.131, zc, 0.0075, AB, segs=12)
    cyl_x(r - 0.002, r + 0.0065, 0.128, zc, 0.0095, AB, segs=12)
    # turret housing block
    box(0.120, 0.142, -0.0172, 0.0172, zc - 0.010, zc + 0.0172, AB, bevel=0.002)


def sights():
    AB = "alloy_black"
    # rear flip-up, folded, at the rear of the upper rail
    side_prism([(0.006, RAIL_TOP), (0.040, RAIL_TOP), (0.040, 0.136), (0.010, 0.137)], -0.0115, 0.0115, AB, bevel=0.0012)
    side_prism([(0.010, 0.136), (0.038, 0.136), (0.036, 0.143), (0.016, 0.145), (0.010, 0.142)], -0.0095, 0.0095, AB, bevel=0.001)
    # front flip-up, folded, at the end of the handguard rail
    side_prism([(0.436, RAIL_TOP), (0.470, RAIL_TOP), (0.468, 0.137), (0.440, 0.138)], -0.0115, 0.0115, AB, bevel=0.0012)
    side_prism([(0.434, 0.137), (0.468, 0.136), (0.466, 0.142), (0.446, 0.148), (0.436, 0.146)], -0.0085, 0.0085, AB, bevel=0.001)


def magazine():
    PB = "polymer_black"
    # PMAG-style curved body: well portion (hidden) + a tail curving forward
    prof = [(0.112, 0.068), (0.186, 0.068), (0.186, 0.010), (0.189, -0.018), (0.194, -0.046),
            (0.205, -0.074), (0.216, -0.098), (0.153, -0.104), (0.145, -0.082), (0.138, -0.054),
            (0.128, -0.026), (0.119, 0.000), (0.112, 0.020)]
    side_prism(prof, -0.0135, 0.0135, PB, part="mag", bevel=0.0018)
    # floor plate (wider, with lip), tilted with the curve
    side_prism([(0.150, -0.100), (0.218, -0.094), (0.223, -0.104), (0.218, -0.112), (0.154, -0.117), (0.146, -0.109)],
               -0.0155, 0.0155, PB, part="mag", bevel=0.002)
    # grip ribs near the bottom (stand proud)
    for z, fa, fb in ((-0.052, 0.136, 0.197), (-0.064, 0.140, 0.200), (-0.076, 0.143, 0.203)):
        side_prism([(fa, z), (fb, z), (fb + 0.002, z + 0.0045), (fa + 0.002, z + 0.0045)], -0.0145, 0.0145, PB, part="mag")
    # dot-matrix panel (raised frame) high on each side
    for s in (-1, 1):
        side_prism([(0.126, -0.006), (0.183, -0.006), (0.188, -0.028), (0.134, -0.028)], s * 0.0134, s * 0.0144, PB, part="mag")


def charging_handle():
    AB = "alloy_black"
    # T-handle at the rear of the upper, latch wing on the left
    box(-0.026, 0.002, -0.0075, 0.0075, 0.104, 0.117, AB, part="charging", bevel=0.001)
    side_prism([(-0.030, 0.103), (-0.016, 0.103), (-0.011, 0.119), (-0.030, 0.119)], -0.029, 0.029, AB, part="charging", bevel=0.0015)
    side_prism([(-0.024, 0.106), (-0.012, 0.106), (-0.010, 0.116), (-0.024, 0.117)], 0.026, 0.031, AB, part="charging", bevel=0.001)
    box(0.002, 0.060, -0.0045, 0.0045, 0.108, 0.115, AB, part="charging")   # shaft under the rail


def build():
    receivers()
    handguard()
    barrel()
    stock()
    pistol_grip()
    foregrip()
    optic()
    sights()
    magazine()
    charging_handle()
    for name, objs in PARTS.items():
        gg.join(name, objs)
    gg.marker("grip", (0, 0, 0))
    gg.marker("muzzle", V(MUZZLE, 0, BORE))
    gg.marker("eye", V(0.100 - 0.08, 0, 0.171))
    gg.marker("support", V(0.405, 0, 0.026))
    gg.marker("butt", V(-0.262, 0, 0.076))
    gg.marker("mag_pivot", V(0.186, 0, 0.068))
    gg.marker("charging_pivot", V(0.002, 0, 0.110))


gg.reset()
build()
gg.finish("auto_rifle", "item", {"hands": 2, "socket": "hand_r", "class": "rifle",
                                 "notes": "AR-15 pattern automatic rifle, FDE, red dot"})
