extends SceneTree
## Headless: the OSRS raid (G34).
##   godot --headless --path . --script res://tools/osrs_probe.gd
## Squares: paths are 8-way without corner cutting, a run moves two squares a
## tick, walking one. Prayer blocks the matching projectile. A projectile flies
## 3 s from any square, is judged on impact, and keeps coming through a slam. Lightning,
## boulders, slams and the tear-out hit only the squares they mark. The Sun
## Sigil empowers. G53: the flanking phantoms fire the projectiles, the
## Warden the specials; a row torn out per 8% lost; the slam's third hit
## spares only the centre column and speeds up below 50%; the damage potion;
## the lightning dagger; the skull phases (seeded, shielded, dagger clears,
## the main weapon is too slow, leftovers burst). G53b: three slam hits with
## three different safe columns; the dagger is melee and strikes on arrival
## (the skate); skulls in a lane, one hit each, a third of the time; the
## magic / bowfire shields. Bot runs end, kill
## sometimes, die sometimes, and replay the same. Exit 0 when every check passes.

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("ok   " if c else "FAIL ") + what)


func _initialize() -> void:
	OsrsTune.use_defaults()
	_squares()
	_prayer()
	_flight()
	_hazards()
	_sigil()
	_flanks()
	_tearout()
	_slam_g53()
	_potion()
	_dagger()
	_skulls()
	_skate()
	_shields()
	_runs()
	print("osrs probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _quiet(s: OsrsSim) -> void:
	s.boss.auto_cd = 9999
	s.boss.special_cd = 9999
	s.boss.sigil_cd = 9999
	s.boss.rips = 9999
	s.boss.skull_i = 3
	s.boss.shield_cd = 9999


func _squares() -> void:
	var s := OsrsSim.new(1)
	_quiet(s)
	s.me.tile = Vector2i(2, 8)
	s.rocks[Vector2i(3, 7)] = 99
	s.rocks[Vector2i(2, 7)] = 99
	var p := s.path(Vector2i(2, 8), Vector2i(3, 6))
	var cut := false
	var prev := Vector2i(2, 8)
	for t: Vector2i in p:
		var d := t - prev
		if d.x != 0 and d.y != 0 and (not s.walkable(Vector2i(prev.x + d.x, prev.y)) or not s.walkable(Vector2i(prev.x, prev.y + d.y))):
			cut = true
		prev = t
	_ok(not p.is_empty() and p[-1] == Vector2i(3, 6) and not cut, "a path round two rocks without cutting a corner (%d squares)" % p.size())
	s.rocks.clear()
	s.me.tile = Vector2i(0, 11)
	s.step({ "move": Vector2i(0, 5), "run": true })
	_ok(s.me.tile == Vector2i(0, 9), "running: two squares a tick")
	s.step({ "run": false })
	_ok(s.me.tile == Vector2i(0, 8), "walking: one square a tick")
	s.step({ "move": Vector2i(40, -3) })
	_ok(OsrsSim.inside(s.me.tile), "a click off the floor walks to the nearest square")


func _prayer() -> void:
	var s := OsrsSim.new(2)
	_quiet(s)
	s._launch("magic", 3, 20.0)
	s.step({ "pray": "magic" })
	s.step({})
	s.step({})
	_ok(is_equal_approx(float(s.me.hp), float(s.me.max_hp)) and int(s.me.blocked) == 1, "Protect from Magic blocks a magic projectile")
	s._launch("ranged", 2, 20.0)
	s.step({})
	s.step({})
	_ok(is_equal_approx(float(s.me.hp), float(s.me.max_hp) - 20.0), "the wrong prayer lets a ranged projectile through (20)")
	var p0 := float(s.me.pray)
	for i in 30:
		s.step({})
	_ok(float(s.me.pray) < p0 - 8.0, "a protect prayer drains (%.0f → %.0f over 30 ticks)" % [p0, float(s.me.pray)])
	s.me.hp = 40.0
	s.step({ "eat": true })
	_ok(is_equal_approx(float(s.me.hp), 40.0 + float(s.me.max_hp) * 0.25), "food restores 25%")


## G45: every prayable projectile takes flight_s (3 s) from launch to impact,
## near or far; the prayer is judged on impact; the twin lands a tick behind;
## projectiles keep launching and landing through a slam.
func _flight() -> void:
	_ok(is_equal_approx(OsrsSim.flight_ticks() * OsrsSim.TICK, 3.0), "a projectile flies %d ticks = %.1f s" % [OsrsSim.flight_ticks(), OsrsSim.flight_ticks() * OsrsSim.TICK])
	for at: Vector2i in [Vector2i(7, 1), Vector2i(0, 11)]:
		var s := OsrsSim.new(8)
		_quiet(s)
		s.me.tile = at
		s.boss.auto_cd = 1
		s.step({})
		var p: Dictionary = s.projs[0] if not s.projs.is_empty() else {}
		var secs := (int(p.land) - int(p.launch)) * OsrsSim.TICK if not p.is_empty() else -1.0
		_ok(str(p.get("style", "")) in OsrsSim.STYLES and is_equal_approx(secs, 3.0), "from %d squares away it lands 3 s after launch (%.1f s)" % [OsrsSim.boss_dist(at), secs])
	# judged on impact: up the whole flight but dropped on the last tick lets it
	# through; switched on only on the landing tick still blocks it
	var s := OsrsSim.new(9)
	_quiet(s)
	s._launch("magic", OsrsSim.flight_ticks(), 20.0)
	s.step({ "pray": "magic" })
	for i in OsrsSim.flight_ticks() - 2:
		s.step({})
	s.step({ "pray": "off" })
	_ok(is_equal_approx(float(s.me.hp), float(s.me.max_hp) - 20.0), "a prayer dropped before impact doesn't block (judged on impact)")
	s._launch("ranged", OsrsSim.flight_ticks(), 20.0)
	for i in OsrsSim.flight_ticks() - 1:
		s.step({})
	_ok(s.projs.size() == 1, "nothing lands before its 3 s are up")
	s.step({ "pray": "ranged" })
	_ok(s.projs.is_empty() and int(s.me.blocked) == 1, "Protect from Missiles switched on the landing tick blocks it")
	# phase 3's twin: the other style, a tick behind, also 3 s
	var t := OsrsSim.new(10)
	_quiet(t)
	t.boss.hp = float(t.boss.max_hp) * 0.3
	t.me.tile = Vector2i(7, 9)
	OsrsTune._values["twin_chance"] = 1.0
	t.boss.auto_cd = 1
	t.step({})
	t.step({})
	OsrsTune._values.erase("twin_chance")
	var ok: bool = t.projs.size() == 2 and t.projs[0].style != t.projs[1].style and int(t.projs[1].land) == int(t.projs[0].land) + 1 		and int(t.projs[1].land) - int(t.projs[1].launch) == OsrsSim.flight_ticks() and t.projs[0].src != t.projs[1].src
	_ok(ok, "phase 3's twin: the other style from the other phantom, landing a tick behind, also a 3 s flight")
	# through the slam: projectiles launch and land while the floor glows
	var u := OsrsSim.new(11)
	_quiet(u)
	u.me.tile = Vector2i(7, 9)
	u.boss.hp = float(u.boss.max_hp) * 0.5
	u.boss.auto_cd = 2
	u._slam()
	var launched := 0
	var landed := 0
	while not u.slams.is_empty():
		for e: Dictionary in u.step({}):
			if str(e.type) == "proj":
				launched += 1
			elif str(e.type) == "hurt" or str(e.type) == "blocked":
				if str(e.get("what", e.get("style", ""))) in OsrsSim.STYLES and str(e.type) == "hurt":
					landed += 1
		u.boss.auto_cd = mini(int(u.boss.auto_cd), int(OsrsTune.value("auto_every")))
	_ok(launched >= 2 and landed >= 1, "the Warden keeps firing through a slam (%d launched, %d landed)" % [launched, landed])
	# and in a real fight, every slam has a projectile in the air
	var v := OsrsSim.new(12)
	var b := OsrsBot.new(12)
	var slams := 0
	var covered := 0
	while v.over == "":
		for e: Dictionary in v.step(b.think(v)):
			if str(e.type) == "slam_land":
				slams += 1
				if not v.projs.is_empty():
					covered += 1
	_ok(slams >= 1 and covered == slams, "in a bot fight every slam lands with a projectile in the air (%d / %d)" % [covered, slams])


func _hazards() -> void:
	var s := OsrsSim.new(3)
	_quiet(s)
	s.me.tile = Vector2i(7, 9)
	s._lightning(8)
	var on_me: bool = s.bolts.any(func(b: Dictionary) -> bool: return b.tile == Vector2i(7, 9))
	_ok(on_me, "lightning always marks your square")
	var hp0 := float(s.me.hp)
	s.step({ "move": Vector2i(0, 2) })                      # run well away
	for i in 6:
		s.step({})
	_ok(is_equal_approx(float(s.me.hp), hp0) and int(s.me.dodged) >= 1, "running off the shadows dodges the bolts")
	var s2 := OsrsSim.new(4)
	_quiet(s2)
	s2.me.tile = Vector2i(7, 9)
	s2._slam()
	var first: int = s2.slams[0].safe
	s2.me.tile = Vector2i(0 if first > 7 else 14, 9)
	for i in 5:
		s2.step({})
	_ok(is_equal_approx(float(s2.me.hp), float(s2.me.max_hp) - OsrsTune.value("slam_dmg")), "a slam hit lands everywhere but its safe column")
	var s3 := OsrsSim.new(5)
	_quiet(s3)
	s3.me.tile = Vector2i(5, 9)
	s3._boulders()
	for i in 6:
		s3.step({})
	_ok(float(s3.me.hp) < float(s3.me.max_hp) and s3.rocks.size() >= 1 and s3.walkable(s3.me.tile), "a boulder on you hurts, stays as a rock, and you're shoved off it")
	var s4 := OsrsSim.new(6)
	_quiet(s4)
	s4.boss.hp = float(s4.boss.max_hp) * 0.3
	s4.boss.rips = 0
	s4.me.tile = Vector2i(7, 11)
	for i in 8:
		s4.step({})
	_ok(s4.gone.has(Vector2i(7, 11)) and s4.me.tile.y < 11 and float(s4.me.hp) < float(s4.me.max_hp), "phase 3 tears out the far row; standing on it hurts and moves you")


func _sigil() -> void:
	var s := OsrsSim.new(7)
	_quiet(s)
	s.me.tile = Vector2i(7, 8)
	s.sigils.append({ "tile": Vector2i(7, 8), "t": 1, "total": 1 })
	s.step({})
	_ok(int(s.me.empowered) == int(OsrsTune.value("sigil_hits")), "standing on the Sun Sigil when it ignites empowers you")
	s.boss.hp = 9999.0
	s.boss.max_hp = 9999.0
	OsrsTune._values["accuracy"] = 1.0
	s.step({ "attack": true })
	var dmg := float(s.me.dmg_done)
	_ok(dmg >= OsrsTune.value("bow_lo") * OsrsTune.value("sigil_mult"), "an empowered bow shot hits for x%.1f (%.0f)" % [OsrsTune.value("sigil_mult"), dmg])
	OsrsTune._values.erase("accuracy")


## G53: the flanking phantoms take turns with the prayable shots; the Warden
## only smacks (melee) when you stand next to it, and does the specials.
func _flanks() -> void:
	var s := OsrsSim.new(20)
	_quiet(s)
	s.me.tile = Vector2i(7, 9)
	var srcs: Array = []
	for i in 40:
		s.boss.auto_cd = mini(int(s.boss.auto_cd), 5)
		for e: Dictionary in s.step({ "pray": "magic" } if i == 0 else {}):
			if str(e.type) == "proj":
				srcs.append(str(e.proj.src))
	var alt := srcs.size() >= 6
	for i in range(1, srcs.size()):
		if srcs[i] == srcs[i - 1] or not srcs[i] in ["west", "east"]:
			alt = false
	_ok(alt, "the prayable shots come from the west and east phantoms by turns (%s)" % ",".join(srcs.slice(0, 6)))
	var m := OsrsSim.new(21)
	_quiet(m)
	m.me.tile = Vector2i(7, 0)
	m.boss.auto_cd = 1
	m.step({})
	_ok(not m.projs.is_empty() and m.projs[0].style == "melee" and m.projs[0].src == "warden", "next to the Warden it smacks you itself (melee)")


## G53: one far row per rip_pct (8%) of the Warden's HP lost, from the start, down to rows_left.
func _tearout() -> void:
	var s := OsrsSim.new(22)
	_quiet(s)
	s.boss.rips = 0
	s.me.tile = Vector2i(7, 2)
	s.boss.hp = float(s.boss.max_hp) * 0.95
	for i in 12:
		s.step({})
	_ok(s.rows_left() == OsrsSim.H, "at 95%% no row is torn out yet (%d rows)" % s.rows_left())
	s.boss.hp = float(s.boss.max_hp) * (1.0 - 0.08 * 3 - 0.01)
	for i in 40:
		s.step({})
	_ok(s.rows_left() == OsrsSim.H - 3, "at 75%%: three rows torn out, one per 8%% lost (%d rows)" % s.rows_left())
	s.boss.hp = 50.0
	for i in 80:
		s.step({})
	_ok(s.rows_left() == int(OsrsTune.value("rows_left")), "never below %d rows (%d)" % [int(OsrsTune.value("rows_left")), s.rows_left()])
	var t := OsrsSim.new(23)
	var rips := 0
	var b := OsrsBot.new(23)
	while t.over == "":
		for e: Dictionary in t.step(b.think(t)):
			if str(e.type) == "rip":
				rips += 1
	_ok(rips >= 6, "a bot fight tears out %d rows (was 0-3 before G53)" % rips)


## G53b: three slam hits, three different safe columns 2-4 apart; running
## column to column dodges them all, at either speed; standing still doesn't.
func _slam_g53() -> void:
	var ok_cols := true
	var bad := ""
	for seed in 40:
		var s := OsrsSim.new(300 + seed)
		_quiet(s)
		s.me.tile = Vector2i(seed % OsrsSim.W, 8)
		if seed % 2 == 1:
			s.boss.hp = float(s.boss.max_hp) * 0.45
		s._slam()
		var safe: Array = s.slams.map(func(x: Dictionary) -> int: return int(x.safe))
		for i in 3:
			var c: Array = s.slams[i].cols
			if c.size() != OsrsSim.W - 1 or c.has(safe[i]):
				ok_cols = false
		if safe[0] == safe[1] or safe[1] == safe[2] or safe[0] == safe[2] or absi(safe[1] - safe[0]) > 4 or absi(safe[2] - safe[1]) > 4 \
				or absi(safe[1] - safe[0]) < 2 or absi(safe[2] - safe[1]) < 2:
			ok_cols = false
			bad = str(safe)
	_ok(ok_cols, "each slam hit spares one column, three different ones 2-4 apart (40 slams) %s" % bad)
	var gap := 0
	var fgap := 0
	for slow in [true, false]:
		var hits := 0
		var still := 0
		for seed in 20:
			var f := OsrsSim.new(400 + seed)
			_quiet(f)
			f.me.tile = Vector2i(7, 9)
			if not slow:
				f.boss.hp = float(f.boss.max_hp) * 0.45
			f._slam()
			if slow:
				gap = int(f.slams[1].t) - int(f.slams[0].t)
			else:
				fgap = int(f.slams[1].t) - int(f.slams[0].t)
			var g := OsrsSim.new(400 + seed)
			_quiet(g)
			g.me.tile = Vector2i(7, 9)
			g.boss.hp = f.boss.hp
			g._slam()
			var hp0 := float(f.me.hp)
			var steps := 0
			while not f.slams.is_empty() and steps < 30:
				var next: Dictionary = f.slams[0]
				for x: Dictionary in f.slams:
					if int(x.t) < int(next.t):
						next = x
				f.step({ "move": Vector2i(int(next.safe), 9) } if f.me.tile.x != int(next.safe) and (f.me.path as Array).is_empty() else {})
				g.step({})
				steps += 1
			if not is_equal_approx(float(f.me.hp), hp0):
				hits += 1
			if is_equal_approx(float(g.me.hp), hp0):
				still += 1
		_ok(hits == 0 and still == 0, "%s slams: running to each safe column in turn dodges all three (%d / 20 hit); standing still never does (%d / 20 clean)" % ["slow" if slow else "fast", hits, still])
	_ok(gap == 4 and fgap == 2, "slam hits %d ticks apart above 50%%, %d below" % [gap, fgap])


## G53: a damage potion; a dose makes bow / staff hits x boost_mult for boost_ticks.
func _potion() -> void:
	OsrsTune._values["accuracy"] = 1.0
	OsrsTune._values["bow_lo"] = 40.0
	OsrsTune._values["bow_hi"] = 40.0
	var s := OsrsSim.new(26)
	_quiet(s)
	s.boss.hp = 9999.0
	s.boss.max_hp = 9999.0
	s.me.tile = Vector2i(7, 5)
	var d0 := int(s.me.boost_doses)
	s.step({ "attack": true })
	var plain := float(s.me.dmg_done)
	s.step({ "boost": true })
	for i in 3:
		s.step({})
	var boosted := float(s.me.dmg_done) - plain
	_ok(d0 == int(OsrsTune.value("boost_doses")) and int(s.me.boost_doses) == d0 - 1, "the damage potion has %d doses; a sip takes one" % d0)
	_ok(is_equal_approx(boosted, roundf(40.0 * OsrsTune.value("boost_mult"))), "boosted, a 40 hits for %.0f" % boosted)
	for i in int(OsrsTune.value("boost_ticks")):
		s.step({})
	var before := float(s.me.dmg_done)
	for i in 4:
		s.step({})
	_ok(int(s.me.boost) == 0 and is_equal_approx(float(s.me.dmg_done) - before, 40.0), "after %d ticks it wears off" % int(OsrsTune.value("boost_ticks")))
	for k in ["accuracy", "bow_lo", "bow_hi"]:
		OsrsTune._values.erase(k)


## G53 / G53b: the lightning dagger: click it to wield; melee (a square
## straight next to the target); a 1 every tick.
func _dagger() -> void:
	var s := OsrsSim.new(27)
	_quiet(s)
	s.boss.hp = 9999.0
	s.boss.max_hp = 9999.0
	s.me.tile = Vector2i(7, 9)
	s.step({ "wield": "dagger", "attack": true })
	_ok(s.me.weapon == "dagger", "the lightning dagger wields from the inventory")
	for i in 8:
		s.step({})
	_ok(s.me.tile.y == 0 and s.me.tile.x >= 5 and s.me.tile.x <= 9, "against the Warden it walks right up to it (melee, %s)" % str(s.me.tile))
	var a0 := int(s.me.attacks)
	var d0 := float(s.me.dmg_done)
	for i in 10:
		s.step({})
	_ok(int(s.me.attacks) - a0 == 10 and is_equal_approx(float(s.me.dmg_done) - d0, 10.0), "it hits every tick for 1 (%d hits, %.0f damage in 10 ticks)" % [int(s.me.attacks) - a0, float(s.me.dmg_done) - d0])
	s.step({ "wield": "bow" })
	_ok(s.me.weapon == "bow", "and the bow wields back")
	# melee reach: straight next to a skull, not diagonal
	var m := OsrsSim.new(30)
	_quiet(m)
	m.me.weapon = "dagger"
	m.skulls = [{ "id": 77, "tile": Vector2i(5, 5), "hp": 1, "max": 1 }]
	m.me.target = 77
	var diag := m.in_reach(Vector2i(6, 6))
	var side := m.in_reach(Vector2i(6, 5))
	var two := m.in_reach(Vector2i(7, 5))
	_ok(side and not diag and not two, "the dagger reaches a skull from a square straight next to it only (not diagonal, not 2 away)")


## G53 / G53b: the skull phases at 75 / 50 / 25%.
func _skulls() -> void:
	var s := OsrsSim.new(28)
	_quiet(s)
	s.boss.skull_i = 0
	s.me.tile = Vector2i(7, 6)
	OsrsTune._values["accuracy"] = 1.0
	s.boss.hp = float(s.boss.max_hp) * 0.76
	var hit_floor := false
	for i in 8:
		s.step({ "attack": true })
		if not s.skull_phase.is_empty():
			hit_floor = is_equal_approx(float(s.boss.hp), float(s.boss.max_hp) * 0.75)
			break
	var n := s.skulls.size()
	_ok(hit_floor and n >= 5 and n <= 10, "at 75%% the Warden stops at %.0f and raises %d skulls" % [float(s.boss.hp), n])
	var total := int(s.skull_phase.total)
	_ok(total == roundi(OsrsTune.value("skull_base") + OsrsTune.value("skull_per") * n) and total <= (6 + 5 * n + 2) / 3,
		"the skulls charge in %d ticks (%.1f s), a third of G53's %d" % [total, total * OsrsSim.TICK, 6 + 5 * n])
	# the lane: two rows of skulls either side of a lane, every other square
	var lanes := 0
	for seed in 20:
		var l := OsrsSim.new(600 + seed)
		_quiet(l)
		l.boss.skull_i = 0
		l.me.tile = Vector2i(seed % OsrsSim.W, 5 + seed % 5)
		l.boss.hp = float(l.boss.max_hp) * 0.75
		l.step({})
		var tiles: Array = l.skulls.map(func(k: Dictionary) -> Vector2i: return k.tile)
		var paired := 0
		for t: Vector2i in tiles:
			if tiles.has(t + Vector2i(0, 2)) or tiles.has(t - Vector2i(0, 2)) or tiles.has(t + Vector2i(2, 0)) or tiles.has(t - Vector2i(2, 0)):
				paired += 1
		if paired >= tiles.size() - 1 and not tiles.has(l.me.tile):
			lanes += 1
	_ok(lanes >= 18, "skulls rise in a lane, two rows every other square, near you (%d / 20)" % lanes)
	var apart := true
	for k: Dictionary in s.skulls:
		if s.walkable(k.tile) or k.tile == s.me.tile:
			apart = false
	_ok(apart, "skulls block their squares, none on you")
	var tl: Array = []
	for k in 2:
		var same := OsrsSim.new(29)
		_quiet(same)
		same.boss.skull_i = 0
		same.me.tile = Vector2i(7, 6)
		same.boss.hp = float(same.boss.max_hp) * 0.75
		same.step({})
		tl.append(same.skulls.map(func(q: Dictionary) -> Vector2i: return q.tile))
	_ok(not tl[0].is_empty() and tl[0] == tl[1], "seeded: the same seed raises the same skulls (%d)" % tl[0].size())
	var hp0 := float(s.boss.hp)
	s.step({ "attack": true })
	_ok(is_equal_approx(float(s.boss.hp), hp0), "the Warden is shielded while its skulls are up")
	# one hit breaks one, from any weapon (a bow shot here)
	var k0: Dictionary = s.skulls[0]
	s.step({ "target": int(k0.id) })
	var t := 0
	while not s.skull(int(k0.id)).is_empty() and t < 10:
		s.step({})
		t += 1
	OsrsTune._values.erase("accuracy")
	_ok(s.skull(int(k0.id)).is_empty() and int(s.me.skulls) == 1, "one bow shot breaks a skull")
	_ok(not s.me.attack, "a broken skull stops your attack (click the next one)")
	# leftovers burst at the end
	var left := s.skulls.size()
	s.me.hp = 999.0
	s.me.max_hp = 999.0
	var burst := 0.0
	while not s.skull_phase.is_empty():
		for e: Dictionary in s.step({}):
			if str(e.type) == "hurt" and str(e.what) == "skulls":
				burst = float(e.dmg)
	_ok(is_equal_approx(burst, OsrsTune.value("skull_dmg") * left) and s.skulls.is_empty(), "%d skulls left burst for %.0f (%.0f each)" % [left, burst, OsrsTune.value("skull_dmg")])
	# a bot that skates with the dagger clears the skull phases; on the bow it can't
	var cleared := [0, 0]
	var bursts := [0, 0]
	var phases := [0, 0]
	var spare := []
	for mode in 2:
		for i in 10:
			var r := OsrsSim.new(900 + i)
			var b := OsrsBot.new(900 + i)
			b.dagger = mode == 0
			while r.over == "":
				for e: Dictionary in r.step(b.think(r)):
					if str(e.type) == "skulls":
						phases[mode] += 1
					elif str(e.type) == "skulls_end":
						if int(e.left) == 0:
							cleared[mode] += 1
							if mode == 0:
								spare.append(int(r.skull_phase.get("t", 0)))
						else:
							bursts[mode] += int(e.left)
	print("  skull phases: skating dagger bots cleared %d / %d (%d skulls burst); bow-only bots cleared %d / %d (%d skulls burst)" % [cleared[0], phases[0], bursts[0], cleared[1], phases[1], bursts[1]])
	_ok(phases[0] > 0 and cleared[0] >= phases[0] * 0.8, "a good player skating with the dagger clears the skulls (%d / %d)" % [cleared[0], phases[0]])
	_ok(phases[1] > 0 and cleared[1] == 0 and bursts[1] >= phases[1] * 3, "the main weapon is too slow: never clears, %d skulls burst over %d phases" % [bursts[1], phases[1]])


## G53b: the skate. Clicking a skull you aren't next to walks to the nearest
## square straight next to it and strikes on the tick you arrive; the next
## click loses no tick. Up a lane that's one skull a tick; stopping a tick
## between (click, arrive, then click to hit) is too slow.
func _skate() -> void:
	var s := OsrsSim.new(31)
	_quiet(s)
	s.me.weapon = "dagger"
	s.me.tile = Vector2i(1, 6)
	s.skulls = []
	var id := 1
	for x in [4, 6, 8, 10]:
		for y in [5, 7]:
			s.skulls.append({ "id": id, "tile": Vector2i(x, y), "hp": 1, "max": 1 })
			id += 1
	s.skull_phase = { "t": 99, "total": 99, "n": 8 }
	var first := s.skulls[0].id as int
	var arrive_hit := false
	for e: Dictionary in s.step({ "target": first }):
		if str(e.type) == "skull_dead":
			arrive_hit = true
	_ok(arrive_hit and s.me.trail.size() == 3, "one click: it runs two squares to a square beside the skull and breaks it the same tick (%s)" % str(s.me.tile))
	var ticks := 1
	while not s.skulls.is_empty() and ticks < 30:
		var want := -1
		for k: Dictionary in s.skulls:
			s.me.target = int(k.id)
			if s.in_reach(s.me.tile):
				want = int(k.id)
				break
		if want < 0:
			want = int(s.skulls[0].id)
		s.me.target = -1
		s.step({ "target": want })
		ticks += 1
	_ok(s.skulls.is_empty() and ticks <= 9, "skating the lane: 8 skulls in %d ticks, about one a tick" % ticks)
	# the slow way: click to walk next to it, then click it
	var w := OsrsSim.new(31)
	_quiet(w)
	w.me.weapon = "dagger"
	w.me.tile = Vector2i(2, 6)
	w.skulls = []
	id = 1
	for x in [4, 6, 8, 10]:
		for y in [5, 7]:
			w.skulls.append({ "id": id, "tile": Vector2i(x, y), "hp": 1, "max": 1 })
			id += 1
	w.skull_phase = { "t": 99, "total": 99, "n": 8 }
	var wt := 0
	while not w.skulls.is_empty() and wt < 60:
		var k: Dictionary = w.skulls[0]
		w.me.target = int(k.id)
		var stand: Array = w.path_to_reach()
		w.me.target = -1
		if not stand.is_empty():
			w.step({ "move": stand[-1] })
			wt += 1
			while not (w.me.path as Array).is_empty():
				w.step({})
				wt += 1
		w.step({ "target": int(k.id) })
		wt += 1
	var limit := roundi(OsrsTune.value("skull_base") + OsrsTune.value("skull_per") * 8)
	_ok(ticks <= limit and wt > limit, "the skate beats the 8-skull charge (%d of %d ticks); walk-then-click doesn't (%d)" % [ticks, limit, wt])


## G53b: the Warden shields itself against magic, then bowfire, by turns.
func _shields() -> void:
	OsrsTune._values["accuracy"] = 1.0
	var s := OsrsSim.new(32)
	_quiet(s)
	s.boss.hp = 9999.0
	s.boss.max_hp = 9999.0
	s.me.tile = Vector2i(7, 6)
	s.boss.shield_cd = 1
	var got := ""
	for e: Dictionary in s.step({}):
		if str(e.type) == "shield":
			got = str(e.style)
	_ok(got == "magic" and s.boss.shield == "magic", "the Warden shields itself against magic")
	s.me.weapon = "staff"
	var d0 := float(s.me.dmg_done)
	for i in 10:
		s.step({ "attack": true } if i == 0 else {})
	_ok(is_equal_approx(float(s.me.dmg_done), d0) and int(s.me.attacks) >= 2, "staff hits do nothing against it (%d hits, %.0f damage)" % [int(s.me.attacks), float(s.me.dmg_done) - d0])
	s.step({ "wield": "bow" })
	for i in 8:
		s.step({})
	_ok(float(s.me.dmg_done) > d0, "the bow gets through (%.0f)" % (float(s.me.dmg_done) - d0))
	s.boss.shield_cd = 1
	s.step({})
	var d1 := float(s.me.dmg_done)
	for i in 8:
		s.step({})
	_ok(s.boss.shield == "ranged" and is_equal_approx(float(s.me.dmg_done), d1), "then against bowfire: the bow does nothing")
	OsrsTune._values.erase("accuracy")
	# in a fight: shields alternate, and a bot that swaps beats one that doesn't
	var sh: Array = []
	var f := OsrsSim.new(33)
	var fb := OsrsBot.new(33)
	while f.over == "":
		for e: Dictionary in f.step(fb.think(f)):
			if str(e.type) == "shield":
				sh.append(str(e.style))
	var alt := sh.size() >= 3
	for i in sh.size():
		if sh[i] != ("magic" if i % 2 == 0 else "ranged"):
			alt = false
	_ok(alt, "in a fight the shields alternate magic, bowfire, ... (%d)" % sh.size())
	var swap_t := 0.0
	var stay_t := 0.0
	var stay_win := 0
	for i in 8:
		for mode in 2:
			var r := OsrsSim.new(950 + i)
			var b := OsrsBot.new(950 + i)
			b.swaps = mode == 0
			while r.over == "":
				r.step(b.think(r))
			if mode == 0:
				swap_t += float(r.result().boss_dmg) / maxf(1.0, r.tick)
			else:
				stay_t += float(r.result().boss_dmg) / maxf(1.0, r.tick)
	print("  shields: damage per tick %.2f swapping, %.2f not" % [swap_t / 8.0, stay_t / 8.0])
	_ok(swap_t > stay_t * 1.25, "swapping weapons against the shields pays (%.2f vs %.2f damage a tick)" % [swap_t / 8.0, stay_t / 8.0])


func _runs() -> void:
	var kills := 0
	var deaths := 0
	var secs := 0.0
	for i in 20:
		var s := OsrsSim.new(100 + i)
		var b := OsrsBot.new(500 + i)
		while s.over == "":
			s.step(b.think(s))
		if s.over == "win":
			kills += 1
			secs += s.tick * OsrsSim.TICK
		elif s.over == "dead":
			deaths += 1
		var r := s.result()
		print("  run %2d: %-4s %3.0f s  dealt %4.0f  taken %3.0f  prayed %d/%d  dodged %d hit %d  sigils %d  skulls %d broken %d burst" % [i, r.how, r.secs, r.boss_dmg, r.taken,
			r.blocked, int(r.blocked) + int(r.unblocked), r.dodged, r.struck, r.sigils, r.skulls, r.skulls_left])
	print("  bots: %d kills (mean %.0f s), %d deaths, %d timeouts" % [kills, secs / maxf(1, kills), deaths, 20 - kills - deaths])
	_ok(kills >= 6, "a good bot kills the Warden in a fair share of runs (%d / 20)" % kills)
	# a careless player (prays right 60%, dodges half the time) dies often: it's meant to be hard for a new player
	var careless := 0
	for i in 20:
		var s := OsrsSim.new(300 + i)
		var b := OsrsBot.new(700 + i)
		b.react = 0.6
		b.dodge = 0.5
		while s.over == "":
			s.step(b.think(s))
		if s.over != "win":
			careless += 1
	print("  careless bots: %d / 20 fail" % careless)
	_ok(careless >= 8, "the fight beats a careless player (%d / 20 fail)" % careless)
	# replay: the same seed and orders give the same fight
	var hs: Array = []
	for k in 2:
		var s := OsrsSim.new(42)
		var b := OsrsBot.new(42)
		while s.over == "":
			s.step(b.think(s))
		hs.append(s.state_hash())
	_ok(hs[0] == hs[1], "replay: the same seed plays the same fight")
	var a := { "how": "win", "ticks": 200, "boss_dmg": 1000.0, "taken": 50.0 }
	var d := { "how": "dead", "ticks": 100, "boss_dmg": 900.0, "taken": 99.0 }
	var f := { "how": "win", "ticks": 180, "boss_dmg": 1000.0, "taken": 80.0 }
	_ok(OsrsSim.beats(a, d) and OsrsSim.beats(f, a) and not OsrsSim.beats(d, a), "the verdict: a kill beats a death, then the faster kill")
