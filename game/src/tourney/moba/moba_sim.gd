class_name MobaSim
extends RefCounted
## The MOBA duel as pure state on a fixed 30 Hz tick: champions, minion
## waves, autos with a wind-up, projectiles, ground areas, damage over time,
## summoner spells. No nodes. Same seed + same orders = same match, so it
## can run lockstep online later. MobaView draws it; MobaBot and the player
## feed it orders.
##
## Orders per champion per tick (all optional):
##   { move: Vector2, attack: unit id, stop: true,
##     cast: { slot: "q"|"w"|"e"|"r"|"flash"|"ignite"|"smite", aim: Vector2, target: unit id },
##     ping: { kind: "go"|"hold", at: Vector2 } }       (the pit: your bot allies answer it)

const TICK := 1.0 / 30.0
const KILLS_TO_WIN := 3
const RESPAWN := 6.0
const HALF_LEN := 21.0          # the lane runs x −21..21 (4200 League units)
const HALF_W := 5.0             # and z −5..5 (1000)
const SPAWN_X := 19.0
const WAVE_EVERY := 25.0
const FIRST_WAVE := 3.0
const AGGRO := 7.0              # minions look this far for something to hit
const ACQUIRE := 1.5            # an idle champion auto-acquires within range + this
const SMOKE_SIGHT := 2.5
const FLASH_RANGE := 5.25       # author 10-16: 525 League units
const FLASH_CD := 60.0          # League 300 s; scaled for a 3-kill duel
const IGNITE_RANGE := 7.5       # 600 x1.25 (G54: every range +25%)
const IGNITE_CD := 60.0
const IGNITE_DMG := 120.0       # true damage over 5 s
## "Objective take": the boss pit (author 10-13: champions on 2 teams dance
## around a boss; whoever lands the kill takes it, smite in hand)
const PIT_R := 10.5             # the pit's walkable radius
const BOSS_R := 1.8
const BOSS_HP := 27000.0
const BOSS_LEASH := 7.0         # come this close and it turns on you
const BOSS_AD := 32.5           # author 10-16: the Giant's damage down 75% (was 130 / 220 / 160)
const SLAM_EVERY := 8.0
const SLAM_DMG := 55.0
const NOVA_EVERY := 12.0
const NOVA_DMG := 40.0
const SMITE_DMG := 600.0        # true damage, the boss only
const SMITE_RANGE := 6.25       # 500 x1.25
## G54: the Giant sits off centre, in the east half toward the wall (as far
## from both entrances), and rocks stand in the pit: nobody walks through
## them, skillshots break on them, and nobody sees (or auto-acquires) past them.
const BOSS_POS := Vector2(5.5, 0.0)
const PIT_ROCKS := [Vector3(-4.5, 0.0, 1.3), Vector3(0.0, 4.6, 0.9), Vector3(0.0, -4.6, 0.9),
	Vector3(-6.0, 4.6, 1.0), Vector3(-6.0, -4.6, 1.0), Vector3(6.2, 5.4, 0.8), Vector3(6.2, -5.4, 0.8)]
const PLAYER_POWER := 2.0       # the players' champions in the pit: 2x health and damage
const PING_TIME := 12.0         # a ping holds the bots this long
const SMITE_CD := 15.0
const RESPAWN_PIT := 8.0

var mode := "duel"              # "duel" | "pit" (the boss) | "practice" (a dummy, no waves, no win)
var rng := RandomNumberGenerator.new()
var time := 0.0
var units: Array = []           # MobaUnit
var projectiles: Array = []     # Dictionary
var areas: Array = []           # Dictionary: delayed blasts, smoke, mines
var score := { "blue": 0, "red": 0 }
var winner := ""
var pings := {}                 # team -> { kind: "go"|"hold", pos, time, by }
var _events: Array = []
var _next := 1
var _wave_t := FIRST_WAVE


func _init(p_seed: int = 1, p_mode: String = "duel") -> void:
	rng.seed = p_seed
	mode = p_mode
	if mode != "duel":
		_wave_t = INF


# ------------------------------------------------------------------ setup

func add_champ(champ_id: String, team: String, name: String) -> MobaUnit:
	var u := MobaChamps.make(champ_id)
	var slot := units.filter(func(o): return o.kind == "champ" and o.team == team).size()
	u.id = "%s_%s" % [team, champ_id] if unit("%s_%s" % [team, champ_id]) == null else "%s_%s_%d" % [team, champ_id, slot]
	u.team = team
	u.name = name
	u.set_meta("slot", slot)
	u.pos = spawn_of(team, slot)
	u.facing = Vector2.RIGHT if team == "blue" else Vector2.LEFT
	if mode == "pit":
		u.facing = Vector2.UP if team == "blue" else Vector2.DOWN
	u.cd = { "q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0, "flash": 0.0, ("smite" if mode == "pit" else "ignite"): 0.0 }
	units.append(u)
	return u


func add_dummy(at: Vector2) -> MobaUnit:
	var u := MobaUnit.new()
	u.id = "dummy%d" % _next
	_next += 1
	u.team = "red"
	u.kind = "dummy"
	u.name = "Dummy"
	u.pos = at
	u.max_hp = 2000.0
	u.hp = u.max_hp
	u.ms = 0.0
	u.range = 0.0
	units.append(u)
	return u


func spawn_of(team: String, slot: int = 0) -> Vector2:
	if mode == "pit":
		var side := 1.0 if team == "blue" else -1.0
		return Vector2((slot - 1) * 2.2, side * (PIT_R - 1.2))
	return Vector2(-SPAWN_X if team == "blue" else SPAWN_X, 0.0)


## The pit's boss: stationary, hits whoever comes closest.
func add_boss() -> MobaUnit:
	var u := MobaUnit.new()
	u.id = "boss"
	u.team = "neutral"
	u.kind = "boss"
	u.name = "The Giant"
	u.pos = BOSS_POS
	u.radius = BOSS_R
	u.max_hp = BOSS_HP
	u.hp = BOSS_HP
	u.ms = 0.0
	u.ad = BOSS_AD
	u.period = 1.6
	u.range = BOSS_LEASH + BOSS_R
	u.windup = 0.45
	u.proj_speed = 14.0
	u.facing = Vector2.DOWN
	u.set_meta("slam_t", SLAM_EVERY * 0.6)
	u.set_meta("nova_t", NOVA_EVERY * 0.75)
	units.append(u)
	return u


func boss() -> MobaUnit:
	return unit("boss")


## The pit's seats (G54): a player's champion gets 2x health and damage and
## smite; a bot ally or a bot enemy gets neither.
func seat_pit(u: MobaUnit, is_player: bool) -> void:
	u.player = is_player
	if is_player:
		u.power = PLAYER_POWER
		u.max_hp *= PLAYER_POWER
		u.hp = u.max_hp
	else:
		u.cd.erase("smite")


func unit(id: String) -> MobaUnit:
	for u in units:
		if u.id == id:
			return u
	return null


## Champions of `team` (alive or not).
func champs_of(team: String) -> Array:
	return units.filter(func(o): return o.kind == "champ" and o.team == team)


func champ_of(team: String) -> MobaUnit:
	for u in units:
		if u.kind == "champ" and u.team == team:
			return u
	return null


func enemies_of(u: MobaUnit) -> Array:
	return units.filter(func(o): return o.team != u.team and o.alive)


# ------------------------------------------------------------------- tick

func step(orders: Dictionary) -> Array:
	_events = []
	if winner != "":
		return _events
	time += TICK
	_waves()
	var order := units.duplicate()
	if mode == "pit" and int(round(time / TICK)) % 2 == 0:
		order.reverse()          # G54: neither side always acts first (a same-tick smite race went to blue)
	for u in order:
		_tick_unit(u, orders.get(u.id, {}))
	_tick_projectiles()
	_tick_areas()
	units = units.filter(func(u): return u.alive or u.kind == "champ")
	return _events


func _waves() -> void:
	if mode != "duel":
		return
	_wave_t -= TICK
	if _wave_t > 0.0:
		return
	_wave_t = WAVE_EVERY
	for team in ["blue", "red"]:
		var x := -SPAWN_X + 1.5 if team == "blue" else SPAWN_X - 1.5
		for i in 3:
			var m := MobaUnit.new()
			m.id = "m%d" % _next
			_next += 1
			m.team = team
			m.kind = "minion"
			m.role = "caster" if i == 2 else "melee"
			m.name = "Caster" if i == 2 else "Melee"
			m.radius = 0.45
			m.lane_dir = 1.0 if team == "blue" else -1.0
			m.pos = Vector2(x - m.lane_dir * (2.2 if i == 2 else 0.0), -1.2 + 2.4 * (i % 2) if i < 2 else 0.0)
			if m.role == "melee":
				m.max_hp = 300.0
				m.ad = 12.0
				m.period = 1.25
				m.range = 1.1
				m.proj_speed = 0.0
				m.windup = 0.25
			else:
				m.max_hp = 220.0
				m.ad = 20.0
				m.period = 1.6
				m.range = 6.25          # x1.25 with everything else
				m.proj_speed = 14.0
				m.windup = 0.35
			m.ms = 3.25
			m.hp = m.max_hp
			units.append(m)
	_emit({ "type": "wave" })


func _tick_unit(u: MobaUnit, ord: Dictionary) -> void:
	if ord.has("ping") and u.kind == "champ" and mode == "pit":
		var pg: Dictionary = ord.ping
		var kind := "hold" if str(pg.get("kind", "")) == "hold" else "go"
		pings[u.team] = { "kind": kind, "pos": _clamp(pg.get("at", u.pos)), "time": time, "by": u.id }
		_emit({ "type": "ping", "team": u.team, "kind": kind, "unit": u.id })
	for k in u.cd:
		u.cd[k] = maxf(0.0, float(u.cd[k]) - TICK)
	u.atk_cd = maxf(0.0, u.atk_cd - TICK)
	u.blind_t = maxf(0.0, u.blind_t - TICK)
	u.buffs = u.buffs.filter(func(b): b.t -= TICK; return b.t > 0.0)
	if not u.alive:
		if u.kind == "champ":
			u.respawn_t -= TICK
			if u.respawn_t <= 0.0:
				u.alive = true
				u.hp = u.max_hp
				u.pos = spawn_of(u.team, int(u.get_meta("slot", 0)))
				u.dots = []
				u.order = { "kind": "idle" }
				_emit({ "type": "respawn", "unit": u.id })
		return
	_tick_dots(u)
	if not u.alive:
		return
	if u.kind == "dummy":
		if u.hp < u.max_hp and time - float(u.get_meta("hurt_at", -10.0)) > 4.0:
			u.hp = u.max_hp
		return
	if u.kind == "boss":
		_boss_brain(u)
		_act(u)
		return
	# orders
	if ord.get("stop", false):
		u.order = { "kind": "idle" }
		u.atk_wind = -1.0
	if ord.has("move"):
		u.order = { "kind": "move", "to": _clamp(ord.move) }
		u.atk_wind = -1.0
	if ord.has("attack") and str(ord.attack) != "":
		var t := unit(str(ord.attack))
		if t and t.team != u.team and t.targetable():
			u.order = { "kind": "attack", "target": t.id }
	if ord.has("cast"):
		_cast(u, ord.cast)
	# the cast stop: rooted until the spell goes off, then the order resumes
	if u.cast_slot != "":
		if time >= u.cast_until - 0.0001:
			_release(u)
		if u.cast_slot != "" or u.dash_t <= 0.0:
			_moved(u, false)
			return
	# a dash carries them
	if u.dash_t > 0.0:
		u.pos = _clamp(u.pos + u.dash_v * TICK)
		u.dash_t -= TICK
		_moved(u, true)
		return
	if u.kind == "minion":
		_minion_brain(u)
	elif u.order.kind == "idle":
		var near := _nearest_enemy(u, u.range + ACQUIRE)
		if near:
			u.order = { "kind": "attack", "target": near.id, "auto": true }
	_act(u)


## Walk toward the order or wind up and fire an auto.
func _act(u: MobaUnit) -> void:
	var moved := false
	match str(u.order.kind):
		"move":
			moved = _walk(u, u.order.to)
			if not moved:
				u.order = { "kind": "idle" }
		"attack":
			var t := unit(str(u.order.target))
			if t == null or not t.targetable() or (u.blind_t > 0.0 and t.pos.distance_to(u.pos) > SMOKE_SIGHT):
				u.order = { "kind": "idle" }
				u.atk_wind = -1.0
			elif u.pos.distance_to(t.pos) > u.range + t.radius + u.radius * 0.5:
				if u.order.get("auto", false) and u.pos.distance_to(t.pos) > u.range + ACQUIRE + 1.0:
					u.order = { "kind": "idle" }
				else:
					u.atk_wind = -1.0
					moved = _walk(u, t.pos)
			else:
				u.facing = (t.pos - u.pos).normalized()
				if u.atk_wind >= 0.0:
					u.atk_wind += TICK
					if u.atk_wind >= u.windup:
						u.atk_wind = -1.0
						_fire_auto(u, t)
				elif u.atk_cd <= 0.0:
					u.atk_wind = 0.0
					u.atk_target = t.id
					u.atk_cd = u.period
					_emit({ "type": "windup", "unit": u.id, "target": t.id })
	_moved(u, moved)


func _moved(u: MobaUnit, moved: bool) -> void:
	u.moving = moved
	if moved:
		u.still_t = 0.0
		if u.stealth:
			u.stealth = false
			_emit({ "type": "reveal", "unit": u.id })
	else:
		u.still_t += TICK
		if u.champ == "temu" and not u.stealth and u.still_t >= MobaChamps.TEMU_STILL:
			u.stealth = true
			_emit({ "type": "stealth", "unit": u.id })
			for o in units:          # nobody can keep targeting what they can't see
				if o.order.get("target", "") == u.id:
					o.order = { "kind": "idle" }
					o.atk_wind = -1.0


func _walk(u: MobaUnit, to: Vector2) -> bool:
	var d := to - u.pos
	if d.length() < 0.05:
		return false
	var step := minf(d.length(), u.ms_now() * TICK)
	u.facing = d.normalized()
	var np := _clamp(u.pos + d.normalized() * step)
	if mode == "pit" and np.distance_to(u.pos) < step * 0.4:
		# walked into a rock or the Giant's dais: slide round it the short way
		for c in _blockers():
			var cc := Vector2(c.x, c.y)
			if u.pos.distance_to(cc) <= c.z + 0.75:
				var tan := (u.pos - cc).orthogonal().normalized()
				if tan.dot(d) < 0.0 or (is_zero_approx(tan.dot(d)) and u.team == "red"):
					tan = -tan
				np = _clamp(u.pos + tan * step)
				break
	u.pos = np
	return true


## The pit's solid things: the rocks and the Giant's dais, as (x, y, radius + a body).
func _blockers() -> Array:
	var out: Array = []
	for r in PIT_ROCKS:
		out.append(Vector3(r.x, r.y, r.z + 0.6))
	out.append(Vector3(BOSS_POS.x, BOSS_POS.y, BOSS_R + 0.5))
	return out


func _clamp(p: Vector2) -> Vector2:
	if mode == "pit":
		if p.length() > PIT_R:
			p = p.normalized() * PIT_R
		for c in _blockers():
			var cc := Vector2(c.x, c.y)
			var d := p - cc
			if d.length() < c.z:
				p = cc + (d.normalized() if d.length() > 0.01 else Vector2.DOWN) * c.z
		return p
	return Vector2(clampf(p.x, -HALF_LEN, HALF_LEN), clampf(p.y, -HALF_W, HALF_W))


## True when no pit rock stands between `a` and `b` (always outside the pit).
func los(a: Vector2, b: Vector2) -> bool:
	if mode != "pit":
		return true
	for r in PIT_ROCKS:
		var c := Vector2(r.x, r.y)
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_to(c) < r.z * 0.85:
			return false
	return true


## Whether `u` (or its team) can see `o`: not hidden, not past a rock for
## every one of u's team, and not lost in Braves' smoke.
func team_sees(team: String, o: MobaUnit) -> bool:
	if not o.targetable():
		return false
	if o.team == team:
		return true
	for a in units:
		if a.team == team and a.alive and a.kind != "boss" and (a.blind_t <= 0.0 or a.pos.distance_to(o.pos) <= SMOKE_SIGHT):
			if a.pos.distance_to(o.pos) <= 2.0 or los(a.pos, o.pos):
				return true
	return false


## The boss: turns on the nearest champion inside its leash; every few
## seconds a telegraphed slam (a cone at its target) or a nova (a ring round it).
func _boss_brain(b: MobaUnit) -> void:
	var t: MobaUnit = null
	var bd := BOSS_LEASH
	for o in units:
		if o.kind == "champ" and o.alive and not o.stealth:
			var d: float = o.pos.distance_to(b.pos) - o.radius - b.radius
			if d <= bd:
				t = o
				bd = d
	if t == null:
		b.order = { "kind": "idle" }
		b.atk_wind = -1.0
		if b.hp < b.max_hp and time - float(b.get_meta("hurt_at", -10.0)) > 6.0:
			b.hp = minf(b.max_hp, b.hp + b.max_hp * 0.02 * TICK)     # left alone, it knits back
		return
	if str(b.order.get("target", "")) != t.id:
		b.order = { "kind": "attack", "target": t.id }
	b.set_meta("slam_t", float(b.get_meta("slam_t")) - TICK)
	b.set_meta("nova_t", float(b.get_meta("nova_t")) - TICK)
	if float(b.get_meta("slam_t")) <= 0.0:
		b.set_meta("slam_t", SLAM_EVERY)
		var dir := (t.pos - b.pos).normalized()
		var at := b.pos
		add_area({ "kind": "blast", "pos": at, "r": 6.5, "cone": dir, "cone_deg": 100.0, "delay": 1.1, "team": "neutral",
			"owner": b.id, "look": "boss_slam",
			"on_fire": func() -> void: cone_hit(at, dir, 6.5, 100.0, b, SLAM_DMG, "slam") })
		b.cast_serial += 1
	elif float(b.get_meta("nova_t")) <= 0.0:
		b.set_meta("nova_t", NOVA_EVERY)
		var at := b.pos
		add_area({ "kind": "blast", "pos": at, "r": 4.5, "delay": 1.3, "team": "neutral", "owner": b.id, "look": "boss_nova",
			"on_fire": func() -> void: area_hit(at, 4.5, b, NOVA_DMG, "nova", false) })
		b.cast_serial += 1


## Everything of another team inside a cone from `at` toward `dir`.
func cone_hit(at: Vector2, dir: Vector2, r: float, deg: float, src: MobaUnit, amount: float, kind: String) -> Array:
	var out: Array = []
	for o in units:
		if o.team == src.team or not o.alive:
			continue
		var d: Vector2 = o.pos - at
		if d.length() <= r + o.radius and (d.length() < 0.5 or rad_to_deg(absf(d.angle_to(dir))) <= deg * 0.5):
			out.append(o)
	for o in out:
		damage(o, amount, src, kind)
	return out


func _nearest_enemy(u: MobaUnit, r: float, kinds: Array = ["champ", "minion", "dummy"]) -> MobaUnit:
	var best: MobaUnit = null
	var bd := INF
	for o in units:
		if o.team == u.team or not o.targetable() or not o.kind in kinds:
			continue
		if u.blind_t > 0.0 and o.pos.distance_to(u.pos) > SMOKE_SIGHT:
			continue
		if not los(u.pos, o.pos):
			continue
		var d: float = o.pos.distance_to(u.pos)
		if d <= r and d < bd:
			best = o
			bd = d
	return best


## Minions: hit the nearest enemy minion, else the champion, else walk the lane.
func _minion_brain(m: MobaUnit) -> void:
	var cur := unit(str(m.order.get("target", "")))
	if cur and cur.targetable() and cur.kind == "minion":
		return
	var t := _nearest_enemy(m, AGGRO, ["minion"])
	if t == null:
		t = _nearest_enemy(m, AGGRO, ["champ", "dummy"])
	if t:
		m.order = { "kind": "attack", "target": t.id }
	else:
		var end := Vector2(m.lane_dir * (HALF_LEN - 0.5), m.pos.y)
		if m.pos.distance_to(end) < 0.6:
			m.alive = false          # reached the far end: off the board
			return
		m.order = { "kind": "move", "to": end }


func _fire_auto(u: MobaUnit, t: MobaUnit) -> void:
	u.atk_serial += 1
	_emit({ "type": "auto", "unit": u.id, "target": t.id })
	if u.proj_speed <= 0.0:
		_auto_hit(u, t)
		return
	projectiles.append({ "id": _next, "kind": "auto", "owner": u.id, "team": u.team, "pos": u.pos + u.facing * 0.5,
		"target": t.id, "speed": u.proj_speed, "champ": u.champ })
	_next += 1


func _auto_hit(u: MobaUnit, t: MobaUnit) -> void:
	damage(t, u.ad, u, "auto")
	if u.champ == "temu":
		dot(t, "poison", MobaChamps.TEMU_POISON, 3.0, u)      # E: Toxic, on every auto


# ------------------------------------------------------------- damage

func damage(t: MobaUnit, amount: float, src: MobaUnit, kind: String) -> void:
	if t == null or not t.alive or amount <= 0.0:
		return
	if src and kind != "smite":
		amount *= src.power
	t.hp -= amount
	t.hit_serial += 1
	t.set_meta("hurt_at", time)
	t.set_meta("last_kind", kind)
	if src:
		src.dmg_done += amount
	_emit({ "type": "hit", "unit": t.id, "amount": amount, "kind": kind, "src": src.id if src else "" })
	if t.hp <= 0.0:
		_die(t, src)


## Damage over time; the same kind from the same source refreshes, not stacks.
func dot(t: MobaUnit, kind: String, total: float, dur: float, src: MobaUnit) -> void:
	if t == null or not t.alive:
		return
	if src:
		total *= src.power
	for d in t.dots:
		if d.kind == kind and d.src == (src.id if src else ""):
			d.per_s = total / dur
			d.t = dur
			return
	t.dots.append({ "kind": kind, "per_s": total / dur, "t": dur, "src": src.id if src else "" })


func _tick_dots(u: MobaUnit) -> void:
	var keep: Array = []
	for d in u.dots:
		d.t -= TICK
		var src := unit(str(d.src))
		u.hp -= float(d.per_s) * TICK
		if src:
			src.dmg_done += float(d.per_s) * TICK
		if u.hp <= 0.0:
			_die(u, src)
			return
		if d.t > 0.0:
			keep.append(d)
	u.dots = keep


func _die(t: MobaUnit, src: MobaUnit) -> void:
	if not t.alive:
		return
	t.hp = 0.0
	t.alive = false
	t.dots = []
	t.dash_t = 0.0
	t.atk_wind = -1.0
	t.cast_slot = ""
	_emit({ "type": "death", "unit": t.id, "by": src.id if src else "" })
	for o in units:
		if o.order.get("target", "") == t.id:
			o.order = { "kind": "idle" }
			o.atk_wind = -1.0
	if t.kind == "boss":
		# the objective: whoever lands the last hit takes it for their team
		var team := src.team if src and src.team in ["blue", "red"] else ""
		if team == "":
			team = "blue" if _damage_by("blue") >= _damage_by("red") else "red"
		winner = team
		_emit({ "type": "win", "team": team, "how": str(t.get_meta("last_kind", "")), "by": src.id if src else "" })
		return
	if t.kind != "champ":
		return
	t.respawn_t = RESPAWN_PIT if mode == "pit" else RESPAWN
	t.stealth = false
	if src == null or src.kind != "champ":
		return
	score[src.team] += 1
	src.kills += 1
	if mode == "duel" and score[src.team] >= KILLS_TO_WIN:
		winner = src.team
		_emit({ "type": "win", "team": src.team })


func _damage_by(team: String) -> float:
	var n := 0.0
	for u in units:
		if u.team == team:
			n += u.dmg_done
	return n


func area_hit(at: Vector2, r: float, src: MobaUnit, amount: float, kind: String, spell: bool = true) -> Array:
	var out: Array = []
	for o in units:
		if o.team != src.team and o.alive and o.pos.distance_to(at) <= r + o.radius:
			out.append(o)
	for o in out:
		damage(o, amount, src, kind)
		if spell:
			MobaChamps.on_spell_hit(self, src, o)
	return out


# --------------------------------------------------------------- casting

func _cast(u: MobaUnit, c: Dictionary) -> void:
	var slot := str(c.get("slot", ""))
	if not u.cd.has(slot) or float(u.cd[slot]) > 0.0 or u.dash_t > 0.0 or u.cast_slot != "":
		return
	var aim: Vector2 = c.get("aim", u.pos + u.facing)
	var tgt := unit(str(c.get("target", "")))
	if slot in ["q", "w", "e", "r"] and u.champ != "":
		# the cast stop (author 10-16): stand still CAST_TIME, then it goes off.
		# A targeted spell with nobody in reach never starts.
		var sp := MobaChamps.shape(u.champ, slot)
		if str(sp.get("shape", "")) == "none":
			return
		if str(sp.shape) == "target":
			tgt = MobaChamps.pick_target(self, u, aim, tgt, float(sp.range))
			if tgt == null:
				return
		u.cast_slot = slot
		u.cast_aim = aim
		u.cast_target = tgt.id if tgt else ""
		u.cast_start = time
		u.cast_until = time + MobaChamps.CAST_TIME
		u.cast_serial += 1
		u.last_cast = slot
		u.atk_wind = -1.0
		if aim.distance_to(u.pos) > 0.05:
			u.facing = (aim - u.pos).normalized()
		_emit({ "type": "cast_start", "unit": u.id, "slot": slot, "aim": aim, "until": u.cast_until })
		return
	_go_off(u, slot, aim, tgt)


## The end of the cast stop: the spell goes off now (its target may have died or hidden).
func _release(u: MobaUnit) -> void:
	var slot := u.cast_slot
	u.cast_slot = ""
	var tgt := unit(u.cast_target)
	if tgt and not tgt.targetable():
		tgt = null
	_go_off(u, slot, u.cast_aim, tgt, false)


func _go_off(u: MobaUnit, slot: String, aim: Vector2, tgt: MobaUnit, bump: bool = true) -> void:
	var ok := false
	match slot:
		"flash":
			var d := aim - u.pos
			u.pos = _clamp(u.pos + d.limit_length(MobaTune.value("flash_range")))
			u.cd.flash = FLASH_CD
			ok = true
			_emit({ "type": "flash", "unit": u.id })
		"smite":
			var b := boss()
			if b and b.alive and b.pos.distance_to(u.pos) <= SMITE_RANGE + b.radius:
				u.cd.smite = SMITE_CD
				ok = true
				_emit({ "type": "smite", "unit": u.id })
				damage(b, SMITE_DMG, u, "smite")
		"ignite":
			if tgt and tgt.team != u.team and tgt.targetable() and tgt.pos.distance_to(u.pos) <= IGNITE_RANGE + tgt.radius:
				dot(tgt, "ignite", IGNITE_DMG, 5.0, u)
				u.cd.ignite = IGNITE_CD
				ok = true
				_emit({ "type": "ignite", "unit": u.id, "target": tgt.id })
		_:
			ok = MobaChamps.cast(self, u, slot, aim, tgt)
			if ok:
				u.cd[slot] = float(MobaChamps.CHAMPS[u.champ].cd[slot])
	if ok:
		if bump:
			u.cast_serial += 1
			u.last_cast = slot
		u.atk_wind = -1.0
		_emit({ "type": "cast", "unit": u.id, "slot": slot, "aim": aim })


func dash(u: MobaUnit, dir: Vector2, dist: float, dur: float) -> void:
	u.dash_v = dir.normalized() * dist / dur
	u.dash_t = dur
	u.facing = dir.normalized()
	u.order = { "kind": "idle" }


## A skillshot or homing spell. p: { pos, dir|target, speed, range, width, on_hit: Callable(MobaUnit, pos), on_end: Callable(pos), owner, look }
func shoot(p: Dictionary) -> void:
	p["id"] = _next
	_next += 1
	p["kind"] = p.get("kind", "spell")
	p["left"] = float(p.get("range", 10.0))
	projectiles.append(p)
	_emit({ "type": "shot", "id": p.id, "look": str(p.get("look", "")), "owner": str(p.owner) })


func _tick_projectiles() -> void:
	var keep: Array = []
	for p in projectiles:
		var done := false
		if p.kind == "auto" or p.has("target"):
			var t := unit(str(p.target))
			if t == null or not t.alive:
				done = true
			else:
				var d: Vector2 = t.pos - p.pos
				var step: float = float(p.speed) * TICK
				if d.length() <= step + t.radius * 0.5:
					p.pos = t.pos
					var owner := unit(str(p.owner))
					if p.kind == "auto":
						if owner:
							_auto_hit(owner, t)
					elif p.has("on_hit"):
						(p.on_hit as Callable).call(t, t.pos)
					done = true
				else:
					p.pos += d.normalized() * step
		else:
			var stepv: Vector2 = p.dir * float(p.speed) * TICK
			p.pos += stepv
			p.left -= stepv.length()
			for o in units:
				if o.team == p.team or not o.alive or p.get("hit", {}).has(o.id):
					continue
				if o.pos.distance_to(p.pos) <= o.radius + float(p.get("width", 0.4)):
					if p.has("on_hit"):
						(p.on_hit as Callable).call(o, p.pos)
					if p.get("pierce", false):
						if not p.has("hit"):
							p["hit"] = {}
						p.hit[o.id] = true
					else:
						done = true
						break
			if not done and (p.left <= 0.0 or _in_rock(p.pos) or (mode == "pit" and p.pos.length() > PIT_R + 1.0)
					or (mode != "pit" and (absf(p.pos.x) > HALF_LEN + 1.0 or absf(p.pos.y) > HALF_W + 1.0))):
				if p.has("on_end"):
					(p.on_end as Callable).call(p.pos)
				done = true
		if done:
			_emit({ "type": "shot_end", "id": p.id, "pos": p.pos })
		else:
			keep.append(p)
	projectiles = keep


func _in_rock(p: Vector2) -> bool:
	if mode != "pit":
		return false
	for r in PIT_ROCKS:
		if p.distance_to(Vector2(r.x, r.y)) < r.z:
			return true
	return false


## A ground effect. a: { kind, pos, r, t (life), delay, team, owner, on_fire: Callable, ... }
func add_area(a: Dictionary) -> void:
	a["id"] = _next
	_next += 1
	areas.append(a)
	_emit({ "type": "area", "id": a.id, "kind": str(a.kind) })


func _tick_areas() -> void:
	var keep: Array = []
	for a in areas:
		a.age = float(a.get("age", 0.0)) + TICK
		var gone := false
		match str(a.kind):
			"blast":            # telegraphed, then fires once
				if a.age >= float(a.delay):
					(a.on_fire as Callable).call()
					gone = true
			"smoke":            # Braves' W: blinds who stands in it
				for o in units:
					if o.team != a.team and o.alive and o.pos.distance_to(a.pos) <= float(a.r) + o.radius:
						o.blind_t = maxf(o.blind_t, 0.3)
				gone = a.age >= float(a.t)
			"mine":             # Temu's R: arms, then waits for an enemy
				if a.age >= float(a.arm):
					for o in units:
						if o.team != a.team and o.alive and o.pos.distance_to(a.pos) <= float(a.trigger) + o.radius:
							(a.on_fire as Callable).call()
							gone = true
							break
				gone = gone or a.age >= float(a.t)
		if gone:
			_emit({ "type": "area_end", "id": a.id, "kind": str(a.kind), "pos": a.pos })
		else:
			keep.append(a)
	areas = keep


func _emit(e: Dictionary) -> void:
	e["time"] = time
	_events.append(e)


## For tests and the desync check later: a fingerprint of the state.
func state_hash() -> int:
	var s := "%.3f|" % time
	for u in units:
		s += "%s:%.2f,%.2f,%.1f|" % [u.id, u.pos.x, u.pos.y, u.hp]
	return hash(s)
