extends SceneTree
## Headless: runs whole evenings with bots only (4 and 8 players), through
## the bracket, the bets and the module simulations, and checks the maths.
##   godot --headless --path . --script res://tools/tourney_probe.gd
## Exit 0 when every check passes.

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", what)


func _initialize() -> void:
	_registry()
	for n in [4, 5, 8]:
		_evening(n)
	print("tourney probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


## G66: the lazy table agrees with every module's info(), every row loads,
## ids are unique, and naming the shell's scripts compiles no game.
func _registry() -> void:
	var bad := TourneyModules.check()
	_ok(bad == "", "TourneyModules rows match info(): " + bad)
	var ids := {}
	for e: Dictionary in TourneyModules.POOL + TourneyModules.SHELVED:
		_ok(not ids.has(e.id), "id %s once" % e.id)
		ids[e.id] = true
		_ok(TourneyModules.script_for(str(e.id)) is GDScript, "%s loads" % e.id)
		var look: Array = TourneyModules.look_of(str(e.id))
		_ok(look.size() < 3 or ResourceLoader.exists(str(look[2])), "%s logo exists" % e.id)
	_ok(TourneyModules.infos().size() == TourneyModules.POOL.size(), "infos() is the pool")
	_ok(TourneyModules.script_for("nope") == null and TourneyModules.name_of("nope") == "nope", "unknown id")
	_ok(TourneyModules.look_of("mmo_tanks")[2] == MmoTanksModule.LOGO, "the tanks tile wears the module's logo")


func _evening(n: int) -> void:
	var st := TourneyState.new()
	st.rng.seed = n * 17
	for i in n:
		st.add_bot()
	_ok(st.players.size() == n, "%d seated" % n)
	st.bracket = TourneyBracket.new()
	st.bracket.build(st.players.map(func(p): return str(p.id)), st.rng)
	var pool := TourneyModules.infos().map(func(i): return str(i.id))
	for m in st.bracket.matches:
		m.game = pool[st.rng.randi() % pool.size()]
	var played := 0
	var guard := 0
	while not st.bracket.done() and guard < 40:
		guard += 1
		st.hand_out_coins()
		var ready := st.bracket.ready()
		_ok(not ready.is_empty(), "%dp: a ready match exists (guard %d)" % [n, guard])
		if ready.is_empty():
			break
		var m: Dictionary = ready[0]
		var coins_before: int = st.players.reduce(func(a, p): return a + p.coins, 0)
		for p in st.players:
			if st.rng.randf() < 0.7:
				st.place_bet(m.id, p.id, m.p1 if st.rng.randf() < 0.5 else m.p2, [5, 10, 25][st.rng.randi() % 3])
		var cfg := { "id": m.id, "seed": st.rng.randi(), "players": [st.player(m.p1), st.player(m.p2)] }
		var r: Dictionary = TourneyModules.script_for(m.game).simulate(cfg, st.rng)
		_ok(r.winner == m.p1 or r.winner == m.p2, "%dp: winner is a competitor" % n)
		st.bracket.report(m.id, r.winner)
		var pay: Dictionary = st.settle(m.id, r.winner)
		var coins_after: int = st.players.reduce(func(a, p): return a + p.coins, 0)
		var paid: int = pay.values().reduce(func(a, b): return a + b, 0) if not pay.is_empty() else 0
		var staked: int = st.bets.get(m.id, {}).values().reduce(func(a, b): return a + b.amount, 0) if st.bets.has(m.id) else 0
		_ok(paid <= staked + TourneyState.HOUSE_PER_SIDE * 2, "%dp: payout within the pot" % n)
		_ok(coins_after == coins_before - staked + paid, "%dp: coins add up" % n)
		played += 1
	_ok(st.bracket.done(), "%dp: bracket finished (%d matches)" % [n, played])
	var expect: Array = { 4: [5, 6], 5: [5, 11], 8: [11, 14] }[n]
	_ok(played >= expect[0] and played <= expect[1], "%dp: %d matches played (expected %s)" % [n, played, expect])
	_ok(st.player(st.bracket.champion).losses <= 1, "%dp: champion lost at most once" % n)
	for m in st.bracket.matches:
		_ok(m.state == "done", "%dp: match %s done" % [n, m.id])
