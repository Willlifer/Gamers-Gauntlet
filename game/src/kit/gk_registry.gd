class_name GKRegistry
extends RefCounted
## Every kit generator by id. A game asks here; nothing else needs to know
## which script builds what.
##
##   var sniper := GKRegistry.build("sniper")                 # defaults
##   var hall := GKRegistry.build("dust_mid", { "length": 40.0 })
##   add_child(sniper.instantiate())

static var _defs := {}


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for d in [GKSniper.new(), GKShotgun.new(), GKSlingshot.new(), GKDustMid.new(), GKRooftop.new(), GKExtractForest.new()]:
		_defs[(d as GKDef).id()] = d
	# modelled in Blender (G43): listed once their .glb is built
	for b: Array in BLENDER:
		if GKGlb.exists(str(b[0])):
			_defs[str(b[0])] = GKGlb.new(str(b[0]), str(b[1]), str(b[2]), float(b[3]))


## The Blender-built assets: [id, title, kind, default scale]. Guns are real
## size, so 1.25 fits them to the 2.2 m body like the procedural ones.
const BLENDER := [
	["pistol", "Pistol (92FS)", "item", 1.25], ["deagle", "Desert Eagle", "item", 1.25],
	["marksman", "Marksman rifle", "item", 1.25], ["carbine", "Personal carbine", "item", 1.25],
	["auto_rifle", "Automatic rifle", "item", 1.25], ["tank", "Tank (IFV)", "prop", 1.25],
	["campus", "Campus paintball", "env", 1.0],
]


static func ids() -> PackedStringArray:
	_ensure()
	return PackedStringArray(_defs.keys())


static func def(asset_id: String) -> GKDef:
	_ensure()
	return _defs.get(asset_id)


static func build(asset_id: String, p: Dictionary = {}) -> GKAsset:
	var d := def(asset_id)
	if d == null:
		push_error("GKRegistry: no asset '%s'" % asset_id)
		return null
	return d.build(p)
