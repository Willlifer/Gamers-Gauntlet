class_name MobaLook
extends RefCounted
## Dressing for the MOBA: Black | White's rigs in colour. Champions get their
## tint on clothes and weapon, a paler wash on the body, their own hair
## colour, and the inked outlines stay black. Minions and the dummy wear
## their team's colour.

const BLUE := Color("#3a7bd5")
const RED := Color("#d64545")
const SELF := Color("#3fcf5a")


static func champ_unit(id: String, team: String) -> BWUnit:
	var c: Dictionary = MobaChamps.CHAMPS[id]
	var u := BWUnit.new()
	u.id = "%s_%s" % [team, id]
	u.name = str(c.name)
	u.team = "player" if team == "blue" else "enemy"
	u.element = ""
	u.weapon_class = str(c.weapon)
	u.weapon_model = str(c.weapon_model)
	u.cosmetics = { "hair_style": str(c.hair_style), "hair_hex": str(c.hair_hex), "gender": str(c.gender),
		"top": str(c.top), "bottom": str(c.bottom), "clothing_shade": "light" }
	for s in BWUnit.STATS:
		u.stats[s] = 5
	u.hp = u.max_hp()
	return u


static func minion_unit(role: String, team: String, id: String) -> BWUnit:
	var u := BWUnit.new()
	u.id = id
	u.name = role.capitalize()
	u.team = "player" if team == "blue" else "enemy"
	u.weapon_class = "staff" if role == "caster" else "sword"
	u.weapon_model = "staff" if role == "caster" else "hatchet"
	u.cosmetics = { "hair_style": "none", "top": "tshirt", "bottom": "tight_pants", "clothing_shade": "light", "gender": "a" }
	for s in BWUnit.STATS:
		u.stats[s] = 3
	u.hp = u.max_hp()
	return u


static func dummy_unit(id: String) -> BWUnit:
	var u := minion_unit("melee", "red", id)
	u.name = "Dummy"
	u.weapon_model = "anchor"
	u.weapon_class = "axe"
	return u


## Colour a built character: `col` on clothes, armour and weapon, a lighter
## wash on skin, hair to `hair` (if given). Outlines (black) stay black.
static func tint(ch: BWCharacter, col: Color, hair: Color = Color(0, 0, 0, 0)) -> void:
	_walk(ch, col)
	if ch.hair and hair.a > 0.0:
		ch.hair.set_color(hair)


static func _walk(n: Node, col: Color) -> void:
	if n is GeometryInstance3D and not n is Label3D:
		var path := _shader_path(n as GeometryInstance3D)
		var t := col
		if path.contains("hair"):
			t = Color.WHITE
		elif path.contains("clothing") or path.contains("equipment") or path.contains("weapon"):
			t = col.lerp(Color.WHITE, 0.15)
		else:
			t = col.lerp(Color.WHITE, 0.6)             # skin: a pale wash, still mostly white
		(n as GeometryInstance3D).set_instance_shader_parameter("tint", t)
	for c in n.get_children():
		_walk(c, col)


static func _shader_path(g: GeometryInstance3D) -> String:
	var m: Material = g.material_override
	if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (g as MeshInstance3D).get_active_material(0)
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		return (m as ShaderMaterial).shader.resource_path
	return ""


static func team_color(team: String) -> Color:
	return BLUE if team == "blue" else RED


## A champion figure on its own little stage (select screen, portraits).
static func stage(parent: Control, id: String, size: Vector2) -> Dictionary:
	var u := champ_unit(id, "blue")
	var st := TourneyUI.stage(parent, u, size, true, Color(0.16, 0.17, 0.22))
	var view: BWUnitView = st.view
	if view.character:
		tint(view.character, Color(str(MobaChamps.CHAMPS[id].tint)), Color(str(MobaChamps.CHAMPS[id].hair_hex)))
	return st
