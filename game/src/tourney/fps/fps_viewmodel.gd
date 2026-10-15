class_name FpsViewmodel
extends Node3D
## The gun you see in first person: a Gauntlet kit item hung off the camera,
## drawn only by the view-model camera (render layer 2, its own FOV, so it
## never clips into walls). All motion is procedural:
##   hip / aim    aiming slides the kit item's `eye` marker onto the eye (the
##                sniper then hands over to the scope overlay)
##   bob, sway    the run cycle and a lag behind the mouse
##   recoil       a spring kick back and up per shot
##   actions      the sniper's bolt (its `bolt` part lifts, slides, closes),
##                the shotgun's pump (its `pump` part racks), the pistols' slide
##                (their `slide` part kicks back, G43), the slingshot's
##                draw (five prebuilt frames of the band pulled back)
##   reload, equip  the gun dips and rolls out of view and back
##   duals        (G43) two pistols, one per hand, each with its own slide; the
##                trick reload: both mags drop, both guns backflip up, two fresh
##                mags rise from below and the guns land on them
## The player script feeds update() each frame; nothing here reads input.

const LAYER := 2                           ## view-model render layer
const R := Basis(Vector3.UP, PI)           ## kit items point +Z; the camera looks -Z

var weapon_id := ""
var spec := {}
var asset: GKAsset
var gun: Node3D
var frames: Array[Node3D] = []             # slingshot: draw 0, .25, .5, .75, 1
var ads := 0.0
var action_t := -1.0                       # bolt / pump progress 0..1; < 0 idle
var reload_t := -1.0                       # reload progress 0..1
var equip_t := 1.0                         # 0 = just switched, 1 = up
var draw := 0.0
var _rp := Vector3.ZERO                    # recoil spring: position, velocity
var _rv := Vector3.ZERO
var _ap := Vector3.ZERO                    # recoil spring: rotation (pitch, yaw, roll)
var _av := Vector3.ZERO
var _sway := Vector2.ZERO
var _bob := 0.0
var _bob_amt := 0.0
var _flash: Node3D
var _flash_t := 0.0
var _assets := {}                          # id -> GKAsset (built once)
var gun_l: Node3D                          # duals: the left hand's gun
var action_l := -1.0                       # duals: the left slide
var _flash_side := ""
var _new_mags: Array[MeshInstance3D] = []  # duals: the fresh mags rising for the catch


func equip(id: String) -> void:
	if id == weapon_id and gun:
		return
	weapon_id = id
	spec = FpsWeapons.SPECS[id]
	for f in frames:
		f.queue_free()
	frames.clear()
	if gun and is_instance_valid(gun) and not gun in frames:
		gun.queue_free()
	gun = null
	if gun_l and is_instance_valid(gun_l):
		gun_l.queue_free()
	gun_l = null
	for m in _new_mags:
		m.queue_free()
	_new_mags.clear()
	if id == "slingshot":
		for k in 5:
			var p: Dictionary = (spec.params as Dictionary).duplicate()
			p["draw"] = k / 4.0
			p["drape"] = 0.0
			var a := GKRegistry.build("slingshot", p)
			var n := _prep(a.instantiate(false))
			n.visible = k == 0
			frames.append(n)
			if k == 0:
				asset = a
		gun = frames[0]
	else:
		if not _assets.has(id):
			_assets[id] = GKRegistry.build(str(spec.asset), spec.params)
		asset = _assets[id]
		gun = _prep(asset.instantiate(false))
		if spec.get("dual", false):
			gun_l = _prep(asset.instantiate(false))
			for g in [gun, gun_l]:
				var mag := (g as Node3D).get_node_or_null("mag") as MeshInstance3D
				var fresh := MeshInstance3D.new()
				fresh.mesh = mag.mesh if mag else _box_mag()
				fresh.layers = LAYER
				fresh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if mag:
					for i in mag.get_surface_override_material_count():
						fresh.set_surface_override_material(i, mag.get_surface_override_material(i))
				fresh.visible = false
				add_child(fresh)
				_new_mags.append(fresh)
	_make_flash()
	equip_t = 0.0
	action_t = -1.0
	action_l = -1.0
	reload_t = -1.0
	draw = 0.0


## A stand-in magazine for a pistol model without a `mag` part.
func _box_mag() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.022, 0.12, 0.04)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.11)
	b.material = m
	return b


func _prep(n: Node3D) -> Node3D:
	add_child(n)
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = LAYER
		if vi is GeometryInstance3D:
			(vi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func _make_flash() -> void:
	if _flash:
		_flash.queue_free()
	_flash = Node3D.new()
	add_child(_flash)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.75, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	for k in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.09, 0.22)
		q.mesh = qm
		q.material_override = m
		q.rotation = Vector3(PI * 0.5, 0, k * PI / 3.0)
		q.position.z = -0.08
		q.layers = LAYER
		_flash.add_child(q)
	var core := MeshInstance3D.new()
	var cm := QuadMesh.new()
	cm.size = Vector2(0.12, 0.12)
	core.mesh = cm
	core.material_override = m
	core.layers = LAYER
	_flash.add_child(core)
	_flash.visible = false


## A shot: the spring kicks, the flash pops, the action starts. `side` "l"
## or "r" for the duals.
func fire(side := "") -> void:
	_flash_side = side
	var k := FpsTune.value("recoil") * float(spec.recoil) / 8.0
	_rv += Vector3(0, 0.25, 2.2) * float(spec.kick) * 10.0 * k
	_av += Vector3(deg_to_rad(float(spec.recoil)) * 9.0, randf_range(-0.6, 0.6), randf_range(-1.5, 1.5)) * k
	if spec.action != "draw":
		_flash_t = 0.05
		_flash.rotation.z = randf() * TAU
	if side == "l":
		action_l = 0.0
	elif spec.action in ["bolt", "pump", "slide"]:
		action_t = 0.0
	draw = 0.0


func start_reload() -> void:
	reload_t = 0.0


## The world position shots and tracers leave from (`side` "l": the left dual).
func muzzle_global(side := "") -> Vector3:
	var g := gun_l if side == "l" and gun_l else gun
	if g == null:
		return global_position
	return g.global_transform * asset.marker("muzzle").origin


## stance: "stand" | "crouch" | "prone"; speed01: run fraction; look: mouse
## delta this frame (pixels).
func update(delta: float, aiming: bool, speed01: float, grounded: bool, stance: String, look: Vector2) -> void:
	if gun == null:
		return
	# aim in / out
	var ads_t := FpsTune.value("ads_time")
	var busy: bool = reload_t >= 0.0 or equip_t < 1.0 or (action_t >= 0.0 and spec.action == "bolt" and action_t > 0.12 and action_t < 0.9)
	ads = move_toward(ads, 1.0 if aiming and not busy else 0.0, delta / ads_t)
	var e := ads * ads * (3.0 - 2.0 * ads)
	# timelines
	if action_t >= 0.0:
		action_t += delta / float(spec.cycle)
		if action_t >= 1.0:
			action_t = -1.0
	if action_l >= 0.0:
		action_l += delta / float(spec.cycle)
		if action_l >= 1.0:
			action_l = -1.0
	if reload_t >= 0.0:
		reload_t += delta / maxf(float(spec.reload), 0.05)
		if reload_t >= 1.0:
			reload_t = -1.0
	equip_t = minf(1.0, equip_t + delta / 0.35)
	_flash_t -= delta
	# springs
	_rv += (-_rp * 260.0 - _rv * 24.0) * delta
	_rp += _rv * delta
	_av += (-_ap * 220.0 - _av * 20.0) * delta
	_ap += _av * delta
	# sway: lag behind the look, settle back
	var sw := FpsTune.value("sway") * (1.0 - e * 0.8)
	_sway = _sway.lerp(Vector2(-look.x, -look.y) * 0.0018 * sw, minf(1.0, delta * 10.0))
	# bob: the run cycle, scaled by speed
	var moving := speed01 if grounded else 0.0
	_bob_amt = move_toward(_bob_amt, moving * FpsTune.value("bob") * (1.0 - e * 0.85), delta * 4.0)
	_bob += delta * (7.0 + 5.0 * speed01) * (0.5 if stance == "prone" else 1.0)
	var bob := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.011, 0.0) * _bob_amt
	var breathe := Vector3(0, sin(Time.get_ticks_msec() * 0.0021) * 0.002, 0) * (1.0 - e * 0.6)
	# where it sits
	var hip: Vector3 = spec.hip
	var eye_mk := "eye" if asset.markers.has("eye") else "muzzle"
	var aim_at := Vector3(0, 0, -0.06) if eye_mk == "eye" else Vector3(0, -0.03, -0.5)
	var ads_pos := aim_at - R * asset.marker(eye_mk).origin
	var pos := hip.lerp(ads_pos, e) + bob + breathe + _rp * Vector3(1, 1, 1)
	var rot := Vector3(_sway.y + _ap.x * 0.02, _sway.x + _ap.y * 0.02, _ap.z * 0.02 + sin(_bob * 0.5) * 0.01 * _bob_amt)
	if stance == "crouch":
		rot.z += deg_to_rad(3.0) * (1.0 - e)
	elif stance == "prone":
		pos.y -= 0.02 * (1.0 - e)
		rot.z += deg_to_rad(6.0) * (1.0 - e)
	# the action's own motion
	match str(spec.action):
		"bolt":
			_bolt(pos, rot)
		"pump":
			_pump()
		"slide":
			_slide()
	if action_t >= 0.0:
		var a := action_t
		var w := _hump(a, 0.12, 0.9)
		if spec.action == "bolt":
			pos += Vector3(-0.02, -0.035, 0.03) * w
			rot += Vector3(deg_to_rad(4.0), 0, deg_to_rad(-16.0)) * w
		elif spec.action == "pump":
			pos += Vector3(0, -0.02, 0.025) * w
			rot += Vector3(deg_to_rad(-3.0), 0, deg_to_rad(6.0)) * w
	if reload_t >= 0.0 and not spec.get("dual", false):
		var w := _hump(reload_t, 0.0, 1.0)
		pos += Vector3(-0.03, -0.12, 0.05) * w
		rot += Vector3(deg_to_rad(-20.0), deg_to_rad(10.0), deg_to_rad(28.0)) * w
	var drop := 1.0 - equip_t
	pos += Vector3(0, -0.3, 0.1) * drop * drop
	rot.x -= 0.8 * drop * drop
	# the slingshot's draw: the frame nearest the draw amount
	if not frames.is_empty():
		var idx := clampi(int(round(draw * 4.0)), 0, 4)
		for k in frames.size():
			frames[k].visible = k == idx
		gun = frames[idx]
	var xf := Transform3D(R * Basis.from_euler(rot), pos)
	for n in ([gun] if frames.is_empty() else frames):
		(n as Node3D).transform = xf
	if gun_l:
		var xl := Transform3D(R * Basis.from_euler(Vector3(rot.x, -rot.y, -rot.z)), Vector3(-pos.x, pos.y, pos.z))
		gun_l.transform = xl
		_dual_reload(gun, xf, 0, 1.0)
		_dual_reload(gun_l, xl, 1, -1.0)
		_slide_on(gun_l, action_l)
	var fx: Transform3D = gun_l.transform if _flash_side == "l" and gun_l else gun.transform
	_flash.transform = Transform3D(fx.basis, fx * asset.marker("muzzle").origin)
	_flash.visible = _flash_t > 0.0


## The duals' trick reload over reload_t: the mags drop out (0-0.2); the
## gun backflips up and comes down (0.15-0.78); a fresh mag rises from below
## to where the grip will be (0.35-0.62); the gun lands on it (0.78) with a
## little settle. `rest` is the gun's pose this frame; `side` 1 right, -1 left.
func _dual_reload(g: Node3D, rest: Transform3D, idx: int, side: float) -> void:
	var mag := g.get_node_or_null("mag") as Node3D
	var fresh := _new_mags[idx] if idx < _new_mags.size() else null
	var t := reload_t
	if t < 0.0:
		if mag:
			mag.position = Vector3.ZERO
			mag.visible = true
		if fresh:
			fresh.visible = false
		return
	# the old mag falls out of the grip and away
	if mag:
		var a := clampf(t / 0.2, 0.0, 1.0)
		mag.position = Vector3(0, -0.55 * a * a, 0.02 * a)
		mag.visible = t < 0.2 or t >= 0.78
		if t >= 0.78:
			mag.position = Vector3.ZERO
	# the toss: up, a full backflip, down onto the fresh mag
	var u := clampf((t - 0.15) / 0.63, 0.0, 1.0)
	var lift := 4.0 * 0.2 * u * (1.0 - u)
	var out := 4.0 * 0.16 * u * (1.0 - u)                  # thrown a little ahead, so it stays in view
	var spin := -TAU * u * u * (3.0 - 2.0 * u)
	var settle := _hump(t, 0.78, 0.9) * 0.018
	g.transform = Transform3D(rest.basis * Basis(Vector3.RIGHT, spin), rest.origin + Vector3(0.05 * side * sin(PI * u), lift - settle, -out))
	# the fresh mag: up from below the view, waiting where the grip will land
	if fresh:
		fresh.visible = t >= 0.35 and t < 0.78
		var c := clampf((t - 0.35) / 0.27, 0.0, 1.0)
		var rise := 1.0 - (1.0 - c) * (1.0 - c)
		fresh.transform = Transform3D(rest.basis, rest.origin + Vector3(0, -0.42 * (1.0 - rise), 0))


## 0 outside [a, b], rising and falling smoothly inside.
static func _hump(t: float, a: float, b: float) -> float:
	if t <= a or t >= b:
		return 0.0
	return sin(PI * (t - a) / (b - a))


## The bolt: lift, draw back, push home, turn down, over the cycle.
func _bolt(_pos: Vector3, _rot: Vector3) -> void:
	var part := gun.get_node_or_null("bolt") as Node3D
	if part == null:
		return
	var pivot := asset.marker("bolt_pivot").origin
	var a := action_t if action_t >= 0.0 else 1.0
	var lift := _seg(a, 0.18, 0.32) - _seg(a, 0.7, 0.84)
	var slide := (_seg(a, 0.34, 0.5) - _seg(a, 0.52, 0.68)) * 0.085 * float(asset.params.get("scale", 1.0))
	part.transform = Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis.IDENTITY, Vector3(0, 0, -slide)) \
		* Transform3D(Basis(Vector3.BACK, -1.1 * lift), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)


## The pump: back and home again.
func _pump() -> void:
	var part := gun.get_node_or_null("pump") as Node3D
	if part == null:
		return
	var a := action_t if action_t >= 0.0 else 1.0
	var k := _seg(a, 0.12, 0.42) - _seg(a, 0.5, 0.8)
	part.position = Vector3(0, 0, -float(asset.meta.get("pump_stroke", 0.1)) * k)


## The slide: snaps back on the shot and rides home over the cycle.
func _slide() -> void:
	_slide_on(gun, action_t)


func _slide_on(g: Node3D, at: float) -> void:
	var part := g.get_node_or_null("slide") as Node3D
	if part == null:
		return
	var a := at if at >= 0.0 else 1.0
	var k := _seg(a, 0.0, 0.12) - _seg(a, 0.18, 0.75)
	part.position = Vector3(0, 0, -float(spec.get("slide", 0.035)) * float(asset.params.get("scale", 1.0)) * k)


## 0 before a, 1 after b, eased between.
static func _seg(t: float, a: float, b: float) -> float:
	var x := clampf((t - a) / (b - a), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
