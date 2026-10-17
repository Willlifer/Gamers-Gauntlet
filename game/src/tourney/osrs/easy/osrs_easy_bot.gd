class_name OsrsEasyBot
extends RefCounted
## G57: the Easy mode (osrs_easy). A frozen copy of the OSRS trial as it was at
## commit 1f1a933, before G53 (no skulls, shields, dagger, phantoms or the
## pose-read slam), classes renamed. Keep its rules as they were.
## A player for OsrsEasySim: prays for the next projectile to land (right
## OsrsTune.bot_react of the time, decided once per projectile), steps off
## squares about to be hit (bot_dodge of the time, per threat), eats under
## half HP, drinks under 30 prayer, takes a nearby Sun Sigil when it's safe,
## and otherwise attacks. Seeded: the same seed plays the same way.

var rng := RandomNumberGenerator.new()
var react := -1.0             ## chance it prays right (-1: OsrsTune.bot_react)
var dodge := -1.0             ## chance it dodges a telegraph (-1: OsrsTune.bot_dodge)
var _choice := {}             # projectile id -> the prayer it will use
var _dodge := {}              # "tick:tile" threat key -> dodges it?


func _init(seed: int = 1) -> void:
	rng.seed = seed


func think(s: OsrsEasySim) -> Dictionary:
	var o := {}
	var me: Dictionary = s.me
	if not me.alive:
		return o
	# prayer: the next projectile to land
	var next: Dictionary = {}
	for p: Dictionary in s.projs:
		if next.is_empty() or int(p.land) < int(next.land):
			next = p
	if not next.is_empty():
		if not _choice.has(next.id):
			var right := rng.randf() < (react if react >= 0.0 else OsrsTune.value("bot_react"))
			_choice[next.id] = str(next.style) if right else ("ranged" if next.style == "magic" else "magic")
		var want := str(_choice[next.id])
		if me.prayer != want and float(me.pray) > 0.0:
			o["pray"] = want
	# supplies
	if float(me.hp) < float(me.max_hp) * 0.5 and int(me.food) > 0:
		o["eat"] = true
	elif float(me.pray) < 30.0 and int(me.doses) > 0:
		o["drink"] = true
	# danger: step to the nearest safe square in range
	var bad := s.danger(2)
	if bad.has(me.tile):
		var key := "%d:%s" % [s.tick / 4, str(me.tile)]
		if not _dodge.has(key):
			_dodge[key] = rng.randf() < (dodge if dodge >= 0.0 else OsrsTune.value("bot_dodge"))
		if _dodge[key]:
			var safe := _safe(s, bad)
			if safe != Vector2i(-1, -1):
				o["move"] = safe
				o["attack"] = true
				return o
	# the Sun Sigil, if it's close and safe
	for sg: Dictionary in s.sigils:
		var t: Vector2i = sg.tile
		if int(sg.t) <= 3 and OsrsEasySim._cheb(t, me.tile) <= 3 and not s.danger(int(sg.t) + 1).has(t) and t != me.tile:
			o["move"] = t
			o["attack"] = true
			return o
	if not me.attack and (me.path as Array).is_empty():
		o["attack"] = true
	return o


func _safe(s: OsrsEasySim, bad: Dictionary) -> Vector2i:
	var me: Dictionary = s.me
	var best := Vector2i(-1, -1)
	var bd := 999.0
	var later := s.danger(5)
	for t: Vector2i in s.floor_tiles():
		if not s.walkable(t) or bad.has(t):
			continue
		var d := Vector2(t).distance_to(Vector2(me.tile)) + (2.0 if later.has(t) else 0.0) + (1.5 if OsrsEasySim.boss_dist(t) > int(OsrsTune.value("range")) else 0.0) \
			+ (3.0 if OsrsEasySim.boss_dist(t) <= 1 else 0.0)
		if d < bd:
			bd = d
			best = t
	return best
