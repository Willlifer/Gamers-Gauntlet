extends SceneTree
## Windowed: the ARAM module on autopilot (a bot drives "your" champion too),
## saving the champion select, frames through the fight, and the MOBA range
## with its dummy to SHOTS=<dir> (default ../design/shots). Exit 0 when the
## match ended and every frame was written.
##   godot --path . --script res://tools/aram_shots.gd

var out := ""
var fails := 0


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/shots").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("aram_" + name + ".png"))
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _go() -> void:
	BWSettings.init(true)
	BWMusic.ensure(root)
	AramModule.autopilot = true
	var mod := AramModule.new()
	var result := [{}]
	mod.finished.connect(func(r): result[0] = r)
	root.add_child(mod)
	mod.setup({ "id": "t", "seed": 4242, "players": [{ "id": "you", "name": "You", "bot": false }, { "id": "b", "name": "Gorbo", "bot": true }],
		"binds": TourneyState.DEFAULT_BINDS })
	await _wait(0.6)
	await _shot("select")
	var t := 0.0
	var marks := [6.0, 20.0, 40.0, 70.0]
	while result[0].is_empty() and t < 300.0:
		await _wait(0.5)
		t += 0.5
		if not marks.is_empty() and t >= marks[0]:
			await _shot("fight_%02d" % int(marks.pop_front()))
	if result[0].is_empty():
		fails += 1
		print("FAIL the match never ended")
	else:
		print("result: ", result[0].summary)
	mod.queue_free()
	# the MOBA range with its dummy
	var rs := RangeScreen.new()
	rs.kind = "moba"
	root.add_child(rs)
	await _wait(2.0)
	await _shot("range")
	print("aram shots: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)
