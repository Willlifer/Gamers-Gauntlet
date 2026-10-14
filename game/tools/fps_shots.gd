extends SceneTree
## Windowed: the FPS prototype's frames at scripted moments (hip, scoped 4x,
## running with the reticle open, crouch, prone, shotgun mid-pump, slingshot
## drawn, the bot up close, the bolt mid-cycle), saved to design/shots/fps/
## and as one sheet. Exit 0.
##   godot --path . --script res://tools/fps_shots.gd

var out := ""
var w: FpsWorld
var shots: Array[Image] = []


func _initialize() -> void:
	FpsTune.use_defaults()
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/fps").simplify_path()
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


func _go() -> void:
	w = FpsWorld.new()
	root.add_child(w)
	await _wait(1.0)
	var pl := w.player
	var bot := w.bot
	bot.set_physics_process(false)          # hold the bot still for framing
	_look_at(bot.eye())
	await _wait(0.6)
	await _shot("1_hip")
	pl.debug_aim = true
	await _wait(0.6)
	await _shot("2_scoped_4x")
	pl.debug_aim = false
	pl.rotation.y += 0.6
	pl.debug_move = Vector2(0, 1)
	await _wait(0.5)
	await _shot("3_running_reticle_open")
	pl.debug_move = Vector2.ZERO
	await _wait(0.5)
	await _shot("4_stopped_reticle_closed")
	pl.stance = "crouch"
	await _wait(0.6)
	await _shot("5_crouch")
	pl.stance = "prone"
	await _wait(0.8)
	await _shot("6_prone")
	pl.stance = "stand"
	_look_at(bot.eye())
	await _wait(0.5)
	pl.debug_fire = true
	await _wait(0.05)
	pl.debug_fire = false
	await _wait(0.35)
	await _shot("7_bolt_cycle")
	pl._switch("shotgun")
	await _wait(0.6)
	pl.debug_fire = true
	await _wait(0.05)
	pl.debug_fire = false
	await _wait(0.25)
	await _shot("8_shotgun_pump")
	pl._switch("slingshot")
	await _wait(0.6)
	pl.debug_fire = true
	await _wait(0.8)
	await _shot("9_slingshot_drawn")
	pl.debug_fire = false
	# the bot up close: put the player on the bot's roof, a few metres away
	pl._switch("sniper")
	bot.set_physics_process(true)
	var bp := bot.global_position
	pl.global_position = bp + Vector3(5.0, 0.2, 3.0)
	await _wait(0.4)
	_look_at(bot.eye() + Vector3(0, -0.5, 0))
	await _wait(1.6)
	await _shot("10_bot_close")
	# sheet: 5 x 2 thumbnails
	var sheet := Image.create(1600, 360, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var t := shots[i].duplicate() as Image
		t.convert(Image.FORMAT_RGB8)
		t.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(t, Rect2i(0, 0, 320, 180), Vector2i((i % 5) * 320, (i / 5) * 180))
	sheet.save_png(out.path_join("sheet.png"))
	quit(0)
