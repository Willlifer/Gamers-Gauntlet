class_name TourneyModules
extends RefCounted
## The games the bracket can roll. Add a module: a TourneyModule subclass
## here and its `info()` fills the roll. `enabled` lists what the lobby
## turned on.

static var POOL: Array = [BWFightModule, AramModule, PitModule, FpsModule, MmoModule]


static func infos() -> Array:
	return POOL.map(func(c): return c.info())


static func script_for(id: String) -> GDScript:
	for c in POOL:
		if str(c.info().id) == id:
			return c
	return null


static func name_of(id: String) -> String:
	for c in POOL:
		if str(c.info().id) == id:
			return str(c.info().name)
	return id
