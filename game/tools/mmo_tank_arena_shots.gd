extends SceneTree
## Windowed: Planet of Tanks' arena (MmoTankArena, the campus with a round
## clearing) from fixed cameras, saved to design/shots/mmo/tank_arena_<view>.png:
##   overview   from above at ~60 m, the whole clearing and the campus round it
##   raid       a raid-eye view from (0, 6, 20) at the origin (the tank's spot)
##   edge_n / edge_e   from the clearing's edge, looking outward
##   low        from the far rim at head height, across the clearing
##   road       down on the south edge, where the road is cut
##   clamp_*    the raid camera at its clamp (WALL_R - 1): it must see the fight, not a wall or a crown
## A red marker stands in for the tank at the origin.
##   godot --path . --script res://tools/mmo_tank_arena_shots.gd

var out := ""


func _initialize() -> void:
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/mmo").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _go() -> void:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(GKStage.outdoor(MmoTankArena.lights()))
	var t0 := Time.get_ticks_msec()
	var arena := MmoTankArena.build(world)
	var tris := 0
	for mi: Node in arena.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			tris += m.surface_get_array_index_len(i) / 3
	print("build ms: %d, triangles: %d" % [Time.get_ticks_msec() - t0, tris])
	var stand := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 2.4, 6.0)
	stand.mesh = bm
	stand.position = Vector3(0, 1.2, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8a2a22")
	stand.material_override = mat
	world.add_child(stand)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 900.0
	world.add_child(cam)
	cam.make_current()
	var R := MmoTankArena.R
	var views := [
		["overview", Vector3(0, 58, 42), Vector3(0, 0, -2)],
		["top", Vector3(0, 95, 0.1), Vector3.ZERO],
		["raid", Vector3(0, 6, 20), Vector3.ZERO],
		["edge_n", Vector3(0, 2.2, -(R - 2.0)), Vector3(0, 4.0, -60)],
		["edge_e", Vector3(R - 2.0, 2.2, 0), Vector3(60, 4.0, 0)],
		["edge_s", Vector3(0, 2.2, R - 2.0), Vector3(0, 4.0, 60)],
		["low", Vector3(-17, 2.0, 17), Vector3(10, 2.5, -14)],
		["road", Vector3(0, 9, 8), Vector3(-6, 0, 30)],
		# the raid camera at its clamp (WALL_R - 1), default height: nothing may sit on it
		["clamp_s", Vector3(0, 8.0, MmoTankArena.WALL_R - 1.0), Vector3(0, 1.5, 0)],
		["clamp_ne", Vector3(1, 8.0, -1).normalized() * (MmoTankArena.WALL_R - 1.0) + Vector3(0, 8.0, 0), Vector3(0, 1.5, 0)],
		["clamp_w", Vector3(-(MmoTankArena.WALL_R - 1.0), 6.0, -6.0), Vector3(0, 1.5, 0)],
	]
	for v: Array in views:
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		for k in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("tank_arena_%s.png" % v[0]))
		print("shot ", v[0])
	quit(0)
