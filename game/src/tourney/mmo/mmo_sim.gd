class_name MmoSim
extends RefCounted
## The raid as pure state on a fixed 30 Hz tick: six players and the Giant
## in a round courtyard. WoW Classic rules, small: a global cooldown, cast
## bars broken by moving, channels, auras (buffs, debuffs, dots, hots,
## shields), threat with taunts, resources (mana, rage, energy + combo
## points), the 180-degree facing rule, rez. No nodes. Same seed + same
## orders = same fight (lockstep later). MmoView draws it; MmoBot and the
## player feed it orders.
##
## Orders per unit per tick (all optional):
##   { mv: Vector2(right, forward) in -1..1, turn: -1..1 (keyboard turning),
##     yaw: float (mouse steering sets the facing), jump: true,
##     target: unit id ("" clears), cast: ability id, auto: bool, stop: true }
##
## The Giant (G22): auto-attacks its top threat (less than the pit's Giant),
## walks after it, and casts one spell at a time with at least
## MmoTune.spell_gap seconds between the end of one and the start of the next:
##   upheaval  raises its anchor, cracks run out at three players, then erupt
##   meteors   a hand to the sky; meteors rain on marked circles
##   bombs     a bomb on everyone; each blows up on its carrier: spread out
##   gather    a ring on the ground; outside it takes heavy damage, inside
##             shares a smaller hit: group up

const TICK := 1.0 / 30.0
const ARENA_R := 25.0
const BOSS_REACH := 3.6
const BOSS_WALK := 3.4
const PULL_R := 16.0
const FIRST_SPELL := 7.0
const SPELLS := ["upheaval", "meteors", "bombs", "gather"]
const SPELL_NAMES := { "upheaval": "Upheaval", "meteors": "Meteor Rain", "bombs": "Giant's Bombs", "gather": "Earthshatter" }
const SPELL_CAST := { "upheaval": 2.0, "meteors": 5.0, "bombs": 1.6, "gather": 1.8 }
const CRIT := 0.1
const QUEUE := 0.4              # a key pressed this close to the end of a cast / the GCD fires when it ends

var rng := RandomNumberGenerator.new()
var time := 0.0
var units: Array = []           # MmoUnit
var boss: MmoUnit
var areas: Array = []           # Dictionary
var winner := ""                # "" | "raid" | "boss"
var pulled := false
var pull_time := 0.0
var enraged := false
var spell := {}                 # the Giant's spell in progress: { id, t, total, stage, ... }
var next_spell_at := INF
var resolving := 0              # spell effects still pending (bomb fuses, the ring)
var _bag: Array = []
var _events: Array = []
var _next := 1
var _pending: Array = []        # { t, f: Callable }
var _queued := {}               # unit id -> ability id
var _bag_last := ""


func _init(p_seed: int = 1) -> void:
	rng.seed = p_seed


# ------------------------------------------------------------------ setup

func add_player(cls_id: String, pname: String) -> MmoUnit:
	var c: Dictionary = MmoClasses.CLASSES[cls_id]
	var u := MmoUnit.new()
	u.id = "%s_%d" % [cls_id, units.size()]
	u.name = pname
	u.cls = cls_id
	u.kind = "player"
	u.role = str(c.role)
	u.base_hp = float(c.hp)
	u.max_hp = u.base_hp
	u.hp = u.max_hp
	u.res_kind = str(c.res)
	u.res_max = float(c.res_max)
	u.res = u.res_max if u.res_kind != "rage" else 0.0
	u.radius = 0.45
	var n := units.filter(func(o: MmoUnit) -> bool: return o.kind == "player").size()
	u.pos = Vector2((n - 2.5) * 1.8, 19.0 + (n % 2) * 1.2)
	u.yaw = PI                       # facing -Z, toward the Giant
	for a: Dictionary in c.abilities:
		u.cd[str(a.id)] = 0.0
	units.append(u)
	return u


func add_boss() -> MmoUnit:
	var u := MmoUnit.new()
	u.id = "boss"
	u.name = "The Giant"
	u.kind = "boss"
	u.base_hp = MmoTune.value("boss_hp")
	u.max_hp = u.base_hp
	u.hp = u.max_hp
	u.res_kind = "none"
	u.radius = 0.6 * MmoTune.value("boss_scale")
	u.pos = Vector2(0, -3)
	u.yaw = 0.0
	units.append(u)
	boss = u
	return u


func unit(id: String) -> MmoUnit:
	for u: MmoUnit in units:
		if u.id == id:
			return u
	return null


func players() -> Array:
	return units.filter(func(o: MmoUnit) -> bool: return o.kind == "player")


func living() -> Array:
	return units.filter(func(o: MmoUnit) -> bool: return o.kind == "player" and o.alive)


func is_enemy(a: MmoUnit, b: MmoUnit) -> bool:
	return a.kind != b.kind


# ------------------------------------------------------------------- tick

func step(orders: Dictionary) -> Array:
	_events = []
	if winner != "":
		return _events
	time += TICK
	for p: Dictionary in _pending.duplicate():
		p.t = float(p.t) - TICK
		if float(p.t) <= 0.0:
			_pending.erase(p)
			(p.f as Callable).call()
	for u: MmoUnit in units:
		if u.kind == "player":
			_tick_player(u, orders.get(u.id, {}))
	_tick_boss()
	_tick_areas()
	if winner == "":
		if not boss.alive:
			_win("raid")
		elif living().is_empty():
			_win("boss")
	return _events


func _emit(e: Dictionary) -> void:
	e["time"] = time
	_events.append(e)


func _win(w: String) -> void:
	winner = w
	_emit({ "type": "win", "winner": w })


# ----------------------------------------------------------------- players

func _tick_player(u: MmoUnit, o: Dictionary) -> void:
	_tick_auras(u)
	for k: String in u.cd:
		u.cd[k] = maxf(0.0, float(u.cd[k]) - TICK)
	u.gcd = maxf(0.0, u.gcd - TICK)
	if not u.alive:
		u.moving = false
		u.move = Vector2.ZERO
		return
	_regen(u)
	if o.has("target"):
		var tid := str(o.target)
		if tid != u.target:
			u.target = tid
	if o.has("auto"):
		u.auto_on = bool(o.auto)
	_move(u, o)
	if o.get("stop", false) and u.casting():
		_cancel(u, "Interrupted")
	if o.has("cast"):
		var ab := str(o.cast)
		if not try_cast(u, ab):
			pass
	elif _queued.has(u.id) and u.gcd <= 0.0 and not u.casting():
		var q := str(_queued[u.id])
		_queued.erase(u.id)
		try_cast(u, q)
	_tick_cast(u)
	_tick_auto(u)


func _regen(u: MmoUnit) -> void:
	match u.res_kind:
		"mana":
			u.res = minf(u.res_max, u.res + u.res_max * 0.011 * u.mod("regen") * TICK)
		"energy":
			u.res = minf(u.res_max, u.res + 10.0 * u.mod("regen") * TICK)
		"rage":
			if not pulled:
				u.res = maxf(0.0, u.res - 2.0 * TICK)


func _move(u: MmoUnit, o: Dictionary) -> void:
	var still := u.frozen()
	if o.has("yaw") and not still:
		u.yaw = wrapf(float(o.yaw), -PI, PI)
	var turn := float(o.get("turn", 0.0))
	if turn != 0.0 and not still:
		u.yaw = wrapf(u.yaw - turn * deg_to_rad(MmoTune.value("turn_rate")) * TICK, -PI, PI)
	var mv: Vector2 = o.get("mv", Vector2.ZERO)
	if still:
		mv = Vector2.ZERO
	if mv.length() > 1.0:
		mv = mv.normalized()
	u.move = mv
	var back := mv.y < -0.01
	var sp := MmoTune.value("back_speed") if back else MmoTune.value("run_speed")
	sp *= u.mod("speed")
	var v := (u.forward() * mv.y + u.right() * mv.x) * sp
	u.moving = mv.length() > 0.01
	u.speed_now = v.length()
	u.pos += v * TICK
	if o.get("jump", false) and u.h <= 0.0 and not still:
		u.vh = MmoTune.value("jump")
		u.airborne = true
	if u.airborne or u.h > 0.0:
		u.vh -= MmoTune.value("gravity") * TICK
		u.h += u.vh * TICK
		if u.h <= 0.0:
			u.h = 0.0
			u.vh = 0.0
			u.airborne = false
	u.pos = _clamp(u.pos, u.radius)
	if (u.moving or u.airborne) and u.casting():          # your own steps break a cast; a shove doesn't
		_cancel(u, "Interrupted")


func _clamp(p: Vector2, r: float) -> Vector2:
	if p.length() > ARENA_R - r:
		p = p.normalized() * (ARENA_R - r)
	if boss and boss.alive:
		var d := p - boss.pos
		var min_d := boss.radius + r
		if d.length() < min_d:
			p = boss.pos + (d.normalized() if d.length() > 0.001 else Vector2.DOWN) * min_d
	return p


## WoW's rule: a hostile target must be in the front half.
func facing(u: MmoUnit, t: MmoUnit) -> bool:
	var d := t.pos - u.pos
	if d.length() < 0.01:
		return true
	return u.forward().dot(d.normalized()) > -0.05


func behind(u: MmoUnit, t: MmoUnit) -> bool:
	var d := (u.pos - t.pos)
	return t.forward().dot(d.normalized()) < -0.2


func dist(a: MmoUnit, b: MmoUnit) -> float:
	return maxf(0.0, a.pos.distance_to(b.pos) - a.radius - b.radius)


# ------------------------------------------------------------------ casting

## Start an ability. false (and an "error" event for the player's screen)
## when it can't go: the same messages WoW gives.
func try_cast(u: MmoUnit, ab_id: String) -> bool:
	var ab := MmoClasses.ability(u.cls, ab_id)
	if ab.is_empty() or not u.alive:
		return false
	if u.frozen():
		return _err(u, "You can't do that right now.")
	var uses_gcd := bool(ab.get("gcd", true))
	if float(u.cd.get(ab_id, 0.0)) > 0.0:
		return _err(u, "That isn't ready yet.")
	if u.casting():
		var left := float(u.cast.total) - float(u.cast.t)
		if left <= QUEUE:
			_queued[u.id] = ab_id
			return false
		if uses_gcd:
			return _err(u, "Another action is in progress.")
	if uses_gcd and u.gcd > 0.0:
		if u.gcd <= QUEUE:
			_queued[u.id] = ab_id
		return false
	var cost := float(ab.get("cost", 0.0))
	if u.res < cost:
		return _err(u, "Not enough %s." % u.res_kind)
	var tgt := _resolve_target(u, ab)
	var kind := str(ab.get("tgt", "none"))
	if kind in ["enemy", "ally", "dead", "any"] and tgt == null:
		match kind:
			"enemy": return _err(u, "You have no target.")
			"dead": return _err(u, "Target a fallen ally.")
			_: return _err(u, "Invalid target.")
	var rng_ := float(ab.get("range", 0.0))
	if tgt and tgt != u and rng_ > 0.0 and dist(u, tgt) > rng_:
		return _err(u, "Out of range.")
	if tgt and is_enemy(u, tgt):
		if not facing(u, tgt):
			return _err(u, "You are facing the wrong way!")
		if ab.get("behind", false) and not behind(u, tgt):
			return _err(u, "You must be behind your target.")
		if ab.get("exec", false) and tgt.hp_pct() > 0.2:
			return _err(u, "Your target must be below 20% health.")
	if ab.get("finisher", false) and u.cp <= 0:
		return _err(u, "That ability requires combo points.")
	var cast_t := float(ab.get("cast", 0.0))
	var chan := float(ab.get("channel", 0.0))
	if (cast_t > 0.0 or chan > 0.0) and (u.moving or u.airborne):
		if not (cast_t > 0.0 and u.flags.get("instant_next", false)):
			return _err(u, "You can't do that while moving.")
	# go
	u.res -= cost
	if uses_gcd:
		u.gcd = float(MmoClasses.CLASSES[u.cls].gcd) if MmoClasses.CLASSES[u.cls].has("gcd") else MmoTune.value("gcd")
	u.last_ab = ab_id
	u.cast_serial += 1
	if tgt and is_enemy(u, tgt):
		_pull()
		if float(ab.get("range", 0.0)) <= MmoClasses.MELEE + 0.1 and MmoClasses.CLASSES[u.cls].auto.has("dmg"):
			u.auto_on = true
	if cast_t > 0.0 and u.flags.get("instant_next", false):
		u.flags.erase("instant_next")
		cast_t = 0.0
	if cast_t > 0.0:
		u.cast = { "ab": ab_id, "t": 0.0, "total": cast_t, "target": tgt.id if tgt else "", "channel": false }
		_emit({ "type": "cast_start", "id": u.id, "ab": ab_id, "total": cast_t })
		return true
	if chan > 0.0:
		var ticks := int(ab.get("ticks", 3))
		u.cast = { "ab": ab_id, "t": 0.0, "total": chan, "target": tgt.id if tgt else "", "channel": true,
			"ticks": ticks, "every": chan / ticks, "tick_t": chan / ticks, "done": 0,
			"at": tgt.pos if tgt else u.pos }
		u.cd[ab_id] = float(ab.get("cd", 0.0))
		_emit({ "type": "cast_start", "id": u.id, "ab": ab_id, "total": chan, "channel": true })
		return true
	u.cd[ab_id] = float(ab.get("cd", 0.0))
	_apply(u, ab, tgt)
	return true


func _err(u: MmoUnit, text: String) -> bool:
	_emit({ "type": "error", "id": u.id, "text": text })
	return false


func _resolve_target(u: MmoUnit, ab: Dictionary) -> MmoUnit:
	var t := unit(u.target) if u.target != "" else null
	match str(ab.get("tgt", "none")):
		"enemy":
			return t if t and t.alive and is_enemy(u, t) else null
		"ally":
			if t and t.alive and not is_enemy(u, t):
				return t
			return u                                   # WoW: no friendly target = yourself
		"dead":
			return t if t and not t.alive and t.kind == "player" else null
		"any":
			if t and t.alive:
				return t
			return u
		"self":
			return u
	return null


func _tick_cast(u: MmoUnit) -> void:
	if not u.casting():
		return
	var ab := MmoClasses.ability(u.cls, str(u.cast.ab))
	u.cast.t = float(u.cast.t) + TICK
	var tgt := unit(str(u.cast.target)) if str(u.cast.target) != "" else null
	if u.cast.channel:
		u.cast.tick_t = float(u.cast.tick_t) - TICK
		if float(u.cast.tick_t) <= 0.0 and int(u.cast.done) < int(u.cast.ticks):
			u.cast.tick_t = float(u.cast.every)
			u.cast.done = int(u.cast.done) + 1
			if tgt and str(ab.get("tgt", "")) == "enemy" and not tgt.alive:
				_cancel(u, "")
				return
			_apply(u, ab, tgt, true)
		if float(u.cast.t) >= float(u.cast.total):
			u.cast = {}
			_emit({ "type": "cast_end", "id": u.id })
		return
	if float(u.cast.t) >= float(u.cast.total):
		u.cast = {}
		var kind := str(ab.get("tgt", ""))
		if tgt and kind == "enemy" and not tgt.alive:
			_emit({ "type": "cast_end", "id": u.id })
			return
		if tgt and kind == "dead" and tgt.alive:
			_emit({ "type": "cast_end", "id": u.id })
			return
		if tgt and tgt != u and float(ab.get("range", 0.0)) > 0.0 and dist(u, tgt) > float(ab.range) + 2.0:
			_err(u, "Out of range.")
			_emit({ "type": "cast_end", "id": u.id })
			return
		_emit({ "type": "cast_end", "id": u.id })
		u.cd[str(ab.id)] = float(ab.get("cd", 0.0))          # a cast's cooldown starts when it lands
		_apply(u, ab, tgt)


func _cancel(u: MmoUnit, why: String) -> void:
	if not u.casting():
		return
	u.cast = {}
	_emit({ "type": "cast_end", "id": u.id, "why": why })


## Run an ability's effects. `tick` = one tick of a channel.
func _apply(u: MmoUnit, ab: Dictionary, tgt: MmoUnit, tick := false) -> void:
	var school := str(ab.get("school", "phys"))
	var name_ := str(ab.name)
	var threat := float(ab.get("threat", 1.0))
	var crit_next := bool(u.flags.get("crit_next", false)) and not tick
	if crit_next:
		u.flags.erase("crit_next")
	var cp := u.cp
	if ab.get("finisher", false):
		u.cp = 0
	_emit({ "type": "use", "id": u.id, "ab": str(ab.id), "target": tgt.id if tgt else "", "tick": tick })
	if str(ab.get("anim", "")) == "strike":
		u.strike_serial += 1
	var delay := 0.0
	if ab.has("proj") and tgt and tgt != u:
		delay = u.pos.distance_to(tgt.pos) / float(ab.proj)
		_emit({ "type": "proj", "src": u.id, "tgt": tgt.id, "ab": str(ab.id), "school": school, "t": delay })
	for fx: Dictionary in ab.fx:
		var f := fx
		var go := func() -> void: _effect(u, ab, f, tgt, school, name_, threat, crit_next, cp)
		if delay > 0.0 and (f.has("dmg") or f.has("dot")):
			_pending.append({ "t": delay, "f": go })
		else:
			go.call()


func _effect(u: MmoUnit, ab: Dictionary, f: Dictionary, tgt: MmoUnit, school: String, name_: String, threat: float, crit_next: bool, cp: int) -> void:
	if f.has("dmg") or f.has("or_dmg"):
		if f.has("heal") and tgt and not is_enemy(u, tgt):
			heal(u, tgt, float(f.heal), name_)
		elif tgt and is_enemy(u, tgt):
			var n := float(f.get("dmg", f.get("or_dmg", 0.0))) + float(f.get("per_cp", 0.0)) * cp
			damage(u, tgt, n, school, name_, "hit", threat, crit_next)
		return
	if f.has("heal") and not f.has("or_dmg"):
		var who := u if f.get("self", false) or tgt == null else tgt
		heal(u, who, float(f.heal), name_)
		return
	if f.has("heal_pct"):
		heal(u, u, u.max_hp * float(f.heal_pct), name_)
		return
	if f.has("full_heal") and tgt:
		heal(u, tgt, tgt.max_hp, name_)
		return
	if f.has("aoe"):
		var at := u.pos if str(f.get("at", "self")) == "self" or tgt == null else tgt.pos
		for o: MmoUnit in units:
			if o.alive and is_enemy(u, o) and o.pos.distance_to(at) <= float(f.r) + o.radius:
				damage(u, o, float(f.aoe), school, name_, "hit", threat, crit_next)
		_emit({ "type": "burst", "id": u.id, "pos": at, "r": float(f.r), "school": school })
		return
	if f.has("dot") and tgt:
		var total := float(f.dot) + float(f.get("per_cp", 0.0)) * cp
		add_aura(tgt, { "id": "%s_%s" % [str(ab.id), u.id], "name": name_, "src": u.id, "dur": float(f.dur), "every": 3.0 if float(f.dur) >= 9.0 else 1.0,
			"dot": total, "school": school, "glyph": str(ab.glyph), "col": str(ab.col), "debuff": true, "threat": threat })
		return
	if f.has("hot"):
		var who := tgt if tgt else u
		add_aura(who, { "id": "%s_%s" % [str(ab.id), u.id], "name": name_, "src": u.id, "dur": float(f.dur), "every": 3.0,
			"hot": float(f.hot), "glyph": str(ab.glyph), "col": str(ab.col) })
		return
	if f.has("group_heal"):
		for o: MmoUnit in living():
			if o.pos.distance_to(u.pos) <= float(f.r):
				heal(u, o, float(f.group_heal), name_)
		return
	if f.has("shield"):
		var who := u if f.get("self", false) or tgt == null else tgt
		if who.has_aura("weakened_soul") and str(ab.id) == "pw_shield":
			return
		add_aura(who, { "id": str(ab.id), "name": name_, "src": u.id, "dur": float(f.dur), "shield": float(f.shield) * u.mod("heal"),
			"glyph": str(ab.glyph), "col": str(ab.col) })
		if str(ab.id) == "pw_shield":
			add_aura(who, { "id": "weakened_soul", "name": "Weakened Soul", "dur": 15.0, "glyph": "crack", "col": "#8a8aa0", "debuff": true })
		return
	if f.has("buff"):
		var dur := float(f.dur) + float(f.get("per_cp_dur", 0.0)) * cp
		var targets: Array = [u]
		match str(f.get("who", "self")):
			"raid": targets = living()
			"target": targets = [tgt if tgt else u]
		if f.has("group"):
			for o: MmoUnit in targets:
				for a: Dictionary in o.auras.duplicate():
					if str(a.get("group", "")) == str(f.group):
						o.auras.erase(a)
		for o: MmoUnit in targets:
			add_aura(o, { "id": str(f.get("id", ab.id)), "name": name_, "src": u.id, "dur": dur, "mods": f.buff,
				"glyph": str(ab.glyph), "col": str(ab.col), "group": str(f.get("group", "")) })
		if (f.buff as Dictionary).has("maxhp"):
			for o: MmoUnit in targets:
				_refresh_maxhp(o)
		return
	if f.has("debuff"):
		var hits: Array = []
		if f.has("r"):
			for o: MmoUnit in units:
				if o.alive and is_enemy(u, o) and o.pos.distance_to(u.pos) <= float(f.r) + o.radius:
					hits.append(o)
		elif tgt and is_enemy(u, tgt):
			hits.append(tgt)
		for o: MmoUnit in hits:
			add_aura(o, { "id": str(f.get("id", ab.id)), "name": name_, "src": u.id, "dur": float(f.dur), "mods": f.debuff,
				"glyph": str(ab.glyph), "col": str(ab.col), "debuff": true })
			add_threat(u, o, 60.0 * threat)
		return
	if f.has("immune"):
		var who := tgt if str(f.get("on", "self")) == "target" and tgt else u
		add_aura(who, { "id": str(ab.id), "name": name_, "src": u.id, "dur": float(f.immune), "immune": true,
			"still": bool(f.get("still", false)), "glyph": str(ab.glyph), "col": str(ab.col) })
		if f.get("still", false):
			_cancel(who, "")
		return
	if f.has("taunt") and tgt and tgt == boss:
		var top := 0.0
		for k: String in boss.threat:
			top = maxf(top, float(boss.threat[k]))
		boss.threat[u.id] = top * 1.1 + 100.0
		boss.target = u.id
		boss.flags["taunt_t"] = 3.0
		boss.flags["taunt_by"] = u.id
		_emit({ "type": "taunt", "id": u.id })
		return
	if f.has("drop_threat"):
		if boss and boss.threat.has(u.id):
			boss.threat[u.id] = float(boss.threat[u.id]) * (1.0 - float(f.drop_threat))
		_emit({ "type": "resource", "id": u.id, "what": "threat" })
		return
	if f.has("dash"):
		_dash(u, f, tgt)
		return
	if f.has("res") and tgt and not tgt.alive:
		tgt.alive = true
		tgt.hp = tgt.max_hp * float(f.res)
		tgt.res = tgt.res_max * 0.3 if tgt.res_kind == "mana" else 0.0
		tgt.auras.clear()
		_emit({ "type": "res", "id": tgt.id, "by": u.id })
		return
	if f.has("gain"):
		u.res = minf(u.res_max, u.res + float(f.gain))
		_emit({ "type": "resource", "id": u.id, "what": u.res_kind })
		return
	if f.has("cp"):
		u.cp = mini(5, u.cp + int(f.cp))
		return
	if f.has("cleanse"):
		var who := tgt if tgt else u
		for a: Dictionary in who.auras:
			if a.get("cleanse", false):
				who.auras.erase(a)
				_emit({ "type": "cleansed", "id": who.id, "name": str(a.name), "by": u.id })
				break
		return
	if f.has("mana"):
		u.res = minf(u.res_max, u.res + u.res_max * float(f.mana))
		_emit({ "type": "resource", "id": u.id, "what": "mana" })
		return
	if f.has("instant_next"):
		u.flags["instant_next"] = true
		add_aura(u, { "id": str(ab.id), "name": name_, "dur": 30.0, "glyph": str(ab.glyph), "col": str(ab.col) })
		return
	if f.has("crit_next"):
		u.flags["crit_next"] = true
		add_aura(u, { "id": str(ab.id), "name": name_, "dur": 30.0, "glyph": str(ab.glyph), "col": str(ab.col) })
		return
	if f.has("ground"):
		var at := u.pos if str(f.get("at", "self")) == "self" or tgt == null else tgt.pos
		if f.get("channel", false):
			var ch_at: Vector2 = u.cast.get("at", at) if u.casting() else at
			for o: MmoUnit in units:
				if o.alive and is_enemy(u, o) and o.pos.distance_to(ch_at) <= float(f.r) + o.radius:
					damage(u, o, float(f.ground), school, name_, "hit", threat, false)
			_emit({ "type": "ground_tick", "id": u.id, "pos": ch_at, "r": float(f.r), "school": school, "ab": str(ab.id) })
			return
		_add_area({ "kind": "ground", "pos": at, "r": float(f.r), "t": float(f.every) * int(f.ticks), "dur": float(f.every) * int(f.ticks),
			"every": float(f.every), "tick_t": float(f.every), "dmg": float(f.ground), "owner": u.id, "school": school, "name": name_, "look": str(ab.id) })
		return


func _dash(u: MmoUnit, f: Dictionary, tgt: MmoUnit) -> void:
	var from := u.pos
	match str(f.dir):
		"target":
			if tgt:
				var d := (tgt.pos - u.pos)
				u.pos = tgt.pos - d.normalized() * (tgt.radius + u.radius + 0.6)
		"behind":
			if tgt:
				u.pos = tgt.pos - tgt.forward() * (tgt.radius + u.radius + 0.7)
				u.yaw = atan2(tgt.pos.x - u.pos.x, tgt.pos.y - u.pos.y)
		"forward":
			u.pos += u.forward() * float(f.dash)
		"back":
			u.pos -= u.forward() * float(f.dash)
	u.pos = _clamp(u.pos, u.radius)
	_cancel(u, "")
	_emit({ "type": "dash", "id": u.id, "from": from, "to": u.pos, "how": str(f.dir) })


func _refresh_maxhp(u: MmoUnit) -> void:
	var share := u.hp_pct()
	u.max_hp = u.base_hp * u.mod("maxhp")
	u.hp = clampf(share * u.max_hp, 1.0, u.max_hp)


# ------------------------------------------------------------------- autos

func _tick_auto(u: MmoUnit) -> void:
	var a: Dictionary = MmoClasses.CLASSES[u.cls].auto
	if a.is_empty():
		return
	u.swing_t = maxf(0.0, u.swing_t - TICK * u.mod("haste"))
	if not u.auto_on or u.swing_t > 0.0:
		return
	var t := unit(u.target)
	if t == null or not t.alive or not is_enemy(u, t):
		return
	if dist(u, t) > float(a.range) or not facing(u, t):
		return
	if a.get("ranged", false) and (u.casting() or u.moving):
		return
	u.swing_t = float(a.speed)
	u.strike_serial += 1
	_pull()
	var n := float(a.dmg) + u.add("proc")
	if a.get("ranged", false):
		var dl := u.pos.distance_to(t.pos) / 50.0
		_emit({ "type": "proj", "src": u.id, "tgt": t.id, "ab": "auto_shot", "school": "phys", "t": dl })
		_pending.append({ "t": dl, "f": func() -> void: damage(u, t, n, "phys", "Auto Shot", "auto", 1.0, false) })
	else:
		_emit({ "type": "swing", "id": u.id, "target": t.id })
		damage(u, t, n, "phys", "Melee", "auto", 1.0, false)
		if u.res_kind == "rage":
			u.res = minf(u.res_max, u.res + 9.0)


# ------------------------------------------------------------------- damage

func damage(src: MmoUnit, t: MmoUnit, amount: float, school: String, what: String, kind: String, threat := 1.0, force_crit := false) -> float:
	if t == null or not t.alive or amount <= 0.0:
		return 0.0
	if t.immune():
		_emit({ "type": "immune", "src": src.id if src else "", "tgt": t.id, "what": what })
		return 0.0
	var n := amount
	var crit := false
	if src and src.kind == "player":
		n *= src.mod("dmg") * MmoTune.value("dmg_mult")
		n *= t.mod("taken")
		if kind != "dot":
			crit = force_crit or rng.randf() < CRIT + src.add("crit")
			if crit:
				n *= 2.0
	elif src and src.kind == "boss":
		n *= src.mod("dmg")
		if enraged:
			n *= 5.0
		if kind == "auto":
			n *= float(MmoClasses.CLASSES[t.cls].armor)
	n *= t.mod("dr")
	n = roundf(n)
	var absorbed := 0.0
	for a: Dictionary in t.auras.duplicate():
		if a.has("shield") and n > 0.0:
			var take := minf(float(a.shield), n)
			a.shield = float(a.shield) - take
			n -= take
			absorbed += take
			if float(a.shield) <= 0.0:
				t.auras.erase(a)
	t.hp -= n
	t.hit_serial += 1
	if src:
		src.dmg_done += n + absorbed if src.kind == "player" else 0.0
		if src.kind == "player" and t == boss:
			add_threat(src, t, (n + absorbed) * threat)
	if t.res_kind == "rage":
		t.res = minf(t.res_max, t.res + (n + absorbed) / 35.0)
	if t.casting() and str(t.cast.ab) == "bandage" and n > 0.0:
		_cancel(t, "Interrupted")
	_emit({ "type": "dmg", "src": src.id if src else "", "tgt": t.id, "n": n, "absorbed": absorbed, "crit": crit,
		"what": what, "school": school, "kind": kind })
	if t.hp <= 0.0:
		_die(t, src)
	return n


func heal(src: MmoUnit, t: MmoUnit, amount: float, what: String, kind := "hit") -> float:
	if t == null or not t.alive:
		return 0.0
	var n := amount * src.mod("heal") * MmoTune.value("heal_mult")
	var crit := false
	if kind != "hot" and rng.randf() < CRIT + src.add("crit"):
		crit = true
		n *= 1.5
	n = roundf(n)
	var eff := minf(n, t.max_hp - t.hp)
	t.hp += eff
	src.heal_done += eff
	if pulled and boss and boss.alive and eff > 0.0:
		add_threat(src, boss, eff * 0.5)
	_emit({ "type": "heal", "src": src.id, "tgt": t.id, "n": n, "eff": eff, "crit": crit, "what": what, "kind": kind })
	return eff


func add_threat(src: MmoUnit, b: MmoUnit, n: float) -> void:
	if b != boss or src.kind != "player":
		return
	var k := float(MmoClasses.CLASSES[src.cls].threat) * src.mod("threat")
	b.threat[src.id] = float(b.threat.get(src.id, 0.0)) + n * k


func _die(t: MmoUnit, src: MmoUnit) -> void:
	t.alive = false
	t.hp = 0.0
	t.cast = {}
	t.auras = t.auras.filter(func(a: Dictionary) -> bool: return a.get("keep_dead", false))
	t.deaths += 1
	t.auto_on = false
	if boss and boss.threat.has(t.id):
		boss.threat.erase(t.id)
	_emit({ "type": "death", "id": t.id, "by": src.id if src else "" })


# -------------------------------------------------------------------- auras

## { id, name, src, dur, t (left), mods, dot / hot (totals), every, shield,
##   immune, still, debuff, cleanse, glyph, col, fuse (bombs) }. Same id on
## the same unit refreshes it.
func add_aura(u: MmoUnit, a: Dictionary) -> void:
	if not u.alive:
		return
	for old: Dictionary in u.auras:
		if str(old.id) == str(a.id):
			u.auras.erase(old)
			break
	a["t"] = float(a.dur)
	if a.has("dot") or a.has("hot"):
		var every := float(a.get("every", 3.0))
		var n := maxi(1, int(round(float(a.dur) / every)))
		a["per"] = float(a.get("dot", a.get("hot", 0.0))) / n
		a["tick_t"] = every
	u.auras.append(a)
	_emit({ "type": "aura", "id": u.id, "src": str(a.get("src", "")), "aura": str(a.id), "on": true, "debuff": bool(a.get("debuff", false)) })


func _tick_auras(u: MmoUnit) -> void:
	for a: Dictionary in u.auras.duplicate():
		a.t = float(a.t) - TICK
		if a.has("per"):
			a.tick_t = float(a.tick_t) - TICK
			if float(a.tick_t) <= 0.0:
				a.tick_t = float(a.every)
				var src := unit(str(a.get("src", "")))
				if a.has("dot"):
					damage(src if src else boss, u, float(a.per), str(a.get("school", "phys")), str(a.name), "dot", float(a.get("threat", 1.0)))
				elif src:
					heal(src, u, float(a.per), str(a.name), "hot")
		if float(a.t) <= 0.0:
			u.auras.erase(a)
			_emit({ "type": "aura", "id": u.id, "aura": str(a.id), "on": false })
			if a.has("fuse"):
				(a.fuse as Callable).call()
			if (a.get("mods", {}) as Dictionary).has("maxhp"):
				_refresh_maxhp(u)
		if not u.alive:
			return


# --------------------------------------------------------------------- boss

func _pull() -> void:
	if pulled:
		return
	pulled = true
	pull_time = time
	next_spell_at = time + FIRST_SPELL
	_emit({ "type": "pull" })
	_emit({ "type": "warn", "text": "The Giant wakes!", "col": "#ff4a3a" })


func _tick_boss() -> void:
	var b := boss
	if b == null or not b.alive:
		return
	_tick_auras(b)
	if not pulled:
		for u: MmoUnit in living():
			if u.pos.distance_to(b.pos) < PULL_R:
				_pull()
		return
	if not enraged and time - pull_time >= MmoTune.value("enrage"):
		enraged = true
		_emit({ "type": "warn", "text": "The Giant goes into a rage!", "col": "#ff2020" })
	# the target: top threat (a taunt holds it for 3 s; 10% over to pull it off)
	b.flags["taunt_t"] = maxf(0.0, float(b.flags.get("taunt_t", 0.0)) - TICK)
	var cur := unit(b.target)
	if float(b.flags.taunt_t) <= 0.0 or cur == null or not cur.alive:
		var best: MmoUnit = null
		var bt := -1.0
		for u: MmoUnit in living():
			if u.add("stealth") > 0.0:
				continue
			var th := float(b.threat.get(u.id, 0.0))
			if u == cur:
				th *= 1.1
			if th > bt:
				bt = th
				best = u
		if best and best != cur:
			b.target = best.id
			cur = best
	if cur == null:
		return
	var busy := not spell.is_empty() and str(spell.get("stage", "")) != "after"
	# face and follow
	var want := atan2(cur.pos.x - b.pos.x, cur.pos.y - b.pos.y)
	if not busy:
		var dy := wrapf(want - b.yaw, -PI, PI)
		b.yaw = wrapf(b.yaw + clampf(dy, -2.6 * TICK, 2.6 * TICK), -PI, PI)
		var d := dist(b, cur)
		b.moving = d > BOSS_REACH
		if b.moving:
			b.pos += (cur.pos - b.pos).normalized() * BOSS_WALK * TICK
			b.pos = b.pos.limit_length(ARENA_R - b.radius - 2.0)
	else:
		b.moving = false
	# swing
	b.swing_t = maxf(0.0, b.swing_t - TICK / b.mod("swing"))
	if not busy and b.swing_t <= 0.0 and dist(b, cur) <= BOSS_REACH + 0.4 and absf(wrapf(want - b.yaw, -PI, PI)) < 1.2:
		b.swing_t = MmoTune.value("boss_swing") * (0.6 if enraged else 1.0)
		b.strike_serial += 1
		var tgt := cur
		_pending.append({ "t": 0.45, "f": func() -> void:
			if tgt.alive and b.alive and dist(b, tgt) <= BOSS_REACH + 1.5:
				damage(b, tgt, MmoTune.value("boss_auto"), "phys", "Melee", "auto") })
	_tick_spell()


func _tick_spell() -> void:
	if spell.is_empty():
		if time >= next_spell_at and resolving <= 0:
			_begin_spell()
		return
	spell.t = float(spell.t) + TICK
	match str(spell.id):
		"upheaval": _upheaval()
		"meteors": _meteors()
		"bombs": _bombs()
		"gather": _gather()


func _begin_spell() -> void:
	if _bag.is_empty():
		_bag = SPELLS.duplicate()
		for i in range(_bag.size() - 1, 0, -1):            # a seeded shuffle, never the same spell twice running
			var j := rng.randi_range(0, i)
			var tmp: Variant = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = tmp
		if str(_bag[0]) == _bag_last and _bag.size() > 1:
			_bag.push_back(_bag.pop_front())
	var id := str(_bag.pop_front())
	spell = { "id": id, "t": 0.0, "total": float(SPELL_CAST[id]), "stage": "cast" }
	boss.cast = { "ab": id, "t": 0.0, "total": float(SPELL_CAST[id]), "channel": id == "meteors" }
	boss.cast_serial += 1
	boss.last_ab = id
	_emit({ "type": "boss_spell", "spell": id, "stage": "cast" })
	match id:
		"upheaval":
			_emit({ "type": "warn", "text": "The Giant raises its anchor: step out of the cracks!", "col": "#e0a050" })
			var pool := living().filter(func(u: MmoUnit) -> bool: return u.id != boss.target)
			if pool.is_empty():
				pool = living()
			var picks: Array = []
			for i in 3:
				if pool.is_empty():
					break
				picks.append(pool.pop_at(rng.randi() % pool.size()))
			var lines: Array = []
			for u: MmoUnit in picks:
				var dir := (u.pos - boss.pos).normalized()
				lines.append(_add_area({ "kind": "line", "pos": boss.pos, "dir": dir, "len": ARENA_R * 2.0, "w": 3.6,
					"t": float(SPELL_CAST.upheaval), "dur": float(SPELL_CAST.upheaval), "look": "upheaval", "owner": "boss" }))
			spell["lines"] = lines
		"meteors":
			_emit({ "type": "warn", "text": "The Giant calls down meteors! Keep out of the circles!", "col": "#ff6a2a" })
			spell["fallen"] = 0
		"bombs":
			_emit({ "type": "warn", "text": "Bombs on everyone: SPREAD OUT!", "col": "#ff4a3a" })
		"gather":
			var ang := rng.randf() * TAU
			var at := boss.pos + Vector2(cos(ang), sin(ang)) * 11.0
			if at.length() > ARENA_R - 6.0:
				at = at.normalized() * (ARENA_R - 6.0)
			spell["at"] = at


func _end_spell(stage_after := 0.6) -> void:
	spell.stage = "after"
	spell["after_t"] = stage_after
	boss.cast = {}


func _spell_after() -> bool:
	if str(spell.stage) != "after":
		return false
	spell.after_t = float(spell.after_t) - TICK
	if float(spell.after_t) <= 0.0:
		_bag_last = str(spell.id)
		spell = {}
		next_spell_at = time + MmoTune.value("spell_gap")
	return true


func _upheaval() -> void:
	if _spell_after():
		return
	if boss.cast.has("ab"):
		boss.cast.t = spell.t
	if float(spell.t) >= float(spell.total):
		var dmg := MmoTune.value("upheaval_dmg")
		var hit := {}
		for a: Dictionary in spell.get("lines", []):
			for u: MmoUnit in living():
				if hit.has(u.id):
					continue
				if _in_line(u.pos, a):
					hit[u.id] = true
					u.fails += 1
					damage(boss, u, dmg, "earth", "Upheaval", "mech")
					if u.alive:
						u.vh = 8.0
						u.airborne = true
						add_aura(u, { "id": "shattered", "name": "Shattered", "dur": 6.0, "mods": { "speed": 0.6 }, "debuff": true,
							"cleanse": true, "glyph": "crack", "col": "#a08060" })
		_emit({ "type": "boss_spell", "spell": "upheaval", "stage": "fire", "lines": spell.get("lines", []) })
		_end_spell(1.0)


func _in_line(p: Vector2, a: Dictionary) -> bool:
	var d := p - (a.pos as Vector2)
	var along := d.dot(a.dir as Vector2)
	if along < 0.0 or along > float(a.len):
		return false
	var off := absf(d.dot((a.dir as Vector2).orthogonal()))
	return off <= float(a.w) * 0.5 + 0.4


func _meteors() -> void:
	if _spell_after():
		return
	if boss.cast.has("ab"):
		boss.cast.t = spell.t
	var n := int(MmoTune.value("meteor_count"))
	var span := float(spell.total) - 0.6
	var due := mini(n, int(floor(float(spell.t) / span * n)) + 1) if float(spell.t) < span else n
	while int(spell.fallen) < due:
		spell.fallen = int(spell.fallen) + 1
		var at: Vector2
		var ppl := living()
		if int(spell.fallen) % 3 == 0 and not ppl.is_empty():
			at = (ppl[rng.randi() % ppl.size()] as MmoUnit).pos         # every third one hunts somebody
		else:
			var ang := rng.randf() * TAU
			at = Vector2(cos(ang), sin(ang)) * sqrt(rng.randf()) * (ARENA_R - 2.0)
		_add_area({ "kind": "circle", "pos": at, "r": 3.4, "t": 1.7, "dur": 1.7, "look": "meteor", "owner": "boss",
			"on_fire": "meteor" })
	if float(spell.t) >= float(spell.total):
		_end_spell(0.8)


func _bombs() -> void:
	if _spell_after():
		return
	if boss.cast.has("ab"):
		boss.cast.t = spell.t
	if str(spell.stage) == "cast" and float(spell.t) >= float(spell.total):
		spell.stage = "fuse"
		boss.cast = {}
		var fuse := MmoTune.value("bomb_fuse")
		for u: MmoUnit in living():
			var carrier := u
			resolving += 1
			add_aura(u, { "id": "bomb", "name": "Giant's Bomb", "dur": fuse, "debuff": true, "glyph": "bomb", "col": "#ff5a2a",
				"fuse": func() -> void: _bomb_pop(carrier) })
			_add_area({ "kind": "bomb", "pos": u.pos, "r": MmoTune.value("bomb_radius"), "t": fuse, "dur": fuse, "follow": u.id,
				"look": "bomb", "owner": "boss" })
		_emit({ "type": "boss_spell", "spell": "bombs", "stage": "fire" })
		spell["fuse_t"] = fuse
	if str(spell.stage) == "fuse":
		spell.fuse_t = float(spell.fuse_t) - TICK
		if float(spell.fuse_t) <= -0.1:
			resolving = 0
			_end_spell(0.3)


func _bomb_pop(c: MmoUnit) -> void:
	resolving = maxi(0, resolving - 1)
	var at := c.pos
	var r := MmoTune.value("bomb_radius")
	var dmg := MmoTune.value("bomb_dmg")
	damage(boss, c, dmg * 0.35, "fire", "Giant's Bomb", "mech")
	for u: MmoUnit in living():
		if u != c and u.pos.distance_to(at) <= r:
			u.fails += 1
			damage(boss, u, dmg, "fire", "Giant's Bomb", "mech")
	_emit({ "type": "explode", "pos": at, "r": r, "what": "bomb" })


func _gather() -> void:
	if _spell_after():
		return
	if boss.cast.has("ab"):
		boss.cast.t = spell.t
	if str(spell.stage) == "cast" and float(spell.t) >= float(spell.total):
		spell.stage = "ring"
		boss.cast = {}
		var fuse := MmoTune.value("gather_fuse")
		resolving += 1
		spell["ring"] = _add_area({ "kind": "ring", "pos": spell.at, "r": MmoTune.value("gather_radius"), "t": fuse, "dur": fuse,
			"look": "gather", "owner": "boss", "on_fire": "gather" })
		_emit({ "type": "warn", "text": "Earthshatter! GET IN THE RING!", "col": "#ffd040" })
		_emit({ "type": "boss_spell", "spell": "gather", "stage": "fire", "at": spell.at })
	if str(spell.stage) == "ring" and resolving <= 0:
		_end_spell(0.4)


func _gather_fire(a: Dictionary) -> void:
	resolving = maxi(0, resolving - 1)
	var inside: Array = []
	var outside: Array = []
	for u: MmoUnit in living():
		if u.pos.distance_to(a.pos as Vector2) <= float(a.r) + u.radius * 0.5:
			inside.append(u)
		else:
			outside.append(u)
	var share := MmoTune.value("gather_split") / maxf(1.0, float(inside.size()))
	for u: MmoUnit in inside:
		damage(boss, u, share, "earth", "Earthshatter", "mech")
	for u: MmoUnit in outside:
		u.fails += 1
		damage(boss, u, MmoTune.value("gather_dmg"), "earth", "Earthshatter", "mech")
	_emit({ "type": "explode", "pos": a.pos, "r": ARENA_R, "what": "gather", "inside": inside.size() })


# -------------------------------------------------------------------- areas

func _add_area(a: Dictionary) -> Dictionary:
	a["id"] = _next
	_next += 1
	areas.append(a)
	_emit({ "type": "area", "area": a })
	return a


func _tick_areas() -> void:
	for a: Dictionary in areas.duplicate():
		if a.has("follow"):
			var f := unit(str(a.follow))
			if f and f.alive:
				a.pos = f.pos
		a.t = float(a.t) - TICK
		if str(a.kind) == "ground":
			a.tick_t = float(a.tick_t) - TICK
			if float(a.tick_t) <= 0.0:
				a.tick_t = float(a.every)
				var src := unit(str(a.owner))
				for o: MmoUnit in units:
					if src and o.alive and is_enemy(src, o) and o.pos.distance_to(a.pos as Vector2) <= float(a.r) + o.radius:
						damage(src, o, float(a.dmg), str(a.school), str(a.name), "hit")
		if float(a.t) <= 0.0:
			areas.erase(a)
			match str(a.get("on_fire", "")):
				"meteor":
					for u: MmoUnit in living():
						if u.pos.distance_to(a.pos as Vector2) <= float(a.r) + u.radius * 0.5:
							u.fails += 1
							damage(boss, u, MmoTune.value("meteor_dmg"), "fire", "Meteor", "mech")
							if u.alive:
								add_aura(u, { "id": "burning", "name": "Burning", "src": "boss", "dur": 6.0, "every": 1.0, "dot": 360.0,
									"school": "fire", "debuff": true, "cleanse": true, "glyph": "flame", "col": "#ff6a2a" })
					_emit({ "type": "explode", "pos": a.pos, "r": float(a.r), "what": "meteor" })
				"gather":
					_gather_fire(a)
			_emit({ "type": "area_end", "id": int(a.id) })


## Is `p` inside a live hazard (the bots dodge with this)?
func danger_at(p: Vector2, pad := 0.6) -> bool:
	for a: Dictionary in areas:
		match str(a.kind):
			"line":
				var d := p - (a.pos as Vector2)
				var along := d.dot(a.dir as Vector2)
				if along >= 0.0 and along <= float(a.len) and absf(d.dot((a.dir as Vector2).orthogonal())) <= float(a.w) * 0.5 + pad:
					return true
			"circle":
				if p.distance_to(a.pos as Vector2) <= float(a.r) + pad:
					return true
	return false


func score_of(u: MmoUnit) -> float:
	return u.dmg_done + u.heal_done - 400.0 * u.fails - 1000.0 * u.deaths


func state_hash() -> int:
	var h := hash(time)
	for u: MmoUnit in units:
		h = hash([h, u.id, snappedf(u.hp, 0.01), snappedf(u.pos.x, 0.001), snappedf(u.pos.y, 0.001), u.alive])
	return h
