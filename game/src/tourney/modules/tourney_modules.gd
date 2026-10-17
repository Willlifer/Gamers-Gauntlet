class_name TourneyModules
extends RefCounted
## The games the bracket can roll. Add a module: a TourneyModule subclass
## here and its `info()` fills the roll. `enabled` lists what the lobby
## turned on. SHELVED modules stay playable by id (`scenes/module.tscn --
## --module aram`, the tools) but never roll and get no Quick play tile:
## the MOBA pair left the pool on the author's 10-16 verdict (G60).

static var POOL: Array = [BWFightModule, FpsModule, FpsMidModule, FpsCampusModule, FpsExtractModule, MmoRaidEasyModule, MmoModule, MmoTanksModule, OsrsEasyModule, OsrsModule]
static var SHELVED: Array = [AramModule, PitModule]


static func infos() -> Array:
	return POOL.map(func(c): return c.info())


static func script_for(id: String) -> GDScript:
	for c in POOL + SHELVED:
		if str(c.info().id) == id:
			return c
	return null


static func name_of(id: String) -> String:
	for c in POOL + SHELVED:
		if str(c.info().id) == id:
			return str(c.info().name)
	return id
