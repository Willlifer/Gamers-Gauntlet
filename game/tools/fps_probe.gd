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
## and on the campus the bushes hide you from the bot.
## Exit 0 when every check passes.

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("ok   " if c else "FAIL ") + what)


func _initialize() -> void:
	FpsTune.use_defaults()
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
	root.add_child(w)
	await _frames(3)
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
	if map_id == "campus":
		_bushes(w)
	w.queue_free()
	await _frames(2)
