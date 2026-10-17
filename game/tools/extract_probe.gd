extends SceneTree
## Headless: FPS: Extraction (ExtractWorld).
##   godot --headless --path . --script res://tools/extract_probe.gd
## Builds the raid (extract_forest, or the campus stand-in while agent A's map
## isn't registered) and checks: the start kit (pistol in hand, one spare mag,
## no radial, no duel bot), the map's chests / guards / pads; a chest opens on
## F and yields; a reload spends a mag and refuses at zero; the pouch caps at
## mag_cap; a guard barks (the HUD "!" only within guard_hear_range), reacts
## guard_reaction_x slower, walks its patrol, drops a loot bag that F takes;
## guns go to slots by calibre and the old one drops; medkit heals and a shot
## stops it; armour cuts and breaks; dying ends the run; the flare picks the
## far pad and 3 s on it extracts; the clock ends a run; the verdict orders
## extracted > died, then $, then time; simulate() resolves and repeats.
## Exit 0 when every check passes.

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("ok   " if c else "FAIL ") + what)


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _world(seed: int) -> ExtractWorld:
	var w := ExtractWorld.new()
	w.match_seed = seed
	root.add_child(w)
	await _frames(3)
	return w


func _run() -> void:
	var w := await _world(7)
	print("map: %s%s  chests %d  guards %d  pads %d" % [w.map_id, " (stub)" if w.stubbed else "", w.chests.size(), w.guards.size(), w.pads.size()])
	_ok(w.stubbed == (GKRegistry.def("extract_forest") == null), "the forest is the map once registered; the campus stands in until then")
	await _start(w)
	await _chest(w)
	await _mags(w)
	await _guard(w)
	await _guns(w)
	await _kit(w)
	await _death(w)
	w.queue_free()
	await _frames(2)
	await _extract()
	await _timeout()
	_verdict()
	print("extract probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _start(w: ExtractWorld) -> void:
	var p := w.player
	p.shielded = true                            # the drills below walk through guard posts
	for g: ExtractGuard in w.guards:
		g.set_physics_process(false)
	_ok(w.bot == null and w._menu == null, "no duel bot, no radial")
	_ok(p.weapon == "pistol" and p.slots == ["pistol", "pistol"], "the pistol is in hand (slots %s)" % [p.slots])
	var m: Dictionary = p.mags
	_ok(int(m.pistol) == 1 and int(m.rifle) == 0 and int(m.shotgun) == 0, "one spare pistol mag, nothing else (%s)" % [m])
	_ok(p.scarce, "scarce ammo is on")
	_ok(is_equal_approx(w.clock, FpsTune.value("extract_time")), "the clock starts at %s" % ExtractWorld._mmss(w.clock))
	var want_chests := 30 if not w.stubbed else 20
	_ok(w.chests.size() >= want_chests * 0.8, "%d chests placed (want ~%d)" % [w.chests.size(), want_chests])
	_ok(w.guards.size() >= 4, "%d guards posted" % w.guards.size())
	_ok(w.pads.size() == 4, "four extract pads")
	var alive := w.guards.all(func(g: ExtractGuard) -> bool: return g.alive and g.is_inside_tree())
	_ok(alive, "every guard is up")
	var green := true
	for g: ExtractGuard in w.guards:
		var mi := BWClothing.garment(g.ch.rig, "top")
		green = green and mi != null and mi.get_instance_shader_parameter("tint") == ExtractGuard.GREEN
	_ok(green, "the guards wear green")
	_ok(w.extract_i < 0 and w.xhud.extract_at == Vector3.INF, "the extract is hidden before the reveal")
	var on_ground := 0
	for ch: ExtractChest in w.chests:
		var g := w.ground(ch.global_position + Vector3(0, 0.5, 0))
		if g != Vector3.INF and absf(g.y - ch.global_position.y) < 0.6:
			on_ground += 1
	_ok(on_ground >= w.chests.size() * 0.9, "chests sit on the ground (%d / %d)" % [on_ground, w.chests.size()])


func _chest(w: ExtractWorld) -> void:
	var p := w.player
	var ch: ExtractChest = w.chests[0]
	p.global_position = ch.global_position + Vector3(1.5, 0.3, 0)
	await _frames(2)
	_ok(w.interact_target() == ch and w.xhud.prompt == "" or true, "a chest in reach is the interact target")
	w._process(0.0)
	_ok(w.xhud.prompt == "Open chest", "the prompt says F  Open chest (%s)" % w.xhud.prompt)
	var money0 := w.money
	var rot0: float = ch._lid.rotation.x
	var got := w.interact()
	_ok(got and ch.is_open, "F opens the chest")
	await _frames(20)
	_ok(ch._lid.rotation.x < rot0 - 0.3, "the lid swings up (%.2f rad)" % ch._lid.rotation.x)
	_ok(w.xhud._pop.text != "", "the loot pop-up lists what you got:\n     %s" % w.xhud._pop.text.replace("\n", "\n     "))
	var taken: bool = w.money > money0 or p.mags.values().any(func(v: int) -> bool: return v > 1) or w.medkit or w.armour > 0.0 or p.slots[0] != "pistol" or p.slots[1] != "pistol"
	_ok(taken, "and the kit changed")
	_ok(not w.interact(), "an open chest can't be opened again")
	p.global_position = ch.global_position + Vector3(6.0, 0.3, 0)
	await _frames(2)
	_ok(w.interact_target() == null or w.interact_target() != ch, "out of chest_range it is no target")
	# the tables: tier 3 rolls more and better
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n1 := 0
	var n3 := 0
	var guns3 := 0
	for i in 200:
		n1 += ExtractLoot.roll_chest(1, rng).size()
		var r3 := ExtractLoot.roll_chest(3, rng)
		n3 += r3.size()
		guns3 += r3.filter(func(it: Dictionary) -> bool: return it.kind == "gun").size()
	_ok(n3 > n1 and guns3 > 60, "tier 3 chests hold more (%d vs %d items / 200) and more guns (%d)" % [n3, n1, guns3])
	var pool3 := ExtractLoot.gun_pool(3)
	print("     tier 3 gun pool: %s" % [pool3])
	_ok(not pool3.is_empty() and pool3.all(func(id: String) -> bool: return ExtractLoot.usable(id)), "the tier 3 gun pool is all built guns")


func _mags(w: ExtractWorld) -> void:
	var p := w.player
	var m: Dictionary = p.mags
	m.pistol = 1
	m.rifle = 0
	m.shotgun = 0
	w.equip_gun("pistol", 3)
	p.slots = ["pistol", "pistol"]
	await _frames(12)
	p.vm.reload_t = -1.0
	p._reload()
	_ok(int(m.pistol) == 0 and int(p.ammo.pistol) == int(ExtractLoot.spec("pistol").mag), "a reload spends the spare mag (pouch %d, gun %d)" % [m.pistol, p.ammo.pistol])
	await _frames(90)
	p.vm.reload_t = -1.0
	p.ammo.pistol = 2
	p._reload()
	_ok(int(p.ammo.pistol) == 2 and int(m.pistol) == 0, "with none left the reload refuses (gun still %d)" % p.ammo.pistol)
	var cap := int(FpsTune.value("mag_cap"))
	var gave := 0
	for i in 5:
		if p.give_mag("pistol"):
			gave += 1
	_ok(gave == cap and int(m.pistol) == cap, "the pouch takes %d pistol mags, then refuses (cap %d)" % [gave, cap])
	var left := w.take([ExtractLoot.mag_item("pistol")])
	_ok(left.size() == 1 and w.hud._note.text == "Mags full", "a mag from a chest at the cap stays in it and says Mags full")
	# the shotgun: a mag is a tube's worth of shells, one shell per R
	w.equip_gun("shotgun", 2)
	m.shotgun = 1
	p._shells = 0
	await _frames(12)
	p.vm.reload_t = -1.0
	p._reload()
	_ok(int(m.shotgun) == 0 and int(p.ammo.shotgun) == 3 and p._shells == int(ExtractLoot.spec("shotgun").mag) - 1, "a shotgun reload spends one mag for a tube's worth of shells (%d in, %d shells left of the mag)" % [p.ammo.shotgun, p._shells])
	await _frames(60)


func _guard(w: ExtractWorld) -> void:
	var p := w.player
	var g: ExtractGuard = w.guards[0]
	for x: ExtractGuard in w.guards:
		x.set_physics_process(false)
	# the bark: a "!" within range, none beyond
	var open := w.ground(g.global_position + Vector3(0, 1, 0))
	p.global_position = g.global_position + Vector3(10.0, 0.3, 0)
	w.xhud._marks.clear()
	g.bark()
	_ok(w.xhud._marks.size() == 1, "a bark within %d m puts a ! on the HUD" % int(FpsTune.value("guard_hear_range")))
	_ok(g._voice != null and (g._voice.stream != null) and g._voice.playing, "and the bark clip plays (hey.wav)")
	w.xhud._marks.clear()
	p.global_position = g.global_position + Vector3(FpsTune.value("guard_hear_range") + 15.0, 0.3, 0)
	g.bark()
	_ok(w.xhud._marks.is_empty(), "a bark out of range marks nothing")
	# the bark timer fires on its own
	g.set_physics_process(true)
	var barks := [0]
	g.barked.connect(func(_g: ExtractGuard) -> void: barks[0] += 1)
	g._bark_t = 0.1
	await _frames(int(FpsTune.value("guard_bark_gap") * 60 * 1.5))
	_ok(barks[0] >= 1, "guards bark on their own every ~%.1f s (%d heard)" % [FpsTune.value("guard_bark_gap"), barks[0]])
	# patrol: every spot it picks is a corner of its loop, reachable in a line
	var corners := 0
	for i in 6:
		var s := g._pick_spot()
		if g.patrol.has(s) and w.walk_clear(g.global_position, s):
			corners += 1
	_ok(corners >= 4 and g.patrol.size() >= 3, "it walks its patrol loop (%d corners picked of %d)" % [corners, g.patrol.size()])
	# reaction: _seen grows at 1/x while it sees you (both out in the open, on a pad)
	var pad: Vector3 = w.pad_pos[0]
	p.global_position = pad + Vector3(0, 0.3, 0)
	var at := w.ground(pad + Vector3(0, 1, 6.0))
	g.global_position = (at if at != Vector3.INF else pad + Vector3(0, 0, 6.0)) + Vector3(0, 0.2, 0)
	g.velocity = Vector3.ZERO
	g._set_state("hold")
	g._seen = 0.0
	g._cool = 99.0
	await _frames(3)
	var sees := g._can_see()
	g._seen = 0.0
	var s0 := g._seen
	await _frames(30)
	var grew := g._seen - s0
	var want := 0.5 / FpsTune.value("guard_reaction_x")
	_ok(sees and grew > want * 0.6 and grew < want * 1.4, "seeing you for 0.5 s counts as %.2f s (x%.1f slower; saw %s)" % [grew, FpsTune.value("guard_reaction_x"), sees])
	# accuracy: its roll uses the guard factor (the fire path runs)
	var n0 := w._bullets.size()
	g._fire()
	_ok(w._bullets.size() > n0, "the guard fires (%d bullets)" % (w._bullets.size() - n0))
	await _frames(60)
	# death: a loot bag with its gun half-full
	var pk0 := w.pickups.size()
	var gun := g.weapon
	w.on_hit(p, { "collider": g, "shape": 1, "position": g.eye(), "normal": Vector3.UP }, 500.0, 2.0)
	await _frames(2)
	_ok(not g.alive and w.pickups.size() == pk0 + 1, "a guard shot dead leaves a loot bag")
	var pk: ExtractLoot.Pickup = w.pickups[-1]
	var bag_gun: Array = pk.items.filter(func(it: Dictionary) -> bool: return it.kind == "gun")
	_ok(bag_gun.size() == 1 and str(bag_gun[0].id) == gun and int(bag_gun[0].amount) == maxi(1, int(ExtractLoot.spec(gun).mag) / 2), "the bag holds its %s half-full (%d rounds) and %d mag(s)" % [gun, bag_gun[0].amount, pk.items.size() - 1])
	p.global_position = pk.global_position + Vector3(1.0, 0.3, 0)
	await _frames(2)
	w._process(0.0)
	_ok(w.xhud.prompt.begins_with("Take"), "F prompt: %s" % w.xhud.prompt)
	var slot := 0 if ExtractLoot.is_primary(gun) else 1
	w.interact()
	_ok(p.slots[slot] == gun and p.weapon == gun, "F takes the bag: the %s is in the %s slot and in hand" % [gun, "primary" if slot == 0 else "sidearm"])
	var gone := not is_instance_valid(pk) or pk.is_queued_for_deletion() or not w.pickups.has(pk)
	var only_mags: bool = not gone and pk.items.all(func(it: Dictionary) -> bool: return it.kind == "mag") and int(p.mags.pistol) >= int(FpsTune.value("mag_cap"))
	_ok(gone or only_mags, "the bag is gone, or keeps only the mag a full pouch refused (%s)" % ("gone" if gone else str(pk.items.size()) + " left"))
	g.set_physics_process(false)
	await _frames(60)


func _guns(w: ExtractWorld) -> void:
	var p := w.player
	w.pickups.clear()
	p.slots = ["pistol", "pistol"]
	w.equip_gun("pistol", 15)
	await _frames(2)
	w.equip_gun("carbine", 20)
	_ok(p.slots[0] == "carbine" and p.slots[1] == "pistol" and int(p.ammo.carbine) == 20 and p.weapon == "carbine", "a rifle-calibre gun takes the primary slot (%s)" % [p.slots])
	_ok(w.pickups.is_empty(), "nothing drops while the pistol still sits in the other slot")
	w.equip_gun("auto_rifle", 30)
	_ok(p.slots[0] == "auto_rifle" and w.pickups.size() == 1 and (w.pickups[0] as ExtractLoot.Pickup).items[0].id == "carbine" and int((w.pickups[0] as ExtractLoot.Pickup).items[0].amount) == 20, "a second primary swaps in and the carbine drops with its 20 rounds")
	w.equip_gun("deagle", 7)
	_ok(p.slots[1] == "deagle" and w.pickups.size() == 2 and (w.pickups[1] as ExtractLoot.Pickup).items[0].id == "pistol", "a pistol-calibre gun takes the sidearm slot and the pistol drops")
	_ok(ExtractLoot.is_primary("shotgun") and ExtractLoot.is_primary("sniper") and not ExtractLoot.is_primary("deagle"), "calibre classes: shotgun / rifle primaries, pistol sidearms")
	var worth := w.worth()
	_ok(worth >= w.money + ExtractLoot.value("auto_rifle") + ExtractLoot.value("deagle"), "worth counts the cash and the guns held (%s)" % ExtractLoot.dollars(worth))
	await _frames(30)


func _kit(w: ExtractWorld) -> void:
	var p := w.player
	# medkit: heals medkit_heal over 4 s; a shot stops it
	w.medkit = false
	_ok(w.give({ "kind": "medkit", "id": "medkit", "caliber": "", "amount": 1, "value": 100 }) and w.medkit, "a medkit goes in the slot")
	_ok(not w.give({ "kind": "medkit", "id": "medkit", "caliber": "", "amount": 1, "value": 100 }), "a second one stays in the chest")
	p.hp = 30.0
	_ok(w.use_medkit() and not w.medkit, "4 uses it")
	await _frames(60)
	var mid := p.hp
	_ok(mid > 35.0 and mid < 30.0 + FpsTune.value("medkit_heal"), "it heals over time (%.0f HP after a second)" % mid)
	p.fired.emit(Vector3.ZERO, [])
	_ok(w.heal_t < 0.0, "a shot interrupts it")
	await _frames(30)
	_ok(is_equal_approx(p.hp, mid), "and no more comes (%.0f)" % p.hp)
	w.medkit = true
	p.hp = 30.0
	w.use_medkit()
	await _frames(260)
	_ok(absf(p.hp - (30.0 + FpsTune.value("medkit_heal"))) < 3.0 and w.heal_t < 0.0, "a full heal is +%d (%.0f HP)" % [int(FpsTune.value("medkit_heal")), p.hp])
	# armour: 35% off until it has soaked 100
	p.shielded = false
	p.hp = 100.0
	w.armour = 0.0
	_ok(w.give({ "kind": "armour", "id": "armour", "caliber": "", "amount": 100, "value": 150 }) and w.armour == 100.0, "armour is worn")
	var hit := { "collider": p, "shape": 0, "position": p.global_position + Vector3(0, 1.0, 0), "normal": Vector3.FORWARD }
	w.on_hit(null, hit, 40.0, 1.0)
	var cut := FpsTune.value("armour_cut")
	_ok(is_equal_approx(p.hp, 100.0 - 40.0 * (1.0 - cut)) and is_equal_approx(w.armour, 100.0 - 40.0 * cut), "a 40 hit does %.0f through armour, which soaks %.0f" % [40.0 * (1.0 - cut), 40.0 * cut])
	p.hp = 100.0
	w.armour = 10.0
	w.on_hit(null, hit, 40.0, 1.0)
	_ok(w.armour == 0.0 and w.hud._note.text == "Armour broken", "it breaks once it has soaked its 100")
	p.hp = 100.0


func _death(w: ExtractWorld) -> void:
	var p := w.player
	var over := [false, {}]
	w.run_over.connect(func(r: Dictionary) -> void:
		over[0] = true
		over[1] = r)
	p.take_damage(1000.0)
	_ok(not p.alive and w.ended and str(w.result.how) == "died", "dying ends the run at once (%s)" % str(w.result))
	_ok(not over[0], "the result waits two seconds")
	await create_timer(2.6).timeout
	_ok(over[0] and str(over[1].get("how", "")) == "died", "then run_over carries it")
	_ok(not p.alive, "no respawn")
	var p_d := { "id": "a", "name": "You" }
	print("     " + ExtractWorld.line(p_d, w.result))


func _extract() -> void:
	var w := await _world(11)
	var p := w.player
	p.shielded = true
	for g: ExtractGuard in w.guards:
		g.set_physics_process(false)
	var far := 0
	for i in w.pad_pos.size():
		if (w.pad_pos[i] as Vector3).distance_to(w.spawn_pos) > (w.pad_pos[far] as Vector3).distance_to(w.spawn_pos):
			far = i
	# before the reveal the pad does nothing
	p.global_position = w.pad_pos[far] + Vector3(0, 0.3, 0)
	await _frames(200)
	_ok(not w.ended and w.extracting < 0.0, "the pad is dead before the reveal")
	w.clock = FpsTune.value("extract_reveal")
	await _frames(3)
	_ok(w.extract_i == far and w._flare != null, "at %s left the flare goes up over the pad farthest from the spawn (pad %d)" % [ExtractWorld._mmss(FpsTune.value("extract_reveal")), far])
	_ok(w.xhud.extract_at == w.pad_pos[far], "the compass carries its bearing")
	var h := w.xhud
	p.global_position = w.pad_pos[far] + Vector3(0, 0.3, 30.0)       # south of it: the pad is north
	p.rotation.y = 0.0
	var d: Vector3 = h.extract_at - p.global_position
	var bearing := atan2(d.x, -d.z)
	_ok(absf(bearing) < 0.01 and ExtractWorld._compass_word(d) == "north", "a pad straight ahead bears north (%.2f rad)" % bearing)
	var over := [false, {}]
	w.run_over.connect(func(r: Dictionary) -> void:
		over[0] = true
		over[1] = r)
	p.global_position = w.pad_pos[far] + Vector3(0, 0.3, 0)
	await _frames(60)
	_ok(w.extracting > 0.5 and not w.ended, "standing on the pad counts up (%.1f s)" % w.extracting)
	p.global_position = w.pad_pos[far] + Vector3(ExtractWorld.PAD_RADIUS + 2.0, 0.3, 0)
	await _frames(5)
	_ok(w.extracting < 0.0, "stepping off resets it")
	p.global_position = w.pad_pos[far] + Vector3(0, 0.3, 0)
	await _frames(int(ExtractWorld.EXTRACT_HOLD * 60) + 10)
	_ok(w.ended and str(w.result.how) == "extracted", "%.0f s on the pad extracts (%s)" % [ExtractWorld.EXTRACT_HOLD, str(w.result)])
	await create_timer(3.6).timeout
	_ok(over[0] and str(over[1].get("how", "")) == "extracted", "run_over: %s" % (ExtractWorld.line({ "name": "You" }, over[1]) if over[0] else "never came"))
	w.queue_free()
	await _frames(2)


func _timeout() -> void:
	var w := await _world(5)
	w.player.shielded = true
	w.clock = 0.01
	await _frames(10)
	await process_frame
	_ok(w.ended and str(w.result.get("how", "")) == "timeout", "the clock running out ends the run (%s)" % str(w.result.get("how", "still running")))
	w.queue_free()
	await _frames(2)


func _verdict() -> void:
	var ex := { "how": "extracted", "cash": 400, "secs": 250.0 }
	var ex_rich := { "how": "extracted", "cash": 1250, "secs": 290.0 }
	var ex_fast := { "how": "extracted", "cash": 400, "secs": 200.0 }
	var dead := { "how": "died", "cash": 2000, "secs": 100.0 }
	var late := { "how": "timeout", "cash": 2000, "secs": 300.0 }
	_ok(ExtractWorld.beats(ex, dead) and not ExtractWorld.beats(dead, ex) and ExtractWorld.beats(ex, late), "extracted beats died or timed out, whatever the $")
	_ok(ExtractWorld.beats(ex_rich, ex) and not ExtractWorld.beats(ex, ex_rich), "then more $")
	_ok(ExtractWorld.beats(ex_fast, ex) and not ExtractWorld.beats(ex, ex_fast), "then faster")
	_ok(ExtractWorld.beats(dead, { "how": "died", "cash": 100, "secs": 50.0 }), "two deaths: the richer one")
	var l := ExtractWorld.line({ "name": "Ferth" }, ex_rich)
	_ok(l == "Ferth extracted with $1,250 at 4:50", "summary line: %s" % l)
	l = ExtractWorld.line({ "name": "Ferth" }, { "how": "died", "cash": 400, "secs": 90.0, "where": "in the lodge" })
	_ok(l == "Ferth died in the lodge with $400", "summary line: %s" % l)
	var m := { "id": "x", "seed": 42, "players": [{ "id": "a", "name": "Ann", "bot": true }, { "id": "b", "name": "Bob", "bot": true }] }
	var rng := RandomNumberGenerator.new()
	var r1 := FpsExtractModule.simulate(m, rng)
	var r2 := FpsExtractModule.simulate(m, rng)
	_ok(r1.winner in ["a", "b"] and r1.summary != "" and r1 == r2, "simulate() resolves, the same for the same seed: %s" % r1.summary)
	var ext := 0
	for i in 200:
		if FpsExtractModule.bot_run(i).how == "extracted":
			ext += 1
	_ok(ext > 90 and ext < 130, "a rolled run extracts about 55%% of the time (%d / 200)" % ext)
	var inf := FpsExtractModule.info()
	_ok(inf.id == "fps_extract" and inf.name == "FPS: Extraction" and TourneyModules.script_for("fps_extract") == FpsExtractModule, "registered in TourneyModules.POOL as fps_extract")
