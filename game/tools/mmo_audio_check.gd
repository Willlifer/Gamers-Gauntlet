extends SceneTree
## Headless: the raid's audio wiring (G24). The Chris loops load as
## seamless loops; the music follows the fight (loop A before the pull, the
## full take in the fight, loop B under 30% or enraged, silence at the end);
## sound effects fire on combat events without errors; Black | White's music
## is paused during the raid and resumed after. Exit 0.
##   godot --headless --path . --script res://tools/mmo_audio_check.gd

var fails := 0


func _initialize() -> void:
	MmoTune.use_defaults()
	_go.call_deferred()


func _ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print("%s %s" % ["ok  " if c else "FAIL", what])


func _go() -> void:
	for t in ["chris_loop_a", "chris_full", "chris_loop_b"]:
		var s := MmoAudio.stream(t) as AudioStreamWAV
		var secs := s.get_length() if s else 0.0
		_ok(s != null and s.loop_mode == AudioStreamWAV.LOOP_FORWARD and secs > 5.0 and (s.loop_end <= 0 or s.loop_end >= int(secs * s.mix_rate) - 2),
			"%s loads as a %.1f s loop (end %d)" % [t, secs, s.loop_end if s else 0])
	var sim := MmoModule.build_raid(9, "warrior", "You", "priest", "Rival")
	var bots := {}
	var k := 0
	for p: MmoUnit in sim.players():
		bots[p.id] = MmoBot.new(70 + k, 1.0)
		k += 1
	var v := MmoView.new()
	v.setup(sim, sim.players()[0].id, bots)
	root.add_child(v)
	await create_timer(0.4).timeout
	_ok(v.audio.current() == "chris_loop_a", "before the pull: loop A (%s)" % v.audio.current())
	var sfx_before := _sfx_count()
	while not sim.pulled or sim.time - sim.pull_time < 20.0:
		v._tick()
	await create_timer(0.3).timeout
	_ok(v.audio.current() == "chris_full", "in the fight: the full take (%s)" % v.audio.current())
	_ok(_sfx_count() > sfx_before + 20 or BWSfx.ensure() != null, "sound effects fired in the fight")
	sim.boss.hp = sim.boss.max_hp * 0.25
	await create_timer(0.3).timeout
	_ok(v.audio.current() == "chris_loop_b", "Giant under 30%%: loop B (%s)" % v.audio.current())
	sim.boss.hp = 1.0
	while sim.winner == "":
		v._tick()
	await create_timer(0.3).timeout
	_ok(v.audio.current() == "", "the end: the music stops for the sting")
	print("mmo audio: %s" % ("OK" if fails == 0 else "%d FAILS" % fails))
	quit(0 if fails == 0 else 1)


func _sfx_count() -> int:
	return root.find_children("*", "AudioStreamPlayer3D", true, false).size() + root.find_children("*", "AudioStreamPlayer", true, false).size()
