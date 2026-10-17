class_name OsrsBot
extends RefCounted
## A player for OsrsSim: prays for the next projectile to land (right
## OsrsTune.bot_react of the time, decided once per projectile), steps off
## squares about to be hit (bot_dodge of the time, per threat), eats under
## half HP, drinks under 30 prayer, takes a nearby Sun Sigil when it's safe,
## and otherwise attacks. G53: it keeps a damage-potion dose going, and in a
## skull phase it wields the lightning dagger and breaks the nearest skull,
## then wields its main weapon again (`dagger` false: it stays on the main
## weapon, which is too slow). G53b: it skates the skulls (always the one
## fewest steps away, struck on arrival), swaps bow <-> staff when the Warden
## shields itself against the one it holds (`swaps` false: it doesn't), and
## runs column to column through the slam (G57: half to half, from the
## moment the pose shows). Seeded: the same seed plays the same way.

var rng := RandomNumberGenerator.new()
var react := -1.0             ## chance it prays right (-1: OsrsTune.bot_react)
var dodge := -1.0             ## chance it dodges a telegraph (-1: OsrsTune.bot_dodge)
var _choice := {}             # projectile id -> the prayer it will use
var dagger := true            ## swaps to the lightning dagger for the skulls
var boost := true             ## drinks the damage potion
var swaps := true             ## swaps weapons against the Warden's shields
var _dodge := {}              # "tick:tile" threat key -> dodges it?
var _main := ""               # the bow or staff it picked


func _init(seed: int = 1) -> void:
	rng.seed = seed


func think(s: OsrsSim) -> Dictionary:
	var o := {}
	var me: Dictionary = s.me
	if not me.alive:
		return o
	if _main == "":
		_main = str(me.weapon) if str(me.weapon) != "dagger" else "bow"
	var skulls := not s.skull_phase.is_empty() and not s.skulls.is_empty()
	# weapons: the dagger for the skulls; otherwise the main weapon, or the
	# other one while the Warden is shielded against it
	var main := _main
	if swaps and str(s.boss.shield) == OsrsSim.style_of(main):
		main = "staff" if main == "bow" else "bow"
	if skulls and dagger and str(me.weapon) != "dagger":
		o["wield"] = "dagger"
	elif not skulls and str(me.weapon) != main and (swaps or str(me.weapon) == "dagger"):
		o["wield"] = main
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
	if float(me.hp) < float(me.max_hp) * (0.3 if skulls else 0.5) and int(me.food) > 0:     # eating mid-skate costs 3 ticks
		o["eat"] = true
	elif float(me.pray) < 30.0 and int(me.doses) > 0:
		o["drink"] = true
	elif boost and int(me.boost) <= 0 and int(me.boost_doses) > 0 and not skulls and me.attack:
		o["boost"] = true
	# danger: step to the nearest safe square in range
	var bad := s.danger(2)
	for sl: Dictionary in s.slams:                       # G57: a half can be 8 columns away: move as the pose shows
		if int(sl.t) <= int(sl.total):
			for x in sl.cols:
				for y in OsrsSim.H:
					bad[Vector2i(int(x), y)] = true
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
		if int(sg.t) <= 3 and OsrsSim._cheb(t, me.tile) <= 3 and not s.danger(int(sg.t) + 1).has(t) and t != me.tile:
			o["move"] = t
			o["attack"] = true
			return o
	if skulls:
		var want := _skull(s)
		if want >= 0 and (int(me.target) != want or not me.attack):
			o["target"] = want
		return o
	if not me.attack and (me.path as Array).is_empty():
		o["attack"] = true
	return o


## The skull to break: the one it's on, else the one fewest steps from a
## square next to it (0: strike it now), so it skates the lane.
func _skull(s: OsrsSim) -> int:
	var keep_t := int(s.me.target)
	var keep_w := str(s.me.weapon)
	if dagger:
		s.me.weapon = "dagger"                          # measure as it will strike (look only; restored below)
	var mid := Vector2.ZERO                             # sweep from the lane's end: farther from its middle first
	for k: Dictionary in s.skulls:
		mid += Vector2(k.tile)
	mid /= float(s.skulls.size())
	var best := -1
	var bd := 1e9
	for k: Dictionary in s.skulls:
		s.me.target = int(k.id)
		var d := 0.0 if s.in_reach(s.me.tile) else float(s.path_to_reach().size())
		if d == 0.0 and not s.in_reach(s.me.tile):
			d = 99.0                                    # can't get next to it
		if int(k.id) == keep_t and d < 99.0:
			d -= 0.5                                    # keep at the one it's after
		d = d * 10.0 - Vector2(k.tile).distance_to(mid)
		if d < bd:
			bd = d
			best = int(k.id)
	s.me.target = keep_t
	s.me.weapon = keep_w
	return best


func _safe(s: OsrsSim, bad: Dictionary) -> Vector2i:
	var me: Dictionary = s.me
	var best := Vector2i(-1, -1)
	var bd := 999.0
	var later := s.danger(5)
	var next_hit: Array = []                            # the slam after the imminent one: lean off its columns (G57: halves)
	var order: Array = s.slams.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.t) < int(b.t))
	if order.size() >= 2:
		next_hit = order[1].cols
	for t: Vector2i in s.floor_tiles():
		if not s.walkable(t) or bad.has(t):
			continue
		var d := Vector2(t).distance_to(Vector2(me.tile)) + (2.0 if later.has(t) else 0.0) + (1.5 if OsrsSim.boss_dist(t) > int(OsrsTune.value("range")) else 0.0) \
			+ (3.0 if OsrsSim.boss_dist(t) <= 1 else 0.0) + (2.5 if next_hit.has(t.x) else 0.0)
		if d < bd:
			bd = d
			best = t
	return best
