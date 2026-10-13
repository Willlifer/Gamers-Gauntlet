extends SceneTree
## Headless: bot vs bot. The ARAM duel over every champion pairing (matches
## end, first to 3), the boss pit as 3v3 (the boss dies, a team takes it,
## how often by smite), and replays with the same seed give the same state
## hash. Prints win rates and lengths. Exit 0 when every check passes.
##   [RUNS=n] godot --headless --path . --script res://tools/moba_probe.gd

const MAX_TIME := 420.0

var fails := 0


func _initialize() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 4
	_duels(runs)
	_pits(runs * 4)
	for mode in ["duel", "pit"]:
		var h1 := _replay(mode, 777)
		var h2 := _replay(mode, 777)
		if h1 != h2:
			fails += 1
			print("FAIL %s replay diverged" % mode)
	print("moba probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _duels(runs: int) -> void:
	var wins := {}
	var games := {}
	var lengths: Array = []
	var seed := 10
	for a in MobaChamps.ORDER:
		for b in MobaChamps.ORDER:
			for i in runs:
				seed += 1
				var s := MobaSim.new(seed)
				var ua := s.add_champ(a, "blue", a)
				var ub := s.add_champ(b, "red", b)
				var bots := { ua.id: MobaBot.new(0.6, seed * 3), ub.id: MobaBot.new(0.6, seed * 7) }
				_run(s, bots)
				games[a] = int(games.get(a, 0)) + 1
				games[b] = int(games.get(b, 0)) + 1
				if s.winner == "":
					fails += 1
					print("FAIL duel %s vs %s seed %d never ended (score %s)" % [a, b, seed, s.score])
					continue
				lengths.append(s.time)
				var w: String = a if s.winner == "blue" else b
				wins[w] = int(wins.get(w, 0)) + 1
	lengths.sort()
	if not lengths.is_empty():
		print("duel: %d matches, median %.0f s (min %.0f, max %.0f)" % [lengths.size(), lengths[lengths.size() / 2], lengths[0], lengths[-1]])
	for c in MobaChamps.ORDER:
		print("  %-7s win %3.0f%%" % [c, 100.0 * int(wins.get(c, 0)) / maxi(1, int(games.get(c, 0)))])


func _pits(n: int) -> void:
	var lengths: Array = []
	var smites := 0
	var blue := 0
	var deaths := 0
	for i in n:
		var seed := 500 + i
		var s := _pit(seed)
		_run(s, s.get_meta("bots"))
		if s.winner == "":
			fails += 1
			print("FAIL pit seed %d never ended (boss hp %.0f)" % [seed, s.boss().hp])
			continue
		lengths.append(s.time)
		if s.get_meta("how", "") == "smite":
			smites += 1
		if s.winner == "blue":
			blue += 1
		deaths += int(s.score.blue) + int(s.score.red)
	lengths.sort()
	if not lengths.is_empty():
		print("pit: %d fights, median %.0f s (min %.0f, max %.0f); smite took it %d%%; blue won %d%%; %.1f champion kills a fight" % [lengths.size(),
			lengths[lengths.size() / 2], lengths[0], lengths[-1], 100 * smites / lengths.size(), 100 * blue / lengths.size(),
			float(deaths) / lengths.size()])


func _pit(seed: int) -> MobaSim:
	var s := MobaSim.new(seed, "pit")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	s.add_boss()
	var bots := {}
	for team in ["blue", "red"]:
		for k in 3:
			var c := s.add_champ(MobaChamps.ORDER[rng.randi() % 3], team, "%s%d" % [team, k])
			bots[c.id] = MobaBot.new(0.6, seed * 11 + k * 3 + (0 if team == "blue" else 1))
	s.set_meta("bots", bots)
	return s


func _run(s: MobaSim, bots: Dictionary) -> void:
	while s.winner == "" and s.time < MAX_TIME:
		var orders := {}
		for id in bots:
			orders[id] = (bots[id] as MobaBot).think(s, s.unit(id))
		for e in s.step(orders):
			if e.type == "win":
				s.set_meta("how", str(e.get("how", "")))


func _replay(mode: String, seed: int) -> int:
	var s: MobaSim
	var bots := {}
	if mode == "pit":
		s = _pit(seed)
		bots = s.get_meta("bots")
	else:
		s = MobaSim.new(seed)
		var a := s.add_champ("merr", "blue", "a")
		var b := s.add_champ("braves", "red", "b")
		bots = { a.id: MobaBot.new(0.6, seed * 3), b.id: MobaBot.new(0.6, seed * 7) }
	_run(s, bots)
	return s.state_hash()
