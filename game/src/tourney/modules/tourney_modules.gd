class_name TourneyModules
extends RefCounted
## The games the bracket can roll. G66: a table, not class references, so the
## lobby starts without compiling any game: each row holds what the menus need
## (the module's `info()` plus the lobby tile's look) and the module script's
## path, which is `load()`ed only when that game starts (`script_for`).
## Add a module: a TourneyModule subclass, then a row here with the same id,
## name, players and blurb as its `info()` (tourney_probe checks they agree).
## SHELVED modules stay playable by id (`scenes/module.tscn -- --module aram`,
## the tools) but never roll and get no Quick play tile: the MOBA pair left
## the pool on the author's 10-16 verdict (G60).
## Nothing on the startup path may name a module class (or anything a module
## pulls in): that compiles it, and the whole game, before the lobby shows.
##
## Row keys: id, name, players, blurb (= info()); script (path); look: the
## lobby tile's [muted tint, big faded tag, optional logo path] (G27, G46);
## warm: true when the game draws Black | White's VFX, so the shader warm-up
## (BWShaderWarm, D232) runs as it loads.

const DIR := "res://src/tourney/modules/"

const POOL: Array = [
	{ "id": "bw_twins", "name": "Black | White: the Twins", "players": 2,
		"blurb": "Thunder, fire and wind against Noon and Dusk. Fastest win takes it.",
		"script": DIR + "bw_fight_module.gd", "look": ["#3b3656", "B|W"], "warm": true },
	{ "id": "fps_roof", "name": "FPS: Rooftop duel", "players": 2,
		"blurb": "First person on the rooftops. Pick a gun each life; pistol or Desert Eagle on the hip. First to 5.",
		"script": DIR + "fps_module.gd", "look": ["#57452f", "FPS"] },
	{ "id": "fps_mid", "name": "FPS: Mid duel", "players": 2,
		"blurb": "First person down the Dust hallway. Pick a gun each life. First to 5.",
		"script": DIR + "fps_mid_module.gd", "look": ["#5e4b2a", "MID"] },
	{ "id": "fps_campus", "name": "FPS: Campus paintball", "players": 2,
		"blurb": "Paintball across an autumn campus. Hide in the bushes. First to 5.",
		"script": DIR + "fps_campus_module.gd", "look": ["#6a3c22", "PAINT"] },
	{ "id": "fps_extract", "name": "FPS: Extraction", "players": 2,
		"blurb": "One life on a seeded forest campus. Start with a pistol; loot chests and the green guards for guns, mags, armour and cash. The extract flares at 2:30: get there with the most.",
		"script": DIR + "fps_extract_module.gd", "look": ["#2c3546", ""] },
	{ "id": "mmo_raid_easy", "name": "MMO: Raid night (Easy)", "players": 2,
		"blurb": "WoW Classic raid on the Giant, easy mode: the slower fire, one mechanic at a time. Pick a class; the better grade wins.",
		"script": DIR + "mmo_raid_easy_module.gd", "look": ["#3d2f4c", "EASY"], "warm": true },
	{ "id": "mmo_raid", "name": "MMO: Raid night (Hard)", "players": 2,
		"blurb": "WoW Classic raid on the Giant, hard mode: the floor turns often, ring and bombs back to back. Pick a class; the better grade wins.",
		"script": DIR + "mmo_module.gd", "look": ["#4c2f3d", "HARD"], "warm": true },
	{ "id": "mmo_tanks", "name": "Planet of Tanks", "players": 2,
		"blurb": "Raid night 2: the raid against a tank in the campus woods. Drag its gun off the raid; the better grade wins.",
		"script": DIR + "mmo_tanks_module.gd", "look": ["#3a4428", "TANKS", "res://art/ui/planet_of_tanks_logo_small.png"], "warm": true },
	{ "id": "osrs_easy", "name": "OSRS: Warden's Trial (Easy)", "players": 2,
		"blurb": "Old School raid boss on 0.6 s ticks, the gentler trial. Pray against its projectiles, dodge lightning, boulders and slams. Fastest kill wins.",
		"script": DIR + "osrs_easy_module.gd", "look": ["#3f4426", "EASY"] },
	{ "id": "osrs_raid", "name": "OSRS: Warden's Trial (Hard)", "players": 2,
		"blurb": "Old School raid boss on 0.6 s ticks. Pray against the phantoms' shots, dodge lightning, boulders and slams, break the skulls with a lightning dagger. Fastest kill wins.",
		"script": DIR + "osrs_module.gd", "look": ["#4e3d26", "HARD"] },
]

const SHELVED: Array = [
	{ "id": "aram", "name": "MOBA: ARAM duel", "players": 2,
		"blurb": "Pick a champion, fight down one lane. First to 3 kills.",
		"script": DIR + "aram_module.gd", "look": ["#25415e", "ARAM"], "warm": true },
	{ "id": "pit", "name": "MOBA: Objective take", "players": 2,
		"blurb": "3v3 around the Giant in its pit. Smite in hand; the last hit takes it.",
		"script": DIR + "pit_module.gd", "look": ["#2b4a3c", "PIT"], "warm": true },
]

## The keys a row shares with its module's `info()`.
const INFO_KEYS := ["id", "name", "players", "blurb"]
const NO_LOOK := ["#2c3546", ""]


## The pool's rows, in order (the lobby's tiles, the bracket's rolls).
static func infos() -> Array:
	return POOL.duplicate(true)


## The row for an id, pool or shelved; {} if there is none.
static func entry(id: String) -> Dictionary:
	for e: Dictionary in POOL + SHELVED:
		if str(e.id) == id:
			return e
	return {}


## The module's script, loaded now (the first call compiles the game).
## Untyped on purpose: naming a module class here would compile it at startup.
static func script_for(id: String) -> GDScript:
	var e := entry(id)
	if e.is_empty():
		return null
	return load(str(e.script)) as GDScript


static func name_of(id: String) -> String:
	var e := entry(id)
	return str(e.name) if not e.is_empty() else id


## The lobby tile's look: [tint, tag, logo path?].
static func look_of(id: String) -> Array:
	return entry(id).get("look", NO_LOOK)


## Rows whose fields disagree with their module's `info()`: "" when all agree
## (tourney_probe; loads every module, so tools only).
static func check() -> String:
	var bad: Array = []
	for e: Dictionary in POOL + SHELVED:
		var s := script_for(str(e.id))
		if s == null:
			bad.append("%s: no script at %s" % [e.id, e.script])
			continue
		var inf: Dictionary = s.info()
		for k in INFO_KEYS:
			if str(inf.get(k, "")) != str(e.get(k, "")):
				bad.append("%s.%s: table '%s' vs info() '%s'" % [e.id, k, e.get(k, ""), inf.get(k, "")])
	return "; ".join(bad)
