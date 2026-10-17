class_name GKForestLots
extends RefCounted
## Building and prop builders for the forest campus (GKExtractForest): the
## campus's dressing (gg_campus.py: brick halls, plaster houses, the stone
## chapel and tower, trees, bushes, lamps, benches, cars) ported to GKMesh
## roles, plus the extract shooter's own kinds (lodge, barn + silo, water
## tower, radio mast, ruin) and disrepair: missing roof panels, knocked-out
## wall bays with rubble, darker tints. Every building is enterable: a door
## opening, a floor slab, walls as collision boxes, a roof over it.
## All builders work in the current GKMesh frame (push the lot's placement
## first); collision goes through g.xf so it follows the frame.
##
## building(g, a, spec) -> { aabb, windows: [{pos, n}], door, spots: [{pos,
## deep}], patrol: [Vector3 x4], top: Vector3, h: float }, all in world space.
## spec: { kind, pos: Vector3 (floor centre, pad height), yaw, disrepair, rng }

const WALL_T := 0.3
const DOOR_W := 1.7
const DOOR_H := 2.4

const FOLIAGE := ["foliage", "foliage", "foliage:#3d6a25", "foliage:#6f8c2c", "foliage:#2f4f22", "foliage_gold", "foliage_autumn", "foliage_red"]
const BUSH_ROLES := ["hedge", "hedge", "foliage", "foliage:#557a2c", "foliage_red", "foliage_autumn", "foliage_gold:#b9a23a"]
const PAINTS := ["#2a2d33", "#9a1c22", "#e8e8ea", "#1d3f8a", "#5a5d62", "#151515", "#6a7a4a", "#c8a040"]


# ----------------------------------------------------------------- buildings

## Footprint half extents, wall height and roles per kind.
static func plan(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	match kind:
		"hall":
			return { "hx": 8.0 + rng.randf_range(-1.0, 1.5), "hz": 4.6 + rng.randf_range(-0.4, 0.6), "h": 6.6, "wall": "brick_hall",
				"roof": "roof_slate", "rise": 3.0, "rows": 2, "trim": "stone_grey:#cdc8bb", "floor": "concrete_light:#9a968c" }
		"house":
			return { "hx": 4.6 + rng.randf_range(-0.4, 0.8), "hz": 3.6 + rng.randf_range(-0.3, 0.5), "h": 3.3,
				"wall": ["plaster_white", "brick_tan", "plaster_white:#e8e2d4", "brick_hall"][rng.randi() % 4],
				"roof": ["roof_slate", "roof_slate:#4a4e55", "roof_slate:#6a5a4e"][rng.randi() % 3], "rise": 2.2, "rows": 1,
				"trim": "stone_grey:#cdc8bb", "floor": "wood_old:#8a7458" }
		"lodge":
			return { "hx": 6.0 + rng.randf_range(-0.5, 0.8), "hz": 4.2 + rng.randf_range(-0.3, 0.4), "h": 3.5, "wall": "wood_old:#6a5238",
				"roof": "roof_slate:#4a4e55", "rise": 2.6, "rows": 1, "trim": "wood_old:#3b2a1e", "floor": "wood_old:#8a7458" }
		"chapel":
			return { "hx": 5.0, "hz": 9.0, "h": 7.2, "wall": "stone_grey:#aa9f8a", "roof": "roof_slate", "rise": 4.4, "rows": 1,
				"trim": "stone_grey:#c9bea6", "floor": "stone_grey:#8f877a" }
		"barn":
			return { "hx": 7.0 + rng.randf_range(-0.5, 0.8), "hz": 4.8, "h": 5.2, "wall": "wood_old:#8a3426", "roof": "roof_slate:#3a3e44",
				"rise": 3.4, "rows": 1, "trim": "wood_old:#2a1e14", "floor": "concrete:#8d8678" }
		"watertower":
			return { "hx": 2.2, "hz": 2.2, "h": 2.7, "wall": "concrete_light", "roof": "roof_membrane", "rise": 0.5, "rows": 1,
				"trim": "concrete", "floor": "concrete:#8d8678" }
		_:   # ruin
			return { "hx": 5.0 + rng.randf_range(-0.5, 1.0), "hz": 3.8, "h": 3.4, "wall": "brick_ruin", "roof": "", "rise": 0.0,
				"rows": 1, "trim": "stone_grey:#9a948a", "floor": "concrete:#8d8678" }


static func building(g: GKMesh, a: GKAsset, spec: Dictionary) -> Dictionary:
	var kind: String = spec.kind
	var rng: RandomNumberGenerator = spec.rng
	var d: float = clampf(float(spec.disrepair), 0.0, 1.0)
	if kind == "ruin":
		d = 1.0
	var p: Dictionary = spec.plan if spec.has("plan") else plan(kind, rng)
	var hx: float = p.hx
	var hz: float = p.hz
	var H: float = p.h
	var pos: Vector3 = spec.pos
	var yaw: float = spec.yaw
	g.push(Transform3D(Basis(Vector3.UP, yaw), pos))
	var out := { "windows": [], "spots": [], "kind": kind }
	var dark := Color.WHITE.darkened(0.42 * d)
	# the floor slab and the pad round it
	g.tint = dark
	GKArch.block(g, a, str(p.floor), Vector3(-hx, -0.3, -hz), Vector3(hx, 0.1, hz))
	g.tint = Color.WHITE.darkened(0.2 * d)
	g.box("path_concrete:#b8b3a6", Vector3(0, -0.2, hz + 1.4), Vector3(4.0, 0.5, 2.8))     # the doorstep
	g.tint = dark
	# walls: four faces, the door on +z; bays knocked out by disrepair
	var faces := [[Vector3(0, 0, 1), hz, hx], [Vector3(0, 0, -1), hz, hx], [Vector3(1, 0, 0), hx, hz], [Vector3(-1, 0, 0), hx, hz]]
	var fi := 0
	for f in faces:
		var n: Vector3 = f[0]
		var off: float = f[1]
		var half: float = f[2]
		_face(g, a, out, p, n, off, half, H, fi == 0, d, rng, kind, dark)
		fi += 1
	# the roof
	if kind == "ruin":
		pass
	elif kind == "house" and d < 0.5:
		_hip(g, p, hx, hz, H, dark)
	elif kind == "watertower":
		g.box(str(p.roof), Vector3(0, H + 0.08, 0), Vector3(hx * 2.0 + 0.4, 0.16, hz * 2.0 + 0.4))
	else:
		_gable(g, p, hx, hz, H, d, rng, dark, kind)
	# inside: a partition with a gap, the chest spots, rubble
	var deep_z := -hz + 1.4
	if hz >= 3.4 and kind != "watertower":
		var gap_x := rng.randf_range(-hx * 0.5, hx * 0.5)
		var ph := minf(H, 2.8)
		g.tint = dark.lightened(0.1)
		var prole := "plaster_white:#ddd6c8" if kind in ["hall", "house"] else str(p.wall)
		GKArch.block(g, a, prole, Vector3(-hx + WALL_T, 0.1, -0.1), Vector3(gap_x - 0.7, ph, 0.1))
		GKArch.block(g, a, prole, Vector3(gap_x + 0.7, 0.1, -0.1), Vector3(hx - WALL_T, ph, 0.1))
		g.tint = dark
	for sx: float in [-1.0, 1.0]:
		out.spots.append({ "pos": g.xf * Vector3(sx * (hx - 1.3), 0.1, deep_z), "deep": true })
		out.spots.append({ "pos": g.xf * Vector3(sx * (hx - 1.3), 0.1, hz - 1.5), "deep": false })
	if hz >= 3.4:
		out.spots.append({ "pos": g.xf * Vector3(0.0, 0.1, -hz * 0.5), "deep": true })
	var rub := int(round(d * 4.0))
	for k in rub:
		_rubble(g, a, Vector3(rng.randf_range(-hx + 1.0, hx - 1.0), 0.1, rng.randf_range(-hz + 1.0, hz - 1.0)), str(p.wall), rng, 0.3 + 0.3 * d)
	g.tint = dark
	# kind extras
	match kind:
		"hall":
			for sx: float in [-1.0, 1.0]:
				g.box("brick_hall", Vector3(sx * (hx - 1.6), H + p.rise * 0.6, 0.0), Vector3(0.9, p.rise * 1.1, 0.6))   # chimneys
			_lamp_wall(g, Vector3(2.2, 3.2, hz), Vector3(0, 0, 1))
		"house":
			g.box(str(p.wall), Vector3(hx * 0.5, H + p.rise * 0.55, -hz * 0.3), Vector3(0.6, p.rise * 1.0, 0.6))
		"lodge":
			_porch(g, a, hx, hz, H, dark)
		"chapel":
			out["top"] = _tower(g, a, hx, hz, H, dark, rng, d)
		"barn":
			out["top"] = _silo(g, a, hx, hz, dark)
		"watertower":
			out["top"] = _tank(g, a, hx, hz, dark)
		"ruin":
			for k in 5:
				_rubble(g, a, Vector3(rng.randf_range(-hx - 2.0, hx + 2.0), 0.0, rng.randf_range(-hz - 2.0, hz + 2.0)), str(p.wall), rng, 0.6)
			# inside: fallen joists from the lost roof, a floor of debris and ash
			for k in 3 + rng.randi() % 3:
				var jx := rng.randf_range(-hx + 1.0, hx - 1.0)
				var jz := rng.randf_range(-hz + 0.8, hz - 0.8)
				var jb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.1, 0.5))
				g.tint = Color.WHITE.darkened(rng.randf_range(0.3, 0.6))
				g.box("wood_old:#4a3828", Vector3(jx, 0.35, jz), Vector3(0.22, 0.22, rng.randf_range(2.4, 4.0)), 0.0, jb)
			g.tint = Color.WHITE
			for k in 4:
				g.box("asphalt:#2e2a26", Vector3(rng.randf_range(-hx + 1.0, hx - 1.0), 0.115, rng.randf_range(-hz + 1.0, hz - 1.0)), Vector3(rng.randf_range(1.2, 2.6), 0.02, rng.randf_range(1.0, 2.2)), 0.0, Basis(Vector3.UP, rng.randf() * TAU))
			for k in 10:
				_rubble(g, null, Vector3(rng.randf_range(-hx + 0.6, hx - 0.6), 0.1, rng.randf_range(-hz + 0.6, hz - 0.6)), str(p.wall), rng, 0.35)
	g.tint = Color.WHITE
	var world_xf := g.xf
	g.pop()
	# world-space results
	var top_h: float = H + float(p.rise) + 0.5
	if not out.has("top"):
		out["top"] = world_xf * Vector3(0, top_h, 0)
	var corners: Array[Vector3] = []
	for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
		corners.append(world_xf * (c as Vector3))
	var aabb := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		aabb = aabb.expand(c)
	var tp: Vector3 = out.top
	out["aabb"] = aabb.expand(tp).grow(0.4)
	out["door"] = world_xf * Vector3(0, 0, hz + 3.0)
	out["front"] = (world_xf.basis * Vector3(0, 0, 1)).normalized()
	out["half"] = Vector2(hx, hz)
	# the guard's loop: 4 m off the walls, wider past the tower / silo side (+x)
	var patrol: Array = []
	var mx := 4.0 + (5.5 if kind in ["chapel", "barn"] else 0.0)
	var start := 3                                      # the +z/-x corner, nearest the door's left
	for k in 4:
		var c: Vector3 = [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)][(start + k) % 4]
		patrol.append(world_xf * (c + Vector3(signf(c.x) * (mx if c.x > 0.0 else 4.0), 0.0, signf(c.z) * 4.0)))
	out["patrol_margin"] = Vector2(mx, 4.0)
	out["patrol"] = patrol
	out["h"] = H
	return out


## One wall face: solid spans, the door (front), knocked-out bays by
## disrepair (a 0.5 m stub stays, rubble falls), windows on whole bays.
static func _face(g: GKMesh, a: GKAsset, out: Dictionary, p: Dictionary, n: Vector3, off: float, half: float, H: float,
		door: bool, d: float, rng: RandomNumberGenerator, kind: String, dark: Color) -> void:
	var along := Vector3(1, 0, 0) if absf(n.z) > 0.5 else Vector3(0, 0, 1)
	var bay := 3.2
	var nb := maxi(int((half * 2.0 - 1.0) / bay), 1)
	if nb % 2 == 0:
		nb -= 1                                       # odd bays: the door sits in the middle
	var bw := (half * 2.0 - 1.0) / float(nb)
	var cuts: Array = []            # [u0, u1, y0, y1]
	var win_bays: Array = []
	var door_bay := nb / 2
	for k in nb:
		var u0 := -half + 0.5 + k * bw
		var u1 := u0 + bw
		var uc := (u0 + u1) * 0.5
		if door and k == door_bay:
			cuts.append([uc - DOOR_W * 0.5, uc + DOOR_W * 0.5, 0.0, DOOR_H])
			continue
		var knocked := rng.randf() < d * 0.55
		if kind == "ruin":
			knocked = rng.randf() < 0.6
		if knocked:
			var top := 0.5 if kind != "ruin" else rng.randf_range(0.4, H * 0.7)
			cuts.append([u0 + 0.2, u1 - 0.2, top, H + 1.0])
			for r in 2:
				var side := 1.0 if rng.randf() < 0.6 else -1.0
				_rubble(g, a, (along * (uc + rng.randf_range(-0.8, 0.8))) + n * (off + side * rng.randf_range(0.6, 1.8)), str(p.wall), rng, 0.5)
		elif kind != "ruin":
			win_bays.append(uc)
	# spans
	g.tint = dark
	var wall: String = p.wall
	var u := -half
	var spans: Array = []
	for c in cuts:
		if float(c[0]) > u + 0.02:
			spans.append([u, float(c[0])])
		u = float(c[1])
	if half - u > 0.02:
		spans.append([u, half])
	var emit := func(u0: float, u1: float, y0: float, y1: float) -> void:
		var lo := along * u0 + n * (off - WALL_T) + Vector3(0, y0, 0)
		var hi := along * u1 + n * off + Vector3(0, y1, 0)
		GKArch.block(g, a, wall, Vector3(minf(lo.x, hi.x), y0, minf(lo.z, hi.z)), Vector3(maxf(lo.x, hi.x), y1, maxf(lo.z, hi.z)))
	for s in spans:
		if kind == "ruin":
			# ragged: the span in ~1.1 m chunks, each its own height, some scorched
			var u0 := float(s[0])
			while u0 < float(s[1]) - 0.05:
				var u1 := minf(u0 + rng.randf_range(0.8, 1.5), float(s[1]))
				g.tint = dark.darkened(0.35) if rng.randf() < 0.3 else dark
				emit.call(u0, u1, 0.0, H * rng.randf_range(0.45, 1.0))
				u0 = u1
			g.tint = dark
		else:
			emit.call(float(s[0]), float(s[1]), 0.0, H)
		# the plinth band (campus halls: a stone footing)
		var mid := along * ((float(s[0]) + float(s[1])) * 0.5) + n * (off + 0.03)
		g.box(str(p.trim), mid + Vector3(0, 0.3, 0), along.abs() * (float(s[1]) - float(s[0])) + n.abs() * 0.06 + Vector3(0, 0.6, 0))
		if kind in ["hall", "house", "chapel"]:
			# the campus halls' white cornice and corner quoins (solid spans only)
			var cr := "window_frame:#e6e2d8" if kind != "chapel" else str(p.trim)
			g.box(cr, mid + n * 0.06 + Vector3(0, H - 0.18, 0), along.abs() * (float(s[1]) - float(s[0]) + 0.1) + n.abs() * 0.18 + Vector3(0, 0.3, 0))
			for e: float in [float(s[0]), float(s[1])]:
				if absf(absf(e) - half) < 0.05:
					var qc := along * (e - signf(e) * 0.25) + n * (off + 0.03)
					for qk in int(H / 0.9):
						var qw := 0.5 if qk % 2 == 0 else 0.34
						g.box(cr, qc - along * signf(e) * (qw - 0.5) * 0.5 + Vector3(0, 0.75 + qk * 0.9, 0), along.abs() * qw + n.abs() * 0.08 + Vector3(0, 0.4, 0))
	for c in cuts:
		if float(c[2]) > 0.0:
			emit.call(float(c[0]), float(c[1]), 0.0, float(c[2]))
		if float(c[3]) < H:
			emit.call(float(c[0]), float(c[1]), float(c[3]), H)
			# the door's frame
			g.box(str(p.trim), along * ((float(c[0]) + float(c[1])) * 0.5) + n * (off + 0.02) + Vector3(0, DOOR_H + 0.12, 0),
				along.abs() * (DOOR_W + 0.5) + n.abs() * 0.2 + Vector3(0, 0.24, 0), 0.01)
	# windows, one per whole bay per row
	var rows: int = p.rows
	var wh := 1.5 if rows == 1 else 1.7
	var ww := 1.1
	if kind == "chapel":
		wh = 3.0
		ww = 1.1
	elif kind == "barn":
		wh = 0.9
	for uc in win_bays:
		for r in rows:
			var y := 1.1 + r * 3.2 + wh * 0.5
			if kind == "chapel":
				y = 1.6
			var at := along * float(uc) + n * off + Vector3(0, y, 0)
			if kind == "chapel":
				GKArch.arch(g, along * float(uc) + n * off + Vector3(0, y, 0), n, ww, wh, { "surround": str(p.trim) })
				at += Vector3(0, wh * 0.5, 0)
			elif kind == "barn":
				g.box("window_dark", at + n * 0.01, along.abs() * ww + n.abs() * 0.02 + Vector3(0, wh, 0))
				g.box(str(p.trim), at + n * 0.02 + Vector3(0, wh * 0.5 + 0.04, 0), along.abs() * (ww + 0.16) + n.abs() * 0.03 + Vector3(0, 0.08, 0))
			else:
				GKArch.window(g, at, n, ww, wh, { "frame": "window_frame", "sill_role": str(p.trim), "mullion": rows == 1 })
				if rng.randf() < d * 0.6:
					# boarded up: three planks across, each at its own slant
					g.tint = Color.WHITE.darkened(rng.randf_range(0.0, 0.3))
					for pk in 3:
						var pb := GKArch.face_basis(n) * Basis(Vector3.BACK, rng.randf_range(-0.25, 0.25))
						g.box("wood_old:#8a7458", at + n * 0.12 + Vector3(0, (pk - 1) * wh * 0.32, 0), Vector3(ww + 0.4, 0.2, 0.04), 0.0, pb)
					g.tint = dark
				if d > 0.6 and rng.randf() < 0.45:
					g.box("tyre", at + n * 0.035 + Vector3(0, wh * 0.5 + 0.7, 0), along.abs() * (ww + 0.2) + n.abs() * 0.02 + Vector3(0, 1.3, 0))   # soot from a fire
			out.windows.append({ "pos": g.xf * at, "n": (g.xf.basis * n).normalized() })
	g.tint = dark


## A gable roof with the ridge along the longer side, as panels (disrepair
## leaves gaps you see the sky through), gable ends filled in the wall role.
static func _gable(g: GKMesh, p: Dictionary, hx: float, hz: float, H: float, d: float, rng: RandomNumberGenerator, dark: Color, kind: String) -> void:
	var along_x := hx >= hz
	var rise: float = p.rise
	var over := 0.5
	var ex := hx + over
	var ez := hz + over
	var span := (hz if along_x else hx) + over
	var slope_len := sqrt(span * span + rise * rise)
	var ang := atan2(rise, span)
	var run := (hx if along_x else hz) + over
	var n := maxi(int(run * 2.0 / 2.6), 2)
	var pw := run * 2.0 / float(n)
	var role: String = p.roof
	for side: float in [-1.0, 1.0]:
		for k in n:
			if rng.randf() < d * (0.45 if kind == "chapel" else 0.62) and kind != "watertower":
				continue
			var u := -run + (k + 0.5) * pw
			var c: Vector3
			var b: Basis
			if along_x:
				c = Vector3(u, H + rise * 0.5, side * span * 0.5)
				b = Basis(Vector3.RIGHT, side * ang)            # the eave end (+/-z) drops
				g.box(role, c, Vector3(pw - 0.02, 0.1, slope_len), 0.0, b)
			else:
				c = Vector3(side * span * 0.5, H + rise * 0.5, u)
				b = Basis(Vector3.BACK, -side * ang)
				g.box(role, c, Vector3(slope_len, 0.1, pw - 0.02), 0.0, b)
	# ridge beam
	if along_x:
		g.box(str(p.trim), Vector3(0, H + rise, 0), Vector3(run * 2.0, 0.14, 0.2))
	else:
		g.box(str(p.trim), Vector3(0, H + rise, 0), Vector3(0.2, 0.14, run * 2.0))
	# gable ends
	for side: float in [-1.0, 1.0]:
		var pts: PackedVector3Array
		if along_x:
			var x := side * hx
			pts = PackedVector3Array([Vector3(x, H, -hz), Vector3(x, H, hz), Vector3(x, H + rise, 0)])
			if side < 0.0:
				pts.reverse()
			_thick_poly(g, str(p.wall), pts, Vector3(side, 0, 0), WALL_T)
		else:
			var z := side * hz
			pts = PackedVector3Array([Vector3(hx, H, z), Vector3(-hx, H, z), Vector3(0, H + rise, z)])
			if side < 0.0:
				pts.reverse()
			_thick_poly(g, str(p.wall), pts, Vector3(0, 0, side), WALL_T)


## A polygon wall `t` thick behind its outward face: front, back, rims.
static func _thick_poly(g: GKMesh, role: String, front: PackedVector3Array, n: Vector3, t: float) -> void:
	face(g, role, front, n)
	var back := PackedVector3Array()
	var cen := Vector3.ZERO
	for q in front:
		back.append(q - n * t)
		cen += q
	cen /= float(front.size())
	face(g, role, back, -n)
	var m := front.size()
	for i in m:
		var j := (i + 1) % m
		var mid := (front[i] + front[j]) * 0.5
		face(g, role, PackedVector3Array([front[j], front[i], front[i] - n * t, front[j] - n * t]), mid - cen)


static func _hip(g: GKMesh, p: Dictionary, hx: float, hz: float, H: float, _dark: Color) -> void:
	var over := 0.5
	var ex := hx + over
	var ez := hz + over
	var rise: float = p.rise
	var inset := minf(ez, ex * 0.9)
	var r0 := Vector3(-ex + inset, H + rise, 0)
	var r1 := Vector3(ex - inset, H + rise, 0)
	var role: String = p.roof
	var c := [Vector3(-ex, H, -ez), Vector3(ex, H, -ez), Vector3(ex, H, ez), Vector3(-ex, H, ez)]
	face(g, role, PackedVector3Array([c[0], r0, r1, c[1]]), Vector3(0, 1, -1))
	face(g, role, PackedVector3Array([c[3], r0, r1, c[2]]), Vector3(0, 1, 1))
	face(g, role, PackedVector3Array([c[1], r1, c[2]]), Vector3(1, 1, 0))
	face(g, role, PackedVector3Array([c[0], r0, c[3]]), Vector3(-1, 1, 0))
	face(g, role, PackedVector3Array(c), Vector3.DOWN)   # the underside, seen from inside
	g.box(str(p.trim), (r0 + r1) * 0.5, Vector3((r1 - r0).length() + 0.1, 0.14, 0.2))


static func _porch(g: GKMesh, a: GKAsset, hx: float, hz: float, H: float, _dark: Color) -> void:
	var depth := 2.2
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hx - 0.5)
		g.cyl("wood_old:#3b2a1e", Vector3(x, 0.1, hz + depth - 0.2), Vector3(x, H - 0.5, hz + depth - 0.2), 0.12, 6)
		a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(x, H * 0.5, hz + depth - 0.2)), Vector3(0.26, H, 0.26))
	var ang := atan2(0.9, depth + 0.3)
	g.box("roof_slate:#4a4e55", Vector3(0, H - 0.1 + 0.45, hz + depth * 0.5), Vector3(hx * 2.0 + 0.6, 0.08, sqrt((depth + 0.3) * (depth + 0.3) + 0.81)), 0.0, Basis(Vector3.RIGHT, ang))
	g.box("wood_old:#8a7458", Vector3(0, -0.02, hz + depth * 0.5 - 0.3), Vector3(hx * 2.0, 0.08, depth - 0.4))
	for sx: float in [-1.0, 1.0]:
		g.box("wood_old:#3b2a1e", Vector3(sx * (hx - 0.3), 0.55, hz + depth * 0.5), Vector3(0.08, 0.08, depth - 1.2))


## The chapel's tower at the front-right corner: a solid stone block with
## lancets, a crenellated parapet and corner pinnacles (the landmark).
static func _tower(g: GKMesh, a: GKAsset, hx: float, hz: float, _H: float, dark: Color, _rng: RandomNumberGenerator, d: float) -> Vector3:
	var th := 17.0 - 2.0 * d
	var tx := hx + 2.4
	var tz := hz - 2.6
	var half := 2.5
	var S := "stone_grey:#aa9f8a"
	var T := "stone_grey:#c9bea6"
	g.tint = dark
	GKArch.block(g, a, S, Vector3(tx - half, -0.3, tz - half), Vector3(tx + half, th, tz + half))
	for y: float in [0.5, 6.0, 12.0, th]:
		g.box(T, Vector3(tx, y, tz), Vector3(half * 2.0 + 0.3, 0.2, half * 2.0 + 0.3))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.box(T, Vector3(tx + sx * (half - 0.1), th * 0.5, tz + sz * (half - 0.1)), Vector3(0.5, th, 0.5))
	for n: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var at := Vector3(tx, 0, tz) + n * half
		GKArch.arch(g, at + Vector3(0, 12.5, 0), n, 0.9, 2.6, { "surround": T })
		GKArch.arch(g, at + Vector3(0, 7.0, 0), n, 0.7, 2.0, { "surround": T })
	# parapet with crenellations
	g.box(S, Vector3(tx, th + 0.35, tz), Vector3(half * 2.0 + 0.3, 0.7, half * 2.0 + 0.3))
	for k in range(-1, 2):
		var u := k * 1.6
		for sd: float in [-1.0, 1.0]:
			g.box(S, Vector3(tx + u, th + 1.05, tz + sd * (half + 0.0)), Vector3(0.6, 0.6, 0.3))
			g.box(S, Vector3(tx + sd * (half + 0.0), th + 1.05, tz + u), Vector3(0.3, 0.6, 0.6))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var px := tx + sx * (half - 0.2)
			var pz := tz + sz * (half - 0.2)
			g.box(T, Vector3(px, th + 1.1, pz), Vector3(0.7, 1.4, 0.7))
			g.tube(S, [Vector3(px, th + 1.8, pz), Vector3(px, th + 4.2, pz)], [0.45, 0.0], 4, true)
	g.tube("roof_slate", [Vector3(tx, th + 0.7, tz), Vector3(tx, th + 5.5, tz)], [1.6, 0.0], 4, true)   # the low spire
	return g.xf * Vector3(tx, th + 5.5, tz)


## A silo beside the barn: a tall steel drum with a domed cap (the landmark).
static func _silo(g: GKMesh, a: GKAsset, hx: float, hz: float, dark: Color) -> Vector3:
	var c := Vector3(hx + 3.6, 0, -hz * 0.3)
	g.tint = dark
	g.lathe("hvac_metal", c + Vector3(0, -0.3, 0), c + Vector3(0, 16.5, 0), [Vector2(0, 2.2), Vector2(0.3, 2.2), Vector2(14.4, 2.2), Vector2(15.6, 1.4), Vector2(16.3, 0.5), Vector2(16.8, 0.0)], 12)
	for y: float in [3.0, 6.0, 9.0, 12.0]:
		g.lathe("iron_dark", c + Vector3(0, y, 0), c + Vector3(0, y + 0.12, 0), [Vector2(0, 2.3), Vector2(0.12, 2.3)], 12)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, c + Vector3(0, 8.0, 0)), Vector3(4.4, 16.0, 4.4))
	return g.xf * (c + Vector3(0, 16.8, 0))


## The water tower: four legs from the pump hut's corners to a tank (the landmark).
static func _tank(g: GKMesh, a: GKAsset, hx: float, hz: float, dark: Color) -> Vector3:
	g.tint = dark
	var top := 16.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var foot := Vector3(sx * (hx + 1.0), 0, sz * (hz + 1.0))
			var head := Vector3(sx * 1.6, top, sz * 1.6)
			g.tube("steel", [foot, head], [0.22, 0.18], 6, false)
			a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, foot + Vector3(0, 1.5, 0)), Vector3(0.4, 3.0, 0.4))
	for y: float in [4.0, 8.0, 12.0, 15.0]:
		var f := 1.0 - (y / top) * (1.0 - 1.6 / (hx + 1.0))
		var r := (hx + 1.0) * f
		for k in 4:
			var a0 := Vector3(r * [-1, 1, 1, -1][k], y, r * [-1, -1, 1, 1][k])
			var a1 := Vector3(r * [1, 1, -1, -1][k], y, r * [-1, 1, 1, -1][k])
			g.cyl("steel", a0, a1, 0.05, 4, false)
	g.box("iron_dark", Vector3(0, top + 0.1, 0), Vector3(5.2, 0.2, 5.2))
	g.lathe("hvac_metal", Vector3(0, top + 0.2, 0), Vector3(0, top + 5.6, 0), [Vector2(0, 2.9), Vector2(0.2, 3.2), Vector2(3.4, 3.2), Vector2(3.7, 2.9), Vector2(4.6, 1.4), Vector2(5.4, 0.0)], 12)
	for y: float in [1.0, 3.0]:
		g.lathe("iron_dark", Vector3(0, top + y, 0), Vector3(0, top + y + 0.12, 0), [Vector2(0, 3.28), Vector2(0.12, 3.28)], 12)
	g.cyl("steel", Vector3(0, 0.1, 0), Vector3(0, top + 0.2, 0), 0.12, 6, false)            # the riser pipe
	return g.xf * Vector3(0, top + 5.6, 0)


static func _lamp_wall(g: GKMesh, at: Vector3, n: Vector3) -> void:
	g.push(Transform3D(GKArch.face_basis(n), at))
	g.box("iron_dark", Vector3(0, 0, 0.03), Vector3(0.14, 0.3, 0.06), 0.01)
	g.tube("iron_dark", [Vector3(0, 0.05, 0.05), Vector3(0, 0.12, 0.35), Vector3(0, 0.05, 0.6)], 0.018, 6)
	g.box("window_frame:#f4e8c0", Vector3(0, -0.2, 0.6), Vector3(0.22, 0.3, 0.22), 0.02)
	g.pop()


## A pile of fallen masonry: a few tilted boxes; the big ones collide.
static func _rubble(g: GKMesh, a: GKAsset, at: Vector3, role: String, rng: RandomNumberGenerator, k: float) -> void:
	for i in 3:
		var sz := Vector3(rng.randf_range(0.3, 0.9), rng.randf_range(0.2, 0.5), rng.randf_range(0.3, 0.8)) * k
		var c := at + Vector3(rng.randf_range(-0.6, 0.6), sz.y * 0.5, rng.randf_range(-0.6, 0.6))
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		g.tint = Color.WHITE.darkened(0.25 + 0.2 * rng.randf())
		g.box(role, c, sz, 0.0, b)
		if a != null and sz.x > 0.5 and sz.y > 0.3:
			a.add_box_xf(g.xf * Transform3D(b, c), sz)
	g.tint = Color.WHITE


# ----------------------------------------------------------------- landmarks

## A lattice radio mast on a concrete pad: the tallest thing on the map.
## Returns its top (world).
static func mast(g: GKMesh, a: GKAsset, at: Vector3, h := 30.0) -> Vector3:
	g.push(Transform3D(Basis.IDENTITY, at))
	GKArch.block(g, a, "concrete", Vector3(-2.6, -0.4, -2.6), Vector3(2.6, 0.3, 2.6))
	var w0 := 1.3
	var w1 := 0.35
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.tube("steel", [Vector3(sx * w0, 0.3, sz * w0), Vector3(sx * w1, h, sz * w1)], [0.09, 0.06], 5, false)
	var levels := int(h / 5.0)
	for k in range(1, levels + 1):
		var y := k * 5.0
		var f := 1.0 - y / h
		var w := w1 + (w0 - w1) * f
		for e in 4:
			var p0 := Vector3(w * [-1, 1, 1, -1][e], y, w * [-1, -1, 1, 1][e])
			var p1 := Vector3(w * [1, 1, -1, -1][e], y, w * [-1, 1, 1, -1][e])
			g.cyl("steel", p0, p1, 0.035, 4, false)
	g.box("hvac_dark", Vector3(0, h * 0.7, w1 + 0.4), Vector3(0.6, 0.9, 0.5))
	g.lathe("hvac_metal", Vector3(0, h * 0.7, w1 + 0.7), Vector3(0, h * 0.7, w1 + 1.3), [Vector2(0, 0.7), Vector2(0.4, 0.4), Vector2(0.6, 0.05)], 10)
	g.cyl("steel", Vector3(0, h, 0), Vector3(0, h + 2.5, 0), 0.05, 5)
	g.box("sign_red", Vector3(0, h + 2.7, 0), Vector3(0.4, 0.4, 0.4), 0.05)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w0 * 2.0 + 0.3, h, w0 * 2.0 + 0.3))
	g.pop()
	return g.xf * (at + Vector3(0, h + 2.9, 0))


## An extract pad: a concrete slab with a marker pole and a smoke flare.
static func extract_pad(g: GKMesh, a: GKAsset, at: Vector3) -> void:
	g.push(Transform3D(Basis.IDENTITY, at))
	GKArch.block(g, a, "concrete_light", Vector3(-2.5, -0.4, -2.5), Vector3(2.5, 0.12, 2.5))
	g.box("sign_white", Vector3(0, 0.125, 0), Vector3(3.6, 0.01, 0.3))
	g.box("sign_white", Vector3(0, 0.125, 0), Vector3(0.3, 0.01, 3.6))
	g.cyl("iron_dark", Vector3(2.2, 0.1, 2.2), Vector3(2.2, 3.2, 2.2), 0.05, 6)
	g.box("sign_red", Vector3(2.2, 3.3, 2.2), Vector3(0.9, 0.6, 0.05))
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(2.2, 1.6, 2.2)), Vector3(0.2, 3.2, 0.2))
	g.pop()


## A spawn pocket: a shallow U of thicket 3.6 m high open toward the
## map's edge, so no window inside the map sees the eye standing in it (the
## lots sit on a disc, so every window is within 60 degrees of `inward`; the
## short returns catch the rest). `inward` points at the map's centre.
static func pocket(g: GKMesh, a: GKAsset, at: Vector3, inward: Vector3) -> void:
	var b := GKArch.face_basis(inward)       # z = inward, x along the wall
	g.push(Transform3D(b, at))
	var H := 3.6
	# a thicket: hedge blocks (bevelled, two greens) over the same boxes a wall would have
	GKArch.block(g, a, "hedge", Vector3(-4.8, -0.5, 2.1), Vector3(4.8, H, 3.3), 0.45)
	g.tint = Color(0.85, 0.9, 0.8)
	g.box("hedge:#4d6a32", Vector3(-2.2, H * 0.55, 2.7), Vector3(2.6, H * 0.9, 1.5), 0.5)
	g.box("hedge:#4d6a32", Vector3(2.6, H * 0.5, 2.7), Vector3(2.2, H * 0.8, 1.5), 0.5)
	g.tint = Color.WHITE
	for sx: float in [-1.0, 1.0]:
		GKArch.block(g, a, "hedge", Vector3(sx * 3.9, -0.5, -0.8), Vector3(sx * 5.0, H, 2.4), 0.45)
		g.box("hedge:#4d6a32", Vector3(sx * 4.5, H * 0.5, 0.6), Vector3(1.4, H * 0.75, 1.8), 0.5)
	g.box("path_concrete:#b8b3a6", Vector3(0, -0.2, 0.2), Vector3(7.0, 0.5, 3.6))
	g.pop()


# ----------------------------------------------------------------- props

## A parked car (the rooftop's box car, with collision and a paint job).
static func car(g: GKMesh, a: GKAsset, at: Vector3, yaw: float, paint: String, wear: float, tilt := Basis.IDENTITY) -> void:
	var B := tilt * Basis(Vector3.UP, yaw)
	g.push(Transform3D(B, at))
	var role := "car_paint:" + paint
	g.tint = Color.WHITE.darkened(0.45 * wear)
	g.box(role, Vector3(0, 0.6, 0), Vector3(4.2, 0.66, 1.78), 0.16)
	g.box(role, Vector3(-0.25, 1.2, 0), Vector3(2.0, 0.58, 1.6), 0.14)
	g.tint = Color.WHITE
	g.box("window_dark", Vector3(-0.25, 1.22, 0), Vector3(1.9, 0.46, 1.63), 0.08)
	for sx: float in [-1.0, 1.0]:
		g.box("iron_dark", Vector3(sx * 2.12, 0.42, 0), Vector3(0.12, 0.2, 1.7), 0.04)              # bumpers
		for sz: float in [-1.0, 1.0]:
			g.box("window_frame:#f4ecd0" if sx > 0.0 else "sign_red", Vector3(sx * 2.1, 0.72, sz * 0.66), Vector3(0.06, 0.14, 0.3))
	for wx in [-1.35, 1.35]:
		for wz in [-0.82, 0.82]:
			g.cyl("tyre", Vector3(wx, 0.34, wz - 0.12), Vector3(wx, 0.34, wz + 0.12), 0.34, 10)
	g.pop()
	a.add_box_xf(g.xf * Transform3D(B, at + B * Vector3(0, 0.75, 0)), Vector3(4.3, 1.5, 1.8))


static func lamp(g: GKMesh, a: GKAsset, at: Vector3) -> void:
	g.tube("iron_dark", [at, at + Vector3(0, 4.2, 0)], [0.09, 0.06], 6, false)
	g.box("iron_dark", at + Vector3(0, 0.25, 0), Vector3(0.32, 0.5, 0.32))
	g.lathe("window_frame:#f4e8c0", at + Vector3(0, 4.1, 0), at + Vector3(0, 4.95, 0), [Vector2(0, 0.14), Vector2(0.15, 0.26), Vector2(0.55, 0.26), Vector2(0.6, 0.32), Vector2(0.85, 0.0)], 6)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 2.2, 0)), Vector3(0.24, 4.4, 0.24))


static func bench(g: GKMesh, a: GKAsset, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	g.push(Transform3D(b, at))
	for k in 3:
		g.box("wood_old", Vector3(0, 0.46, -0.18 + k * 0.18), Vector3(1.8, 0.06, 0.14))
	g.box("wood_old", Vector3(0, 0.78, 0.27), Vector3(1.8, 0.24, 0.08))
	for s: float in [-1.0, 1.0]:
		g.box("iron_dark", Vector3(s * 0.78, 0.23, 0), Vector3(0.08, 0.46, 0.5))
		g.box("iron_dark", Vector3(s * 0.78, 0.6, 0.27), Vector3(0.08, 0.6, 0.06))
	g.pop()
	a.add_box_xf(g.xf * Transform3D(b, at + Vector3(0, 0.45, 0)), Vector3(1.84, 0.9, 0.64))


# ----------------------------------------------------------------- forest

## A broadleaf tree: tapered trunk, two foliage blobs. k scales it (1 = 11 m).
static func tree(g: GKMesh, at: Vector3, k: float, rng: RandomNumberGenerator, role: String) -> void:
	var th := 5.4 * k
	g.tube("bark", [at, at + Vector3(0, th, 0)], [0.32 * k, 0.2 * k], 6, false)
	var c := at + Vector3(0, th + 1.6 * k, 0)
	g.sphere(role, c, 2.4 * k, 7, Vector3(1.0, 0.8, 1.0))
	var a2 := rng.randf() * TAU
	g.sphere(role, c + Vector3(cos(a2) * 1.4, 1.2, sin(a2) * 1.4) * k, 1.8 * k, 7, Vector3(1.0, 0.85, 1.0))


## A conifer: trunk and three stacked cones (the campus's conifer).
static func conifer(g: GKMesh, at: Vector3, k: float, role: String) -> void:
	g.tube("bark", [at, at + Vector3(0, 4.2 * k, 0)], [0.26 * k, 0.18 * k], 6, false)
	for i in 3:
		var y := (2.4 + 2.6 * i) * k
		var r := (2.5 - 0.6 * i) * k
		g.tube(role, [at + Vector3(0, y, 0), at + Vector3(0, y + 4.4 * k, 0)], [r, 0.0], 6, true)


## A walk-through bush clump: two blobs; the caller records the hide volume.
static func bush(g: GKMesh, at: Vector3, r: float, rng: RandomNumberGenerator, role: String) -> void:
	var h := r * 1.25                          # tall enough to hide a standing eye (1.6-2.4 m)
	g.sphere(role, at + Vector3(0, h * 0.5, 0), r * 0.9, 6, Vector3(1.0, 0.7, 1.0))
	var a2 := rng.randf() * TAU
	g.sphere(role, at + Vector3(cos(a2) * r * 0.55, h * 0.55, sin(a2) * r * 0.55), r * 0.7, 6, Vector3(1.0, 0.8, 1.0))


# ----------------------------------------------------------------- terrain

## The heightfield as one mesh, straight into packed arrays (no GKMesh: the
## grid is the biggest single surface, and its split must match height_at
## exactly: the diagonal runs from (i, j) to (i + 1, j + 1)).
## hf: { origin: [x, z], step, cols, rows, data }; tint(i, j) -> Color.
static func terrain_mesh(hf: Dictionary, tint: Callable, role := "grass") -> ArrayMesh:
	var cols: int = hf.cols
	var rows: int = hf.rows
	var step: float = hf.step
	var ox: float = hf.origin[0]
	var oz: float = hf.origin[1]
	var data: PackedFloat32Array = hf.data
	var P := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	for j in rows:
		for i in cols:
			P.append(Vector3(ox + i * step, data[j * cols + i], oz + j * step))
			var hl := data[j * cols + maxi(i - 1, 0)]
			var hr := data[j * cols + mini(i + 1, cols - 1)]
			var hd := data[maxi(j - 1, 0) * cols + i]
			var hu := data[mini(j + 1, rows - 1) * cols + i]
			N.append(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
			C.append(tint.call(i, j))
	var n := (cols - 1) * (rows - 1) * 6
	var V := PackedVector3Array()
	var VN := PackedVector3Array()
	var VC := PackedColorArray()
	var UV := PackedVector2Array()
	V.resize(n)
	VN.resize(n)
	VC.resize(n)
	UV.resize(n)
	var k := 0
	for j in rows - 1:
		for i in cols - 1:
			var a := j * cols + i
			var b := a + 1
			var c := a + cols + 1
			var d := a + cols
			for idx in [a, b, c, a, c, d]:
				V[k] = P[idx]
				VN[k] = N[idx]
				VC[k] = C[idx]
				UV[k] = Vector2(P[idx].x, P[idx].z)
				k += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = VN
	arr[Mesh.ARRAY_COLOR] = VC
	arr[Mesh.ARRAY_TEX_UV] = UV
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_name(0, role)
	return m


## A ribbon on the terrain between the polyline's points: half width hw,
## `lift` above the ground, the ground from height(x, z).
## Resampled every `step` m along and split into `across` strips, every
## vertex on the ground, so a ribbon can't sink into the terrain's 3 m
## triangles (r0's grey shards) or bridge over a crest.
static func ribbon(g: GKMesh, pts: Array, hw: float, role: String, height: Callable, lift := 0.1, across := 4, step := 1.5) -> void:
	if pts.size() < 2:
		return
	var rs: Array[Vector3] = [pts[0]]
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var m := maxi(int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / step)), 1)
		for k in range(1, m + 1):
			rs.append(a.lerp(b, k / float(m)))
	var n := rs.size()
	var rows: Array = []
	var norms: Array = []
	for i in n:
		var p: Vector3 = rs[i]
		var t: Vector3
		if i == 0:
			t = rs[1] - p
		elif i == n - 1:
			t = p - rs[n - 2]
		else:
			t = rs[i + 1] - rs[i - 1]
		t.y = 0.0
		t = t.normalized()
		var s := Vector3(-t.z, 0, t.x) * hw
		var row: Array[Vector3] = []
		var nrow: Array[Vector3] = []
		for k in across + 1:
			var q := p + s * (1.0 - 2.0 * k / float(across))
			q.y = float(height.call(q.x, q.z)) + lift
			row.append(q)
			nrow.append(_ground_n(height, q.x, q.z))
		rows.append(row)
		norms.append(nrow)
	for i in n - 1:
		var r0: Array[Vector3] = rows[i]
		var r1: Array[Vector3] = rows[i + 1]
		var n0: Array[Vector3] = norms[i]
		var n1: Array[Vector3] = norms[i + 1]
		for k in across:
			_up_quad(g, role, [r0[k], r1[k], r1[k + 1], r0[k + 1]], [n0[k], n1[k], n1[k + 1], n0[k + 1]])


static func _ground_n(height: Callable, x: float, z: float) -> Vector3:
	return Vector3(float(height.call(x - 0.75, z)) - float(height.call(x + 0.75, z)), 1.5, float(height.call(x, z - 0.75)) - float(height.call(x, z + 0.75))).normalized()


## A quad facing up with per-vertex normals (wound as face() would).
static func _up_quad(g: GKMesh, role: String, p: Array, ns: Array) -> void:
	for t in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = p[t[0]]
		var b: Vector3 = p[t[1]]
		var c: Vector3 = p[t[2]]
		var fn := (c - a).cross(b - a)
		if fn.length_squared() < 1e-10:
			continue
		if fn.y < 0.0:
			g.tri(role, a, c, b, ns[t[0]], ns[t[2]], ns[t[1]])
		else:
			g.tri(role, a, b, c, ns[t[0]], ns[t[1]], ns[t[2]])


## A ribbon offset sideways from a polyline (a sidewalk beside a road).
static func offset_line(pts: Array, d: float) -> Array:
	var out := []
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)
		t.y = 0.0
		t = t.normalized()
		out.append(p + Vector3(-t.z, 0, t.x) * d)
	return out


## A paved rect draped on the ground (a forecourt): a grid every ~1.5 m.
static func drape_rect(g: GKMesh, role: String, c: Vector3, yaw: float, hx: float, hz: float, height: Callable, lift := 0.16) -> void:
	var b := Basis(Vector3.UP, yaw)
	var nx := maxi(int(ceil(hx * 2.0 / 1.5)), 1)
	var nz := maxi(int(ceil(hz * 2.0 / 1.5)), 1)
	var P: Array = []
	for j in nz + 1:
		var row: Array[Vector3] = []
		for i in nx + 1:
			var q := c + b * Vector3(-hx + 2.0 * hx * i / float(nx), 0, -hz + 2.0 * hz * j / float(nz))
			q.y = float(height.call(q.x, q.z)) + lift
			row.append(q)
		P.append(row)
	for j in nz:
		for i in nx:
			face(g, role, PackedVector3Array([P[j][i], P[j][i + 1], P[j + 1][i + 1], P[j + 1][i]]), Vector3.UP)


## A convex polygon wound to face `out` (GKMesh's front is the clockwise
## side seen from outside: this picks the order, so roofs can't end up
## inside out).
static func face(g: GKMesh, role: String, pts: PackedVector3Array, out: Vector3) -> void:
	if pts.size() < 3:
		return
	var fn := (pts[2] - pts[0]).cross(pts[1] - pts[0])
	if fn.dot(out) < 0.0:
		pts = pts.duplicate()
		pts.reverse()
	g.poly(role, pts)



# ----------------------------------------------------------------- forest variety (gauntlet r1)

## A birch: a thin white trunk, a narrow crown of three small blobs.
static func birch(g: GKMesh, at: Vector3, k: float, rng: RandomNumberGenerator, role: String) -> void:
	var th := 7.5 * k
	var lean := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)) * k
	g.tube("bark_birch", [at, at + Vector3(0, th, 0) + lean], [0.17 * k, 0.09 * k], 6, false)
	for i in 3:
		var y := th * (0.55 + 0.17 * i)
		var c := at + lean * (y / th) + Vector3(rng.randf_range(-0.5, 0.5) * k, y, rng.randf_range(-0.5, 0.5) * k)
		g.sphere(role, c, (1.5 - 0.3 * i) * k, 7, Vector3(1.0, 1.25, 1.0))


## Undergrowth: a low fern / bramble clump (no hide volume, no collision).
static func fern(g: GKMesh, at: Vector3, r: float, rng: RandomNumberGenerator, role: String) -> void:
	g.sphere(role, at + Vector3(0, r * 0.25, 0), r, 5, Vector3(1.0, 0.45, 1.0))
	var a2 := rng.randf() * TAU
	g.sphere(role, at + Vector3(cos(a2) * r * 0.7, r * 0.2, sin(a2) * r * 0.7), r * 0.7, 5, Vector3(1.0, 0.5, 1.0))


## A fallen trunk with a root plate; collides (knee high).
static func log_fallen(g: GKMesh, a: GKAsset, at: Vector3, yaw: float, ln: float, r: float, height: Callable) -> void:
	var d := Vector3(sin(yaw), 0, cos(yaw))
	var p0 := at - d * ln * 0.5
	var p1 := at + d * ln * 0.5
	p0.y = float(height.call(p0.x, p0.z)) + r * 0.8
	p1.y = float(height.call(p1.x, p1.z)) + r * 0.7
	g.tube("bark", [p0, p1], [r, r * 0.7], 7, true)
	g.tint = Color(0.85, 0.8, 0.75)
	g.cyl("wood_old:#4a3a2a", p0 - d * 0.1, p0 + d * 0.05, r * 1.9, 7, true)        # the root plate
	g.tint = Color.WHITE
	a.add_box_xf(g.xf * Transform3D(Basis.looking_at(d, Vector3.UP), (p0 + p1) * 0.5), Vector3(r * 1.6, r * 1.6, ln))


# ----------------------------------------------------------------- points of interest (gauntlet r1)

## A fire lookout: four braced timber legs to a cab with a window band and a
## pyramid roof, ~19 m; collides at the legs and the cab. Returns its top.
static func lookout(g: GKMesh, a: GKAsset, at: Vector3, yaw: float) -> Vector3:
	g.push(Transform3D(Basis(Vector3.UP, yaw), at))
	var h := 15.0
	var w0 := 2.6
	var w1 := 1.7
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.tube("wood_pole", [Vector3(sx * w0, -0.3, sz * w0), Vector3(sx * w1, h, sz * w1)], [0.16, 0.13], 6, false)
			a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(sx * w0, 1.5, sz * w0)), Vector3(0.35, 3.0, 0.35))
	for y: float in [3.5, 7.5, 11.5]:
		var w := w0 + (w1 - w0) * (y / h)
		var w2 := w0 + (w1 - w0) * ((y + 4.0) / h)
		for e in 4:
			var p0 := Vector3(w * [-1, 1, 1, -1][e], y, w * [-1, -1, 1, 1][e])
			var p1 := Vector3(w * [1, 1, -1, -1][e], y, w * [-1, 1, 1, -1][e])
			g.cyl("wood_pole", p0, p1, 0.07, 4, false)
			if y < 11.0:
				var q := Vector3(w2 * [1, 1, -1, -1][e], y + 4.0, w2 * [-1, 1, 1, -1][e])
				g.cyl("wood_pole", p0, q, 0.05, 4, false)                       # the cross braces
	# a ladder up one face
	for sx: float in [-0.35, 0.35]:
		g.cyl("wood_pole", Vector3(sx, 0, w0 + 0.3), Vector3(sx, h, w1 + 0.3), 0.05, 4, false)
	# the cab
	var c := 2.0
	g.box("wood_old:#6e5a42", Vector3(0, h + 0.1, 0), Vector3(c * 2.0 + 0.8, 0.2, c * 2.0 + 0.8))
	g.box("wood_old:#7b6248", Vector3(0, h + 0.7, 0), Vector3(c * 2.0, 1.0, c * 2.0))
	g.box("window_dark", Vector3(0, h + 1.75, 0), Vector3(c * 2.0 - 0.1, 1.1, c * 2.0 - 0.1))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.box("wood_old:#3b2a1e", Vector3(sx * (c - 0.06), h + 1.75, sz * (c - 0.06)), Vector3(0.14, 1.1, 0.14))
	g.box("window_frame:#e6e2d8", Vector3(0, h + 2.33, 0), Vector3(c * 2.0 + 0.1, 0.06, c * 2.0 + 0.1))
	g.tube("roof_slate:#7a3a2a", [Vector3(0, h + 2.35, 0), Vector3(0, h + 3.9, 0)], [c * 1.45, 0.0], 4, true)
	g.cyl("iron_dark", Vector3(0, h + 3.8, 0), Vector3(0, h + 5.2, 0), 0.04, 4)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 1.2, 0)), Vector3(c * 2.0, 2.4, c * 2.0))
	var top := g.xf * Vector3(0, h + 4.0, 0)
	g.pop()
	return top


## A hunting stand: four poles, a plywood box seat 4 m up, a ladder.
static func hunting_stand(g: GKMesh, a: GKAsset, at: Vector3, yaw: float) -> void:
	g.push(Transform3D(Basis(Vector3.UP, yaw), at))
	var h := 3.8
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.tube("wood_pole", [Vector3(sx * 1.0, -0.2, sz * 1.0), Vector3(sx * 0.7, h + 1.6, sz * 0.7)], [0.08, 0.07], 5, false)
			a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(sx * 1.0, 1.0, sz * 1.0)), Vector3(0.2, 2.0, 0.2))
	g.box("wood_old:#7a6a4e", Vector3(0, h, 0), Vector3(1.8, 0.1, 1.8))
	g.box("paint_army", Vector3(0, h + 0.5, -0.86), Vector3(1.7, 0.9, 0.06))
	g.box("paint_army", Vector3(0.86, h + 0.5, 0), Vector3(0.06, 0.9, 1.7))
	g.box("paint_army", Vector3(-0.86, h + 0.5, 0), Vector3(0.06, 0.9, 1.7))
	g.box("roof_slate:#4a5040", Vector3(0, h + 1.65, 0), Vector3(2.0, 0.08, 2.0), 0.0, Basis(Vector3.RIGHT, 0.12))
	for k in 6:
		g.box("wood_pole", Vector3(0, 0.4 + k * 0.6, 1.25 + k * 0.05), Vector3(0.6, 0.06, 0.06))
	for sx: float in [-0.3, 0.3]:
		g.cyl("wood_pole", Vector3(sx, 0, 1.2), Vector3(sx, h, 1.5), 0.04, 4, false)
	g.pop()


## A car gone off the road: nose down and rolled, rusted, a door off in the grass.
static func crashed_car(g: GKMesh, a: GKAsset, at: Vector3, yaw: float, paint: String, slope := Basis.IDENTITY) -> void:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(-fwd.z, 0, fwd.x)
	var tilt := slope * Basis(fwd, 0.55) * Basis(side, 0.14)
	car(g, a, at + Vector3(0, 0.05, 0), yaw, paint, 0.95, tilt)
	g.tint = Color(0.7, 0.66, 0.6)
	g.box("car_paint:" + paint, at + side * 1.8 + fwd * 0.3 + Vector3(0, 0.06, 0), Vector3(1.1, 0.06, 0.9), 0.02, Basis(Vector3.UP, yaw + 0.5))
	g.tint = Color.WHITE
	for k in 3:
		g.box("iron_rust", at - fwd * (2.8 + k * 0.7) + side * (0.5 - k * 0.4) + Vector3(0, 0.04, 0), Vector3(0.4, 0.05, 0.25), 0.0, Basis(Vector3.UP, k * 1.3))


## A campfire clearing: a stone ring with ash, log seats, a tarp lean-to.
static func campfire(g: GKMesh, a: GKAsset, at: Vector3, yaw: float, height: Callable) -> void:
	var b := Basis(Vector3.UP, yaw)
	for k in 9:
		var an := k * TAU / 9.0
		var q := at + Vector3(cos(an), 0, sin(an)) * 0.9
		q.y = float(height.call(q.x, q.z)) + 0.1
		g.box("stone_grey:#8a877e", q, Vector3(0.34, 0.24, 0.28), 0.04, Basis(Vector3.UP, an))
	g.box("asphalt:#2a2624", at + Vector3(0, 0.03, 0), Vector3(1.2, 0.05, 1.2))
	for k in 3:
		g.cyl("bark", at + Vector3(cos(k * 2.1) * 0.4, 0.1, sin(k * 2.1) * 0.4), at + Vector3(0, 0.45, 0), 0.06, 5)
	for k in 3:
		var an := yaw + k * TAU / 3.0 + 0.4
		var d := Vector3(sin(an), 0, cos(an))
		var q := at + d * 2.6
		q.y = float(height.call(q.x, q.z))
		var s := Vector3(-d.z, 0, d.x)
		g.cyl("bark", q - s * 0.9 + Vector3(0, 0.22, 0), q + s * 0.9 + Vector3(0, 0.22, 0), 0.22, 7)
	# the lean-to: two poles, a ridge, a tarp sloping to the ground
	var t := at + b * Vector3(0, 0, -4.2)
	t.y = float(height.call(t.x, t.z))
	g.push(Transform3D(b, t))
	for sx: float in [-1.4, 1.4]:
		g.cyl("wood_pole", Vector3(sx, 0, 0), Vector3(sx, 1.7, 0), 0.05, 5)
	g.cyl("wood_pole", Vector3(-1.6, 1.7, 0), Vector3(1.6, 1.7, 0), 0.05, 5)
	var ang := atan2(1.7, 2.0)
	g.box("canvas_awning:#4a6a8a", Vector3(0, 0.85, -1.0), Vector3(3.2, 0.03, sqrt(1.7 * 1.7 + 4.0)), 0.0, Basis(Vector3.RIGHT, -ang))
	g.box("canvas_awning:#7a6a50", Vector3(0.3, 0.12, -0.7), Vector3(0.7, 0.24, 1.8), 0.08)    # a bedroll
	# an orange ridge tent beside it: the colour you spot through the trees
	g.push(Transform3D(Basis(Vector3.UP, 0.9), Vector3(4.2, 0, 0.8)))
	for sd: float in [-1.0, 1.0]:
		var ta := atan2(1.6, 1.3)
		g.box("sign_red:#e0701c", Vector3(sd * 0.65, 0.8, 0), Vector3(0.03, sqrt(1.6 * 1.6 + 1.3 * 1.3), 2.6), 0.0, Basis(Vector3.BACK, -sd * (PI * 0.5 - ta)))
	g.box("canvas_awning:#3a3a34", Vector3(0, 0.7, 1.31), Vector3(1.0, 1.2, 0.02))
	g.cyl("iron_dark", Vector3(0, 0, -1.4), Vector3(0, 2.2, -1.4), 0.03, 4)
	g.box("sign_red", Vector3(0.3, 2.0, -1.4), Vector3(0.6, 0.38, 0.02))
	g.pop()
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.85, -1.0)), Vector3(3.0, 1.6, 1.6))
	g.pop()


## A ruined field wall: a run of mossy stone with fallen stretches and a gate gap.
static func ruin_wall(g: GKMesh, a: GKAsset, at: Vector3, yaw: float, ln: float, rng: RandomNumberGenerator, height: Callable) -> void:
	var d := Vector3(sin(yaw), 0, cos(yaw))
	var bb := Basis.looking_at(d, Vector3.UP)
	var n := int(ln / 1.6)
	for k in n:
		var u := -ln * 0.5 + (k + 0.5) * 1.6
		if absf(u) < 1.2:
			continue                                           # the gate gap
		var q := at + d * u
		var gy := float(height.call(q.x, q.z))
		var h := rng.randf_range(0.5, 1.9)
		if rng.randf() < 0.25:
			h = 0.35
		var c := Vector3(q.x, gy + h * 0.5 - 0.2, q.z)
		g.tint = Color.WHITE.darkened(rng.randf_range(0.0, 0.25))
		g.box("stone_grey:#9a958a", c, Vector3(0.7, h + 0.4, 1.62), 0.06, bb)
		g.tint = Color(0.8, 0.95, 0.7)
		if h > 0.6:
			g.box("hedge:#5a7a34", Vector3(q.x, gy + h + 0.02, q.z), Vector3(0.72, 0.1, 1.5), 0.04, bb)   # moss on the cap
		a.add_box_xf(g.xf * Transform3D(bb, c), Vector3(0.7, h + 0.4, 1.62))
		if h < 0.5 and rng.randf() < 0.7:
			_rubble(g, a, Vector3(q.x, gy, q.z) + Vector3(-d.z, 0, d.x) * rng.randf_range(-1.2, 1.2), "stone_grey:#9a958a", rng, 0.9)
	g.tint = Color.WHITE


## A wooden H-frame power pole with a crossarm and insulators; returns the
## three wire points (world).
static func pylon(g: GKMesh, a: GKAsset, at: Vector3, yaw: float) -> Array:
	g.push(Transform3D(Basis(Vector3.UP, yaw), at))
	var h := 10.5
	for sx: float in [-1.0, 1.0]:
		g.tube("wood_pole", [Vector3(sx * 1.3, -0.4, 0), Vector3(sx * 1.2, h + 0.4, 0)], [0.17, 0.13], 6, false)
		a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(sx * 1.3, 1.5, 0)), Vector3(0.32, 3.0, 0.32))
	g.box("wood_pole", Vector3(0, h, 0), Vector3(4.6, 0.2, 0.18))
	g.cyl("wood_pole", Vector3(-1.25, h - 1.6, 0), Vector3(1.25, h - 0.15, 0), 0.06, 4, false)
	var wires: Array = []
	for u: float in [-1.9, 0.0, 1.9]:
		g.cyl("hvac_metal", Vector3(u, h + 0.1, 0), Vector3(u, h + 0.45, 0), 0.06, 5)
		wires.append(g.xf * Vector3(u, h + 0.45, 0))
	g.pop()
	return wires
