extends SceneTree
## Windowed: the OSRS raid on autopilot, frames of each mechanic to
## design/shots/osrs/<TAG>_<what>.png (TAG default r0): start, lightning,
## boulders, slam, sigil, tear-out, the end card; G53: a phantom's shot
## leaving the flank, the slam's third hit (centre column only), a fast slam
## below 50%, the damage potion up, the skulls rising, the dagger on them.
## G53b: a falling boulder (no cast shadow, only its square), a phantom
## winding up and firing; G53d: each slam pose (slam_west / slam_both /
## slam_east) just before it lands, both shields, the skulls
## charging, a skate mid-chain.
## G57: Hard's slams are the fist's half (slam_west / slam_east, the top-row
## marker gold over the other half) and both fists last (slam_both, gold only
## on the centre); no fast slam any more. MODE=easy shoots the Easy mode
## (OsrsEasySim, the 1f1a933 frames: start, lightning, boulders, slam, the
## orb through a slam, sigil, tear-out, phase 3, end) as <TAG>_easy_<what>.
## Runs at 2x speed.
##   [TAG=r1] [MODE=easy] godot --path . --script res://tools/osrs_shots.gd

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
	if OS.get_environment("MODE") == "easy":
		name = "easy_" + name
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [tag, name]))
	print("shot ", name)


func _go() -> void:
	OsrsTune.use_defaults()
	BWSettings.init(true)
	if OS.get_environment("MODE") == "easy":
		await _go_easy()
		return
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
		# G53
		if s.projs.any(func(p: Dictionary) -> bool: return str(p.get("src", "")) in ["west", "east"] and s.tick - int(p.launch) == 1) and v._acc > 0.3:
			await _shot("flank_shot")
		if s.slams.size() == 1 and str(s.slams[0].side) == "both" and int(s.slams[0].t) == 1:
			await _shot("slam_third")
		if int(s.me.boost) > 0 and int(s.me.boost) < int(OsrsTune.value("boost_ticks")) - 2:
			await _shot("boost")
		if not s.skull_phase.is_empty() and int(s.skull_phase.total) - int(s.skull_phase.t) == 1:
			await _shot("skulls_rise")
		if not s.skull_phase.is_empty() and s.me.weapon == "dagger" and s.skulls.size() <= int(s.skull_phase.n) - 2 and s.me.attack:
			await _shot("skulls_dagger")
		# G53b
		if s.falls.any(func(x: Dictionary) -> bool: return int(x.t) == 2) and v._acc > 0.3:
			await _shot("boulder_noshadow")
		# G53d: the mage's orb leaving his staff, the ranger's arrow leaving his bow
		if s.projs.any(func(p: Dictionary) -> bool: return str(p.style) == "magic" and str(p.src) != "warden" and s.tick == int(p.launch)) and v._acc > 0.25:
			await _shot("mage_cast")
		if s.projs.any(func(p: Dictionary) -> bool: return str(p.style) == "ranged" and str(p.src) != "warden" and s.tick == int(p.launch)) and v._acc > 0.25:
			await _shot("ranger_loose")
		if str(s.boss.next_style) == "magic" and int(s.boss.auto_cd) <= 1 and OsrsSim.boss_dist(s.me.tile) > 1 and v._acc > 0.45:
			await _shot("mage_windup")
		# G53d: one frame per slam pose, its fist up, just before it lands
		var ps: Dictionary = v._posing()
		if not ps.is_empty() and int(ps.t) == 2 and v._acc > 0.3:
			await _shot("slam_" + str(ps.side))
		if int(s.boss.auto_cd) <= 1 and OsrsSim.boss_dist(s.me.tile) > 1 and v._acc > 0.45:
			await _shot("phantom_windup")
		if str(s.boss.shield) == "magic" and int(s.boss.shield_cd) <= int(OsrsTune.value("shield_every")) - 3:
			await _shot("shield_magic")
		if str(s.boss.shield) == "ranged" and int(s.boss.shield_cd) <= int(OsrsTune.value("shield_every")) - 3:
			await _shot("shield_bowfire")
		if not s.skull_phase.is_empty() and float(s.skull_phase.t) / float(s.skull_phase.total) < 0.45 and not s.skulls.is_empty():
			await _shot("skulls_charging")
		if not s.skull_phase.is_empty() and s.me.weapon == "dagger" and s.skulls.size() <= int(s.skull_phase.n) - 3 and s.skulls.size() >= 2 and (s.me.trail as Array).size() >= 2 and v._acc > 0.3:
			await _shot("skate")
	Engine.time_scale = 1.0
	await create_timer(1.2).timeout
	await _shot("end")
	print("osrs_shots: %d frames to %s (%s)" % [shots.size(), out, s.over])
	quit(0)


## G57: the Easy mode, the 1f1a933 frames.
func _go_easy() -> void:
	var s := OsrsEasySim.new(31)
	var v := OsrsEasyView.new()
	v.setup(s)
	v.bot = OsrsEasyBot.new(31)
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
		if not s.slams.is_empty() and s.projs.any(func(p: Dictionary) -> bool: return str(p.style) != "melee" and s.tick - int(p.launch) == 2):
			await _shot("slam_orb")
		if s.sigils.any(func(x: Dictionary) -> bool: return int(x.t) <= 3):
			await _shot("sigil")
		if not s.rip.is_empty():
			await _shot("tearout")
		if s.phase() == 3 and s.gone.size() >= OsrsEasySim.W * 2:
			await _shot("phase3")
	Engine.time_scale = 1.0
	await create_timer(1.2).timeout
	await _shot("end")
	print("osrs_shots (easy): %d frames to %s (%s)" % [shots.size(), out, s.over])
	quit(0)
