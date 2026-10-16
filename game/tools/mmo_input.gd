extends SceneTree
## Headless: WoW-style controls drive the raid view (G22). Feeds real input
## events (keys, mouse buttons, motion, wheel) through Input and checks the
## sim: W runs forward, S backpedals slower, A/D turn, A/D strafe with the
## right button held, Q/E strafe, Space jumps, both buttons run, the right
## button steers your facing, Tab targets the Giant, 1 casts, Shift+1 uses
## the second bar, the wheel zooms, Esc clears the target. Exit 0.
##   godot --headless --path . --script res://tools/mmo_input.gd

var fails := 0
var v: MmoView
var s: MmoSim
var me: MmoUnit


func _initialize() -> void:
	MmoTune.use_defaults()
	_go.call_deferred()


func _ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s %s" % ["ok  " if cond else "FAIL", what])


func _key(code: Key, down: bool, shift := false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	e.shift_pressed = shift
	Input.parse_input_event(e)


func _btn(idx: MouseButton, down: bool, at := Vector2(800, 450)) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = down
	e.position = at
	Input.parse_input_event(e)


func _motion(rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.position = Vector2(800, 450)
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	# headless frames outrun the 30 Hz tick: wait real time, a tick at least per frame asked
	await create_timer(maxf(0.05, n * MmoSim.TICK * 1.5)).timeout


func _hold(code: Key, secs: float) -> void:
	_key(code, true)
	await create_timer(secs).timeout
	_key(code, false)
	await _frames(2)


func _go() -> void:
	s = MmoModule.build_raid(3, "mage", "You", "priest", "Rival")
	me = s.players()[0]
	v = MmoView.new()
	v.setup(s, me.id, {})               # no bots: only you move
	root.add_child(v)
	await _frames(5)
	me.pos = Vector2(0, 18)
	me.yaw = PI
	var p0 := me.pos
	await _hold(KEY_W, 0.5)
	_ok(me.pos.y < p0.y - 2.0 and absf(me.pos.x - p0.x) < 0.2, "W runs forward (toward the Giant): %s -> %s" % [p0, me.pos])
	var run := p0.distance_to(me.pos)
	p0 = me.pos
	await _hold(KEY_S, 0.5)
	var back := p0.distance_to(me.pos)
	_ok(me.pos.y > p0.y and back < run * 0.85, "S backpedals, slower (%.2f vs %.2f m)" % [back, run])
	var y0 := me.yaw
	await _hold(KEY_A, 0.3)
	_ok(absf(wrapf(me.yaw - y0, -PI, PI)) > 0.3, "A turns (%.2f rad)" % wrapf(me.yaw - y0, -PI, PI))
	y0 = me.yaw
	p0 = me.pos
	await _hold(KEY_E, 0.4)
	_ok(absf(wrapf(me.yaw - y0, -PI, PI)) < 0.01 and p0.distance_to(me.pos) > 1.0, "E strafes without turning")
	# right button held: A strafes, the mouse steers
	_btn(MOUSE_BUTTON_RIGHT, true)
	await _frames(2)
	y0 = me.yaw
	p0 = me.pos
	await _hold(KEY_A, 0.4)
	_ok(absf(wrapf(me.yaw - y0, -PI, PI)) < 0.05 and p0.distance_to(me.pos) > 1.0, "RMB + A strafes")
	_motion(Vector2(40, 0))
	_motion(Vector2(40, 0))
	await _frames(4)
	_ok(absf(wrapf(me.yaw - y0, -PI, PI)) > 0.1, "RMB drag steers your facing (%.2f rad)" % wrapf(me.yaw - y0, -PI, PI))
	# both buttons: run
	p0 = me.pos
	_btn(MOUSE_BUTTON_LEFT, true)
	await create_timer(0.4).timeout
	_btn(MOUSE_BUTTON_LEFT, false)
	_btn(MOUSE_BUTTON_RIGHT, false)
	await _frames(2)
	_ok(p0.distance_to(me.pos) > 1.5, "both buttons run forward")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# jump
	_key(KEY_SPACE, true)
	await _frames(6)
	_key(KEY_SPACE, false)
	_ok(me.h > 0.05 or me.airborne, "Space jumps (h %.2f)" % me.h)
	await create_timer(1.0).timeout
	# target and cast
	_key(KEY_TAB, true)
	_key(KEY_TAB, false)
	await _frames(3)
	_ok(me.target == "boss", "Tab targets the Giant")
	me.pos = Vector2(0, 14)
	me.yaw = PI
	await _frames(3)
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _frames(3)
	_ok(float(me.cd.get("ice_lance", 0.0)) > 0.0, "1 fires Ice Lance (instant, on a 3 s cooldown)")
	await create_timer(1.6).timeout
	me.gcd = 0.0
	_key(KEY_7, true)
	_key(KEY_7, false)
	await _frames(3)
	_ok(me.casting() and str(me.cast.ab) == "pyroblast", "7 casts Pyroblast (1 s)")
	await create_timer(1.4).timeout
	me.gcd = 0.0
	var cd0 := float(me.cd.get("blink", 0.0))
	_key(KEY_8, true)
	_key(KEY_8, false)
	await _frames(3)
	_ok(float(me.cd.get("blink", 0.0)) > cd0, "8 uses Blink")
	# G52: Shift+1-8 is the consumables bar, off the global cooldown
	me.hp = me.max_hp * 0.5
	me.gcd = 1.0
	_key(KEY_1, true, true)
	_key(KEY_1, false, true)
	await _frames(3)
	_ok(float(me.cd.get("item_heal", 0.0)) > 0.0 and me.hp > me.max_hp * 0.8, "Shift+1 drinks a Major Healing Potion, even on the GCD (hp %.0f%%)" % (me.hp / me.max_hp * 100.0))
	_key(KEY_3, true, true)
	_key(KEY_3, false, true)
	await _frames(3)
	_ok(me.has_aura("item_power"), "Shift+3 drinks the Elixir of Giants' Might")
	me.pos = Vector2(0, 14)
	me.yaw = PI
	await _frames(2)
	_key(KEY_8, true, true)
	_key(KEY_8, false, true)
	await _frames(3)
	_ok(float(me.cd.get("item_dynamite", 0.0)) > 0.0, "Shift+8 throws Dense Dynamite at the target")
	var d0 := v.cam_dist
	_btn(MOUSE_BUTTON_WHEEL_UP, true)
	_btn(MOUSE_BUTTON_WHEEL_UP, false)
	await _frames(2)
	_ok(v.cam_dist < d0, "the wheel zooms in (%.1f -> %.1f)" % [d0, v.cam_dist])
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_ok(me.target == "", "Esc clears the target")
	print("mmo input: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)
