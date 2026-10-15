class_name MmoMoves
extends RefCounted
## The Giant's spell animations (G22), keyed in Black | White's pose space
## and laid over its clips through BWCharacterPose.override (the legs keep
## walking the clip; hands, spine and head follow these keys). Root frame:
## +Z forward, +Y up, +X the Giant's left; origin at the chest pivot.
## Hand keys: pos, aim (up the anchor's shaft), edge, pole (the elbow), grip
## (1 = the left fist on the shaft, 0 = free).
##
##   upheaval  heave the anchor overhead, hold it trembling, drive it down
##   meteors   plant the anchor, raise the left hand to the sky; at the end
##             the hand comes down pointing (the rain)
##   bombs     scoop low with the left hand, then fling it up and out
##   gather    lift the anchor upright, then plant it head-first: a roar

const EASE_IN := 0.22
const EASE_OUT := 0.35

const PR := Vector3(-1.0, -0.4, -0.3)
const PL := Vector3(1.0, -0.4, -0.3)


static func _h(pos: Vector3, aim: Vector3, edge: Vector3, pole: Vector3, grip := 1.0) -> Dictionary:
	return { "pos": pos, "aim": aim.normalized(), "edge": edge.normalized(), "pole": pole, "frame": "root", "grip": grip }


static func _free(pos: Vector3, pole: Vector3) -> Dictionary:
	return { "pos": pos, "pole": pole, "frame": "root", "grip": 0.0 }


static var _moves := {}


static func moves() -> Dictionary:
	if not _moves.is_empty():
		return _moves
	var ready_r := _h(Vector3(0, -0.05, 0.42), Vector3(0, 0.8, 0.6), Vector3(0, 0.6, -0.8), PR)
	var lift_r := _h(Vector3(0, 0.64, 0.02), Vector3(0, 0.35, -0.94), Vector3(0, 0.94, 0.35), Vector3(-1, 0.2, -0.2))
	var slam_r := _h(Vector3(0, -0.36, 0.66), Vector3(0, -0.6, 0.8), Vector3(0, 0.8, 0.6), PR)
	var both_l := { "pos": Vector3(0.1, 0, 0.4), "pole": PL, "frame": "root", "grip": 1.0 }
	_moves["upheaval"] = { "len": 3.0, "keys": [
		[0.0, { "hand_r": ready_r, "hand_l": both_l, "chest": Vector3(0.1, 0, 0), "spine": Vector3(0.05, 0, 0), "head": Vector3(0, 0, 0), "root": Vector3(0, -0.06, 0) }],
		[0.75, { "hand_r": lift_r, "hand_l": both_l, "chest": Vector3(-0.32, 0, 0), "spine": Vector3(-0.14, 0, 0), "head": Vector3(-0.28, 0, 0), "root": Vector3(0, 0.02, -0.05) }],
		[1.9, { "hand_r": _h(Vector3(0, 0.7, -0.02), Vector3(0, 0.3, -0.95), Vector3(0, 0.95, 0.3), Vector3(-1, 0.2, -0.2)), "hand_l": both_l,
			"chest": Vector3(-0.38, 0, 0), "spine": Vector3(-0.16, 0, 0), "head": Vector3(-0.32, 0, 0), "root": Vector3(0, 0.03, -0.06) }],
		[2.08, { "hand_r": slam_r, "hand_l": both_l, "chest": Vector3(0.52, 0, 0), "spine": Vector3(0.3, 0, 0), "head": Vector3(0.1, 0, 0), "root": Vector3(0, -0.3, 0.14) }],
		[2.75, { "hand_r": slam_r, "hand_l": both_l, "chest": Vector3(0.48, 0, 0), "spine": Vector3(0.28, 0, 0), "head": Vector3(-0.05, 0, 0), "root": Vector3(0, -0.27, 0.12) }],
	] }
	var plant_r := _h(Vector3(-0.46, -0.06, 0.32), Vector3(-0.1, -1.0, 0.12), Vector3(0, 0.12, 1), PR, 0.0)      # the anchor planted, flukes down
	_moves["meteors"] = { "len": 5.8, "keys": [
		[0.0, { "hand_r": plant_r, "hand_l": _free(Vector3(0.28, -0.3, 0.2), PL), "chest": Vector3(0, 0, 0), "head": Vector3(0, 0, 0), "spine": Vector3(0, 0, 0) }],
		[0.7, { "hand_r": plant_r, "hand_l": _free(Vector3(0.3, 1.2, 0.02), Vector3(1, 0, -0.5)), "chest": Vector3(-0.24, -0.3, 0.12),
			"head": Vector3(-0.5, 0.1, 0), "spine": Vector3(-0.1, 0, 0), "arm_stretch": 0.15 }],
		[4.9, { "hand_r": plant_r, "hand_l": _free(Vector3(0.28, 1.24, 0.0), Vector3(1, 0, -0.5)), "chest": Vector3(-0.3, -0.32, 0.14),
			"head": Vector3(-0.56, 0.1, 0), "spine": Vector3(-0.14, 0, 0), "arm_stretch": 0.15 }],
		[5.25, { "hand_r": plant_r, "hand_l": _free(Vector3(0.22, 0.32, 0.78), Vector3(1, -0.4, -0.3)), "chest": Vector3(0.22, 0.1, 0),
			"head": Vector3(0.05, 0, 0), "spine": Vector3(0.08, 0, 0) }],
		[5.8, { "hand_r": plant_r, "hand_l": _free(Vector3(0.24, 0.26, 0.72), Vector3(1, -0.4, -0.3)), "chest": Vector3(0.18, 0.1, 0),
			"head": Vector3(0.0, 0, 0), "spine": Vector3(0.06, 0, 0) }],
	] }
	var low_r := plant_r
	_moves["bombs"] = { "len": 2.2, "keys": [
		[0.0, { "hand_r": low_r, "hand_l": _free(Vector3(0.26, -0.2, 0.3), PL), "chest": Vector3(0, 0, 0), "head": Vector3(0, 0, 0), "root": Vector3(0, -0.04, 0) }],
		[0.45, { "hand_r": low_r, "hand_l": _free(Vector3(0.5, -0.55, 0.45), Vector3(1, -0.2, -0.6)), "chest": Vector3(0.6, -0.2, 0),
			"spine": Vector3(0.35, -0.1, 0), "head": Vector3(0.1, -0.1, 0), "root": Vector3(0, -0.36, 0.08) }],
		[0.85, { "hand_r": low_r, "hand_l": _free(Vector3(-0.1, -0.6, 0.6), Vector3(1, -0.2, -0.6)), "chest": Vector3(0.62, 0.35, 0),
			"spine": Vector3(0.36, 0.14, 0), "head": Vector3(0.1, 0.1, 0), "root": Vector3(0, -0.38, 0.08) }],
		[1.25, { "hand_r": low_r, "hand_l": _free(Vector3(0.46, 1.1, 0.5), Vector3(1, -0.3, -0.4)), "arm_stretch": 0.15, "chest": Vector3(-0.28, -0.36, 0),
			"spine": Vector3(-0.12, -0.12, 0), "head": Vector3(-0.38, -0.1, 0), "root": Vector3(0, 0.04, -0.02) }],
		[2.2, { "hand_r": low_r, "hand_l": _free(Vector3(0.4, 0.84, 0.58), Vector3(1, -0.3, -0.4)), "arm_stretch": 0.0, "chest": Vector3(-0.22, -0.3, 0),
			"spine": Vector3(-0.1, -0.1, 0), "head": Vector3(-0.3, -0.1, 0), "root": Vector3(0, 0.02, 0) }],
	] }
	var up_r := _h(Vector3(0, 0.66, 0.32), Vector3(0, 1, 0.08), Vector3(0, 0, 1), Vector3(-1, -0.2, -0.4))
	var plant_down := _h(Vector3(0, -0.04, 0.6), Vector3(0, -1.0, 0.06), Vector3(0, 0.06, 1.0), PR)      # straight down into the stone
	_moves["gather"] = { "len": 2.6, "keys": [
		[0.0, { "hand_r": ready_r, "hand_l": both_l, "chest": Vector3(0.05, 0, 0), "head": Vector3(0, 0, 0), "root": Vector3(0, -0.05, 0) }],
		[0.85, { "hand_r": up_r, "hand_l": both_l, "chest": Vector3(-0.26, 0, 0), "spine": Vector3(-0.1, 0, 0), "head": Vector3(-0.42, 0, 0), "root": Vector3(0, 0.04, 0) }],
		[1.55, { "hand_r": up_r, "hand_l": both_l, "chest": Vector3(-0.3, 0, 0), "spine": Vector3(-0.12, 0, 0), "head": Vector3(-0.5, 0, 0), "root": Vector3(0, 0.05, 0) }],
		[1.75, { "hand_r": plant_down, "hand_l": both_l, "chest": Vector3(0.46, 0, 0), "spine": Vector3(0.26, 0, 0), "head": Vector3(-0.3, 0, 0), "root": Vector3(0, -0.32, 0.1) }],
		[2.6, { "hand_r": plant_down, "hand_l": both_l, "chest": Vector3(0.42, 0, 0), "spine": Vector3(0.24, 0, 0), "head": Vector3(-0.45, 0, 0), "root": Vector3(0, -0.3, 0.1) }],
	] }
	return _moves


static func length(id: String) -> float:
	return float(moves().get(id, {}).get("len", 0.0))


## The override at `t` seconds into move `id` (smoothstep between keys),
## with a small tremble where the Giant strains.
static func sample(id: String, t: float) -> Dictionary:
	var m: Dictionary = moves().get(id, {})
	if m.is_empty():
		return {}
	var keys: Array = m.keys
	var a: Array = keys[0]
	var b: Array = keys[0]
	for i in keys.size():
		if float(keys[i][0]) <= t:
			a = keys[i]
			b = keys[mini(i + 1, keys.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var f := 1.0 if span <= 0.0 else clampf((t - float(a[0])) / span, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var out := BWCharacterPose._mix(a[1], b[1], f)
	var shake := 0.0
	if id == "upheaval" and t > 0.8 and t < 1.95:
		shake = 0.012
	elif id == "meteors" and t > 0.7 and t < 4.9:
		shake = 0.01
	if shake > 0.0:
		var j := Vector3(sin(t * 47.0), sin(t * 39.0 + 1.0), 0) * shake
		for k: String in ["hand_r", "hand_l"]:
			if out.has(k):
				var h: Dictionary = (out[k] as Dictionary).duplicate()
				h.pos = (h.pos as Vector3) + j
				out[k] = h
	return out


static func weight(id: String, t: float) -> float:
	var len_ := length(id)
	if len_ <= 0.0:
		return 0.0
	return clampf(minf(t / EASE_IN, (len_ - t) / EASE_OUT), 0.0, 1.0)
