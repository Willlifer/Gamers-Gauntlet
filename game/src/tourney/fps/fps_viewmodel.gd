class_name FpsViewmodel
extends Node3D
## The gun you see in first person: a Gauntlet kit item hung off the camera,
## drawn only by the view-model camera (render layer 2, its own FOV, so it
## never clips into walls). All motion is procedural:
##   hip / aim    aiming slides the kit item's `eye` marker onto the eye (the
##                sniper then hands over to the scope overlay)
##   bob, sway    the run cycle and a lag behind the mouse; G51: a sideways
##                sway too (a slow figure-eight drift, and the gun swinging
##                out against a strafe), which side_drift() lends the camera
##                so a scope drifts across the target
##   recoil       a spring kick back and up per shot
##   actions      the sniper's bolt (its `bolt` part lifts, slides, closes),
##                the shotgun's pump (its `pump` part racks), the pistols' slide
##                (their `slide` part kicks back, G43), the slingshot's
##                draw (five prebuilt frames of the band pulled back)
##   reload, equip  the gun dips and rolls out of view and back
##   lens         (G51) the sniper's, marksman's and automatic rifle's sights
##                show a small low-res magnified picture of the world (a
##                96 px SubViewport camera riding the eye) on the ocular lens
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
var _strafe := 0.0                         # smoothed sideways run (-1 left .. 1 right)
var _bob := 0.0
var _bob_amt := 0.0
var _flash: FpsMuzzleFlash                 # G51: after design/ref/kit/muzzle_flash.png
var _assets := {}                          # id -> GKAsset (built once)
var gun_l: Node3D                          # duals: the left hand's gun
var action_l := -1.0                       # duals: the left slide
var _flash_side := ""
var _new_mags: Array[MeshInstance3D] = []  # duals: the fresh mags rising for the catch
var lens_view: SubViewport                 ## the sight's picture (G51); null on guns without one
var optic: FpsOptic                        ## G51c: the sight bolted on (automatic rifle, carbine); null otherwise
var _optic_kind := ""
var _eye_point := Vector3.ZERO             # where the eye sits when aimed in (gun frame)
var _lens_spec := {}                       # { pos, r, zoom } for the picture, or empty
var _lens_cam: Camera3D
var _lens: MeshInstance3D
const LENS_PX := 96                         ## the picture's resolution: low-def on purpose


func equip(id: String) -> void:
	if id == weapon_id and gun and _optic_kind == FpsTune.optic(id):
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
	_make_optic()
	_make_flash()
	_make_lens()
	equip_t = 0.0
	action_t = -1.0
	action_l = -1.0
	reload_t = -1.0
	draw = 0.0


## The sight (G51c): an FpsOptic on guns with optics (the radial's pick),
## which may hide model parts; then where the eye goes and where the
## picture (if any) goes. Guns without optics: the eye marker and the spec's
## lens.
func _make_optic() -> void:
	optic = null
	_optic_kind = FpsTune.optic(weapon_id)
	_lens_spec = {}
	var sc := float((spec.params as Dictionary).get("scale", 1.0))
	if asset.markers.has("eye"):
		_eye_point = asset.marker("eye").origin
	if spec.has("lens") and asset.markers.has("eye"):
		var l: Array = spec.lens
		_lens_spec = { "pos": _eye_point + Vector3(0, 0, float(l[0]) * sc - 0.0015), "r": float(l[1]) * sc,
			"zoom": float(spec.get("zoom", FpsTune.value("scope_zoom"))) }
	if _optic_kind == "" or gun == null or frames.size() > 0:
		return
	var o: Dictionary = spec.optics[_optic_kind]
	for part: String in o.get("hide", []):
		var n := gun.get_node_or_null(part) as Node3D
		if n:
			n.visible = false
	optic = FpsOptic.new()
	gun.add_child(optic)
	optic.build(_optic_kind, o, sc, float(spec.optics.rail), LAYER)
	_eye_point = optic.eye
	if not optic.lens.is_empty():
		_lens_spec = { "pos": (optic.lens.pos as Vector3) - Vector3(0, 0, 0.0015), "r": float(optic.lens.r), "zoom": float(o.get("zoom", 2.5)) }


## The sight's picture-in-picture (G51): a small SubViewport sharing the
## world, its camera on the eye at the sight's magnification (world layer
## only), drawn onto a disc over the ocular lens, round-masked.
func _make_lens() -> void:
	if _lens and is_instance_valid(_lens):
		_lens.queue_free()
	_lens = null
	if _lens_spec.is_empty() or gun == null:
		if lens_view:
			lens_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if lens_view == null:
		lens_view = SubViewport.new()
		lens_view.size = Vector2i(LENS_PX, LENS_PX)
		lens_view.world_3d = get_viewport().world_3d
		add_child(lens_view)
		_lens_cam = Camera3D.new()
		_lens_cam.cull_mask = 1
		_lens_cam.near = 0.3
		_lens_cam.far = 1500.0
		lens_view.add_child(_lens_cam)
		_lens_cam.current = true
	lens_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_lens = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(_lens_spec.r) * 2.0
	_lens.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _lens_shader()
	m.set_shader_parameter("view", lens_view.get_texture())
	_lens.material_override = m
	_lens.layers = LAYER
	_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gun.add_child(_lens)
	# just behind the ocular glass, facing the eye (the model looks +Z)
	_lens.position = _lens_spec.pos
	_lens.rotation.y = PI


static var _lens_sh: Shader


static func _lens_shader() -> Shader:
	if _lens_sh == null:
		_lens_sh = Shader.new()
		_lens_sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D view : source_color, filter_linear;
void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	if (r > 1.0) discard;
	vec3 col = texture(view, UV).rgb;
	// glass: a dark rim, a faint blue cast, a soft glint top-left
	col *= mix(1.0, 0.25, smoothstep(0.62, 1.0, r));
	col = mix(col, col * vec3(0.86, 0.95, 1.05), 0.5);
	col += vec3(0.18) * smoothstep(0.3, 0.0, length(c - vec2(-0.2, -0.22)));
	ALBEDO = col;
}
"""
	return _lens_sh


## Keep the sight's camera on the eye, at the main view's FOV over the zoom.
func _lens_follow() -> void:
	if _lens == null or lens_view == null:
		return
	var cam := get_parent() as Camera3D
	if cam == null:
		return
	var on := visible and ads < 0.97 and equip_t >= 1.0
	lens_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_lens_cam.global_transform = cam.global_transform
	var z := float(_lens_spec.get("zoom", 2.5))
	var base := FpsTune.value("fov")
	_lens_cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) / z))
	_lens_cam.keep_aspect = Camera3D.KEEP_HEIGHT


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
	var f := FpsMuzzleFlash.new()
	f.layer = LAYER
	# first person: the camera looks along the barrel, so the flash reads
	# small; lift it, the small guns most (the review's r6 note)
	f.size = 0.5 + float(spec.get("flash", 1.0)) * 0.9
	_flash = f
	add_child(_flash)


## A shot: the spring kicks, the flash pops, the action starts. `side` "l"
## or "r" for the duals.
func fire(side := "") -> void:
	_flash_side = side
	var rc := FpsTune.recoil(weapon_id)        # G51b: the gun's preset, trimmed in F1
	var k := FpsTune.value("recoil") * float(rc.recoil) / 8.0
	_rv += Vector3(0, 0.25, 2.2) * float(rc.kick) * 10.0 * k
	_av += Vector3(deg_to_rad(float(rc.recoil)) * 9.0, randf_range(-0.6, 0.6) * float(rc.side), randf_range(-1.5, 1.5)) * k
	if spec.action != "draw":
		_flash.pop(flash_seed)
		flash_seed = -1
	if side == "l":
		action_l = 0.0
	elif spec.action in ["bolt", "pump", "slide"]:
		action_t = 0.0
	draw = 0.0


## Tools: the next flash's seed (fixed frames); -1 random.
var flash_seed := -1


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
func update(delta: float, aiming: bool, speed01: float, grounded: bool, stance: String, look: Vector2, strafe := 0.0) -> void:
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
	# springs
	_rv += (-_rp * 260.0 - _rv * 24.0) * delta
	_rp += _rv * delta
	_av += (-_ap * 220.0 - _av * 20.0) * delta
	_ap += _av * delta
	# sway: lag behind the look, settle back
	var sw := FpsTune.value("sway") * float(spec.get("sway", 1.0)) * (1.0 - e * 0.8)
	_sway = _sway.lerp(Vector2(-look.x, -look.y) * 0.0018 * sw, minf(1.0, delta * 10.0))
	_strafe = lerpf(_strafe, strafe, minf(1.0, delta * 6.0))
	var drift := side_drift() * float(spec.get("sway", 1.0)) * (1.0 - e * 0.5)
	# bob: the run cycle, scaled by speed
	var moving := speed01 if grounded else 0.0
	_bob_amt = move_toward(_bob_amt, moving * FpsTune.value("bob") * (1.0 - e * 0.85), delta * 4.0)
	_bob += delta * (7.0 + 5.0 * speed01) * (0.5 if stance == "prone" else 1.0)
	var bob := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.011, 0.0) * _bob_amt
	var breathe := Vector3(0, sin(Time.get_ticks_msec() * 0.0021) * 0.002, 0) * (1.0 - e * 0.6)
	# where it sits
	var hip: Vector3 = spec.hip
	var has_eye := asset.markers.has("eye") or optic != null
	var aim_at := Vector3(0, 0, -float(spec.get("ads_dist", 0.06))) if has_eye else Vector3(0, -0.03, -0.5)
	var ads_pos := aim_at - R * (_eye_point if has_eye else asset.marker("muzzle").origin)
	var side := Vector3(-_strafe * 0.012 * sw + drift.x * 1.5, 0, 0)
	var pos := hip.lerp(ads_pos, e) + bob + breathe + side + _rp * Vector3(1, 1, 1)
	var rot := Vector3(_sway.y + _ap.x * 0.02 + drift.y, _sway.x + _ap.y * 0.02 + drift.x * 2.0 + _strafe * 0.02 * sw,
		_ap.z * 0.02 + sin(_bob * 0.5) * 0.01 * _bob_amt - _strafe * 0.05 * sw)
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
	_flash.transform = Transform3D(fx.basis.orthonormalized(), fx * asset.marker("muzzle").origin) * Transform3D(Basis(Vector3.BACK, _flash.roll), Vector3.ZERO)
	_lens_follow()
	if optic and gun:
		var cam := get_parent() as Node3D
		if cam:
			optic.track(gun.global_transform.affine_inverse() * cam.global_transform)


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


## G51 sideways sway: a slow figure-eight (radians: x yaw, y pitch), scaled
## by FpsTune sway (2.3 = 1x) and sway_side. The player adds it to the camera
## (doubled in a scope) and the gun carries it.
func side_drift() -> Vector2:
	var t := Time.get_ticks_msec() * 0.001
	var k := 0.0035 * FpsTune.value("sway_side") * FpsTune.value("sway") / 2.3
	return Vector2(sin(t * 0.9) + 0.25 * sin(t * 2.3 + 1.0), 0.35 * sin(t * 1.8)) * k


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
