class_name ExtractChest
extends StaticBody3D
## Extraction's chest: a kit-built strongbox (a planked body, iron bands, a
## lid that swings up on a tween when you F it within FpsTune.chest_range).
## Contents roll once, by tier (ExtractLoot.roll_chest), from the world's
## seeded rng; `opened` hands them over. Tier 3 boxes carry a brass clasp
## so a deep find reads as one.

signal opened(items: Array)

const SIZE := Vector3(0.9, 0.5, 0.55)

var tier := 1
var is_open := false
var _lid: MeshInstance3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var band := "iron_dark" if tier < 3 else "brass"
	var body := GKMesh.new()
	body.box("wood_old", Vector3(0, SIZE.y * 0.5 * 0.7, 0), Vector3(SIZE.x, SIZE.y * 0.7, SIZE.z), 0.012)
	for x in [-0.3, 0.3]:
		body.box(band, Vector3(x, SIZE.y * 0.35, 0), Vector3(0.05, SIZE.y * 0.72, SIZE.z + 0.02))
	var mi := MeshInstance3D.new()
	mi.mesh = body.commit()
	GKMaterials.apply(mi)
	add_child(mi)
	# the lid hinges on the back edge: its mesh is built with the hinge at origin
	var lid := GKMesh.new()
	var lh := SIZE.y * 0.3
	lid.box("wood_old", Vector3(0, lh * 0.5, SIZE.z * 0.5), Vector3(SIZE.x, lh, SIZE.z), 0.012)
	for x in [-0.3, 0.3]:
		lid.box(band, Vector3(x, lh * 0.5, SIZE.z * 0.5), Vector3(0.05, lh + 0.02, SIZE.z + 0.02))
	lid.box(band, Vector3(0, lh * 0.3, SIZE.z - 0.01), Vector3(0.1, 0.1, 0.03))
	_lid = MeshInstance3D.new()
	_lid.mesh = lid.commit()
	GKMaterials.apply(_lid)
	_lid.position = Vector3(0, SIZE.y * 0.7, -SIZE.z * 0.5)
	add_child(_lid)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = SIZE
	cs.shape = bs
	cs.position.y = SIZE.y * 0.5
	add_child(cs)


## The lid swings up over 0.5 s; the roll happens at once.
func open(rng: RandomNumberGenerator) -> Array:
	if is_open:
		return []
	is_open = true
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_lid, "rotation:x", -deg_to_rad(105.0), 0.5)
	var items := ExtractLoot.roll_chest(tier, rng)
	opened.emit(items)
	return items


func prompt() -> String:
	return "Open chest" if not is_open else ""
