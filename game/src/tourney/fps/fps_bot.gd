class_name FpsBot
extends CharacterBody3D
## The enemy: a Black | White character (walk/run/kneel clips from the
## "heavy" set) carrying the kit sniper, held through GKBWHold so the clips
## move the body while the hands keep the rifle. Hitboxes: a body capsule
## (shape 0) and a head sphere (shape 1, the headshot).
## Behaviour, on its own roof: run to a cover spot, kneel, peek; when it sees
## you it turns, shoulders the rifle, waits its reaction time and fires
## (accuracy from FpsTune, worse when you move or lie down, at range).

signal died

const HEAD_Y := { "stand": 1.92, "crouch": 1.32 }
const GRAVITY := 12.25

var world: FpsWorld
var ch: BWCharacter
var gun_asset: GKAsset
var gun: Node3D
var hp := 100.0
var alive := true
var crouched := false
var roof: Array = []                       ## Rect2s it may walk (world xz)
var target: Node3D                         ## the player
var _goal := Vector3.INF
var _state := "move"
var _t := 0.0                              # time in the state
var _seen := 0.0                           # how long it has seen you
var _cool := 0.0
var _stuck := 0.0
var _body: CollisionShape3D
var _head: CollisionShape3D
var _rng := RandomNumberGenerator.new()
var _yaw := 0.0


func _ready() -> void:
	_rng.seed = 77
	collision_layer = 8
	collision_mask = 1
	_body = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	_body.shape = cap
	_body.position.y = 0.88
	add_child(_body)
	_head = CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.25
	_head.shape = sp
	_head.position.y = HEAD_Y.stand
	add_child(_head)
	BWCharacter.animate = true
	ch = BWCharacter.create(_unit())
	add_child(ch)
	gun_asset = GKRegistry.build("sniper", { "scale": 1.25, "bipod": "folded" })
	gun = GKBWHold.swap_weapon(ch, gun_asset)
	GKBWHold.hold_rifle(ch, gun_asset, "low")


## A dressed fighter with a two-handed weapon, so the "heavy" clip set
## (walk, run, kneel) drives it; the weapon itself is swapped for the rifle.
func _unit() -> BWUnit:
	var u := BWUnit.new()
	u.id = "fps_bot"
	u.name = "Gorbo"
	u.team = "enemy"
	var pick := ""
	for id in BWWeaponView.ids():
		if BWCharacterPose.style_for(BWWeaponView.meta_for(id)) == "heavy":
			pick = id
			break
	u.weapon_model = pick
	u.weapon_class = str(BWWeaponView.meta_for(pick).get("class", "sword"))
	u.cosmetics = { "hair_style": "buzzed", "hair_hex": "#8b5a2b", "gender": "m", "top": "hoodie", "bottom": "baggy_sweatpants", "clothing_shade": "dark" }
	for s in BWUnit.STATS:
		u.stats[s] = 5
	u.hp = u.max_hp()
	return u


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if not alive:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_t += delta
	_cool -= delta
	var sees := _can_see()
	_seen = _seen + delta if sees else maxf(_seen - delta * 2.0, 0.0)
	match _state:
		"move":
			if sees and _seen > 0.15:
				_set_state("engage")
			elif _goal == Vector3.INF or _flat(global_position).distance_to(_flat(_goal)) < 0.6:
				_set_state("hold")
			else:
				_run_to(_goal, delta)
		"hold":
			_stop()
			crouched = true
			if sees and _seen > 0.15:
				_set_state("engage")
			elif _t > _rng.randf_range(2.5, 4.5):
				_goal = _pick_spot()
				_set_state("move")
		"engage":
			_stop()
			crouched = _rng.randf() < 0.0           # stands to shoot; kneels again in hold
			_face(target.global_position, delta)
			if not sees and _seen <= 0.0:
				_goal = _pick_spot()
				_set_state("move")
			elif _seen >= FpsTune.value("bot_reaction") and _cool <= 0.0:
				_fire()
				_cool = 1.6 + _rng.randf() * 0.6
				if _rng.randf() < 0.3:
					_goal = _pick_spot()
					_set_state("move")
	move_and_slide()
	if velocity.length() < 0.3 and _state == "move":
		_stuck += delta
		if _stuck > 1.0:
			_goal = _pick_spot()
			_stuck = 0.0
	else:
		_stuck = 0.0
	_animate(delta)


func _set_state(s: String) -> void:
	_state = s
	_t = 0.0
	if s == "move":
		crouched = false


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _run_to(p: Vector3, delta: float) -> void:
	var d := p - global_position
	d.y = 0.0
	var v := d.normalized() * FpsTune.value("bot_speed")
	velocity.x = move_toward(velocity.x, v.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, v.z, 30.0 * delta)
	_face(global_position + d, delta)


func _stop() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1.0)
	velocity.z = move_toward(velocity.z, 0.0, 1.0)


func _face(p: Vector3, delta: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	_yaw = lerp_angle(_yaw, atan2(d.x, d.z), minf(1.0, delta * 8.0))
	rotation.y = _yaw


## A spot on its roof near cover (any low collider), clear of the edge.
func _pick_spot() -> Vector3:
	var y := global_position.y
	for i in 20:
		var r: Rect2 = roof[_rng.randi() % roof.size()]
		var p := Vector3(_rng.randf_range(r.position.x + 3.0, r.end.x - 3.0), y + 0.5, _rng.randf_range(r.position.y + 3.0, r.end.y - 3.0))
		# not inside anything: a short down ray lands on the roof membrane
		var hit := world.trace(p + Vector3(0, 2.0, 0), p + Vector3(0, -3.0, 0), [get_rid()])
		if not hit.is_empty() and absf(hit.position.y - y) < 0.4:
			return hit.position
	return global_position


func eye() -> Vector3:
	return global_position + Vector3(0, _head.position.y, 0)


func _can_see() -> bool:
	if target == null or not target.alive:
		return false
	var to: Vector3 = target.cam.global_position
	var hit := world.trace(eye(), to, [get_rid()], 1 | 4)
	return not hit.is_empty() and hit.collider == target


func _fire() -> void:
	var to: Vector3 = target.cam.global_position + Vector3(0, -0.5, 0)
	var dist := eye().distance_to(to)
	var acc := FpsTune.value("bot_accuracy")
	acc *= lerpf(1.0, 0.55, float(target.speed01))
	acc *= { "stand": 1.0, "crouch": 0.85, "prone": 0.6 }[target.stance]
	acc *= clampf(1.15 - dist / 140.0, 0.35, 1.0)
	var muzzle := gun.global_transform * gun_asset.marker("muzzle").origin
	world.muzzle_flash(muzzle, (to - muzzle).normalized())
	# the roll picks where it aims; the bullet still has to get there (G28):
	# a good roll aims at the chest (or the head, 12%), a bad one beside you
	var aim := to
	if _rng.randf() < acc:
		if _rng.randf() < 0.12:
			aim = target.cam.global_position
	else:
		aim = to + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.6, 1.4), _rng.randf_range(-1.2, 1.2))
	world.fire_bullet(muzzle, (aim - muzzle).normalized(), self, 34.0, 100.0 / 34.0, 300.0, Color(1.0, 0.75, 0.45), muzzle)
	world.shot_near_player(muzzle)


func _animate(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	var want := "run" if moving else ("kneel" if crouched else "idle")
	if ch.pose_name() != want:
		ch.pose(want)
	var aim := _state == "engage"
	var pitch := 0.0
	if aim and target:
		var d: Vector3 = target.cam.global_position - eye()
		pitch = atan2(d.y, Vector2(d.x, d.z).length())
	GKBWHold.hold_rifle(ch, gun_asset, "aim" if aim else "low", pitch)
	_head.position.y = move_toward(_head.position.y, HEAD_Y.crouch if crouched and not moving else HEAD_Y.stand, delta * 3.0)
	var cap := _body.shape as CapsuleShape3D
	cap.height = 1.2 if crouched and not moving else 1.75
	_body.position.y = cap.height * 0.5


func hurt(d: float, head: bool) -> void:
	if not alive:
		return
	hp -= d * (1.0 if not head else 1.0)
	if _state != "engage":
		_set_state("engage")
		_seen = FpsTune.value("bot_reaction") * 0.6
	if hp <= 0.0:
		alive = false
		GKBWHold.release(ch)
		ch.pose("fall")
		_body.disabled = true
		_head.disabled = true
		died.emit()


func respawn(at: Transform3D) -> void:
	global_transform = at
	_yaw = rotation.y
	hp = 100.0
	alive = true
	_body.disabled = false
	_head.disabled = false
	ch.pose("idle")
	_goal = _pick_spot()
	_set_state("move")
