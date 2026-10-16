extends SceneTree
## Windowed: the tournament's Twins fight (G50) at its first turn (fire opens,
## the lance drawn, the staff carried), then after Swap (the staff's element
## skills, fire and dark on each), then the wind and thunder turns. Frames to
## SHOTS=<dir> (default ../design/shots/twins), tagged TAG (default g50).
##   godot --path . --script res://tools/twins_shots.gd

var out := ""
var tag := ""


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/shots/twins").simplify_path()
	tag = OS.get_environment("TAG")
	if tag == "":
		tag = "g50"
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var p := out.path_join("%s_%s.png" % [tag, name])
	root.get_texture().get_image().save_png(p)
	print("shot ", p)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _go() -> void:
	BWSettings.init(true)
	var f := BWFightModule.build_fight(1)
	var s := BWCombatScreen.new()
	s.configure("res://maps/%s.json" % BWRun.TWINS_MAP, f.players, f.enemies, [], 1)
	s.trust_fn = f.run.trust_stage
	root.add_child(s)
	await _wait(6.0)
	await _shot("1_fire_lance")
	var b: BWBattle = s.battle
	b.swap_weapon(b.current())
	s._after_events()
	await _wait(1.5)
	await _shot("2_fire_staff")
	for i in 2:                                   # fire, then wind, ends its turn: the next one's menu
		b.end_turn()
		s._after_events()
		await _wait(3.0)
		await _shot("%d_%s" % [i + 3, b.current().element])
	quit(0)
