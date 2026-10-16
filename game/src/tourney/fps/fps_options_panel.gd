class_name FpsOptionsPanel
extends PanelContainer
## The shooter's settings (G51), what the lobby's Shooter range held: mouse
## and aim sensitivity, field of view (FpsTune, the store the F1 panel
## edits) and the keys (FpsBinds: click one, press a key; Esc cancels).
## A self-contained node: FpsLoadoutMenu opens it in the buy phase; any other
## screen can add it too. Emits `closed` from its back button.

signal closed

const GOLD := Color("#d8b25a")
const GREEN := Color("#a6d86a")
const SLIDERS := ["mouse_sens", "ads_sens", "fov"]

var _bind_box: VBoxContainer
var _waiting := ""                          # a bind waiting for its key
var _note: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.05, 0.9)
	sb.border_color = GOLD
	sb.set_border_width_all(1)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(620, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_label(col, "OPTIONS", 26, Color(1, 1, 1, 0.92))
	for key: String in SLIDERS:
		col.add_child(_slider(key))
	_label(col, "Keys: click one, then press the key you want (Esc cancels)", 15, Color(1, 1, 1, 0.6))
	_bind_box = VBoxContainer.new()
	_bind_box.add_theme_constant_override("separation", 3)
	col.add_child(_bind_box)
	_refresh_binds()
	_note = _label(col, "", 15, GOLD)
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
	cl.pressed.connect(func() -> void: closed.emit())
	row.add_child(cl)


## Is a bind waiting for its key (so Esc / O belong to it)?
func capturing() -> bool:
	return _waiting != ""


## A bind waiting for its key takes the next key press before anything else.
func _input(ev: InputEvent) -> void:
	if _waiting == "" or not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	get_viewport().set_input_as_handled()
	var k: int = ev.physical_keycode
	if k == KEY_ESCAPE:
		_note.text = ""
	else:
		var bumped := FpsBinds.set_key(_waiting, k)
		_note.text = ("%s was on %s; it's unbound now." % [FpsBinds.LABEL[bumped], FpsBinds.name_of(k)]) if bumped != "" else ""
	_waiting = ""
	_refresh_binds()


func _label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


## A labelled slider on an FpsTune number.
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
