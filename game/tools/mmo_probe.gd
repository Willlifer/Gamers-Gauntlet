extends SceneTree
## Headless checks for the MMO raid (G22):
##   - every class's 8 abilities go off in a set-up situation (no errors)
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
	_themes()
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


## A raid of eight bots (G39): one of each class, then a second warrior and paladin.
func _raid(seed: int) -> MmoSim:
	return MmoModule.build_seats(seed, [])


# ------------------------------------------------------------- abilities

func _abilities() -> void:
	var ok := 0
	for c: String in MmoClasses.ORDER:
		var abs: Array = MmoClasses.abilities(c)
		if abs.size() != MmoClasses.SLOTS:
			_fail("%s has %d abilities, not %d" % [c, abs.size(), MmoClasses.SLOTS])
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
			if kind == "self":
				for f: Dictionary in ab.fx:
					if f.has("cleanse"):
						s.add_aura(u, { "id": "burning", "name": "Burning", "src": "boss", "dur": 6.0, "debuff": true, "cleanse": true })
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


## G41: each class's kit carries its theme, and the new effects work.
func _themes() -> void:
	var count := func(c: String, test: Callable) -> int:
		var n := 0
		for ab: Dictionary in MmoClasses.abilities(c):
			for f: Dictionary in ab.fx:
				if test.call(f):
					n += 1
					break
		return n
	var want := {
		"warrior": [func(f: Dictionary) -> bool: return str(f.get("dir", "")) == "target", 2, "charges"],
		"paladin": [func(f: Dictionary) -> bool: return f.has("group_heal") or f.has("group_hot"), 3, "group heals"],
		"priest": [func(f: Dictionary) -> bool: return f.has("hot") or f.has("group_hot") or f.has("dot") or f.has("foe_dot"), 4, "over-time spells"],
		"mage": [func(f: Dictionary) -> bool: return f.has("dot"), 3, "DoTs"],
		"hunter": [func(f: Dictionary) -> bool: return f.has("dash"), 3, "moves"],
		"rogue": [func(f: Dictionary) -> bool: return f.has("dash"), 3, "moves"],
	}
	for c: String in want:
		var n: int = count.call(c, want[c][0])
		if n < int(want[c][1]):
			_fail("%s has %d %s (want %d)" % [c, n, want[c][2], want[c][1]])
	# a charge lands in melee from 20 m; Renew on the Giant is Shadow Word: Pain; Vampiric Embrace dots the Giant
	var s := _raid(7)
	var b := s.boss
	s._pull()
	s.next_spell_at = INF
	var w: MmoUnit
	var pr: MmoUnit
	for p: MmoUnit in s.players():
		if p.cls == "warrior" and not w:
			w = p
		if p.cls == "priest" and not pr:
			pr = p
	w.pos = b.pos + Vector2(0, b.radius + 20.0)
	w.yaw = atan2(b.pos.x - w.pos.x, b.pos.y - w.pos.y)
	w.res = w.res_max
	w.target = b.id
	s.try_cast(w, "shield_slam")
	if s.dist(w, b) > MmoClasses.MELEE:
		_fail("Shield Charge didn't reach melee (%.1f m)" % s.dist(w, b))
	pr.pos = b.pos + Vector2(b.radius + 15.0, 0)
	pr.yaw = atan2(b.pos.x - pr.pos.x, b.pos.y - pr.pos.y)
	pr.target = b.id
	s.try_cast(pr, "renew")
	if b.aura("sw_pain_%s" % pr.id).is_empty():
		_fail("Renew on the Giant laid no Shadow Word: Pain")
	pr.cd.clear()
	pr.gcd = 0.0
	var ve_ok := s.try_cast(pr, "vampiric_embrace")
	var ve_err: Array = s._events.filter(func(e: Dictionary) -> bool: return e.type == "error").map(func(e: Dictionary) -> String: return str(e.text))
	for i in 45:
		s.step({})
	if not ve_ok:
		_fail("Vampiric Embrace didn't go: %s" % [ve_err])
	if b.aura("vampiric_embrace_%s" % pr.id).is_empty():
		_fail("Vampiric Embrace laid no DoT on the Giant")
	print("themes: checked")


# ------------------------------------------------------------- mechanics

func _mechanics() -> void:
	# bombs: all stacked -> everyone takes splash; spread -> only their own
	for spread in [false, true]:
		var s := _raid(5)
		s._pull()
		var ps := s.players()
		for i in ps.size():
			var p: MmoUnit = ps[i]
			p.pos = Vector2(4, 12) if not spread else Vector2(sin(TAU * i / ps.size()), cos(TAU * i / ps.size())) * 17.0
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
					p.pos = Vector2(sin(TAU * i / ps.size()), cos(TAU * i / ps.size())) * 17.0
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
		(ps[i] as MmoUnit).pos = Vector2(sin(TAU * i / ps.size()), cos(TAU * i / ps.size())) * 20.0
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
	if (r.branded as Dictionary).size() != s.players().size():
		_fail("brand: %d of %d branded" % [(r.branded as Dictionary).size(), s.players().size()])
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
	var grade_c := {}
	var seats_c := {}
	var parts_c := {}
	var grades: Array = []
	var frenzy_gaps: Array = []
	var on_own := 0
	var late_warns := 0
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
			var was_silent := s.silent
			for e: Dictionary in s.step(orders):
				if e.type == "warn" and (was_silent or s.silent):
					if e.get("always", false):
						on_own += 1
					else:
						late_warns += 1
				if (e.type == "dmg" or e.type == "heal") and str(e.src) != "boss" and str(e.src) != "":
					var key := "%s %s" % [s.unit(str(e.src)).cls, e.what]
					_by[key] = float(_by.get(key, 0.0)) + float(e.get("eff", e.n))
				if e.type == "boss_spell" and e.stage == "cast":
					if s.frenzied:
						frenzy_gaps.append(s.time - last_end)
					if s.time - last_end < s.spell_gap_now() - 0.05:
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
			seats_c[p.cls] = int(seats_c.get(p.cls, 0)) + 1
			totals[p.cls] = float(totals.get(p.cls, 0.0)) + p.dmg_done + p.heal_done
			fails_c[p.cls] = int(fails_c.get(p.cls, 0)) + p.fails
			deaths_c[p.cls] = int(deaths_c.get(p.cls, 0)) + p.deaths
			var g := MmoGrade.grade(s, p)
			grade_c[p.cls] = float(grade_c.get(p.cls, 0.0)) + float(g.score)
			for part in MmoGrade.PARTS:
				var k: String = p.cls + "." + str(part)
				parts_c[k] = float(parts_c.get(k, 0.0)) + float(g.parts[part])
			if float(g.score) < 0.0 or float(g.score) > 100.0:
				_fail("grade out of range: %s %.1f" % [p.cls, g.score])
		print("raid %d: %s in %.0f s, Giant at %.0f%%" % [i, s.winner, s.time - s.pull_time, s.boss.hp_pct() * 100.0])
	var avg := 0.0
	for l: float in lens:
		avg += l
	avg /= maxf(1.0, lens.size())
	print("raids: %d / %d kills, mean %.0f s" % [wins, runs, avg])
	for c: String in MmoClasses.ORDER:
		var n_c := float(seats_c[c])
		print("  %-8s score/seat %7.0f  par %5.0f/s (table %3.0f)  fails/seat %.1f  deaths/seat %.1f" % [c, float(totals[c]) / n_c, float(totals[c]) / n_c / avg,
			float(MmoClasses.PAR[c]), float(fails_c[c]) / n_c, float(deaths_c[c]) / n_c])
		var gs := float(grade_c[c]) / n_c
		var line := "  %-8s grade %5.1f %s  " % [c, gs, MmoGrade.letter_for(gs)]
		for part in MmoGrade.PARTS:
			line += " %s %.2f" % [part.substr(0, 4), float(parts_c[c + "." + part]) / n_c]
		print(line)
		grades.append(gs)
	# the grade is fair across classes: a bot of every class lands within 8 points of the others
	grades.sort()
	if not grades.is_empty() and grades[-1] - grades[0] > 8.0:
		_fail("bot grades spread %.1f points across classes (> 8)" % (grades[-1] - grades[0]))
	# G37: Scorched Earth burns the half it marked, hurts there and nowhere else, and turns counter-clockwise
	var sc := _raid(9090)
	var sb := {}
	for p: MmoUnit in sc.players():
		sb[p.id] = MmoBot.new(9090 + sb.size(), 1.0)
	var warned := false
	var ang_live := 0.0
	var hurt_safe := false
	var spun := false
	while sc.winner == "" and sc.time < 900.0:
		var orders := {}
		for id: String in sb:
			orders[id] = (sb[id] as MmoBot).think(sc, sc.unit(id))
		var before := {}
		for p: MmoUnit in sc.living():
			before[p.id] = [p.hp, sc.in_scorch(p.pos)]
		for e: Dictionary in sc.step(orders):
			if e.type == "scorch" and e.stage == "warn":
				warned = true
			if e.type == "scorch" and e.stage == "live":
				ang_live = float(sc.scorch.ang)
			if e.type == "dmg" and str(e.what) == "Scorched Earth" and before.has(str(e.tgt)) and not before[str(e.tgt)][1] and not sc.in_scorch(sc.unit(str(e.tgt)).pos):
				hurt_safe = true
		if not spun and not sc.scorch.is_empty() and sc.scorch.spinning and sc.time - sc.pull_time > MmoTune.value("scorch_spin_at") + 5.0:
			spun = true
			var turned := angle_difference(ang_live, float(sc.scorch.ang))
			print("  G37: turned %.0f deg in the first %.0f s of spin (negative = counter-clockwise from above)" % [rad_to_deg(turned), sc.time - sc.pull_time - MmoTune.value("scorch_spin_at")])
			if turned >= 0.0:
				_fail("Scorched Earth turned the wrong way")
	var burnt := 0.0
	for p: MmoUnit in sc.players():
		burnt += p.scorch_t
	# G40: the fire turns in bursts (15 s), holds (30 s); bombs leave burning ground about half the time
	var gr := _raid(7171)
	var gb := {}
	for p: MmoUnit in gr.players():
		gb[p.id] = MmoBot.new(7171 + gb.size(), 1.0)
	var at := {}
	var pools := 0
	var bombs := 0
	var on := MmoTune.value("scorch_spin_at")
	var marks := [on + 2.0, on + 12.0, on + MmoTune.value("scorch_spin_on") + 3.0, on + MmoTune.value("scorch_spin_on") + 25.0]
	while gr.winner == "" and gr.time < 900.0:
		var orders := {}
		for id: String in gb:
			orders[id] = (gb[id] as MmoBot).think(gr, gr.unit(id))
		for e: Dictionary in gr.step(orders):
			if e.type == "explode" and str(e.what) == "bomb":
				bombs += 1
			if e.type == "area" and str(e.area.get("look", "")) == "fire_pool":
				pools += 1
		var el := gr.time - gr.pull_time
		for m in marks:
			if not at.has(m) and el >= float(m) and not gr.scorch.is_empty():
				at[m] = float(gr.scorch.ang)
	if at.size() == 4:
		var turning := absf(angle_difference(float(at[marks[0]]), float(at[marks[1]])))
		var resting := absf(angle_difference(float(at[marks[2]]), float(at[marks[3]])))
		print("  G40: turned %.0f deg in 10 s of a burst, %.1f deg in 22 s of rest" % [rad_to_deg(turning), rad_to_deg(resting)])
		if turning < deg_to_rad(30.0) or resting > 0.001:
			_fail("Scorched Earth doesn't turn in bursts")
	print("  G40: %d of %d bombs left burning ground" % [pools, bombs])
	if bombs >= 8 and (pools == 0 or pools == bombs):
		_fail("burning ground isn't a coin flip per bomb")
	print("  G37: warned %s, raid %s in %.0f s, %.1f raider-seconds in the fire" % [warned, sc.winner, sc.time - sc.pull_time, burnt])
	if not warned:
		_fail("Scorched Earth never warned")
	if hurt_safe:
		_fail("Scorched Earth hurt someone outside it")
	if sc.time - sc.pull_time > MmoTune.value("scorch_spin_at") + 5.0 and not spun:
		_fail("Scorched Earth never turned")
	# G35: one "You're on your own now." per raid at half health, no warnings after it; the rotation doubles at a quarter
	if on_own != runs:
		_fail("\"You're on your own now.\" came %d times in %d raids" % [on_own, runs])
	if late_warns > 0:
		_fail("%d text warnings after the Giant went quiet" % late_warns)
	var fg := 0.0
	for g: float in frenzy_gaps:
		fg += g
	print("  G35: %d raids quiet from 50%%; %d spells under frenzy, mean gap %.1f s (normal %.1f)" % [on_own, frenzy_gaps.size(), fg / maxf(1.0, frenzy_gaps.size()), MmoTune.value("spell_gap")])
	if frenzy_gaps.is_empty() or fg / frenzy_gaps.size() > MmoTune.value("spell_gap") * 0.75:
		_fail("the rotation didn't speed up below 25%")
	# the letter decides first, then the score
	if not MmoGrade.beats({ "rank": 1, "score": 86.0 }, { "rank": 2, "score": 99.0 }) or MmoGrade.beats({ "rank": 1, "score": 86.0 }, { "rank": 1, "score": 90.0 }):
		_fail("MmoGrade.beats: the letter first, then the score")
	# a contestant who stands there doing nothing grades low
	var idle := _raid(4242)
	var ib := {}
	for p: MmoUnit in idle.players():
		if p != idle.players()[0]:
			ib[p.id] = MmoBot.new(4242 + ib.size(), 1.0)
	while idle.winner == "" and idle.time < 900.0:
		var orders := {}
		for id: String in ib:
			orders[id] = (ib[id] as MmoBot).think(idle, idle.unit(id))
		idle.step(orders)
	var gi := MmoGrade.grade(idle, idle.players()[0])
	print("  idle seat grades %.1f %s" % [gi.score, gi.letter])
	if float(gi.score) >= MmoTune.value("grade_c"):
		_fail("an idle contestant graded %.1f (should be under C)" % gi.score)
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
