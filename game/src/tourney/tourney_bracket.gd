class_name TourneyBracket
extends RefCounted
## Double elimination for 4 to 8 players (padded to 4 or 8 with byes).
## A match: { id, bracket: "w" | "l" | "gf", round, slot, p1, p2, game, winner,
## loser, state }, where p1 / p2 are player ids once known, and `feeds`
## says where each side comes from: { from: match id, take: "winner" | "loser" }.
## A bye is a player id "" on one side: it resolves itself.

var matches: Array = []
var order: Array = []        # match ids in layout order (top-left first)
var size := 4
var champion := ""


func build(player_ids: Array, rng: RandomNumberGenerator) -> void:
	var ids := player_ids.duplicate()
	size = 4 if ids.size() <= 4 else 8
	while ids.size() < size:
		ids.append("")
	# the visible roll: shuffle, byes spread so no one gets two
	ids.shuffle()
	for i in range(1, size, 2):
		if ids[i] == "" and ids[i - 1] == "":
			var j := ids.find(ids.filter(func(x): return x != "")[0])
			ids[i] = ids[j]
			ids[j] = ""
	matches = []
	if size == 4:
		_m("w1a", "w", 1, 0, ids[0], ids[1])
		_m("w1b", "w", 1, 1, ids[2], ids[3])
		_m("w2", "w", 2, 0, "", "", { "from": "w1a", "take": "winner" }, { "from": "w1b", "take": "winner" })
		_m("l1", "l", 1, 0, "", "", { "from": "w1a", "take": "loser" }, { "from": "w1b", "take": "loser" })
		_m("l2", "l", 2, 0, "", "", { "from": "w2", "take": "loser" }, { "from": "l1", "take": "winner" })
		_m("gf", "gf", 3, 0, "", "", { "from": "w2", "take": "winner" }, { "from": "l2", "take": "winner" })
	else:
		for k in 4:
			_m("w1%s" % "abcd"[k], "w", 1, k, ids[k * 2], ids[k * 2 + 1])
		_m("w2a", "w", 2, 0, "", "", { "from": "w1a", "take": "winner" }, { "from": "w1b", "take": "winner" })
		_m("w2b", "w", 2, 1, "", "", { "from": "w1c", "take": "winner" }, { "from": "w1d", "take": "winner" })
		_m("w3", "w", 3, 0, "", "", { "from": "w2a", "take": "winner" }, { "from": "w2b", "take": "winner" })
		_m("l1a", "l", 1, 0, "", "", { "from": "w1a", "take": "loser" }, { "from": "w1b", "take": "loser" })
		_m("l1b", "l", 1, 1, "", "", { "from": "w1c", "take": "loser" }, { "from": "w1d", "take": "loser" })
		_m("l2a", "l", 2, 0, "", "", { "from": "w2b", "take": "loser" }, { "from": "l1a", "take": "winner" })
		_m("l2b", "l", 2, 1, "", "", { "from": "w2a", "take": "loser" }, { "from": "l1b", "take": "winner" })
		_m("l3", "l", 3, 0, "", "", { "from": "l2a", "take": "winner" }, { "from": "l2b", "take": "winner" })
		_m("l4", "l", 4, 0, "", "", { "from": "w3", "take": "loser" }, { "from": "l3", "take": "winner" })
		_m("gf", "gf", 4, 0, "", "", { "from": "w3", "take": "winner" }, { "from": "l4", "take": "winner" })
	order = matches.map(func(m): return m.id)
	_resolve_byes()


func _m(id: String, br: String, round: int, slot: int, p1: String, p2: String, f1: Dictionary = {}, f2: Dictionary = {}) -> void:
	matches.append({ "id": id, "bracket": br, "round": round, "slot": slot, "p1": p1, "p2": p2,
		"feed1": f1, "feed2": f2, "game": "", "winner": "", "loser": "", "state": "waiting", "bye": false })


func get_match(id: String) -> Dictionary:
	for m in matches:
		if m.id == id:
			return m
	return {}


## Matches whose two players are known and that haven't been played.
func ready() -> Array:
	return matches.filter(func(m): return m.state == "ready")


func pending() -> Array:
	return matches.filter(func(m): return m.state != "done")


func done() -> bool:
	return champion != ""


func report(id: String, winner: String) -> void:
	var m := get_match(id)
	if m.is_empty() or m.state == "done":
		return
	m.winner = winner
	m.loser = m.p2 if winner == m.p1 else m.p1
	m.state = "done"
	if m.bracket == "gf":
		champion = winner
	_propagate()


## Fill in every side whose feeder is done; byes resolve themselves.
func _propagate() -> void:
	var changed := true
	while changed:
		changed = false
		for m in matches:
			if m.state == "done":
				continue
			for side in ["1", "2"]:
				if m["p" + side] != "":
					continue
				var f: Dictionary = m["feed" + side]
				if f.is_empty():
					continue
				var src := get_match(str(f.from))
				if src.state == "done":
					var who: String = src[str(f.take)]
					if who == "" and f.take == "loser" and src.bye:
						who = "bye"     # a bye's loser is nobody
					m["p" + side] = who
					changed = true
			if m.state != "done":
				var a: String = m.p1
				var b: String = m.p2
				if a != "" and b != "":
					if a == "bye" or b == "bye":
						m.bye = true
						m.winner = b if a == "bye" else a
						m.loser = ""
						m.state = "done"
						if m.bracket == "gf":
							champion = m.winner
						changed = true
					else:
						m.state = "ready"


func _resolve_byes() -> void:
	for m in matches:
		if m.round == 1 and m.bracket == "w":
			if m.p1 == "" or m.p2 == "":
				m.bye = true
				m.winner = m.p2 if m.p1 == "" else m.p1
				m.loser = ""
				m.state = "done"
				m.p1 = m.winner
				m.p2 = "bye"
			else:
				m.state = "ready"
	_propagate()


## The next matches after this one that a win or loss leads to (for the zoom).
func next_of(id: String) -> Array:
	var out: Array = []
	for m in matches:
		for side in ["feed1", "feed2"]:
			if str(m[side].get("from", "")) == id:
				out.append(m)
	return out


static func label(m: Dictionary) -> String:
	match m.bracket:
		"w": return "Winners round %d" % m.round
		"l": return "Losers round %d" % m.round
	return "Grand final"
