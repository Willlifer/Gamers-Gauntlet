class_name MmoBot
extends RefCounted
## A raid member played by the computer: the tank holds the Giant at the
## north mark, melee stand behind it, ranged and healers in an arc to the
## south. Mechanics: step out of cracks and meteor circles, run to a spread
## slot with a bomb, run into the ring for Earthshatter, run Cinderbrand off
## when it hurts (healers cleanse it instead). They react after
## MmoTune.bot_react seconds and fumble a mechanic now and then
## (MmoTune.bot_slip), so a human can beat them on the meter.
## Abilities by priority of their `ai` tag (MmoClasses).

const TANK_SPOT := Vector2(0, -9)
const SPREAD_R := 16.5

const PRIO := {
	"tank": ["self_heal", "self_cleanse", "def", "taunt", "tank_cd", "resource", "raid_buff", "debuff", "exec", "dps", "burst", "filler", "filler2"],
	"healer": ["self_heal", "self_cleanse", "def", "emergency", "save", "cleanse", "shield", "big_heal", "heal", "hot", "group_heal", "group_heal_near",
		"rez", "raid_buff", "self_buff", "threat", "mana", "dot", "dps", "filler"],
	"hybrid": ["self_heal", "self_cleanse", "def", "emergency", "save", "heal_fast", "heal", "big_heal", "rez", "cleanse", "raid_buff", "self_buff",
		"burst", "exec", "dps", "dps_aoe"],
	"dps": ["self_heal", "self_cleanse", "def", "threat", "self_shield", "raid_buff", "self_buff", "mana", "burst", "pom", "exec", "snd", "finisher_dot",
		"finisher", "debuff", "dot", "nuke", "dps", "dps_close", "builder_behind", "builder", "filler", "filler2", "dps_aoe", "bandage"],
}

var rng := RandomNumberGenerator.new()
var skill := 1.0
var _seen := {}            # mechanic key -> time first seen (the reaction delay)
var _slip := {}            # mechanic key -> true when this bot fumbles it
var _moving_to := Vector2.INF


func _init(p_seed: int = 1, p_skill := 1.0) -> void:
	rng.seed = p_seed
	skill = p_skill


func think(s: MmoSim, u: MmoUnit) -> Dictionary:
	var o := {}
	if not u.alive or s.winner != "":
		return o
	var b := s.boss
	o["target"] = b.id
	var dest := _where(s, u)
	var need_move := u.pos.distance_to(dest) > 0.8
	if need_move and not u.frozen():
		var d := dest - u.pos
		o["yaw"] = atan2(d.x, d.y)
		o["mv"] = Vector2(0, 1)
		if u.casting() and str(u.cast.get("ab", "")) != "":
			o["stop"] = true
	elif b.alive:
		o["yaw"] = atan2(b.pos.x - u.pos.x, b.pos.y - u.pos.y)
	if not s.pulled and u.role != "tank":
		return o                                  # let the tank open
	if u.casting():
		return o
	_moving_to = dest if need_move else Vector2.INF
	var pick := _choose(s, u, need_move)
	if not pick.is_empty():
		o["cast"] = str(pick.ab)
		if pick.has("target"):
			o["target"] = str(pick.target)
			var t := s.unit(str(pick.target))
			if t and t != u and not need_move:
				o["yaw"] = atan2(t.pos.x - u.pos.x, t.pos.y - u.pos.y) if s.is_enemy(u, t) else o.get("yaw", u.yaw)
	if MmoClasses.CLASSES[u.cls].auto.has("dmg"):
		o["auto"] = true
	return o


# ---------------------------------------------------------------- position

func _where(s: MmoSim, u: MmoUnit) -> Vector2:
	var b := s.boss
	var idx := s.players().find(u)
	# a bomb on me: my spread slot
	if u.has_aura("bomb") and _react(s, "bomb%d" % int(s.time / 20.0)):
		if not s.scorch.is_empty():
			# Scorched Earth (G37): fan the bombs across the safe half instead of the whole circle
			# two rings (inner 12.5 m, outer 21 m), half the raid on each: slots 7.5 m+ apart, clear of a 6 m bomb
			var per := maxi(1, (s.players().size() + 1) / 2)
			var slot := idx / 2
			var fa := float(s.scorch.ang) + float(s.scorch.get("dir", 1.0)) * (PI * 0.5 + 0.3 + (float(slot) + (0.5 if idx % 2 else 0.0)) * (PI * 0.8 / float(per)))
			var rr := 21.0 if idx % 2 == 0 else 12.5
			return (b.pos + Vector2(cos(fa), sin(fa)) * rr).limit_length(MmoSim.ARENA_R - 1.5)
		var a := TAU * idx / float(s.players().size()) + 0.4
		return Vector2(sin(a), cos(a)) * SPREAD_R
	# the ring: get in
	for ar: Dictionary in s.areas:
		if str(ar.kind) == "ring" and _react(s, "ring%d" % int(ar.id)):
			var a := TAU * idx / 6.0
			return (ar.pos as Vector2) + Vector2(sin(a), cos(a)) * minf(1.6, float(ar.r) * 0.4)
	var home := _home(s, u, idx)
	# Scorched Earth (G37): stand just behind the fire's trailing edge and walk with it as it turns
	if not s.scorch.is_empty() and (s.scorch.state == "live" or s.time - s.pull_time >= MmoTune.value("scorch_at") - 3.0) 			and _react(s, "scorch%d" % int(s.time / 6.0)):
		home = _scorch_home(s, u, idx)
	# hazards: if home or here is in one, find the nearest safe spot
	if s.danger_at(u.pos) and _react(s, "haz%d" % int(s.time * 2.0)):
		return _safe(s, u.pos, home)
	if s.danger_at(home, 0.8):
		return _safe(s, home, home)
	# Cinderbrand (G30): low and still branded, a non-healer runs it off in a
	# small circle around its spot (the healers keep healing and cleansing)
	if u.role != "tank" and u.role != "healer" and u.has_aura(MmoSim.BRAND) and u.hp_pct() < MmoTune.value("bot_run_off") 			and _react(s, "brand%d" % int(s.next_brand_at)):
		var w := s.time * 2.2 + idx
		return (home + Vector2(sin(w), cos(w)) * 3.0).limit_length(MmoSim.ARENA_R - 1.5)
	return home


func _home(s: MmoSim, u: MmoUnit, idx: int) -> Vector2:
	var b := s.boss
	if not s.pulled and u.role != "tank":
		return u.pos if u.pos.distance_to(b.pos) > MmoSim.PULL_R + 2.0 else b.pos + (u.pos - b.pos).normalized() * (MmoSim.PULL_R + 3.0)
	var tank := _tank(s)
	var away := (b.pos - (tank.pos if tank and tank != u else TANK_SPOT)).normalized()
	if away.length() < 0.1:
		away = Vector2(0, 1)
	match u.role:
		"tank":
			if not s.pulled:
				return b.pos + (u.pos - b.pos).normalized() * (b.radius + 2.0)
			var to := TANK_SPOT
			if b.target != u.id or b.pos.distance_to(TANK_SPOT) > 6.0:
				to = b.pos + (TANK_SPOT - b.pos).normalized() * (b.radius + 1.8)
			return to
	var melee: bool = float(MmoClasses.CLASSES[u.cls].auto.get("range", 0.0)) <= MmoClasses.MELEE and MmoClasses.CLASSES[u.cls].auto.has("dmg")
	if melee:
		var side := 0.55 if idx % 2 == 0 else -0.55
		var dir := away.rotated(side)
		return b.pos + dir * (b.radius + 2.0)
	var arc := [-0.75, 0.0, 0.75, -0.4, 0.4]
	var a := float(arc[idx % arc.size()])
	return (b.pos + away.rotated(a) * 13.0).limit_length(MmoSim.ARENA_R - 2.0)


func _scorch_home(s: MmoSim, u: MmoUnit, idx: int) -> Vector2:
	var b := s.boss
	var melee: bool = float(MmoClasses.CLASSES[u.cls].auto.get("range", 0.0)) <= MmoClasses.MELEE and MmoClasses.CLASSES[u.cls].auto.has("dmg")
	var r := b.radius + 1.8 if u.role == "tank" else (b.radius + 2.0 if melee else 8.5)
	var a := float(s.scorch.ang) + float(s.scorch.get("dir", 1.0)) * (PI * 0.5 + 0.6 + float(idx % 3) * 0.32)
	return (b.pos + Vector2(cos(a), sin(a)) * r).limit_length(MmoSim.ARENA_R - 1.5)


func _tank(s: MmoSim) -> MmoUnit:
	for p: MmoUnit in s.living():
		if p.role == "tank":
			return p
	return null


func _safe(s: MmoSim, from: Vector2, prefer: Vector2) -> Vector2:
	var best := from
	var bd := INF
	for ring: float in [3.5, 6.0, 9.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p := (from + Vector2(sin(a), cos(a)) * float(ring)).limit_length(MmoSim.ARENA_R - 1.5)
			if s.danger_at(p, 1.0):
				continue
			var score := p.distance_to(from) + 0.3 * p.distance_to(prefer)
			if score < bd:
				bd = score
				best = p
		if bd < INF:
			break
	return best


## True once this bot has noticed the mechanic (after its reaction time),
## unless it fumbles this one.
func _react(s: MmoSim, key: String) -> bool:
	if not _seen.has(key):
		_seen[key] = s.time + MmoTune.value("bot_react") * rng.randf_range(0.6, 1.4) / skill
		_slip[key] = rng.randf() < MmoTune.value("bot_slip") / skill
	if _slip[key]:
		return s.time >= float(_seen[key]) + 2.5        # a fumble: late
	return s.time >= float(_seen[key])


# --------------------------------------------------------------- abilities

func _choose(s: MmoSim, u: MmoUnit, moving: bool) -> Dictionary:
	var c: Dictionary = MmoClasses.CLASSES[u.cls]
	var prio: Array = PRIO.get(u.role, PRIO.dps)
	for tag: String in prio:
		for ab: Dictionary in c.abilities:
			if str(ab.get("ai", "")) != tag:
				continue
			if not _ready(s, u, ab, moving):
				continue
			var t := _want(s, u, ab, tag)
			if t.is_empty():
				continue
			return t
	return {}


func _ready(s: MmoSim, u: MmoUnit, ab: Dictionary, moving: bool) -> bool:
	if float(u.cd.get(str(ab.id), 0.0)) > 0.0:
		return false
	if bool(ab.get("gcd", true)) and u.gcd > 0.0:
		return false
	if u.res < float(ab.get("cost", 0.0)):
		return false
	if moving and (float(ab.get("cast", 0.0)) > 0.0 or float(ab.get("channel", 0.0)) > 0.0) and not u.flags.get("instant_next", false):
		return false
	return true


func _want(s: MmoSim, u: MmoUnit, ab: Dictionary, tag: String) -> Dictionary:
	var b := s.boss
	var go := { "ab": str(ab.id) }
	var r := float(ab.get("range", 0.0))
	var kind := str(ab.get("tgt", "none"))
	if kind == "enemy":
		if not b.alive or s.dist(u, b) > r:
			return {}
		if _moving_to != Vector2.INF and (_moving_to - u.pos).normalized().dot((b.pos - u.pos).normalized()) < 0.1:
			return {}                                 # running away from it: can't face it
		if ab.get("behind", false) and not s.behind(u, b):
			return {}
		if ab.get("exec", false) and b.hp_pct() > 0.2:
			return {}
		go["target"] = b.id
	for f: Dictionary in ab.fx:                        # G41: never dash into fire, bombs or circles
		if f.has("dash"):
			var land := s.dash_to(u, f, b if kind == "enemy" else null)
			if s.danger_at(land, 1.0) or s.in_scorch(land, 2.0, 3.0):
				return {}
	var fight := s.pulled and s.time - s.pull_time > 1.0
	match tag:
		"def":
			return go if u.hp_pct() < 0.35 and fight else {}
		"self_heal":
			return go if u.hp_pct() < 0.5 and fight else {}
		"self_cleanse":
			for a: Dictionary in u.auras:
				if a.get("cleanse", false) and str(a.get("src", "")) == "boss":
					return go
			return {}
		"taunt":
			return go if b.target != u.id and fight else {}
		"tank_cd":
			return go if b.target == u.id and fight else {}
		"resource":
			return go if u.res < 30.0 and fight else {}
		"raid_buff":
			var aid := _buff_id(ab)
			for p: MmoUnit in s.living():
				if not p.has_aura(aid):
					return go
			return {}
		"self_buff", "self_shield":
			return go if not u.has_aura(_buff_id(ab)) else {}
		"debuff":
			var aid := _buff_id(ab)
			var a := b.aura(aid)
			return go if fight and (a.is_empty() or float(a.t) < 3.0) else {}
		"dot":
			var a := b.aura("%s_%s" % [str(ab.id), u.id])
			return go if fight and (a.is_empty() or float(a.t) < 2.0) else {}
		"burst", "pom":
			return go if fight and s.time - s.pull_time > 6.0 else {}
		"mana":
			return go if u.res_kind == "mana" and u.res < u.res_max * 0.25 else {}
		"exec", "nuke", "dps", "filler", "filler2", "dps_close":
			return go if fight or u.role == "tank" else {}
		"dps_aoe":
			return go if fight and rng.randf() < 0.15 else {}
		"builder_behind":
			return go if u.cp < 5 else {}
		"builder":
			return go if u.cp < 5 and not s.behind(u, b) else {}      # behind it: save up for Backstab
		"snd":
			return go if u.cp >= 2 and not u.has_aura("slice_dice") else {}
		"finisher_dot":
			var a := b.aura("%s_%s" % [str(ab.id), u.id])
			return go if u.cp >= 4 and a.is_empty() else {}
		"finisher":
			return go if u.cp >= 5 or (u.cp >= 3 and b.hp_pct() < 0.1) else {}
		"threat":
			if not fight:
				return {}
			var top := 0.0
			for k: String in b.threat:
				top = maxf(top, float(b.threat[k]))
			return go if b.target == u.id and u.role != "tank" or float(b.threat.get(u.id, 0.0)) > top * 0.9 and u.role != "tank" else {}
		"bandage":
			return go if u.hp_pct() < 0.5 and not u.has_aura("bomb") else {}
		"emergency":
			return _ally(s, u, ab, go, 0.18)
		"save":
			return _ally(s, u, ab, go, 0.15, true)
		"big_heal":
			return _ally(s, u, ab, go, 0.55 if u.role == "healer" else 0.35)
		"heal", "heal_fast":
			return _ally(s, u, ab, go, 0.8 if u.role == "healer" else 0.45)
		"hot":
			return _ally(s, u, ab, go, 0.95, false, "%s_%s" % [str(ab.id), u.id])
		"shield":
			return _ally(s, u, ab, go, 0.9, false, "weakened_soul", true)
		"group_heal":
			var hurt := 0
			for p: MmoUnit in s.living():
				if p.hp_pct() < 0.7 and p.pos.distance_to(u.pos) < 40.0:
					hurt += 1
			return go if hurt >= 3 else {}
		"group_heal_near":
			var hurt := 0
			for p: MmoUnit in s.living():
				if p.hp_pct() < 0.8 and p.pos.distance_to(u.pos) < 9.0:
					hurt += 1
			return go if hurt >= 2 else {}
		"cleanse":
			for p: MmoUnit in s.living():
				if p.pos.distance_to(u.pos) <= r:
					for a: Dictionary in p.auras:
						if a.get("cleanse", false):
							go["target"] = p.id
							return go
			return {}
		"rez":
			for p: MmoUnit in s.players():
				if not p.alive and p.pos.distance_to(u.pos) <= r and not _being_rezzed(s, p):
					for q: MmoUnit in s.living():
						if q.hp_pct() < 0.5:
							return {}
					go["target"] = p.id
					return go
			return {}
	return {}


func _buff_id(ab: Dictionary) -> String:
	for f: Dictionary in ab.fx:
		if f.has("buff") or f.has("debuff"):
			return str(f.get("id", ab.id))
	return str(ab.id)


## The neediest ally under `below` of their health (tank first among equals).
func _ally(s: MmoSim, u: MmoUnit, ab: Dictionary, go: Dictionary, below: float, not_self := false, skip_aura := "", tank_first := false) -> Dictionary:
	var best: MmoUnit = null
	var bv := below
	for p: MmoUnit in s.living():
		if not_self and p == u:
			continue
		if p.pos.distance_to(u.pos) > float(ab.get("range", MmoClasses.HEAL_R)):
			continue
		if skip_aura != "" and p.has_aura(skip_aura):
			continue
		var v := p.hp_pct()
		if tank_first and p.role == "tank" and s.boss.target == p.id:
			v -= 0.3
		if v < bv:
			bv = v
			best = p
	if best == null:
		return {}
	go["target"] = best.id
	return go


func _being_rezzed(s: MmoSim, p: MmoUnit) -> bool:
	for q: MmoUnit in s.living():
		if q.casting() and str(q.cast.target) == p.id:
			return true
	return false
