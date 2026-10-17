extends SceneTree
## Windowed: review frames of the extract shooter's map (GKExtractForest),
## saved to design/shots/extract/map/<TAG>_s<SEED>_<scene>.png. Same seed,
## same cameras, every run, so gauntlet rounds compare like for like. Exit 0.
##   [SEED=7] [TAG=r1] godot --path . --script res://tools/extract_map_shots.gd
## Scenes: 0_plan (no haze), 0b_aerial (the campus photo's low oblique),
## 1_spawn_k (beside three spawn pockets, looking in: what you see once you
## step out), 2_hilltop_* (from the chapel's / water tower's door, and back
## at it from down its road), 3_inside (the most broken building, looking
## out of the door), 4_road_landmark, 5_lake, 6_junction (the door most roads
## meet at), 7_valley (a valley lot from the slope above), 8_forest_mid
## (half way in from a spawn, deep woods), 9_poi_* (each mid-forest point of
## interest from 14 m, when meta.pois lists them).

const W := 1600
const H := 900

var out := ""
var tag := ""
var sd := 7
var cam: Camera3D
var asset: GKAsset


func _initialize() -> void:
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/extract/map").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	tag = OS.get_environment("TAG")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(W, H))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var fn := (tag + "_" if tag != "" else "") + "s%d_" % sd + name + ".png"
	img.save_png(out.path_join(fn))
	print("shot ", fn)


func _eye(from: Vector3, to: Vector3, fov := 75.0) -> void:
	cam.fov = fov
	cam.global_transform = Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP), from)


func _ground(x: float, z: float) -> float:
	return GKExtractForest.height_at(asset.meta, x, z)


func _at_eye(p: Vector3, up := 1.7) -> Vector3:
	return Vector3(p.x, _ground(p.x, p.z) + up, p.z)


## A camera spot with nothing solid within 1.6 m and a clear line to `look`
## (hits within 5 m of it don't count): procedural eye cameras land in trees.
func _clear(eye: Vector3, look: Vector3) -> bool:
	var space := root.get_world_3d().direct_space_state
	var sh := SphereShape3D.new()
	sh.radius = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, eye + Vector3(0, 1.0, 0))
	q.collision_mask = 1
	var hits := space.intersect_shape(q, 4)
	for h in hits:
		# the terrain counts as clear (it's under us)
		if h.collider is StaticBody3D and (h.shape as int) == 0:
			continue
		return false
	var r := PhysicsRayQueryParameters3D.create(eye, look, 1)
	var hit := space.intersect_ray(r)
	return hit.is_empty() or (hit.position as Vector3).distance_to(look) < 5.0


func _trunks(at: Vector3, r: float) -> int:
	var sh := SphereShape3D.new()
	sh.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 1.0, 0))
	q.collision_mask = 1
	return root.get_world_3d().direct_space_state.intersect_shape(q, 64).size()


## The best clear spot round `c` at `dists`, preferring high ground.
func _spot(c: Vector3, look: Vector3, dists: Array, half: float, prefer_high := true) -> Vector3:
	var best := Vector3.INF
	var bs := -1e9
	for dd in dists:
		for k in 16:
			var an := k * TAU / 16.0
			var q := c + Vector3(cos(an), 0, sin(an)) * float(dd)
			if absf(q.x) > half - 5.0 or absf(q.z) > half - 5.0:
				continue
			var eye := _at_eye(q)
			var sc := eye.y if prefer_high else -float(dd)
			if sc > bs and _clear(eye, look):
				bs = sc
				best = eye
	return best


func _go() -> void:
	if OS.get_environment("SEED") != "":
		sd = int(OS.get_environment("SEED"))
	var t0 := Time.get_ticks_msec()
	asset = GKRegistry.build("extract_forest", { "seed": sd })
	print("extract_forest seed %d: %d tris, %d parts, %d ms" % [sd, asset.triangle_count(), asset.parts.size(), Time.get_ticks_msec() - t0])
	var stage := GKStage.outdoor(asset.lights)
	root.add_child(stage)
	var env: Environment = (stage.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	var fog := env.fog_density
	root.add_child(asset.instantiate(true))
	cam = Camera3D.new()
	cam.far = 1500.0
	root.add_child(cam)
	cam.make_current()
	await process_frame
	await physics_frame
	await physics_frame
	var m := asset.meta
	var buildings: Array = m.buildings
	var landmarks: Array = m.landmarks
	var mast: Vector3 = m.mast
	var roads: Array = m.roads
	var pa: Array = m.play_area
	var half := float(pa[2])
	# the plan view
	var rc: Transform3D = asset.marker("ref_cam")
	cam.fov = float(m.get("ref_cam_fov", 60.0))
	cam.global_transform = rc
	env.fog_density = 0.0                      # the plan is a map: no haze
	await _shot("0_plan")
	# straight down, orthographic: the layout as a map
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = half * 2.0 + 20.0
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, 200, 0))
	await _shot("0c_top")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	env.fog_density = fog
	# the campus photo's camera: low and oblique from a corner, over the woods
	var corner := Vector3(-half * 0.95, 0, half * 0.95)
	_eye(Vector3(corner.x, _ground(corner.x, corner.z) + 55.0, corner.z), Vector3(half * 0.15, _ground(0, 0), -half * 0.15), 60.0)
	await _shot("0b_aerial")
	# three spawns: stand beside the pocket (just out of it), looking in
	for k in [0, 3, 5]:
		var t: Transform3D = asset.marker("spawn_a%d" % k)
		var inward := -Vector3(t.origin.x, 0, t.origin.z).normalized()
		var side := Vector3(-inward.z, 0, inward.x) * (1.0 if k % 2 == 0 else -1.0)
		var eye := _at_eye(t.origin + side * 11.0 + inward * 3.5)        # past the pocket's hedge return
		var tgt := eye + inward * 30.0 + Vector3(0, 0.6, 0)
		var bd := 1e9
		for lm in landmarks:
			if lm.get("low", false):
				continue
			var lp: Vector3 = lm.top
			var dd := Vector2(lp.x - eye.x, lp.z - eye.z).length()
			if dd < bd:
				bd = dd
				tgt = Vector3(lp.x, eye.y + minf((lp.y - eye.y) * 0.5, dd * 0.12), lp.z)
		_eye(eye, tgt)
		await _shot("1_spawn_%d" % k)
	# the two hilltops: the chapel's and the water tower's doorsteps, looking across
	var hills := []
	for b in buildings:
		if b.kind in ["chapel", "watertower"]:
			hills.append(b)
	for b in hills:
		var c: Vector3 = (b.aabb as AABB).get_center()
		var g := _ground(c.x, c.z)
		var post := c
		for q in m.guards:
			if int(q.building) == int(b.id):
				post = q.pos
		_eye(post + Vector3(0, 1.7, 0), Vector3(0, _ground(0, 0) + 6.0, 0))
		await _shot("2_hilltop_%s" % str(b.kind))
		# and back at the building from 25 m down its road
		var back := post
		var bd := 1e9
		for rd in roads:
			var pts: Array = rd
			for end in [0, pts.size() - 1]:
				var d := (pts[end] as Vector3).distance_to(post)
				if d < bd and pts.size() > 9:
					bd = d
					back = pts[8] if end == 0 else pts[pts.size() - 9]
		_eye(back + Vector3(0, 1.7, 0), Vector3(c.x, g + 7.0, c.z))
		await _shot("2_hilltop_%s_building" % str(b.kind))
	# inside the most broken building, from a front corner looking out of the door
	var ruin: Dictionary = {}
	for b in buildings:
		if ruin.is_empty() or (b.kind == "ruin" and ruin.kind != "ruin") or (ruin.kind != "ruin" and float(b.disrepair) > float(ruin.disrepair)):
			ruin = b
	if not ruin.is_empty():
		var c: Vector3 = (ruin.aabb as AABB).get_center()
		var door: Vector3 = c + Vector3(0, 0, 8)
		for q in m.guards:
			if int(q.building) == int(ruin.id):
				door = q.pos
		var fwd := Vector3(door.x - c.x, 0, door.z - c.z).normalized()
		var side := Vector3(-fwd.z, 0, fwd.x)
		var inside := c + fwd * 1.3 + side * 2.2
		_eye(_at_eye(inside, 1.6), _at_eye(door + fwd * 6.0 - side * 2.0, 1.4))
		await _shot("3_inside_%s" % str(ruin.kind))
	# a road toward a landmark: the longest road, from a third along toward the best-lined-up landmark
	var best: Array = []
	for rd in roads:
		if (rd as Array).size() > best.size():
			best = rd
	if best.size() > 4:
		var i := best.size() / 3
		var p0: Vector3 = best[i]
		var p1: Vector3 = best[i + 2]
		var fwd := (p1 - p0).normalized()
		var target := mast
		var bd := 1e9
		for lm in landmarks:
			if lm.get("low", false):
				continue
			var lp: Vector3 = lm.pos
			var d := absf(Vector2(lp.x - p0.x, lp.z - p0.z).angle_to(Vector2(fwd.x, fwd.z)))
			if d < bd:
				bd = d
				target = lm.top
		var td := Vector2(target.x - p0.x, target.z - p0.z).length()
		_eye(p0 + Vector3(0, 1.7, 0), Vector3(target.x, p0.y + 1.7 + clampf((target.y - p0.y) * 0.5, 0.0, td * 0.2), target.z))
		await _shot("4_road_landmark")
	# the lake
	var lake: Dictionary = m.get("lake", {})
	if not lake.is_empty():
		var lc: Vector3 = lake.center
		var look := lc + Vector3(-10.0, 1.0, -10.0)
		var from := _spot(lc, look, [30.0, 36.0], half, false)
		if from == Vector3.INF:
			from = _at_eye(lc + Vector3(28.0, 0, 20.0))
		_eye(from, look)
		await _shot("5_lake")
	# the junction: the road end most roads share, from 14 m down one of them
	var ends := {}
	for rd in roads:
		var pts: Array = rd
		for e in [0, pts.size() - 1]:
			var key: Vector3 = (pts[e] as Vector3).snapped(Vector3.ONE * 2.0)
			ends[key] = ends.get(key, []) + [[rd, e]]
	var jk: Vector3 = Vector3.ZERO
	var jn := 0
	for key in ends:
		if (ends[key] as Array).size() > jn:
			jn = (ends[key] as Array).size()
			jk = key
	if jn > 0:
		var pick: Array = ends[jk][0]
		var pts: Array = pick[0]
		var e: int = pick[1]
		var from_i := mini(5, pts.size() - 1) if e == 0 else maxi(pts.size() - 6, 0)
		var jp: Vector3 = pts[e]
		_eye((pts[from_i] as Vector3) + Vector3(0, 1.7, 0), jp + Vector3(0, 2.5, 0))
		await _shot("6_junction")
	# a valley lot from the slope above it
	var vb: Dictionary = {}
	for b in buildings:
		if str(b.get("site", "")) == "valley" and (vb.is_empty() or b.kind in ["house", "lodge"]):
			vb = b
	if not vb.is_empty():
		var c: Vector3 = (vb.aabb as AABB).get_center()
		var look := Vector3(c.x, _ground(c.x, c.z) + 2.5, c.z)
		var top := _spot(c, look, [26.0, 32.0, 38.0], half)
		if top == Vector3.INF:
			top = _at_eye(c + Vector3(30, 0, 0))
		_eye(top, look)
		await _shot("7_valley")
	# deep woods: half way from spawn 2 to the centre
	var s2: Transform3D = asset.marker("spawn_a2")
	var dirc := -Vector3(s2.origin.x, 0, s2.origin.z).normalized()
	var mid := s2.origin * 0.55
	var most := -1
	for f: float in [0.75, 0.68, 0.61, 0.55, 0.48, 0.41]:
		var q := _at_eye(s2.origin * f)
		var n := _trunks(q, 12.0)
		if n > most and _clear(q, q + dirc * 8.0):
			most = n
			mid = s2.origin * f
	_eye(_at_eye(mid), _at_eye(mid + dirc * 30.0, 2.4))
	await _shot("8_forest_mid")
	# the points of interest
	var pois: Array = m.get("pois", [])
	var seen := {}
	for poi in pois:
		var kind := str(poi.kind)
		if seen.has(kind):
			continue
		seen[kind] = true
		var pp: Vector3 = poi.pos
		var to_c := -Vector3(pp.x, 0, pp.z).normalized()
		if to_c.length() < 0.5:
			to_c = Vector3(0, 0, 1)
		var look := pp + Vector3(0, float(poi.get("look_h", 2.0)), 0)
		var from := _spot(pp, look, [12.0, 16.0, 20.0], half, false)
		if from == Vector3.INF:
			from = _at_eye(pp + to_c * 14.0)
		_eye(from, look)
		await _shot("9_poi_%s" % kind)
	quit(0)
