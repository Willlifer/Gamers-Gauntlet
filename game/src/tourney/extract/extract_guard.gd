class_name ExtractGuard
extends FpsBot
## Extraction's guard: a FpsBot in green (its hoodie and sweats tinted), dumb
## and loud. It walks its post's patrol loop (meta.guards[].patrol: straight
## legs, a kneel at each corner) instead of picking roof spots, barks "hey"
## every FpsTune.guard_bark_gap s so you hear it to guard_hear_range (the
## world puts a "!" on the HUD edge toward it), takes guard_reaction_x times
## the bot's reaction to open fire and shoots at guard_accuracy_x of its
## accuracy. The world turns its death into a loot bag (ExtractLoot.guard_drop).
## G65: it starts calm. A calm guard patrols and never fights: it doesn't
## look for you at all (no sight ray, so it's cheap too). It turns hostile,
## for the rest of the run, when you come within guard_aggro_range (50 ft,
## 15.24 m; seen or not), when you hurt it, or when you fire within
## guard_shot_alert of it or land a shot near it (ExtractWorld.on_player_shot).
## Hostile, it is the old guard: sees you at any range and hunts.

signal barked(guard: ExtractGuard)

const GREEN := Color(0.45, 0.95, 0.4)
const BARK := "res://audio/barks/hey.wav"

var patrol: Array = []                 ## Vector3 corners, walked in order
var post := 0                          ## index into meta.guards
var _leg := 0
var _bark_t := 1.0
var _voice: AudioStreamPlayer3D
var alerted := false                   ## G65: hostile (see the header); calm until then


func _ready() -> void:
	super._ready()
	_rng.seed = 77 + post * 131
	_bark_t = _rng.randf_range(0.5, 2.0)
	# green clothes: the garments' tint (the clothing shader's instance uniform)
	if ch and ch.rig:
		for slot in ["top", "bottom"]:
			var mi := BWClothing.garment(ch.rig, slot)
			if mi:
				mi.set_instance_shader_parameter("tint", GREEN)
	_voice = AudioStreamPlayer3D.new()
	_voice.stream = load(BARK) if ResourceLoader.exists(BARK) else null
	_voice.unit_size = 12.0
	_voice.max_db = 3.0
	_voice.volume_db = 2.0
	_voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_voice.bus = "SFX"
	_voice.position.y = 1.7
	add_child(_voice)


func _unit() -> BWUnit:
	var u := super._unit()
	u.id = "extract_guard_%d" % post
	u.name = "Guard"
	u.cosmetics["clothing_shade"] = "mid"
	u.cosmetics["hair_hex"] = "#3a2a1a"
	return u


## Slow to react: the time it has seen you grows at 1 / guard_reaction_x.
## Calm, it checks only how close you are.
func _physics_process(delta: float) -> void:
	if alive and not alerted and target and target.alive and not drill:
		if global_position.distance_squared_to(target.global_position) <= pow(FpsTune.value("guard_aggro_range"), 2.0):
			alert()
	var saw := _seen
	super._physics_process(delta)
	if not alive:
		return
	if _seen > saw:
		_seen = saw + (_seen - saw) / maxf(FpsTune.value("guard_reaction_x"), 0.1)
	_bark_t -= delta
	if _bark_t <= 0.0:
		_bark_t = FpsTune.value("guard_bark_gap") * _rng.randf_range(0.75, 1.3)
		bark()


## Turn hostile (G65): it knows where you are now and faces that way.
func alert() -> void:
	if alerted or not alive:
		return
	alerted = true
	if target:
		_known = target.global_position
		_known_t = 0.0


## Calm guards don't look (G65).
func _can_see() -> bool:
	return alerted and super._can_see()


## Shot: hostile at once, then the bot's reaction (turn, cover, peek).
func hurt(d: float, head: bool) -> void:
	alert()
	super.hurt(d, head)


## The loud bark: the clip to guard_hear_range, and the world's "!".
func bark() -> void:
	if _voice:
		_voice.max_distance = FpsTune.value("guard_hear_range")
		_voice.pitch_scale = _rng.randf_range(0.9, 1.1)
		if _voice.stream:
			_voice.play()
	barked.emit(self)


## The next corner of the patrol (a straight leg; a corner it can't walk to
## in a line is skipped, so a blocked leg doesn't pin it).
func _pick_spot() -> Vector3:
	if patrol.is_empty():
		return global_position
	for i in patrol.size():
		_leg = (_leg + 1) % patrol.size()
		var p: Vector3 = patrol[_leg]
		if world.walk_clear(global_position, p):
			return p
	return global_position


## Half accuracy, and its misses land wider.
func accuracy() -> float:
	return super.accuracy() * FpsTune.value("guard_accuracy_x")


func miss_spread() -> float:
	return 1.33
