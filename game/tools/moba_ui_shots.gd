extends SceneTree
## Windowed: the G54 MOBA interface frames to SHOTS=<dir> (default
## ../design/shots): the champion select's options panel, a slow-cast aim
## indicator per shape (Merr Q line, W circle; Braves Q cone), a spell
## tooltip, smite beside flash, and a pit ping with the bots answering.
##   godot --path . --script res://tools/moba_ui_shots.gd

const MobaOptions := preload("res://src/tourney/moba/moba_options.gd")

var out := ""


func _initialize() -> void:
	MobaTune.use_defaults()
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
	root.get_texture().get_image().save_png(out.path_join("moba_ui_" + name + ".png"))
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _point(at: Vector2) -> void:
	root.warp_mouse(at)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	Input.parse_input_event(m)


func _go() -> void:
	BWSettings.init(true)
	# 1. the options on the champion select
	var mod := AramModule.new()
	root.add_child(mod)
	mod.setup({ "id": "t", "seed": 4242, "players": [{ "id": "you", "name": "You", "bot": false }, { "id": "b", "name": "Gorbo", "bot": true }],
		"binds": TourneyState.DEFAULT_BINDS })
	await _wait(0.5)
	mod._toggle_opts()
	await _wait(0.3)
	await _shot("options")
	mod.queue_free()
	await _wait(0.3)
	# 2. aim indicators and a tooltip on a practice view
	for pair in [["merr", "q"], ["merr", "w"], ["braves", "q"]]:
		var s := MobaSim.new(1, "practice")
		var me := s.add_champ(pair[0], "blue", "You")
		me.pos = Vector2(-4, 0)
		s.add_dummy(Vector2(3, 1))
		var v := MobaView.new()
		v.setup(s, me.id, {}, MobaOptions.with_extras(TourneyState.DEFAULT_BINDS), { "blue": "You" })
		root.add_child(v)
		await _wait(0.6)
		_point(v.camera().unproject_position(Vector3(4, 0, -2)))
		v._aim.mode = "slow"
		v._aim.armed = pair[1]
		if pair[0] == "merr" and pair[1] == "q":
			var ic: Control = v._hud._icons["q"]
			ic.mouse_entered.emit()
		await _wait(0.3)
		await _shot("aim_%s_%s" % pair)
		v.queue_free()
		await _wait(0.2)
	# 3. the pit: a hold ping, then a go ping, with smite beside flash
	PitModule.autopilot = false
	var s2 := MobaSim.new(77, "pit")
	s2.add_boss()
	var me2 := s2.add_champ("braves", "blue", "You")
	s2.seat_pit(me2, true)
	var bots := {}
	for c in ["merr", "temu"]:
		var a := s2.add_champ(c, "blue", "%s (ally)" % c.capitalize())
		s2.seat_pit(a, false)
		bots[a.id] = MobaBot.new(0.6, 5)
	var them := s2.add_champ("merr", "red", "Gorbo")
	s2.seat_pit(them, true)
	bots[them.id] = MobaBot.new(0.5, 9)
	var v2 := MobaView.new()
	v2.setup(s2, me2.id, bots, MobaOptions.with_extras(TourneyState.DEFAULT_BINDS), { "blue": "You", "red": "Gorbo" })
	root.add_child(v2)
	await _wait(1.0)
	v2._order["ping"] = { "kind": "hold", "at": Vector2(-2.5, 6.0) }
	await _wait(3.0)
	await _shot("pit_hold")
	v2._order["ping"] = { "kind": "go", "at": Vector2(2.5, -1.0) }
	await _wait(3.5)
	await _shot("pit_go")
	print("moba ui shots: OK")
	quit(0)
