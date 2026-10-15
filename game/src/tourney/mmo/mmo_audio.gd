class_name MmoAudio
extends Node
## The raid's sound (G24): the author's "Chris" loops for music and the
## project's sound effects (res://audio/sfx, res://audio/barks) on MmoSim's
## events. Black | White's own music pauses while the raid plays and comes
## back when it ends.
##
## Music (trimmed by tools/audio/trim_chris.py; seamless loops):
##   before the pull    chris_loop_a
##   the fight          chris_full
##   Giant under 30% or enraged   chris_loop_b
##   the end            the music fades, the victory / defeat sting
## Each change crossfades over FADE seconds on the Music bus.

const DIR := "res://audio/music/chris/"
const FADE := 1.6
const STEP_EVERY := 0.32            ## your footsteps while running (s)

var view: MmoView
var _decks: Array[AudioStreamPlayer] = []
var _cur := -1
var _track := ""
var _paused_bw: Array = []
var _loops := {}                    # unit id -> channel loop player
var _step_t := 0.0
var _boss_step_t := 0.0
var _hurt_t := {}                   # unit id -> time of the last pain bark
var _over := false


func _ready() -> void:
	BWAudio.ensure(self)
	BWSfx.ensure(self)
	_pause_bw(true)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_decks.append(p)
	music("chris_loop_a")


func _exit_tree() -> void:
	_pause_bw(false)


## Pause (or resume) whatever Black | White's music node is playing.
func _pause_bw(on: bool) -> void:
	var bw := BWMusic.instance()
	if bw == null:
		return
	if on:
		_paused_bw = []
		for c in bw.find_children("*", "AudioStreamPlayer", true, false):
			var p := c as AudioStreamPlayer
			if p.playing and not p.stream_paused:
				p.stream_paused = true
				_paused_bw.append(p)
	else:
		for p: AudioStreamPlayer in _paused_bw:
			if is_instance_valid(p):
				p.stream_paused = false
		_paused_bw = []


## The tracks import as forward loops over the whole file (their .import:
## edit/loop_mode=2, loop_end=-1); trim_chris.py made the seams.
static func stream(track: String) -> AudioStream:
	return load(DIR + track + ".wav") as AudioStreamWAV


func music(track: String) -> void:
	if track == _track:
		return
	_track = track
	var old := _decks[_cur] if _cur >= 0 else null
	_cur = (_cur + 1) % 2
	var p := _decks[_cur]
	if track == "":
		p.stop()
	else:
		p.stream = stream(track)
		p.volume_db = -40.0
		p.play()
		create_tween().tween_property(p, "volume_db", 0.0, FADE)
	if old:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.tween_callback(old.stop)


func current() -> String:
	return _track


# ------------------------------------------------------------------ frame

func update(delta: float) -> void:
	var s := view.sim
	if s == null or _over:
		return
	if s.pulled and s.boss:
		music("chris_loop_b" if s.boss.hp_pct() < 0.3 or s.enraged else "chris_full")
	var me := s.unit(view.me_id)
	if me and me.alive and me.moving and me.h <= 0.0:
		_step_t -= delta * (me.speed_now / maxf(1.0, MmoTune.value("run_speed")))
		if _step_t <= 0.0:
			_step_t = STEP_EVERY
			BWSfx.play("step_stone", _feet(me), { "gain_db": -8.0 })
	var b := s.boss
	if b and b.alive and b.moving:
		_boss_step_t -= delta
		if _boss_step_t <= 0.0:
			_boss_step_t = 0.75
			BWSfx.play("ph_colossus_step", _feet(b), { "gain_db": -2.0, "pitch": 0.8 })


func _feet(u: MmoUnit) -> Vector3:
	return Vector3(u.pos.x, 0.1, u.pos.y)


func _at(u: MmoUnit) -> Vector3:
	return Vector3(u.pos.x, 1.2 if u.kind == "player" else 4.0, u.pos.y)


const ELEM := { "fire": "elem_fire", "ice": "elem_ice", "light": "elem_light", "dark": "elem_dark", "thunder": "elem_thunder",
	"earth": "tile_detonate" }


# ----------------------------------------------------------------- events

func on_event(e: Dictionary) -> void:
	var s := view.sim
	match str(e.type):
		"swing":
			var u := s.unit(str(e.id))
			if u:
				BWSfx.play("swing_light" if u.cls == "rogue" else "swing_heavy", _at(u), { "gain_db": -4.0 })
		"dmg":
			var t := s.unit(str(e.tgt))
			var src := s.unit(str(e.src)) if str(e.src) != "" else null
			if t == null:
				return
			var mine := str(e.src) == view.me_id or str(e.tgt) == view.me_id
			var g := 0.0 if mine else -7.0
			if float(e.n) <= 0.0 and float(e.absorbed) > 0.0:
				BWSfx.play("hit_block", _at(t), { "gain_db": g - 2.0 })
			elif str(e.kind) == "auto":
				if src and src.kind == "boss":
					BWSfx.play("swing_axe", _at(src), { "gain_db": 0.0, "pitch": 0.7 })
					BWSfx.play("hit_crit", _at(t), { "gain_db": g, "pitch": 0.8 })
				elif mine or (s.unit(view.me_id) and s.unit(view.me_id).target == str(e.tgt)):
					BWSfx.play("hit_crit" if e.crit else "hit_flesh", _at(t), { "gain_db": g - 3.0 })
			elif str(e.kind) == "hit" and mine:
				var school := str(e.school)
				BWSfx.play(str(ELEM[school]) if ELEM.has(school) else ("hit_crit" if e.crit else "hit_flesh"), _at(t), { "gain_db": g - 4.0 })
			if t.kind == "player" and t.alive and float(e.n) > t.max_hp * 0.15:
				_bark(t, ["oof", "ouch_grunt", "oogh"])
		"heal":
			if str(e.kind) != "hot" and (str(e.src) == view.me_id or str(e.tgt) == view.me_id):
				var t := s.unit(str(e.tgt))
				if t:
					BWSfx.play("heal", _at(t), { "gain_db": -4.0 })
		"immune":
			if str(e.src) == view.me_id or str(e.tgt) == view.me_id:
				var t := s.unit(str(e.tgt))
				if t:
					BWSfx.play("ph_immune", _at(t))
		"cast_start":
			var u := s.unit(str(e.id))
			if u == null:
				return
			var ab := MmoClasses.ability(u.cls, str(e.ab))
			var near := str(e.id) == view.me_id
			BWSfx.play("ph_cast_%s" % _cast_el(str(ab.get("school", "phys"))), _at(u), { "gain_db": 0.0 if near else -8.0 })
			if near:
				_loops[u.id] = BWSfx.loop_start("channel_loop", view.unit_root(u.id), { "gain_db": -10.0 })
		"cast_end":
			if _loops.has(str(e.id)):
				BWSfx.loop_stop(_loops[str(e.id)])
				_loops.erase(str(e.id))
			if str(e.get("why", "")) == "Interrupted" and str(e.id) == view.me_id:
				BWSfx.ui("ui_cancel", { "gain_db": -6.0 })
		"use":
			var u := s.unit(str(e.id))
			if u == null or e.get("tick", false):
				return
			var ab := MmoClasses.ability(u.cls, str(e.ab))
			var near := str(e.id) == view.me_id
			var g := 0.0 if near else -8.0
			if str(ab.get("anim", "")) == "strike":
				if u.cls == "hunter":
					BWSfx.play("bow_release", _at(u), { "gain_db": g })
				else:
					BWSfx.play("swing_heavy" if u.cls in ["warrior", "paladin"] else "swing_light", _at(u), { "gain_db": g })
			elif str(ab.get("anim", "")) == "cast":
				BWSfx.play("cast_whoom", _at(u), { "gain_db": g - 2.0 })
			if str(e.ab) in ["charge", "heroic_strike"] and near:
				_bark(u, ["yah", "hiyah"])
		"proj":
			var u := s.unit(str(e.src))
			if u and str(e.ab) == "auto_shot":
				BWSfx.play("bow_release", _at(u), { "gain_db": 0.0 if str(e.src) == view.me_id else -9.0 })
		"dash":
			var u := s.unit(str(e.id))
			if u:
				BWSfx.play("elem_wind", _at(u), { "gain_db": -4.0 })
		"death":
			var u := s.unit(str(e.id))
			if u and u.kind == "player":
				_bark(u, ["dying"], true)
				BWSfx.play("ko_thud", _feet(u))
			elif u:
				BWSfx.play("ko_thud", _feet(u), { "pitch": 0.6, "gain_db": 4.0 })
		"res":
			var u := s.unit(str(e.id))
			if u:
				BWSfx.play("heal", _at(u))
				_bark(u, ["hey", "yeah"], true)
		"error":
			if str(e.id) == view.me_id:
				BWSfx.ui("ui_cancel", { "gain_db": -8.0 })
		"warn":
			BWSfx.ui("sting_bad", { "gain_db": -6.0 })
		"pull":
			BWSfx.play("ph_colossus_thrust", Vector3(s.boss.pos.x, 3.0, s.boss.pos.y), { "gain_db": 3.0, "pitch": 0.7 })
		"boss_spell":
			var at := Vector3(s.boss.pos.x, 3.0, s.boss.pos.y)
			if str(e.stage) == "cast":
				BWSfx.play("ph_cast_%s" % { "upheaval": "wind", "meteors": "fire", "bombs": "fire", "gather": "light" }.get(str(e.spell), "dark"), at, { "gain_db": 3.0, "pitch": 0.75 })
			else:
				match str(e.spell):
					"upheaval":
						BWSfx.play("tile_detonate", at, { "gain_db": 4.0, "pitch": 0.6 })
						BWSfx.play("ko_thud", at, { "gain_db": 4.0, "pitch": 0.5 })
					"bombs":
						BWSfx.play("bolt_fizz", at, { "gain_db": 0.0 })
					"gather":
						BWSfx.play("ph_colossus_thrust", at, { "gain_db": 4.0, "pitch": 0.6 })
		"explode":
			var p := Vector3((e.pos as Vector2).x, 0.5, (e.pos as Vector2).y)
			match str(e.what):
				"meteor":
					BWSfx.play("elem_fire", p, { "gain_db": -2.0, "pitch": 0.8 })
					BWSfx.play("tile_detonate", p, { "gain_db": -4.0 })
				"bomb":
					BWSfx.play("tile_detonate", p, { "gain_db": 0.0 })
				"gather":
					BWSfx.play("tile_detonate", p, { "gain_db": 5.0, "pitch": 0.5 })
					BWSfx.play("ko_thud", p, { "gain_db": 5.0, "pitch": 0.45 })
		"win":
			_over = true
			music("")
			BWSfx.ui("sting_victory" if str(e.winner) == "raid" else "sting_defeat")
			for id: String in _loops:
				BWSfx.loop_stop(_loops[id])
			_loops.clear()


func _cast_el(school: String) -> String:
	match school:
		"fire", "ice", "light", "dark", "thunder", "water", "wind":
			return school
	return "wind"


## A voice line from res://audio/barks on a unit (at most one every 2.5 s each).
func _bark(u: MmoUnit, pool: Array, always := false) -> void:
	var now := view.sim.time
	if not always and now - float(_hurt_t.get(u.id, -10.0)) < 2.5:
		return
	_hurt_t[u.id] = now
	var clip := str(pool[randi() % pool.size()])
	var st := load("res://audio/barks/%s.wav" % clip) as AudioStream
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "Voice"
	p.unit_size = 12.0
	p.volume_db = 0.0 if u.id == view.me_id else -6.0
	p.pitch_scale = randf_range(0.92, 1.08)
	add_child(p)
	p.global_position = _at(u)
	p.play()
	p.finished.connect(p.queue_free)
