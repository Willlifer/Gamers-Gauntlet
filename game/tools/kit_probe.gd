extends SceneTree
## Headless checks for the Gauntlet Kit (G16/G17). Exit 0 when all pass.
##   godot --headless --path . --script res://tools/kit_probe.gd
## Per asset: defaults and every preset build without warnings; every
## parameter at its min and max builds; the same params give the same mesh
## (determinism); bad input is reported, not fatal; required markers exist;
## triangle budget; no inverted faces (winding against the normals it
## carries); instantiate() and free; envs have colliders and spawns.
## Then the export round trip (.glb + sidecar) and the bench's undo/redo.

const BUDGET := { "item": 12000, "env": 260000 }
const NEED := { "item": ["grip", "muzzle"], "env": ["ref_cam", "spawn_a0", "spawn_b0"] }

var fails := 0
var checks := 0


func _initialize() -> void:
	_go.call_deferred()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func _go() -> void:
	_primitives()
	for id in GKRegistry.ids():
		_asset(id)
	_bad_input()
	_export()
	await _bench()
	print("kit_probe: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _asset(id: String) -> void:
	var d := GKRegistry.def(id)
	var t0 := Time.get_ticks_msec()
	var a := d.build()
	var ms := Time.get_ticks_msec() - t0
	ok(a.warnings.is_empty(), "%s defaults warn: %s" % [id, a.warnings])
	ok(not a.parts.is_empty(), "%s builds nothing" % id)
	ok(a.triangle_count() <= int(BUDGET[a.kind]), "%s %d tris over budget %d" % [id, a.triangle_count(), BUDGET[a.kind]])
	for m in NEED[a.kind]:
		ok(a.markers.has(m), "%s lacks marker %s" % [id, m])
	var inv := inverted(a)
	ok(inv == 0, "%s has %d inverted triangles" % [id, inv])
	ok(_hash(a) == _hash(d.build()), "%s not deterministic" % id)
	if a.kind == "env":
		ok(a.colliders.size() > 10, "%s has %d colliders" % [id, a.colliders.size()])
		for c in a.colliders:
			var sz: Vector3 = c.size
			ok(sz.x > 0.0 and sz.y > 0.0 and sz.z > 0.0, "%s collider with empty size %s" % [id, sz])
			var b: Basis = (c.xform as Transform3D).basis
			ok(absf(b.determinant() - 1.0) < 0.01, "%s collider basis not a rotation" % id)
	else:
		ok(a.meta.has("hands") and a.meta.has("socket"), "%s item meta lacks hands/socket" % id)
	for pname in d.presets():
		var pa := d.build(d.preset(pname))
		ok(pa.warnings.is_empty() and not pa.parts.is_empty(), "%s preset '%s' failed %s" % [id, pname, pa.warnings])
	for e in d.schema():
		for v in _extremes(e):
			var pa := d.build({ e.key: v })
			ok(pa.warnings.is_empty() and not pa.parts.is_empty(), "%s %s=%s failed %s" % [id, e.key, v, pa.warnings])
			ok(inverted(pa) == 0, "%s %s=%s has inverted triangles" % [id, e.key, v])
	var n := a.instantiate()
	ok(n.get_child_count() >= a.parts.size(), "%s instantiate short" % id)
	n.free()
	print("%s: %d tris, %d colliders, %d ms" % [id, a.triangle_count(), a.colliders.size(), ms])


## Convex primitives: every face must look away from the centre (a face
## turned inward is culled from outside: the part looks missing).
func _primitives() -> void:
	var cases := {}
	var g := GKMesh.new()
	g.box("x", Vector3.ZERO, Vector3.ONE)
	cases["plain box"] = g
	g = GKMesh.new()
	g.box("x", Vector3.ZERO, Vector3.ONE, 0.1)
	cases["bevelled box"] = g
	g = GKMesh.new()
	g.extrude("x", PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), -0.5, 0.5, 0.05)
	cases["extrude (left-handed plane)"] = g
	g = GKMesh.new()
	g.extrude("x", PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), -0.5, 0.5, 0.0, Basis.IDENTITY)
	cases["extrude (right-handed plane)"] = g
	g = GKMesh.new()
	g.cyl("x", Vector3.ZERO, Vector3(0, 0, 1), 0.3)
	cases["cylinder"] = g
	g = GKMesh.new()
	g.loft("x", [GKMesh.station(Vector3.ZERO, 1, 1, 1), GKMesh.station(Vector3(0, 0, 1), 1, 1, 1)])
	cases["loft"] = g
	g = GKMesh.new()
	g.sphere("x", Vector3.ZERO, 1.0)
	cases["sphere"] = g
	g = GKMesh.new()
	g.push(Transform3D(Basis.from_scale(Vector3(1, 1, -1)), Vector3.ZERO))
	g.box("x", Vector3.ZERO, Vector3.ONE, 0.1)
	cases["mirrored bevelled box"] = g
	for k in cases:
		var m: ArrayMesh = (cases[k] as GKMesh).commit()
		var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var c := Vector3.ZERO
		for q in v:
			c += q
		c /= v.size()
		var inward := 0
		for i in range(0, v.size(), 3):
			var fn := (v[i + 2] - v[i]).cross(v[i + 1] - v[i])
			if fn.length_squared() > 1e-12 and fn.dot((v[i] + v[i + 1] + v[i + 2]) / 3.0 - c) < 0.0:
				inward += 1
		ok(inward == 0, "primitive %s: %d faces turned inward" % [k, inward])


func _extremes(e: Dictionary) -> Array:
	match str(e.type):
		"bool":
			return [not bool(e.default)]
		"enum":
			return (e.options as Array).filter(func(o: Variant) -> bool: return o != e.default)
		_:
			return [e.min, e.max]


## Triangles whose winding (the side the GPU treats as front) disagrees with
## the normals they carry: shows up as see-through or black faces.
static func inverted(a: GKAsset) -> int:
	var bad := 0
	for p in a.parts:
		var m: ArrayMesh = p.mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in range(0, v.size(), 3):
				var fn := (v[i + 2] - v[i]).cross(v[i + 1] - v[i])
				if fn.length_squared() < 1e-14:
					continue
				var avg := nn[i] + nn[i + 1] + nn[i + 2]
				if fn.dot(avg) < 0.0:
					bad += 1
	return bad


static func _hash(a: GKAsset) -> int:
	var h := 0
	for p in a.parts:
		var m: ArrayMesh = p.mesh
		for s in m.get_surface_count():
			var v: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			h = hash([h, m.surface_get_name(s), v.size(), v[0] if v.size() > 0 else Vector3.ZERO, v[v.size() / 2] if v.size() > 0 else Vector3.ZERO])
	return h


func _bad_input() -> void:
	var d := GKRegistry.def("sniper")
	var a := d.build({ "scale": "big", "nonsense": 3, "barrel": 99.0 })
	ok(a.warnings.size() == 2, "bad input should give 2 warnings, got %s" % [a.warnings])
	ok(is_equal_approx(float(a.params.barrel), float(d.entry("barrel").max)), "out-of-range not clamped")
	ok(GKRegistry.def("nope") == null, "unknown id should be null")


func _export() -> void:
	var dir := "user://kit_probe"
	DirAccess.make_dir_recursive_absolute(dir)
	for id in ["shotgun", "dust_mid"]:
		var a := GKRegistry.build(id)
		var path := dir.path_join(id + ".glb")
		var res := GKExport.export_glb(a, path)
		ok(res.ok, "%s export failed: %s" % [id, res.get("error", "")])
		ok(FileAccess.file_exists(path) and FileAccess.file_exists(path.get_basename() + ".json"), "%s export files missing" % id)
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		ok(doc.append_from_file(path, st) == OK, "%s glb does not load back" % id)
		var scene := doc.generate_scene(st)
		ok(scene != null and scene.find_children("*", "MeshInstance3D", true, false).size() >= a.parts.size(), "%s glb lost meshes" % id)
		if scene:
			scene.free()
		var side := JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json")) as Dictionary
		ok(side != null and str(side.get("id", "")) == id and (side.params as Dictionary).size() == a.params.size(), "%s sidecar wrong" % id)
		# the sidecar rebuilds the same asset
		if side != null:
			var again := GKRegistry.build(id, side.params)
			ok(_hash(again) == _hash(a), "%s sidecar params don't rebuild the same mesh" % id)


func _bench() -> void:
	var sc := load("res://scenes/kit_bench.tscn") as PackedScene
	ok(sc != null, "bench scene missing")
	if sc == null:
		return
	var b: Node = sc.instantiate()
	b.set("headless", true)
	root.add_child(b)
	await process_frame
	b.call("select", "sniper")
	var before: float = b.call("value", "barrel")
	b.call("set_param", "barrel", 0.7)
	ok(is_equal_approx(b.call("value", "barrel"), 0.7), "bench set_param")
	b.call("undo_step")
	ok(is_equal_approx(b.call("value", "barrel"), before), "bench undo")
	b.call("redo_step")
	ok(is_equal_approx(b.call("value", "barrel"), 0.7), "bench redo")
	b.call("apply_preset", "Black ops")
	ok(str(b.call("value", "stock")) == "black", "bench preset")
	b.call("undo_step")
	ok(str(b.call("value", "stock")) == "olive", "bench preset undo")
	# a merged drag is one undo step
	b.call("set_param", "forend", 0.2, true)
	b.call("set_param", "forend", 0.22, true)
	b.call("set_param", "forend", 0.24, true)
	b.call("undo_step")
	ok(is_equal_approx(b.call("value", "forend"), 0.27), "bench drag should undo in one step, got %s" % b.call("value", "forend"))
	var saved: bool = b.call("save_preset", "probe test")
	ok(saved, "bench save preset")
	b.call("select", "shotgun")
	b.call("select", "sniper")
	ok((b.call("user_presets") as Dictionary).has("probe test"), "bench user preset persists")
	b.call("delete_preset", "probe test")
	b.queue_free()
	await process_frame
