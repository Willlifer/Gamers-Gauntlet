extends SceneTree
## Windowed: the FPS prototype's frames at scripted moments (hip, scoped 4x,
## running with the reticle open, crouch, prone, shotgun mid-pump, slingshot
## drawn, the bot up close, the bolt mid-cycle), saved to design/shots/fps/
## and as one sheet. G51: the sights' pictures (automatic rifle hip and
## aimed, marksman hip), the pistols aimed in at a foot, a bullet trail
## fading in from the barrel, and a muzzle flash per gun. Exit 0.
##   [MAP=campus] godot --path . --script res://tools/fps_shots.gd

var out := ""
var w: FpsWorld
var shots: Array[Image] = []


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	FpsWorld.ask_loadout = false
	out = ProjectSettings.globalize_path("res://").path_join("../design/shots/fps").simplify_path()
	if OS.get_environment("MAP") != "":
		out = out.path_join(OS.get_environment("MAP"))         # MAP=campus: that map's frames in their own folder
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_go.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	shots.append(img)
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _look_at(p: Vector3) -> void:
	var pl := w.player
	var d := p - pl.cam.global_position
	pl.rotation.y = atan2(-d.x, -d.z)
	pl._pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _go() -> void:
	w = FpsWorld.new()
	if OS.get_environment("MAP") != "":
		w.map_id = OS.get_environment("MAP")
	root.add_child(w)
	await _wait(1.0)
	var pl := w.player
	var bot := w.bot
	bot.set_physics_process(false)          # hold the bot still for framing
	pl.shielded = true                      # and keep the player alive through the walk
	_look_at(bot.eye())
	await _wait(0.6)
	await _shot("1_hip")
	pl.debug_aim = true
	await _wait(0.6)
	await _shot("2_scoped_4x")
	pl.debug_aim = false
	pl.rotation.y += 0.6
	pl.debug_move = Vector2(0, 1)
	await _wait(0.5)
	await _shot("3_running_reticle_open")
	pl.debug_move = Vector2.ZERO
	await _wait(0.5)
	await _shot("4_stopped_reticle_closed")
	pl.stance = "crouch"
	await _wait(0.6)
	await _shot("5_crouch")
	pl.stance = "prone"
	await _wait(0.8)
	await _shot("6_prone")
	pl.stance = "stand"
	_look_at(bot.eye())
	await _wait(0.5)
	pl.debug_fire = true
	await _wait(0.05)
	pl.debug_fire = false
	await _wait(0.35)
	await _shot("7_bolt_cycle")
	pl._switch("shotgun")
	await _wait(0.6)
	pl.debug_fire = true
	await _wait(0.05)
	pl.debug_fire = false
	await _wait(0.25)
	await _shot("8_shotgun_pump")
	pl._switch("slingshot")
	await _wait(0.6)
	pl.debug_fire = true
	await _wait(0.8)
	await _shot("9_slingshot_drawn")
	pl.debug_fire = false
	# the bot up close: put the player on the bot's roof, a few metres away
	pl._switch("sniper")
	bot.set_physics_process(true)
	var bp := bot.global_position
	pl.global_position = bp + Vector3(5.0, 0.2, 3.0)
	await _wait(0.4)
	_look_at(bot.eye() + Vector3(0, -0.5, 0))
	await _wait(1.6)
	await _shot("10_bot_close")
	# G43: the radial loadout, then the dual Berettas and their trick reload
	bot.set_physics_process(false)
	FpsWorld.ask_loadout = true
	w.open_loadout()
	await _wait(1.0)
	await _shot("11_radial")
	if w._menu:
		w._menu.toggle_options()                # G51: the shooter's settings, in the buy phase
		await _wait(0.4)
		await _shot("11b_radial_options")
		w._menu.toggle_options()
	if w._menu:
		w._menu._pick("dual_berettas" if FpsWeapons.available("dual_berettas") else "sniper")
	FpsWorld.ask_loadout = false
	await _wait(0.8)
	await _shot("12_loadout_in_hand")
	# G51b: the F1 panel's recoil presets (scrolled to the bottom)
	if w._menu == null:
		w._toggle_tune()
		await _wait(0.2)
		for sc in w._tune.find_children("*", "ScrollContainer", true, false):
			(sc as ScrollContainer).scroll_vertical = 100000
		await _wait(0.3)
		await _shot("11c_tune_recoil_presets")
		w._toggle_tune()
	if pl.weapon == "dual_berettas":
		pl.ammo.dual_l = 0
		pl._reload()
		await _wait(0.12)
		await _shot("13_duals_mags_drop")
		await _wait(0.55)
		await _shot("14_duals_flip")
		await _wait(0.6)
		await _shot("15_duals_catch")
	# G51: the sights' pictures, the pistols aimed in, a trail, the flashes
	pl.shielded = true
	bot.set_physics_process(false)
	_look_at(bot.eye())
	for g in [["auto_rifle", "16_auto_rifle_lens_hip", false], ["auto_rifle", "17_auto_rifle_lens_aimed", true], ["marksman", "18_marksman_lens_hip", false],
			["pistol", "19_pistol_aimed", true], ["deagle", "20_deagle_aimed", true]]:
		if not FpsWeapons.available(str(g[0])):
			continue
		pl.set_loadout(str(g[0]), "pistol")
		pl.debug_aim = bool(g[2])
		await _wait(0.8)
		await _shot(str(g[1]))
	pl.debug_aim = false
	# a trail seen from beside the shot: step aside, fire past the bot
	pl.set_loadout("sniper", "pistol")
	await _wait(0.6)
	pl.debug_fire = true
	await _wait(0.03)
	pl.debug_fire = false
	await _wait(0.02)
	await _shot("21_trail_from_barrel")
	var n := 22
	for id in FpsWeapons.ORDER:
		if id == "slingshot" or id == "dual_berettas" or not FpsWeapons.available(id):
			continue
		pl.set_loadout(id, "pistol")
		await _wait(0.7)
		pl._cool = 0.0
		pl._held_before = false
		pl.vm.flash_seed = 7
		pl.debug_fire = true
		await physics_frame
		await process_frame
		pl.debug_fire = false
		# hold the flash at a fixed moment (seeded) for the review
		pl.vm._flash.set_process(false)
		pl.vm._flash._shape(0.15)
		pl.vm._flash.visible = true
		await _shot("%d_flash_%s" % [n, id])
		pl.vm._flash.set_process(true)
		n += 1
	# G51c: every optic on the automatic rifle and the carbine, aimed in (and
	# the red dot at the hip); the scoped rifles at the hip and half aimed in
	_look_at(bot.eye())
	for id in ["auto_rifle", "carbine"]:
		if not FpsWeapons.available(id):
			continue
		for k: String in FpsWeapons.OPTIC_ORDER:
			FpsTune.set_optic(id, k)
			pl.set_loadout(id, "pistol")
			pl.debug_aim = true
			await _wait(0.8)
			await _shot("%d_optic_%s_%s_aimed" % [n, id, k])
			n += 1
			if k == "red_dot":
				pl.debug_aim = false
				await _wait(0.6)
				await _shot("%d_optic_%s_%s_hip" % [n, id, k])
				n += 1
		FpsTune.set_optic(id, str(FpsWeapons.SPECS[id].optics.default))
	pl.debug_aim = false
	for id in ["sniper", "marksman"]:
		pl.set_loadout(id, "pistol")
		await _wait(0.8)
		await _shot("%d_scope_%s_hip" % [n, id])
		n += 1
		pl.debug_aim = true
		await _wait(FpsTune.value("ads_time") * 0.55)
		await _shot("%d_scope_%s_half_aimed" % [n, id])
		n += 1
		pl.debug_aim = false
		await _wait(0.5)
	for id in ["pistol", "deagle"]:
		pl.set_loadout("sniper", id)
		pl._switch(id)
		pl.debug_aim = true
		await _wait(0.8)
		await _shot("%d_%s_aimed_arms_length" % [n, id])
		n += 1
		pl.debug_aim = false
	# G51c: a shot across the court, roof A to roof B, the bullet in the air
	if w.map_id == "rooftop":
		bot.set_physics_process(false)
		pl.set_loadout("sniper", "pistol")
		pl.global_position = Vector3(-9.0 * 1.25 - 3.0, w.map.meta.roof_height + 0.05, -12.0)
		bot.global_position = Vector3(9.0 * 1.25 + 4.0, w.map.meta.roof_height + 0.05, -14.0)
		await _wait(0.8)
		_look_at(bot.eye())
		await _wait(0.3)
		pl._cool = 0.0
		pl._held_before = false
		pl.debug_fire = true
		await physics_frame
		await physics_frame
		pl.debug_fire = false
		await _shot("%d_across_the_court" % n)
		n += 1
		await _wait(0.4)
		await _shot("%d_across_the_court_hit" % n)
		n += 1
	# sheet: 5 across, as many rows as frames
	var rows := ceili(shots.size() / 5.0)
	var sheet := Image.create(1600, 180 * rows, false, Image.FORMAT_RGB8)
	for i in shots.size():
		var t := shots[i].duplicate() as Image
		t.convert(Image.FORMAT_RGB8)
		t.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(t, Rect2i(0, 0, 320, 180), Vector2i((i % 5) * 320, (i / 5) * 180))
	sheet.save_png(out.path_join("sheet.png"))
	quit(0)
