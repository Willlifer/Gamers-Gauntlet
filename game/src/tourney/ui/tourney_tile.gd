class_name TourneyTile
extends Control
## A menu tile after Smash Ultimate's main menu (G27): a slanted card whose
## surface is slow painted streaks in one muted tint (tile.gdshader), a
## white rim, a huge faded tag behind a heavy italic title, a line under it.
## Hover lifts it and lights the rim; a click flashes it and emits `pressed`.
##   var t := TourneyTile.make(parent, Rect2(20, 80, 600, 300), "Tournament", "4–8 players", TourneyUI.ACCENT)
##   t.pressed.connect(...)

signal pressed
signal hovered(tile: TourneyTile)

const SKEW := 16.0

var title := ""
var sub := ""
var tag := ""                               ## the big faded word behind (MOBA, FPS…)
var tint := Color("#2a3346")
var title_size := 30
var disabled := false:
	set(v):
		disabled = v
		modulate = Color(1, 1, 1, 0.45) if v else Color.WHITE
		mouse_default_cursor_shape = Control.CURSOR_ARROW if v else Control.CURSOR_POINTING_HAND
var blurb := ""                             ## the ticker line while hovered

var _hov := 0.0
var _hov_to := 0.0
var _flash := 0.0
var _surface: Control
var _mat: ShaderMaterial
var _title_l: Label
var _sub_l: Label
var _tag_l: Label

static var _shader: Shader


static func make(parent: Control, rect: Rect2, p_title: String, p_sub: String, p_tint: Color, p_tag: String = "") -> TourneyTile:
	var t := TourneyTile.new()
	t.title = p_title
	t.sub = p_sub
	t.tint = p_tint
	t.tag = p_tag
	t.position = rect.position
	t.size = rect.size
	parent.add_child(t)
	return t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size * 0.5
	clip_contents = false
	if _shader == null:
		_shader = load("res://src/tourney/ui/tile.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_surface = Control.new()
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.material = _mat
	_surface.draw.connect(_draw_surface)
	add_child(_surface)
	var clip := Control.new()               # the tag and titles stay inside the card
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	if tag != "":
		_tag_l = Label.new()
		_tag_l.text = tag
		_tag_l.add_theme_font_override("font", TourneyUI.display_font())
		_tag_l.add_theme_font_size_override("font_size", int(minf(size.y * 0.62, 150.0)))
		_tag_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.07))
		_tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_tag_l.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tag_l.offset_right = -SKEW - 10.0
		_tag_l.offset_top = -size.y * 0.12
		_tag_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(_tag_l)
	var rim := Control.new()
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.draw.connect(_draw_rim.bind(rim))
	add_child(rim)
	rim.set_meta("rim", true)
	_title_l = Label.new()
	_title_l.text = title
	_title_l.add_theme_font_override("font", TourneyUI.display_font())
	_title_l.add_theme_font_size_override("font_size", title_size)
	_title_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_title_l.add_theme_constant_override("outline_size", maxi(4, title_size / 6))
	_title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_title_l)
	_sub_l = Label.new()
	_sub_l.text = sub
	_sub_l.add_theme_font_size_override("font_size", BWStyle.F_SMALL if size.y > 120 else 14)
	_sub_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	_sub_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_sub_l.add_theme_constant_override("outline_size", 3)
	_sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clip.add_child(_sub_l)
	_place_text()
	mouse_entered.connect(func():
		if disabled:
			return
		_hov_to = 1.0
		BWSfx.ui("ui_hover")
		hovered.emit(self))
	mouse_exited.connect(func(): _hov_to = 0.0)


func set_title(t: String) -> void:
	title = t
	if _title_l:
		_title_l.text = t


func set_sub(t: String) -> void:
	sub = t
	if _sub_l:
		_sub_l.text = t
		_place_text()


func _place_text() -> void:
	var sub_h := 0.0 if sub == "" else (22.0 if size.y <= 120 else 46.0)
	var pad := 18.0
	_sub_l.position = Vector2(pad, size.y - pad - sub_h + 4.0)
	_sub_l.size = Vector2(size.x - pad * 2.0 - SKEW, sub_h)
	# long names shrink to fit the card
	var room := size.x - pad * 2.0 - SKEW
	var fs := title_size
	while fs > 14 and TourneyUI.display_font().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	_title_l.add_theme_font_size_override("font_size", fs)
	_title_l.position = Vector2(pad + SKEW * 0.3, size.y - pad - sub_h - title_size * 1.35 + (title_size - fs) * 0.6)
	_title_l.size = Vector2(size.x - pad * 2.0, title_size * 1.4)


func _gui_input(ev: InputEvent) -> void:
	if disabled:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_flash = 1.0
		BWSfx.ui("ui_confirm")
		accept_event()
		pressed.emit()


func _process(delta: float) -> void:
	_hov = move_toward(_hov, _hov_to, delta * 7.0)
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	var e := _hov * _hov * (3.0 - 2.0 * _hov)
	scale = Vector2.ONE * (1.0 + 0.03 * e)
	_mat.set_shader_parameter("hover", e)
	_mat.set_shader_parameter("flash", _flash)
	z_index = 1 if _hov > 0.01 else 0
	for c in get_children():
		if c.has_meta("rim"):
			(c as Control).queue_redraw()


func _poly(inset: float = 0.0) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var k := SKEW
	return PackedVector2Array([Vector2(k + inset, inset), Vector2(w - inset, inset), Vector2(w - k - inset, h - inset), Vector2(inset, h - inset)])


func _draw() -> void:
	var sh := _poly()
	var off := Vector2(6, 8) * (1.0 + _hov)
	for i in sh.size():
		sh[i] += off
	draw_colored_polygon(sh, Color(0, 0, 0, 0.38))


func _draw_surface() -> void:
	var pts := _poly()
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(p / size)
	_surface.draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs)


func _draw_rim(rim: Control) -> void:
	var pts := _poly(1.5)
	pts.append(pts[0])
	var e := _hov * _hov * (3.0 - 2.0 * _hov)
	var col := Color(1, 1, 1, 0.55 + 0.45 * e)
	rim.draw_polyline(pts, col, 2.0 + 2.0 * e, true)
	# the line under the title
	var y := _title_l.position.y + title_size * 1.32 if _title_l else size.y - 30.0
	rim.draw_line(Vector2(18, y), Vector2(18 + (size.x - 60) * (0.35 + 0.65 * e), y), Color(1, 1, 1, 0.35 + 0.4 * e), 2.0)
