class_name GKBWHold
extends RefCounted
## The kit's posing adapter for Black | White characters (the only kit file
## that knows BWCharacter; the rest of the kit runs in any Godot game).
##
##   var gun := GKBWHold.swap_weapon(ch, GKRegistry.build("sniper"))   # in hand
##   GKBWHold.hold_rifle(ch, gun_asset, "aim")                          # shouldered, sighting
##   GKBWHold.hold_rifle(ch, gun_asset, "low")                          # low ready (walking)
##   GKBWHold.release(ch)                                               # back to the clips' hands
##
## A kit item hangs on the socket its meta names (items are modelled in the
## same weapon frame as Black | White's: grip at the fist, +Z forward). The
## character's own weapon is hidden, not freed, so its clip set keeps
## animating the body. Rifle holds go through BWCharacterPose.override: the
## clips still walk the legs and the torso, the hands hold the rifle.

const SHOULDER_R := Vector3(-0.15, 0.43, 0.04)   ## the right shoulder pocket, root frame (2.2 m rig)


static func swap_weapon(ch: BWCharacter, a: GKAsset) -> Node3D:
	if ch == null or a == null or ch.rig == null:
		return null
	if ch.weapon:
		ch.weapon.visible = false
	var old: Node3D = ch.get_meta("gk_item") if ch.has_meta("gk_item") else null
	if old and is_instance_valid(old):
		old.queue_free()
	var node := a.instantiate(false)
	node.name = "GKItem"
	if not ch.rig.attach(node, str(a.meta.get("socket", "socket_weapon_r"))):
		node.free()
		return null
	node.transform = Transform3D.IDENTITY
	ch.set_meta("gk_item", node)
	return node


## Two hands on a long gun: the right on the grip, the left on the support
## marker. "aim": the butt in the shoulder, the barrel level; "low": the
## muzzle dipped, the gun across the body.
static func hold_rifle(ch: BWCharacter, a: GKAsset, stance := "aim", pitch := 0.0) -> void:
	if ch == null or ch.poser == null:
		return
	var butt := a.marker("butt").origin
	var support := a.marker("support").origin
	var meta := { "class": str(a.meta.get("class", "rifle")), "hands": "two",
		"second_hand": { "hand": "l", "point": [support.x, support.y, support.z] }, "length": float(a.meta.get("length", 1.0)) }
	ch.poser.has_second = true
	ch.poser.second_point = support
	ch.poser.hold_hand = "r"
	var dir := Vector3(0, sin(pitch), cos(pitch)) if stance == "aim" else Vector3(0.35, -0.55, 0.76).normalized()
	var up := Vector3(0, cos(pitch), -sin(pitch)) if stance == "aim" else Vector3(0.1, 0.8, 0.55).normalized()
	var b := Basis(up.cross(dir).normalized(), up, dir)
	var shoulder := SHOULDER_R if stance == "aim" else SHOULDER_R + Vector3(0.06, -0.2, 0.08)
	var grip := shoulder - b * butt
	# the pose solver takes the two-hander's hand position as the fists' midpoint
	var mid := grip + b * support * 0.5
	ch.poser.override = {
		"hand_r": { "pos": mid, "aim": up, "edge": dir, "pole": Vector3(-1.0, -0.6, -0.2), "frame": "root" },
		"hand_l": { "pos": mid, "pole": Vector3(0.8, -1.0, 0.1), "frame": "root", "grip": 1.0 },
		"flat": 0.0,
	}
	ch.set_meta("gk_meta", meta)


static func release(ch: BWCharacter) -> void:
	if ch and ch.poser:
		ch.poser.override = {}
