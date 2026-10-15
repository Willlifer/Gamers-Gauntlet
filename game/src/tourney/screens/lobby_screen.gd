class_name LobbyScreen
extends Node
## The lobby, after Smash Ultimate's main menu (G27): a grid of slanted
## tiles over the circling map. The big one starts the tournament; the two
## ranges sit beside it; Quick play opens any game at once against a bot
## (a playtest, nothing counts). The seated players run along the bottom,
## a ticker under them describes the tile under the mouse, and the
## character creator is a small card on the right (a quarter of the screen
## at most).

signal start
signal open_range(kind: String)
signal quick_play(module_id: String)

## Muted tints and the big faded tag per game (restrained: the streaks move, the colour stays quiet).
const LOOKS := {
	"bw_twins": ["#3b3656", "B|W"], "aram": ["#25415e", "ARAM"], "pit": ["#2b4a3c", "PIT"],
	"fps_roof": ["#57452f", "FPS"], "fps_mid": ["#5e4b2a", "MID"], "mmo_raid": ["#4c2f3d", "RAID"],
}
const CARD := Rect2(1200, 90, 380, 736)     ## the creator: 19% of 1600x900

var state: TourneyState
var _root: Control
var _players_row: HBoxContainer
var _stage: Dictionary
var _stage_box: Control
var _me: Dictionary
var _swatches: HBoxContainer
var _start_tile: TourneyTile
var _ticker: Label


func _ready() -> void:
	_me = state.me()
	_root = TourneyUI.root(self)
	TourneyUI.header(_root, "GAMERS GAUNTLET", "Join code  %s   ·   offline: bots fill the seats" % state.join_code)
	_build_tiles()
	_build_players()
	_build_creator()
	_build_ticker()
	_refresh_players()


# ----------------------------------------------------------------- tiles

func _build_tiles() -> void:
	_start_tile = TourneyTile.make(_root, Rect2(20, 92, 610, 300), "Tournament", "", Color("#6e2622"), "GO")
	_start_tile.title_size = 54
	_start_tile.blurb = "Double elimination for 4 to 8. Every match rolls a game; bet on every match. The champion takes the night."
	_start_tile.pressed.connect(_start)
	_hook(_start_tile)
	var mr := TourneyTile.make(_root, Rect2(650, 92, 520, 142), "MOBA range", "QWER, flash, click to move", Color("#2c3546"), "BINDS")
	mr.blurb = "Set your MOBA keybinds and practise on a dummy."
	mr.pressed.connect(func(): open_range.emit("moba"))
	_hook(mr)
	var sr := TourneyTile.make(_root, Rect2(650, 250, 520, 142), "Shooter range", "WASD, aim, sensitivity", Color("#2c3546"), "AIM")
	sr.blurb = "Set your shooter binds and mouse sensitivity."
	sr.pressed.connect(func(): open_range.emit("shooter"))
	_hook(sr)
	var ql := TourneyUI.display(_root, "QUICK PLAY", 22, Color(1, 1, 1, 0.9))
	ql.position = Vector2(26, 404)
	var hint := TourneyUI.label(_root, "straight into a game against a bot: a playtest, nothing counts  ·  F10 leaves a game", BWStyle.F_SMALL, TourneyUI.DIM)
	hint.position = Vector2(200, 409)
	var infos := TourneyModules.infos()
	for i in infos.size():
		var info: Dictionary = infos[i]
		var look: Array = LOOKS.get(str(info.id), ["#2c3546", ""])
		var col := i % 3
		var row := i / 3
		var t := TourneyTile.make(_root, Rect2(20 + col * 385, 442 + row * 140, 370, 126), str(info.name), "", Color(look[0]), str(look[1]))
		t.title_size = 22
		t.blurb = str(info.get("blurb", ""))
		var id := str(info.id)
		t.pressed.connect(func(): quick_play.emit(id))
		_hook(t)


func _hook(t: TourneyTile) -> void:
	t.hovered.connect(func(tile: TourneyTile): _ticker.text = tile.blurb)


func _start() -> void:
	_me.ready = true
	if state.all_ready():
		start.emit()
	else:
		_ticker.text = "Need %d players to start: add a bot below." % TourneyState.MIN_PLAYERS
	_refresh_players()


# --------------------------------------------------------------- players

func _build_players() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", TourneyUI.panel_box())
	p.position = Vector2(20, 728)
	p.size = Vector2(1150, 98)
	_root.add_child(p)
	var h := TourneyUI.row(p, 10)
	_players_row = HBoxContainer.new()
	_players_row.add_theme_constant_override("separation", 8)
	_players_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_players_row)
	var b := VBoxContainer.new()
	h.add_child(b)
	TourneyUI.button(b, "+ bot", func(): state.add_bot(); _refresh_players())
	TourneyUI.button(b, "− bot", func(): state.remove_bot(); _refresh_players())


func _refresh_players() -> void:
	for c in _players_row.get_children():
		c.queue_free()
	for p in state.players:
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06) if p.bot else Color(TourneyUI.ACCENT, 0.22)
		sb.border_color = Color(str(p.hair_hex))
		sb.border_width_left = 4
		sb.set_content_margin_all(6)
		sb.content_margin_left = 10
		chip.add_theme_stylebox_override("panel", sb)
		chip.custom_minimum_size = Vector2(122, 0)
		_players_row.add_child(chip)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		chip.add_child(v)
		var n := TourneyUI.label(v, str(p.name), BWStyle.F_SMALL)
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		TourneyUI.label(v, "%s%s" % [p.title, "  · bot" if p.bot else ""], 13, TourneyUI.DIM)
		TourneyUI.label(v, "● ready" if p.ready else "○ not ready", 13, Color("#4cc38a") if p.ready else TourneyUI.DIM)
	var left := TourneyState.MAX_PLAYERS - state.players.size()
	if left > 0:
		TourneyUI.label(_players_row, "%d / %d" % [state.players.size(), TourneyState.MAX_PLAYERS], BWStyle.F_SMALL, TourneyUI.DIM)
	if _start_tile:
		var n := state.players.size()
		_start_tile.set_sub("%d players  ·  double elimination  ·  bets" % n if n >= TourneyState.MIN_PLAYERS
			else "Need %d players: add a bot below" % TourneyState.MIN_PLAYERS)


# --------------------------------------------------------------- creator

func _build_creator() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", TourneyUI.panel_box(TourneyUI.ACCENT))
	p.position = CARD.position
	p.size = CARD.size
	_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	TourneyUI.display(v, "YOU", 20)
	var top := TourneyUI.row(v, 10)
	_stage_box = top
	_stage = TourneyUI.stage(top, state.unit_for(_me), Vector2(140, 236), true, Color(0, 0, 0, 0))
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 4)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(form)
	var name_e := LineEdit.new()
	name_e.text = str(_me.name)
	name_e.max_length = 14
	name_e.add_theme_font_size_override("font_size", BWStyle.F_SMALL)
	name_e.text_changed.connect(func(t): _me.name = t if t != "" else "You"; _save(); _refresh_players())
	_field(form, "Name", name_e)
	_pick(form, "Title", TourneyState.TITLES, "title", false)
	_pick(form, "Experience", ["new", "some", "lots"], "exp", false, ["New", "Some", "Lots"])
	_pick(form, "Hair", Array(BWHair.styles()), "hair_style", true)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	v.add_child(grid)
	var weapons := TourneyState.weapon_models()
	_pick(grid, "Weapon", weapons, "weapon", true, weapons.map(func(w): return str(w).capitalize()))
	_pick(grid, "Shade", TourneyState.SHADES, "shade", true)
	_pick(grid, "Top", Array(BWClothing.TOPS), "top", true)
	_pick(grid, "Bottom", Array(BWClothing.BOTTOMS), "bottom", true)
	for slot in ["head", "chest", "legs"]:
		var ids := TourneyState.armour_for(slot)
		_pick(grid, slot.capitalize() + " armour", ids, slot, true, ids.map(func(i): return "None" if i == "" else str(i).capitalize()))
	TourneyUI.label(v, "Hair colour", 13, TourneyUI.DIM)
	_swatches = TourneyUI.row(v, 4)
	_refresh_swatches()


func _field(parent: Control, title: String, c: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	TourneyUI.label(box, title, 12, TourneyUI.DIM)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(c)


## A dropdown bound to a profile key; `restage` redresses the figure.
func _pick(parent: Control, title: String, values: Array, key: String, restage: bool, labels: Array = []) -> void:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 14)
	o.fit_to_longest_item = false
	o.clip_text = true
	o.custom_minimum_size.x = 150
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
	_field(parent, title, o)


func _refresh_swatches() -> void:
	for c in _swatches.get_children():
		c.queue_free()
	for hx in TourneyState.HAIR_COLOURS:
		var b := TourneyUI.swatch(_swatches, hx, hx == str(_me.hair_hex), func():
			_me.hair_hex = hx
			_save()
			_refresh_swatches()
			_restage())
		b.custom_minimum_size = Vector2(28, 28)


func _restage() -> void:
	var cont: Control = _stage.container
	var idx := cont.get_index()
	cont.queue_free()
	_stage = TourneyUI.stage(_stage_box, state.unit_for(_me), Vector2(140, 236), true, Color(0, 0, 0, 0))
	_stage_box.move_child(_stage.container, idx)
	_refresh_players()


func _save() -> void:
	TourneyState.save_profile(_me)


# ---------------------------------------------------------------- ticker

func _build_ticker() -> void:
	var strip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(TourneyUI.INK, 0.9)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	strip.add_theme_stylebox_override("panel", sb)
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = 846
	strip.offset_bottom = 884
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(strip)
	var mark := TourneyUI.label(_root, "▶", BWStyle.F_SMALL, TourneyUI.ACCENT)
	mark.position = Vector2(24, 853)
	_ticker = TourneyUI.label(_root, "Pick a tile. Quick play drops you into any game against a bot.", BWStyle.F_SMALL, Color(1, 1, 1, 0.85))
	_ticker.position = Vector2(50, 853)
