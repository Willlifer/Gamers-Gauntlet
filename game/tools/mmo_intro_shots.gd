extends SceneTree
## Windowed: the first-time card (G52b) over each raid, to
## design/shots/mmo/<TAG>_intro_<raid>_<class>.png. Doesn't touch the
## [seen] flags in user://tourney.cfg.
##   [TAG=g52b] godot --path . --script res://tools/mmo_intro_shots.gd

var out := ""
var tag := "r0"


func _initialize() -> void:
	MmoTune.use_defaults()
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "r0"
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/mmo").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _go() -> void:
	for pair in [["giant", "priest", "mmo_raid"], ["tank", "warrior", "mmo_tanks"]]:
		var s := MmoModule.build_raid(77, str(pair[1]), "Edangbang", "mage", "Kawika", str(pair[0]))
		var v := MmoView.new()
		v.setup(s, s.players()[0].id, {})
		root.add_child(v)
		await create_timer(1.5).timeout
		var card := MmoIntro.open(v, str(pair[1]), str(pair[0]), str(pair[2]), false)
		await create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		var name := "%s_intro_%s_%s.png" % [tag, pair[0], pair[1]]
		root.get_texture().get_image().save_png(out.path_join(name))
		print("shot ", name, "  sim held: ", v.hold_sim and s.time == 0.0)
		card.close()
		await process_frame
		print("released: ", not v.hold_sim)
		v.queue_free()
		await create_timer(0.3).timeout
	quit(0)
