extends SceneTree
## Windowed: the raid's review frames (G22) at fixed seeded moments, saved
## to design/shots/mmo/<TAG>_<scene>.png, beside the reference
## design/ref/mmo/wow_classic_ui.jpg (the reference-gauntlet skill):
##   pick       the class pick screen
##   start      the default camera behind you, before the pull
##   fight      twenty seconds in, everyone at work
##   <spell>    each of the Giant's spells at its telling moment, from your
##              camera, and from the side at the Giant (the new animations):
##              upheaval (cracks), meteors (the rain), bombs (spread), gather (the ring)
## Everyone is a bot, you included (CLASS picks your seat; default mage).
##   [TAG=r1] [CLASS=priest] godot --path . --script res://tools/mmo_shots.gd

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
	img.save_png(out.path_join("%s_%s.png" % [tag, name]))
	shots[name] = true
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _go() -> void:
	# the pick screen
	var mod := MmoModule.new()
	root.add_child(mod)
	mod.setup({ "id": "shots", "seed": 7, "players": [{ "id": "you", "name": "You", "bot": false }, { "id": "rival", "name": "Rival", "bot": true }] })
	await _wait(1.2)
	await _shot("pick")
	mod.queue_free()
	await _wait(0.2)
	# the raid, everyone a bot
	var cls := OS.get_environment("CLASS") if OS.get_environment("CLASS") != "" else "mage"
	var other := "priest" if cls != "priest" else "mage"
	var s := MmoModule.build_raid(77, cls, "Edangbang", other, "Kawika")
	var bots := {}
	var k := 0
	for p: MmoUnit in s.players():
		bots[p.id] = MmoBot.new(500 + k, 1.0)
		k += 1
	v = MmoView.new()
	v.setup(s, s.players()[0].id, bots)
	root.add_child(v)
	v.input_on = false
	var me: MmoUnit = s.players()[0]
	(bots[me.id] as MmoBot).skill = 1.0
	# hold everyone still for the opening frame
	var hold := bots.duplicate()
	v.bots = {}
	await _wait(1.6)
	v.set_target("boss")
	await _wait(0.4)
	await _shot("start")
	v.bots = hold
	# fast-forward to twenty seconds into the fight
	while not s.pulled or s.time - s.pull_time < 14.0 or not s.spell.is_empty() or not s.areas.is_empty():
		v._tick()
		if s.winner != "" or s.time > 200.0:
			break
	await _wait(1.5)
	await _shot("fight")
	var want := ["upheaval", "meteors", "bombs", "gather"]
	var guard := 0
	while not want.is_empty() and s.winner == "" and guard < 4000:
		guard += 1
		# run fast until a spell is about to start, then in real time
		if s.spell.is_empty() and s.next_spell_at - s.time > 1.2:
			v._tick()
			continue
		await process_frame
		if s.spell.is_empty():
			continue
		var id := str(s.spell.id)
		if not id in want:
			continue
		var t := float(s.spell.t)
		var ready := false
		match id:
			"upheaval": ready = t > 1.3
			"meteors": ready = t > 2.8
			"bombs": ready = str(s.spell.stage) == "fuse" and float(s.spell.get("fuse_t", 9.0)) < MmoTune.value("bomb_fuse") - 2.6
			"gather": ready = str(s.spell.stage) == "ring" and s.areas.any(func(a: Dictionary) -> bool: return str(a.kind) == "ring" and float(a.t) < float(a.dur) - 3.0)
		if not ready:
			continue
		await _shot(id)
		await _giant(id)
		want.erase(id)
	if not shots.has("upheaval_fire"):
		pass
	print("mmo_shots: %d frames to %s" % [shots.size(), out])
	quit(0)


## The same moment from the side: the Giant mid-move, the camera on it.
func _giant(id: String) -> void:
	var b := v.sim.boss
	var root3: Node3D = v._views["boss"].root
	v.cam_hold = true
	var side := b.right() * 16.0 + b.forward() * 6.0
	var cam := v.camera()
	cam.position = Vector3(b.pos.x + side.x, 6.5, b.pos.y + side.y)
	cam.look_at(root3.global_position + Vector3(0, 3.6, 0))
	await _shot(id + "_giant")
	v.cam_hold = false
