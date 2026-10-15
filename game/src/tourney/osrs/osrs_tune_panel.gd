class_name OsrsTunePanel
extends CanvasLayer
## F1 in the OSRS raid: every OsrsTune number, grouped, live; saved to
## user://osrs_tune.cfg. Reset restores the shipped numbers.

var _rows := {}
var _note: Label


func _ready() -> void:
	layer = 50
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.94)
	sb.border_color = Color("#c8aa6e")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(16, 16)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 820)
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	scroll.add_child(col)
	var head := Label.new()
	head.text = "OSRS raid numbers  (F1 to close)"
	head.add_theme_color_override("font_color", Color("#c8aa6e"))
	head.add_theme_font_size_override("font_size", 18)
	col.add_child(head)
	var section := ""
	for k: String in OsrsTune.ENTRIES:
		var e: Array = OsrsTune.ENTRIES[k]
		if str(e[5]) != section:
			section = str(e[5])
			var l := Label.new()
			l.text = section
			l.add_theme_color_override("font_color", Color("#e8dcc0"))
			col.add_child(l)
		col.add_child(_row(k, e))
	var reset := Button.new()
	reset.text = "Reset to shipped numbers"
	reset.pressed.connect(func() -> void:
		OsrsTune.reset()
		for key in _rows:
			(_rows[key][0] as HSlider).set_value_no_signal(OsrsTune.value(key))
			(_rows[key][1] as SpinBox).set_value_no_signal(OsrsTune.value(key))
		_status())
	col.add_child(reset)
	_note = Label.new()
	_note.add_theme_color_override("font_color", Color("#8a96a3"))
	_note.add_theme_font_size_override("font_size", 12)
	col.add_child(_note)
	_status()


func _row(key: String, e: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "  " + str(e[0])
	l.custom_minimum_size = Vector2(270, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = float(e[2])
	sl.max_value = float(e[3])
	sl.step = float(e[4])
	sl.value = OsrsTune.value(key)
	sl.custom_minimum_size = Vector2(130, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var box := SpinBox.new()
	box.min_value = sl.min_value
	box.max_value = sl.max_value
	box.step = sl.step
	box.value = sl.value
	box.custom_minimum_size = Vector2(80, 0)
	row.add_child(box)
	sl.value_changed.connect(func(v: float) -> void:
		box.set_value_no_signal(v)
		OsrsTune.set_value(key, v)
		_status())
	box.value_changed.connect(func(v: float) -> void:
		sl.set_value_no_signal(v)
		OsrsTune.set_value(key, v)
		_status())
	_rows[key] = [sl, box]
	return row


func _status() -> void:
	_note.text = "Saved to %s\n%d changed from shipped" % [ProjectSettings.globalize_path(OsrsTune.PATH), OsrsTune.changed_keys().size()]
