class_name MobaView
extends Node3D
## Draws a MobaSim and drives it: League's locked camera on your champion,
## right- or left-click to move and attack, QWER at the cursor, D flash,
## F ignite (binds from the testing range), S stop. Bots play the rest.
## Works full screen or inside a SubViewport (the range).

signal match_over(winner_team: String)

const CAM_PITCH := 56.0
const CAM_DIST := 25.0
const CAM_FOV := 40.0
const ATK_ANIM := 2.2           # clip playback rate for autos and casts

var sim: MobaSim
var local_id := ""              # the champion this machine controls ("" = watch)
var bots := {}                  # unit id -> MobaBot
var binds := {}
var names := {}                 # team -> player name (HUD)

var _acc := 0.0
var _prev := {}                 # unit id -> Vector2 at the previous tick
var _views := {}                # unit id -> { root, char, bar, kind, pose }
var _shots := {}                # projectile id -> Node3D
var _areas := {}                # area id -> Node3D
var _cam: Camera3D
var _hud: CanvasLayer
var _bars: Control
var _order := {}                # the local player's pending order
var _rmb := false
var _rmb_t := 0.0
var _slots := {}                # slot -> { panel, cd }
var _score_l: Label
var _center_l: Label
var _feed: VBoxContainer
var _hp_fill: ColorRect
var _hp_l: Label
var _smoke: ColorRect
var _over := false
var _hover_ring: MeshInstance3D


func setup(p_sim: MobaSim, p_local: String, p_bots: Dictionary, p_binds: Dictionary, p_names: Dictionary = {}) -> void:
	sim = p_sim
	local_id = p_local
	bots = p_bots
	binds = p_binds
	names = p_names


func _ready() -> void:
	_build_world()
	_build_hud()
	for u in sim.units:
		_add_unit(u)
		_prev[u.id] = u.pos
	_place_camera(true)


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1d2433")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8c4e0")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var L := MobaSim.HALF_LEN
	var W := MobaSim.HALF_W
	# the abyss under everything
	_box(Vector3(0, -3.2, 0), Vector3(L * 2 + 30, 0.2, W * 2 + 30), Color("#141924"))
	# the lane: stone slabs with a worn centre
	_box(Vector3(0, -0.25, 0), Vector3(L * 2 + 3.0, 0.5, W * 2 + 1.0), Color("#5a6170"))
	_box(Vector3(0, 0.005, 0), Vector3(L * 2, 0.01, 3.0), Color("#6b7385"))
	for i in range(-int(L), int(L) + 1, 3):
		_box(Vector3(i, 0.008, 0), Vector3(0.08, 0.01, W * 2), Color("#4b5160"))
	# walls of ice-blue rock along both sides
	for side in [-1.0, 1.0]:
		for i in range(-int(L) - 1, int(L) + 2, 2):
			var h := 1.2 + 0.6 * absf(sin(i * 1.7 + side))
			_box(Vector3(i, h / 2.0 - 0.3, side * (W + 1.0)), Vector3(2.1, h, 1.4), Color("#9fb6d1").lerp(Color("#5d7393"), absf(sin(i * 0.9))))
	# bases
	for team in ["blue", "red"]:
		var x := -L - 1.0 if team == "blue" else L + 1.0
		var col := MobaLook.team_color(team)
		_cyl(Vector3(x, -0.05, 0), 2.4, 0.3, col.darkened(0.45))
		_cyl(Vector3(x, 0.12, 0), 1.8, 0.06, col)
		_cyl(Vector3(x - (1.2 if team == "blue" else -1.2), 1.6, 0), 0.4, 3.2, col.lightened(0.2), true)
	_hover_ring = _ring(0.9, Color(1, 0.3, 0.3, 0.9))
	_hover_ring.visible = false
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	add_child(_cam)
	_cam.make_current()


func _box(at: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = at
	add_child(mi)
	return mi


func _cyl(at: Vector3, r: float, h: float, col: Color, glow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * (0.6 if glow else 1.0)
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = _mat(col, glow)
	mi.position = at
	add_child(mi)
	return mi


func _mat(col: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.4
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _ring(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.07
	tm.outer_radius = r
	tm.rings = 32
	mi.mesh = tm
	var m := _mat(col, true)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.scale = Vector3(1, 0.05, 1)
	add_child(mi)
	return mi


func _disc(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	mi.mesh = cm
	var m := _mat(col)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	return mi


# ------------------------------------------------------------------ units

func _add_unit(u: MobaUnit) -> void:
	var root := Node3D.new()
	add_child(root)
	var bu: BWUnit
	match u.kind:
		"champ": bu = MobaLook.champ_unit(u.champ, u.team)
		"minion": bu = MobaLook.minion_unit(u.role, u.team, u.id)
		_: bu = MobaLook.dummy_unit(u.id)
	var ch := BWCharacter.create(bu)
	root.add_child(ch)
	if u.kind == "champ":
		var c: Dictionary = MobaChamps.CHAMPS[u.champ]
		MobaLook.tint(ch, Color(str(c.tint)), Color(str(c.hair_hex)))
	elif u.kind == "minion":
		MobaLook.tint(ch, MobaLook.team_color(u.team))
		root.scale = Vector3.ONE * 0.72
	else:
		MobaLook.tint(ch, Color("#c9a66b"))
	var sel := _disc(u.radius, Color(MobaLook.team_color(u.team), 0.35))
	sel.reparent(root, false)
	sel.position.y = 0.02
	sel.scale = Vector3.ONE / root.scale.x
	var bar := _make_bar(u)
	_views[u.id] = { "root": root, "char": ch, "bar": bar, "kind": u.kind, "pose": "", "cast": u.cast_serial,
		"atk": u.atk_serial, "hit": u.hit_serial, "anim_t": 0.0 }
	ch.pose("idle")


func _make_bar(u: MobaUnit) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 96.0 if u.kind == "champ" else 46.0
	var h := 11.0 if u.kind == "champ" else 6.0
	c.size = Vector2(w, h)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.size = Vector2(w, h)
	c.add_child(bg)
	var fill := ColorRect.new()
	fill.name = "fill"
	fill.position = Vector2(1, 1)
	fill.size = Vector2(w - 2, h - 2)
	fill.color = MobaLook.SELF if u.id == local_id else (MobaLook.BLUE if _ally(u) else MobaLook.RED)
	c.add_child(fill)
	if u.kind == "champ":
		var n := Label.new()
		n.text = str(names.get(u.team, u.name))
		n.add_theme_font_size_override("font_size", 13)
		n.add_theme_color_override("font_outline_color", Color.BLACK)
		n.add_theme_constant_override("outline_size", 5)
		n.position = Vector2(0, -19)
		c.add_child(n)
	_bars.add_child(c)
	return c


func _ally(u: MobaUnit) -> bool:
	var me := sim.unit(local_id)
	return u.team == (me.team if me else "blue")


# ------------------------------------------------------------------- HUD

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = BWStyle.theme()
	_hud.add_child(root)
	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bars)
	_smoke = ColorRect.new()
	_smoke.set_anchors_preset(Control.PRESET_FULL_RECT)
	_smoke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5, 0.55));
	COLOR = vec4(0.03, 0.03, 0.04, amount * smoothstep(0.08, 0.32, d));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_smoke.material = sm
	_smoke.visible = false
	root.add_child(_smoke)
	_score_l = Label.new()
	_score_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 10)
	_score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_l.add_theme_font_size_override("font_size", 26)
	_score_l.add_theme_color_override("font_outline_color", Color.BLACK)
	_score_l.add_theme_constant_override("outline_size", 8)
	_score_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_score_l)
	_center_l = Label.new()
	_center_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_center_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_l.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_l.add_theme_font_size_override("font_size", 40)
	_center_l.add_theme_color_override("font_outline_color", Color.BLACK)
	_center_l.add_theme_constant_override("outline_size", 10)
	root.add_child(_center_l)
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 16)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_left = -360
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)
	var me := sim.unit(local_id)
	if me == null:
		return
	# the ability bar
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	sb.border_color = Color(0.85, 0.7, 0.35, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", sb)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 12)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bar)
	var v := VBoxContainer.new()
	bar.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var c: Dictionary = MobaChamps.CHAMPS[me.champ]
	for slot in ["q", "w", "e", "r", "flash", "ignite"]:
		var p := PanelContainer.new()
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(MobaLook.team_color(me.team), 0.25) if slot in ["flash", "ignite"] else Color(Color(str(c.tint)), 0.3)
		ps.set_corner_radius_all(4)
		ps.set_content_margin_all(4)
		p.add_theme_stylebox_override("panel", ps)
		p.custom_minimum_size = Vector2(78, 70)
		row.add_child(p)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 0)
		p.add_child(pv)
		var key := Label.new()
		key.text = TourneyUI.key_name(int(binds.get("spell2" if slot == "ignite" else slot, 0)))
		key.add_theme_font_size_override("font_size", 13)
		key.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		pv.add_child(key)
		var nm := Label.new()
		nm.text = "Flash" if slot == "flash" else ("Ignite" if slot == "ignite" else MobaChamps.spell_name(me.champ, slot))
		nm.add_theme_font_size_override("font_size", 12)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size.x = 70
		pv.add_child(nm)
		var cdl := Label.new()
		cdl.add_theme_font_size_override("font_size", 18)
		cdl.add_theme_color_override("font_outline_color", Color.BLACK)
		cdl.add_theme_constant_override("outline_size", 6)
		pv.add_child(cdl)
		_slots[slot] = { "panel": p, "cd": cdl }
		if slot == "r":
			var gap := Control.new()
			gap.custom_minimum_size.x = 10
			row.add_child(gap)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.9)
	hp_bg.custom_minimum_size = Vector2(0, 18)
	v.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = MobaLook.SELF
	_hp_fill.position = Vector2(1, 1)
	hp_bg.add_child(_hp_fill)
	_hp_l = Label.new()
	_hp_l.add_theme_font_size_override("font_size", 13)
	_hp_l.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_l.add_theme_constant_override("outline_size", 4)
	_hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bg.add_child(_hp_l)


func _feed_line(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_feed.add_child(l)
	TourneyUI.after(self, 5.0, func(): if is_instance_valid(l): l.queue_free())


# ------------------------------------------------------------------ input

func _mouse_world() -> Vector2:
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var from := _cam.project_ray_origin(mp)
	var dir := _cam.project_ray_normal(mp)
	if absf(dir.y) < 0.001:
		return Vector2.ZERO
	var t := -from.y / dir.y
	var p := from + dir * t
	return Vector2(p.x, p.z)


## The enemy under the cursor, judged on screen (generous, like League's).
func _hovered() -> MobaUnit:
	var me := sim.unit(local_id)
	if me == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var best: MobaUnit = null
	var bd := 42.0
	for u in sim.units:
		if u.team == me.team or not u.targetable() or not _views.has(u.id):
			continue
		var root: Node3D = _views[u.id].root
		var sp := _cam.unproject_position(root.global_position + Vector3(0, 0.9, 0))
		var d := sp.distance_to(mp)
		if d < bd:
			best = u
			bd = d
	return best


func _unhandled_input(ev: InputEvent) -> void:
	if local_id == "" or _over:
		return
	if ev is InputEventMouseButton and ev.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT]:
		_rmb = ev.pressed
		if ev.pressed:
			_click()
			get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var slot := ""
		for k in ["q", "w", "e", "r", "flash"]:
			if int(binds.get(k, -1)) == ev.keycode:
				slot = k
		if int(binds.get("spell2", -1)) == ev.keycode:
			slot = "ignite"
		if slot != "":
			var h := _hovered()
			_order["cast"] = { "slot": slot, "aim": _mouse_world(), "target": h.id if h else "" }
			get_viewport().set_input_as_handled()
		elif int(binds.get("stop", -1)) == ev.keycode:
			_order["stop"] = true
			get_viewport().set_input_as_handled()


func _click() -> void:
	var h := _hovered()
	if h:
		_order["attack"] = h.id
		_order.erase("move")
	else:
		_order["move"] = _mouse_world()
		_order.erase("attack")
		_click_fx(_mouse_world())


func _click_fx(at: Vector2) -> void:
	var r := _ring(0.45, Color(0.4, 1.0, 0.5, 0.9))
	r.position = Vector3(at.x, 0.05, at.y)
	var tw := create_tween()
	tw.tween_property(r, "scale", Vector3(0.2, 0.05, 0.2), 0.3)
	tw.tween_callback(r.queue_free)


# ------------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if _rmb and local_id != "":
		_rmb_t -= delta
		if _rmb_t <= 0.0:
			_rmb_t = 0.12
			if not _order.has("attack"):
				_order["move"] = _mouse_world()
	if not _over:
		_acc += delta
		var guard := 0
		while _acc >= MobaSim.TICK and guard < 6:
			_acc -= MobaSim.TICK
			guard += 1
			_tick()
	var alpha := clampf(_acc / MobaSim.TICK, 0.0, 1.0)
	_draw(alpha, delta)


func _tick() -> void:
	for u in sim.units:
		_prev[u.id] = u.pos
	var orders := {}
	for id in bots:
		var u := sim.unit(id)
		if u:
			orders[id] = (bots[id] as MobaBot).think(sim, u)
	if local_id != "":
		orders[local_id] = _order
		_order = {}
	var evs := sim.step(orders)
	for e in evs:
		_on_event(e)


func _on_event(e: Dictionary) -> void:
	match str(e.type):
		"wave":
			for u in sim.units:
				if not _views.has(u.id):
					_add_unit(u)
					_prev[u.id] = u.pos
		"hit":
			var u := sim.unit(str(e.unit))
			if u and _views.has(u.id) and float(e.amount) >= 5.0:
				_float_num(u, int(round(float(e.amount))), str(e.kind))
		"death":
			var u := sim.unit(str(e.unit))
			if u and u.kind == "champ":
				var by := sim.unit(str(e.by))
				_feed_line("%s slain%s" % [str(names.get(u.team, u.name)), (" by " + str(names.get(by.team, by.name))) if by and by.kind == "champ" else ""],
					MobaLook.team_color(u.team))
				BWMusic.sting("pick")
		"shot":
			var p := _proj(int(e.id))
			if not p.is_empty():
				_shots[int(e.id)] = _shot_mesh(str(p.get("look", p.get("champ", ""))), p)
		"shot_end":
			if _shots.has(int(e.id)):
				(_shots[int(e.id)] as Node3D).queue_free()
				_shots.erase(int(e.id))
		"area":
			for a in sim.areas:
				if int(a.id) == int(e.id):
					_areas[int(e.id)] = _area_mesh(a)
		"area_end":
			if _areas.has(int(e.id)):
				(_areas[int(e.id)] as Node3D).queue_free()
				_areas.erase(int(e.id))
			if str(e.kind) == "blast":
				_burst(e.pos, 2.5, Color("#9cff57"))
		"burst":
			var col := Color("#9cff57") if str(e.look).begins_with("merr") else (Color("#c084ff") if str(e.look).begins_with("temu") else Color("#ffb347"))
			_burst(e.pos, 2.5 if str(e.look) != "merr_spread" else 3.0, col)
		"flash":
			var u := sim.unit(str(e.unit))
			if u:
				_burst(u.pos, 1.0, Color("#fff27a"))
		"win":
			_over = true
			var t := str(e.team)
			_center_l.text = "%s wins" % str(names.get(t, t.capitalize()))
			_center_l.add_theme_color_override("font_color", MobaLook.team_color(t))
			BWMusic.sting("level_up")
			for id in _views:
				var u := sim.unit(id)
				if u and u.kind == "champ" and u.team == t and u.alive:
					(_views[id].char as BWCharacter).pose("cheer")
			TourneyUI.after(self, 3.0, func(): match_over.emit(t))


func _proj(id: int) -> Dictionary:
	for p in sim.projectiles:
		if int(p.id) == id:
			return p
	return {}


func _look_color(look: String, team: String) -> Color:
	if look.begins_with("merr"):
		return Color("#9cff57")
	if look.begins_with("temu"):
		return Color("#c084ff")
	if look.begins_with("braves"):
		return Color("#ffb347")
	return MobaLook.team_color(team).lightened(0.3)


func _shot_mesh(look: String, p: Dictionary) -> Node3D:
	var owner := sim.unit(str(p.owner))
	if look == "" and owner:
		look = owner.champ
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r := 0.16
	match look:
		"merr_spit": r = 0.34
		"merr_phlegm": r = 0.4
		"braves_shell": r = 0.38
		"braves_pellet": r = 0.1
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	var m := _mat(_look_color(look, str(p.team)), true)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	mi.position = Vector3(p.pos.x, 1.0, p.pos.y)
	return mi


func _area_mesh(a: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(a.pos.x, 0.03, a.pos.y)
	var col := _look_color(str(a.get("look", "")), str(a.team))
	match str(a.kind):
		"blast":
			var ring := _ring(float(a.r), Color(col, 0.95))
			ring.reparent(root, false)
			var fill := _disc(float(a.r), Color(col, 0.25))
			fill.reparent(root, false)
			fill.scale = Vector3(0.05, 1, 0.05)
			var tw := create_tween()
			tw.tween_property(fill, "scale", Vector3.ONE, float(a.delay))
		"smoke":
			for i in 9:
				var mi := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 1.0
				sm.height = 1.4
				mi.mesh = sm
				mi.material_override = _mat(Color(0.25, 0.25, 0.28, 0.55))
				var ang := i * TAU / 8.0
				var rr := 0.0 if i == 8 else float(a.r) * 0.6
				mi.position = Vector3(cos(ang) * rr, 0.6, sin(ang) * rr)
				mi.scale = Vector3.ONE * (1.3 if i == 8 else 1.0)
				root.add_child(mi)
		"mine":
			var me := sim.unit(local_id)
			root.visible = me != null and me.team == str(a.team) or local_id == ""
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.3
			mi.mesh = sm
			mi.material_override = _mat(col, true)
			mi.position.y = 0.12
			root.add_child(mi)
			var ring := _ring(float(a.trigger), Color(col, 0.4))
			ring.reparent(root, false)
	return root


func _burst(at: Vector2, r: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.0
	mi.mesh = sm
	var m := _mat(Color(col, 0.6), true)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	mi.position = Vector3(at.x, 0.2, at.y)
	mi.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r, r * 0.5, r), 0.25)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)


func _float_num(u: MobaUnit, n: int, kind: String) -> void:
	var l := Label.new()
	l.text = str(n)
	var col := Color.WHITE
	if kind in ["poison", "nuke", "toxic_shot"]:
		col = Color("#c084ff")
	elif kind in ["blaze", "ignite"]:
		col = Color("#ff9a3c")
	elif kind != "auto":
		col = Color("#7fd3ff")
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 20 if u.kind == "champ" else 14)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_bars.add_child(l)
	var root: Node3D = _views[u.id].root
	var sp := _cam.unproject_position(root.global_position + Vector3(0, 2.4, 0))
	l.position = sp + Vector2(randf_range(-14, 14), 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", sp.y - 40, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ------------------------------------------------------------------- draw

func _draw(alpha: float, delta: float) -> void:
	var me := sim.unit(local_id)
	for id in _views.keys():
		var v: Dictionary = _views[id]
		var u := sim.unit(id)
		if u == null:
			(v.root as Node3D).queue_free()
			(v.bar as Control).queue_free()
			_views.erase(id)
			continue
		var root: Node3D = v.root
		var ch: BWCharacter = v.char
		var p: Vector2 = (_prev.get(id, u.pos) as Vector2).lerp(u.pos, alpha)
		root.position = Vector3(p.x, 0.0, p.y)
		root.rotation.y = lerp_angle(root.rotation.y, atan2(u.facing.x, u.facing.y), minf(1.0, delta * 18.0))
		var hidden := u.stealth and (me == null or u.team != me.team)
		var blind := me != null and me.blind_t > 0.0 and u.team != me.team and u.pos.distance_to(me.pos) > MobaSim.SMOKE_SIGHT
		root.visible = u.alive and not hidden and not blind or (u.kind == "champ" and not u.alive and v.pose == "fall" and float(v.anim_t) < 1.6)
		if u.stealth and not hidden:
			MobaLook._walk(ch, Color(0.45, 0.4, 0.6))
			v["stealth_drawn"] = true
		elif v.get("stealth_drawn", false):
			v["stealth_drawn"] = false
			var c: Dictionary = MobaChamps.CHAMPS.get(u.champ, {})
			MobaLook.tint(ch, Color(str(c.get("tint", "#ffffff"))))
		v.anim_t = float(v.anim_t) + delta
		_pose(u, v)
		var bar: Control = v.bar
		bar.visible = root.visible and u.alive
		if bar.visible:
			var sp := _cam.unproject_position(root.global_position + Vector3(0, 2.55 * root.scale.y, 0))
			bar.position = sp - Vector2(bar.size.x / 2.0, 0)
			var fill := bar.get_node("fill") as ColorRect
			fill.size.x = (bar.size.x - 2.0) * clampf(u.hp / u.max_hp, 0.0, 1.0)
	for pid in _shots:
		var p := _proj(pid)
		if not p.is_empty():
			var n: Node3D = _shots[pid]
			n.position = n.position.lerp(Vector3(p.pos.x, 1.0, p.pos.y), minf(1.0, delta * 30.0))
	var h := _hovered() if local_id != "" else null
	_hover_ring.visible = h != null
	if h:
		_hover_ring.position = Vector3(h.pos.x, 0.05, h.pos.y)
	_place_camera(false, delta)
	_hud_update(me)


func _pose(u: MobaUnit, v: Dictionary) -> void:
	var ch: BWCharacter = v.char
	if not u.alive:
		if v.pose != "fall":
			v.pose = "fall"
			v.anim_t = 0.0
			ch.anim_speed = 1.0
			ch.pose("fall")
		return
	if u.cast_serial != int(v.cast):
		v.cast = u.cast_serial
		v.pose = "cast"
		v.anim_t = 0.0
		ch.anim_speed = ATK_ANIM
		ch.pose("cast" if ch.has_clip("cast") else "strike")
		return
	if u.atk_wind >= 0.0 and v.pose != "windup" and v.pose != "strike":
		v.pose = "windup"
		v.anim_t = 0.0
		ch.anim_speed = ATK_ANIM
		ch.pose("windup" if ch.has_clip("windup") else "strike")
		return
	if u.atk_serial != int(v.atk):
		v.atk = u.atk_serial
		v.pose = "strike"
		v.anim_t = 0.0
		ch.anim_speed = ATK_ANIM
		ch.pose("strike")
		return
	if v.pose in ["cast", "strike", "windup"] and float(v.anim_t) < 0.45 and not u.moving:
		return
	var want := "run" if u.moving else "idle"
	if u.moving and not ch.has_clip("run"):
		want = "walk"
	if v.pose != want:
		v.pose = want
		ch.anim_speed = 1.0 if want == "idle" else clampf(u.ms_now() / 3.4, 0.8, 1.6)
		ch.pose(want)


func _place_camera(snap: bool, delta: float = 0.0) -> void:
	var me := sim.unit(local_id)
	var focus := Vector3.ZERO
	if me:
		var p: Vector2 = (_prev.get(me.id, me.pos) as Vector2).lerp(me.pos, clampf(_acc / MobaSim.TICK, 0.0, 1.0))
		focus = Vector3(p.x, 0, p.y)
	var pitch := deg_to_rad(CAM_PITCH)
	var want := focus + Vector3(0, sin(pitch) * CAM_DIST, cos(pitch) * CAM_DIST)
	_cam.position = want if snap else _cam.position.lerp(want, minf(1.0, delta * 12.0))
	_cam.look_at(_cam.position - Vector3(0, sin(pitch), cos(pitch)))


func _hud_update(me: MobaUnit) -> void:
	var b := sim.champ_of("blue")
	var r := sim.champ_of("red")
	if sim.mode == "duel":
		_score_l.text = "%s  %d  –  %d  %s\nfirst to %d" % [str(names.get("blue", b.name if b else "Blue")), sim.score.blue, sim.score.red,
			str(names.get("red", r.name if r else "Red")), MobaSim.KILLS_TO_WIN]
	else:
		_score_l.text = "Practice: hit the dummy"
	if me == null:
		return
	if not _over:
		_center_l.text = "" if me.alive else "Respawn in %d" % ceili(me.respawn_t)
	for slot in _slots:
		var cd := float(me.cd.get(slot, 0.0))
		var passive: bool = me.champ == "temu" and slot == "e"
		(_slots[slot].cd as Label).text = "passive" if passive else ("%d" % ceili(cd) if cd > 0.0 else "")
		(_slots[slot].panel as Control).modulate = Color(0.5, 0.5, 0.5) if cd > 0.0 else Color.WHITE
	var w := (_hp_fill.get_parent() as Control).size.x - 2.0
	_hp_fill.size = Vector2(w * clampf(me.hp / me.max_hp, 0.0, 1.0), 16)
	_hp_l.text = "%d / %d" % [maxi(0, int(me.hp)), int(me.max_hp)]
	_smoke.visible = me.blind_t > 0.0
	(_smoke.material as ShaderMaterial).set_shader_parameter("amount", 0.92 if me.blind_t > 0.0 else 0.0)
