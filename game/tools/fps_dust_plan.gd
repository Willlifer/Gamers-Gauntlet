extends SceneTree
## Windowed: the Dust hallway from straight above (G51), spawn markers drawn
## on, plus an eye-level view from each spawn pocket down the lane. Saves
## design/shots/fps/dust_plan/<TAG>_plan.png and <TAG>_pocket_<side><k>.png.
##   [TAG=after] [COVER=0] godot --path . --script res://tools/fps_dust_plan.gd

var out := ""
var tag := "after"


func _initialize() -> void:
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "after"
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/fps/dust_plan").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _go() -> void:
	var params := {}
	if OS.get_environment("COVER") == "0":
		params["cover"] = false
	var a := GKRegistry.build("dust_mid", params)
	var w := Node3D.new()
	root.add_child(w)
	w.add_child(GKStage.outdoor(a.lights))
	var inst := a.instantiate(true)
	w.add_child(inst)
	# the lid is collision-only, so the top view sees the floor
	var pa: Array = a.meta.play_area
	var cx := (float(pa[0]) + float(pa[2])) * 0.5
	var cz := (float(pa[1]) + float(pa[3])) * 0.5
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = absf(float(pa[3]) - float(pa[1])) + 4.0
	w.add_child(cam)
	# the lane runs along z; lay it across the frame: look down with x up the screen
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.RIGHT), Vector3(cx, 30.0, cz))
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.far = 60.0
	cam.current = true
	# spawn pins
	for k in a.markers:
		if str(k).begins_with("spawn_"):
			var pin := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.45
			cyl.bottom_radius = 0.45
			cyl.height = 9.0
			pin.mesh = cyl
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color("#2a7ad8") if str(k).begins_with("spawn_a") else Color("#e0308a")
			pin.material_override = m
			w.add_child(pin)
			pin.global_position = a.marker(k).origin + Vector3(0, 4.5, 0)
	await _frames(8)
	_save("%s_plan" % tag)
	# eye level from each pocket, looking down the lane
	for k in a.markers:
		if not str(k).begins_with("spawn_"):
			continue
		var t: Transform3D = a.marker(k)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 74.0
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.far = 400.0
		cam.global_transform = Transform3D(t.basis, t.origin + Vector3(0, 1.98, 0))
		await _frames(4)
		_save("%s_pocket_%s" % [tag, str(k).trim_prefix("spawn_")])
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
