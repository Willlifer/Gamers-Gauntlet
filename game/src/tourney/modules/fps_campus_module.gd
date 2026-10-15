class_name FpsCampusModule
extends FpsModule
## FPS: Campus paintball (G43): the duel on the Blender-built autumn campus
## (game/art/gauntlet/campus.glb). Paint marks every miss; bushes can be
## walked through and hide whoever is inside.


static func info() -> Dictionary:
	return { "id": "fps_campus", "name": "FPS: Campus paintball", "players": 2,
		"blurb": "Paintball across an autumn campus. Hide in the bushes. First to 5." }


func map_id() -> String:
	return "campus"


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var p: Array = m.players
	var w: Dictionary = p[rng.randi() % p.size()]
	return { "winner": w.id, "summary": "%s painted the campus 5 – %d." % [w.name, rng.randi_range(1, 4)], "stats": {} }
