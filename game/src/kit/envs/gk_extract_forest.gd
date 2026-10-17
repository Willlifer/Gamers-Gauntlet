class_name GKExtractForest
extends GKDef
## The extract shooter's map (design/extract/PLAN.md): a seeded 300 x 300 m
## forest campus in the campus-paintball look. Heightfield terrain with hills
## and valleys (a lake in the lowest one), 8-14 buildings in varying disrepair
## (hilltops, a valley, one cut into a hillside; every one enterable), roads
## as terrain-following ribbons joining them all (an MST plus one loop, asphalt
## or gravel by disrepair, parked cars), tall low-poly forest everywhere else
## (trunks collide, crowns don't, one part per 60 m cell so culling works),
## walk-through bushes as hide volumes, and landmarks you steer by: the
## chapel tower, the water tower, the radio mast, the barn's silo, the lake.
## Procedural at runtime so every match seed is a new map (the plan's call).
## Gauntlet pass (design/extract/GAUNTLET.md, r0-r4): roads carved into the
## ground and draped (forecourts, sidewalks, lamp rows), dirt trails from each
## spawn, a sightline from each spawn to its nearest tall landmark, mid-forest
## points of interest (meta.pois: a fire lookout landmark, hunting stands, a
## wreck, a camp, ruined field walls, a power-line cut), a forest varied by
## seeded fields (clearings, thick stands, birch groves, autumn patches), two
## outlying lots, cut-in pads with retaining walls, distant wooded hills.
## Contract (markers / meta) is the plan's: spawn_a0..7 = spawn_b0..7 in
## walled pockets round the edge that no window sees, extract0..3, ref_cam;
## meta height (height_at is the one way to ask the ground), chests, guards,
## buildings, landmarks, roads, play_area, hide_volumes, lights.
## Real metres, +y up, ground about y 0; `scale` fits the 2.2 m body.

func id() -> String:
	return "extract_forest"


func title() -> String:
	return "Extraction forest"


func kind() -> String:
	return "env"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pi("seed", "Map seed", "Layout", 7, 0, 99999),
		pf("size", "Play area (m)", "Layout", 300.0, 200.0, 400.0, 10.0),
		pf("hills", "Hills", "Layout", 0.6, 0.0, 1.0, 0.01),
		pf("density", "Buildings", "Layout", 0.5, 0.0, 1.0, 0.01),
		pf("disrepair", "Disrepair", "Layout", 0.5, 0.0, 1.0, 0.01),
		pf("scale", "Scale", "Fit", 1.0, 0.8, 1.6, 0.01),
	]


func presets() -> Dictionary:
	return {
		"Reference": {},
		"Flat and tidy": { "hills": 0.15, "disrepair": 0.1 },
		"Mountain ruins": { "hills": 1.0, "disrepair": 0.9, "density": 0.8 },
	}


const STEP := 3.0                 ## heightfield grid step (m)
const MARGIN := 39.0              ## terrain past the play area's edge (m)
const CELL := 60.0                ## tree chunk size (m)
const ROAD_HW := 2.6

# the build's working state (one build at a time)
var _hf := {}                     # the height meta
var _cols := 0
var _half := 150.0
var _ox := 0.0
var _blocked := PackedByteArray() # per grid node: 1 no trees, 2 lake, 4 clearing, 8 a lot / pocket / pad / car / poi (no bushes), 16 a road / trail
var _rng := RandomNumberGenerator.new()
var _seed := 0


## The ground's height at (x, z): the one way anyone asks (bots, chests,
## the probe). Matches the terrain mesh exactly: each cell is two triangles
## split from (i, j) to (i + 1, j + 1); outside the grid the edge's height.
static func height_at(meta: Dictionary, x: float, z: float) -> float:
	var hf: Dictionary = meta.get("height", meta)
	if hf.is_empty():
		return 0.0
	var cols: int = hf.cols
	var rows: int = hf.rows
	var step: float = hf.step
	var data: PackedFloat32Array = hf.data
	var fx := clampf((x - float(hf.origin[0])) / step, 0.0, float(cols - 1) - 1e-4)
	var fz := clampf((z - float(hf.origin[1])) / step, 0.0, float(rows - 1) - 1e-4)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var h00 := data[j * cols + i]
	var h10 := data[j * cols + i + 1]
	var h01 := data[(j + 1) * cols + i]
	var h11 := data[(j + 1) * cols + i + 1]
	if v <= u:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h01 - h00) * v + (h11 - h01) * u


func _h(x: float, z: float) -> float:
	return height_at(_hf, x, z)


func _build(p: Dictionary) -> GKAsset:
	var a := GKAsset.new()
	var s: float = p.scale
	var M := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(p.seed) * 7919 + 13
	_seed = int(p.seed)
	_half = float(p.size) * 0.5
	var ext := _half + MARGIN
	_cols = int(ceil(ext * 2.0 / STEP)) + 1
	_ox = -float(_cols - 1) * STEP * 0.5
	var d_all: float = p.disrepair
	# ---- 1. the raw hills
	_hf = { "origin": [_ox, _ox], "step": STEP, "cols": _cols, "rows": _cols, "data": PackedFloat32Array() }
	_terrain_raw(int(p.seed), float(p.hills))
	_blocked = PackedByteArray()
	_blocked.resize(_cols * _cols)
	# ---- 2. the lake: the lowest ground well inside the play area
	var lake_c := _lowest(_half * 0.7)
	# ---- 3. building sites by relief: hilltops, valleys, a hillside
	var n_b := 8 + int(round(6.0 * float(p.density)))
	var specs := _sites(n_b, lake_c, d_all)
	# the radio mast: the highest point clear of everything
	var mast_at := _highest(_half * 0.8, specs, lake_c)
	# ---- 4. flatten pads, then the lake, then the roads
	for sp in specs:
		var pl: Dictionary = sp.plan
		sp["pos"] = Vector3(sp.pos.x, _pad(sp.pos.x, sp.pos.z, float(sp.yaw), float(pl.hx) + 1.0, float(pl.hz) + 1.0, sp.site == "hillside" or float(sp.get("slope", 0.0)) > 0.12), sp.pos.z)
	mast_at.y = _pad(mast_at.x, mast_at.z, 0.0, 3.0, 3.0, false)
	var spawns: Array[Vector3] = []
	var spawn_in: Array[Vector3] = []
	for k in 8:
		var an := k * TAU / 8.0
		var r := _half - 11.0
		var c := Vector3(sin(an) * r, 0, -cos(an) * r)
		var inward := -c.normalized()
		c.y = _pad(c.x, c.z, atan2(inward.x, inward.z), 5.5, 4.5, false)
		spawns.append(c)
		spawn_in.append(inward)
	var extracts: Array[Vector3] = []
	for k in 4:
		var an := (k + 0.5) * TAU / 4.0 + TAU / 16.0
		var r := _half - 9.0
		var c := Vector3(sin(an) * r, 0, -cos(an) * r)
		c.y = _pad(c.x, c.z, 0.0, 3.5, 3.5, false)
		extracts.append(c)
	var lake := _lake(lake_c)
	var roads := _roads(specs, lake)
	_carve(roads)
	var cars := _cars(roads, specs, d_all)
	var trails := _trails(spawns, spawn_in, roads, specs, lake)
	_mark(specs, mast_at, roads + trails, spawns, extracts, cars)
	var pois := _pois(specs, spawns, roads, lake)
	var tall_at: Array[Vector3] = [mast_at]
	for sp in specs:
		if sp.kind in ["chapel", "watertower", "barn"]:
			tall_at.append(sp.pos)
	for item in pois.items:
		if item.kind == "lookout":
			tall_at.append(item.pos)
	for k in spawns.size():
		var sd_k := Vector3(-spawn_in[k].z, 0, spawn_in[k].x) * (1.0 if k % 2 == 0 else -1.0)
		var s0: Vector3 = spawns[k] + sd_k * 6.8 + spawn_in[k] * 1.5
		var tgt := tall_at[0]
		for t in tall_at:
			if Vector2(t.x - s0.x, t.z - s0.z).length() < Vector2(tgt.x - s0.x, tgt.z - s0.z).length():
				tgt = t
		var dir := Vector3(tgt.x - s0.x, 0, tgt.z - s0.z)
		var ln := minf(dir.length() - 10.0, 90.0)
		dir = dir.normalized()
		var u := 4.0
		while u < ln:
			_disc(s0.x + dir.x * u, s0.z + dir.z * u, 3.0 + 2.5 * minf(u / 30.0, 1.0), 1)
			u += 2.5
	# ---- 5. geometry
	var tint := func(i: int, j: int) -> Color:
		return _ground_tint(i, j, lake.level)
	var tmesh := GKForestLots.terrain_mesh(_hf, tint)
	a.add_part("terrain", tmesh, M)
	a.add_trimesh_collider(tmesh, M)
	var g := GKMesh.new()
	g.push(M)
	_skirt(g)
	_water(g, lake)
	var ri := 0
	for rd in roads:
		var lift := 0.16 + 0.012 * ri                 # two roads leaving one door never share a depth
		GKForestLots.ribbon(g, rd.pts, ROAD_HW, str(rd.role), _h, lift)
		if rd.role == "asphalt" or rd.role == "asphalt_lot":
			var pts: Array = rd.pts
			var lc := "sign_white:#e8c84a" if rd.role == "asphalt" else "sign_white:#bdbab0"
			for i in range(0, pts.size() - 1, 2):
				GKForestLots.ribbon(g, [(pts[i] as Vector3).lerp(pts[i + 1], 0.2), (pts[i] as Vector3).lerp(pts[i + 1], 0.8)], 0.08, lc, _h, lift + 0.012, 1)
			if pts.size() > 12:
				var walk := GKForestLots.offset_line(pts.slice(3, pts.size() - 3), (ROAD_HW + 0.95) * (1.0 if ri % 2 == 0 else -1.0))
				GKForestLots.ribbon(g, walk, 0.6, "path_concrete:#c3bfb4", _h, 0.06, 1)
		ri += 1
	for tr in trails:
		GKForestLots.ribbon(g, tr.pts, 1.0, "asphalt_lot:#8a7656", _h, 0.07, 2)
	# a paved forecourt at every door: where the roads meet, and the campus's front walk
	for sp in specs:
		var b := Basis(Vector3.UP, float(sp.yaw))
		var fc: Vector3 = sp.pos + b * Vector3(0, 0, float(sp.plan.hz) + 3.4)
		GKForestLots.drape_rect(g, "path_concrete:#c3bfb4", fc, float(sp.yaw), minf(float(sp.plan.hx), 4.2) + 0.4, 3.0, _h, 0.16 + 0.012 * ri + 0.03)
	g.pop()
	a.add_part("ground", g.commit())
	# buildings: one part each
	var built: Array = []
	var bi := 0
	for sp in specs:
		g = GKMesh.new()
		g.push(M)
		var brng := RandomNumberGenerator.new()
		brng.seed = int(p.seed) * 31 + bi * 101
		var out := GKForestLots.building(g, a, { "kind": sp.kind, "pos": sp.pos, "yaw": sp.yaw, "disrepair": sp.disrepair, "rng": brng, "plan": sp.plan })
		# a bench and a lamp outside the door
		var fwd: Vector3 = out.front
		var side := Vector3(-fwd.z, 0, fwd.x)
		var door: Vector3 = out.door
		var lp: Vector3 = door + fwd * 7.0 + side * 3.6
		lp.y = _h(lp.x, lp.z)
		GKForestLots.lamp(g, a, lp)
		if sp.kind in ["hall", "house", "lodge", "chapel"]:
			var bp: Vector3 = sp.pos + side * (float(sp.plan.hx) + 1.1) + fwd * 0.5
			bp.y = _h(bp.x, bp.z)
			GKForestLots.bench(g, a, bp, float(sp.yaw) + PI * 0.5)
		# the hillside cut: a retaining wall along the uphill face
		_retaining(g, a, sp)
		g.pop()
		a.add_part("bld_%d" % bi, g.commit())
		out["spec"] = sp
		built.append(out)
		bi += 1
	# props: cars, pockets, pads, the mast
	g = GKMesh.new()
	g.push(M)
	for c in cars:
		GKForestLots.car(g, a, c.pos, c.yaw, c.paint, c.wear, _tilt_at(c.pos.x, c.pos.z))
	for rd in roads:
		if str(rd.role) == "concrete:#8f8872":
			continue
		var pts: Array = rd.pts
		var flip := -1.0 if roads.find(rd) % 2 == 0 else 1.0
		for i in range(4, pts.size() - 4, 8):
			var p0: Vector3 = pts[i]
			var dir: Vector3 = (pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)
			dir.y = 0.0
			dir = dir.normalized()
			var lp := p0 + Vector3(-dir.z, 0, dir.x) * flip * (ROAD_HW + 0.9)
			var ok := true
			for sp in specs:
				if Vector2(lp.x - sp.pos.x, lp.z - sp.pos.z).length() < _loop_radius(sp) + 3.0:
					ok = false
			for c in cars:
				if Vector2(lp.x - c.pos.x, lp.z - c.pos.z).length() < 4.0:
					ok = false
			if ok:
				lp.y = _h(lp.x, lp.z)
				GKForestLots.lamp(g, a, lp)
	for k in 8:
		GKForestLots.pocket(g, a, spawns[k], spawn_in[k])
	for e in extracts:
		GKForestLots.extract_pad(g, a, e)
	var mast_top := GKForestLots.mast(g, a, mast_at, 30.0)
	g.pop()
	a.add_part("props", g.commit())
	# the points of interest and the power line, one part
	g = GKMesh.new()
	g.push(M)
	var prng := RandomNumberGenerator.new()
	prng.seed = int(p.seed) * 53 + 11
	var poi_meta := []
	var lookout_top := Vector3.ZERO
	var lookout_at := Vector3.ZERO
	for q in pois.items:
		var at: Vector3 = q.pos
		match str(q.kind):
			"lookout":
				lookout_top = GKForestLots.lookout(g, a, at, q.yaw)
				lookout_at = at
			"stand":
				GKForestLots.hunting_stand(g, a, at, q.yaw)
			"wreck":
				GKForestLots.crashed_car(g, a, at, q.yaw, GKForestLots.PAINTS[prng.randi() % GKForestLots.PAINTS.size()], _tilt_at(at.x, at.z))
			"camp":
				GKForestLots.campfire(g, a, at, q.yaw, _h)
			"wall":
				GKForestLots.ruin_wall(g, a, at, q.yaw, prng.randf_range(14.0, 22.0), prng, _h)
		poi_meta.append({ "kind": q.kind, "pos": M * at, "yaw": q.yaw, "look_h": { "lookout": 9.0, "stand": 2.5, "wreck": 0.8, "camp": 0.8, "wall": 1.0 }[str(q.kind)] })
	var prev: Array = []
	var prev_t := -1e9
	for pl in pois.pylons:
		var w := GKForestLots.pylon(g, a, pl.pos, pl.yaw)
		if not prev.is_empty() and float(pl.t) - prev_t < 75.0:
			for k in 3:
				GKArch.cable(g, prev[k], w[k], 1.1, 0.025, "cable", 10)
		prev = w
		prev_t = float(pl.t)
	if not pois.pylons.is_empty():
		poi_meta.append({ "kind": "powerline", "pos": M * (pois.pylons[pois.pylons.size() / 2].pos as Vector3), "yaw": pois.pylons[0].yaw, "look_h": 8.0 })
	g.pop()
	a.add_part("pois", g.commit())
	# the forest and the bushes, chunked per 60 m cell
	var bushes := _forest(a, M, lake)
	_far_ring(a, M)
	# ---- 6. barriers round the play area
	var B := _half
	for w in [[Vector3(-B - 1.0, -40, -B - 1.0), Vector3(B + 1.0, 80, -B)], [Vector3(-B - 1.0, -40, B), Vector3(B + 1.0, 80, B + 1.0)],
			[Vector3(-B - 1.0, -40, -B), Vector3(-B, 80, B)], [Vector3(B, -40, -B), Vector3(B + 1.0, 80, B)]]:
		GKArch.barrier(a, w[0], w[1], M)
	# ---- 7. markers
	var look := func(from: Vector3, to: Vector3) -> Transform3D:
		return Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP), M * from)
	a.markers = { "ref_cam": look.call(Vector3(0, _half * 1.9, _half * 0.55), Vector3(0, 0, -_half * 0.15)) }
	for k in 8:
		var face := Basis(Vector3.UP, (0.25 if k % 2 == 0 else -0.25) * PI) * spawn_in[k]
		var t := Transform3D(Basis.looking_at(face, Vector3.UP), M * spawns[k])
		a.markers["spawn_a%d" % k] = t
		a.markers["spawn_b%d" % k] = t
	for k in 4:
		a.markers["extract%d" % k] = Transform3D(Basis.IDENTITY, M * extracts[k])
	# ---- 8. meta
	var buildings := []
	var guards := []
	var landmarks := []
	var chests := []
	var crng := RandomNumberGenerator.new()
	crng.seed = int(p.seed) * 977 + 5
	var deep_names := { "chapel": "the chapel", "hall": "the hall", "house": "the house", "lodge": "the lodge", "barn": "the barn", "watertower": "the pump house", "ruin": "the ruin" }
	bi = 0
	for out in built:
		var sp: Dictionary = out.spec
		var kind: String = sp.kind
		var nm: String = deep_names[kind]
		var aabb: AABB = out.aabb
		var wins := []
		for w in out.windows:
			wins.append({ "pos": M * (w.pos as Vector3), "n": w.n })
		buildings.append({ "id": bi, "name": nm, "aabb": AABB(M * aabb.position, aabb.size * s), "kind": kind, "disrepair": sp.disrepair,
			"site": sp.site, "windows": wins })
		var patrol := []
		for q in out.patrol:
			var pq: Vector3 = q
			patrol.append(M * Vector3(pq.x, pq.y, pq.z))
		guards.append({ "pos": M * (out.door as Vector3), "building": bi, "patrol": patrol })
		# chests: 2-3 per building, tier 3 only on the deep spots
		var spots: Array = (out.spots as Array).duplicate()
		var n_c := 2 + (1 if crng.randf() < 0.6 else 0)
		for k in n_c:
			if spots.is_empty():
				break
			var si := crng.randi() % spots.size()
			var spot: Dictionary = spots[si]
			spots.remove_at(si)
			var tier := 1 + (1 if crng.randf() < 0.45 else 0)
			if spot.deep:
				tier = 3 if crng.randf() < 0.55 else 2
			chests.append({ "pos": M * (spot.pos as Vector3), "yaw": crng.randf() * TAU, "where": "building", "tier": tier, "building": bi })
		match kind:
			"chapel":
				landmarks.append({ "name": "chapel tower", "pos": M * (sp.pos as Vector3), "top": M * (out.top as Vector3) })
			"watertower":
				landmarks.append({ "name": "water tower", "pos": M * (sp.pos as Vector3), "top": M * (out.top as Vector3) })
			"barn":
				landmarks.append({ "name": "barn silo", "pos": M * (sp.pos as Vector3), "top": M * (out.top as Vector3) })
		bi += 1
	landmarks.append({ "name": "radio mast", "pos": M * mast_at, "top": M * mast_top })
	if lookout_top != Vector3.ZERO:
		landmarks.append({ "name": "fire lookout", "pos": M * lookout_at, "top": M * lookout_top })
	landmarks.append({ "name": "lake", "pos": M * Vector3(lake_c.x, lake.level, lake_c.z), "top": M * Vector3(lake_c.x, lake.level + 0.3, lake_c.z), "low": true })
	# cars and bushes top the chests up to 30-45
	var car_list := []
	for c in cars:
		car_list.append({ "pos": M * (c.pos as Vector3), "yaw": c.yaw })
	var ci := 0
	while chests.size() < 36 and ci < cars.size():
		var c: Dictionary = cars[ci]
		ci += 1
		if crng.randf() < 0.7:
			var cp: Vector3 = (c.pos as Vector3) + Basis(Vector3.UP, float(c.yaw)) * Vector3(0, 0, 1.7)
			cp.y = _h(cp.x, cp.z)
			chests.append({ "pos": M * cp, "yaw": float(c.yaw), "where": "car", "tier": 1 if crng.randf() < 0.7 else 2 })
	var bk := 0
	while chests.size() < 36 and bk < bushes.size():
		var b: Dictionary = bushes[(bk * 7) % bushes.size()]
		bk += 1
		if bk % 2 == 0:
			continue
		var bc: Vector3 = b.center
		chests.append({ "pos": M * Vector3(bc.x, bc.y - float((b.half as Vector3).y), bc.z), "yaw": crng.randf() * TAU, "where": "bush", "tier": 1 })
	if chests.size() > 45:
		chests.resize(45)
	var hide := []
	for b in bushes:
		hide.append({ "center": M * (b.center as Vector3), "half": (b.half as Vector3) * s, "basis": b.basis })
	var road_lines := []
	for rd in roads:
		var line := []
		for q in rd.pts:
			line.append(M * (q as Vector3))
		road_lines.append(line)
	# the height meta in scaled metres
	var hf := _hf.duplicate(true)
	if not is_equal_approx(s, 1.0):
		hf.origin = [float(hf.origin[0]) * s, float(hf.origin[1]) * s]
		hf.step = float(hf.step) * s
		var dd: PackedFloat32Array = hf.data
		for i in dd.size():
			dd[i] *= s
		hf.data = dd
	a.meta = { "class": "map", "extract": true, "bot_hunt": false, "play_area": [-_half * s, -_half * s, _half * s, _half * s],
		"height": hf, "chests": chests, "guards": guards, "buildings": buildings, "landmarks": landmarks, "roads": road_lines,
		"hide_volumes": hide, "cars": car_list, "lake": { "center": M * Vector3(lake_c.x, lake.level, lake_c.z), "level": lake.level * s },
		"mast": M * mast_at, "ref_cam_fov": 60.0, "pois": poi_meta,
		"notes": "Extraction forest (seed %d): %d buildings, %d chests, %d guard posts, %d roads. spawn_a* = spawn_b* are the eight edge pockets; extract0..3 the pads; height_at(meta, x, z) is the ground." % [int(p.seed), buildings.size(), chests.size(), guards.size(), roads.size()] }
	# G65: dusk. A low orange sun, a deep blue-violet sky, cool dim ambient and
	# a blue haze that swallows the far woods; shadows out to 100 m (the
	# low sun's long ones; 160 m drew every tree chunk into four splits).
	a.lights = { "sun_dir": [0.700, -0.200, -0.685], "sun_col": "#ffa26a", "sun_energy": 1.05, "sky_top": "#121a30", "sky_horizon": "#6b5266",
		"ground": "#24241e", "ambient": 0.95, "ambient_col": "#8090b4", "sky_share": 0.35, "ssao": 1.6, "fog_col": "#2b3247",
		"fog_density": 0.006, "exposure": 1.3, "sun_angle": 6.0, "saturation": 0.9, "contrast": 1.08, "shadow_dist": 100.0 * s }
	return a


# ----------------------------------------------------------------- terrain

## Value noise on a lattice: position-stable (no rng), so pads and sites can
## read it anywhere.
static func _vn(ix: int, iz: int, sd: int) -> float:
	var h := ix * 374761393 + iz * 668265263 + sd * 982451653
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func _noise(x: float, z: float, cell: float, sd: int) -> float:
	var fx := x / cell
	var fz := z / cell
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var u := fx - ix
	var v := fz - iz
	u = 0.5 - 0.5 * cos(u * PI)
	v = 0.5 - 0.5 * cos(v * PI)
	var a := _vn(ix, iz, sd)
	var b := _vn(ix + 1, iz, sd)
	var c := _vn(ix, iz + 1, sd)
	var d := _vn(ix + 1, iz + 1, sd)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Three octaves, normalised over the play area to a range of 10 + 12 * hills
## metres centred on y 0.
func _terrain_raw(sd: int, hills: float) -> void:
	var data := PackedFloat32Array()
	data.resize(_cols * _cols)
	var lo := 1e9
	var hi := -1e9
	for j in _cols:
		var z := _ox + j * STEP
		for i in _cols:
			var x := _ox + i * STEP
			var h := _noise(x + 1000.0, z + 1000.0, 64.0, sd) + 0.42 * _noise(x, z, 27.0, sd + 1) + 0.14 * _noise(x, z, 11.0, sd + 2)
			data[j * _cols + i] = h
			if absf(x) <= _half and absf(z) <= _half:
				lo = minf(lo, h)
				hi = maxf(hi, h)
	var amp := 11.0 + 14.0 * hills
	var k := amp / maxf(hi - lo, 1e-3)
	var mid := (lo + hi) * 0.5
	for i in data.size():
		data[i] = (data[i] - mid) * k
	_hf.data = data


func _node(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(round((x - _ox) / STEP)), 0, _cols - 1), clampi(int(round((z - _ox) / STEP)), 0, _cols - 1))


func _raw(ix: int, iz: int) -> float:
	return (_hf.data as PackedFloat32Array)[iz * _cols + ix]


func _lowest(r: float) -> Vector3:
	var best := 1e9
	var at := Vector3.ZERO
	var data: PackedFloat32Array = _hf.data
	for j in _cols:
		var z := _ox + j * STEP
		for i in _cols:
			var x := _ox + i * STEP
			if absf(x) > r or absf(z) > r:
				continue
			var h := data[j * _cols + i]
			if h < best:
				best = h
				at = Vector3(x, h, z)
	return at


func _highest(r: float, specs: Array, lake_c: Vector3) -> Vector3:
	var best := -1e9
	var at := Vector3.ZERO
	var data: PackedFloat32Array = _hf.data
	for j in range(0, _cols, 2):
		var z := _ox + j * STEP
		for i in range(0, _cols, 2):
			var x := _ox + i * STEP
			if absf(x) > r or absf(z) > r:
				continue
			var h := data[j * _cols + i]
			if h <= best:
				continue
			if Vector2(x, z).distance_to(Vector2(lake_c.x, lake_c.z)) < 30.0:
				continue
			var ok := true
			for sp in specs:
				if Vector2(x, z).distance_to(Vector2(sp.pos.x, sp.pos.z)) < 30.0:
					ok = false
					break
			if ok:
				best = h
				at = Vector3(x, h, z)
	return at


## Flatten the ground under a lot: level inside the (rotated) rect grown by
## `plateau`, blending back to the hills over the next 7 m. Returns the pad
## height (the mean of the raw heights under the footprint; a hillside lot
## keeps the mean too, so its uphill side is cut). Marks the pad's nodes
## tree-free.
func _pad(cx: float, cz: float, yaw: float, hx: float, hz: float, _hillside: bool, plateau := 5.0) -> float:
	var data: PackedFloat32Array = _hf.data
	var b := Basis(Vector3.UP, yaw)
	var mean := 0.0
	var cnt := 0
	for sx: float in [-0.7, 0.0, 0.7]:
		for sz: float in [-0.7, 0.0, 0.7]:
			var q := Vector3(cx, 0, cz) + b * Vector3(sx * hx, 0, sz * hz)
			mean += _h(q.x, q.z)
			cnt += 1
	mean /= float(cnt)
	var blend := 5.0 if _hillside else 11.0
	var reach := maxf(hx, hz) + plateau + blend + STEP
	var n0 := _node(cx - reach, cz - reach)
	var n1 := _node(cx + reach, cz + reach)
	var binv := b.transposed()
	for j in range(n0.y, n1.y + 1):
		for i in range(n0.x, n1.x + 1):
			var q := binv * Vector3(_ox + i * STEP - cx, 0, _ox + j * STEP - cz)
			var dist := maxf(maxf(absf(q.x) - hx, absf(q.z) - hz), 0.0)
			if dist > plateau + blend:
				continue
			var t := clampf((dist - plateau) / blend, 0.0, 1.0)
			var w := 1.0 - t * t * (3.0 - 2.0 * t)
			var idx := j * _cols + i
			data[idx] = lerpf(data[idx], mean, w)
			if dist <= plateau + 1.5:
				_blocked[idx] |= 1
	_hf.data = data
	return mean


## Flood the lowest basin: cells whose lowest corner is under the water
## level, from the lake's centre out, capped in size (lower the level until
## it fits). Marks the lake and a 6 m clearing round it.
func _lake(c: Vector3) -> Dictionary:
	var data: PackedFloat32Array = _hf.data
	var start := _node(c.x, c.z)
	var level := float(data[start.y * _cols + start.x]) + 1.8
	var cells: Array[Vector2i] = []
	for attempt in 6:
		cells = []
		var seen := {}
		var q: Array[Vector2i] = [start]
		seen[start] = true
		while not q.is_empty() and cells.size() < 1400:
			var n: Vector2i = q.pop_front()
			if n.x < 1 or n.y < 1 or n.x >= _cols - 2 or n.y >= _cols - 2:
				continue
			var mn := minf(minf(data[n.y * _cols + n.x], data[n.y * _cols + n.x + 1]), minf(data[(n.y + 1) * _cols + n.x], data[(n.y + 1) * _cols + n.x + 1]))
			if mn >= level:
				continue
			if absf(_ox + n.x * STEP) > _half - 6.0 or absf(_ox + n.y * STEP) > _half - 6.0:
				continue
			cells.append(n)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var m: Vector2i = n + d
				if not seen.has(m):
					seen[m] = true
					q.append(m)
		if cells.size() <= 900:
			break
		level -= 0.35
	for n in cells:
		for dj in range(-2, 4):
			for di in range(-2, 4):
				var i := n.x + di
				var j := n.y + dj
				if i >= 0 and j >= 0 and i < _cols and j < _cols:
					_blocked[j * _cols + i] |= 4
		for dj in 2:
			for di in 2:
				_blocked[(n.y + dj) * _cols + n.x + di] |= 2
	return { "cells": cells, "level": level }


func _water(g: GKMesh, lake: Dictionary) -> void:
	var y: float = lake.level
	for n in lake.cells:
		var c: Vector2i = n
		var x0 := _ox + c.x * STEP
		var z0 := _ox + c.y * STEP
		GKForestLots.face(g, "window_dark:#2f4c58", PackedVector3Array([Vector3(x0, y, z0), Vector3(x0 + STEP, y, z0), Vector3(x0 + STEP, y, z0 + STEP), Vector3(x0, y, z0 + STEP)]), Vector3.UP)


## Beyond the grid: flat skirts out to the horizon at the edge's own heights
## (height_at clamps to the edge, so the far trees sit on them).
func _skirt(g: GKMesh) -> void:
	var data: PackedFloat32Array = _hf.data
	var far := 1600.0
	var e := _ox + (_cols - 1) * STEP
	var role := "foliage:#3e5a2a"
	g.tint = Color(0.8, 0.82, 0.72)
	var rise := 95.0
	for k in _cols - 1:
		var x0 := _ox + k * STEP
		var x1 := x0 + STEP
		var hn0 := data[k]
		var hn1 := data[k + 1]
		GKForestLots.face(g, role, PackedVector3Array([Vector3(x0, hn0, _ox), Vector3(x1, hn1, _ox), Vector3(x1, hn1 + rise, -far), Vector3(x0, hn0 + rise, -far)]), Vector3.UP)
		var hs0 := data[(_cols - 1) * _cols + k]
		var hs1 := data[(_cols - 1) * _cols + k + 1]
		GKForestLots.face(g, role, PackedVector3Array([Vector3(x0, hs0, e), Vector3(x1, hs1, e), Vector3(x1, hs1 + rise, far), Vector3(x0, hs0 + rise, far)]), Vector3.UP)
		var hw0 := data[k * _cols]
		var hw1 := data[(k + 1) * _cols]
		GKForestLots.face(g, role, PackedVector3Array([Vector3(_ox, hw0, x0), Vector3(_ox, hw1, x1), Vector3(-far, hw1 + rise, x1), Vector3(-far, hw0 + rise, x0)]), Vector3.UP)
		var he0 := data[k * _cols + _cols - 1]
		var he1 := data[(k + 1) * _cols + _cols - 1]
		GKForestLots.face(g, role, PackedVector3Array([Vector3(e, he0, x0), Vector3(e, he1, x1), Vector3(far, he1 + rise, x1), Vector3(far, he0 + rise, x0)]), Vector3.UP)
	for cx: float in [_ox, e]:
		for cz: float in [_ox, e]:
			var nn := _node(cx, cz)
			var hc := data[nn.y * _cols + nn.x]
			var fx := -far if cx < 0.0 else far
			var fz := -far if cz < 0.0 else far
			GKForestLots.face(g, role, PackedVector3Array([Vector3(cx, hc, cz), Vector3(fx, hc + rise, cz), Vector3(fx, hc + rise, fz), Vector3(cx, hc + rise, fz)]), Vector3.UP)
	g.tint = Color.WHITE


func _ground_tint(i: int, j: int, level: float) -> Color:
	var data: PackedFloat32Array = _hf.data
	var h := data[j * _cols + i]
	var x := _ox + i * STEP
	var z := _ox + j * STEP
	var hl := data[j * _cols + maxi(i - 1, 0)]
	var hr := data[j * _cols + mini(i + 1, _cols - 1)]
	var hd := data[maxi(j - 1, 0) * _cols + i]
	var hu := data[mini(j + 1, _cols - 1) * _cols + i]
	var slope := Vector2(hr - hl, hu - hd).length() / (2.0 * STEP)
	var t := clampf((h + 9.0) / 18.0, 0.0, 1.0)
	var c := Color(0.66, 0.70, 0.50).lerp(Color(0.98, 1.0, 0.86), t)
	var jit := _vn(i, j, 77) * 0.12 - 0.06
	c = Color(c.r + jit, c.g + jit, c.b + jit * 0.5)
	if slope > 0.9:
		c = c.lerp(Color(0.8, 0.76, 0.62), clampf((slope - 0.9) * 1.5, 0.0, 0.3))
	var fl := _blocked[j * _cols + i]
	if (fl & 8) != 0 and (fl & 2) == 0:
		c = c.lerp(Color(0.80, 1.0, 0.62), 0.45)                  # the mown lawn round a lot
	if h < level + 0.4 and (_blocked[j * _cols + i] & 2) != 0:
		c = c.lerp(Color(0.45, 0.40, 0.30), 0.8)
	elif (_blocked[j * _cols + i] & 1) == 0 and (_blocked[j * _cols + i] & 4) == 0:
		c = c.darkened(0.3).lerp(Color(0.55, 0.5, 0.36), 0.25)  # the forest floor under the crowns
		var warm_t := 0.42 + 0.22 * _vn(_seed, 3, 91)
		if _noise(x + 90.0, z + 40.0, 58.0, _seed + 13) > warm_t:
			c = c.lerp(Color(0.85, 0.6, 0.32), 0.35)                # fallen leaves under the autumn stands
	if absf(x) > _half or absf(z) > _half:
		c = c.darkened(0.15)
	return c


# ----------------------------------------------------------------- layout

## Pick the lots: candidates on a jittered grid, ranked by relief; the
## chapel, water tower and barn take hilltops, the lodge and a house the
## valley, a hall is cut into the steepest side; the rest fill in. Kinds
## cycle so every map has the landmarks and a mix.
func _sites(n_b: int, lake_c: Vector3, d_all: float) -> Array:
	var lim := _half - 40.0
	var lim_out := _half - 34.0                         # the outliers' ring, out in the woods
	var cands := []
	var sp := 24.0
	var k := int(lim * 2.0 / sp)
	for j in k + 1:
		for i in k + 1:
			var x := -lim + i * sp + _rng.randf_range(-6.0, 6.0)
			var z := -lim + j * sp + _rng.randf_range(-6.0, 6.0)
			if Vector2(x, z).length() > lim_out:
				continue                                     # a disc: every lot sits well inside every pocket's U
			if Vector2(x, z).distance_to(Vector2(lake_c.x, lake_c.z)) < 40.0:
				continue
			var h := _h(x, z)
			var around := 0.0
			for q in 8:
				var an := q * TAU / 8.0
				around += _h(x + cos(an) * 22.0, z + sin(an) * 22.0)
			around /= 8.0
			var gx := _h(x + 6.0, z) - _h(x - 6.0, z)
			var gz := _h(x, z + 6.0) - _h(x, z - 6.0)
			cands.append({ "pos": Vector3(x, h, z), "relief": h - around, "slope": Vector2(gx, gz).length() / 12.0, "outer": Vector2(x, z).length() > lim })
	var picked := []
	var take := func(c: Dictionary, kind: String, site: String) -> void:
		picked.append({ "kind": kind, "pos": c.pos, "site": site, "yaw": 0.0, "slope": c.slope })
	var free := func(c: Dictionary, min_d: float) -> bool:
		for q in picked:
			if Vector2(c.pos.x, c.pos.z).distance_to(Vector2(q.pos.x, q.pos.z)) < min_d:
				return false
		return true
	var by_relief := cands.duplicate()
	by_relief.sort_custom(func(u: Dictionary, v: Dictionary) -> bool: return u.relief > v.relief)
	var by_slope := cands.duplicate()
	by_slope.sort_custom(func(u: Dictionary, v: Dictionary) -> bool: return u.slope > v.slope)
	var order := [["chapel", "hilltop"], ["lodge", "valley"], ["watertower", "hilltop"], ["hall", "hillside"], ["barn", "hilltop"],
		["house", "valley"], ["lodge", "outer"], ["hall", "any"], ["ruin", "outer"], ["house", "any"], ["lodge", "any"], ["house", "any"], ["ruin", "any"],
		["hall", "any"], ["house", "any"]]
	for o in order:
		if picked.size() >= n_b:
			break
		var kind: String = o[0]
		var site: String = o[1]
		var pool: Array
		match site:
			"hilltop":
				pool = by_relief
			"valley":
				pool = by_relief.duplicate()
				pool.reverse()
			"hillside":
				pool = by_slope
			"outer":
				pool = _shuffled(cands).filter(func(c: Dictionary) -> bool: return c.outer)
			_:
				pool = _shuffled(cands)
		for c in pool:
			if c.outer and site != "outer":
				continue
			if site == "hilltop" and float(c.relief) < 1.0:
				break
			if site == "valley" and float(c.relief) > -0.5:
				break
			if free.call(c, 36.0):
				take.call(c, kind, site)
				break
	# fill if the relief ran out of hilltops / valleys
	var fill := _shuffled(cands)
	var kinds := ["house", "hall", "lodge", "ruin"]
	var ki := 0
	for c in fill:
		if picked.size() >= n_b:
			break
		if not c.outer and free.call(c, 36.0):
			take.call(c, kinds[ki % kinds.size()], "any")
			ki += 1
	# face the others (roads start at the door), snapped to 15 degrees
	var cen := Vector3.ZERO
	for q in picked:
		cen += q.pos
	cen /= float(maxi(picked.size(), 1))
	for q in picked:
		var to: Vector3 = cen - (q.pos as Vector3)
		if to.length() < 1.0:
			to = Vector3(0, 0, 1)
		var yaw := atan2(to.x, to.z) + deg_to_rad(_rng.randf_range(-25.0, 25.0))
		q.yaw = snappedf(yaw, deg_to_rad(15.0))
		q["disrepair"] = clampf(d_all + _rng.randf_range(-0.45, 0.45), 0.0, 1.0)
		if q.kind == "barn":
			q.disrepair = maxf(q.disrepair, 0.7)             # the burnt barn on the hill
		if q.kind == "chapel":
			q.disrepair = minf(q.disrepair, 0.4)             # the landmark stays whole
		if q.kind == "ruin":
			q.disrepair = 1.0
		var prng := RandomNumberGenerator.new()
		prng.seed = _rng.randi()
		q["plan"] = GKForestLots.plan(q.kind, prng)
	return picked


func _shuffled(arr: Array) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out


## Roads: the minimum spanning tree over the doors plus one loop-closing
## edge; each a gently bent polyline every 3 m, bent the other way when it
## would cross a lot or the lake.
func _roads(specs: Array, lake: Dictionary) -> Array:
	var n := specs.size()
	var doors: Array[Vector3] = []
	for sp in specs:
		var b := Basis(Vector3.UP, float(sp.yaw))
		doors.append(sp.pos + b * Vector3(0, 0, float(sp.plan.hz) + 4.0))
	var in_tree := [0]
	var edges := []
	while in_tree.size() < n:
		var best := 1e18
		var bi := -1
		var bj := -1
		for i in in_tree:
			for j in n:
				if j in in_tree:
					continue
				var d := doors[i].distance_squared_to(doors[j])
				if d < best:
					best = d
					bi = i
					bj = j
		in_tree.append(bj)
		edges.append([bi, bj])
	# the loop: the shortest pair not already joined, at least 3 hops apart
	var adj := {}
	for e in edges:
		adj[e[0]] = adj.get(e[0], []) + [e[1]]
		adj[e[1]] = adj.get(e[1], []) + [e[0]]
	var best_e := []
	var best_d := 1e18
	for i in n:
		for j in range(i + 1, n):
			if _hops(adj, i, j) < 3:
				continue
			var d := doors[i].distance_to(doors[j])
			if d < best_d:
				best_d = d
				best_e = [i, j]
	if not best_e.is_empty():
		edges.append(best_e)
	var out := []
	for e in edges:
		var i: int = e[0]
		var j: int = e[1]
		var dis := (float(specs[i].disrepair) + float(specs[j].disrepair)) * 0.5
		var role := "asphalt" if dis < 0.4 else ("asphalt_lot" if dis < 0.7 else "concrete:#8f8872")
		var pts := _road_line(doors[i], doors[j], specs, i, j, lake)
		out.append({ "pts": pts, "role": role, "a": i, "b": j })
	return out


static func _hops(adj: Dictionary, a: int, b: int) -> int:
	var dist := { a: 0 }
	var q := [a]
	while not q.is_empty():
		var u: int = q.pop_front()
		if u == b:
			return dist[u]
		for v in adj.get(u, []):
			if not dist.has(v):
				dist[v] = dist[u] + 1
				q.append(v)
	return 99


func _road_line(a: Vector3, b: Vector3, specs: Array, ia: int, ib: int, lake: Dictionary) -> Array:
	var ln := a.distance_to(b)
	var dir := (b - a) / maxf(ln, 1e-3)
	var side := Vector3(-dir.z, 0, dir.x)
	var best: Array = []
	var best_hits := 1 << 30
	var bend := _rng.randf_range(0.08, 0.2) * ln * (1.0 if _rng.randf() < 0.5 else -1.0)
	for attempt in 6:
		var ctrl := (a + b) * 0.5 + side * bend
		var pts: Array = []
		var n := maxi(int(ln / 3.0), 2)
		var hits := 0
		for k in n + 1:
			var t := k / float(n)
			var q := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
			q.y = _h(q.x, q.z)
			pts.append(q)
			if k > 1 and k < n - 1:
				for si in specs.size():
					if si == ia or si == ib:
						continue
					var sp: Dictionary = specs[si]
					var l: Vector3 = Basis(Vector3.UP, float(sp.yaw)).transposed() * (q - (sp.pos as Vector3))
					if absf(l.x) < float(sp.plan.hx) + 7.0 and absf(l.z) < float(sp.plan.hz) + 7.0:
						hits += 1
				var nd := _node(q.x, q.z)
				if (_blocked[nd.y * _cols + nd.x] & 2) != 0:
					hits += 1
		if hits < best_hits:
			best_hits = hits
			best = pts
		if hits == 0:
			break
		bend = -bend * (1.0 + 0.5 * attempt)
	return best


## Parked cars: one or two a road leg, pulled off to the side, away from
## the lots (the guards' loops run 4 m off the walls).
func _cars(roads: Array, specs: Array, d_all: float) -> Array:
	var out := []
	for rd in roads:
		var pts: Array = rd.pts
		if pts.size() < 8:
			continue
		var n := 1 + (1 if _rng.randf() < 0.5 else 0)
		for k in n:
			var i := _rng.randi_range(3, pts.size() - 4)
			var p: Vector3 = pts[i]
			var dir: Vector3 = ((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3))
			dir.y = 0.0
			dir = dir.normalized()
			var sd := 1.0 if _rng.randf() < 0.5 else -1.0
			var at := p + Vector3(-dir.z, 0, dir.x) * sd * (ROAD_HW + 1.4)
			var ok := true
			for sp in specs:
				if Vector2(at.x, at.z).distance_to(Vector2(sp.pos.x, sp.pos.z)) < _loop_radius(sp) + 5.0:
					ok = false
			for c in out:
				if Vector2(at.x, at.z).distance_to(Vector2(c.pos.x, c.pos.z)) < 7.0:
					ok = false
			if not ok:
				continue
			at.y = _h(at.x, at.z)
			var yaw := atan2(dir.x, dir.z) + (PI if _rng.randf() < 0.5 else 0.0) + _rng.randf_range(-0.12, 0.12)
			out.append({ "pos": at, "yaw": yaw, "paint": GKForestLots.PAINTS[_rng.randi() % GKForestLots.PAINTS.size()],
				"wear": clampf(d_all + _rng.randf_range(-0.3, 0.3), 0.0, 1.0) })
	return out


## How far the guard's loop reaches from the lot's centre (its far corner,
## past the tower / silo side).
static func _loop_radius(sp: Dictionary) -> float:
	var mx := 4.0 + (5.5 if sp.kind in ["chapel", "barn"] else 0.0)
	return Vector2(float(sp.plan.hx) + mx, float(sp.plan.hz) + 4.0).length()


## Mark the nodes trees must keep off: lots, the mast, the roads, the spawn
## pockets, the pads, the cars.
func _mark(specs: Array, mast_at: Vector3, roads: Array, spawns: Array, extracts: Array, cars: Array) -> void:
	var disc := func(x: float, z: float, r: float, bit: int) -> void:
		var n0 := _node(x - r, z - r)
		var n1 := _node(x + r, z + r)
		for j in range(n0.y, n1.y + 1):
			for i in range(n0.x, n1.x + 1):
				if Vector2(_ox + i * STEP - x, _ox + j * STEP - z).length() <= r:
					_blocked[j * _cols + i] |= bit
	for sp in specs:
		disc.call(sp.pos.x, sp.pos.z, _loop_radius(sp) + 5.0, 1 | 8)
	disc.call(mast_at.x, mast_at.z, 7.0, 1 | 8)
	for rd in roads:
		var hw := ROAD_HW if str(rd.get("role", "")) != "trail" else 1.0
		for q in rd.pts:
			disc.call((q as Vector3).x, (q as Vector3).z, hw + 3.0, 1)
			disc.call((q as Vector3).x, (q as Vector3).z, hw + 1.0, 16)
	for s in spawns:
		disc.call(s.x, s.z, 7.5, 1 | 8)
	for e in extracts:
		disc.call(e.x, e.z, 5.5, 1 | 8)
	for c in cars:
		disc.call(c.pos.x, c.pos.z, 4.5, 1 | 8)


## Cut the road beds: each road's centre height smoothed along it (ends
## pinned to the doors), and the ground within ROAD_HW + 4.5 m pulled level
## to it across, so roads cut crests and fill dips instead of rolling over
## every bump. The lots' pads (already flat) are left alone.
func _carve(roads: Array) -> void:
	var data: PackedFloat32Array = _hf.data
	var best := {}                       # node -> [dist, y]
	for rd in roads:
		var pts: Array = rd.pts
		var n := pts.size()
		var ys := PackedFloat32Array()
		ys.resize(n)
		for i in n:
			if i < 3 or i > n - 4:
				ys[i] = (pts[i] as Vector3).y
				continue
			var acc := 0.0
			var cnt := 0
			for k in range(maxi(i - 6, 0), mini(i + 7, n)):
				acc += (pts[k] as Vector3).y
				cnt += 1
			ys[i] = acc / float(cnt)
		for i in n - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var reach := ROAD_HW + 5.0
			var n0 := _node(minf(a.x, b.x) - reach, minf(a.z, b.z) - reach)
			var n1 := _node(maxf(a.x, b.x) + reach, maxf(a.z, b.z) + reach)
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var l2 := maxf(ab.length_squared(), 1e-4)
			for j in range(n0.y, n1.y + 1):
				for ii in range(n0.x, n1.x + 1):
					var idx := j * _cols + ii
					if (_blocked[idx] & 1) != 0:
						continue
					var q := Vector2(_ox + ii * STEP - a.x, _ox + j * STEP - a.z)
					var t := clampf(q.dot(ab) / l2, 0.0, 1.0)
					var d := (q - ab * t).length()
					if d > reach:
						continue
					if not best.has(idx) or float(best[idx][0]) > d:
						best[idx] = [d, lerpf(ys[i], ys[i + 1], t)]
	for idx in best:
		var d: float = best[idx][0]
		var w := 1.0 - smoothstep(ROAD_HW + 2.0, ROAD_HW + 5.0, d)
		data[idx] = lerpf(data[idx], float(best[idx][1]), w)
	_hf.data = data
	for rd in roads:
		var pts: Array = rd.pts
		for i in pts.size():
			var v: Vector3 = pts[i]
			v.y = _h(v.x, v.z)
			pts[i] = v


## A dirt trail from beside each spawn pocket to the nearest road point, so
## the first thing you see stepping out is a way in.
func _trails(spawns: Array, spawn_in: Array, roads: Array, specs: Array, lake: Dictionary) -> Array:
	var out := []
	for k in spawns.size():
		var sp: Vector3 = spawns[k]
		var inward: Vector3 = spawn_in[k]
		var side := Vector3(-inward.z, 0, inward.x) * (1.0 if k % 2 == 0 else -1.0)
		var start := sp + side * 6.8 + inward * 1.5
		var best := Vector3.ZERO
		var bd := 1e9
		for rd in roads:
			for q in rd.pts:
				var d := Vector2((q as Vector3).x - start.x, (q as Vector3).z - start.z).length()
				if d < bd:
					bd = d
					best = q
		if bd > 1e8:
			continue
		var pts := _road_line(start, best, specs, -1, -1, lake)
		for i in pts.size():
			var v: Vector3 = pts[i]
			v.x = clampf(v.x, -_half + 4.0, _half - 4.0)
			v.z = clampf(v.z, -_half + 4.0, _half - 4.0)
			v.y = _h(v.x, v.z)
			pts[i] = v
		var keep := [pts[0]]
		for i in range(1, pts.size()):
			if Vector2((pts[i] as Vector3).x - (keep[-1] as Vector3).x, (pts[i] as Vector3).z - (keep[-1] as Vector3).z).length() > 1.0:
				keep.append(pts[i])
		pts = keep
		if pts.size() < 2:
			continue
		out.append({ "pts": pts, "role": "trail" })
	return out


func _free_at(x: float, z: float, r: float, bits := 2 | 8 | 16) -> bool:
	if absf(x) > _half - 8.0 or absf(z) > _half - 8.0:
		return false
	var n0 := _node(x - r, z - r)
	var n1 := _node(x + r, z + r)
	for j in range(n0.y, n1.y + 1):
		for i in range(n0.x, n1.x + 1):
			if (_blocked[j * _cols + i] & bits) != 0:
				return false
	return true


func _disc(x: float, z: float, r: float, bit: int) -> void:
	var n0 := _node(x - r, z - r)
	var n1 := _node(x + r, z + r)
	for j in range(n0.y, n1.y + 1):
		for i in range(n0.x, n1.x + 1):
			if Vector2(_ox + i * STEP - x, _ox + j * STEP - z).length() <= r:
				_blocked[j * _cols + i] |= bit


## Mid-forest points of interest, so the walk in from an edge has things
## to steer by and look at: a fire lookout on high ground (a landmark),
## hunting stands, a car wreck off a road, a campfire clearing, ruined field
## walls; and a power line cut straight across the map, its clearing a
## navigation line. Returns { items: [{kind, pos, yaw}], pylons: [{pos, yaw, t}] }.
func _pois(specs: Array, spawns: Array, roads: Array, lake: Dictionary) -> Dictionary:
	var items := []
	var far_from := func(x: float, z: float, d: float) -> bool:
		for q in items:
			if Vector2(x - q.pos.x, z - q.pos.z).length() < d:
				return false
		for sp in specs:
			if Vector2(x - sp.pos.x, z - sp.pos.z).length() < _loop_radius(sp) + 14.0:
				return false
		for s in spawns:
			if Vector2(x - s.x, z - s.z).length() < 20.0:
				return false
		return true
	var cands := []
	for k in 500:
		cands.append(Vector2(_rng.randf_range(-_half + 12.0, _half - 12.0), _rng.randf_range(-_half + 12.0, _half - 12.0)))
	# the lookout: the highest free spot 60-125 m out
	var lb := -1e9
	var lat := Vector2.INF
	for c in cands:
		var r: float = c.length()
		if r < 60.0 or r > 125.0:
			continue
		var h := _h(c.x, c.y)
		if h > lb and _free_at(c.x, c.y, 14.0) and far_from.call(c.x, c.y, 30.0):
			lb = h
			lat = c
	if lat != Vector2.INF:
		var y := _pad(lat.x, lat.y, 0.0, 3.2, 3.2, false, 1.5)
		items.append({ "kind": "lookout", "pos": Vector3(lat.x, y, lat.y), "yaw": _rng.randf() * TAU, "r": 7.0 })
	# the rest: ring-biased (the walk in is the empty part), spaced out
	var want := [["stand", 4.0], ["stand", 4.0], ["camp", 7.5], ["wall", 9.0], ["wall", 9.0], ["stand", 4.0]]
	for wk in want:
		var kind: String = wk[0]
		var r: float = wk[1]
		for tries in 60:
			var c: Vector2 = cands[_rng.randi() % cands.size()]
			if c.length() < 55.0:
				continue
			if _free_at(c.x, c.y, r) and far_from.call(c.x, c.y, 32.0):
				items.append({ "kind": kind, "pos": Vector3(c.x, _h(c.x, c.y), c.y), "yaw": _rng.randf() * TAU, "r": r })
				break
	# the wreck: off the longest road's middle, nose into the trees
	var longest: Array = []
	for rd in roads:
		if (rd.pts as Array).size() > longest.size():
			longest = rd.pts
	if longest.size() > 10:
		for tries in 8:
			var i := _rng.randi_range(4, longest.size() - 5)
			var p0: Vector3 = longest[i]
			var dir: Vector3 = (longest[i + 1] as Vector3) - (longest[i - 1] as Vector3)
			dir.y = 0.0
			dir = dir.normalized()
			var sd := 1.0 if _rng.randf() < 0.5 else -1.0
			var at := p0 + Vector3(-dir.z, 0, dir.x) * sd * (ROAD_HW + 8.5)
			if _free_at(at.x, at.z, 3.0, 2 | 8) and far_from.call(at.x, at.z, 20.0):
				at.y = _h(at.x, at.z)
				items.append({ "kind": "wreck", "pos": at, "yaw": atan2(dir.x, dir.z) + sd * 0.7, "r": 4.0 })
				break
	for q in items:
		_disc(q.pos.x, q.pos.z, float(q.r), 1 | 8)
	# the power line: a straight cut across the whole map
	var pylons := []
	var ang := _rng.randf() * PI
	var d := Vector3(cos(ang), 0, sin(ang))
	var nrm := Vector3(-d.z, 0, d.x)
	var off := _rng.randf_range(-45.0, 45.0)
	var t := -_half - MARGIN + 8.0
	var lim := _half + MARGIN - 8.0
	while t < lim:
		var q := nrm * off + d * t
		var inside := absf(q.x) < _half - 2.0 and absf(q.z) < _half - 2.0
		var nd := _node(q.x, q.z)
		var flags := _blocked[nd.y * _cols + nd.x]
		var ok := (flags & (2 | 8 | 16)) == 0 and _free_at(q.x, q.z, 3.0, 2 | 8 | 16) if inside else (flags & (2 | 8)) == 0
		if ok:
			q.y = _h(q.x, q.z)
			pylons.append({ "pos": q, "yaw": atan2(d.x, d.z) + PI * 0.5, "t": t })
		t += 34.0
	# the clearing under it (trees off, ground lighter; bushes may stay)
	var s := -_half - MARGIN
	while s < _half + MARGIN:
		_disc(nrm.x * off + d.x * s, nrm.z * off + d.z * s, 6.5, 1)
		s += 3.0
	return { "items": items, "pylons": pylons }


## A car's lean on the slope under it.
func _tilt_at(x: float, z: float) -> Basis:
	var n := Vector3(_h(x - 1.5, z) - _h(x + 1.5, z), 3.0, _h(x, z - 1.5) - _h(x, z + 1.5)).normalized()
	var ax := Vector3.UP.cross(n)
	if ax.length() < 1e-4:
		return Basis.IDENTITY
	return Basis(ax.normalized(), acos(clampf(n.y, -1.0, 1.0)))


## The retaining wall behind a lot cut into a hillside: stone along the
## uphill face where the ground stands over the pad.
func _retaining(g: GKMesh, a: GKAsset, sp: Dictionary) -> void:
	var b := Basis(Vector3.UP, float(sp.yaw))
	var hx: float = sp.plan.hx
	var hz: float = sp.plan.hz
	var pad: float = sp.pos.y
	var best_n := Vector3.ZERO
	var best_rise := 0.0
	for n: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var off := (hz if absf(n.z) > 0.5 else hx) + 7.5
		var q: Vector3 = sp.pos + b * (n * off)
		var rise := _h(q.x, q.z) - pad
		if rise > best_rise:
			best_rise = rise
			best_n = n
	if best_rise < 1.2:
		return
	var off := (hz if absf(best_n.z) > 0.5 else hx) + 5.4
	var along := Vector3(1, 0, 0) if absf(best_n.z) > 0.5 else Vector3(0, 0, 1)
	var half := (hx if absf(best_n.z) > 0.5 else hz) + 5.0
	g.push(Transform3D(b, sp.pos))
	var h := minf(best_rise * 0.6, 3.5)
	GKArch.block(g, a, "stone_grey", along * -half + best_n * (off - 0.3) + Vector3(0, -0.5, 0), along * half + best_n * (off + 0.3) + Vector3(0, h, 0))
	g.box("stone_grey:#cdc8bb", best_n * off + Vector3(0, h + 0.05, 0), along.abs() * (half * 2.0 + 0.2) + best_n.abs() * 0.8 + Vector3(0, 0.1, 0))
	g.pop()


# ----------------------------------------------------------------- forest

## Big cheap conifers out on the skirt (40-260 m past the grid), on the same
## ramp the skirt rises by, so the hills on the horizon read as forest.
func _far_ring(a: GKAsset, M: Transform3D) -> void:
	var g := GKMesh.new()
	g.push(M)
	var e := _ox + (_cols - 1) * STEP
	var rise := 95.0
	var span := 1600.0 - e
	var rr := RandomNumberGenerator.new()
	rr.seed = _seed * 17 + 5
	for ring in 4:
		var dist := 40.0 + ring * 60.0
		var r := e + dist
		var stepw := 11.0 + ring * 5.0
		var t := -r
		while t < r:
			for side in 4:
				var x := t + rr.randf_range(-4.0, 4.0)
				var z := -r + rr.randf_range(-10.0, 10.0)
				var q: Vector3 = [Vector3(x, 0, z), Vector3(-x, 0, -z), Vector3(z, 0, x), Vector3(-z, 0, -x)][side]
				var over := maxf(absf(q.x), absf(q.z)) - e
				q.y = _h(clampf(q.x, _ox, e), clampf(q.z, _ox, e)) + rise * maxf(over, 0.0) / span - 0.5
				var k := rr.randf_range(1.4, 2.2)
				var roles := ["foliage:#2d4a26", "foliage:#355a22", "foliage:#27421f", "foliage:#3d5a2a"]
				g.tube(roles[rr.randi() % roles.size()], [q + Vector3(0, 2.0 * k, 0), q + Vector3(0, 11.0 * k, 0)], [2.6 * k, 0.0], 5, false)
			t += stepw
	g.pop()
	a.add_part("far_ring", g.commit(), Transform3D.IDENTITY, false)

## Trees on a jittered grid wherever nothing else is, one GKMesh per 60 m
## cell; conifers and broadleaves, trunks as thin box colliders inside the
## play area. A far ring of big conifers past the edge. Bushes (walk-through
## hide volumes) in the forest and along the roads. Returns the bushes.
func _forest(a: GKAsset, M: Transform3D, _lake: Dictionary) -> Array:
	var cells := {}
	var cell_of := func(x: float, z: float) -> Vector2i:
		return Vector2i(int(floor((x + _half + MARGIN) / CELL)), int(floor((z + _half + MARGIN) / CELL)))
	var mesh_for := func(x: float, z: float) -> GKMesh:
		var c: Vector2i = cell_of.call(x, z)
		if not cells.has(c):
			var g := GKMesh.new()
			g.push(M)
			cells[c] = g
		return cells[c]
	var ext := _half + MARGIN - 4.0
	var sp := 7.4
	var sd := _seed
	# per seed: how far the autumn has got (the season mix differs run to run)
	var warm_t := 0.42 + 0.22 * _vn(sd, 3, 91)
	var WARM := ["foliage_gold", "foliage_gold:#e2bb34", "foliage_autumn", "foliage_autumn:#dc8f2c", "foliage_red", "foliage_red:#c2461f", "foliage:#6f8c2c"]
	var GREEN := ["foliage", "foliage:#3d6a25", "foliage:#6f8c2c", "foliage:#2f4f22", "foliage", "foliage_gold"]
	var PINE := ["foliage:#2d4a26", "foliage:#355a22", "foliage:#3d6a25", "foliage:#27421f"]
	var BIRCH := ["foliage_gold:#e2c040", "foliage:#7a9a34", "foliage_gold", "foliage:#8aa83c"]
	var FERN := ["foliage:#4a6a2a", "foliage:#5e7a30", "foliage_autumn:#a8702a", "hedge:#3e5a28"]
	var plant := func(px: float, pz: float, inside: bool, dens: float, warm: float, birch: bool) -> void:
		var thick := dens > 0.66
		var k := _rng.randf_range(0.85, 1.45) * (1.25 if not inside else 1.0) * (1.2 if thick else 1.0)
		var at := Vector3(px, _h(px, pz) - 0.15, pz)
		var g: GKMesh = mesh_for.call(px, pz)
		var trunk := 0.5 * k
		var th := 5.0 * k
		if birch and _rng.randf() < 0.8:
			GKForestLots.birch(g, at, k * 0.95, _rng, BIRCH[_rng.randi() % BIRCH.size()])
			trunk = 0.3 * k
			th = 6.0 * k
		else:
			var p_con := 0.22 if warm > warm_t else (0.85 if warm < 0.3 else 0.55)
			if _rng.randf() < p_con:
				if _rng.randf() < 0.18:
					k *= 1.45                                   # the odd tall pine over the canopy
				GKForestLots.conifer(g, at, k, PINE[_rng.randi() % PINE.size()])
			else:
				var pal: Array = WARM if warm > warm_t else GREEN
				GKForestLots.tree(g, at, k * (1.15 if warm > warm_t else 1.0), _rng, pal[_rng.randi() % pal.size()])
		if inside:
			a.add_box_xf(M * Transform3D(Basis.IDENTITY, at + Vector3(0, th * 0.5, 0)), Vector3(trunk, th, trunk))
			if dens > 0.4 and _rng.randf() < 0.45:
				var fa := _rng.randf() * TAU
				var fp := Vector2(px + cos(fa) * 2.2, pz + sin(fa) * 2.2)
				var fn := _node(fp.x, fp.y)
				if (_blocked[fn.y * _cols + fn.x] & (2 | 8 | 16)) == 0:
					GKForestLots.fern(g, Vector3(fp.x, _h(fp.x, fp.y), fp.y), _rng.randf_range(0.6, 1.1), _rng, FERN[_rng.randi() % FERN.size()])
	var x := -ext
	while x < ext:
		var z := -ext
		while z < ext:
			var px := x + _rng.randf_range(-2.8, 2.8)
			var pz := z + _rng.randf_range(-2.8, 2.8)
			var inside := absf(px) < _half - 3.0 and absf(pz) < _half - 3.0
			var dens := _noise(px + 311.0, pz - 97.0, 68.0, sd + 11) + 0.3 * smoothstep(70.0, 125.0, maxf(absf(px), absf(pz)))
			var warm := _noise(px + 90.0, pz + 40.0, 58.0, sd + 13)
			var birch := _noise(px - 500.0, pz + 200.0, 44.0, sd + 12) > 0.7
			# clearings where the density field is low; thick stands where it's high
			var p_accept := lerpf(0.0, 1.0, smoothstep(0.14, 0.5, dens)) if inside else 0.62
			if _rng.randf() > p_accept:
				z += sp
				continue
			var nd := _node(px, pz)
			if inside and (_blocked[nd.y * _cols + nd.x] & 7) != 0:
				z += sp
				continue
			plant.call(px, pz, inside, dens, warm, birch)
			if inside and dens > 0.66 and _rng.randf() < 0.6:
				var qx := px + _rng.randf_range(-3.6, 3.6)
				var qz := pz + _rng.randf_range(-3.6, 3.6)
				var qn := _node(qx, qz)
				if (_blocked[qn.y * _cols + qn.x] & 7) == 0:
					plant.call(qx, qz, true, dens, warm, birch)
			z += sp
		x += sp
	# fallen logs in the woods
	var logs := 0
	var lt := 0
	while logs < 26 and lt < 400:
		lt += 1
		var px := _rng.randf_range(-_half + 10.0, _half - 10.0)
		var pz := _rng.randf_range(-_half + 10.0, _half - 10.0)
		if not _free_at(px, pz, 5.0, 1 | 2 | 8 | 16):
			continue
		GKForestLots.log_fallen(mesh_for.call(px, pz), a, Vector3(px, 0, pz), _rng.randf() * TAU, _rng.randf_range(4.0, 7.5), _rng.randf_range(0.28, 0.42), _h)
		logs += 1
	# bushes: in the woods and along the roads
	var bushes := []
	var n_b := int(110.0 * (_half / 150.0) * (_half / 150.0))
	var tries := 0
	while bushes.size() < n_b and tries < n_b * 6:
		tries += 1
		var px := _rng.randf_range(-_half + 6.0, _half - 6.0)
		var pz := _rng.randf_range(-_half + 6.0, _half - 6.0)
		var nd := _node(px, pz)
		var flags := _blocked[nd.y * _cols + nd.x]
		if (flags & (2 | 8)) != 0:
			continue                                    # never on the lake, a lot, a pocket, a pad or a car
		if (flags & 1) != 0 and _rng.randf() < 0.6:
			continue                                    # mostly off the roads; a few beside them
		var r := _rng.randf_range(1.3, 1.9)
		var at := Vector3(px, _h(px, pz), pz)
		var g: GKMesh = mesh_for.call(px, pz)
		GKForestLots.bush(g, at, r, _rng, GKForestLots.BUSH_ROLES[_rng.randi() % GKForestLots.BUSH_ROLES.size()])
		bushes.append({ "center": at + Vector3(0, r * 0.62, 0), "half": Vector3(r * 0.95, r * 0.62, r * 0.95), "basis": Basis(Vector3.UP, _rng.randf() * TAU) })
	for c in cells:
		var g: GKMesh = cells[c]
		g.pop()
		a.add_part("trees_%d_%d" % [c.x, c.y], g.commit())
	return bushes
