extends SceneTree
## Headless: bot vs bot over every champion pairing. Checks that matches end
## (first to 3), that a replay with the same seed gives the same state hash,
## and prints win rates and match length. Exit 0 when every check passes.
##   [RUNS=n] godot --headless --path . --script res://tools/moba_probe.gd

const MAX_TIME := 420.0

var fails := 0


func _initialize() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 4
	var wins := {}
	var games := {}
	var lengths: Array = []
	var seed := 10
	for a in MobaChamps.ORDER:
		for b in MobaChamps.ORDER:
			for i in runs:
				seed += 1
				var r := _match(a, b, seed)
				games[a] = int(games.get(a, 0)) + 1
				games[b] = int(games.get(b, 0)) + 1
				if r.winner == "":
					fails += 1
					print("FAIL %s vs %s seed %d never ended (score %s)" % [a, b, seed, r.score])
					continue
				lengths.append(r.time)
				var w: String = a if r.winner == "blue" else b
				wins[w] = int(wins.get(w, 0)) + 1
	# determinism: the same match twice
	var h1 := _match("merr", "braves", 777)
	var h2 := _match("merr", "braves", 777)
	if h1.hash != h2.hash:
		fails += 1
		print("FAIL replay diverged")
	lengths.sort()
	if not lengths.is_empty():
		print("matches %d, median %.0f s (min %.0f, max %.0f)" % [lengths.size(), lengths[lengths.size() / 2], lengths[0], lengths[-1]])
	for c in MobaChamps.ORDER:
		print("  %-7s win %3.0f%%" % [c, 100.0 * int(wins.get(c, 0)) / maxi(1, int(games.get(c, 0)))])
	print("moba probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _match(a: String, b: String, seed: int) -> Dictionary:
	var s := MobaSim.new(seed)
	var ua := s.add_champ(a, "blue", a)
	var ub := s.add_champ(b, "red", b)
	var ba := MobaBot.new(0.6, seed * 3)
	var bb := MobaBot.new(0.6, seed * 7)
	while s.winner == "" and s.time < MAX_TIME:
		s.step({ ua.id: ba.think(s, ua), ub.id: bb.think(s, ub) })
	return { "winner": s.winner, "time": s.time, "score": s.score, "hash": s.state_hash() }
