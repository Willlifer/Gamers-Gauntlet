class_name TourneyUI
extends RefCounted
## Control builders shared by the tournament screens. The palette is the
## tournament's own: ink panels with a colour accent per side.

const BLUE := Color("#3a7bd5")
const RED := Color("#c43c2a")
const GOLD := Color("#e0b040")
const PANEL := Color(0.07, 0.07, 0.09, 0.92)
const PANEL_LINE := Color(1, 1, 1, 0.18)
const DIM := Color(1, 1, 1, 0.55)


static func root(host: Node) -> Control:
	var layer := CanvasLayer.new()
	host.add_child(layer)
	var r := Control.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.theme = BWStyle.theme()
	layer.add_child(r)
	return r


static func panel(parent: Control, rect: Rect2, title: String = "") -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = PANEL_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	if title != "":
		var t := label(v, title, BWStyle.F_SUB)
		t.add_theme_color_override("font_color", GOLD)
	return v


static func label(parent: Control, text: String, size: int = BWStyle.F_BODY, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


## A paragraph: wraps to its container's width.
static func para(parent: Control, text: String, size: int = BWStyle.F_SMALL, col: Color = DIM) -> Label:
	var l := label(parent, text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func big(parent: Control, text: String, size: int = 44, col: Color = Color.WHITE) -> Label:
	var l := label(parent, text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	return l


static func button(parent: Control, text: String, fn: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", BWStyle.F_BODY)
	if fn.is_valid():
		b.pressed.connect(fn)
	parent.add_child(b)
	return b


static func row(parent: Control, sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


static func line_edit(parent: Control, text: String, placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", BWStyle.F_BODY)
	e.custom_minimum_size.x = 220
	parent.add_child(e)
	return e


static func option(parent: Control, items: Array, selected: int, fn: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	o.add_theme_font_size_override("font_size", BWStyle.F_BODY)
	o.item_selected.connect(fn)
	parent.add_child(o)
	return o


static func swatch(parent: Control, hex: String, picked: bool, fn: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(30, 30)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(hex)
	sb.border_color = Color.WHITE if picked else Color(1, 1, 1, 0.25)
	sb.set_border_width_all(3 if picked else 1)
	sb.set_corner_radius_all(15)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


## A 3D stage in a SubViewport showing one character, for the lobby and
## the matchup. Returns { container, viewport, view }.
static func stage(parent: Control, u: BWUnit, size: Vector2, full_body: bool, tint: Color = Color(0.11, 0.11, 0.13)) -> Dictionary:
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = size
	svc.stretch = true
	parent.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = tint
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var view := BWUnitView.new()
	vp.add_child(view)
	view.setup(u)
	view.show_label(false)
	var cam := Camera3D.new()
	cam.fov = 28.0
	vp.add_child(cam)
	var hy := view.head_height()
	if full_body:
		cam.position = Vector3(0.0, 1.1, 5.6)
		cam.look_at(Vector3(0, 0.95, 0))
	else:
		cam.position = Vector3(0.0, hy + 0.18, 3.2)
		cam.look_at(Vector3(0, hy + 0.02, 0))
	cam.make_current()
	return { "container": svc, "viewport": vp, "view": view }


## A one-shot timer owned by `host`: its callback never outlives the screen.
static func after(host: Node, sec: float, fn: Callable) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(sec, 0.01)
	host.add_child(t)
	t.timeout.connect(func():
		fn.call()
		t.queue_free())
	t.start()


static func key_name(k: int) -> String:
	return OS.get_keycode_string(k)
