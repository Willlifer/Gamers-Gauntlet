class_name MobaDress
extends RefCounted
## The champions' outfits, gaits and cast gestures (G55). Equipment is
## Black | White's armour pieces (BWEquipmentView, res://art/equipment):
## one piece per slot through the unit (so the layering pass hides what a
## robe covers), plus "extra" pieces worn over them. Colours ride on
## MobaLook.tint; here a piece can take its own tint and the gun its own
## colour. Animations: GGAnim.
##
##   u.equipment = MobaDress.equipment("merr")      # MobaLook.champ_unit
##   MobaDress.dress(ch, "merr")                    # after MobaLook.tint
##   ch.pose(MobaDress.cast_pose(ch, "merr", "q"))  # the view, on a cast
##   MobaDress.ghost(ch, true)                      # Temu hidden (his own side's view)

## Per champion:
##   armour   slot -> [piece id, accent element] (the unit's equipment)
##   extra    [piece id, accent element, tint?]: worn over the slotted pieces
##   gear     tint for the armour pieces (null: the champion's own tint)
##   clothes  tint for the clothes, skin wash and weapon (null: own tint)
##   weapon   a colour for the weapon alone (null: tinted like the clothes)
##   gait     GGAnim locomotion: "float", "skip", "cool"
##   casts    ability slot -> GGAnim cast gesture
const DRESS := {
	"merr": {
		# a mage: the pointed hat and a long silk robe, a mantle (scarf) at
		# the shoulders; a deeper emerald robe over his lime, embers on the trim
		"armour": { "head": ["wizard_hat", "fire"], "chest": ["silken_robe", "fire"] },
		"extra": [["scarf", "fire"]],
		"gear": "#2f9a6a", "clothes": "#93d957", "weapon": null,
		"gait": "float",
		"casts": { "q": "thrust", "w": "slam", "e": "flick", "r": "thrust" },
	},
	"temu": {
		# a ranger: his hoodie is the hood; a feathered leather cap, the
		# quiver's strap across the chest, leather tassets at the hips
		"armour": { "head": ["feathered_cap", "wind"], "chest": ["bandolier", ""], "legs": ["leather_tassets", ""] },
		"extra": [],
		"gear": "#8a6342", "clothes": null, "weapon": null,
		"gait": "skip",
		"casts": { "q": "shoot", "w": "rally", "e": "flick", "r": "toss" },
	},
	"braves": {
		# ranger / tank: a pauldron on the gun side, a bandolier of shells,
		# heavy plated legs; his flintlock steel grey
		"armour": { "chest": ["single_shoulder_guard", ""], "legs": ["platelegs", ""] },
		"extra": [["bandolier", "fire", "#6e4a2c"]],
		"gear": "#6c7078", "clothes": null, "weapon": "#9aa2ab",
		"gait": "cool",
		"casts": { "q": "shoot", "w": "toss", "e": "rally", "r": "blast" },
	},
}
## Summoner spells (any champion).
const SPELL_CASTS := { "flash": "flick", "ignite": "flick", "smite": "slam" }
## Temu hidden, as his own side sees him: 75% transparent (the author, 10-16).
const GHOST := 0.75


## The unit's armour slots for BWCharacter (BWRun.make_item's shape; the
## accent rides on "imbue", BWRun.item_element).
static func equipment(id: String) -> Dictionary:
	var out := {}
	var d: Dictionary = DRESS.get(id, {})
	var arm: Dictionary = d.get("armour", {})
	for slot in arm:
		out[slot] = { "base": str(arm[slot][0]), "slot": slot, "imbue": str(arm[slot][1]) }
	return out


## Finish a built, tinted champion: the extra pieces, the gear / clothes /
## weapon colours, the gait and the cast clips.
static func dress(ch: BWCharacter, id: String) -> void:
	var d: Dictionary = DRESS.get(id, {})
	if ch == null or d.is_empty():
		return
	var extras: Array = []
	for e in d.get("extra", []):
		extras.append([_wear_extra(ch, str(e[0]), str(e[1])), e[2] if (e as Array).size() > 2 else null])
	if d.get("clothes") != null:
		MobaLook._walk(ch, Color(str(d.clothes)))
		var c: Dictionary = MobaChamps.CHAMPS.get(id, {})
		if ch.hair and c.has("hair_hex"):
			ch.hair.set_color(Color(str(c.hair_hex)))
	_paint(ch, "equipment", Color(str(d.gear)) if d.get("gear") != null else Color(0, 0, 0, 0))
	for x in extras:
		if x[0] != null and x[1] != null:
			_paint(x[0], "equipment", Color(str(x[1])))
	if d.get("weapon") != null and ch.weapon:
		_tint_all(ch.weapon, Color(str(d.weapon)))
	GGAnim.install(ch, str(d.get("gait", "")))
	ch.set_meta("moba_dress", id)


## A cast's pose name for this champion's ability slot.
static func cast_pose(ch: BWCharacter, id: String, slot: String) -> String:
	var kind := str(SPELL_CASTS.get(slot, (DRESS.get(id, {}) as Dictionary).get("casts", {}).get(slot, "thrust")))
	var clip := GGAnim.cast_clip(kind)
	if ch and ch.has_clip(clip):
		return clip
	return "cast" if ch and ch.has_clip("cast") else "strike"


## Temu hidden: the whole figure see-through (GeometryInstance3D.transparency,
## so every shader and the outline hulls fade alike).
static func ghost(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = GHOST if on else 0.0
	for c in n.get_children():
		ghost(c, on)


# ------------------------------------------------------------------ parts

## A second piece over the slotted ones (B/W wears one per slot): attached
## exactly as BWEquipmentView does (socket pieces on their socket, skinned
## pieces rebound to the rig's skeleton by bone name).
static func _wear_extra(ch: BWCharacter, base_id: String, element: String) -> Node3D:
	var row := BWEquipmentView.info(base_id)
	if row.is_empty() or ch.rig == null:
		return null
	var root := BWEquipmentView.instantiate(base_id, element)
	if root == null:
		return null
	root.name = "extra_" + base_id
	if str(row.get("attach", "")) == "socket":
		if not ch.rig.attach(root, str(row.socket)):
			root.free()
			return null
		return root
	var mis := BWEquipmentView.meshes_of(root)
	if mis.is_empty() or (mis[0] as MeshInstance3D).skin == null:
		root.free()
		return null
	var mi: MeshInstance3D = mis[0]
	var skin := mi.skin
	mi.get_parent().remove_child(mi)
	mi.owner = null
	root.free()
	mi.name = "extra_" + base_id
	ch.rig.skeleton.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	mi.skin = skin
	mi.skeleton = NodePath("..")
	return mi


## Retint every part drawn with a shader whose path contains `kind`
## (a = 0: leave them as tinted).
static func _paint(n: Node, kind: String, col: Color) -> void:
	if col.a <= 0.0:
		return
	if n is GeometryInstance3D and MobaLook._shader_path(n as GeometryInstance3D).contains(kind):
		(n as GeometryInstance3D).set_instance_shader_parameter("tint", col)
	for c in n.get_children():
		_paint(c, kind, col)


static func _tint_all(n: Node, col: Color) -> void:
	if n is GeometryInstance3D and not n is Label3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("tint", col)
	for c in n.get_children():
		_tint_all(c, col)
