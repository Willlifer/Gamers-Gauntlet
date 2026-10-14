class_name MobaTunePanel
extends CanvasLayer
## The live tuning panel (F1 in a MOBA match or the range): every MobaTune
## number as a slider + field, per champion and global. Changes apply to
## the running match at once and are saved to user://moba_tune.cfg; Reset
## puts the shipped numbers back. The game keeps running underneath.

signal changed

var sim: MobaSim
var _rows := {}           # key -> [HSlider, SpinBox]
var _note: Label


func _ready() -> void:
	layer = 50
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.92)
	sb.border_color = Color("#c8aa6e")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(16, 70)
	panel.custom_minimum_size = Vector2(470, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := Label.new()
	head.text = "Feel numbers  (F1 to close)"
	head.add_theme_color_override("font_color", Color("#c8aa6e"))
	head.add_theme_font_size_override("font_size", 18)
	col.add_child(head)
	for id in MobaChamps.ORDER:
		col.add_child(_section(str(MobaChamps.CHAMPS[id].name)))
		for s in MobaTune.STATS:
			col.add_child(_row("%s.%s" % [id, s]))
	col.add_child(_section("Everyone"))
	for k in MobaTune.GLOBAL:
		col.add_child(_row(k))
	var bar := HBoxContainer.new()
	var reset := Button.new()
	reset.text = "Reset to shipped numbers"
	reset.pressed.connect(func() -> void:
		MobaTune.reset()
		_refresh()
		_push())
	bar.add_child(reset)
	col.add_child(bar)
	_note = Label.new()
	_note.add_theme_color_override("font_color", Color("#8a96a3"))
	_note.add_theme_font_size_override("font_size", 12)
	col.add_child(_note)
	_refresh()


func _section(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color("#e8dcc0"))
	return l


func _row(key: String) -> HBoxContainer:
	var sp := MobaTune.spec(key)
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "  " + str(sp[0])
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = float(sp[1])
	sl.max_value = float(sp[2])
	sl.step = float(sp[3])
	sl.custom_minimum_size = Vector2(130, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var box := SpinBox.new()
	box.min_value = sl.min_value
	box.max_value = sl.max_value
	box.step = sl.step
	box.custom_minimum_size = Vector2(80, 0)
	row.add_child(box)
	sl.value_changed.connect(func(v: float) -> void:
		box.set_value_no_signal(v)
		MobaTune.set_value(key, v)
		_push())
	box.value_changed.connect(func(v: float) -> void:
		sl.set_value_no_signal(v)
		MobaTune.set_value(key, v)
		_push())
	_rows[key] = [sl, box]
	return row


func _refresh() -> void:
	for k in _rows:
		(_rows[k][0] as HSlider).set_value_no_signal(MobaTune.value(k))
		(_rows[k][1] as SpinBox).set_value_no_signal(MobaTune.value(k))
	_status()


func _push() -> void:
	MobaTune.apply(sim)
	_status()
	changed.emit()


func _status() -> void:
	var ch := MobaTune.changed_keys()
	_note.text = ("Saved to %s\n%d changed from shipped" % [ProjectSettings.globalize_path(MobaTune.PATH), ch.size()])
