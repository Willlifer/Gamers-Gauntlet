class_name TourneyUI
extends RefCounted
## Control builders shared by the tournament screens. The look (G27, after the
## author's Smash Ultimate references): restrained ink panels over the slowly
## circling map (TourneyBackdrop), one warm accent, gold for winners, blue and
## red only for the two sides of a match; the motion comes from the tiles'
## painted streaks, the reels and the camera, not from colour.

const BLUE := Color("#4a86d8")
const RED := Color("#d8473b")
const GOLD := Color("#e2b54a")
const ACCENT := Color("#e8483b")           ## the one warm accent: start, up next, you
const INK := Color("#0c111b")
const PANEL := Color(0.05, 0.07, 0.11, 0.84)
const PANEL_LINE := Color(1, 1, 1, 0.16)
const PLATE := Color("#e9ecf1")            ## the bracket's name plates
const PLATE_INK := Color("#141a26")
const DIM := Color(1, 1, 1, 0.55)

static var _display: Font


## The display face for titles and tiles: a heavy italic system sans (Segoe UI
## Black on Windows), falling back to the theme font.
static func display_font() -> Font:
	if _display == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Black", "Arial Black", "Helvetica Neue", "Arial"])
		f.font_weight = 900
		f.font_italic = true
		_display = f
	return _display


## A title in the display face with a dark outline.
static func display(parent: Control, text: String, size: int, col: Color = Color.WHITE) -> Label:
	var l := label(parent, text, size, col)
	l.add_theme_font_override("font", display_font())
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	return l


## The banner across the top of a screen: a slanted accent block with the
## title, a thin ink strip with the subtitle. Returns the strip.
static func header(parent: Control, title: String, sub: String = "") -> Control:
	var strip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.86)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.border_width_bottom = 2
	strip.add_theme_stylebox_override("panel", sb)
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = 14
	strip.offset_bottom = 66
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(strip)
	var block := Panel.new()
	var bb := StyleBoxFlat.new()
	bb.bg_color = ACCENT
	bb.skew = Vector2(0.35, 0)
	block.add_theme_stylebox_override("panel", bb)
	block.position = Vector2(-30, 8)
	block.size = Vector2(560, 64)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	var t := display(parent, title, 34)
	t.position = Vector2(40, 12)
	if sub != "":
		var s := label(parent, sub, BWStyle.F_SMALL, Color(1, 1, 1, 0.8))
		s.position = Vector2(580, 27)
	return strip


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
	p.add_theme_stylebox_override("panel", panel_box())
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	if title != "":
		display(v, title.to_upper(), 20, Color.WHITE)
	return v


## The ink card: translucent over the backdrop, a hairline rim, a thicker top.
static func panel_box(top: Color = Color(1, 1, 1, 0.22)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = top
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(4, 6)
	return sb


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
	b.custom_minimum_size = Vector2(26, 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(hex)
	sb.border_color = Color.WHITE if picked else Color(1, 1, 1, 0.25)
	sb.set_border_width_all(3 if picked else 1)
	sb.set_corner_radius_all(13)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


## A 3D stage in a SubViewport showing one character, for the lobby and
## the matchup. A clear `tint` (alpha 0) leaves the background see-through.
## Returns { container, viewport, view }.
static func stage(parent: Control, u: BWUnit, size: Vector2, full_body: bool, tint: Color = Color(0.07, 0.09, 0.13)) -> Dictionary:
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = size
	svc.stretch = true
	parent.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = tint.a < 0.01          # see-through: the figure stands on the backdrop
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR if vp.transparent_bg else Environment.BG_COLOR
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
