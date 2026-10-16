extends PanelContainer
## The MOBA options, on the champion select (G54: the MOBA range left the
## lobby, its options moved here): the keybinds from user://tourney.cfg
## (click a bind, press a key), the two pit pings, and the cast mode.
## Preloaded, not a global class: `const MobaOptions := preload(...)`.
##
## Cast modes (author 10-16), for Q W E R (flash and the second summoner
## always cast at once):
##   quick   - pressing the key casts at the cursor
##   slow    - the first press shows the range and the shape, a second press
##             (or a left click) casts, a right click or Esc cancels
##   release - holding the key shows them, letting go casts

const CFG := TourneyState.CFG
const CAST_MODES := ["quick", "slow", "release"]
const CAST_NAMES := { "quick": "Quick cast", "slow": "Slow cast", "release": "Release cast" }
const CAST_HELP := {
	"quick": "Pressing an ability key casts it at the cursor.",
	"slow": "Press once to see the range and the shape, press again (or left-click) to cast. Right-click or Esc cancels.",
	"release": "Hold the key to see the range and the shape, let go to cast.",
}
## Binds the shared store doesn't list (TourneyState.DEFAULT_BINDS): the pit's pings.
const EXTRA_BINDS := { "ping_go": KEY_V, "ping_hold": KEY_C }
const LIST := [["q", "Q spell"], ["w", "W spell"], ["e", "E spell"], ["r", "Ultimate"], ["flash", "Flash"],
	["spell2", "Ignite / smite"], ["stop", "Stop"], ["ping_go", "Ping: go in (pit)"], ["ping_hold", "Ping: hold here (pit)"]]

signal closed

var _binds := {}
var _waiting := ""
var _list: VBoxContainer
var _status: Label
var _mode_row: HBoxContainer
var _help: Label


static func load_cast_mode() -> String:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return "quick"
	var m := str(cf.get_value("moba", "cast_mode", "quick"))
	return m if m in CAST_MODES else "quick"


static func save_cast_mode(m: String) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("moba", "cast_mode", m)
	cf.save(CFG)


## The shared binds plus the MOBA-only ones, from the store.
static func load_binds() -> Dictionary:
	return with_extras(TourneyState.load_binds(), true)


## `b` with the MOBA-only binds filled in (from the store when `stored`, else defaults).
static func with_extras(b: Dictionary, stored: bool = false) -> Dictionary:
	var out := b.duplicate()
	var cf := ConfigFile.new()
	var ok := stored and cf.load(CFG) == OK
	for k in EXTRA_BINDS:
		if not out.has(k):
			out[k] = int(cf.get_value("binds", k, EXTRA_BINDS[k])) if ok else int(EXTRA_BINDS[k])
	return out


func _ready() -> void:
	_binds = load_binds()
	add_theme_stylebox_override("panel", TourneyUI.panel_box(TourneyUI.GOLD))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	TourneyUI.display(v, "OPTIONS", 20, Color.WHITE)
	TourneyUI.label(v, "Cast mode", BWStyle.F_SMALL, TourneyUI.DIM)
	_mode_row = TourneyUI.row(v, 6)
	_help = TourneyUI.para(v, "", 14)
	_help.custom_minimum_size = Vector2(520, 44)
	_modes()
	TourneyUI.label(v, "Keybinds: click one, then press the key you want.", BWStyle.F_SMALL, TourneyUI.DIM)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	v.add_child(_list)
	_refresh()
	_status = TourneyUI.label(v, "", 14, TourneyUI.GOLD)
	var r := TourneyUI.row(v)
	TourneyUI.button(r, "Reset binds", func():
		_binds = with_extras(TourneyState.DEFAULT_BINDS)
		_save()
		_refresh())
	TourneyUI.button(r, "Done", func(): closed.emit())


func _modes() -> void:
	for c in _mode_row.get_children():
		c.queue_free()
	var cur := load_cast_mode()
	for m in CAST_MODES:
		var b := TourneyUI.button(_mode_row, str(CAST_NAMES[m]), func():
			save_cast_mode(m)
			_modes())
		b.toggle_mode = true
		b.button_pressed = m == cur
		b.add_theme_font_size_override("font_size", 16)
	_help.text = str(CAST_HELP[cur])


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for pair in LIST:
		var id: String = pair[0]
		var r := TourneyUI.row(_list)
		var l := TourneyUI.label(r, pair[1], 16)
		l.custom_minimum_size.x = 300
		var b := TourneyUI.button(r, "..." if _waiting == id else TourneyUI.key_name(int(_binds.get(id, 0))), func():
			_waiting = id
			_refresh())
		b.custom_minimum_size = Vector2(150, 0)
		b.add_theme_font_size_override("font_size", 16)


func _save() -> void:
	TourneyState.save_binds(_binds)          # writes every key it is given, extras included


func _input(ev: InputEvent) -> void:
	if not visible or _waiting == "" or not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	get_viewport().set_input_as_handled()
	if ev.keycode == KEY_ESCAPE:
		_waiting = ""
		_refresh()
		return
	for k in _binds:
		if int(_binds[k]) == ev.keycode and k != _waiting:
			_status.text = "%s was on that key; it's unbound now." % str(k).capitalize()
			_binds[k] = 0
	_binds[_waiting] = ev.keycode
	_waiting = ""
	_save()
	_refresh()
