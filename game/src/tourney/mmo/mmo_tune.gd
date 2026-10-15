class_name MmoTune
extends RefCounted
## The raid's feel numbers in one place (the MobaTune / FpsTune pattern, G19):
## movement, the camera, combat pacing, the Giant and its spells, the bots.
## Changes live in user://mmo_tune.cfg; F1 in the raid opens MmoTunePanel.
## Distances are metres on the 2.2 m Black | White body.

const PATH := "user://mmo_tune.cfg"

## key -> [label, default, min, max, step, section]
const ENTRIES := {
	"run_speed": ["Run speed (m/s)", 7.0, 2.0, 14.0, 0.1, "Move"],
	"back_speed": ["Backpedal speed (m/s)", 4.5, 1.0, 10.0, 0.1, "Move"],
	"turn_rate": ["Keyboard turn (deg/s)", 180.0, 60.0, 540.0, 5.0, "Move"],
	"jump": ["Jump speed (m/s)", 7.2, 0.0, 14.0, 0.1, "Move"],
	"gravity": ["Gravity (m/s²)", 21.0, 5.0, 40.0, 0.5, "Move"],
	"cam_dist": ["Camera distance at start (m)", 16.0, 2.0, 30.0, 0.5, "Camera"],
	"cam_pitch": ["Camera pitch at start (deg down)", 34.0, -10.0, 80.0, 1.0, "Camera"],
	"cam_min": ["Closest zoom (m)", 2.2, 0.5, 8.0, 0.1, "Camera"],
	"cam_max": ["Farthest zoom (m)", 26.0, 8.0, 50.0, 0.5, "Camera"],
	"zoom_step": ["Zoom per wheel notch (x)", 1.15, 1.02, 1.6, 0.01, "Camera"],
	"mouse_sens": ["Mouse look sensitivity", 0.25, 0.05, 1.0, 0.01, "Camera"],
	"cam_fov": ["Field of view (deg)", 62.0, 40.0, 100.0, 1.0, "Camera"],
	"gcd": ["Global cooldown (s)", 1.5, 0.5, 2.5, 0.05, "Combat"],
	"dmg_mult": ["Player damage (x)", 1.0, 0.2, 4.0, 0.05, "Combat"],
	"heal_mult": ["Player healing (x)", 1.0, 0.2, 4.0, 0.05, "Combat"],
	"boss_hp": ["Giant HP", 300000.0, 20000.0, 800000.0, 5000.0, "Giant"],
	"boss_auto": ["Giant auto-attack damage", 360.0, 0.0, 2000.0, 10.0, "Giant"],
	"boss_swing": ["Giant swing time (s)", 2.2, 0.8, 5.0, 0.1, "Giant"],
	"boss_scale": ["Giant size (x a person)", 5.0, 1.5, 5.0, 0.1, "Giant"],
	"spell_gap": ["Least time between spells (s)", 5.0, 5.0, 30.0, 0.5, "Giant"],
	"upheaval_dmg": ["Upheaval damage", 1700.0, 0.0, 6000.0, 50.0, "Giant"],
	"meteor_dmg": ["Meteor damage", 1300.0, 0.0, 6000.0, 50.0, "Giant"],
	"meteor_count": ["Meteors per rain", 14.0, 3.0, 40.0, 1.0, "Giant"],
	"bomb_dmg": ["Bomb splash damage (to others nearby)", 1500.0, 0.0, 6000.0, 50.0, "Giant"],
	"bomb_radius": ["Bomb radius (m)", 6.0, 2.0, 14.0, 0.25, "Giant"],
	"bomb_fuse": ["Bomb fuse (s)", 6.0, 2.0, 12.0, 0.25, "Giant"],
	"gather_dmg": ["Gather: damage outside the ring", 2800.0, 0.0, 8000.0, 50.0, "Giant"],
	"gather_split": ["Gather: damage shared by those inside", 3000.0, 0.0, 12000.0, 50.0, "Giant"],
	"gather_radius": ["Gather ring radius (m)", 5.0, 2.0, 12.0, 0.25, "Giant"],
	"gather_fuse": ["Gather: time to get in (s)", 7.0, 2.0, 14.0, 0.25, "Giant"],
	"enrage": ["Enrage after (s)", 300.0, 60.0, 900.0, 10.0, "Giant"],
	"brand_first": ["Cinderbrand: first after the pull (s)", 20.0, 5.0, 120.0, 1.0, "Cinderbrand"],
	"brand_every": ["Cinderbrand: every (s)", 45.0, 15.0, 180.0, 1.0, "Cinderbrand"],
	"brand_pct": ["Cinderbrand: share of max HP if left alone (0 = off)", 0.25, 0.0, 1.0, 0.01, "Cinderbrand"],
	"brand_dur": ["Cinderbrand: lasts (s)", 30.0, 5.0, 60.0, 1.0, "Cinderbrand"],
	"brand_tick": ["Cinderbrand: a tick every (s)", 1.5, 0.5, 5.0, 0.1, "Cinderbrand"],
	"brand_run": ["Cinderbrand: seconds burned off per metre run", 0.5, 0.0, 3.0, 0.05, "Cinderbrand"],
	"bot_react": ["Bot reaction to mechanics (s)", 0.7, 0.0, 3.0, 0.05, "Bots"],
	"bot_slip": ["Bot chance to fumble a mechanic (0-1)", 0.12, 0.0, 1.0, 0.01, "Bots"],
	"bot_run_off": ["Bots run the brand off below this HP (0-1)", 0.6, 0.0, 1.0, 0.05, "Bots"],
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
	for k: String in _values:
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
	for k: String in ENTRIES:
		if cf.has_section_key("mmo", k):
			var e: Array = ENTRIES[k]
			_values[k] = clampf(float(cf.get_value("mmo", k)), float(e[2]), float(e[3]))


static func save() -> void:
	if _defaults_only:
		return
	var cf := ConfigFile.new()
	for k: String in ENTRIES:
		cf.set_value("mmo", k, snappedf(value(k), 0.001))
	cf.save(PATH)
