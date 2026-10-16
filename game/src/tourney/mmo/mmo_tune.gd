class_name MmoTune
extends RefCounted
## The raid's feel numbers in one place (the MobaTune / FpsTune pattern, G19):
## movement, the camera, combat pacing, the Giant and its spells, the bots.
## Changes live in user://mmo_tune.cfg; F1 in the raid opens MmoTunePanel.
## Distances are metres on the 2.2 m Black | White body.

const PATH := "user://mmo_tune.cfg"

## key -> [label, default, min, max, step, section]
const ENTRIES := {
	"w_output": ["Weight: output (damage + healing vs your class)", 35.0, 0.0, 100.0, 1.0, "Verdict"],
	"w_mech": ["Weight: mechanics performed", 30.0, 0.0, 100.0, 1.0, "Verdict"],
	"w_dodge": ["Weight: AoEs avoided", 15.0, 0.0, 100.0, 1.0, "Verdict"],
	"w_alive": ["Weight: survival (time alive)", 12.0, 0.0, 100.0, 1.0, "Verdict"],
	"w_busy": ["Weight: activity (always be casting)", 8.0, 0.0, 100.0, 1.0, "Verdict"],
	"out_full": ["Output for full marks (x a bot's pace)", 1.15, 0.5, 2.0, 0.05, "Verdict"],
	"cleanse_credit": ["Mechanics credit per cleanse on someone else", 0.5, 0.0, 2.0, 0.1, "Verdict"],
	"grade_s": ["Grade S from", 96.0, 50.0, 100.0, 1.0, "Verdict"],
	"grade_a": ["Grade A from", 88.0, 40.0, 100.0, 1.0, "Verdict"],
	"grade_b": ["Grade B from", 76.0, 30.0, 100.0, 1.0, "Verdict"],
	"grade_c": ["Grade C from", 64.0, 20.0, 100.0, 1.0, "Verdict"],
	"grade_d": ["Grade D from", 50.0, 10.0, 100.0, 1.0, "Verdict"],
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
	"scorch_at": ["Scorched Earth: half the courtyard burns from (s into the fight)", 45.0, 10.0, 300.0, 1.0, "Scorched Earth"],
	"scorch_warn": ["Scorched Earth: warning before it burns (s)", 8.0, 2.0, 20.0, 0.5, "Scorched Earth"],
	"scorch_pct": ["Scorched Earth: damage per second (fraction of max HP)", 0.25, 0.0, 2.0, 0.05, "Scorched Earth"],
	"scorch_spin_at": ["Scorched Earth: starts turning at (s into the fight)", 90.0, 10.0, 600.0, 1.0, "Scorched Earth"],
	"scorch_spin": ["Scorched Earth: turn speed (deg/s)", 9.0, 0.0, 45.0, 0.5, "Scorched Earth"],
	"scorch_spin_on": ["Scorched Earth: turns for (s) at a time", 15.0, 1.0, 30.0, 0.5, "Scorched Earth"],
	"scorch_spin_off": ["Scorched Earth: then holds still for (s)", 30.0, 0.0, 30.0, 0.5, "Scorched Earth"],
	"bomb_pool_chance": ["A bomb leaves burning ground (chance)", 0.5, 0.0, 1.0, 0.05, "Giant"],
	"bomb_pool_r": ["Burning ground radius (m)", 4.0, 1.0, 10.0, 0.25, "Giant"],
	"bomb_pool_dur": ["Burning ground lasts (s)", 15.0, 1.0, 60.0, 1.0, "Giant"],
	"bomb_pool_dps": ["Burning ground damage per second", 350.0, 0.0, 3000.0, 10.0, "Giant"],
	"silence_at": ["Below this HP, no more text warnings (\"You're on your own now.\")", 0.5, 0.0, 1.0, 0.05, "Giant"],
	"frenzy_at": ["Below this HP, the spell rotation speeds up", 0.25, 0.0, 1.0, 0.05, "Giant"],
	"frenzy_rate": ["Spell rotation speed below that (x)", 2.0, 1.0, 4.0, 0.25, "Giant"],
	"brand_first": ["Cinderbrand: first after the pull (s)", 20.0, 5.0, 120.0, 1.0, "Cinderbrand"],
	"brand_every": ["Cinderbrand: every (s)", 45.0, 15.0, 180.0, 1.0, "Cinderbrand"],
	"brand_pct": ["Cinderbrand: share of max HP if left alone (0 = off)", 0.25, 0.0, 1.0, 0.01, "Cinderbrand"],
	"brand_dur": ["Cinderbrand: lasts (s)", 30.0, 5.0, 60.0, 1.0, "Cinderbrand"],
	"brand_tick": ["Cinderbrand: a tick every (s)", 1.5, 0.5, 5.0, 0.1, "Cinderbrand"],
	"brand_run": ["Cinderbrand: seconds burned off per metre run", 0.5, 0.0, 3.0, 0.05, "Cinderbrand"],
	"tank_hp": ["Tank HP (for six; scales with the raid)", 330000.0, 20000.0, 900000.0, 5000.0, "Planet of Tanks"],
	"cannon_every": ["Cannon blast every (s)", 5.0, 2.0, 15.0, 0.25, "Planet of Tanks"],
	"cannon_warn": ["Cannon blast: telegraph (s)", 1.8, 0.5, 4.0, 0.1, "Planet of Tanks"],
	"cannon_dmg": ["Cannon blast damage (one caught)", 1400.0, 0.0, 6000.0, 50.0, "Planet of Tanks"],
	"cannon_stack": ["Cannon blast: extra damage per extra body caught (x)", 0.75, 0.0, 3.0, 0.05, "Planet of Tanks"],
	"cannon_arc": ["Cannon blast arc (deg)", 120.0, 30.0, 180.0, 5.0, "Planet of Tanks"],
	"barrage_count": ["Barrage: rounds", 10.0, 3.0, 30.0, 1.0, "Planet of Tanks"],
	"barrage_r": ["Barrage: blast radius (m)", 4.2, 1.5, 8.0, 0.1, "Planet of Tanks"],
	"barrage_dmg": ["Barrage: damage per round", 1700.0, 0.0, 6000.0, 50.0, "Planet of Tanks"],
	"barrage_pool_r": ["Barrage: burning crater radius (m)", 3.4, 1.0, 8.0, 0.1, "Planet of Tanks"],
	"barrage_pool_dps": ["Barrage: crater damage per second", 450.0, 0.0, 3000.0, 10.0, "Planet of Tanks"],
	"smoke_speed": ["Smokescreen: spreads at (m/s)", 2.2, 0.5, 8.0, 0.1, "Planet of Tanks"],
	"smoke_band": ["Smokescreen: thick front band (m)", 5.0, 1.0, 12.0, 0.25, "Planet of Tanks"],
	"smoke_core": ["Smokescreen: strength behind the front (0-1)", 0.15, 0.0, 1.0, 0.05, "Planet of Tanks"],
	"smoke_pct": ["Smokescreen: poison per second at full (fraction of max HP)", 0.07, 0.0, 0.5, 0.01, "Planet of Tanks"],
	"smoke_slow": ["Smokescreen: slow and damage cut at full (0-1)", 0.5, 0.0, 0.9, 0.05, "Planet of Tanks"],
	"tread_warn": ["Treadburn: dust builds for (s)", 4.0, 1.5, 8.0, 0.25, "Planet of Tanks"],
	"tread_dmg": ["Treadburn: explosion damage", 2600.0, 0.0, 8000.0, 50.0, "Planet of Tanks"],
	"tread_both": ["Treadburn: chance both treads go at once", 0.35, 0.0, 1.0, 0.05, "Planet of Tanks"],
	"loose_wobble": ["Loose Cannon: wobble before it goes (s)", 3.0, 1.0, 6.0, 0.25, "Planet of Tanks"],
	"loose_dur": ["Loose Cannon: wild fire lasts (s)", 4.0, 1.0, 10.0, 0.25, "Planet of Tanks"],
	"loose_dmg": ["Loose Cannon: damage per 0.4 s in the middle", 750.0, 0.0, 4000.0, 25.0, "Planet of Tanks"],
	"loose_r": ["Loose Cannon: the deadly middle (share of the arena)", 0.75, 0.3, 0.95, 0.05, "Planet of Tanks"],
	"flank_mult": ["After Loose Cannon: damage taken on the flanks (x)", 1.5, 1.0, 3.0, 0.05, "Planet of Tanks"],
	"ram_rock": ["Ram: rocking before the charge (s)", 2.5, 1.0, 6.0, 0.25, "Planet of Tanks"],
	"ram_speed": ["Ram: charge speed (m/s)", 16.0, 5.0, 40.0, 0.5, "Planet of Tanks"],
	"ram_dmg": ["Ram: damage to anyone in its path", 3200.0, 0.0, 9000.0, 50.0, "Planet of Tanks"],
	"ram_aim": ["Ram: the edge blast's telegraph (s)", 3.0, 1.0, 6.0, 0.25, "Planet of Tanks"],
	"arc_dmg": ["Ram: the edge blast's damage", 3000.0, 0.0, 9000.0, 50.0, "Planet of Tanks"],
	"arc_deg": ["Ram: the edge blast's arc (deg)", 110.0, 40.0, 170.0, 5.0, "Planet of Tanks"],
	"add_hp": ["Light tanks: HP each (for six)", 20000.0, 2000.0, 100000.0, 1000.0, "Planet of Tanks"],
	"add_speed": ["Light tanks: chase speed (m/s)", 4.2, 1.0, 10.0, 0.1, "Planet of Tanks"],
	"add_dmg": ["Light tanks: ram damage", 520.0, 0.0, 3000.0, 10.0, "Planet of Tanks"],
	"add_every": ["Light tanks: a ram every (s)", 1.5, 0.5, 5.0, 0.1, "Planet of Tanks"],
	"tank_rush_rate": ["Below 10%: everything this much faster (x)", 2.0, 1.0, 4.0, 0.25, "Planet of Tanks"],
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
