class_name FpsAudio
extends Node
## The FPS's sound (G62). Its own files live in res://audio/sfx/fps/
## (tools/audio/make_fps_sfx.py writes them; <name>_<n>.wav, Ogg twins for
## the web build, G49) and play on the SFX bus: a shot per weapon class,
## the reload's mag out / in, a shell, the bolt and the pump, the whizz of
## a near miss, the hit marker's tick, the headshot ding and the kill sting.
## From Black | White's pool (BWSfx): footsteps (step_stone), being hit
## (hit_flesh), going down (ko_thud), the draw (ph_swap_draw) and the match
## stings (sting_victory / sting_defeat).
##   audio.shot("sniper")            yours: 2D, full
##   audio.shot("sniper", muzzle)    the bot's: 3D at its muzzle, carries far
##   audio.ui("hitmark")             2D
##   audio.play("whizz", at)         3D
## Pace-matched footsteps come from update(): yours from your speed and
## stance, the bot's from its velocity at its feet.

const DIR := "res://audio/sfx/fps/"
## name -> variations on disk
const SOUNDS := {
	"shot_pistol": 3, "shot_deagle": 2, "shot_carbine": 3, "shot_auto_rifle": 3,
	"shot_marksman": 2, "shot_sniper": 2, "shot_shotgun": 2, "shot_slingshot": 2,
	"reload_out": 2, "reload_in": 2, "shell_in": 2,
	"bolt_open": 1, "bolt_close": 1, "pump_back": 1, "pump_fwd": 1,
	"whizz": 3, "hitmark": 2, "headshot": 1, "kill": 1,
}
## Per-sound mix (dB) on top of the files' -16 LUFS-ish level.
const MIX := {
	"shot_pistol": -3.0, "shot_deagle": 1.0, "shot_carbine": -3.0, "shot_auto_rifle": -2.5,
	"shot_marksman": -1.0, "shot_sniper": 1.0, "shot_shotgun": 0.5, "shot_slingshot": -8.0,
	"reload_out": -10.0, "reload_in": -9.0, "shell_in": -10.0,
	"bolt_open": -9.0, "bolt_close": -8.0, "pump_back": -8.0, "pump_fwd": -7.0,
	"whizz": -6.0, "hitmark": -9.0, "headshot": -6.0, "kill": -5.0,
}
## Weapon id -> its shot
const SHOT := { "pistol": "shot_pistol", "dual_berettas": "shot_pistol", "deagle": "shot_deagle",
	"carbine": "shot_carbine", "auto_rifle": "shot_auto_rifle", "marksman": "shot_marksman",
	"sniper": "shot_sniper", "shotgun": "shot_shotgun", "slingshot": "shot_slingshot" }
## 3D: a shot carries across a map; a step is heard a room away.
const UNIT_SHOT := 45.0
const UNIT_STEP := 9.0
const UNIT_WHIZZ := 3.0
## Pitch jitter per play (± fraction). 0 in captures.
static var jitter := 0.04
## Tools: every play, in order (name, where).
static var log_enabled := false
static var events: Array = []

var world: FpsWorld
var _streams := {}                          # path -> AudioStream
var _last_variant := {}
var _rng := RandomNumberGenerator.new()
var _step_t := 0.0
var _bot_step_t := 0.0
var _bot_was_moving := false
var _player_was_moving := false


func _ready() -> void:
	_rng.seed = 0x5f5
	BWAudio.ensure(self)
	BWSfx.ensure(self)


static func path_of(name: String, n: int) -> String:
	return "%s%s_%d.%s" % [DIR, name, n, "ogg" if OS.has_feature("web") else "wav"]   # G49: the web build ships Ogg twins


## Loads a variation (cached); null when the file is missing.
func stream(name: String, n: int) -> AudioStream:
	var path := path_of(name, n)
	if _streams.has(path):
		return _streams[path]
	var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[path] = st
	return st


func _pick(name: String) -> int:
	var n := int(SOUNDS.get(name, 1))
	var v := _rng.randi_range(1, n)
	if n > 1 and v == int(_last_variant.get(name, -1)):
		v = v % n + 1
	_last_variant[name] = v
	return v


## A sound: `where` null is 2D; a Vector3 places it. opts: gain_db, pitch,
## unit (3D reach), delay (s).
func play(name: String, where: Variant = null, opts: Dictionary = {}) -> Node:
	if not SOUNDS.has(name):
		push_warning("FpsAudio: no sound '%s'" % name)
		return null
	var delay := float(opts.get("delay", 0.0))
	if delay > 0.0 and is_inside_tree():
		var o := opts.duplicate()
		o.erase("delay")
		get_tree().create_timer(delay).timeout.connect(func() -> void: play(name, where, o))
		return null
	var st := stream(name, _pick(name))
	if st == null:
		return null
	var gain := float(MIX.get(name, -6.0)) + float(opts.get("gain_db", 0.0))
	var pitch := float(opts.get("pitch", 1.0)) * (1.0 + _rng.randf_range(-jitter, jitter))
	var p: Node
	if where == null:
		var p2 := AudioStreamPlayer.new()
		p2.stream = st
		p2.volume_db = gain
		p2.pitch_scale = pitch
		p2.bus = "SFX"
		p = p2
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = st
		p3.volume_db = gain
		p3.pitch_scale = pitch
		p3.bus = "SFX"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = float(opts.get("unit", UNIT_SHOT))
		p3.max_db = 2.0
		p3.panning_strength = 1.2
		p3.attenuation_filter_cutoff_hz = 8000.0
		p3.attenuation_filter_db = -12.0        # a far shot is duller
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p = p3
	if not is_inside_tree():
		p.free()
		return null
	add_child(p)
	if p is Node3D:
		(p as Node3D).global_position = where
	p.call("play")
	p.connect("finished", p.queue_free)
	if log_enabled:
		events.append({ "name": name, "where": where, "frame": Engine.get_process_frames() })
	return p


func ui(name: String, opts: Dictionary = {}) -> Node:
	return play(name, null, opts)


## A gun's shot: yours (where null) in 2D, the bot's at its muzzle.
func shot(weapon: String, where: Variant = null) -> void:
	play(shot_name(weapon), where, { "unit": UNIT_SHOT, "gain_db": 0.0 if where == null else 2.0 })


## The shot for a gun id (a variant of a base gun, `<base>_<x>`, fires its base's).
static func shot_name(weapon: String) -> String:
	if SHOT.has(weapon):
		return str(SHOT[weapon])
	var best := ""
	for k: String in SHOT:
		if weapon.begins_with(k) and k.length() > best.length():
			best = k
	return str(SHOT.get(best, "shot_pistol"))


## The reload: the mag out now, the fresh one in before the end (both
## pistols for the duals); the shotgun's shell straight in.
func reload(weapon: String) -> void:
	var sp: Dictionary = FpsWeapons.SPECS.get(weapon, {})
	var t := float(sp.get("reload", 1.5))
	if sp.get("shell_reload", false):
		ui("shell_in", { "delay": t * 0.4 })
		return
	ui("reload_out", { "delay": t * 0.12 })
	if sp.get("dual", false):
		ui("reload_in", { "delay": t * 0.78 })
		ui("reload_in", { "delay": t * 0.86, "pitch": 1.06 })
	else:
		ui("reload_in", { "delay": t * 0.62 })


## Pace-matched footsteps (yours and the bot's).
func update(delta: float) -> void:
	if world == null:
		return
	var p := world.player
	if p and p.alive and p.is_on_floor():
		var moving := p.speed01 > 0.12 and p.stance != "prone"
		if moving:
			var pace := lerpf(0.62, 0.34, p.speed01) * (1.35 if p.stance == "crouch" else 1.0)
			_step_t -= delta
			if _step_t <= 0.0 or not _player_was_moving:
				_step_t = pace
				BWSfx.ui("step_stone", { "gain_db": -16.0 if p.stance == "crouch" else -11.0 + 4.0 * p.speed01, "pitch": 0.92, "stack": true })
		_player_was_moving = moving
	var b := world.bot
	if b and b.alive:
		var sp := Vector2(b.velocity.x, b.velocity.z).length()
		var moving := sp > 0.8 and b.is_on_floor()
		if moving:
			_bot_step_t -= delta
			if _bot_step_t <= 0.0 or not _bot_was_moving:
				_bot_step_t = lerpf(0.6, 0.36, clampf(sp / maxf(FpsTune.value("bot_speed"), 0.1), 0.0, 1.0))
				BWSfx.play("step_stone", b.global_position + Vector3(0, 0.1, 0), { "gain_db": 2.0, "pitch": 0.85, "stack": true })
		_bot_was_moving = moving
