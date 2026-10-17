class_name FpsMapPolish
extends RefCounted
## G62: play polish laid on top of the three duel maps at match start, one
## fix each, without touching the kit's map builders (the author likes the
## maps as they are). Boxes in kit materials with their own colliders,
## added under the level before the navigation mesh bakes, so the bot
## paths round them like anything else.
##   rooftop   a louvred plant screen court-side of each roof's spawn row:
##             you could be seen (and shot) at your spawn from the far
##             roof's court edge the moment the loadout closed. 2.2 m, so it
##             hides a standing player; step round either end.
##   dust_mid  the left wall ran open 65 m from the tower end to the A
##             pockets' exit (the longest line on the map; every step out
##             of the left pocket was under the tower's gun). A two-crate
##             stack (2.6 m) by the left wall at plan z 9 cuts it.
##   campus    each spawn stood in the open, seen from 360 far floor points
##             (the road is the open lane by design; the spawns needn't be).
##             A tall bunker wall 4.5 m field-side of each spawn.

## map id -> boxes: [role, centre (world m), size (world m), yaw (rad)]
const PIECES := {
	"rooftop": [
		# roof B (east, spawn x 53.75, z -15..-9 world): the screen 7 m court-side of the row; roof A mirrored
		["hvac_metal", Vector3(46.75, 25.1, -11.75), Vector3(0.3, 2.2, 11.0), 0.0],
		["hvac_metal", Vector3(-46.75, 25.1, -11.75), Vector3(0.3, 2.2, 11.0), 0.0],
	],
	"dust_mid": [
		# the left wall ran open 65 m from the tower end to the A pockets' exit (plan x -5..-3):
		# a two-crate stack at plan (-3.3, 9) cuts it, leaving a 1.3 m squeeze at the wall
		["wood_old", Vector3(-4.1, 1.3, -11.25), Vector3(2.0, 2.6, 1.5), 0.06],
	],
	"campus": [
		# each spawn stood in the open (seen from 360 far floor points): a tall bunker wall
		# 4.5 m field-side of each, across the spawn's line to the field; step round either end
		["sign_red", Vector3(-46.5, 1.1, 5.0), Vector3(1.2, 2.2, 9.0), 0.0],
		["sign_red", Vector3(46.5, 1.1, 5.0), Vector3(1.2, 2.2, 9.0), 0.0],
	],
}


## Builds the map's pieces under `parent` (meshes and one StaticBody3D on
## the level's layer). Returns how many it placed.
static func apply(map_id: String, parent: Node3D) -> int:
	var pieces: Array = PIECES.get(map_id, [])
	if pieces.is_empty():
		return 0
	var root := Node3D.new()
	root.name = "Polish"
	parent.add_child(root)
	var body := StaticBody3D.new()
	body.name = "PolishCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for p in pieces:
		var role := str(p[0])
		var c: Vector3 = p[1]
		var size: Vector3 = p[2]
		var b := Basis(Vector3.UP, float(p[3]))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = GKMaterials.get_material(role)
		mi.transform = Transform3D(b, c)
		root.add_child(mi)
		# louvres on the screens: dark slats across the face
		if role == "hvac_metal" and size.y > 1.5:
			var n := int(size.y / 0.25)
			for k in n:
				var slat := MeshInstance3D.new()
				var sm := BoxMesh.new()
				sm.size = Vector3(size.x + 0.06, 0.04, size.z - 0.2)
				slat.mesh = sm
				slat.material_override = GKMaterials.get_material("hvac_dark")
				slat.transform = Transform3D(b, c + Vector3(0, -size.y * 0.5 + 0.2 + k * 0.25, 0))
				root.add_child(slat)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = Transform3D(b, c)
		body.add_child(cs)
	return pieces.size()
