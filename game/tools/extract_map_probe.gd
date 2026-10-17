extends SceneTree
## Headless checks for the extract shooter's map (design/extract/PLAN.md,
## "Checks before hand-back"), over six seeds. Exit 0 when all pass.
##   godot --headless --path . --script res://tools/extract_map_probe.gd
## Per seed: builds in < 3 s and <= 600k tris; the contract's markers and
## meta keys; >= 6 buildings; 30-45 chests, each where it claims (inside a
## building AABB, within 4 m of a car, within 1.5 m of a bush); >= 8 guard
## posts whose every patrol leg a knee-high sphere sweeps clear; every spawn
## eye hidden from every building window; the tall landmarks seen from a
## 15 x 15 eye-height sample (the best from >= 50% of it, and at least four
## of them); the hills span >= 12 m; the same seed rebuilds the same mesh.
## Then: two seeds put their buildings in different places.

const SEEDS := [7, 1, 2, 3, 4, 5]
const BUDGET_TRIS := 600000
const BUDGET_MS := 3000

var fails := 0
var checks := 0
var first_positions := []


func _initialize() -> void:
	_go.call_deferred()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)


func _go() -> void:
	for sd in SEEDS:
		await _seed(sd)
	print("extract_map_probe: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _seed(sd: int) -> void:
	var d := GKRegistry.def("extract_forest")
	ok(d != null, "extract_forest registered")
	if d == null:
		return
	var t0 := Time.get_ticks_msec()
	var a := d.build({ "seed": sd })
	var ms := Time.get_ticks_msec() - t0
	var tris := a.triangle_count()
	ok(a.warnings.is_empty(), "seed %d warns: %s" % [sd, a.warnings])
	ok(ms < BUDGET_MS, "seed %d built in %d ms (budget %d)" % [sd, ms, BUDGET_MS])
	ok(tris <= BUDGET_TRIS, "seed %d %d tris (budget %d)" % [sd, tris, BUDGET_TRIS])
	# the contract
	for k in 8:
		ok(a.markers.has("spawn_a%d" % k) and a.markers.has("spawn_b%d" % k), "seed %d spawn markers %d" % [sd, k])
	for k in 4:
		ok(a.markers.has("extract%d" % k), "seed %d extract%d" % [sd, k])
	ok(a.markers.has("ref_cam"), "seed %d ref_cam" % sd)
	var m := a.meta
	for key in ["class", "extract", "play_area", "bot_hunt", "height", "chests", "guards", "buildings", "landmarks", "roads", "hide_volumes"]:
		ok(m.has(key), "seed %d meta.%s" % [sd, key])
	ok(m.get("extract", false) == true and m.get("bot_hunt", true) == false and str(m.get("class", "")) == "map", "seed %d meta flags" % sd)
	ok(not a.lights.is_empty(), "seed %d lights" % sd)
	var pa: Array = m.play_area
	var h_lo := 1e9
	var h_hi := -1e9
	for i in 31:
		for j in 31:
			var x := lerpf(float(pa[0]), float(pa[2]), i / 30.0)
			var z := lerpf(float(pa[1]), float(pa[3]), j / 30.0)
			var h := GKExtractForest.height_at(m, x, z)
			ok(is_finite(h), "seed %d height finite" % sd)
			h_lo = minf(h_lo, h)
			h_hi = maxf(h_hi, h)
	ok(h_hi - h_lo >= 12.0, "seed %d hills span %.1f m (need 12)" % [sd, h_hi - h_lo])
	var buildings: Array = m.buildings
	ok(buildings.size() >= 6, "seed %d %d buildings" % [sd, buildings.size()])
	var sites := {}
	for b in buildings:
		sites[str(b.get("site", ""))] = sites.get(str(b.get("site", "")), 0) + 1
	ok(sites.get("hilltop", 0) >= 2 and sites.get("valley", 0) >= 1 and sites.get("hillside", 0) >= 1, "seed %d sites: %s" % [sd, sites])
	var chests: Array = m.chests
	ok(chests.size() >= 30 and chests.size() <= 45, "seed %d %d chests" % [sd, chests.size()])
	var cars: Array = m.get("cars", [])
	var hide: Array = m.hide_volumes
	var misplaced := 0
	var tiers := { 1: 0, 2: 0, 3: 0 }
	for c in chests:
		var p: Vector3 = c.pos
		tiers[int(c.tier)] = tiers.get(int(c.tier), 0) + 1
		var where := str(c.where)
		var good := false
		match where:
			"building":
				for b in buildings:
					if (b.aabb as AABB).has_point(p):
						good = true
				if int(c.tier) == 3:
					good = good and c.has("building")
			"car":
				for cr in cars:
					if (cr.pos as Vector3).distance_to(p) <= 4.0:
						good = true
			"bush":
				for hv in hide:
					var hc: Vector3 = hv.center
					if Vector2(hc.x, hc.z).distance_to(Vector2(p.x, p.z)) <= 1.5:
						good = true
		if not good:
			misplaced += 1
	ok(misplaced == 0, "seed %d %d chests not where they claim" % [sd, misplaced])
	var guards: Array = m.guards
	ok(guards.size() >= 8 and guards.size() <= 14, "seed %d %d guard posts" % [sd, guards.size()])
	var landmarks: Array = m.landmarks
	ok(landmarks.size() >= 4, "seed %d %d landmarks" % [sd, landmarks.size()])
	# ---- physics: the map in the world
	var node := a.instantiate(true)
	root.add_child(node)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	# patrol legs: a knee-high sphere swept along each leg meets nothing
	var blocked_legs := 0
	var sh := SphereShape3D.new()
	sh.radius = 0.35
	for gd in guards:
		var pts: Array = gd.patrol
		ok(pts.size() >= 3 and pts.size() <= 5, "seed %d patrol has %d points" % [sd, pts.size()])
		for i in pts.size():
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[(i + 1) % pts.size()]
			if not _leg_clear(space, sh, m, p0, p1):
				blocked_legs += 1
				print("  seed %d guard %d (%s) leg %d blocked near %s" % [sd, int(gd.building), buildings[int(gd.building)].kind, i, _last_hit])
		# the post itself must be reachable from the loop
		if not _leg_clear(space, sh, m, gd.pos, pts[0]):
			blocked_legs += 1
	ok(blocked_legs == 0, "seed %d %d patrol legs blocked" % [sd, blocked_legs])
	# spawns hidden from every window
	var seen := 0
	var windows := 0
	for b in buildings:
		for w in b.get("windows", []):
			windows += 1
			var wp: Vector3 = w.pos
			var wn: Vector3 = w.n
			for k in 8:
				var eye: Vector3 = (a.markers["spawn_a%d" % k] as Transform3D).origin + Vector3(0, 1.7, 0)
				var q := PhysicsRayQueryParameters3D.create(wp + wn * 0.4, eye, 1)
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					seen += 1
					print("  seed %d window of %s at %s sees spawn %d" % [sd, b.kind, wp.snapped(Vector3.ONE), k])
	ok(seen == 0, "seed %d %d window->spawn sight lines open (%d windows)" % [sd, seen, windows])
	# landmarks from a 15 x 15 eye-height sample
	var tall := []
	for lm in landmarks:
		if not lm.get("low", false):
			tall.append(lm)
	ok(tall.size() >= 4, "seed %d %d tall landmarks" % [sd, tall.size()])
	var cover := []
	for lm in tall:
		var top: Vector3 = lm.get("top", (lm.pos as Vector3) + Vector3(0, 10, 0))
		var vis := 0
		for i in 15:
			for j in 15:
				var x := lerpf(float(pa[0]) + 8.0, float(pa[2]) - 8.0, i / 14.0)
				var z := lerpf(float(pa[1]) + 8.0, float(pa[3]) - 8.0, j / 14.0)
				var eye := Vector3(x, GKExtractForest.height_at(m, x, z) + 1.7, z)
				var q := PhysicsRayQueryParameters3D.create(eye, top, 1)
				var hit := space.intersect_ray(q)
				if hit.is_empty() or (hit.position as Vector3).distance_to(top) < 4.0:
					vis += 1
		cover.append([str(lm.name), vis / 225.0])
	var best := 0.0
	var good_lm := 0
	for cv in cover:
		best = maxf(best, float(cv[1]))
		if float(cv[1]) >= 0.5:
			good_lm += 1
	ok(best >= 0.5, "seed %d best landmark seen from %.0f%% of the sample" % [sd, best * 100.0])
	ok(good_lm >= 4, "seed %d only %d landmarks seen from >= 50%%: %s" % [sd, good_lm, cover])
	# determinism
	var again := d.build({ "seed": sd })
	ok(_hash(again) == _hash(a), "seed %d rebuild differs" % sd)
	node.free()
	await physics_frame
	var pos := []
	for b in buildings:
		pos.append((b.aabb as AABB).get_center().snapped(Vector3.ONE))
	if first_positions.is_empty():
		first_positions = pos
	else:
		ok(pos != first_positions, "seed %d has the same buildings as seed %d" % [sd, SEEDS[0]])
	var lm_txt := ""
	for cv in cover:
		lm_txt += "%s %.0f%% " % [cv[0], float(cv[1]) * 100.0]
	print("seed %d: %d ms, %d tris, %d parts, %d colliders; %d buildings (%s), %d chests (tiers %s), %d guards, %d roads, %d cars, %d bushes; hills %.1f m; landmarks: %s" % [
		sd, ms, tris, a.parts.size(), a.colliders.size(), buildings.size(), sites, chests.size(), tiers, guards.size(), (m.roads as Array).size(), cars.size(), hide.size(), h_hi - h_lo, lm_txt])


var _last_hit := Vector3.ZERO


func _leg_clear(space: PhysicsDirectSpaceState3D, sh: SphereShape3D, m: Dictionary, a: Vector3, b: Vector3) -> bool:
	var n := maxi(int(a.distance_to(b) / 0.6), 1)
	for k in n + 1:
		var p := a.lerp(b, k / float(n))
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.collision_mask = 1
		q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, GKExtractForest.height_at(m, p.x, p.z) + 0.9, p.z))
		if not space.intersect_shape(q, 1).is_empty():
			_last_hit = q.transform.origin.snapped(Vector3.ONE * 0.1)
			return false
	return true


static func _hash(a: GKAsset) -> int:
	var h := 0
	for p in a.parts:
		var mm: ArrayMesh = p.mesh
		for s in mm.get_surface_count():
			var v: PackedVector3Array = mm.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			h = hash([h, mm.surface_get_name(s), v.size(), v[0] if v.size() > 0 else Vector3.ZERO, v[v.size() / 2] if v.size() > 0 else Vector3.ZERO])
	return h
