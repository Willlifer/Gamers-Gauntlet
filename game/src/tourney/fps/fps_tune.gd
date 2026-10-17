class_name FpsTune
extends RefCounted
## The FPS prototype's feel numbers in one place (the MobaTune pattern):
## movement, stances, aim, the reticle, the viewmodel's motion and the bot.
## Changes live in user://fps_tune.cfg; F1 in the game opens FpsTunePanel.
## Distances are metres on the 2.2 m Black | White body (real x1.25).

const PATH := "user://fps_tune.cfg"
## G51 (the author's 10-16 notes): a saved cfg older than this drops the keys
## whose meaning moved, so the new defaults reach players who had saved them:
## run_speed (the floaty max is the campus's own now), move_spread (the scale
## grew), the reticle and sway keys (re-baked).
const VERSION := 2
const MIGRATE := { 2: ["run_speed", "move_spread", "cross_gap", "sway"] }

## key -> [label, default, min, max, step, section]
const ENTRIES := {
	"run_speed": ["Run speed (m/s)", 6.6, 2.0, 12.0, 0.1, "Move"],
	"campus_speed": ["Campus paintball run speed (m/s; floaty, G51)", 12.0, 2.0, 16.0, 0.1, "Move"],
	"crouch_speed": ["Crouch speed (m/s)", 2.9, 0.5, 6.0, 0.1, "Move"],
	"prone_speed": ["Prone crawl speed (m/s)", 1.1, 0.2, 3.0, 0.05, "Move"],
	"ads_move": ["Move speed while aiming (x)", 0.55, 0.1, 1.0, 0.05, "Move"],
	"accel": ["Acceleration (m/s²)", 42.0, 5.0, 120.0, 1.0, "Move"],
	"jump": ["Jump speed (m/s)", 5.6, 0.0, 10.0, 0.1, "Move"],
	"prone_hold": ["Hold Shift this long to go prone (s)", 0.32, 0.1, 1.0, 0.01, "Move"],
	"mouse_sens": ["Mouse sensitivity", 2.2, 0.3, 8.0, 0.05, "Aim"],
	"ads_sens": ["Sensitivity while aiming (x)", 0.7, 0.1, 1.5, 0.05, "Aim"],
	"ads_time": ["Time to aim in (s)", 0.2, 0.05, 0.6, 0.01, "Aim"],
	"scope_zoom": ["Scope zoom (x)", 4.0, 1.5, 8.0, 0.1, "Aim"],
	"fov": ["Field of view (vertical deg)", 74.0, 50.0, 100.0, 1.0, "Aim"],
	"vm_fov": ["Weapon view FOV (deg)", 54.0, 35.0, 80.0, 1.0, "Aim"],
	"cross_gap": ["Reticle gap at rest (px)", 0.0, 0.0, 30.0, 0.5, "Reticle"],
	"rest_spread": ["Hip inaccuracy standing still (x the gun's)", 0.45, 0.0, 1.5, 0.05, "Reticle"],
	"move_spread": ["Inaccuracy when running (x; the reticle opens with it)", 4.5, 0.0, 8.0, 0.05, "Reticle"],
	"cross_snap": ["Reticle snap speed", 22.0, 2.0, 60.0, 1.0, "Reticle"],
	"cross_len": ["Reticle line length (px)", 9.0, 2.0, 20.0, 0.5, "Reticle"],
	"bob": ["Weapon bob (x)", 1.0, 0.0, 3.0, 0.05, "Weapon"],
	"sway": ["Weapon sway (x)", 2.3, 0.0, 4.0, 0.05, "Weapon"],
	"sway_side": ["Sideways sway (x; doubled scoped)", 1.0, 0.0, 3.0, 0.05, "Weapon"],
	"recoil": ["Recoil kick (x)", 3.0, 0.0, 6.0, 0.05, "Weapon"],
	"bullet_speed": ["Bullet speed (x the slingshot ball)", 5.0, 1.0, 20.0, 0.5, "Weapon"],
	"bullet_trail": ["Bullet trail length (m)", 30.0, 0.0, 30.0, 0.5, "Weapon"],
	"trail_fade": ["Trail fades in over this far from the barrel (m)", 1.1, 0.0, 4.0, 0.05, "Weapon"],
	"bot_reaction": ["Bot reaction time (s)", 0.6, 0.1, 2.0, 0.05, "Bot"],
	"bot_accuracy": ["Bot accuracy (0-1)", 0.5, 0.0, 1.0, 0.05, "Bot"],
	"bot_speed": ["Bot run speed (m/s)", 4.6, 1.0, 10.0, 0.1, "Bot"],
	"bot_push": ["Bot pushes toward you (0 camps, 1 hunts; G62)", 0.6, 0.0, 1.0, 0.05, "Bot"],
	"bot_peek": ["Bot peek time out of cover (s)", 1.4, 0.3, 4.0, 0.1, "Bot"],
	"bot_retreat_hp": ["Bot falls back to cover under this HP", 45.0, 0.0, 100.0, 5.0, "Bot"],
	"kills_to_win": ["Kills to win", 5.0, 1.0, 20.0, 1.0, "Match"],
	# Extraction (ExtractWorld)
	"extract_time": ["Raid clock (s)", 300.0, 60.0, 900.0, 10.0, "Extract"],
	"extract_reveal": ["Extract revealed with this long left (s)", 150.0, 10.0, 600.0, 10.0, "Extract"],
	"guard_bark_gap": ["Guard bark gap (s)", 3.0, 0.5, 10.0, 0.1, "Extract"],
	"guard_hear_range": ["Guard bark heard to (m)", 40.0, 5.0, 150.0, 1.0, "Extract"],
	"guard_reaction_x": ["Guard reaction (x bot_reaction)", 3.0, 0.5, 8.0, 0.1, "Extract"],
	"guard_accuracy_x": ["Guard accuracy (x bot_accuracy)", 0.5, 0.0, 1.5, 0.05, "Extract"],
	"armour_cut": ["Armour damage cut (0-1)", 0.35, 0.0, 0.9, 0.05, "Extract"],
	"medkit_heal": ["Medkit heal (HP over 4 s)", 60.0, 10.0, 100.0, 5.0, "Extract"],
	"chest_range": ["Interact reach (m)", 2.5, 1.0, 5.0, 0.1, "Extract"],
	"mag_cap": ["Magazines carried per caliber (the pouch's cap)", 3.0, 1.0, 9.0, 1.0, "Extract"],
}

static var _values := {}
static var _presets := {}                   ## G51b: gun id -> recoil preset name ("" = baked)
static var _scales := {}                    ## gun id -> its recoil scale (x)
static var _optics := {}                    ## G51c: gun id -> its sight (FpsWeapons.OPTIC_ORDER)
static var _loaded := false
static var _defaults_only := false


static func use_defaults() -> void:
	_defaults_only = true
	_loaded = true
	_values = {}
	_presets = {}
	_scales = {}
	_optics = {}


static func value(key: String) -> float:
	_ensure()
	return float(_values.get(key, ENTRIES[key][1]))


static func set_value(key: String, v: float) -> void:
	_ensure()
	var e: Array = ENTRIES[key]
	_values[key] = clampf(v, float(e[2]), float(e[3]))
	save()


static func reset() -> void:
	_values = {}
	_presets = {}
	_scales = {}
	_optics = {}
	save()


## G51b: the gun's recoil profile now: its preset's (or its own baked)
## numbers, the felt ones (recoil, kick, punch, side) times its scale.
static func recoil(id: String) -> Dictionary:
	_ensure()
	var name := str(_presets.get(id, ""))
	var src: String = FpsWeapons.RECOIL_PRESETS.get(name, id)
	var out := FpsWeapons.baked_recoil(src)
	var sc := float(_scales.get(id, 1.0))
	for k in ["recoil", "kick", "punch", "side"]:
		out[k] = float(out[k]) * sc
	return out


## G51c: the sight on `id` (one of its SPECS optics; "" for a gun without).
static func optic(id: String) -> String:
	_ensure()
	var o: Dictionary = FpsWeapons.spec(id).get("optics", {})
	if o.is_empty():
		return ""
	var k := str(_optics.get(id, o.default))
	return k if o.has(k) else str(o.default)


static func set_optic(id: String, k: String) -> void:
	_ensure()
	_optics[id] = k
	save()


static func recoil_preset(id: String) -> String:
	_ensure()
	return str(_presets.get(id, ""))


static func set_recoil_preset(id: String, name: String) -> void:
	_ensure()
	if name == "" or not FpsWeapons.RECOIL_PRESETS.has(name):
		_presets.erase(id)
	else:
		_presets[id] = name
	save()


static func recoil_scale(id: String) -> float:
	_ensure()
	return float(_scales.get(id, 1.0))


static func set_recoil_scale(id: String, v: float) -> void:
	_ensure()
	_scales[id] = clampf(v, 0.0, 3.0)
	save()


static func changed_keys() -> PackedStringArray:
	_ensure()
	var out := PackedStringArray()
	for k in _values:
		if not is_equal_approx(float(_values[k]), float(ENTRIES[k][1])):
			out.append(k)
	return out


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var drop := dropped_keys(int(cf.get_value("meta", "version", 1)))
	for k in ENTRIES:
		if cf.has_section_key("fps", k) and not k in drop:
			var e: Array = ENTRIES[k]
			_values[k] = clampf(float(cf.get_value("fps", k)), float(e[2]), float(e[3]))
	for id in FpsWeapons.SPECS:
		if cf.has_section_key("recoil_preset", id):
			_presets[id] = str(cf.get_value("recoil_preset", id))
		if cf.has_section_key("optic", id):
			_optics[id] = str(cf.get_value("optic", id))
		if cf.has_section_key("recoil_scale", id):
			_scales[id] = clampf(float(cf.get_value("recoil_scale", id)), 0.0, 3.0)


## The keys a cfg saved at `ver` loses on load (G51 migration).
static func dropped_keys(ver: int) -> Array:
	var drop: Array = []
	for v: int in MIGRATE:
		if ver < v:
			drop.append_array(MIGRATE[v])
	return drop


static func save() -> void:
	if _defaults_only:
		return
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", VERSION)
	for k in ENTRIES:
		cf.set_value("fps", k, snappedf(value(k), 0.001))
	for id in _presets:
		cf.set_value("recoil_preset", id, _presets[id])
	for id in _scales:
		cf.set_value("recoil_scale", id, snappedf(float(_scales[id]), 0.001))
	for id in _optics:
		cf.set_value("optic", id, _optics[id])
	cf.save(PATH)
