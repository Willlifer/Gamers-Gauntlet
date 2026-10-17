"""Gauntlet kit, Blender side (G43): the shared contract every gg_<id>.py uses.

    blender -b --factory-startup --python game/tools/blender/gauntlet/gg_<id>.py [-- --tag r1 --views]

A model script builds its asset at real size in metres, then calls
`finish(id, kind, meta)`, which:
  * recalculates normals outward and counts triangles,
  * writes game/art/gauntlet/<id>.glb (+Y up glTF) and <id>.json (the sidecar),
  * saves game/art/source/gauntlet/<id>.blend,
  * with `--views`, renders the review views to design/shots/kit/<tag>_<id>_<view>.png.
The Godot side is GKGlb (src/kit/gk_glb.gd): it loads the .glb and hands the
game an ordinary GKAsset (parts, markers, colliders), so the kit shader, the
view model, the probes and the bench all work unchanged.

FRAMES (read this before modelling)
  Items (guns): the weapon frame. Origin = centre of the main hand's fist on
  the grip. In BLENDER: the muzzle points -Y, up is +Z, +X is the gun's LEFT
  side (so the glTF export lands it in Godot as +Z forward, +Y up, +X left,
  the frame every kit item uses). Real size in metres; the game scales it.
  Props (the tank): origin on the ground under the hull's centre, the front
  toward -Y, up +Z.
  Envs (maps): metres, ground at z = 0, +Z up; any heading.

NAMING (the loader reads names, nothing else)
  Mesh objects        -> parts, by object name: "body", plus moving parts the
                         game animates ("slide", "bolt", "mag", "turret", "gun"...).
                         Parent them to nothing; the loader keeps world placement.
  Materials           -> the kit's material ROLE names (ROLES below, or
                         "role:#rrggbb" to recolour a role). The game swaps in
                         its own shader by that name; colours here are only for
                         Blender's review renders.
  Empties "M_<name>"  -> markers. Their local -Y is the marker's forward (Godot
                         +Z), local +Z its up. Use marker(name, loc, fwd, up).
                         Items need M_grip (at the origin, identity) and M_muzzle;
                         guns with sights also M_eye (on the sight line, behind
                         the rear sight / optic, looking forward), M_support
                         (the off hand), long guns M_butt. Moving parts get a
                         pivot marker (M_bolt_pivot, M_slide_pivot, M_turret_pivot...).
  Empties "COL_<n>"   -> (envs) box colliders: an empty of display type CUBE,
                         its scale = the box's half-extents, any rotation.
  Empties "HIDE_<n>"  -> (envs) walk-through hiding volumes (bushes): same as COL.
  Envs also need M_spawn_a0.., M_spawn_b0.. (looking at the fight) and M_ref_cam.
  Views (M_spawn_*, M_ref_cam, M_cam*, M_eye_*): give marker() the LOOK
  direction as fwd; the loader turns them to Godot's camera rule (look -Z).

Determinism: no randomness without a fixed seed; same script, same file.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ROOT = os.path.dirname(GAME)
ART = os.path.join(GAME, "art", "gauntlet")
SRC = os.path.join(GAME, "art", "source", "gauntlet")
SHOTS = os.path.join(ROOT, "design", "shots", "kit")
REF = os.path.join(ROOT, "design", "ref", "kit")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(flag, fallback=None):
    if flag in ARGS:
        i = ARGS.index(flag)
        if i + 1 < len(ARGS) and not ARGS[i + 1].startswith("--"):
            return ARGS[i + 1]
        return True
    return fallback


# The kit's roles with their review colours (game/src/kit/gk_materials.gd is
# the truth in game; keep names in step). (base colour hex, roughness, metallic)
ROLES = {
    "gunmetal": ("#26292d", 0.3, 0.85), "blued": ("#1a1d22", 0.22, 0.9), "steel": ("#8a8d90", 0.35, 1.0),
    "alloy_black": ("#18191b", 0.42, 0.65), "polymer_black": ("#111213", 0.62, 0.0),
    "polymer_olive": ("#4a5536", 0.6, 0.0), "rubber": ("#19191a", 0.92, 0.0), "glass_lens": ("#1c3440", 0.05, 0.0),
    "brass": ("#b08d4a", 0.3, 1.0), "orange_tip": ("#e0601c", 0.6, 0.0), "leather_black": ("#1b1a19", 0.68, 0.0),
    "plaster_white": ("#c6c1b8", 0.95, 0.0), "sandstone": ("#c4a273", 0.95, 0.0), "concrete": ("#a7a49c", 0.92, 0.0),
    "concrete_light": ("#c3c0b8", 0.92, 0.0), "asphalt": ("#4a4c4e", 0.95, 0.0), "grass": ("#8a9558", 1.0, 0.0),
    "hedge": ("#3f5f2a", 1.0, 0.0), "foliage": ("#4f7a2e", 1.0, 0.0), "brick_red": ("#8a4a3a", 0.95, 0.0),
    "brick_tan": ("#d8c5a0", 0.95, 0.0), "window_dark": ("#20262a", 0.12, 0.0), "window_frame": ("#dcdad5", 0.6, 0.0),
    "wood_old": ("#7b6248", 0.9, 0.0), "wood_pole": ("#8a7253", 0.9, 0.0), "iron_dark": ("#3a3b3c", 0.6, 0.7),
    "roof_membrane": ("#3a4350", 0.9, 0.0), "flagstone": ("#c4b69c", 0.9, 0.0), "tyre": ("#1a1a1b", 0.9, 0.0),
    "car_paint": ("#2a2d33", 0.25, 0.6), "sign_white": ("#e9e6df", 0.6, 0.0), "sign_red": ("#c73a2c", 0.6, 0.0),
    # Gauntlet additions (G43); gk_materials.gd carries the same names
    "steel_bright": ("#c8cbce", 0.18, 1.0), "polymer_fde": ("#a08a66", 0.6, 0.0), "anodized_fde": ("#9c8562", 0.45, 0.4),
    "polymer_speckle": ("#5a5e66", 0.75, 0.0), "polymer_clear": ("#3a3026", 0.25, 0.0), "paint_army": ("#4d5a3c", 0.7, 0.1),
    "track_rubber": ("#1c1d1e", 0.9, 0.0), "roof_slate": ("#5a5f66", 0.85, 0.0), "roof_copper": ("#5f8a78", 0.6, 0.4),
    "stone_grey": ("#a8a59c", 0.92, 0.0), "path_concrete": ("#bdb8ad", 0.92, 0.0), "foliage_autumn": ("#c8761e", 1.0, 0.0),
    "foliage_red": ("#a8381e", 1.0, 0.0), "foliage_gold": ("#d0a020", 1.0, 0.0), "bark": ("#4a3a2c", 0.95, 0.0),
    "paint_splat": ("#e0308a", 0.5, 0.0), "net": ("#2a2a2a", 0.9, 0.0),
    "polymer_checker": ("#151515", 0.7, 0.0),   # G61: diamond-checkered grip panels (the kit shader draws the diamonds)
}


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(role):
    """The material for a kit role ("role" or "role:#hex"), made once."""
    m = bpy.data.materials.get(role)
    if m:
        return m
    base = role.split(":")[0]
    col, rough, metal = ROLES.get(base, ("#808080", 0.8, 0.0))
    if ":" in role:
        col = role.split(":", 1)[1]
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    rgb = _lin(_hex(col))
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*rgb, 1.0)            # workbench "material" colour
    m.roughness = rough
    m.metallic = metal
    return m


def marker(name, loc, fwd=(0, -1, 0), up=(0, 0, 1)):
    """An M_<name> empty at `loc` whose local -Y points along `fwd`, +Z along `up`."""
    f = Vector(fwd).normalized()
    u = Vector(up).normalized()
    u = (u - f * u.dot(f)).normalized()
    y = -f
    x = y.cross(u).normalized()
    m = Matrix((x, y, u)).transposed().to_4x4()
    m.translation = Vector(loc)
    e = bpy.data.objects.new("M_" + name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = 0.03
    e.matrix_world = m
    bpy.context.scene.collection.objects.link(e)
    return e


def box_volume(prefix, center, half, rot_z=0.0):
    """COL_/HIDE_ box: an empty cube, scale = half extents, turned about Z (radians)."""
    n = len([o for o in bpy.data.objects if o.name.startswith(prefix + "_")])
    e = bpy.data.objects.new("%s_%d" % (prefix, n), None)
    e.empty_display_type = "CUBE"
    e.empty_display_size = 1.0
    e.location = Vector(center)
    e.rotation_euler = (0.0, 0.0, rot_z)
    e.scale = Vector(half)
    bpy.context.scene.collection.objects.link(e)
    return e


def mesh_object(name, bm, role_for_faces=None):
    """Turn a bmesh into a mesh object named `name` (a part). Faces keep the
    material index they were given; pass `role_for_faces` = [roles] in index order."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for r in (role_for_faces or []):
        me.materials.append(mat(r))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def join(name, objs):
    """Join objects into one part named `name` (materials kept)."""
    objs = [o for o in objs if o]
    if not objs:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def _clean(ob):
    """Apply modifiers and transforms, recalc normals outward, triangulate-count."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for md in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=md.name)
        except RuntimeError:
            ob.modifiers.remove(md)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    bm.free()
    ob.data.update()
    return tris


def finish(asset_id, kind="item", meta=None, version=1):
    """Validate, export the .glb + sidecar + .blend, and render views on --views."""
    meta = dict(meta or {})
    os.makedirs(ART, exist_ok=True)
    os.makedirs(SRC, exist_ok=True)
    parts = {}
    tris = 0
    for ob in list(bpy.data.objects):
        if ob.type == "MESH":
            ob.parent = None if ob.parent is None else ob.parent
            n = _clean(ob)
            parts[ob.name] = n
            tris += n
            if not ob.data.materials:
                ob.data.materials.append(mat("polymer_black"))
    markers = sorted(o.name[2:] for o in bpy.data.objects if o.type == "EMPTY" and o.name.startswith("M_"))
    need = {"item": ["grip", "muzzle"], "prop": ["muzzle"], "env": ["ref_cam", "spawn_a0", "spawn_b0"]}[kind]
    missing = [m for m in need if m not in markers]
    if missing:
        raise SystemExit("gg %s: missing markers %s" % (asset_id, missing))
    glb = os.path.join(ART, asset_id + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True, export_apply=True,
                              use_selection=False, export_cameras=False, export_lights=False)
    side = {"id": asset_id, "kind": kind, "version": version, "tris": tris, "parts": parts, "markers": markers,
            "colliders": len([o for o in bpy.data.objects if o.name.startswith("COL_")]),
            "hide_volumes": len([o for o in bpy.data.objects if o.name.startswith("HIDE_")]), "meta": meta}
    with open(os.path.join(ART, asset_id + ".json"), "w", encoding="utf-8") as fh:
        json.dump(side, fh, indent=1, sort_keys=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, asset_id + ".blend"))
    print("gg %s: %d tris, parts %s, markers %s" % (asset_id, tris, list(parts), markers))
    if arg("--views"):
        render_views(asset_id, kind, str(arg("--tag", "r0")))
    return side


# ------------------------------------------------------------------ review renders

def _bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


VIEWS = {
    # name: (direction FROM the target TO the camera, in Blender axes), for items/props
    "right": (-1.0, 0.0, 0.0),        # the gun's right side (muzzle to the image's right)
    "left": (1.0, 0.0, 0.0),
    "top": (0.0, 0.0, 1.0),
    "q_front": (-0.8, -0.9, 0.55),
    "q_rear": (0.8, 0.9, 0.45),
}


def render_views(asset_id, kind, tag, views=None, size=(1200, 800), engine="BLENDER_EEVEE_NEXT"):
    """Review renders with simple studio light on a pale ground; returns the paths.
    Envs: an overview from M_ref_cam plus a high oblique; pass `views` as
    {name: (location, look_at)} for custom envs cameras."""
    os.makedirs(SHOTS, exist_ok=True)
    sc = bpy.context.scene
    try:
        sc.render.engine = engine
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.film_transparent = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.72, 0.74, 0.78, 1.0)
    bg.inputs["Strength"].default_value = 0.9
    try:
        sc.view_settings.view_transform = "AgX"
    except TypeError:
        pass
    if not any(o.type == "LIGHT" for o in bpy.data.objects):
        for nm, rot, en in (("Key", (math.radians(50), 0, math.radians(35)), 4.0), ("Fill", (math.radians(60), 0, math.radians(-140)), 1.5)):
            ld = bpy.data.lights.new(nm, "SUN")
            ld.energy = en
            lo = bpy.data.objects.new(nm, ld)
            lo.rotation_euler = rot
            sc.collection.objects.link(lo)
    lo, hi = _bounds()
    c = (lo + hi) * 0.5
    r = max((hi - lo).length * 0.5, 0.05)
    cam_d = bpy.data.cameras.new("ReviewCam")
    cam = bpy.data.objects.new("ReviewCam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    out = []
    if views is None:
        if kind == "env":
            rc = bpy.data.objects.get("M_ref_cam")
            views = {}
            if rc:
                views["ref_cam"] = (rc.matrix_world.translation, rc.matrix_world.translation - rc.matrix_world.to_3x3() @ Vector((0, 1, 0)) * 50.0)
            views["overview"] = (c + Vector((-0.55, -0.8, 0.75)).normalized() * r * 1.6, c)
            views["top"] = (c + Vector((0, 0, r * 2.2)), c)
        else:
            views = {k: (c + Vector(v).normalized() * r * 4.2, c) for k, v in VIEWS.items()}
    for name, (loc, look) in views.items():
        loc, look = Vector(loc), Vector(look)
        cam.location = loc
        d = (look - loc).normalized()
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        cam_d.lens = 50.0 if kind != "env" else 24.0
        cam_d.clip_end = 5000.0
        cam_d.clip_start = 0.01 if kind != "env" else 0.1
        path = os.path.join(SHOTS, "%s_%s_%s.png" % (tag, asset_id, name))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        out.append(path)
    bpy.data.objects.remove(cam)
    print("gg %s views: %s" % (asset_id, ", ".join(os.path.basename(p) for p in out)))
    return out
