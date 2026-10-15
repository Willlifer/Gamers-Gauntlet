class_name GKGlb
extends GKDef
## A kit asset modelled in Blender (G43): game/art/gauntlet/<id>.glb plus its
## sidecar <id>.json, both written by game/tools/blender/gauntlet/gg_<id>.py
## (never hand-edit them; change the script and rebuild). This turns the
## imported scene into an ordinary GKAsset, so the view model, the kit
## shader (material names are kit roles), the probes and the bench treat it
## like a procedural item:
##   mesh objects     -> parts by name ("body", "slide", "bolt", "turret"...)
##   M_<name> empties -> markers (the empty's frame; +Z forward after export)
##   COL_<n> empties  -> box colliders (envs; scale = half extents)
##   HIDE_<n> empties -> meta.hide_volumes: walk-through cover (bushes)
## The one parameter is `scale` (the game's fit to the 2.2 m body).

const DIR := "res://art/gauntlet/"

var _id := ""
var _title := ""
var _kind := "item"
var _scale := 1.0
var _side := {}


func _init(asset_id := "", title_ := "", kind_ := "item", default_scale := 1.0) -> void:
	_id = asset_id
	_title = title_
	_kind = kind_
	_scale = default_scale


func id() -> String:
	return _id


func title() -> String:
	return _title if _title != "" else _id.capitalize()


func kind() -> String:
	return _kind


func version() -> int:
	return int(sidecar().get("version", 1))


func schema() -> Array[Dictionary]:
	return [pf("scale", "Scale", "Fit", _scale, 0.25, 3.0, 0.01)]


func presets() -> Dictionary:
	return { "Reference": {} }


func sidecar() -> Dictionary:
	if _side.is_empty():
		var f := FileAccess.open(DIR + _id + ".json", FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_side = d
	return _side


## Is the model built (so the registry can list it)?
static func exists(asset_id: String) -> bool:
	return ResourceLoader.exists(DIR + asset_id + ".glb")


func _build(p: Dictionary) -> GKAsset:
	var a := GKAsset.new()
	var s: float = p.scale
	var ps := load(DIR + _id + ".glb") as PackedScene
	if ps == null:
		a.warnings.append("no model at %s%s.glb: run its Blender script" % [DIR, _id])
		return a
	var root := ps.instantiate() as Node3D
	var fit := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3.ZERO)
	a.params = p.duplicate()
	var hide: Array = []
	for n: Node in root.find_children("*", "Node3D", true, false):
		var xf: Transform3D = fit * _rel(root, n as Node3D)
		var nm := str(n.name)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			a.add_part(nm, _baked(mi, xf))                 # baked: parts sit at identity, like the procedural items
		elif nm.begins_with("M_"):
			var mk := nm.substr(2)
			var t := xf.orthonormalized()
			if _looks(mk):
				t.basis = t.basis * Basis(Vector3.UP, PI)   # views look down -Z (Godot's camera rule)
			a.markers[mk] = t
		elif nm.begins_with("COL_"):
			a.add_box_xf(xf, Vector3.ONE * 2.0)
		elif nm.begins_with("HIDE_"):
			var b := xf.basis
			hide.append({ "center": xf.origin, "half": Vector3(b.x.length(), b.y.length(), b.z.length()),
				"basis": b.orthonormalized() })
	root.free()
	a.meta = (sidecar().get("meta", {}) as Dictionary).duplicate(true)
	a.meta["source"] = "blender"
	# the rig's names: the right hand's socket is socket_weapon_r; hands "one"/"two"
	if _kind == "item":
		var sk := str(a.meta.get("socket", ""))
		a.meta["socket"] = sk if sk.begins_with("socket_") else "socket_weapon_r"
		var h: Variant = a.meta.get("hands", 1)
		a.meta["hands"] = h if h is String else ("two" if int(h) >= 2 else "one")
	if a.meta.has("play_area"):
		a.meta["play_area"] = (a.meta["play_area"] as Array).map(func(x: Variant) -> float: return float(x) * s)
	if a.meta.has("lights"):
		a.lights = a.meta["lights"]
		a.meta.erase("lights")
	if not hide.is_empty():
		a.meta["hide_volumes"] = hide
	return a


## Spawn and camera markers are views: in Blender their forward is the look
## (local -Y, +Z after export); the kit's views look down -Z, so they turn.
static func _looks(marker_name: String) -> bool:
	for p in ["spawn_", "ref_cam", "cam", "eye_"]:
		if marker_name.begins_with(p):
			return true
	return false


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## The mesh moved into the asset frame by `xf` (vertices, normals, tangents),
## each surface named by its material (the kit role) so GKMaterials.apply
## swaps in the kit shader. A view model sets moving parts' transforms from
## identity (the bolt, the slide), so nothing may hide in the node transform.
static func _baked(mi: MeshInstance3D, xf: Transform3D) -> ArrayMesh:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return null
	var nb := xf.basis.inverse().transposed()
	var flip := xf.basis.determinant() < 0.0
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in v.size():
			v[k] = xf * v[k]
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for k in n.size():
				n[k] = (nb * n[k]).normalized()
			arr[Mesh.ARRAY_NORMAL] = n
		if arr[Mesh.ARRAY_TANGENT] != null:
			var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for k in range(0, t.size(), 4):
				var tv := (xf.basis * Vector3(t[k], t[k + 1], t[k + 2])).normalized()
				t[k] = tv.x
				t[k + 1] = tv.y
				t[k + 2] = tv.z
			arr[Mesh.ARRAY_TANGENT] = t
		if flip and arr[Mesh.ARRAY_INDEX] != null:
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for k in range(0, idx.size(), 3):
				var tmp := idx[k + 1]
				idx[k + 1] = idx[k + 2]
				idx[k + 2] = tmp
			arr[Mesh.ARRAY_INDEX] = idx
		# plain triangles, no index, like the procedural items (the probes and
		# triangle counts read every three vertices as a face)
		if arr[Mesh.ARRAY_INDEX] != null:
			var st := SurfaceTool.new()
			st.create_from_arrays(arr, src.surface_get_primitive_type(i))
			st.deindex()
			arr = st.commit_to_arrays()
		out.add_surface_from_arrays(src.surface_get_primitive_type(i), arr)
		var mat := src.surface_get_material(i)
		out.surface_set_name(i, mat.resource_name if mat else "polymer_black")
	return out
