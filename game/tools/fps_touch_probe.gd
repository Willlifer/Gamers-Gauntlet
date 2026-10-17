extends SceneTree
## Headless: the shooters' touch controls (G67, FpsTouch) through real
## InputEventScreenTouch / ScreenDrag events (Input.parse_input_event, so
## Godot's touch-to-mouse emulation runs too).
##   godot --headless --path . --script res://tools/fps_touch_probe.gd
## Off (the desktop): no overlay, the mouse is captured as before. On: the
## stick moves you (half a push, about half the speed), a right-side drag
## turns you, FIRE fires (and its finger looks), move + look + fire at once
## on three fingers, RELOAD, AIM toggles, SWAP, JUMP, CROUCH tap / hold,
## the duals' two triggers (FIRE left, AIM right), the emulated mouse never
## captures or fires, II pauses (the controls stand down, taps go to the
## card), the radial takes a tap. Extraction: USE opens the chest in reach,
## MED uses the medkit. Exit 0 when every check passes.

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("ok   " if c else "FAIL ") + what)


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	FpsWorld.ask_loadout = false
	FpsWorld.bake_nav = false
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP   # headless is square: keep a 1600x900 landscape canvas
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


## Canvas point -> window point (the stretch transform).
func _win(at: Vector2) -> Vector2:
	return root.get_final_transform() * at


func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = _win(at)
	e.pressed = down
	Input.parse_input_event(e)


func _drag(i: int, at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = _win(at)
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)


func _tap(t: FpsTouch, id: String) -> void:
	var at: Vector2 = t._btn[id].at
	_touch(0, at, true)
	await _frames(2)
	_touch(0, at, false)
	await _frames(2)


func _overlay(w: Node) -> FpsTouch:
	for c in w.get_children():
		if c is FpsTouch:
			return c
	return null


func _run() -> void:
	# off: the desktop is untouched
	FpsTouch.force = 0
	var w0 := FpsWorld.new()
	root.add_child(w0)
	await _frames(3)
	_ok(_overlay(w0) == null, "off: no touch overlay")
	w0.queue_free()
	await _frames(2)
	FpsTouch.force = 1
	var w := FpsWorld.new()
	root.add_child(w)
	await _frames(3)
	var t := _overlay(w)
	_ok(t != null, "on: the overlay is there")
	if t == null:
		quit(1)
		return
	var p := w.player
	p.shielded = true
	w.bot.set_physics_process(false)
	w.bot.set_process(false)
	await _frames(2)
	_ok(t.live(), "the controls are live once the gun is picked")
	_ok(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "the mouse isn't captured on touch")
	var size := t._size
	print("canvas %s" % size)
	# the stick: a full push up walks forward
	var c := t._stick_rest()
	var fwd0 := -p.global_transform.basis.z
	var p0 := p.global_position
	_touch(1, c, true)
	await _frames(1)
	_drag(1, c + Vector2(0, -100), Vector2(0, -100))
	await _frames(40)
	var moved := (p.global_position - p0).dot(fwd0)
	_ok(p.touch_move.y > 0.95, "the stick pushed up is full forward (%.2f)" % p.touch_move.y)
	_ok(moved > 2.0, "the stick walks you forward (%.1f m)" % moved)
	var full_v := Vector2(p.velocity.x, p.velocity.z).length()
	_drag(1, c + Vector2(0, -55), Vector2(0, 45))
	await _frames(30)
	var half_v := Vector2(p.velocity.x, p.velocity.z).length()
	_ok(half_v < full_v * 0.75 and half_v > full_v * 0.25, "half a push is slower (%.1f vs %.1f m/s)" % [half_v, full_v])
	_touch(1, c + Vector2(0, -55), false)
	await _frames(20)
	_ok(p.touch_move == Vector2.ZERO and Vector2(p.velocity.x, p.velocity.z).length() < 0.5, "letting go stops")
	# look: a drag on the right turns
	var la := Vector2(size.x * 0.62, size.y * 0.35)
	var yaw0 := p.rotation.y
	_touch(2, la, true)
	await _frames(1)
	_drag(2, la + Vector2(100, 0), Vector2(100, 0))
	await _frames(2)
	var turned := rad_to_deg(yaw0 - p.rotation.y)
	_ok(absf(turned - FpsTune.value("touch_sens")) < 0.5, "a 100 px drag turns %.1f deg (touch_sens %.1f)" % [turned, FpsTune.value("touch_sens")])
	var pitch0 := p._pitch
	_drag(2, la + Vector2(100, -50), Vector2(0, -50))
	await _frames(2)
	_ok(p._pitch > pitch0, "dragging up looks up")
	_touch(2, la, false)
	await _frames(2)
	# fire, and the fire finger looks
	p.set_loadout("auto_rifle" if FpsWeapons.available("auto_rifle") else str(FpsWeapons.primaries()[0]), "pistol")
	await _frames(25)
	var gun := p.weapon
	var a0 := int(p.ammo[gun])
	var fa: Vector2 = t._btn.fire.at
	_touch(0, fa, true)
	await _frames(20)
	_ok(int(p.ammo[gun]) < a0, "FIRE fires the %s (%d -> %d)" % [gun, a0, int(p.ammo[gun])])
	_ok(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "the emulated mouse didn't capture")
	yaw0 = p.rotation.y
	_drag(0, fa + Vector2(-60, 0), Vector2(-60, 0))
	await _frames(2)
	_ok(p.rotation.y > yaw0, "the fire finger drags the look")
	_touch(0, fa, false)
	await _frames(5)
	_ok(not p.touch_fire, "letting go of FIRE stops")
	# all three at once: stick, look, fire
	p.set_loadout(gun, "pistol")
	await _frames(25)
	a0 = int(p.ammo[gun])
	p0 = p.global_position
	yaw0 = p.rotation.y
	_touch(0, fa, true)
	_touch(1, c, true)
	_touch(2, la, true)
	await _frames(1)
	_drag(1, c + Vector2(100, 0), Vector2(100, 0))
	for k in 10:
		_drag(2, la + Vector2(10 * k, 0), Vector2(10, 0))
		await _frames(2)
	await _frames(10)
	_ok(int(p.ammo[gun]) < a0 and p.global_position.distance_to(p0) > 1.0 and absf(p.rotation.y - yaw0) > 0.05,
		"three fingers: fire (%d shots), move (%.1f m) and turn (%.1f deg) at once" % [a0 - int(p.ammo[gun]), p.global_position.distance_to(p0), rad_to_deg(absf(p.rotation.y - yaw0))])
	_touch(0, fa, false)
	_touch(1, c, false)
	_touch(2, la, false)
	await _frames(5)
	# G69: the web build's relative, which is measured from the previous point
	# in the same changedTouches slot, so from the other finger: move and look
	# fingers alternating must still turn by the look finger's own travel only
	_touch(1, c, true)
	_touch(2, la, true)
	await _frames(1)
	yaw0 = p.rotation.y
	var wsp := c + Vector2(0, -80)
	var wlp := la
	for k in 5:
		_drag(1, wsp, wsp - wlp)
		wlp = la + Vector2(20 * (k + 1), 0)
		_drag(2, wlp, wlp - wsp)
		await _frames(2)
	var want_deg := FpsTune.value("touch_sens")    # degrees per 100 px
	var wgot := rad_to_deg(absf(p.rotation.y - yaw0))
	_ok(absf(wgot - want_deg) < want_deg * 0.25, "web-style relatives: move + turn turns %.1f deg for 100 px (want %.1f)" % [wgot, want_deg])
	_touch(1, wsp, false)
	_touch(2, wlp, false)
	await _frames(25)
	# reload
	var before := int(p.ammo[gun])
	await _tap(t, "reload")
	_ok(p.vm.reload_t >= 0.0 or int(p.ammo[gun]) > before, "RELOAD reloads")
	await _frames(150)
	# aim toggle
	await _tap(t, "aim")
	await _frames(3)
	_ok(p.aiming, "AIM aims in (and stays in)")
	await _tap(t, "aim")
	await _frames(3)
	_ok(not p.aiming, "AIM again aims out")
	# swap
	var w1 := p.weapon
	await _tap(t, "swap")
	_ok(p.weapon != w1 and p.weapon == str(p.slots[1]), "SWAP takes the sidearm (%s -> %s)" % [w1, p.weapon])
	await _tap(t, "swap")
	_ok(p.weapon == w1, "SWAP again: the primary")
	# jump
	await _frames(10)
	await _tap(t, "jump")
	_ok(p.velocity.y > 0.5 or not p.is_on_floor(), "JUMP jumps")
	await _frames(60)
	# crouch: tap, then hold for prone
	await _tap(t, "crouch")
	await _frames(3)
	_ok(p.stance == "crouch", "CROUCH tapped: crouch (%s)" % p.stance)
	await _tap(t, "crouch")
	await _frames(3)
	_ok(p.stance == "stand", "CROUCH tapped again: stand (%s)" % p.stance)
	var ca: Vector2 = t._btn.crouch.at
	_touch(0, ca, true)
	await _frames(40)
	_touch(0, ca, false)
	await _frames(3)
	_ok(p.stance == "prone", "CROUCH held: prone (%s)" % p.stance)
	await _tap(t, "jump")
	_ok(p.stance == "stand", "JUMP stands you up")
	# a stray finger on empty left screen top doesn't fire or capture
	a0 = int(p.ammo[gun])
	_touch(0, Vector2(size.x * 0.2, size.y * 0.1), true)
	await _frames(10)
	_ok(int(p.ammo[gun]) == a0 and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "a finger off the buttons never fires or captures")
	_touch(0, Vector2(size.x * 0.2, size.y * 0.1), false)
	await _frames(3)
	# the duals: FIRE the left gun, AIM the right
	if FpsWeapons.available("dual_berettas"):
		p.set_loadout("dual_berettas", "pistol")
		await _frames(25)
		await _frames(1)
		_ok(str(t._btn.aim.label) == "FIRE R", "duals: AIM becomes the right trigger")
		await _tap(t, "fire")
		_ok(int(p.ammo.dual_l) == 14 and int(p.ammo.dual_r) == 15, "duals: FIRE is the left gun (%d | %d)" % [p.ammo.dual_l, p.ammo.dual_r])
		await _frames(15)
		await _tap(t, "aim")
		_ok(int(p.ammo.dual_l) == 14 and int(p.ammo.dual_r) == 14, "duals: FIRE R is the right gun (%d | %d)" % [p.ammo.dual_l, p.ammo.dual_r])
	# pause: the controls stand down; Resume by a tap (emulated click)
	await _tap(t, "pause")
	_ok(t.pause_open() and not t.live(), "II opens the pause card; the controls stand down")
	var resume: Button = null
	for b in t._pause.find_children("*", "Button", true, false):
		if (b as Button).text == "Resume":
			resume = b
	await _frames(2)
	var rc := resume.get_global_rect().get_center()
	_touch(0, rc, true)
	await _frames(2)
	_touch(0, rc, false)
	await _frames(3)
	_ok(not t.pause_open() and t.live(), "a tap on Resume closes it")
	# the radial by tap
	FpsWorld.ask_loadout = true
	w.open_loadout()
	await _frames(3)
	_ok(w.menu_open() and not t.live(), "the radial is up; the controls stand down")
	var menu: FpsLoadoutMenu = w._menu
	var want := str(menu.options[1])
	var cen := menu._center()
	var sp := menu._span(1)
	var mid := (sp.x + sp.y) * 0.5
	var at := cen + Vector2(cos(mid), sin(mid)) * menu._radius() * 0.7
	_touch(0, at, true)
	await _frames(2)
	_touch(0, at, false)
	await _frames(3)
	_ok(not w.menu_open() and (p.weapon == want or want == "random"), "a tap on a wedge picks it (%s, wanted %s)" % [p.weapon, want])
	_ok(t.live() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "back in play, the mouse still free")
	FpsWorld.ask_loadout = false
	w.queue_free()
	await _frames(3)
	await _extract()
	FpsTouch.force = -1
	print("fps touch probe: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _extract() -> void:
	var w := ExtractWorld.new()
	w.match_seed = 7
	root.add_child(w)
	await _frames(4)
	var t := _overlay(w)
	_ok(t != null and t._btn.has("use") and not t._btn.has("med"), "Extraction: USE is there, MED only with a medkit")
	var p := w.player
	p.shielded = true
	for g: ExtractGuard in w.guards:
		g.set_physics_process(false)
	var ch: ExtractChest = w.chests[0]
	p.global_position = ch.global_position + Vector3(1.5, 0.3, 0)
	await _frames(4)
	await _tap(t, "use")
	_ok(ch.is_open, "USE opens the chest in reach")
	w.medkit = true
	p.hp = 40.0
	await _frames(2)
	_ok(t._btn.has("med"), "MED shows with a medkit")
	await _tap(t, "med")
	_ok(not w.medkit and w.heal_t >= 0.0, "MED uses it")
	w.queue_free()
	await _frames(2)
