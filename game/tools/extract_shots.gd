extends SceneTree
## Windowed: FPS: Extraction's frames at scripted moments, saved to
## design/shots/extract/ (and one sheet): the start, a chest opening, the
## loot pop-up, a guard with its "!" at the screen edge and one in view
## (green), the flare with the compass bearing, the extract hold, the HUD
## with a full kit. Exit 0.
##   [SEED=7] godot --path . --script res://tools/extract_shots.gd

var out := ""
var w: ExtractWorld
var shots: Array[Image] = []


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/extract").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	shots.append(img)
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _look_at(p: Vector3) -> void:
	var pl := w.player
	var d := p - pl.cam.global_position
	pl.rotation.y = atan2(-d.x, -d.z)
	pl._pitch = atan2(d.y, Vector2(d.x, d.z).length())


## A spot `dist` m from `from` toward `to`'s heading, on the ground.
func _toward(from: Vector3, to: Vector3, dist: float) -> Vector3:
	var d := to - from
	d.y = 0.0
	var p := from + d.normalized() * dist
	var g := w.ground(p + Vector3(0, 1, 0))
	return (g if g != Vector3.INF else p) + Vector3(0, 0.3, 0)


func _go() -> void:
	w = ExtractWorld.new()
	w.match_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	root.add_child(w)
	await _wait(1.0)
	var pl := w.player
	pl.shielded = true
	for g: ExtractGuard in w.guards:
		g.set_physics_process(false)
	# 1: the start, looking into the map
	var centre := Vector3((float(w.map.meta.play_area[0]) + float(w.map.meta.play_area[2])) * 0.5, pl.cam.global_position.y, (float(w.map.meta.play_area[1]) + float(w.map.meta.play_area[3])) * 0.5)
	_look_at(centre)
	await _wait(0.5)
	await _shot("1_start")
	# 2-3: a chest: stand 1.7 m off on a side with a clear look at it, F; the lid mid-swing, then the pop-up
	var ch: ExtractChest = w.chests[0]
	var stand := Vector3.INF
	for c: ExtractChest in w.chests:
		for k in 4:
			var dir := Vector3(0, 0, 1).rotated(Vector3.UP, c.global_rotation.y + k * PI * 0.5)
			var g := w.ground(c.global_position + dir * 1.7 + Vector3(0, 1, 0))
			if g == Vector3.INF or absf(g.y - c.global_position.y) > 0.5:
				continue
			var eye := g + Vector3(0, 1.98, 0)
			var hit := w.trace(eye, c.global_position + Vector3(0, 0.3, 0), [], 1)
			if not hit.is_empty() and hit.collider == c:
				ch = c
				stand = g + Vector3(0, 0.3, 0)
				break
		if stand != Vector3.INF and int(ch.tier) >= 2:
			break
	if stand == Vector3.INF:
		stand = ch.global_position + ch.global_transform.basis.z * 1.7 + Vector3(0, 0.3, 0)
	pl.global_position = stand
	pl.velocity = Vector3.ZERO
	await _wait(0.3)
	_look_at(ch.global_position + Vector3(0, 0.35, 0))
	await _wait(0.4)
	w.interact()
	await _wait(0.22)
	await _shot("2_chest_opening")
	await _wait(0.5)
	await _shot("3_loot_popup")
	# 4: a guard barking off-screen left: the "!" at the edge; 4b: one in view, green
	var g: ExtractGuard = w.guards[0]
	var pad: Vector3 = w.pad_pos[0]
	pl.global_position = pad + Vector3(0, 0.3, 0)
	pl.rotation.y = 0.0
	pl._pitch = 0.0
	var left := pl.global_transform.basis.x * -18.0 + -pl.global_transform.basis.z * 4.0
	g.global_position = _toward(pad, pad + left, 18.0)
	g.velocity = Vector3.ZERO
	await _wait(0.4)
	g.bark()
	await _wait(0.15)
	await _shot("4_guard_mark")
	g.global_position = _toward(pad, pad - pl.global_transform.basis.z * 10.0, 9.0)
	g._set_state("hold")
	g.crouched = false
	await _wait(0.4)
	_look_at(g.eye() + Vector3(0, -0.4, 0))
	g.bark()
	await _wait(0.2)
	await _shot("4b_guard_green")
	# 5: the flare: reveal, stand 70 m off the pad, look at it; the compass carries the bearing
	w.clock = FpsTune.value("extract_reveal")
	await _wait(0.1)
	var far: Vector3 = w.pad_pos[w.extract_i]
	var view := _toward(far, w.spawn_pos, 70.0)
	for d in [70.0, 55.0, 45.0, 35.0]:               # the first spot with the flare in plain sight
		for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
			var dir := (w.spawn_pos - far).rotated(Vector3.UP, turn)
			var p := _toward(far, far + dir, d)
			var open := w.trace(p + Vector3(0, 1.98, 0), far + Vector3(0, 30.0, 0), [], 1).is_empty()
			if open:
				view = p
				break
		if view != _toward(far, w.spawn_pos, 70.0) or d == 35.0:
			break
	pl.global_position = view
	pl.velocity = Vector3.ZERO
	await _wait(0.2)
	_look_at(far + Vector3(0, 14.0, 0))
	await _wait(2.4)
	await _shot("5_flare_compass")
	# 6: on the pad, the hold half way
	pl.global_position = far + Vector3(0, 0.3, 0)
	_look_at(far + Vector3(0, 30.0, 0) + (w.spawn_pos - far).normalized() * -20.0)
	pl._pitch = 0.5
	await _wait(1.6)
	await _shot("6_extract")
	# 7: the HUD with a kit: cash, armour, a medkit, mags, a rifle in hand
	w.ended = true                         # freeze the hold so the run doesn't end under the camera
	w.extracting = -1.0
	w.money = 1250
	w.armour = 72.0
	w.medkit = true
	pl.mags = { "rifle": 2, "shotgun": 1, "pistol": 3 }
	w.equip_gun("auto_rifle", 30)
	pl.global_position = _toward(far, w.spawn_pos, 25.0)
	_look_at(far + Vector3(0, 1.5, 0))
	w.ended = false
	await _wait(0.8)
	w.ended = true
	await _shot("7_hud")
	# sheet
	var rows := ceili(shots.size() / 4.0)
	var sheet := Image.create(1600, 225 * rows, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var t := shots[i].duplicate() as Image
		t.convert(Image.FORMAT_RGB8)
		t.resize(400, 225, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(t, Rect2i(0, 0, 400, 225), Vector2i((i % 4) * 400, (i / 4) * 225))
	sheet.save_png(out.path_join("sheet.png"))
	quit(0)
