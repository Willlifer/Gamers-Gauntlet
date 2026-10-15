extends SceneTree
## Headless checks for the MMO raid (G22):
##   - every class's 16 abilities go off in a set-up situation (no errors)
##   - each Giant mechanic does what it says (bombs hurt the stacked,
##     the ring spares the grouped, cracks and meteors hit who stands in them)
##   - the Giant never starts a spell sooner than spell_gap after the last ended
##   - bot raids end (the Giant dies or the raid wipes) at a sane length
##   - Cinderbrand (G30): lands on all six; left alone it deals brand_pct of
##     max HP over brand_dur; a cleanse takes it off; running burns it down
##   - the same seed replays to the same state
##   [RUNS=n] godot --headless --path . --script res://tools/mmo_probe.gd

var fails := 0
var _by := {}


func _initialize() -> void:
	MmoTune.use_defaults()
	_abilities()
	_mechanics()
	_brand()
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 6
	_raids(runs)
	if _replay(4242) != _replay(4242):
		_fail("replay diverged")
	print("mmo probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _fail(t: String) -> void:
	fails += 1
	print("FAIL ", t)


func _raid(seed: int) -> MmoSim:
	var s := MmoSim.new(seed)
	s.add_boss()
	for c: String in MmoClasses.ORDER:
		s.add_player(c, c)
	return s


# ------------------------------------------------------------- abilities

func _abilities() -> void:
	var ok := 0
	for c: String in MmoClasses.ORDER:
		var abs: Array = MmoClasses.abilities(c)
		if abs.size() != MmoClasses.SLOTS:
			_fail("%s has %d abilities, not 16" % [c, abs.size()])
		for ab: Dictionary in abs:
			var s := _raid(1)
			var u: MmoUnit
			for p: MmoUnit in s.players():
				if p.cls == c:
					u = p
			var b := s.boss
			s._pull()
			s.next_spell_at = INF
			u.pos = b.pos + Vector2(0, b.radius + u.radius + 2.0)
			u.yaw = atan2(b.pos.x - u.pos.x, b.pos.y - u.pos.y)
			u.res = u.res_max
			u.target = b.id
			var kind := str(ab.get("tgt", ""))
			if ab.get("behind", false):
				u.pos = b.pos - b.forward() * (b.radius + u.radius + 1.0)
				u.yaw = atan2(b.pos.x - u.pos.x, b.pos.y - u.pos.y)
			if ab.get("exec", false):
				b.hp = b.max_hp * 0.1
			if ab.get("finisher", false):
				u.cp = 5
			var ally: MmoUnit = s.players()[0] if s.players()[0] != u else s.players()[1]
			ally.pos = u.pos + Vector2(2, 0)
			if kind == "ally":
				ally.hp = ally.max_hp * 0.3
				u.target = ally.id
				for f: Dictionary in ab.fx:
					if f.has("cleanse"):
						s.add_aura(ally, { "id": "burning", "name": "Burning", "dur": 6.0, "debuff": true, "cleanse": true })
			if kind == "dead":
				ally.hp = 1.0
				s.damage(b, ally, 9999.0, "phys", "test", "mech")
				u.target = ally.id
			var errs: Array = []
			var hp0 := b.hp
			var ally0 := ally.hp
			var went := s.try_cast(u, str(ab.id))
			var seen := {}
			for e: Dictionary in s._events:
				seen[e.type] = true
				if e.type == "error":
					errs.append(e.text)
			var after := 0
			for i in 400:
				for e: Dictionary in s.step({}):
					if e.get("src", e.get("id", "")) == u.id or e.get("by", "") == u.id:
						seen[e.type] = true
					if e.type == "error" and e.id == u.id:
						errs.append(e.text)
				if not u.casting():
					after += 1
					if after > 60:
						break
			if not went or not errs.is_empty():
				_fail("%s %s: went=%s %s" % [c, ab.id, went, errs])
				continue
			if kind == "dead" and not ally.alive:
				_fail("%s %s didn't raise the ally" % [c, ab.id])
				continue
			var did := b.hp < hp0 or ally.hp > ally0
			for k in ["dmg", "heal", "aura", "dash", "taunt", "res", "cleansed", "burst", "ground_tick", "resource"]:
				did = did or seen.has(k)
			if not did:
				_fail("%s %s had no effect" % [c, ab.id])
				continue
			ok += 1
	print("abilities: %d / %d went off" % [ok, MmoClasses.ORDER.size() * MmoClasses.SLOTS])


# ------------------------------------------------------------- mechanics

func _mechanics() -> void:
	# bombs: all stacked -> everyone takes splash; spread -> only their own
	for spread in [false, true]:
		var s := _raid(5)
		s._pull()
		var ps := s.players()
		for i in ps.size():
			var p: MmoUnit = ps[i]
			p.pos = Vector2(4, 12) if not spread else Vector2(sin(TAU * i / 6.0), cos(TAU * i / 6.0)) * 17.0
		s._bag = ["bombs"]
		s.next_spell_at = 0.0
		var t := 0.0
		var hp0 := ps.map(func(p: MmoUnit) -> float: return p.hp)
		while t < 12.0:
			s.step({})
			t += MmoSim.TICK
			for p: MmoUnit in ps:
				if spread:
					var i := ps.find(p)
					p.pos = Vector2(sin(TAU * i / 6.0), cos(TAU * i / 6.0)) * 17.0
				else:
					p.pos = Vector2(4, 12)
		var fails_n := 0
		for p: MmoUnit in ps:
			fails_n += p.fails
		if spread and fails_n > 0:
			_fail("bombs: spread players still splashed (%d)" % fails_n)
		if not spread and fails_n < 6:
			_fail("bombs: stacked players weren't splashed (%d)" % fails_n)
		print("bombs %s: %d splashes" % ["spread" if spread else "stacked", fails_n])
	# the ring: all in -> no fails; one out -> one fail
	var s := _raid(6)
	s._pull()
	s._bag = ["gather"]
	s.next_spell_at = 0.0
	var ring := Vector2.INF
	var ps := s.players()
	for i in 360:
		for e: Dictionary in s.step({}):
			if e.type == "boss_spell" and e.spell == "gather" and e.stage == "fire":
				ring = e.at
		if ring != Vector2.INF:
			for p: MmoUnit in ps:
				p.pos = ring if p != ps[0] else ring + Vector2(12, 0)
	var outs := 0
	for p: MmoUnit in ps:
		outs += p.fails
	if outs != 1:
		_fail("ring: %d fails, expected 1 (the one outside)" % outs)
	print("ring: %d outside" % outs)


# ------------------------------------------------------------ Cinderbrand

## Players far from the Giant, no orders, nothing else cast: the burn alone.
func _brand_run(seed: int, each_tick: Callable) -> Dictionary:
	var s := _raid(seed)
	s._pull()
	var ps := s.players()
	for i in ps.size():
		(ps[i] as MmoUnit).pos = Vector2(sin(TAU * i / 6.0), cos(TAU * i / 6.0)) * 20.0
	s.next_spell_at = 0.0
	s.next_brand_at = 0.0
	var took := {}
	var branded := {}
	var t := 0.0
	while t < MmoTune.value("brand_dur") + MmoSim.SPELL_CAST.brand + 3.0:
		var orders: Dictionary = each_tick.call(s)
		for e: Dictionary in s.step(orders):
			if e.type == "dmg" and str(e.what) == "Cinderbrand":
				took[e.tgt] = float(took.get(e.tgt, 0.0)) + float(e.n)
			if e.type == "aura" and str(e.aura) == MmoSim.BRAND and e.on:
				branded[e.id] = true
		if s.spell.is_empty():
			s.next_spell_at = INF                    # nothing else this test
		t += MmoSim.TICK
	return { "sim": s, "took": took, "branded": branded }


func _brand() -> void:
	# left alone: all six branded, each takes brand_pct of max HP (rounding: ±1%)
	var r := _brand_run(31, func(_s: MmoSim) -> Dictionary: return {})
	var s: MmoSim = r.sim
	if (r.branded as Dictionary).size() != 6:
		_fail("brand: %d of 6 branded" % (r.branded as Dictionary).size())
	var worst := 0.0
	for p: MmoUnit in s.players():
		var want := p.max_hp * MmoTune.value("brand_pct")
		var got := float(r.took.get(p.id, 0.0))
		worst = maxf(worst, absf(got - want) / want)
		if absf(got - want) > want * 0.01:
			_fail("brand: %s took %.0f, want %.0f (25%% of %.0f)" % [p.cls, got, want, p.max_hp])
	print("brand left alone: 6 x %.0f%% of max HP (worst off by %.2f%%)" % [MmoTune.value("brand_pct") * 100.0, worst * 100.0])
	# running: one player runs the whole time; the brand burns off early
	var runner := ""
	r = _brand_run(32, func(sim: MmoSim) -> Dictionary:
		var w: MmoUnit = sim.players()[3]
		return { w.id: { "mv": Vector2(0, 1), "turn": 1.0 } })
	s = r.sim
	runner = (s.players()[3] as MmoUnit).id
	var ran := float(r.took.get(runner, 0.0))
	var full := (s.players()[3] as MmoUnit).max_hp * MmoTune.value("brand_pct")
	if ran > full * 0.5:
		_fail("brand: running only cut it to %.0f of %.0f" % [ran, full])
	print("brand run off: %.0f of %.0f (%.0f%%)" % [ran, full, ran / full * 100.0])
	# cleanse: the priest's Dispel Magic takes it off an ally
	s = _raid(33)
	s._pull()
	var pr: MmoUnit
	var al: MmoUnit
	for p: MmoUnit in s.players():
		if p.cls == "priest":
			pr = p
		elif p.cls == "mage":
			al = p
	s.brand(al)
	pr.target = al.id
	pr.pos = al.pos + Vector2(3, 0)
	var went := s.try_cast(pr, "dispel")
	if not went or al.has_aura(MmoSim.BRAND):
		_fail("brand: Dispel Magic didn't take it off (went=%s)" % went)
	else:
		print("brand cleansed: OK")


# ------------------------------------------------------------------ raids

func _raids(runs: int) -> void:
	var lens: Array = []
	var wins := 0
	var totals := {}
	var fails_c := {}
	var deaths_c := {}
	for i in runs:
		var s := _raid(100 + i * 7)
		var bots := {}
		for p: MmoUnit in s.players():
			bots[p.id] = MmoBot.new(1000 + i * 13 + bots.size(), 1.0)
		var last_end := -INF
		var was_busy := false
		while s.winner == "" and s.time < 900.0:
			var orders := {}
			for id: String in bots:
				orders[id] = (bots[id] as MmoBot).think(s, s.unit(id))
			for e: Dictionary in s.step(orders):
				if (e.type == "dmg" or e.type == "heal") and str(e.src) != "boss" and str(e.src) != "":
					var key := "%s %s" % [s.unit(str(e.src)).cls, e.what]
					_by[key] = float(_by.get(key, 0.0)) + float(e.get("eff", e.n))
				if e.type == "boss_spell" and e.stage == "cast":
					if s.time - last_end < MmoTune.value("spell_gap") - 0.05:
						_fail("spell %s began %.2f s after the last ended" % [e.spell, s.time - last_end])
			var busy := not s.spell.is_empty()
			if was_busy and not busy:
				last_end = s.time
			was_busy = busy
		lens.append(s.time - s.pull_time)
		if s.winner == "raid":
			wins += 1
		elif s.winner == "":
			_fail("raid %d never ended" % i)
		for p: MmoUnit in s.players():
			totals[p.cls] = float(totals.get(p.cls, 0.0)) + p.dmg_done + p.heal_done
			fails_c[p.cls] = int(fails_c.get(p.cls, 0)) + p.fails
			deaths_c[p.cls] = int(deaths_c.get(p.cls, 0)) + p.deaths
		print("raid %d: %s in %.0f s, Giant at %.0f%%" % [i, s.winner, s.time - s.pull_time, s.boss.hp_pct() * 100.0])
	var avg := 0.0
	for l: float in lens:
		avg += l
	avg /= maxf(1.0, lens.size())
	print("raids: %d / %d kills, mean %.0f s" % [wins, runs, avg])
	for c: String in MmoClasses.ORDER:
		print("  %-8s score/run %7.0f  par %5.0f/s (table %3.0f)  fails/run %.1f  deaths/run %.1f" % [c, float(totals[c]) / runs, float(totals[c]) / runs / avg,
			float(MmoClasses.PAR[c]), float(fails_c[c]) / runs, float(deaths_c[c]) / runs])
	if OS.get_environment("BREAKDOWN") != "":
		var keys := _by.keys()
		keys.sort()
		for k: String in keys:
			print("    %-34s %7.0f" % [k, float(_by[k]) / runs])
	if wins < runs / 2:
		_fail("the bots kill the Giant in fewer than half the raids")


func _replay(seed: int) -> int:
	var s := _raid(seed)
	var bots := {}
	for p: MmoUnit in s.players():
		bots[p.id] = MmoBot.new(seed + bots.size(), 1.0)
	for i in 30 * 60:
		var orders := {}
		for id: String in bots:
			orders[id] = (bots[id] as MmoBot).think(s, s.unit(id))
		s.step(orders)
	return s.state_hash()
