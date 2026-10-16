extends SceneTree
## Headless: the FPS bullets (G28) and the Dust hallway map (G29).
##   godot --headless --path . --script res://tools/fps_probe.gd
## Builds FpsWorld on each map, holds the bot still 20 m down the lane, and
## checks: bullets fly at 5x the slingshot ball (not instant), a bullet that
## meets the bot hurts it, the bot's bullet hurts you, a bullet into a wall
## hurts nobody, the trigger makes bullets, and the bot's walk area is on
## the map. G43: the sidearm roll (half Desert Eagles), the loadout, the
## semi-automatic trigger, the dual Berettas (each click its own gun, each
## its own magazine, the trick reload refills both), every built gun fires,
## and on the campus the bushes hide you from the bot. G51: the spawns follow
## the match seed; the Dust hallway's spawn pockets are hidden from the far
## half of the lane and from each other, its crates cut the long sight lines,
## and the bot only walks where a straight line is clear; the tune cfg
## migration; the bullet trail's fade; the sight pictures.
## Exit 0 when every check passes.

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("ok   " if c else "FAIL ") + what)


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	FpsWorld.ask_loadout = false
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_ok(is_equal_approx(FpsWeapons.bullet_speed(), 5.0 * float(FpsWeapons.SPECS.slingshot.ball_speed)), "bullet speed is 5x the slingshot ball (%.0f m/s)" % FpsWeapons.bullet_speed())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var eagles := 0
	for i in 2000:
		eagles += int(FpsWeapons.roll_sidearm(rng) == "deagle")
	if FpsWeapons.available("pistol") and FpsWeapons.available("deagle"):
		_ok(eagles > 900 and eagles < 1100, "the sidearm is a Desert Eagle about half the time (%d / 2000)" % eagles)
	else:
		print("skip the sidearm roll: pistol %s, deagle %s built" % [FpsWeapons.available("pistol"), FpsWeapons.available("deagle")])
	print("primaries built: %s" % [FpsWeapons.primaries()])
	_g51_static()
	var maps := ["rooftop", "dust_mid"]
	if GKRegistry.def("campus") != null:
		maps.append("campus")
	for map_id in maps:
		await _map(map_id)
	print("fps probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


## Every built gun fires through the loadout; semi-automatics once per pull;
## the duals' two triggers and their trick reload.
func _guns(w: FpsWorld) -> void:
	var p := w.player
	for id: String in FpsWeapons.primaries() + FpsWeapons.SIDEARMS:
		if not FpsWeapons.available(id) or FpsWeapons.SPECS[id].get("dual", false):
			continue
		p.set_loadout(id, "pistol")
		await _frames(12)
		var n0 := w._bullets.size()
		var a0 := int(p.ammo[id])
		p._cool = 0.0
		p._held_before = false
		p.debug_fire = true
		await _frames(30)
		p.debug_fire = false
		await _frames(2)
		var shots := a0 - int(p.ammo[id])
		var sp: Dictionary = FpsWeapons.SPECS[id]
		if sp.get("auto", false):
			_ok(shots > 3, "%s: holding the trigger keeps firing (%d shots in 0.5 s)" % [id, shots])
		elif sp.action == "slide":
			_ok(shots == 1, "%s: a semi-automatic fires once per pull (%d)" % [id, shots])
		else:
			_ok(shots >= 1, "%s fires (%d)" % [id, shots])
		_ok(w._bullets.size() > n0 or shots > 0, "%s: its bullets fly" % id)
	if not FpsWeapons.available("dual_berettas"):
		print("skip the duals: no pistol model")
		return
	p.set_loadout("dual_berettas", "pistol")
	await _frames(12)
	p._held_before = false
	p.debug_fire = true
	await _frames(3)
	p.debug_fire = false
	_ok(int(p.ammo.dual_l) == 14 and int(p.ammo.dual_r) == 15, "duals: the left click fires the left gun only (%d | %d)" % [p.ammo.dual_l, p.ammo.dual_r])
	await _frames(12)
	p._held_r_before = false
	p.debug_fire_r = true
	await _frames(3)
	p.debug_fire_r = false
	_ok(int(p.ammo.dual_l) == 14 and int(p.ammo.dual_r) == 14, "duals: the right click fires the right gun only (%d | %d)" % [p.ammo.dual_l, p.ammo.dual_r])
	p.ammo.dual_l = 0
	await _frames(12)
	p._held_before = false
	p.debug_fire = true
	await _frames(3)
	p.debug_fire = false
	_ok(p.vm.reload_t >= 0.0, "duals: an empty gun starts the trick reload")
	var flipped := false
	var mags := false
	for i in 200:
		await physics_frame
		await process_frame
		if p.vm.reload_t > 0.3 and p.vm.reload_t < 0.6 and p.vm.gun_l:
			flipped = flipped or p.vm.gun_l.transform.origin.y > p.vm.transform.origin.y - 0.05
			mags = mags or p.vm._new_mags.any(func(m: MeshInstance3D) -> bool: return m.visible)
		if p.vm.reload_t < 0.0:
			break
	_ok(flipped, "duals: the guns go up in the air")
	_ok(mags, "duals: fresh mags come up for the catch")
	_ok(p.vm.reload_t < 0.0 and int(p.ammo.dual_l) == 15 and int(p.ammo.dual_r) == 15, "duals: both guns reloaded (%d | %d)" % [p.ammo.dual_l, p.ammo.dual_r])


## G51: the Dust hallway's pockets and cover; the bot's straight-line walk.
func _dust(w: FpsWorld) -> void:
	var m := w.map
	var a: Array = []
	var b: Array = []
	for k in 4:
		if m.markers.has("spawn_a%d" % k):
			a.append(m.marker("spawn_a%d" % k).origin)
		if m.markers.has("spawn_b%d" % k):
			b.append(m.marker("spawn_b%d" % k).origin)
	_ok(a.size() == 2 and b.size() == 2, "dust_mid: two spawn pockets a side (%d, %d)" % [a.size(), b.size()])
	# eye to head between every pocket and a grid over the far 60% of the lane
	var pa: Array = m.meta.play_area
	var eye := Vector3(0, 1.98, 0)
	for side in [["a", a, b], ["b", b, a]]:
		var mine: Array = side[1]
		var seen := 0
		var looks := 0
		for sp: Vector3 in mine:
			for other: Vector3 in side[2]:
				looks += 1
				if w.trace(other + eye, sp + Vector3(0, 1.7, 0), [], 1).is_empty():
					seen += 1
		_ok(seen == 0, "dust_mid: no %s pocket can be seen from the other side's pockets (%d / %d lines open)" % [side[0], seen, looks])
		var open := 0
		var n := 0
		var zs: float = (mine[0] as Vector3).z
		for i in 9:
			for j in 30:
				var p := Vector3(lerpf(float(pa[0]) + 0.6, float(pa[2]) - 0.6, i / 8.0), 0.0, lerpf(float(pa[1]) + 0.6, float(pa[3]) - 0.6, j / 29.0))
				if absf(p.z - zs) < absf(float(pa[3]) - float(pa[1])) * 0.4:
					continue                         # the far 60% of the lane only
				var hit := w.trace(p + Vector3(0, 6.0, 0), p + Vector3(0, -1.0, 0), [], 1)
				if hit.is_empty() or hit.position.y > 1.2:
					continue                         # inside a crate / building, or the walkway (checked from the floor only)
				for sp: Vector3 in mine:
					n += 1
					if w.trace(hit.position + eye, sp + Vector3(0, 1.7, 0), [], 1).is_empty():
						open += 1
						print("     open: plan (%.1f, %.1f) sees pocket plan (%.1f, %.1f)" % [hit.position.x / 1.25, -hit.position.z / 1.25, sp.x / 1.25, -sp.z / 1.25])
		_ok(open == 0, "dust_mid: the %s pockets are hidden from the far 60%% of the lane floor (%d / %d lines open)" % [side[0], open, n])
	# the long lines: from each A pocket's exit, nothing reaches the B end down a wall
	var long := 0
	var tried := 0
	for x in [-5.0, -4.0, -3.0, -2.0, 0.0, 2.0, 3.0]:
		var from := Vector3(x * 1.25, 1.98, 3.0 * 1.25 * -1.0)
		for x2 in [-6.0, -5.0, -4.0, -3.0, -2.0, -1.0]:
			var to := Vector3(x2 * 1.25, 1.7, -40.0 * 1.25)
			if w.trace(from + Vector3(0, -1.0, 0), from, [], 1).size() > 0 or w.trace(to, to + Vector3(0, 0.5, 0), [], 1).size() > 0:
				continue
			tried += 1
			if w.trace(from, to, [], 1).is_empty():
				long += 1
				print("     open: plan x %.0f at z 3 to x %.0f at z 40" % [x, x2])
	_ok(long == 0, "dust_mid: no open sight line from the T exits (3 m) to the tower passage end (40 m): %d / %d open" % [long, tried])
	# the bot: every spot it picks is a straight, clear walk
	var bot := w.bot
	var bad := 0
	for i in 12:
		var g := bot._pick_spot()
		if g != bot.global_position and not w.walk_clear(bot.global_position, g):
			bad += 1
	_ok(bad == 0, "dust_mid: the bot only picks spots it can walk to in a line (%d bad)" % bad)
	var fresh := FpsWorld.new()
	fresh.map_id = "dust_mid"
	fresh.match_seed = 7
	root.add_child(fresh)
	await _frames(2)
	var w2 := FpsWorld.new()
	w2.map_id = "dust_mid"
	w2.match_seed = 7
	root.add_child(w2)
	await _frames(2)
	_ok(Vector2(fresh.player.global_position.x, fresh.player.global_position.z).is_equal_approx(Vector2(w2.player.global_position.x, w2.player.global_position.z)), "dust_mid: the same match seed starts you in the same pocket")
	var sides := {}
	for i in 16:
		sides[str(w2._spawn("a").origin.snapped(Vector3.ONE * 0.1))] = true
	_ok(sides.size() == 2, "dust_mid: lives start in both pockets (%d seen in 16)" % sides.size())
	fresh.queue_free()
	w2.queue_free()
	await _frames(2)
	# the probe's shots below want an open lane: stand in it
	w.player.global_position = Vector3(1.0, 0.2, -5.0 * 1.25)


## G51: the tune migration, the baked numbers, the buy-phase keys.
func _g51_static() -> void:
	var d := FpsTune.dropped_keys(1)
	_ok("run_speed" in d and "move_spread" in d and FpsTune.dropped_keys(FpsTune.VERSION).is_empty(), "tune: an old cfg drops the re-baked keys (%s), a current one nothing" % [d])
	_ok(FpsTune.value("campus_speed") == 12.0 and FpsTune.value("run_speed") < 12.0, "tune: the floaty 12 m/s is the campus default only")
	_ok(FpsTune.value("cross_gap") == 0.0 and FpsTune.value("rest_spread") < 1.0 and FpsTune.value("move_spread") > 3.0, "tune: the reticle is tighter at rest and opens wider on the run")
	_ok(is_equal_approx(FpsTune.value("sway"), 2.3) and FpsTune.value("recoil") == 3.0 and FpsTune.value("bullet_trail") == 30.0, "tune: sway 2.3, recoil 3 (the old max), 30 m trail baked in")
	var dg: Dictionary = FpsWeapons.SPECS.deagle
	for id in ["sniper", "marksman", "shotgun"]:
		_ok(float(FpsWeapons.SPECS[id].punch) >= float(dg.punch) * 0.7, "recoil: the %s kicks like the Desert Eagle (punch %.2f vs %.2f)" % [id, FpsWeapons.SPECS[id].punch, dg.punch])
	_ok(float(FpsWeapons.SPECS.carbine.recoil) >= 2.0 * 2.0 and float(FpsWeapons.SPECS.carbine.punch) > 0.24, "recoil: the carbine kicks harder than before (x2)")
	FpsBinds.reset()
	var bumped := FpsBinds.set_key("reload", KEY_W)
	_ok(bumped == "forward" and FpsBinds.key("reload") == KEY_W and FpsBinds.key("forward") == 0, "binds: a key taken from another action unbinds that one")
	FpsBinds.reset()
	_ok(FpsBinds.key("forward") == KEY_W, "binds: reset restores WASD")
	# G51b: recoil presets per gun, trimmed by a scale
	_ok(FpsTune.recoil("carbine") == FpsWeapons.baked_recoil("carbine"), "recoil presets: a gun starts on its own baked profile")
	FpsTune.set_recoil_preset("carbine", "Desert Eagle")
	_ok(is_equal_approx(float(FpsTune.recoil("carbine").punch), float(FpsWeapons.SPECS.deagle.punch)), "recoil presets: the carbine on the Desert Eagle preset kicks like it")
	FpsTune.set_recoil_scale("carbine", 0.5)
	_ok(is_equal_approx(float(FpsTune.recoil("carbine").punch), float(FpsWeapons.SPECS.deagle.punch) * 0.5) and is_equal_approx(float(FpsTune.recoil("carbine").bloom), float(FpsWeapons.SPECS.deagle.bloom)), "recoil presets: the gun's scale trims the felt kick, not the accuracy")
	_ok(FpsWeapons.RECOIL_PRESETS.size() == 6, "recoil presets: Desert Eagle, Rifle, Sniper, Shotgun, Pistol, Carbine")
	FpsTune.reset()
	_ok(FpsTune.recoil_preset("carbine") == "" and FpsTune.recoil_scale("carbine") == 1.0, "recoil presets: reset goes back to baked")


## G51 in the world: the sight pictures, the trail's fade, the pistols aimed out.
func _g51_world(w: FpsWorld) -> void:
	var p := w.player
	if FpsWeapons.available("auto_rifle"):
		p.set_loadout("auto_rifle", "pistol")
		await _frames(30)
		_ok(p.vm.lens_view != null and p.vm.lens_view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "lens: the automatic rifle's sight renders a picture")
		_ok(absf(p.vm._lens_cam.fov - p.cam.fov / 2.0) < p.cam.fov * 0.4, "lens: and it is magnified (fov %.1f vs %.1f)" % [p.vm._lens_cam.fov, p.cam.fov])
	p.set_loadout("shotgun", "pistol")
	await _frames(10)
	_ok(p.vm.lens_view == null or p.vm.lens_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "lens: a gun without a sight renders none")
	var eye := p.cam.global_position
	w.fire_bullet(eye + Vector3(0, 30, 0), Vector3.UP, p, 1.0, 1.0, 300.0, Color.WHITE, eye + Vector3(0, 30, 0))
	await _frames(3)
	var b: Dictionary = w._bullets[w._bullets.size() - 1]
	var mat := b.mat as ShaderMaterial
	_ok(mat != null and float(mat.get_shader_parameter("tail_d")) <= 0.01 and float(mat.get_shader_parameter("fade")) > 0.5, "trail: starts at the barrel, fading in over %.2f m" % float(mat.get_shader_parameter("fade")))
	_ok(float(FpsWeapons.SPECS.pistol.get("ads_dist", 0.0)) >= 0.3, "pistols: aimed in about a foot from the eye")


## Campus paintball: inside a bush, past 3 m, the bot can't see you; out of it, it can.
func _bushes(w: FpsWorld) -> void:
	_ok(not w.hide_volumes.is_empty(), "campus: the map has bushes (%d)" % w.hide_volumes.size())
	if w.hide_volumes.is_empty():
		return
	var h: Dictionary = w.hide_volumes[0]
	var c: Vector3 = h.center
	var hf: Vector3 = h.half
	_ok(w.in_bush(c) and not w.in_bush(c + Vector3(hf.x + hf.z + 2.0, 0, 0)), "campus: in_bush knows inside from outside")
	_ok(w.bush_between(c + Vector3(-hf.length() - 3.0, 0, 0).rotated(Vector3.UP, 0.0), c) > 0.5, "campus: a line into a bush runs through leaves")


func _map(map_id: String) -> void:
	var w := FpsWorld.new()
	w.map_id = map_id
	w.match_seed = 7
	root.add_child(w)
	await _frames(3)
	if map_id == "dust_mid":
		await _dust(w)
	_ok(not w.bot.roof.is_empty(), "%s: the bot has a walk area" % map_id)
	var p := w.player
	var b := w.bot
	b.set_physics_process(false)                     # held still: the probe aims
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	b.global_position = p.global_position + fwd * 20.0
	b.velocity = Vector3.ZERO
	await _frames(3)
	# a clear line: on maps with cover ahead of the spawn, try other spots
	for spot: Vector3 in [fwd * 20.0, fwd * 12.0, fwd * 8.0, fwd.rotated(Vector3.UP, 0.5) * 14.0, fwd.rotated(Vector3.UP, -0.5) * 14.0, fwd * 30.0]:
		b.global_position = p.global_position + spot
		await _frames(2)
		var look := w.trace(p.cam.global_position, b.global_position + Vector3(0, 1.1, 0), [p.get_rid()])
		if not look.is_empty() and look.collider == b:
			break
	# your bullet into the bot's chest
	var eye := p.cam.global_position
	var chest := b.global_position + Vector3(0, 1.1, 0)
	w.fire_bullet(eye, (chest - eye).normalized(), p, 40.0, 2.0, 600.0, Color.WHITE, eye)
	await _frames(1)
	_ok(is_equal_approx(b.hp, 100.0), "%s: the bullet is in flight after one tick (not hitscan)" % map_id)
	await _frames(6)
	_ok(b.hp < 100.0 and b.hp > 50.0, "%s: your bullet hit the bot (hp %.0f)" % [map_id, b.hp])
	# the bot's bullet into your chest
	var hp0 := p.hp
	var from := b.global_position + Vector3(0, 1.6, 0)
	var at := p.global_position + Vector3(0, 1.2, 0)
	w.fire_bullet(from, (at - from).normalized(), b, 34.0, 100.0 / 34.0, 300.0, Color.WHITE, from)
	await _frames(8)
	_ok(is_equal_approx(p.hp, hp0 - 34.0), "%s: the bot's bullet hit you for 34 (hp %.0f)" % [map_id, p.hp])
	# a shot at the floor hurts nobody
	var hb := b.hp
	var hp1 := p.hp
	w.fire_bullet(eye, Vector3(0, -1, 0), p, 40.0, 2.0, 600.0, Color.WHITE, eye)
	await _frames(6)
	_ok(b.hp == hb and p.hp == hp1, "%s: a bullet into the floor hurts nobody" % map_id)
	# the trigger fires bullets (the sniper: one)
	var n0 := w._bullets.size()
	p.weapon = "sniper"
	p._cool = 0.0
	p._shoot(1.0)
	_ok(w._bullets.size() == n0 + 1, "%s: the rifle's trigger makes a bullet" % map_id)
	p.weapon = "shotgun"
	p._cool = 0.0
	n0 = w._bullets.size()
	p._shoot(1.0)
	_ok(w._bullets.size() == n0 + int(FpsWeapons.SPECS.shotgun.pellets), "%s: the shotgun makes a bullet per pellet" % map_id)
	await _frames(60)
	_ok(w._bullets.is_empty(), "%s: spent bullets are cleared" % map_id)
	if map_id == "rooftop":
		await _guns(w)
		await _g51_world(w)
	_ok(w.player.run_key == ("campus_speed" if map_id == "campus" else "run_speed"), "%s: top speed from %s (the floaty max is the campus's alone)" % [map_id, w.player.run_key])
	if map_id == "campus":
		_bushes(w)
	w.queue_free()
	await _frames(2)
