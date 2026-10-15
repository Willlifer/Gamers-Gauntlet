class_name FpsTune
extends RefCounted
## The FPS prototype's feel numbers in one place (the MobaTune pattern):
## movement, stances, aim, the reticle, the viewmodel's motion and the bot.
## Changes live in user://fps_tune.cfg; F1 in the game opens FpsTunePanel.
## Distances are metres on the 2.2 m Black | White body (real x1.25).

const PATH := "user://fps_tune.cfg"

## key -> [label, default, min, max, step, section]
const ENTRIES := {
	"run_speed": ["Run speed (m/s)", 6.6, 2.0, 12.0, 0.1, "Move"],
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
	"cross_gap": ["Reticle gap at rest (px)", 5.0, 0.0, 30.0, 0.5, "Reticle"],
	"move_spread": ["Inaccuracy when running (x; the reticle opens with it)", 1.0, 0.0, 3.0, 0.05, "Reticle"],
	"cross_snap": ["Reticle snap speed", 22.0, 2.0, 60.0, 1.0, "Reticle"],
	"cross_len": ["Reticle line length (px)", 9.0, 2.0, 20.0, 0.5, "Reticle"],
	"bob": ["Weapon bob (x)", 1.0, 0.0, 3.0, 0.05, "Weapon"],
	"sway": ["Weapon sway (x)", 1.0, 0.0, 3.0, 0.05, "Weapon"],
	"recoil": ["Recoil kick (x)", 1.0, 0.0, 3.0, 0.05, "Weapon"],
	"bullet_speed": ["Bullet speed (x the slingshot ball)", 5.0, 1.0, 20.0, 0.5, "Weapon"],
	"bullet_trail": ["Bullet trail length (m)", 8.0, 0.0, 30.0, 0.5, "Weapon"],
	"bot_reaction": ["Bot reaction time (s)", 0.6, 0.1, 2.0, 0.05, "Bot"],
	"bot_accuracy": ["Bot accuracy (0-1)", 0.5, 0.0, 1.0, 0.05, "Bot"],
	"bot_speed": ["Bot run speed (m/s)", 4.6, 1.0, 10.0, 0.1, "Bot"],
	"kills_to_win": ["Kills to win", 5.0, 1.0, 20.0, 1.0, "Match"],
}

static var _values := {}
static var _loaded := false
static var _defaults_only := false


static func use_defaults() -> void:
	_defaults_only = true
	_loaded = true
	_values = {}


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
	for k in ENTRIES:
		if cf.has_section_key("fps", k):
			var e: Array = ENTRIES[k]
			_values[k] = clampf(float(cf.get_value("fps", k)), float(e[2]), float(e[3]))


static func save() -> void:
	if _defaults_only:
		return
	var cf := ConfigFile.new()
	for k in ENTRIES:
		cf.set_value("fps", k, snappedf(value(k), 0.001))
	cf.save(PATH)
