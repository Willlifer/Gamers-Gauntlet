class_name MmoTankView
extends Node3D
## Planet of Tanks on screen (G46): MmoView's helper for the tank fight. The
## kit tank as the boss (turret and gun on their pivots, the treads that glow
## red, the wobble and the spin), the light tanks, the smokescreen, the
## ground telegraphs' dressing (shells falling, dust building), the blasts,
## and the announcer.

const BOSS_LEN := 8.6            ## the boss tank's length (m)
const ADD_LEN := 3.4
const GUN_MAX := 0.75            ## the gun's top elevation (rad)

var view: MmoView
var sim: MmoSim
var _smoke_root: Node3D
var _smoke_wall: MeshInstance3D
var _smoke_floor: MeshInstance3D
var _smoke_mat: ShaderMaterial
var _smoke_floor_mat: ShaderMaterial
var _smoke_puffs: CPUParticles3D
var _layer: CanvasLayer
var _ann: Label
var _ann_sub: Label
var _ann_t := 0.0


func _init(v: MmoView) -> void:
	view = v
	sim = v.sim


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	_ann = Label.new()
	_ann.add_theme_font_size_override("font_size", 74)
	_ann.add_theme_color_override("font_color", Color("#ffd040"))
	_ann.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.0))
	_ann.add_theme_constant_override("outline_size", 16)
	_ann.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ann.position = Vector2(0, 250)
	_ann.size = Vector2(1600, 100)
	_ann.pivot_offset = Vector2(800, 50)
	_ann.visible = false
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black"])
	f.font_weight = 800
	_ann.add_theme_font_override("font", f)
	_layer.add_child(_ann)
	_ann_sub = Label.new()
	_ann_sub.add_theme_font_size_override("font_size", 24)
	_ann_sub.add_theme_color_override("font_color", Color(1, 0.92, 0.8))
	_ann_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	_ann_sub.add_theme_constant_override("outline_size", 8)
	_ann_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ann_sub.position = Vector2(0, 342)
	_ann_sub.size = Vector2(1600, 40)
	_ann_sub.visible = false
	_layer.add_child(_ann_sub)


# ------------------------------------------------------------------ models

## The tank (boss or light tank) under `root`; fills `v` with its moving parts.
func build_unit(u: MmoUnit, root: Node3D, v: Dictionary) -> void:
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var a := GKRegistry.build("tank")
	var len := a.aabb().size.z
	var k := (BOSS_LEN if u.kind == "boss" else ADD_LEN) / maxf(0.1, len)
	body.scale = Vector3.ONE * k
	var n := a.instantiate(false)
	body.add_child(n)
	# the turret and the gun turn on their own pivots
	var tp: Vector3 = a.marker("turret_pivot").origin if a.markers.has("turret_pivot") else Vector3(0, 2, 0)
	var gp: Vector3 = a.marker("gun_pivot").origin if a.markers.has("gun_pivot") else tp
	var turret_pv := Node3D.new()
	turret_pv.position = tp
	n.add_child(turret_pv)
	var gun_pv := Node3D.new()
	gun_pv.position = gp - tp
	turret_pv.add_child(gun_pv)
	for c in n.get_children():
		if c.name == "turret":
			n.remove_child(c)
			turret_pv.add_child(c)
			(c as Node3D).position = -tp
		elif c.name == "gun":
			n.remove_child(c)
			gun_pv.add_child(c)
			(c as Node3D).position = -gp
		elif c.name == "muzzle":
			n.remove_child(c)
			gun_pv.add_child(c)
			(c as Node3D).transform.origin -= gp
	var muzzle := gun_pv.get_node_or_null("muzzle") as Node3D
	# the treads' glow: the tracks drawn again over themselves, one side each,
	# glowing (a shader keeps one side of the hull), and a light
	var bb := a.aabb()
	var glows: Array = []
	var tracks := n.get_node_or_null("tracks") as MeshInstance3D
	for side in [-1, 1]:
		var g := MeshInstance3D.new()
		var m := ShaderMaterial.new()
		m.shader = _glow_shader()
		m.set_shader_parameter("side", -float(side))          # -1 is the hull's left: MmoUnit.right() is -X at yaw 0
		m.set_shader_parameter("col", Color(0, 0, 0, 0))
		if tracks:
			g.mesh = tracks.mesh
		g.material_override = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(g)
		var lp := Vector3(-float(side) * (bb.size.x * 0.5 - 0.2), bb.position.y + bb.size.y * 0.15, bb.get_center().z)
		var l := OmniLight3D.new()
		l.light_color = Color("#ff3010")
		l.light_energy = 0.0
		l.omni_range = 5.0 / k
		l.position = lp + Vector3(-float(side) * 0.8, 0.3, 0)
		n.add_child(l)
		glows.append([g, l])
	v["body"] = body
	v["turret"] = turret_pv
	v["gun"] = gun_pv
	v["muzzle"] = muzzle
	v["glows"] = glows
	v["vehicle"] = true
	v["fired"] = u.strike_serial
	v["plate_h"] = bb.end.y * k + 0.6
	v["dust"] = _track_dust(root)
	if u.kind == "boss":
		_flank_marks(n, bb, k, v)
		_exhaust(n, bb, v)


## G52b: the soft flanks, shown: a plate along each side that pulses, and a
## target ring standing off it. Hidden until Loose Cannon opens them.
func _flank_marks(n: Node3D, bb: AABB, k: float, v: Dictionary) -> void:
	var marks: Array = []
	for side in [-1, 1]:
		var g := Node3D.new()
		var plate := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, bb.size.y * 0.42, bb.size.z * 0.6)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.75, 0.2, 0.0)
		bm.material = m
		plate.mesh = bm
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(plate)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.5 / k
		tm.outer_radius = 0.66 / k
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color("#ffb030")
		rm.no_depth_test = true
		tm.material = rm
		ring.mesh = tm
		ring.rotation.z = PI * 0.5
		ring.position = Vector3(float(side) * 1.1 / k, 0, 0)
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14 / k
		sm.height = 0.28 / k
		sm.material = rm
		dot.mesh = sm
		dot.position = ring.position
		g.add_child(ring)
		g.add_child(dot)
		g.position = Vector3(float(side) * (bb.size.x * 0.5 + 0.03), bb.position.y + bb.size.y * 0.42, bb.get_center().z)
		g.visible = false
		n.add_child(g)
		marks.append(g)
	v["flank_marks"] = marks


## G52b: exhaust flames off the tail, lit at the 15% speed-up.
func _exhaust(n: Node3D, bb: AABB, v: Dictionary) -> void:
	var pipes: Array = []
	for side in [-1, 1]:
		var p := view._sparkles(Color("#ff7020"))
		p.emission_sphere_radius = 0.12
		p.amount = 50
		p.lifetime = 0.45
		p.direction = Vector3(0, 0.6, -1)
		p.spread = 18.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 5.5
		p.gravity = Vector3(0, 2.0, 0)
		p.scale_amount_min = 0.25
		p.scale_amount_max = 0.5
		p.position = Vector3(float(side) * bb.size.x * 0.28, bb.position.y + bb.size.y * 0.55, bb.position.z + 0.1)
		p.emitting = false
		n.add_child(p)
		pipes.append(p)
	v["exhaust"] = pipes


func _track_dust(root: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.6, 0.1, 0.4)
	p.position = Vector3(0, 0.2, -2.0)
	p.direction = Vector3(0, 1, -0.5)
	p.spread = 35.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -0.3, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.32, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	p.emitting = false
	root.add_child(p)
	return p


## Every frame for a tank's view.
func pose(u: MmoUnit, v: Dictionary, delta: float) -> void:
	var body: Node3D = v.body
	if not u.alive:
		body.rotation = body.rotation.lerp(Vector3(0.0, 0.0, 0.12), minf(1.0, delta * 2.0))
		(v.dust as CPUParticles3D).emitting = false
		_glow(v, [0.0, 0.0], delta)
		return
	var tf := sim.tank
	var t := Time.get_ticks_msec() / 1000.0
	var tur: Node3D = v.turret
	var gun: Node3D = v.gun
	if u.kind == "boss":
		tur.rotation.y = lerp_angle(tur.rotation.y, wrapf(tf.turret - u.yaw, -PI, PI), minf(1.0, delta * 14.0))
		gun.rotation.x = lerpf(gun.rotation.x, -tf.gun_pitch * GUN_MAX, minf(1.0, delta * 4.0))
		var wob := Vector3.ZERO
		if tf.wobble == 1.0:
			wob.z = sin(t * 15.0) * 0.07                    # side to side
		elif tf.wobble == 2.0:
			wob.x = sin(t * 9.0) * 0.06                     # fore and aft
		if tf.spinning:
			wob.z = sin(t * 31.0) * 0.03
		body.rotation = body.rotation.lerp(wob, minf(1.0, delta * 12.0))
		var rush := tf.rate > 1.0
		var g: Array = tf.glow
		if rush:                                          # G52b: past 15% the whole tank runs hot
			g = [maxf(float(g[0]), 1.7), maxf(float(g[1]), 1.7)]
		_glow(v, g, delta)
		for p: CPUParticles3D in v.get("exhaust", []):
			p.emitting = rush
		var soft := u.has_aura("soft_flanks")
		for m: Node3D in v.get("flank_marks", []):
			m.visible = soft
			if soft:
				var pl := (m.get_child(0) as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
				pl.albedo_color.a = 0.25 + 0.3 * (0.5 + 0.5 * sin(t * 5.0))
				var r := 1.0 + 0.12 * sin(t * 5.0)
				(m.get_child(1) as Node3D).scale = Vector3.ONE * r
		(v.dust as CPUParticles3D).emitting = u.moving or tf.spinning or tf.wobble > 0.0
	else:
		var tgt := sim.unit(u.target)
		if u.flags.has("face"):
			tur.rotation.y = lerp_angle(tur.rotation.y, 0.0, minf(1.0, delta * 6.0))     # G52: parked, gun to the front
		elif tgt:
			var want := atan2(tgt.pos.x - u.pos.x, tgt.pos.y - u.pos.y) - u.yaw
			tur.rotation.y = lerp_angle(tur.rotation.y, want, minf(1.0, delta * 6.0))
		(v.dust as CPUParticles3D).emitting = u.moving
	# a shot: the muzzle flashes and the gun kicks
	if u.strike_serial != int(v.fired):
		v.fired = u.strike_serial
		_muzzle(v, 1.0 if u.kind == "boss" else 0.5)
		gun.position.z = -0.25 if u.kind == "boss" else -0.1
	gun.position.z = move_toward(gun.position.z, 0.0, delta * 1.2)


const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.0);
uniform float side = 1.0;
varying float lx;
void vertex() {
	lx = VERTEX.x;
	VERTEX *= 1.015;
}
void fragment() {
	if (lx * side < 0.05) { discard; }
	float pulse = 0.8 + 0.2 * sin(TIME * 9.0 + FRAGCOORD.y * 0.02);
	ALBEDO = col.rgb * pulse * 1.6;
	ALPHA = col.a;
}
"""
static var _glow_sh: Shader


static func _glow_shader() -> Shader:
	if _glow_sh == null:
		_glow_sh = Shader.new()
		_glow_sh.code = GLOW_SHADER
	return _glow_sh


func _glow(v: Dictionary, g: Array, delta: float) -> void:
	var k := 0
	for pair: Array in v.glows:
		var lvl := float(g[k])
		var col := Color(0, 0, 0, 0)
		var energy := 0.0
		if lvl > 0.01:
			var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 90.0)
			if lvl <= 0.5:
				col = Color(1.0, 0.55, 0.12, 0.75)                     # cooled to orange
				energy = 1.0
			elif lvl <= 1.0:
				col = Color(0.95, 0.12, 0.05, 0.8)                     # red
				energy = 2.2
			else:
				col = Color(1.0, 0.2 + 0.4 * (lvl - 1.0), 0.15, 1.0) * Color(1.6, 1.6, 1.6, 1.0)   # bright red
				energy = 2.2 + 4.0 * (lvl - 1.0)
			col.a *= pulse
		var mm := (pair[0] as MeshInstance3D).material_override as ShaderMaterial
		mm.set_shader_parameter("col", (mm.get_shader_parameter("col") as Color).lerp(col, minf(1.0, delta * 8.0)))
		var l: OmniLight3D = pair[1]
		l.light_energy = lerpf(l.light_energy, energy, minf(1.0, delta * 8.0))
		k += 1


func _muzzle(v: Dictionary, s: float) -> void:
	var m: Node3D = v.get("muzzle")
	if m == null or not is_instance_valid(m):
		return
	var at := m.global_position
	if at.distance_to(view.camera().global_position) > 6.0:
		view._fx.release_at("fire", at, 0.7 * s)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffb060")
	l.light_energy = 6.0 * s
	l.omni_range = 10.0 * s
	add_child(l)
	l.global_position = at
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


# ----------------------------------------------------------------- the ground

## Dressing for an area MmoView has just laid down.
func decorate(a: Dictionary, root: Node3D) -> void:
	match str(a.get("look", "")):
		"deny":
			kick(a.pos as Vector2)                            # G52b: parked: dust, a nudge, the wedge flashes in (MmoView._sync_areas)
			view._shake = maxf(view._shake, 0.35)
		"smoke_mark":
			var can := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.18
			cy.bottom_radius = 0.18
			cy.height = 0.6
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color("#4a5a3a")
			cm.metallic = 0.4
			cy.material = cm
			can.mesh = cy
			var trail := CPUParticles3D.new()
			trail.amount = 30
			trail.lifetime = 0.6
			trail.local_coords = false
			trail.gravity = Vector3(0, 0.4, 0)
			trail.scale_amount_min = 0.3
			trail.scale_amount_max = 0.7
			var pm := SphereMesh.new()
			pm.radius = 0.5
			pm.height = 1.0
			pm.radial_segments = 6
			pm.rings = 3
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.85, 0.85, 0.8, 0.5)
			pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pm.material = pmat
			trail.mesh = pm
			can.add_child(trail)
			root.add_child(can)
			root.set_meta("rock", can)
			var bv: Dictionary = view._views.get("boss", {})
			var mz: Variant = bv.get("muzzle")
			var from := view._v3(sim.boss.pos, 3.0)
			if mz != null and is_instance_valid(mz):
				from = (mz as Node3D).global_position
			root.set_meta("arc_from", from)
		"shell":
			var shell := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.22
			cm.height = 1.0
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color("#3a3f30")
			sm.metallic = 0.6
			sm.emission_enabled = true
			sm.emission = Color("#ff7020")
			sm.emission_energy_multiplier = 0.6
			cm.material = sm
			shell.mesh = cm
			var trail := view._sparkles(Color("#ffb060"))
			trail.emission_sphere_radius = 0.2
			trail.amount = 20
			trail.lifetime = 0.35
			trail.local_coords = false
			shell.add_child(trail)
			root.add_child(shell)
			root.set_meta("rock", shell)
		"dust":
			var p := CPUParticles3D.new()
			p.amount = 160
			p.lifetime = 1.6
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
			var pts := PackedVector3Array()
			var rng := RandomNumberGenerator.new()
			rng.seed = int(a.id)
			for i in 240:
				var ang := rng.randf_range(-float(a.half), float(a.half))
				var rr := sqrt(rng.randf()) * MmoSim.ARENA_R * 1.05
				pts.append(Vector3(sin(ang) * rr, 0.3, cos(ang) * rr))
			p.emission_points = pts
			p.direction = Vector3.UP
			p.spread = 40.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 1.2
			p.gravity = Vector3(0, 0.2, 0)
			p.scale_amount_min = 1.2
			p.scale_amount_max = 2.6
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			m.radial_segments = 6
			m.rings = 3
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.62, 0.48, 0.3, 0.22)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.material = mat
			p.mesh = m
			root.add_child(p)


## The sector telegraph's colour by its look.
static func sector_col(look: String) -> Color:
	match look:
		"cannon": return Color(1.0, 0.32, 0.1, 1.0)
		"dust": return Color(0.95, 0.62, 0.25, 1.0)
		"arc": return Color(1.0, 0.1, 0.05, 1.0)
		"deny": return Color(0.95, 0.04, 0.04, 1.0)           # G52: the light tanks' zones
	return Color(1.0, 0.3, 0.1, 1.0)


func explode(e: Dictionary) -> void:
	var fx := view._fx
	var at := view._v3(e.pos as Vector2)
	var me := sim.unit(view.me_id)
	match str(e.what):
		"deny":
			# G52: a light tank's round lands in its zone
			fx.release_at("fire", at + Vector3(0, 0.4, 0), 0.8)
			view._scorch(at, 1.8)
			if me and me.pos.distance_to(e.pos as Vector2) < 8.0:
				view._shake = maxf(view._shake, 0.3)
		"shell":
			fx.release_at("fire", at + Vector3(0, 0.5, 0), 1.3)
			view._scorch(at, 3.0)
			if me and me.pos.distance_to(e.pos as Vector2) < 12.0:
				view._shake = maxf(view._shake, 0.5)
		"cannon", "arc", "tread":
			var dir := e.dir as Vector2
			var half := float(e.half)
			var cannon := str(e.what) == "cannon"
			var steps := 5 if cannon else 9
			var cam := view.camera().global_position
			for i in steps:
				var ang := lerpf(-half, half, (i + 0.5) / steps)
				var d := dir.rotated(ang)
				for rr: float in ([9.0, 17.0] if cannon else [6.0, 13.0, 20.0]):
					var p := (e.pos as Vector2) + d * rr
					if p.length() > MmoSim.ARENA_R:
						continue
					var p3 := view._v3(p, 0.6)
					if p3.distance_to(cam) < 7.0:
						continue                                       # never a fireball in the camera's face
					fx.release_at("fire", p3, 0.9 if not cannon else 0.55)
			if me and MmoTankFight.in_sector(me.pos, { "pos": e.pos, "dir": e.dir, "half": e.half, "r": e.r }, 6.0):
				view._shake = maxf(view._shake, 0.8 if str(e.what) != "cannon" else 0.5)


# ------------------------------------------------------------------ smoke

const SMOKE_WALL := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float fade = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	float n = noise(vec2(UV.x * 60.0 + TIME * 0.4, UV.y * 3.0 - TIME * 0.3)) * 0.6 + noise(vec2(UV.x * 140.0 - TIME * 0.6, UV.y * 6.0)) * 0.4;
	float h = 1.0 - UV.y;                       // 0 at the top
	float a = smoothstep(0.0, 0.55, h) * (0.55 + 0.45 * n);
	float near = smoothstep(4.0, 14.0, length(VERTEX));   // thin out close to the camera: it never blinds you
	ALBEDO = mix(vec3(0.62, 0.63, 0.58), vec3(0.85, 0.85, 0.8), n);
	ALPHA = clamp(a * 0.6 * fade * near, 0.0, 1.0);
}
"""
const SMOKE_FLOOR := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float r = 10.0;          // the smoke's radius (m)
uniform float band = 5.0;
uniform float core = 0.15;
uniform float fade = 1.0;
uniform float size = 80.0;       // the plane's half size (m)
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * size;
	float d = length(p);
	if (d > r) { discard; }
	float k = d >= r - band ? 1.0 : mix(core, 1.0, clamp(1.0 - (r - band - d) / 6.0, 0.0, 1.0));
	float n = noise(p * 0.25 + vec2(TIME * 0.2, -TIME * 0.15));
	ALBEDO = vec3(0.7, 0.71, 0.66);
	ALPHA = clamp(k * fade * (0.42 + 0.25 * n), 0.0, 0.85);
}
"""


func sync(_delta: float) -> void:
	_sync_smoke()
	_sync_marks(_delta)
	if _ann_t > 0.0:
		_ann_t -= _delta
		if _ann_t <= 0.0:
			_ann.visible = false
			_ann_sub.visible = false


func _sync_smoke() -> void:
	var sm: Dictionary = sim.tank.smoke
	if sm.is_empty():
		if _smoke_root:
			_smoke_root.visible = false
			_smoke_puffs.emitting = false
		return
	if _smoke_root == null:
		_smoke_root = Node3D.new()
		add_child(_smoke_root)
		_smoke_wall = MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 1.0
		cy.bottom_radius = 1.0
		cy.height = 1.0
		cy.cap_top = false
		cy.cap_bottom = false
		cy.radial_segments = 96
		_smoke_wall.mesh = cy
		var sh := Shader.new()
		sh.code = SMOKE_WALL
		_smoke_mat = ShaderMaterial.new()
		_smoke_mat.shader = sh
		_smoke_wall.material_override = _smoke_mat
		_smoke_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smoke_root.add_child(_smoke_wall)
		_smoke_floor = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * 160.0
		_smoke_floor.mesh = pm
		var fs := Shader.new()
		fs.code = SMOKE_FLOOR
		_smoke_floor_mat = ShaderMaterial.new()
		_smoke_floor_mat.shader = fs
		_smoke_floor_mat.set_shader_parameter("size", 80.0)
		_smoke_floor.material_override = _smoke_floor_mat
		_smoke_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smoke_floor.position.y = 0.6
		_smoke_root.add_child(_smoke_floor)
		_smoke_puffs = CPUParticles3D.new()
		_smoke_puffs.amount = 260
		_smoke_puffs.lifetime = 2.4
		_smoke_puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		_smoke_puffs.emission_ring_axis = Vector3.UP
		_smoke_puffs.emission_ring_height = 0.5
		_smoke_puffs.direction = Vector3.UP
		_smoke_puffs.spread = 50.0
		_smoke_puffs.initial_velocity_min = 0.3
		_smoke_puffs.initial_velocity_max = 1.0
		_smoke_puffs.gravity = Vector3(0, 0.15, 0)
		_smoke_puffs.scale_amount_min = 1.6
		_smoke_puffs.scale_amount_max = 3.2
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 8
		m.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.82, 0.82, 0.78, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material = mat
		_smoke_puffs.mesh = m
		_smoke_root.add_child(_smoke_puffs)
	_smoke_root.visible = true
	var c := sm.c as Vector2
	var r := float(sm.r)
	_smoke_root.position = Vector3(c.x, 0, c.y)
	_smoke_wall.scale = Vector3(r, 3.2, r)
	_smoke_wall.position.y = 1.6
	_smoke_mat.set_shader_parameter("fade", float(sm.fade))
	_smoke_floor_mat.set_shader_parameter("r", r)
	_smoke_floor_mat.set_shader_parameter("band", MmoTune.value("smoke_band"))
	_smoke_floor_mat.set_shader_parameter("core", MmoTune.value("smoke_core"))
	_smoke_floor_mat.set_shader_parameter("fade", float(sm.fade))
	_smoke_puffs.emission_ring_radius = r - 1.0
	_smoke_puffs.emission_ring_inner_radius = maxf(0.0, r - MmoTune.value("smoke_band"))
	_smoke_puffs.emitting = float(sm.fade) > 0.25


# ------------------------------------------------------------ hit markers

var _marks: Array = []           ## { node, t, id }


## G52b: DOUBLE / TRIPLE HIT, drawn: over everyone caught, a stack of `n`
## red chevrons that pops in and fades, and the damage multiplier under it.
func multi_hit(ids: Array, n: int, mult: float) -> void:
	for id: String in ids:
		var u := sim.unit(id)
		if u == null or not view._views.has(id):
			continue
		var root := Node3D.new()
		add_child(root)
		for i in mini(n, 6):
			var ch := _chevron(Color(1.0, 0.25 + 0.12 * i, 0.08))
			ch.position = Vector3(0, i * 0.5, 0)
			ch.scale = Vector3.ONE * 1.8
			root.add_child(ch)
		root.scale = Vector3.ONE * 0.1
		var tw := create_tween()
		tw.tween_property(root, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK)
		tw.tween_property(root, "scale", Vector3.ONE, 0.1)
		_marks.append({ "node": root, "t": 0.0, "id": id })
		view._floater(u, "x%.2f" % mult, Color("#ff8a30"), true)
	if not ids.is_empty():
		BWSfx.play("ph_colossus_thrust", Vector3.ZERO, { "gain_db": -2.0, "pitch": 1.3 })


func _chevron(col: Color) -> Node3D:
	var c := Node3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 4
	for s in [-1, 1]:
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.42, 0.11, 0.02)
		bm.material = m
		arm.mesh = bm
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.position = Vector3(s * 0.15, 0.08, 0)
		arm.rotation.z = s * 0.6                        # a V pointing down at the head
		c.add_child(arm)
	return c


func _sync_marks(delta: float) -> void:
	var cam := view.camera()
	for mk: Dictionary in _marks.duplicate():
		mk.t = float(mk.t) + delta
		var node: Node3D = mk.node
		var vv: Dictionary = view._views.get(str(mk.id), {})
		if float(mk.t) > 1.8 or vv.is_empty():
			node.queue_free()
			_marks.erase(mk)
			continue
		node.global_position = (vv.root as Node3D).global_position + Vector3(0, 2.9 + float(mk.t) * 0.25, 0)
		var to := cam.global_position - node.global_position
		node.rotation.y = atan2(to.x, to.z)
		if float(mk.t) > 1.3:
			node.scale = Vector3.ONE * maxf(0.05, 1.0 - (float(mk.t) - 1.3) * 2.0)


## G52b: a dust kick where the light tanks break out of the trees.
func kick(p: Vector2) -> void:
	var at := view._v3(p, 0.3)
	for i in 3:
		view._puff(at + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), Color(0.62, 0.5, 0.34, 0.7))
	view._fx._burst_parts(at, "wind", 14, 0.0, { "up": 2.5, "spread": 4.0, "g": 6.0, "shape": 2, "life": 0.7, "s0": 0.18 })


# --------------------------------------------------------------- announcer

## The announcer: big gold words, a line under them, and (when the OS has a
## voice) the call out loud.
func announce(text: String, sub: String) -> void:
	_ann.text = text
	_ann_sub.text = sub
	_ann.visible = true
	_ann_sub.visible = sub != ""
	_ann_t = 2.6
	_ann.scale = Vector2(1.8, 1.8)
	_ann.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_ann, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ann, "modulate:a", 1.0, 0.12)
	BWSfx.play("ph_colossus_thrust", Vector3.ZERO, { "gain_db": 2.0, "pitch": 1.2 })
	_say(text.capitalize())


static func _say(text: String) -> void:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, voices[0], 80, 0.9, 1.15)
