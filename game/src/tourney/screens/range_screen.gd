class_name RangeScreen
extends Node
## A testing module: keybinds (click a bind, press a key) and sensitivity,
## saved to user://tourney.cfg. The MOBA and shooter ranges share the code
## and list different binds; a playable practice target comes with the
## first module of each kind.

signal back

var kind := "moba"
var _binds := {}
var _sens := {}
var _root: Control
var _list: VBoxContainer
var _waiting := ""        # bind id awaiting a key
var _status: Label

const MOBA := [["q", "Q spell"], ["w", "W spell"], ["e", "E spell"], ["r", "Ultimate"], ["flash", "Flash"],
	["spell2", "Second spell (ignite / smite)"], ["stop", "Stop"], ["recall", "Recall"]]
const SHOOTER := [["q", "Ability 1"], ["w", "Ability 2"], ["e", "Ability 3"], ["r", "Ultimate"], ["flash", "Reload"],
	["spell2", "Use / plant"], ["stop", "Crouch"], ["recall", "Night vision"]]


func _ready() -> void:
	_binds = TourneyState.load_binds()
	_sens = TourneyState.load_sens()
	_root = TourneyUI.root(self)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_root.move_child(bg, 0)
	var v := TourneyUI.panel(_root, Rect2(20, 20, 620, 860), "MOBA range" if kind == "moba" else "Shooter range")
	TourneyUI.label(v, "Click a bind, then press the key you want.", BWStyle.F_SMALL, TourneyUI.DIM)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	_refresh()
	TourneyUI.label(v, "Mouse sensitivity", BWStyle.F_SMALL, TourneyUI.DIM)
	var sl := HSlider.new()
	sl.min_value = 0.2
	sl.max_value = 3.0
	sl.step = 0.05
	sl.value = float(_sens.mouse)
	sl.value_changed.connect(func(x): _sens.mouse = x; TourneyState.save_sens(_sens))
	v.add_child(sl)
	var lock := CheckBox.new()
	lock.text = "Camera locked to your champion"
	lock.button_pressed = bool(_sens.camera_lock)
	lock.toggled.connect(func(on): _sens.camera_lock = on; TourneyState.save_sens(_sens))
	v.add_child(lock)
	_status = TourneyUI.label(v, "", BWStyle.F_SMALL, TourneyUI.GOLD)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var r := TourneyUI.row(v)
	TourneyUI.button(r, "Reset to defaults", func():
		_binds = TourneyState.DEFAULT_BINDS.duplicate()
		TourneyState.save_binds(_binds)
		_refresh())
	TourneyUI.button(r, "Back to the lobby", func(): back.emit())
	var p := TourneyUI.panel(_root, Rect2(660, 20, 920, 860), "Practice")
	TourneyUI.para(p, "The practice target arrives with the first %s game. For now this is where your binds live." % ("MOBA" if kind == "moba" else "shooter"), BWStyle.F_BODY)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for pair in (MOBA if kind == "moba" else SHOOTER):
		var id: String = pair[0]
		var r := TourneyUI.row(_list)
		var l := TourneyUI.label(r, pair[1], BWStyle.F_BODY)
		l.custom_minimum_size.x = 330
		var b := TourneyUI.button(r, "..." if _waiting == id else TourneyUI.key_name(int(_binds[id])), func():
			_waiting = id
			_refresh())
		b.custom_minimum_size.x = 160


func _unhandled_input(ev: InputEvent) -> void:
	if _waiting == "" or not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	if ev.keycode == KEY_ESCAPE:
		_waiting = ""
		_refresh()
		return
	for k in _binds:
		if int(_binds[k]) == ev.keycode and k != _waiting:
			_status.text = "%s was on that key; it's unbound now." % k.capitalize()
			_binds[k] = 0
	_binds[_waiting] = ev.keycode
	_waiting = ""
	TourneyState.save_binds(_binds)
	_refresh()
	get_viewport().set_input_as_handled()
