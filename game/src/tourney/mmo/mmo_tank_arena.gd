class_name MmoTankArena
extends RefCounted
## Planet of Tanks (raid night 2): the forest campus (the Blender-built
## "campus" kit map, G43) with a round clearing cut into its middle, the
## fight's circle (MmoSim.ARENA_R) centred on the origin, floor at y = 0.
## The drop-in sibling of MmoArena: build(), lights(), R, WALL_R.
##
## The campus goes in at SCALE (a fifth bigger, so its buildings stand
## outside the camera's reach) with the clearing just south of its centre
## (Blender (0, 3)): the chapel and its tower go, the two brick halls
## (north, -Z), the lodges (east, west) and the gatehouse (south, +Z) stand
## round it, the curving road runs off both sides. Campus pieces (triangles
## joined by shared corners; a crown goes with its trunk) are removed whole
## when their footprint centre is inside CUT_R, or when they stand taller
## than LOW_H anywhere inside WALL_R (so the camera, clamped to WALL_R - 1,
## never sits in a tree); the campus ground goes per triangle inside
## GROUND_CUT_R; the paintball bunkers go. Then a trampled grass floor with
## worn earth, tread ruts and leaf litter; bushes and saplings mark the
## edge, full-size autumn trees stand past the camera's reach.
## Deterministic, no textures, no colliders (the sim clamps movement).
## Without the campus model it falls back to MmoArena.

const R := MmoSim.ARENA_R
const WALL_R := 34.0                   ## the third-person camera stays inside WALL_R - 1
const CUT_R := R + 3.5                 ## campus pieces centred inside this go
const GROUND_CUT_R := R + 1.5          ## campus ground triangles centred inside this go
const LOW_H := 6.5                     ## pieces taller than this go anywhere inside WALL_R
const SCALE := 1.2                     ## the campus's fit (GKGlb "scale")
const SPOT := Vector3(0, 0, -3.0)      ## the campus spot (Godot axes, unscaled) that lands on the origin
const DROP := ["bunkers"]              ## campus parts left out (paintball inflatables)

const FLOOR := "grass:#7f8549"         ## trampled, yellowed grass
const DIRT := "grass:#7d6a4b"          ## worn earth (the kit has no dirt role: grass in brown)
const RUT := "grass:#735f42"
const RIM := "grass:#6c7a3a"
const LIP := "grass:#5a4a34"
const LAWN := "grass:#638a36"          ## the campus lawn (gg_campus.py GRASS)
const BARK := "bark"
const LEAVES := ["foliage_autumn", "foliage_red", "foliage_gold", "foliage_gold:#e2bb34", "foliage_autumn:#b8661a", "foliage:#6f8c2c"]
const BUSHES := ["hedge", "foliage", "foliage:#557a2c", "foliage_red", "foliage_autumn", "hedge:#4a6a2c"]
const LITTER := ["foliage_autumn", "foliage_red", "foliage_gold", "foliage_autumn:#9a5418"]

static var _blocks: Array[Rect2] = []  ## footprints of the tall campus pieces kept near the clearing (planting avoids them)


static func build(parent: Node3D) -> Node3D:
	if GKRegistry.def("campus") == null:
		return MmoArena.build(parent)
	var a := GKRegistry.build("campus", { "scale": SCALE })
	if a == null or a.parts.is_empty():
		return MmoArena.build(parent)
	_blocks.clear()
	var root := Node3D.new()
	root.name = "TankClearing"
	parent.add_child(root)
	var campus := Node3D.new()
	campus.name = "Campus"
	campus.position = -SPOT * SCALE
	root.add_child(campus)
	for p in a.parts:
		var nm := str(p.name)
		if nm in DROP:
			continue
		var xf: Transform3D = Transform3D(Basis.IDENTITY, campus.position) * (p.xform as Transform3D)
		var mesh := _cut(p.mesh as ArrayMesh, xf, nm == "ground")
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = nm.to_pascal_case()
		mi.mesh = mesh
		mi.transform = p.xform
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(p.shadow) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		GKMaterials.apply(mi)
		campus.add_child(mi)
	var g := GKMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_ground(g, rng)
	_edge(g, rng)
	var mi := MeshInstance3D.new()
	mi.name = "ClearingMesh"
	mi.mesh = g.commit()
	GKMaterials.apply(mi)
	root.add_child(mi)
	return root


## Autumn campus daylight: the campus sidecar's own lights (art/gauntlet/
## campus.json meta.lights), the sun a touch higher and warmer, with
## MmoArena's keys (exposure, normal_bias).
static func lights() -> Dictionary:
	return { "sun_dir": [0.609, -0.5, -0.669], "sun_col": "#ffdcb4", "sun_energy": 1.8, "sky_top": "#6a9ad0",
		"sky_horizon": "#dfe2e0", "ground": "#6a6a4a", "ambient": 0.66, "ambient_col": "#c8bfa8", "sky_share": 0.35,
		"fog_col": "#d8dcdc", "fog_density": 0.004, "exposure": 0.95, "saturation": 1.08, "contrast": 1.06,
		"ssao": 2.0, "shadow_dist": 110.0, "normal_bias": 0.9 }


# ------------------------------------------------------------------ the cut

## `src` without what falls in the clearing (`xf` places it in arena space).
## Surface names (kit roles) are kept, so GKMaterials.apply still works.
static func _cut(src: ArrayMesh, xf: Transform3D, ground: bool) -> ArrayMesh:
	if src == null:
		return null
	var surfs: Array = []                                 # { arr, w (arena-space verts), idx, keep }
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(v.size())
			for k in v.size():
				idx[k] = k
		var w := PackedVector3Array()
		w.resize(v.size())
		for k in v.size():
			w[k] = xf * v[k]
		var keep := PackedByteArray()
		keep.resize(idx.size() / 3)
		keep.fill(1)
		surfs.append({ "arr": arr, "w": w, "idx": idx, "keep": keep, "name": src.surface_get_name(i) })
	if ground:
		var r2 := GROUND_CUT_R * GROUND_CUT_R
		for s: Dictionary in surfs:
			var w: PackedVector3Array = s.w
			var idx: PackedInt32Array = s.idx
			var keep: PackedByteArray = s.keep
			for t in keep.size():
				var c := (w[idx[t * 3]] + w[idx[t * 3 + 1]] + w[idx[t * 3 + 2]]) / 3.0
				if c.x * c.x + c.z * c.z < r2:
					keep[t] = 0
	else:
		_pieces(surfs)
	var out := ArrayMesh.new()
	for s: Dictionary in surfs:
		var idx: PackedInt32Array = s.idx
		var keep: PackedByteArray = s.keep
		var kept := PackedInt32Array()
		for t in keep.size():
			if keep[t] == 1:
				kept.append(idx[t * 3])
				kept.append(idx[t * 3 + 1])
				kept.append(idx[t * 3 + 2])
		if kept.is_empty():
			continue
		var arr: Array = s.arr
		arr[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_name(out.get_surface_count() - 1, str(s.name))
	return out if out.get_surface_count() > 0 else null


## Pieces: triangles near the clearing joined by shared positions (1 cm grid,
## across surfaces). A piece off the ground (a crown blob, a roof) joins the
## grounded piece nearest it within 6 m (its trunk, its walls); each group
## goes whole when its footprint centre is inside CUT_R, or when it is taller
## than LOW_H and its footprint reaches inside WALL_R.
static func _pieces(surfs: Array) -> void:
	var near2 := (WALL_R + 20.0) ** 2
	var cell := {}                                        # Vector3i -> position id
	var tri_pos: Array[PackedInt32Array] = []             # per surface: 3 position ids per triangle (-1 = far)
	for s: Dictionary in surfs:
		var w: PackedVector3Array = s.w
		var idx: PackedInt32Array = s.idx
		var tp := PackedInt32Array()
		tp.resize(idx.size())
		tp.fill(-1)
		for t in idx.size() / 3:
			var c := (w[idx[t * 3]] + w[idx[t * 3 + 1]] + w[idx[t * 3 + 2]]) / 3.0
			if c.x * c.x + c.z * c.z > near2:
				continue
			for j in 3:
				var p := w[idx[t * 3 + j]]
				var q := Vector3i(roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0))
				var id: int = cell.get(q, -1)
				if id < 0:
					id = cell.size()
					cell[q] = id
				tp[t * 3 + j] = id
		tri_pos.append(tp)
	if cell.is_empty():
		return
	var par := PackedInt32Array()
	par.resize(cell.size())
	for k in par.size():
		par[k] = k
	for tp in tri_pos:
		for t in tp.size() / 3:
			if tp[t * 3] < 0:
				continue
			var a := _root(par, tp[t * 3])
			for j in [1, 2]:
				var b := _root(par, tp[t * 3 + j])
				if a != b:
					par[b] = a
					a = _root(par, a)
	# bounds per piece
	var lo := {}
	var hi := {}
	for si in surfs.size():
		var w: PackedVector3Array = (surfs[si] as Dictionary).w
		var idx: PackedInt32Array = (surfs[si] as Dictionary).idx
		var tp := tri_pos[si]
		for t in tp.size() / 3:
			if tp[t * 3] < 0:
				continue
			var r := _root(par, tp[t * 3])
			for j in 3:
				var p := w[idx[t * 3 + j]]
				if lo.has(r):
					lo[r] = (lo[r] as Vector3).min(p)
					hi[r] = (hi[r] as Vector3).max(p)
				else:
					lo[r] = p
					hi[r] = p
	# floating pieces join the nearest grounded piece (a grid of grounded centres)
	var grid := {}
	for r: int in lo:
		if (lo[r] as Vector3).y < 0.4:
			var c: Vector3 = ((lo[r] as Vector3) + (hi[r] as Vector3)) * 0.5
			var gk := Vector2i(floori(c.x / 6.0), floori(c.z / 6.0))
			if not grid.has(gk):
				grid[gk] = []
			(grid[gk] as Array).append(r)
	var group := {}                                       # piece -> its anchor
	for r: int in lo:
		group[r] = r
		if (lo[r] as Vector3).y < 0.4:
			continue
		var c: Vector3 = ((lo[r] as Vector3) + (hi[r] as Vector3)) * 0.5
		var gk := Vector2i(floori(c.x / 6.0), floori(c.z / 6.0))
		var best := 36.0
		for i in [-1, 0, 1]:
			for j in [-1, 0, 1]:
				for o: int in grid.get(gk + Vector2i(i, j), []):
					var oc: Vector3 = ((lo[o] as Vector3) + (hi[o] as Vector3)) * 0.5
					var d := Vector2(oc.x - c.x, oc.z - c.z).length_squared()
					if d < best:
						best = d
						group[r] = o
	var glo := {}
	var ghi := {}
	for r: int in lo:
		var g: int = group[r]
		glo[g] = (glo[g] as Vector3).min(lo[r]) if glo.has(g) else lo[r]
		ghi[g] = (ghi[g] as Vector3).max(hi[r]) if ghi.has(g) else hi[r]
	var gone := {}
	for g: int in glo:
		var l: Vector3 = glo[g]
		var h: Vector3 = ghi[g]
		var c := (l + h) * 0.5
		var out := c.x * c.x + c.z * c.z >= CUT_R * CUT_R
		if out and h.y > LOW_H:
			var nx := clampf(0.0, l.x, h.x)               # the footprint's nearest point to the origin
			var nz := clampf(0.0, l.z, h.z)
			out = nx * nx + nz * nz >= WALL_R * WALL_R
		if not out:
			gone[g] = true
		elif h.y > 2.5 and c.length() < WALL_R + 14.0:
			_blocks.append(Rect2(l.x, l.z, h.x - l.x, h.z - l.z))
	if gone.is_empty():
		return
	for si in surfs.size():
		var keep: PackedByteArray = (surfs[si] as Dictionary).keep
		var tp := tri_pos[si]
		for t in tp.size() / 3:
			if tp[t * 3] >= 0 and gone.has(group[_root(par, tp[t * 3])]):
				keep[t] = 0


static func _root(par: PackedInt32Array, k: int) -> int:
	var r := k
	while par[r] != r:
		r = par[r]
	while par[k] != r:                                    # path compression
		var n := par[k]
		par[k] = r
		k = n
	return r


# ------------------------------------------------------------------ the clearing

static func _ring(g: GKMesh, role: String, r0: float, r1: float, y: float, seg := 128) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(sin(a0), 0, cos(a0))
		var p1 := Vector3(sin(a1), 0, cos(a1))
		var h := Vector3(0, y, 0)
		if r0 <= 0.0:
			g.tri(role, h, p1 * r1 + h, p0 * r1 + h)
		else:
			g.quad(role, p0 * r0 + h, p1 * r0 + h, p1 * r1 + h, p0 * r1 + h)


## A flat triangle or quad on the ground, wound to face up whatever order
## its corners come in.
static func _flat(g: GKMesh, role: String, q: Array) -> void:
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var c: Vector3 = q[2]
	if (b - a).cross(c - a).y > 0.0:
		q.reverse()
	if q.size() == 3:
		g.tri(role, q[0], q[1], q[2])
	else:
		g.quad(role, q[0], q[1], q[2], q[3])


## A flat blob: a fan with a wobbling radius.
static func _blob(g: GKMesh, role: String, c: Vector3, r: float, rng: RandomNumberGenerator, stretch := Vector2.ONE, rot := 0.0) -> void:
	var n := 14
	var ph := rng.randf() * TAU
	var k2 := rng.randf_range(0.1, 0.22)
	var k3 := rng.randf_range(0.06, 0.16)
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		var rr := r * (1.0 + k2 * sin(2.0 * a + ph) + k3 * sin(3.0 * a + ph * 1.7) + rng.randf_range(-0.06, 0.06))
		var lx := cos(a) * rr * stretch.x
		var lz := sin(a) * rr * stretch.y
		pts.append(c + Vector3(lx * cos(rot) - lz * sin(rot), 0, lx * sin(rot) + lz * cos(rot)))
	for i in n:
		_flat(g, role, [c, pts[i], pts[(i + 1) % n]])


## The floor: trampled grass with worn earth patches and the tank's ruts,
## a darker rim band and an earth lip at the fight's edge (R), the campus
## lawn beneath everything out to where the campus ground resumes.
static func _ground(g: GKMesh, rng: RandomNumberGenerator) -> void:
	_ring(g, LAWN, 0.0, R + 16.0, -0.03, 128)             # under the cut's ragged edge
	_ring(g, FLOOR, 0.0, R - 1.2, 0.0)
	_ring(g, RIM, R - 1.2, R + 3.2, 0.0)                  # the edge band, over the cut
	_ring(g, LIP, R - 0.2, R + 0.25, 0.02)                # the fight's line
	# worn earth: soft blobs, denser and bigger toward the tank
	for k in 34:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (R - 3.0)
		var s := lerpf(2.6, 1.2, r / R) * rng.randf_range(0.7, 1.3)
		_blob(g, DIRT, Vector3(sin(a) * r, 0.008, cos(a) * r), s, rng, Vector2(rng.randf_range(1.0, 1.8), 1.0), rng.randf() * TAU)
	_blob(g, DIRT, Vector3(0, 0.009, 0), 7.5, rng)        # the tank's churned pad
	# ruts: the tank's tracks, a few broken wobbly arcs
	for k in 4:
		var r0 := rng.randf_range(8.5, 15.0)
		var a0 := rng.randf() * TAU
		var span := rng.randf_range(0.6, 1.5)
		var seg := int(span * r0 / 1.2)
		for side: float in [-1.0, 1.0]:
			var prev := Vector3.ZERO
			for i in seg + 1:
				var a := a0 + span * i / seg
				var rr := r0 + side * 1.35 + sin(a * 3.0 + k) * 0.6
				var p := Vector3(sin(a) * rr, 0.014, cos(a) * rr)
				if i > 0:
					var d := (p - prev).normalized()
					var nrm := Vector3(-d.z, 0, d.x) * 0.22
					_flat(g, RUT, [prev - nrm, prev + nrm, p + nrm, p - nrm])
				prev = p
	# leaf litter: scattered flat leaves, densest along the edge
	for k in 2600:
		var a := rng.randf() * TAU
		var t := pow(rng.randf(), 0.3)
		var r := lerpf(3.0, R + 7.0, t)
		var p := Vector3(sin(a) * r, 0.022 + rng.randf() * 0.01, cos(a) * r)
		var s := rng.randf_range(0.07, 0.14)
		var rot := rng.randf() * TAU
		var u := Vector3(cos(rot), 0, sin(rot)) * s
		var vv := Vector3(-sin(rot), 0, cos(rot)) * s * 0.7
		_flat(g, LITTER[k % LITTER.size()], [p - u - vv, p - u + vv, p + u + vv, p + u - vv])


## The edge: a broken ring of bushes just outside R and saplings behind
## them, all low (crowns under 4.5 m: the raid camera, out to WALL_R - 1,
## looks over them); full-size autumn trees stand past the camera's reach,
## in the gaps the campus leaves.
static func _edge(g: GKMesh, rng: RandomNumberGenerator) -> void:
	var nb := 52
	for k in nb:
		var a := TAU * (k + rng.randf_range(-0.3, 0.3)) / nb
		if rng.randf() < 0.15:
			continue
		var r := R + rng.randf_range(1.3, 2.8)
		_bush(g, Vector3(sin(a) * r, 0, cos(a) * r), rng.randf_range(0.8, 1.35), BUSHES[rng.randi() % BUSHES.size()], rng)
	var ns := 18
	for k in ns:
		var a := TAU * (k + 0.5 + rng.randf_range(-0.3, 0.3)) / ns
		var r := R + rng.randf_range(3.6, 5.8)
		var p := Vector3(sin(a) * r, 0, cos(a) * r)
		if not _blocked(p, 1.5):
			_tree(g, p, rng.randf_range(0.68, 0.8), rng)
	var planted: Array[Vector3] = []
	for k in 60:
		var a := TAU * (k + rng.randf_range(-0.35, 0.35)) / 60.0
		var r := WALL_R + rng.randf_range(3.6, 7.0)
		var p := Vector3(sin(a) * r, 0, cos(a) * r)
		if _blocked(p, 3.4) or planted.any(func(q: Vector3) -> bool: return q.distance_to(p) < 5.5):
			continue
		planted.append(p)
		_tree(g, p, rng.randf_range(1.35, 1.7), rng)


static func _blocked(p: Vector3, clear: float) -> bool:
	for b in _blocks:
		if b.grow(clear).has_point(Vector2(p.x, p.z)):
			return true
	return false


static func _bush(g: GKMesh, at: Vector3, s: float, role: String, rng: RandomNumberGenerator) -> void:
	for k in 3:
		var o := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7)) * s
		var r := rng.randf_range(0.7, 1.0) * s
		g.sphere(role, at + o + Vector3(0, r * 0.55, 0), r, 9, Vector3(1.0, 0.75, 1.0))


static func _tree(g: GKMesh, at: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var h := 3.6 * s
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	g.tube(BARK, [at, at + Vector3(0, h * 0.55, 0) + lean * 0.5, at + Vector3(0, h, 0) + lean], [0.26 * s, 0.2 * s, 0.14 * s], 8)
	var top := at + Vector3(0, h, 0) + lean
	var role: String = LEAVES[rng.randi() % LEAVES.size()]
	g.sphere(role, top + Vector3(0, 0.4 * s, 0), 2.0 * s, 11, Vector3(1.0, 0.8, 1.0))
	for k in 3:
		var a := rng.randf() * TAU
		var o := Vector3(sin(a), 0, cos(a)) * 1.3 * s + Vector3(0, rng.randf_range(-0.4, 0.6) * s, 0)
		var r2: String = role if rng.randf() < 0.6 else LEAVES[rng.randi() % LEAVES.size()]
		g.sphere(r2, top + o, rng.randf_range(1.1, 1.5) * s, 10, Vector3(1.0, 0.85, 1.0))
