extends SceneTree
## Windowed: frame timings for FPS: Extraction against the campus duel (the
## baseline the author called fine). Loads the map, stands the player at the
## spawn and a few spots (a lot, the map's middle, a pad), looks four ways at
## each, lets it settle, then samples frames with vsync off and prints, per
## spot: fps, frame ms (wall), CPU process / physics ms, GPU ms, draw calls,
## objects, primitives; then the scene's counts (mesh instances, surfaces,
## collision shapes, lights, guards). Guards run (the AI is part of the cost);
## last, every guard is alerted (G65: they start calm) and the middle sampled
## again, the old worst case.
##   [SEED=7] [MAPS=extract,campus] [FRAMES=90] godot --path . --script res://tools/extract_perf.gd
## Exit 0.

var frames := 90
var lines: Array[String] = []


func _initialize() -> void:
	FpsTune.use_defaults()
	FpsBinds.defaults_only = true
	FpsWorld.ask_loadout = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if OS.get_environment("FRAMES") != "":
		frames = int(OS.get_environment("FRAMES"))
	_go.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _look(pl: FpsPlayer, yaw: float) -> void:
	pl.rotation.y = yaw
	pl._pitch = -0.05


## Samples `frames` frames; returns the averages.
func _sample() -> Dictionary:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 8:
		await process_frame
	var acc := { "wall": 0.0, "proc": 0.0, "phys": 0.0, "gpu": 0.0, "cpu_r": 0.0, "draws": 0.0, "objs": 0.0, "prims": 0.0 }
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		worst = maxf(worst, dt)
		acc.wall += dt
		acc.proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		acc.phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		acc.gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		acc.cpu_r += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		acc.draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		acc.objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		acc.prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	for k in acc:
		acc[k] = acc[k] / frames
	acc["fps"] = 1000.0 / acc.wall
	acc["worst"] = worst
	return acc


func _row(tag: String, a: Dictionary) -> String:
	return "%-22s fps %6.1f  frame %6.2f ms (worst %6.1f)  proc %5.2f  phys %5.2f  gpu %6.2f  rcpu %5.2f  draws %6d  objs %5d  prims %8d" % [
		tag, a.fps, a.wall, a.worst, a.proc, a.phys, a.gpu, a.cpu_r, int(a.draws), int(a.objs), int(a.prims)]


func _counts(w: FpsWorld) -> String:
	var mis := 0
	var surf := 0
	var shapes := 0
	var lights := 0
	var mms := 0
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			mis += 1
			surf += (n as MeshInstance3D).mesh.get_surface_count()
		elif n is MultiMeshInstance3D:
			mms += 1
		elif n is CollisionShape3D:
			shapes += 1
		elif n is Light3D:
			lights += 1
		stack.append_array(n.get_children())
	var guards: int = (w as ExtractWorld).guards.size() if w is ExtractWorld else 1
	return "  nodes: mesh instances %d (surfaces %d), multimeshes %d, collision shapes %d, lights %d, bots %d, physics active %d, nav polys %d" % [
		mis, surf, mms, shapes, lights, guards, Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), w.nav.polygons if w.nav else 0]


func _spots(w: FpsWorld) -> Array:
	var out: Array = [["spawn", w.player.global_position]]
	if w is ExtractWorld:
		var ew := w as ExtractWorld
		var bl: Array = ew.map.meta.get("buildings", [])
		if not bl.is_empty():
			var b: AABB = bl[0].aabb
			var g := ew.ground(b.get_center() + Vector3(b.size.x * 0.5 + 4.0, 0, 0))
			if g != Vector3.INF:
				out.append(["lot", g + Vector3(0, 0.3, 0)])
		var mid := ew.ground(Vector3(0, 0, 0))
		if mid != Vector3.INF:
			out.append(["middle", mid + Vector3(0, 0.3, 0)])
		if not ew.pad_pos.is_empty():
			out.append(["pad", (ew.pad_pos[0] as Vector3) + Vector3(0, 0.3, 0)])
	return out


func _run(map: String) -> void:
	var w: FpsWorld
	if map == "extract":
		var ew := ExtractWorld.new()
		ew.match_seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
		w = ew
	else:
		w = FpsWorld.new()
		w.map_id = map
		w.match_seed = 7
	var t0 := Time.get_ticks_msec()
	root.add_child(w)
	var load_ms := Time.get_ticks_msec() - t0
	await _wait(1.5)
	var pl := w.player
	pl.shielded = true
	if w is ExtractWorld:
		(w as ExtractWorld).clock = 9999.0
	lines.append("== %s (load %d ms)" % [map, load_ms])
	var all := { "fps": 0.0, "wall": 0.0, "n": 0 }
	for s: Array in _spots(w):
		pl.global_position = s[1]
		pl.velocity = Vector3.ZERO
		for k in 4:
			_look(pl, k * PI * 0.5)
			await _wait(0.25)
			var a := await _sample()
			lines.append(_row("%s %s" % [s[0], ["N", "W", "S", "E"][k]], a))
			print(lines[-1])
			all.wall += a.wall
			all.n += 1
	lines.append("  mean frame %.2f ms (%.1f fps)" % [all.wall / all.n, 1000.0 * all.n / all.wall])
	if w is ExtractWorld:
		# the old worst case: every guard hostile, looking for you across the map
		var ew := w as ExtractWorld
		for g: ExtractGuard in ew.guards:
			g.alert()
		var mid := ew.ground(Vector3.ZERO)
		pl.global_position = (mid if mid != Vector3.INF else pl.global_position) + Vector3(0, 0.3, 0)
		for k in 2:
			_look(pl, k * PI)
			await _wait(1.0)
			var a := await _sample()
			lines.append(_row("hostile middle %s" % ["N", "S"][k], a))
			print(lines[-1])
	lines.append(_counts(w))
	print(lines[-2])
	print(lines[-1])
	w.queue_free()
	await _wait(0.5)


func _go() -> void:
	var maps := (OS.get_environment("MAPS") if OS.get_environment("MAPS") != "" else "extract,campus").split(",")
	for m in maps:
		await _run(m)
	print("\n".join(lines))
	quit(0)
