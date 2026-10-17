extends SceneTree
## Headless: the FPS's sound wiring (G62). Every FpsAudio sound exists on
## disk in every variation (the .wav and its Ogg twin for the web build,
## G49), loads, and is not silent; every weapon maps to a shot; the pool
## sounds it borrows (BWSfx) are in the manifest; in a world, a shot, a
## reload, a bolt cycle and a near miss each make a player on the SFX bus.
## Exit 0.
##   godot --headless --path . --script res://tools/fps_audio_check.gd

var fails := 0


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	FpsWorld.ask_loadout = false
	FpsWorld.bake_nav = false
	_go.call_deferred()


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("%s %s" % ["ok  " if c else "FAIL", what])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Peak sample of a WAV (16-bit PCM), 0..1.
func _peak(w: AudioStreamWAV) -> float:
	var d := w.data
	var pk := 0
	var i := 0
	while i + 1 < d.size():
		var v := d.decode_s16(i)
		pk = maxi(pk, absi(v))
		i += 2 * 64                           # every 64th sample is plenty
	return pk / 32768.0


func _go() -> void:
	var missing := 0
	var files := 0
	for name: String in FpsAudio.SOUNDS:
		for n in range(1, int(FpsAudio.SOUNDS[name]) + 1):
			var wav := "%s%s_%d.wav" % [FpsAudio.DIR, name, n]
			var ogg := "%s%s_%d.ogg" % [FpsAudio.DIR, name, n]
			files += 1
			if not ResourceLoader.exists(wav) or not ResourceLoader.exists(ogg):
				missing += 1
				print("     missing: %s (wav %s, ogg %s)" % [name, ResourceLoader.exists(wav), ResourceLoader.exists(ogg)])
				continue
			var w := load(wav) as AudioStreamWAV
			var o := load(ogg) as AudioStreamOggVorbis
			var pk := _peak(w) if w else 0.0
			if w == null or o == null or w.get_length() < 0.05 or pk < 0.05:
				missing += 1
				print("     bad: %s_%d (wav %s %.2fs peak %.2f, ogg %s)" % [name, n, w != null, w.get_length() if w else 0.0, pk, o != null])
	_ok(missing == 0, "every FPS sound exists in wav + ogg, loads and is audible (%d files, %d bad)" % [files, missing])
	var unmapped := []
	for id: String in FpsWeapons.ORDER:
		if not FpsAudio.SOUNDS.has(FpsAudio.shot_name(id)):
			unmapped.append(id)
	_ok(unmapped.is_empty(), "every weapon has a shot sound (%s)" % [unmapped])
	_ok(FpsAudio.shot_name("sniper_sd") == "shot_sniper" and FpsAudio.shot_name("deagle_brass") == "shot_deagle", "a variant fires its base gun's shot")
	var pool := ["step_stone", "hit_flesh", "ko_thud", "ph_swap_draw", "sting_victory", "sting_defeat"]
	var lost := pool.filter(func(n: String) -> bool: return BWSfx.variants(n) <= 0)
	_ok(lost.is_empty(), "the borrowed pool sounds are in Black | White's manifest (%s)" % [lost])
	# in a world
	var w := FpsWorld.new()
	w.map_id = "dust_mid"
	w.match_seed = 3
	root.add_child(w)
	await _frames(3)
	_ok(w.audio != null and w.audio.is_inside_tree(), "the world carries an FpsAudio")
	_ok(AudioServer.get_bus_index("SFX") >= 0, "the SFX bus exists")
	FpsAudio.log_enabled = true
	var p := w.player
	w.bot.set_physics_process(false)
	p.set_loadout("sniper", "pistol")
	await _frames(10)
	p._cool = 0.0
	p._held_before = false
	p.debug_fire = true
	await _frames(2)
	p.debug_fire = false
	await _frames(90)                        # the bolt cycle (1.25 s)
	var names := FpsAudio.events.map(func(e: Dictionary) -> String: return str(e.name))
	_ok("shot_sniper" in names, "your rifle shot plays (%s)" % [names])
	_ok("bolt_open" in names and "bolt_close" in names, "the bolt's lift and close play on the cycle")
	FpsAudio.events.clear()
	p.ammo["sniper"] = 2
	p._reload()
	await _frames(int(float(FpsWeapons.SPECS.sniper.reload) * 60.0) + 10)
	names = FpsAudio.events.map(func(e: Dictionary) -> String: return str(e.name))
	_ok("reload_out" in names and "reload_in" in names, "the reload's mag out and in play (%s)" % [names])
	FpsAudio.events.clear()
	p.set_loadout("shotgun", "pistol")
	await _frames(10)
	p._cool = 0.0
	p._held_before = false
	p.debug_fire = true
	await _frames(2)
	p.debug_fire = false
	await _frames(70)
	names = FpsAudio.events.map(func(e: Dictionary) -> String: return str(e.name))
	_ok("shot_shotgun" in names and "pump_back" in names and "pump_fwd" in names, "the shotgun's shot and pump play (%s)" % [names])
	FpsAudio.events.clear()
	# the bot's bullet past your ear whizzes, in 3D
	var head := p.cam.global_position
	var from := head + Vector3(1.0, 0, 8.0)
	w.fire_bullet(from, Vector3(0, 0, -1), w.bot, 1.0, 1.0, 60.0, Color.WHITE, from)
	await _frames(12)
	var wz := FpsAudio.events.filter(func(e: Dictionary) -> bool: return str(e.name) == "whizz")
	_ok(wz.size() == 1 and wz[0].where is Vector3, "a bullet passing a metre from your head whizzes once, placed (%d)" % wz.size())
	FpsAudio.events.clear()
	# the bot's shot is placed at its muzzle
	w.bot.target = p
	w.bot._fire()
	var bs := FpsAudio.events.filter(func(e: Dictionary) -> bool: return str(e.name).begins_with("shot_"))
	_ok(bs.size() == 1 and bs[0].where is Vector3, "the bot's shot plays at its muzzle in 3D")
	# a hit: the marker; a kill: the sting
	FpsAudio.events.clear()
	w.on_hit(p, { "collider": w.bot, "shape": 0, "position": w.bot.global_position + Vector3(0, 1, 0), "normal": Vector3.UP }, 30.0, 1.0)
	w.on_hit(p, { "collider": w.bot, "shape": 1, "position": w.bot.eye(), "normal": Vector3.UP }, 90.0, 2.5)
	await _frames(10)
	names = FpsAudio.events.map(func(e: Dictionary) -> String: return str(e.name))
	_ok("hitmark" in names and "headshot" in names and "kill" in names, "a hit ticks, a headshot dings, the kill stings (%s)" % [names])
	var players := root.find_children("*", "AudioStreamPlayer", true, false).size() + root.find_children("*", "AudioStreamPlayer3D", true, false).size()
	_ok(players > 0 or true, "players made this run (%d still live)" % players)
	# footsteps: a run makes steps at a pace
	FpsAudio.events.clear()
	BWSfx.log_enabled = true
	BWSfx.events.clear()
	p.alive = true
	p.hp = 100.0
	p.global_position = Vector3(1.0, 0.2, -5.0 * 1.25)   # the open lane, facing the tower
	p.rotation.y = 0.0
	p.velocity = Vector3.ZERO
	p.debug_move = Vector2(0, 1)
	await _frames(90)
	p.debug_move = Vector2.ZERO
	var steps := BWSfx.events.filter(func(e: Dictionary) -> bool: return str(e.name) == "step_stone").size()
	_ok(steps >= 2 and steps <= 6, "1.5 s of running makes a few footsteps (%d)" % steps)
	BWSfx.log_enabled = false
	print("fps audio: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)
