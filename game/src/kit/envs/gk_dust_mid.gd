class_name GKDustMid
extends GKDef
## Shooter hallway after Dust2's mid (design/ref/kit/dust_mid.jpg): a long
## sunlit lane of sandy paving between whitewashed buildings on the left and a
## tall ochre wall on the right, a raised walkway behind a low wall on the
## right, a wooden utility pole with sagging cables, the blue "Hotel Aurore"
## sign with the red A, an awning, manhole covers, and a sandstone tower closing
## the far end. Anything the photo doesn't show is a wall or an invisible
## barrier (the brief), so the lane is a closed box: T end behind the camera,
## the far end at the tower.
## Laid out in real metres (x across, left negative; z down the lane), then
## scaled by `scale` so doors fit the 2.2 m Black | White body.

func id() -> String:
	return "dust_mid"


func title() -> String:
	return "Dust hallway (mid)"


func kind() -> String:
	return "env"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pf("scale", "Scale", "Fit", 1.25, 0.8, 1.6, 0.01),
		pf("length", "Lane length (m)", "Layout", 52.0, 36.0, 70.0, 0.5),
		pf("width", "Lane width (m)", "Layout", 10.5, 8.0, 14.0, 0.1),
		pb("catwalk", "Raised walkway", "Layout", true),
		pf("cat_h", "Walkway height (m)", "Layout", 0.9, 0.5, 1.4, 0.05),
		pb("pole", "Utility pole + cables", "Dressing", true),
		pb("sign", "Hotel sign", "Dressing", true),
		pb("awning", "Awning", "Dressing", true),
		pf("sun_yaw", "Sun direction (deg)", "Light", -128.0, -180.0, 180.0, 1.0),
		pf("sun_height", "Sun height (deg)", "Light", 46.0, 15.0, 85.0, 1.0),
	]


func presets() -> Dictionary:
	return {
		"Reference": {},
		"Short and wide": { "length": 40.0, "width": 12.5 },
		"No walkway": { "catwalk": false },
		"Late sun": { "sun_yaw": -100.0, "sun_height": 20.0 },
	}


func _build(p: Dictionary) -> GKAsset:
	var a := GKAsset.new()
	var s: float = p.scale
	var g := GKMesh.new()
	# authored with the lane running +z and the left side at -x; the photo
	# looks down the lane with that side on its left, which in Godot (camera
	# looking -z) means the lane runs -z: so the plan is mirrored in z.
	var M := Transform3D(Basis.from_scale(Vector3(s, s, -s)), Vector3.ZERO)
	g.push(M)
	var L: float = p.length
	var W: float = p.width
	var xl := -W * 0.55              # left face (the lane is a touch off-centre, like the photo)
	var xr := W * 0.45
	var z0 := -8.0                   # T end wall
	var z1 := L                      # the tower's face
	# ---- ground: the lane's paving, carried under everything
	GKArch.block(g, a, "flagstone", Vector3(xl - 10.0, -0.3, z0 - 4.0), Vector3(xr + 10.0, 0.0, z1 + 12.0))
	var cam := Vector3(xr - 2.65, 1.72, -1.3)      # the photo's eye: just left of the low wall's line
	_manholes(g, cam)
	_left(g, a, xl, z0, z1)
	_right(g, a, xr, z0, z1, p)
	if p.catwalk:
		_catwalk(g, a, xr, TOWER_Z, float(p.cat_h))
	_tower(g, a, xr)
	_far_end(g, a, xl, xr, z1)
	_t_end(g, a, xl, xr, z0)
	if p.pole:
		_pole(g, a, xl, xr)
	_skyline(g, xl, xr, z0, z1)
	g.pop()
	a.add_part("world", g.commit())
	# ---- edges: invisible walls along the lane, a lid at roof height
	GKArch.barrier(a, Vector3(xl - 1.0, 0, z0 - 1.0), Vector3(xr + 1.0, 14.0, z0), M)
	GKArch.barrier(a, Vector3(xl - 1.0, 0, z1), Vector3(xr + 1.0, 14.0, z1 + 1.0), M)
	GKArch.barrier(a, Vector3(xl - 1.0, 0, z0), Vector3(xl, 14.0, z1), M)
	GKArch.barrier(a, Vector3(xr, 0, z0), Vector3(xr + 1.0, 14.0, z1), M)
	GKArch.barrier(a, Vector3(xl, 9.5, z0), Vector3(xr, 10.0, z1), M)
	# ---- markers
	var look := func(from: Vector3, to: Vector3) -> Transform3D:
		return Transform3D(Basis.looking_at((M * to - M * from).normalized(), Vector3.UP), M * from)
	a.markers = {
		"ref_cam": look.call(cam, Vector3(0.6, 2.9, 30.0)),
		"eye_a": look.call(Vector3(xr - 1.2, float(p.cat_h) + 1.72 if p.catwalk else 1.72, 30.0), Vector3(-1.5, 1.6, 2.0)),
		"eye_b": look.call(Vector3(-1.5, 1.72, z1 - 3.0), Vector3(1.0, 2.6, 0.0)),
	}
	for k in 3:
		a.markers["spawn_a%d" % k] = Transform3D(Basis.IDENTITY, M * Vector3(-2.0 + k * 2.0, 0.0, z0 + 2.5))
		a.markers["spawn_b%d" % k] = Transform3D(Basis(Vector3.UP, PI), M * Vector3(-2.0 + k * 2.0, 0.0, z1 - 2.5))
	a.meta = { "ref_cam_fov": 66.0, "eye_a_fov": 70.0, "eye_b_fov": 70.0, "play_area": [xl * s, -z1 * s, xr * s, -z0 * s],
		"notes": "Closed lane: T end (spawn_a*) to the tower (spawn_b*). Raised walkway on the right." }
	var yaw := deg_to_rad(float(p.sun_yaw))
	var el := deg_to_rad(float(p.sun_height))
	var to_sun := Vector3(sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el))
	a.lights = { "sun_dir": [-to_sun.x, -to_sun.y, -to_sun.z], "sun_col": "#fff0d8", "sun_energy": 2.0,
		"sky_top": "#5f93d0", "sky_horizon": "#dfe6ea", "ground": "#9a8a70", "ambient": 0.72, "exposure": 1.0,
		"ambient_col": "#bbb2a4", "sky_share": 0.32, "ssao": 2.4,
		"fog_col": "#d6e0e8", "fog_density": 0.0045, "saturation": 1.05, "contrast": 1.05, "shadow_dist": 90.0 * s }
	return a


const TOWER_Z := 30.0            ## the sandstone tower's face: where the walkway ends


## Two rusty manhole covers just ahead of the eye, as in the photo's foreground.
func _manholes(g: GKMesh, cam: Vector3) -> void:
	for c in [Vector3(cam.x - 1.45, 0, 1.75), Vector3(cam.x - 0.2, 0, 1.9)]:
		g.lathe("iron_rust", c + Vector3(0, -0.01, 0), c + Vector3(0, 0.018, 0), [Vector2(0, 0.56), Vector2(0.024, 0.545), Vector2(0.028, 0.0)], 36)
		for k in 7:
			var off := Vector3(0, 0.02, -0.33 + k * 0.11)
			g.box("iron_rust", c + off, Vector3(0.84 - absf(k - 3.0) * 0.14, 0.008, 0.032))
		g.lathe("iron_dark", c + Vector3(0, -0.01, 0), c + Vector3(0, 0.012, 0), [Vector2(0, 0.62), Vector2(0.022, 0.62)], 36)   # the frame


## The left side: whitewashed blocks stepping back and up, arched windows,
## a plank door, a lantern, roof beams poking out.
func _left(g: GKMesh, a: GKAsset, xl: float, z0: float, z1: float) -> void:
	var n := Vector3.RIGHT
	# L0: a single-storey annex jutting into the lane by the T end, its roof railed
	var xj := xl + 2.2
	GKArch.block(g, a, "plaster_white", Vector3(xl - 0.1, 0, z0), Vector3(xj, 3.6, 3.2), 0.05)
	g.box("plaster_white", Vector3((xl + xj) * 0.5, 3.72, (z0 + 3.2) * 0.5), Vector3(xj - xl + 0.2, 0.24, 3.2 - z0 + 0.2), 0.03)
	GKArch.window(g, Vector3(xj, 1.7, 0.4), n, 0.7, 0.9, { "bars": 3, "sill_role": "plaster_white", "reveal": "plaster_white" })
	GKArch.door(g, Vector3(xj - 1.0, 0, 3.2), Vector3.BACK, 1.0, 2.2, "wood_door", false)
	var rx := z0 + 0.3
	while rx < 3.1:
		g.cyl("iron_dark", Vector3(xj - 0.08, 3.84, rx), Vector3(xj - 0.08, 4.7, rx), 0.018, 6)
		rx += 0.75
	g.cyl("iron_dark", Vector3(xj - 0.08, 4.7, z0 + 0.3), Vector3(xj - 0.08, 4.7, 3.1), 0.022, 6)
	g.push(Transform3D(Basis(Vector3.UP, deg_to_rad(60.0)) * Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(xl - 2.0, 7.9, 1.2)))
	g.lathe("hvac_metal", Vector3.ZERO, Vector3(0, 0, 0.16), [Vector2(0, 0.38), Vector2(0.08, 0.34), Vector2(0.14, 0.22), Vector2(0.16, 0.02)], 18)
	g.cyl("iron_dark", Vector3(0, 0, 0), Vector3(0, 0, -0.45), 0.02, 6)
	g.pop()
	g.cyl("iron_dark", Vector3(xl - 2.0, 7.2, 1.2), Vector3(xl - 2.0, 7.8, 1.2), 0.03, 6)
	# L1: two storeys, the door and lantern nearest the camera
	GKArch.block(g, a, "plaster_white", Vector3(xl - 9.0, 0, z0), Vector3(xl, 7.2, 9.0), 0.04)
	g.box("plaster_white", Vector3(xl - 0.12, 7.35, (z0 + 9.0) * 0.5), Vector3(0.36, 0.3, 17.0 - 0.1), 0.03)   # the roof lip
	GKArch.door(g, Vector3(xl, 0, 5.4), n, 1.7, 2.6, "wood_door")
	for z in [-3.5, 3.4, 7.0]:
		GKArch.window(g, Vector3(xl, 5.1, z), n, 0.75, 0.95, { "shutters": "wood_door", "sill_role": "plaster_white", "depth": 0.22 })
	GKArch.window(g, Vector3(xl, 2.1, -4.2), n, 0.6, 0.8, { "bars": 3, "sill_role": "plaster_white" })
	_lantern(g, Vector3(xl, 3.7, 7.4), n)
	# the roof terrace above L1: a pergola of rough beams
	for z in [2.0, 3.6, 5.2, 6.8, 8.4]:
		g.box("wood_old", Vector3(xl - 1.2, 8.55, z), Vector3(2.6, 0.14, 0.14), 0.02)
	for z in [2.0, 8.4]:
		g.box("wood_old", Vector3(xl - 0.25, 7.9, z), Vector3(0.14, 1.4, 0.14), 0.02)
		g.box("wood_old", Vector3(xl - 2.3, 7.9, z), Vector3(0.14, 1.4, 0.14), 0.02)
	g.box("wood_old", Vector3(xl - 0.25, 8.4, 5.2), Vector3(0.14, 0.14, 6.6), 0.02)
	# a railing along L1's roof edge
	var rz := z0 + 0.5
	while rz < 9.0:
		g.cyl("iron_dark", Vector3(xl - 0.2, 7.45, rz), Vector3(xl - 0.2, 8.4, rz), 0.02, 6)
		rz += 0.9
	g.cyl("iron_dark", Vector3(xl - 0.2, 8.4, z0 + 0.5), Vector3(xl - 0.2, 8.4, 9.0), 0.025, 6)
	g.cyl("iron_dark", Vector3(xl - 0.2, 7.9, z0 + 0.5), Vector3(xl - 0.2, 7.9, 9.0), 0.018, 6)
	# L2: set back half a metre, two tall arched windows and an arched door
	var x2 := xl - 0.5
	GKArch.block(g, a, "plaster_white", Vector3(x2 - 8.0, 0, 9.0), Vector3(x2, 6.0, 21.0), 0.04)
	g.box("plaster_white", Vector3(xl - 0.25, 0.35, 15.0), Vector3(0.5, 0.7, 12.0), 0.06)   # a plinth bench along the foot
	for z in [11.6, 15.2]:
		GKArch.arch(g, Vector3(x2, 0.7, z), n, 1.25, 2.7, { "bars": 4, "reveal": "plaster_white", "depth": 0.35 })
	GKArch.arch(g, Vector3(x2, 0.0, 19.0), n, 1.5, 3.0, { "door": "wood_door", "reveal": "plaster_white", "depth": 0.3 })
	# L2b: the taller block behind, three storeys, beam ends under the parapet
	GKArch.block(g, a, "plaster_white", Vector3(x2 - 8.0, 6.0, 9.6), Vector3(x2 - 1.6, 10.2, 18.0), 0.04)
	for z in [11.0, 13.5, 16.0]:
		GKArch.window(g, Vector3(x2 - 1.6, 8.0, z), n, 0.6, 0.8, { "sill_role": "plaster_white", "depth": 0.2 })
	var bz := 10.0
	while bz < 17.8:
		g.box("wood_old", Vector3(x2 - 1.45, 9.65, bz), Vector3(0.36, 0.14, 0.14), 0.02)
		bz += 0.8
	g.box("plaster_white", Vector3(x2 - 1.0, 6.15, 15.0), Vector3(1.2, 0.3, 12.0), 0.03)
	# L3: down to the far end, two storeys with a buttress
	GKArch.block(g, a, "plaster_white", Vector3(xl - 9.0, 0, 21.0), Vector3(xl, 7.6, z1 - 12.0), 0.04)
	GKArch.block(g, a, "plaster_white", Vector3(xl - 0.1, 0, 27.0), Vector3(xl + 0.45, 3.2, 28.2), 0.08)
	for z in [24.0, 31.0, 35.5]:
		GKArch.window(g, Vector3(xl, 5.2, z), n, 0.7, 0.9, { "shutters": "wood_door", "sill_role": "plaster_white", "shutter_open": 0.1 })
	GKArch.window(g, Vector3(xl, 2.0, 33.0), n, 0.9, 1.1, { "bars": 4, "sill_role": "plaster_white" })
	GKArch.arch(g, Vector3(xl, 0.0, 30.0), n, 1.3, 2.6, { "door": "wood_door", "reveal": "plaster_white" })
	# L4: the side street, gated off (out of bounds), and the last block
	GKArch.block(g, a, "plaster_white", Vector3(xl - 9.0, 0, z1 - 12.0 + 6.0), Vector3(xl, 6.5, z1 + 2.0), 0.04)
	GKArch.block(g, a, "sandstone", Vector3(xl - 6.0, 0, z1 - 12.0), Vector3(xl - 5.0, 6.0, z1 - 6.0))
	GKArch.door(g, Vector3(xl - 5.0, 0, z1 - 9.0), n, 3.0, 3.4, "wood_door")
	for z in [z1 - 4.0]:
		GKArch.window(g, Vector3(xl, 4.6, z), n, 0.7, 0.9, { "shutters": "wood_door", "sill_role": "plaster_white" })


func _lantern(g: GKMesh, at: Vector3, n: Vector3) -> void:
	g.push(Transform3D(GKArch.face_basis(n), at))
	g.box("iron_dark", Vector3(0, 0, 0.03), Vector3(0.16, 0.3, 0.06), 0.01)
	g.tube("iron_dark", [Vector3(0, 0.05, 0.05), Vector3(0, 0.12, 0.35), Vector3(0, 0.05, 0.62)], 0.018, 6)
	g.cyl("iron_dark", Vector3(0, 0.05, 0.62), Vector3(0, -0.12, 0.62), 0.01, 6)
	g.box("iron_dark", Vector3(0, -0.2, 0.62), Vector3(0.2, 0.04, 0.2), 0.01)
	g.box("window_dark", Vector3(0, -0.36, 0.62), Vector3(0.17, 0.28, 0.17))
	g.box("iron_dark", Vector3(0, -0.52, 0.62), Vector3(0.14, 0.04, 0.14), 0.01)
	g.pop()


## The right side: the tall ochre wall with the sign, the awning, cables.
func _right(g: GKMesh, a: GKAsset, xr: float, z0: float, z1: float, p: Dictionary) -> void:
	var n := Vector3.LEFT
	GKArch.block(g, a, "plaster_white", Vector3(xr, 0, z0), Vector3(xr + 9.0, 9.0, 20.0), 0.04)
	g.box("plaster_white", Vector3(xr + 0.12, 9.12, (z0 + 20.0) * 0.5), Vector3(0.36, 0.25, 28.0 - 0.1), 0.03)
	_skirt(g, xr, z0, z1)
	# a bundle of cables down the wall from the roof, and a junction box
	for k in 3:
		var cz := 5.9 + k * 0.07
		GKArch.cable(g, Vector3(xr - 0.06 - k * 0.02, 9.0, cz), Vector3(xr - 0.06 - k * 0.02, 0.0, cz + 0.3), 0.0, 0.016)
	g.box("iron_dark", Vector3(xr - 0.08, 1.6, 6.15), Vector3(0.16, 0.5, 0.36), 0.01)
	for z in [-4.5, 2.5, 9.5, 15.5]:
		GKArch.window(g, Vector3(xr, 6.2, z), n, 0.8, 1.1, { "shutters": "wood_door", "sill_role": "plaster_ochre", "shutter_open": 0.15 })
	GKArch.window(g, Vector3(xr, 2.0, -2.0), n, 0.7, 0.9, { "bars": 3, "sill_role": "plaster_ochre" })
	if p.sign:
		_sign(g, Vector3(xr, 2.45, 3.4), n)
	if p.awning:
		for wz in [10.6, 12.6]:
			GKArch.window(g, Vector3(xr, 2.15 + float(p.cat_h if p.catwalk else 0.0) * 0.0, wz), n, 1.2, 1.5, { "frame": "wood_door", "sill_role": "plaster_ochre", "shutters": "wood_door", "shutter_open": 0.9 })
		_awning(g, Vector3(xr, 3.9, 11.6), n, 5.6)
	# a wall cable with brackets, sagging between them
	var prev := Vector3(xr - 0.08, 4.6, z0)
	var z := z0 + 4.0
	while z <= 20.0:
		var q := Vector3(xr - 0.08, 4.6, z)
		GKArch.cable(g, prev, q, 0.12, 0.014)
		g.box("iron_dark", q + Vector3(0.04, 0, 0), Vector3(0.08, 0.04, 0.04))
		prev = q
		z += 4.0
	# satellite dish on the roof
	for ax in [[xr + 0.5, 8.0], [xr + 0.6, 12.5], [xr + 0.4, 16.0]]:
		g.cyl("iron_dark", Vector3(ax[0], 9.0, ax[1]), Vector3(ax[0], 10.8, ax[1]), 0.02, 6)        # antenna masts
		g.cyl("iron_dark", Vector3(ax[0] - 0.3, 10.5, ax[1]), Vector3(ax[0] + 0.3, 10.5, ax[1]), 0.012, 4)
	g.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-120.0)) * Basis(Vector3.RIGHT, deg_to_rad(-25.0)), Vector3(xr + 0.7, 9.6, 5.0)))
	g.lathe("hvac_metal", Vector3(0, 0, 0), Vector3(0, 0, 0.18), [Vector2(0, 0.42), Vector2(0.09, 0.38), Vector2(0.16, 0.24), Vector2(0.18, 0.02)], 18)
	g.cyl("iron_dark", Vector3(0, 0, 0), Vector3(0, 0, -0.5), 0.02, 6)
	g.pop()
	g.cyl("iron_dark", Vector3(xr + 0.7, 9.2, 5.0), Vector3(xr + 0.7, 9.8, 5.0), 0.03, 6)
	# R2 / R3 on to the far end: white, lower, with a stair door up to the walkway
	GKArch.block(g, a, "plaster_white", Vector3(xr, 0, 20.0), Vector3(xr + 9.0, 7.4, z1 + 2.0), 0.04)
	for z2 in [23.0, 27.0]:
		GKArch.window(g, Vector3(xr, 5.2, z2), n, 0.7, 0.9, { "shutters": "wood_door", "sill_role": "plaster_white", "shutter_open": 0.4 })
	GKArch.door(g, Vector3(xr, float(p.cat_h) if p.catwalk else 0.0, 25.0), n, 1.3, 2.3, "wood_door", false)


## The ochre lower coat along the right side: proud of the whitewash by a
## few millimetres, its top edge ragged where the paint has flaked.
func _skirt(g: GKMesh, xr: float, z0: float, z1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var top := PackedVector2Array()
	var z := z1
	while z > z0:
		var y := 2.35 + 0.18 * sin(z * 0.7) + rng.randf_range(-0.14, 0.14)
		if rng.randf() < 0.15:
			y -= rng.randf_range(0.2, 0.55)                      # a deep flake
		top.append(Vector2(z, y))
		z -= rng.randf_range(0.25, 0.6)
	top.append(Vector2(z0, 2.3))
	var o := PackedVector2Array([Vector2(z0, 0.0), Vector2(z1, 0.0)])
	o.append_array(top)
	g.extrude("plaster_ochre", o, xr - 0.025, xr + 0.01, 0.006)
	# chipped patches in the ochre where the whitewash underneath shows
	var zc := z0 + 1.0
	while zc < z1 - 1.0:
		zc += rng.randf_range(1.5, 4.0)
		var cy := rng.randf_range(0.5, 1.9)
		var pts := PackedVector2Array()
		var rad := rng.randf_range(0.05, 0.16)
		for k in 9:
			var an := TAU * k / 9.0
			pts.append(Vector2(zc + cos(an) * rad * rng.randf_range(0.6, 1.3), cy + sin(an) * rad * 0.7 * rng.randf_range(0.6, 1.3)))
		if not Geometry2D.triangulate_polygon(pts).is_empty():
			g.extrude("plaster_white", pts, xr - 0.03, xr - 0.02, 0.0)


## The sandstone tower at the walkway's end: tall and narrow, coursed stone
## with ochre render patches, slit windows, a broken, stepped top.
func _tower(g: GKMesh, a: GKAsset, xr: float) -> void:
	var x0 := xr - 4.6
	var x1 := xr + 1.6
	var z := TOWER_Z
	var n := Vector3.FORWARD
	GKArch.block(g, a, "sandstone_render", Vector3(x0, 0, z), Vector3(x1, 11.2, z + 6.0), 0.03)
	# the broken top: uneven steps of masonry
	var steps := [[x0, x0 + 1.4, 12.4], [x0 + 1.4, x0 + 2.9, 11.9], [x0 + 2.9, x0 + 4.4, 12.8], [x0 + 4.4, x1, 11.6]]
	for st in steps:
		GKArch.block(g, null, "sandstone_render", Vector3(st[0], 11.2, z), Vector3(st[1], st[2], z + 6.0), 0.03, false)
	# where the render has fallen away: bare coursed stone
	g.box("sandstone", Vector3(x0 + 1.2, 6.2, z - 0.01), Vector3(1.8, 2.2, 0.03), 0.01)
	g.box("sandstone", Vector3(x1 - 1.0, 2.0, z - 0.01), Vector3(1.4, 1.4, 0.03), 0.01)
	for y in [5.0, 8.2]:
		GKArch.window(g, Vector3(x0 + 1.6, y, z), n, 0.45, 0.85, { "sill_role": "sandstone_trim", "lintel": "sandstone_trim", "depth": 0.3 })
	GKArch.window(g, Vector3(x1 - 1.6, 9.6, z), n, 0.45, 0.85, { "sill_role": "sandstone_trim", "lintel": "sandstone_trim", "depth": 0.3 })
	GKArch.window(g, Vector3(x1 - 1.4, 4.0, z), n, 0.7, 0.9, { "bars": 3, "sill_role": "sandstone_trim", "depth": 0.3 })
	# the back face, seen from the far end
	var nb := Vector3.BACK
	g.box("sandstone", Vector3(x0 + 1.6, 4.0, z + 6.01), Vector3(1.6, 2.6, 0.03), 0.01)
	for y in [3.4, 6.6, 9.8]:
		GKArch.window(g, Vector3(x1 - 1.8, y, z + 6.0), nb, 0.45, 0.85, { "sill_role": "sandstone_trim", "lintel": "sandstone_trim" })
	GKArch.window(g, Vector3(x0 + 1.4, 8.4, z + 6.0), nb, 0.45, 0.85, { "sill_role": "sandstone_trim", "lintel": "sandstone_trim" })
	GKArch.door(g, Vector3((x0 + x1) * 0.5, 0, z + 6.0), nb, 1.2, 2.3, "wood_door", false, "sandstone_trim")
	# beam ends
	var bx := x0 + 0.5
	while bx < x1 - 0.3:
		g.box("wood_old", Vector3(bx, 10.6, z - 0.15), Vector3(0.14, 0.14, 0.36), 0.02)
		bx += 0.9


## The blue hotel sign: arrow and name, the white plate with a red A beside.
func _sign(g: GKMesh, at: Vector3, n: Vector3) -> void:
	g.push(Transform3D(GKArch.face_basis(n), at))
	g.box("sign_white", Vector3(-0.5, 0, 0.012), Vector3(3.62, 1.07, 0.02), 0.01)
	g.box("sign_blue", Vector3(0, 0, 0.04), Vector3(2.5, 0.95, 0.06), 0.015)
	g.box("sign_white:#b6dbe0", Vector3(-1.82, 0, 0.04), Vector3(0.95, 0.95, 0.06), 0.015)
	for k in 4:   # fixing screws
		g.cyl("steel", Vector3(-1.15 + (k % 2) * 2.3, -0.38 + (k / 2) * 0.76, 0.07), Vector3(-1.15 + (k % 2) * 2.3, -0.38 + (k / 2) * 0.76, 0.08), 0.02, 6)
	# arrow pointing on down the lane (+x on this face), the A plate nearer the T end
	var arrow := PackedVector2Array([Vector2(1.12, 0.12), Vector2(0.88, 0.36), Vector2(0.88, 0.2), Vector2(0.55, 0.2), Vector2(0.55, 0.04), Vector2(0.88, 0.04), Vector2(0.88, -0.12)])
	g.extrude("sign_white", arrow, 0.07, 0.08, 0.0, Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK))
	g.pop()
	var b := GKArch.face_basis(n)
	GKArch.text(g, "sign_white", "HOTEL", at + b * Vector3(0.62, -0.1, 0.075), n, 0.14)
	GKArch.text(g, "sign_white", "AURORE", at + b * Vector3(0.62, -0.31, 0.075), n, 0.14)
	GKArch.text(g, "sign_white", "فندق اورور", at + b * Vector3(-0.3, 0.2, 0.075), n, 0.2)
	GKArch.text(g, "sign_red", "A", at + b * Vector3(-1.82, -0.02, 0.075), n, 0.52, 0.02)
	# the swoosh through the A
	g.push(Transform3D(b, at + b * Vector3(-1.82, 0.0, 0.0)))
	var sw: Array = []
	for k in 9:
		var t := k / 8.0
		sw.append(Vector3(lerpf(-0.36, 0.38, t), -0.06 + 0.16 * sin(t * PI * 0.9) - 0.05 * t, 0.1))
	g.tube("sign_red", sw, 0.022, 6, true, Vector3.BACK, 0.35)
	g.pop()


func _awning(g: GKMesh, at: Vector3, n: Vector3, w: float) -> void:
	g.push(Transform3D(GKArch.face_basis(n), at))
	var depth := 1.6
	var drop := 0.7
	var slope := Basis(Vector3.RIGHT, atan2(drop, depth))
	var stripes := int(w / 0.3)
	for k in stripes:
		var x := -w * 0.5 + (k + 0.5) * w / stripes
		var role := "canvas_awning" if k % 2 == 0 else "sign_white"
		g.box(role, Vector3(x, -drop * 0.5, depth * 0.5), Vector3(w / stripes, 0.03, sqrt(depth * depth + drop * drop)), 0.0, slope)
		g.box(role, Vector3(x, -drop - 0.12, depth), Vector3(w / stripes, 0.24, 0.02))    # the valance
	for sx in [-1.0, 1.0]:
		g.cyl("iron_dark", Vector3(sx * w * 0.5, 0, 0.02), Vector3(sx * w * 0.5, -drop, depth), 0.018, 6)
		g.cyl("iron_dark", Vector3(sx * w * 0.5, -drop - 0.9, 0.02), Vector3(sx * w * 0.5, -drop, depth), 0.016, 6)
	g.pop()


## The raised walkway along the right wall, its ramp, and the low wall.
func _catwalk(g: GKMesh, a: GKAsset, xr: float, z1: float, h: float) -> void:
	var xw := xr - 2.0                # the low wall's lane-side face
	var zr0 := 6.0
	var zr1 := 17.0
	GKArch.block(g, a, "flagstone", Vector3(xw + 0.3, 0, zr1), Vector3(xr, h, z1))
	# the ramp: a sloped slab, collision as a tilted box
	var run := zr1 - zr0
	var ang := atan2(h, run)
	var ln := sqrt(run * run + h * h)
	var c := Vector3((xw + 0.3 + xr) * 0.5, h * 0.5 - 0.06, (zr0 + zr1) * 0.5)
	var basis := Basis(Vector3.RIGHT, -ang)
	g.box("flagstone", c, Vector3(xr - xw - 0.3, 0.12, ln), 0.0, basis)
	a.add_box_xf(g.xf * Transform3D(basis, c), Vector3(xr - xw - 0.3, 0.12, ln))
	# the low wall: rises with the ramp, then runs level
	# the low wall: from ~6 m ahead of the eye, its top riding 0.45 m over the ramp
	var top := h + 0.16
	var zs := zr0 - 0.8
	var prof := PackedVector2Array([Vector2(zs, 0), Vector2(z1, 0), Vector2(z1, top), Vector2(zr1, top), Vector2(zr0, 0.42), Vector2(zs + 0.3, 0.42), Vector2(zs, 0.36)])
	g.extrude("plaster_white", prof, xw, xw + 0.42, 0.05)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(xw + 0.21, top * 0.5, (zr1 + z1) * 0.5)), Vector3(0.42, top, z1 - zr1))
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, Vector3(xw + 0.21, 0.4, (zs + zr1) * 0.5)), Vector3(0.42, 0.8, zr1 - zs))


## The far end: the sandstone tower and the closed mid doors beside it.
func _far_end(g: GKMesh, a: GKAsset, xl: float, xr: float, z1: float) -> void:
	var n := Vector3.FORWARD          # the faces look back down the lane
	var tx0 := xr - 4.5
	GKArch.block(g, a, "plaster_ochre", Vector3(tx0, 0, z1), Vector3(xr + 3.0, 7.5, z1 + 7.0), 0.03)
	GKArch.arch(g, Vector3(tx0 + 2.3, 0.0, z1), n, 1.4, 2.8, { "door": "wood_door", "reveal": "plaster_ochre" })
	# the mid-doors block
	GKArch.block(g, a, "plaster_white", Vector3(xl - 2.0, 0, z1 + 1.5), Vector3(tx0, 7.0, z1 + 8.0), 0.04)
	GKArch.door(g, Vector3((xl + tx0) * 0.5, 0, z1 + 1.5), n, 2.8, 3.4, "wood_door")
	GKArch.window(g, Vector3((xl + tx0) * 0.5 - 2.5, 5.0, z1 + 1.5), n, 0.7, 0.9, { "shutters": "wood_door", "sill_role": "plaster_white" })
	GKArch.block(g, a, "plaster_white", Vector3(xl - 2.0, 0, z1 - 1.0), Vector3(xl + 0.8, 4.2, z1 + 1.5), 0.04)


## Behind the camera: a closing wall with a doorway (out of bounds).
func _t_end(g: GKMesh, a: GKAsset, xl: float, xr: float, z0: float) -> void:
	GKArch.block(g, a, "plaster_ochre", Vector3(xl - 2.0, 0, z0 - 6.0), Vector3(xr + 2.0, 8.0, z0), 0.04)
	GKArch.door(g, Vector3(xl + 3.0, 0, z0), Vector3.BACK, 2.4, 3.0, "wood_door")
	GKArch.window(g, Vector3(xr - 2.5, 5.5, z0), Vector3.BACK, 0.8, 1.0, { "shutters": "wood_door", "sill_role": "plaster_ochre" })


## The wooden pole, its cross-arm, and the cables to both walls.
func _pole(g: GKMesh, a: GKAsset, xl: float, xr: float) -> void:
	var base := Vector3(-0.7, 0, 8.2)
	var top := base + Vector3(0, 10.4, 0)
	g.tube("wood_pole", [base + Vector3(0, -0.2, 0), base + Vector3(0, 5, 0), top], [0.17, 0.15, 0.12], 10)
	g.box("wood_pole", top + Vector3(0, -0.55, 0), Vector3(2.4, 0.12, 0.12), 0.01)
	var ends := [top + Vector3(-1.05, -0.4, 0), top + Vector3(-0.35, -0.4, 0), top + Vector3(0.35, -0.4, 0), top + Vector3(1.05, -0.4, 0)]
	for e in ends:
		g.cyl("sign_white", e, e + Vector3(0, 0.14, 0), 0.03, 6)
	a.add_box_xf(g.xf * Transform3D(Basis.IDENTITY, base + Vector3(0, 5, 0)), Vector3(0.32, 10.0, 0.32))
	# to the right wall, the left wall, and two running back over the camera
	GKArch.cable(g, ends[3] + Vector3(0, 0.14, 0), Vector3(xr - 0.05, 7.6, 6.0), 0.7)
	GKArch.cable(g, ends[2] + Vector3(0, 0.14, 0), Vector3(xr - 0.05, 7.9, 19.0), 0.6)
	GKArch.cable(g, ends[0] + Vector3(0, 0.14, 0), Vector3(xl + 0.05, 6.6, 8.0), 0.5)
	GKArch.cable(g, ends[1] + Vector3(0, 0.14, 0), Vector3(xr - 0.05, 8.4, -6.0), 1.4)
	GKArch.cable(g, ends[3] + Vector3(0, 0.14, 0), Vector3(xr - 0.05, 8.0, -3.0), 1.2)
	GKArch.cable(g, ends[2] + Vector3(0, 0.14, 0), Vector3(xr - 0.05, 8.8, 1.0), 0.9)
	GKArch.cable(g, ends[3] + Vector3(0, 0.14, 0), Vector3(xr - 0.05, 8.9, 11.0), 0.6)
	GKArch.cable(g, base + Vector3(0.1, 7.5, 0), base + Vector3(2.5, 0.0, -1.0), 0.0, 0.012)   # the stay wire
	g.box("iron_dark", base + Vector3(-0.17, 2.4, 0), Vector3(0.06, 0.5, 0.18), 0.01)        # a junction box


## Rooftops beyond the walls, so the sky line isn't a ruler edge.
func _skyline(g: GKMesh, xl: float, xr: float, z0: float, z1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for side in [-1.0, 1.0]:
		var z := z0
		while z < z1 + 8.0:
			var ln := rng.randf_range(5.0, 10.0)
			var h := rng.randf_range(8.0, 12.5)
			var x0 := (xl - 9.5 - rng.randf_range(0.0, 3.0)) if side < 0.0 else (xr + 9.5)
			var x1 := x0 - 7.0 if side < 0.0 else x0 + 7.0 + rng.randf_range(0.0, 3.0)
			var role := "plaster_white" if rng.randf() < 0.6 else ("sandstone" if rng.randf() < 0.5 else "plaster_ochre")
			GKArch.block(g, null, role, Vector3(minf(x0, x1), 0, z), Vector3(maxf(x0, x1), h, z + ln), 0.04, false)
			z += ln
