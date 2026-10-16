extends SceneTree
## Windowed: opens the tournament with 3 bots, walks lobby → the creator's dice → the
## settings' tabs (G56, to <dir>/g56/) → quick
## play (FPS: Mid duel, back on F10's path) → bracket rolls → up next → matchup → (the game is skipped: the human's run is
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


## A frame into a subfolder of the shots dir (design/shots/<sub>/<name>.png).
func _shot_to(sub: String, name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var dir := out.path_join(sub)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("shot ", sub, "/", name)


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
	var ts: GDScript = load("res://src/tourney/tourney.gd")
	ts.set("simulate_all", true)
	tour = ts.new()
	root.add_child(tour)
	var lobby: LobbyScreen = await _until(LobbyScreen)
	await _wait(1.5)
	await _shot("lobby")
	# the creator's dice (G50); the profile is put back after
	var keep: Dictionary = lobby.state.me().duplicate()
	lobby.randomize_me()
	await _wait(0.8)
	await _shot("lobby_randomized")
	lobby.state.me().merge(keep, true)
	TourneyState.save_profile(lobby.state.me())
	# G56: the settings, from the creator card's gear: one frame per tab, to design/shots/g56/
	lobby.open_settings()
	await _wait(0.4)
	if lobby._opts == null:
		fails += 1
		print("FAIL: the lobby's gear opened no settings")
	else:
		for t: String in TourneySettings.TABS:
			lobby._opts.select(t)
			await _wait(0.3)
			await _shot_to("g56", "settings_" + t)
		lobby.open_settings()
		await _wait(0.2)
	# every game in the pool has a visible Quick play tile, above the players strip (G50)
	var tiles := 0
	for c in lobby._root.get_children():
		if c is TourneyTile and c.get_rect().end.y > 360 and c.get_rect().end.y <= 728:
			tiles += 1
	if tiles != TourneyModules.POOL.size():
		fails += 1
		print("FAIL: %d quick play tiles for %d games" % [tiles, TourneyModules.POOL.size()])
	tour.go_quick("fps_mid")
	await _wait(3.0)
	await _shot("quick_fps_mid")
	tour.go_lobby()
	lobby = await _until(LobbyScreen)
	await _wait(0.8)
	lobby.state.me().ready = true
	lobby.start.emit()
	var br: BracketScreen = await _until(BracketScreen)
	await _wait(0.8)
	await _shot("bracket_rolling")
	await _wait(1.0)
	await _shot("bracket_landing")
	var t0 := 0.0
	while br._phase != "next" and t0 < 15.0:
		await _wait(0.1)
		t0 += 0.1
	await _wait(0.6)
	await _shot("bracket_next")
	var mu: MatchupScreen = await _until(MatchupScreen, 20.0)
	await _wait(2.0)
	await _shot("matchup")
	mu._bet(mu.state.me().id, mu._m.p1, 10)
	await _wait(0.5)
	await _shot("matchup_bet")
	# the load-in (G42), twice: this match's game, then a game with a map (the slams at each beat)
	var mid := mu.match_id
	var m: Dictionary = tour.state.bracket.get_match(mid)
	for g: String in [str(m.game), "fps_mid"]:
		var vs := VersusScreen.new()
		vs.state = tour.state
		vs.players = [tour.state.player(m.p1), tour.state.player(m.p2)]
		vs.game_id = g
		var map := str(TourneyBackdrop.FOR_GAME.get(g, ""))
		if map != "":
			tour.backdrop.show_map(map)
			vs.map_tex = tour.backdrop.map_texture()
		tour._swap(vs)
		var tag := "versus" if g == str(m.game) else "versus_map"
		await _wait(0.3)
		await _shot(tag + "_0_black")
		await _wait(0.65)
		await _shot(tag + "_1_left")
		await _wait(0.8)
		await _shot(tag + "_2_right")
		await _wait(1.2)
		await _shot(tag + "_3_all")
	tour.go_matchup(mid)
	mu = await _until(MatchupScreen, 5.0)
	await _wait(0.3)
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
		elif cur is BracketScreen and (cur as BracketScreen)._phase == "next":
			(cur as BracketScreen).decide()
	var ch: ChampionScreen = await _until(ChampionScreen, 10.0)
	await _wait(0.5)
	await _wait(1.0)
	await _shot("champion")
	print("tourney shots: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)
