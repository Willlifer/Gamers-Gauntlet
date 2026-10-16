class_name GKRooftop
extends GKDef
## Apartment-rooftop shooter field after the aerial photo
## (design/ref/kit/rooftop.png): two six-storey apartment blocks side by side
## across a parking court, flat dark membrane roofs behind light metal-capped
## parapets, clusters of round exhaust fans and stair bulkheads for cover, the
## top floor in dark grey siding over beige stucco, balconies, and around them
## streets, parked cars, trees, lawns and two taller towers.
## Play: the two roofs (spawn_a* on the left block, spawn_b* on the right),
## fenced by invisible walls at the parapets (GKAsset.BARRIER_LAYER: they stop
## bodies, not bullets, so you can shoot across). `bridge` adds a scaffold
## walk across the gap, ramped up from each roof (a gameplay addition the
## photo doesn't have).
## G51c (the author's round-2 notes): fair. The west block's playable part
## is the east block mirrored (its roof kit, cover and spawns too; the rest
## of it is a taller annex, out of play); more cover (duct runs, a water
## tank, a skylight row); and `interior`: the top storey under each roof is
## open, down a ramped stairwell from the roof, with pillars, partitions and
## crates inside. meta.stairs lists each stairwell's top and bottom, so the
## bot (no pathfinding) can take it as a two-point route.
## Real metres, +y up, the camera side is +z; scaled by `scale`.

func id() -> String:
	return "rooftop"


func title() -> String:
	return "Apartment rooftops"


func kind() -> String:
	return "env"


func version() -> int:
	return 2


func schema() -> Array[Dictionary]:
	return [
		pf("scale", "Scale", "Fit", 1.25, 0.8, 1.6, 0.01),
		pi("floors", "Storeys", "Layout", 6, 3, 9),
		pf("gap", "Court between blocks (m)", "Layout", 18.0, 6.0, 30.0, 0.5),
		pb("bridge", "Scaffold walk across the gap", "Layout", true),
		pb("interior", "Top storey open, stairwell down (G51c)", "Layout", true),
		pi("fans", "Fan clusters per roof", "Cover", 5, 0, 10),
		pi("hvac", "HVAC units per roof", "Cover", 4, 0, 8),
		pi("seed", "Dressing seed", "Cover", 5, 0, 999),
		pb("city", "Streets, cars, towers", "Dressing", true),
		pf("sun_yaw", "Sun direction (deg)", "Light", -52.0, -180.0, 180.0, 1.0),
		pf("sun_height", "Sun height (deg)", "Light", 48.0, 15.0, 85.0, 1.0),
	]


func presets() -> Dictionary:
	return {
		"Reference": {},
		"Reference only": { "bridge": false },
		"Close quarters": { "gap": 7.0, "fans": 7, "hvac": 6 },
		"Low rise": { "floors": 4 },
		"Evening": { "sun_yaw": -100.0, "sun_height": 16.0 },
	}


const STOREY := 3.1
const PARAPET := 1.1


func _build(p: Dictionary) -> GKAsset:
	var a := GKAsset.new()
	var s: float = p.scale
	var g := GKMesh.new()
	var M := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	g.push(M)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.seed)
	var floors: int = p.floors
	var H := floors * STOREY + 0.6
	var gap: float = p.gap
	# block B (east) is the field's unit; block A's playable part is B
	# mirrored across the court (G51c: fair to both spawns), and the rest of
	# A is a taller annex to the west, out of play (the photo's bigger block)
	var ax1 := -gap * 0.5
	var bx0 := gap * 0.5
	var b_rects := [Rect2(bx0, -20.0, 40.0, 28.0)]
	var a_rects := [Rect2(-bx0 - 40.0, -20.0, 40.0, 28.0)]
	var annex := [Rect2(-bx0 - 58.0, -38.0, 18.0, 46.0)]
	var MIR := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	var interior: bool = p.interior
	var hole := Rect2(bx0 + 16.0, -2.6, 8.0, 2.6)            # the stairwell (east-block coords)
	for side in ["b", "a"]:
		if side == "a":
			g.push(MIR)
		var krng := RandomNumberGenerator.new()               # the same dressing on both roofs
		krng.seed = int(p.seed)
		_block(g, a, b_rects, H, floors, krng, interior, hole)
		_roof_kit(g, a, b_rects, H, krng, int(p.fans), int(p.hvac), Vector3(bx0 + 8.0, H, -13.0), false, hole if interior else Rect2())
		if interior:
			_stairwell(g, a, hole, H)
			_interior(g, a, b_rects[0], H, hole)
		if side == "a":
			g.pop()
	_block(g, a, annex, H + STOREY, floors + 1, rng)
	if p.bridge:
		_bridge(g, a, ax1, bx0, H, 1.0)
	if p.city:
		_city(g, rng, ax1, bx0, H)
	else:
		GKArch.block(g, a, "asphalt_lot", Vector3(-140, -0.3, -140), Vector3(140, 0.0, 80))
	g.pop()
	a.add_part("world", g.commit())
	# barriers: a 3 m fence above every playable parapet, open where the bridge lands
	var gaps := [] if not p.bridge else [1.0 - 1.1, 1.0 + 1.1]
	for side in ["b", "a"]:
		_fence(a, b_rects[0], H, M * (MIR if side == "a" else Transform3D.IDENTITY), b_rects, gaps)
	if p.bridge:
		GKArch.barrier(a, Vector3(ax1, H, 1.0 - 1.3), Vector3(bx0, H + 3.5, 1.0 - 1.2), M)
		GKArch.barrier(a, Vector3(ax1, H, 1.0 + 1.2), Vector3(bx0, H + 3.5, 1.0 + 1.3), M)
	# markers
	var look := func(from: Vector3, to: Vector3) -> Transform3D:
		return Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP), M * from)
	a.markers = {
		# the photo: a drone over the street corner south-east of block B, looking across both roofs
		"ref_cam": look.call(Vector3(bx0 + 24.0, H + 48.0, 52.0), Vector3(-14.0, H - 8.0, -12.0)),
		# eye level from each roof's front outer corner (clusters keep 5 m off the edges)
		"eye_a": look.call(Vector3(-bx0 - 38.5, H + 1.72, 6.0), Vector3(bx0 + 20.0, H + 1.0, -6.0)),
		"eye_b": look.call(Vector3(bx0 + 38.5, H + 1.72, 6.0), Vector3(-bx0 - 20.0, H + 1.0, -6.0)),
	}
	for k in 3:
		a.markers["spawn_a%d" % k] = Transform3D(Basis(Vector3.UP, -PI * 0.5), M * Vector3(-bx0 - 34.0, H, -12.0 + k * 3.0))
		a.markers["spawn_b%d" % k] = Transform3D(Basis(Vector3.UP, PI * 0.5), M * Vector3(bx0 + 34.0, H, -12.0 + k * 3.0))
	if interior:
		a.markers["floor_a"] = Transform3D(Basis.IDENTITY, M * Vector3(-bx0 - 30.0, H - STOREY, -10.0))
		a.markers["floor_b"] = Transform3D(Basis.IDENTITY, M * Vector3(bx0 + 30.0, H - STOREY, -10.0))
	var roofs := { "a": [], "b": [] }
	for side in ["a", "b"]:
		for r in (a_rects if side == "a" else b_rects):
			var rr: Rect2 = r
			(roofs[side] as Array).append([rr.position.x * s, rr.position.y * s, rr.end.x * s, rr.end.y * s])
	# the stairwells for the bot: walk to `top` on the roof, then to `bottom` inside
	var stairs := []
	if interior:
		for side in ["b", "a"]:
			var sx := 1.0 if side == "b" else -1.0
			var cz := hole.get_center().y
			stairs.append({ "side": side, "top": M * Vector3(sx * (hole.position.x - 1.2), H, cz), "bottom": M * Vector3(sx * (hole.end.x + 1.5), H - STOREY, cz) })
	a.meta = { "roofs": roofs, "ref_cam_fov": 46.0, "eye_a_fov": 70.0, "eye_b_fov": 70.0, "roof_height": H * s,
		"floor_height": (H - STOREY) * s, "stairs": stairs, "bot_hunt": true,
		"notes": "Two mirrored roofs; spawn_a* west, spawn_b* east; the scaffold walk joins them when `bridge` is on; with `interior` a stairwell on each roof leads down to the open top storey." }
	var yaw := deg_to_rad(float(p.sun_yaw))
	var el := deg_to_rad(float(p.sun_height))
	var to_sun := Vector3(sin(yaw) * cos(el), sin(el), cos(yaw) * cos(el))
	a.lights = { "sun_dir": [-to_sun.x, -to_sun.y, -to_sun.z], "sun_col": "#ffefd6", "sun_energy": 1.7, "shadow_bias": 0.03,
		"sky_top": "#6a98cc", "sky_horizon": "#e4e8e6", "ground": "#7a7a68", "ambient": 0.85,
		"ambient_col": "#b8b4a8", "sky_share": 0.45, "exposure": 1.0, "fog_col": "#dfe4e4", "fog_density": 0.0011,
		"saturation": 1.0, "contrast": 1.08, "shadow_dist": 180.0 * s }
	return a


func _fence(a: GKAsset, r: Rect2, H: float, M: Transform3D, all: Array, gap_z := []) -> void:
	# one wall per side, skipping where it would cut another rect of the same roof
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var y0 := H + PARAPET
	var y1 := H + 4.0
	var sides := [[Vector3(x0, y0, z0 - 0.2), Vector3(x1, y1, z0)], [Vector3(x0, y0, z1), Vector3(x1, y1, z1 + 0.2)],
		[Vector3(x0 - 0.2, y0, z0), Vector3(x0, y1, z1)], [Vector3(x1, y0, z0), Vector3(x1 + 0.2, y1, z1)]]
	for sd in sides:
		var lo: Vector3 = sd[0]
		var hi: Vector3 = sd[1]
		var c := (lo + hi) * 0.5
		var inside_other := false
		for o in all:
			var orr: Rect2 = o
			if orr != r and orr.grow(0.3).has_point(Vector2(c.x, c.z)):
				inside_other = true
		if inside_other:
			continue
		# the court-side wall opens where the bridge lands
		if not gap_z.is_empty() and absf(lo.x - (x0 - 0.2)) < 0.01 and absf(hi.x - x0) < 0.01:
			GKArch.barrier(a, lo, Vector3(hi.x, hi.y, float(gap_z[0])), M)
			GKArch.barrier(a, Vector3(lo.x, lo.y, float(gap_z[1])), hi, M)
			continue
		GKArch.barrier(a, lo, hi, M)


## One building: stucco mass, the grey siding top floor, a plinth, windows
## on a grid with some balcony bays, parapets with coping, the roof slab.
func _block(g: GKMesh, a: GKAsset, rects: Array, H: float, floors: int, rng: RandomNumberGenerator, hollow := false, hole := Rect2()) -> void:
	for r in rects:
		var rr: Rect2 = r
		var lo := Vector3(rr.position.x, 0, rr.position.y)
		var hi := Vector3(rr.end.x, H, rr.end.y)
		if hollow:
			_hollow_top(g, a, rr, H, hole)
		else:
			GKArch.block(g, a, "stucco_beige", lo, hi)
		# the top storey clad in dark siding, a hair proud of the stucco
		g.box("siding_grey", Vector3((lo.x + hi.x) * 0.5, H - STOREY * 0.5 - 0.15, (lo.z + hi.z) * 0.5), Vector3(rr.size.x + 0.12, STOREY + 0.3, rr.size.y + 0.12))
		# a band at each floor line, darker plinth at the foot
		g.box("stucco_beige:#b9a888", Vector3((lo.x + hi.x) * 0.5, 0.6, (lo.z + hi.z) * 0.5), Vector3(rr.size.x + 0.1, 1.2, rr.size.y + 0.1))
		g.box("concrete_light", Vector3((lo.x + hi.x) * 0.5, STOREY + 0.6, (lo.z + hi.z) * 0.5), Vector3(rr.size.x + 0.16, 0.18, rr.size.y + 0.16))
		# roof slab top (the walkable surface) and parapets
		for piece in _around(rr.grow(-0.05), hole if hollow else Rect2()):
			var pc: Rect2 = piece
			g.box("roof_membrane", Vector3(pc.get_center().x, H + 0.02, pc.get_center().y), Vector3(pc.size.x, 0.04, pc.size.y))
		_parapets(g, a, rr, H, rects)
		# windows on every outward face, avoiding faces shared with another rect
		var faces := [[Vector3(0, 0, 1), Vector3(lo.x, 0, hi.z), Vector3(hi.x, 0, hi.z)],
			[Vector3(0, 0, -1), Vector3(hi.x, 0, lo.z), Vector3(lo.x, 0, lo.z)],
			[Vector3(-1, 0, 0), Vector3(lo.x, 0, lo.z), Vector3(lo.x, 0, hi.z)],
			[Vector3(1, 0, 0), Vector3(hi.x, 0, hi.z), Vector3(hi.x, 0, lo.z)]]
		for f in faces:
			_facade(g, f[0], f[1], f[2], floors, rects, rr, rng)


func _parapets(g: GKMesh, a: GKAsset, r: Rect2, H: float, all: Array) -> void:
	var t := 0.3
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var segs := [[Vector3(x0, H, z0), Vector3(x1, H + PARAPET, z0 + t)], [Vector3(x0, H, z1 - t), Vector3(x1, H + PARAPET, z1)],
		[Vector3(x0, H, z0), Vector3(x0 + t, H + PARAPET, z1)], [Vector3(x1 - t, H, z0), Vector3(x1, H + PARAPET, z1)]]
	for sd in segs:
		var lo: Vector3 = sd[0]
		var hi: Vector3 = sd[1]
		# trim the parts that run inside a neighbouring rect of the same roof
		var pieces := _clip_outside(lo, hi, all, r)
		for pc in pieces:
			var plo: Vector3 = pc[0]
			var phi: Vector3 = pc[1]
			GKArch.block(g, a, "siding_grey", plo, phi)
			g.box("parapet_cap", Vector3((plo.x + phi.x) * 0.5, H + PARAPET + 0.04, (plo.z + phi.z) * 0.5), (phi - plo).abs() * Vector3(1, 0, 1) + Vector3(0.12, 0.08, 0.12), 0.01)


## The parts of a wall run [lo, hi] (along x or z) that lie outside every
## other rect of the same roof.
func _clip_outside(lo: Vector3, hi: Vector3, all: Array, own: Rect2) -> Array:
	var along_x := (hi.x - lo.x) > (hi.z - lo.z)
	var spans := [[lo.x if along_x else lo.z, hi.x if along_x else hi.z]]
	var mid := (lo.z + hi.z) * 0.5 if along_x else (lo.x + hi.x) * 0.5
	for o in all:
		var orr: Rect2 = o
		if orr == own:
			continue
		var cross_lo := orr.position.y if along_x else orr.position.x
		var cross_hi := orr.end.y if along_x else orr.end.x
		if mid <= cross_lo + 0.01 or mid >= cross_hi - 0.01:
			# touching edge counts as inside when the wall lies on the shared line
			if absf(mid - cross_lo) > 0.4 and absf(mid - cross_hi) > 0.4:
				continue
		var cut_lo := orr.position.x if along_x else orr.position.y
		var cut_hi := orr.end.x if along_x else orr.end.y
		var next := []
		for sp in spans:
			var s0: float = sp[0]
			var s1: float = sp[1]
			if cut_hi <= s0 or cut_lo >= s1:
				next.append([s0, s1])
				continue
			if cut_lo > s0:
				next.append([s0, cut_lo])
			if cut_hi < s1:
				next.append([cut_hi, s1])
		spans = next
	var out := []
	for sp in spans:
		if float(sp[1]) - float(sp[0]) < 0.05:
			continue
		if along_x:
			out.append([Vector3(sp[0], lo.y, lo.z), Vector3(sp[1], hi.y, hi.z)])
		else:
			out.append([Vector3(lo.x, lo.y, sp[0]), Vector3(hi.x, hi.y, sp[1])])
	return out


## Windows along one face, bay by bay, floor by floor; every few bays a
## recessed balcony stack; the ground floor gets a door near the middle.
func _facade(g: GKMesh, n: Vector3, from: Vector3, to: Vector3, floors: int, all: Array, own: Rect2, _rng: RandomNumberGenerator) -> void:
	var run := to - from
	var ln := run.length()
	var dir := run / ln
	var bay := 3.4
	var count := int(ln / bay)
	var pad := (ln - count * bay) * 0.5
	for i in count:
		var c := from + dir * (pad + bay * (i + 0.5))
		# skip bays that face into a neighbouring rect
		var probe := c + n * 0.6
		var blocked := false
		for o in all:
			var orr: Rect2 = o
			if orr != own and orr.has_point(Vector2(probe.x, probe.z)):
				blocked = true
		if blocked:
			continue
		var bay_proj := (i % 6 == 1) and i + 1 < count and ln > 24.0
		var bay_tail := (i % 6 == 2) and ln > 24.0
		if bay_proj:
			_bay(g, c + dir * bay * 0.5, n, dir, bay * 2.0, floors)
			continue
		if bay_tail:
			continue
		var balcony := (i % 6 == 4) and ln > 20.0
		for f in floors:
			var y := f * STOREY + 1.0 + (0.6 if f == 0 else 0.0)
			var top_floor := f == floors - 1
			if balcony and f > 0:
				_balcony(g, c + Vector3(0, f * STOREY + 0.6, 0), n, dir, top_floor)
				continue
			if f == 0 and i == count / 2:
				GKArch.door(g, c + Vector3(0, 0.0, 0), n, 1.8, 2.5, "window_dark", true, "concrete_light")
				continue
			var tall := 1.55 if not top_floor else 1.35
			GKArch.window(g, c + Vector3(0, y + tall * 0.5, 0), n, 1.25, tall, { "frame": "window_frame", "out": 0.06 if top_floor else 0.0,
				"sill_role": "concrete_light" if not top_floor else "parapet_cap", "mullion": true })


## A projecting bay two window-bays wide, clad in dark siding from the first
## floor to the parapet, its own windows on the front and the returns.
func _bay(g: GKMesh, c: Vector3, n: Vector3, dir: Vector3, w: float, floors: int) -> void:
	var proj := 0.9
	var H := floors * STOREY + 0.6
	var y0 := STOREY + 0.5
	var center := c + n * (proj * 0.5) + Vector3(0, (y0 + H + PARAPET) * 0.5, 0)
	var size := dir.abs() * (w - 0.2) + n.abs() * proj + Vector3(0, H + PARAPET - y0, 0)
	g.box("siding_grey", center, size)
	g.box("parapet_cap", center + Vector3(0, (H + PARAPET - y0) * 0.5 + 0.04, 0), size * Vector3(1, 0, 1) + Vector3(0.12, 0.08, 0.12), 0.01)
	g.box("concrete_light", c + n * (proj * 0.5) + Vector3(0, y0 - 0.1, 0), dir.abs() * (w - 0.1) + n.abs() * (proj + 0.1) + Vector3(0, 0.2, 0))
	for f in range(1, floors):
		var y := f * STOREY + 1.0 + 0.775
		for k in [-1.0, 1.0]:
			GKArch.window(g, c + n * proj + dir * (k * w * 0.24) + Vector3(0, y, 0), n, 1.2, 1.5, { "depth": 0.1, "frame": "window_frame",
				"sill_role": "parapet_cap", "mullion": true })


func _balcony(g: GKMesh, base: Vector3, n: Vector3, _dir: Vector3, top: bool) -> void:
	var b := GKArch.face_basis(n)
	g.push(Transform3D(b, base))
	# a glass door on the face, a slab projecting 1.2 m, its railing, side screens
	g.box("window_dark", Vector3(0, 1.15, 0.01), Vector3(2.2, 2.2, 0.02))
	g.box("iron_dark", Vector3(0, 1.15, 0.025), Vector3(0.05, 2.2, 0.03))
	g.box("siding_grey", Vector3(0, -0.06, 0.6), Vector3(3.0, 0.16, 1.2))
	g.box("siding_grey" if top else "stucco_beige:#c9b58f", Vector3(-1.45, 1.2, 0.6), Vector3(0.1, 2.4, 1.2))
	g.box("iron_dark", Vector3(0, 0.95, 1.18), Vector3(2.8, 0.05, 0.05))
	var x := -1.33
	while x <= 1.35:
		g.box("iron_dark", Vector3(x, 0.48, 1.18), Vector3(0.025, 0.95, 0.025))
		x += 0.12
	g.pop()


## Roof dressing: a stair bulkhead with a door, an elevator overrun, a hatch,
## and clusters of mushroom exhaust fans: the cover.
func _roof_kit(g: GKMesh, a: GKAsset, rects: Array, H: float, rng: RandomNumberGenerator, clusters: int, units: int, stair_at: Vector3, left: bool, hole := Rect2()) -> void:
	var main: Rect2 = rects[0]
	_extra_cover(g, a, main, H)
	# stair bulkhead
	var sb := Vector3(4.6, 3.2, 3.6)
	GKArch.block(g, a, "siding_grey", stair_at - Vector3(sb.x * 0.5, 0, sb.z * 0.5), stair_at + Vector3(sb.x * 0.5, sb.y, sb.z * 0.5))
	g.box("parapet_cap", stair_at + Vector3(0, sb.y + 0.06, 0), Vector3(sb.x + 0.2, 0.12, sb.z + 0.2), 0.01)
	GKArch.door(g, stair_at + Vector3(0, 0, sb.z * 0.5), Vector3.BACK, 1.0, 2.2, "hvac_dark", false, "parapet_cap")
	# elevator overrun beside it
	var eo := stair_at + Vector3(-5.5 if left else -5.0, 0, -1.0 if left else -4.0)
	GKArch.block(g, a, "siding_grey", eo - Vector3(1.6, 0, 1.6), eo + Vector3(1.6, 2.4, 1.6))
	g.box("parapet_cap", eo + Vector3(0, 2.46, 0), Vector3(3.4, 0.12, 3.4), 0.01)
	# roof hatch, red-orange as in the photo
	var hx := main.position.x + main.size.x * (0.62 if left else 0.7)
	var hz := main.position.y + main.size.y * 0.25
	g.box("sign_red:#b84a2c", Vector3(hx, H + 0.3, hz), Vector3(1.6, 0.6, 1.0), 0.03)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(hx, H + 0.3, hz)), Vector3(1.6, 0.6, 1.0))
	# fan clusters on a loose grid over all the roof rects
	var placed: Array[Vector2] = [Vector2(stair_at.x, stair_at.z), Vector2(eo.x, eo.z)]
	# keep clear of the stairwell, the bridge landing and the G51c cover
	# (these keep 4.5 m off; clusters keep 9 m apart from each other)
	var keep_off: Array[Vector2] = []
	if hole.has_area():
		for t in 5:
			keep_off.append(Vector2(lerpf(hole.position.x - 2.0, hole.end.x, t / 4.0), hole.get_center().y))
	for q: Vector2 in EXTRA_SPOTS:
		keep_off.append(Vector2(main.position.x, main.position.y) + q)
	for t in 4:                                   # the bridge landing and the walk off it
		keep_off.append(Vector2(main.position.x + 1.0 + t * 2.5, 1.0))
	for k in 3:                                   # the spawns (spawn_b*: 34 m in, 8-14 m down)
		keep_off.append(Vector2(main.position.x + 34.0, main.position.y + 8.0 + k * 3.0))
	var tries := 0
	var made := 0
	while made < clusters and tries < 200:
		tries += 1
		var r: Rect2 = rects[rng.randi() % rects.size()]
		var c := Vector2(rng.randf_range(r.position.x + 5.0, r.end.x - 5.0), rng.randf_range(r.position.y + 4.0, r.end.y - 4.0))
		if tries == 1 and not left:
			c = Vector2(stair_at.x + 11.0, stair_at.z - 3.5)             # the photo's big cluster past the bulkhead
		var ok := true
		for q in placed:
			if q.distance_to(c) < 9.0:
				ok = false
		for q in keep_off:
			if q.distance_to(c) < 4.5:
				ok = false
		if not ok:
			continue
		placed.append(c)
		made += 1
		# a tight clump of 6-12 fans about a metre apart, packed round a point
		var n := 12 if (tries == 1 and not left) else rng.randi_range(6, 12)
		var fans: Array[Vector2] = [c]
		_fan(g, a, Vector3(c.x, H, c.y), rng.randf_range(1.05, 1.2))
		var guard := 0
		while fans.size() < n and guard < 200:
			guard += 1
			var from: Vector2 = fans[rng.randi() % fans.size()]
			var an := rng.randf() * TAU
			var fp := from + Vector2(cos(an), sin(an)) * 1.2
			var clear := true
			for q in fans:
				if q.distance_to(fp) < 1.15:
					clear = false
			if clear:
				fans.append(fp)
				_fan(g, a, Vector3(fp.x, H, fp.y), rng.randf_range(1.0, 1.18))
	# HVAC units: chest-high boxes with a fan grille on top, mid-height cover
	var made_u := 0
	tries = 0
	while made_u < units and tries < 200:
		tries += 1
		var r: Rect2 = rects[rng.randi() % rects.size()]
		var c := Vector2(rng.randf_range(r.position.x + 4.0, r.end.x - 4.0), rng.randf_range(r.position.y + 3.5, r.end.y - 3.5))
		var ok := true
		for q in placed + keep_off:
			if q.distance_to(c) < (6.0 if q in placed else 4.0):
				ok = false
		if not ok:
			continue
		placed.append(c)
		made_u += 1
		var yaw := PI * 0.5 * rng.randi_range(0, 1)
		_hvac(g, a, Vector3(c.x, H, c.y), yaw)


func _hvac(g: GKMesh, a: GKAsset, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	g.push(Transform3D(b, at))
	g.box("hvac_dark", Vector3(0, 0.12, 0), Vector3(2.6, 0.24, 1.6), 0.02)                   # the curb
	g.box("hvac_metal", Vector3(0, 0.82, 0), Vector3(2.4, 1.16, 1.4), 0.04)
	g.cyl("hvac_dark", Vector3(0.55, 1.4, 0), Vector3(0.55, 1.44, 0), 0.5, 18)               # fan grille
	g.cyl("iron_dark", Vector3(0.55, 1.44, 0), Vector3(0.55, 1.46, 0), 0.12, 10)
	for k in 6:
		g.box("hvac_dark", Vector3(-0.55, 0.45 + k * 0.13, -0.705), Vector3(1.0, 0.035, 0.012))   # louvres
	g.cyl("iron_dark", Vector3(1.2, 0.5, 0.4), Vector3(2.2, 0.08, 0.4), 0.06, 8)             # a conduit to the roof
	g.pop()
	a.add_box_xf(g.xf * Transform3D(b, at + Vector3(0, 0.75, 0)), Vector3(2.6, 1.5, 1.6))


func _fan(g: GKMesh, a: GKAsset, at: Vector3, k: float) -> void:
	# curb, a short drum, the domed hood with its gap where the air leaves
	g.box("hvac_dark", at + Vector3(0, 0.2 * k, 0), Vector3(0.9, 0.4, 0.9) * k, 0.03)
	g.lathe("fan_metal", at + Vector3(0, 0.4 * k, 0), at + Vector3(0, 1.15 * k, 0), [
		Vector2(0.0, 0.3 * k), Vector2(0.14 * k, 0.3 * k), Vector2(0.16 * k, 0.24 * k), Vector2(0.22 * k, 0.24 * k),
		Vector2(0.24 * k, 0.56 * k), Vector2(0.3 * k, 0.55 * k), Vector2(0.38 * k, 0.42 * k), Vector2(0.44 * k, 0.18 * k), Vector2(0.47 * k, 0.0)], 18)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.55 * k, 0)), Vector3(0.95, 1.1, 0.95) * k)


## G51c cover on every roof, in the roof's own frame (x from its court-side
## edge, z from its north edge): two duct runs (waist high), a water tank on
## its stand (full cover), a skylight row (crouch cover).
const EXTRA_SPOTS := [Vector2(16.0, 4.0), Vector2(30.0, 23.0), Vector2(33.0, 5.5), Vector2(28.0, 13.0)]


func _extra_cover(g: GKMesh, a: GKAsset, r: Rect2, H: float) -> void:
	var o := Vector3(r.position.x, H, r.position.y)
	# duct runs: galvanised boxes on little legs
	for d in [[Vector3(16.0, 0, 4.0), Vector3(6.5, 0.9, 0.8)], [Vector3(30.0, 0, 23.0), Vector3(0.8, 0.9, 6.0)]]:
		var c: Vector3 = o + (d[0] as Vector3)
		var sz: Vector3 = d[1]
		g.box("hvac_metal", c + Vector3(0, 0.15 + sz.y * 0.5, 0), sz, 0.03)
		for sx in [-0.45, 0.45]:
			g.box("iron_dark", c + Vector3(sz.x * sx, 0.075, sz.z * sx), Vector3(0.1, 0.15, 0.1))
		a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, c + Vector3(0, (0.15 + sz.y) * 0.5, 0)), Vector3(sz.x, 0.15 + sz.y, sz.z))
	# the water tank: a drum on a steel stand
	var t := o + Vector3(33.0, 0, 5.5)
	for sx in [-0.9, 0.9]:
		for sz in [-0.9, 0.9]:
			g.box("iron_dark", t + Vector3(sx, 0.35, sz), Vector3(0.12, 0.7, 0.12))
	g.box("iron_dark", t + Vector3(0, 0.72, 0), Vector3(2.1, 0.08, 2.1))
	g.lathe("hvac_metal", t + Vector3(0, 0.76, 0), t + Vector3(0, 3.3, 0), [Vector2(0.0, 1.25), Vector2(0.95, 1.25), Vector2(1.0, 0.9), Vector2(1.08, 0.0)], 20)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, t + Vector3(0, 1.65, 0)), Vector3(2.4, 3.3, 2.4))
	# a skylight row: low glazed humps
	var sk := o + Vector3(28.0, 0, 13.0)
	for k in 3:
		var c := sk + Vector3((k - 1) * 1.9, 0, 0)
		g.box("concrete_light", c + Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 1.4), 0.02)
		g.box("window_dark", c + Vector3(0, 0.55, 0), Vector3(1.4, 0.3, 1.2), 0.08)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, sk + Vector3(0, 0.38, 0)), Vector3(5.4, 0.76, 1.4))


## The top storey made hollow (G51c): the building solid up to the top floor,
## then four walls, a floor and a roof slab cut round the stairwell.
func _hollow_top(g: GKMesh, a: GKAsset, r: Rect2, H: float, hole: Rect2) -> void:
	var y0 := H - STOREY
	var lo := Vector3(r.position.x, 0, r.position.y)
	var hi := Vector3(r.end.x, H, r.end.y)
	GKArch.block(g, a, "stucco_beige", lo, Vector3(hi.x, y0, hi.z))
	g.box("concrete_light:#8f8c86", Vector3(r.get_center().x, y0 + 0.01, r.get_center().y), Vector3(r.size.x - 0.6, 0.02, r.size.y - 0.6))
	var t := 0.3
	for w in [[Vector3(lo.x, y0, lo.z), Vector3(hi.x, H - 0.3, lo.z + t)], [Vector3(lo.x, y0, hi.z - t), Vector3(hi.x, H - 0.3, hi.z)],
			[Vector3(lo.x, y0, lo.z), Vector3(lo.x + t, H - 0.3, hi.z)], [Vector3(hi.x - t, y0, lo.z), Vector3(hi.x, H - 0.3, hi.z)]]:
		GKArch.block(g, a, "stucco_beige:#cfc6b6", w[0], w[1])
	for piece in _around(r, hole):
		var pc: Rect2 = piece
		GKArch.block(g, a, "concrete_light", Vector3(pc.position.x, H - 0.3, pc.position.y), Vector3(pc.end.x, H, pc.end.y))


## `r` minus the rect `cut` (inside it), as up to four rects.
static func _around(r: Rect2, cut: Rect2) -> Array:
	if not cut.has_area() or not r.intersects(cut):
		return [r]
	var c := r.intersection(cut)
	var out := []
	if c.position.y > r.position.y:
		out.append(Rect2(r.position.x, r.position.y, r.size.x, c.position.y - r.position.y))
	if c.end.y < r.end.y:
		out.append(Rect2(r.position.x, c.end.y, r.size.x, r.end.y - c.end.y))
	if c.position.x > r.position.x:
		out.append(Rect2(r.position.x, c.position.y, c.position.x - r.position.x, c.size.y))
	if c.end.x < r.end.x:
		out.append(Rect2(c.end.x, c.position.y, r.end.x - c.end.x, c.size.y))
	return out


## The stairwell: a ramp from the roof at the hole's court-side end down to
## the top floor at its far end, railed along the open sides (the rails
## stop bodies, not bullets).
func _stairwell(g: GKMesh, a: GKAsset, hole: Rect2, H: float) -> void:
	var y0 := H - STOREY
	var run := hole.size.x
	var ang := atan2(STOREY, run)
	var ln := sqrt(run * run + STOREY * STOREY)
	var c := Vector3(hole.get_center().x, (H + y0) * 0.5 - 0.08, hole.get_center().y)
	var b := Basis(Vector3.BACK, -ang)
	g.box("concrete_light", c, Vector3(ln, 0.16, hole.size.y - 0.1), 0.0, b)
	a.add_box_xf(g.xf * Transform3D(b, c), Vector3(ln, 0.16, hole.size.y - 0.1))
	# treads: dark strips across the ramp
	for k in 12:
		var f := (k + 0.5) / 12.0
		g.box("hvac_dark", Vector3(hole.position.x + run * f, H - STOREY * f + 0.005, c.z), Vector3(0.06, 0.02, hole.size.y - 0.2), 0.0)
	# rails round the hole on the roof: both long sides and the far end
	for z in [hole.position.y, hole.end.y]:
		_rail(g, a, Vector3(hole.position.x, H, z), Vector3(hole.end.x, H, z))
	_rail(g, a, Vector3(hole.end.x, H, hole.position.y), Vector3(hole.end.x, H, hole.end.y))


func _rail(g: GKMesh, a: GKAsset, p0: Vector3, p1: Vector3) -> void:
	var d := p1 - p0
	var n := maxi(1, int(d.length() / 1.6))
	for k in n + 1:
		var q := p0 + d * (float(k) / n)
		g.cyl("steel", q, q + Vector3(0, 1.0, 0), 0.025, 6)
	for hy in [0.5, 1.0]:
		g.cyl("steel", p0 + Vector3(0, hy, 0), p1 + Vector3(0, hy, 0), 0.025, 6)
	var lo := Vector3(minf(p0.x, p1.x) - 0.05, p0.y, minf(p0.z, p1.z) - 0.05)
	var hi := Vector3(maxf(p0.x, p1.x) + 0.05, p0.y + 1.05, maxf(p0.z, p1.z) + 0.05)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, (lo + hi) * 0.5), hi - lo, true)


## Inside the top storey: a grid of pillars, partition walls with gaps,
## crate stacks and desks, so a fight indoors has corners. In the roof's
## own frame (x from the court-side edge, z from the north edge).
func _interior(g: GKMesh, a: GKAsset, r: Rect2, H: float, _hole: Rect2) -> void:
	var y0 := H - STOREY
	var o := Vector3(r.position.x, y0, r.position.y)
	var top := STOREY - 0.3
	for px in [8.0, 16.0, 24.0, 32.0]:
		for pz in [7.0, 21.0]:
			GKArch.block(g, a, "concrete_light", o + Vector3(px - 0.3, 0, pz - 0.3), o + Vector3(px + 0.3, top, pz + 0.3))
	# partitions (2.6 m, 0.2 thick), each with a way round
	for w in [[Vector3(19.0, 0, 13.0), Vector3(25.0, 0, 13.2)], [Vector3(13.0, 0, 3.0), Vector3(13.2, 0, 9.0)],
			[Vector3(29.0, 0, 17.0), Vector3(35.0, 0, 17.2)], [Vector3(35.0, 0, 5.0), Vector3(35.2, 0, 11.0)],
			[Vector3(4.0, 0, 13.0), Vector3(9.0, 0, 13.2)]]:
		GKArch.block(g, a, "plaster_white:#ddd6c8", o + (w[0] as Vector3), o + (w[1] as Vector3) + Vector3(0, 2.6, 0))
	# crates and desks (crouch cover)
	for c in [[Vector3(6.0, 0, 5.0), Vector3(1.4, 1.1, 1.4)], [Vector3(28.0, 0, 8.0), Vector3(2.4, 0.8, 1.2)], [Vector3(18.0, 0, 23.0), Vector3(1.4, 1.1, 1.4)],
			[Vector3(31.0, 0, 24.0), Vector3(2.4, 0.8, 1.2)], [Vector3(10.0, 0, 21.0), Vector3(1.2, 1.4, 1.2)], [Vector3(37.0, 0, 15.0), Vector3(1.2, 1.1, 2.0)]]:
		var p: Vector3 = o + (c[0] as Vector3)
		var sz: Vector3 = c[1]
		GKArch.block(g, a, "wood_old" if sz.y > 1.0 else "hvac_metal", p - Vector3(sz.x * 0.5, 0, sz.z * 0.5), p + Vector3(sz.x * 0.5, sz.y, sz.z * 0.5), 0.02)


## A scaffold walkway across the gap: deck of boards on tube frames, rails.
func _bridge(g: GKMesh, a: GKAsset, x0: float, x1: float, H: float, z: float) -> void:
	var y := H + PARAPET + 0.02
	var w := 2.2
	GKArch.block(g, a, "hvac_metal", Vector3(x0 - 0.5, y, z - w * 0.5), Vector3(x1 + 0.5, y + 0.06, z + w * 0.5))
	var gx := x0 - 0.4
	while gx < x1 + 0.45:
		g.box("hvac_dark", Vector3(gx, y + 0.062, z), Vector3(0.03, 0.004, w - 0.1))      # grating bars
		gx += 0.12
	# ramps up from each roof over the parapet to the deck (G51c: walkable)
	for side in [-1.0, 1.0]:
		var edge := x0 - 0.5 if side < 0.0 else x1 + 0.5          # the deck's end, over the parapet
		var run := 3.8
		var rise := y + 0.06 - H
		var ln := sqrt(run * run + rise * rise)
		var c := Vector3(edge + side * run * 0.5, H + rise * 0.5 - 0.05, z)
		var b := Basis(Vector3.BACK, -side * atan2(rise, run))
		g.box("hvac_metal", c, Vector3(ln, 0.1, w), 0.0, b)
		a.add_box_xf(g.xf * Transform3D(b, c), Vector3(ln, 0.1, w))
		for k in 8:
			var f := (k + 0.5) / 8.0
			g.box("hvac_dark", Vector3(edge + side * run * f, y + 0.06 - rise * f + 0.01, z), Vector3(0.05, 0.02, w - 0.1))
	var k := 0
	var xx := x0 - 0.5
	while xx <= x1 + 0.5:
		for sz in [-1.0, 1.0]:
			g.cyl("steel", Vector3(xx, y, z + sz * w * 0.5), Vector3(xx, y + 1.05, z + sz * w * 0.5), 0.024, 6)
		g.cyl("steel", Vector3(xx, y - 0.02, z - w * 0.5), Vector3(xx, y - 0.02, z + w * 0.5), 0.024, 6)
		xx += 2.0
		k += 1
	for sz in [-1.0, 1.0]:
		for hy in [0.55, 1.05]:
			g.cyl("steel", Vector3(x0 - 0.5, y + hy, z + sz * w * 0.5), Vector3(x1 + 0.5, y + hy, z + sz * w * 0.5), 0.024, 6)
	# the under-truss
	g.cyl("steel", Vector3(x0, y - 0.05, z - w * 0.5), Vector3((x0 + x1) * 0.5, y - 1.2, z - w * 0.5), 0.03, 6)
	g.cyl("steel", Vector3(x1, y - 0.05, z - w * 0.5), Vector3((x0 + x1) * 0.5, y - 1.2, z - w * 0.5), 0.03, 6)
	g.cyl("steel", Vector3(x0, y - 0.05, z + w * 0.5), Vector3((x0 + x1) * 0.5, y - 1.2, z + w * 0.5), 0.03, 6)
	g.cyl("steel", Vector3(x1, y - 0.05, z + w * 0.5), Vector3((x0 + x1) * 0.5, y - 1.2, z + w * 0.5), 0.03, 6)


## Around the blocks: streets, sidewalks, the parking court, lawns, trees,
## parked cars, and two towers behind (scenery: no collision).
func _city(g: GKMesh, rng: RandomNumberGenerator, ax1: float, bx0: float, _h: float) -> void:
	# ground: lots everywhere, lawns, then streets on top
	g.box("grass", Vector3(0, -0.2, -40.0), Vector3(1400, 0.3, 1400))                  # out to the horizon
	g.box("asphalt_lot", Vector3(-10.0, -0.12, -14.0), Vector3(150, 0.3, 64))
	g.box("grass", Vector3(95.0, 0.02, -70.0), Vector3(70.0, 0.04, 60.0))
	g.box("grass", Vector3(-30.0, 0.02, -75.0), Vector3(50.0, 0.04, 40.0))
	g.box("grass", Vector3(-110.0, 0.02, -40.0), Vector3(50.0, 0.04, 80.0))
	g.box("asphalt", Vector3(0, 0.03, 24.0), Vector3(320, 0.04, 14.0))                  # the front street
	g.box("asphalt", Vector3(bx0 + 58.0, 0.03, -40.0), Vector3(14.0, 0.04, 140.0))       # the side street
	g.box("concrete_light", Vector3(0, 0.08, 15.5), Vector3(320, 0.12, 3.0))             # sidewalks
	g.box("concrete_light", Vector3(0, 0.08, 32.5), Vector3(320, 0.12, 3.0))
	g.box("concrete_light", Vector3(bx0 + 49.5, 0.08, -40.0), Vector3(3.0, 0.12, 140.0))
	g.box("grass", Vector3(0, 0.05, 12.0), Vector3(320, 0.06, 4.0))                     # verge
	for x in range(-150, 150, 12):
		g.box("sign_white", Vector3(float(x), 0.06, 24.0), Vector3(3.0, 0.01, 0.15))      # centre line
	# the parking court between the blocks and behind
	g.box("asphalt_lot", Vector3((ax1 + bx0) * 0.5, 0.04, -12.0), Vector3(bx0 - ax1, 0.04, 42.0))
	var x := -150.0
	while x < 150.0:
		if x < ax1 - 60.0 or x > bx0 + 50.0 or rng.randf() < 0.5:
			_tree(g, Vector3(x + rng.randf_range(-1.5, 1.5), 0, 12.0 + rng.randf_range(-0.6, 0.6)), rng.randf_range(0.9, 1.3), rng)
		x += rng.randf_range(9.0, 14.0)
	for k in 16:
		_tree(g, Vector3(rng.randf_range(70.0, 130.0), 0, rng.randf_range(-100.0, -40.0)), rng.randf_range(1.0, 1.5), rng)
	for k in 10:
		_tree(g, Vector3(rng.randf_range(-130.0, -90.0), 0, rng.randf_range(-80.0, 0.0)), rng.randf_range(1.0, 1.5), rng)
	# parked cars: along the front kerb, in the court
	var paints := ["#2a2d33", "#9a1c22", "#e8e8ea", "#1d3f8a", "#5a5d62", "#151515"]
	x = -140.0
	while x < 140.0:
		if rng.randf() < 0.35:
			_car(g, Vector3(x, 0, 19.0), 0.0, str(paints[rng.randi() % paints.size()]))
		x += 6.5
	# the court: two rows of painted stalls behind block A's wing, half full
	var cx0 := ax1 - 24.0
	var row_x := [cx0 + 6.0, bx0 - 6.0]
	for rx in row_x:
		for k in 12:
			var sz := -36.0 + k * 2.7
			g.box("sign_white", Vector3(float(rx), 0.06, sz), Vector3(5.0, 0.01, 0.1))
			if rng.randf() < 0.55:
				_car(g, Vector3(float(rx), 0, sz + 1.35), 0.0, str(paints[rng.randi() % paints.size()]))
	# a light pole in the middle
	g.cyl("iron_dark", Vector3((cx0 + bx0) * 0.5, 0, -22.0), Vector3((cx0 + bx0) * 0.5, 7.5, -22.0), 0.09, 8)
	g.box("hvac_dark", Vector3((cx0 + bx0) * 0.5, 7.5, -22.0), Vector3(0.8, 0.15, 0.4))
	g.box("grass", Vector3(-20.0, 0.03, 3.0), Vector3(30.0, 0.04, 5.0))                  # front lawns
	g.box("grass", Vector3(bx0 + 20.0, 0.03, 11.0), Vector3(36.0, 0.04, 2.6))
	for k in 8:
		_tree(g, Vector3(rng.randf_range(ax1 - 50.0, bx0 + 40.0), 0, rng.randf_range(9.5, 11.0)), rng.randf_range(0.7, 0.9), rng)
	# the newer block across the side street (bottom right of the photo)
	var cb := Rect2(bx0 + 66.0, -10.0, 26.0, 22.0)
	g.box("brick_red", Vector3(cb.get_center().x, 2.0, cb.get_center().y), Vector3(cb.size.x, 4.0, cb.size.y))
	g.box("siding_light", Vector3(cb.get_center().x, 4.0 + 7.5, cb.get_center().y), Vector3(cb.size.x, 15.0, cb.size.y))
	g.box("siding_grey", Vector3(cb.position.x + 4.0, 4.0 + 7.6, cb.get_center().y), Vector3(8.2, 15.4, cb.size.y + 0.4))
	g.box("roof_membrane", Vector3(cb.get_center().x, 19.05, cb.get_center().y), Vector3(cb.size.x, 0.1, cb.size.y))
	for f in 5:
		for i in 7:
			g.box("window_dark", Vector3(cb.position.x - 0.03, 5.6 + f * 3.0, cb.position.y + 2.0 + i * 3.0), Vector3(0.04, 1.5, 1.5))
	# towers behind
	# behind: a back street, lots and clumps of trees
	g.box("asphalt", Vector3(0, 0.03, -56.0), Vector3(320, 0.04, 12.0))
	g.box("asphalt_lot", Vector3(40.0, 0.03, -80.0), Vector3(50, 0.04, 30.0))
	g.box("asphalt_lot", Vector3(-70.0, 0.03, -76.0), Vector3(40, 0.04, 26.0))
	for k in 14:
		_tree(g, Vector3(rng.randf_range(-140.0, 140.0), 0, rng.randf_range(-64.0, -60.0)), rng.randf_range(0.9, 1.3), rng)
	_tower(g, Rect2(-14.0, -112.0, 36.0, 22.0), 14)
	_tower(g, Rect2(-120.0, -100.0, 26.0, 26.0), 12)


func _tree(g: GKMesh, at: Vector3, k: float, rng: RandomNumberGenerator) -> void:
	g.cyl("wood_pole", at, at + Vector3(0, 2.6 * k, 0), 0.16 * k, 6)
	for i in 3:
		var off := Vector3(rng.randf_range(-0.8, 0.8), 3.2 + i * 0.9, rng.randf_range(-0.8, 0.8)) * k
		g.sphere("foliage", at + off, rng.randf_range(1.5, 2.1) * k, 10, Vector3(1.0, 0.85, 1.0))


func _car(g: GKMesh, at: Vector3, yaw: float, paint: String) -> void:
	g.push(Transform3D(Basis(Vector3.UP, yaw), at))
	var role := "car_paint:" + paint
	g.box(role, Vector3(0, 0.62, 0), Vector3(4.4, 0.7, 1.8), 0.18)
	g.box(role, Vector3(-0.2, 1.17, 0), Vector3(2.4, 0.5, 1.6), 0.15)
	g.box("window_dark", Vector3(-0.2, 1.2, 0), Vector3(2.3, 0.4, 1.63), 0.1)
	for wx in [-1.4, 1.4]:
		for wz in [-0.82, 0.82]:
			g.cyl("tyre", Vector3(wx, 0.34, wz - 0.1), Vector3(wx, 0.34, wz + 0.1), 0.34, 10)
	g.pop()


func _tower(g: GKMesh, r: Rect2, floors: int) -> void:
	var H := floors * STOREY
	var lo := Vector3(r.position.x, 0, r.position.y)
	var hi := Vector3(r.end.x, H, r.end.y)
	g.box("stucco_beige:#d9cbb0", (lo + hi) * 0.5, hi - lo)
	g.box("parapet_cap", Vector3((lo.x + hi.x) * 0.5, H + 0.6, (lo.z + hi.z) * 0.5), Vector3(r.size.x * 0.4, 1.2, r.size.y * 0.4))
	# the facade facing the camera: a grid of windows and balcony slots
	var n := Vector3.BACK
	var bays := int(r.size.x / 3.0)
	for f in floors:
		for i in bays:
			var c := Vector3(lo.x + (i + 0.5) * r.size.x / bays, f * STOREY + 1.6, hi.z)
			g.box("window_dark" if (i % 4) != 1 else "siding_grey", c + n * 0.02, Vector3(1.4 if (i % 4) != 1 else 2.2, 1.5, 0.04))
	var bays_z := int(r.size.y / 3.0)
	for f in floors:
		for i in bays_z:
			var c := Vector3(hi.x, f * STOREY + 1.6, lo.z + (i + 0.5) * r.size.y / bays_z)
			g.box("window_dark", c + Vector3.RIGHT * 0.02, Vector3(0.04, 1.5, 1.4))
			var c2 := Vector3(lo.x, f * STOREY + 1.6, lo.z + (i + 0.5) * r.size.y / bays_z)
			g.box("window_dark", c2 - Vector3.RIGHT * 0.02, Vector3(0.04, 1.5, 1.4))
