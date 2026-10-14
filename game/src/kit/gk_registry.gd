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
	for d in [GKSniper.new(), GKShotgun.new(), GKSlingshot.new(), GKDustMid.new(), GKRooftop.new()]:
		_defs[(d as GKDef).id()] = d


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
