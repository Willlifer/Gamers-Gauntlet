class_name MobaTune
extends RefCounted
## The MOBA feel numbers in one place, for playtests: move speed, attack
## wind-up and projectile speed per champion, flash distance, and how fast
## champions turn to face where they go. Defaults come from MobaChamps and
## MobaSim; anything changed is kept in user://moba_tune.cfg (one readable
## file, also editable by hand) and read at start. MobaTunePanel (F1 in a
## match or the range) edits them live: the running match picks changes up
## on the next tick.
##
## Online (lockstep) will need every peer on the same numbers: the host's
## file becomes part of the match setup then. Tools (probes, shots) call
## use_defaults() so a tuned file never changes their results.

const PATH := "user://moba_tune.cfg"
## G54 moved the flash default (4.0 -> 5.25) and every range: a file saved
## before then would pin the old flash, so its flash is dropped on load.
const VERSION := 2

## key -> [label, min, max, step]; champion keys are "<champ>.<stat>".
const STATS := {
	"ms": ["Move speed (units/s)", 1.5, 6.0, 0.05],
	"windup": ["Attack wind-up (s)", 0.05, 0.8, 0.01],
	"proj_speed": ["Projectile speed (units/s)", 4.0, 60.0, 0.5],
}
const GLOBAL := {
	"flash_range": ["Flash distance (units)", 1.0, 8.0, 0.1],
	"turn_rate": ["Turn rate (higher = snappier)", 2.0, 60.0, 0.5],
}

static var _values := {}
static var _loaded := false
static var _defaults_only := false


static func defaults() -> Dictionary:
	var d := {}
	for id in MobaChamps.CHAMPS:
		var c: Dictionary = MobaChamps.CHAMPS[id]
		for s in STATS:
			d["%s.%s" % [id, s]] = float(c[s])
	d["flash_range"] = MobaSim.FLASH_RANGE
	d["turn_rate"] = 18.0
	return d


## Tools: ignore the file, run on the shipped numbers.
static func use_defaults() -> void:
	_defaults_only = true
	_values = defaults()
	_loaded = true


static func value(key: String) -> float:
	_ensure()
	return float(_values.get(key, defaults().get(key, 0.0)))


static func spec(key: String) -> Array:
	var i := key.find(".")
	return STATS[key.substr(i + 1)] if i >= 0 else GLOBAL[key]


static func set_value(key: String, v: float) -> void:
	_ensure()
	var sp := spec(key)
	_values[key] = clampf(v, float(sp[1]), float(sp[2]))
	save()


static func reset() -> void:
	_values = defaults()
	save()


static func changed_keys() -> PackedStringArray:
	_ensure()
	var d := defaults()
	var out := PackedStringArray()
	for k: String in _values:
		if not is_equal_approx(float(_values[k]), float(d.get(k, 0.0))):
			out.append(k)
	return out


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_values = defaults()
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var old := int(cf.get_value("meta", "version", 1)) < VERSION
	for k: String in _values:
		var sec := "global" if k.find(".") < 0 else k.get_slice(".", 0)
		var key := k if k.find(".") < 0 else k.get_slice(".", 1)
		if old and k == "flash_range":
			continue
		if cf.has_section_key(sec, key):
			var sp := spec(k)
			_values[k] = clampf(float(cf.get_value(sec, key)), float(sp[1]), float(sp[2]))


static func save() -> void:
	if _defaults_only:
		return
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", VERSION)
	for k: String in _values:
		var sec := "global" if k.find(".") < 0 else k.get_slice(".", 0)
		var key := k if k.find(".") < 0 else k.get_slice(".", 1)
		cf.set_value(sec, key, snappedf(float(_values[k]), 0.001))
	var err := cf.save(PATH)
	if err != OK:
		push_warning("MobaTune: cannot save %s (%s)" % [PATH, error_string(err)])


## Push the current numbers into a running match's champions.
static func apply(sim: MobaSim) -> void:
	if sim == null:
		return
	for u in sim.units:
		if u.kind != "champ" or u.champ == "":
			continue
		u.ms = value(u.champ + ".ms")
		u.windup = value(u.champ + ".windup")
		u.proj_speed = value(u.champ + ".proj_speed")
