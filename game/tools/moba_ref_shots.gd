extends SceneTree
## Windowed: the reference-review frames. Each scene seeds a sim, fast-forwards
## it with bots on both seats to the first tick that matches its moment (a
## fight with a spell in the air, a wave clash, the Giant), lets it run a
## breath in real time so effects animate, and saves the frame. Same seed,
## same moment, every run: before/after frames compare like for like.
##   godot --path . --script res://tools/moba_ref_shots.gd
## SHOTS=<dir> (default ../design/shots/ref), TAG=<prefix> (default "now").

var out := ""
var tag := "now"


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/shots/ref").simplify_path()
	if OS.get_environment("TAG") != "":
		tag = OS.get_environment("TAG")
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [tag, name]))
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


## One scene: `side` is the local seat; `until` decides the moment.
func _scene(name: String, mode: String, mine: String, theirs: String, side: String, t0: float, until: Callable) -> void:
	var s := MobaSim.new(4242, mode)
	var bots := {}
	var me: MobaUnit
	if mode == "pit":
		s.add_boss()
		var other := "red" if side == "blue" else "blue"
		var picks := { side: [mine, "temu", "braves"], other: [theirs, "merr", "temu"] }
		for team in ["blue", "red"]:
			for i in 3:
				var u := s.add_champ(picks[team][i], team, "%s %d" % [team, i])
				if team == side and i == 0:
					me = u
				bots[u.id] = MobaBot.new(0.6, 17 + i * 5 + (0 if team == "blue" else 100))
	else:
		var a := s.add_champ(mine, side, "You")
		var b := s.add_champ(theirs, "red" if side == "blue" else "blue", "Gorbo")
		me = a
		bots[a.id] = MobaBot.new(0.6, 21)
		bots[b.id] = MobaBot.new(0.55, 29)
	var v := MobaView.new()
	var other_team := "red" if side == "blue" else "blue"
	v.setup(s, me.id, bots, TourneyState.DEFAULT_BINDS, { side: "You", other_team: "Gorbo" } if mode != "pit" else {})
	root.add_child(v)
	await process_frame
	var guard := 0
	while guard < 30 * 240 and s.winner == "" and not (s.time >= t0 and until.call(s, me)):
		v._tick()
		guard += 1
	await _wait(0.25)
	await _shot(name)
	v.queue_free()
	await process_frame


func _go() -> void:
	BWSettings.init(true)
	BWMusic.ensure(root)
	var fight := func(s: MobaSim, me: MobaUnit) -> bool:
		var them: MobaUnit = null
		for u in s.units:
			if u.kind == "champ" and u.team != me.team:
				them = u
		return me.alive and me.blind_t <= 0.0 and them != null and them.alive and me.pos.distance_to(them.pos) < 7.0 and not s.projectiles.is_empty()
	var clash := func(s: MobaSim, _me: MobaUnit) -> bool:
		var n := 0
		for u in s.units:
			if u.kind == "minion" and u.alive:
				n += 1
		return n >= 5 and not s.projectiles.is_empty()
	var boss_fight := func(s: MobaSim, me: MobaUnit) -> bool:
		return me.alive and not s.areas.is_empty()
	await _scene("duel_wave", "duel", "merr", "braves", "blue", 6.0, clash)
	await _scene("duel_fight", "duel", "merr", "braves", "blue", 10.0, fight)
	await _scene("duel_red", "duel", "temu", "merr", "red", 14.0, fight)
	await _scene("pit", "pit", "braves", "temu", "blue", 12.0, boss_fight)
	print("ref shots: OK")
	quit(0)
