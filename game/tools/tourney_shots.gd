extends SceneTree
## Windowed: opens the tournament with 3 bots, walks lobby → range → bracket
## rolls → vote → matchup → (the game is skipped: the human's run is
## replaced by a roll) → result → champion, saving a frame of each to
## SHOTS=<dir> (default ../design/shots). Exit 0 when every screen appeared.
##   godot --path . --script res://tools/tourney_shots.gd

var out := ""
var tour: Node
var fails := 0


func _initialize() -> void:
	out = OS.get_environment("SHOTS")
	if out == "":
		out = ProjectSettings.globalize_path("res://").path_join("../design/shots").simplify_path()
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("tourney_" + name + ".png"))
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _screen(cls) -> Node:
	for c in tour.get_children():
		if is_instance_of(c, cls):
			return c
	return null


func _until(cls, timeout: float = 20.0) -> Node:
	var t := 0.0
	while t < timeout:
		var s := _screen(cls)
		if s:
			return s
		await _wait(0.1)
		t += 0.1
	fails += 1
	print("FAIL: screen never appeared ", cls)
	return null


func _go() -> void:
	# a scripted human: the fight module rolls their result instead of playing
	BWFightModule.scripted = true
	tour = load("res://src/tourney/tourney.gd").new()
	root.add_child(tour)
	var lobby: LobbyScreen = await _until(LobbyScreen)
	await _wait(1.5)
	await _shot("lobby")
	lobby.open_range.emit("moba")
	var rng: RangeScreen = await _until(RangeScreen)
	await _wait(0.5)
	await _shot("range_moba")
	rng.back.emit()
	lobby = await _until(LobbyScreen)
	await _wait(0.8)
	lobby.state.me().ready = true
	lobby.start.emit()
	var br: BracketScreen = await _until(BracketScreen)
	await _wait(0.8)
	await _shot("bracket_rolling")
	await _wait(3.5)
	await _shot("bracket_rolled")
	await _wait(1.5)
	await _shot("bracket_vote")
	var mu: MatchupScreen = await _until(MatchupScreen, 20.0)
	await _wait(2.0)
	await _shot("matchup")
	mu._bet(mu.state.me().id, mu._m.p1, 10)
	await _wait(0.5)
	await _shot("matchup_bet")
	mu._go()
	var rs: ResultScreen = await _until(ResultScreen, 30.0)
	await _wait(0.8)
	await _shot("result")
	# play the rest of the evening through, voting the first option and starting at once
	var t := 0.0
	while t < 120.0 and _screen(ChampionScreen) == null:
		await _wait(0.4)
		t += 0.4
		var cur: Node = tour.screen
		if cur == null or not is_instance_valid(cur) or cur.is_queued_for_deletion():
			continue
		if cur is ResultScreen:
			(cur as ResultScreen).done.emit()
		elif cur is MatchupScreen:
			(cur as MatchupScreen)._go()
		elif cur is BracketScreen and (cur as BracketScreen)._phase == "vote":
			(cur as BracketScreen)._decide()
	var ch: ChampionScreen = await _until(ChampionScreen, 10.0)
	await _wait(1.0)
	await _shot("champion")
	print("tourney shots: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)
