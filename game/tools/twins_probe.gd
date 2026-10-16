extends SceneTree
## The tournament's Twins fight setup (G50): each of the three carries its two
## elements (both offered on every element skill, at one rank) and its two
## weapons (the first drawn, the second carried and swappable); fire opens
## every cycle; the build is deterministic; the fight plays to an end with the
## AI on both sides (the AI draws carried weapons too). Exit 0 when all hold.
##   godot --headless --path . --script res://tools/twins_probe.gd

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	for seed_value in [1, 7, 12345, 99991]:
		var f := BWFightModule.build_fight(seed_value)
		var players: Array = f.players
		_check(players.size() == BWFightModule.KITS.size(), "three units")
		for i in players.size():
			var u: BWUnit = players[i]
			var kit: Dictionary = BWFightModule.KITS[i]
			_check(u.element == str(kit.elements[0]), "%s native %s" % [kit.role, u.element])
			_check(u.attuned_elements() == kit.elements, "%s elements %s" % [kit.role, u.attuned_elements()])
			_check(u.affinity_rank(kit.elements[0]) == u.affinity_rank(kit.elements[1]), "%s ranks equal" % kit.role)
			_check(u.weapon_class == str(kit.weapons[0]), "%s draws %s" % [kit.role, u.weapon_class])
			_check(str(u.second_weapon().get("weight", "")) == str(kit.weapons[1]), "%s carries %s" % [kit.role, u.second_weapon().get("weight", "")])
			if seed_value == 1:
				print("%-8s %-8s elements %s  weapons %s / %s (%s / %s)  spd %d..%d" % [kit.role, u.name, u.attuned_elements(),
					u.weapon_class, u.second_weapon().weight, u.weapon_model, u.second_weapon().base,
					BWFightModule.speed_span(u, true), BWFightModule.speed_span(u)])
		var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % BWRun.TWINS_MAP), seed_value)
		b.setup(players, f.enemies)
		var fire: BWUnit = players[BWFightModule.FIRST]
		_check(b.current() == fire, "fire opens cycle 1 (got %s)" % (b.current().name if b.current() else "none"))
		if seed_value == 1:
			print("cycle 1 order: ", b.queue.map(func(u): return "%s(%s,%d)" % [u.name, u.element, u.speed()]))
		# every element skill offers both elements; the swap is open and draws the other class
		for i in players.size():
			var u: BWUnit = players[i]
			var kit: Dictionary = BWFightModule.KITS[i]
			for s in b.skills_for(u) if u == b.current() else []:
				if s.needs_element:
					_check(Array(s.elements) == kit.elements, "%s %s offers %s" % [kit.role, s.key, s.elements])
		_check(b.can_swap(fire), "fire can swap")
		b.swap_weapon(fire)
		_check(fire.weapon_class == "staff" and b.skills_for(fire).any(func(s): return s.needs_element), "fire swapped to the staff with element skills")
		b.swap_weapon(fire)
		_check(fire.weapon_class == "lance", "fire swaps back")
		# determinism: the same seed builds the same units
		var g := BWFightModule.build_fight(seed_value)
		for i in players.size():
			_check(JSON.stringify(g.players[i].to_dict()) == JSON.stringify(BWFightModule.build_fight(seed_value).players[i].to_dict()), "deterministic build")
		# the whole fight on autopilot: fire first every cycle; it ends
		var h := BWFightModule.build_fight(seed_value)
		var b2 := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % BWRun.TWINS_MAP), seed_value)
		b2.setup(h.players, h.enemies)
		var hfire: BWUnit = h.players[BWFightModule.FIRST]
		var swaps := 0
		var els := {}
		b2.event.connect(func(e):
			if str(e.get("type", "")) == "swap":
				swaps += 1
			if str(e.get("type", "")) in ["skill", "cast"] and str(e.get("element", "")) != "":
				els[str(e.element)] = true)
		var last_cycle := 0
		var guard := 0
		while not b2.over and guard < 2000:
			if b2.cycle != last_cycle:
				last_cycle = b2.cycle
				if hfire.alive():
					_check(b2.queue[0] == hfire, "fire first in cycle %d" % b2.cycle)
			BWAI.take_turn(b2)
			guard += 1
		_check(b2.over, "seed %d: the fight ends" % seed_value)
		print("seed %d: over=%s winner=%s cycles=%d swaps=%d elements used=%s" % [seed_value, b2.over, b2.winner if "winner" in b2 else "?", b2.cycle, swaps, els.keys()])
	print("twins probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)
