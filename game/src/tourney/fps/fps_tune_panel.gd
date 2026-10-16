class_name FpsTunePanel
extends CanvasLayer
## F1 in the FPS prototype: every FpsTune number, grouped, live; saved to
## user://fps_tune.cfg. Reset restores the shipped numbers.
## G51b: "Recoil per gun": pick a named preset for each gun (Desert Eagle,
## Rifle, Sniper, Shotgun, Pistol, Carbine, or its own Baked profile), then
## trim it with that gun's scale; both save to the same cfg.

var _rows := {}
var _recoil_rows := {}                      # gun id -> [OptionButton, HSlider, SpinBox]
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
	head.text = "FPS feel numbers  (F1 to close)"
	head.add_theme_color_override("font_color", Color("#c8aa6e"))
	head.add_theme_font_size_override("font_size", 18)
	col.add_child(head)
	var section := ""
	for k: String in FpsTune.ENTRIES:
		var e: Array = FpsTune.ENTRIES[k]
		if str(e[5]) != section:
			section = str(e[5])
			var l := Label.new()
			l.text = section
			l.add_theme_color_override("font_color", Color("#e8dcc0"))
			col.add_child(l)
		col.add_child(_row(k, e))
	_recoil_section(col)
	var reset := Button.new()
	reset.text = "Reset to shipped numbers"
	reset.pressed.connect(func() -> void:
		FpsTune.reset()
		for key in _rows:
			(_rows[key][0] as HSlider).set_value_no_signal(FpsTune.value(key))
			(_rows[key][1] as SpinBox).set_value_no_signal(FpsTune.value(key))
		_refresh_recoil()
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
	sl.value = FpsTune.value(key)
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
		FpsTune.set_value(key, v)
		_status())
	box.value_changed.connect(func(v: float) -> void:
		sl.set_value_no_signal(v)
		FpsTune.set_value(key, v)
		_status())
	_rows[key] = [sl, box]
	return row


## G51b: a preset and a scale per gun.
func _recoil_section(col: VBoxContainer) -> void:
	var l := Label.new()
	l.text = "Recoil per gun (preset, then trim x)"
	l.add_theme_color_override("font_color", Color("#e8dcc0"))
	col.add_child(l)
	var names: Array = [""] + FpsWeapons.RECOIL_PRESETS.keys()
	for id: String in FpsWeapons.ORDER:
		if id == "slingshot":
			continue
		var row := HBoxContainer.new()
		var nl := Label.new()
		nl.text = "  " + str(FpsWeapons.SPECS[id].name)
		nl.custom_minimum_size = Vector2(150, 0)
		nl.add_theme_font_size_override("font_size", 13)
		row.add_child(nl)
		var ob := OptionButton.new()
		for n in names:
			ob.add_item("Baked (its own)" if n == "" else str(n))
		ob.custom_minimum_size = Vector2(130, 0)
		ob.item_selected.connect(func(i: int) -> void:
			FpsTune.set_recoil_preset(id, str(names[i]))
			_status())
		row.add_child(ob)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 3.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(110, 0)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sl)
		var box := SpinBox.new()
		box.min_value = 0.0
		box.max_value = 3.0
		box.step = 0.05
		box.custom_minimum_size = Vector2(80, 0)
		row.add_child(box)
		sl.value_changed.connect(func(v: float) -> void:
			box.set_value_no_signal(v)
			FpsTune.set_recoil_scale(id, v))
		box.value_changed.connect(func(v: float) -> void:
			sl.set_value_no_signal(v)
			FpsTune.set_recoil_scale(id, v))
		_recoil_rows[id] = [ob, sl, box, names]
		col.add_child(row)
	_refresh_recoil()


func _refresh_recoil() -> void:
	for id in _recoil_rows:
		var r: Array = _recoil_rows[id]
		(r[0] as OptionButton).select(maxi(0, (r[3] as Array).find(FpsTune.recoil_preset(id))))
		(r[1] as HSlider).set_value_no_signal(FpsTune.recoil_scale(id))
		(r[2] as SpinBox).set_value_no_signal(FpsTune.recoil_scale(id))


func _status() -> void:
	_note.text = "Saved to %s\n%d changed from shipped" % [ProjectSettings.globalize_path(FpsTune.PATH), FpsTune.changed_keys().size()]
