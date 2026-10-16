class_name MobaView
extends Node3D
## Draws a MobaSim and drives it: League's locked camera on your champion,
## left-click moves (only), right-click attacks what is under or near the
## cursor (else moves), QWER in the chosen cast mode (moba_aim.gd), D flash,
## F ignite / smite, S stop, in the pit V / C ping your bots (binds and cast
## mode from the champion select's options, G54). Bots play the rest.
## Works full screen or inside a SubViewport (the range).

signal match_over(winner_team: String)

const CAM_PITCH := 47.6          # author 10-16: 15% lower to the ground (was 56)
const RING_FOR := 30.0           # author 10-16: the auto-attack ring shows the first 30 s only
const MobaAim := preload("res://src/tourney/moba/moba_aim.gd")
const CAM_DIST := 21.5
const CAM_FOV := 40.0
const ATK_ANIM := 2.2           # clip playback rate for autos and casts

var sim: MobaSim
var local_id := ""              # the champion this machine controls ("" = watch)
var bots := {}                  # unit id -> MobaBot
var binds := {}
var names := {}                 # team -> player name (HUD)

var _acc := 0.0
var _prev := {}                 # unit id -> Vector2 at the previous tick
var _views := {}                # unit id -> { root, char, bar, kind, pose }
var _shots := {}                # projectile id -> Node3D
var _areas := {}                # area id -> Node3D
var _cam: Camera3D
var _hud: MobaHud
var _bars: Control
var _order := {}                # the local player's pending order
var _rmb := 0                  # the mouse button held (repeats its order), 0 = none
var _rmb_t := 0.0
var _aim                        # MobaAim: the cast modes and the aim indicator
var _pings := {}                # team -> Node3D marker
var _smoke: ColorRect
var _over := false
var _hover_ring: MeshInstance3D
var _range_ring: MeshInstance3D
var _fx: BWVfxCasts             # Black | White's element releases and sparks, dyed per champion

## The element shape each champion's effects borrow, and the dye they wear.
const LOOK_EL := { "merr": "fire", "temu": "dark", "braves": "thunder", "boss": "ice" }
const FX_TINTS := { "fire": Color("#8cff4a"), "dark": Color("#b46cff"), "thunder": Color("#ffb347"),
	"light": Color("#ffe27a"), "water": Color("#9b6bff"), "ice": Color("#ff5a6e"), "wind": Color("#e6edf5") }


func setup(p_sim: MobaSim, p_local: String, p_bots: Dictionary, p_binds: Dictionary, p_names: Dictionary = {}) -> void:
	sim = p_sim
	local_id = p_local
	bots = p_bots
	binds = p_binds
	names = p_names


func _exit_tree() -> void:
	BWVfxCasts.tint_over = {}


func _ready() -> void:
	_build_world()
	_build_hud()
	for u in sim.units:
		_add_unit(u)
		_prev[u.id] = u.pos
	_place_camera(true)


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#16211d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8ea6c2")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true                   # the far scenery melts into the backdrop
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#1c2a26")
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 62.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.86
	env.adjustment_contrast = 1.1
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -30, 0)
	sun.light_color = Color("#ffe0b8")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	if sim.mode == "pit":
		_build_pit()
	else:
		_build_lane()
	_hover_ring = _ring(0.9, Color(1, 0.3, 0.3, 0.9))
	_hover_ring.visible = false
	BWVfxCasts.tint_over = FX_TINTS
	_fx = BWVfxCasts.new()
	add_child(_fx)
	var me := sim.unit(local_id)
	if me:                          # your auto-attack range (an enemy's edge inside it is in reach)
		_range_ring = _ring(me.range + me.radius * 0.5, Color(0.78, 0.96, 1.0, 0.75), 0.035)
		_range_ring.layers = 2
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	add_child(_cam)
	_cam.make_current()
	_aim = MobaAim.new()
	_aim.view = self
	add_child(_aim)


## The objective pit: a round paved floor laid in rings, a broken wall of
## mossy rock with a gap at each team's entrance, the Giant's dais, and
## grass and trees outside.
func _build_pit() -> void:
	var R := MobaSim.PIT_R
	_scatter_rng.seed = 11
	_ground({ "disc": R + 0.6, "tile": 1.15 })
	for i in 30:
		var a := i * TAU / 30.0
		if absf(sin(a)) > 0.95:            # the entrances: south blue, north red
			continue
		var rr := R + 1.7 + _scatter_rng.randf_range(-0.2, 0.5)
		if i % 3 == 2:
			_ruin(Vector3(cos(a) * rr, 0, sin(a) * rr), -a + PI / 2.0)
		else:
			_rocks(Vector3(cos(a) * rr, 0, sin(a) * rr), _scatter_rng.randf_range(0.9, 1.3))
		if i % 2 == 0:
			var r2 := R + 4.0 + _scatter_rng.randf_range(0.0, 1.0)
			_rocks(Vector3(cos(a + 0.1) * r2, 0, sin(a + 0.1) * r2), _scatter_rng.randf_range(1.3, 1.9))
	for team in ["blue", "red"]:
		var z := (R + 1.0) * (1.0 if team == "blue" else -1.0)
		var col := MobaLook.team_color(team)
		var rune := _ring(1.4, Color(col.lightened(0.2), 0.8), 0.06)
		rune.position = Vector3(0, 0.03, z)
		for sx in [-1.0, 1.0]:
			_pillar(Vector3(sx * 3.4, 0, z * 1.08), col)
	_foliage(func(p: Vector2) -> bool: return p.length() > R + 4.5, 70, 34.0)
	# the dais and its glow, where the Giant stands (G54: off centre)
	var bp := Vector3(MobaSim.BOSS_POS.x, 0, MobaSim.BOSS_POS.y)
	_cyl(bp + Vector3(0, 0.12, 0), MobaSim.BOSS_R + 0.9, 0.24, Color("#4a463f"))
	_cyl(bp + Vector3(0, 0.26, 0), MobaSim.BOSS_R + 0.6, 0.06, Color("#5e594f"))
	var rune := _ring(MobaSim.BOSS_R + 0.3, Color(0.62, 0.42, 1.0, 0.9), 0.08)   # the Giant's mark, a violet rune ring
	rune.position = bp + Vector3(0, 0.31, 0)
	var leash := _ring(MobaSim.BOSS_LEASH + MobaSim.BOSS_R, Color(0.75, 0.5, 1.0, 0.35))
	leash.position = bp + Vector3(0, 0.03, 0)
	for r in MobaSim.PIT_ROCKS:              # the rocks: solid, and nobody sees past them
		_rock(Vector3(r.x, 0, r.y), r.z * 2.25, r.z * 2.0 + 0.8)
		for k in 2:
			var a := _scatter_rng.randf() * TAU
			_rock(Vector3(r.x, 0, r.y) + Vector3(cos(a), 0, sin(a)) * r.z * 0.8, r.z * 0.9, r.z * 0.9)


## The lane: worn flagstones with moss at the edges, banks of mossy rock
## along both sides, a base pad and tower at each end, and grass, bushes and
## trees out to the fog so there is no edge of the world in view.
func _build_lane() -> void:
	var L := MobaSim.HALF_LEN
	var W := MobaSim.HALF_W
	_scatter_rng.seed = 7
	_ground({ "lane": Vector2(L + 3.5, W + 0.5) })
	for side in [-1.0, 1.0]:
		var x := -L - 5.0 + _scatter_rng.randf_range(0.0, 2.0)
		var k := 0
		while x < L + 5.0:                   # the banks: rock clusters, bushes and ruins in turn
			var z: float = side * (W + 1.6 + _scatter_rng.randf_range(0.0, 1.2))
			match k % 4:
				0, 2: _rocks(Vector3(x, 0, z), _scatter_rng.randf_range(0.9, 1.4))
				1:
					if _scatter_rng.randf() < 0.45:
						_tree(Vector3(x, 0, z + side * 1.2), _scatter_rng.randf_range(1.0, 1.4))
					else:
						_bush(Vector3(x, 0, z), _scatter_rng.randf_range(0.8, 1.2))
				3:
					if _scatter_rng.randf() < 0.5:
						_ruin(Vector3(x, 0, z + side * 0.4), _scatter_rng.randf_range(-0.3, 0.3))
					else:
						_pillar(Vector3(x, 0, side * (W + 0.9)), Color("#9a958a"))
			x += _scatter_rng.randf_range(2.2, 3.6)
			k += 1
		x = -L - 3.0
		while x < L + 3.0:                   # a second, taller row behind
			_rocks(Vector3(x, 0, side * (W + 4.2 + _scatter_rng.randf_range(0.0, 1.5))), _scatter_rng.randf_range(1.2, 1.9))
			x += _scatter_rng.randf_range(3.0, 5.0)
	_foliage(func(p: Vector2) -> bool: return absf(p.y) > W + 3.4 or absf(p.x) > L + 5.0, 140, 46.0)
	for team in ["blue", "red"]:
		var x := -L - 1.0 if team == "blue" else L + 1.0
		var col := MobaLook.team_color(team)
		_cyl(Vector3(x, 0.03, 0), 2.4, 0.06, Color("#4f4c46"))
		var rune := _ring(2.25, Color(col.lightened(0.15), 0.8), 0.06)   # the team's mark on the footing
		rune.position = Vector3(x, 0.07, 0)
		_tower(Vector3(x, 0.06, 0), col)
	for side in [-1.0, 1.0]:                 # a low stone curb: where the lane ends and the jungle starts
		var x := -L - 2.0
		while x < L + 2.0:
			var seg := _scatter_rng.randf_range(1.2, 2.0)
			var b := _box(Vector3(x + seg / 2.0, 0.14, side * (W + 0.45)), Vector3(seg - 0.06, 0.28 + _scatter_rng.randf_range(0.0, 0.1), 0.5),
				Color("#6a665c").darkened(_scatter_rng.randf_range(0.0, 0.2)))
			b.rotation.y = _scatter_rng.randf_range(-0.04, 0.04)
			x += seg


var _scatter_rng := RandomNumberGenerator.new()      # scenery only (never the sim's)


func _ground(params: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/moba_ground.gdshader")
	for k in params:
		m.set_shader_parameter(k, params[k])
	if not params.has("lane"):
		m.set_shader_parameter("lane", Vector2(-1, -1))
	mi.material_override = m
	add_child(mi)


static var _rock_meshes: Array = []     # a few shared boulder shapes, built once
var _rock_mat: ShaderMaterial


## Boulders: a sphere pushed in and out by 3D noise (moba_rock.gdshader
## mosses whatever faces the sky).
static func _rock_mesh(k: int) -> Mesh:
	if _rock_meshes.is_empty():
		var nz := FastNoiseLite.new()
		nz.frequency = 1.0
		for v in 5:
			nz.seed = 31 + v * 7
			var sm := SphereMesh.new()
			sm.radial_segments = 11
			sm.rings = 7
			sm.radius = 0.5
			sm.height = 1.0
			var arr := sm.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in verts.size():
				var d := verts[i].normalized() if verts[i].length() > 0.001 else Vector3.UP
				st.add_vertex(verts[i] * (1.0 + 0.42 * nz.get_noise_3dv(d * 1.6)))
			for t in idx:
				st.add_index(t)
			st.generate_normals()
			_rock_meshes.append(st.commit())
	return _rock_meshes[k % _rock_meshes.size()]


## A boulder `w` wide and `h` tall, sunk a little into the ground.
func _rock(at: Vector3, w: float, h: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_mesh(_scatter_rng.randi())
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = load("res://shaders/moba_rock.gdshader")
	mi.material_override = _rock_mat
	mi.set_instance_shader_parameter("shade", _scatter_rng.randf_range(0.75, 1.05))
	mi.position = at + Vector3(0, h * 0.28, 0)
	mi.scale = Vector3(w, h, w * _scatter_rng.randf_range(0.7, 1.15))
	mi.rotation.y = _scatter_rng.randf() * TAU
	mi.rotation.z = _scatter_rng.randf_range(-0.2, 0.2)
	add_child(mi)


## A cluster of two to four boulders of mixed size around `at`.
func _rocks(at: Vector3, s: float) -> void:
	var n := _scatter_rng.randi_range(2, 4)
	for k in n:
		var w := _scatter_rng.randf_range(0.6, 2.0) * s
		var off := Vector3(_scatter_rng.randf_range(-1, 1), 0, _scatter_rng.randf_range(-1, 1)) * s * 0.9
		_rock(at + off, w, w * _scatter_rng.randf_range(0.6, 1.1))


## A broken length of ruined wall: a few stacked blocks, some fallen.
func _ruin(at: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = yaw
	add_child(root)
	var stone := Color("#8f897c")
	var cnt := _scatter_rng.randi_range(2, 4)
	for k in cnt:
		var h := _scatter_rng.randi_range(1, 3)
		for y in h:
			var b := _box(Vector3.ZERO, Vector3(0.95, 0.5, 0.6), stone.darkened(_scatter_rng.randf_range(0.0, 0.25)))
			b.reparent(root, false)
			b.position = Vector3(k * 1.0 - cnt * 0.5, 0.25 + y * 0.5, _scatter_rng.randf_range(-0.05, 0.05))
			b.rotation.y = _scatter_rng.randf_range(-0.08, 0.08)


## A broken stone pillar with a band of `col`.
func _pillar(at: Vector3, col: Color) -> void:
	var h := _scatter_rng.randf_range(1.6, 3.0)
	_cyl(at + Vector3(0, 0.25, 0), 0.6, 0.5, Color("#6f6b62"))
	_cyl(at + Vector3(0, h / 2.0 + 0.5, 0), 0.42, h, Color("#a39d90"))
	_cyl(at + Vector3(0, 1.3, 0), 0.46, 0.18, col.darkened(0.2))


## Trees and bushes wherever `ok(p)` allows, out to `reach` from the centre.
func _foliage(ok: Callable, n: int, reach: float) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 20:
		tries += 1
		var p := Vector2(_scatter_rng.randf_range(-reach, reach), _scatter_rng.randf_range(-reach * 0.7, reach * 0.7))
		if not ok.call(p):
			continue
		placed += 1
		if _scatter_rng.randf() < 0.55:
			_tree(Vector3(p.x, 0, p.y), _scatter_rng.randf_range(0.9, 1.5))
		else:
			_bush(Vector3(p.x, 0, p.y), _scatter_rng.randf_range(0.6, 1.2))


func _tree(at: Vector3, s: float) -> void:
	_cyl(at + Vector3(0, 1.0 * s, 0), 0.22 * s, 2.0 * s, Color("#4a3726"))
	var leaf := Color("#2f5a2a").lerp(Color("#466f2c"), _scatter_rng.randf())
	for k in 4:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 8
		sm.rings = 5
		mi.mesh = sm
		mi.material_override = _mat(leaf.lightened(0.08 * k))
		var a := k * 2.1 + _scatter_rng.randf()
		var spread := 0.6 * s * (1.0 if k > 0 else 0.0)
		mi.position = at + Vector3(cos(a) * spread, (2.3 + (0.5 if k == 0 else 0.0) + 0.25 * k) * s, sin(a) * spread)
		mi.scale = Vector3.ONE * (1.6 - 0.15 * k) * s
		add_child(mi)


func _bush(at: Vector3, s: float) -> void:
	var leaf := Color("#35612b").lerp(Color("#527a33"), _scatter_rng.randf())
	for k in 3:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
		mi.material_override = _mat(leaf.lightened(0.06 * k))
		mi.position = at + Vector3((k - 1) * 0.45 * s, 0.35 * s, _scatter_rng.randf_range(-0.3, 0.3) * s)
		mi.scale = Vector3(1.0, 0.75, 1.0) * s * _scatter_rng.randf_range(0.8, 1.1)
		add_child(mi)


## A team's tower (scenery: the duel has no tower fights), League-shaped: a
## stepped dark-stone footing, a tall tapering shaft bound in metal, a
## crown of buttresses, and a glowing orb in the team colour held aloft.
func _tower(at: Vector3, col: Color) -> void:
	var stone := Color("#56534d")
	var dark := Color("#3a3833")
	var metal := Color("#6e6a5e")
	_cyl(at + Vector3(0, 0.25, 0), 1.5, 0.5, dark)
	_cyl(at + Vector3(0, 0.7, 0), 1.2, 0.4, stone.darkened(0.1))
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = 0.95
	cm.top_radius = 0.6
	cm.height = 4.2
	cm.radial_segments = 8
	shaft.mesh = cm
	shaft.material_override = _mat(stone)
	shaft.position = at + Vector3(0, 3.0, 0)
	add_child(shaft)
	for y in [1.4, 2.6, 3.8]:
		var r: float = 0.95 - (y - 0.9) / 4.2 * 0.35
		_cyl(at + Vector3(0, y, 0), r + 0.08, 0.16, metal)
		_cyl(at + Vector3(0, y + 0.1, 0), r + 0.09, 0.05, col.darkened(0.25))
	for k in 4:                                # buttresses round the footing
		var a := k * TAU / 4.0 + PI / 4.0
		var b := _box(at + Vector3(cos(a) * 1.0, 1.0, sin(a) * 1.0), Vector3(0.35, 1.6, 0.35), dark)
		b.rotation.y = -a
	_cyl(at + Vector3(0, 5.2, 0), 0.85, 0.3, metal.darkened(0.2))
	for k in 4:                                # the claws that hold the orb
		var a := k * TAU / 4.0
		var c := _box(at + Vector3(cos(a) * 0.62, 5.75, sin(a) * 0.62), Vector3(0.18, 0.9, 0.18), metal)
		c.rotation = Vector3(0, -a, 0.35)
		c.rotate_object_local(Vector3.FORWARD, 0.0)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	orb.mesh = sm
	var om := _mat(col.lightened(0.1), true)
	om.emission_energy_multiplier = 0.9          # keeps its team hue instead of blowing out white
	orb.material_override = om
	orb.position = at + Vector3(0, 6.05, 0)
	add_child(orb)
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.62
	hm.height = 1.24
	halo.mesh = hm
	halo.material_override = _add_mat(Color(col, 0.25))
	halo.position = orb.position
	add_child(halo)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.4
	light.omni_range = 7.0
	light.position = at + Vector3(0, 5.6, 0)
	add_child(light)
	var tw := create_tween().set_loops()
	tw.tween_property(orb, "position:y", at.y + 6.2, 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(orb, "position:y", at.y + 5.95, 1.4).set_trans(Tween.TRANS_SINE)


func _box(at: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = at
	add_child(mi)
	return mi


func _cyl(at: Vector3, r: float, h: float, col: Color, glow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * (0.6 if glow else 1.0)
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = _mat(col, glow)
	mi.position = at
	add_child(mi)
	return mi


func _mat(col: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.4
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _ring(r: float, col: Color, w: float = 0.07) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - w
	tm.outer_radius = r
	tm.rings = 96
	mi.mesh = tm
	var m := _mat(col, true)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.scale = Vector3(1, 0.05, 1)
	add_child(mi)
	return mi


## A flat fan (cone telegraph) pointing along +x, `deg` wide.
func _fan(r: float, deg: float, col: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	var half := deg_to_rad(deg) * 0.5
	for i in n:
		var a0 := -half + 2.0 * half * i / n
		var a1 := -half + 2.0 * half * (i + 1) / n
		st.set_uv(Vector2(0.0, 0.5))
		st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(1.0, float(i + 1) / n))
		st.add_vertex(Vector3(cos(a1) * r, 0, sin(a1) * r))
		st.set_uv(Vector2(1.0, float(i) / n))
		st.add_vertex(Vector3(cos(a0) * r, 0, sin(a0) * r))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _mat(col)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	return mi


func _disc(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	mi.mesh = cm
	var m := _mat(col)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	return mi


# ------------------------------------------------------------------ units

func _add_unit(u: MobaUnit) -> void:
	var root := Node3D.new()
	add_child(root)
	var bu: BWUnit
	match u.kind:
		"champ": bu = MobaLook.champ_unit(u.champ, u.team)
		"minion": bu = MobaLook.minion_unit(u.role, u.team, u.id)
		"boss": bu = MobaLook.boss_unit()
		_: bu = MobaLook.dummy_unit(u.id)
	var ch := BWCharacter.create(bu)
	root.add_child(ch)
	_layer.call_deferred(root, 2)
	if u.kind == "champ":
		var c: Dictionary = MobaChamps.CHAMPS[u.champ]
		MobaLook.tint(ch, Color(str(c.tint)), Color(str(c.hair_hex)))
		if c.has("kit_weapon"):
			# a Gauntlet kit item in place of the Black | White weapon (held on the
			# same socket; the weapon's clips keep driving the body)
			GKBWHold.swap_weapon(ch, GKRegistry.build(str(c.kit_weapon), c.get("kit_params", {})))
		MobaDress.dress(ch, u.champ)             # G55: equipment, gait, cast gestures
	elif u.kind == "minion":
		MobaLook.tint(ch, MobaLook.team_color(u.team))
		root.scale = Vector3.ONE * 0.72
	elif u.kind == "boss":
		MobaLook.tint(ch, MobaLook.BOSS)
		root.scale = Vector3.ONE * 2.3
	else:
		MobaLook.tint(ch, Color("#c9a66b"))
	var ring_col := MobaLook.BOSS if u.kind == "boss" else (MobaHud.HP_SELF if u.id == local_id else (MobaHud.HP_ALLY if _ally(u) else MobaHud.HP_FOE))
	var sel := _disc(u.radius, Color(ring_col, 0.35))
	sel.reparent(root, false)
	sel.position.y = 0.02
	sel.scale = Vector3.ONE / root.scale.x
	var bar := _make_bar(u)
	_views[u.id] = { "root": root, "char": ch, "bar": bar, "kind": u.kind, "pose": "", "cast": u.cast_serial,
		"atk": u.atk_serial, "hit": u.hit_serial, "anim_t": 0.0 }
	ch.pose("idle")


## Put every visual under `n` on render layer `bits` only (units: off the minimap photo).
func _layer(n: Node, bits: int) -> void:
	if not is_instance_valid(n):
		return
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = bits
	for c in n.get_children():
		_layer(c, bits)


## The minimap's background: the map photographed once from straight above,
## turned like your camera, without units (layer 1 only) or fog.
func minimap_photo(px: int, world_span: float) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = world_span
	cam.cull_mask = 1
	cam.far = 200.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#16211d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c8d4d8")
	env.ambient_light_energy = 0.7
	cam.environment = env
	vp.add_child(cam)
	var f := view_forward()
	cam.position = Vector3(0, 80, 0)
	cam.look_at(Vector3.ZERO, Vector3(f.x, 0, f.y))
	cam.current = true
	return vp.get_texture()


func _make_bar(u: MobaUnit) -> MobaHud.Bar:
	var b := MobaHud.Bar.new()
	var col := MobaHud.HP_SELF if u.id == local_id else (MobaLook.BOSS if u.kind == "boss" else (MobaHud.HP_ALLY if _ally(u) else MobaHud.HP_FOE))
	b.setup(u.kind if u.kind in ["champ", "boss"] else "minion", _who(u) if u.kind == "champ" else "", col, u.max_hp)
	_bars.add_child(b)
	return b


func _ally(u: MobaUnit) -> bool:
	var me := sim.unit(local_id)
	return u.team == (me.team if me else "blue")


# ------------------------------------------------------------------- HUD

func _build_hud() -> void:
	_hud = MobaHud.new()
	_hud.setup(self)
	add_child(_hud)
	_bars = _hud.bars
	_smoke = ColorRect.new()
	_smoke.set_anchors_preset(Control.PRESET_FULL_RECT)
	_smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5, 0.55));
	COLOR = vec4(0.03, 0.03, 0.04, amount * smoothstep(0.08, 0.32, d));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_smoke.material = sm
	_smoke.visible = false
	_hud.root.add_child(_smoke)
	_hud.root.move_child(_smoke, _bars.get_index() + 1)


func _feed_line(text: String, col: Color) -> void:
	_hud.feed_line(text, col)


## The key a slot is bound to, as shown on its icon.
func key_label(slot: String) -> String:
	return TourneyUI.key_name(int(binds.get("spell2" if slot in ["ignite", "smite"] else slot, 0)))


## A slot's full cooldown (for the icon's sweep).
func cd_full(u: MobaUnit, slot: String) -> float:
	match slot:
		"flash": return MobaSim.FLASH_CD
		"ignite": return MobaSim.IGNITE_CD
		"smite": return MobaSim.SMITE_CD
	return float(MobaChamps.CHAMPS[u.champ].cd.get(slot, 0.0)) if u.champ != "" else 0.0


func camera() -> Camera3D:
	return _cam


func is_over() -> bool:
	return _over


# ------------------------------------------------------------------ input

func _mouse_world() -> Vector2:
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var from := _cam.project_ray_origin(mp)
	var dir := _cam.project_ray_normal(mp)
	if absf(dir.y) < 0.001:
		return Vector2.ZERO
	var t := -from.y / dir.y
	var p := from + dir * t
	return Vector2(p.x, p.z)


## The enemy under the cursor, judged on screen (generous, like League's).
func _hovered() -> MobaUnit:
	var me := sim.unit(local_id)
	if me == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var best: MobaUnit = null
	var bd := 42.0
	for u in sim.units:
		if u.team == me.team or not u.targetable() or not _views.has(u.id) or not (_views[u.id].root as Node3D).visible:
			continue
		var root: Node3D = _views[u.id].root
		var sp := _cam.unproject_position(root.global_position + Vector3(0, 0.9, 0))
		var d := sp.distance_to(mp)
		if d < bd:
			best = u
			bd = d
	return best


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F1:
		_toggle_tune()
		get_viewport().set_input_as_handled()
		return
	if local_id == "" or _over:
		return
	if ev is InputEventMouseButton and ev.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT]:
		var left: bool = ev.button_index == MOUSE_BUTTON_LEFT
		if ev.pressed and _aim.click(left):    # slow cast: a left click casts, a right click cancels
			get_viewport().set_input_as_handled()
			return
		if ev.pressed:
			_rmb = ev.button_index
			_rmb_t = 0.12
			_click(left)
			get_viewport().set_input_as_handled()
		elif _rmb == ev.button_index:
			_rmb = 0
		return
	if ev is InputEventKey and not ev.echo:
		var slot := ""
		for k in ["q", "w", "e", "r"]:
			if int(binds.get(k, -1)) == ev.keycode:
				slot = k
		if slot != "":                          # Q W E R: the cast mode decides (moba_aim.gd)
			if _aim.key(slot, ev.pressed):
				get_viewport().set_input_as_handled()
			return
		if not ev.pressed:
			return
		if int(binds.get("flash", -1)) == ev.keycode:
			slot = "flash"
		elif int(binds.get("spell2", -1)) == ev.keycode:
			slot = "smite" if sim.mode == "pit" else "ignite"
		if slot != "":                          # summoner spells: always at once
			var h := _hovered()
			_order["cast"] = { "slot": slot, "aim": _mouse_world(), "target": h.id if h else "" }
			get_viewport().set_input_as_handled()
		elif sim.mode == "pit" and ev.keycode in [int(binds.get("ping_go", KEY_V)), int(binds.get("ping_hold", KEY_C))]:
			var go: bool = ev.keycode == int(binds.get("ping_go", KEY_V))
			_order["ping"] = { "kind": "go" if go else "hold", "at": _mouse_world() }
			get_viewport().set_input_as_handled()
		elif ev.keycode == KEY_ESCAPE and _aim.armed != "":
			_aim.cancel()
			get_viewport().set_input_as_handled()
		elif int(binds.get("stop", -1)) == ev.keycode:
			_order["stop"] = true
			get_viewport().set_input_as_handled()


## F1: the live feel-numbers panel (MobaTunePanel).
var _tune_panel: MobaTunePanel


func _toggle_tune() -> void:
	if _tune_panel:
		_tune_panel.queue_free()
		_tune_panel = null
		return
	_tune_panel = MobaTunePanel.new()
	_tune_panel.sim = sim
	add_child(_tune_panel)


## Left click: move there, nothing else (kite with it). Right click: attack
## the enemy under the cursor or, failing that, the one nearest it within
## 2.5 units; with nobody there it moves too (author 10-16, G54).
func _click(left: bool, quiet: bool = false) -> void:
	var t: MobaUnit = null if left else _attack_target()
	if t:
		_order["attack"] = t.id
		_order.erase("move")
	else:
		_order["move"] = _mouse_world()
		_order.erase("attack")
		if not quiet:
			_click_fx(_mouse_world())


func _attack_target() -> MobaUnit:
	var h := _hovered()
	if h:
		return h
	var me := sim.unit(local_id)
	if me == null:
		return null
	var mw := _mouse_world()
	var best: MobaUnit = null
	var bd := 2.5
	for u in sim.units:
		if u.team == me.team or not u.targetable() or not _views.has(u.id) or not (_views[u.id].root as Node3D).visible:
			continue
		var d: float = u.pos.distance_to(mw) - u.radius
		if d < bd:
			best = u
			bd = d
	return best


func _click_fx(at: Vector2) -> void:
	var r := _ring(0.45, Color(0.4, 1.0, 0.5, 0.9))
	r.position = Vector3(at.x, 0.05, at.y)
	var tw := create_tween()
	tw.tween_property(r, "scale", Vector3(0.2, 0.05, 0.2), 0.3)
	tw.tween_callback(r.queue_free)


# ------------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if _rmb != 0 and local_id != "":           # a held button keeps steering
		_rmb_t -= delta
		if _rmb_t <= 0.0:
			_rmb_t = 0.12
			if not _order.has("attack"):
				_click(_rmb == MOUSE_BUTTON_LEFT, true)
	if not _over:
		_acc += delta
		var guard := 0
		while _acc >= MobaSim.TICK and guard < 6:
			_acc -= MobaSim.TICK
			guard += 1
			_tick()
	var alpha := clampf(_acc / MobaSim.TICK, 0.0, 1.0)
	_draw(alpha, delta)


func _tick() -> void:
	for u in sim.units:
		_prev[u.id] = u.pos
	var orders := {}
	for id in bots:
		var u := sim.unit(id)
		if u:
			orders[id] = (bots[id] as MobaBot).think(sim, u)
	if local_id != "":
		orders[local_id] = _order
		_order = {}
	var evs := sim.step(orders)
	for e in evs:
		_on_event(e)


func _on_event(e: Dictionary) -> void:
	match str(e.type):
		"wave":
			for u in sim.units:
				if not _views.has(u.id):
					_add_unit(u)
					_prev[u.id] = u.pos
		"hit":
			var u := sim.unit(str(e.unit))
			if u and _views.has(u.id) and float(e.amount) >= 5.0:
				_float_num(u, int(round(float(e.amount))), str(e.kind))
				_hit_fx(u, sim.unit(str(e.get("src", ""))), str(e.kind))
		"death":
			var u := sim.unit(str(e.unit))
			if u and u.kind == "minion" and str(e.by) == local_id:
				_hud.cs += 1
			if u and u.kind == "champ":
				u.set_meta("deaths", int(u.get_meta("deaths", 0)) + 1)
				var by := sim.unit(str(e.by))
				var kn := ""
				if by:
					kn = _who(by) if by.kind == "champ" else ("The Giant" if by.kind == "boss" else "Minions")
				_hud.feed_kill(kn, MobaLook.BOSS if by and by.kind == "boss" else MobaLook.team_color(by.team if by else ""),
					_who(u), MobaLook.team_color(u.team))
				BWMusic.sting("pick")
		"area":
			for a in sim.areas:
				if int(a.id) == int(e.id):
					_areas[int(e.id)] = _area_mesh(a)
		"area_end":
			if _areas.has(int(e.id)):
				var n: Node3D = _areas[int(e.id)]
				if str(e.kind) == "blast":
					var look := str(n.get_meta("look", ""))
					var el := "water" if look == "boss_nova" else _el_of(look)
					_fx.release_at(el, Vector3(e.pos.x, 0, e.pos.y), minf(float(n.get_meta("r", 2.5)) / 2.2, 1.4))
				n.queue_free()
				_areas.erase(int(e.id))
		"burst":
			var look := str(e.look)
			_fx.release_at(_el_of(look), Vector3(e.pos.x, 0, e.pos.y), 1.1 if look == "braves_shell" else 0.9)
		"flash":
			var u := sim.unit(str(e.unit))
			if u:
				_fx.release_at("light", Vector3(u.pos.x, 0, u.pos.y), 0.5)
		"smite":
			var b := sim.boss()
			if b:
				_fx.release_at("light", Vector3(b.pos.x, 0, b.pos.y), 1.5)
				var u := sim.unit(str(e.unit))
				if u:
					_feed_line("%s smites (%d)" % [u.name, int(MobaSim.SMITE_DMG)], MobaLook.team_color(u.team))
		"ping":
			_ping_fx(str(e.team))
		"win":
			_over = true
			var t := str(e.team)
			if sim.mode == "pit":
				var by := sim.unit(str(e.get("by", "")))
				_hud.center("Team %s takes the Giant%s" % [str(names.get(t, t.capitalize())),
					("\n" + by.name + (" smites it" if str(e.get("how", "")) == "smite" else " lands the last hit")) if by else ""],
					MobaLook.team_color(t).lightened(0.3))
			else:
				_hud.center("%s wins" % str(names.get(t, t.capitalize())), MobaLook.team_color(t).lightened(0.3))
			BWMusic.sting("level_up")
			for id in _views:
				var u := sim.unit(id)
				if u and u.kind == "champ" and u.team == t and u.alive:
					(_views[id].char as BWCharacter).pose("cheer")
			TourneyUI.after(self, 3.0, func(): match_over.emit(t))


## A ping in the pit (G54): a beam and a ring where it points, for the
## pinging side only (the other side never sees it), and a feed line.
func _ping_fx(team: String) -> void:
	var me := sim.unit(local_id)
	if me == null or me.team != team or not sim.pings.has(team):
		return
	var pg: Dictionary = sim.pings[team]
	var go := str(pg.kind) == "go"
	var col := Color("#ff6a3d") if go else Color("#4fb0ff")
	if _pings.has(team) and is_instance_valid(_pings[team]):
		(_pings[team] as Node3D).queue_free()
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pg.pos.x, 0.0, pg.pos.y)
	var ring := _ring(1.2, Color(col, 0.95), 0.12)
	ring.reparent(root, false)
	ring.position = Vector3(0, 0.06, 0)
	var beam := _cyl(Vector3(0, 1.6, 0), 0.08, 3.2, Color(col, 0.7), true)
	beam.reparent(root, false)
	beam.position = Vector3(0, 1.6, 0)
	var l := Label3D.new()
	l.text = "GO IN" if go else "HOLD"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.outline_size = 12
	l.modulate = col.lightened(0.3)
	l.position = Vector3(0, 3.6, 0)
	root.add_child(l)
	_layer(root, 2)
	_pings[team] = root
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(1.5, 0.05, 1.5), 0.25)
	tw.tween_property(ring, "scale", Vector3(1.0, 0.05, 1.0), 0.25)
	tw.tween_interval(MobaSim.PING_TIME - 1.5)
	tw.tween_property(root, "scale", Vector3(0.01, 0.01, 0.01), 1.0)
	tw.tween_callback(root.queue_free)
	var by := sim.unit(str(pg.by))
	_feed_line("%s: %s" % [_who(by) if by else "You", "go in!" if go else "hold here!"], col)


## A champion's display name: the player's name in the duel, its own label in the pit.
func _who(u: MobaUnit) -> String:
	return str(names.get(u.id, names.get(u.team, u.name) if sim.mode == "duel" else u.name))


func _proj(id: int) -> Dictionary:
	for p in sim.projectiles:
		if int(p.id) == id:
			return p
	return {}


func _look_color(look: String, team: String) -> Color:
	if look.begins_with("merr"):
		return Color("#9cff57")
	if look.begins_with("temu"):
		return Color("#c084ff")
	if look.begins_with("braves"):
		return Color("#ffb347")
	if look.begins_with("boss"):
		return Color("#ff4f6d")
	return MobaLook.team_color(team).lightened(0.3)


## Projectiles follow the sim's list: new ones get a mesh, gone ones burst
## where they were. Autos and spells alike (autos raise no "shot" event).
func _sync_shots(delta: float) -> void:
	var live := {}
	for p in sim.projectiles:
		var pid := int(p.id)
		live[pid] = true
		if not _shots.has(pid):
			_shots[pid] = _shot_mesh(str(p.get("look", "")), p)
		var n: Node3D = _shots[pid]
		var to := Vector3(p.pos.x, 1.0, p.pos.y)
		var from := n.position
		n.position = from.lerp(to, minf(1.0, delta * 30.0))
		var d := n.position - from
		if d.length() > 0.001:
			n.look_at(n.position + d, Vector3.UP)
		var trail: Array = n.get_meta("trail")
		var hist: Array = n.get_meta("hist")
		hist.push_front(n.position)
		if hist.size() > trail.size() * 2 + 1:
			hist.pop_back()
		for k in trail.size():
			var g: Node3D = trail[k]
			g.global_position = hist[mini(k * 2 + 1, hist.size() - 1)]
	for pid in _shots.keys():
		if not live.has(pid):
			var n: Node3D = _shots[pid]
			_impact(n.position, str(n.get_meta("el", "wind")), float(n.get_meta("r", 0.16)))
			for g in n.get_meta("trail"):
				(g as Node3D).queue_free()
			n.queue_free()
			_shots.erase(pid)


func _el_of(look: String) -> String:
	for k in LOOK_EL:
		if look.begins_with(k):
			return LOOK_EL[k]
	return "wind"


## Temu's slingshot shot: the white felt ball itself, tumbling, a faint
## violet trail (it reads as a thing thrown, not a bolt of magic).
func _stone_mesh(p: Dictionary, col: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(p.pos.x, 1.0, p.pos.y)
	root.set_meta("el", "dark")
	root.set_meta("r", 0.16)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	ball.mesh = sm
	ball.material_override = GKMaterials.get_material("felt_white")
	root.add_child(ball)
	var tw := create_tween().set_loops()
	tw.tween_property(ball, "rotation:x", TAU, 0.35).from(0.0)
	var trail: Array = []
	for k in 4:
		var g := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.12 - 0.022 * k
		gm.height = gm.radius * 2.0
		g.mesh = gm
		g.material_override = _add_mat(Color(col, 0.32 - 0.07 * k))
		add_child(g)
		g.global_position = root.position
		trail.append(g)
	root.set_meta("trail", trail)
	root.set_meta("hist", [])
	return root


## A glowing bolt: a bright core, a soft additive halo, and a fading trail.
func _shot_mesh(look: String, p: Dictionary) -> Node3D:
	var owner := sim.unit(str(p.owner))
	if look == "" and owner:
		look = owner.champ
	var col := _look_color(look, str(p.team))
	var r := 0.22
	if look == "temu" and owner and owner.kind == "champ":
		return _stone_mesh(p, col)
	match look:
		"merr_spit": r = 0.42
		"merr_phlegm": r = 0.48
		"braves_shell": r = 0.46
		"braves_pellet": r = 0.15
		"temu_dart": r = 0.26
	if owner and owner.kind == "minion":
		r = 0.11
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(p.pos.x, 1.0, p.pos.y)
	root.set_meta("el", _el_of(look) if owner == null or owner.kind != "minion" else "wind")
	root.set_meta("r", r)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	core.mesh = sm
	var cm := _mat(col.lerp(Color.WHITE, 0.55), true)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = cm
	core.scale = Vector3(1, 1, 1.6)             # stretched along its flight
	root.add_child(core)
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = r * 2.2
	hm.height = r * 4.4
	halo.mesh = hm
	halo.material_override = _add_mat(Color(col, 0.35))
	root.add_child(halo)
	var trail: Array = []
	for k in 5:
		var g := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = r * (0.85 - 0.14 * k)
		gm.height = gm.radius * 2.0
		gm.radial_segments = 10
		gm.rings = 6
		g.mesh = gm
		g.material_override = _add_mat(Color(col, 0.5 - 0.09 * k))
		add_child(g)
		g.global_position = root.position
		trail.append(g)
	root.set_meta("trail", trail)
	root.set_meta("hist", [])
	return root


func _add_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = false
	return m


## Where a bolt lands: a star flash and a spray of sparks in its dye.
func _impact(at: Vector3, el: String, r: float) -> void:
	var s := clampf(r / 0.16, 0.6, 2.4)
	_fx._quad(8, el, at, Vector2(0.9, 0.9) * s, 0.2)
	_fx._burst_parts(at, el, int(4 + 3 * s), 0.0, { "up": 2.0, "spread": 2.6 * s, "g": 7.0, "shape": 2, "life": 0.32, "s0": 0.09 * s })


## A hit landing on a unit: melee blows and spells get a flash on the body
## (ranged autos already burst where the bolt lands).
func _hit_fx(u: MobaUnit, src: MobaUnit, kind: String) -> void:
	if not _views.has(u.id):
		return
	var at := (_views[u.id].root as Node3D).position + Vector3(0, 1.0 * (_views[u.id].root as Node3D).scale.y, 0)
	if kind == "auto" and src and src.proj_speed <= 0.0:
		_impact(at, "wind" if src.kind == "minion" else _el_of(src.champ), 0.12)
	elif kind not in ["auto", "poison", "blaze", "ignite"] and src:
		_fx._quad(8, _el_of(src.champ if src.kind == "champ" else "boss"), at, Vector2(1.3, 1.3), 0.22)


func _area_mesh(a: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(a.pos.x, 0.03, a.pos.y)
	root.set_meta("look", str(a.get("look", "")))
	root.set_meta("r", float(a.get("r", 2.5)))
	var col := _look_color(str(a.get("look", "")), str(a.team))
	match str(a.kind):
		"blast":
			var tm := ShaderMaterial.new()
			tm.shader = load("res://shaders/moba_telegraph.gdshader")
			tm.set_shader_parameter("col", Color(col, 0.95))
			var mi: MeshInstance3D
			if a.has("cone"):
				var dir: Vector2 = a.cone
				mi = _fan(float(a.r), float(a.cone_deg), col)
				mi.rotation.y = -dir.angle()
				tm.set_shader_parameter("cone", true)
			else:
				mi = MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(float(a.r), float(a.r)) * 2.0
				mi.mesh = pm
				add_child(mi)
			mi.material_override = tm
			mi.reparent(root, false)
			var tw := create_tween()
			tw.tween_method(func(v: float): tm.set_shader_parameter("progress", v), 0.0, 1.0, float(a.delay))
		"smoke":
			for i in 9:
				var mi := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 1.0
				sm.height = 1.4
				mi.mesh = sm
				mi.material_override = _mat(Color(0.25, 0.25, 0.28, 0.55))
				var ang := i * TAU / 8.0
				var rr := 0.0 if i == 8 else float(a.r) * 0.6
				mi.position = Vector3(cos(ang) * rr, 0.6, sin(ang) * rr)
				mi.scale = Vector3.ONE * (1.3 if i == 8 else 1.0)
				root.add_child(mi)
		"mine":
			var me := sim.unit(local_id)
			root.visible = me != null and me.team == str(a.team) or local_id == ""
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.3
			mi.mesh = sm
			mi.material_override = _mat(col, true)
			mi.position.y = 0.12
			root.add_child(mi)
			var ring := _ring(float(a.trigger), Color(col, 0.4))
			ring.reparent(root, false)
	return root


const NUM_MERGE_MS := 250          # hits of one kind on one unit this close together show as one number
const NUM_LIVE := 3                 # at most this many numbers over a unit at once


func _float_num(u: MobaUnit, n: int, kind: String) -> void:
	var col := Color.WHITE
	if kind in ["poison", "nuke"]:
		col = Color("#c084ff")                  # damage over time: its own colour
	elif kind in ["blaze", "ignite"]:
		col = Color("#ff9a3c")
	elif kind in ["smite"]:
		col = Color("#fff4d0")                  # true damage
	elif kind == "auto":
		col = Color("#ffcf8a")                  # physical, League's orange-white
	else:
		col = Color("#8fb8ff")                  # spells, League's magic blue
	var v: Dictionary = _views[u.id]
	var now := Time.get_ticks_msec()
	var nums: Array = v.get("nums", [])
	nums = nums.filter(func(r: Dictionary) -> bool: return is_instance_valid(r.label))
	v["nums"] = nums
	for r in nums:                           # a burst sums into the number already rising
		if r.kind == kind and now - int(r.at) < NUM_MERGE_MS:
			r.n = int(r.n) + n
			(r.label as Label).text = str(r.n)
			return
	if nums.size() >= NUM_LIVE:
		(nums[0].label as Label).queue_free()
		nums.pop_front()
	var l := Label.new()
	l.text = str(n)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 22 if u.kind in ["champ", "boss"] else 15)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(90, 30)
	_bars.add_child(l)
	nums.append({ "label": l, "kind": kind, "n": n, "at": now })
	# League's spray: each new number takes the next lane of a small fan
	# (centre, left, right...), starting above the name and HP bar
	var k := int(v.get("num_k", 0))
	v["num_k"] = k + 1
	var lane: float = [0.0, -58.0, 58.0][k % 3]
	var root: Node3D = v.root
	var sp := _cam.unproject_position(root.global_position + Vector3(0, 2.45 * root.scale.y, 0)) + Vector2(-45, -66)
	l.position = sp + Vector2(lane * 0.5, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", sp + Vector2(lane * 1.4, -40), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


# ------------------------------------------------------------------- draw

func _draw(alpha: float, delta: float) -> void:
	var me := sim.unit(local_id)
	for id in _views.keys():
		var v: Dictionary = _views[id]
		var u := sim.unit(id)
		if u == null:
			(v.root as Node3D).queue_free()
			(v.bar as Control).queue_free()
			_views.erase(id)
			continue
		var root: Node3D = v.root
		var ch: BWCharacter = v.char
		var p: Vector2 = (_prev.get(id, u.pos) as Vector2).lerp(u.pos, alpha)
		root.position = Vector3(p.x, 0.0, p.y)
		root.rotation.y = lerp_angle(root.rotation.y, atan2(u.facing.x, u.facing.y), minf(1.0, delta * MobaTune.value("turn_rate")))
		var hidden := u.stealth and (me == null or u.team != me.team)
		if sim.mode == "pit" and me and u.team != me.team and u.kind == "champ" and not sim.team_sees(me.team, u):
			hidden = true                        # G54: behind a rock from every one of your side
		var blind := me != null and me.blind_t > 0.0 and u.team != me.team and u.pos.distance_to(me.pos) > MobaSim.SMOKE_SIGHT
		root.visible = u.alive and not hidden and not blind or (u.kind == "champ" and not u.alive and v.pose == "fall" and float(v.anim_t) < 1.6)
		if u.stealth and not hidden:
			if not v.get("stealth_drawn", false):
				MobaDress.ghost(ch, true)            # G55: hidden Temu, as his side sees him: 75% transparent
			v["stealth_drawn"] = true
		elif v.get("stealth_drawn", false):
			v["stealth_drawn"] = false
			MobaDress.ghost(ch, false)
		v.anim_t = float(v.anim_t) + delta
		_pose(u, v)
		var bar: MobaHud.Bar = v.bar
		bar.visible = root.visible and u.alive
		if bar.visible:
			var sp := _cam.unproject_position(root.global_position + Vector3(0, 2.45 * root.scale.y, 0))
			bar.position = (sp - bar.anchor_offset()).round()
			bar.level = u.kills
			bar.set_hp(clampf(u.hp / u.max_hp, 0.0, 1.0), delta)
	_sync_shots(delta)
	if _range_ring and me:
		var mp: Vector3 = (_views[me.id].root as Node3D).position if _views.has(me.id) else Vector3(me.pos.x, 0, me.pos.y)
		_range_ring.position = Vector3(mp.x, 0.04, mp.z)
		_range_ring.visible = me.alive and sim.time < RING_FOR
	var h := _hovered() if local_id != "" else null
	_hover_ring.visible = h != null
	if h:
		_hover_ring.position = Vector3(h.pos.x, 0.05, h.pos.y)
	_place_camera(false, delta)
	_hud_update(me, delta)


func _pose(u: MobaUnit, v: Dictionary) -> void:
	var ch: BWCharacter = v.char
	if not u.alive:
		if v.pose != "fall":
			v.pose = "fall"
			v.anim_t = 0.0
			ch.anim_speed = 1.0
			ch.pose("fall")
		return
	if u.cast_serial != int(v.cast):
		v.cast = u.cast_serial
		v.pose = "cast"
		v.anim_t = 0.0
		ch.anim_speed = ATK_ANIM
		if u.kind == "champ":
			# G55: the champion's own gesture, its release (f6) on the cast stop's end
			var cu: Variant = u.get("cast_until")       # the cast stop (G54), read defensively
			var cs: Variant = u.get("cast_start")
			var stop := float(cu) - float(cs) if cu != null and cs != null and str(u.get("cast_slot")) != "" else 0.0
			ch.anim_speed = (6.0 / 24.0) / stop if stop > 0.05 else 2.0
			ch.pose(MobaDress.cast_pose(ch, u.champ, u.last_cast))
		else:
			ch.pose("cast" if ch.has_clip("cast") else "strike")
		return
	if u.atk_wind >= 0.0 and v.pose != "windup" and v.pose != "strike":
		v.pose = "windup"
		v.anim_t = 0.0
		ch.anim_speed = ATK_ANIM
		ch.pose("windup" if ch.has_clip("windup") else "strike")
		return
	if u.atk_serial != int(v.atk):
		v.atk = u.atk_serial
		v.pose = "strike"
		v.anim_t = 0.0
		ch.anim_speed = ATK_ANIM
		ch.pose("strike")
		return
	if v.pose in ["cast", "strike", "windup"] and float(v.anim_t) < 0.45 and not u.moving:
		return
	var want := "run" if u.moving else "idle"
	if u.moving and not ch.has_clip("run"):
		want = "walk"
	if v.pose != want:
		v.pose = want
		ch.anim_speed = 1.0 if want == "idle" else clampf(u.ms_now() / 3.4, 0.8, 1.6)
		ch.pose(want)


func _place_camera(snap: bool, delta: float = 0.0) -> void:
	var me := sim.unit(local_id)
	var focus := Vector3.ZERO
	if me:
		var p: Vector2 = (_prev.get(me.id, me.pos) as Vector2).lerp(me.pos, clampf(_acc / MobaSim.TICK, 0.0, 1.0))
		focus = Vector3(p.x, 0, p.y)
		if sim.mode == "pit":                    # keep the Giant in frame: lean the view toward it
			focus = focus.lerp(Vector3(MobaSim.BOSS_POS.x, 0, MobaSim.BOSS_POS.y), 0.6)
	var pitch := deg_to_rad(CAM_PITCH)
	var fwd := view_forward()
	var back := Vector3(-fwd.x, 0, -fwd.y)
	var want := focus + back * cos(pitch) * CAM_DIST + Vector3(0, sin(pitch) * CAM_DIST, 0)
	_cam.position = want if snap else _cam.position.lerp(want, minf(1.0, delta * 12.0))
	_cam.look_at(_cam.position - back * cos(pitch) - Vector3(0, sin(pitch), 0))


## Which way "up the screen" points on the ground, per side (author 10-13):
## in the duel your tower sits bottom-left and theirs upper-right, so the
## lane runs corner to corner; red sees the same picture turned 180°. In
## the pit your entrance is at the bottom.
func view_forward() -> Vector2:
	var me := sim.unit(local_id)
	var blue := me == null or me.team == "blue"
	if sim.mode == "pit":
		return Vector2(0, -1) if blue else Vector2(0, 1)
	var f := Vector2(1, -1).normalized()          # +x (toward red) shows up-right
	return f if blue else -f


func _hud_update(me: MobaUnit, delta: float) -> void:
	_hud.update(me, delta)
	if me:
		_smoke.visible = me.blind_t > 0.0
		(_smoke.material as ShaderMaterial).set_shader_parameter("amount", 0.92 if me.blind_t > 0.0 else 0.0)
