class_name GKAsset
extends RefCounted
## What a kit generator returns: pure data, no nodes. Meshes with their
## placement, named markers (the posing contract), collision boxes, and
## metadata. instantiate() turns it into a scene branch; nothing else in
## the kit touches the scene tree, so a game can use the data its own way.
##
## Markers are Transform3Ds in the asset's own frame. Items (kind "item")
## use the weapon frame Black | White's rig already uses: origin = centre of
## the main hand's fist, +Z = the muzzle / forward, +Y = up, +X = the
## wielder's left. Standard item markers:
##   grip      main hand (identity for items)       support   off hand
##   muzzle    where shots leave, +Z out             eye       sight line, behind the optic
##   butt      shoulder contact (long guns)          pouch     draw point (slingshot)
## Environments (kind "env") use metres on the 2.2 m Black | White rig scale,
## +Y up, and mark spawns (spawn_a*, spawn_b*) and the reference camera (ref_cam).

var id := ""
var kind := "item"               ## "item" or "env"
var version := 1                 ## the generator's version
var params := {}                 ## the exact parameters it was built from
var parts: Array[Dictionary] = []      ## { name, mesh: ArrayMesh, xform: Transform3D, shadow: bool }
var markers := {}                ## name -> Transform3D
var colliders: Array[Dictionary] = []  ## { size: Vector3, xform: Transform3D, barrier: bool } boxes; env only
## Physics layer of the invisible walls (barrier boxes, G51c): bodies that
## should be fenced in add it to their mask; shots and sight lines, which
## test the level's layer 1, pass through, so a roof edge doesn't stop a
## bullet between buildings.
const BARRIER_LAYER := 16
var trimeshes: Array[Dictionary] = []  ## { mesh: ArrayMesh, xform } concave colliders (terrain); env only
var lights := {}                 ## env only: sun, sky and fog numbers (GKStage reads them)
var meta := {}                   ## hands, socket, class, notes, budgets...
var warnings: PackedStringArray = []


func add_part(part_name: String, mesh: ArrayMesh, xform := Transform3D.IDENTITY, shadow := true) -> void:
	if mesh == null:
		return
	parts.append({ "name": part_name, "mesh": mesh, "xform": xform, "shadow": shadow })


func add_box_collider(center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	colliders.append({ "size": size.abs(), "xform": Transform3D(basis, center) })


## A box placed by any transform (scaled, rotated or mirrored): the scale
## goes into the size, the rotation is kept orthonormal and right-handed,
## so physics gets a valid shape.
func add_box_xf(xf: Transform3D, size: Vector3, barrier := false) -> void:
	var b := xf.basis
	var sc := Vector3(b.x.length(), b.y.length(), b.z.length())
	var o := Basis(b.x / sc.x, b.y / sc.y, b.z / sc.z)
	if o.determinant() < 0.0:
		o.x = -o.x                     # a box is symmetric: flip an axis back
	colliders.append({ "size": (size * sc).abs(), "xform": Transform3D(o.orthonormalized(), xf.origin), "barrier": barrier })


## A mesh that collides as itself (a ConcavePolygonShape3D): heightfield
## terrain, which boxes can't follow. Same StaticBody3D as the boxes.
func add_trimesh_collider(mesh: ArrayMesh, xform := Transform3D.IDENTITY) -> void:
	if mesh == null:
		return
	trimeshes.append({ "mesh": mesh, "xform": xform })


func triangle_count() -> int:
	var n := 0
	for p in parts:
		var m: ArrayMesh = p.mesh
		for i in m.get_surface_count():
			n += m.surface_get_array_len(i) / 3
	return n


func aabb() -> AABB:
	var out := AABB()
	var first := true
	for p in parts:
		var b: AABB = (p.xform as Transform3D) * (p.mesh as ArrayMesh).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func marker(name: String) -> Transform3D:
	return markers.get(name, Transform3D.IDENTITY)


## The asset as nodes: a Node3D with one MeshInstance3D per part, Marker3Ds
## for the markers, and (env, `with_collision`) a StaticBody3D of boxes.
## `plain` swaps the kit shader for StandardMaterial3D (export).
func instantiate(with_collision := true, plain := false) -> Node3D:
	var root := Node3D.new()
	root.name = id.to_pascal_case() if id != "" else "GKAsset"
	root.set_meta("gk_id", id)
	root.set_meta("gk_version", version)
	root.set_meta("gk_params", params.duplicate(true))
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.name = str(p.name)
		mi.mesh = p.mesh
		mi.transform = p.xform
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(p.shadow) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		GKMaterials.apply(mi, plain)
		root.add_child(mi)
	for k in markers:
		var mk := Marker3D.new()
		mk.name = str(k)
		mk.transform = markers[k]
		mk.gizmo_extents = 0.05
		root.add_child(mk)
	if with_collision and (not colliders.is_empty() or not trimeshes.is_empty()):
		var body := StaticBody3D.new()
		body.name = "Collision"
		var walls := StaticBody3D.new()           # the invisible walls, on their own layer
		walls.name = "Barriers"
		walls.collision_layer = BARRIER_LAYER
		walls.collision_mask = 0
		for t in trimeshes:
			var ts := CollisionShape3D.new()
			ts.shape = (t.mesh as ArrayMesh).create_trimesh_shape()
			ts.transform = t.xform
			body.add_child(ts)
		for c in colliders:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = c.size
			cs.shape = bs
			cs.transform = c.xform
			(walls if c.get("barrier", false) else body).add_child(cs)
		root.add_child(body)
		if walls.get_child_count() > 0:
			root.add_child(walls)
		else:
			walls.free()
	return root


## The metadata a game needs without the meshes (written beside exports).
func describe() -> Dictionary:
	var mk := {}
	for k in markers:
		var t: Transform3D = markers[k]
		mk[k] = { "origin": [snappedf(t.origin.x, 0.0001), snappedf(t.origin.y, 0.0001), snappedf(t.origin.z, 0.0001)],
			"forward": _v((t.basis.z).normalized()), "up": _v((t.basis.y).normalized()) }
	var b := aabb()
	return { "id": id, "kind": kind, "version": version, "params": params, "markers": mk,
		"tris": triangle_count(), "aabb": { "min": _v(b.position), "max": _v(b.end) },
		"colliders": colliders.size(), "trimeshes": trimeshes.size(), "meta": meta, "lights": lights }


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
