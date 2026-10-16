extends SceneTree
## Headless checks for Planet of Tanks (G46, MmoTankFight):
##   - the cannon blast: aimed at the closest warrior or paladin; each extra
##     body caught raises everyone's damage (cannon_stack); the announcer calls it
##   - treadburn on both sides spares only the 20-degree wedges fore and aft
##   - the smokescreen is thick at its front, thin behind it, and spreads
##   - Loose Cannon waits loose_wobble s, then burns the middle, not the rim;
##     the flanks take flank_mult after it
##   - the phases: Loose Cannon at 75%, the ram (twice) at 50%, two light
##     tanks at 25%, everything faster at 10%
##   - bot raids of eight end at a sane length; grades; replay
##   [RUNS=n] godot --headless --path . --script res://tools/mmo_tanks_probe.gd

var fails := 0


func _initialize() -> void:
	MmoTune.use_defaults()
	_cannon()
	_treads()
	_smoke()
	_loose()
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 6
	_raids(runs)
	if _replay(777) != _replay(777):
		_fail("replay diverged")
	print("mmo tanks probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _fail(t: String) -> void:
	fails += 1
	print("FAIL ", t)


func _ok(c: bool, t: String) -> void:
	if not c:
		_fail(t)


func _raid(seed: int) -> MmoSim:
	return MmoModule.build_seats(seed, [], MmoModule.RAID_SIZE, "tank")


func _cls(s: MmoSim, c: String) -> MmoUnit:
	for u: MmoUnit in s.players():
		if u.cls == c:
			return u
	return null


## Park everyone away, pulled, nothing else going on.
func _quiet(s: MmoSim) -> void:
	s.pulled = true
	s.pull_time = s.time
	s.next_spell_at = INF
	s.tank.cannon_wait = INF
	var k := 0
	for u: MmoUnit in s.players():
		u.pos = Vector2(sin(k * 0.3 - 1.0), cos(k * 0.3 - 1.0)) * 20.0       # south, out of the way
		k += 1


func _run(s: MmoSim, secs: float) -> Array:
	var ev: Array = []
	var n := int(secs / MmoSim.TICK)
	for i in n:
		ev.append_array(s.step({}))
	return ev


func _cannon() -> void:
	for n in [1, 3]:
		var s := _raid(5)
		_quiet(s)
		var w := _cls(s, "warrior")
		w.pos = Vector2(0, -6)
		var mage := _cls(s, "mage")
		var priest := _cls(s, "priest")
		if n == 3:
			mage.pos = Vector2(1, -8)
			priest.pos = Vector2(-1, -9)
		_ok(s.tank.catcher() == w, "the cannon picks the closest warrior or paladin")
		s.tank.cannon_wait = 0.0
		var hp0 := w.hp
		var ev := _run(s, MmoTune.value("cannon_warn") + 0.3)
		var took := hp0 - w.hp
		var want: float = MmoTune.value("cannon_dmg") * (1.0 + MmoTune.value("cannon_stack") * (n - 1)) * float(MmoClasses.CLASSES.warrior.armor)
		_ok(absf(took - want) < 2.0, "cannon on %d: the warrior takes %.0f (want %.0f)" % [n, took, want])
		var called := ev.any(func(e: Dictionary) -> bool: return e.type == "announce")
		_ok(called == (n >= 2), "the announcer calls a multi-hit (n=%d, called %s)" % [n, called])
		print("cannon on %d: %.0f each" % [n, took])


func _treads() -> void:
	var s := _raid(6)
	_quiet(s)
	s.boss.yaw = 0.0                                  # nose to +Z
	s.tank._begin("treadburn")
	while (s.spell.sides as Array).size() < 2:          # roll until both treads go
		s.spell = {}
		s.areas.clear()
		s.tank._begin("treadburn")
	var b := s.boss
	var safe := [b.forward() * 10.0, -b.forward() * 10.0, b.forward().rotated(0.12) * 12.0]
	var hit := [b.right() * 10.0, -b.right() * 10.0, b.forward().rotated(0.35) * 10.0, -b.forward().rotated(-0.4) * 14.0]
	for p: Vector2 in safe:
		_ok(not s.danger_at(p, 0.0), "both treads: %s (fore / aft) is safe" % p)
	for p: Vector2 in hit:
		_ok(s.danger_at(p, 0.0), "both treads: %s is in the dust" % p)
	var pr := _cls(s, "priest")
	pr.pos = b.right() * 8.0
	var pa := _cls(s, "paladin")
	pa.pos = b.forward() * 8.0
	var h_pr := pr.hp
	var h_pa := pa.hp
	_run(s, MmoTune.value("tread_warn") + 0.4)
	_ok(pr.hp < h_pr - 1000.0 and pa.hp >= h_pa, "treadburn: the flank burns (%d), the nose doesn't (%d)" % [h_pr - pr.hp, h_pa - pa.hp])


func _smoke() -> void:
	var s := _raid(7)
	_quiet(s)
	s.tank._begin("smoke")
	_run(s, 1.6)
	_ok(not s.tank.smoke.is_empty(), "the smokescreen is out")
	_run(s, 8.0)
	var sm: Dictionary = s.tank.smoke
	var c: Vector2 = sm.c
	_ok(s.players().any(func(p: MmoUnit) -> bool: return p.pos.distance_to(c) < 0.01), "smoke: a grenade on a raider's spot (G47)")
	var r := float(sm.r)
	var front := s.tank.smoke_at(c + Vector2(r - 1.0, 0))
	var core := s.tank.smoke_at(c)
	var out := s.tank.smoke_at(c + Vector2(r + 1.0, 0))
	print("smoke at 8 s: r %.1f, front %.2f, middle %.2f, outside %.2f" % [r, front, core, out])
	_ok(front > 0.9 and core < 0.4 and out == 0.0, "smoke: thick front, thin middle, nothing ahead")
	_ok(r > 15.0, "smoke: it spreads (%.1f m in 8 s)" % r)
	var u := _cls(s, "mage")
	u.pos = c + Vector2(r - 1.0, 0)
	_run(s, 0.1)
	_ok(u.mod("speed") < 0.7 and u.mod("dmg") < 0.7, "smoke slows and cuts damage in the front")


func _loose() -> void:
	var s := _raid(8)
	_quiet(s)
	var inner := _cls(s, "rogue")
	inner.pos = Vector2(0, 7)
	var outer := _cls(s, "hunter")
	outer.pos = Vector2(0, -23)
	var h0 := inner.hp
	s.tank._begin("loose")
	_run(s, MmoTune.value("loose_wobble") - 0.2)
	_ok(inner.hp == h0, "Loose Cannon: nothing during the wobble")
	var ho := outer.hp
	_run(s, MmoTune.value("loose_dur") + 1.5)
	_ok(not inner.alive or inner.hp < h0 - 2000.0, "Loose Cannon: the middle is shredded")
	_ok(outer.hp == ho, "Loose Cannon: the rim is safe")
	_ok(s.tank.flank_open, "Loose Cannon opens the flanks")
	# flank damage
	var r := _cls(s, "warrior")
	r.alive = true
	r.hp = r.max_hp
	s.boss.yaw = 0.0
	r.pos = s.boss.right() * 4.0
	var bh := s.boss.hp
	s.rng.seed = 1
	s.damage(r, s.boss, 1000.0, "phys", "test", "dot")
	var side := bh - s.boss.hp
	r.pos = s.boss.forward() * -4.0
	bh = s.boss.hp
	s.damage(r, s.boss, 1000.0, "phys", "test", "dot")
	var tail := bh - s.boss.hp
	_ok(side > tail * 1.3, "the flanks take more after Loose Cannon (%.0f vs %.0f)" % [side, tail])


func _raids(runs: int) -> void:
	var wins := 0
	var lens: Array = []
	var specials := {}
	var phases := {}
	var adds_dead := 0
	var multi := 0
	var grades := {}
	for i in runs:
		var s := _raid(300 + i * 11)
		var bots := {}
		for p: MmoUnit in s.players():
			bots[p.id] = MmoBot.new(2000 + i * 17 + bots.size(), 1.0)
		var seen := {}
		while s.winner == "" and s.time < 900.0:
			var orders := {}
			for id: String in bots:
				orders[id] = (bots[id] as MmoBot).think(s, s.unit(id))
			for e: Dictionary in s.step(orders):
				if e.type == "boss_spell" and e.stage == "cast" and e.spell != "cannon":
					specials[e.spell] = int(specials.get(e.spell, 0)) + 1
					if e.spell in ["loose", "ram"] and not seen.has(e.spell):
						seen[e.spell] = s.boss.hp_pct()
				if e.type == "announce":
					multi += 1
				if e.type == "death" and str(e.id).begins_with("light_tank"):
					adds_dead += 1
		for k in [75, 50, 25, 10]:
			if s.tank._done.has(k):
				phases[k] = int(phases.get(k, 0)) + 1
		if s.winner == "raid":
			wins += 1
		lens.append(s.time - s.pull_time)
		var deaths := 0
		for p: MmoUnit in s.players():
			deaths += p.deaths
			var g := MmoGrade.grade(s, p)
			if not grades.has(p.cls):
				grades[p.cls] = []
			grades[p.cls].append(float(g.score))
		print("raid %d: %s in %d s, boss %d%%, deaths %d, first Loose Cannon at %s, first ram at %s" % [i, s.winner, int(s.time - s.pull_time),
			int(s.boss.hp_pct() * 100.0), deaths, seen.get("loose", "-"), seen.get("ram", "-")])
	var mean := 0.0
	for l: float in lens:
		mean += l / lens.size()
	print("raids: %d / %d kills, mean %d s; specials %s; phases reached %s; light tanks killed %d; multi-hit calls %d" % [wins, runs, int(mean), specials, phases, adds_dead, multi])
	for c: String in grades:
		var a: Array = grades[c]
		var m := 0.0
		for v: float in a:
			m += v / a.size()
		print("  %-8s grade %.1f %s" % [c, m, MmoGrade.letter_for(m)])
	_ok(wins >= int(ceil(runs * 0.6)), "bots kill the tank most of the time (%d / %d)" % [wins, runs])
	_ok(mean > 90.0 and mean < 420.0, "a sane fight length (%d s)" % int(mean))
	for k in ["barrage", "smoke", "treadburn", "loose", "ram"]:
		_ok(specials.has(k), "%s happened" % k)


func _replay(seed: int) -> int:
	var s := _raid(seed)
	var bots := {}
	for p: MmoUnit in s.players():
		bots[p.id] = MmoBot.new(seed + bots.size(), 1.0)
	for i in 3000:
		var orders := {}
		for id: String in bots:
			orders[id] = (bots[id] as MmoBot).think(s, s.unit(id))
		s.step(orders)
	return s.state_hash()
