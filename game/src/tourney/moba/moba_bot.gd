class_name MobaBot
extends RefCounted
## A computer champion: reads the sim and returns orders, like a player.
## Re-decides every REACT s, aims with some error, farms when the enemy is
## away, trades when it's ahead, runs when it's low. `skill` 0..1.

var skill := 0.6
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _last_seen := {}            # enemy id -> last position seen


func _init(p_skill: float = 0.6, p_seed: int = 3) -> void:
	skill = p_skill
	rng.seed = p_seed


func think(s: MobaSim, u: MobaUnit) -> Dictionary:
	_t -= MobaSim.TICK
	if _t > 0.0 or not u.alive:
		return {}
	_t = lerpf(0.35, 0.12, skill) + rng.randf() * 0.08
	return _decide(s, u)


func _decide(s: MobaSim, u: MobaUnit) -> Dictionary:
	var e := s.champ_of("red" if u.team == "blue" else "blue")
	var sees: float = e != null and e.alive and (e.targetable()) and (u.blind_t <= 0.0 or e.pos.distance_to(u.pos) <= MobaSim.SMOKE_SIGHT)
	if sees:
		_last_seen[e.id] = e.pos
	var hp := u.hp / u.max_hp
	var ehp := e.hp / e.max_hp if e and e.alive else 1.0
	var dist: float = e.pos.distance_to(u.pos) if e and e.alive else INF
	var base := s.spawn_of(u.team)
	# 1. run home when low and the enemy is healthier
	if hp < 0.28 and e and e.alive and ehp > hp + 0.1 and dist < 9.0:
		var o := { "move": base }
		if float(u.cd.flash) <= 0.0 and dist < 3.5 and hp < 0.18:
			o["cast"] = { "slot": "flash", "aim": u.pos + (base - u.pos).normalized() * 4.0 }
		elif u.champ == "temu" and float(u.cd.w) <= 0.0:
			o["cast"] = { "slot": "w", "aim": base }
		elif u.champ == "braves" and float(u.cd.e) <= 0.0:
			o["cast"] = { "slot": "e", "aim": u.pos + (base - u.pos).normalized() * 5.0 }
		return o
	# 2. a kill or a trade on the champion
	if sees and dist < u.range + 6.0:
		var aim := e.pos + (e.facing * e.ms_now() * 0.35 if e.moving else Vector2.ZERO)
		aim += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * lerpf(1.4, 0.2, skill)
		var o := {}
		var c := _spell(s, u, e, aim, dist)
		if not c.is_empty():
			o["cast"] = c
		elif float(u.cd.ignite) <= 0.0 and dist <= MobaSim.IGNITE_RANGE and e.hp < MobaSim.IGNITE_DMG + u.ad * 2.0:
			o["cast"] = { "slot": "ignite", "aim": e.pos, "target": e.id }
		if hp >= ehp - 0.15 or dist <= u.range:
			o["attack"] = e.id
		else:
			o["move"] = u.pos + (u.pos - e.pos).normalized() * 3.0
		# Temu: stand still to vanish when the enemy is near but not on top of him
		if u.champ == "temu" and dist > 3.0 and dist <= u.range and rng.randf() < 0.5:
			o.erase("move")
		return o
	# 3. Temu blind-fires at where he last saw a hidden enemy (skillshots only matter for others)
	if e and e.alive and not sees and _last_seen.has(e.id) and u.pos.distance_to(_last_seen[e.id]) < 8.0:
		var lp: Vector2 = _last_seen[e.id]
		if u.champ == "braves" and float(u.cd.q) <= 0.0:
			return { "cast": { "slot": "q", "aim": lp } }
		if u.champ == "merr" and float(u.cd.w) <= 0.0:
			return { "cast": { "slot": "w", "aim": lp } }
	# 4. farm: the minion nearest our side of the fight
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
	var front := u.pos
	var mine := s.units.filter(func(o): return o.team == u.team and o.kind == "minion" and o.alive)
	if not mine.is_empty():
		front = mine[0].pos - Vector2((1.0 if u.team == "blue" else -1.0) * 2.0, 0.0)
	else:
		front = Vector2((-1.0 if u.team == "blue" else 1.0) * 4.0, 0.0)
	return { "move": front + Vector2(0, rng.randf_range(-2, 2)) }


func _spell(s: MobaSim, u: MobaUnit, e: MobaUnit, aim: Vector2, dist: float) -> Dictionary:
	if rng.randf() > lerpf(0.5, 0.95, skill):
		return {}
	var ready := func(k: String) -> bool: return float(u.cd.get(k, 99.0)) <= 0.0
	match u.champ:
		"merr":
			if ready.call("r") and dist <= 7.5:
				return { "slot": "r", "aim": e.pos, "target": e.id }
			if ready.call("e") and dist <= 6.75:
				return { "slot": "e", "aim": e.pos, "target": e.id }
			if ready.call("q") and dist <= 10.0:
				return { "slot": "q", "aim": aim }
			if ready.call("w") and dist <= 9.0:
				return { "slot": "w", "aim": aim }
		"temu":
			if ready.call("q") and dist <= 6.8:
				return { "slot": "q", "aim": e.pos, "target": e.id }
			if ready.call("r") and dist <= 6.0:
				return { "slot": "r", "aim": u.pos + (e.pos - u.pos).limit_length(3.5) }
			if ready.call("w") and dist > u.range + 1.0:
				return { "slot": "w", "aim": e.pos }
		"braves":
			if ready.call("q") and dist <= 5.0:
				return { "slot": "q", "aim": e.pos }
			if ready.call("r") and dist <= 9.5:
				return { "slot": "r", "aim": aim }
			if ready.call("w") and dist <= 8.5:
				return { "slot": "w", "aim": aim }
			if ready.call("e") and dist > u.range and dist < 8.0:
				return { "slot": "e", "aim": e.pos }
	return {}
