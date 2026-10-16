class_name RangeScreen
extends Node
## A testing module: keybinds (click a bind, press a key) and sensitivity,
## saved to user://tourney.cfg. The MOBA and shooter ranges share the code
## and list different binds; a playable practice target comes with the
## first module of each kind.
## G50: the lobby no longer opens it (the options move into each game's own
## select / buy phase); kept for tools/aram_shots.gd and for reuse.

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
	if kind != "moba":
		TourneyUI.para(p, "The shooter practice target arrives with the first shooter game. For now this is where your binds live.", BWStyle.F_BODY)
		return
	var r2 := TourneyUI.row(p)
	TourneyUI.label(r2, "Champion:", BWStyle.F_SMALL, TourneyUI.DIM)
	for id in MobaChamps.ORDER:
		TourneyUI.button(r2, str(MobaChamps.CHAMPS[id].name), func(): _practice(id))
	TourneyUI.para(p, "Right- or left-click to move and attack. Your binds work here. The dummy heals 4 s after you stop hitting it.")
	_box = p
	_practice(MobaChamps.ORDER[0])


var _box: VBoxContainer
var _svc: SubViewportContainer


func _practice(champ: String) -> void:
	if _svc:
		_svc.queue_free()
	_binds = TourneyState.load_binds()
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_svc.custom_minimum_size = Vector2(880, 640)
	_box.add_child(_svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.handle_input_locally = true
	_svc.add_child(vp)
	var s := MobaSim.new(1, "practice")
	var me := s.add_champ(champ, "blue", "You")
	me.pos = Vector2(-6, 0)
	s.add_dummy(Vector2(0, 0))
	var view := MobaView.new()
	view.setup(s, me.id, {}, _binds, { "blue": "You" })
	vp.add_child(view)


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
