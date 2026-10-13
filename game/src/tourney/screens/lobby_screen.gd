class_name LobbyScreen
extends Node
## The lobby: players and the join code on the left, connection on the
## right, the character creator centre-right, the testing modules along the
## bottom. Start opens once everyone is ready (bots fill the empty seats).

signal start
signal open_range(kind: String)

var state: TourneyState
var _root: Control
var _players_box: VBoxContainer
var _stage: Dictionary
var _me: Dictionary
var _swatches: HBoxContainer
var _start_btn: Button
var _ready_btn: Button


func _ready() -> void:
	_me = state.me()
	_root = TourneyUI.root(self)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_root.move_child(bg, 0)
	_build_left()
	_build_right()
	_build_creator()
	_build_bottom()
	_refresh_players()


# ------------------------------------------------------------------ left

func _build_left() -> void:
	var v := TourneyUI.panel(_root, Rect2(20, 20, 400, 580), "Lobby")
	var code := TourneyUI.label(v, "Join code  %s" % state.join_code, BWStyle.F_NAME)
	code.add_theme_color_override("font_color", Color.WHITE)
	TourneyUI.para(v, "Friends enter it from the title screen. Offline for now: bots fill the seats.")
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	v.add_child(_players_box)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var r := TourneyUI.row(v)
	TourneyUI.button(r, "Add bot", func(): state.add_bot(); _refresh_players())
	TourneyUI.button(r, "Remove bot", func(): state.remove_bot(); _refresh_players())
	_ready_btn = TourneyUI.button(v, "Ready", func():
		_me.ready = not _me.ready
		_refresh_players())


func _refresh_players() -> void:
	for c in _players_box.get_children():
		c.queue_free()
	for p in state.players:
		var r := TourneyUI.row(_players_box)
		var dot := TourneyUI.label(r, "●", BWStyle.F_BODY, Color("#2fa36b") if p.ready else Color(1, 1, 1, 0.25))
		dot.custom_minimum_size.x = 24
		var sw := ColorRect.new()
		sw.color = Color(str(p.hair_hex))
		sw.custom_minimum_size = Vector2(14, 22)
		r.add_child(sw)
		TourneyUI.label(r, "%s  ·  %s%s" % [p.name, p.title, "  (bot)" if p.bot else ""], BWStyle.F_BODY).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TourneyUI.label(_players_box, "%d / %d players  ·  %d needed" % [state.players.size(), TourneyState.MAX_PLAYERS, TourneyState.MIN_PLAYERS],
		BWStyle.F_SMALL, TourneyUI.DIM)
	if _ready_btn:
		_ready_btn.text = "Not ready" if _me.ready else "Ready"
	if _start_btn:
		_start_btn.disabled = not state.all_ready()
		_start_btn.text = "Start the tournament" if state.all_ready() else "Start (waiting on ready)"


# ----------------------------------------------------------------- right

func _build_right() -> void:
	var v := TourneyUI.panel(_root, Rect2(1180, 20, 400, 300), "Connection")
	TourneyUI.label(v, "Latency   —  (offline)", BWStyle.F_BODY)
	TourneyUI.label(v, "Mode      local, bots fill", BWStyle.F_BODY)
	TourneyUI.label(v, "Games in the pool:", BWStyle.F_BODY)
	for i in TourneyModules.infos():
		TourneyUI.label(v, "  · " + str(i.name), BWStyle.F_SMALL, TourneyUI.DIM)
	var n := TourneyUI.panel(_root, Rect2(1180, 340, 400, 260), "Notes")
	TourneyUI.para(n, "Double elimination, 4 to 8 players. Every match's game is rolled before anyone is placed. 5 coins a game; bet 5 to 25 on any match.")


# --------------------------------------------------------------- creator

func _build_creator() -> void:
	var v := TourneyUI.panel(_root, Rect2(440, 20, 720, 580), "You")
	var r := TourneyUI.row(v, 20)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	r.add_child(left)
	_stage = TourneyUI.stage(left, state.unit_for(_me), Vector2(300, 300), false)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(form)
	TourneyUI.label(form, "Name", BWStyle.F_SMALL, TourneyUI.DIM)
	var name_e := TourneyUI.line_edit(form, str(_me.name), "Your name")
	name_e.max_length = 14
	name_e.text_changed.connect(func(t): _me.name = t if t != "" else "You"; _save(); _refresh_players())
	TourneyUI.label(form, "Title", BWStyle.F_SMALL, TourneyUI.DIM)
	TourneyUI.option(form, TourneyState.TITLES, TourneyState.TITLES.find(str(_me.title)),
		func(i): _me.title = TourneyState.TITLES[i]; _save(); _refresh_players())
	TourneyUI.label(form, "Game experience", BWStyle.F_SMALL, TourneyUI.DIM)
	var exps := ["new", "some", "lots"]
	TourneyUI.option(form, ["New to these games", "Some experience", "Lots of experience"], exps.find(str(_me.exp)),
		func(i): _me.exp = exps[i]; _save())
	TourneyUI.label(form, "Hair", BWStyle.F_SMALL, TourneyUI.DIM)
	var styles := Array(BWHair.styles())
	TourneyUI.option(form, styles.map(func(s): return str(s).capitalize()), styles.find(str(_me.hair_style)),
		func(i): _me.hair_style = styles[i]; _save(); _restage())
	TourneyUI.label(form, "Hair colour", BWStyle.F_SMALL, TourneyUI.DIM)
	_swatches = TourneyUI.row(form, 6)
	_refresh_swatches()


func _refresh_swatches() -> void:
	for c in _swatches.get_children():
		c.queue_free()
	for hx in TourneyState.HAIR_COLOURS:
		TourneyUI.swatch(_swatches, hx, hx == str(_me.hair_hex), func():
			_me.hair_hex = hx
			_save()
			_refresh_swatches()
			_restage())


func _restage() -> void:
	var cont: Control = _stage.container
	var parent := cont.get_parent()
	var idx := cont.get_index()
	cont.queue_free()
	_stage = TourneyUI.stage(parent, state.unit_for(_me), Vector2(300, 300), false)
	parent.move_child(_stage.container, idx)
	_refresh_players()


func _save() -> void:
	TourneyState.save_profile(_me)


# ---------------------------------------------------------------- bottom

func _build_bottom() -> void:
	var v := TourneyUI.panel(_root, Rect2(20, 620, 1560, 260), "Testing modules")
	TourneyUI.para(v, "Set your keybinds and sensitivity before the games start. Enter a range any time you're ready.")
	var r := TourneyUI.row(v, 16)
	TourneyUI.button(r, "MOBA range  (QWER, flash, click to move)", func(): open_range.emit("moba"))
	TourneyUI.button(r, "Shooter range  (WASD, aim, sensitivity)", func(): open_range.emit("shooter"))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var r2 := TourneyUI.row(v)
	_start_btn = TourneyUI.button(r2, "Start", func(): start.emit())
	_start_btn.add_theme_font_size_override("font_size", BWStyle.F_SUB)
	_refresh_players()
