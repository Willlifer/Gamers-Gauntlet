extends SceneTree
## Headless: the OSRS raid (G34).
##   godot --headless --path . --script res://tools/osrs_probe.gd
## Squares: paths are 8-way without corner cutting, a run moves two squares a
## tick, walking one. Prayer blocks the matching projectile. A projectile flies
## 3 s from any square, is judged on impact, and keeps coming through a slam. Lightning,
## boulders, slams and the tear-out hit only the squares they mark. The Sun
## Sigil empowers. Bot runs end, kill sometimes, die sometimes, and replay
## the same. Exit 0 when every check passes.

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
	_runs()
	print("osrs probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _quiet(s: OsrsSim) -> void:
	s.boss.auto_cd = 9999
	s.boss.special_cd = 9999
	s.boss.sigil_cd = 9999
	s.boss.rip_cd = 9999


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
	var ok: bool = t.projs.size() == 2 and t.projs[0].style != t.projs[1].style and int(t.projs[1].land) == int(t.projs[0].land) + 1 		and int(t.projs[1].land) - int(t.projs[1].launch) == OsrsSim.flight_ticks()
	_ok(ok, "phase 3's twin: the other style, landing a tick behind, also a 3 s flight")
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
	s2.me.tile = Vector2i(12, 9)
	s2._slam()
	for i in 5:
		s2.step({})
	_ok(is_equal_approx(float(s2.me.hp), float(s2.me.max_hp) - OsrsTune.value("slam_dmg")), "the east slam hits the east side")
	s2.step({ "move": Vector2i(7, 9) })
	for i in 9:
		s2.step({})
	_ok(is_equal_approx(float(s2.me.hp), float(s2.me.max_hp) - OsrsTune.value("slam_dmg")), "the centre columns are safe from the west and both-sides slams")
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
	s4.boss.rip_cd = 1
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
		print("  run %2d: %-4s %3.0f s  dealt %4.0f  taken %3.0f  prayed %d/%d  dodged %d hit %d  sigils %d" % [i, r.how, r.secs, r.boss_dmg, r.taken,
			r.blocked, int(r.blocked) + int(r.unblocked), r.dodged, r.struck, r.sigils])
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
