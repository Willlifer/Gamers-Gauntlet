class_name ExtractLoot
extends RefCounted
## Extraction's loot: the tables a chest rolls from (by tier), what a dead
## guard leaves, and the pickup on the ground (ExtractLoot.Pickup: a bag or
## a dropped gun you F). An item is { kind, id, caliber, amount, value }:
##   gun      id a FpsWeapons gun (variants once FpsWeapons.VARIANTS lands);
##            `amount` rounds in it
##   mag      one magazine of `caliber` (rifle / shotgun / pistol): the most common roll
##   medkit   heal FpsTune.medkit_heal over 4 s (one carried)
##   armour   one piece: FpsTune.armour_cut off every hit until it has soaked 100
##   money    $amount
## Everything a run holds at the end is worth its `value` ($) for the verdict.

const CALIBERS := ["rifle", "shotgun", "pistol"]
## Pistol-calibre guns ride on the hip; the rest are primaries.
const PRIMARY_CALIBERS := ["rifle", "shotgun"]

## Rolls per tier: how many items, and the weights of each kind.
const TIER := {
	1: { "n": [1, 2], "w": { "mag": 5.0, "money": 3.0, "medkit": 1.5, "armour": 0.5, "gun": 1.0 }, "money": [50, 150] },
	2: { "n": [1, 3], "w": { "mag": 4.0, "money": 3.0, "medkit": 1.5, "armour": 1.0, "gun": 2.0 }, "money": [100, 300] },
	3: { "n": [2, 3], "w": { "mag": 3.0, "money": 3.0, "medkit": 1.0, "armour": 1.5, "gun": 3.0 }, "money": [200, 400] },
}
## Which guns a tier may hold (variants of these come along once they exist).
const GUNS := {
	1: ["pistol", "carbine", "shotgun"],
	2: ["pistol", "deagle", "carbine", "shotgun", "auto_rifle", "marksman"],
	3: ["deagle", "auto_rifle", "marksman", "sniper"],
}
const VALUE := { "medkit": 100, "armour": 150, "mag": 25 }

## The merged spec of a gun (a variant over its base).
static func spec(id: String) -> Dictionary:
	return FpsWeapons.spec(id) if FpsWeapons.SPECS.has(id) else {}


static func caliber(id: String) -> String:
	return str(spec(id).get("caliber", "pistol"))


static func value(id: String) -> int:
	return int(spec(id).get("value", 200))


static func is_primary(id: String) -> bool:
	return caliber(id) in PRIMARY_CALIBERS


## Is the gun a real pick (built, and not the duals: they need both hands' slots)?
static func usable(id: String) -> bool:
	var sp := spec(id)
	return not sp.is_empty() and not sp.get("dual", false) and FpsWeapons.available(str(sp.get("base", id)))


## The guns a tier can roll: its bases and their variants.
static func gun_pool(tier: int) -> Array:
	var out: Array = []
	for id: String in GUNS[clampi(tier, 1, 3)]:
		if usable(id):
			out.append(id)
	for v: String in FpsWeapons.VARIANTS:
		var sp := spec(v)
		if str(sp.get("base", "")) in GUNS[clampi(tier, 1, 3)] and usable(v):
			out.append(v)
	return out


## A chest's contents by tier (1–3 items; see TIER).
static func roll_chest(tier: int, rng: RandomNumberGenerator) -> Array:
	var t: Dictionary = TIER[clampi(tier, 1, 3)]
	var n: int = rng.randi_range(int(t.n[0]), int(t.n[1]))
	var out: Array = []
	for i in n:
		out.append(roll_item(tier, rng, t.w))
	return out


static func roll_item(tier: int, rng: RandomNumberGenerator, weights: Dictionary) -> Dictionary:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	var kind := "mag"
	for k in weights:
		r -= float(weights[k])
		if r < 0.0:
			kind = str(k)
			break
	match kind:
		"gun":
			var pool := gun_pool(tier)
			if pool.is_empty():
				return mag_item(CALIBERS[rng.randi() % CALIBERS.size()])
			var id := str(pool[rng.randi() % pool.size()])
			return gun_item(id, int(spec(id).get("mag", 10)))
		"mag":
			# the pistol's calibre most often: that's what you start with
			var cal: String = "pistol" if rng.randf() < 0.45 else CALIBERS[rng.randi() % CALIBERS.size()]
			return mag_item(cal)
		"medkit":
			return { "kind": "medkit", "id": "medkit", "caliber": "", "amount": 1, "value": VALUE.medkit }
		"armour":
			return { "kind": "armour", "id": "armour", "caliber": "", "amount": 100, "value": VALUE.armour }
	var m: Array = TIER[clampi(tier, 1, 3)].money
	var cash := rng.randi_range(int(m[0]), int(m[1]))
	cash -= cash % 10
	return { "kind": "money", "id": "money", "caliber": "", "amount": cash, "value": cash }


static func mag_item(cal: String) -> Dictionary:
	return { "kind": "mag", "id": "mag_" + cal, "caliber": cal, "amount": 1, "value": VALUE.mag }


static func gun_item(id: String, rounds: int) -> Dictionary:
	return { "kind": "gun", "id": id, "caliber": caliber(id), "amount": rounds, "value": value(id) }


## A dead guard's bag: its gun half-full and 0–1 mags of its calibre.
static func guard_drop(gun: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = [gun_item(gun, maxi(1, int(spec(gun).get("mag", 10)) / 2))]
	if rng.randf() < 0.5:
		out.append(mag_item(caliber(gun)))
	return out


## One line per item for the pop-up.
static func label(it: Dictionary) -> String:
	match str(it.kind):
		"gun": return "%s  (%d rounds)" % [str(spec(str(it.id)).get("name", it.id)), int(it.amount)]
		"mag": return "%s mag" % str(it.caliber).capitalize()
		"medkit": return "Medkit"
		"armour": return "Body armour"
		"money": return "$%d" % int(it.amount)
	return str(it.id)


static func dollars(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if n < 0 else "$") + s + out



## Something on the ground you can F: a guard's bag or a dropped gun. Built
## from the kit (a small canvas bag; a gun lies on its side), with a thin
## collider so bullets and feet meet it.
class Pickup extends StaticBody3D:
	var items: Array = []
	var label := "Loot bag"
	var _gun_id := ""


	static func make(at: Vector3, what: Array, gun_only := "") -> Pickup:
		var pk := Pickup.new()
		pk.items = what
		pk._gun_id = gun_only
		pk.position = at
		if gun_only != "":
			pk.label = str(ExtractLoot.spec(gun_only).get("name", gun_only))
		return pk


	func _ready() -> void:
		collision_layer = 1
		collision_mask = 0
		if _gun_id != "":
			var sp := ExtractLoot.spec(_gun_id)
			var a := GKRegistry.build(str(sp.get("asset", "pistol")), sp.get("params", {}))
			if a:
				var n := a.instantiate(false)
				# on its side on the ground, the grip up a little
				n.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, randf() * TAU), Vector3(0, 0.08, 0))
				add_child(n)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.9, 0.16, 0.3)
			cs.shape = bs
			cs.position.y = 0.08
			add_child(cs)
			return
		var g := GKMesh.new()
		g.box("canvas_awning:#4a5a3c", Vector3(0, 0.17, 0), Vector3(0.5, 0.34, 0.36), 0.05)
		g.tube("leather_black", [Vector3(-0.2, 0.34, 0), Vector3(-0.1, 0.46, 0), Vector3(0.1, 0.46, 0), Vector3(0.2, 0.34, 0)], 0.02, 6)
		var mi := MeshInstance3D.new()
		mi.mesh = g.commit()
		GKMaterials.apply(mi)
		add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 0.34, 0.36)
		cs.shape = bs
		cs.position.y = 0.17
		add_child(cs)
