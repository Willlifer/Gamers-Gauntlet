class_name MobaBot
extends RefCounted
## A computer champion: reads the sim and returns orders, like a player.
## Re-decides every so often, aims with some error, steps out of telegraphs,
## farms or trades in the duel, and in the pit plays the boss: chip it from
## outside its reach, fight whoever contests, and smite at the right moment.
## `skill` 0..1 sharpens aim, reactions and smite timing.

var skill := 0.6
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _last_seen := {}            # enemy id -> last position seen


func _init(p_skill: float = 0.6, p_seed: int = 3) -> void:
	skill = p_skill
	rng.seed = p_seed


func think(s: MobaSim, u: MobaUnit) -> Dictionary:
	if not u.alive:
		return {}
	# smite can't wait for the next decision: check it every tick
	if s.mode == "pit":
		var sm := _smite(s, u)
		if not sm.is_empty():
			return sm
	_t -= MobaSim.TICK
	if _t > 0.0:
		return {}
	_t = lerpf(0.35, 0.12, skill) + rng.randf() * 0.08
	var dodge := _dodge(s, u)
	if not dodge.is_empty():
		return dodge
	return _decide_pit(s, u) if s.mode == "pit" else _decide(s, u)


## The nearest living enemy champion (seen or not).
func _foe(s: MobaSim, u: MobaUnit) -> MobaUnit:
	var best: MobaUnit = null
	var bd := INF
	for o in s.units:
		if o.kind == "champ" and o.team != u.team and o.alive:
			var d: float = o.pos.distance_to(u.pos)
			if d < bd:
				best = o
				bd = d
	return best


func _sees(u: MobaUnit, e: MobaUnit, s: MobaSim = null) -> bool:
	if e == null or not e.alive or not e.targetable():
		return false
	if s and not s.team_sees(u.team, e):
		return false
	return u.blind_t <= 0.0 or e.pos.distance_to(u.pos) <= MobaSim.SMOKE_SIGHT


## Step out of an enemy telegraph that will land on us.
func _dodge(s: MobaSim, u: MobaUnit) -> Dictionary:
	if rng.randf() > lerpf(0.35, 0.95, skill):
		return {}
	for a in s.areas:
		if str(a.kind) != "blast" or str(a.team) == u.team:
			continue
		var c: Vector2 = a.pos
		var r := float(a.r) + u.radius + 0.4
		var d := u.pos - c
		if d.length() > r:
			continue
		if a.has("cone"):
			var dir: Vector2 = a.cone
			if d.length() > 0.5 and rad_to_deg(absf(d.angle_to(dir))) > float(a.cone_deg) * 0.5 + 8.0:
				continue
			# sidestep out of the cone, toward the nearer edge
			var side := dir.orthogonal() * (1.0 if d.dot(dir.orthogonal()) >= 0.0 else -1.0)
			return { "move": u.pos + side * 4.0 }
		var away := d.normalized() if d.length() > 0.05 else Vector2.RIGHT
		return { "move": c + away * (r + 0.8) }
	return {}


# ------------------------------------------------------------------- duel

func _decide(s: MobaSim, u: MobaUnit) -> Dictionary:
	var e := _foe(s, u)
	var sees := _sees(u, e, s)
	if sees:
		_last_seen[e.id] = e.pos
	var hp := u.hp / u.max_hp
	var ehp := e.hp / e.max_hp if e else 1.0
	var dist := e.pos.distance_to(u.pos) if e else INF
	var base := s.spawn_of(u.team, int(u.get_meta("slot", 0)))
	# 1. run home when low and the enemy is healthier
	if hp < 0.28 and e and ehp > hp + 0.1 and dist < 9.0:
		return _flee(u, base, dist, hp)
	# 2. a kill or a trade on the champion
	if sees and dist < u.range + 6.0:
		return _trade(s, u, e, dist, hp, ehp)
	# 3. blind-fire at where a hidden enemy was last seen
	if e and not sees and _last_seen.has(e.id) and u.pos.distance_to(_last_seen[e.id]) < 8.0:
		var lp: Vector2 = _last_seen[e.id]
		if u.champ == "braves" and float(u.cd.q) <= 0.0:
			return { "cast": { "slot": "q", "aim": lp } }
		if u.champ == "merr" and float(u.cd.w) <= 0.0:
			return { "cast": { "slot": "w", "aim": lp } }
	# 4. farm: the nearest minion
	var best: MobaUnit = null
	var bd := INF
	for o in s.units:
		if o.team != u.team and o.alive and o.kind == "minion":
			var d: float = o.pos.distance_to(u.pos)
			if d < bd:
				best = o
				bd = d
	if best and bd < 12.0:
		return { "attack": best.id }
	# 5. walk up behind our own minions, or to the middle
	var mine := s.units.filter(func(o): return o.team == u.team and o.kind == "minion" and o.alive)
	var front: Vector2 = mine[0].pos - Vector2((1.0 if u.team == "blue" else -1.0) * 2.0, 0.0) if not mine.is_empty() \
		else Vector2((-1.0 if u.team == "blue" else 1.0) * 4.0, 0.0)
	return { "move": front + Vector2(0, rng.randf_range(-2, 2)) }


func _flee(u: MobaUnit, home: Vector2, dist: float, hp: float) -> Dictionary:
	var o := { "move": home }
	var away := (home - u.pos).normalized()
	if float(u.cd.flash) <= 0.0 and dist < 3.5 and hp < 0.18:
		o["cast"] = { "slot": "flash", "aim": u.pos + away * 4.0 }
	elif u.champ == "temu" and float(u.cd.w) <= 0.0:
		o["cast"] = { "slot": "w", "aim": home }
	elif u.champ == "braves" and float(u.cd.e) <= 0.0:
		o["cast"] = { "slot": "e", "aim": u.pos + away * 5.0 }
	return o


func _trade(s: MobaSim, u: MobaUnit, e: MobaUnit, dist: float, hp: float, ehp: float) -> Dictionary:
	var aim := e.pos + (e.facing * e.ms_now() * 0.35 if e.moving else Vector2.ZERO)
	aim += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * lerpf(1.4, 0.2, skill)
	var o := {}
	var c := _spell(u, e, aim, dist)
	if not c.is_empty():
		o["cast"] = c
	elif u.cd.has("ignite") and float(u.cd.ignite) <= 0.0 and dist <= MobaSim.IGNITE_RANGE and e.hp < MobaSim.IGNITE_DMG + u.ad * 2.0:
		o["cast"] = { "slot": "ignite", "aim": e.pos, "target": e.id }
	if hp >= ehp - 0.15 or dist <= u.range:
		o["attack"] = e.id
	else:
		o["move"] = u.pos + (u.pos - e.pos).normalized() * 3.0
	# Temu: stand still to vanish when the enemy is near but not on top of him
	if u.champ == "temu" and dist > 3.0 and dist <= u.range and rng.randf() < 0.5:
		o.erase("move")
	return o


func _spell(u: MobaUnit, e: MobaUnit, aim: Vector2, dist: float) -> Dictionary:
	if u.casting() or rng.randf() > lerpf(0.5, 0.95, skill):
		return {}
	var ready := func(k: String) -> bool: return float(u.cd.get(k, 99.0)) <= 0.0
	var reach := func(k: String) -> float: return MobaChamps.spell_range(u.champ, k)
	match u.champ:
		"merr":
			if ready.call("r") and dist <= reach.call("r"):
				return { "slot": "r", "aim": e.pos, "target": e.id }
			if ready.call("e") and dist <= reach.call("e"):
				return { "slot": "e", "aim": e.pos, "target": e.id }
			if ready.call("q") and dist <= reach.call("q") - 0.5:
				return { "slot": "q", "aim": aim }
			if ready.call("w") and dist <= reach.call("w"):
				return { "slot": "w", "aim": aim }
		"temu":
			if ready.call("q") and dist <= reach.call("q"):
				return { "slot": "q", "aim": e.pos, "target": e.id }
			if ready.call("r") and dist <= reach.call("r") + 1.5:
				return { "slot": "r", "aim": u.pos + (e.pos - u.pos).limit_length(reach.call("r") * 0.9) }
			if ready.call("w") and dist > u.range + 1.0:
				return { "slot": "w", "aim": e.pos }
		"braves":
			if ready.call("q") and dist <= reach.call("q") * 0.6:
				return { "slot": "q", "aim": e.pos }
			if ready.call("r") and dist <= reach.call("r") - 0.5:
				return { "slot": "r", "aim": aim }
			if ready.call("w") and dist <= reach.call("w") - 0.5:
				return { "slot": "w", "aim": aim }
			if ready.call("e") and dist > u.range and dist < u.range + 2.0:
				return { "slot": "e", "aim": e.pos }
	return {}


# -------------------------------------------------------------------- pit

## Smite when the boss is in reach and one smite kills it. A sharper bot
## waits closer to the line; a duller one sometimes fires early or late.
func _smite(s: MobaSim, u: MobaUnit) -> Dictionary:
	if float(u.cd.get("smite", 99.0)) > 0.0:
		return {}
	var b := s.boss()
	if b == null or not b.alive or b.pos.distance_to(u.pos) > MobaSim.SMITE_RANGE + b.radius:
		return {}
	var line := MobaSim.SMITE_DMG * lerpf(1.25, 1.0, skill)
	if b.hp > line:
		return {}
	if rng.randf() > lerpf(0.08, 0.5, skill):       # a human-ish reaction, checked every tick
		return {}
	return { "cast": { "slot": "smite", "aim": b.pos, "target": b.id } }


func _decide_pit(s: MobaSim, u: MobaUnit) -> Dictionary:
	var b := s.boss()
	var e := _foe(s, u)
	var hp := u.hp / u.max_hp
	var dist := e.pos.distance_to(u.pos) if e else INF
	var home := s.spawn_of(u.team, int(u.get_meta("slot", 0)))
	var boss_low := b != null and b.hp < MobaSim.SMITE_DMG * 3.0
	var boss_on_me := b != null and str(b.order.get("target", "")) == u.id
	# a ping from the team's player (G54): V go in, C hold here
	var pg: Dictionary = s.pings.get(u.team, {})
	if not u.player and not pg.is_empty() and s.time - float(pg.time) < MobaSim.PING_TIME:
		var o := _answer_ping(s, u, e, b, pg, dist, hp)
		if not o.is_empty():
			return o
	# low: back off to the wall (the boss and the enemy both hurt)
	if hp < 0.25 and (boss_on_me or (e and dist < 6.0)):
		return _flee(u, home, dist, hp)
	# endgame: hold smite range, fight whoever contests
	if boss_low and b:
		var to_b := b.pos.distance_to(u.pos)
		if to_b > MobaSim.SMITE_RANGE + b.radius - 0.4:
			return { "move": b.pos + (u.pos - b.pos).normalized() * (MobaSim.SMITE_RANGE + b.radius - 1.0) }
		if _sees(u, e, s) and dist <= u.range + 1.0:
			return _trade(s, u, e, dist, hp, e.hp / e.max_hp)
		return { "attack": b.id }
	# contest: an enemy close by gets fought first; each team's first seat
	# is its hunter and goes looking for the other side
	var hunter := int(u.get_meta("slot", 0)) == 0
	if _sees(u, e, s) and dist <= u.range + (9.0 if hunter and hp > 0.45 else 2.5):
		return _trade(s, u, e, dist, hp, e.hp / e.max_hp)
	if b == null or not b.alive:
		return {}
	# chip the boss from just outside its reach when it's busy with someone else;
	# when it's on us and we're not the toughest, let someone else take it
	var stand := b.radius + u.range - 0.3
	var reach := MobaSim.BOSS_LEASH + b.radius
	if boss_on_me and hp < 0.6:
		stand = maxf(stand, reach + u.radius + 0.6)
	var to_b := b.pos.distance_to(u.pos)
	if absf(to_b - stand) > 0.8:
		var ang := (u.pos - b.pos).angle() + rng.randf_range(-0.25, 0.25)
		return { "move": b.pos + Vector2.from_angle(ang) * stand }
	return { "attack": b.id }


## A bot ally answering its player's ping. "go": run to the spot and fight
## whatever is there, chasing, low health or not; at the Giant, hit it.
## "hold": stand at the spot (spread round it), hit only what walks into
## range, back off when hurt. {} = carry on as usual.
func _answer_ping(s: MobaSim, u: MobaUnit, e: MobaUnit, b: MobaUnit, pg: Dictionary, dist: float, hp: float) -> Dictionary:
	var at: Vector2 = pg.pos
	var slot := int(u.get_meta("slot", 0))
	var spot := at + Vector2.from_angle(slot * 2.1 + (0.0 if u.team == "blue" else PI)) * 1.6
	var seen := _sees(u, e, s)
	if str(pg.kind) == "go":
		if hp < 0.12:
			return {}
		if seen and (e.pos.distance_to(at) < 7.0 or dist <= u.range + 1.0):
			var o := _trade(s, u, e, dist, hp, e.hp / e.max_hp)
			o.erase("move")
			o["attack"] = e.id
			return o
		if b and b.alive and b.pos.distance_to(at) < 6.0 and u.pos.distance_to(at) < 4.0:
			return { "attack": b.id }
		if u.pos.distance_to(spot) > 1.0:
			return { "move": spot }
		return { "attack": b.id } if b and b.alive and b.pos.distance_to(u.pos) <= u.range + b.radius else {}
	# hold
	if hp < 0.35 and seen and dist < 5.0:
		return { "move": u.pos + (u.pos - e.pos).normalized() * 3.0 }
	if seen and dist <= u.range + 0.3:
		var o := _trade(s, u, e, dist, hp, e.hp / e.max_hp)
		o.erase("move")
		o["attack"] = e.id
		return o
	if u.pos.distance_to(spot) > 0.8:
		return { "move": spot }
	return { "hold": true }          # nothing to do: stay put (an unknown key, the sim ignores it)
