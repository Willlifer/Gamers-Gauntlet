extends SceneTree
## Windowed: Planet of Tanks' frames (G46) at fixed seeded moments, to
## design/shots/mmo/<TAG>_tanks_<scene>.png. Everyone is a bot, you included
## (CLASS picks your seat; default warrior, so the gun is on you). Each
## moment twice: your camera, and a high view over the clearing ("_top").
##   pick, start, cannon, barrage, craters (G52), smoke, loose (wobble, fire), treadburn,
##   ram (rock, edge blast), adds (G52: parked back to back), announce, report
##   [TAG=r1] [CLASS=mage] godot --path . --script res://tools/mmo_tanks_shots.gd

var out := ""
var tag := "r0"
var v: MmoView
var shots := {}


func _initialize() -> void:
	MmoTune.use_defaults()
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "r0"
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/mmo").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("%s_tanks_%s.png" % [tag, name]))
	shots[name] = true
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


## The same moment from high over the clearing, then back to your camera.
func _top(name: String) -> void:
	var cam := v.camera()
	v.cam_hold = true
	cam.position = Vector3(0, 40, 34)
	cam.look_at(Vector3(0, 0, 2))
	await _shot(name + "_top")
	v.cam_hold = false


func _go() -> void:
	var mod := MmoTanksModule.new()
	root.add_child(mod)
	mod.setup({ "id": "shots", "seed": 7, "players": [{ "id": "you", "name": "You", "bot": false }, { "id": "rival", "name": "Rival", "bot": true }] })
	await _wait(1.2)
	await _shot("pick")
	mod.queue_free()
	await _wait(0.2)
	var cls := OS.get_environment("CLASS") if OS.get_environment("CLASS") != "" else "warrior"
	var other := "priest" if cls != "priest" else "mage"
	var s := MmoModule.build_raid(77, cls, "Edangbang", other, "Kawika", "tank")
	var bots := {}
	var k := 0
	for p: MmoUnit in s.players():
		bots[p.id] = MmoBot.new(500 + k, 1.0)
		k += 1
	v = MmoView.new()
	v.setup(s, s.players()[0].id, bots)
	root.add_child(v)
	v.input_on = false
	var hold := bots.duplicate()
	v.bots = {}
	await _wait(2.0)
	v.set_target("boss")
	await _wait(0.4)
	await _shot("start")
	v.bots = hold
	# the cannon's wedge in its telegraph
	while s.winner == "" and not (s.pulled and s.time - s.pull_time > 8.0 and not s.tank.cannon.is_empty() and s.spell.is_empty()):
		v._tick()
	for i in 20:
		v._tick()
	await _wait(0.3)
	await _shot("cannon")
	await _top("cannon")
	var want := ["smoke_throw", "barrage", "craters", "smoke", "loose_wobble", "loose_fire", "treadburn", "ram_rock", "ram_arc", "adds"]
	var guard := 0
	while not want.is_empty() and s.winner == "" and guard < 60000:
		guard += 1
		var id := str(s.spell.get("id", ""))
		var st := str(s.spell.get("stage", ""))
		var t := float(s.spell.get("t", 0.0))
		var name := ""
		if id == "smoke" and t > 0.15 and "smoke_throw" in want:
			name = "smoke_throw"
		elif id == "barrage" and st == "fire" and int(s.spell.get("fired", 0)) >= 6:
			name = "barrage"
		elif "craters" in want and "barrage" not in want and id != "barrage" and s.areas.filter(func(a: Dictionary) -> bool: return a.get("pool", false)).size() >= 6:
			name = "craters"                                  # G52: the burning remainder after a barrage
		elif "smoke" in want and not s.tank.smoke.is_empty() and float(s.tank.smoke.r) > 14.0:
			name = "smoke"
		elif id == "loose" and st == "cast" and t > 1.6:
			name = "loose_wobble"
		elif id == "loose" and st == "fire" and float(s.spell.get("ft", 0.0)) > 1.2:
			name = "loose_fire"
		elif id == "treadburn" and t > float(s.spell.total) * 0.7:
			name = "treadburn"
		elif id == "ram" and st == "rock" and float(s.spell.get("ft", 0.0)) > 1.2:
			name = "ram_rock"
		elif id == "ram" and st == "aim" and float(s.spell.get("ft", 0.0)) > 1.5:
			name = "ram_arc"
		elif "adds" in want and s.tank.adds.size() == 2 and s.tank.adds.all(func(a: MmoUnit) -> bool: return a.alive and str(a.flags.get("state", "")) == "set"):
			if not s.tank.adds[0].flags.has("born"):
				s.tank.adds[0].flags["born"] = s.time + 2.5           # G52: parked back to back, a couple of shots in
			elif s.time > float(s.tank.adds[0].flags.born):
				name = "adds"
		if name != "" and name in want:
			await _wait(0.6)
			await _shot(name)
			await _top(name)
			want.erase(name)
			continue
		v._tick()
		if guard % 6 == 0:
			await process_frame
	# the announcer
	v.tank_view.announce("TRIPLE HIT!", "3 caught in the blast: x2.50 damage each. Spread from the tank!")
	await _wait(0.5)
	await _shot("announce")
	while s.winner == "" and s.time < 900.0:
		v._tick()
	await _wait(2.6)
	await _shot("report")
	print("mmo_tanks_shots: %d frames to %s; missed %s" % [shots.size(), out, want])
	quit(0)
