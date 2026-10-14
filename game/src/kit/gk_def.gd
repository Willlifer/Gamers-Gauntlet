class_name GKDef
extends RefCounted
## One kit generator: its parameters (the data contract), presets, and the
## build itself. Subclasses override id(), kind(), version(), schema(),
## presets() and _build(p). Everything public goes through build(), which
## validates first, so a generator never sees a missing or out-of-range value.
##
## A schema entry: { key, label, group, type: "float" | "int" | "bool" | "enum",
##   default, min, max, step, options (enum) }
## Parameters are plain numbers/bools/strings, so a preset is a JSON object
## and an export carries exactly what rebuilds it.

func id() -> String:
	return ""


func title() -> String:
	return id().capitalize()


func kind() -> String:
	return "item"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return []


func presets() -> Dictionary:
	return {}


func _build(_p: Dictionary) -> GKAsset:
	return GKAsset.new()


# ----------------------------------------------------------------- shared

func defaults() -> Dictionary:
	var out := {}
	for e in schema():
		out[e.key] = e.default
	return out


func entry(key: String) -> Dictionary:
	for e in schema():
		if e.key == key:
			return e
	return {}


## Fill missing keys with defaults, clamp ranges, coerce types; problems go
## to `errors` (unknown keys, wrong types), never stop the build.
func validate(p: Dictionary, errors: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out := defaults()
	for k in p:
		var e := entry(str(k))
		if e.is_empty():
			errors.append("%s: unknown parameter '%s' ignored" % [id(), k])
			continue
		out[k] = coerce(e, p[k], errors)
	return out


static func coerce(e: Dictionary, v: Variant, errors: PackedStringArray) -> Variant:
	match str(e.get("type", "float")):
		"bool":
			if typeof(v) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
				return bool(v)
		"int":
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
				return clampi(int(round(float(v))), int(e.get("min", -1073741824)), int(e.get("max", 1073741824)))
		"enum":
			var opts: Array = e.get("options", [])
			if opts.has(str(v)):
				return str(v)
		_:
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
				return clampf(float(v), float(e.get("min", -1e9)), float(e.get("max", 1e9)))
	errors.append("'%s': bad value %s, default used" % [e.key, var_to_str(v)])
	return e.default


## Validated build. The asset carries its id, version and exact params.
func build(p: Dictionary = {}) -> GKAsset:
	var errs := PackedStringArray()
	var q := validate(p, errs)
	var a := _build(q)
	a.id = id()
	a.kind = kind()
	a.version = version()
	a.params = q
	a.warnings.append_array(errs)
	return a


## A named preset merged over the defaults ("" = the defaults).
func preset(preset_name: String) -> Dictionary:
	var out := defaults()
	var ps := presets()
	if preset_name != "" and ps.has(preset_name):
		out.merge(ps[preset_name], true)
	return out


# helpers for schema literals
static func pf(key: String, label: String, group: String, def: float, lo: float, hi: float, step := 0.001) -> Dictionary:
	return { "key": key, "label": label, "group": group, "type": "float", "default": def, "min": lo, "max": hi, "step": step }


static func pi(key: String, label: String, group: String, def: int, lo: int, hi: int) -> Dictionary:
	return { "key": key, "label": label, "group": group, "type": "int", "default": def, "min": lo, "max": hi, "step": 1 }


static func pb(key: String, label: String, group: String, def: bool) -> Dictionary:
	return { "key": key, "label": label, "group": group, "type": "bool", "default": def }


static func pe(key: String, label: String, group: String, def: String, options: Array) -> Dictionary:
	return { "key": key, "label": label, "group": group, "type": "enum", "default": def, "options": options }
