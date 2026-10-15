class_name FpsMidModule
extends FpsModule
## FPS: Mid duel (G29). The FPS duel on the Gauntlet kit's Dust2-mid hallway
## (GKDustMid): you at the T end, the bot in the tower half of the lane, first
## to FpsTune.kills_to_win. Same guns, bullets and bot as the Rooftop duel.


static func info() -> Dictionary:
	return { "id": "fps_mid", "name": "FPS: Mid duel", "players": 2,
		"blurb": "First person down the Dust hallway. Sniper, shotgun, slingshot. First to 5." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var p: Array = m.players
	var w: Dictionary = p[rng.randi() % p.size()]
	var lo := rng.randi_range(1, 4)
	return { "winner": w.id, "summary": "%s took mid 5 – %d." % [w.name, lo], "stats": {} }


func map_id() -> String:
	return "dust_mid"
