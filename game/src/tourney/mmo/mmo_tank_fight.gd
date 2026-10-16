class_name MmoTankFight
extends RefCounted
## Planet of Tanks (G46), raid night 2: the kit tank parked in the middle of
## a clearing in the forest campus. Same classes, same raid of eight, same
## WoW rules (MmoSim); this is the boss's brain. MmoSim hands its tick here
## when `sim.tank` is set. Every attack is telegraphed on the ground (G52: no
## more lines of text for the moves, the visuals say it; only the two rule
## changes nothing on screen shows get a line: the soft flanks and the
## enrage); the numbers are MmoTune's "Planet of Tanks" section.
##
## Main cycle, the cannon blast: a 120-degree wedge from the tank to the edge
## of the clearing, at the closest warrior or paladin (else the closest
## anyone). Each body it catches makes it hit everyone harder
## (cannon_stack), so a warrior or paladin drags it away from the raid; the
## announcer calls out multi-hits.
## Specials (one at a time, MmoTune.spell_gap between, like the Giant):
##   barrage    the turret climbs; rounds land at random (every third on
##              someone); each leaves a burning crater until 1 s after the
##              next special is announced
##   smoke      a smoke grenade lobbed at a random raider's spot spreads over
##              the whole map: thick at its front, thin behind it; it poisons, slows
##              and cuts damage. Keep away, then rush through the front.
##              Spreads at smoke_speed, then thins out as slowly.
##   treadburn  (from 75%) one tread or both rev red to bright red; dust
##              fills that side (all but 10 degrees fore and aft), then
##              ignites. Both at once: only the fore and aft wedges are safe.
##   loose      Loose Cannon (at 75%, and in the mix from 25%): bright red
##              treads, a 3 s wobble, then it spins and sprays the middle
##              loose_r of the clearing. Afterwards the treads cool to orange
##              and its flanks take flank_mult damage for the rest of the fight.
##   ram        (at 50%, and in the mix from 25%): it turns, rocks, charges to
##              the edge flattening anyone in its path, then fires a huge arc
##              back across the clearing; twice; then it drives home.
## At 25% two light tanks roll in and park back to back (G52); they take
## turns firing into a big wedge in front of each (add_zone_*): ground you
## can't stand on until they die. Optional, but killing them gives the raid
## room. At tank_rush_at (G52: 15%) everything runs tank_rush_rate (1.5) x faster.

const SPELL_CAST := { "barrage": 1.6, "smoke": 1.4, "treadburn": 4.0, "loose": 3.0, "ram": 1.2 }
## The HUD's names: vague, like the warnings.
const NAMES := { "barrage": "The turret climbs", "smoke": "A canister flies", "treadburn": "The treads scream",
	"loose": "It strains", "ram": "It rocks", "cannon": "Main gun" }
const BAG_1 := ["barrage", "smoke"]
const BAG_2 := ["barrage", "smoke", "treadburn", "treadburn"]
const BAG_4 := ["barrage", "smoke", "treadburn", "loose", "ram"]
const TREAD_HALF := 1.396        ## 80 degrees: a tread's dust covers all of its side but 10 degrees fore and aft
const HOME_DIR := Vector2(0, -1) ## where the blast catcher holds the gun (north); the raid gathers south

var s: MmoSim
var phase := 1
var rate := 1.0                  ## tank_rush_rate below 10%
var flank_open := false          ## after the first Loose Cannon
var turret := 0.0                ## the turret's world yaw (MmoUnit.yaw convention)
var gun_pitch := 0.0             ## 0 level, 1 the barrage's high angle
var wobble := 0.0                ## view: 1 side to side (Loose Cannon), 2 fore and aft (the ram)
var spinning := false            ## view: Loose Cannon's wild fire
var glow := [0.0, 0.0]           ## view: left / right tread, 0 cold, 0.5 orange, 1 red, 2 bright red
var cannon := {}                 ## the blast in its telegraph: { area, target }
var cannon_wait := 3.0
var smoke := {}                  ## { c, r, max_r, fade, stage, faced: {} }
var adds: Array = []             ## the light tanks (MmoUnit, kind "add")
var _forced: Array = []
var _bag: Array = []
var _last := ""
var _done := {}
var _safe_cache := {}            ## who -> [time, spots]


func _init(p_sim: MmoSim) -> void:
	s = p_sim


# ------------------------------------------------------------------- tick

func tick() -> void:
	var dt := MmoSim.TICK * rate
	var b := s.boss
	if not s.enraged and s.time - s.pull_time >= MmoTune.value("enrage"):
		s.enraged = true
		s._emit({ "type": "enrage" })                          # G52b: on screen, not in text (MmoTankView)
	_phases()
	var tgt := catcher()
	b.target = tgt.id if tgt else ""
	_tick_adds(dt)
	_tick_smoke(dt)
	_tick_cannon(dt, tgt)
	_tick_special(dt)
	if s.spell.is_empty() or not str(s.spell.id) in ["barrage"]:
		gun_pitch = move_toward(gun_pitch, 0.0, dt * 1.2)


func _phases() -> void:
	var p := s.boss.hp_pct()
	if not _done.has(75) and p <= 0.75:
		_done[75] = true
		phase = 2
		glow = [1.0, 1.0]
		_force("loose")
	if not _done.has(50) and p <= 0.5:
		_done[50] = true
		phase = 3
		_force("ram")
	if not _done.has(25) and p <= 0.25:
		_done[25] = true
		phase = 4
		_bag = []
		_spawn_adds()
	if not _done.has(15) and p <= MmoTune.value("tank_rush_at"):
		_done[15] = true                                     # G52: the enrage, 15% and x1.5 (was 10% and x2)
		rate = MmoTune.value("tank_rush_rate")
		s.frenzied = true
		s.next_spell_at = minf(s.next_spell_at, s.time + 1.0)
		s._emit({ "type": "frenzy" })                          # G52b: a screen-edge pulse, the tank glows, exhaust flames


func _force(id: String) -> void:
	_forced.append(id)
	s.next_spell_at = minf(s.next_spell_at, s.time + 1.5)


## The cannon's mark: the closest living warrior or paladin, else the closest anyone.
func catcher() -> MmoUnit:
	var best: MmoUnit = null
	var bd := INF
	for pass_ in 2:
		for u: MmoUnit in s.living():
			if pass_ == 0 and not u.cls in ["warrior", "paladin"]:
				continue
			var d := u.pos.distance_to(s.boss.pos)
			if d < bd:
				bd = d
				best = u
		if best:
			return best
	return best


func spell_gap() -> float:
	return MmoTune.value("spell_gap") / rate


# ----------------------------------------------------------------- cannon

func _tick_cannon(dt: float, tgt: MmoUnit) -> void:
	var b := s.boss
	var busy := not s.spell.is_empty() and str(s.spell.id) in ["barrage", "loose", "ram"]
	if not cannon.is_empty():
		if not s.areas.has(cannon.area):
			cannon = {}
			cannon_wait = maxf(0.5, MmoTune.value("cannon_every") - MmoTune.value("cannon_warn"))
		return
	if busy:
		return
	if tgt:
		var want := atan2(tgt.pos.x - b.pos.x, tgt.pos.y - b.pos.y)
		turret = wrapf(turret + clampf(wrapf(want - turret, -PI, PI), -2.2 * dt, 2.2 * dt), -PI, PI)
	cannon_wait -= dt
	if cannon_wait > 0.0 or tgt == null:
		return
	var dir := (tgt.pos - b.pos).normalized()
	if dir.length() < 0.5:
		dir = b.forward()
	turret = atan2(dir.x, dir.y)
	var warn := MmoTune.value("cannon_warn") / rate
	cannon = { "target": tgt.id, "area": s._add_area({ "kind": "sector", "pos": b.pos, "dir": dir,
		"half": deg_to_rad(MmoTune.value("cannon_arc")) * 0.5, "r": MmoSim.ARENA_R * 2.0, "t": warn, "dur": warn,
		"on_fire": "cannon", "look": "cannon", "owner": "boss", "target": tgt.id }) }
	s._emit({ "type": "boss_spell", "spell": "cannon", "stage": "cast" })


# --------------------------------------------------------------- specials

func _tick_special(dt: float) -> void:
	var b := s.boss
	if s.spell.is_empty():
		if s.time >= s.next_spell_at:
			_begin(str(_forced.pop_front()) if not _forced.is_empty() else _draw())
		return
	if str(s.spell.stage) == "after":
		s.spell.after_t = float(s.spell.after_t) - dt
		if float(s.spell.after_t) <= 0.0:
			_last = str(s.spell.id)
			s.spell = {}
			s.next_spell_at = s.time + spell_gap()
		return
	s.spell.t = float(s.spell.t) + dt
	if b.cast.has("ab"):
		b.cast.t = s.spell.t
	match str(s.spell.id):
		"barrage": _barrage(dt)
		"smoke": _smoke_cast()
		"treadburn": _treadburn()
		"loose": _loose(dt)
		"ram": _ram(dt)


func _draw() -> String:
	if _bag.is_empty():
		_bag = (BAG_4 if phase >= 4 else (BAG_2 if phase >= 2 else BAG_1)).duplicate()
		for i in range(_bag.size() - 1, 0, -1):
			var j := s.rng.randi_range(0, i)
			var tmp: Variant = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = tmp
		if str(_bag[0]) == _last and _bag.size() > 1:
			_bag.push_back(_bag.pop_front())
	var id := str(_bag.pop_front())
	if id == "smoke" and not smoke.is_empty():
		id = "barrage"                                   # one smokescreen at a time
	return id


func _begin(id: String) -> void:
	var b := s.boss
	# the barrage's craters go out 1 s after the next special is announced
	for a: Dictionary in s.areas:
		if a.get("pool", false):
			a.t = minf(float(a.t), 1.0)
	# spell.t runs on the tank's clock (x rate); the ground's areas on the real one
	var base := float(SPELL_CAST[id])
	if id == "treadburn":
		base = MmoTune.value("tread_warn")
	elif id == "loose":
		base = MmoTune.value("loose_wobble")
	var total := base / rate
	s.spell = { "id": id, "t": 0.0, "total": base, "stage": "cast" }
	b.cast = { "ab": id, "t": 0.0, "total": float(s.spell.total), "channel": false }
	b.cast_serial += 1
	b.last_ab = id
	match id:
		"barrage":
			pass
		"smoke":
			# a smoke grenade: lobbed at the ground under a random raider (the spot is marked while it flies)
			var ppl := s.living()
			var at: Vector2 = (ppl[s.rng.randi() % ppl.size()] as MmoUnit).pos if not ppl.is_empty() else b.pos + b.forward() * 8.0
			s.spell["at"] = at
			s._add_area({ "kind": "circle", "pos": at, "r": 2.5, "t": total, "dur": total, "look": "smoke_mark", "owner": "boss" })
		"treadburn":
			var r := s.rng.randf()
			var sides: Array = [-1, 1] if r < MmoTune.value("tread_both") else ([-1] if r < 0.5 + MmoTune.value("tread_both") * 0.5 else [1])
			s.spell["sides"] = sides
			for side: int in sides:
				glow[0 if side < 0 else 1] = 1.0
				s._add_area({ "kind": "sector", "pos": b.pos, "dir": tread_dir(side), "half": TREAD_HALF, "r": MmoSim.ARENA_R * 2.0,
					"t": total, "dur": total, "on_fire": "tread", "look": "dust", "owner": "boss", "side": side })
		"loose":
			glow = [2.0, 2.0]
			wobble = 1.0
			var whole := (MmoTune.value("loose_wobble") + MmoTune.value("loose_dur")) / rate
			s.spell["area"] = s._add_area({ "kind": "circle", "pos": b.pos, "r": loose_r(), "t": whole, "dur": whole,
				"look": "loose", "owner": "boss" })
		"ram":
			s.spell["count"] = 0
			s.spell["stage"] = "turn"
			_ram_pick()
			wobble = 2.0
	s._emit({ "type": "boss_spell", "spell": id, "stage": "cast", "sides": s.spell.get("sides", []) })


func _end(after := 0.6) -> void:
	s.spell.stage = "after"
	s.spell["after_t"] = after
	s.boss.cast = {}


func loose_r() -> float:
	return MmoSim.ARENA_R * MmoTune.value("loose_r")


## The ground on one side of the hull: -1 left, 1 right.
func tread_dir(side: int) -> Vector2:
	return s.boss.right() * float(side)


func base_glow() -> float:
	return 0.5 if flank_open else (1.0 if phase >= 2 else 0.0)


# barrage: up goes the gun, then the rounds come down over ~3 s
func _barrage(dt: float) -> void:
	var b := s.boss
	gun_pitch = move_toward(gun_pitch, 1.0, dt * 1.4)
	if str(s.spell.stage) == "cast":
		if float(s.spell.t) >= float(s.spell.total):
			s.spell.stage = "fire"
			s.spell["fired"] = 0
			s.spell["ft"] = 0.0
			b.cast = {}
			b.strike_serial += 1
			s._emit({ "type": "boss_spell", "spell": "barrage", "stage": "fire" })
		return
	s.spell.ft = float(s.spell.ft) + dt
	var n := int(MmoTune.value("barrage_count"))
	var every := 0.28
	while int(s.spell.fired) < n and float(s.spell.ft) >= int(s.spell.fired) * every:
		s.spell.fired = int(s.spell.fired) + 1
		var at: Vector2
		var ppl := s.living()
		if int(s.spell.fired) % 3 == 0 and not ppl.is_empty():
			at = (ppl[s.rng.randi() % ppl.size()] as MmoUnit).pos
		else:
			var ang := s.rng.randf() * TAU
			at = Vector2(cos(ang), sin(ang)) * sqrt(s.rng.randf()) * (MmoSim.ARENA_R - 1.5)
		var fuse := 1.7 / rate
		s._add_area({ "kind": "circle", "pos": at, "r": MmoTune.value("barrage_r"), "t": fuse, "dur": fuse, "look": "shell",
			"owner": "boss", "on_fire": "shell" })
	if int(s.spell.fired) >= n and float(s.spell.ft) >= n * every + 1.8:
		_end(0.5)


func _smoke_cast() -> void:
	var b := s.boss
	if float(s.spell.t) < float(s.spell.total):
		return
	var c: Vector2 = s.spell.get("at", b.pos)
	smoke = { "c": c, "r": 1.0, "max_r": c.length() + MmoSim.ARENA_R + MmoTune.value("smoke_band"), "fade": 1.0, "stage": "grow", "faced": {} }
	b.strike_serial += 1
	s._emit({ "type": "boss_spell", "spell": "smoke", "stage": "fire", "at": c })
	_end(0.6)


func _treadburn() -> void:
	var k := clampf(float(s.spell.t) / maxf(0.01, float(s.spell.total)), 0.0, 1.0)
	for side: int in s.spell.sides:
		glow[0 if side < 0 else 1] = 1.0 + k
	if float(s.spell.t) >= float(s.spell.total):
		s._emit({ "type": "boss_spell", "spell": "treadburn", "stage": "fire", "sides": s.spell.sides })
		glow = [base_glow(), base_glow()]
		_end(0.8)


func _loose(dt: float) -> void:
	var b := s.boss
	if str(s.spell.stage) == "cast":
		if float(s.spell.t) >= float(s.spell.total):
			s.spell.stage = "fire"
			s.spell["ft"] = 0.0
			s.spell["tick"] = 0.0
			s.spell["hit"] = {}
			b.cast = {}
			wobble = 0.0
			spinning = true
			for u: MmoUnit in s.living():
				if u.pos.distance_to(b.pos) <= loose_r() + MmoSim.DODGE_PAD:
					u.dodge_faced += 1
			s._emit({ "type": "boss_spell", "spell": "loose", "stage": "fire" })
		return
	s.spell.ft = float(s.spell.ft) + dt
	b.yaw = wrapf(b.yaw + 5.5 * dt, -PI, PI)
	turret = wrapf(turret - 9.0 * dt, -PI, PI)
	s.spell.tick = float(s.spell.tick) - dt
	if float(s.spell.tick) <= 0.0:
		s.spell.tick = 0.4
		b.strike_serial += 1
		for u: MmoUnit in s.living():
			if u.pos.distance_to(b.pos) <= loose_r() + u.radius * 0.5:
				if not (s.spell.hit as Dictionary).has(u.id):
					s.spell.hit[u.id] = true
					u.dodge_hit += 1
					u.fails += 1
				s.damage(b, u, MmoTune.value("loose_dmg"), "fire", "Loose Cannon", "mech")
		s._emit({ "type": "boss_spell", "spell": "loose", "stage": "volley" })
	if float(s.spell.ft) >= MmoTune.value("loose_dur"):
		spinning = false
		glow = [0.5, 0.5]
		if not flank_open:
			flank_open = true
			# G52b: shown, not said: the flank plates pulse, targets on them, and a debuff on its frame
			s.add_aura(b, { "id": "soft_flanks", "name": "Soft Flanks", "dur": 1.0e6, "glyph": "crack", "col": "#ffa040", "debuff": true })
		s._emit({ "type": "boss_spell", "spell": "loose", "stage": "end" })
		_end(0.8)


func _ram_pick() -> void:
	var ppl := s.living()
	var far: Array = ppl.filter(func(u: MmoUnit) -> bool: return u.pos.distance_to(s.boss.pos) > 8.0)
	var pool := far if not far.is_empty() else ppl
	var t: MmoUnit = pool[s.rng.randi() % pool.size()] if not pool.is_empty() else null
	s.spell["aim"] = t.pos if t else -s.boss.pos
	s.spell["ft"] = 0.0


## How far the tank can drive from `p` along `dir` before the edge.
func run_to_edge(p: Vector2, dir: Vector2) -> float:
	var lim := MmoSim.ARENA_R - s.boss.radius - 0.5
	var pd := p.dot(dir)
	return maxf(0.0, -pd + sqrt(maxf(0.0, pd * pd - p.length_squared() + lim * lim)))


func _ram(dt: float) -> void:
	var b := s.boss
	s.spell.ft = float(s.spell.ft) + dt
	match str(s.spell.stage):
		"turn":
			var aim: Vector2 = s.spell.aim
			var want := atan2(aim.x - b.pos.x, aim.y - b.pos.y)
			var dy := wrapf(want - b.yaw, -PI, PI)
			b.yaw = wrapf(b.yaw + clampf(dy, -2.4 * dt, 2.4 * dt), -PI, PI)
			turret = b.yaw
			if absf(dy) < 0.03 or float(s.spell.ft) >= 1.4:
				b.yaw = want
				turret = want
				var len := run_to_edge(b.pos, b.forward())
				var rock := MmoTune.value("ram_rock") / rate
				s.spell.stage = "rock"
				s.spell.ft = 0.0
				b.cast = {}
				s.spell["line"] = s._add_area({ "kind": "line", "pos": b.pos, "dir": b.forward(), "len": len + b.radius, "w": b.radius * 2.0 + 1.2,
					"t": rock + len / MmoTune.value("ram_speed") + 0.3, "dur": rock, "look": "ram", "owner": "boss" })
				wobble = 2.0
		"rock":
			if float(s.spell.ft) >= MmoTune.value("ram_rock"):
				s.spell.stage = "charge"
				s.spell.ft = 0.0
				s.spell["hit"] = {}
				wobble = 0.0
				var ln: Dictionary = s.spell.line
				for u: MmoUnit in s.living():
					if s._in_line(u.pos, ln, MmoSim.DODGE_PAD):
						u.dodge_faced += 1
				s._emit({ "type": "boss_spell", "spell": "ram", "stage": "charge" })
		"charge":
			var step := MmoTune.value("ram_speed") * dt
			var left := run_to_edge(b.pos, b.forward())
			b.pos += b.forward() * minf(step, left)
			b.moving = true
			for u: MmoUnit in s.living():
				if (s.spell.hit as Dictionary).has(u.id):
					continue
				if u.pos.distance_to(b.pos) <= b.radius + u.radius + 0.5:
					s.spell.hit[u.id] = true
					u.dodge_hit += 1
					u.fails += 1
					s.damage(b, u, MmoTune.value("ram_dmg"), "phys", "Ram", "mech")
					var side := signf((u.pos - b.pos).dot(b.right()))
					u.pos += b.right() * (side if side != 0.0 else 1.0) * 2.0
					u.vh = 7.0
					u.airborne = true
			if left <= step + 0.01:
				b.moving = false
				var ln: Dictionary = s.spell.get("line", {})
				ln["t"] = 0.0
				var aim := MmoTune.value("ram_aim") / rate
				var dir := -b.pos.normalized()
				turret = atan2(dir.x, dir.y)
				s.spell.stage = "aim"
				s.spell.ft = 0.0
				s.spell["arc"] = s._add_area({ "kind": "sector", "pos": b.pos, "dir": dir, "half": deg_to_rad(MmoTune.value("arc_deg")) * 0.5,
					"r": MmoSim.ARENA_R * 2.0, "t": aim, "dur": aim, "on_fire": "arc", "look": "arc", "owner": "boss" })
				s._emit({ "type": "boss_spell", "spell": "ram", "stage": "hit_edge" })
		"aim":
			if not s.areas.has(s.spell.arc):
				s.spell.count = int(s.spell.count) + 1
				if int(s.spell.count) < 2:
					s.spell.stage = "turn"
					_ram_pick()
					wobble = 2.0
				else:
					s.spell.stage = "home"
					s.spell.ft = 0.0
		"home":
			var to := -b.pos
			var want := atan2(to.x, to.y)
			b.yaw = wrapf(b.yaw + clampf(wrapf(want - b.yaw, -PI, PI), -2.4 * dt, 2.4 * dt), -PI, PI)
			var step := 5.0 * dt
			if to.length() <= step:
				b.pos = Vector2.ZERO
				b.moving = false
				_end(0.6)
			else:
				b.pos += to.normalized() * step
				b.moving = true


# ------------------------------------------------------------------ smoke

func _tick_smoke(dt: float) -> void:
	if smoke.is_empty():
		return
	var sp := MmoTune.value("smoke_speed")
	if smoke.stage == "grow":
		smoke.r = float(smoke.r) + sp * dt
		if float(smoke.r) >= float(smoke.max_r):
			smoke.stage = "fade"
	else:
		smoke.fade = float(smoke.fade) - dt * sp / float(smoke.max_r)
		if float(smoke.fade) <= 0.0:
			for id: String in smoke.faced:
				var u := s.unit(id)
				if u:
					u.mech_faced += 1.0
					u.mech_done += clampf(1.0 - (float(u.flags.get("smoke_x", 0.0)) - 2.5) / 5.0, 0.0, 1.0)
					u.flags.erase("smoke_x")
			smoke = {}
			s._emit({ "type": "boss_spell", "spell": "smoke", "stage": "end" })
			return
	var b := s.boss
	for u: MmoUnit in s.living():
		var st := smoke_at(u.pos)
		if st <= 0.04:
			continue
		smoke.faced[u.id] = true
		if st > 0.5:
			u.flags["smoke_x"] = float(u.flags.get("smoke_x", 0.0)) + MmoSim.TICK
		var cut := 1.0 - MmoTune.value("smoke_slow") * st
		var au := u.aura("smokescreen")
		if au.is_empty():
			s.add_aura(u, { "id": "smokescreen", "name": "Smokescreen", "src": "boss", "dur": 0.4, "mods": { "speed": cut, "dmg": cut },
				"debuff": true, "glyph": "snake", "col": "#b8b8a0" })
		else:
			au.t = 0.4
			au.mods = { "speed": cut, "dmg": cut }
		u.flags["smoke_acc"] = float(u.flags.get("smoke_acc", 0.0)) + u.max_hp * MmoTune.value("smoke_pct") * st * MmoSim.TICK
		u.flags["smoke_tick"] = float(u.flags.get("smoke_tick", 1.0)) - MmoSim.TICK
		if float(u.flags.smoke_tick) <= 0.0:
			u.flags.smoke_tick = 1.0
			var n := float(u.flags.smoke_acc)
			u.flags.smoke_acc = 0.0
			s.damage(b, u, n, "nature", "Smokescreen", "dot")


## The smoke's strength at `p` (0..1): thick in the front band, thin behind it.
func smoke_at(p: Vector2) -> float:
	if smoke.is_empty():
		return 0.0
	var d := p.distance_to(smoke.c as Vector2)
	var r := float(smoke.r)
	if d > r:
		return 0.0
	var band := MmoTune.value("smoke_band")
	var k := 1.0
	if d < r - band:
		k = lerpf(MmoTune.value("smoke_core"), 1.0, clampf(1.0 - (r - band - d) / 6.0, 0.0, 1.0))
	return k * float(smoke.fade)


# ------------------------------------------------------------------- adds

## G52: two light tanks drive in from the treeline and park back to back,
## off the raid's side of the clearing, each nose along the circle.
func _spawn_adds() -> void:
	var n := s.players().size()
	var ang := (-HOME_DIR).angle() + s.rng.randf_range(-1.1, 1.1)
	var dir := Vector2(cos(ang), sin(ang))
	var spot := dir * ADD_RING
	var t := dir.orthogonal()
	for k in 2:
		var u := MmoUnit.new()
		u.id = "light_tank_%d" % (k + 1)
		u.name = "Light Tank"
		u.kind = "add"
		u.base_hp = MmoTune.value("add_hp") * float(n) / 6.0
		u.max_hp = u.base_hp
		u.hp = u.max_hp
		u.res_kind = "none"
		u.radius = 1.0
		var face := t * (1.0 if k == 0 else -1.0)
		var park := spot + face * (MmoTankView.ADD_LEN * 0.5 + 0.15)
		u.pos = (park + dir * 12.0).limit_length(MmoSim.ARENA_R - 0.5)          # out of the trees
		u.yaw = atan2(-dir.x, -dir.y)
		u.flags["park"] = park
		u.flags["face"] = atan2(face.x, face.y)
		u.flags["state"] = "drive"
		s.units.append(u)
		adds.append(u)
		s._emit({ "type": "spawn", "id": u.id })
	add_clock = ADD_WARN


const ADD_RING := 13.0           ## G52: how far out the light tanks park
const ADD_WARN := 2.0            ## G52: their zones show this long before the first shot
var add_clock := 0.0
var _add_turn := 0


func _tick_adds(dt: float) -> void:
	var firing: Array = []
	for a: MmoUnit in adds:
		if not a.alive:
			var dead: Variant = a.flags.get("zone")
			if dead is Dictionary and s.areas.has(dead):
				(dead as Dictionary).t = 0.0                       # its zone goes with it
			a.flags.erase("zone")
			continue
		s._tick_auras(a)
		if not a.alive:
			continue
		a.target = ""
		match str(a.flags.get("state", "")):
			"drive":
				var to: Vector2 = (a.flags.park as Vector2) - a.pos
				var step := MmoTune.value("add_speed") * dt
				a.moving = to.length() > 0.05
				if to.length() <= step:
					a.pos = a.flags.park
					a.moving = false
					a.flags.state = "turn"
				else:
					a.pos += to.normalized() * step
			"turn":
				var dy := wrapf(float(a.flags.face) - a.yaw, -PI, PI)
				a.yaw = wrapf(a.yaw + clampf(dy, -2.5 * dt, 2.5 * dt), -PI, PI)
				if absf(dy) < 0.02:
					a.yaw = float(a.flags.face)
					a.flags.state = "set"
					a.flags["zone"] = s._add_area({ "kind": "sector", "pos": a.pos, "dir": a.forward(), "half": deg_to_rad(MmoTune.value("add_zone_deg")) * 0.5,
						"r": MmoTune.value("add_zone_r"), "t": 1.0e6, "dur": 1.0e6, "look": "deny", "owner": a.id })
			"set":
				firing.append(a)
	if firing.is_empty():
		return
	add_clock -= dt
	if add_clock > 0.0:
		return
	add_clock = MmoTune.value("add_every") / float(firing.size())          # they take turns
	_add_turn = (_add_turn + 1) % firing.size()
	_add_fire(firing[_add_turn])


## One light tank's shot: everyone in its wedge is hit; the shell lands somewhere in it.
func _add_fire(a: MmoUnit) -> void:
	var zone: Dictionary = a.flags.get("zone", {})
	if zone.is_empty():
		return
	a.strike_serial += 1
	for u: MmoUnit in s.living():
		if in_sector(u.pos, zone, u.radius * 0.5):
			s.damage(a, u, MmoTune.value("add_dmg"), "fire", "Light Tank", "mech")
	var land := (zone.dir as Vector2).rotated(s.rng.randf_range(-float(zone.half), float(zone.half)) * 0.85) * s.rng.randf_range(3.0, float(zone.r) - 1.0)
	s._emit({ "type": "explode", "pos": (zone.pos as Vector2) + land, "r": 3.0, "what": "deny", "src": a.id })


# ------------------------------------------------------------- the ground

## A sector area (cannon, treadburn, the edge blast): inside, with `pad` metres to spare?
static func in_sector(p: Vector2, a: Dictionary, pad := 0.0) -> bool:
	var d := p - (a.pos as Vector2)
	var l := d.length()
	if l > float(a.r) + pad:
		return false
	if l < 0.01:
		return true
	return absf(d.angle_to(a.dir as Vector2)) <= float(a.half) + pad / maxf(l, 1.0)


## An area of the tank's went off (MmoSim._tick_areas).
func area_fired(a: Dictionary) -> void:
	var b := s.boss
	match str(a.get("on_fire", "")):
		"cannon":
			var hits: Array = []
			for u: MmoUnit in s.living():
				if in_sector(u.pos, a, u.radius * 0.5):
					hits.append(u)
			var n := hits.size()
			var tid := str(a.get("target", ""))
			for u: MmoUnit in s.living():
				if u.id == tid:
					u.mech_faced += 1.0
					if n <= 1:
						u.mech_done += 1.0
				elif in_sector(u.pos, a, MmoSim.DODGE_PAD):
					u.dodge_faced += 1
			var dmg := MmoTune.value("cannon_dmg") * (1.0 + MmoTune.value("cannon_stack") * maxf(0.0, n - 1.0))
			for u: MmoUnit in hits:
				if u.id != tid:
					u.dodge_hit += 1
					u.fails += 1
				s.damage(b, u, dmg, "fire", "Cannon Blast", "auto")
			b.strike_serial += 1
			s._emit({ "type": "explode", "pos": a.pos, "dir": a.dir, "r": float(a.r), "half": float(a.half), "what": "cannon", "n": n })
			if n >= 2:
				var word: String = { 2: "DOUBLE", 3: "TRIPLE", 4: "QUAD" }.get(n, "MEGA")
				# G52b: drawn as a stacked hit marker over each one caught (MmoTankView.multi_hit), not a banner
				s._emit({ "type": "announce", "text": "%s HIT!" % word, "sub": "%d caught in the blast: x%.2f damage each." % [n, 1.0 + MmoTune.value("cannon_stack") * (n - 1)],
					"n": n, "mult": 1.0 + MmoTune.value("cannon_stack") * (n - 1), "ids": hits.map(func(u: MmoUnit) -> String: return u.id) })
		"shell":
			for u: MmoUnit in s.living():
				if u.pos.distance_to(a.pos as Vector2) <= float(a.r) + MmoSim.DODGE_PAD:
					u.dodge_faced += 1
				if u.pos.distance_to(a.pos as Vector2) <= float(a.r) + u.radius * 0.5:
					u.fails += 1
					u.dodge_hit += 1
					s.damage(b, u, MmoTune.value("barrage_dmg"), "fire", "Barrage", "mech")
			s._emit({ "type": "explode", "pos": a.pos, "r": float(a.r), "what": "shell" })
			var big := 999.0
			s._add_area({ "kind": "ground", "pos": a.pos, "r": MmoTune.value("barrage_pool_r"), "t": big, "dur": big, "every": 1.0, "tick_t": 1.0,
				"dmg": MmoTune.value("barrage_pool_dps"), "school": "fire", "name": "Burning Crater", "owner": "boss", "look": "fire_pool", "pool": true })
		"tread", "arc":
			var tread := str(a.on_fire) == "tread"
			for u: MmoUnit in s.living():
				if in_sector(u.pos, a, MmoSim.DODGE_PAD):
					u.dodge_faced += 1
				if in_sector(u.pos, a, u.radius * 0.5):
					u.fails += 1
					u.dodge_hit += 1
					s.damage(b, u, MmoTune.value("tread_dmg" if tread else "arc_dmg"), "fire", "Treadburn" if tread else "Main Gun", "mech")
			s._emit({ "type": "explode", "pos": a.pos, "dir": a.dir, "r": float(a.r), "half": float(a.half), "what": str(a.on_fire),
				"side": int(a.get("side", 0)) })


## Is `p` in something of the tank's? `who`: a raider the cannon is aimed at
## ignores that wedge (they're meant to take it).
func danger_at(p: Vector2, pad: float, who := "") -> bool:
	for a: Dictionary in s.areas:
		if str(a.kind) == "sector":
			if str(a.get("target", "")) != "" and str(a.target) == who:
				continue
			if in_sector(p, a, pad):
				return true
	if not smoke.is_empty():
		if smoke_at(p) > 0.45:
			return true
		var d := p.distance_to(smoke.c as Vector2)
		var r := float(smoke.r)
		if smoke.stage == "grow" and d > r and d - r < MmoTune.value("smoke_speed") * rate * 2.5 + pad:
			return true                                   # the front will be here in a moment
	for a: MmoUnit in adds:
		if a.alive and a.target == who and who != "" and p.distance_to(a.pos) < a.radius + 1.5:
			return true
	return false


## Spots in the clearing that are safe right now (the bots pick from these),
## a polar grid around the middle, worked out once a tick per raider.
func safe_spots(who: String) -> Array:
	var c: Array = _safe_cache.get(who, [-1.0, []])
	if float(c[0]) == s.time:
		return c[1]
	var out: Array = []
	for ri in 15:
		var rr := 2.5 + ri * 1.5
		var n := maxi(12, int(rr * 2.2))
		for k in n:
			var ang := TAU * k / n
			var p := Vector2(sin(ang), cos(ang)) * rr
			if p.distance_to(s.boss.pos) < s.boss.radius + 0.9 or p.length() > MmoSim.ARENA_R - 1.0:
				continue
			if not s.danger_at(p, 1.0, who):
				out.append(p)
	_safe_cache[who] = [s.time, out]
	return out


## On the flanks (the sides of the hull, not the nose or the tail)?
func on_flank(p: Vector2) -> bool:
	var d := (p - s.boss.pos).normalized()
	return absf(d.dot(s.boss.forward())) < 0.6
