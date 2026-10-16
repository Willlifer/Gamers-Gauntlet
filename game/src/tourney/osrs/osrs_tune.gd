class_name OsrsTune
extends RefCounted
## The OSRS raid's numbers in one place (the MobaTune pattern): the player,
## the weapons, the Warden's attacks and specials. Ticks are OSRS game ticks
## (0.6 s). Changes live in user://osrs_tune.cfg; F1 in the raid opens
## OsrsTunePanel.

const PATH := "user://osrs_tune.cfg"

## key -> [label, default, min, max, step, section]
const ENTRIES := {
	"hp": ["Your hitpoints", 99.0, 20.0, 200.0, 1.0, "You"],
	"prayer": ["Your prayer points", 99.0, 20.0, 200.0, 1.0, "You"],
	"drain_every": ["A protect prayer drains 1 point every (ticks)", 3.0, 1.0, 12.0, 1.0, "You"],
	"food": ["Food in the inventory", 12.0, 0.0, 26.0, 1.0, "You"],
	"potions": ["Prayer potions (4 doses each)", 4.0, 0.0, 10.0, 1.0, "You"],
	"restore": ["Food / a dose restores (fraction of max)", 0.25, 0.05, 1.0, 0.05, "You"],
	"eat_delay": ["Eating delays your next attack (ticks)", 3.0, 0.0, 6.0, 1.0, "You"],
	"boost_doses": ["Damage potion doses", 4.0, 0.0, 12.0, 1.0, "You"],
	"boost_mult": ["Damage potion: bow / staff damage (x)", 1.2, 1.0, 2.0, 0.05, "You"],
	"boost_ticks": ["Damage potion: a dose lasts (ticks)", 40.0, 5.0, 200.0, 5.0, "You"],
	"bow_lo": ["Bow: min hit", 10.0, 0.0, 100.0, 1.0, "Weapons"],
	"bow_hi": ["Bow: max hit", 45.0, 1.0, 150.0, 1.0, "Weapons"],
	"bow_speed": ["Bow: attack every (ticks)", 4.0, 1.0, 10.0, 1.0, "Weapons"],
	"staff_lo": ["Staff: min hit", 15.0, 0.0, 100.0, 1.0, "Weapons"],
	"staff_hi": ["Staff: max hit", 55.0, 1.0, 150.0, 1.0, "Weapons"],
	"staff_speed": ["Staff: attack every (ticks)", 5.0, 1.0, 10.0, 1.0, "Weapons"],
	"accuracy": ["Chance a bow / staff hit lands", 0.85, 0.1, 1.0, 0.05, "Weapons"],
	"range": ["Bow / staff range (tiles)", 10.0, 1.0, 15.0, 1.0, "Weapons"],
	"dagger_dmg": ["Lightning dagger: hit (always lands)", 1.0, 0.0, 20.0, 1.0, "Weapons"],
	"dagger_speed": ["Lightning dagger: attack every (ticks)", 1.0, 1.0, 10.0, 1.0, "Weapons"],
	"boss_hp": ["The Warden's hitpoints", 1200.0, 100.0, 4000.0, 10.0, "Warden"],
	"auto_every": ["Projectile every (ticks), phases 1-2", 5.0, 2.0, 12.0, 1.0, "Warden"],
	"auto_every_p3": ["Projectile every (ticks), phase 3", 4.0, 2.0, 12.0, 1.0, "Warden"],
	"auto_lo": ["Projectile: min hit unprayed", 18.0, 0.0, 99.0, 1.0, "Warden"],
	"auto_hi": ["Projectile: max hit unprayed", 28.0, 1.0, 99.0, 1.0, "Warden"],
	"flight_s": ["Projectile flight, any distance (s)", 3.0, 0.6, 6.0, 0.6, "Warden"],
	"twin_chance": ["Phase 3: chance of a twin volley (flick)", 0.35, 0.0, 1.0, 0.05, "Warden"],
	"melee_hit": ["Melee smack if you stand next to it", 40.0, 0.0, 99.0, 1.0, "Warden"],
	"special_every": ["A special every (ticks)", 11.0, 4.0, 30.0, 1.0, "Specials"],
	"lightning_n": ["Lightning bolts, phases 1-2", 7.0, 1.0, 30.0, 1.0, "Specials"],
	"lightning_n_p3": ["Lightning bolts, phase 3", 11.0, 1.0, 40.0, 1.0, "Specials"],
	"lightning_warn": ["Lightning shadow grows for (ticks)", 4.0, 1.0, 8.0, 1.0, "Specials"],
	"lightning_dmg": ["Lightning hit", 15.0, 0.0, 99.0, 1.0, "Specials"],
	"boulder_n": ["Boulders per drop", 3.0, 1.0, 10.0, 1.0, "Specials"],
	"boulder_warn": ["Boulder shadow (ticks)", 5.0, 1.0, 10.0, 1.0, "Specials"],
	"boulder_dmg": ["Boulder hit", 25.0, 0.0, 99.0, 1.0, "Specials"],
	"boulder_stay": ["A fallen boulder blocks its tile for (ticks)", 12.0, 0.0, 60.0, 1.0, "Specials"],
	"slam_warn": ["Slam: the floor glows for (ticks)", 4.0, 1.0, 8.0, 1.0, "Specials"],
	"slam_dmg": ["Slam hit", 30.0, 0.0, 99.0, 1.0, "Specials"],
	"slam_gap": ["Slam: ticks between its three hits", 4.0, 1.0, 8.0, 1.0, "Specials"],
	"slam_gap_fast": ["Slam: ticks between hits below 50% HP", 2.0, 1.0, 8.0, 1.0, "Specials"],
	"rip_pct": ["The far row is torn out per (fraction of HP lost)", 0.08, 0.02, 0.5, 0.01, "Specials"],
	"rip_warn": ["The row cracks for (ticks)", 4.0, 1.0, 10.0, 1.0, "Specials"],
	"rip_dmg": ["Falling with the row", 40.0, 0.0, 99.0, 1.0, "Specials"],
	"rows_left": ["Rows that always stay", 5.0, 2.0, 12.0, 1.0, "Specials"],
	"skull_min": ["Skulls per skull phase: fewest", 5.0, 1.0, 20.0, 1.0, "Skulls"],
	"skull_max": ["Skulls per skull phase: most", 10.0, 1.0, 20.0, 1.0, "Skulls"],
	"skull_hp": ["Skull hitpoints (any hit that lands takes 1)", 1.0, 1.0, 10.0, 1.0, "Skulls"],
	"skull_base": ["Skull phase: base charge time (ticks)", 2.0, 0.0, 40.0, 1.0, "Skulls"],
	"skull_per": ["Skull phase: extra charge time per skull (ticks)", 1.67, 0.5, 20.0, 0.01, "Skulls"],
	"skull_dmg": ["Each skull left bursts for", 15.0, 0.0, 99.0, 1.0, "Skulls"],
	"shield_first": ["First shield after (ticks)", 30.0, 1.0, 200.0, 1.0, "Shields"],
	"shield_every": ["Shield swaps magic / bowfire every (ticks)", 35.0, 5.0, 200.0, 1.0, "Shields"],
	"sigil_every": ["Sun Sigil every (ticks)", 22.0, 5.0, 100.0, 1.0, "Sun Sigil"],
	"sigil_warn": ["Sun Sigil ignites after (ticks)", 6.0, 2.0, 12.0, 1.0, "Sun Sigil"],
	"sigil_hits": ["Empowered attacks from a sigil", 3.0, 0.0, 10.0, 1.0, "Sun Sigil"],
	"sigil_mult": ["Empowered damage (x)", 2.0, 1.0, 4.0, 0.1, "Sun Sigil"],
	"time_limit": ["Time limit (s)", 240.0, 60.0, 900.0, 10.0, "Match"],
	"bot_react": ["Bot: chance it prays right", 0.85, 0.0, 1.0, 0.05, "Bot"],
	"bot_dodge": ["Bot: chance it dodges a telegraph", 0.8, 0.0, 1.0, 0.05, "Bot"],
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
		if cf.has_section_key("osrs", k):
			var e: Array = ENTRIES[k]
			_values[k] = clampf(float(cf.get_value("osrs", k)), float(e[2]), float(e[3]))


static func save() -> void:
	if _defaults_only:
		return
	var cf := ConfigFile.new()
	for k in ENTRIES:
		cf.set_value("osrs", k, snappedf(value(k), 0.001))
	cf.save(PATH)
