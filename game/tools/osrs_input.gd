extends SceneTree
## Windowed: the OSRS raid's clicks through real input events (G53d), after
## tools/mmo_input.gd. Skulls on the floor; mouse clicks go through
## Input.parse_input_event to the view like a player's. A click on a skull's
## head (which draws over the square behind it), its square, its feet, or a
## little off it targets the skull, never the floor; a click on an empty
## square walks there. G57: then the Easy mode's view (OsrsEasyView): a click
## on the Warden attacks, a click on a square walks there.
##   godot --path . --script res://tools/osrs_input.gd      (exit 0 when all pass)

var fails := 0


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("ok   " if c else "FAIL ") + what)


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _click(v: Object, at: Vector2) -> Dictionary:
	v._orders = {}
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await process_frame
	await process_frame
	var o: Dictionary = v._orders.duplicate()
	v._orders = {}
	return o


func _go() -> void:
	OsrsTune.use_defaults()
	BWSettings.init(true)
	var s := OsrsSim.new(41)
	s.boss.auto_cd = 9999
	s.boss.special_cd = 9999
	s.boss.sigil_cd = 9999
	s.boss.rips = 9999
	s.boss.skull_i = 3
	s.boss.shield_cd = 9999
	s.me.tile = Vector2i(7, 9)
	var tiles := [Vector2i(5, 6), Vector2i(9, 6), Vector2i(5, 8), Vector2i(9, 8), Vector2i(7, 4)]
	for i in tiles.size():
		s.skulls.append({ "id": i + 1, "tile": tiles[i], "hp": 1, "max": 1 })
	s.skull_phase = { "t": 9999, "total": 9999, "n": tiles.size() }
	var v := OsrsView.new()
	v.setup(s)
	root.add_child(v)
	await create_timer(1.0).timeout
	Engine.time_scale = 0.0                                   # hold the sim still while we click
	var cam := v._cam
	var head_ok := 0
	var feet_ok := 0
	var near_ok := 0
	var sq_ok := 0
	for k: Dictionary in s.skulls:
		var id := int(k.id)
		var head := cam.unproject_position(v.w(k.tile) + Vector3(0, 1.45, 0))
		var feet := cam.unproject_position(v.w(k.tile) + Vector3(0, 0.05, 0))
		var o := await _click(v, head)
		if int(o.get("target", -1)) == id and not o.has("move"):
			head_ok += 1
		o = await _click(v, feet)
		if int(o.get("target", -1)) == id and not o.has("move"):
			feet_ok += 1
		o = await _click(v, head + Vector2(22, -10))
		if int(o.get("target", -1)) == id and not o.has("move"):
			near_ok += 1
		var corner := cam.unproject_position(v.w(k.tile) + Vector3(OsrsView.TILE * 0.42, 0, OsrsView.TILE * 0.42))
		o = await _click(v, corner)
		if int(o.get("target", -1)) == id and not o.has("move"):
			sq_ok += 1
	var n := s.skulls.size()
	_ok(head_ok == n, "a click on a skull's head targets it, not the square behind it (%d / %d)" % [head_ok, n])
	_ok(feet_ok == n, "a click at its feet targets it (%d / %d)" % [feet_ok, n])
	_ok(near_ok == n, "a click a little off it still targets it (%d / %d)" % [near_ok, n])
	_ok(sq_ok == n, "a click on its square's corner targets it (%d / %d)" % [sq_ok, n])
	var far := await _click(v, cam.unproject_position(v.w(Vector2i(12, 10))))
	_ok(far.get("move", Vector2i(-1, -1)) == Vector2i(12, 10) and not far.has("target"), "a click on an empty square walks there (%s)" % str(far))
	# the hover square shows the skull a click would hit
	Input.warp_mouse(cam.unproject_position(v.w(tiles[0]) + Vector3(0, 1.45, 0)))
	await process_frame
	await process_frame
	_ok(v._hover.visible and v._hover.position.distance_to(v.w(tiles[0])) < 0.2, "hovering a skull's head outlines its square")
	var out := ProjectSettings.globalize_path("res://").path_join("../design/shots/osrs").simplify_path()
	var tag := OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "r4"
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_skull_hover.png" % tag))
	Engine.time_scale = 1.0
	v.queue_free()
	await process_frame
	await _easy()
	print("osrs input: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


## G57: the Easy mode's clicks (OsrsEasyView, the 1f1a933 view).
func _easy() -> void:
	var s := OsrsEasySim.new(41)
	s.boss.auto_cd = 9999
	s.boss.special_cd = 9999
	s.boss.sigil_cd = 9999
	s.boss.rip_cd = 9999
	s.me.tile = Vector2i(7, 9)
	var v := OsrsEasyView.new()
	v.setup(s)
	root.add_child(v)
	await create_timer(1.0).timeout
	Engine.time_scale = 0.0
	var cam := v._cam
	var boss := await _click(v, cam.unproject_position(OsrsEasyView.BOSS_POS + Vector3(0, 3.2, 0)))
	_ok(bool(boss.get("attack", false)) and not boss.has("move"), "easy: a click on the Warden attacks it (%s)" % str(boss))
	var sq := await _click(v, cam.unproject_position(v.w(Vector2i(3, 10))))
	_ok(sq.get("move", Vector2i(-1, -1)) == Vector2i(3, 10), "easy: a click on a square walks there (%s)" % str(sq))
	Engine.time_scale = 1.0
	v.queue_free()
