class_name MmoArena
extends RefCounted
## The Giant's Courtyard, after the author's reference (a WoW Classic
## monastery courtyard, design/ref/mmo/wow_classic_ui.jpg): a round cobbled
## plaza (MmoSim.ARENA_R) inside a wide stone curb, a lawn with four
## fountains, a cloister of columns and arches under a tiled roof, and a
## high brick wall with red banners; a gate behind the Giant, an opening
## behind the raid. Built from the Gamer kit (GKMesh + GKMaterials roles),
## deterministic, no textures.

const R := MmoSim.ARENA_R
const CURB_R := R + 0.55
const LAWN_R := 31.5
const COL_R := 33.0
const WALL_R := 37.0
const COLS := 40

const FLOOR := "cobble:#8e8a84"
const FLOOR_BAND := "flagstone:#7f7b74"
const DAIS := "flagstone:#9a948a"
const INNER_R := 17.0
const PATH_W := 3.2
const CURB := "sandstone_trim:#8f8c86"
const CAP := "sandstone_trim:#b3ada2"
const LAWN := "grass:#5d7a34"
const STONE := "sandstone:#9a978f"
const BRICK := "brick_red:#4e3d37"
const ROOF := "brick_red:#6a3428"
const BEAM := "wood_old"
const WATER := "glass_lens:#3e6f86"
const BANNER := "sign_red:#a3241e"
const GOLD := "brass"


static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Courtyard"
	parent.add_child(root)
	var g := GKMesh.new()
	_ground(g)
	_curb(g)
	_cloister(g)
	_wall(g)
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		_fountain(g, Vector3(sin(a), 0, cos(a)) * 28.4, root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for k in 10:
		var a := TAU * k / 10.0 + rng.randf_range(-0.12, 0.12)
		if absf(wrapf(a - PI / 4.0, -PI / 4.0, PI / 4.0)) < 0.18:
			continue                                        # keep clear of the fountains
		if absf(cos(a)) > 0.93:
			continue                                        # the gate and the opening
		_tree(g, Vector3(sin(a), 0, cos(a)) * rng.randf_range(29.6, 30.6), rng.randf_range(0.85, 1.2))
	var mi := MeshInstance3D.new()
	mi.name = "CourtyardMesh"
	mi.mesh = g.commit()
	GKMaterials.apply(mi)
	root.add_child(mi)
	return root


static func lights() -> Dictionary:
	return { "sun_dir": [0.45, -0.62, 0.64], "sun_col": "#ffe6c4", "sun_energy": 1.75, "sky_top": "#3f6496",
		"sky_horizon": "#aeb2ac", "ground": "#4a4436", "ambient": 0.45, "ambient_col": "#9a9488", "sky_share": 0.5,
		"fog_col": "#8f9496", "fog_density": 0.006, "exposure": 0.92, "saturation": 1.12, "contrast": 1.16,
		"shadow_dist": 90.0, "normal_bias": 0.9 }


# ------------------------------------------------------------------ parts

static func _disc(g: GKMesh, role: String, r0: float, r1: float, y: float, seg := 96) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(sin(a0), 0, cos(a0))
		var p1 := Vector3(sin(a1), 0, cos(a1))
		if r0 <= 0.0:
			g.tri(role, Vector3(0, y, 0), p1 * r1 + Vector3(0, y, 0), p0 * r1 + Vector3(0, y, 0))
		else:
			g.quad(role, p0 * r0 + Vector3(0, y, 0), p1 * r0 + Vector3(0, y, 0), p1 * r1 + Vector3(0, y, 0), p0 * r1 + Vector3(0, y, 0))


static func _ground(g: GKMesh) -> void:
	_disc(g, DAIS, 0.0, 7.2, 0.0)
	_disc(g, FLOOR_BAND, 7.2, 8.4, 0.0, 72)
	_lawns(g)
	_disc(g, FLOOR_BAND, INNER_R, INNER_R + 0.7, 0.0)
	_disc(g, FLOOR, INNER_R + 0.7, R - 1.4, 0.0)
	_disc(g, FLOOR_BAND, R - 1.4, CURB_R, 0.0)
	_disc(g, LAWN, CURB_R, LAWN_R + 1.0, -0.02)
	_disc(g, FLOOR_BAND, LAWN_R + 1.0, WALL_R + 0.5, -0.01)       # the cloister walk
	_disc(g, LAWN, WALL_R + 0.5, 140.0, -0.05, 48)


## Between the dais and the walk: four lawns cut by cobbled paths (the
## reference's grass beside the paving), flush with the stone so nothing
## reads as a step.
static func _lawns(g: GKMesh) -> void:
	var seg := 96
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for k in 6:
			var r0 := 8.4 + (INNER_R - 8.4) * k / 6.0
			var r1 := 8.4 + (INNER_R - 8.4) * (k + 1) / 6.0
			var pa := Vector3(sin(a0), 0, cos(a0))
			var pb := Vector3(sin(a1), 0, cos(a1))
			var mid := (pa + pb) * 0.5 * (r0 + r1) * 0.5
			var on_path := absf(mid.x) < PATH_W * 0.5 or absf(mid.z) < PATH_W * 0.5
			g.quad(FLOOR if on_path else LAWN, pa * r0, pb * r0, pb * r1, pa * r1)


## The wide stone curb round the plaza (the reference's walkway wall): a
## low wall with a broad coping, broken at the gate (north) and the
## opening (south).
static func _curb(g: GKMesh) -> void:
	var seg := 64
	for i in seg:
		var a := TAU * (i + 0.5) / seg
		if absf(cos(a)) > 0.995:
			continue
		var w := TAU * CURB_R / seg + 0.02
		g.push(Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * CURB_R))
		g.box(CURB, Vector3(0, 0.28, 0), Vector3(w, 0.56, 0.8), 0.02)
		g.box(CAP, Vector3(0, 0.6, 0), Vector3(w + 0.03, 0.1, 1.15), 0.03)
		g.pop()


static func _cloister(g: GKMesh) -> void:
	var step := TAU / COLS
	for i in COLS:
		var a := step * i
		if absf(cos(a)) > 0.985:
			continue
		var p := Vector3(sin(a), 0, cos(a)) * COL_R
		g.lathe(STONE, p, p + Vector3(0, 0.5, 0), [Vector2(0.0, 0.52), Vector2(0.18, 0.52), Vector2(0.25, 0.4), Vector2(0.5, 0.36)], 12)
		g.cyl(STONE, p + Vector3(0, 0.5, 0), p + Vector3(0, 4.6, 0), 0.32, 12)
		g.lathe(STONE, p + Vector3(0, 4.6, 0), p + Vector3(0, 5.1, 0), [Vector2(0.0, 0.36), Vector2(0.3, 0.48), Vector2(0.5, 0.5)], 12)
		g.box(STONE, p + Vector3(0, 5.2, 0), Vector3(1.1, 0.2, 1.1), 0.03, Basis(Vector3.UP, a))
		# the arch to the next column: a half-ring of voussoirs
		var a2 := a + step
		if absf(cos(a2)) > 0.985:
			continue
		var q := Vector3(sin(a2), 0, cos(a2)) * COL_R
		var mid := (p + q) * 0.5
		var span := p.distance_to(q) * 0.5
		var along := (q - p).normalized()
		var pts: Array = []
		for k in 13:
			var t := PI * k / 12.0
			pts.append(mid + along * (-cos(t) * span) + Vector3(0, 5.3 + sin(t) * span * 0.75, 0))
		g.tube(STONE, pts, 0.28, 8, true)
		g.box(STONE, mid + Vector3(0, 6.15 + 0.35, 0), Vector3(span * 2.0 + 0.4, 0.7, 0.75), 0.02, Basis(Vector3.UP, a + step * 0.5))
	# the roof over the walk: a ring of sloped tiles from above the arches to the wall
	var seg := 80
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var o0 := Vector3(sin(a0), 0, cos(a0))
		var o1 := Vector3(sin(a1), 0, cos(a1))
		var lo := 7.0
		var hi := 9.0
		var ri := COL_R - 0.7
		var ro := WALL_R
		g.quad(ROOF, o0 * ri + Vector3(0, lo, 0), o1 * ri + Vector3(0, lo, 0), o1 * ro + Vector3(0, hi, 0), o0 * ro + Vector3(0, hi, 0))
		g.quad(BEAM, o0 * ri + Vector3(0, lo - 0.25, 0), o0 * ro + Vector3(0, hi - 0.25, 0), o1 * ro + Vector3(0, hi - 0.25, 0), o1 * ri + Vector3(0, lo - 0.25, 0))
		g.quad(BEAM, o0 * ri + Vector3(0, lo - 0.25, 0), o1 * ri + Vector3(0, lo - 0.25, 0), o1 * ri + Vector3(0, lo, 0), o0 * ri + Vector3(0, lo, 0))


static func _wall(g: GKMesh) -> void:
	var seg := 48
	var h := 13.0
	for i in seg:
		var a := TAU * (i + 0.5) / seg
		var w := TAU * WALL_R / seg + 0.05
		var gate := absf(cos(a)) > 0.995 and cos(a) < 0.0
		g.push(Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * (WALL_R + 0.6)))
		if gate:
			g.box(BRICK, Vector3(0, h - 2.5, 0), Vector3(w, 5.0, 1.2))
			GKArch.arch(g, Vector3(0, 0, -0.62), Vector3(0, 0, -1), 4.2, 7.6, { "glass": "wood_door", "surround": STONE })
		else:
			g.box(BRICK, Vector3(0, h * 0.5, 0), Vector3(w, h, 1.2))
			g.box(STONE, Vector3(0, h + 0.2, 0), Vector3(w + 0.02, 0.4, 1.5), 0.03)
			for k: int in [-1, 1]:
				g.box(STONE, Vector3(k * w * 0.25, h + 0.75, 0), Vector3(w * 0.22, 0.8, 1.4), 0.03)       # crenels
			if i % 3 == 0:
				# a buttress and a tall red banner with a gold edge
				g.box(STONE, Vector3(0, 4.0, -0.9), Vector3(0.9, 8.0, 0.7), 0.04)
			elif i % 3 == 1:
				g.box(BANNER, Vector3(0, 10.2, -0.66), Vector3(1.4, 3.6, 0.04))
				g.box(GOLD, Vector3(0, 12.05, -0.68), Vector3(1.6, 0.12, 0.08))
				g.box(GOLD, Vector3(0, 8.42, -0.68), Vector3(1.4, 0.08, 0.06))
				g.box(GOLD, Vector3(0, 10.4, -0.69), Vector3(0.5, 0.5, 0.02), 0.0, Basis(Vector3.BACK, PI / 4.0))
			else:
				GKArch.window(g, Vector3(0, 10.0, -0.6), Vector3(0, 0, -1), 1.0, 2.0, { "frame": STONE, "glass": "window_dark" })
		g.pop()
	# the opening behind the raid: two gate towers
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * 3.4, 0, WALL_R + 0.6)
		g.box(STONE, p + Vector3(0, 8.0, 0), Vector3(2.0, 16.0, 2.0), 0.05)
		g.box(ROOF, p + Vector3(0, 16.6, 0), Vector3(2.4, 1.2, 2.4), 0.3)


static func _fountain(g: GKMesh, at: Vector3, root: Node3D) -> void:
	g.lathe(STONE, at, at + Vector3(0, 0.7, 0), [Vector2(0.0, 2.3), Vector2(0.56, 2.3), Vector2(0.7, 2.05)], 32)
	_disc_at(g, WATER, at + Vector3(0, 0.55, 0), 2.05)
	g.cyl(STONE, at + Vector3(0, 0.55, 0), at + Vector3(0, 1.8, 0), 0.28, 10)
	g.lathe(STONE, at + Vector3(0, 1.8, 0), at + Vector3(0, 2.1, 0), [Vector2(0.0, 0.3), Vector2(0.18, 0.85), Vector2(0.3, 0.8)], 18)
	# the spouts: four jets arcing into the basin
	for k in 4:
		var p := CPUParticles3D.new()
		p.amount = 40
		p.lifetime = 0.9
		p.direction = Vector3(sin(k * PI / 2.0), 2.2, cos(k * PI / 2.0)).normalized()
		p.spread = 4.0
		p.initial_velocity_min = 3.6
		p.initial_velocity_max = 3.9
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.12
		p.scale_amount_max = 0.2
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 6
		m.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.93, 1.0, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material = mat
		p.mesh = m
		p.position = at + Vector3(0, 2.05, 0)
		root.add_child(p)


static func _disc_at(g: GKMesh, role: String, c: Vector3, r: float) -> void:
	for i in 32:
		var a0 := TAU * i / 32.0
		var a1 := TAU * (i + 1) / 32.0
		g.tri(role, c, c + Vector3(sin(a1), 0, cos(a1)) * r, c + Vector3(sin(a0), 0, cos(a0)) * r)


static func _tree(g: GKMesh, at: Vector3, s: float) -> void:
	g.cyl(BEAM, at, at + Vector3(0, 3.2 * s, 0), 0.22 * s, 8)
	g.sphere("foliage:#4f7a2a", at + Vector3(0, 4.2 * s, 0), 1.9 * s, 10, Vector3(1.0, 0.85, 1.0))
	g.sphere("foliage:#5b8a32", at + Vector3(0.7 * s, 5.0 * s, 0.3 * s), 1.3 * s, 10)
	g.sphere("foliage:#46702a", at + Vector3(-0.6 * s, 4.8 * s, -0.4 * s), 1.2 * s, 10)
