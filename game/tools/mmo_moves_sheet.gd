extends SceneTree
## Windowed: the Giant's four spell moves (MmoMoves) frozen at three times
## each, in a grid, seen from the front three-quarter; saved to
## design/shots/mmo/<TAG>_moves.png. For checking the poses read.
##   [TAG=r2] godot --path . --script res://tools/mmo_moves_sheet.gd

const TIMES := { "upheaval": [0.9, 1.9, 2.4], "meteors": [0.4, 2.5, 5.4], "bombs": [0.8, 1.2, 1.8], "gather": [0.9, 1.6, 2.3] }

var chars: Array = []


func _initialize() -> void:
	MmoTune.use_defaults()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _go() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3a4048")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	w.add_child(sun)
	var col := 0
	for id: String in TIMES:
		var row := 0
		for t: float in TIMES[id]:
			var u := MmoUnit.new()
			u.id = "boss"
			u.kind = "boss"
			var ch := MmoView.dress(u)
			ch.position = Vector3((col - 1.5) * 2.4, (1 - row) * 2.9 - 0.6, 0)
			ch.rotation.y = 0.6
			w.add_child(ch)
			chars.append([ch, id, t])
			var l := Label3D.new()
			l.text = "%s %.1f" % [id, t]
			l.font_size = 40
			l.pixel_size = 0.004
			l.position = ch.position + Vector3(0, -0.15, 0.6)
			w.add_child(l)
			row += 1
		col += 1
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 9.2
	cam.position = Vector3(0, 0.6, 20)
	w.add_child(cam)
	cam.make_current()
	for i in 40:
		for c: Array in chars:
			var ch: BWCharacter = c[0]
			ch.poser.override = MmoMoves.sample(str(c[1]), float(c[2]))
			ch.poser.override_w = 1.0
		await process_frame
	await RenderingServer.frame_post_draw
	var tag := OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "r1"
	var out := ProjectSettings.globalize_path("res://").path_join("../design/shots/mmo/%s_moves.png" % tag).simplify_path()
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
