class_name FpsModule
extends TourneyModule
## FPS: Rooftop duel (prototype). First person on the Gamer kit's apartment
## rooftops, you against a bot, first to FpsTune.kills_to_win. Offline: the
## human on this machine plays; the other seat is the bot. (Online needs the
## shooter network model, G8.)


static func info() -> Dictionary:
	return { "id": "fps_roof", "name": "FPS: Rooftop duel", "players": 2,
		"blurb": "First person on the rooftops. Sniper, shotgun, slingshot. First to 5." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	rng.seed = int(m.seed)
	var p: Array = m.players
	var w: Dictionary = p[rng.randi() % p.size()]
	var lo := rng.randi_range(1, 4)
	return { "winner": w.id, "summary": "%s took the rooftop 5 – %d." % [w.name, lo], "stats": {} }


func setup(m: Dictionary) -> void:
	super.setup(m)
	var human: Dictionary = m.players[0]
	var other: Dictionary = m.players[1]
	for p in m.players:
		if not p.get("bot", false):
			human = p
	for p in m.players:
		if p != human:
			other = p
	var world := FpsWorld.new()
	world.match_over.connect(func(won: bool, summary: String) -> void:
		finished.emit({ "winner": human.id if won else other.id, "summary": summary, "stats": {} }))
	add_child(world)
	TourneyMusic.play("fight")
