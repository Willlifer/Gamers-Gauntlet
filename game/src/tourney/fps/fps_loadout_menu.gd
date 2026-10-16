class_name FpsLoadoutMenu
extends CanvasLayer
## The radial loadout (G43), after Counter-Strike's buy wheel
## (design/ref/fps/radial_buy.jpg): before every life, over the live view, a
## dark wheel of up to six wedges (the primaries, then "Random"), numbers on
## the inner ring, an emblem in the hub; an inventory panel on the right with
## this life's rolled sidearm and the pick; key hints along the bottom; a pick
## timer. Click a wedge or press its number. Esc or the timer keeps the last
## pick, F3 picks at random. Emits `picked(primary)` once, then frees itself.
## G51: O (or the Options button) opens the shooter's settings, moved here
## from the lobby's Shooter range: mouse and aim sensitivity, field of view,
## and the keys (FpsBinds); the pick timer waits while it's open.

signal picked(primary: String)

const TIME := 10.0
const GREEN := Color("#a6d86a")
const INK := Color(0.04, 0.045, 0.05, 0.72)
const LINE := Color(1, 1, 1, 0.22)
const GOLD := Color("#d8b25a")

var options: Array = []                     # primary ids, "random" last
var sidearm := "pistol"
var last := ""
var _t := TIME
var _hover := -1
var _wheel: Control
var _inv: VBoxContainer
var _timer_l: Label
var _done := false
var _icons := {}                            # id -> SubViewport texture
var _opts: PanelContainer                   # the options panel (G51); null when closed
var _bind_box: VBoxContainer
var _waiting := ""                          # a bind waiting for its key
var _opt_note: Label


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = BWStyle.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var title := _label(root, "LOADOUT", 40, Color(1, 1, 1, 0.92))
	title.position = Vector2(150, 50)
	var sub := _label(root, "SELECT PRIMARY", 22, Color(1, 1, 1, 0.7))
	sub.position = Vector2(150, 98)
	_timer_l = _label(root, "", 20, Color(1, 1, 1, 0.65))
	_timer_l.position = Vector2(150, 132)
	_wheel = Control.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.draw.connect(_draw_wheel)
	_wheel.gui_input.connect(_wheel_input)
	root.add_child(_wheel)
	for i in options.size():
		var id := str(options[i])
		if id != "random":
			_icons[id] = _icon(id)
	_icons[sidearm] = _icon(sidearm)
	# the inventory panel
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -360
	panel.offset_right = -40
	panel.offset_top = 150
	panel.offset_bottom = -150
	root.add_child(panel)
	_inv = VBoxContainer.new()
	_inv.add_theme_constant_override("separation", 10)
	panel.add_child(_inv)
	# hints
	var hints := HBoxContainer.new()
	hints.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hints.offset_top = -70
	hints.offset_bottom = -30
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_theme_constant_override("separation", 140)
	root.add_child(hints)
	for h in ["[ESC] Keep last pick", "[1-%d] Pick" % options.size(), "[F3] Random"]:
		_label(hints, h, 18, Color(1, 1, 1, 0.75))
	var ob := Button.new()
	ob.text = "[O] Options: keys, sensitivity"
	ob.add_theme_font_size_override("font_size", 18)
	ob.focus_mode = Control.FOCUS_NONE
	ob.pressed.connect(toggle_options)
	hints.add_child(ob)
	_refresh_inv()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _center() -> Vector2:
	var s := _wheel.size
	return Vector2(s.x * 0.36, s.y * 0.52)


func _radius() -> float:
	return _wheel.size.y * 0.3


## Wedge i spans [a0, a1], clockwise from the top.
func _span(i: int) -> Vector2:
	var n := options.size()
	var w := TAU / n
	var a0 := -PI * 0.5 - w * 0.5 + w * i
	return Vector2(a0, a0 + w)


func _draw_wheel() -> void:
	var c := _center()
	var r := _radius()
	var hub := r * 0.24
	var font := ThemeDB.fallback_font
	_wheel.draw_circle(c, r, INK)
	for i in options.size():
		var sp := _span(i)
		if i == _hover:
			var pts := PackedVector2Array()
			for k in 25:
				var a := lerpf(sp.x, sp.y, k / 24.0)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			for k in 25:
				var a := lerpf(sp.y, sp.x, k / 24.0)
				pts.append(c + Vector2(cos(a), sin(a)) * hub * 1.25)
			_wheel.draw_colored_polygon(pts, Color(1, 1, 1, 0.12))
		_wheel.draw_line(c + Vector2(cos(sp.x), sin(sp.x)) * hub * 1.25, c + Vector2(cos(sp.x), sin(sp.x)) * r, LINE, 2.0)
		var mid := (sp.x + sp.y) * 0.5
		var dir := Vector2(cos(mid), sin(mid))
		var id := str(options[i])
		var at := c + dir * r * 0.66
		var name_ := "Random" if id == "random" else str(FpsWeapons.SPECS[id].name)
		var role := "Surprise me" if id == "random" else str(FpsWeapons.ROLE.get(id, ""))
		var isz := Vector2(r * 0.5, r * 0.22)
		if _icons.has(id) and _icons[id]:
			var tex: Texture2D = _icons[id]
			_wheel.draw_texture_rect(tex, Rect2(at - Vector2(isz.x * 0.5, isz.y + 4.0), isz), false)
		if FpsWeapons.PRICE.has(id):
			_text(font, at - Vector2(0, isz.y + 10.0), "$%d" % int(FpsWeapons.PRICE[id]), 17, GREEN)
		_text(font, at + Vector2(0, 16), name_, 18, Color.WHITE)
		_text(font, at + Vector2(0, 34), role, 13, Color(1, 1, 1, 0.6))
		_text(font, c + dir * hub * 1.55 + Vector2(0, 6), str(i + 1), 15, Color(1, 1, 1, 0.75))
	_wheel.draw_arc(c, r, 0, TAU, 96, LINE, 2.0, true)
	_wheel.draw_arc(c, hub * 1.25, 0, TAU, 64, LINE, 1.5, true)
	# the hub: a gold roundel with a star
	_wheel.draw_circle(c, hub, Color(0.08, 0.08, 0.09, 0.9))
	_wheel.draw_arc(c, hub * 0.82, 0, TAU, 48, GOLD, 3.0, true)
	var star := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		star.append(c + Vector2(cos(a), sin(a)) * hub * (0.55 if k % 2 == 0 else 0.23))
	_wheel.draw_colored_polygon(star, GOLD)


func _text(font: Font, at: Vector2, text: String, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_wheel.draw_string_outline(font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.7))
	_wheel.draw_string(font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _refresh_inv() -> void:
	for ch in _inv.get_children():
		ch.queue_free()
	_label(_inv, "Inventory", 22, Color(1, 1, 1, 0.9))
	var pick := last if _hover < 0 else str(options[_hover])
	for row in [[pick, "Primary"], [sidearm, "Sidearm (rolled)" if sidearm != "deagle" else "Sidearm (rolled): BIG BOOM"]]:
		var id := str(row[0])
		_label(_inv, str(row[1]), 15, GREEN if id != "deagle" else GOLD)
		if _icons.has(id):
			var tr := TextureRect.new()
			tr.texture = _icons[id]
			tr.custom_minimum_size = Vector2(280, 110)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_inv.add_child(tr)
		var nm := "Random" if id == "random" or id == "" else str(FpsWeapons.SPECS[id].name)
		_label(_inv, nm, 20, Color.WHITE)


func _wheel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var d: Vector2 = ev.position - _center()
		var h := -1
		if d.length() > _radius() * 0.3 and d.length() < _radius() * 1.1:
			var a := atan2(d.y, d.x)
			for i in options.size():
				var sp := _span(i)
				if fposmod(a - sp.x, TAU) < sp.y - sp.x:
					h = i
		if h != _hover:
			_hover = h
			_wheel.queue_redraw()
			_refresh_inv()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _hover >= 0:
		_pick(str(options[_hover]))


## A bind waiting for its key takes the next key press before anything else.
func _input(ev: InputEvent) -> void:
	if _waiting == "" or not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	get_viewport().set_input_as_handled()
	var k: int = ev.physical_keycode
	if k == KEY_ESCAPE:
		_waiting = ""
		_opt_note.text = ""
	else:
		var bumped := FpsBinds.set_key(_waiting, k)
		_opt_note.text = ("%s was on %s; it's unbound now." % [FpsBinds.LABEL[bumped], FpsBinds.name_of(k)]) if bumped != "" else ""
		_waiting = ""
	_refresh_binds()


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var k: int = ev.physical_keycode
	if _opts:
		if k == KEY_ESCAPE or k == KEY_O:
			toggle_options()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_O:
		toggle_options()
	elif k >= KEY_1 and k < KEY_1 + options.size():
		_pick(str(options[k - KEY_1]))
	elif k == KEY_ESCAPE:
		_pick(last)
	elif k == KEY_F3:
		_pick("random")
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _opts:
		return                              # the timer waits while the options are open
	_t -= delta
	_timer_l.text = "Pick time left: %d" % ceili(maxf(_t, 0.0))
	if _t <= 0.0:
		_pick(last)


func _pick(id: String) -> void:
	if _done:
		return
	_done = true
	var real := options.filter(func(o: String) -> bool: return o != "random")
	if id == "random" or id == "" or not id in real:
		id = str(real[randi() % real.size()]) if id == "random" or last == "" or not last in real else last
	picked.emit(id)
	queue_free()


# ------------------------------------------------------------- options (G51)

## Open or close the shooter's settings over the wheel.
func toggle_options() -> void:
	if _opts:
		_opts.queue_free()
		_opts = null
		_waiting = ""
		_wheel.visible = true
		return
	_wheel.visible = false
	_opts = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.05, 0.9)
	sb.border_color = GOLD
	sb.set_border_width_all(1)
	sb.set_content_margin_all(18)
	_opts.add_theme_stylebox_override("panel", sb)
	_opts.position = Vector2(150, 170)
	_opts.custom_minimum_size = Vector2(620, 0)
	_wheel.get_parent().add_child(_opts)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_opts.add_child(col)
	_label(col, "OPTIONS", 26, Color(1, 1, 1, 0.92))
	for key in ["mouse_sens", "ads_sens", "fov"]:
		col.add_child(_slider(key))
	_label(col, "Keys: click one, then press the key you want (Esc cancels)", 15, Color(1, 1, 1, 0.6))
	_bind_box = VBoxContainer.new()
	_bind_box.add_theme_constant_override("separation", 3)
	col.add_child(_bind_box)
	_refresh_binds()
	_opt_note = _label(col, "", 15, GOLD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var rs := Button.new()
	rs.text = "Reset keys"
	rs.focus_mode = Control.FOCUS_NONE
	rs.pressed.connect(func() -> void:
		FpsBinds.reset()
		_refresh_binds())
	row.add_child(rs)
	var cl := Button.new()
	cl.text = "Back to the wheel [O]"
	cl.focus_mode = Control.FOCUS_NONE
	cl.pressed.connect(toggle_options)
	row.add_child(cl)


## A labelled slider on an FpsTune number (the same store as the F1 panel).
func _slider(key: String) -> HBoxContainer:
	var e: Array = FpsTune.ENTRIES[key]
	var row := HBoxContainer.new()
	var l := _label(row, str(e[0]), 16, Color.WHITE)
	l.custom_minimum_size.x = 300
	var sl := HSlider.new()
	sl.min_value = float(e[2])
	sl.max_value = float(e[3])
	sl.step = float(e[4])
	sl.value = FpsTune.value(key)
	sl.custom_minimum_size = Vector2(200, 24)
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var v := _label(row, "%.2f" % sl.value, 16, GREEN)
	sl.value_changed.connect(func(x: float) -> void:
		FpsTune.set_value(key, x)
		v.text = "%.2f" % x)
	return row


func _refresh_binds() -> void:
	if _bind_box == null:
		return
	for c in _bind_box.get_children():
		c.queue_free()
	for a: String in FpsBinds.ORDER:
		var row := HBoxContainer.new()
		_bind_box.add_child(row)
		var l := _label(row, str(FpsBinds.LABEL[a]), 16, Color(1, 1, 1, 0.85))
		l.custom_minimum_size.x = 300
		var b := Button.new()
		b.text = "..." if _waiting == a else FpsBinds.name_of(FpsBinds.key(a))
		b.custom_minimum_size.x = 160
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_waiting = a
			_refresh_binds())
		row.add_child(b)


## A side view of the gun, rendered once into a small transparent viewport.
func _icon(id: String) -> Texture2D:
	if not FpsWeapons.available(id):
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 160)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var a := GKRegistry.build(str(FpsWeapons.SPECS[id].asset), FpsWeapons.SPECS[id].params)
	var n := a.instantiate(false)
	vp.add_child(n)
	var bb := a.aabb()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(bb.size.z * 1.06 * 160.0 / 360.0, bb.size.y * 1.1)   # the orthographic size is the view's height
	var mid := bb.get_center()
	cam.position = mid + Vector3(-2.0, 0, 0)          # the gun's right side: muzzle to the right
	vp.add_child(cam)
	cam.look_at(mid, Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -120, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)
	return vp.get_texture()
