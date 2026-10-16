extends SceneTree
## Windowed: the OSRS raid on autopilot, frames of each mechanic to
## design/shots/osrs/<TAG>_<what>.png (TAG default r0): start, lightning,
## boulders, slam, sigil, tear-out, the end card. Runs at 2x speed.
##   [TAG=r1] godot --path . --script res://tools/osrs_shots.gd

var out := ""
var tag := ""
var shots := {}


func _initialize() -> void:
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "r0"
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/osrs").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	if shots.has(name):
		return
	shots[name] = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [tag, name]))
	print("shot ", name)


func _go() -> void:
	OsrsTune.use_defaults()
	BWSettings.init(true)
	var s := OsrsSim.new(31)
	var v := OsrsView.new()
	v.setup(s)
	v.bot = OsrsBot.new(31)
	root.add_child(v)
	await create_timer(1.5).timeout
	await _shot("start")
	Engine.time_scale = 2.0
	var guard := 0.0
	while s.over == "" and guard < 400.0:
		await process_frame
		guard += 1.0 / 60.0
		if not s.bolts.is_empty() and s.bolts.any(func(b: Dictionary) -> bool: return int(b.t) == 2):
			await _shot("lightning")
		if not s.falls.is_empty() and s.falls.any(func(f: Dictionary) -> bool: return int(f.t) == 2):
			await _shot("boulders")
		if s.slams.any(func(x: Dictionary) -> bool: return int(x.t) <= 2 and int(x.t) >= 1):
			await _shot("slam")
		# G45: an orb mid-flight (3 s from any distance) while the floor glows
		if not s.slams.is_empty() and s.projs.any(func(p: Dictionary) -> bool: return str(p.style) != "melee" and s.tick - int(p.launch) == 2):
			await _shot("slam_orb")
		if s.sigils.any(func(x: Dictionary) -> bool: return int(x.t) <= 3):
			await _shot("sigil")
		if not s.rip.is_empty():
			await _shot("tearout")
		if s.phase() == 3 and s.gone.size() >= OsrsSim.W * 2:
			await _shot("phase3")
	Engine.time_scale = 1.0
	await create_timer(1.2).timeout
	await _shot("end")
	print("osrs_shots: %d frames to %s (%s)" % [shots.size(), out, s.over])
	quit(0)
