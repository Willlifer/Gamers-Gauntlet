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
	var r := TourneyUI.row(v, 16)
	_stage = TourneyUI.stage(r, state.unit_for(_me), Vector2(250, 420), true)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 6)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(form)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	form.add_child(grid)
	var name_e := LineEdit.new()
	name_e.text = str(_me.name)
	name_e.max_length = 14
	name_e.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	name_e.text_changed.connect(func(t): _me.name = t if t != "" else "You"; _save(); _refresh_players())
	_field(grid, "Name", name_e)
	_pick(grid, "Title", TourneyState.TITLES, "title", false)
	_pick(grid, "Experience", ["new", "some", "lots"], "exp", false, ["New", "Some", "Lots"])
	var styles := Array(BWHair.styles())
	_pick(grid, "Hair", styles, "hair_style", true)
	var weapons := TourneyState.weapon_models()
	_pick(grid, "Weapon", weapons, "weapon", true,
		weapons.map(func(w): return "%s  (%s)" % [str(w).capitalize(), str(BWWeaponView.meta_for(w).get("class", ""))]))
	_pick(grid, "Shade", TourneyState.SHADES, "shade", true)
	_pick(grid, "Top", Array(BWClothing.TOPS), "top", true)
	_pick(grid, "Bottom", Array(BWClothing.BOTTOMS), "bottom", true)
	for slot in ["head", "chest", "legs"]:
		var ids := TourneyState.armour_for(slot)
		_pick(grid, slot.capitalize() + " armour", ids, slot, true, ids.map(func(i): return "None" if i == "" else str(i).capitalize()))
	TourneyUI.label(form, "Hair colour", BWStyle.F_SMALL, TourneyUI.DIM)
	_swatches = TourneyUI.row(form, 5)
	_refresh_swatches()


func _field(grid: GridContainer, title: String, c: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(box)
	TourneyUI.label(box, title, 13, TourneyUI.DIM)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(c)


## A dropdown bound to a profile key; `restage` redresses the figure.
func _pick(grid: GridContainer, title: String, values: Array, key: String, restage: bool, labels: Array = []) -> void:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	o.fit_to_longest_item = false
	for i in values.size():
		o.add_item(str(labels[i]) if not labels.is_empty() else str(values[i]).capitalize())
	o.selected = maxi(0, values.find(_me.get(key, "")))
	o.item_selected.connect(func(i):
		_me[key] = values[i]
		_save()
		if restage:
			_restage()
		else:
			_refresh_players())
	_field(grid, title, o)


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
	_stage = TourneyUI.stage(parent, state.unit_for(_me), Vector2(250, 420), true)
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
