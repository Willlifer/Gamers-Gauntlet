class_name FpsPlayer
extends CharacterBody3D
## You, in first person. Nothing of your body is drawn; the camera sits at
## eye height and carries the view model (FpsViewmodel).
##   WASD move · mouse look · Space jump (or stand up) · Shift tap: crouch /
##   stand · Shift hold: lie down · LMB fire (slingshot: hold to draw, release
##   to loose) · RMB aim in · R reload · 1 2 3 / wheel: weapons · F1 tuning
## Inaccuracy is one number per frame (spread_deg); the reticle draws it, the
## shots use it, so the crosshair never lies.

signal fired(from: Vector3, hits: Array)
signal died

const EYE := { "stand": 1.98, "crouch": 1.32, "prone": 0.46 }
const BODY_H := { "stand": 2.1, "crouch": 1.45, "prone": 0.72 }
const RADIUS := 0.36
const GRAVITY := 12.25                      ## 9.8 on the 1.25 body scale

var world: FpsWorld                         ## effects, damage
var cam: Camera3D
var vm: FpsViewmodel
var hp := 100.0
var alive := true
var stance := "stand"
var weapon := "sniper"
var ammo := {}
var spread_deg := 0.0
var speed01 := 0.0
var aiming := false
var scoped := false                         ## the sniper's scope is up (the HUD draws it)
var input_on := true
var debug_aim := false                      ## tools: hold aim without a mouse
var debug_move := Vector2.ZERO              ## tools: x strafe, y forward (-1..1)
var debug_fire := false                     ## tools: hold the trigger
var _pitch := 0.0
var _eye := 1.98
var _shift_t := -1.0
var _look := Vector2.ZERO
var _cool := 0.0                            # until the next shot
var _bloom := 0.0                           # shot bloom, degrees, decays
var _shape: CollisionShape3D
var _drawing := false
var _punch := 0.0


func _ready() -> void:
	collision_layer = 4                     # the player's body (bots aim at it)
	collision_mask = 1
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = BODY_H.stand
	_shape.shape = cap
	_shape.position.y = BODY_H.stand * 0.5
	add_child(_shape)
	cam = Camera3D.new()
	cam.position.y = EYE.stand
	cam.cull_mask = 1                       # the world, not the view model
	cam.near = 0.05
	cam.far = 1500.0
	add_child(cam)
	vm = FpsViewmodel.new()
	cam.add_child(vm)
	for id in FpsWeapons.ORDER:
		ammo[id] = int(FpsWeapons.SPECS[id].mag)
	vm.equip(weapon)


func spec() -> Dictionary:
	return FpsWeapons.SPECS[weapon]


func _unhandled_input(ev: InputEvent) -> void:
	if not input_on or not alive:
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := FpsTune.value("mouse_sens") * 0.001 * (FpsTune.value("ads_sens") if aiming else 1.0)
		if scoped:
			sens /= FpsTune.value("scope_zoom")
		rotate_y(-ev.relative.x * sens)
		_pitch = clampf(_pitch - ev.relative.y * sens, -1.45, 1.45)
		_look += ev.relative
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_SPACE:
				if stance != "stand":
					stance = "stand"
				elif is_on_floor():
					velocity.y = FpsTune.value("jump")
			KEY_R:
				_reload()
			KEY_1, KEY_2, KEY_3:
				_switch(FpsWeapons.ORDER[ev.physical_keycode - KEY_1])
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var i := FpsWeapons.ORDER.find(weapon) + (1 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			_switch(FpsWeapons.ORDER[posmod(i, FpsWeapons.ORDER.size())])


func _switch(id: String) -> void:
	if id == weapon:
		return
	weapon = id
	vm.equip(id)
	_cool = 0.35
	_drawing = false


func _reload() -> void:
	var sp := spec()
	if int(sp.mag) <= 0 or ammo[weapon] >= int(sp.mag) or vm.reload_t >= 0.0:
		return
	vm.start_reload()
	_cool = float(sp.reload)
	if sp.get("shell_reload", false):
		ammo[weapon] += 1                    # a shell at a time: R again (or it keeps going below)
	else:
		ammo[weapon] = int(sp.mag)


func _physics_process(delta: float) -> void:
	var cap := _shape.shape as CapsuleShape3D
	# stance: tap Shift to crouch / stand, hold it to lie down
	if input_on and alive and Input.is_physical_key_pressed(KEY_SHIFT):
		if _shift_t < 0.0:
			_shift_t = 0.0
		_shift_t += delta
		if _shift_t >= FpsTune.value("prone_hold") and stance != "prone" and _shift_t < 99.0:
			stance = "prone"
			_shift_t = 99.0                  # held: done until released
	elif _shift_t >= 0.0:
		if _shift_t < FpsTune.value("prone_hold"):
			stance = "stand" if stance == "crouch" else "crouch"
		_shift_t = -1.0
	var want_h: float = BODY_H[stance]
	cap.height = move_toward(cap.height, want_h, delta * 4.0)
	cap.radius = minf(RADIUS, cap.height * 0.5)
	_shape.position.y = cap.height * 0.5
	_eye = move_toward(_eye, float(EYE[stance]), delta * 4.5)
	# movement
	var dir := Vector3.ZERO
	if input_on and alive:
		var f := int(Input.is_physical_key_pressed(KEY_W)) - int(Input.is_physical_key_pressed(KEY_S))
		var s := int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
		if debug_move != Vector2.ZERO:
			f = int(signf(debug_move.y))
			s = int(signf(debug_move.x))
		dir = (-transform.basis.z * f + transform.basis.x * s)
		dir.y = 0.0
		dir = dir.normalized()
	var top := FpsTune.value("run_speed")
	if stance == "crouch":
		top = FpsTune.value("crouch_speed")
	elif stance == "prone":
		top = FpsTune.value("prone_speed")
	if aiming:
		top *= FpsTune.value("ads_move")
	var hv := Vector3(velocity.x, 0, velocity.z)
	var accel := FpsTune.value("accel") * (1.0 if is_on_floor() else 0.25)
	hv = hv.move_toward(dir * top, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	speed01 = clampf(Vector2(velocity.x, velocity.z).length() / FpsTune.value("run_speed"), 0.0, 1.0)
	_weapon(delta)


func _process(delta: float) -> void:
	aiming = input_on and alive and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or debug_aim)
	_punch = move_toward(_punch, 0.0, delta * 0.5)
	cam.position.y = _eye
	cam.rotation.x = _pitch + _punch
	var sp := spec()
	scoped = bool(sp.scope) and vm.ads > 0.97
	var base := FpsTune.value("fov")
	var div := FpsTune.value("scope_zoom") if scoped else lerpf(1.0, float(sp.ads_div), vm.ads)
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) / div))
	vm.visible = not scoped
	vm.update(delta, aiming, speed01, is_on_floor(), stance, _look)
	_look = Vector2.ZERO
	# one inaccuracy number: hip / aimed cone, the run, the air, the stance, the bloom
	var aimw := vm.ads
	var cone := lerpf(float(sp.spread), float(sp.ads_spread), aimw)
	cone += float(sp.move_spread) * FpsTune.value("move_spread") * speed01 * (1.0 - 0.4 * aimw)
	if not is_on_floor():
		cone += 6.0
	cone *= { "stand": 1.0, "crouch": 0.75, "prone": 0.55 }[stance]
	_bloom = move_toward(_bloom, 0.0, delta * 9.0)
	spread_deg = cone + _bloom


func _weapon(delta: float) -> void:
	_cool -= delta
	var sp := spec()
	if not alive or not input_on:
		_drawing = false
		return
	var held := (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) or debug_fire
	if sp.action == "draw":
		if held and _cool <= 0.0:
			_drawing = true
			vm.draw = minf(1.0, vm.draw + delta / float(sp.draw_time))
		elif _drawing:
			_drawing = false
			if vm.draw > 0.2:
				_shoot(vm.draw)
			vm.draw = 0.0
		return
	# shell-by-shell reload keeps going while the tube isn't full and you don't shoot
	if sp.get("shell_reload", false) and vm.reload_t < 0.0 and _cool <= 0.0 and ammo[weapon] < int(sp.mag) and ammo[weapon] > 0 and not held and _reload_pending:
		_reload()
	if held and _cool <= 0.0 and vm.reload_t < 0.0:
		if ammo[weapon] <= 0:
			_reload_pending = true
			_reload()
			return
		_reload_pending = false
		_shoot(1.0)


var _reload_pending := false


## Fire: hitscan pellets inside the current cone (the slingshot looses a ball).
func _shoot(power: float) -> void:
	var sp := spec()
	_cool = float(sp.cycle)
	if int(sp.mag) > 0:
		ammo[weapon] -= 1
		if ammo[weapon] <= 0:
			_reload_pending = true
	vm.fire()
	_bloom += float(sp.recoil) * 0.35
	_punch += deg_to_rad(float(sp.recoil)) * 0.12 * FpsTune.value("recoil") * (0.4 if scoped else 1.0)
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	if sp.action == "draw":
		var dir := _cone(fwd, spread_deg)
		world.loose_ball(vm.muzzle_global(), dir * float(sp.ball_speed) * lerpf(0.55, 1.0, power), self, float(sp.damage) * lerpf(0.35, 1.0, power))
		return
	var hits := []
	for k in int(sp.pellets):
		var dir := _cone(fwd, spread_deg)
		var hit := world.trace(from, from + dir * float(sp.range), [get_rid()])
		hits.append(hit)
		var end: Vector3 = hit.position if not hit.is_empty() else from + dir * float(sp.range)
		world.tracer(vm.muzzle_global() if not scoped else from + fwd * 0.3 + Vector3(0, -0.15, 0), end, sp.tracer)
		if not hit.is_empty():
			world.on_hit(self, hit, float(sp.damage), float(sp.head))
	fired.emit(from, hits)


static func _cone(fwd: Vector3, deg: float) -> Vector3:
	if deg <= 0.001:
		return fwd
	var r := deg_to_rad(deg) * 0.5 * sqrt(randf())
	var a := randf() * TAU
	var side := fwd.cross(Vector3.UP).normalized() if absf(fwd.y) < 0.99 else Vector3.RIGHT
	var up := side.cross(fwd).normalized()
	return (fwd + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


func take_damage(d: float) -> void:
	if not alive:
		return
	hp -= d
	if hp <= 0.0:
		hp = 0.0
		alive = false
		died.emit()


func respawn(at: Transform3D) -> void:
	global_transform = at
	velocity = Vector3.ZERO
	hp = 100.0
	alive = true
	stance = "stand"
	_pitch = 0.0
	for id in FpsWeapons.ORDER:
		ammo[id] = int(FpsWeapons.SPECS[id].mag)
	vm.equip(weapon)
