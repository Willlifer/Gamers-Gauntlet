extends RefCounted
## The MOBA options' store (G54, G56): the keybinds from user://tourney.cfg
## ([binds], the shared ones plus the two pit pings) and the cast mode
## ([moba] cast_mode). The panel that edits them is TourneySettings' MOBA tab
## (G56: one settings panel for every game; opened from the champion select).
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
