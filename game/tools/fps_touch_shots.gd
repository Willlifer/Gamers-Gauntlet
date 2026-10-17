extends SceneTree
## Windowed: the shooters' touch controls (G67, FpsTouch forced on) on each
## of the four shooters at phone-ish landscape sizes, with a thumb on the
## stick; then the pause card, the radial, Extraction's USE lit at a chest
## and the portrait "turn your phone" card. Frames to design/shots/fps/touch/
## as <size>_<game>.png; `python tools/fps_touch_sheet.py` makes the sheets.
##   [SIZES=1280x720,2400x1080] godot --path . --script res://tools/fps_touch_shots.gd

var out := ""
var w: FpsWorld


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	FpsWorld.ask_loadout = false
	FpsTouch.force = 1
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/fps/touch").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot %s %s (canvas %s)" % [name, img.get_size(), root.get_visible_rect().size])


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _touch(i: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = root.get_final_transform() * at
	e.pressed = down
	Input.parse_input_event(e)


func _drag(i: int, at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = root.get_final_transform() * at
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)


func _overlay() -> FpsTouch:
	for c in w.get_children():
		if c is FpsTouch:
			return c
	return null


func _size(s: Vector2i) -> void:
	DisplayServer.window_set_size(s)
	await _wait(0.4)
	print("window %s (asked %s)" % [DisplayServer.window_get_size(), s])


func _world(game: String) -> void:
	if game == "extract":
		var x := ExtractWorld.new()
		x.match_seed = 7
		w = x
	else:
		w = FpsWorld.new()
		w.map_id = game
		w.match_seed = 3
	root.add_child(w)
	await _wait(1.2)
	w.player.shielded = true
	if w.bot:
		w.bot.set_physics_process(false)
	if w is ExtractWorld:
		for g: ExtractGuard in (w as ExtractWorld).guards:
			g.set_physics_process(false)


## A thumb on the stick pushed up and right (it floats to where it lands).
func _thumb() -> FpsTouch:
	var t := _overlay()
	var c := t._stick_rest() + Vector2(20, -10)
	_touch(1, c, true)
	await process_frame
	_drag(1, c + Vector2(55, -70), Vector2(55, -70))
	await process_frame
	w.player.touch_move = Vector2.ZERO      # drawn, not walked: the frame stays put
	w.player.set_physics_process(false)
	return t


func _done() -> void:
	_touch(1, Vector2.ZERO, false)
	w.queue_free()
	await _wait(0.3)


func _go() -> void:
	var sizes := (OS.get_environment("SIZES") if OS.get_environment("SIZES") != "" else "1280x720,2400x1080").split(",")
	var games := ["rooftop", "dust_mid", "campus", "extract"]
	if GKRegistry.def("campus") == null:
		games.erase("campus")
	for sz in sizes:
		var p := sz.split("x")
		await _size(Vector2i(int(p[0]), int(p[1])))
		for g: String in games:
			await _world(g)
			await _thumb()
			await _shot("%s_%s" % [sz, g])
			await _done()
	# extras at the wide phone size
	await _size(Vector2i(2400, 1080))
	await _world("rooftop")
	var t := _overlay()
	_touch(0, t._btn.pause.at, true)
	await process_frame
	_touch(0, t._btn.pause.at, false)
	await _shot("extra_pause")
	t._close_pause()
	FpsWorld.ask_loadout = true
	w.open_loadout()
	await _wait(0.6)
	await _shot("extra_radial")
	FpsWorld.ask_loadout = false
	await _done()
	await _world("extract")
	var x := w as ExtractWorld
	var ch: ExtractChest = x.chests[0]
	var pl := w.player
	pl.global_position = ch.global_position + Vector3(1.6, 0.3, 0)
	var d := ch.global_position - pl.cam.global_position
	pl.rotation.y = atan2(-d.x, -d.z)
	pl._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	x.medkit = true
	await _wait(0.4)
	await _shot("extra_extract_use")
	await _done()
	await _size(Vector2i(540, 1200))
	await _world("rooftop")
	await _shot("extra_portrait")
	await _done()
	quit(0)
