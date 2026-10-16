extends SceneTree
## Windowed: the muzzle flash review frames (G51, the reference-gauntlet
## loop): every built gun from its right side on black, firing, with a fixed
## seed and a fixed moment of the flash, like design/ref/kit/muzzle_flash.png;
## and a sheet with the reference first. Saves
## design/shots/fps/flash/<TAG>_<gun>.png and <TAG>_sheet.png.
## OLD=1 draws the flash as it was before G51 (three crossed quads, one
## flat colour) for the round-0 frames.
## BRIGHT=1: on a pale sky instead of black (no dark box or fringe may show).
##   [TAG=r1] [OLD=1] [BRIGHT=1] godot --path . --script res://tools/fps_flash_shots.gd

const GUNS := ["pistol", "deagle", "carbine", "auto_rifle", "shotgun", "marksman", "sniper"]
var out := ""
var tag := "r0"


func _initialize() -> void:
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "r0"
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/fps/flash").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(960, 540))
	_go.call_deferred()


func _go() -> void:
	var frames: Array[Image] = []
	for id in GUNS:
		if not FpsWeapons.available(id):
			continue
		var w := Node3D.new()
		root.add_child(w)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color.BLACK if OS.get_environment("BRIGHT") != "1" else Color("#9ec3e6")
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.35, 0.36, 0.4)
		e.ambient_light_energy = 0.35
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
		e.glow_enabled = true
		e.glow_intensity = 0.6
		e.glow_bloom = 0.1
		env.environment = e
		w.add_child(env)
		var sp: Dictionary = FpsWeapons.SPECS[id]
		var a := GKRegistry.build(str(sp.asset), sp.params)
		var gun := a.instantiate(false)
		w.add_child(gun)
		var muzzle := a.marker("muzzle").origin
		var f := FpsMuzzleFlash.new()
		f.size = float(sp.get("flash", 1.0))
		gun.add_child(f)
		f.position = muzzle
		f.pop(7)
		f.set_process(false)
		f._shape(0.15)
		f.transform = Transform3D(Basis(Vector3.BACK, f.roll), muzzle)
		if OS.get_environment("OLD") == "1":
			f.visible = false
			gun.add_child(_old_flash(muzzle))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.38)
		l.light_energy = 2.5 + 3.0 * f.size
		l.omni_range = 0.6 + 0.6 * f.size
		gun.add_child(l)
		l.position = muzzle + Vector3(0, 0, 0.08 * f.size)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-30, -60, 0)
		key.light_energy = 0.25
		w.add_child(key)
		# frame: the back half of the gun on the left, the flash on the right (the reference's layout)
		var bb := a.aabb()
		var back := minf(bb.size.z, 0.7)                 # this much gun behind the muzzle
		var ahead := FpsMuzzleFlash.PLUME.x * f.size * 1.5
		var mid := Vector3(0, muzzle.y, muzzle.z + (ahead - back) * 0.5)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = (back + ahead) * 1.1
		w.add_child(cam)
		cam.position = mid + Vector3(-3.0, 0, 0)       # the gun's right side: muzzle to the right
		cam.look_at(mid, Vector3.UP)
		cam.current = true
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(out.path_join("%s_%s.png" % [tag, id]))
		frames.append(img)
		print("shot ", id)
		w.queue_free()
		await process_frame
	# the sheet: the reference, then each gun, 3 across at 480 x 270
	var ref := Image.load_from_file(ProjectSettings.globalize_path("res://").path_join("../design/ref/kit/muzzle_flash.png"))
	ref.convert(Image.FORMAT_RGB8)
	ref.resize(270, 270, Image.INTERPOLATE_LANCZOS)
	var cells := frames.size() + 1
	var rows := ceili(cells / 3.0)
	var sheet := Image.create(1440, 270 * rows, false, Image.FORMAT_RGB8)
	sheet.blit_rect(ref, Rect2i(0, 0, 270, 270), Vector2i(105, 0))
	for i in frames.size():
		var t := frames[i].duplicate() as Image
		t.convert(Image.FORMAT_RGB8)
		t.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		var c := i + 1
		sheet.blit_rect(t, Rect2i(0, 0, 480, 270), Vector2i((c % 3) * 480, (c / 3) * 270))
	sheet.save_png(out.path_join("%s_sheet.png" % tag))
	quit(0)


## The pre-G51 view-model flash, verbatim, for r0.
func _old_flash(at: Vector3) -> Node3D:
	var fl := Node3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.75, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.09, 0.22)
		q.mesh = qm
		q.material_override = m
		q.rotation = Vector3(PI * 0.5, 0, k * PI / 3.0)
		q.position.z = 0.08
		fl.add_child(q)
	var core := MeshInstance3D.new()
	var cm := QuadMesh.new()
	cm.size = Vector2(0.12, 0.12)
	core.mesh = cm
	core.material_override = m
	fl.add_child(core)
	fl.position = at
	return fl
