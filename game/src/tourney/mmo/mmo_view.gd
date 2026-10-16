class_name MmoView
extends Node3D
## The raid on screen (G22): the courtyard, the six dressed classes and the
## Giant, WoW Classic's third-person camera and movement, telegraphs and
## effects, nameplates and floating combat text, MmoHud. Feeds the human's
## orders and the bots' to MmoSim at 30 Hz and draws between ticks.
##
## Controls (WoW Classic defaults):
##   W / S          run forward / backpedal          A / D   turn (strafe with RMB held)
##   Q / E          strafe                           Space   jump
##   hold RMB       steer: the mouse turns you and the camera
##   hold LMB       look around without turning      both    run forward
##   wheel          zoom in / out                    Num Lock  autorun
##   1-8, Shift+1-8 the two action bars              Tab     target the Giant
##   click          target a unit (or its frame)     RMB click an enemy: attack
##   F2 / F3-F7     target yourself / a party member Esc     clear the target
##   F1             the feel-number panel (MmoTune)

signal match_over(result: Dictionary)

const HEAD := 2.05                         # camera pivot above the feet (the 2.2 m body)
const PICK_PX := 70.0

var sim: MmoSim
var me_id := ""
var bots := {}                             # unit id -> MmoBot
var names := {}

var _acc := 0.0
var _prev := {}                            # id -> [pos, h, yaw]
var _views := {}                           # id -> { root, char, pose, ... }
var _cam: Camera3D
var _hud: MmoHud
var _fx: BWVfxCasts
var _areas := {}                           # area id -> Node3D
var _shots: Array = []                     # { node, src, tgt, t, total, from }
var _floaters: Array = []
var _sel: MeshInstance3D
var _plate: Control
var _over_t := -1.0
var _tune: MmoTunePanel
var _shake := 0.0

# camera and input state
var cam_yaw_off := 0.0                     # the camera's yaw relative to the character
var cam_pitch := 24.0
var cam_dist := 11.0
var _lmb := false
var _rmb := false
var _drag := 0.0
var _press_pos := Vector2.ZERO
var _autorun := false
var _jump := false
var _queued_slot := -1
var _target_req := ""
var _auto_req := -1
var _stop_req := false
var _mouse_restore := Vector2.ZERO
var input_on := true
var cam_hold := false                      ## tools: the camera is placed by hand
var hold_sim := false                      ## G52b: the raid waits (the first-time card is up)
var audio: MmoAudio
var tank_view: MmoTankView                 ## Planet of Tanks (G46): the tank's own drawing


func setup(p_sim: MmoSim, p_me: String, p_bots: Dictionary, p_names: Dictionary = {}) -> void:
	sim = p_sim
	me_id = p_me
	bots = p_bots
	names = p_names


func _ready() -> void:
	cam_pitch = MmoTune.value("cam_pitch")
	cam_dist = MmoTune.value("cam_dist")
	var stage := GKStage.outdoor(MmoTankArena.lights() if sim.tank else MmoArena.lights())
	add_child(stage)
	if sim.tank:
		MmoTankArena.build(self)
		tank_view = MmoTankView.new(self)
		add_child(tank_view)
	else:
		MmoArena.build(self)
	BWVfxCasts.tint_over = { "water": Color("#b47cff") }
	_fx = BWVfxCasts.new()
	add_child(_fx)
	_cam = Camera3D.new()
	_cam.fov = MmoTune.value("cam_fov")
	_cam.far = 400.0
	add_child(_cam)
	_cam.make_current()
	_sel = _ring_mesh(1.0, Color(1, 0.2, 0.15, 0.95), 0.08)
	_sel.visible = false
	for u: MmoUnit in sim.units:
		_add_unit(u)
		_prev[u.id] = [u.pos, u.h, u.yaw]
	_hud = MmoHud.new()
	_hud.sim = sim
	_hud.me_id = me_id
	_hud.view = self
	add_child(_hud)
	_portraits()
	_plate = BossPlate.new(self)
	_hud.add_child(_plate)
	audio = MmoAudio.new()
	audio.view = self
	add_child(audio)
	_place_camera(1.0)
	var me := sim.unit(me_id)
	if me:
		_hud.log_line("You join the raid as a %s." % MmoClasses.CLASSES[me.cls].name, Color("#ffd100"))
		_hud.log_line("Tab targets " + ("the Tank" if sim.tank else "the Giant") + "; 1-8 and Shift+1-8 use your abilities.", Color("#ffff80"))
		_hud.log_line("WASD move, Q/E strafe, hold right mouse to steer, wheel zooms, F1 tunes.", Color("#ffff80"))


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ units

static func unit_look(u: MmoUnit) -> BWUnit:
	if u.kind == "boss":
		return MobaLook.boss_unit()
	var c: Dictionary = MmoClasses.CLASSES[u.cls]
	var lk: Dictionary = c.look
	var b := BWUnit.new()
	b.id = u.id
	b.name = u.name
	b.team = "player"
	b.weapon_model = str(lk.weapon)
	b.weapon_class = str(BWWeaponView.meta_for(str(lk.weapon)).get("class", "sword"))
	b.cosmetics = { "hair_style": str(lk.hair), "hair_hex": str(lk.hair_hex), "gender": str(lk.gender),
		"top": str(lk.top), "bottom": str(lk.bottom), "clothing_shade": "mid" }
	for slot: String in ["head", "chest", "legs"]:
		if lk.has(slot) and BWEquipmentView.has_model(str(lk[slot])):
			b.equipment[slot] = { "base": str(lk[slot]), "slot": slot, "element": str(lk.get("accent", "")) }
	for s in BWUnit.STATS:
		b.stats[s] = 6
	b.hp = b.max_hp()
	return b


static func dress(u: MmoUnit) -> BWCharacter:
	var ch := BWCharacter.create(unit_look(u))
	if u.kind == "boss":
		MobaLook.tint(ch, MobaLook.BOSS)
	else:
		var lk: Dictionary = MmoClasses.CLASSES[u.cls].look
		_tint_class(ch, Color(str(lk.tint)), Color(str(lk.hair_hex)))
	return ch


## Clothes, armour and weapon in the class colour; skin a warm tone; the
## hair its own colour (the outlines stay black).
static func _tint_class(n: Node, col: Color, hair: Color) -> void:
	if n is GeometryInstance3D and not n is Label3D:
		var path := MobaLook._shader_path(n as GeometryInstance3D)
		var t := Color(1, 1, 1)
		if path.contains("hair"):
			t = Color.WHITE
		elif path.contains("equipment"):
			t = col.lerp(Color.WHITE, 0.35)
		elif path.contains("clothing"):
			t = col.lerp(Color(0.2, 0.2, 0.22), 0.35)
		elif path.contains("weapon"):
			t = Color(0.95, 0.92, 0.85)
		else:
			t = Color("#f2c9a8")
		(n as GeometryInstance3D).set_instance_shader_parameter("tint", t)
	if n is BWCharacter and (n as BWCharacter).hair:
		(n as BWCharacter).hair.set_color(hair)
	for c in n.get_children():
		_tint_class(c, col, hair)


func _add_unit(u: MmoUnit) -> void:
	var root := Node3D.new()
	add_child(root)
	if tank_view and u.kind != "player":
		_add_vehicle(u, root)
		return
	var ch := dress(u)
	root.add_child(ch)
	var vehicle := ""
	if u.kind == "player":
		vehicle = str(MmoClasses.CLASSES[u.cls].get("vehicle", ""))
	if vehicle != "":
		ride(root, ch, vehicle)
	if u.kind == "boss":
		root.scale = Vector3.ONE * MmoTune.value("boss_scale")
	var name_l := Label3D.new()
	name_l.text = u.name
	name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_l.fixed_size = true
	name_l.pixel_size = 0.0009
	name_l.font_size = 22 if u.kind != "boss" else 26
	name_l.outline_size = 8
	name_l.no_depth_test = true
	name_l.modulate = Color("#ff3a2a") if u.kind == "boss" else MmoClasses.color(u.cls)
	name_l.outline_modulate = Color(0, 0, 0, 0.9)
	name_l.font = MmoHud._font(["Friz Quadrata TT", "Palatino Linotype", "Georgia"], 600)
	name_l.position = Vector3(0, 2.55 if u.kind != "boss" else 2.6, 0)
	name_l.visible = u.id != me_id
	root.add_child(name_l)
	_views[u.id] = { "root": root, "char": ch, "pose": "", "cast": u.cast_serial, "strike": u.strike_serial, "hit": u.hit_serial,
		"anim_t": 0.0, "name": name_l, "move": "", "move_t": 0.0, "glow": null }
	ch.pose("idle")


## Planet of Tanks (G46): the boss tank or a light tank, no character inside.
func _add_vehicle(u: MmoUnit, root: Node3D) -> void:
	var name_l := Label3D.new()
	name_l.text = u.name
	name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_l.fixed_size = true
	name_l.pixel_size = 0.0009
	name_l.font_size = 22
	name_l.outline_size = 8
	name_l.no_depth_test = true
	name_l.modulate = Color("#ff3a2a")
	name_l.outline_modulate = Color(0, 0, 0, 0.9)
	name_l.font = MmoHud._font(["Friz Quadrata TT", "Palatino Linotype", "Georgia"], 600)
	root.add_child(name_l)
	var v := { "root": root, "char": null, "pose": "", "cast": u.cast_serial, "strike": u.strike_serial, "hit": u.hit_serial,
		"anim_t": 0.0, "name": name_l, "move": "", "move_t": 0.0, "glow": null }
	tank_view.build_unit(u, root, v)
	name_l.position = Vector3(0, float(v.plate_h) + 0.4, 0)
	_views[u.id] = v
	_prev[u.id] = [u.pos, u.h, u.yaw]


## A hidden class's vehicle (G44): the kit model shrunk to raid size around
## the crewman, who stands in the hatch with only the top half showing.
const VEHICLE_SCALE := 0.42


static func ride(root: Node3D, ch: Node3D, vehicle_id: String) -> void:
	if GKRegistry.def(vehicle_id) == null:
		return
	var a := GKRegistry.build(vehicle_id, { "scale": VEHICLE_SCALE })
	var n := a.instantiate(false)
	n.name = "Vehicle"
	# the kit's front is +Z after the glTF flip; the characters face +Z too
	root.add_child(n)
	var hatch := a.marker("hatch").origin if a.markers.has("hatch") else Vector3(0, a.aabb().end.y, 0)
	ch.scale = Vector3.ONE * 0.62
	ch.position = hatch + Vector3(0, -0.72, 0)


## Round portraits for the frames: each unit dressed again in a little
## studio of its own, photographed head and shoulders.
func _portraits() -> void:
	for u: MmoUnit in sim.units:
		var vp := SubViewport.new()
		vp.size = Vector2i(128, 128)
		vp.own_world_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("#2a2620") if u.kind != "boss" else Color("#3a1a2a")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#c8bca8")
		env.ambient_light_energy = 0.7
		we.environment = env
		vp.add_child(we)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-30, 30, 0)
		l.light_energy = 1.2
		vp.add_child(l)
		var cam := Camera3D.new()
		cam.fov = 30.0
		if tank_view and u.kind != "player":
			var tk := GKRegistry.build("tank").instantiate(false)
			tk.rotation.y = 0.5
			vp.add_child(tk)
			vp.add_child(cam)
			cam.position = Vector3(1.0, 4.2, 9.5)
			cam.look_at(Vector3(0, 2.2, 0))
		else:
			var ch := dress(u)
			vp.add_child(ch)
			vp.add_child(cam)
			var head_y := 1.86
			cam.position = Vector3(0.25, head_y + 0.08, 1.25)
			cam.look_at(Vector3(0, head_y - 0.02, 0))
		cam.make_current()
		_hud.portraits[u.id] = vp.get_texture()
		var v := vp
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if is_instance_valid(v):
				v.render_target_update_mode = SubViewport.UPDATE_DISABLED)


# ------------------------------------------------------------------ input

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_F1:
		_toggle_tune()
		return
	if not input_on:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					cam_dist = clampf(cam_dist / MmoTune.value("zoom_step"), MmoTune.value("cam_min"), MmoTune.value("cam_max"))
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					cam_dist = clampf(cam_dist * MmoTune.value("zoom_step"), MmoTune.value("cam_min"), MmoTune.value("cam_max"))
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				var left := mb.button_index == MOUSE_BUTTON_LEFT
				if mb.pressed:
					if not _lmb and not _rmb:
						_press_pos = mb.position
						_drag = 0.0
						_mouse_restore = mb.position
					if left:
						_lmb = true
					else:
						_rmb = true
						_steer_now()
				else:
					if left:
						_lmb = false
					else:
						_rmb = false
					if _drag < 5.0:
						_click(mb.position, not left)
					if not _lmb and not _rmb and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
						Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
						Input.warp_mouse(_mouse_restore)
	elif ev is InputEventMouseMotion and (_lmb or _rmb):
		var mm := ev as InputEventMouseMotion
		_drag += mm.relative.length()
		if _drag >= 5.0 and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _drag >= 5.0:
			var s := MmoTune.value("mouse_sens")
			cam_pitch = clampf(cam_pitch + mm.relative.y * s, -60.0, 85.0)
			if _rmb:
				_steer(-mm.relative.x * s)
			else:
				cam_yaw_off = wrapf(cam_yaw_off - deg_to_rad(mm.relative.x * s), -PI, PI)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		var code := k.physical_keycode
		if code >= KEY_1 and code <= KEY_8:
			press_slot(int(code - KEY_1) + (8 if k.shift_pressed else 0))
		elif code == KEY_SPACE:
			_jump = true
		elif code == KEY_TAB:
			set_target("boss")
		elif code == KEY_NUMLOCK:
			_autorun = not _autorun
		elif code == KEY_ESCAPE:
			if sim.unit(me_id) and sim.unit(me_id).casting():
				_stop_req = true
			else:
				set_target("")
		elif code == KEY_F2:
			set_target(me_id)
		elif code >= KEY_F3 and code <= KEY_F7:
			var others := sim.players().filter(func(p: MmoUnit) -> bool: return p.id != me_id)
			var i := int(code - KEY_F3)
			if i < others.size():
				set_target((others[i] as MmoUnit).id)
		elif code in [KEY_W, KEY_S, KEY_Q, KEY_E] and _autorun:
			if code == KEY_W or code == KEY_S:
				_autorun = false


## RMB held: the character turns with the camera (WoW's mouse steering).
var _steer_yaw := INF


func _steer_now() -> void:
	var me := sim.unit(me_id)
	if me:
		_steer_yaw = wrapf(me.yaw + cam_yaw_off, -PI, PI)
		cam_yaw_off = 0.0


func _steer(dx_deg: float) -> void:
	var me := sim.unit(me_id)
	if me == null:
		return
	if _steer_yaw == INF:
		_steer_yaw = me.yaw
	_steer_yaw = wrapf(_steer_yaw + deg_to_rad(dx_deg), -PI, PI)


func press_slot(slot: int) -> void:
	var me := sim.unit(me_id)
	if me == null:
		return
	_queued_slot = slot
	_hud.flash_slot(slot)


## The four utility buttons on the top bar's right (click only).
func utility(i: int) -> void:
	match i:
		0: _auto_req = 1
		1: _stop_req = true
		2: set_target("boss")
		3: set_target(me_id)


func set_target(id: String) -> void:
	_target_req = id if id != "" else "-"


func _click(at: Vector2, right: bool) -> void:
	var u := _pick(at)
	if u:
		set_target(u.id)
		if right and u.kind == "boss":
			_auto_req = 1
	elif not right:
		set_target("")


func _pick(at: Vector2) -> MmoUnit:
	var best: MmoUnit = null
	var bd := PICK_PX
	for u: MmoUnit in sim.units:
		if not _views.has(u.id):
			continue
		var root: Node3D = _views[u.id].root
		var hgt := 1.1 * root.scale.y
		var wp := root.global_position + Vector3(0, hgt, 0)
		if _cam.is_position_behind(wp):
			continue
		var sp := _cam.unproject_position(wp)
		var reach := bd * (2.5 if u.kind == "boss" else 1.0)
		var d := sp.distance_to(at)
		if d < reach and (best == null or d < bd):
			best = u
			bd = d
	return best


func _toggle_tune() -> void:
	if _tune:
		_tune.queue_free()
		_tune = null
		input_on = true
		return
	_tune = MmoTunePanel.new()
	add_child(_tune)
	input_on = false
	_lmb = false
	_rmb = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _my_order() -> Dictionary:
	var o := {}
	var me := sim.unit(me_id)
	if me == null:
		return o
	var fwd := 0.0
	var side := 0.0
	var turn := 0.0
	if input_on:
		if Input.is_physical_key_pressed(KEY_W):
			fwd += 1.0
		if Input.is_physical_key_pressed(KEY_S):
			fwd -= 1.0
		if Input.is_physical_key_pressed(KEY_Q):
			side -= 1.0
		if Input.is_physical_key_pressed(KEY_E):
			side += 1.0
		var a := Input.is_physical_key_pressed(KEY_A)
		var d := Input.is_physical_key_pressed(KEY_D)
		if _rmb:
			side += (1.0 if d else 0.0) - (1.0 if a else 0.0)
		else:
			turn += (1.0 if d else 0.0) - (1.0 if a else 0.0)
		if _lmb and _rmb:
			fwd = maxf(fwd, 1.0)
		if _autorun and fwd == 0.0:
			fwd = 1.0
	o["mv"] = Vector2(clampf(side, -1, 1), clampf(fwd, -1, 1))
	if turn != 0.0:
		o["turn"] = turn
	if _rmb and _steer_yaw != INF:
		o["yaw"] = _steer_yaw
	elif not _rmb:
		_steer_yaw = INF
	if _jump:
		o["jump"] = true
		_jump = false
	if _target_req != "":
		o["target"] = "" if _target_req == "-" else _target_req
		if _target_req == "-" or (sim.unit(_target_req) and not sim.is_enemy(me, sim.unit(_target_req))):
			o["auto"] = false
		_target_req = ""
	if _auto_req >= 0:
		o["auto"] = _auto_req == 1
		_auto_req = -1
	if _stop_req:
		o["stop"] = true
		_stop_req = false
	if _queued_slot >= 0:
		var abs: Array = MmoClasses.abilities(me.cls)
		if _queued_slot < abs.size():
			o["cast"] = str(abs[_queued_slot].id)
		elif not MmoItems.at_slot(_queued_slot).is_empty():
			o["cast"] = str(MmoItems.at_slot(_queued_slot).id)      # G52: Shift+1-8, the consumables
		_queued_slot = -1
	return o


# ------------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if sim == null:
		return
	_acc += minf(delta, 0.25)
	if hold_sim:
		_acc = 0.0
	while _acc >= MmoSim.TICK:
		_acc -= MmoSim.TICK
		_tick()
	_draw_units(clampf(_acc / MmoSim.TICK, 0.0, 1.0), delta)
	_sync_shots(delta)
	_sync_areas(delta)
	_sync_scorch(delta)
	if tank_view:
		tank_view.sync(delta)
	_tick_floaters(delta)
	audio.update(delta)
	_place_camera(delta)
	_hud.update(delta)
	if _over_t >= 0.0:
		_over_t += delta
		if _over_t > 1.5 and _over_t - delta <= 1.5:
			_report()
		if _over_t > REPORT_HOLD and _over_t - delta <= REPORT_HOLD:
			match_over.emit(result())


func _tick() -> void:
	for u: MmoUnit in sim.units:
		_prev[u.id] = [u.pos, u.h, u.yaw]
	var orders := {}
	for id: String in bots:
		orders[id] = (bots[id] as MmoBot).think(sim, sim.unit(id))
	if me_id != "" and not bots.has(me_id):
		orders[me_id] = _my_order()
	for e: Dictionary in sim.step(orders):
		_on_event(e)


## The end of the raid shows this long (the report card from 1.5 s), then the verdict.
const REPORT_HOLD := 11.0


## The report card (G33): the two contestants' grades, part by part.
func _report() -> void:
	var r := MmoReport.new()
	r.sim = sim
	r.me_id = me_id
	add_child(r)


## The raid's end; the module grades the contestants (MmoGrade).
func result() -> Dictionary:
	return { "winner": sim.winner, "time": sim.time - sim.pull_time }


# ----------------------------------------------------------------- events

func _on_event(e: Dictionary) -> void:
	audio.on_event(e)
	var me := sim.unit(me_id)
	match str(e.type):
		"error":
			if str(e.id) == me_id:
				_hud.error(str(e.text))
		"warn":
			_hud.warn(str(e.text), Color(str(e.get("col", "#ff8a2a"))), bool(e.get("always", false)))
		"pull":
			pass
		"dmg":
			var t := sim.unit(str(e.tgt))
			var s := sim.unit(str(e.src)) if str(e.src) != "" else null
			if t == null:
				return
			if str(e.tgt) == me_id or str(e.src) == me_id:
				_floater(t, ("%d" % int(e.n)) + ("!" if e.crit else ""), Color("#ffff40") if str(e.src) == me_id else Color("#ff3030"), bool(e.crit))
			if str(e.src) == me_id:
				_hud.log_line("Your %s %s %s for %d.%s" % [str(e.what), "crits" if e.crit else "hits", t.name, int(e.n), (" (%d absorbed)" % int(e.absorbed)) if float(e.absorbed) > 0.0 else ""], Color("#ffffa0"))
			elif str(e.tgt) == me_id:
				if float(e.n) <= 0.0 and float(e.absorbed) > 0.0:
					_hud.log_line("%s's %s hits you: %d absorbed." % [s.name if s else "Something", str(e.what), int(e.absorbed)], Color("#c0c0ff"))
				else:
					_hud.log_line("%s's %s hits you for %d." % [s.name if s else "Something", str(e.what), int(e.n)], Color("#ff8080"))
			if str(e.kind) == "mech" or (s and s.kind == "boss" and str(e.kind) == "auto"):
				_hit_fx(t, str(e.school))
			elif s and s.kind == "player" and str(e.kind) == "hit":
				_impact_on(t, str(e.school), 0.55)
		"heal":
			var t := sim.unit(str(e.tgt))
			if t and float(e.eff) > 0.0 and (str(e.src) == me_id or str(e.tgt) == me_id):
				_floater(t, "+%d" % int(e.eff), Color("#40ff40"), bool(e.crit))
			if str(e.src) == me_id and str(e.kind) != "hot":
				_hud.log_line("Your %s heals %s for %d." % [str(e.what), t.name if t else "?", int(e.eff)], Color("#80ff80"))
			if t and str(e.kind) != "hot":
				_heal_fx(t)
		"immune":
			var t := sim.unit(str(e.tgt))
			if t and (str(e.src) == me_id or str(e.tgt) == me_id):
				_floater(t, "Immune", Color(1, 1, 1), false)
		"use":
			var u := sim.unit(str(e.id))
			var ab := MmoClasses.ability(u.cls, str(e.ab))
			_use_fx(u, ab, sim.unit(str(e.target)) if str(e.target) != "" else null)
		"proj":
			_launch(str(e.src), str(e.tgt), str(e.ab), str(e.school), float(e.t))
		"burst":
			var bu := sim.unit(str(e.id))
			var bab := MmoClasses.ability(bu.cls, bu.last_ab) if bu and bu.kind == "player" else {}
			_shock(_v3(e.pos as Vector2), float(e.r), Color(str(bab.get("col", "#ffffff"))))
		"ground_tick":
			_ground_tick(e)
		"dash":
			var u := sim.unit(str(e.id))
			_prev[u.id] = [u.pos, u.h, u.yaw]
			_puff(_v3(e.from as Vector2), Color(0.8, 0.8, 1.0, 0.6))
			_puff(_v3(e.to as Vector2), Color(0.8, 0.8, 1.0, 0.6))
		"death":
			var u := sim.unit(str(e.id))
			if u:
				_hud.log_line("%s dies." % u.name, Color("#ff6060") if u.kind == "player" else Color("#ffd100"))
		"res":
			var u := sim.unit(str(e.id))
			_hud.log_line("%s is brought back to life." % u.name, Color("#80ff80"))
			_fx.release_at("light", _v3(u.pos), 1.2)
			if _views.has(u.id):
				(_views[u.id].char as BWCharacter).pose("idle")
				_views[u.id].pose = "idle"
		"cleansed":
			var u := sim.unit(str(e.id))
			_fx.release_at("ice", _v3(u.pos) + Vector3(0, 1.2, 0), 0.6)
		"taunt":
			_hud.log_line("%s taunts %s!" % [sim.unit(str(e.id)).name, sim.boss.name], Color("#ff9040"))
		"spawn":
			var su := sim.unit(str(e.id))
			if su and not _views.has(su.id):
				_add_unit(su)
			if su and su.kind == "add" and tank_view:
				tank_view.kick(su.pos)                          # G52b: the light tanks' arrival: dust and a nudge
				_shake = maxf(_shake, 0.55)
		"announce":
			# G52b: a stacked hit marker over everyone caught, not a banner
			if tank_view:
				tank_view.multi_hit(e.get("ids", []), int(e.get("n", 2)), float(e.get("mult", 1.0)))
			_hud.log_line("%s %s" % [str(e.text), str(e.get("sub", ""))], Color("#ffd040"))
		"frenzy":
			# G52b: the speed-up (Planet of Tanks 15%, the Giant's 25%) as a screen-edge pulse, the boss glowing
			_hud.edge_pulse(1.0)
			_hud.edge_base = maxf(_hud.edge_base, 0.3)
			_shake = maxf(_shake, 0.5)
			if not tank_view:
				_giant_rage(1)
		"enrage":
			_hud.edge_pulse(1.0)
			_hud.edge_base = maxf(_hud.edge_base, 0.65)
			_shake = maxf(_shake, 0.7)
			if not tank_view:
				_giant_rage(2)
		"area":
			_add_area(e.area as Dictionary)
		"area_end":
			pass
		"explode":
			_explode(e)
		"boss_spell":
			_boss_spell(e)
		"win":
			_over_t = 0.0
			if str(e.winner) == "raid":
				_hud.center("%s has been defeated!" % sim.boss.name, 6.0)
				_hud.log_line("%s has been defeated! %d s." % [sim.boss.name, int(sim.time - sim.pull_time)], Color("#ffd100"))
				for u: MmoUnit in sim.living():
					if _views.has(u.id):
						(_views[u.id].char as BWCharacter).pose("cheer")
						_views[u.id].pose = "cheer"
			else:
				_hud.center("Your raid has wiped.", 6.0)
	if me and str(e.type) == "death" and str(e.id) == me_id:
		_hud.warn("You died!", Color("#ff3030"))


func _boss_spell(e: Dictionary) -> void:
	if tank_view:
		if str(e.stage) == "cast" and str(e.spell) != "cannon":
			_hud.log_line("The Tank: %s..." % sim.spell_name(str(e.spell)).to_lower(), Color("#ff9040"))
		if str(e.spell) == "loose" and str(e.stage) == "volley":
			_shake = maxf(_shake, 0.35)
		if str(e.spell) == "ram" and str(e.stage) == "hit_edge":
			_shake = maxf(_shake, 0.9)
		return
	var v: Dictionary = _views.get("boss", {})
	match str(e.stage):
		"cast", "chain":
			if not sim.silent:
				_hud.log_line("The Giant begins to cast %s." % MmoSim.SPELL_NAMES.get(str(e.spell), ""), Color("#ff9040"))
			if not v.is_empty():
				v.move = "bombs" if str(e.spell) == "brand" else str(e.spell)      # Cinderbrand reuses the fling
				v.move_t = 0.0
		"fire":
			match str(e.spell):
				"upheaval":
					for a: Dictionary in e.get("lines", []):
						_spikes(a)
					_shake = 0.7
				"bombs":
					for u: MmoUnit in sim.living():
						_fx.release_at("fire", _v3(u.pos) + Vector3(0, 2.6, 0), 0.5)
				"gather":
					_fx.release_at("light", _v3(e.at as Vector2), 1.6)
				"brand":
					for u: MmoUnit in sim.living():
						_fx.release_at("fire", _v3(u.pos) + Vector3(0, 1.2, 0), 0.8)
					if not sim.silent:
						_hud.log_line("Cinderbrand burns the raid. Run it off, cleanse it or heal through it.", Color("#ff9040"))


# ------------------------------------------------------------------- draw

func _draw_units(alpha: float, delta: float) -> void:
	var me := sim.unit(me_id)
	var tgt := sim.unit(me.target) if me and me.target != "" else null
	for id: String in _views:
		var v: Dictionary = _views[id]
		var u := sim.unit(id)
		var root: Node3D = v.root
		var ch: BWCharacter = v.char
		var pv: Array = _prev.get(id, [u.pos, u.h, u.yaw])
		var p: Vector2 = (pv[0] as Vector2).lerp(u.pos, alpha)
		var hh := lerpf(float(pv[1]), u.h, alpha)
		root.position = Vector3(p.x, hh, p.y)
		var yaw := lerp_angle(float(pv[2]), u.yaw, alpha)
		if v.get("vehicle", false):
			root.rotation.y = yaw
			tank_view.pose(u, v, delta)
			(v.name as Label3D).visible = u.kind == "add" and u.alive
			continue
		# strafing: turn the body toward the run; backpedal: walk the clip backwards
		var mv := u.move
		var off := 0.0
		var back := false
		if u.kind == "player" and u.moving and u.alive:
			if mv.y < -0.01:
				back = true
				off = clampf(atan2(mv.x, -mv.y), -0.8, 0.8)
			else:
				off = clampf(atan2(-mv.x, mv.y), -1.25, 1.25)
		v["off"] = lerp_angle(float(v.get("off", 0.0)), off, minf(1.0, delta * 10.0))
		root.rotation.y = yaw + float(v.off)
		if ch.animator:
			ch.animator.reverse = back
		v.anim_t = float(v.anim_t) + delta
		_pose(u, v, delta)
		(v.name as Label3D).visible = id != me_id and (u.alive or u.kind == "player")
		if u.kind == "boss":
			(v.name as Label3D).visible = false
		# Cinderbrand (G30; G52: on fire, flames up the whole body and a flickering light)
		var branded := u.alive and u.kind == "player" and u.has_aura(MmoSim.BRAND)
		var bf: Variant = v.get("brand_fx")
		if branded and bf == null:
			bf = _brand_flames()
			root.add_child(bf)
			v["brand_fx"] = bf
		if bf != null:
			var flames: CPUParticles3D = (bf as Node3D).get_child(0)
			flames.emitting = branded
			var bl: OmniLight3D = (bf as Node3D).get_child(1)
			bl.light_energy = (2.2 + 0.8 * sin(Time.get_ticks_msec() / 45.0) + 0.5 * sin(Time.get_ticks_msec() / 17.0)) if branded else move_toward(bl.light_energy, 0.0, delta * 8.0)
		if branded:
			v["brand_t"] = float(v.get("brand_t", 0.0)) - delta
			if float(v.brand_t) <= 0.0:
				v.brand_t = 0.55
				_fx.release_at("fire", root.position + Vector3(0, 1.1, 0), 0.32)
	if tgt and _views.has(tgt.id):
		_sel.visible = tgt.alive
		var r := tgt.radius + 0.35
		_sel.scale = Vector3(r, 1, r)
		_sel.position = (_views[tgt.id].root as Node3D).position * Vector3(1, 0, 1) + Vector3(0, 0.04, 0)
		var col := Color(0.85, 0.15, 0.1, 0.55) if sim.is_enemy(me, tgt) else Color(1, 0.9, 0.2, 0.8)
		(_sel.material_override as StandardMaterial3D).albedo_color = col
	else:
		_sel.visible = false
	_plate.queue_redraw()
	_declutter()


## Nameplates that land on each other on screen: the farther one moves up.
func _declutter() -> void:
	var placed: Array = []
	var ids := _views.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return (_views[a].root as Node3D).global_position.distance_to(_cam.global_position) < (_views[b].root as Node3D).global_position.distance_to(_cam.global_position))
	for id: String in ids:
		var l: Label3D = _views[id].name
		var root: Node3D = _views[id].root
		l.position.y = 2.55
		if not l.visible:
			continue
		var wp := root.global_position + Vector3(0, 2.55, 0)
		if _cam.is_position_behind(wp):
			continue
		var sp := _cam.unproject_position(wp)
		var dist := wp.distance_to(_cam.global_position)
		var lift := 0.0
		for q: Vector2 in placed:
			if absf(q.x - sp.x) < 100.0 and absf(q.y - (sp.y - lift)) < 24.0:
				lift += 28.0
		l.position.y = 2.55 + lift * dist * 0.0011
		placed.append(Vector2(sp.x, sp.y - lift))


func _pose(u: MmoUnit, v: Dictionary, delta: float) -> void:
	var ch: BWCharacter = v.char
	if u.kind == "boss":
		_boss_pose(u, v, delta)
	if not u.alive:
		if v.pose != "fall":
			v.pose = "fall"
			ch.anim_speed = 1.0
			ch.pose("fall")
		return
	if v.pose == "fall":
		v.pose = ""
	if v.pose == "cheer":
		return
	if u.strike_serial != int(v.strike):
		v.strike = u.strike_serial
		v.pose = "strike"
		v.anim_t = 0.0
		ch.anim_speed = 1.8
		ch.pose("strike")
		return
	if u.casting() and u.kind == "player":
		if v.pose != "channel":
			v.pose = "channel"
			v.anim_t = 0.0
			ch.anim_speed = 1.0
			ch.pose("channel" if ch.has_clip("channel") else "cast")
		_cast_glow(u, v, true)
		return
	_cast_glow(u, v, false)
	if u.cast_serial != int(v.cast):
		v.cast = u.cast_serial
		if u.kind == "player":
			var ab := MmoClasses.ability(u.cls, u.last_ab)
			if str(ab.get("anim", "")) == "cast" or str(ab.get("anim", "")) == "channel":
				v.pose = "cast"
				v.anim_t = 0.0
				ch.anim_speed = 1.7
				ch.pose("cast" if ch.has_clip("cast") else "strike")
				return
	if v.pose in ["cast", "strike"] and float(v.anim_t) < 0.5 and not u.moving:
		return
	var want := "idle"
	if u.moving:
		want = "walk" if u.move.y < -0.01 or u.speed_now < 3.5 else "run"
		if not ch.has_clip(want):
			want = "walk"
	if v.pose != want:
		v.pose = want
		ch.anim_speed = 1.0
		ch.pose(want)


func _boss_pose(u: MmoUnit, v: Dictionary, delta: float) -> void:
	var ch: BWCharacter = v.char
	if str(v.move) == "":
		return
	v.move_t = float(v.move_t) + delta
	var t := float(v.move_t)
	var m := str(v.move)
	if t >= MmoMoves.length(m) or not u.alive:
		v.move = ""
		ch.poser.override = {}
		ch.poser.override_w = 1.0
		_hand_fx(v, "")
		return
	var want := ""
	if m == "meteors" and t > 0.45 and t < 5.1:
		want = "fire"
	elif m == "bombs" and t > 0.35 and t < 1.28:
		want = "bomb"
	_hand_fx(v, want)
	ch.poser.override = MmoMoves.sample(m, t)
	ch.poser.override_w = MmoMoves.weight(m, t)


func _hand_fx(v: Dictionary, kind: String) -> void:
	if str(v.get("hand_kind", "")) == kind:
		return
	var old: Variant = v.get("hand_fx")
	if old != null and is_instance_valid(old):
		(old as Node).queue_free()
	v["hand_kind"] = kind
	v["hand_fx"] = null
	if kind == "":
		return
	var ch: BWCharacter = v.char
	var sock := ch.rig.socket("offhand_l")
	if sock == null:
		return
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	if kind == "fire":
		sm.radius = 0.32
		sm.height = 0.64
		sm.material = _glow_mat(Color("#ff8a2a"))
		var light := OmniLight3D.new()
		light.light_color = Color("#ff7a30")
		light.light_energy = 3.0
		light.omni_range = 9.0
		n.add_child(light)
		var p := _sparkles(Color("#ff6a1a"))
		p.emission_sphere_radius = 0.3
		p.amount = 40
		p.local_coords = false
		p.scale_amount_min = 0.1
		p.scale_amount_max = 0.22
		n.add_child(p)
	else:
		sm.radius = 0.2
		sm.height = 0.4
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("#1a1a1e")
		bm.metallic = 0.6
		sm.material = bm
		var p := _sparkles(Color("#ffb030"))
		p.emission_sphere_radius = 0.04
		p.position = Vector3(0, 0.22, 0)
		n.add_child(p)
	m.mesh = sm
	n.add_child(m)
	sock.add_child(n)
	v["hand_fx"] = n


func _cast_glow(u: MmoUnit, v: Dictionary, on: bool) -> void:
	var g: Variant = v.get("glow")
	if on and g == null:
		var ab := MmoClasses.ability(u.cls, str(u.cast.get("ab", "")))
		var p := _sparkles(Color(str(ab.get("col", "#ffffff"))))
		(v.root as Node3D).add_child(p)
		p.position = Vector3(0, 1.1, 0.25)
		v["glow"] = p
	elif not on and g != null:
		if is_instance_valid(g):
			(g as Node).queue_free()
		v["glow"] = null


## G52: Cinderbrand sets you on fire: tongues of flame licking up the body
## (yellow at the root, red as they rise and fade), and a flickering orange light.
func _brand_flames() -> Node3D:
	var n := Node3D.new()
	var p := CPUParticles3D.new()
	p.amount = 140
	p.lifetime = 0.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.34, 0.7, 0.24)
	p.position = Vector3(0, 0.9, 0)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.9
	p.initial_velocity_max = 1.9
	p.gravity = Vector3(0, 1.2, 0)
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1.0, 0.1))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.82, 0.3, 0.95))
	ramp.set_color(1, Color(0.45, 0.04, 0.0, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.45, 0.06, 0.9))
	ramp.add_point(0.7, Color(0.85, 0.15, 0.02, 0.6))
	p.color_ramp = ramp
	var q := SphereMesh.new()                             # a tongue of flame: a tall, soft-edged teardrop
	q.radius = 0.16
	q.height = 0.62
	q.radial_segments = 8
	q.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.mesh = q
	n.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color("#ff7a20")
	l.omni_range = 4.5
	l.position = Vector3(0, 1.2, 0)
	n.add_child(l)
	return n


## G52b: the Giant's speed-up (1, frenzy) and enrage (2): it glows red, embers off it.
func _giant_rage(level: int) -> void:
	var v: Dictionary = _views.get("boss", {})
	if v.is_empty():
		return
	var root: Node3D = v.root
	var fx: Node3D = v.get("rage_fx")
	if fx == null:
		fx = Node3D.new()
		var l := OmniLight3D.new()
		l.light_color = Color("#ff3010")
		l.omni_range = 2.6                             # x5: the Giant is scaled
		l.position = Vector3(0, 1.4, 0)
		fx.add_child(l)
		var p := _sparkles(Color("#ff5020"))
		p.emission_sphere_radius = 0.9
		p.position = Vector3(0, 1.3, 0)
		p.amount = 60
		p.lifetime = 1.2
		p.initial_velocity_max = 2.0
		fx.add_child(p)
		root.add_child(fx)
		v["rage_fx"] = fx
	(fx.get_child(0) as OmniLight3D).light_energy = 1.6 if level == 1 else 3.5
	(fx.get_child(1) as CPUParticles3D).amount = 60 if level == 1 else 140


func _sparkles(col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.1
	p.mesh = _dot_mesh(col)
	return p


func _dot_mesh(col: Color) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	m.material = _glow_mat(col)
	return m


func _glow_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.lightened(0.2), 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat


# ----------------------------------------------------------------- camera

func _place_camera(delta: float) -> void:
	if cam_hold:
		return
	var me := sim.unit(me_id)
	if me == null or not _views.has(me_id):
		return
	var root: Node3D = _views[me_id].root
	var moving := me.moving and not _lmb
	if moving and absf(cam_yaw_off) > 0.001:
		cam_yaw_off = lerp_angle(cam_yaw_off, 0.0, minf(1.0, delta * 3.0))       # the camera swings back behind you
	var me_yaw := lerp_angle(float(_prev[me_id][2]), me.yaw, clampf(_acc / MmoSim.TICK, 0.0, 1.0))
	var yaw := me_yaw + cam_yaw_off
	var pivot := Vector3(root.position.x, root.position.y * 0.6 + HEAD, root.position.z)
	var pr := deg_to_rad(cam_pitch)
	var back := Vector3(-sin(yaw), 0, -cos(yaw))
	var want := pivot + back * cos(pr) * cam_dist + Vector3(0, sin(pr) * cam_dist, 0)
	if want.y < 0.35:
		want.y = 0.35
	var lim := (MmoTankArena.WALL_R if tank_view else MmoArena.WALL_R) - 1.0
	var flat := Vector2(want.x, want.z)
	if flat.length() > lim:                                   # don't back into the wall
		flat = flat.normalized() * lim
		want = Vector3(flat.x, want.y, flat.y)
	var b := sim.boss
	if b and b.alive and _views.has("boss"):
		var bc := _v3(b.pos)
		var br := b.radius * 1.25
		var bh := 3.2 if tank_view else 2.3 * MmoTune.value("boss_scale")
		var d := want - pivot
		var hit := 1.0
		for k in 24:                                          # march out from the head: the first step inside the Giant stops it
			var f := (k + 1) / 24.0
			var p := pivot + d * f
			if Vector2(p.x - bc.x, p.z - bc.z).length() < br and p.y < bh:
				hit = maxf(0.08, f - 1.0 / 24.0)
				break
		want = pivot + d * hit
	_cam.position = want
	var ahead := Vector3(sin(yaw), 0, cos(yaw)) * clampf(cam_dist * 0.16, 0.0, 3.0)
	_cam.look_at(pivot + ahead + Vector3(0, -0.1, 0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		_cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.12
	_cam.fov = MmoTune.value("cam_fov")
	# hide your own name; fade yourself when the camera is inside your head
	(_views[me_id].char as Node3D).visible = cam_dist > 0.9


# ---------------------------------------------------------------- effects

func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func _el(school: String) -> String:
	match school:
		"fire": return "fire"
		"ice": return "ice"
		"light": return "light"
		"dark": return "water"
		"thunder": return "thunder"
		"earth": return "wind"
	return "wind"


func _chest(u: MmoUnit) -> Vector3:
	if not _views.has(u.id):
		return _v3(u.pos, 1.2)
	var root: Node3D = _views[u.id].root
	return root.global_position + Vector3(0, 1.2 * root.scale.y, 0)


func _use_fx(u: MmoUnit, ab: Dictionary, t: MmoUnit) -> void:
	if ab.is_empty():
		return
	var col := Color(str(ab.get("col", "#ffffff")))
	for f: Dictionary in ab.fx:
		if f.has("buff") or f.has("shield") or f.has("immune"):
			var who: Array = [u]
			if str(f.get("who", "")) == "raid":
				who = sim.living()
			elif t and not sim.is_enemy(u, t) and (f.has("shield") or str(f.get("on", "")) == "target"):
				who = [t]
			for w: MmoUnit in who:
				_ring_flash(w, col)
		if f.has("dash"):
			pass
		if f.has("taunt") and t:
			_fx.release_at("fire", _chest(t), 0.5)
	if str(ab.get("anim", "")) == "strike" and t and sim.is_enemy(u, t) and not ab.has("proj"):
		_fx._quad(8, _el(str(ab.school)), _chest(t), Vector2(1.2, 1.2), 0.2)


func _impact_on(t: MmoUnit, school: String, s: float) -> void:
	var at := _chest(t)
	if t.kind == "boss":
		var toward := (_cam.global_position - at).normalized()
		at += toward * t.radius * 0.8
	if school in ["light", "dark", "phys"]:
		# holy's release is a pillar and shadow's a vortex: a flash and sparks read better on a hit
		_fx._quad(8, _el(school) if school != "light" else "light", at, Vector2(1.4, 1.4) * s * 1.6, 0.22)
		_fx._burst_parts(at, _el(school), 6, 0.0, { "up": 1.6, "spread": 2.2, "g": 6.0, "shape": 2, "life": 0.3, "s0": 0.08 })
	else:
		_fx.release_at(_el(school), at, s)


func _hit_fx(t: MmoUnit, school: String) -> void:
	_fx._burst_parts(_chest(t), _el(school), 6, 0.0, { "up": 2.0, "spread": 2.4, "g": 7.0, "shape": 2, "life": 0.3, "s0": 0.08 })
	if t.id == me_id:
		_shake = maxf(_shake, 0.25)


func _heal_fx(t: MmoUnit) -> void:
	var p := _sparkles(Color("#9cff7a"))
	p.one_shot = true
	p.amount = 18
	p.emitting = true
	add_child(p)
	p.global_position = _chest(t)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _ring_flash(u: MmoUnit, col: Color) -> void:
	var r := _ring_mesh(1.0, Color(col, 0.9), 0.1)
	r.position = _v3(u.pos, 0.06)
	var tw := create_tween()
	tw.tween_property(r, "scale", Vector3(1.6, 1, 1.6), 0.5)
	tw.parallel().tween_property(r.material_override, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(r.queue_free)


func _puff(at: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -2, 0)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.22
	p.mesh = _dot_mesh(col)
	add_child(p)
	p.global_position = at + Vector3(0, 0.6, 0)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _launch(src: String, tgt: String, ab_id: String, school: String, t: float) -> void:
	var s := sim.unit(src)
	if s == null or not _views.has(src):
		return
	var col := Color("#e8e0c8")
	var size_ := 0.18
	if s.kind == "player":
		var ab := MmoClasses.ability(s.cls, ab_id)
		if not ab.is_empty():
			col = Color(str(ab.col))
			size_ = 0.32 if school != "phys" else 0.12
	var n := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = size_
	m.height = size_ * 2.0
	m.material = _glow_mat(col)
	n.mesh = m
	if school == "phys":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, 0.9)
		bm.material = _glow_mat(col.lightened(0.4))
		n.mesh = bm
	add_child(n)
	var trail := _sparkles(col)
	trail.emission_sphere_radius = size_ * 0.6
	trail.initial_velocity_max = 0.2
	trail.gravity = Vector3.ZERO
	trail.lifetime = 0.3
	trail.local_coords = false
	n.add_child(trail)
	var from := _chest(s) + (_views[src].root as Node3D).global_basis.z.normalized() * 0.5
	n.global_position = from
	_shots.append({ "node": n, "tgt": tgt, "t": 0.0, "total": maxf(0.05, t), "from": from, "school": school })


func _sync_shots(delta: float) -> void:
	for s: Dictionary in _shots.duplicate():
		s.t = float(s.t) + delta
		var n: Node3D = s.node
		var t := sim.unit(str(s.tgt))
		var to := _chest(t) if t else (s.from as Vector3)
		var f := clampf(float(s.t) / float(s.total), 0.0, 1.0)
		var at := (s.from as Vector3).lerp(to, f) + Vector3(0, sin(f * PI) * 0.6, 0)
		var step := at - n.global_position
		if step.length() > 0.001 and absf(step.normalized().y) < 0.98:
			n.look_at_from_position(n.global_position, at, Vector3.UP)
		n.global_position = at
		if f >= 1.0:
			_shots.erase(s)
			n.queue_free()


func _ground_tick(e: Dictionary) -> void:
	var at := _v3(e.pos as Vector2)
	var r := float(e.r)
	var ab := str(e.ab)
	for i in 6:
		var a := randf() * TAU
		var d := sqrt(randf()) * r
		var p := at + Vector3(cos(a) * d, 0, sin(a) * d)
		if ab == "blizzard":
			_fx.release_at("ice", p, 0.5, randf() * 0.25)
		else:
			_fx._burst_parts(p + Vector3(0, 0.2, 0), "wind", 3, randf() * 0.2, { "up": 1.5, "spread": 1.0, "g": 8.0, "shape": 2, "life": 0.3, "s0": 0.06 })


func _floater(u: MmoUnit, text: String, col: Color, big: bool) -> void:
	if not _views.has(u.id):
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.001
	l.font_size = 40 if big else 28
	l.outline_size = 10
	l.no_depth_test = true
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font = MmoHud._font(["Friz Quadrata TT", "Palatino Linotype", "Georgia"], 800)
	add_child(l)
	var root: Node3D = _views[u.id].root
	var base := root.global_position + Vector3(randf_range(-0.6, 0.6), 2.4 * root.scale.y, randf_range(-0.6, 0.6))
	l.global_position = base
	_floaters.append({ "node": l, "t": 0.0, "base": base })


func _tick_floaters(delta: float) -> void:
	for f: Dictionary in _floaters.duplicate():
		f.t = float(f.t) + delta
		var l: Label3D = f.node
		l.global_position = (f.base as Vector3) + Vector3(0, float(f.t) * 1.6, 0)
		l.modulate.a = clampf(1.6 - float(f.t) * 1.2, 0.0, 1.0)
		if float(f.t) > 1.4:
			_floaters.erase(f)
			l.queue_free()


# ------------------------------------------------------------------ areas

## Scorched Earth (G37): one big disc over the courtyard; the shader draws the
## burning half by angle. warn: hatching that fills in and an edge line that
## pulses faster as it nears; live: fire with embers and a bright edge;
## spinning: chevrons along the edge running the way it turns.
const SCORCH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec2 dir = vec2(1.0, 0.0);
uniform float warn = 0.0;        // 0..1 through the warning
uniform float live = 0.0;        // 0 or 1
uniform float spin = 0.0;        // 0..1: the chevrons' strength
uniform float turn = 1.0;        // 1 counter-clockwise from above, -1 clockwise
uniform float radius = 26.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * radius;
	float r = length(p);
	if (r > radius) { discard; }
	float s = dot(p, dir);                       // > 0: the burning side
	vec2 along = vec2(-dir.y, dir.x);
	float t = dot(p, along);
	float edge = 1.0 - smoothstep(0.0, 0.6, abs(s));
	vec3 c = vec3(0.0);
	float a = 0.0;
	if (live < 0.5) {
		float beat = 0.5 + 0.5 * sin(TIME * mix(4.0, 22.0, warn));
		float hatch = step(0.5, fract((s + t) * 0.35 - TIME * 0.6));
		if (s > 0.0) {
			c = mix(vec3(1.0, 0.55, 0.1), vec3(1.0, 0.15, 0.05), warn);
			a = hatch * (0.10 + 0.32 * warn) + 0.06 * warn;
		}
		c = mix(c, vec3(1.0, 0.8, 0.3), edge);
		a = max(a, edge * (0.45 + 0.5 * beat));
	} else {
		float n = noise(p * 0.35 + vec2(0.0, -TIME * 0.8)) * 0.6 + noise(p * 1.1 - vec2(TIME * 1.3, 0.0)) * 0.4;
		if (s > 0.0) {
			c = mix(vec3(0.35, 0.03, 0.0), vec3(1.0, 0.42, 0.05), smoothstep(0.35, 0.9, n));
			a = 0.62 + 0.25 * n;
		}
		c = mix(c, vec3(1.0, 0.85, 0.4), edge);
		a = max(a, edge);
		if (spin > 0.01) {
			// The fire turns counter-clockwise (seen from above): the edge on the t < 0 ray
			// advances into safe ground, the edge on the t > 0 ray retreats.
			// Advancing: red chevrons on the safe side, pointing out of the fire, marching away.
			// Retreating: gold chevrons on the fire side, pointing into the fire, marching in.
			t *= turn;                                             // clockwise: the edges swap roles
			float wc = (fract(abs(t) / 2.0) - 0.5) * 2.0;          // across the chevron, repeating along the edge
			float arms = 1.0 - smoothstep(0.55, 0.7, abs(wc));     // G52: trim where neighbours meet (the W's backward points): lone chevrons
			float adv_band = step(1.5, -t) * (1.0 - smoothstep(0.0, 0.4, -s - 3.4)) * smoothstep(0.2, 0.6, -s) * arms;
			float fa = fract((-s + abs(wc) * 1.4) * 0.5 - TIME * 0.9);
			float adv = smoothstep(0.58, 0.62, fa) * (1.0 - smoothstep(0.86, 0.9, fa));
			float ret_band = step(1.5, t) * (1.0 - smoothstep(0.0, 0.4, s - 3.4)) * smoothstep(0.2, 0.6, s) * arms;
			float fr = fract((s + abs(wc) * 1.4) * 0.5 - TIME * 0.9);
			float ret = smoothstep(0.58, 0.62, fr) * (1.0 - smoothstep(0.86, 0.9, fr));
			float k = clamp(spin, 0.0, 1.0);
			c = mix(c, vec3(1.0, 0.18, 0.08), adv_band * adv * k);
			a = max(a, adv_band * adv * 0.9 * k);
			c = mix(c, vec3(1.0, 0.88, 0.35), ret_band * ret * k);
			a = max(a, ret_band * ret * 0.9 * k);
		}
	}
	a *= 1.0 - smoothstep(radius - 1.0, radius, r);
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
var _scorch_node: MeshInstance3D
var _scorch_mat: ShaderMaterial
var _scorch_fire: CPUParticles3D

const TELE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform float fill = 0.0;
uniform int shape = 0;          // 0 disc, 1 strip, 2 ring (safe zone), 3 soft (players' ground spells), 4 sector (G46), 5 burning ground (G52)
uniform float pulse = 0.0;
uniform float half = 1.0;       // the sector's half angle (rad)
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (shape == 4) {
		// a wedge from the centre along +Z, filling outward as it nears
		float d4 = length(p);
		float ang = abs(atan(p.x, p.y));
		float inside4 = step(ang, half) * (1.0 - smoothstep(0.985, 1.0, d4));
		float side = (half - ang) * max(d4, 0.05) * 30.0;
		float rim4 = (1.0 - smoothstep(0.0, 0.25, side)) * inside4;
		float grow4 = 1.0 - smoothstep(fill - 0.02, fill, d4);
		float stripes = step(0.5, fract(d4 * 18.0 - TIME * 1.5));
		float a4 = rim4 * 0.95 + inside4 * (0.16 + 0.06 * stripes) + grow4 * inside4 * 0.34;
		ALBEDO = col.rgb * (1.0 + rim4 * 0.6);
		ALPHA = clamp(a4 * col.a, 0.0, 1.0);
	} else if (shape == 5) {
		// G52: burning ground you must not stand in: a red disc, a bright red rim, a dark line outside it
		float d5 = length(p);
		float in5 = 1.0 - smoothstep(0.995, 1.0, d5);
		float rim5 = smoothstep(0.84, 0.87, d5) * (1.0 - smoothstep(0.94, 0.95, d5));
		float out5 = smoothstep(0.94, 0.95, d5) * in5;
		float lick = 0.5 + 0.5 * sin(TIME * 5.0 - d5 * 14.0);
		vec3 c5 = mix(vec3(0.85, 0.06, 0.03), vec3(1.0, 0.35, 0.1), lick * 0.35 * (1.0 - d5));
		c5 = mix(c5, vec3(1.0, 0.22, 0.12), rim5);
		c5 = mix(c5, vec3(0.08, 0.0, 0.0), out5);
		float a5 = in5 * (0.5 + 0.08 * lick) + rim5 * 0.5 + out5 * 0.4;
		ALBEDO = c5;
		ALPHA = clamp(a5, 0.0, 1.0);
	} else {
	float d = shape == 1 ? max(abs(p.x), 0.0) : length(p);
	float edge = shape == 1 ? abs(p.x) : d;
	float rim = smoothstep(0.86, 0.94, edge) * (1.0 - smoothstep(0.97, 1.0, edge));
	float inside = 1.0 - smoothstep(0.97, 1.0, edge);
	float grow = shape == 1 ? step(UV.y, fill) : (1.0 - smoothstep(fill - 0.02, fill, d));
	float a = rim * 0.95 + inside * 0.18 + grow * inside * 0.32;
	if (shape == 3) {
		a = (1.0 - smoothstep(0.55, 1.0, d)) * (0.22 + 0.06 * sin(TIME * 3.0));
	}
	if (shape == 2) {
		a = rim * (0.75 + 0.25 * sin(TIME * 8.0)) + inside * (0.16 + 0.08 * sin(TIME * 4.0));
	}
	ALBEDO = col.rgb * (1.0 + rim * 0.6);
	ALPHA = clamp(a * col.a, 0.0, 1.0);
	}
}
"""
static var _tele_shader: Shader


func _tele_mat(col: Color, shape: int) -> ShaderMaterial:
	if _tele_shader == null:
		_tele_shader = Shader.new()
		_tele_shader.code = TELE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _tele_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("shape", shape)
	return m


func _sync_scorch(_delta: float) -> void:
	var sc: Dictionary = sim.scorch
	if sc.is_empty():
		if _scorch_node:
			_scorch_node.visible = false
		return
	if _scorch_node == null:
		_scorch_node = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var R := MmoSim.ARENA_R + 2.0
		pm.size = Vector2.ONE * R * 2.0
		_scorch_node.mesh = pm
		_scorch_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := Shader.new()
		sh.code = SCORCH_SHADER
		_scorch_mat = ShaderMaterial.new()
		_scorch_mat.shader = sh
		_scorch_mat.set_shader_parameter("radius", R)
		_scorch_node.material_override = _scorch_mat
		add_child(_scorch_node)
		_scorch_fire = _sparkles(Color("#ff6a20"))
		_scorch_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_scorch_fire.emission_box_extents = Vector3(R * 0.5, 0.1, R)
		_scorch_fire.amount = 220
		_scorch_fire.lifetime = 1.4
		_scorch_fire.initial_velocity_min = 1.0
		_scorch_fire.initial_velocity_max = 3.5
		_scorch_fire.emitting = false
		_scorch_node.add_child(_scorch_fire)
	_scorch_node.visible = true
	var bp := _v3(sim.boss.pos, 0.07)
	_scorch_node.position = bp
	var ang := float(sc.ang)
	_scorch_mat.set_shader_parameter("dir", Vector2(cos(ang), sin(ang)))
	var warn_len := MmoTune.value("scorch_warn")
	_scorch_mat.set_shader_parameter("warn", clampf(float(sc.t) / maxf(0.1, warn_len), 0.0, 1.0))
	_scorch_mat.set_shader_parameter("live", 1.0 if sc.state == "live" else 0.0)
	# full chevrons while it turns; dim while it holds, flashing in the scorch_spin_warn s before the
	# next burst and before it first turns (G38, G40; G52: less warning, was 2 s and 10 s)
	var to_spin := MmoTune.value("scorch_spin_at") - (sim.time - sim.pull_time)
	var flash := 0.35 + 0.25 * sin(Time.get_ticks_msec() / 160.0)
	var spin_k := 0.0
	if sc.spinning:
		spin_k = 1.0 if sc.get("moving", false) else (flash if sim.scorch_next_turn() <= MmoTune.value("scorch_spin_warn") else 0.22)
	elif sc.state == "live" and to_spin <= MmoTune.value("scorch_spin_warn"):
		spin_k = flash
	_scorch_mat.set_shader_parameter("spin", spin_k)
	_scorch_mat.set_shader_parameter("turn", float(sc.get("dir", 1.0)))
	# embers over the burning half
	_scorch_fire.emitting = sc.state == "live"
	var d := Vector3(cos(ang), 0, sin(ang))
	_scorch_fire.position = d * (MmoSim.ARENA_R + 2.0) * 0.5
	_scorch_fire.rotation.y = -ang


func _add_area(a: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)
	var q := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match str(a.kind):
		"line":
			pm.size = Vector2(float(a.w), float(a.len))
			q.mesh = pm
			q.material_override = _tele_mat(Color(1.0, 0.45, 0.1, 1.0), 1)
			var dir := a.dir as Vector2
			root.rotation.y = atan2(dir.x, dir.y)
			q.position = Vector3(0, 0.05, float(a.len) * 0.5)
		"sector":
			pm.size = Vector2.ONE * float(a.r) * 2.0
			q.mesh = pm
			var sm := _tele_mat(MmoTankView.sector_col(str(a.look)), 4)
			sm.set_shader_parameter("half", float(a.half))
			q.material_override = sm
			var sd := a.dir as Vector2
			root.rotation.y = atan2(sd.x, sd.y)
			q.position.y = 0.07 if str(a.look) != "dust" else 0.06
		"circle", "bomb", "ground":
			pm.size = Vector2.ONE * float(a.r) * 2.0
			q.mesh = pm
			var c := Color(1.0, 0.25, 0.08, 1.0)
			if str(a.get("look", "")) == "smoke_mark":
				c = Color(0.85, 0.85, 0.78, 1.0)                  # G46: where the smoke grenade lands
			if str(a.kind) == "bomb":
				c = Color(1.0, 0.12, 0.05, 0.6)
			elif str(a.kind) == "ground":
				c = Color("#ffd040") if str(a.look) == "consecration" else (Color("#ff4a12") if str(a.look) == "fire_pool" else Color("#9fd8ff"))
			var shape := 3 if str(a.kind) == "ground" else 0
			if str(a.get("look", "")) == "fire_pool":
				shape = 5                                         # G52: the burning remainder, a clear red circle
			q.material_override = _tele_mat(c, shape)
			if shape == 5:
				(q.material_override as ShaderMaterial).render_priority = 3      # G52: drawn over the smoke, never washed out
			q.position.y = 0.05
		"ring":
			pm.size = Vector2.ONE * float(a.r) * 2.0
			q.mesh = pm
			q.material_override = _tele_mat(Color(1.0, 0.85, 0.2, 1.0), 2)
			q.position.y = 0.06
			var sp := _sparkles(Color(1.0, 0.85, 0.3))
			sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			sp.emission_ring_axis = Vector3.UP
			sp.emission_ring_radius = float(a.r)
			sp.emission_ring_inner_radius = float(a.r) * 0.95
			sp.emission_ring_height = 0.1
			sp.amount = 90
			sp.lifetime = 1.2
			sp.initial_velocity_min = 1.5
			sp.initial_velocity_max = 3.0
			sp.spread = 5.0
			root.add_child(sp)
	root.add_child(q)
	root.position = _v3(a.pos as Vector2)
	if str(a.kind) == "circle" and str(a.look) == "meteor":
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.9
		sm.height = 1.8
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color("#3a2a20")
		rm.emission_enabled = true
		rm.emission = Color("#ff5a10")
		rm.emission_energy_multiplier = 3.0
		var ml := OmniLight3D.new()
		ml.light_color = Color("#ff7a30")
		ml.light_energy = 2.5
		ml.omni_range = 7.0
		sm.material = rm
		rock.mesh = sm
		rock.add_child(ml)
		var trail := _sparkles(Color("#ff7a20"))
		trail.emission_sphere_radius = 0.8
		trail.amount = 40
		trail.lifetime = 0.5
		trail.local_coords = false
		trail.scale_amount_min = 0.25
		trail.scale_amount_max = 0.45
		rock.add_child(trail)
		var tail := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.05
		tm.bottom_radius = 0.42
		tm.height = 5.0
		tm.material = _glow_mat(Color("#ff8a30"))
		(tm.material as StandardMaterial3D).albedo_color.a = 0.28
		tail.mesh = tm
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fall := (Vector3(0, 0.6, 0) - Vector3(-6.0, 34.0, -4.0)).normalized()
		tail.basis = Basis(Quaternion(Vector3.UP, -fall))
		tail.position = -fall * 2.6
		rock.add_child(tail)
		root.add_child(rock)
		root.set_meta("rock", rock)
	if str(a.kind) == "bomb":
		var bomb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.64
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color("#1a1a1e")
		bm.metallic = 0.6
		bm.roughness = 0.3
		sm.material = bm
		bomb.mesh = sm
		bomb.position.y = 3.0
		var spark := _sparkles(Color("#ffb030"))
		spark.emission_sphere_radius = 0.05
		spark.position = Vector3(0, 0.36, 0)
		bomb.add_child(spark)
		root.add_child(bomb)
		var cnt := Label3D.new()
		cnt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cnt.fixed_size = true
		cnt.pixel_size = 0.001
		cnt.font_size = 30
		cnt.outline_size = 8
		cnt.no_depth_test = true
		cnt.modulate = Color("#ff5030")
		cnt.position.y = 3.7
		root.add_child(cnt)
		root.set_meta("count", cnt)
	if tank_view:
		tank_view.decorate(a, root)
	_areas[int(a.id)] = { "node": root, "a": a }


func _sync_areas(_delta: float) -> void:
	var live := {}
	for a: Dictionary in sim.areas:
		live[int(a.id)] = a
	for id: int in _areas.keys():
		var rec: Dictionary = _areas[id]
		var root: Node3D = rec.node
		if not live.has(id):
			root.queue_free()
			_areas.erase(id)
			continue
		var a: Dictionary = live[id]
		root.position = _v3(a.pos as Vector2)
		var fill := 1.0 - clampf(float(a.t) / maxf(0.01, float(a.dur)), 0.0, 1.0)
		if str(a.get("look", "")) == "deny":
			fill = 1.0                                        # G52: the light tanks' zones, solid while they live
			var age := float(a.dur) - float(a.t)              # G52b: they flash in
			var fl := clampf(1.0 - age / 1.6, 0.0, 1.0) * (0.5 + 0.5 * sin(age * 22.0))
			for c in root.get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
					((c as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("col", MmoTankView.sector_col("deny").lerp(Color(1, 0.85, 0.5), fl))
		for c in root.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
				((c as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("fill", fill)
		if root.has_meta("arc_from"):
			# G46: lobbed from the tank's gun in an arc (the smoke grenade)
			var rock: Node3D = root.get_meta("rock")
			var from: Vector3 = (root.get_meta("arc_from") as Vector3) - root.position
			var p3 := from.lerp(Vector3(0, 0.3, 0), fill)
			p3.y += sin(fill * PI) * maxf(6.0, from.length() * 0.45)
			rock.position = p3
			rock.rotation.x = fill * 9.0
		elif root.has_meta("rock"):
			var rock: Node3D = root.get_meta("rock")
			rock.position = Vector3(-6.0, 34.0, -4.0).lerp(Vector3(0, 0.6, 0), fill * fill)
		if root.has_meta("count"):
			(root.get_meta("count") as Label3D).text = "%d" % ceili(float(a.t))


func _spikes(a: Dictionary) -> void:
	var dir := a.dir as Vector2
	var start := a.pos as Vector2
	var n := 22
	for i in n:
		var d := 3.0 + float(a.len) * 0.5 * i / n
		var p := start + dir * d + dir.orthogonal() * randf_range(-1.0, 1.0)
		if p.length() > MmoSim.ARENA_R:
			break
		var spike := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = randf_range(0.45, 0.8)
		cm.height = randf_range(1.6, 3.0)
		cm.radial_segments = 5
		cm.material = GKMaterials.get_material("sandstone:#7a6a58")
		spike.mesh = cm
		add_child(spike)
		spike.position = _v3(p, -cm.height * 0.5)
		spike.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
		var delay := i * 0.025
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(spike, "position:y", cm.height * 0.38, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.7)
		tw.tween_property(spike, "position:y", -cm.height * 0.6, 0.5)
		tw.tween_callback(spike.queue_free)
		if i % 3 == 0:
			_fx._burst_parts(_v3(p, 0.3), "wind", 4, delay, { "up": 3.0, "spread": 2.0, "g": 9.0, "shape": 2, "life": 0.5, "s0": 0.12 })


func _explode(e: Dictionary) -> void:
	if tank_view and str(e.what) in ["shell", "cannon", "arc", "tread", "deny"]:
		tank_view.explode(e)
		return
	var at := _v3(e.pos as Vector2)
	var me := sim.unit(me_id)
	match str(e.what):
		"meteor":
			_fx.release_at("fire", at + Vector3(0, 0.4, 0), 1.1)
			_scorch(at, 2.8)
			if me and me.pos.distance_to(e.pos as Vector2) < 10.0:
				_shake = maxf(_shake, 0.45)
		"bomb":
			_fx.release_at("fire", at + Vector3(0, 1.0, 0), 1.6)
			_shock(at, float(e.r), Color(1.0, 0.4, 0.1))
		"gather":
			_shock(at, MmoSim.ARENA_R, Color(0.95, 0.75, 0.3))
			_fx.release_at("light", at, 2.0)
			_shake = 0.9


func _shock(at: Vector3, r: float, col: Color) -> void:
	var ring := _ring_mesh(1.0, Color(col, 0.95), 0.12)
	ring.position = at + Vector3(0, 0.15, 0)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(r, 1, r), 0.45).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring.material_override, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(ring.queue_free)


func _scorch(at: Vector3, r: float) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * r * 2.0
	m.mesh = pm
	var mat := _tele_mat(Color(0.32, 0.2, 0.12, 0.5), 3)
	mat.set_shader_parameter("fill", 1.0)
	m.material_override = mat
	m.position = at + Vector3(0, 0.03, 0)
	add_child(m)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(m, "scale", Vector3(0.01, 1, 0.01), 1.0)
	tw.tween_callback(m.queue_free)


func _ring_mesh(r: float, col: Color, w: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - w
	tm.outer_radius = r
	tm.rings = 48
	tm.ring_segments = 4
	m.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.scale = Vector3(1, 0.05, 1)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func unit_root(id: String) -> Node3D:
	return _views[id].root if _views.has(id) else self


func camera() -> Camera3D:
	return _cam


func hud() -> MmoHud:
	return _hud


## The Giant's nameplate: name, level and a health bar over its head (the
## reference's red plate), drawn on the HUD layer.
class BossPlate extends Control:
	var view: MmoView

	func _init(v: MmoView) -> void:
		view = v
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var b := view.sim.boss
		if b == null or not b.alive or not view._views.has("boss"):
			return
		var root: Node3D = view._views["boss"].root
		var wp := root.global_position + Vector3(0, float(view._views["boss"].get("plate_h", 2.45 * root.scale.y)), 0)
		var cam := view.camera()
		if cam.is_position_behind(wp):
			return
		var sp := cam.unproject_position(wp)
		sp.y = maxf(sp.y, 132.0)                         # pinned under the top edge, like WoW's plates
		var w := 170.0
		var r := Rect2(sp.x - w * 0.5, sp.y - 8, w, 12)
		draw_rect(r.grow(2), Color(0, 0, 0, 0.85))
		draw_rect(r, Color(0.25, 0.05, 0.05))
		draw_rect(Rect2(r.position, Vector2(w * b.hp_pct(), 12)), Color("#d42a20"))
		var f: Font = view.hud().serif
		draw_string_outline(f, Vector2(r.position.x, r.position.y + 10), b.name, HORIZONTAL_ALIGNMENT_CENTER, w, 12, 3, Color.BLACK)
		draw_string(f, Vector2(r.position.x, r.position.y + 10), b.name, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color.WHITE)
		draw_string_outline(f, Vector2(r.position.x - 30, r.position.y + 11), "??", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		draw_string(f, Vector2(r.position.x - 30, r.position.y + 11), "??", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff4030"))
