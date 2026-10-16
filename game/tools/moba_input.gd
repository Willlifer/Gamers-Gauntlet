extends SceneTree
## Headless: the MOBA controls (G54) through real input events on a practice
## MobaView: left click only moves (even on an enemy), right click attacks
## the enemy under or near the cursor and moves on empty ground; the three
## cast modes (Quick: the press casts; Slow: a press shows the indicator, a
## second press casts, a right click cancels; Release: hold shows, letting
## go casts); the 0.3 s cast stop roots you, then the walk resumes; the
## auto-attack ring is gone after 30 s. Exit 0.
##   godot --headless --path . --script res://tools/moba_input.gd

const MobaOptions := preload("res://src/tourney/moba/moba_options.gd")

var fails := 0
var v: MobaView
var s: MobaSim
var me: MobaUnit
var dummy: MobaUnit


func _initialize() -> void:
	MobaTune.use_defaults()
	_go.call_deferred()


func _ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
	print("%s %s" % ["ok  " if cond else "FAIL", what])


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _at(world: Vector2) -> Vector2:
	return v.camera().unproject_position(Vector3(world.x, 0.9, world.y))


func _point(at: Vector2) -> void:
	root.warp_mouse(at)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	Input.parse_input_event(m)


func _btn(idx: MouseButton, at: Vector2) -> void:
	_point(at)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = idx
		e.pressed = down
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)


func _frames(n: int) -> void:
	await create_timer(maxf(0.05, n * MobaSim.TICK * 1.5)).timeout


func _go() -> void:
	s = MobaSim.new(1, "practice")
	me = s.add_champ("merr", "blue", "You")
	me.pos = Vector2(-6, 0)
	dummy = s.add_dummy(Vector2(0, 0))
	root.size = Vector2i(1600, 900)          # headless windows start tiny
	v = MobaView.new()
	v.setup(s, me.id, {}, MobaOptions.with_extras(TourneyState.DEFAULT_BINDS), { "blue": "You" })
	root.add_child(v)
	await _frames(4)
	_point(_at(dummy.pos))
	await _frames(1)
	_ok(v._hovered() == dummy, "the cursor over the dummy hovers it (mouse at %s)" % v.get_viewport().get_mouse_position())
	# 1. left click on the enemy: a move, never an attack
	_btn(MOUSE_BUTTON_LEFT, _at(dummy.pos))
	await _frames(2)
	_ok(str(me.order.kind) == "move", "left click on the enemy moves (order %s)" % me.order.kind)
	# 2. right click on it: attack
	_btn(MOUSE_BUTTON_RIGHT, _at(dummy.pos))
	await _frames(2)
	_ok(str(me.order.kind) == "attack" and str(me.order.get("target", "")) == dummy.id, "right click on the enemy attacks it")
	# 3. right click near it (not on it): still attacks
	me.order = { "kind": "idle" }
	_btn(MOUSE_BUTTON_RIGHT, _at(dummy.pos + Vector2(0, 2.0)) + Vector2(0, 0))
	await _frames(2)
	_ok(str(me.order.kind) == "attack", "right click 2 units off the enemy attacks it (order %s)" % me.order.kind)
	# 4. right click on empty ground: moves
	_btn(MOUSE_BUTTON_RIGHT, _at(Vector2(-12, 3)))
	await _frames(2)
	_ok(str(me.order.kind) == "move", "right click on empty ground moves (order %s)" % me.order.kind)
	await _frames(20)
	# 5. quick cast + the cast stop
	v._aim.mode = "quick"
	_point(_at(dummy.pos))
	_btn(MOUSE_BUTTON_LEFT, _at(Vector2(-12, -3)))         # walking away
	await _frames(2)
	_key(KEY_Q, true)
	_key(KEY_Q, false)
	await _frames(1)
	var p0 := me.pos
	_ok(me.cast_slot == "q" and float(me.cd.q) == 0.0, "quick cast: Q starts at once, cooldown not yet (slot '%s')" % me.cast_slot)
	_ok(me.cast_until - me.cast_start > 0.29, "the stop lasts %.2f s (cast_until - cast_start)" % (me.cast_until - me.cast_start))
	await create_timer(0.15).timeout
	_ok(me.pos.distance_to(p0) < 0.01, "rooted while casting")
	await create_timer(0.4).timeout
	_ok(me.cast_slot == "" and float(me.cd.q) > 0.0, "it goes off after the stop (cd %.1f)" % float(me.cd.q))
	await create_timer(0.3).timeout
	_ok(me.pos.distance_to(p0) > 0.3, "the walk resumes after the cast (%.2f)" % me.pos.distance_to(p0))
	# 6. slow cast
	v._aim.mode = "slow"
	_point(_at(dummy.pos))
	_key(KEY_W, true)
	_key(KEY_W, false)
	await _frames(2)
	_ok(v._aim.armed == "w" and me.cast_slot == "" and float(me.cd.w) == 0.0, "slow cast: the first W press only aims")
	_ok(v._aim._shape != null and v._aim._shape.visible and v._aim._range.visible, "the range and the shape show")
	_btn(MOUSE_BUTTON_RIGHT, _at(dummy.pos))
	await _frames(2)
	_ok(v._aim.armed == "" and me.cast_slot == "" and float(me.cd.w) == 0.0, "a right click cancels it")
	_key(KEY_W, true)
	_key(KEY_W, false)
	await _frames(1)
	_key(KEY_W, true)
	_key(KEY_W, false)
	await _frames(1)
	_ok(me.cast_slot == "w", "the second press casts")
	await create_timer(0.5).timeout
	# 7. release cast (E: a targeted spell, the dummy in reach)
	v._aim.mode = "release"
	me.pos = Vector2(-5, 0)
	await _frames(20)                         # the camera settles on the new spot
	_point(_at(dummy.pos))
	_key(KEY_E, true)
	await _frames(3)
	_ok(v._aim.armed == "e" and me.cast_slot == "", "release cast: holding E aims")
	_key(KEY_E, false)
	await _frames(1)
	_ok(me.cast_slot == "e" or float(me.cd.e) > 0.0, "letting go casts")
	await create_timer(0.5).timeout
	# 8. the auto-attack ring goes after 30 s
	await _frames(2)
	_ok(v._range_ring.visible, "the auto-attack ring shows early on")
	s.time = 31.0
	await _frames(2)
	_ok(not v._range_ring.visible, "and is gone after 30 s")
	print("moba input: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)
