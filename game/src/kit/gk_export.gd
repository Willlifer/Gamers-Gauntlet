class_name GKExport
extends RefCounted
## Writing kit assets out for other projects and tools: a .glb (plain PBR
## materials named after their roles, the markers as empty nodes) and a JSON
## sidecar beside it (id, version, the exact params that rebuild it, markers,
## colliders, lights, budgets). Any Godot game can then either load the .glb
## or rebuild from the params with the kit itself.
## Returns { ok: bool, error: String, path: String, bytes: int }; never throws.

static func export_glb(a: GKAsset, path: String) -> Dictionary:
	if a == null or a.parts.is_empty():
		return { "ok": false, "error": "nothing to export", "path": path }
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return { "ok": false, "error": "cannot create folder %s (%s)" % [dir, error_string(mk)], "path": path }
	var node := a.instantiate(false, true)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(node, st)
	if err != OK:
		node.free()
		return { "ok": false, "error": "glTF conversion failed (%s)" % error_string(err), "path": path }
	err = doc.write_to_filesystem(st, path)
	node.free()
	if err != OK:
		return { "ok": false, "error": "cannot write %s (%s)" % [path, error_string(err)], "path": path }
	var side := path.get_basename() + ".json"
	var f := FileAccess.open(side, FileAccess.WRITE)
	if f == null:
		return { "ok": false, "error": "cannot write %s (%s)" % [side, error_string(FileAccess.get_open_error())], "path": path }
	var info := a.describe()
	info["generator"] = "GKRegistry (The Gamer kit)"
	info["exported"] = Time.get_datetime_string_from_system(true)
	f.store_string(JSON.stringify(_plain(info), "\t"))
	f.close()
	var bytes := FileAccess.get_file_as_bytes(path).size()
	return { "ok": true, "error": "", "path": path, "bytes": bytes }


## JSON can't hold Vector3 / Color: turn them into arrays and strings.
static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[str(k)] = _plain(v[k])
			return o
		TYPE_ARRAY:
			var o := []
			for x in v:
				o.append(_plain(x))
			return o
		TYPE_VECTOR3:
			return [v.x, v.y, v.z]
		TYPE_VECTOR2:
			return [v.x, v.y]
		TYPE_COLOR:
			return (v as Color).to_html()
		TYPE_TRANSFORM3D:
			var t: Transform3D = v
			return { "origin": [t.origin.x, t.origin.y, t.origin.z], "basis": [[t.basis.x.x, t.basis.x.y, t.basis.x.z], [t.basis.y.x, t.basis.y.y, t.basis.y.z], [t.basis.z.x, t.basis.z.y, t.basis.z.z]] }
	return v


## A preset file: { "kit_preset": 1, "asset": id, "version": n, "params": {...} }.
static func save_preset(path: String, asset_id: String, version: int, params: Dictionary) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return { "ok": false, "error": "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())] }
	f.store_string(JSON.stringify({ "kit_preset": 1, "asset": asset_id, "version": version, "params": params }, "\t"))
	f.close()
	return { "ok": true, "error": "" }


## Reads a preset file; unknown keys and a version mismatch come back as
## warnings (GKDef.validate fills and clamps the rest).
static func load_preset(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return { "ok": false, "error": "no file %s" % path }
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("params"):
		return { "ok": false, "error": "%s is not a kit preset" % path.get_file() }
	var d := GKRegistry.def(str(data.get("asset", "")))
	if d == null:
		return { "ok": false, "error": "preset is for unknown asset '%s'" % data.get("asset", "") }
	var warn := PackedStringArray()
	if int(data.get("version", 0)) != d.version():
		warn.append("preset made for v%d, generator is v%d" % [int(data.get("version", 0)), d.version()])
	var params := d.validate(data.params, warn)
	return { "ok": true, "error": "", "asset": d.id(), "params": params, "warnings": warn }
