extends SceneTree
## Headless: the FPS bullets (G28) and the Dust hallway map (G29).
##   godot --headless --path . --script res://tools/fps_probe.gd
## Builds FpsWorld on each map, holds the bot still 20 m down the lane, and
## checks: bullets fly at 5x the slingshot ball (not instant), a bullet that
## meets the bot hurts it, the bot's bullet hurts you, a bullet into a wall
## hurts nobody, the trigger makes bullets, and the bot's walk area is on
## the map. Exit 0 when every check passes.

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("ok   " if c else "FAIL ") + what)


func _initialize() -> void:
	FpsTune.use_defaults()
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_ok(is_equal_approx(FpsWeapons.bullet_speed(), 5.0 * float(FpsWeapons.SPECS.slingshot.ball_speed)), "bullet speed is 5x the slingshot ball (%.0f m/s)" % FpsWeapons.bullet_speed())
	for map_id in ["rooftop", "dust_mid"]:
		await _map(map_id)
	print("fps probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


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
	w.queue_free()
	await _frames(2)
