class_name FpsBot
extends CharacterBody3D
## The enemy: a Black | White character (walk/run/kneel clips from the
## "heavy" set) carrying a kit gun, held through GKBWHold so the clips move
## the body while the hands keep the gun. Hitboxes: a body capsule (shape 0)
## and a head sphere (shape 1, the headshot).
## G62: it navigates. FpsWorld bakes a NavigationMesh per map (FpsNav) and
## the bot walks paths on it: the rooftop bridge, the stairwells and the
## floor below, both Dust lanes, the campus's cover. Its mind is a few
## states:
##   move     walking a path to a spot (cover near where it thinks you are)
##   hold     kneeling at that cover for a moment
##   peek     stepping out to a point that sees your last known position
##   engage   facing you, shouldering the gun, firing bursts after its
##            reaction time (accuracy from FpsTune, worse when you move or
##            lie down, at range); after a burst it may push closer
##   retreat  breaking line of sight when it is hurt or has emptied a burst
## `bot_push` (F1) weighs how close it tries to get; `bot_peek` how long it
## stands out; `bot_retreat_hp` when it falls back. The aim roll is the
## same as before (G28): a good roll aims at the chest, a bad one beside
## you, and the bullet still has to land.
## G43: it carries a primary picked each life (set_weapon) and fires it the
## gun's way: bursts from the automatics, pellets from the shotgun, single
## shots otherwise. Bushes (the map's hide volumes) hide you past 3 m and
## hide it too; on the campus it likes to wait in them.

signal died

const HEAD_Y := { "stand": 1.92, "crouch": 1.32 }
const GRAVITY := 12.25
const REPATH := 0.6                         ## seconds between path refreshes
const WAYPOINT := 0.55                      ## metres: close enough to the next waypoint

var world: FpsWorld
var ch: BWCharacter
var gun_asset: GKAsset
var gun: Node3D
var weapon := "sniper"
var _burst := 0                            # bullets left in this burst
var _burst_t := 0.0
var hp := 100.0
var alive := true
var crouched := false
var roof: Array = []                       ## Rect2s it may walk without a mesh (world xz; the old fallback)
var target: Node3D                         ## the player (null in the probe's drills)
var _goal := Vector3.INF
var _route: Array[Vector3] = []            # legacy: waypoints after _goal (used only without a mesh)
var _path := PackedVector3Array()          # the mesh path to _goal
var _path_i := 0
var _path_t := 0.0                         # since the last path refresh
var _peek := Vector3.INF                   # where to step out to from the hold spot
var _hold_spot := Vector3.INF
var _known := Vector3.INF                  ## where it last saw (or was shot from) you
var _known_t := 99.0                       # seconds since
var _state := "move"
var _t := 0.0                              # time in the state
var _seen := 0.0                           # how long it has seen you
var _cool := 0.0
var _stuck := 0.0
var _hold_for := 2.0
var _body: CollisionShape3D
var _head: CollisionShape3D
var _rng := RandomNumberGenerator.new()
var _yaw := 0.0
## Tools: drills (the probe) set a goal and watch it arrive; no shooting.
var drill := false
var crossings := 0                         ## tools: times it has been over the rooftop court (the bridge)


func _ready() -> void:
	_rng.seed = 77
	collision_layer = 8
	collision_mask = 1 | GKAsset.BARRIER_LAYER
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
	set_weapon(weapon)


## Hold `id` (a FpsWeapons gun) for this life.
func set_weapon(id: String) -> void:
	weapon = id if FpsWeapons.available(id) else "sniper"
	if ch == null:
		return
	var sp: Dictionary = FpsWeapons.SPECS[weapon]
	var params: Dictionary = (sp.params as Dictionary).duplicate()
	if weapon == "sniper":
		params = { "scale": 1.25, "bipod": "folded" }
	gun_asset = GKRegistry.build(str(sp.asset), params)
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


func nav() -> FpsNav:
	return world.nav if world else null


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
	_known_t += delta
	_path_t += delta
	var sees := _can_see() and not drill
	_seen = _seen + delta if sees else maxf(_seen - delta * 2.0, 0.0)
	if sees:
		_known = target.global_position
		_known_t = 0.0
	var hunt := world != null and bool(world.map.meta.get("bot_hunt", false))
	match _state:
		"move", "retreat":
			if sees and _seen > 0.15 and (_state == "move" or _seen > 0.6 or hp > FpsTune.value("bot_retreat_hp")):
				_set_state("engage")
			elif _arrived():
				if not _route.is_empty():
					_goal = _route.pop_front()       # the old two-point stairwell route (no mesh)
					_path = PackedVector3Array()
				else:
					_hold_spot = global_position
					_peek = _peek_point()
					_hold_for = _rng.randf_range(0.8, 1.8) if hunt else _rng.randf_range(2.0, 4.0)
					_set_state("hold")
			else:
				_follow(delta)
		"hold":
			_stop()
			crouched = true
			if _known != Vector3.INF:
				_face(_known, delta)
			if sees and _seen > 0.15:
				_set_state("engage")
			elif _t > _hold_for:
				if _peek != Vector3.INF and _known_t < 12.0 and _rng.randf() < 0.7:
					_set_state("peek")
				else:
					_go(_pick_spot())
		"peek":
			crouched = false
			if sees and _seen > 0.1:
				_set_state("engage")
			elif _t > FpsTune.value("bot_peek") + 0.6:
				# nothing there: back behind cover, or on to the next spot
				if _rng.randf() < 0.5 and _hold_spot != Vector3.INF:
					_go(_hold_spot)
				else:
					_go(_pick_spot())
			elif global_position.distance_to(_peek) > WAYPOINT:
				_run_to(_peek, delta)
			else:
				_stop()
				if _known != Vector3.INF:
					_face(_known, delta)
		"engage":
			_stop()
			crouched = false
			if target:
				_face(target.global_position, delta)
			_burst_t -= delta
			if _burst > 0 and _burst_t <= 0.0 and sees:
				_fire()
				_burst -= 1
				_burst_t = float(FpsWeapons.SPECS[weapon].cycle)
				if _burst <= 0:
					_after_burst()
			elif not sees and _seen <= 0.0:
				_burst = 0
				if _t < 0.4 and _known != Vector3.INF:
					_go(_pick_spot())                  # it slipped away: chase the last sighting
				else:
					_go(_pick_spot())
			elif _burst <= 0 and _seen >= FpsTune.value("bot_reaction") and _cool <= 0.0:
				var sp: Dictionary = FpsWeapons.SPECS[weapon]
				_burst = _rng.randi_range(3, 6) if sp.get("auto", false) or sp.get("dual", false) else 1
				_burst_t = 0.0
				_cool = (1.6 + _rng.randf() * 0.6) * (0.7 if sp.get("auto", false) else (0.55 if sp.action == "slide" else 1.0))
	if _unstick_t > 0.0:
		# G62: backed against a kerb or a ramp's side: back off along the path for a moment, then re-path
		_unstick_t -= delta
		var back := (_path[maxi(_path_i - 1, 0)] if _path.size() > 0 else global_position) - global_position
		back.y = 0.0
		if back.length() < 0.3:
			back = -Vector3(velocity.x, 0, velocity.z).normalized() if velocity.length() > 0.1 else Vector3(cos(_yaw + PI), 0, sin(_yaw + PI))
		velocity.x = back.normalized().x * FpsTune.value("bot_speed") * 0.6
		velocity.z = back.normalized().z * FpsTune.value("bot_speed") * 0.6
	move_and_slide()
	if Vector2(velocity.x, velocity.z).length() < 0.3 and _state in ["move", "retreat"] and _unstick_t <= 0.0:
		_stuck += delta
		if _stuck > 0.6:
			_unstick_t = 0.4
			_path = PackedVector3Array()           # back off, then a fresh path
			_path_t = REPATH
			_stuck = 0.0
			_unsticks += 1
			if _unsticks >= 4 and not drill:
				_unsticks = 0
				_route.clear()
				_go(_pick_spot())
	elif Vector2(velocity.x, velocity.z).length() >= 0.3:
		_stuck = 0.0
	if world and world.map.meta.has("roofs") and absf(global_position.x) < float(world.map.meta.get("gap_half", 11.25)) - 1.0 and not _over_court:
		_over_court = true
		crossings += 1
	elif world and world.map.meta.has("roofs") and absf(global_position.x) >= float(world.map.meta.get("gap_half", 11.25)):
		_over_court = false
	_animate(delta)


var _over_court := false
var _unstick_t := 0.0
var _unsticks := 0


## After a burst: wounded, break line of sight; otherwise half the time
## push to a closer spot, else hold here for the next burst.
func _after_burst() -> void:
	if hp < FpsTune.value("bot_retreat_hp"):
		_go(_cover_spot(), "retreat")
	elif _rng.randf() < 0.35 + 0.4 * FpsTune.value("bot_push"):
		_go(_pick_spot())


func _set_state(s: String) -> void:
	_state = s
	_t = 0.0
	if s in ["move", "retreat", "peek"]:
		crouched = false


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Walk to `p` (through the mesh when there is one).
func _go(p: Vector3, state := "move") -> void:
	_goal = p
	_unsticks = 0
	_path = PackedVector3Array()
	_path_i = 0
	_path_t = REPATH
	_set_state(state)


## Tools: the probe's drill. The bot walks to `p` and does nothing else.
func drill_to(p: Vector3) -> void:
	drill = true
	_route.clear()
	_go(p)


func _arrived() -> bool:
	if _goal == Vector3.INF:
		return true
	var d := _flat(global_position).distance_to(_flat(_goal))
	return d < 0.7 and absf(global_position.y - _goal.y) < 1.6


## Along the mesh path to _goal, refreshed every REPATH seconds; a straight
## run when the map has no mesh.
func _follow(delta: float) -> void:
	var n := nav()
	if n == null or not n.ready():
		_run_to(_goal, delta)
		return
	if _path.is_empty() or _path_t >= REPATH:
		_path = n.path(global_position, _goal)
		_path_i = 0
		_path_t = 0.0
		if _path.size() < 2:
			_run_to(_goal, delta)
			return
	while _path_i < _path.size() - 1 and _flat(global_position).distance_to(_flat(_path[_path_i])) < WAYPOINT:
		_path_i += 1
	_run_to(_path[_path_i], delta)


func _run_to(p: Vector3, delta: float) -> void:
	var d := p - global_position
	d.y = 0.0
	var v := d.normalized() * FpsTune.value("bot_speed") * (0.85 if _state == "peek" else 1.0)
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


## Where it thinks you are: the last sighting, or (nothing seen yet) a guess
## within 20 m of where you really are, so it heads for your side of the map.
func _guess() -> Vector3:
	if _known != Vector3.INF and _known_t < 25.0:
		return _known
	if target == null:
		return global_position
	var tp: Vector3 = target.global_position
	return tp + Vector3(_rng.randf_range(-20.0, 20.0), 0, _rng.randf_range(-20.0, 20.0))


## A spot to go to: on the mesh, reachable, scored for hunting: a walk of
## 6-28 m from where you are (closer with bot_push), hidden from your last
## known head position, with a peek point beside it, and not where it is
## already standing. On a map with bushes, a third of the time the middle
## of a bush. Without a mesh: the old straight-line pick on its own roof.
func _pick_spot() -> Vector3:
	var n := nav()
	if n == null or not n.ready():
		return _pick_spot_legacy()
	var guess := _guess()
	var hunt: bool = world.map.meta.get("bot_hunt", false) or target != null
	var push := FpsTune.value("bot_push")
	var best := Vector3.INF
	var best_score := -INF
	var fallback := Vector3.INF
	var fallback_walk := INF
	var tries := 26
	for i in tries:
		var p := Vector3.INF
		if not world.hide_volumes.is_empty() and i % 3 == 0:
			var h: Dictionary = world.hide_volumes[_rng.randi() % world.hide_volumes.size()]
			p = n.snap(h.center)
			if p.distance_to(h.center as Vector3) > 2.0:
				continue
		else:
			p = n.random_point()
		if p == Vector3.INF or _flat(p).distance_to(_flat(global_position)) < 3.0:
			continue
		var d_me := _flat(p).distance_to(_flat(guess))
		var sc := _rng.randf() * 2.0
		if hunt:
			var want := lerpf(24.0, 8.0, push)
			sc -= absf(d_me - want) * 0.18
			if d_me < 4.0:
				sc -= 4.0
			if target != null and not drill:
				var los := world.trace(p + Vector3(0, HEAD_Y.stand, 0), guess + Vector3(0, 1.5, 0), [get_rid()], 1)
				if not los.is_empty():
					sc += 3.0                        # cover from where you were
				else:
					sc -= 1.0
		else:
			sc += minf(_flat(p).distance_to(_flat(global_position)), 30.0) * 0.08
		if sc <= best_score:
			continue
		var walk := n.walk_length(global_position, p)
		if walk == INF:
			continue
		if fallback == Vector3.INF or walk < fallback_walk:
			fallback = p                             # anywhere it can get to, if nothing scores
			fallback_walk = walk
		if walk > 160.0:
			continue
		sc -= walk * 0.03
		if sc > best_score:
			best_score = sc
			best = p
	if best != Vector3.INF:
		return best
	return fallback if fallback != Vector3.INF else global_position


## Somewhere near (4-14 m walk) with no line from your last known position.
func _cover_spot() -> Vector3:
	var n := nav()
	var guess := _guess()
	if n == null or not n.ready():
		return _pick_spot_legacy()
	var best := Vector3.INF
	var best_score := -INF
	for i in 24:
		var p := n.random_point()
		var d := _flat(p).distance_to(_flat(global_position))
		if d < 3.0 or d > 16.0:
			continue
		var los := world.trace(p + Vector3(0, HEAD_Y.crouch, 0), guess + Vector3(0, 1.5, 0), [get_rid()], 1)
		var sc := _rng.randf() + (4.0 if not los.is_empty() else 0.0) - d * 0.1 + _flat(p).distance_to(_flat(guess)) * 0.05
		if sc > best_score and n.reachable(global_position, p):
			best_score = sc
			best = p
	return best if best != Vector3.INF else _pick_spot()


## From the hold spot: a point a step or two aside that sees your last known
## head position (INF when none does, or nothing is known).
func _peek_point() -> Vector3:
	var n := nav()
	if n == null or not n.ready() or _known == Vector3.INF or target == null or drill:
		return Vector3.INF
	var head: Vector3 = _known + Vector3(0, 1.5, 0)
	var here := global_position
	for k in 8:
		var a := k * TAU / 8.0 + _rng.randf() * 0.4
		var q := n.snap(here + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.4, 2.6))
		if q.distance_to(here) > 3.2 or q.distance_to(here) < 0.8:
			continue
		if world.trace(q + Vector3(0, HEAD_Y.stand, 0), head, [get_rid()], 1).is_empty():
			return q
	return Vector3.INF


## The pre-mesh pick (G51): a spot on its own roof it can walk to in a line.
func _pick_spot_legacy() -> Vector3:
	var y := global_position.y
	var via := _stairs_route()
	if via != Vector3.INF:
		return via
	if roof.is_empty():
		return global_position
	if not world.hide_volumes.is_empty() and _rng.randf() < 0.5:
		var mine := world.hide_volumes.filter(func(h: Dictionary) -> bool:
			var c: Vector3 = h.center
			return roof.any(func(r: Rect2) -> bool: return r.has_point(Vector2(c.x, c.z))))
		if not mine.is_empty():
			var h: Dictionary = mine[_rng.randi() % mine.size()]
			var c: Vector3 = h.center
			return Vector3(c.x, y, c.z)
	var hunt: bool = world.map.meta.get("bot_hunt", false) and target != null
	var best := Vector3.INF
	var best_score := -INF
	for i in (30 if hunt else 20):
		var r: Rect2 = roof[_rng.randi() % roof.size()]
		var p := Vector3(_rng.randf_range(r.position.x + 1.5 if hunt else r.position.x + 3.0, r.end.x - (1.5 if hunt else 3.0)), y + 0.5,
			_rng.randf_range(r.position.y + (1.5 if hunt else 3.0), r.end.y - (1.5 if hunt else 3.0)))
		var hit := world.trace(p + Vector3(0, 2.0, 0), p + Vector3(0, -3.0, 0), [get_rid()])
		if hit.is_empty() or absf(hit.position.y - y) >= 0.4:
			continue
		var at: Vector3 = hit.position
		if not world.walk_clear(global_position, at):
			continue
		if not hunt:
			return at
		var sc := -at.distance_to(target.global_position) * 0.1 + _rng.randf() * 2.0
		var los := world.trace(at + Vector3(0, HEAD_Y.stand, 0), target.global_position + Vector3(0, 1.4, 0), [get_rid()], 1)
		if los.is_empty():
			sc += 6.0
		if sc > best_score:
			best_score = sc
			best = at
	return best if best != Vector3.INF else global_position


## G51c, without a mesh: a stairwell as a two-point route (meta.stairs).
func _stairs_route() -> Vector3:
	var stairs: Array = world.map.meta.get("stairs", [])
	if stairs.is_empty() or not _route.is_empty():
		return Vector3.INF
	var floor_y := float(world.map.meta.get("floor_height", -100.0))
	var inside := global_position.y < floor_y + 1.0
	var want := _rng.randf() < 0.15
	if target != null and target.alive:
		var tp: Vector3 = target.global_position
		var t_inside: bool = tp.y < floor_y + 1.0 and tp.y > floor_y - 1.0
		var t_mine := roof.any(func(r: Rect2) -> bool: return r.has_point(Vector2(tp.x, tp.z)))
		want = want or (t_mine and t_inside != inside)
	if not want:
		return Vector3.INF
	for st: Dictionary in stairs:
		var top: Vector3 = st.top
		var bottom: Vector3 = st.bottom
		if not roof.any(func(r: Rect2) -> bool: return r.grow(1.0).has_point(Vector2(top.x, top.z))):
			continue
		var first := bottom if inside else top
		var second := top if inside else bottom
		if world.walk_clear(global_position, first):
			_route = [second]
			return first
	return Vector3.INF


func eye() -> Vector3:
	return global_position + Vector3(0, _head.position.y, 0)


func _can_see() -> bool:
	if target == null or not target.alive:
		return false
	var to: Vector3 = target.cam.global_position
	var hit := world.trace(eye(), to, [get_rid()], 1 | 4)
	if hit.is_empty() or hit.collider != target:
		return false
	# bushes: past 3 m, more than a metre of leaves between hides you (G43)
	return eye().distance_to(to) < 3.0 or world.bush_between(eye(), to) < 1.0


func _fire() -> void:
	var to: Vector3 = target.cam.global_position + Vector3(0, -0.5, 0)
	var dist := eye().distance_to(to)
	var acc := FpsTune.value("bot_accuracy")
	acc *= lerpf(1.0, 0.55, float(target.speed01))
	acc *= { "stand": 1.0, "crouch": 0.85, "prone": 0.6 }[target.stance]
	acc *= clampf(1.15 - dist / 140.0, 0.35, 1.0)
	var muzzle := gun.global_transform * gun_asset.marker("muzzle").origin
	var sp: Dictionary = FpsWeapons.SPECS[weapon]
	world.muzzle_flash(muzzle, (to - muzzle).normalized(), float(sp.get("flash", 1.0)))
	if sp.get("boom", false):
		world.boom(muzzle)
	if world.audio:
		world.audio.shot(weapon, muzzle)
	# the roll picks where it aims; the bullet still has to get there (G28):
	# a good roll aims at the chest (or the head, 12%), a bad one beside you
	var aim := to
	if _rng.randf() < acc:
		if _rng.randf() < 0.12:
			aim = target.cam.global_position
	else:
		aim = to + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.6, 1.4), _rng.randf_range(-1.2, 1.2))
	for k in int(sp.pellets):
		var dir := (aim - muzzle).normalized()
		if int(sp.pellets) > 1:
			dir = FpsPlayer._cone(dir, float(sp.spread))
		world.fire_bullet(muzzle, dir, self, float(sp.damage), float(sp.head), float(sp.range), Color(1.0, 0.75, 0.45), muzzle)
	world.shot_near_player(muzzle)


func _animate(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	var want := "run" if moving else ("kneel" if crouched else "idle")
	if ch.pose_name() != want:
		ch.pose(want)
	var aim := _state == "engage" or _state == "peek"
	var pitch := 0.0
	if aim and target:
		var d: Vector3 = (target.global_position + Vector3(0, 1.5, 0) if _state == "engage" else _known + Vector3(0, 1.5, 0)) - eye()
		pitch = atan2(d.y, Vector2(d.x, d.z).length())
	GKBWHold.hold_rifle(ch, gun_asset, "aim" if aim else "low", pitch)
	_head.position.y = move_toward(_head.position.y, HEAD_Y.crouch if crouched and not moving else HEAD_Y.stand, delta * 3.0)
	var cap := _body.shape as CapsuleShape3D
	cap.height = 1.2 if crouched and not moving else 1.75
	_body.position.y = cap.height * 0.5


## Shot: it learns where you are; if it can't see you it breaks away to
## cover and peeks from there; wounded, it falls back.
func hurt(d: float, head: bool) -> void:
	if not alive:
		return
	hp -= d * (1.0 if not head else 1.0)
	if target:
		_known = target.global_position
		_known_t = 0.0
	if hp > 0.0 and _state != "engage":
		if _can_see():
			_set_state("engage")
			_seen = FpsTune.value("bot_reaction") * 0.6
		elif _state != "retreat":
			_go(_cover_spot(), "retreat")
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
	_route.clear()
	_known = Vector3.INF
	_known_t = 99.0
	_peek = Vector3.INF
	_hold_spot = Vector3.INF
	_over_court = false
	_go(_pick_spot())
