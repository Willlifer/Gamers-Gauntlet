class_name TourneySettings
extends Control
## One settings panel for every game (G56), in the TourneyUI look: a gold-
## topped ink card over a dimmed screen, a tab per game kind (MOBA, Shooter,
## Raid, OSRS, General). The calling screen opens it on its own tab; the
## others stay a click away. It edits the stores the games already read,
## under their existing keys, so a change lands in the running match:
##   MOBA     cast mode ([moba] cast_mode) and keys ([binds], MobaOptions)
##   Shooter  mouse / aim sensitivity, field of view (FpsTune, fps_tune.cfg)
##            and keys ([fps_binds], FpsBinds)
##   Raid     mouse look (MmoTune mouse_sens), the card every raid
##            (MmoTune intro_always); the WoW keys, read-only (fixed in MmoView)
##   OSRS     the card every run (OsrsTune card_always); the keys, read-only
##   General  master / music / sound volume ([audio] in tourney.cfg, applied
##            to BWAudio's buses), and "show the first-time cards again"
##            (clears [seen])
##
##   var s := TourneySettings.open(parent_control, "shooter")
##   s.closed.connect(...)        # Done or Esc; the host frees it
## Hosts: the champion select (aram_module), the FPS buy wheel
## (FpsLoadoutMenu, O), the raid class pick (mmo_module), the OSRS weapon pick
## (osrs_module) and the lobby's gear (LobbyScreen). A pick clock waits while
## it's open (each host checks its own handle).

signal closed

const MobaOptions := preload("res://src/tourney/moba/moba_options.gd")
const CFG := TourneyState.CFG
const TABS := ["moba", "shooter", "raid", "osrs", "general"]
const TAB_NAMES := { "moba": "MOBA", "shooter": "Shooter", "raid": "Raid", "osrs": "OSRS", "general": "General" }
const TAB_GAMES := { "moba": "ARAM duel and Objective take", "shooter": "Rooftop, Mid and Campus paintball",
	"raid": "Raid night and Planet of Tanks", "osrs": "Warden's Trial", "general": "Every game" }
const FPS_SLIDERS := ["mouse_sens", "ads_sens", "fov"]
## [key in [audio], label, the BWAudio buses it sets]
const VOLUMES := [["master", "Master volume", ["Master"]], ["music", "Music", ["Music"]],
	["sfx", "Sound effects and voices", ["SFX", "Voice", "UI"]]]
const SEEN_NAMES := { "mmo_raid": "Raid night", "mmo_tanks": "Planet of Tanks", "osrs_raid": "Warden's Trial" }
## The raid's keys (MmoView._unhandled_input, fixed: WoW's defaults).
const RAID_KEYS := [["1 - 8", "Action bar"], ["Shift + 1 - 8", "Consumables"], ["W  /  S", "Run forward / back up"],
	["A  /  D", "Turn (hold the right mouse button: strafe)"], ["Q  /  E", "Strafe left / right"], ["Space", "Jump"],
	["Num Lock", "Autorun"], ["Tab", "Target the boss"], ["F2", "Target yourself"], ["F3 - F7", "Target your party"],
	["Esc", "Stop casting, then clear the target"], ["Right mouse drag", "Steer"], ["Left mouse drag", "Look around"],
	["Mouse wheel", "Zoom"], ["F1", "Tune panel (playtests)"]]
## Warden's Trial's keys (OsrsView, fixed: OSRS's defaults).
const OSRS_KEYS := [["Left click a square", "Walk / run there"], ["Left click the Warden", "Attack it"],
	["Left click a skull", "Attack it (wield the dagger first)"], ["Left click an item", "Wield it, eat or drink"],
	["1  /  2  /  3", "Protect from Magic / Missiles / Melee"], ["Arrows, A/D, W/S", "Turn and tilt the camera"],
	["Middle mouse drag", "Turn the camera"], ["Mouse wheel", "Zoom"], ["F1", "Tune panel (playtests)"]]
const W := 1060.0
const H := 770.0
const KEY_BOX_W := 190.0

var tab := "general"
var _waiting := ""                          # "moba:<id>" or "fps:<id>": a bind waiting for its key
var _tab_b := {}                            # tab -> its Button
var _body: VBoxContainer
var _status: Label
var _games: Label

static var _gear: Texture2D


## Open the panel over `parent` (a full-screen Control) on `first_tab`.
static func open(parent: Control, first_tab: String) -> TourneySettings:
	var s := TourneySettings.new()
	s.tab = first_tab if first_tab in TABS else "general"
	parent.add_child(s)
	return s


## Is a bind waiting for its key (so Esc and the host's keys belong to it)?
func capturing() -> bool:
	return _waiting != ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = BWStyle.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	var box := TourneyUI.panel_box(TourneyUI.GOLD)
	box.bg_color = Color(TourneyUI.PANEL, 0.97)          # opaque enough to read over a busy screen
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size = Vector2(W, H)
	centre.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var head := TourneyUI.row(v, 14)
	var ic := TextureRect.new()
	ic.texture = gear_icon()
	ic.custom_minimum_size = Vector2(30, 30)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = TourneyUI.GOLD
	head.add_child(ic)
	TourneyUI.display(head, "SETTINGS", 28)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_games = TourneyUI.label(head, "", BWStyle.F_SMALL, TourneyUI.DIM)
	_games.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tabs := TourneyUI.row(v, 6)
	var group := ButtonGroup.new()
	for t: String in TABS:
		var b := TourneyUI.button(tabs, str(TAB_NAMES[t]), func() -> void: select(t))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 42)
		b.add_theme_color_override("font_pressed_color", TourneyUI.GOLD)
		b.add_theme_color_override("font_hover_pressed_color", TourneyUI.GOLD)
		_tab_b[t] = b
	var rule := ColorRect.new()
	rule.color = TourneyUI.PANEL_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	var foot := TourneyUI.row(v, 12)
	_status = TourneyUI.label(foot, "", BWStyle.F_SMALL, TourneyUI.GOLD)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var done := TourneyUI.button(foot, "Done  [Esc]", func() -> void: closed.emit())
	done.focus_mode = Control.FOCUS_NONE
	done.custom_minimum_size = Vector2(170, 42)
	select(tab)


## Show a tab (any of TABS).
func select(t: String) -> void:
	if not t in TABS:
		return
	tab = t
	_waiting = ""
	_status.text = ""
	for k: String in _tab_b:
		(_tab_b[k] as Button).set_pressed_no_signal(k == t)
	_games.text = str(TAB_GAMES[t])
	_build()


func _build() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match tab:
		"moba": _build_moba()
		"shooter": _build_shooter()
		"raid": _build_raid()
		"osrs": _build_osrs()
		_: _build_general()


# ---------------------------------------------------------------- the tabs

func _build_moba() -> void:
	_section("Cast mode  (Q W E R; flash and the second summoner always cast at once)")
	var cur := MobaOptions.load_cast_mode()
	var r := TourneyUI.row(_body, 6)
	for m: String in MobaOptions.CAST_MODES:
		var b := TourneyUI.button(r, str(MobaOptions.CAST_NAMES[m]), func() -> void:
			MobaOptions.save_cast_mode(m)
			_build())
		b.toggle_mode = true
		b.button_pressed = m == cur
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_pressed_color", TourneyUI.GOLD)
	_note(str(MobaOptions.CAST_HELP[cur]))
	_section("Keys")
	_note("Click one, then press the key you want (Esc cancels). Left-click moves, right-click attacks.")
	var binds := MobaOptions.load_binds()
	for pair: Array in MobaOptions.LIST:
		var id: String = pair[0]
		_key_row(str(pair[1]), TourneyUI.key_name(int(binds.get(id, 0))), "moba:" + id)
	var rr := TourneyUI.row(_body)
	_small_button(rr, "Reset MOBA keys", func() -> void:
		TourneyState.save_binds(MobaOptions.with_extras(TourneyState.DEFAULT_BINDS))
		_status.text = "MOBA keys back to the defaults."
		_build())


func _build_shooter() -> void:
	_section("Aim")
	for key: String in FPS_SLIDERS:
		var e: Array = FpsTune.ENTRIES[key]
		var fmt := "%.0f" if key == "fov" else "%.2f"
		_slider(str(e[0]), float(e[2]), float(e[3]), float(e[4]), FpsTune.value(key), fmt, func(x: float) -> void: FpsTune.set_value(key, x))
	_section("Keys")
	_note("Click one, then press the key you want (Esc cancels). Left mouse fires, right mouse aims.")
	for a: String in FpsBinds.ORDER:
		_key_row(str(FpsBinds.LABEL[a]), FpsBinds.name_of(FpsBinds.key(a)), "fps:" + a)
	var rr := TourneyUI.row(_body)
	_small_button(rr, "Reset shooter keys", func() -> void:
		FpsBinds.reset()
		_status.text = "Shooter keys back to the defaults."
		_build())


func _build_raid() -> void:
	_section("Camera")
	var e: Array = MmoTune.ENTRIES["mouse_sens"]
	_slider(str(e[0]), float(e[2]), float(e[3]), float(e[4]), MmoTune.value("mouse_sens"), "%.2f", func(x: float) -> void: MmoTune.set_value("mouse_sens", x))
	_section("First-time card")
	_toggle("Show the first-time card every raid", MmoTune.value("intro_always") > 0.5, func(on: bool) -> void:
		MmoTune.set_value("intro_always", 1.0 if on else 0.0))
	_section("Keys")
	_note("WoW's default keys. They're fixed for now, so this list is for reading.")
	for pair: Array in RAID_KEYS:
		_key_row(str(pair[1]), str(pair[0]), "")


func _build_osrs() -> void:
	_section("First-time card")
	_toggle("Show the first-time card every run", OsrsTune.value("card_always") > 0.5, func(on: bool) -> void:
		OsrsTune.set_value("card_always", 1.0 if on else 0.0))
	_section("Keys")
	_note("Old School RuneScape's controls. They're fixed for now, so this list is for reading.")
	for pair: Array in OSRS_KEYS:
		_key_row(str(pair[1]), str(pair[0]), "")


func _build_general() -> void:
	_section("Sound")
	for vol: Array in VOLUMES:
		var k: String = vol[0]
		_slider(str(vol[1]), 0.0, 100.0, 1.0, volume(k) * 100.0, "%.0f%%", func(x: float) -> void: set_volume(k, x / 100.0))
	_section("First-time cards")
	var seen := seen_cards()
	_note(("Seen so far: %s." % ", ".join(seen.map(func(g: String) -> String: return str(SEEN_NAMES.get(g, g))))) if not seen.is_empty()
		else "None seen yet: each game shows its card the first time you play it.")
	var rr := TourneyUI.row(_body)
	_small_button(rr, "Show first-time cards again", func() -> void:
		reset_cards()
		_status.text = "Every game shows its first-time card again, once."
		_build())


# ---------------------------------------------------------------- rows

func _section(text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_body.add_child(gap)
	TourneyUI.label(_body, text, BWStyle.F_SMALL, Color(TourneyUI.GOLD, 0.95))


func _note(text: String) -> void:
	var l := TourneyUI.para(_body, text, 15)
	l.custom_minimum_size.x = W - 60.0


func _name_label(r: Control, text: String) -> Label:
	var l := TourneyUI.label(r, text, 17)
	l.custom_minimum_size.x = 380
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _small_button(parent: Control, text: String, fn: Callable) -> Button:
	var b := TourneyUI.button(parent, text, fn)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	return b


## A bind: `wait_id` "moba:q" / "fps:jump" makes it a button that takes the
## next key; "" makes it read-only (the key in an ink box).
func _key_row(what: String, key_text: String, wait_id: String) -> void:
	var r := TourneyUI.row(_body)
	_name_label(r, what)
	if wait_id == "":
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06)
		sb.border_color = Color(1, 1, 1, 0.14)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		box.add_theme_stylebox_override("panel", sb)
		box.custom_minimum_size = Vector2(KEY_BOX_W + 70.0, 0)
		r.add_child(box)
		var l := TourneyUI.label(box, key_text, 16, Color(1, 1, 1, 0.85))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var b := TourneyUI.button(r, "..." if _waiting == wait_id else key_text, func() -> void:
		_waiting = wait_id
		_status.text = "Press the key for %s (Esc cancels)." % what
		_build())
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(KEY_BOX_W, 0)
	b.add_theme_font_size_override("font_size", 16)
	if _waiting == wait_id:
		b.add_theme_color_override("font_color", TourneyUI.GOLD)


func _slider(what: String, lo: float, hi: float, step: float, val: float, fmt: String, fn: Callable) -> void:
	var r := TourneyUI.row(_body)
	_name_label(r, what)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.custom_minimum_size = Vector2(340, 26)
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(sl)
	var vl := TourneyUI.label(r, fmt % val, 17, Color("#a6d86a"))
	vl.custom_minimum_size.x = 80
	sl.value_changed.connect(func(x: float) -> void:
		fn.call(x)
		vl.text = fmt % x)


func _toggle(what: String, on: bool, fn: Callable) -> void:
	var r := TourneyUI.row(_body)
	_name_label(r, what)
	var c := CheckButton.new()
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(x: bool) -> void: fn.call(x))
	r.add_child(c)


# ---------------------------------------------------------------- input

func _input(ev: InputEvent) -> void:
	if not is_visible_in_tree() or not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var k := ev as InputEventKey
	if _waiting == "":
		if k.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
		return
	get_viewport().set_input_as_handled()
	var wid := _waiting
	_waiting = ""
	if k.physical_keycode == KEY_ESCAPE:
		_status.text = ""
		_build()
		return
	var parts := wid.split(":")
	if parts[0] == "moba":
		_status.text = _bind_moba(parts[1], k.keycode)
	else:
		var bumped := FpsBinds.set_key(parts[1], k.physical_keycode)
		_status.text = ("%s was on %s; it's unbound now." % [FpsBinds.LABEL[bumped], FpsBinds.name_of(k.physical_keycode)]) if bumped != "" else ""
	_build()


## Put the MOBA bind `id` on `code` (logical keycode, as MobaView reads it);
## another bind on that key loses it. Returns the note for the status line.
func _bind_moba(id: String, code: int) -> String:
	var binds := MobaOptions.load_binds()
	var note := ""
	for other in binds:
		if int(binds[other]) == code and other != id:
			binds[other] = 0
			note = "%s was on that key; it's unbound now." % _moba_label(str(other))
	binds[id] = code
	TourneyState.save_binds(binds)           # writes every key it is given, extras included
	return note


func _moba_label(id: String) -> String:
	for pair: Array in MobaOptions.LIST:
		if pair[0] == id:
			return str(pair[1])
	return id.capitalize()


# ---------------------------------------------------------------- stores

## A volume, 0..1, from [audio] in tourney.cfg (1 = the designed mix).
static func volume(key: String) -> float:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return 1.0
	return clampf(float(cf.get_value("audio", key, 1.0)), 0.0, 1.0)


static func set_volume(key: String, v: float) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("audio", key, snappedf(clampf(v, 0.0, 1.0), 0.01))
	cf.save(CFG)
	apply_audio()


## Set the buses from the saved volumes, in memory (BWSettings runs isolated
## in the tournament, so Black | White's own settings files stay untouched).
## The tournament and module_proto call it at boot, after BWSettings.apply_all.
static func apply_audio() -> void:
	BWAudio._load()
	for vol: Array in VOLUMES:
		var v := volume(str(vol[0]))
		for bus: String in vol[2]:
			BWAudio._volumes[bus] = v
			BWAudio._apply(bus)


## Which first-time cards this profile has seen ([seen] in tourney.cfg).
static func seen_cards() -> Array:
	var out := []
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK or not cf.has_section("seen"):
		return out
	for k in cf.get_section_keys("seen"):
		if bool(cf.get_value("seen", k, false)):
			out.append(str(k))
	return out


## Show every first-time card again (once each): clears [seen].
static func reset_cards() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK or not cf.has_section("seen"):
		return
	cf.erase_section("seen")
	cf.save(CFG)


# ---------------------------------------------------------------- the gear

## A small white gear (24 px, drawn once): tint it with modulate.
static func gear_icon() -> Texture2D:
	if _gear:
		return _gear
	var n := 24
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var a := 0.0
			for sy in 4:
				for sx in 4:
					var p := Vector2(x + (sx + 0.5) / 4.0, y + (sy + 0.5) / 4.0) - c
					var r := p.length()
					var tooth := fposmod(p.angle() * 8.0 / TAU + 0.25, 1.0) < 0.5
					if r >= 3.8 and r <= (11.2 if tooth else 8.4):
						a += 1.0 / 16.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_gear = ImageTexture.create_from_image(img)
	return _gear


## A TourneyUI button with the gear on it ("" text: the gear alone).
static func gear_button(parent: Control, text: String, fn: Callable) -> Button:
	var b := TourneyUI.button(parent, text, fn)
	b.icon = gear_icon()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Settings: keys, sensitivity, sound, first-time cards"
	return b
