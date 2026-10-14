class_name GKMaterials
extends RefCounted
## Material roles for the Gamer Kit. A GKMesh surface is named after a role;
## this turns the role into a material (gk_surface.gdshader, cached and
## shared), or into a plain StandardMaterial3D for export to other tools.
## A role unknown here renders magenta and warns once, so a typo shows up in
## the first frame instead of silently looking grey.
##
## Role entry: a, b, c = colours (hex), rough, metal, spec, pat (see the
## shader), scale, amt, wear, world (environment roles: patterns in world
## space so neighbouring pieces line up), axis (grain / brushing direction).

const SHADER := "res://shaders/gk_surface.gdshader"
const PAT := { "plain": 0, "grain": 1, "plaster": 2, "blocks": 3, "cobble": 4, "siding": 5, "membrane": 6,
	"stipple": 7, "brushed": 8, "asphalt": 9, "grass": 10, "concrete": 11, "pavers": 12 }

const ROLES := {
	# ---- items (object space)
	"gunmetal": { "a": "#26292d", "b": "#1b1d20", "rough": 0.3, "metal": 0.85, "pat": "brushed", "scale": 260.0, "amt": 0.18 },
	"blued": { "a": "#1a1d22", "b": "#121418", "rough": 0.22, "metal": 0.9, "pat": "brushed", "scale": 300.0, "amt": 0.15 },
	"steel": { "a": "#8a8d90", "b": "#6c6f73", "rough": 0.35, "metal": 1.0, "pat": "brushed", "scale": 300.0, "amt": 0.2 },
	"alloy_black": { "a": "#18191b", "b": "#121314", "rough": 0.42, "metal": 0.65, "pat": "stipple", "scale": 400.0, "amt": 0.1 },
	"polymer_black": { "a": "#111213", "b": "#0d0e0f", "rough": 0.62, "metal": 0.0, "pat": "stipple", "scale": 700.0, "amt": 0.15 },
	"polymer_olive": { "a": "#4a5536", "b": "#455033", "rough": 0.6, "metal": 0.0, "pat": "stipple", "scale": 700.0, "amt": 0.12, "wear": 0.2 },
	"rubber": { "a": "#19191a", "b": "#121213", "rough": 0.92, "metal": 0.0, "pat": "stipple", "scale": 900.0, "amt": 0.2 },
	"glass_lens": { "a": "#1c3440", "b": "#0d1a22", "rough": 0.05, "metal": 0.0, "spec": 1.0, "pat": "plain", "scale": 30.0, "amt": 0.2 },
	"brass": { "a": "#b08d4a", "b": "#8a6a32", "rough": 0.3, "metal": 1.0, "pat": "brushed", "scale": 200.0, "amt": 0.2 },
	"orange_tip": { "a": "#e0601c", "b": "#c4521a", "rough": 0.6, "pat": "plain", "scale": 50.0, "amt": 0.1 },
	"wood_branch": { "a": "#6f5a44", "b": "#3a2b1d", "c": "#251c13", "rough": 0.62, "pat": "grain", "scale": 30.0, "amt": 0.95, "axis": [0, 1, 0] },
	"wood_end": { "a": "#8a7055", "b": "#6a5440", "c": "#3a2a1c", "rough": 0.85, "pat": "plain", "scale": 60.0, "amt": 0.4 },
	"leather_black": { "a": "#1b1a19", "b": "#2a2725", "rough": 0.68, "pat": "stipple", "scale": 500.0, "amt": 0.6 },
	"felt_white": { "a": "#e8e4dc", "b": "#cfc9be", "rough": 1.0, "spec": 0.2, "pat": "stipple", "scale": 900.0, "amt": 0.8 },
	# ---- environments (world space)
	"plaster_white": { "a": "#c6c1b8", "b": "#9d978d", "c": "#b59e7c", "rough": 0.95, "pat": "plaster", "scale": 0.45, "amt": 0.3, "world": true },
	"plaster_ochre": { "a": "#d8ad68", "b": "#c0924f", "c": "#cdbfa6", "rough": 0.95, "pat": "plaster", "scale": 0.45, "amt": 0.22, "world": true },
	"sandstone": { "a": "#c4a273", "b": "#ad8a5c", "c": "#8f7451", "rough": 0.95, "pat": "blocks", "scale": 0.32, "amt": 0.4, "world": true },
	"sandstone_trim": { "a": "#cdb08a", "b": "#b89a72", "c": "#9c8260", "rough": 0.9, "pat": "plain", "scale": 2.0, "amt": 0.25, "world": true },
	"cobble": { "a": "#c9b597", "b": "#a99476", "c": "#8a7558", "rough": 0.92, "pat": "cobble", "scale": 0.42, "amt": 0.45, "world": true },
	"flagstone": { "a": "#c4b69c", "b": "#9f927c", "c": "#9a8c76", "rough": 0.9, "pat": "pavers", "scale": 0.55, "amt": 0.7, "world": true },
	"sandstone_render": { "a": "#c9a46c", "b": "#b38c58", "c": "#b89a74", "rough": 0.95, "pat": "plaster", "scale": 0.4, "amt": 0.35, "world": true },
	"wood_old": { "a": "#7b6248", "b": "#5c4632", "c": "#3b2d20", "rough": 0.9, "pat": "grain", "scale": 4.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"wood_pole": { "a": "#8a7253", "b": "#6a5640", "c": "#4a3b2a", "rough": 0.9, "pat": "grain", "scale": 3.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"wood_door": { "a": "#5a6e78", "b": "#4a5a62", "c": "#3a3530", "rough": 0.85, "pat": "grain", "scale": 4.0, "amt": 0.5, "world": true, "axis": [0, 1, 0] },
	"iron_rust": { "a": "#5e4a3e", "b": "#43352c", "rough": 0.85, "metal": 0.15, "pat": "plain", "scale": 6.0, "amt": 0.45, "world": true },
	"iron_dark": { "a": "#3a3b3c", "b": "#2a2b2c", "rough": 0.6, "metal": 0.7, "pat": "plain", "scale": 3.0, "amt": 0.3, "world": true },
	"canvas_awning": { "a": "#9aa5a8", "b": "#7c878a", "rough": 0.95, "pat": "plain", "scale": 3.0, "amt": 0.3, "world": true },
	"sign_blue": { "a": "#2f6f8e", "b": "#285f7a", "rough": 0.6, "pat": "plain", "scale": 4.0, "amt": 0.15, "world": true },
	"sign_white": { "a": "#e9e6df", "b": "#d8d4cb", "rough": 0.6, "pat": "plain", "scale": 4.0, "amt": 0.15, "world": true },
	"sign_red": { "a": "#c73a2c", "b": "#a52f24", "rough": 0.6, "pat": "plain", "scale": 4.0, "amt": 0.1, "world": true },
	"cable": { "a": "#1a1a1a", "b": "#121212", "rough": 0.7, "pat": "plain", "scale": 4.0, "amt": 0.1, "world": true },
	"window_dark": { "a": "#20262a", "b": "#2d3a40", "rough": 0.12, "spec": 0.9, "pat": "plain", "scale": 1.5, "amt": 0.4, "world": true },
	"window_frame": { "a": "#dcdad5", "b": "#c8c5be", "rough": 0.6, "pat": "plain", "scale": 3.0, "amt": 0.1, "world": true },
	"roof_membrane": { "a": "#3a4350", "b": "#333b47", "c": "#55606c", "rough": 0.9, "pat": "membrane", "scale": 3.0, "amt": 0.5, "world": true },
	"parapet_cap": { "a": "#cfd3d6", "b": "#b9bec2", "rough": 0.5, "metal": 0.4, "pat": "plain", "scale": 2.0, "amt": 0.2, "world": true },
	"siding_grey": { "a": "#4f5a66", "b": "#46505b", "rough": 0.7, "pat": "siding", "scale": 0.22, "amt": 0.3, "world": true },
	"siding_light": { "a": "#9aa2a8", "b": "#8a9298", "rough": 0.7, "pat": "siding", "scale": 0.22, "amt": 0.3, "world": true },
	"stucco_beige": { "a": "#d8c49a", "b": "#ccb68a", "c": "#c2ab80", "rough": 0.95, "pat": "plaster", "scale": 0.3, "amt": 0.04, "world": true },
	"brick_tan": { "a": "#d8c5a0", "b": "#ccb791", "c": "#bfae8c", "rough": 0.95, "pat": "blocks", "scale": 0.09, "amt": 0.2, "world": true },
	"brick_red": { "a": "#8a4a3a", "b": "#76402f", "c": "#b0a594", "rough": 0.95, "pat": "blocks", "scale": 0.09, "amt": 0.3, "world": true },
	"concrete": { "a": "#a7a49c", "b": "#959189", "c": "#76736c", "rough": 0.92, "pat": "concrete", "scale": 3.0, "amt": 0.4, "world": true },
	"concrete_light": { "a": "#c3c0b8", "b": "#b2aea5", "c": "#8f8b83", "rough": 0.92, "pat": "concrete", "scale": 1.6, "amt": 0.3, "world": true },
	"asphalt": { "a": "#4a4c4e", "b": "#3c3e40", "c": "#2c2d2f", "rough": 0.95, "pat": "asphalt", "scale": 0.4, "amt": 0.5, "world": true },
	"asphalt_lot": { "a": "#7f8081", "b": "#6c6d6e", "c": "#5a5b5c", "rough": 0.95, "pat": "asphalt", "scale": 0.4, "amt": 0.4, "world": true },
	"grass": { "a": "#8a9558", "b": "#76844a", "c": "#9a9468", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.45, "world": true },
	"hedge": { "a": "#3f5f2a", "b": "#2c4620", "c": "#4d6a32", "rough": 1.0, "pat": "grass", "scale": 2.0, "amt": 0.3, "world": true },
	"foliage": { "a": "#4f7a2e", "b": "#355a22", "c": "#6a8a3a", "rough": 1.0, "pat": "grass", "scale": 1.2, "amt": 0.3, "world": true },
	"hvac_metal": { "a": "#8c9296", "b": "#767c80", "rough": 0.5, "metal": 0.6, "pat": "brushed", "scale": 40.0, "amt": 0.2, "axis": [0, 1, 0], "world": true },
	"fan_metal": { "a": "#6d7378", "b": "#5c6267", "rough": 0.62, "metal": 0.3, "pat": "brushed", "scale": 30.0, "amt": 0.2, "axis": [0, 1, 0], "world": true },
	"hvac_dark": { "a": "#4a5056", "b": "#3c4248", "rough": 0.5, "metal": 0.6, "pat": "plain", "scale": 6.0, "amt": 0.2, "world": true },
	"car_paint": { "a": "#2a2d33", "b": "#202328", "rough": 0.25, "metal": 0.6, "pat": "plain", "scale": 2.0, "amt": 0.1, "world": true },
	"tyre": { "a": "#1a1a1b", "b": "#141415", "rough": 0.9, "pat": "plain", "scale": 4.0, "amt": 0.1, "world": true },
	"barrier": { "a": "#ff00ff", "b": "#ff00ff", "rough": 1.0, "pat": "plain", "scale": 1.0, "amt": 0.0, "world": true },
}

static var _cache := {}          # role -> ShaderMaterial
static var _std := {}            # role -> StandardMaterial3D
static var _warned := {}


static func has(role: String) -> bool:
	return ROLES.has(_base(role))


## "car_paint:#8a1e22" overrides the first colour (a, and b a step darker):
## one role, many paint jobs.
static func _base(role: String) -> String:
	var i := role.find(":")
	return role if i < 0 else role.substr(0, i)


static func _spec(role: String) -> Dictionary:
	var base := _base(role)
	if not ROLES.has(base):
		if not _warned.has(base):
			_warned[base] = true
			push_warning("GKMaterials: unknown role '%s' (magenta)" % base)
		return { "a": "#ff00ff", "b": "#ff00ff", "rough": 1.0, "pat": "plain" }
	var s: Dictionary = (ROLES[base] as Dictionary).duplicate()
	var i := role.find(":")
	if i >= 0:
		var c := Color(role.substr(i + 1))
		s["a"] = c.to_html(false)
		s["b"] = c.darkened(0.15).to_html(false)
	return s


static func get_material(role: String) -> Material:
	if _cache.has(role):
		return _cache[role]
	var s := _spec(role)
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("col_a", Color(str(s.a)))
	m.set_shader_parameter("col_b", Color(str(s.get("b", s.a))))
	m.set_shader_parameter("col_c", Color(str(s.get("c", s.get("b", s.a)))))
	m.set_shader_parameter("rough", float(s.get("rough", 0.8)))
	m.set_shader_parameter("metal", float(s.get("metal", 0.0)))
	m.set_shader_parameter("spec", float(s.get("spec", 0.5)))
	m.set_shader_parameter("pat", int(PAT.get(str(s.get("pat", "plain")), 0)))
	m.set_shader_parameter("scale", float(s.get("scale", 1.0)))
	m.set_shader_parameter("amt", float(s.get("amt", 0.2)))
	m.set_shader_parameter("wear", float(s.get("wear", 0.0)))
	m.set_shader_parameter("world", bool(s.get("world", false)))
	var ax: Array = s.get("axis", [0, 0, 1])
	m.set_shader_parameter("axis", Vector3(float(ax[0]), float(ax[1]), float(ax[2])))
	_cache[role] = m
	return m


## A plain PBR stand-in (colour, roughness, metallic): what a .glb carries
## to tools that don't run Godot shaders.
static func standard(role: String) -> StandardMaterial3D:
	if _std.has(role):
		return _std[role]
	var s := _spec(role)
	var m := StandardMaterial3D.new()
	m.resource_name = role
	m.albedo_color = Color(str(s.a))
	m.roughness = float(s.get("rough", 0.8))
	m.metallic = float(s.get("metal", 0.0))
	m.vertex_color_use_as_albedo = true
	_std[role] = m
	return m


## Material every surface of `mi` by its surface name.
static func apply(mi: MeshInstance3D, plain := false) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var role := ""
		if mesh is ArrayMesh:
			role = (mesh as ArrayMesh).surface_get_name(i)
		mi.set_surface_override_material(i, standard(role) if plain else get_material(role))
