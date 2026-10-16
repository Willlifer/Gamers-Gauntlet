class_name FpsBinds
extends RefCounted
## The shooter's keys (G51): what the lobby's Shooter range held, moved into
## the FPS buy phase (FpsLoadoutMenu's options). Physical keycodes, so a
## layout change doesn't move them; saved in user://tourney.cfg under
## [fps_binds] beside the profile and the MOBA binds. FpsPlayer reads them
## every press.

const ORDER := ["forward", "back", "left", "right", "jump", "crouch", "reload", "primary", "sidearm"]
const LABEL := { "forward": "Move forward", "back": "Move back", "left": "Strafe left", "right": "Strafe right",
	"jump": "Jump / stand up", "crouch": "Crouch (tap) / prone (hold)", "reload": "Reload",
	"primary": "Primary", "sidearm": "Sidearm" }
const DEFAULTS := { "forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE,
	"crouch": KEY_SHIFT, "reload": KEY_R, "primary": KEY_1, "sidearm": KEY_2 }

static var _keys := {}
static var _loaded := false
static var defaults_only := false           ## tools: ignore the saved file


static func key(action: String) -> int:
	_ensure()
	return int(_keys.get(action, DEFAULTS[action]))


static func pressed(action: String) -> bool:
	return Input.is_physical_key_pressed(key(action) as Key)


## Bind `action` to `code`; another action on that key is moved off it
## (to nothing) and returned, so the menu can say so.
static func set_key(action: String, code: int) -> String:
	_ensure()
	var bumped := ""
	for a in ORDER:
		if a != action and key(a) == code:
			_keys[a] = 0
			bumped = a
	_keys[action] = code
	save()
	return bumped


static func reset() -> void:
	_keys = DEFAULTS.duplicate()
	save()


static func name_of(code: int) -> String:
	if code == 0:
		return "-"
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code as Key))


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_keys = DEFAULTS.duplicate()
	if defaults_only:
		return
	var cf := ConfigFile.new()
	if cf.load(TourneyState.CFG) == OK:
		for a in ORDER:
			_keys[a] = int(cf.get_value("fps_binds", a, DEFAULTS[a]))


static func save() -> void:
	if defaults_only:
		return
	var cf := ConfigFile.new()
	cf.load(TourneyState.CFG)
	for a in ORDER:
		cf.set_value("fps_binds", a, int(_keys.get(a, DEFAULTS[a])))
	cf.save(TourneyState.CFG)
