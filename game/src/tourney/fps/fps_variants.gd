class_name FpsVariants
extends RefCounted
## Extraction: a gun variant dressed at runtime, no new Blender model. apply()
## copies the base GKAsset, retints its furniture (the surfaces are renamed to
## the dress's role, and GKMaterials.apply reads surface names, "role:#hex"
## included) and builds kit attachments (GKMesh) onto the markers, so a
## variant reads at a glance in hand, in the bot's hands and on the ground.
## The weapon frame: +Z the muzzle, +Y up, metres x the build scale (`sc`);
## mod sizes are model metres, markers already scaled.
##   suppressor   a can at `muzzle` along +Z (len, r)       muzzle moves out
##   brake        a slotted muzzle brake at `muzzle`        muzzle moves out
##   long_barrel  a barrel extension at `muzzle` (len, r)   muzzle moves out
##   light        a flashlight under the muzzle (pistols)
##   red_dot      an open reflex sight over the body at `at` (z), its axis
##                `axis` or the body's top there + the riser; `size` scales
##                it (a pistol dot 0.6); eye_back sets `eye`
##   scope        a tube scope on rings at `at` (len, r); sets `eye`; the spec
##                gives `lens` [eye_back - 0.001, r + 0.001] for the picture
##   drum         replaces the `mag` part: a stub into the well and a drum
##   ext_mag      lengthens the `mag` part downward (len); no mag part (the
##                Desert Eagle): a floorplate box under the grip (w, d, z)
##   stock        a pad at `butt` extending back (len, w, h); butt moves back
## Results are cached per base id + params + dress.

const FURNITURE := ["polymer_black", "polymer_olive", "polymer_fde", "polymer_speckle", "anodized_fde", "polymer_clear"]

static var _cache := {}


## The variant `id`'s asset: its spec's base asset dressed (or plain when it
## has no dress). FpsViewmodel, FpsBot and the loot go through here.
static func build(id: String) -> GKAsset:
	var sp := FpsWeapons.spec(id)
	var a := GKRegistry.build(str(sp.asset), sp.params)
	if a == null or not sp.has("dress"):
		return a
	return apply(a, sp.dress)


## A copy of `base` dressed by `dress` ({ tint, tint_of, mods }).
static func apply(base: GKAsset, dress: Dictionary) -> GKAsset:
	var key := "%s|%s|%s" % [base.id, base.params, dress]
	if _cache.has(key):
		return _cache[key]
	var a := _copy(base)
	var tint := str(dress.get("tint", ""))
	if tint != "":
		var of: Array = dress.get("tint_of", FURNITURE)
		for p in a.parts:
			p.mesh = _retint(p.mesh, of, tint)
	var sc := float(base.params.get("scale", 1.0))
	for m: Dictionary in dress.get("mods", []):
		var g := GKMesh.new()
		var part_name := "mod_" + str(m.kind)
		match str(m.kind):
			"suppressor":
				_suppressor(g, a, m, sc)
			"brake":
				_brake(g, a, m, sc)
			"long_barrel":
				_long_barrel(g, a, m, sc)
			"light":
				_light(g, a, m, sc)
			"red_dot":
				_red_dot(g, a, m, sc)
			"scope":
				_scope(g, a, m, sc)
			"drum":
				_drum(g, a, m, sc)
				part_name = "mag"
			"ext_mag":
				_ext_mag(g, a, m, sc)
			"stock":
				_stock(g, a, m, sc)
			_:
				a.warnings.append("FpsVariants: unknown mod '%s'" % m.kind)
		var mesh := g.commit()
		if mesh:
			a.add_part(part_name, mesh)
	a.meta["dress"] = dress.duplicate(true)
	_cache[key] = a
	return a


static func _copy(base: GKAsset) -> GKAsset:
	var a := GKAsset.new()
	a.id = base.id
	a.kind = base.kind
	a.version = base.version
	a.params = base.params.duplicate(true)
	for p in base.parts:
		a.parts.append(p.duplicate())
	a.markers = base.markers.duplicate()
	for c in base.colliders:
		a.colliders.append(c.duplicate())
	a.lights = base.lights.duplicate(true)
	a.meta = base.meta.duplicate(true)
	a.warnings = base.warnings.duplicate()
	return a


## The mesh with every surface whose base role is in `of` renamed to `tint`.
static func _retint(src: ArrayMesh, of: Array, tint: String) -> ArrayMesh:
	var hit := false
	for i in src.get_surface_count():
		if GKMaterials._base(src.surface_get_name(i)) in of:
			hit = true
	if not hit:
		return src
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var nm := src.surface_get_name(i)
		out.add_surface_from_arrays(src.surface_get_primitive_type(i), src.surface_get_arrays(i))
		out.surface_set_name(i, tint if GKMaterials._base(nm) in of else nm)
	return out


## The highest point of the body near z (asset metres), within `hw` of the
## centreline: where a sight's riser lands.
static func _top_at(a: GKAsset, z: float, hw: float, dz: float) -> float:
	var top := -INF
	for p in a.parts:
		if str(p.name) != "body" and str(p.name) != "slide":
			continue
		var m: ArrayMesh = p.mesh
		for i in m.get_surface_count():
			var v: PackedVector3Array = m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for q in v:
				if absf(q.z - z) < dz and absf(q.x) < hw and q.y > top:
					top = q.y
	return top if top > -INF else 0.1


## The lowest point of a part (the mag's foot, the grip's heel).
static func _bottom(a: GKAsset, part_name: String) -> Dictionary:
	for p in a.parts:
		if str(p.name) == part_name:
			var b: AABB = (p.mesh as ArrayMesh).get_aabb()
			return { "y": b.position.y, "c": b.get_center(), "size": b.size }
	return {}


static func _move_muzzle(a: GKAsset, dz: float) -> void:
	var t := a.marker("muzzle")
	t.origin.z += dz
	a.markers["muzzle"] = t
	if a.meta.has("length"):
		a.meta["length"] = float(a.meta.length) + dz


static func _suppressor(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var mz := a.marker("muzzle").origin
	var ln := float(m.get("len", 0.17)) * sc
	var r := float(m.get("r", 0.019)) * sc
	var role := str(m.get("role", "alloy_black"))
	var z0 := mz.z - 0.012 * sc
	g.lathe(role, Vector3(mz.x, mz.y, z0), Vector3(mz.x, mz.y, z0 + ln + 0.012 * sc), [
		Vector2(0.0, r * 0.7), Vector2(0.006 * sc, r * 0.92), Vector2(0.012 * sc, r), Vector2(ln - 0.004 * sc, r), Vector2(ln + 0.004 * sc, r * 0.9), Vector2(ln + 0.012 * sc, r * 0.78)], 18)
	g.cyl("rubber", Vector3(mz.x, mz.y, z0 + ln + 0.0121 * sc), Vector3(mz.x, mz.y, z0 + ln + 0.0135 * sc), r * 0.32, 12)   # the bore
	g.tube("rubber", [Vector3(mz.x, mz.y, mz.z + ln * 0.35), Vector3(mz.x, mz.y, mz.z + ln * 0.42)], [r + 0.0006 * sc, r + 0.0006 * sc], 18, false)   # a wrap band
	_move_muzzle(a, ln + 0.002 * sc)


static func _brake(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var mz := a.marker("muzzle").origin
	var ln := float(m.get("len", 0.055)) * sc
	var r := float(m.get("r", 0.016)) * sc
	var role := str(m.get("role", "gunmetal"))
	var z0 := mz.z - 0.008 * sc
	g.lathe(role, Vector3(mz.x, mz.y, z0), Vector3(mz.x, mz.y, z0 + ln + 0.008 * sc), [
		Vector2(0.0, r * 0.75), Vector2(0.004 * sc, r), Vector2(ln + 0.003 * sc, r), Vector2(ln + 0.008 * sc, r * 0.8)], 14)
	# the ports: dark slots down both sides, and the bore
	var n := int(m.get("ports", 3))
	for k in n:
		var z := z0 + 0.014 * sc + (ln - 0.02 * sc) * (float(k) + 0.5) / float(n)
		for sx in [-1.0, 1.0]:
			g.box("rubber", Vector3(mz.x + sx * r * 0.92, mz.y + r * 0.1, z), Vector3(r * 0.3, r * 0.9, 0.006 * sc))
	g.cyl("rubber", Vector3(mz.x, mz.y, z0 + ln + 0.0081 * sc), Vector3(mz.x, mz.y, z0 + ln + 0.0095 * sc), r * 0.4, 12)
	_move_muzzle(a, ln + 0.002 * sc)


static func _long_barrel(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var mz := a.marker("muzzle").origin
	var ln := float(m.get("len", 0.12)) * sc
	var r := float(m.get("r", 0.012)) * sc
	var role := str(m.get("role", "blued"))
	g.lathe(role, Vector3(mz.x, mz.y, mz.z - 0.02 * sc), Vector3(mz.x, mz.y, mz.z + ln), [
		Vector2(0.0, r * 1.15), Vector2(0.012 * sc, r * 1.15), Vector2(0.016 * sc, r), Vector2(ln + 0.02 * sc - 0.004 * sc, r), Vector2(ln + 0.02 * sc, r * 0.85)], 16)
	g.cyl("rubber", Vector3(mz.x, mz.y, mz.z + ln + 0.0001), Vector3(mz.x, mz.y, mz.z + ln + 0.0015 * sc), r * 0.42, 12)
	_move_muzzle(a, ln)


static func _light(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var mz := a.marker("muzzle").origin
	var ln := float(m.get("len", 0.04)) * sc
	var r := float(m.get("r", 0.011)) * sc
	var y := mz.y - float(m.get("drop", 0.034)) * sc
	var z1 := mz.z - 0.004 * sc
	g.lathe("alloy_black", Vector3(mz.x, y, z1 - ln), Vector3(mz.x, y, z1), [
		Vector2(0.0, r * 0.8), Vector2(ln * 0.3, r * 0.8), Vector2(ln * 0.45, r), Vector2(ln, r)], 14)
	g.cyl("glass_lens", Vector3(mz.x, y, z1 + 0.0001), Vector3(mz.x, y, z1 + 0.001 * sc), r * 0.8, 14)
	g.box("alloy_black", Vector3(mz.x, y + r + 0.004 * sc, z1 - ln * 0.6), Vector3(0.016 * sc, 0.01 * sc, ln * 0.6), 0.001 * sc)   # the clamp up to the frame


## An open reflex sight: riser, body, hood, a tinted pane and the dot on the
## axis (true to the aim when the eye is on the sight line).
static func _red_dot(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var at := float(m.get("at", 0.1)) * sc
	var k := float(m.get("size", 1.0)) * sc
	var rail := _top_at(a, at, 0.03 * sc, 0.03 * sc) + 0.001 * sc
	var w := 0.028 * k
	var h := 0.022 * k
	var axis := float(m.get("axis", -1.0)) * sc
	if axis < 0.0:
		axis = rail + 0.012 * k + h * 0.5 + 0.004 * k
	var base_top := axis - h * 0.5 - 0.004 * k
	g.box("alloy_black", Vector3(0, (rail + base_top) * 0.5, at), Vector3(0.024 * k, maxf(base_top - rail, 0.004 * k), 0.04 * k), 0.002 * k)
	g.box("alloy_black", Vector3(0, base_top + 0.002 * k, at), Vector3(w + 0.008 * k, 0.006 * k, 0.03 * k), 0.0015 * k)
	var hz := at + 0.008 * k
	for sx in [-1.0, 1.0]:
		g.box("alloy_black", Vector3(sx * (w * 0.5 + 0.002 * k), axis, hz), Vector3(0.004 * k, h + 0.004 * k, 0.016 * k), 0.001 * k)
	g.box("alloy_black", Vector3(0, axis + h * 0.5 + 0.002 * k, hz), Vector3(w + 0.008 * k, 0.004 * k, 0.016 * k), 0.001 * k)
	g.box("alloy_black", Vector3(0.011 * k, base_top + 0.006 * k, at - 0.012 * k), Vector3(0.006 * k, 0.004 * k, 0.006 * k))     # the emitter
	g.box("glass_lens", Vector3(0, axis, hz + 0.004 * k), Vector3(w, h, 0.0012 * k))                                            # the pane
	g.box("sign_red", Vector3(0, axis, hz + 0.0034 * k), Vector3(0.0022 * k, 0.0022 * k, 0.0006 * k))                          # the dot
	a.markers["eye"] = Transform3D(Basis.IDENTITY, Vector3(0, axis, at - float(m.get("eye_back", 0.1)) * sc))


## A tube scope on two rings: the ocular toward the eye, the objective ahead.
static func _scope(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var at := float(m.get("at", 0.1)) * sc
	var ln := float(m.get("len", 0.2)) * sc
	var r := float(m.get("r", 0.016)) * sc
	var rail := _top_at(a, at, 0.03 * sc, ln * 0.5) + 0.001 * sc
	var axis := float(m.get("axis", -1.0)) * sc
	if axis < 0.0:
		axis = rail + r + 0.014 * sc
	var z0 := at - ln * 0.5
	var z1 := at + ln * 0.5
	g.lathe("alloy_black", Vector3(0, axis, z0), Vector3(0, axis, z1), [
		Vector2(0.0, r + 0.003 * sc), Vector2(0.035 * sc, r + 0.003 * sc), Vector2(0.045 * sc, r), Vector2(ln - 0.04 * sc, r), Vector2(ln - 0.025 * sc, r + 0.005 * sc), Vector2(ln, r + 0.005 * sc)], 20)
	g.cyl("glass_lens", Vector3(0, axis, z1 + 0.0005 * sc), Vector3(0, axis, z1 + 0.0015 * sc), r + 0.003 * sc, 20)   # the objective
	g.cyl("glass_lens", Vector3(0, axis, z0 - 0.0015 * sc), Vector3(0, axis, z0 - 0.0005 * sc), r + 0.001 * sc, 20)   # the ocular
	g.cyl("alloy_black", Vector3(0, axis + r - 0.002 * sc, at), Vector3(0, axis + r + 0.008 * sc, at), 0.007 * sc, 12)  # the turret
	for rz in [at - ln * 0.22, at + ln * 0.22]:
		g.box("alloy_black", Vector3(0, (rail + axis) * 0.5, rz), Vector3(0.02 * sc, axis - rail, 0.014 * sc), 0.0015 * sc)
		g.cyl("alloy_black", Vector3(0, axis, rz - 0.007 * sc), Vector3(0, axis, rz + 0.007 * sc), r + 0.0025 * sc, 16)
	g.box("alloy_black", Vector3(0, rail + 0.003 * sc, at), Vector3(0.024 * sc, 0.006 * sc, ln * 0.6), 0.001 * sc)   # the rail base
	a.markers["eye"] = Transform3D(Basis.IDENTITY, Vector3(0, axis, z0 - float(m.get("eye_back", 0.08)) * sc))


## The mag part becomes a stub into the well and a drum under it.
static func _drum(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var mag := _bottom(a, "mag")
	if mag.is_empty():
		a.warnings.append("FpsVariants: drum on a gun without a mag part")
		return
	for i in a.parts.size():
		if str(a.parts[i].name) == "mag":
			a.parts.remove_at(i)
			break
	var c: Vector3 = mag.c
	var size: Vector3 = mag.size
	var top := c.y + size.y * 0.5
	var r := float(m.get("r", 0.046)) * sc
	var w := float(m.get("w", 0.055)) * sc
	var stub := 0.075 * sc
	g.box("polymer_black", Vector3(c.x, top - stub * 0.5, c.z), Vector3(size.x, stub, size.z), 0.002 * sc)
	var cy := top - stub - r * 0.82
	var cz := c.z + 0.01 * sc
	g.cyl("polymer_black", Vector3(c.x - w * 0.5, cy, cz), Vector3(c.x + w * 0.5, cy, cz), r, 24)
	g.cyl("steel", Vector3(c.x - w * 0.5 - 0.0015 * sc, cy, cz), Vector3(c.x + w * 0.5 + 0.0015 * sc, cy, cz), r * 0.32, 16)   # the hub
	g.tube("alloy_black", [Vector3(c.x - w * 0.5 - 0.0005 * sc, cy, cz), Vector3(c.x + w * 0.5 + 0.0005 * sc, cy, cz)], [r * 0.9, r * 0.9], 24, false)   # a band
	g.box("polymer_black", Vector3(c.x, cy + r * 0.55, cz - 0.01 * sc), Vector3(size.x * 0.9, r * 0.9, size.z * 0.8), 0.002 * sc)   # the tower joining them


## A longer magazine: the mag's footprint carried down `len`, a plate under
## it; a gun without a mag part gets the plate under its grip.
static func _ext_mag(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	var ln := float(m.get("len", 0.05)) * sc
	var mag := _bottom(a, "mag")
	if mag.is_empty():
		var body := _bottom(a, "body")
		var y0: float = body.get("y", -0.07 * sc)
		var w := float(m.get("w", 0.028)) * sc
		var d := float(m.get("d", 0.046)) * sc
		var z := float(m.get("z", 0.0)) * sc
		g.box("alloy_black", Vector3(0, y0 - ln * 0.5 + 0.004 * sc, z), Vector3(w, ln + 0.004 * sc, d), 0.002 * sc)
		g.box("alloy_black", Vector3(0, y0 - ln - 0.001 * sc, z), Vector3(w + 0.004 * sc, 0.006 * sc, d + 0.004 * sc), 0.0015 * sc)
		return
	var c: Vector3 = mag.c
	var size: Vector3 = mag.size
	var y0: float = mag.y
	g.box("polymer_black", Vector3(c.x, y0 - ln * 0.5 + 0.004 * sc, c.z), Vector3(size.x * 0.96, ln + 0.004 * sc, size.z * 0.96), 0.002 * sc)
	g.box("alloy_black", Vector3(c.x, y0 - ln - 0.002 * sc, c.z), Vector3(size.x * 1.04, 0.007 * sc, size.z * 1.04), 0.0015 * sc)


## A stock extension: a spacer and a pad behind the butt.
static func _stock(g: GKMesh, a: GKAsset, m: Dictionary, sc: float) -> void:
	if not a.markers.has("butt"):
		return
	var b := a.marker("butt").origin
	var ln := float(m.get("len", 0.04)) * sc
	var w := float(m.get("w", 0.04)) * sc
	var h := float(m.get("h", 0.12)) * sc
	var y := b.y + float(m.get("y", 0.02)) * sc
	g.box("polymer_black", Vector3(b.x, y, b.z - ln * 0.35), Vector3(w * 0.9, h * 0.92, ln * 0.7), 0.003 * sc)
	g.box("rubber", Vector3(b.x, y, b.z - ln + 0.0075 * sc), Vector3(w, h, 0.015 * sc), 0.003 * sc)
	var t := a.marker("butt")
	t.origin.z -= ln
	a.markers["butt"] = t
	if a.meta.has("length"):
		a.meta["length"] = float(a.meta.length) + ln
